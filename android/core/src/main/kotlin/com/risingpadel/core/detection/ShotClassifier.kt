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
     * El bosque entrenado, si esta versión lleva uno. Inyectable para poder probarlo
     * sin esperar a que exista el de fábrica.
     */
    private val modelo: ModeloDeGolpes? = ModeloEntrenado.actual

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
        // El modelo entrenado manda cuando lo hay y cuando está seguro; si no, la
        // heurística, que además es la que sabe decir por qué. Ver `ModeloDeGolpes`.
        modelo?.clasificar(features)?.let {
            if (it.confidence >= ModeloEntrenado.MIN_VOTOS) return it
        }
        return porHeuristica(features)
    }

    private fun porHeuristica(features: ShotFeatures): Classification {
        // La pregunta que separa un golpe alto de uno de fondo es "¿pasó la mano por
        // encima del hombro?", y esa la responde el recorrido del swing, no la postura
        // en el instante del impacto. Ver el comentario de `peakElevationDeg`.
        // Dos testigos de golpe alto: hasta dónde subió el brazo durante el swing, y
        // cómo estaba armado en la preparación. El segundo manda cuando existe: se
        // mide con el brazo calmado, donde la gravedad es fiable — en pista (ago
        // 2026) los remates reales salían con el pico corrupto (+3°, −41°) y solo la
        // preparación los delataba.
        val overhead = features.peakElevationDeg > config.overheadElevationDeg ||
            (features.prepElevationDeg ?: -90f) > config.prepOverheadElevationDeg
        // El margen se mide sobre el MISMO rasgo que decide, el pico. Antes se medía
        // sobre el máximo de pico y preparación, y eso mezclaba dos escalas: la
        // preparación se compara contra su propio umbral, no contra el del pico. Con la
        // puerta en la horizontal el error se volvió visible — una volea de revés se
        // arma a +20° de preparación, así que su "margen" salía cero y el golpe acababa
        // sin clasificar por dudoso cuando de dudoso no tenía nada.
        val elevationMargin = margin(
            value = features.peakElevationDeg,
            threshold = config.overheadElevationDeg,
            scale = 15f,
        )

        if (overhead) {
            return classifyOverhead(features, elevationMargin)
        }

        // El saque se decide DESPUÉS de descartar el golpe alto, y a propósito.
        //
        // Estuvo antes durante una tanda, cuando la elevación llegaba con el eje girado
        // y no se podía confiar en ella: entonces adelantar el saque salvaba tres de
        // cinco. Con el eje ya bien, la elevación es el rasgo más limpio que hay —los
        // altos y los bajos no se solapan ni en un grado— y adelantar el saque cuesta
        // más de lo que da: el saque del pádel se golpea **a la cintura**, así que un
        // golpe que pica a +33° no puede serlo por mucho que barra. En la tanda limpia
        // (ago 2026) la regla del saque se estaba llevando una víbora que barrió 348°.
        //
        // La firma sigue siendo la misma —barrido largo con mucha pronación—, solo que
        // ahora se le pide además no haber pasado por encima de la cabeza.
        val axialDelSaque = abs(features.axialRotationRadS)
        if (axialDelSaque >= config.serveAxialRadS &&
            features.sweptAngleDeg >= config.serveSweptDeg
        ) {
            // Base alta a propósito: pasar dos puertas independientes —rotar como un
            // saque Y barrer como un saque— ya es prueba de sobra. Con la fórmula de
            // solo márgenes, un saque justo en la frontera salía con 0,16 de confianza
            // y el detector lo tiraba por dudoso, que es lo contrario de lo que pasaba.
            val axialMargin = margin(axialDelSaque, config.serveAxialRadS, config.serveAxialRadS * 0.5f)
            val sweptMargin = margin(features.sweptAngleDeg, config.serveSweptDeg, config.serveSweptDeg * 0.3f)
            return finalize(ShotType.SERVE, 0.5f + 0.25f * axialMargin + 0.25f * sweptMargin)
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
            // Base alta, como en el saque y por el mismo motivo: haber pasado la puerta
            // de la volea —compacta o con la pala quieta— y no ser un golpe alto ya son
            // dos pruebas independientes. Sin base, una volea con acompañamiento salía a
            // 0,38 y el detector la tiraba por dudosa; y una volea con acompañamiento es
            // una volea de manual, no una duda.
            confidence = 0.5f + 0.2f * compactMargin + 0.15f * quietMargin +
                0.15f * elevationMargin
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
        // Aquí ya no vive el saque: el saque del pádel es BAJO (se arma a la cintura),
        // así que se decide antes, por su pronación. Herencia del tenis corregida en
        // pista (ago 2026): un remate real barrió 291° y caía como "saque".
        //
        // Entre los tres golpes altos manda la ALTURA DEL GOLPEO, no el efecto. La
        // bandeja y la víbora empiezan igual —brazo arriba— pero la víbora se golpea
        // más baja: es un golpe cortado que sale más plano. Con la tanda de ocho tipos
        // en la mano, la bandeja pica a +25° de mediana y la víbora a +4°.
        //
        // El efecto NO sirve para separarlas, aunque parezca lo lógico: la rotación
        // axial media de las víboras (−2,0) y la de las bandejas (−1,9) son el mismo
        // número. Una víbora no rota todo el swing, da un latigazo al final, y
        // promediarlo sobre 200° de arco lo borra. Por eso se mide ahora el pico de
        // rotación ([ShotFeatures.peakAxialRotationRadS]), que aún no tiene tanda con
        // la que fijar su umbral.
        val alturaMargin = margin(
            features.peakElevationDeg, config.viboraElevationDeg, config.viboraElevationDeg
        )
        val peakMargin =
            margin(features.peakGyroRadS, config.smashPeakGyroRadS, config.smashPeakGyroRadS * 0.35f)

        val type = when {
            features.peakGyroRadS > config.smashPeakGyroRadS -> ShotType.SMASH
            features.peakElevationDeg >= config.viboraElevationDeg -> ShotType.BANDEJA
            else -> ShotType.VIBORA
        }
        // Dos rasgos y ya: el que decidió el tipo, y la certeza de que fue golpe alto.
        // El barrido no aporta aquí (los tres golpes altos barren parecido).
        val decisionMargin = if (type == ShotType.SMASH) peakMargin else alturaMargin
        // Misma base que la volea: si el golpe pasó la puerta de altura, es uno de los
        // tres altos con seguridad; lo único que queda por decidir es cuál. Reportarlo
        // como "sin clasificar" tiraría un golpe del que se sabe casi todo — una víbora
        // justo en la frontera (+15°) salía a 0,36 y desaparecía.
        return finalize(type, 0.5f + 0.25f * decisionMargin + 0.25f * elevationMargin)
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
