package com.risingpadel.core.session

import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.detection.ShotDetector
import com.risingpadel.core.model.HealthMetrics
import com.risingpadel.core.model.HeartRateSummary
import com.risingpadel.core.model.HeartRateZones
import com.risingpadel.core.model.MatchRef
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.score.MatchScore
import kotlin.math.roundToInt

/**
 * Acumula una sesión en curso: golpeos detectados + métricas de salud del workout.
 *
 * Vive en el reloj y es el único punto donde se junta todo. Las apps solo tienen que
 * bombear muestras y métricas; el resultado es una [PadelSession] lista para enviar al
 * móvil.
 *
 * Los tiempos vienen por duplicado a propósito: **epoch** para fechar la sesión y
 * **monótono** para medir dentro de ella (el epoch puede saltar si el reloj se
 * sincroniza a mitad de partido).
 */
class SessionRecorder(
    private val source: SourceInfo,
    private val profile: PlayerProfile = PlayerProfile(),
    config: DetectorConfig = DetectorConfig.DEFAULT,
    private val currentYear: Int = 2026,
    private val sessionIdProvider: () -> String,
) {
    private val detector = ShotDetector(config, profile)
    private val maxHeartRate = profile.effectiveMaxHeartRate(currentYear)

    private var sessionId: String? = null
    private var startedAtEpochMs = 0L
    private var startedAtMonotonicMs = 0L

    private val collectedShots = mutableListOf<Shot>()

    private var lastHeartRateBpm: Int? = null
    private var lastHeartRateAtMs: Long? = null
    private var maxObservedBpm = 0
    private var weightedBpmSum = 0.0
    private var weightedSeconds = 0.0
    private val zoneSeconds = mutableMapOf<String, Double>()

    private var activeEnergyKcal: Float? = null
    private var totalEnergyKcal: Float? = null
    private var steps: Int? = null
    private var distanceMeters: Float? = null

    var matchRef: MatchRef? = null

    /**
     * Marcador del partido, si el jugador lo está llevando. El reloj lo mantiene aparte
     * del conteo de golpeos: se puede jugar con marcador y sin él, y una sesión sin
     * marcador sigue siendo una sesión válida.
     */
    var score: MatchScore? = null

    val shots: List<Shot> get() = collectedShots
    val isRecording: Boolean get() = sessionId != null

    fun start(startedAtEpochMs: Long, monotonicMs: Long) {
        sessionId = sessionIdProvider()
        this.startedAtEpochMs = startedAtEpochMs
        this.startedAtMonotonicMs = monotonicMs
        collectedShots.clear()
        lastHeartRateBpm = null
        lastHeartRateAtMs = null
        maxObservedBpm = 0
        weightedBpmSum = 0.0
        weightedSeconds = 0.0
        zoneSeconds.clear()
        activeEnergyKcal = null
        totalEnergyKcal = null
        steps = null
        distanceMeters = null
        detector.reset(monotonicMs)
    }

    /** Devuelve el golpeo si esta muestra cierra uno, para poder avisar en la UI al instante. */
    fun onMotion(sample: MotionSample): Shot? =
        detector.process(sample)?.also { collectedShots.add(it) }

    /**
     * Cada lectura de FC cierra el intervalo anterior: el tiempo transcurrido desde la
     * lectura previa se atribuye a la zona de **esa** lectura previa, que es la que
     * estuvo vigente durante el intervalo.
     */
    fun onHeartRate(bpm: Int, monotonicMs: Long) {
        if (bpm <= 0) return
        val previousBpm = lastHeartRateBpm
        val previousAt = lastHeartRateAtMs
        if (previousBpm != null && previousAt != null) {
            val elapsed = ((monotonicMs - previousAt) / 1000.0).coerceIn(0.0, 60.0)
            if (elapsed > 0.0) {
                val zone = HeartRateZones.zoneFor(previousBpm, maxHeartRate)
                zoneSeconds[zone] = (zoneSeconds[zone] ?: 0.0) + elapsed
                weightedBpmSum += previousBpm * elapsed
                weightedSeconds += elapsed
            }
        }
        lastHeartRateBpm = bpm
        lastHeartRateAtMs = monotonicMs
        if (bpm > maxObservedBpm) maxObservedBpm = bpm
    }

    /** Valores acumulados del workout; se sustituyen, no se suman. */
    fun onEnergy(activeKcal: Float?, totalKcal: Float? = null) {
        activeKcal?.let { activeEnergyKcal = it }
        totalKcal?.let { totalEnergyKcal = it }
    }

    fun onSteps(count: Int) {
        steps = count
    }

    fun onDistance(meters: Float) {
        distanceMeters = meters
    }

    /**
     * Cierra la sesión. [shareHealth] es el consentimiento del usuario: si es false, la
     * sesión sale sin ningún dato de salud (no se recorta después, no se construye).
     */
    fun finish(endedAtEpochMs: Long, monotonicMs: Long, shareHealth: Boolean): PadelSession {
        val id = requireNotNull(sessionId) { "finish() sin start()" }
        detector.flush()?.let { collectedShots.add(it) }
        // Cierra el último intervalo de FC con el instante de fin.
        lastHeartRateBpm?.let { onHeartRate(it, monotonicMs) }

        val session = PadelSession(
            sessionId = id,
            source = source,
            startedAtEpochMs = startedAtEpochMs,
            endedAtEpochMs = endedAtEpochMs,
            profile = profile,
            shots = collectedShots.toList(),
            health = if (shareHealth) buildHealth() else HealthMetrics.EMPTY,
            score = score,
            matchRef = matchRef,
        )
        sessionId = null
        return session
    }

    /** Métricas parciales para la pantalla del reloj mientras se juega. */
    fun liveSnapshot(monotonicMs: Long): LiveStats {
        val elapsedSeconds = ((monotonicMs - startedAtMonotonicMs) / 1000).coerceAtLeast(0)
        return LiveStats(
            elapsedSeconds = elapsedSeconds,
            shotCount = collectedShots.size,
            currentHeartRate = lastHeartRateBpm,
            activeEnergyKcal = activeEnergyKcal,
            lastShot = collectedShots.lastOrNull(),
        )
    }

    private fun buildHealth(): HealthMetrics {
        val heartRate = if (maxObservedBpm > 0) {
            HeartRateSummary(
                meanBpm = if (weightedSeconds > 0) (weightedBpmSum / weightedSeconds).roundToInt()
                else maxObservedBpm,
                maxBpm = maxObservedBpm,
                restingBpm = profile.restingHeartRate,
            )
        } else {
            null
        }
        return HealthMetrics(
            heartRate = heartRate,
            activeEnergyKcal = activeEnergyKcal,
            totalEnergyKcal = totalEnergyKcal,
            steps = steps,
            distanceMeters = distanceMeters,
            zones = HeartRateZones(zoneSeconds.mapValues { it.value.roundToInt() }),
        )
    }
}

data class LiveStats(
    val elapsedSeconds: Long,
    val shotCount: Int,
    val currentHeartRate: Int?,
    val activeEnergyKcal: Float?,
    val lastShot: Shot?,
)
