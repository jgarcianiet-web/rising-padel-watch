package com.risingpadel.core.score

import kotlin.test.Test
import kotlin.test.assertEquals

class ScoreEventTest {

    private val US = Side.US
    private val THEM = Side.THEM

    private fun MatchScore.winGame(side: Side): MatchScore =
        (1..4).fold(this) { state, _ -> state.pointTo(side) }

    @Test
    fun `un punto que no cierra nada es POINT`() {
        val before = MatchScore.start()
        assertEquals(ScoreEvent.POINT, ScoreEvent.between(before, before.pointTo(US)))
    }

    @Test
    fun `el punto que cierra un juego es GAME`() {
        val before = MatchScore.start().pointTo(US).pointTo(US).pointTo(US)
        assertEquals(ScoreEvent.GAME, ScoreEvent.between(before, before.pointTo(US)))
    }

    @Test
    fun `el punto que cierra un set es SET`() {
        var before = MatchScore.start()
        repeat(5) { before = before.winGame(US) }
        repeat(3) { before = before.pointTo(US) }

        assertEquals(ScoreEvent.SET, ScoreEvent.between(before, before.pointTo(US)))
    }

    @Test
    fun `el punto que cierra el partido es MATCH`() {
        var before = MatchScore.start(ScoreRules(setsToWin = 1))
        repeat(5) { before = before.winGame(US) }
        repeat(3) { before = before.pointTo(US) }

        // Cierra set y partido a la vez: manda el partido, que es lo que hay que celebrar.
        assertEquals(ScoreEvent.MATCH, ScoreEvent.between(before, before.pointTo(US)))
    }

    @Test
    fun `un punto del rival tambien puede cerrar juego`() {
        val before = MatchScore.start().pointTo(THEM).pointTo(THEM).pointTo(THEM)
        assertEquals(ScoreEvent.GAME, ScoreEvent.between(before, before.pointTo(THEM)))
    }
}
