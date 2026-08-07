package com.risingpadel.core.analytics

import com.risingpadel.core.level.LevelEstimator
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotType

/** Un intervalo de la sesión y cuántos golpeos cayeron dentro. */
data class FrequencyBucket(
    val startMs: Long,
    val endMs: Long,
    val count: Int,
)

/** El nivel estimado en un instante de la sesión, mirando la ventana que lo precede. */
data class LevelPoint(
    val offsetMs: Long,
    val level: Float,
    /** Golpeos que puntuaron en la ventana: con pocos, el punto es orientativo. */
    val gradedShots: Int,
)

/**
 * Todo lo que se puede decir de **un tipo de golpe** en una sesión.
 *
 * Es la unidad que lee el jugador: nadie mira un golpeo suelto, mira "cómo fue mi
 * derecha hoy". Reúne las tres preguntas —cuántos, a qué velocidad y con qué
 * calidad— en un solo objeto para que la app no tenga que recalcular nada ni pueda
 * hacerlo distinto en iPhone y en Android.
 */
data class ShotBreakdown(
    val type: ShotType,
    val count: Int,
    val meanKmh: Float,
    val maxKmh: Float,
    /** Fracción del total de golpeos de la sesión, 0 a 1. */
    val share: Float,
    /**
     * Nota del golpe en la escala 1-7, o null si ninguno puntuó (poca confianza del
     * detector o tipo sin banda). Null es "no lo sé", que no es lo mismo que un 1.
     */
    val grade: Float?,
    /**
     * Regularidad de ese golpe: 0 = cada uno de su padre y de su madre, 1 = calcados.
     * Null con menos de dos golpeos puntuados — con uno solo no hay regularidad de la
     * que hablar.
     */
    val consistency: Float?,
    /** Minuto de la sesión de cada golpeo, para pintar cuándo se dieron. */
    val offsetsMs: List<Long>,
)

/**
 * Series listas para pintar a partir de los golpeos de una sesión.
 *
 * Vive en el core y no en las apps por la misma razón que el nivel: las dos plataformas
 * tienen que enseñar exactamente las mismas curvas para los mismos golpeos, y aquí hay
 * tests que lo fijan. Las apps solo dibujan.
 */
class SessionAnalytics(
    private val estimator: LevelEstimator = LevelEstimator(),
) {

    /**
     * Golpeos por intervalo de tiempo, cubriendo la sesión entera.
     *
     * Devuelve **todos** los intervalos, también los vacíos: en la gráfica un hueco de
     * cinco minutos sin golpeos es información (un descanso, un set perdido de paliza),
     * no un dato que falte.
     */
    fun shotFrequency(shots: List<Shot>, durationMs: Long, intervalMs: Long): List<FrequencyBucket> {
        require(intervalMs > 0) { "intervalMs debe ser positivo" }
        if (durationMs <= 0) return emptyList()

        val bucketCount = ((durationMs + intervalMs - 1) / intervalMs).toInt()
        val counts = IntArray(bucketCount)
        for (shot in shots) {
            // Un offset fuera de rango (relojes con redondeos raros) se acota al borde
            // en vez de descartarse: el golpeo existió y tiene que contar en algún sitio.
            val index = (shot.offsetMs / intervalMs).toInt().coerceIn(0, bucketCount - 1)
            counts[index]++
        }
        return List(bucketCount) { index ->
            FrequencyBucket(
                startMs = index * intervalMs,
                endMs = ((index + 1) * intervalMs).coerceAtMost(durationMs),
                count = counts[index],
            )
        }
    }

    /**
     * El nivel de la sesión a lo largo del tiempo: un punto cada [stepMs], estimado
     * sobre los golpeos de la ventana de [windowMs] anterior a ese instante.
     *
     * Es una ventana deslizante y no un acumulado a propósito: el acumulado converge a
     * la media y se aplana, y lo que interesa ver es si el jugador vino arriba, se cayó
     * en el segundo set o remontó. Los instantes sin ningún golpeo puntuado en la
     * ventana no emiten punto: dibujar un nivel sin golpeos sería inventar.
     */
    fun levelProgression(
        shots: List<Shot>,
        durationMs: Long,
        stepMs: Long = DEFAULT_STEP_MS,
        windowMs: Long = DEFAULT_WINDOW_MS,
    ): List<LevelPoint> {
        require(stepMs > 0) { "stepMs debe ser positivo" }
        require(windowMs > 0) { "windowMs debe ser positivo" }
        if (durationMs <= 0 || shots.isEmpty()) return emptyList()

        val instants = generateSequence(stepMs) { it + stepMs }
            .takeWhile { it < durationMs }
            .plus(durationMs) // El último punto cae en el final real, no en el múltiplo.
            .toList()

        return instants.mapNotNull { instant ->
            val window = shots.filter { it.offsetMs > instant - windowMs && it.offsetMs <= instant }
            val level = estimator.estimate(window)
            if (level.gradedShots == 0) return@mapNotNull null
            LevelPoint(offsetMs = instant, level = level.overall, gradedShots = level.gradedShots)
        }
    }

    /**
     * Nota media (1-7) de un tipo de golpe en la sesión, o null si no hay ninguno que
     * puntúe. Es lo que alimenta el filtro "por golpe" del histórico.
     */
    fun typeGrade(shots: List<Shot>, type: ShotType): Float? {
        val grades = shots.filter { it.type == type }.mapNotNull { estimator.grade(it) }
        if (grades.isEmpty()) return null
        return grades.average().toFloat()
    }

    /**
     * Un resumen por tipo de golpe, del más usado al menos usado.
     *
     * Ordenado por cantidad a propósito: lo primero que quiere saber cualquiera es en
     * qué golpe se le fue el partido, y ese es casi siempre el que más repitió. Los
     * tipos sin ningún golpeo no aparecen — una fila a cero no es información, es ruido.
     */
    fun shotBreakdown(shots: List<Shot>): List<ShotBreakdown> {
        if (shots.isEmpty()) return emptyList()
        val total = shots.size.toFloat()
        return shots.groupBy { it.type }
            .map { (type, delTipo) ->
                val grades = delTipo.mapNotNull { estimator.grade(it) }
                ShotBreakdown(
                    type = type,
                    count = delTipo.size,
                    meanKmh = delTipo.map { it.racketSpeedKmh }.average().toFloat(),
                    maxKmh = delTipo.maxOf { it.racketSpeedKmh },
                    share = delTipo.size / total,
                    grade = if (grades.isEmpty()) null else grades.average().toFloat(),
                    consistency = if (grades.size < 2) null else regularidad(grades),
                    offsetsMs = delTipo.map { it.offsetMs }.sorted(),
                )
            }
            // A igualdad de golpeos manda el orden del enum, para que dos sesiones
            // iguales no salgan en orden distinto según cómo cayeron en el mapa.
            .sortedWith(compareByDescending<ShotBreakdown> { it.count }.thenBy { it.type.ordinal })
    }

    /**
     * La misma regularidad que usa el nivel, pero de un solo golpe: cuánto se parecen
     * entre sí sus notas. Se comparte la escala (1,5 niveles de desviación ya es mucho)
     * para que "regular" signifique lo mismo en la ficha del golpe y en el nivel global.
     */
    private fun regularidad(grades: List<Float>): Float {
        val mean = grades.average()
        val variance = grades.sumOf { (it - mean) * (it - mean) } / grades.size
        val sd = kotlin.math.sqrt(variance).toFloat()
        return (1f - sd / MAX_MEANINGFUL_DEVIATION).coerceIn(0f, 1f)
    }

    companion object {
        /** Misma escala que la regularidad del nivel: sin esto, dos "regular" distintos. */
        const val MAX_MEANINGFUL_DEVIATION = 1.5f

        const val DEFAULT_STEP_MS = 5 * 60_000L
        const val DEFAULT_WINDOW_MS = 15 * 60_000L

        /** Los dos zooms que ofrece la UI de frecuencia. */
        const val INTERVAL_5_MIN_MS = 5 * 60_000L
        const val INTERVAL_10_MIN_MS = 10 * 60_000L
    }
}
