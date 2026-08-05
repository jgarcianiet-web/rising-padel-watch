package com.risingpadel.core.insights

import com.risingpadel.core.model.GameRecord
import com.risingpadel.core.model.HealthMetrics
import com.risingpadel.core.model.HeartRateSample
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.score.Side
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class InsightEngineTest {

    private val engine = InsightEngine()

    private fun shot(
        offsetMs: Long,
        type: ShotType = ShotType.FOREHAND,
        speedKmh: Float = 45f,
    ) = Shot(
        offsetMs = offsetMs,
        type = type,
        racketSpeedKmh = speedKmh,
        impactG = 6f,
        confidence = 0.9f,
        features = ShotFeatures(200f, speedKmh / 2.34f, 10f, 12f, 300),
    )

    private fun session(
        shots: List<Shot>,
        health: HealthMetrics = HealthMetrics.EMPTY,
        durationMs: Long = 60 * 60_000L,
    ) = PadelSession(
        sessionId = "s1",
        source = SourceInfo(Platform.WATCHOS, "Apple Watch", "1.0.0"),
        startedAtEpochMs = 1_785_002_652_000,
        endedAtEpochMs = 1_785_002_652_000 + durationMs,
        profile = PlayerProfile(),
        shots = shots,
        health = health,
    )

    private fun insight(session: PadelSession, category: InsightCategory) =
        engine.insights(session).firstOrNull { it.category == category }

    // --- saque contra resto ---

    private fun games(vararg pairs: Pair<Side, Side>, everyMs: Long = 120_000L) =
        pairs.mapIndexed { i, (server, winner) ->
            GameRecord(offsetMs = (i + 1) * everyMs, server = server, winner = winner)
        }

    @Test
    fun `compara los juegos ganados sacando y restando`() {
        val shots = (0 until 40).map { shot(it * 20_000L) }
        val recorded = games(
            Side.US to Side.US,
            Side.THEM to Side.THEM,
            Side.US to Side.US,
            Side.THEM to Side.THEM,
            Side.US to Side.US,
            Side.THEM to Side.THEM,
        )

        val idea = engine.insights(session(shots).copy(games = recorded))
            .firstOrNull { "saque" in it.headline }

        assertNotNull(idea)
        assertTrue("3 de 3" in idea.detail, "detalle inesperado: ${idea.detail}")
        assertTrue("0 de 3" in idea.detail)
    }

    @Test
    fun `con pocos juegos no concluye nada del saque`() {
        val shots = (0 until 40).map { shot(it * 20_000L) }
        val recorded = games(Side.US to Side.US, Side.THEM to Side.THEM)

        val ideas = engine.insights(session(shots).copy(games = recorded))

        assertTrue(ideas.none { "saque" in it.headline || "restando" in it.headline })
    }

    @Test
    fun `atribuye cada golpeo al juego en el que se dio`() {
        val recorded = games(
            Side.US to Side.US,
            Side.THEM to Side.THEM,
            everyMs = 100_000L,
        )
        // Uno en el primer juego (saca US) y dos en el segundo (saca THEM).
        val shots = listOf(shot(50_000), shot(150_000), shot(190_000))

        val sacando = engine.shotsWhileServing(session(shots).copy(games = recorded), Side.US)
        val restando = engine.shotsWhileServing(session(shots).copy(games = recorded), Side.THEM)

        assertEquals(1, sacando.size)
        assertEquals(2, restando.size)
    }

    @Test
    fun `los golpeos del juego sin terminar quedan fuera`() {
        val recorded = games(Side.US to Side.US, everyMs = 100_000L)
        val shots = listOf(shot(50_000), shot(500_000))

        val sacando = engine.shotsWhileServing(session(shots).copy(games = recorded), Side.US)

        assertEquals(1, sacando.size, "el golpeo posterior al último juego cerrado no cuenta")
    }

    // --- puntos ---

    @Test
    fun `agrupa los golpeos en puntos por el hueco entre ellos`() {
        val shots = listOf(
            shot(0), shot(1_000), shot(2_000),
            shot(30_000), shot(31_000),
        )

        val rallies = engine.rallies(shots)

        assertEquals(2, rallies.size)
        assertEquals(3, rallies[0].size)
        assertEquals(2, rallies[1].size)
    }

    @Test
    fun `un golpeo suelto es un punto de un golpeo`() {
        assertEquals(1, engine.rallies(listOf(shot(0))).single().size)
    }

    @Test
    fun `sin golpeos no hay puntos`() {
        assertTrue(engine.rallies(emptyList()).isEmpty())
    }

    /**
     * El caso del ejemplo: puntos largos con golpeos mejores que los cortos. La idea
     * tiene que salir con el signo correcto y con los dos números dentro del texto.
     */
    @Test
    fun `detecta que el jugador crece en los puntos largos`() {
        val shots = mutableListOf<Shot>()
        var t = 0L
        // 6 puntos cortos de 3 golpeos flojos.
        repeat(6) {
            repeat(3) { i -> shots += shot(t + i * 1_000L, speedKmh = 33f) }
            t += 30_000
        }
        // 5 puntos largos de 6 golpeos buenos.
        repeat(5) {
            repeat(6) { i -> shots += shot(t + i * 1_000L, speedKmh = 60f) }
            t += 30_000
        }

        val idea = insight(session(shots), InsightCategory.STRENGTHS)

        assertNotNull(idea)
        assertTrue("largos" in idea.headline, "titular inesperado: ${idea.headline}")
        assertTrue("+" in idea.detail, "falta el cambio porcentual: ${idea.detail}")
    }

    @Test
    fun `sin diferencia entre puntos largos y cortos no dice nada`() {
        val shots = mutableListOf<Shot>()
        var t = 0L
        repeat(6) {
            repeat(3) { i -> shots += shot(t + i * 1_000L) }
            t += 30_000
        }
        repeat(5) {
            repeat(6) { i -> shots += shot(t + i * 1_000L) }
            t += 30_000
        }

        val ideas = engine.insights(session(shots))
            .filter { "puntos largos" in it.headline || "largos" in it.headline }

        assertTrue(ideas.isEmpty(), "no debería inventar una diferencia que no existe")
    }

    // --- pulso ---

    @Test
    fun `cruza el pulso con el rendimiento`() {
        val shots = mutableListOf<Shot>()
        // Primera media hora: pulso bajo y buenos golpeos.
        repeat(20) { shots += shot(it * 60_000L, speedKmh = 60f) }
        // Segunda media hora: pulso alto y golpeos flojos.
        repeat(20) { shots += shot(20 * 60_000L + it * 60_000L, speedKmh = 32f) }

        val series = (0 until 20).map { HeartRateSample(it * 60_000L, 120) } +
            (0 until 20).map { HeartRateSample(20 * 60_000L + it * 60_000L, 170) }

        val idea = insight(
            session(shots, HealthMetrics(heartRateSeries = series), durationMs = 40 * 60_000L),
            InsightCategory.MATCH_ANALYSIS,
        )

        assertNotNull(idea)
        assertTrue("pulso" in idea.detail, "debería hablar del pulso: ${idea.detail}")
        assertTrue("ppm" in idea.detail)
    }

    @Test
    fun `sin serie de pulso no se inventa la correlacion`() {
        val shots = (0 until 40).map { shot(it * 60_000L) }

        val ideas = engine.insights(session(shots)).filter { "pulso" in it.detail }

        assertTrue(ideas.isEmpty())
    }

    @Test
    fun `con muy pocas lecturas de pulso no concluye nada`() {
        val shots = (0 until 40).map { shot(it * 60_000L) }
        val series = listOf(HeartRateSample(0, 120), HeartRateSample(60_000, 170))

        val ideas = engine.insights(session(shots, HealthMetrics(heartRateSeries = series)))
            .filter { "pulso" in it.detail }

        assertTrue(ideas.isEmpty())
    }

    // --- mejor y peor golpe ---

    @Test
    fun `senala el golpe fuerte y el flojo`() {
        val shots = (0 until 12).map { shot(it * 20_000L, ShotType.FOREHAND, speedKmh = 62f) } +
            (0 until 12).map { shot(300_000L + it * 20_000L, ShotType.BACKHAND, speedKmh = 30f) }

        val ideas = engine.insights(session(shots))
        val fuerte = ideas.firstOrNull { "golpe fuerte" in it.headline }

        assertNotNull(fuerte)
        assertTrue("derecha" in fuerte.headline, "titular inesperado: ${fuerte.headline}")
        assertTrue("revés" in fuerte.detail.lowercase())
    }

    @Test
    fun `con un solo tipo de golpe no compara`() {
        val shots = (0 until 20).map { shot(it * 20_000L) }

        assertTrue(engine.insights(session(shots)).none { "golpe fuerte" in it.headline })
    }

    // --- entrenamiento ---

    @Test
    fun `propone entrenar el golpe mas flojo`() {
        val shots = (0 until 20).map { shot(it * 20_000L, ShotType.FOREHAND, speedKmh = 60f) } +
            (0 until 10).map { shot(500_000L + it * 20_000L, ShotType.BACKHAND, speedKmh = 29f) }

        val idea = insight(session(shots), InsightCategory.TRAINING)

        assertNotNull(idea)
        assertTrue(idea.evidence > 0, "toda idea lleva su evidencia")
    }

    @Test
    fun `avisa de que falta el juego alto`() {
        val shots = (0 until 70).map { shot(it * 20_000L) }

        val ideas = engine.insights(session(shots))

        assertTrue(ideas.any { "juego alto" in it.headline }, "debería echar en falta los altos")
    }

    @Test
    fun `una sesion vacia no produce ideas`() {
        assertTrue(engine.insights(session(emptyList())).isEmpty())
    }

    @Test
    fun `toda idea lleva evidencia positiva`() {
        val shots = (0 until 40).map { shot(it * 20_000L, ShotType.FOREHAND, speedKmh = 60f) } +
            (0 until 20).map { shot(900_000L + it * 20_000L, ShotType.BACKHAND, speedKmh = 30f) }

        val ideas = engine.insights(session(shots))

        assertTrue(ideas.isNotEmpty())
        assertTrue(ideas.all { it.evidence > 0 })
        assertTrue(ideas.all { it.headline.isNotBlank() && it.detail.isNotBlank() })
    }
}
