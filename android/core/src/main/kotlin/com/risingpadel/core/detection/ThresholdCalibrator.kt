package com.risingpadel.core.detection

import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlinx.serialization.Serializable
import kotlin.math.abs

/**
 * Los umbrales personales de un jugador, sacados de sus propias tandas etiquetadas.
 *
 * Nace de un problema real: los umbrales de fábrica salen de una técnica media, y en
 * pista (ago 2026) las víboras de un jugador promediaban |4-5| de rotación axial cuando
 * el umbral estaba en 9 — ninguna llegaba. Cada jugador tiene su muñeca: lo que hay que
 * medir no es "cuánto efecto lleva una víbora" sino "cuánto efecto llevan LAS TUYAS".
 *
 * Los campos nulos se quedan con el valor de fábrica: se calibra solo lo que las tandas
 * pueden sostener.
 */
@Serializable
data class DetectorCalibration(
    val prepOverheadElevationDeg: Float? = null,
    val smashPeakGyroRadS: Float? = null,
    val viboraAxialRadS: Float? = null,
    val volleyAxialMaxRadS: Float? = null,
    /**
     * El eje del antebrazo lee la elevación al revés en este reloj.
     *
     * Se decide **con tandas etiquetadas** y no en vivo. Antes lo decidía una media
     * larga de la sesión: si el brazo salía "en alto" un rato, se daba por invertido.
     * Esa regla no puede distinguir "el sensor está al revés" de "este jugador acaba de
     * dar treinta bandejas", y una tanda de golpes altos es exactamente el caso que la
     * dispara en falso — justo cuando la elevación más falta hace. En pista (ago 2026)
     * el resultado fue que las bandejas medían MENOS elevación que las voleas.
     *
     * Aquí no hay ambigüedad: si en las tandas los golpes altos se preparan más abajo
     * que los bajos, el eje está invertido. Lo dice la etiqueta, no una suposición.
     */
    val ejeDeElevacionInvertido: Boolean? = null,
    /** Cuántos golpeos etiquetados la sostienen. */
    val muestras: Int = 0,
    val creadoEpochMs: Long = 0,
) {
    val vacia: Boolean
        get() = prepOverheadElevationDeg == null && smashPeakGyroRadS == null &&
            viboraAxialRadS == null && volleyAxialMaxRadS == null &&
            ejeDeElevacionInvertido == null
}

/** El resultado de calibrar: los umbrales y cuánto mejoran sobre las propias tandas. */
data class ResultadoCalibracion(
    val calibracion: DetectorCalibration,
    /** Acierto de la heurística de fábrica sobre las tandas, 0..1. */
    val aciertoAntes: Float,
    /** Acierto con los umbrales calibrados, 0..1. */
    val aciertoDespues: Float,
    /** Cuántos golpeos etiquetados de cada tipo entraron. */
    val porTipo: Map<ShotType, Int>,
)

/**
 * Deriva umbrales personales a partir de golpeos etiquetados por el jugador (las tandas
 * del modo de datos, donde la etiqueta la eligió él antes de dar el golpe).
 *
 * El método es deliberadamente simple y explicable: para separar dos familias por un
 * rasgo se toma el **punto medio entre sus medianas**. Sin medias (un golpe raro no
 * puede mover el umbral), sin ajuste fino, sin nada que no se pueda contar en una
 * frase. Y con tres cinturones de seguridad:
 *
 * 1. Mínimo de golpeos por familia: con dos ejemplos no se calibra nada.
 * 2. Las medianas tienen que estar separadas de verdad; si se solapan, ese rasgo no
 *    distingue a este jugador y se queda el valor de fábrica.
 * 3. El umbral se acota a un rango sensato: una tanda mal etiquetada no puede dejar el
 *    detector inservible.
 */
object ThresholdCalibrator {

    /** Con menos de esto por familia, el rasgo no se toca. */
    const val MIN_POR_FAMILIA = 5

    /**
     * Grados que tienen que separar a los altos de los bajos para creerse el signo.
     * Por debajo, la diferencia puede ser ruido y girar el eje sería peor que no hacer
     * nada: se rompería un detector que a lo mejor estaba bien.
     */
    const val MIN_SEPARACION_EJE_DEG = 15f

    private val ALTOS = setOf(ShotType.BANDEJA, ShotType.VIBORA, ShotType.SMASH)
    private val VOLEAS = setOf(ShotType.FOREHAND_VOLLEY, ShotType.BACKHAND_VOLLEY)
    private val FONDO = setOf(ShotType.FOREHAND, ShotType.BACKHAND)

    fun calibrar(
        etiquetados: List<Pair<ShotType, ShotFeatures>>,
        base: DetectorConfig = DetectorConfig.DEFAULT,
        ahoraEpochMs: Long = 0,
    ): ResultadoCalibracion {
        val porTipo = etiquetados.groupingBy { it.first }.eachCount()

        // ── Golpe alto: la elevación de preparación de los altos contra la del resto ──
        val prepAltos = etiquetados.filter { it.first in ALTOS }
            .mapNotNull { it.second.prepElevationDeg }
        val prepBajos = etiquetados.filter { it.first in VOLEAS || it.first in FONDO }
            .mapNotNull { it.second.prepElevationDeg }
        // ¿Está el eje al revés? Si los golpes altos se **preparan más abajo** que los
        // bajos, la elevación llega con el signo cambiado. Lo dice la etiqueta del
        // jugador, que es la única fuente que no se puede confundir con "hoy tocaba
        // tanda de bandejas".
        val invertido = ejeInvertido(altos = prepAltos, bajos = prepBajos)
        // Con el eje corregido, la frontera se calcula sobre los valores ya girados: si
        // no, se derivaría un umbral para un signo y se aplicaría al contrario.
        val giro = if (invertido == true) -1f else 1f
        val prep = frontera(
            prepBajos.map { it * giro }, prepAltos.map { it * giro }, rango = 20f..70f
        )

        // ── Smash contra el resto de altos: la violencia del pico de giro ──
        val picoSmash = etiquetados.filter { it.first == ShotType.SMASH }
            .map { it.second.peakGyroRadS }
        val picoOtrosAltos = etiquetados
            .filter { it.first == ShotType.BANDEJA || it.first == ShotType.VIBORA }
            .map { it.second.peakGyroRadS }
        val smash = frontera(picoOtrosAltos, picoSmash, rango = 10f..30f)

        // ── Víbora contra bandeja: el efecto lateral ──
        val axialVibora = etiquetados.filter { it.first == ShotType.VIBORA }
            .map { abs(it.second.axialRotationRadS) }
        val axialBandeja = etiquetados.filter { it.first == ShotType.BANDEJA }
            .map { abs(it.second.axialRotationRadS) }
        val vibora = frontera(axialBandeja, axialVibora, rango = 2f..12f)

        // ── Volea contra golpe de fondo: la pala quieta ──
        val axialVoleas = etiquetados.filter { it.first in VOLEAS }
            .map { abs(it.second.axialRotationRadS) }
        val axialFondo = etiquetados.filter { it.first in FONDO }
            .map { abs(it.second.axialRotationRadS) }
        val volea = frontera(axialVoleas, axialFondo, rango = 1.5f..8f)

        val calibracion = DetectorCalibration(
            prepOverheadElevationDeg = prep,
            smashPeakGyroRadS = smash,
            viboraAxialRadS = vibora,
            volleyAxialMaxRadS = volea,
            ejeDeElevacionInvertido = invertido,
            muestras = etiquetados.size,
            creadoEpochMs = ahoraEpochMs,
        )

        return ResultadoCalibracion(
            calibracion = calibracion,
            aciertoAntes = acierto(etiquetados, base),
            aciertoDespues = acierto(etiquetados, base.aplicando(calibracion)),
            porTipo = porTipo,
        )
    }

    /**
     * ¿Lee este reloj la elevación al revés?
     *
     * Un golpe alto se arma con el brazo por encima del hombro y uno de fondo o una
     * volea, no. Si las medianas dicen lo contrario —y por un margen que no se explica
     * por ruido— el eje está invertido. Null si no hay material suficiente o si la
     * separación es pequeña: ante la duda, no se toca nada.
     */
    private fun ejeInvertido(altos: List<Float>, bajos: List<Float>): Boolean? {
        if (altos.size < MIN_POR_FAMILIA || bajos.size < MIN_POR_FAMILIA) return null
        val medianaAltos = mediana(altos)
        val medianaBajos = mediana(bajos)
        val separacion = medianaAltos - medianaBajos
        if (abs(separacion) < MIN_SEPARACION_EJE_DEG) return null
        return separacion < 0
    }

    /**
     * El punto medio entre las medianas de dos familias, o null si no hay material o
     * las dos familias se solapan en ese rasgo.
     *
     * @param bajos la familia que debe quedar por debajo del umbral.
     * @param altos la que debe quedar por encima.
     */
    private fun frontera(
        bajos: List<Float>,
        altos: List<Float>,
        rango: ClosedFloatingPointRange<Float>,
    ): Float? {
        if (bajos.size < MIN_POR_FAMILIA || altos.size < MIN_POR_FAMILIA) return null
        val medianaBajos = mediana(bajos)
        val medianaAltos = mediana(altos)
        // Solapadas o al revés de lo esperado: este rasgo no separa a este jugador.
        if (medianaAltos <= medianaBajos) return null
        val punto = (medianaBajos + medianaAltos) / 2
        return punto.coerceIn(rango.start, rango.endInclusive)
    }

    private fun mediana(valores: List<Float>): Float {
        val ordenados = valores.sorted()
        return ordenados[ordenados.size / 2]
    }

    /** Qué fracción de las tandas clasifica bien una configuración dada. */
    private fun acierto(
        etiquetados: List<Pair<ShotType, ShotFeatures>>,
        config: DetectorConfig,
    ): Float {
        if (etiquetados.isEmpty()) return 0f
        val classifier = ShotClassifier(config)
        val buenos = etiquetados.count { (etiqueta, rasgos) ->
            classifier.classify(rasgos).type == etiqueta
        }
        return buenos.toFloat() / etiquetados.size
    }
}
