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
    /**
     * La puerta de golpe alto de ESTE jugador. La de fábrica (+14) sale de una tanda
     * donde altos y bajos no se rozaban; en la tanda de 40 en bloques (ago 2026) el
     * mismo jugador impactó sus golpes altos entre +4 y +31 — cuatro de ellos por
     * debajo de la puerta de fábrica, perdidos como voleas. Se fija en el punto medio
     * del HUECO entre el bajo más alto y el alto más bajo (no entre medianas: es una
     * puerta, y una puerta que deja un golpe al otro lado ya está mal puesta), y solo
     * si el hueco existe.
     */
    val overheadElevationDeg: Float? = null,
    val prepOverheadElevationDeg: Float? = null,
    val smashPeakGyroRadS: Float? = null,
    val viboraElevationDeg: Float? = null,
    /**
     * Frontera bandeja/víbora por pronación (con signo) en vez de por altura, para los
     * jugadores cuyas tandas demuestran que a ellos las separa el efecto. Ver
     * [DetectorConfig.viboraAxialRadS].
     */
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
        get() = overheadElevationDeg == null && prepOverheadElevationDeg == null &&
            smashPeakGyroRadS == null && viboraElevationDeg == null &&
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

        // ── Víbora contra bandeja: la ALTURA del golpeo ──
        // Las dos se preparan igual; la víbora se golpea más baja. Ojo al orden de los
        // argumentos: aquí la familia "alta" es la BANDEJA, al revés que en los demás
        // rasgos, porque lo que define a la víbora es quedarse por debajo.
        val alturaVibora = etiquetados.filter { it.first == ShotType.VIBORA }
            .map { it.second.peakElevationDeg * giro }
        val alturaBandeja = etiquetados.filter { it.first == ShotType.BANDEJA }
            .map { it.second.peakElevationDeg * giro }
        val vibora = frontera(alturaVibora, alturaBandeja, rango = -10f..45f)

        // ── Volea contra golpe de fondo: la pala quieta ──
        val axialVoleas = etiquetados.filter { it.first in VOLEAS }
            .map { abs(it.second.axialRotationRadS) }
        val axialFondo = etiquetados.filter { it.first in FONDO }
            .map { abs(it.second.axialRotationRadS) }
        val volea = frontera(axialVoleas, axialFondo, rango = 1.5f..8f)

        // ── La puerta de golpe alto: el pico de elevación de los altos contra TODO lo
        // demás, saques incluidos. Los saques no son ni voleas ni fondo, pero viven
        // debajo de la puerta: si se calibrara sin contarlos, una puerta baja los
        // mandaría a la rama alta y los mataría a todos. Y es una PUERTA, no una
        // frontera de medianas: se pone en el punto medio del hueco real, porque un
        // solo golpe al otro lado ya es un golpe mal clasificado.
        val alturaAltos = etiquetados.filter { it.first in ALTOS }
            .map { it.second.peakElevationDeg * giro }
        val alturaBajos = etiquetados.filter { it.first !in ALTOS }
            .map { it.second.peakElevationDeg * giro }
        val puerta = hueco(alturaBajos, alturaAltos, rango = 0f..40f)

        // ── Víbora contra bandeja por pronación, la frontera alternativa ──
        // Con signo: la víbora se corta con pronación de derecha; el valor absoluto
        // mezclaría un corte con su contrario. Solo sobrevivirá (ver la validación de
        // abajo) si en las tandas de ESTE jugador separa mejor que la altura.
        val viboraPorAxial = frontera(
            etiquetados.filter { it.first == ShotType.BANDEJA }
                .map { it.second.axialRotationRadS },
            etiquetados.filter { it.first == ShotType.VIBORA }
                .map { it.second.axialRotationRadS },
            rango = 1f..6f,
        )

        val candidata = DetectorCalibration(
            overheadElevationDeg = puerta,
            prepOverheadElevationDeg = prep,
            smashPeakGyroRadS = smash,
            viboraElevationDeg = vibora,
            viboraAxialRadS = viboraPorAxial,
            volleyAxialMaxRadS = volea,
            ejeDeElevacionInvertido = invertido,
            muestras = etiquetados.size,
            creadoEpochMs = ahoraEpochMs,
        )

        // Cada umbral se queda solo si NO EMPEORA las tandas del jugador. Esto no es
        // adorno: en la tanda de 40 en bloques, la elevación de preparación calibraba a
        // +20° (el punto medio entre familias, acotado al rango) y a +20° se preparan
        // los saques de ese jugador — tres saques muertos por un umbral "bien" derivado.
        // El método sigue siendo explicable: se prueba cada umbral sobre las mismas
        // tandas de las que salió, y el que resta, fuera.
        val calibracion = validada(candidata, etiquetados, base)

        return ResultadoCalibracion(
            calibracion = calibracion,
            aciertoAntes = acierto(etiquetados, base),
            aciertoDespues = acierto(etiquetados, base.aplicando(calibracion)),
            porTipo = porTipo,
        )
    }

    /**
     * Deja en null todo umbral candidato que empeore el acierto sobre las propias
     * tandas. Se evalúan uno a uno, en orden fijo y de forma acumulada: cada umbral se
     * juzga con los ya aceptados puestos. Empate = se queda (personalizado no es peor
     * que de fábrica, y el jugador ve su calibración aplicada).
     */
    private fun validada(
        candidata: DetectorCalibration,
        etiquetados: List<Pair<ShotType, ShotFeatures>>,
        base: DetectorConfig,
    ): DetectorCalibration {
        var aceptada = DetectorCalibration(
            ejeDeElevacionInvertido = candidata.ejeDeElevacionInvertido,
            muestras = candidata.muestras,
            creadoEpochMs = candidata.creadoEpochMs,
        )
        var mejorAcierto = acierto(etiquetados, base.aplicando(aceptada))

        // El eje invertido no se valida por acierto: es una corrección de signo que se
        // decidió por separación de medianas, y sin él puestos, el resto de umbrales de
        // elevación no significan nada.
        val pasos = listOf<Pair<String, (DetectorCalibration) -> DetectorCalibration>>(
            "puerta" to { it.copy(overheadElevationDeg = candidata.overheadElevationDeg) },
            "prep" to { it.copy(prepOverheadElevationDeg = candidata.prepOverheadElevationDeg) },
            "smash" to { it.copy(smashPeakGyroRadS = candidata.smashPeakGyroRadS) },
            "viboraAltura" to { it.copy(viboraElevationDeg = candidata.viboraElevationDeg) },
            "viboraAxial" to { it.copy(viboraAxialRadS = candidata.viboraAxialRadS) },
            "volea" to { it.copy(volleyAxialMaxRadS = candidata.volleyAxialMaxRadS) },
        )
        for ((_, aplicar) in pasos) {
            val prueba = aplicar(aceptada)
            if (prueba == aceptada) continue
            val conEste = acierto(etiquetados, base.aplicando(prueba))
            if (conEste >= mejorAcierto) {
                aceptada = prueba
                mejorAcierto = conEste
            }
        }
        return aceptada
    }

    /**
     * El punto medio del **hueco** entre dos familias: entre el mayor de los bajos y el
     * menor de los altos. Para una puerta —donde un solo golpe al otro lado ya cuenta
     * como error— el hueco es lo que importa, no las medianas. Null si no hay material
     * o si las familias se pisan.
     */
    private fun hueco(
        bajos: List<Float>,
        altos: List<Float>,
        rango: ClosedFloatingPointRange<Float>,
    ): Float? {
        if (bajos.size < MIN_POR_FAMILIA || altos.size < MIN_POR_FAMILIA) return null
        val techoBajos = bajos.max()
        val sueloAltos = altos.min()
        if (sueloAltos <= techoBajos) return null
        val punto = (techoBajos + sueloAltos) / 2
        if (punto < rango.start || punto > rango.endInclusive) return null
        return punto
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
