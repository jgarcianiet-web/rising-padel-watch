package com.risingpadel.core.detection

import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.Vector3

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
class ShotDetector(
    private val config: DetectorConfig = DetectorConfig.DEFAULT,
    profile: PlayerProfile = PlayerProfile(),
) {
    private enum class State { IDLE, SWINGING }

    private val classifier = ShotClassifier(config, profile)

    /** Ventana de muestras recientes, solo para promediar la rotación axial pre-impacto. */
    private val window = ArrayDeque<MotionSample>()
    private val windowCapacity =
        (config.axialWindowMs / config.sampleIntervalMs).toInt().coerceAtLeast(4) + 4

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
    private var refractoryUntilMs = Long.MIN_VALUE

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
        refractoryUntilMs = Long.MIN_VALUE
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

                val duration = s.timestampMs - swingStartMs
                val isImpact = accelMag > config.impactG &&
                    accelMag >= (before?.accel?.magnitude() ?: 0f) &&
                    accelMag > after.accel.magnitude()

                when {
                    isImpact && duration >= config.minSwingMs && peakGyroRadS >= config.minPeakGyroRadS ->
                        emitShot(s, accelMag, duration)

                    // Impacto sin swing con energía suficiente: botar la pelota, chocar
                    // la pala. No es un golpeo.
                    isImpact -> {
                        goIdle()
                        null
                    }

                    duration > config.maxSwingMs -> {
                        goIdle()
                        null
                    }

                    // El swing se apaga sin llegar a impactar: amago o preparación.
                    gyroMag < config.swingOnsetRadS * 0.5f -> {
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
            // El ángulo barrido arranca en el inicio real del swing, no en la muestra
            // que lo confirma.
            sweptAngleRad = pendingSweptRad
            peakGyroRadS = gyroMag
            onsetCount = 0
            pendingSweptRad = 0f
        }
    }

    private fun emitShot(impact: MotionSample, impactG: Float, durationMs: Long): Shot {
        val features = ShotFeatures(
            sweptAngleDeg = Math.toDegrees(sweptAngleRad.toDouble()).toFloat(),
            peakGyroRadS = peakGyroRadS,
            // La gravedad se promedia sobre la ventana previa, igual que el giro axial:
            // en la muestra del impacto (5-10 g, 15+ rad/s) la estimación de gravedad
            // del sistema se va decenas de grados y las derechas salían como "altas".
            elevationDeg = classifier.elevationDeg(meanGravityBefore(impact)),
            axialRotationRadS = classifier.axialRotation(meanGyroBefore(impact.timestampMs)),
            swingDurationMs = durationMs,
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
    }

    /** Media vectorial del giróscopo en la ventana previa al impacto. */
    private fun meanGravityBefore(impact: MotionSample): Vector3 {
        // La ventana no entra en la preparación: en un golpeo corto (un smash dura
        // ~170 ms) las muestras de antes del swing describen cómo esperaba el brazo,
        // no cómo golpeó, y arrastran la elevación decenas de grados.
        val from = maxOf(impact.timestampMs - config.axialWindowMs, swingStartMs)
        var sum = Vector3.ZERO
        var count = 0
        for (sample in window) {
            if (sample.timestampMs in from..impact.timestampMs) {
                sum += sample.gravity
                count++
            }
        }
        return if (count == 0) impact.gravity else sum * (1f / count)
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
