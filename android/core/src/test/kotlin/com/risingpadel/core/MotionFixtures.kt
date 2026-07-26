package com.risingpadel.core

import com.risingpadel.core.model.MotionSample
import com.risingpadel.core.model.Vector3
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Generador de señales sintéticas de muñeca.
 *
 * Modela un golpeo como media onda de seno en la velocidad angular (acelera, alcanza el
 * pico, frena) con un pico gaussiano corto de aceleración en el instante del impacto,
 * situado al 75% del swing. Es la forma que tienen las señales reales de un golpeo de
 * raqueta, y es suficiente para fijar el comportamiento del detector frente a
 * regresiones.
 *
 * No sustituye a la validación en pista: sirve para que el algoritmo no cambie sin
 * querer, no para demostrar que acierta con jugadores reales.
 */
object MotionFixtures {

    const val SAMPLE_RATE_HZ = 50
    const val SAMPLE_INTERVAL_MS = 1000L / SAMPLE_RATE_HZ

    /**
     * @param peakGyroRadS pico de velocidad angular del swing.
     * @param swingDurationMs duración total del swing (el impacto cae al 75%).
     * @param axialFraction fracción de la rotación que va sobre el eje del antebrazo,
     *   con signo: positivo = lado de derecha, negativo = lado de revés.
     * @param elevationDeg elevación del antebrazo sobre la horizontal en el impacto.
     */
    fun swing(
        startMs: Long,
        peakGyroRadS: Float,
        swingDurationMs: Long,
        impactG: Float,
        axialFraction: Float,
        elevationDeg: Float,
        impactFraction: Float = 0.75f,
    ): List<MotionSample> {
        val steps = (swingDurationMs / SAMPLE_INTERVAL_MS).toInt()
        require(steps >= 4) { "swing demasiado corto para $SAMPLE_RATE_HZ Hz" }
        val impactIndex = (steps * impactFraction).roundToInt()

        val elevationRad = elevationDeg * PI.toFloat() / 180f
        // up = (cos e, sin e, 0) ⇒ el eje del antebrazo (+Y) forma `elevationDeg` con la horizontal.
        val gravity = Vector3(-cos(elevationRad), -sin(elevationRad), 0f)

        val lateral = sqrt((1f - axialFraction * axialFraction).coerceAtLeast(0f))
        val gyroDirection = Vector3(lateral, axialFraction, 0f)

        return (0..steps).map { i ->
            val gyroMag = peakGyroRadS * sin(PI * i / steps).toFloat()
            val fromImpactMs = (i - impactIndex) * SAMPLE_INTERVAL_MS.toFloat()
            val spike = impactG * exp(-(fromImpactMs / IMPACT_SIGMA_MS).let { it * it })
            MotionSample(
                timestampMs = startMs + i * SAMPLE_INTERVAL_MS,
                accel = Vector3(BASELINE_ACCEL_G + spike, 0f, 0f),
                gyro = gyroDirection * gyroMag,
                gravity = gravity,
            )
        }
    }

    /** Muñeca quieta: el detector debe volver a IDLE. */
    fun rest(startMs: Long, durationMs: Long, elevationDeg: Float = 0f): List<MotionSample> {
        val steps = (durationMs / SAMPLE_INTERVAL_MS).toInt()
        val elevationRad = elevationDeg * PI.toFloat() / 180f
        val gravity = Vector3(-cos(elevationRad), -sin(elevationRad), 0f)
        return (0 until steps).map { i ->
            MotionSample(
                timestampMs = startMs + i * SAMPLE_INTERVAL_MS,
                accel = Vector3(BASELINE_ACCEL_G, 0f, 0f),
                gyro = Vector3(0.2f, 0.1f, 0.05f),
                gravity = gravity,
            )
        }
    }

    /**
     * Correr por la pista: picos de aceleración grandes (hasta 3.5 g al apoyar) pero
     * poca velocidad angular en la muñeca. El detector no debe contar golpeos.
     */
    fun running(startMs: Long, durationMs: Long): List<MotionSample> {
        val steps = (durationMs / SAMPLE_INTERVAL_MS).toInt()
        return (0 until steps).map { i ->
            val t = i * SAMPLE_INTERVAL_MS / 1000f
            val stride = sin(2 * PI * STRIDE_HZ * t).toFloat()
            MotionSample(
                timestampMs = startMs + i * SAMPLE_INTERVAL_MS,
                accel = Vector3(1.8f * stride, 1.2f * stride, 0.6f * stride) * 1.2f,
                gyro = Vector3(1.6f * stride, 0.9f * stride, 0.4f * stride),
                gravity = Vector3(-1f, 0f, 0f),
            )
        }
    }

    /**
     * Golpe seco sin swing: chocar la pala con el compañero, botar la pelota fuerte.
     * Pico de aceleración alto con la muñeca casi parada.
     */
    fun tapWithoutSwing(startMs: Long, impactG: Float = 6f): List<MotionSample> {
        val steps = 20
        val impactIndex = 10
        return (0..steps).map { i ->
            val fromImpactMs = (i - impactIndex) * SAMPLE_INTERVAL_MS.toFloat()
            val spike = impactG * exp(-(fromImpactMs / IMPACT_SIGMA_MS).let { it * it })
            MotionSample(
                timestampMs = startMs + i * SAMPLE_INTERVAL_MS,
                accel = Vector3(BASELINE_ACCEL_G + spike, 0f, 0f),
                gyro = Vector3(0.8f, 0.5f, 0.2f),
                gravity = Vector3(-1f, 0f, 0f),
            )
        }
    }

    // --- golpeos tipo, con parámetros dentro del rango de un jugador adulto medio ---

    fun forehand(startMs: Long) = swing(
        startMs = startMs,
        peakGyroRadS = 20f,
        swingDurationMs = 300,
        impactG = 6.5f,
        axialFraction = 0.8f,
        elevationDeg = 10f,
    )

    fun backhand(startMs: Long) = swing(
        startMs = startMs,
        peakGyroRadS = 18f,
        swingDurationMs = 300,
        impactG = 5.5f,
        axialFraction = -0.8f,
        elevationDeg = 8f,
    )

    fun forehandVolley(startMs: Long) = swing(
        startMs = startMs,
        peakGyroRadS = 7f,
        swingDurationMs = 280,
        impactG = 4.0f,
        axialFraction = 0.75f,
        elevationDeg = 12f,
    )

    fun backhandVolley(startMs: Long) = swing(
        startMs = startMs,
        peakGyroRadS = 7f,
        swingDurationMs = 280,
        impactG = 4.0f,
        axialFraction = -0.75f,
        elevationDeg = 12f,
    )

    /** Bandeja / smash: brazo alto y swing contenido. */
    fun overhead(startMs: Long) = swing(
        startMs = startMs,
        peakGyroRadS = 18f,
        swingDurationMs = 250,
        impactG = 8f,
        axialFraction = 0.5f,
        elevationDeg = 80f,
    )

    /** Saque: brazo alto y swing completo. */
    fun serve(startMs: Long) = swing(
        startMs = startMs,
        peakGyroRadS = 28f,
        swingDurationMs = 350,
        impactG = 9f,
        axialFraction = 0.6f,
        elevationDeg = 60f,
    )

    private const val BASELINE_ACCEL_G = 0.2f
    private const val IMPACT_SIGMA_MS = 25f
    private const val STRIDE_HZ = 2.8f
}
