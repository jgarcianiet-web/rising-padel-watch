package com.risingpadel.core.model

import kotlinx.serialization.Serializable

@Serializable
enum class Platform(val wireName: String) {
    WATCHOS("watchos"),
    WEAROS("wearos"),
}

@Serializable
data class SourceInfo(
    val platform: Platform,
    val device: String,
    val appVersion: String,
)

@Serializable
data class MatchRef(
    val matchId: String,
    val leagueId: String? = null,
)

@Serializable
data class ShotIntensity(
    val meanRacketSpeedKmh: Float,
    val maxRacketSpeedKmh: Float,
    val meanImpactG: Float,
    val maxImpactG: Float,
) {
    companion object {
        val EMPTY = ShotIntensity(0f, 0f, 0f, 0f)

        fun from(shots: List<Shot>): ShotIntensity {
            if (shots.isEmpty()) return EMPTY
            return ShotIntensity(
                meanRacketSpeedKmh = shots.map { it.racketSpeedKmh }.average().toFloat(),
                maxRacketSpeedKmh = shots.maxOf { it.racketSpeedKmh },
                meanImpactG = shots.map { it.impactG }.average().toFloat(),
                maxImpactG = shots.maxOf { it.impactG },
            )
        }
    }
}

/** Zonas de frecuencia cardiaca como % de la FC máxima: z1 <60, z2 60-70, z3 70-80, z4 80-90, z5 >=90. */
@Serializable
data class HeartRateZones(val secondsPerZone: Map<String, Int>) {
    companion object {
        val EMPTY = HeartRateZones(emptyMap())
        val ZONE_KEYS = listOf("z1", "z2", "z3", "z4", "z5")

        fun zoneFor(bpm: Int, maxHeartRate: Int): String {
            val pct = bpm.toFloat() / maxHeartRate
            return when {
                pct < 0.60f -> "z1"
                pct < 0.70f -> "z2"
                pct < 0.80f -> "z3"
                pct < 0.90f -> "z4"
                else -> "z5"
            }
        }
    }
}

@Serializable
data class HeartRateSummary(
    val meanBpm: Int,
    val maxBpm: Int,
    val restingBpm: Int? = null,
)

/**
 * Métricas de salud del entrenamiento. Se omiten por completo del payload si el
 * usuario no ha dado el consentimiento de compartir datos de salud.
 */
@Serializable
data class HealthMetrics(
    val heartRate: HeartRateSummary? = null,
    val activeEnergyKcal: Float? = null,
    val totalEnergyKcal: Float? = null,
    val steps: Int? = null,
    val distanceMeters: Float? = null,
    val zones: HeartRateZones = HeartRateZones.EMPTY,
) {
    val isEmpty: Boolean
        get() = heartRate == null && activeEnergyKcal == null && totalEnergyKcal == null &&
            steps == null && distanceMeters == null && zones.secondsPerZone.isEmpty()

    companion object {
        val EMPTY = HealthMetrics()
    }
}

/** Estado de sincronización de una sesión con la app de liga. */
@Serializable
enum class SyncState {
    /** Aún no se ha intentado, o se reintentará. */
    PENDING,

    /** Confirmada por el servidor. */
    SYNCED,

    /** Fallo permanente (400/409/versión de esquema): no se reintenta solo. */
    FAILED,

    /** El token no vale: hace falta que el usuario vuelva a conectar la liga. */
    NEEDS_AUTH,
}

@Serializable
data class SyncStatus(
    val state: SyncState = SyncState.PENDING,
    val attempts: Int = 0,
    val lastAttemptAtEpochMs: Long? = null,
    val nextAttemptAtEpochMs: Long? = null,
    val lastError: String? = null,
    val remoteId: String? = null,
)

/** Una sesión de pádel completa, tal y como la construye el reloj. */
@Serializable
data class PadelSession(
    val sessionId: String,
    val source: SourceInfo,
    val startedAtEpochMs: Long,
    val endedAtEpochMs: Long,
    val profile: PlayerProfile,
    val shots: List<Shot>,
    val health: HealthMetrics = HealthMetrics.EMPTY,
    val matchRef: MatchRef? = null,
    val sync: SyncStatus = SyncStatus(),
) {
    val durationSeconds: Long get() = ((endedAtEpochMs - startedAtEpochMs) / 1000).coerceAtLeast(0)

    val totalShots: Int get() = shots.size

    val shotsByType: Map<ShotType, Int>
        get() = shots.groupingBy { it.type }.eachCount()

    val intensity: ShotIntensity get() = ShotIntensity.from(shots)

    /** Golpeos por minuto, la métrica más comparable entre sesiones de distinta duración. */
    val shotsPerMinute: Float
        get() = if (durationSeconds <= 0) 0f else totalShots * 60f / durationSeconds

    companion object {
        const val SCHEMA_VERSION = 1
    }
}
