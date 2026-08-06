package com.risingpadel.core.model

import com.risingpadel.core.liga.LigaMapper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionReviewTest {

    private fun shot(offsetMs: Long, type: ShotType) = Shot(
        offsetMs = offsetMs,
        type = type,
        racketSpeedKmh = 45f,
        impactG = 5f,
        confidence = 0.9f,
        features = ShotFeatures(
            sweptAngleDeg = 200f,
            peakGyroRadS = 19f,
            elevationDeg = 20f,
            axialRotationRadS = 3f,
            swingDurationMs = 300,
        ),
    )

    /** 14 bandejas y 6 derechas contadas por el reloj. */
    private fun sesion(review: SessionReview? = null): PadelSession {
        val shots = (0 until 20).map { i ->
            shot(i * 2 * 60_000L, if (i < 14) ShotType.BANDEJA else ShotType.FOREHAND)
        }
        return PadelSession(
            sessionId = "s1",
            source = SourceInfo(Platform.WEAROS, "Pixel Watch", "1.0"),
            startedAtEpochMs = 1_754_000_000_000,
            endedAtEpochMs = 1_754_000_000_000 + 40 * 60_000L,
            profile = PlayerProfile(),
            shots = shots,
            review = review,
        )
    }

    @Test
    fun `sin revision los recuentos efectivos son los del reloj`() {
        val s = sesion()
        assertEquals(s.shotsByType, s.effectiveShotsByType)
        assertEquals(20, s.effectiveTotalShots)
        assertNull(s.reviewAccuracy)
    }

    @Test
    fun `la correccion manda sobre el reloj y los ceros desaparecen`() {
        val s = sesion(
            SessionReview(
                correctedCounts = mapOf("bandeja" to 12, "forehand" to 0, "smash" to 3),
                reviewedAtEpochMs = 1,
            )
        )
        assertEquals(12, s.effectiveShotsByType[ShotType.BANDEJA])
        assertEquals(3, s.effectiveShotsByType[ShotType.SMASH])
        // Corregir a cero borra el tipo del recuento, no deja un "0 derechas".
        assertTrue(ShotType.FOREHAND !in s.effectiveShotsByType)
        assertEquals(15, s.effectiveTotalShots)
    }

    @Test
    fun `la precision compara tipo a tipo aunque el total coincida`() {
        // El reloj contó 14+6; fueron 12 bandejas, 6 derechas y 2 smashes: total 20 en
        // ambos, pero con 4 golpes mal repartidos → 1 - 4/20 = 0.8.
        val s = sesion(
            SessionReview(
                correctedCounts = mapOf("bandeja" to 12, "smash" to 2),
                reviewedAtEpochMs = 1,
            )
        )
        assertEquals(0.8f, s.reviewAccuracy!!, 0.001f)
    }

    @Test
    fun `la liga y los objetivos leen los recuentos corregidos`() {
        val s = sesion(
            SessionReview(correctedCounts = mapOf("bandeja" to 16), reviewedAtEpochMs = 1)
        )
        val match = LigaMapper.matchFrom(
            s, playerAverage = null,
            objetivos = listOf("Hacer 15 bandejas"),
        )
        // El reloj contó 14 (no llegaba); la corrección a 16 cumple el objetivo.
        assertEquals(listOf(true), match.objetivos)
        assertEquals(16, match.golpesVolumen?.first { it.nombre == "Bandeja" }?.cantidad)
        assertEquals(22, match.totalGolpes)
    }
}
