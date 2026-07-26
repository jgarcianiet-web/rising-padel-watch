package com.risingpadel.core.detection

import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.Vector3
import kotlin.math.abs
import kotlin.math.asin

/** Resultado de clasificar un golpeo ya detectado. */
data class Classification(val type: ShotType, val confidence: Float)

/**
 * Decide de qué tipo es un golpeo a partir de sus rasgos. Ver `docs/shot-detection.md`.
 *
 * Está separado de [ShotDetector] a propósito: la detección (¿hubo golpeo?) es estable,
 * mientras que la clasificación (¿de qué tipo?) es la pieza que se sustituirá por un
 * modelo entrenado cuando haya datos etiquetados.
 */
class ShotClassifier(
    private val config: DetectorConfig = DetectorConfig.DEFAULT,
    private val profile: PlayerProfile = PlayerProfile(),
) {

    /**
     * Eje codo → mano en coordenadas del dispositivo. Con el reloj en la muñeca
     * izquierda el dispositivo está girado 180° sobre su eje Z respecto al brazo, así
     * que el eje físico apunta al contrario.
     */
    private val forearmAxis: Vector3 =
        if (profile.watchWrist == Hand.RIGHT) config.forearmAxis.normalized()
        else (-config.forearmAxis).normalized()

    /**
     * Un jugador zurdo es la imagen especular de uno diestro, y una imagen especular
     * invierte el signo de la rotación sobre el eje del antebrazo.
     */
    private val handSign: Float = if (profile.hand == Hand.RIGHT) 1f else -1f

    private val axialSign: Float = handSign * (if (config.invertAxialSign) -1f else 1f)

    /**
     * Elevación del antebrazo sobre la horizontal, en grados.
     * +90 = antebrazo vertical hacia arriba, 0 = horizontal, -90 = hacia abajo.
     */
    fun elevationDeg(gravity: Vector3): Float {
        val up = (-gravity).normalized()
        if (up == Vector3.ZERO) return 0f
        val sin = forearmAxis.dot(up).coerceIn(-1f, 1f)
        return Math.toDegrees(asin(sin).toDouble()).toFloat()
    }

    /**
     * Rotación sobre el eje del antebrazo, normalizada para que **positivo = lado de
     * derecha** y negativo = lado de revés, sea cual sea la mano y la muñeca.
     */
    fun axialRotation(meanGyro: Vector3): Float = meanGyro.dot(forearmAxis) * axialSign

    fun classify(features: ShotFeatures): Classification {
        val overhead = features.elevationDeg > config.overheadElevationDeg
        val elevationMargin = margin(
            value = features.elevationDeg,
            threshold = config.overheadElevationDeg,
            scale = 45f,
        )

        if (overhead) {
            val isServe = features.sweptAngleDeg > config.serveSweptDeg &&
                features.peakGyroRadS > config.servePeakGyroRadS
            // La escala es media frontera y no la frontera entera: un smash de 140°
            // está lejos del saque en términos prácticos aunque en valor absoluto se
            // quede a menos de la mitad del umbral.
            val sweptMargin =
                margin(features.sweptAngleDeg, config.serveSweptDeg, config.serveSweptDeg * 0.5f)
            // En la rama alta la rotación axial no participa en la decisión, así que no
            // debe penalizar la confianza: se reparte entre los dos rasgos que sí deciden.
            val confidence = 0.5f * sweptMargin + 0.5f * elevationMargin
            return finalize(if (isServe) ShotType.SERVE else ShotType.OVERHEAD, confidence)
        }

        val axial = features.axialRotationRadS
        val volley = features.sweptAngleDeg < config.volleySweptDeg
        val sweptMargin = margin(features.sweptAngleDeg, config.volleySweptDeg, config.volleySweptDeg)
        val axialMargin = (abs(axial) / config.axialConfidenceScaleRadS).coerceIn(0f, 1f)
        val confidence = 0.35f * sweptMargin + 0.35f * axialMargin + 0.30f * elevationMargin

        val type = when {
            volley && axial > 0f -> ShotType.FOREHAND_VOLLEY
            volley -> ShotType.BACKHAND_VOLLEY
            axial > 0f -> ShotType.FOREHAND
            else -> ShotType.BACKHAND
        }
        return finalize(type, confidence)
    }

    /**
     * Un golpeo poco fiable se reporta como UNKNOWN, pero conserva su confianza: sigue
     * contando en el total y la UI puede mostrar por qué no se clasificó.
     */
    private fun finalize(type: ShotType, confidence: Float): Classification {
        val clamped = confidence.coerceIn(0f, 1f)
        return if (clamped < config.minConfidence) Classification(ShotType.UNKNOWN, clamped)
        else Classification(type, clamped)
    }

    /** Distancia normalizada de un rasgo a su umbral de decisión: 0 = justo en la frontera. */
    private fun margin(value: Float, threshold: Float, scale: Float): Float =
        (abs(value - threshold) / scale).coerceIn(0f, 1f)
}
