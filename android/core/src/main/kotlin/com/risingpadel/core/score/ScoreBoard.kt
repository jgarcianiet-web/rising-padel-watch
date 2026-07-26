package com.risingpadel.core.score

/**
 * Marcador con historial para deshacer.
 *
 * Puntuar mal es constante: se anota un punto al bando equivocado, o se anota dos veces
 * el mismo. Sin deshacer, un marcador en el reloj es inservible en cuanto pasa una vez,
 * porque no hay forma de recomponer el estado a mano.
 *
 * Guarda el estado completo antes de cada punto en vez de intentar invertir la
 * transición. Un partido son unos 200 puntos: la memoria es irrelevante y a cambio
 * deshacer es exacto aunque el punto cerrara un juego, un set o el partido.
 */
class ScoreBoard(
    rules: ScoreRules = ScoreRules.DEFAULT,
    firstServer: Side = Side.US,
) {
    private val history = ArrayDeque<MatchScore>()

    var current: MatchScore = MatchScore.start(rules, firstServer)
        private set

    val canUndo: Boolean get() = history.isNotEmpty()

    fun point(to: Side): MatchScore {
        if (current.isFinished) return current
        history.addLast(current)
        current = current.pointTo(to)
        return current
    }

    /** Devuelve el estado restaurado, o null si no había nada que deshacer. */
    fun undo(): MatchScore? {
        val previous = history.removeLastOrNull() ?: return null
        current = previous
        return previous
    }

    fun reset(rules: ScoreRules = current.rules, firstServer: Side = Side.US) {
        history.clear()
        current = MatchScore.start(rules, firstServer)
    }

    /** Restaura un marcador ya empezado, por ejemplo al recuperar una sesión interrumpida. */
    fun restore(score: MatchScore) {
        history.clear()
        current = score
    }
}
