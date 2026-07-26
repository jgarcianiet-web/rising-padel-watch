package com.risingpadel.core.score

/**
 * Qué acaba de pasar al anotar un punto.
 *
 * Los relojes lo usan para elegir la vibración: el jugador tiene que enterarse de que ha
 * cerrado un juego o un set sin mirar la pantalla. Vive en el core y no en cada app
 * porque es una comparación entre dos marcadores, no una decisión de interfaz.
 */
enum class ScoreEvent {
    POINT,
    GAME,
    SET,
    MATCH,
    UNDO;

    companion object {
        fun between(before: MatchScore, after: MatchScore): ScoreEvent = when {
            after.isFinished -> MATCH
            after.completedSets.size > before.completedSets.size -> SET
            after.currentSet != before.currentSet -> GAME
            else -> POINT
        }
    }
}
