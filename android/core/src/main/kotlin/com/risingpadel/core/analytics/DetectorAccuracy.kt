package com.risingpadel.core.analytics

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.ShotType
import kotlin.math.abs

/**
 * Lo que sabemos del acierto del reloj en **un** tipo de golpe.
 *
 * Junta las dos únicas fuentes de verdad que existen, y las mantiene separadas porque no
 * valen lo mismo:
 *
 * - **Las tandas etiquetadas** son verdad-terreno perfecta: alguien dijo "esto van a ser
 *   treinta bandejas" *antes* de pegar, así que se sabe golpe a golpe si acertó y con qué
 *   se confundió. Es el dato bueno.
 * - **Las revisiones de partido** son recuentos: el jugador dijo "fueron 12 bandejas, no
 *   14". No dicen *cuál* falló, solo cuántos de más o de menos contó el reloj. Es un dato
 *   más pobre, pero es el único que sale de jugar de verdad.
 *
 * Mezclarlas en un solo porcentaje daría un número más gordo y más falso. Aquí conviven.
 */
data class PrecisionDeGolpe(
    val type: ShotType,
    /** Golpes de este tipo en tandas etiquetadas. */
    val enTandas: Int,
    /** De esos, cuántos clasificó bien. */
    val acertadosEnTandas: Int,
    /** El tipo con el que más se lo confunde. Null si no falla nunca. */
    val seConfundeCon: ShotType?,
    val vecesConfundido: Int,
    /** Golpes de este tipo que contó el reloj en partidos revisados. */
    val contadosEnPartidos: Int,
    /** Los que dijo el jugador que fueron de verdad. */
    val realesEnPartidos: Int,
) {
    /** 0 a 1 sobre tandas. Null sin tandas de este golpe: no se inventa un cero. */
    val aciertoEnTandas: Float?
        get() = if (enTandas == 0) null else acertadosEnTandas.toFloat() / enTandas

    /**
     * Cuánto se pasa o se queda corto el reloj contando este golpe en partido.
     * +0,25 = cuenta un 25% de más. Null si el jugador nunca corrigió este tipo.
     *
     * Es distinto del acierto: un reloj puede contar exactamente 12 bandejas y que sean
     * doce bandejas *distintas* de las que fueron. El desvío no lo detecta y por eso no
     * sustituye a las tandas — pero un desvío grande sí es prueba de que algo va mal.
     */
    val desvioEnPartidos: Float?
        get() = if (realesEnPartidos == 0) null
        else (contadosEnPartidos - realesEnPartidos).toFloat() / realesEnPartidos

    /** Lo que hay que grabar. Un golpe sin tandas no se puede ni juzgar ni arreglar. */
    val faltanTandas: Boolean get() = enTandas < MIN_TANDAS_PARA_JUZGAR

    companion object {
        /** Con menos de esto, el porcentaje es una anécdota y no se debe presumir de él. */
        const val MIN_TANDAS_PARA_JUZGAR = 15
    }
}

/**
 * El informe de precisión del detector: la única pregunta que decide si esta app vale.
 *
 * Todo lo demás —el nivel, la liga, las gráficas, la comunidad— se apoya en que el reloj
 * acierte al decir qué golpe fue. Ese número existía ya, pero repartido: dentro de cada
 * sesión revisada y dentro de cada tanda. Suelto no cambia ninguna decisión; junto dice
 * exactamente qué golpe está roto y qué tanda toca grabar el sábado.
 */
data class InformeDePrecision(
    val golpes: List<PrecisionDeGolpe>,
    /** Cuántas sesiones ha revisado el jugador. Sin revisiones, esa mitad está vacía. */
    val sesionesRevisadas: Int,
    val golpesEnTandas: Int,
    /** Acierto global sobre tandas, 0 a 1. Null sin tandas. */
    val aciertoGlobal: Float?,
    /**
     * Fracción de golpes de tanda que el reloj dejó sin clasificar. Se cuenta aparte del
     * acierto porque no es lo mismo equivocarse que rendirse: un "sin clasificar" no
     * ensucia las estadísticas del jugador, solo le quita un golpe.
     */
    val sinClasificar: Float?,
) {

    val hayDatos: Boolean get() = golpesEnTandas > 0 || sesionesRevisadas > 0

    /**
     * El golpe que peor va, de los que tienen tandas suficientes para juzgarlos. Es la
     * respuesta a "¿y ahora qué arreglo?".
     */
    val peorGolpe: PrecisionDeGolpe?
        get() = golpes
            .filter { !it.faltanTandas && it.aciertoEnTandas != null }
            .minByOrNull { it.aciertoEnTandas!! }

    /** Los golpes de los que no hay tandas suficientes: lo que hay que ir a grabar. */
    val golpesSinTandas: List<ShotType>
        get() = ShotType.entries
            .filter { it != ShotType.UNKNOWN }
            .filter { tipo -> golpes.firstOrNull { it.type == tipo }?.faltanTandas ?: true }

    companion object {

        /**
         * Construye el informe.
         *
         * @param sesiones el historial; solo cuentan las que el jugador haya revisado.
         * @param tandas pares (lo que era, lo que dijo el reloj) sacados de las muestras
         *   etiquetadas volviendo a pasar el clasificador por sus rasgos. Se pide ya
         *   emparejado y no en crudo para que el core no dependa de dónde vive el fichero.
         */
        fun de(
            sesiones: List<PadelSession>,
            tandas: List<Pair<ShotType, ShotType>>,
        ): InformeDePrecision {
            val revisadas = sesiones.filter { it.review != null }

            // --- tandas: verdad-terreno golpe a golpe ---
            val porReal = tandas.groupBy { it.first }
            var aciertos = 0
            var desconocidos = 0
            for ((real, dicho) in tandas) {
                if (dicho == real) aciertos++
                if (dicho == ShotType.UNKNOWN) desconocidos++
            }

            // --- revisiones: recuentos de partido ---
            val contados = mutableMapOf<ShotType, Int>()
            val reales = mutableMapOf<ShotType, Int>()
            for (sesion in revisadas) {
                for ((tipo, n) in sesion.shotsByType) {
                    contados[tipo] = (contados[tipo] ?: 0) + n
                }
                for ((tipo, n) in sesion.effectiveShotsByType) {
                    reales[tipo] = (reales[tipo] ?: 0) + n
                }
            }

            val tipos = (porReal.keys + contados.keys + reales.keys)
                .filter { it != ShotType.UNKNOWN }
                .toSet()

            val golpes = tipos.map { tipo ->
                val delTipo = porReal[tipo].orEmpty()
                // La confusión más repetida, ignorando los aciertos y los "no lo sé":
                // que un golpe se escape sin clasificar es otro problema, y mezclarlo
                // taparía con quién se está confundiendo de verdad.
                val fallos = delTipo
                    .filter { it.second != tipo && it.second != ShotType.UNKNOWN }
                    .groupingBy { it.second }
                    .eachCount()
                val peor = fallos.maxByOrNull { it.value }
                PrecisionDeGolpe(
                    type = tipo,
                    enTandas = delTipo.size,
                    acertadosEnTandas = delTipo.count { it.second == tipo },
                    seConfundeCon = peor?.key,
                    vecesConfundido = peor?.value ?: 0,
                    contadosEnPartidos = contados[tipo] ?: 0,
                    realesEnPartidos = reales[tipo] ?: 0,
                )
            }.sortedWith(
                // Primero lo que peor va y se puede juzgar; después lo que no tiene
                // tandas suficientes; dentro de cada grupo, por golpes medidos.
                compareBy<PrecisionDeGolpe> { it.faltanTandas }
                    .thenBy { it.aciertoEnTandas ?: 2f }
                    .thenByDescending { it.enTandas + it.realesEnPartidos }
            )

            return InformeDePrecision(
                golpes = golpes,
                sesionesRevisadas = revisadas.size,
                golpesEnTandas = tandas.size,
                aciertoGlobal = if (tandas.isEmpty()) null else aciertos.toFloat() / tandas.size,
                sinClasificar = if (tandas.isEmpty()) null else desconocidos.toFloat() / tandas.size,
            )
        }

        /** Redondeo compartido con la UI para que el número no baile entre pantallas. */
        fun porcentaje(fraccion: Float): Int = (abs(fraccion) * 100).toInt()
    }
}
