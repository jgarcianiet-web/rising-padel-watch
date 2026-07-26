package com.risingpadel.core.score

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MatchScoreTest {

    private val US = Side.US
    private val THEM = Side.THEM

    private fun MatchScore.play(vararg sides: Side): MatchScore =
        sides.fold(this) { state, side -> state.pointTo(side) }

    /** Cuatro puntos seguidos ganan un juego desde 0-0 con cualquier reglamento. */
    private fun MatchScore.winGame(side: Side): MatchScore =
        (1..4).fold(this) { state, _ -> state.pointTo(side) }

    private fun MatchScore.winGames(side: Side, count: Int): MatchScore =
        (1..count).fold(this) { state, _ -> state.winGame(side) }

    /** Deja el set en 6-6, listo para tie-break. */
    private fun sixAll(): MatchScore =
        (1..6).fold(MatchScore.start()) { state, _ ->
            state.winGame(US).winGame(THEM)
        }

    // --- puntuación dentro del juego ---

    @Test
    fun `los puntos van 0 15 30 40 y juego`() {
        var score = MatchScore.start()
        assertEquals("0", score.pointsLabel(US))
        score = score.pointTo(US)
        assertEquals("15", score.pointsLabel(US))
        score = score.pointTo(US)
        assertEquals("30", score.pointsLabel(US))
        score = score.pointTo(US)
        assertEquals("40", score.pointsLabel(US))
        score = score.pointTo(US)
        assertEquals(1, score.currentSet.us, "el cuarto punto cierra el juego")
        assertEquals("0", score.pointsLabel(US), "el marcador de juego se reinicia")
    }

    @Test
    fun `con punto de oro el 40-40 lo decide el siguiente punto`() {
        val deuce = MatchScore.start().play(US, US, US, THEM, THEM, THEM)
        assertEquals("40", deuce.pointsLabel(US))
        assertEquals("40", deuce.pointsLabel(THEM))

        val decided = deuce.pointTo(THEM)
        assertEquals(1, decided.currentSet.them, "el punto de oro cierra el juego sin ventaja")
        assertEquals(0, decided.currentSet.us)
    }

    @Test
    fun `sin punto de oro hace falta sacar dos de diferencia`() {
        val rules = ScoreRules(goldenPoint = false)
        val deuce = MatchScore.start(rules).play(US, US, US, THEM, THEM, THEM)

        val advantage = deuce.pointTo(US)
        assertEquals("AD", advantage.pointsLabel(US))
        assertEquals(0, advantage.currentSet.us, "la ventaja todavía no es juego")

        val backToDeuce = advantage.pointTo(THEM)
        assertEquals("40", backToDeuce.pointsLabel(US), "se vuelve a iguales")
        assertEquals("40", backToDeuce.pointsLabel(THEM))

        val game = backToDeuce.play(US, US)
        assertEquals(1, game.currentSet.us, "dos puntos seguidos desde iguales sí ganan el juego")
    }

    @Test
    fun `el saque alterna en cada juego`() {
        val start = MatchScore.start(firstServer = US)
        assertEquals(US, start.server)
        assertEquals(THEM, start.winGame(US).server)
        assertEquals(US, start.winGame(US).winGame(THEM).server)
    }

    // --- sets ---

    @Test
    fun `gana el set a seis juegos con dos de diferencia`() {
        val score = MatchScore.start().winGames(US, 6)
        assertEquals(listOf(SetScore(us = 6, them = 0)), score.completedSets)
        assertEquals(1, score.setsWon(US))
    }

    @Test
    fun `a 6-5 el set sigue en juego`() {
        var score = MatchScore.start()
        repeat(5) { score = score.winGame(US).winGame(THEM) }
        score = score.winGame(US)

        assertEquals(SetScore(us = 6, them = 5), score.currentSet)
        assertTrue(score.completedSets.isEmpty(), "6-5 no cierra el set")
        assertFalse(score.isTieBreak)

        score = score.winGame(US)
        assertEquals(listOf(SetScore(us = 7, them = 5)), score.completedSets, "7-5 sí lo cierra")
    }

    // --- tie-break ---

    @Test
    fun `a 6-6 se juega tie-break y los puntos se cuentan crudos`() {
        val score = sixAll()
        assertTrue(score.isTieBreak)

        val afterPoint = score.pointTo(US)
        assertEquals("1", afterPoint.pointsLabel(US), "en tie-break no hay 15/30/40")
    }

    @Test
    fun `el tie-break se gana a siete con dos de diferencia`() {
        var score = sixAll()
        repeat(6) { score = score.play(US, THEM) }
        assertEquals(6, score.usPoints)
        assertEquals(6, score.themPoints)

        score = score.pointTo(US)
        assertTrue(score.completedSets.isEmpty(), "7-6 no cierra el tie-break")

        score = score.pointTo(US)
        assertEquals(listOf(SetScore(us = 7, them = 6)), score.completedSets, "8-6 sí lo cierra")
    }

    @Test
    fun `en el tie-break saca uno un punto y luego se alterna cada dos`() {
        val start = sixAll()
        val first = start.server
        val servers = (0..5).runningFold(start) { state, _ -> state.pointTo(US) }
            .map { it.server }

        // Punto 1 lo saca quien abre; 2 y 3 el otro; 4 y 5 vuelve el primero.
        assertEquals(first, servers[0])
        assertEquals(first.other, servers[1])
        assertEquals(first.other, servers[2])
        assertEquals(first, servers[3])
        assertEquals(first, servers[4])
    }

    @Test
    fun `quien abre el tie-break resta primero en el set siguiente`() {
        val tieBreak = sixAll()
        val opener = tieBreak.server

        val afterSet = (1..7).fold(tieBreak) { state, _ -> state.pointTo(US) }
        assertEquals(listOf(SetScore(us = 7, them = 6)), afterSet.completedSets)
        assertEquals(opener.other, afterSet.server, "el que abrió el tie-break resta")
    }

    // --- partido ---

    @Test
    fun `gana el partido quien gana dos sets`() {
        val score = MatchScore.start().winGames(US, 12)
        assertEquals(US, score.winner)
        assertTrue(score.isFinished)
        assertEquals(2, score.completedSets.size)
    }

    @Test
    fun `un partido a un set se decide con ese set`() {
        val score = MatchScore.start(ScoreRules(setsToWin = 1)).winGames(US, 6)
        assertEquals(US, score.winner)
    }

    @Test
    fun `con el partido terminado no se anotan mas puntos`() {
        val finished = MatchScore.start().winGames(US, 12)
        assertEquals(finished, finished.pointTo(THEM), "el estado no cambia")
    }

    // --- cambio de pista ---

    @Test
    fun `se cambia de pista tras cada juego impar`() {
        val afterFirst = MatchScore.start().winGame(US)
        assertTrue(afterFirst.changeEndsPending, "tras el juego 1 se cambia")

        val afterSecond = afterFirst.winGame(THEM)
        assertFalse(afterSecond.changeEndsPending, "tras el juego 2 no")

        val afterThird = afterSecond.winGame(US)
        assertTrue(afterThird.changeEndsPending, "tras el juego 3 sí")
    }

    @Test
    fun `el aviso de cambio de pista se apaga al siguiente punto`() {
        val afterGame = MatchScore.start().winGame(US)
        assertTrue(afterGame.changeEndsPending)
        assertFalse(afterGame.pointTo(US).changeEndsPending)
    }

    @Test
    fun `en el tie-break se cambia de pista cada seis puntos`() {
        var score = sixAll()
        repeat(5) { score = score.pointTo(US) }
        assertFalse(score.changeEndsPending, "a los 5 puntos todavía no")

        score = score.pointTo(THEM)
        assertTrue(score.changeEndsPending, "a los 6 puntos sí")
    }

    // --- lectura del marcador ---

    @Test
    fun `allSets incluye el set en juego solo si ya tiene juegos`() {
        assertEquals(listOf(SetScore(0, 0)), MatchScore.start().allSets)

        val midSecondSet = MatchScore.start().winGames(US, 6).winGame(THEM)
        assertEquals(
            listOf(SetScore(us = 6, them = 0), SetScore(us = 0, them = 1)),
            midSecondSet.allSets,
        )
    }

    @Test
    fun `el ganador es nulo mientras el partido sigue`() {
        assertNull(MatchScore.start().winGames(US, 6).winner, "un set no gana el partido")
    }
}
