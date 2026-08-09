package com.risingpadel.core.detection

import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.Vector3
import kotlin.math.abs

/**
 * Detector de golpeos en streaming. Ver `docs/shot-detection.md`.
 *
 * Consume muestras a [DetectorConfig.sampleRateHz] y devuelve un [Shot] en la muestra
 * en la que se cierra un golpeo, o null. No reserva memoria por muestra más allá de una
 * ventana corta, así que puede correr en el reloj durante horas.
 *
 * Trabaja con **una muestra de retardo** (20 ms a 50 Hz): para confirmar que el pico de
 * aceleración es un máximo local hace falta ver la muestra siguiente.
 *
 * No es thread-safe: hay que llamarlo desde un único hilo (el del callback de sensores).
 */
/**
 * Los swings que el detector vio y tiró, con el motivo.
 *
 * Existe porque hasta ahora los golpes que **no** se detectan eran invisibles: las
 * tandas de entrenamiento solo guardan ventanas alrededor de lo que sí se detectó, así
 * que un golpe perdido no deja rastro en ningún sitio. Se podía medir cuánto se
 * equivoca el clasificador, pero no cuánto se le escapa al detector — que es la pérdida
 * más grande y la que hace que nada converja.
 *
 * Cada contador apunta a **un umbral concreto**, así que dejan de hacer falta las
 * conjeturas: si se acumulan en `swingSinImpacto`, sobra `impactG` para golpes suaves
 * como la bandeja o la volea; si es `impactoConSwingCorto`, sobran `minSwingMs` o
 * `minPeakGyroRadS`.
 */
@kotlinx.serialization.Serializable
data class DescartesDelDetector(
    /** Hubo impacto pero el swing fue corto o flojo: `minSwingMs` / `minPeakGyroRadS`. */
    val impactoConSwingCorto: Int = 0,
    /** El swing duró más de la cuenta sin que se viera impacto: `impactG` demasiado alto. */
    val swingSinImpacto: Int = 0,
    /** El giro se apagó sin llegar a impactar: amago o preparación. */
    val amago: Int = 0,
    /** Llegó dentro del tiempo muerto del golpe anterior: `refractoryMs`. */
    val enRefractario: Int = 0,
) {
    val total: Int get() = impactoConSwingCorto + swingSinImpacto + amago + enRefractario
}

class ShotDetector(
    private val config: DetectorConfig = DetectorConfig.DEFAULT,
    profile: PlayerProfile = PlayerProfile(),
) {
    private enum class State { IDLE, SWINGING }

    private val classifier = ShotClassifier(config, profile)

    /** Ventana de muestras recientes, solo para promediar la rotación axial pre-impacto. */
    private val window = ArrayDeque<MotionSample>()
    private val windowCapacity =
        (maxOf(config.axialWindowMs, config.prepWindowMs + 200) / config.sampleIntervalMs)
            .toInt().coerceAtLeast(4) + 4

    private var referenceMs: Long? = null
    private var prevPrev: MotionSample? = null
    private var prev: MotionSample? = null

    private var state = State.IDLE
    private var onsetCount = 0
    private var candidateStartMs = 0L
    private var pendingSweptRad = 0f
    private var swingStartMs = 0L
    private var sweptAngleRad = 0f
    private var peakGyroRadS = 0f
    /** Mayor rotación axial vista en el swing, con su signo. */
    private var peakAxialRadS = 0f

    /**
     * Elevación del antebrazo en cada muestra del swing. Se guarda la serie entera —como
     * mucho 45 valores a 50 Hz— porque las estadísticas robustas (mediana, percentil)
     * necesitan verla completa, y un solo valor instantáneo no vale: la estimación de
     * gravedad del sistema se va decenas de grados en mitad de un golpe.
     */
    private val swingElevations = ArrayList<Float>()
    /** Elevación de preparación del swing en curso (null si no hubo muestras calmadas). */
    private var prepElevationDeg: Float? = null
    private var refractoryUntilMs = Long.MIN_VALUE

    /** Lo que se ha tirado desde el último [reset], por motivo. */
    var descartes = DescartesDelDetector()
        private set

    /** Reinicia el detector y fija el origen de tiempos de la sesión. */
    fun reset(referenceTimestampMs: Long? = null) {
        window.clear()
        referenceMs = referenceTimestampMs
        prevPrev = null
        prev = null
        state = State.IDLE
        onsetCount = 0
        pendingSweptRad = 0f
        sweptAngleRad = 0f
        peakGyroRadS = 0f
        peakAxialRadS = 0f
        refractoryUntilMs = Long.MIN_VALUE
        descartes = DescartesDelDetector()
    }

    /** Procesa una muestra. Devuelve el golpeo si esta muestra cierra uno. */
    fun process(sample: MotionSample): Shot? {
        if (referenceMs == null) referenceMs = sample.timestampMs
        val pending = prev
        val shot = if (pending != null) evaluate(prevPrev, pending, sample) else null
        prevPrev = prev
        prev = sample
        return shot
    }

    /**
     * Cierra el stream. Evalúa la última muestra pendiente contra una muestra sintética
     * en reposo, para no perder un golpeo que caiga justo al final de la sesión.
     */
    fun flush(): Shot? {
        val pending = prev ?: return null
        val synthetic = pending.copy(
            timestampMs = pending.timestampMs + config.sampleIntervalMs,
            accel = Vector3.ZERO,
            gyro = Vector3.ZERO,
        )
        val shot = evaluate(prevPrev, pending, synthetic)
        prevPrev = null
        prev = null
        return shot
    }

    private fun evaluate(before: MotionSample?, s: MotionSample, after: MotionSample): Shot? {
        pushWindow(s)

        if (s.timestampMs < refractoryUntilMs) {
            // Solo cuenta como descarte si venía un swing en marcha: el silencio entre
            // golpes también cae aquí y no es nada que se esté perdiendo.
            if (state == State.SWINGING) {
                descartes = descartes.copy(enRefractario = descartes.enRefractario + 1)
            }
            state = State.IDLE
            onsetCount = 0
            pendingSweptRad = 0f
            return null
        }

        val gyroMag = s.gyro.magnitude()
        val accelMag = s.accel.magnitude()
        val dt = deltaSeconds(before, s)

        return when (state) {
            State.IDLE -> {
                trackOnset(s, gyroMag, dt)
                null
            }

            State.SWINGING -> {
                sweptAngleRad += gyroMag * dt
                if (gyroMag > peakGyroRadS) peakGyroRadS = gyroMag
                // El pico de rotación axial se mide muestra a muestra: una víbora no
                // rota todo el swing, da un latigazo al final, y la media lo borra.
                val axialAhora = classifier.axialRotation(s.gyro)
                if (abs(axialAhora) > abs(peakAxialRadS)) peakAxialRadS = axialAhora
                swingElevations += classifier.elevationDeg(s.gravity)

                val duration = s.timestampMs - swingStartMs
                val isImpact = accelMag > config.impactG &&
                    accelMag >= (before?.accel?.magnitude() ?: 0f) &&
                    accelMag > after.accel.magnitude()

                when {
                    isImpact && duration >= config.minSwingMs && peakGyroRadS >= config.minPeakGyroRadS ->
                        emitShot(s, accelMag, duration)

                    // Impacto sin swing con energía suficiente: botar la pelota, chocar
                    // la pala. No es un golpeo... o sí lo era y el umbral pide demasiado.
                    isImpact -> {
                        descartes = descartes.copy(
                            impactoConSwingCorto = descartes.impactoConSwingCorto + 1
                        )
                        goIdle()
                        null
                    }

                    duration > config.maxSwingMs -> {
                        descartes = descartes.copy(
                            swingSinImpacto = descartes.swingSinImpacto + 1
                        )
                        goIdle()
                        null
                    }

                    // El swing se apaga sin llegar a impactar: amago o preparación.
                    gyroMag < config.swingOnsetRadS * 0.5f -> {
                        descartes = descartes.copy(amago = descartes.amago + 1)
                        goIdle()
                        null
                    }

                    else -> null
                }
            }
        }
    }

    private fun trackOnset(s: MotionSample, gyroMag: Float, dt: Float) {
        if (gyroMag <= config.swingOnsetRadS) {
            onsetCount = 0
            pendingSweptRad = 0f
            return
        }
        if (onsetCount == 0) {
            candidateStartMs = s.timestampMs
            pendingSweptRad = 0f
        }
        onsetCount++
        pendingSweptRad += gyroMag * dt
        if (onsetCount >= config.onsetSamples) {
            state = State.SWINGING
            swingStartMs = candidateStartMs
            // La preparación: mediana de la elevación en la ventana previa al arranque,
            // cuando el brazo aún estaba calmado y la gravedad era de fiar. Es el
            // testigo honesto de si el golpe se armó en alto — durante el swing
            // violento el filtro de gravedad se corrompe (validado en pista, ago 2026:
            // remates reales con pico de elevación medido a +3° o −41°).
            val calmadas = window
                .filter { it.timestampMs in (candidateStartMs - config.prepWindowMs) until candidateStartMs }
                .map { classifier.elevationDeg(it.gravity) }
                .sorted()
            prepElevationDeg = if (calmadas.size >= 3) calmadas[calmadas.size / 2] else null
            swingElevations.clear()
            swingElevations += classifier.elevationDeg(s.gravity)
            // El ángulo barrido arranca en el inicio real del swing, no en la muestra
            // que lo confirma.
            sweptAngleRad = pendingSweptRad
            peakGyroRadS = gyroMag
            onsetCount = 0
            pendingSweptRad = 0f
        }
    }

    private fun emitShot(impact: MotionSample, impactG: Float, durationMs: Long): Shot {
        val elevations = swingElevations.sorted()
        val features = ShotFeatures(
            sweptAngleDeg = Math.toDegrees(sweptAngleRad.toDouble()).toFloat(),
            peakGyroRadS = peakGyroRadS,
            // Estadísticas sobre el swing entero, no un valor suelto: ni la muestra del
            // impacto (5-10 g de golpe descuadran el filtro de gravedad) ni la media de
            // la ventana previa (se promedia sobre un arco de 100-200°) describen la
            // postura del brazo. Ver `docs/shot-detection.md`.
            elevationDeg = percentile(elevations, 0.5f),
            axialRotationRadS = classifier.axialRotation(meanGyroBefore(impact.timestampMs)),
            swingDurationMs = durationMs,
            peakElevationDeg = percentile(elevations, 0.8f),
            prepElevationDeg = prepElevationDeg,
            peakAxialRotationRadS = peakAxialRadS,
            // De lo más alto del swing a donde estaba el brazo al golpear. Positivo =
            // el brazo bajó, que es la firma del remate.
            elevationDropDeg = if (swingElevations.isEmpty()) null else
                percentile(elevations, 0.9f) - classifier.elevationDeg(impact.gravity),
        )
        val classification = classifier.classify(features)
        val shot = Shot(
            offsetMs = (impact.timestampMs - (referenceMs ?: impact.timestampMs)).coerceAtLeast(0L),
            type = classification.type,
            racketSpeedKmh = peakGyroRadS * config.armLeverM * 3.6f,
            impactG = impactG,
            confidence = classification.confidence,
            features = features,
        )
        refractoryUntilMs = impact.timestampMs + config.refractoryMs
        goIdle()
        return shot
    }

    private fun goIdle() {
        state = State.IDLE
        onsetCount = 0
        pendingSweptRad = 0f
        sweptAngleRad = 0f
        peakGyroRadS = 0f
        peakAxialRadS = 0f
        swingElevations.clear()
    }

    /** Percentil de una lista **ya ordenada**. Lista vacía = 0. */
    private fun percentile(sorted: List<Float>, fraction: Float): Float {
        if (sorted.isEmpty()) return 0f
        val index = ((sorted.size - 1) * fraction).toInt().coerceIn(0, sorted.size - 1)
        return sorted[index]
    }

    private fun meanGyroBefore(impactMs: Long): Vector3 {
        val from = impactMs - config.axialWindowMs
        var sum = Vector3.ZERO
        var count = 0
        for (sample in window) {
            if (sample.timestampMs in from..impactMs) {
                sum += sample.gyro
                count++
            }
        }
        return if (count == 0) Vector3.ZERO else sum * (1f / count)
    }

    private fun pushWindow(sample: MotionSample) {
        window.addLast(sample)
        while (window.size > windowCapacity) window.removeFirst()
    }

    /**
     * dt real entre muestras, acotado: si el sistema entrega muestras con un hueco
     * (app suspendida, sensor saturado) no debe inflar el ángulo barrido.
     */
    private fun deltaSeconds(before: MotionSample?, s: MotionSample): Float {
        val defaultDt = 1f / config.sampleRateHz
        if (before == null) return defaultDt
        val dt = (s.timestampMs - before.timestampMs) / 1000f
        return if (dt <= 0f) defaultDt else dt.coerceAtMost(0.1f)
    }
}
