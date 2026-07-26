package com.risingpadel.core.score

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScoreBoardTest {

    private val US = Side.US
    private val THEM = Side.THEM

    @Test
    fun `deshacer devuelve exactamente el estado anterior`() {
        val board = ScoreBoard()
        board.point(US)
        val before = board.current
        board.point(THEM)

        assertEquals(before, board.undo())
        assertEquals(before, board.current)
    }

    @Test
    fun `deshacer funciona a traves de un juego cerrado`() {
        val board = ScoreBoard()
        repeat(3) { board.point(US) }
        val atForty = board.current
        assertEquals("40", atForty.pointsLabel(US))

        board.point(US)
        assertEquals(1, board.current.currentSet.us, "el juego se cerró")

        board.undo()
        assertEquals(atForty, board.current, "deshacer reabre el juego")
        assertEquals(0, board.current.currentSet.us)
    }

    @Test
    fun `deshacer funciona a traves de un set cerrado`() {
        val board = ScoreBoard()
        repeat(5) { repeat(4) { board.point(US) } }
        repeat(3) { board.point(US) }
        val beforeSetPoint = board.current
        assertEquals(5, beforeSetPoint.currentSet.us)

        board.point(US)
        assertEquals(1, board.current.completedSets.size, "el set se cerró")

        board.undo()
        assertEquals(beforeSetPoint, board.current, "deshacer reabre el set")
        assertTrue(board.current.completedSets.isEmpty())
    }

    @Test
    fun `deshacer varias veces seguidas retrocede punto a punto`() {
        val board = ScoreBoard()
        val start = board.current
        board.point(US)
        val afterFirst = board.current
        board.point(THEM)
        board.point(US)

        board.undo()
        board.undo()
        assertEquals(afterFirst, board.current)

        board.undo()
        assertEquals(start, board.current)
    }

    @Test
    fun `sin puntos anotados no hay nada que deshacer`() {
        val board = ScoreBoard()
        assertFalse(board.canUndo)
        assertNull(board.undo())
    }

    @Test
    fun `canUndo refleja si queda historial`() {
        val board = ScoreBoard()
        assertFalse(board.canUndo)
        board.point(US)
        assertTrue(board.canUndo)
        board.undo()
        assertFalse(board.canUndo)
    }

    @Test
    fun `un partido terminado no acepta mas puntos ni crece el historial`() {
        val board = ScoreBoard(ScoreRules(setsToWin = 1))
        repeat(6 * 4) { board.point(US) }
        assertEquals(US, board.current.winner)

        val finished = board.current
        board.point(THEM)
        assertEquals(finished, board.current)

        board.undo()
        assertEquals(
            5,
            board.current.currentSet.us,
            "deshacer sobre un partido terminado retrocede el punto que lo cerró",
        )
    }

    @Test
    fun `reset vuelve al principio y limpia el historial`() {
        val board = ScoreBoard()
        repeat(5) { board.point(US) }
        board.reset(firstServer = THEM)

        assertFalse(board.canUndo)
        assertEquals(0, board.current.currentSet.us)
        assertEquals(THEM, board.current.server)
    }

    @Test
    fun `restore recupera un marcador ya empezado`() {
        val board = ScoreBoard()
        board.point(US)
        val saved = board.current

        val other = ScoreBoard()
        other.restore(saved)

        assertEquals(saved, other.current)
        assertFalse(other.canUndo, "un marcador restaurado no arrastra historial ajeno")
    }
}
