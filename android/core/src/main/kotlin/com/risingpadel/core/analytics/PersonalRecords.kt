package com.risingpadel.core.analytics

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.ShotType

/**
 * Un récord personal: el valor y la sesión en la que cayó.
 */
data class PersonalRecord(
    val valor: Float,
    val sessionId: String,
    val startedAtEpochMs: Long,
)

/**
 * Los récords del jugador sobre su historial: pura motivación, cero coste de captura.
 * Se recalculan de las sesiones cada vez — como el nivel, no pueden desincronizarse.
 */
data class PersonalRecords(
    /** Pala más rápida (km/h). */
    val velocidadMax: PersonalRecord?,
    /** Más golpeos en una sesión. */
    val golpeosMax: PersonalRecord?,
    /** Mejor ritmo (golpeos/minuto) en sesiones de al menos 10 minutos. */
    val ritmoMax: PersonalRecord?,
    /** Mejor nivel de sesión (solo sesiones con nivel fiable). */
    val nivelMax: PersonalRecord?,
    /** Más smashes en una sesión. */
    val smashesMax: PersonalRecord?,
) {
    /** ¿Esta sesión ostenta alguno de los récords? Para el distintivo 🏆 en su ficha. */
    fun esDe(sessionId: String): Boolean = listOfNotNull(
        velocidadMax, golpeosMax, ritmoMax, nivelMax, smashesMax
    ).any { it.sessionId == sessionId }

    companion object {
        /** Sesiones muy cortas fuera del ritmo: 3 golpeos en 1 min no son un récord. */
        const val MIN_RITMO_DURATION_S = 10 * 60L

        fun from(sessions: List<PadelSession>): PersonalRecords {
            fun mejor(valorDe: (PadelSession) -> Float?): PersonalRecord? =
                sessions.mapNotNull { s ->
                    valorDe(s)?.takeIf { it > 0 }?.let {
                        PersonalRecord(it, s.sessionId, s.startedAtEpochMs)
                    }
                }.maxByOrNull { it.valor }

            return PersonalRecords(
                velocidadMax = mejor { it.intensity.maxRacketSpeedKmh },
                golpeosMax = mejor { it.totalShots.toFloat() },
                ritmoMax = mejor { s ->
                    s.shotsPerMinute.takeIf { s.durationSeconds >= MIN_RITMO_DURATION_S }
                },
                nivelMax = mejor { s ->
                    s.level.takeIf { it.gradedShots > 0 && it.reliable }?.overall
                },
                smashesMax = mejor { s ->
                    s.shotsByType[ShotType.SMASH]?.toFloat()
                },
            )
        }
    }
}
