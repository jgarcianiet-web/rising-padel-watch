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
        // La pregunta que separa un golpe alto de uno de fondo es "¿pasó la mano por
        // encima del hombro?", y esa la responde el recorrido del swing, no la postura
        // en el instante del impacto. Ver el comentario de `peakElevationDeg`.
        val overhead = features.peakElevationDeg > config.overheadElevationDeg
        val elevationMargin = margin(
            value = features.peakElevationDeg,
            threshold = config.overheadElevationDeg,
            scale = 15f,
        )

        if (overhead) {
            return classifyOverhead(features, elevationMargin)
        }

        val axial = features.axialRotationRadS
        val axialAbs = abs(axial)
        // La firma de la volea es doble (validado en pista, ago 2026): swing corto, o
        // swing medio con la pala quieta — voleas reales con acompañamiento barrían
        // 147-170° pero con axial 0.3-3.8, mientras un golpe de fondo lleva efecto de
        // sobra (7.9-10.5 en derechas reales).
        val volley = features.sweptAngleDeg < config.volleySweptDeg ||
            (features.sweptAngleDeg < config.volleyMaxSweptDeg &&
                axialAbs < config.volleyAxialMaxRadS)

        val confidence: Float
        if (volley) {
            // A una volea no se le puede pedir efecto: la vieja fórmula castigaba el
            // axial bajo — que es justo lo que define una volea — y ejecutaba golpes
            // bien clasificados. Aquí la confianza premia lo compacta (lejos del techo
            // de barrido) y lo quieta (poco axial) que es.
            val compactMargin = margin(
                features.sweptAngleDeg, config.volleyMaxSweptDeg, config.volleyMaxSweptDeg
            )
            val quietMargin = 1f - (axialAbs / config.volleyAxialMaxRadS).coerceIn(0f, 1f)
            confidence = 0.4f * compactMargin + 0.3f * quietMargin + 0.3f * elevationMargin
        } else {
            val sweptMargin = margin(features.sweptAngleDeg, config.volleySweptDeg, config.volleySweptDeg)
            val axialMargin = (axialAbs / config.axialConfidenceScaleRadS).coerceIn(0f, 1f)
            confidence = 0.35f * sweptMargin + 0.35f * axialMargin + 0.30f * elevationMargin
        }

        val type = when {
            volley && axial > 0f -> ShotType.FOREHAND_VOLLEY
            volley -> ShotType.BACKHAND_VOLLEY
            axial > 0f -> ShotType.FOREHAND
            else -> ShotType.BACKHAND
        }
        return finalize(type, confidence)
    }

    /**
     * Los cuatro golpeos por encima de la cabeza, en orden de decisión:
     *
     * 1. **Saque**: swing completo (barre mucho más ángulo que cualquier otro alto).
     * 2. **Smash**: violencia — pico de giro por encima de [DetectorConfig.smashPeakGyroRadS].
     * 3. **Víbora**: efecto — rotación axial alta sin la violencia del smash.
     * 4. **Bandeja**: el resto; el golpe alto de control, plano y sin exceso.
     *
     * El orden importa: un smash suele llevar también algo de efecto, pero la violencia
     * lo define antes de que la rotación axial pueda confundirlo con una víbora.
     */
    private fun classifyOverhead(features: ShotFeatures, elevationMargin: Float): Classification {
        // La escala del margen es media frontera y no la frontera entera: una bandeja
        // de 140° está lejos del saque en términos prácticos aunque en valor absoluto
        // se quede a menos de la mitad del umbral.
        val sweptMargin =
            margin(features.sweptAngleDeg, config.serveSweptDeg, config.serveSweptDeg * 0.5f)

        val isServe = features.sweptAngleDeg > config.serveSweptDeg &&
            features.peakGyroRadS > config.servePeakGyroRadS
        if (isServe) {
            // En el saque la rotación axial no participa en la decisión, así que no debe
            // penalizar la confianza: se reparte entre los dos rasgos que sí deciden.
            return finalize(ShotType.SERVE, 0.5f * sweptMargin + 0.5f * elevationMargin)
        }

        val axialAbs = abs(features.axialRotationRadS)
        val peakMargin =
            margin(features.peakGyroRadS, config.smashPeakGyroRadS, config.smashPeakGyroRadS * 0.35f)
        // Media frontera, como el saque: una víbora real promedia 10-14 rad/s de axial
        // y con la frontera entera de escala nunca pasaría del confianza mínima.
        val axialMargin = margin(axialAbs, config.viboraAxialRadS, config.viboraAxialRadS * 0.5f)

        val type = when {
            features.peakGyroRadS > config.smashPeakGyroRadS -> ShotType.SMASH
            axialAbs > config.viboraAxialRadS -> ShotType.VIBORA
            else -> ShotType.BANDEJA
        }
        // El rasgo que decidió cada tipo es el que más pesa en su confianza; la
        // distancia al saque y la elevación completan el reparto.
        val decisionMargin = if (type == ShotType.SMASH) peakMargin else axialMargin
        return finalize(type, 0.4f * decisionMargin + 0.3f * sweptMargin + 0.3f * elevationMargin)
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
