package com.risingpadel.core.training

import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.detection.ShotDetector
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo

/**
 * Graba tandas de golpeos etiquetados para entrenar el clasificador.
 *
 * El jugador elige un tipo de golpe y da 30-40 seguidos solo de ese tipo. Cada golpeo
 * que detecta la heurística se guarda con su ventana cruda y la etiqueta ya puesta.
 *
 * Reutiliza el mismo [ShotDetector] de siempre: interesa entrenar el clasificador con
 * los golpeos que el detector **realmente** encuentra en pista, no con una selección
 * ideal. Si el detector se deja golpeos, eso es un problema del detector y se arregla
 * ahí, no maquillando el conjunto de entrenamiento.
 *
 * Ver `docs/training-data.md`.
 */
class TrainingRecorder(
    private val source: SourceInfo,
    private val profile: PlayerProfile,
    private val config: DetectorConfig = DetectorConfig.DEFAULT,
    private val sampleIdProvider: () -> String,
    private val nowEpochMs: () -> Long,
) {
    private val detector = ShotDetector(config, profile)
    private val capture = TrainingCapture(sampleRateHz = config.sampleRateHz)

    private var referenceMs = 0L
    private var recording = false
    private var captured = 0

    /** Tipo de golpe de la tanda en curso. Es la etiqueta que se guarda. */
    var label: ShotType = ShotType.FOREHAND

    /** Alias del jugador, para poder validar dejando fuera a una persona entera. */
    var playerAlias: String = "anon"

    /** Nivel de pádel (1-7) del jugador que graba, si se conoce. */
    var playerLevel: Int? = null

    val capturedCount: Int get() = captured
    val isRecording: Boolean get() = recording

    fun start(monotonicMs: Long) {
        detector.reset(monotonicMs)
        capture.reset()
        referenceMs = monotonicMs
        captured = 0
        recording = true
    }

    /** Devuelve las muestras de entrenamiento que han quedado completas con esta señal. */
    fun onMotion(sample: MotionSample): List<TrainingSample> {
        if (!recording) return emptyList()

        // Primero se empuja la muestra —puede cerrar la cola de un golpeo anterior— y
        // luego se mira si esta muestra cierra un golpeo nuevo.
        val ready = capture.onSample(sample)
        detector.process(sample)?.let { shot ->
            capture.onShotDetected(shot, referenceMs + shot.offsetMs)
        }
        return ready.map { toTrainingSample(it) }.also { captured += it.size }
    }

    /** Cierra la tanda. Incluye el último golpeo aunque le falte cola. */
    fun stop(): List<TrainingSample> {
        if (!recording) return emptyList()
        detector.flush()?.let { shot ->
            capture.onShotDetected(shot, referenceMs + shot.offsetMs)
        }
        recording = false
        return capture.flush().map { toTrainingSample(it) }.also { captured += it.size }
    }

    private fun toTrainingSample(window: CapturedWindow): TrainingSample = TrainingSample(
        sampleId = sampleIdProvider(),
        label = label,
        recordedAtEpochMs = nowEpochMs(),
        playerAlias = playerAlias,
        playerLevel = playerLevel,
        hand = profile.hand,
        watchWrist = profile.watchWrist,
        platform = source.platform,
        device = source.device,
        sampleRateHz = config.sampleRateHz,
        impactIndex = window.impactIndex,
        // Offsets relativos al impacto: así la ventana es comparable entre golpeos
        // aunque los relojes arranquen su reloj monótono donde les dé la gana.
        offsetsMs = window.samples.map { (it.timestampMs - window.impactTimestampMs).toInt() },
        accel = window.samples.map { listOf(it.accel.x, it.accel.y, it.accel.z) },
        gyro = window.samples.map { listOf(it.gyro.x, it.gyro.y, it.gyro.z) },
        gravity = window.samples.map { listOf(it.gravity.x, it.gravity.y, it.gravity.z) },
        heuristicFeatures = window.shot.features,
        heuristicPrediction = window.shot.type,
        heuristicConfidence = window.shot.confidence,
    )
}
