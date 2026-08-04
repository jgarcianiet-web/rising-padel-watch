package com.risingpadel.core.analytics

import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionAnalyticsTest {

    private val analytics = SessionAnalytics()

    private fun shot(
        offsetMs: Long,
        type: ShotType = ShotType.FOREHAND,
        speedKmh: Float = 45f,
        confidence: Float = 0.9f,
    ) = Shot(
        offsetMs = offsetMs,
        type = type,
        racketSpeedKmh = speedKmh,
        impactG = 5f,
        confidence = confidence,
        features = ShotFeatures(
            sweptAngleDeg = 200f,
            peakGyroRadS = speedKmh / 2.34f,
            elevationDeg = 20f,
            axialRotationRadS = 3f,
            swingDurationMs = 300,
        ),
    )

    private val min = 60_000L

    // --- frecuencia de golpeo ---

    @Test
    fun `reparte los golpeos en su intervalo`() {
        val shots = listOf(shot(1 * min), shot(2 * min), shot(7 * min))

        val buckets = analytics.shotFrequency(shots, durationMs = 10 * min, intervalMs = 5 * min)

        assertEquals(2, buckets.size)
        assertEquals(2, buckets[0].count)
        assertEquals(1, buckets[1].count)
    }

    @Test
    fun `los intervalos vacios tambien salen`() {
        val buckets = analytics.shotFrequency(
            listOf(shot(1 * min)),
            durationMs = 30 * min,
            intervalMs = 10 * min,
        )

        assertEquals(3, buckets.size)
        assertEquals(listOf(1, 0, 0), buckets.map { it.count })
    }

    @Test
    fun `el ultimo intervalo se recorta a la duracion real`() {
        val buckets = analytics.shotFrequency(emptyList(), durationMs = 12 * min, intervalMs = 5 * min)

        assertEquals(3, buckets.size)
        assertEquals(12 * min, buckets.last().endMs)
    }

    @Test
    fun `un offset fuera de rango cuenta en el borde en vez de perderse`() {
        val shots = listOf(shot(-500), shot(99 * min))

        val buckets = analytics.shotFrequency(shots, durationMs = 10 * min, intervalMs = 5 * min)

        assertEquals(1, buckets.first().count)
        assertEquals(1, buckets.last().count)
    }

    @Test
    fun `una sesion sin duracion no tiene intervalos`() {
        assertTrue(analytics.shotFrequency(listOf(shot(0)), durationMs = 0, intervalMs = 5 * min).isEmpty())
    }

    // --- progreso del nivel ---

    @Test
    fun `emite un punto por paso y el ultimo cae en el final real`() {
        // Golpeos repartidos por toda la sesión para que todas las ventanas tengan datos.
        val shots = (0 until 60).map { shot(offsetMs = it * 30_000L) }

        val points = analytics.levelProgression(shots, durationMs = 17 * min, stepMs = 5 * min)

        assertEquals(listOf(5 * min, 10 * min, 15 * min, 17 * min), points.map { it.offsetMs })
    }

    @Test
    fun `un instante sin golpeos en la ventana no emite punto`() {
        // Todos los golpeos en los primeros 5 minutos; la ventana de 15 min los pierde
        // de vista a partir del minuto 20.
        val shots = (0 until 10).map { shot(offsetMs = it * 30_000L) }

        val points = analytics.levelProgression(
            shots,
            durationMs = 40 * min,
            stepMs = 5 * min,
            windowMs = 15 * min,
        )

        assertTrue(points.isNotEmpty())
        assertTrue(points.all { it.offsetMs <= 20 * min })
    }

    @Test
    fun `la ventana deslizante refleja el cambio de calidad`() {
        // Primera mitad floja, segunda mitad fuerte: la curva tiene que subir.
        val weak = (0 until 20).map { shot(offsetMs = it * 30_000L, speedKmh = 32f) }
        val strong = (0 until 20).map { shot(offsetMs = 10 * min + it * 30_000L, speedKmh = 62f) }

        val points = analytics.levelProgression(
            weak + strong,
            durationMs = 20 * min,
            stepMs = 5 * min,
            windowMs = 10 * min,
        )

        assertTrue(points.first().level < points.last().level)
    }

    @Test
    fun `cada punto dice cuantos golpeos lo sostienen`() {
        val shots = (0 until 6).map { shot(offsetMs = it * min) }

        val points = analytics.levelProgression(shots, durationMs = 6 * min, stepMs = 6 * min)

        assertEquals(6, points.single().gradedShots)
    }

    // --- nota por tipo ---

    @Test
    fun `la nota por tipo solo mira ese tipo`() {
        val shots = listOf(
            shot(0, type = ShotType.FOREHAND, speedKmh = 65f),
            shot(min, type = ShotType.BACKHAND, speedKmh = 30f),
        )

        val forehand = analytics.typeGrade(shots, ShotType.FOREHAND)
        assertNotNull(forehand)
        assertEquals(7f, forehand, 0.01f)
    }

    @Test
    fun `sin golpeos de ese tipo la nota es null`() {
        assertNull(analytics.typeGrade(listOf(shot(0)), ShotType.SMASH))
    }

    @Test
    fun `un golpeo con confianza baja no arrastra la nota del tipo`() {
        val shots = listOf(
            shot(0, speedKmh = 65f),
            shot(min, speedKmh = 20f, confidence = 0.1f),
        )

        assertEquals(7f, analytics.typeGrade(shots, ShotType.FOREHAND)!!, 0.01f)
    }
}
