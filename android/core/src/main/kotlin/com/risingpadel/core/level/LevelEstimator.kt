package com.risingpadel.core.level

import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotType
import kotlinx.serialization.Serializable
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Nivel técnico estimado de una sesión, en la escala de pádel de 1 a 7.
 *
 * @param overall nivel global, ya con los ajustes de regularidad y repertorio.
 * @param byShotType nivel medio de cada tipo de golpe con muestras suficientes.
 * @param consistency 0 = golpeos muy dispares, 1 = muy regular.
 * @param repertoire 0 = un solo tipo de golpe, 1 = repertorio completo.
 * @param gradedShots golpeos que han puntuado. Los de tipo desconocido no cuentan.
 * @param reliable false si no hay golpeos suficientes. **El nivel se sigue calculando**,
 *   pero la UI debe presentarlo como provisional en vez de esconderlo: un jugador que ha
 *   dado 20 golpes prefiere ver una estimación con aviso que un hueco.
 */
@Serializable
data class SessionLevel(
    val overall: Float,
    val byShotType: Map<ShotType, Float>,
    val consistency: Float,
    val repertoire: Float,
    val gradedShots: Int,
    val reliable: Boolean,
) {
    /** El nivel redondeado a medio punto, que es como se habla de nivel en un club. */
    val rounded: Float get() = (overall * 2).roundToInt() / 2f
}

/**
 * Puntúa cada golpeo de 1 a 7 y saca el nivel técnico de la sesión.
 *
 * Es una **heurística sin validar**: puntúa lo que el giróscopo puede ver —lo rápido que
 * va la pala y qué forma tiene el swing— y de ahí infiere un nivel. No ve la colocación,
 * ni la lectura de la pared, ni la táctica, que en pádel pesan tanto como el golpeo. Ver
 * `docs/level.md` para lo que mide, lo que no, y cómo calibrarlo.
 */
class LevelEstimator(private val config: LevelConfig = LevelConfig.DEFAULT) {

    /**
     * Nota de un golpeo suelto, de 1 a 7.
     *
     * Devuelve null si el tipo es desconocido o la clasificación no es fiable: puntuar un
     * golpeo que no se sabe qué es sería inventar.
     */
    fun grade(shot: Shot): Float? {
        if (shot.type == ShotType.UNKNOWN) return null
        if (shot.confidence < config.minConfidence) return null
        val band = config.bands[shot.type] ?: return null

        val speedScore = interpolate(shot.racketSpeedKmh, band.speedAtLevel1, band.speedAtLevel7)
        val swingScore = swingScore(shot.features.sweptAngleDeg, band)

        val blended = speedScore * config.speedWeight + swingScore * (1 - config.speedWeight)
        return toLevel(blended)
    }

    fun estimate(shots: List<Shot>): SessionLevel {
        val graded = shots.mapNotNull { shot -> grade(shot)?.let { shot.type to it } }

        if (graded.isEmpty()) {
            return SessionLevel(
                overall = LevelConfig.MIN_LEVEL,
                byShotType = emptyMap(),
                consistency = 0f,
                repertoire = 0f,
                gradedShots = 0,
                reliable = false,
            )
        }

        val byType = graded.groupBy({ it.first }, { it.second })
        val grades = graded.map { it.second }

        // La media es por tipo de golpe y no por golpeo suelto: si no, una sesión con 200
        // derechas y 5 voleas sería "el nivel de derecha del jugador" con otro nombre.
        val mean = byType.values.map { it.average().toFloat() }.average().toFloat()

        val consistency = consistency(byType)
        val repertoire = repertoire(byType, graded.size)

        val overall = (
            mean -
                (1 - consistency) * config.maxConsistencyPenalty +
                repertoire * config.maxRepertoireBonus
            ).coerceIn(LevelConfig.MIN_LEVEL, LevelConfig.MAX_LEVEL)

        return SessionLevel(
            overall = overall,
            byShotType = byType.mapValues { (_, values) -> round1(values.average().toFloat()) },
            consistency = round2(consistency),
            repertoire = round2(repertoire),
            gradedShots = graded.size,
            reliable = graded.size >= config.minShotsForEstimate,
        )
    }

    /**
     * Regularidad: cuánto se parecen entre sí los golpeos del mismo tipo.
     *
     * En pádel el nivel **es** regularidad. Dos jugadores con la misma derecha máxima no
     * son el mismo nivel si uno la repite treinta veces y el otro una de cada cinco. Se
     * mide dentro de cada tipo y no sobre el total, porque la diferencia natural entre una
     * volea y un smash no es irregularidad del jugador.
     */
    private fun consistency(byType: Map<ShotType, List<Float>>): Float {
        val deviations = byType.values
            .filter { it.size >= 2 }
            .map { standardDeviation(it) }
        if (deviations.isEmpty()) return NO_DATA_CONSISTENCY

        val average = deviations.average().toFloat()
        // Una desviación de 1.5 niveles dentro del mismo golpe es ya muy irregular.
        return (1f - average / MAX_MEANINGFUL_DEVIATION).coerceIn(0f, 1f)
    }

    /**
     * Repertorio: cuántos tipos de golpe distintos usa con soltura.
     *
     * Solo **suma**, nunca resta: una sesión de entrenamiento de solo derechas no
     * significa que el jugador no sepa volear, y penalizarla sería castigar entrenar.
     */
    private fun repertoire(byType: Map<ShotType, List<Float>>, total: Int): Float {
        if (total < config.minShotsForEstimate) return 0f
        val used = byType.count { (_, values) -> values.size >= config.minShotsPerTypeForRepertoire }
        return (used.toFloat() / config.bands.size).coerceIn(0f, 1f)
    }

    /** Amplitud del swing: 0 = lejos de la referencia, 1 = en ella. */
    private fun swingScore(sweptDeg: Float, band: ShotBand): Float {
        if (band.compactIsBetter) {
            // Por debajo del ideal no se penaliza: una volea muy corta es correcta.
            if (sweptDeg <= band.idealSweptDeg) return 1f
            val excess = sweptDeg - band.idealSweptDeg
            return (1f - excess / band.idealSweptDeg).coerceIn(0f, 1f)
        }
        return (sweptDeg / band.idealSweptDeg).coerceIn(0f, 1f)
    }

    /** Posición de [value] en el rango, acotada a [0, 1]. */
    private fun interpolate(value: Float, atLevel1: Float, atLevel7: Float): Float {
        if (atLevel7 <= atLevel1) return 0f
        return ((value - atLevel1) / (atLevel7 - atLevel1)).coerceIn(0f, 1f)
    }

    /** Un 0..1 pasado a la escala 1..7. */
    private fun toLevel(normalized: Float): Float =
        round1(LevelConfig.MIN_LEVEL + normalized * (LevelConfig.MAX_LEVEL - LevelConfig.MIN_LEVEL))

    private fun standardDeviation(values: List<Float>): Float {
        val mean = values.average()
        val variance = values.sumOf { (it - mean) * (it - mean) } / values.size
        return sqrt(variance).toFloat()
    }

    private fun round1(value: Float): Float = (value * 10).roundToInt() / 10f
    private fun round2(value: Float): Float = (value * 100).roundToInt() / 100f

    private companion object {
        /** Con un golpeo por tipo no se puede hablar de regularidad; ni premia ni castiga. */
        const val NO_DATA_CONSISTENCY = 0.5f
        const val MAX_MEANINGFUL_DEVIATION = 1.5f
    }
}

/** Etiqueta corta para enseñar el nivel sin decimales inventados. */
fun SessionLevel.label(): String = when {
    !reliable -> "Nivel ~${rounded} (pocos golpeos)"
    else -> "Nivel ${rounded}"
}
