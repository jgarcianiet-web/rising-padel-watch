package com.risingpadel.wear.score

import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.ScoreBoard
import com.risingpadel.core.score.ScoreEvent
import com.risingpadel.core.score.ScoreRules
import com.risingpadel.core.score.Side
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Envuelve el [ScoreBoard] del core con estado observable para la UI del reloj.
 *
 * Vive en el contenedor de la aplicación y no en el servicio ni en la Activity: el
 * marcador tiene que sobrevivir a que se apague la pantalla y a que Android recree la
 * Activity, que en un reloj pasa constantemente.
 */
class ScoreSession {

    private var board = ScoreBoard()

    private val _state = MutableStateFlow<MatchScore?>(null)
    val state: StateFlow<MatchScore?> = _state.asStateFlow()

    val isActive: Boolean get() = _state.value != null

    val canUndo: Boolean get() = board.canUndo

    fun start(rules: ScoreRules = ScoreRules.DEFAULT, firstServer: Side = Side.US) {
        board = ScoreBoard(rules, firstServer)
        _state.value = board.current
    }

    fun point(to: Side): ScoreEvent {
        val before = board.current
        val after = board.point(to)
        _state.value = after
        return ScoreEvent.between(before, after)
    }

    fun undo(): ScoreEvent? {
        val restored = board.undo() ?: return null
        _state.value = restored
        return ScoreEvent.UNDO
    }

    /** Cierra el marcador y devuelve el resultado final para adjuntarlo a la sesión. */
    fun finish(): MatchScore? {
        val final = _state.value
        _state.value = null
        return final
    }
}
