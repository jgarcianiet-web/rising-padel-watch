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
        val rules = ScoreRules(deuceFormat = DeuceFormat.ADVANTAGE)
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

    // --- star point: dos ventajas y el tercer 40-40 decide ---

    /** Deja el juego en 40-40 (tres puntos cada uno). */
    private fun deuce(rules: ScoreRules): MatchScore =
        MatchScore.start(rules).play(US, US, US, THEM, THEM, THEM)

    @Test
    fun `el star point permite dos ventajas antes de decidir`() {
        val rules = ScoreRules(deuceFormat = DeuceFormat.STAR_POINT)

        // 40-40, primera ventaja, vuelta a 40-40.
        var score = deuce(rules)
        assertFalse(score.isGoldenPoint, "el primer 40-40 no decide")

        score = score.pointTo(US)
        assertEquals("AD", score.pointsLabel(US), "primera ventaja")
        assertEquals(0, score.currentSet.us, "la ventaja no cierra el juego")

        score = score.pointTo(THEM)
        assertEquals("40", score.pointsLabel(US), "vuelta a iguales")
        assertFalse(score.isGoldenPoint, "el segundo 40-40 tampoco decide")

        // Segunda ventaja y vuelta a 40-40: este ya es el decisivo.
        score = score.pointTo(THEM)
        assertEquals("AD", score.pointsLabel(THEM), "segunda ventaja")
        assertEquals(0, score.currentSet.them, "sigue sin cerrar")

        score = score.pointTo(US)
        assertEquals("40", score.pointsLabel(US))
        assertTrue(score.isGoldenPoint, "el tercer 40-40 sí es punto de oro")

        score = score.pointTo(US)
        assertEquals(1, score.currentSet.us, "el punto decisivo cierra el juego")
    }

    @Test
    fun `con star point una ventaja convertida gana el juego como siempre`() {
        val rules = ScoreRules(deuceFormat = DeuceFormat.STAR_POINT)
        val game = deuce(rules).play(US, US)
        assertEquals(1, game.currentSet.us, "ventaja y punto siguiente: juego")
    }

    @Test
    fun `el punto de oro marca el 40-40 como decisivo desde el primero`() {
        val golden = deuce(ScoreRules(deuceFormat = DeuceFormat.GOLDEN_POINT))
        assertTrue(golden.isGoldenPoint)
    }

    @Test
    fun `con ventajas clasicas ningun 40-40 es decisivo`() {
        var score = deuce(ScoreRules(deuceFormat = DeuceFormat.ADVANTAGE))
        repeat(6) {
            assertFalse(score.isGoldenPoint, "con ventajas nunca hay punto decisivo")
            score = score.pointTo(US).pointTo(THEM)
        }
        assertEquals(0, score.currentSet.us, "el juego sigue abierto tras seis iguales")
    }

    @Test
    fun `un juego sin llegar a iguales no es punto decisivo en ningun formato`() {
        DeuceFormat.entries.forEach { format ->
            val score = MatchScore.start(ScoreRules(deuceFormat = format))
                .play(US, US, US, THEM)
            assertFalse(score.isGoldenPoint, "40-15 no es punto decisivo con $format")
        }
    }

    @Test
    fun `el tie-break nunca es punto de oro`() {
        DeuceFormat.entries.forEach { format ->
            var score = MatchScore.start(ScoreRules(deuceFormat = format))
            repeat(6) { score = score.winGame(US).winGame(THEM) }
            repeat(4) { score = score.pointTo(US).pointTo(THEM) }

            assertTrue(score.isTieBreak, "debería estar en tie-break con $format")
            assertFalse(score.isGoldenPoint, "el tie-break tiene sus propias reglas ($format)")
        }
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
