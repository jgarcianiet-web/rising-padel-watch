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

    // --- desglose por tipo de golpe ---

    @Test
    fun `el desglose sale ordenado por cantidad, del golpe mas usado al menos usado`() {
        val shots = List(5) { shot(it * min, ShotType.FOREHAND) } +
            List(9) { shot(it * min, ShotType.BACKHAND) } +
            List(2) { shot(it * min, ShotType.SMASH) }

        val desglose = analytics.shotBreakdown(shots)

        assertEquals(listOf(ShotType.BACKHAND, ShotType.FOREHAND, ShotType.SMASH), desglose.map { it.type })
        assertEquals(9, desglose[0].count)
        assertEquals(16, desglose.sumOf { it.count })
    }

    @Test
    fun `los tipos que no se jugaron no aparecen`() {
        val desglose = analytics.shotBreakdown(List(3) { shot(it * min, ShotType.FOREHAND_VOLLEY) })
        assertEquals(1, desglose.size)
        assertEquals(ShotType.FOREHAND_VOLLEY, desglose[0].type)
    }

    @Test
    fun `cada fila trae velocidad media, maxima y su parte del total`() {
        val shots = listOf(
            shot(0, ShotType.FOREHAND, speedKmh = 40f),
            shot(min, ShotType.FOREHAND, speedKmh = 60f),
            shot(2 * min, ShotType.SMASH, speedKmh = 80f),
        )

        val derecha = analytics.shotBreakdown(shots).first { it.type == ShotType.FOREHAND }

        assertEquals(50f, derecha.meanKmh, 0.1f)
        assertEquals(60f, derecha.maxKmh, 0.1f)
        assertEquals(2f / 3f, derecha.share, 0.01f)
    }

    @Test
    fun `golpes calcados son mas regulares que golpes dispares`() {
        val regulares = List(6) { shot(it * min, ShotType.FOREHAND, speedKmh = 50f) }
        val dispares = listOf(30f, 75f, 35f, 80f, 40f, 70f).mapIndexed { i, v ->
            shot(i * min, ShotType.BACKHAND, speedKmh = v)
        }

        val desglose = analytics.shotBreakdown(regulares + dispares)
        val calcada = desglose.first { it.type == ShotType.FOREHAND }.consistency
        val irregular = desglose.first { it.type == ShotType.BACKHAND }.consistency

        assertNotNull(calcada)
        assertNotNull(irregular)
        assertEquals(1f, calcada, 0.01f)
        assertTrue(irregular < calcada, "la derecha calcada debe salir más regular que el revés disparejo")
    }

    @Test
    fun `con un solo golpeo no se inventa regularidad`() {
        val desglose = analytics.shotBreakdown(listOf(shot(0, ShotType.SMASH)))
        assertNull(desglose[0].consistency, "un golpeo suelto no tiene regularidad")
        assertNotNull(desglose[0].grade, "pero sí tiene nota")
    }

    @Test
    fun `un golpe que el detector no supo puntuar no inventa nota`() {
        // Confianza por debajo del mínimo: el estimador no lo puntúa.
        val desglose = analytics.shotBreakdown(
            List(4) { shot(it * min, ShotType.FOREHAND, confidence = 0.1f) }
        )
        assertNull(desglose[0].grade, "sin golpeos puntuados la nota es desconocida, no un 1")
        assertEquals(4, desglose[0].count, "pero los golpeos siguen contando")
    }

    @Test
    fun `los minutos de cada golpeo vienen en orden para poder pintarlos`() {
        val shots = listOf(
            shot(5 * min, ShotType.FOREHAND),
            shot(min, ShotType.FOREHAND),
            shot(3 * min, ShotType.FOREHAND),
        )
        assertEquals(
            listOf(min, 3 * min, 5 * min),
            analytics.shotBreakdown(shots)[0].offsetsMs,
        )
    }

    @Test
    fun `una sesion sin golpeos no tiene desglose`() {
        assertTrue(analytics.shotBreakdown(emptyList()).isEmpty())
    }
}
