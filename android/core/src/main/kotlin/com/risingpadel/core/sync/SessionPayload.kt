package com.risingpadel.core.sync

import com.risingpadel.core.analytics.SessionAnalytics
import com.risingpadel.core.level.SessionLevel
import com.risingpadel.core.model.HealthMetrics
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.score.MatchScore
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlin.math.round

/**
 * DTOs del contrato con la app de liga (`docs/api-contract.md`).
 *
 * Están separados del modelo de dominio a propósito: el modelo puede evolucionar sin
 * romper el contrato, y el contrato puede versionarse sin contaminar el dominio.
 */
@Serializable
data class SessionPayload(
    val sessionId: String,
    val schemaVersion: Int,
    val source: SourcePayload,
    val startedAt: String,
    val endedAt: String,
    val durationSeconds: Long,
    val player: PlayerPayload? = null,
    val matchRef: MatchRefPayload? = null,
    val shots: ShotsPayload,
    val health: HealthPayload? = null,
    val score: ScorePayload? = null,
    val level: LevelPayload? = null,
    val analytics: AnalyticsPayload? = null,
)

/**
 * Series agregadas para las gráficas de la liga. Opcional y **aditivo**: no sube la
 * versión del esquema, y un receptor viejo lo ignora sin romperse.
 *
 * Son decenas de números y no los eventos por golpeo: caben en un deep link y no
 * exponen nada que los agregados (nivel, recuentos) no expongan ya.
 */
@Serializable
data class AnalyticsPayload(
    val frequency: FrequencyPayload? = null,
    val levelProgression: LevelProgressionPayload? = null,
    /**
     * Nivel medio del jugador sobre su historial en el dispositivo emisor, si lo conoce.
     * Es la línea "calidad media" de las gráficas de la liga.
     */
    val playerAverageLevel: Float? = null,
)

@Serializable
data class FrequencyPayload(
    val intervalMinutes: Int,
    /** Golpeos por intervalo, desde el minuto 0. Los intervalos vacíos van como 0. */
    val counts: List<Int>,
)

@Serializable
data class LevelProgressionPayload(
    val points: List<LevelProgressionPointPayload>,
)

@Serializable
data class LevelProgressionPointPayload(
    /** Minuto de sesión en el que se evalúa el punto (fin de la ventana). */
    val minute: Float,
    val level: Float,
)

/**
 * Nivel técnico estimado, en la escala de pádel de 1 a 7.
 *
 * Es **derivado**: la liga puede recalcularlo de los golpeos si algún día quiere usar su
 * propia fórmula. Viaja en el payload para que no tenga que hacerlo.
 */
@Serializable
data class LevelPayload(
    val overall: Float,
    val byShotType: Map<String, Float>,
    /** 0 a 1. En pádel la regularidad es tanto del nivel como la potencia. */
    val consistency: Float,
    val repertoire: Float,
    val gradedShots: Int,
    /** false si hubo pocos golpeos: el número está, pero no hay que fiarse de él. */
    val reliable: Boolean,
)

@Serializable
data class SourcePayload(
    val platform: String,
    val device: String,
    val appVersion: String,
)

@Serializable
data class PlayerPayload(
    val hand: String,
    val watchWrist: String,
)

@Serializable
data class MatchRefPayload(
    val matchId: String,
    val leagueId: String? = null,
)

@Serializable
data class ShotsPayload(
    val total: Int,
    val byType: Map<String, Int>,
    val intensity: IntensityPayload? = null,
    val events: List<ShotEventPayload> = emptyList(),
)

@Serializable
data class IntensityPayload(
    val meanRacketSpeedKmh: Float,
    val maxRacketSpeedKmh: Float,
    val meanImpactG: Float,
    val maxImpactG: Float,
)

@Serializable
data class ShotEventPayload(
    val offsetMs: Long,
    val type: String,
    val racketSpeedKmh: Float,
    val impactG: Float,
    val confidence: Float,
)

@Serializable
data class HealthPayload(
    val heartRate: HeartRatePayload? = null,
    val activeEnergyKcal: Float? = null,
    val totalEnergyKcal: Float? = null,
    val steps: Int? = null,
    val distanceMeters: Float? = null,
    val zonesSeconds: Map<String, Int>? = null,
)

@Serializable
data class ScorePayload(
    val rules: ScoreRulesPayload,
    val sets: List<SetScorePayload>,
    /** "us" | "them", o ausente si el partido no llegó a terminarse. */
    val winner: String? = null,
    val completed: Boolean,
)

@Serializable
data class ScoreRulesPayload(
    /** "advantage" | "goldenPoint" | "starPoint". */
    val deuceFormat: String,
    val setsToWin: Int,
)

@Serializable
data class SetScorePayload(val us: Int, val them: Int)

@Serializable
data class HeartRatePayload(
    val meanBpm: Int,
    val maxBpm: Int,
    val restingBpm: Int? = null,
)

/**
 * Estado en vivo de un partido, para que otros lo sigan mientras se juega.
 *
 * Es **estado completo, no eventos**: cada actualización sustituye del todo a la
 * anterior, así que perder una no rompe nada — la siguiente trae la verdad entera. Por
 * eso se publica con PUT y sin cola de reintentos: reenviar un marcador viejo sería
 * peor que no enviar nada.
 */
@Serializable
data class LiveScorePayload(
    val sessionId: String,
    val updatedAt: String,
    /** true en la última publicación: el partido acabó y el espectador deja de refrescar. */
    val completed: Boolean,
    val score: ScorePayload? = null,
    val shotCount: Int = 0,
    val heartRateBpm: Int? = null,
    val elapsedSeconds: Long = 0,
)

@Serializable
data class SessionRefResponse(
    val id: String,
    val sessionId: String? = null,
    val createdAt: String? = null,
    val matchRef: MatchRefPayload? = null,
)

@Serializable
data class ApiErrorResponse(val error: ApiErrorBody? = null)

@Serializable
data class ApiErrorBody(val code: String? = null, val message: String? = null)

@Serializable
data class MatchesResponse(val matches: List<MatchSummary> = emptyList())

@Serializable
data class MatchSummary(
    val matchId: String,
    val leagueId: String? = null,
    val scheduledAt: String? = null,
    val opponents: String? = null,
    val venue: String? = null,
)

/**
 * Convierte una sesión al payload del contrato.
 *
 * @param shareHealth consentimiento del usuario. Si es false el bloque `health` no se
 *   incluye en absoluto (no se manda vacío: se omite).
 * @param includeEvents si es false solo se suben los agregados. Se usa para reintentar
 *   una sesión que el servidor rechazó por tamaño.
 * @param playerAverageLevel media del historial del jugador, si quien llama la conoce.
 *   La sesión no sabe de historial: por eso entra como parámetro.
 */
fun PadelSession.toPayload(
    shareHealth: Boolean,
    includeEvents: Boolean = true,
    playerAverageLevel: Float? = null,
): SessionPayload = SessionPayload(
    sessionId = sessionId,
    schemaVersion = schemaVersion,
    source = SourcePayload(
        platform = source.platform.wireName,
        device = source.device,
        appVersion = source.appVersion,
    ),
    startedAt = isoUtc(startedAtEpochMs),
    endedAt = isoUtc(endedAtEpochMs),
    durationSeconds = durationSeconds,
    player = PlayerPayload(hand = profile.hand.wireName, watchWrist = profile.watchWrist.wireName),
    matchRef = matchRef?.let { MatchRefPayload(it.matchId, it.leagueId) },
    shots = ShotsPayload(
        total = totalShots,
        byType = shotsByType.entries.associate { (type, count) -> type.wireName to count },
        intensity = if (shots.isEmpty()) null else intensity.let {
            IntensityPayload(
                meanRacketSpeedKmh = round1(it.meanRacketSpeedKmh),
                maxRacketSpeedKmh = round1(it.maxRacketSpeedKmh),
                meanImpactG = round1(it.meanImpactG),
                maxImpactG = round1(it.maxImpactG),
            )
        },
        events = if (!includeEvents) emptyList() else shots.map { shot ->
            ShotEventPayload(
                offsetMs = shot.offsetMs,
                type = shot.type.wireName,
                racketSpeedKmh = round1(shot.racketSpeedKmh),
                impactG = round1(shot.impactG),
                confidence = round2(shot.confidence),
            )
        },
    ),
    health = if (shareHealth) health.toPayloadOrNull() else null,
    score = score?.toPayload(),
    level = level.toPayloadOrNull(),
    analytics = analyticsPayloadOrNull(playerAverageLevel),
)

/** Sin golpeos no hay series que mandar: se omite el bloque entero. */
private fun PadelSession.analyticsPayloadOrNull(playerAverageLevel: Float?): AnalyticsPayload? {
    if (shots.isEmpty()) return null
    val analytics = SessionAnalytics()
    val durationMs = durationSeconds * 1000

    val buckets = analytics.shotFrequency(shots, durationMs, SessionAnalytics.INTERVAL_10_MIN_MS)
    val points = analytics.levelProgression(shots, durationMs)

    return AnalyticsPayload(
        frequency = buckets.takeIf { it.isNotEmpty() }?.let { list ->
            FrequencyPayload(intervalMinutes = 10, counts = list.map { it.count })
        },
        levelProgression = points.takeIf { it.isNotEmpty() }?.let { list ->
            LevelProgressionPayload(
                points = list.map {
                    LevelProgressionPointPayload(
                        minute = round1(it.offsetMs / 60_000f),
                        level = round1(it.level),
                    )
                }
            )
        },
        playerAverageLevel = playerAverageLevel?.let { round2(it) },
    )
}

/** Sin golpeos puntuables no hay nivel que mandar: se omite en vez de mandar un 1 falso. */
private fun SessionLevel.toPayloadOrNull(): LevelPayload? {
    if (gradedShots == 0) return null
    return LevelPayload(
        overall = round1(overall),
        byShotType = byShotType.entries.associate { (type, value) -> type.wireName to round1(value) },
        consistency = round2(consistency),
        repertoire = round2(repertoire),
        gradedShots = gradedShots,
        reliable = reliable,
    )
}

private fun MatchScore.toPayload() = ScorePayload(
    rules = ScoreRulesPayload(
        deuceFormat = rules.deuceFormat.wireName,
        setsToWin = rules.setsToWin,
    ),
    sets = allSets.map { SetScorePayload(us = it.us, them = it.them) },
    winner = winner?.wireName,
    completed = isFinished,
)

private fun HealthMetrics.toPayloadOrNull(): HealthPayload? {
    if (isEmpty) return null
    return HealthPayload(
        heartRate = heartRate?.let { HeartRatePayload(it.meanBpm, it.maxBpm, it.restingBpm) },
        activeEnergyKcal = activeEnergyKcal?.let { round1(it) },
        totalEnergyKcal = totalEnergyKcal?.let { round1(it) },
        steps = steps,
        distanceMeters = distanceMeters?.let { round1(it) },
        zonesSeconds = zones.secondsPerZone.takeIf { it.isNotEmpty() },
    )
}

/** ISO-8601 UTC truncado a segundos: `2026-07-25T18:04:12Z`. */
internal fun isoUtc(epochMs: Long): String =
    DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochSecond(Math.floorDiv(epochMs, 1000L)))

private fun round1(value: Float): Float = round(value * 10f) / 10f

private fun round2(value: Float): Float = round(value * 100f) / 100f
