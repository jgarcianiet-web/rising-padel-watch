package com.risingpadel.core.liga

import com.risingpadel.core.analytics.SessionAnalytics
import com.risingpadel.core.insights.ObjectiveEvaluator
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.Side
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Convierte una sesión del reloj en un partido de la liga.
 *
 * Es el mismo mapeo que hace iOS en `LigaModel.saveMatch` — voleas unificadas, catálogo
 * de nombres de la liga, curva del reloj en los campos heredados, objetivos medibles
 * marcados por el [ObjectiveEvaluator] — y vive en el core para que Android y cualquier
 * plataforma futura guarden exactamente el mismo partido. Con tests.
 */
object LigaMapper {

    /** Tipos del reloj → catálogo de la liga (las voleas se tratan aparte). */
    private val CATALOGO = mapOf(
        ShotType.FOREHAND to "Derecha",
        ShotType.BACKHAND to "Revés",
        ShotType.BANDEJA to "Bandeja",
        ShotType.VIBORA to "Víbora",
        ShotType.SMASH to "Remate",
        ShotType.SERVE to "Saque",
    )

    fun matchFrom(
        session: PadelSession,
        playerAverage: Float?,
        objetivos: List<String>,
    ): LigaMatch {
        val analytics = SessionAnalytics()
        val level = session.level

        // Nivel por golpe con el catálogo de la liga; las dos voleas se funden en una.
        val golpes = mutableListOf<LigaGolpeSesion>()
        val voleas = mutableListOf<Double>()
        for ((type, grade) in level.byShotType) {
            if (type == ShotType.FOREHAND_VOLLEY || type == ShotType.BACKHAND_VOLLEY) {
                voleas.add(grade.toDouble())
            } else {
                CATALOGO[type]?.let { golpes.add(LigaGolpeSesion(it, round1(grade.toDouble()))) }
            }
        }
        if (voleas.isNotEmpty()) golpes.add(LigaGolpeSesion("Volea", round1(voleas.average())))

        // Los recuentos con la revisión del jugador aplicada: si dijo que fueron 12
        // bandejas, la liga y los objetivos ven 12, contara lo que contara el reloj.
        val volumen = mutableListOf<LigaGolpeVolumen>()
        var voleaCount = 0
        for ((type, count) in session.effectiveShotsByType) {
            if (type == ShotType.FOREHAND_VOLLEY || type == ShotType.BACKHAND_VOLLEY) {
                voleaCount += count
            } else if (count > 0) {
                CATALOGO[type]?.let { volumen.add(LigaGolpeVolumen(it, count)) }
            }
        }
        if (voleaCount > 0) volumen.add(LigaGolpeVolumen("Volea", voleaCount))

        val durationMs = session.durationSeconds * 1000
        val progression = analytics.levelProgression(session.shots, durationMs)
        val frequency = analytics.shotFrequency(
            session.shots, durationMs, SessionAnalytics.INTERVAL_10_MIN_MS
        )

        // Los objetivos que el reloj puede medir se marcan solos; el resto queda a mano.
        val checks = objetivos.map { objetivo ->
            ObjectiveEvaluator.evaluate(
                objetivo, session.effectiveShotsByType, session.effectiveTotalShots
            )?.met ?: false
        }

        val score = session.score
        return LigaMatch(
            // El id es la fecha de inicio: guardar dos veces actualiza, no duplica.
            id = session.startedAtEpochMs,
            fecha = fechaLocal(session.startedAtEpochMs),
            tipo = if (score != null) "competitivo" else "amistoso",
            resultado = resultado(score),
            sets = score?.allSets?.joinToString(", ") { "${it.us}-${it.them}" } ?: "",
            marcador = score?.allSets?.map { LigaSetMarcador(yo = "${it.us}", rival = "${it.them}") },
            nivelBand = if (level.gradedShots > 0 && level.reliable) round1(level.overall.toDouble()) else null,
            golpesSesion = golpes.takeIf { it.isNotEmpty() }?.sortedByDescending { it.nota },
            objetivos = checks,
            bandInicio = progression.firstOrNull()?.let { round1(it.level.toDouble()) },
            bandFin = progression.lastOrNull()?.let { round1(it.level.toDouble()) },
            bandMediaJugador = playerAverage?.let { round1(it.toDouble()) },
            golpesVolumen = volumen.takeIf { it.isNotEmpty() }?.sortedByDescending { it.cantidad },
            totalGolpes = session.effectiveTotalShots,
            salud = if (session.health.isEmpty) null else LigaSaludPartido(
                duracionMin = (session.durationSeconds / 60.0).roundToInt(),
                pulsoMedio = session.health.heartRate?.meanBpm,
                pulsoMax = session.health.heartRate?.maxBpm,
                calorias = session.health.activeEnergyKcal?.roundToInt(),
            ),
            bandPuntos = progression.takeIf { it.size >= 2 }?.map {
                LigaPuntoProgreso(minuto = it.offsetMs / 60_000.0, nivel = round1(it.level.toDouble()))
            },
            frecuenciaGolpeo = frequency.takeIf { it.isNotEmpty() }?.let { buckets ->
                LigaFrecuenciaGolpeo(intervaloMin = 10, cuentas = buckets.map { it.count })
            },
        )
    }

    /** Un partido interrumpido se decide por sets ganados, como haría el jugador. */
    private fun resultado(score: MatchScore?): String {
        score ?: return "derrota"
        if (score.isFinished) {
            return if (score.winner == Side.US) "victoria" else "derrota"
        }
        val us = score.gamesWon(Side.US)
        val them = score.gamesWon(Side.THEM)
        return when {
            us == them -> "empate"
            us > them -> "victoria"
            else -> "derrota"
        }
    }

    private fun fechaLocal(epochMs: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date(epochMs))

    private fun round1(value: Double): Double = (value * 10).roundToInt() / 10.0
}
