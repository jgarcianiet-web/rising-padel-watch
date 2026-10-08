package com.risingpadel.core.video

import com.risingpadel.core.model.ShotType
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Casar los golpes que se ven en un vídeo con los que midió el reloj.
 *
 * ## Para qué sirve, y por qué es el cuello de botella de todo lo demás
 *
 * El Video Lab marca golpes a mano, y marcar a mano es carísimo: un partido son
 * trescientos golpes y nadie etiqueta trescientas cosas dos sábados seguidos. Pero si el
 * jugador llevaba el reloj mientras se grababa el vídeo, **el reloj ya sabe qué golpe fue
 * cada uno y en qué milisegundo**. Cruzar las dos listas convierte una tarde de
 * etiquetado manual en un botón.
 *
 * Eso abre las dos cosas que el laboratorio existe para hacer:
 *
 * 1. **Medir el detector de verdad.** Los pares dicen en qué acertó; las marcas sin par
 *    dicen qué golpes se le escaparon al reloj, y los golpes del reloj sin par, qué se
 *    inventó. Eso es precisión medida, no la etiqueta que el jugador le puso a la tanda.
 * 2. **Entrenar la detección por visión.** Cada par es un ejemplo etiquetado: esta
 *    postura, este golpe. Sin este emparejador no hay corpus, y sin corpus no hay modelo.
 *
 * ## El problema real: los dos relojes no marcan la misma hora
 *
 * El vídeo trae la hora del iPhone que grabó, con resolución de segundo. Los golpes traen
 * la del Apple Watch. Entre los dos hay un desfase de uno o dos segundos con toda
 * naturalidad — y dos golpes seguidos de una tanda van a segundo y medio, así que un
 * desfase de dos segundos no desordena un poco: empareja cada golpe con el siguiente y da
 * un informe limpio y completamente falso. **Un emparejamiento mal alineado es peor que
 * ninguno**, porque parece correcto.
 *
 * Tres formas de alinear, de la más fiable a la más cómoda:
 *
 * - **Dos claquetas** ([desfaseConDosAnclas]): el usuario señala el mismo golpe al
 *   principio y otro al final, en el vídeo y en el reloj. Da desfase **y escala**, que es
 *   lo único que corrige la deriva — los dos relojes no corren exactamente igual y en
 *   veinte minutos la diferencia se nota.
 * - **Una claqueta** ([desfaseConUnaAncla]): un solo par. Da desfase y nada más; la
 *   deriva se queda dentro.
 * - **Automático** ([estimarDesfaseMs]): se prueban desfases y gana el que empareja más
 *   golpes. Cómodo y casi siempre acertado, pero puede fallar justo donde más duele —en
 *   una tanda de golpes regulares, correr el desfase un golpe entero empareja igual de
 *   bien. Por eso devuelve también cuántos emparejó, para poder desconfiar.
 */
object SincronizacionDeVideo {

    /**
     * Cuánto se admite entre un golpe visto y el mismo golpe medido, una vez alineados.
     *
     * 300 ms y no más: el detector del reloj tiene 320 ms de tiempo muerto tras cada
     * impacto, así que con una ventana más ancha un golpe del vídeo podría caer a tiro de
     * dos golpes del reloj y la elección dejaría de estar determinada por los datos.
     */
    const val VENTANA_MS = 300L

    /** Hasta dónde se busca el desfase automático. Más de seis segundos ya no es desfase
     * de relojes, es que el vídeo y la sesión no son del mismo partido. */
    const val RANGO_AUTOMATICO_MS = 6_000L

    /** Paso de la búsqueda. 50 ms es bastante más fino que la ventana. */
    const val PASO_AUTOMATICO_MS = 50L

    /** Un golpe situado en tiempo de reloj de pared, venga del vídeo o de la muñeca. */
    data class GolpeEnTiempo(
        val epochMs: Long,
        /** Nulo en una marca de vídeo que todavía no tiene tipo puesto. */
        val tipo: ShotType? = null,
    )

    /** Un golpe del vídeo casado con uno del reloj, por sus posiciones en cada lista. */
    data class Par(
        val indiceVideo: Int,
        val indiceReloj: Int,
        /** Lo que quedó sin cuadrar entre los dos, ya alineados. Con signo. */
        val restoMs: Long,
    )

    /**
     * El resultado de cruzar las dos listas.
     *
     * Las tres listas juntas cuentan la historia entera, y por eso no se devuelven solo
     * los pares: [soloEnVideo] son golpes que se vieron y el reloj no midió, y
     * [soloEnReloj] son golpes que el reloj midió y no se ven. Quedarse con los pares
     * sería quedarse con la parte en la que el detector acierta.
     */
    data class Cruce(
        val pares: List<Par>,
        val soloEnVideo: List<Int>,
        val soloEnReloj: List<Int>,
        val desfaseMs: Long,
        val escala: Double,
    ) {
        /** Qué fracción de lo que se ve en el vídeo encontró su golpe en el reloj. */
        val cobertura: Double
            get() {
                val total = pares.size + soloEnVideo.size
                return if (total == 0) 0.0 else pares.size.toDouble() / total
            }

        /**
         * El resto típico de los pares, en valor absoluto.
         *
         * **Es la cifra que dice si el alineamiento es bueno**, y hace falta justo porque
         * el número de pares no basta: con restos de decenas de milisegundos cuadra de
         * verdad; con restos pegados a la ventana está corrido un golpe entero y el
         * informe, aunque esté lleno de pares, no vale nada.
         */
        val restoMedianoMs: Long?
            get() {
                if (pares.isEmpty()) return null
                val restos = pares.map { abs(it.restoMs) }.sorted()
                return restos[restos.size / 2]
            }

        /**
         * De los pares emparejados, en cuántos coincidió el tipo de golpe.
         *
         * Nulo si ningún par tiene tipo en los dos lados: sin tipos no se puede hablar de
         * acierto, y un 0 % diría que falla todo cuando lo que pasa es que no se sabe.
         */
        fun aciertoDeTipo(video: List<GolpeEnTiempo>, reloj: List<GolpeEnTiempo>): Double? {
            val comparables = pares.filter {
                video[it.indiceVideo].tipo != null && reloj[it.indiceReloj].tipo != null
            }
            if (comparables.isEmpty()) return null
            val iguales = comparables.count {
                video[it.indiceVideo].tipo == reloj[it.indiceReloj].tipo
            }
            return iguales.toDouble() / comparables.size
        }
    }

    /**
     * Desfase a partir de **una** claqueta: el mismo golpe señalado en los dos lados.
     *
     * Positivo significa que el reloj va por delante del vídeo.
     */
    fun desfaseConUnaAncla(marcaEpochMs: Long, golpeEpochMs: Long): Long =
        golpeEpochMs - marcaEpochMs

    /**
     * Desfase **y escala** a partir de dos claquetas, una al principio y otra al final.
     *
     * La escala corrige la deriva: si entre las dos claquetas el vídeo mide 600 s y el
     * reloj 600,4 s, los relojes no corren igual y los golpes del final se desplazan casi
     * medio segundo — más de la ventana de emparejado.
     *
     * Devuelve null si las dos claquetas son la misma o están del revés: con dos puntos
     * pegados la escala sale de dividir por casi cero y amplifica cualquier error de
     * señalar el fotograma. **Se pide medio minuto de separación**, que es poco para un
     * vídeo de entreno y suficiente para que la cuenta signifique algo.
     */
    fun desfaseConDosAnclas(
        marca1EpochMs: Long,
        golpe1EpochMs: Long,
        marca2EpochMs: Long,
        golpe2EpochMs: Long,
        separacionMinimaMs: Long = 30_000,
    ): Pair<Long, Double>? {
        val vanoVideo = marca2EpochMs - marca1EpochMs
        val vanoReloj = golpe2EpochMs - golpe1EpochMs
        if (vanoVideo < separacionMinimaMs || vanoReloj < separacionMinimaMs) return null

        val escala = vanoReloj.toDouble() / vanoVideo.toDouble()
        // Con la escala puesta, el desfase es lo que le falta a la primera marca estirada
        // para caer sobre su golpe.
        val desfase = golpe1EpochMs - (marca1EpochMs * escala).roundToLong()
        return desfase to escala
    }

    /**
     * Prueba desfases y devuelve el que empareja más golpes, con cuántos emparejó.
     *
     * El recuento se devuelve a propósito: es lo que permite desconfiar. Si de cuarenta
     * marcas solo cuadran seis, el desfase "mejor" no significa nada y lo que hay que
     * hacer es señalar una claqueta, no aceptar el número.
     *
     * Para puntuar cada desfase NO se usa el emparejador bueno: basta contar cuántas
     * marcas tienen algún golpe a tiro, que es una búsqueda binaria en vez de una tabla
     * entera, y por eso se pueden probar doscientos cuarenta desfases sin que se note.
     * El emparejamiento uno-a-uno de verdad se hace una sola vez, con el ganador.
     */
    fun estimarDesfaseMs(
        video: List<GolpeEnTiempo>,
        reloj: List<GolpeEnTiempo>,
        rangoMs: Long = RANGO_AUTOMATICO_MS,
        pasoMs: Long = PASO_AUTOMATICO_MS,
        ventanaMs: Long = VENTANA_MS,
    ): Pair<Long, Int> {
        if (video.isEmpty() || reloj.isEmpty()) return 0L to 0
        val tiemposReloj = reloj.map { it.epochMs }.sorted()

        var mejorDesfase = 0L
        var mejorCuenta = -1
        var mejorError = Long.MAX_VALUE
        var desfase = -rangoMs
        while (desfase <= rangoMs) {
            var cuenta = 0
            var error = 0L
            for (marca in video) {
                val buscado = marca.epochMs + desfase
                val cercano = masCercano(tiemposReloj, buscado)
                if (cercano != null && abs(cercano - buscado) <= ventanaMs) {
                    cuenta++
                    error += abs(cercano - buscado)
                }
            }
            // Más pares gana; a igualdad, el que cuadra más fino. Sin el desempate por
            // error, dos desfases vecinos empatan y se queda el primero por casualidad.
            if (cuenta > mejorCuenta || (cuenta == mejorCuenta && error < mejorError)) {
                mejorDesfase = desfase
                mejorCuenta = cuenta
                mejorError = error
            }
            desfase += pasoMs
        }
        return mejorDesfase to mejorCuenta
    }

    /** El valor de la lista ordenada más cercano a [objetivo], por búsqueda binaria. */
    private fun masCercano(ordenados: List<Long>, objetivo: Long): Long? {
        if (ordenados.isEmpty()) return null
        var bajo = 0
        var alto = ordenados.size - 1
        while (bajo < alto) {
            val medio = (bajo + alto) / 2
            if (ordenados[medio] < objetivo) bajo = medio + 1 else alto = medio
        }
        val candidato = ordenados[bajo]
        val anterior = if (bajo > 0) ordenados[bajo - 1] else null
        return if (anterior != null && abs(anterior - objetivo) < abs(candidato - objetivo)) {
            anterior
        } else {
            candidato
        }
    }

    /**
     * Cruza las dos listas con un desfase y una escala dados.
     *
     * **El emparejamiento respeta el orden y es uno a uno**, y las dos condiciones son
     * necesarias. Uno a uno porque un golpe del reloj no puede explicar dos del vídeo. En
     * orden porque las dos listas son cronológicas: si la marca 5 casa con el golpe 9, la
     * marca 6 no puede casar con el 8 — eso sería el tiempo andando hacia atrás, y es
     * exactamente el error que comete un emparejador voraz cuando dos golpes van pegados.
     *
     * Con esas dos condiciones el óptimo sale de una tabla (programación dinámica) y no
     * de ir eligiendo lo que mejor pinta en cada paso: se maximiza el número de pares y,
     * a igualdad, se minimiza lo que queda sin cuadrar.
     */
    fun cruzar(
        video: List<GolpeEnTiempo>,
        reloj: List<GolpeEnTiempo>,
        desfaseMs: Long,
        escala: Double = 1.0,
        ventanaMs: Long = VENTANA_MS,
    ): Cruce {
        val ordenVideo = video.indices.sortedBy { video[it].epochMs }
        val ordenReloj = reloj.indices.sortedBy { reloj[it].epochMs }
        val n = ordenVideo.size
        val m = ordenReloj.size

        // Instantes del vídeo llevados al tiempo del reloj.
        val alineados = ordenVideo.map { (video[it].epochMs * escala).roundToLong() + desfaseMs }
        val tiemposReloj = ordenReloj.map { reloj[it].epochMs }

        // pares[i][j] = cuántos pares se pueden formar con las i primeras marcas y los j
        // primeros golpes; error[i][j] = lo que cuesta ese mejor emparejamiento.
        val pares = Array(n + 1) { IntArray(m + 1) }
        val error = Array(n + 1) { LongArray(m + 1) }
        for (i in 1..n) {
            for (j in 1..m) {
                // Dejar fuera la marca i, o dejar fuera el golpe j.
                var mejorPares = pares[i - 1][j]
                var mejorError = error[i - 1][j]
                if (pares[i][j - 1] > mejorPares ||
                    (pares[i][j - 1] == mejorPares && error[i][j - 1] < mejorError)
                ) {
                    mejorPares = pares[i][j - 1]
                    mejorError = error[i][j - 1]
                }
                // O casarlos, si se tocan dentro de la ventana.
                val resto = abs(alineados[i - 1] - tiemposReloj[j - 1])
                if (resto <= ventanaMs) {
                    val conPar = pares[i - 1][j - 1] + 1
                    val errorConPar = error[i - 1][j - 1] + resto
                    if (conPar > mejorPares || (conPar == mejorPares && errorConPar < mejorError)) {
                        mejorPares = conPar
                        mejorError = errorConPar
                    }
                }
                pares[i][j] = mejorPares
                error[i][j] = mejorError
            }
        }

        // Se recorre la tabla hacia atrás para saber QUÉ se emparejó, no solo cuánto.
        val resultado = mutableListOf<Par>()
        var i = n
        var j = m
        while (i > 0 && j > 0) {
            val resto = abs(alineados[i - 1] - tiemposReloj[j - 1])
            val conPar = if (resto <= ventanaMs) pares[i - 1][j - 1] + 1 else -1
            val errorConPar =
                if (resto <= ventanaMs) error[i - 1][j - 1] + resto else Long.MAX_VALUE
            when {
                conPar == pares[i][j] && errorConPar == error[i][j] -> {
                    resultado.add(
                        Par(
                            indiceVideo = ordenVideo[i - 1],
                            indiceReloj = ordenReloj[j - 1],
                            restoMs = alineados[i - 1] - tiemposReloj[j - 1],
                        )
                    )
                    i--
                    j--
                }
                pares[i - 1][j] == pares[i][j] && error[i - 1][j] == error[i][j] -> i--
                else -> j--
            }
        }

        val emparejadosVideo = resultado.map { it.indiceVideo }.toSet()
        val emparejadosReloj = resultado.map { it.indiceReloj }.toSet()
        return Cruce(
            pares = resultado.sortedBy { video[it.indiceVideo].epochMs },
            soloEnVideo = ordenVideo.filter { it !in emparejadosVideo },
            soloEnReloj = ordenReloj.filter { it !in emparejadosReloj },
            desfaseMs = desfaseMs,
            escala = escala,
        )
    }

    /**
     * Cruza estimando el desfase sola.
     *
     * Atajo para el caso cómodo. Devuelve además cuántos emparejó la estimación, que es
     * lo que hay que mirar antes de creerse el resultado.
     */
    fun cruzarAutomatico(
        video: List<GolpeEnTiempo>,
        reloj: List<GolpeEnTiempo>,
        ventanaMs: Long = VENTANA_MS,
    ): Cruce {
        val (desfase, _) = estimarDesfaseMs(video, reloj, ventanaMs = ventanaMs)
        return cruzar(video, reloj, desfaseMs = desfase, ventanaMs = ventanaMs)
    }
}
