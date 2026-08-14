package com.risingpadel.core.training

import com.risingpadel.core.detection.DescartesDelDetector
import com.risingpadel.core.detection.DetectorConfig
import com.risingpadel.core.detection.ShotDetector
import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo

/**
 * Graba una tanda de entrenamiento entera y en crudo.
 *
 * El contrato es deliberadamente a prueba de decepciones: **cada muestra que entra se
 * guarda**. El detector corre en paralelo pero solo como comentarista — sus golpes y sus
 * descartes se apuntan como metadatos y sirven de contador en vivo, sin poder vetar ni
 * una muestra. Si el detector está mal calibrado, la señal sigue completa y se segmenta
 * después, con mejores ojos.
 *
 * Vive en el core para que watchOS y Wear graben exactamente igual, con tests en Kotlin.
 */
class GrabadorDeTanda(
    private val source: SourceInfo,
    private val profile: PlayerProfile,
    config: DetectorConfig = DetectorConfig.DEFAULT,
    private val tandaIdProvider: () -> String,
    private val nowEpochMs: () -> Long,
) {
    private val detector = ShotDetector(config, profile)

    private val offsets = ArrayList<Long>()
    private val accel = ArrayList<List<Float>>()
    private val gyro = ArrayList<List<Float>>()
    private val gravity = ArrayList<List<Float>>()
    private val golpesVistos = ArrayList<GolpeDeTanda>()

    private var referenceMs = 0L
    private var startedAtEpochMs = 0L
    private var recording = false

    /** Tipo de golpe de la tanda entera. Se fija antes de empezar a pegar. */
    var label: ShotType = ShotType.FOREHAND

    var playerAlias: String = "anon"
    var playerLevel: Int? = null

    val isRecording: Boolean get() = recording
    val muestras: Int get() = offsets.size
    val segundos: Int get() = if (offsets.isEmpty()) 0 else (offsets.last() / 1000).toInt()

    /** Golpes que el detector cree haber visto. Contador en vivo, no puerta. */
    val golpes: Int get() = golpesVistos.size
    val descartes: DescartesDelDetector get() = detector.descartes

    /** La tanda está en el tope y ya no admite más muestras. */
    val llena: Boolean get() = offsets.size >= MAX_MUESTRAS

    fun start(monotonicMs: Long) {
        detector.reset(monotonicMs)
        offsets.clear()
        accel.clear()
        gyro.clear()
        gravity.clear()
        golpesVistos.clear()
        referenceMs = monotonicMs
        startedAtEpochMs = nowEpochMs()
        recording = true
    }

    /**
     * Guarda la muestra y devuelve el golpe si el detector creyó ver uno.
     *
     * El retorno es solo para vibrar o subir el contador: la muestra ya está guardada
     * pase lo que pase.
     */
    fun onMotion(sample: MotionSample): Shot? {
        if (!recording || llena) return null

        offsets.add(sample.timestampMs - referenceMs)
        accel.add(listOf(sample.accel.x, sample.accel.y, sample.accel.z))
        gyro.add(listOf(sample.gyro.x, sample.gyro.y, sample.gyro.z))
        gravity.add(listOf(sample.gravity.x, sample.gravity.y, sample.gravity.z))

        val shot = detector.process(sample) ?: return null
        golpesVistos.add(
            GolpeDeTanda(
                offsetMs = shot.offsetMs,
                tipo = shot.type,
                confidence = shot.confidence,
                features = shot.features,
            )
        )
        return shot
    }

    /** Cierra la tanda. Null si no llegó ni una muestra: no hay nada que guardar. */
    fun stop(): TandaCruda? {
        recording = false
        if (offsets.isEmpty()) return null
        return TandaCruda(
            tandaId = tandaIdProvider(),
            label = label,
            playerAlias = playerAlias,
            playerLevel = playerLevel,
            hand = profile.hand,
            watchWrist = profile.watchWrist,
            platform = source.platform,
            device = source.device,
            appVersion = source.appVersion,
            startedAtEpochMs = startedAtEpochMs,
            sampleRateHz = detectorSampleRate,
            offsetsMs = offsets.toList(),
            accel = accel.toList(),
            gyro = gyro.toList(),
            gravity = gravity.toList(),
            golpes = golpesVistos.toList(),
            descartes = detector.descartes,
        )
    }

    private val detectorSampleRate = config.sampleRateHz

    companion object {
        /**
         * Tope de cinco minutos a 50 Hz. Una tanda son 30-40 golpes —dos o tres
         * minutos— y sin tope un "grabar" olvidado se comería la memoria del reloj.
         */
        const val MAX_MUESTRAS = 5 * 60 * 50
    }
}
