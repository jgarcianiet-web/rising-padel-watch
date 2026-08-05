package com.risingpadel.core.insights

import com.risingpadel.core.analytics.SessionAnalytics
import com.risingpadel.core.level.LevelEstimator
import com.risingpadel.core.model.HeartRateSample
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotType
import kotlin.math.abs
import kotlin.math.roundToInt

/** Las tres familias de ideas que la app enseña al acabar una sesión. */
enum class InsightCategory {
    /** Qué pasó en el partido: los momentos que lo movieron. */
    MATCH_ANALYSIS,

    /** Cómo juegas: en qué eres fuerte y en qué no. */
    STRENGTHS,

    /** Qué hacer la próxima vez. */
    TRAINING,
}

/**
 * Una idea concreta sobre la sesión, con el número que la sostiene.
 *
 * @param evidence golpeos (o lecturas) que respaldan la idea. La UI lo enseña porque una
 *   afirmación sobre 12 golpeos y otra sobre 300 no valen lo mismo.
 */
data class Insight(
    val category: InsightCategory,
    val headline: String,
    val detail: String,
    val evidence: Int,
)

/**
 * Saca conclusiones en lenguaje llano de una sesión.
 *
 * **Cada frase sale de una cuenta sobre los datos del jugador, no de un texto genérico.**
 * Es la diferencia entre un consejo que se puede comprobar ("en los puntos largos tu
 * nivel sube de 3.4 a 4.1") y uno de horóscopo ("sé más paciente"). Una regla que no
 * llega al mínimo de evidencia no dice nada: preferimos tres ideas sólidas a diez
 * inventadas.
 *
 * Todo se calcula en el dispositivo: no hace falta red ni mandar la sesión a ningún
 * sitio para tener las ideas. Un modelo de lenguaje puede después redactar el resumen
 * a partir de estos hechos —esa es la parte que hace bien—, pero los hechos salen de
 * aquí.
 */
class InsightEngine(
    private val estimator: LevelEstimator = LevelEstimator(),
    private val analytics: SessionAnalytics = SessionAnalytics(),
) {

    fun insights(session: PadelSession): List<Insight> = buildList {
        addAll(rallyInsight(session.shots))
        addAll(heartRateInsight(session))
        addAll(fatigueInsight(session))
        addAll(shotQualityInsights(session))
        addAll(trainingSuggestions(session))
    }

    // MARK: Puntos largos contra puntos cortos

    /**
     * Agrupa los golpeos en puntos: un hueco largo entre dos golpeos significa que el
     * punto acabó y se está sacando otra vez.
     */
    fun rallies(shots: List<Shot>, gapMs: Long = RALLY_GAP_MS): List<List<Shot>> {
        if (shots.isEmpty()) return emptyList()
        val ordered = shots.sortedBy { it.offsetMs }
        val result = mutableListOf<MutableList<Shot>>()
        var current = mutableListOf(ordered.first())
        for (shot in ordered.drop(1)) {
            if (shot.offsetMs - current.last().offsetMs > gapMs) {
                result += current
                current = mutableListOf(shot)
            } else {
                current += shot
            }
        }
        result += current
        return result
    }

    private fun rallyInsight(shots: List<Shot>): List<Insight> {
        val rallies = rallies(shots)
        val longShots = rallies.filter { it.size >= LONG_RALLY_SHOTS }.flatten()
        val shortShots = rallies.filter { it.size <= SHORT_RALLY_SHOTS }.flatten()

        val longGrade = meanGrade(longShots) ?: return emptyList()
        val shortGrade = meanGrade(shortShots) ?: return emptyList()
        if (longShots.size < MIN_EVIDENCE || shortShots.size < MIN_EVIDENCE) return emptyList()

        val delta = longGrade - shortGrade
        if (abs(delta) < MIN_LEVEL_DELTA) return emptyList()

        val percent = percentChange(from = shortGrade, to = longGrade)
        return listOf(
            if (delta > 0) {
                Insight(
                    category = InsightCategory.STRENGTHS,
                    headline = "Creces en los puntos largos",
                    detail = "En los puntos de $LONG_RALLY_SHOTS golpeos o más tu nivel medio " +
                        "es ${format(longGrade)} frente a ${format(shortGrade)} en los cortos " +
                        "($percent% mejor). Alargar el punto te favorece: ten paciencia y deja " +
                        "que el error lo cometa el rival.",
                    evidence = longShots.size,
                )
            } else {
                Insight(
                    category = InsightCategory.STRENGTHS,
                    headline = "Te desgastan los puntos largos",
                    detail = "En los puntos de $LONG_RALLY_SHOTS golpeos o más tu nivel medio " +
                        "cae a ${format(longGrade)} desde ${format(shortGrade)} en los cortos " +
                        "($percent%). Busca cerrar antes el punto, o entrena el aguante en el " +
                        "intercambio largo.",
                    evidence = longShots.size,
                )
            }
        )
    }

    // MARK: Pulso contra rendimiento

    /**
     * Cruza la serie de pulso con la calidad de los golpeos: a cada golpeo se le asigna
     * la lectura de pulso vigente y se comparan los golpeos por encima y por debajo de
     * la mediana del pulso de la sesión.
     *
     * La frontera es el pulso **medio de la sesión** y no un número fijo (160 ppm, por
     * ejemplo) porque el pulso al que cada jugador se rompe depende de su edad y su
     * forma física; la media de **su** sesión es la única referencia que no hay que
     * calibrar.
     *
     * Media y no mediana: una sesión suele tener dos mesetas de pulso (calentamiento y
     * juego), y con dos mesetas la mediana cae dentro de una de ellas y deja el otro
     * lado de la comparación vacío. La media parte por el medio.
     */
    private fun heartRateInsight(session: PadelSession): List<Insight> {
        val series = session.health.heartRateSeries
        if (series.size < MIN_HR_SAMPLES) return emptyList()

        val threshold = series.map { it.bpm }.average().toFloat()
        val graded = session.shots.mapNotNull { shot ->
            val bpm = bpmAt(shot.offsetMs, series) ?: return@mapNotNull null
            estimator.grade(shot)?.let { bpm to it }
        }
        val high = graded.filter { it.first > threshold }.map { it.second }
        val low = graded.filter { it.first <= threshold }.map { it.second }
        if (high.size < MIN_EVIDENCE || low.size < MIN_EVIDENCE) return emptyList()

        val highGrade = high.average().toFloat()
        val lowGrade = low.average().toFloat()
        val delta = highGrade - lowGrade
        if (abs(delta) < MIN_LEVEL_DELTA) return emptyList()

        val bpmLabel = threshold.roundToInt()
        val percent = percentChange(from = lowGrade, to = highGrade)
        return listOf(
            if (delta < 0) {
                Insight(
                    category = InsightCategory.MATCH_ANALYSIS,
                    headline = "El pulso te pasa factura",
                    detail = "Con el pulso por encima de $bpmLabel ppm tu nivel baja de " +
                        "${format(lowGrade)} a ${format(highGrade)} ($percent%). Trabajar el " +
                        "fondo físico te daría más que cualquier cambio técnico.",
                    evidence = high.size,
                )
            } else {
                Insight(
                    category = InsightCategory.MATCH_ANALYSIS,
                    headline = "Juegas mejor enchufado",
                    detail = "Con el pulso por encima de $bpmLabel ppm tu nivel sube de " +
                        "${format(lowGrade)} a ${format(highGrade)} ($percent%). Te cuesta " +
                        "arrancar: calienta más antes de empezar.",
                    evidence = high.size,
                )
            }
        )
    }

    /** Pulso vigente en un instante: la última lectura anterior o igual a él. */
    private fun bpmAt(offsetMs: Long, series: List<HeartRateSample>): Int? =
        series.lastOrNull { it.offsetMs <= offsetMs }?.bpm

    // MARK: Cómo llegaste al final

    private fun fatigueInsight(session: PadelSession): List<Insight> {
        val points = analytics.levelProgression(
            session.shots,
            durationMs = session.durationSeconds * 1000,
        )
        if (points.size < 4) return emptyList()

        val third = points.size / 3
        if (third == 0) return emptyList()
        val start = points.take(third).map { it.level }.average().toFloat()
        val end = points.takeLast(third).map { it.level }.average().toFloat()
        val delta = end - start
        if (abs(delta) < MIN_LEVEL_DELTA) return emptyList()

        val evidence = points.sumOf { it.gradedShots }
        return listOf(
            if (delta < 0) {
                Insight(
                    category = InsightCategory.MATCH_ANALYSIS,
                    headline = "Te fuiste apagando",
                    detail = "Empezaste jugando a ${format(start)} y acabaste a ${format(end)}. " +
                        "La diferencia está en el último tercio: o es cansancio o es " +
                        "concentración, y las dos se entrenan.",
                    evidence = evidence,
                )
            } else {
                Insight(
                    category = InsightCategory.MATCH_ANALYSIS,
                    headline = "Fuiste a más",
                    detail = "Empezaste a ${format(start)} y acabaste a ${format(end)}: entraste " +
                        "en calor tarde. Un calentamiento más largo te ahorraría los primeros " +
                        "juegos.",
                    evidence = evidence,
                )
            }
        )
    }

    // MARK: Tu mejor y tu peor golpe

    private fun shotQualityInsights(session: PadelSession): List<Insight> {
        val byType = session.shots
            .groupBy { it.type }
            .mapNotNull { (type, shots) ->
                if (type == ShotType.UNKNOWN || shots.size < MIN_SHOTS_PER_TYPE) return@mapNotNull null
                meanGrade(shots)?.let { Triple(type, it, shots.size) }
            }
            .sortedByDescending { it.second }
        if (byType.size < 2) return emptyList()

        val best = byType.first()
        val worst = byType.last()
        if (best.second - worst.second < MIN_LEVEL_DELTA) return emptyList()

        return listOf(
            Insight(
                category = InsightCategory.STRENGTHS,
                headline = "Tu golpe fuerte es ${label(best.first).lowercase()}",
                detail = "${label(best.first)} te sale a ${format(best.second)} sobre " +
                    "${best.third} golpeos, mientras que ${label(worst.first).lowercase()} se " +
                    "queda en ${format(worst.second)}. Construye el punto con el primero y " +
                    "evita que el rival te busque el segundo.",
                evidence = best.third + worst.third,
            )
        )
    }

    // MARK: Qué entrenar

    private fun trainingSuggestions(session: PadelSession): List<Insight> = buildList {
        val level = session.level
        if (level.gradedShots < MIN_EVIDENCE) return@buildList

        // Regularidad antes que potencia: en pádel el nivel es repetir.
        if (level.consistency < LOW_CONSISTENCY) {
            add(
                Insight(
                    category = InsightCategory.TRAINING,
                    headline = "Repite, no pegues más fuerte",
                    detail = "Tu regularidad es del ${(level.consistency * 100).roundToInt()}%: " +
                        "los golpeos del mismo tipo te salen muy distintos entre sí. Series de " +
                        "20 bolas cruzadas buscando el mismo golpe, sin subir la potencia.",
                    evidence = level.gradedShots,
                )
            )
        }

        // Repertorio: solo suma. Que falte un golpe no es un defecto, es una oportunidad.
        val played = session.shotsByType.filterKeys { it != ShotType.UNKNOWN }.keys
        val missing = listOf(ShotType.BANDEJA, ShotType.VIBORA, ShotType.SMASH)
            .filter { it !in played }
        if (missing.isNotEmpty() && session.totalShots >= MIN_SHOTS_FOR_REPERTOIRE) {
            add(
                Insight(
                    category = InsightCategory.TRAINING,
                    headline = "Te falta el juego alto",
                    detail = "En ${session.totalShots} golpeos no apareció " +
                        missing.joinToString(" ni ") { label(it).lowercase() } +
                        ". O no te suben globos o los estás dejando botar: media hora de " +
                        "globos y salida de pared cambia el partido.",
                    evidence = session.totalShots,
                )
            )
        }

        // El golpe más flojo con muestras suficientes es lo más accionable que hay.
        val worst = session.shots
            .groupBy { it.type }
            .mapNotNull { (type, shots) ->
                if (type == ShotType.UNKNOWN || shots.size < MIN_SHOTS_PER_TYPE) return@mapNotNull null
                meanGrade(shots)?.let { type to it }
            }
            .minByOrNull { it.second }
        if (worst != null && worst.second < level.overall - MIN_LEVEL_DELTA) {
            add(
                Insight(
                    category = InsightCategory.TRAINING,
                    headline = "Dedica la próxima sesión a ${label(worst.first).lowercase()}",
                    detail = "${label(worst.first)} va a ${format(worst.second)}, por debajo de " +
                        "tu ${format(level.overall)} global. Es donde menos esfuerzo cuesta " +
                        "ganar nivel: 15 minutos de ese golpe al empezar, con el brazo fresco.",
                    evidence = session.shotsByType[worst.first] ?: 0,
                )
            )
        }
    }

    // MARK: Utilidades

    private fun meanGrade(shots: List<Shot>): Float? {
        val grades = shots.mapNotNull { estimator.grade(it) }
        return if (grades.isEmpty()) null else grades.average().toFloat()
    }

    /** Cambio porcentual con signo explícito, ya redondeado y con el símbolo. */
    private fun percentChange(from: Float, to: Float): String {
        if (from <= 0f) return "+0"
        val percent = ((to - from) / from * 100).roundToInt()
        return if (percent >= 0) "+$percent" else "$percent"
    }

    private fun format(level: Float): String = "%.1f".format(level)

    private fun label(type: ShotType): String = when (type) {
        ShotType.FOREHAND -> "La derecha"
        ShotType.BACKHAND -> "El revés"
        ShotType.FOREHAND_VOLLEY -> "La volea de derecha"
        ShotType.BACKHAND_VOLLEY -> "La volea de revés"
        ShotType.BANDEJA -> "La bandeja"
        ShotType.VIBORA -> "La víbora"
        ShotType.SMASH -> "El remate"
        ShotType.SERVE -> "El saque"
        ShotType.UNKNOWN -> "Sin clasificar"
    }

    private companion object {
        /** Hueco entre golpeos a partir del cual se considera que el punto acabó. */
        const val RALLY_GAP_MS = 4_000L
        const val LONG_RALLY_SHOTS = 5
        const val SHORT_RALLY_SHOTS = 3

        /** Por debajo de esto la comparación es anécdota, no dato. */
        const val MIN_EVIDENCE = 15
        const val MIN_SHOTS_PER_TYPE = 8
        const val MIN_SHOTS_FOR_REPERTOIRE = 60
        const val MIN_HR_SAMPLES = 6

        /** Media décima de nivel no la nota nadie; media unidad sí. */
        const val MIN_LEVEL_DELTA = 0.3f
        const val LOW_CONSISTENCY = 0.6f
    }
}
