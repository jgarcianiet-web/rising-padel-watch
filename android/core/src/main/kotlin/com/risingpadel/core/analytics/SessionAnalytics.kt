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

    companion object {
        const val DEFAULT_STEP_MS = 5 * 60_000L
        const val DEFAULT_WINDOW_MS = 15 * 60_000L

        /** Los dos zooms que ofrece la UI de frecuencia. */
        const val INTERVAL_5_MIN_MS = 5 * 60_000L
        const val INTERVAL_10_MIN_MS = 10 * 60_000L
    }
}
