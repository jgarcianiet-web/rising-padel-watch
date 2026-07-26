package com.risingpadel.core.sync

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.SyncState
import com.risingpadel.core.model.SyncStatus
import com.risingpadel.core.storage.SessionStore
import kotlin.math.min
import kotlin.random.Random

/**
 * Backoff exponencial con jitter: 2s, 4s, 8s, 16s, 32s, 60s y a partir de ahí cada 15
 * minutos. El jitter evita que todos los relojes de una liga reintenten a la vez tras
 * una caída del servidor.
 */
class RetryPolicy(
    private val random: Random = Random.Default,
    private val jitterFraction: Float = 0.2f,
    /** Pasado este tiempo desde el fin de la sesión se deja de reintentar. */
    val maxAgeMs: Long = 72 * 60 * 60 * 1000L,
) {
    fun delayMs(attempt: Int): Long {
        val base = when {
            attempt <= 0 -> BASE_DELAY_MS
            attempt <= LADDER.size -> LADDER[attempt - 1]
            else -> LONG_DELAY_MS
        }
        val jitter = (base * jitterFraction).toLong()
        if (jitter <= 0L) return base
        return base + random.nextLong(-jitter, jitter + 1)
    }

    companion object {
        private const val BASE_DELAY_MS = 2_000L
        private const val LONG_DELAY_MS = 15 * 60 * 1000L
        private val LADDER = longArrayOf(2_000, 4_000, 8_000, 16_000, 32_000, 60_000)
    }
}

data class SyncReport(
    val uploaded: Int = 0,
    val retryLater: Int = 0,
    val failed: Int = 0,
    val needsAuth: Boolean = false,
    val skipped: Boolean = false,
) {
    val didWork: Boolean get() = uploaded > 0 || retryLater > 0 || failed > 0
}

/**
 * Sube al servidor de la liga todas las sesiones pendientes que ya tocan.
 *
 * Es idempotente y reentrante: si se ejecuta dos veces a la vez, el `Idempotency-Key`
 * del cliente impide duplicados en el servidor.
 */
class SyncQueue(
    private val store: SessionStore,
    private val client: LeagueApiClient,
    private val clock: () -> Long = System::currentTimeMillis,
    private val retryPolicy: RetryPolicy = RetryPolicy(),
) {

    /**
     * @param config null o incompleta (sin liga configurada) ⇒ no se hace nada y las
     *   sesiones se quedan esperando en local.
     * @param shareHealth consentimiento de compartir datos de salud.
     */
    suspend fun sync(
        config: LeagueConfig?,
        shareHealth: Boolean,
        includeEvents: Boolean = true,
    ): SyncReport {
        if (config == null || !config.isUsable) return SyncReport(skipped = true)

        val now = clock()
        val due = store.all()
            .filter { it.sync.state == SyncState.PENDING }
            .filter { (it.sync.nextAttemptAtEpochMs ?: 0L) <= now }
            .sortedBy { it.startedAtEpochMs }

        var report = SyncReport()
        for (session in due) {
            if (report.needsAuth) break // El token está roto: no tiene sentido seguir.

            if (now - session.endedAtEpochMs > retryPolicy.maxAgeMs) {
                store.upsert(session.withSync(session.sync.copy(
                    state = SyncState.FAILED,
                    lastAttemptAtEpochMs = now,
                    lastError = "Caducada: no se pudo sincronizar en 72 h",
                )))
                report = report.copy(failed = report.failed + 1)
                continue
            }

            val attempt = session.sync.attempts + 1
            val outcome = client.upload(config, session, shareHealth, includeEvents)
            report = apply(session, outcome, attempt, now, report)
        }
        return report
    }

    private fun apply(
        session: PadelSession,
        outcome: UploadOutcome,
        attempt: Int,
        now: Long,
        report: SyncReport,
    ): SyncReport = when (outcome) {
        is UploadOutcome.Success -> {
            store.upsert(session.withSync(SyncStatus(
                state = SyncState.SYNCED,
                attempts = attempt,
                lastAttemptAtEpochMs = now,
                remoteId = outcome.remoteId,
            )))
            report.copy(uploaded = report.uploaded + 1)
        }

        is UploadOutcome.PermanentFailure -> {
            store.upsert(session.withSync(session.sync.copy(
                state = SyncState.FAILED,
                attempts = attempt,
                lastAttemptAtEpochMs = now,
                lastError = outcome.message,
            )))
            report.copy(failed = report.failed + 1)
        }

        is UploadOutcome.AuthFailure -> {
            store.upsert(session.withSync(session.sync.copy(
                state = SyncState.NEEDS_AUTH,
                attempts = attempt,
                lastAttemptAtEpochMs = now,
                lastError = outcome.message,
            )))
            report.copy(needsAuth = true)
        }

        is UploadOutcome.RateLimited -> {
            val delay = outcome.retryAfterSeconds?.times(1000L) ?: retryPolicy.delayMs(attempt)
            store.upsert(session.withSync(session.sync.copy(
                state = SyncState.PENDING,
                attempts = attempt,
                lastAttemptAtEpochMs = now,
                nextAttemptAtEpochMs = now + min(delay, MAX_DELAY_MS),
                lastError = "Rate limit",
            )))
            report.copy(retryLater = report.retryLater + 1)
        }

        is UploadOutcome.TransientFailure -> {
            store.upsert(session.withSync(session.sync.copy(
                state = SyncState.PENDING,
                attempts = attempt,
                lastAttemptAtEpochMs = now,
                nextAttemptAtEpochMs = now + retryPolicy.delayMs(attempt),
                lastError = outcome.message,
            )))
            report.copy(retryLater = report.retryLater + 1)
        }
    }

    /**
     * Vuelve a poner en cola una sesión fallada. Lo dispara el usuario desde la UI, o la
     * app tras reintroducir el token.
     */
    fun requeue(sessionId: String) {
        val session = store.get(sessionId) ?: return
        if (session.sync.state == SyncState.SYNCED) return
        store.upsert(session.withSync(session.sync.copy(
            state = SyncState.PENDING,
            nextAttemptAtEpochMs = null,
            lastError = null,
        )))
    }

    /** Tras reconectar la liga, todo lo que estaba bloqueado por auth vuelve a la cola. */
    fun requeueAllNeedingAuth() {
        store.all().filter { it.sync.state == SyncState.NEEDS_AUTH }.forEach { requeue(it.sessionId) }
    }

    companion object {
        private const val MAX_DELAY_MS = 6 * 60 * 60 * 1000L
    }
}

private fun PadelSession.withSync(status: SyncStatus) = copy(sync = status)
