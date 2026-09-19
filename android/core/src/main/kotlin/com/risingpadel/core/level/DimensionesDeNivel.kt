package com.risingpadel.core.level

import com.risingpadel.core.model.HeartRateZones
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.ShotType
import kotlinx.serialization.Serializable
import kotlin.math.roundToInt

/**
 * Las dimensiones del nivel que **se pueden sostener con lo que miden los sensores**.
 *
 * El enum existe para que la UI pinte solo los ejes que tienen dato: una rueda de seis
 * radios con dos huecos es honesta; una de ocho con dos radios inventados, no.
 */
@Serializable
enum class DimensionDeNivel(val etiqueta: String) {
    ATAQUE("Ataque"),
    DEFENSA("Defensa"),
    JUEGO_DE_RED("Juego de red"),
    JUEGO_DE_FONDO("Juego de fondo"),
    CONSISTENCIA("Consistencia"),
    RENDIMIENTO_FISICO("Rendimiento físico"),
}

/**
 * El nivel de una sesión abierto por dimensiones, todas en la misma escala 1-7.
 *
 * Un número global dice poco: saber que el juego de red va dos puntos por debajo del de
 * fondo dice qué entrenar. Cada dimensión es `null` cuando la sesión no trae evidencia
 * suficiente, y un `null` se enseña como hueco, nunca como cero.
 *
 * ### Lo que el producto pide y aquí no está, a propósito
 *
 * **Toma de decisiones: no se implementa.** No es una dimensión que falte por hacer, es
 * una dimensión que este hardware **no puede medir**. Decidir bien en pádel es elegir el
 * golpe adecuado para dónde está la bola, dónde están los rivales y dónde está tu
 * compañero; un acelerómetro y un giróscopo en una muñeca no ven ninguna de las tres
 * cosas. Ven que el brazo se movió así de rápido y describió este arco — y con eso se
 * puede saber cómo se ejecutó un golpe, jamás si tocaba jugarlo. Cualquier número que
 * pusiéramos aquí sería una función de la velocidad y el arco con una etiqueta que
 * promete otra cosa, que es la peor clase de mentira: la que parece un dato. Se queda
 * fuera hasta que haya una fuente que vea la pista (vídeo, o bola instrumentada).
 *
 * **Técnica: no se duplica.** Sería [SessionLevel.overall] con otro nombre. El estimador
 * puntúa exactamente dos cosas —velocidad de pala y forma del swing— y las dos son
 * técnica de ejecución; no hay ningún otro ingrediente del que separarla. Enseñar
 * "técnica 4,2" al lado de "nivel 4,2" no añade información, añade la sospecha de que
 * son medidas distintas. La técnica **es** el nivel global; la UI que quiera un eje de
 * técnica debe pintar `session.level.overall`.
 *
 * **El saque no entra en ninguna dimensión.** No es juego de fondo —no es un peloteo— ni
 * juego de red, y en pádel es un golpe de inicio que se juega a media pista. Meterlo en
 * cualquiera de las dos ensuciaría esa dimensión sin dar ninguna a cambio. Su nota sigue
 * disponible tal cual en [SessionLevel.byShotType].
 */
@Serializable
data class DimensionesDeNivel(
    /**
     * Notas de smash, víbora y bandeja: los golpes con los que se ataca.
     *
     * La bandeja entra aquí aunque sea un golpe de control porque es la respuesta al
     * globo del rival y se juega desde la posición atacante — con ella no se ataca, se
     * **sostiene** el ataque, y sin ella la dimensión se quedaría en los remates sueltos
     * de una sesión. Su banda ya premia el control y no la fuerza (ver [LevelConfig]),
     * así que incluirla no infla la nota.
     */
    val ataque: Float? = null,

    /**
     * Notas de los globos. El globo es **el** golpe defensivo del pádel: es con lo que se
     * sale de una bola apurada y se recupera la red.
     *
     * Mide la ejecución del globo, no la defensa como concepto: la lectura de la pared,
     * la colocación y el aguante no los ve el reloj. Y dentro del propio globo, lo que lo
     * hace bueno —altura y profundidad— tampoco se mide; lo que se mide es el recorrido
     * limpio a poca velocidad, que es el rasgo del globo bien pegado que sí llega al
     * giróscopo.
     */
    val defensa: Float? = null,

    /**
     * Notas de las dos voleas.
     *
     * Solo las voleas: bandeja, víbora y smash también se juegan en la red, pero cuentan
     * en [ataque] y **una sola vez**. Si un golpe alimentara dos dimensiones, las dos
     * serían casi el mismo número con dos nombres y la rueda mentiría sobre lo
     * independientes que son sus ejes.
     */
    val juegoDeRed: Float? = null,

    /** Notas de derecha y revés: el peloteo desde el fondo de la pista. */
    val juegoDeFondo: Float? = null,

    /**
     * La regularidad que ya calcula el estimador ([SessionLevel.consistency]), reescalada
     * de 0-1 a 1-7.
     *
     * No es una medida nueva y no se recalcula aquí: sería el mismo número dos veces con
     * riesgo de que se separaran al tocar uno. Solo se reescala, y se reescala porque las
     * seis dimensiones se pintan en el mismo eje — un radar con cinco radios de 1 a 7 y
     * uno de 0 a 1 se lee mal. Quien quiera el valor crudo lo tiene en
     * [SessionLevel.consistency].
     */
    val consistencia: Float? = null,

    /**
     * Cuánto esfuerzo sostuvo el jugador, a partir del reparto por zonas de pulso.
     *
     * Null sin permiso de salud: sin pulso no hay absolutamente nada que decir aquí.
     *
     * Ojo con el nombre, que es el del documento de producto y promete más de lo que da:
     * **no mide la forma física del jugador**, mide la intensidad a la que jugó esta
     * sesión. Para hablar de forma física haría falta comparar el mismo esfuerzo con su
     * propio pulso a lo largo de meses, que es otra función y otra pantalla.
     */
    val rendimientoFisico: Float? = null,
) {

    fun valor(dimension: DimensionDeNivel): Float? = when (dimension) {
        DimensionDeNivel.ATAQUE -> ataque
        DimensionDeNivel.DEFENSA -> defensa
        DimensionDeNivel.JUEGO_DE_RED -> juegoDeRed
        DimensionDeNivel.JUEGO_DE_FONDO -> juegoDeFondo
        DimensionDeNivel.CONSISTENCIA -> consistencia
        DimensionDeNivel.RENDIMIENTO_FISICO -> rendimientoFisico
    }

    /** Solo las dimensiones con dato, en orden de enum. Es lo que debe pintar la UI. */
    val medidas: Map<DimensionDeNivel, Float>
        get() = DimensionDeNivel.entries
            .mapNotNull { dimension -> valor(dimension)?.let { dimension to it } }
            .toMap()

    /** Si no hay ni una dimensión, no hay rueda que pintar: mejor no enseñar el bloque. */
    val hayAlgoQueEnsenar: Boolean get() = medidas.isNotEmpty()

    companion object {
        /** Los golpes con los que se ataca. Ver [DimensionesDeNivel.ataque]. */
        val GOLPES_DE_ATAQUE = listOf(ShotType.SMASH, ShotType.VIBORA, ShotType.BANDEJA)

        /** El globo, con sus dos lados. Ver [DimensionesDeNivel.defensa]. */
        val GOLPES_DE_DEFENSA = listOf(ShotType.FOREHAND_LOB, ShotType.BACKHAND_LOB)

        val GOLPES_DE_RED = listOf(ShotType.FOREHAND_VOLLEY, ShotType.BACKHAND_VOLLEY)

        val GOLPES_DE_FONDO = listOf(ShotType.FOREHAND, ShotType.BACKHAND)

        /**
         * Por debajo de esto una sesión no dice nada del esfuerzo sostenido.
         *
         * Un partido de pádel dura entre una hora y hora y media; veinte minutos es el
         * calentamiento. Medir "cuánto aguantó" en un rato que no exige aguantar nada
         * daría notas altísimas a quien solo peloteó fuerte cinco minutos.
         */
        const val MIN_SEGUNDOS_PARA_FISICO = 20 * 60

        /**
         * Intensidad representativa de cada zona, como fracción de la FC máxima.
         *
         * Son los puntos medios de las bandas que define [HeartRateZones.zoneFor]
         * (z2 = 60-70 %, z3 = 70-80 %, z4 = 80-90 %). Las dos zonas abiertas por arriba y
         * por abajo llevan un representante prudente: a z1 se le da 0,55 y no 0,30 porque
         * en pista, entre punto y punto, el pulso baja poco; y a z5 se le da 0,93 y no
         * 1,00 porque estar en z5 es pasar del 90 %, no estar clavado en el máximo.
         */
        val INTENSIDAD_DE_ZONA: Map<String, Float> = mapOf(
            "z1" to 0.55f,
            "z2" to 0.65f,
            "z3" to 0.75f,
            "z4" to 0.85f,
            "z5" to 0.93f,
        )

        /**
         * Los dos extremos de la escala física, en fracción de FC máxima.
         *
         * Una sesión entera por debajo del 55 % es un paseo (nivel 1); sostener el 90 %
         * de la FC máxima durante todo un partido es de jugador muy en forma jugando muy
         * en serio (nivel 7). Igual que las bandas de golpeo, **son estimaciones
         * razonadas y no medidas contra jugadores de nivel conocido**: se calibran con el
         * mismo procedimiento descrito en `docs/level.md`.
         */
        const val FCMAX_NIVEL_1 = 0.55f
        const val FCMAX_NIVEL_7 = 0.90f

        /**
         * La fracción de la sesión que tiene que venir con pulso para fiarse del reparto
         * por zonas.
         *
         * Si el reloj solo midió pulso en diez minutos de una hora, ese reparto describe
         * diez minutos, no la sesión, y esos diez minutos suelen ser justo los del
         * principio — los más suaves. Con menos cobertura que esto no se reporta.
         */
        const val MIN_COBERTURA_DE_PULSO = 0.5f

        /**
         * Las dimensiones de [sesion], cada una null si no hay con qué sostenerla.
         *
         * Se apoya en [LevelEstimator] y no reimplementa ninguna nota: si mañana cambia
         * la forma de puntuar un golpeo, estas dimensiones cambian con ella.
         */
        fun de(
            sesion: PadelSession,
            config: LevelConfig = LevelConfig.current,
        ): DimensionesDeNivel {
            val estimador = LevelEstimator(config)

            val notasPorTipo = LinkedHashMap<ShotType, MutableList<Float>>()
            for (golpe in sesion.shots) {
                // Los golpeos sin clasificar o mal clasificados no cuentan, ni siquiera
                // para llegar al mínimo: son los mismos que el estimador descarta.
                val nota = estimador.grade(golpe) ?: continue
                notasPorTipo.getOrPut(golpe.type) { mutableListOf() }.add(nota)
            }

            // Mismo listón que para entrar en el repertorio. Aquí se aplica al grupo
            // entero y no a cada tipo a propósito: la dimensión habla del ataque, no del
            // smash, y pedir cinco de cada uno dejaría sin ataque a una sesión con tres
            // remates y cuatro bandejas, que sí tiene ataque de sobra que contar.
            val minimoGolpeos = config.minShotsPerTypeForRepertoire

            return DimensionesDeNivel(
                ataque = notaDeGrupo(notasPorTipo, GOLPES_DE_ATAQUE, minimoGolpeos),
                defensa = notaDeGrupo(notasPorTipo, GOLPES_DE_DEFENSA, minimoGolpeos),
                juegoDeRed = notaDeGrupo(notasPorTipo, GOLPES_DE_RED, minimoGolpeos),
                juegoDeFondo = notaDeGrupo(notasPorTipo, GOLPES_DE_FONDO, minimoGolpeos),
                consistencia = regularidadReescalada(notasPorTipo, sesion, estimador, minimoGolpeos),
                rendimientoFisico = intensidadSostenida(sesion),
            )
        }

        /**
         * Nota media de un grupo de golpes, o null si el grupo no llega al mínimo.
         *
         * Promedia **por tipo y no por golpeo**, igual que el estimador y que
         * `GolpeVisible.agruparNotas`: si no, cuarenta bandejas dejarían mudos a cinco
         * remates y "ataque" sería "bandeja" con otro nombre.
         */
        private fun notaDeGrupo(
            notasPorTipo: Map<ShotType, List<Float>>,
            tipos: List<ShotType>,
            minimoGolpeos: Int,
        ): Float? {
            val presentes = tipos.mapNotNull { notasPorTipo[it] }
            if (presentes.sumOf { it.size } < minimoGolpeos) return null
            val medias = presentes.map { redondear1(it.average().toFloat()) }
            return redondear1(medias.average().toFloat())
        }

        /**
         * La regularidad del estimador, reescalada, o null si no la sostiene nada.
         *
         * Solo la sostienen los tipos con dos golpeos o más: con un golpeo suelto no hay
         * nada que comparar y el estimador devuelve un 0,5 de relleno que ni premia ni
         * castiga. Ese 0,5 es correcto dentro del cálculo global —donde se mezcla con la
         * media y el repertorio— pero enseñado como "tu consistencia es un 4" sería un
         * número inventado con cara de medida.
         */
        private fun regularidadReescalada(
            notasPorTipo: Map<ShotType, List<Float>>,
            sesion: PadelSession,
            estimador: LevelEstimator,
            minimoGolpeos: Int,
        ): Float? {
            val golpeosQueLaSostienen = notasPorTipo.values.filter { it.size >= 2 }.sumOf { it.size }
            if (golpeosQueLaSostienen < minimoGolpeos) return null
            return aEscalaDeNivel(estimador.estimate(sesion.shots).consistency)
        }

        /**
         * Intensidad sostenida a partir del reparto por zonas de pulso.
         *
         * Se usan las zonas y no el pulso medio porque las zonas ya vienen normalizadas
         * por la FC máxima del jugador (ver `SessionRecorder`), y comparar pulsos en bruto
         * entre dos personas no significa nada: 150 pulsaciones son un trote para uno y el
         * límite para otro.
         *
         * La duración entra **solo como puerta** y no como multiplicador: un partido de
         * dos horas no es más nivel físico que uno de una hora a la misma intensidad, es
         * más volumen, que es otra cosa y merece su propia métrica.
         */
        private fun intensidadSostenida(sesion: PadelSession): Float? {
            val segundosPorZona = sesion.health.zones.secondsPerZone
            val segundosConPulso = HeartRateZones.ZONE_KEYS.sumOf { segundosPorZona[it] ?: 0 }
            if (segundosConPulso <= 0) return null
            if (sesion.durationSeconds < MIN_SEGUNDOS_PARA_FISICO) return null
            if (segundosConPulso < sesion.durationSeconds * MIN_COBERTURA_DE_PULSO) return null

            var acumulado = 0.0
            for (zona in HeartRateZones.ZONE_KEYS) {
                val segundos = segundosPorZona[zona] ?: 0
                acumulado += segundos * (INTENSIDAD_DE_ZONA[zona] ?: 0f).toDouble()
            }
            val fraccionMedia = (acumulado / segundosConPulso).toFloat()

            val normalizado =
                ((fraccionMedia - FCMAX_NIVEL_1) / (FCMAX_NIVEL_7 - FCMAX_NIVEL_1)).coerceIn(0f, 1f)
            return aEscalaDeNivel(normalizado)
        }

        /** Un 0..1 pasado a la escala 1..7, igual que hace el estimador con sus notas. */
        private fun aEscalaDeNivel(normalizado: Float): Float = redondear1(
            LevelConfig.MIN_LEVEL + normalizado * (LevelConfig.MAX_LEVEL - LevelConfig.MIN_LEVEL)
        )

        private fun redondear1(valor: Float): Float = (valor * 10).roundToInt() / 10f
    }
}
