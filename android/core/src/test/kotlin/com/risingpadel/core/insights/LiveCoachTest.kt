package com.risingpadel.core.insights

import com.risingpadel.core.model.GameRecord
import com.risingpadel.core.score.Side
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LiveCoachTest {

    private fun juego(server: Side, winner: Side, minuto: Int) =
        GameRecord(offsetMs = minuto * 60_000L, server = server, winner = winner)

    @Test
    fun `con pocos juegos no dice nada`() {
        val games = listOf(
            juego(Side.US, Side.US, 4),
            juego(Side.THEM, Side.THEM, 8),
            juego(Side.US, Side.US, 12),
        )
        assertNull(LiveCoach.tip(games, emptySet()))
    }

    @Test
    fun `tres juegos seguidos perdidos disparan el aviso de racha`() {
        val games = listOf(
            juego(Side.US, Side.US, 4),
            juego(Side.THEM, Side.THEM, 8),
            juego(Side.US, Side.THEM, 12),
            juego(Side.THEM, Side.THEM, 16),
        )
        val tip = LiveCoach.tip(games, emptySet())
        assertTrue(tip!!.text.contains("3 juegos seguidos"))
    }

    @Test
    fun `un aviso ya dado no se repite y con dos juegos por lado no hay veredicto`() {
        val games = listOf(
            juego(Side.US, Side.US, 4),
            juego(Side.THEM, Side.THEM, 8),
            juego(Side.US, Side.THEM, 12),
            juego(Side.THEM, Side.THEM, 16),
        )
        val primero = LiveCoach.tip(games, emptySet())!!
        assertNull(LiveCoach.tip(games, setOf(primero.key)))
    }

    @Test
    fun `un desequilibrio grande entre saque y resto se avisa`() {
        // 3 de 3 con el saque, 0 de 3 al resto: 100% contra 0%.
        val games = listOf(
            juego(Side.US, Side.US, 4),
            juego(Side.THEM, Side.THEM, 8),
            juego(Side.US, Side.US, 12),
            juego(Side.THEM, Side.THEM, 16),
            juego(Side.US, Side.US, 20),
            juego(Side.THEM, Side.THEM, 24),
        )
        // La racha no está activa (el último juego lo perdieron pero alternando).
        val tip = LiveCoach.tip(games, setOf("racha-6"))
        assertEquals("saque-mejor", tip?.key)
        assertTrue(tip!!.text.contains("100%"))
    }

    @Test
    fun `sin diferencia real entre saque y resto hay silencio`() {
        val games = listOf(
            juego(Side.US, Side.US, 4),
            juego(Side.THEM, Side.US, 8),
            juego(Side.US, Side.THEM, 12),
            juego(Side.THEM, Side.THEM, 16),
        )
        assertNull(LiveCoach.tip(games, emptySet()))
    }

    @Test
    fun `sin juegos de un lado no se compara`() {
        // Todos al saque propio: no hay con qué comparar el resto.
        val games = List(5) { juego(Side.US, if (it == 0) Side.THEM else Side.US, it * 4) }
        assertNull(LiveCoach.tip(games, emptySet()))
    }
}
