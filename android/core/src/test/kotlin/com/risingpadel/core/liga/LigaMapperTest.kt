package com.risingpadel.core.liga

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.model.Platform
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.Side
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LigaMapperTest {

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

    private fun sesion(): PadelSession {
        // 16 bandejas y 4 derechas repartidas en 40 minutos, con partido ganado 6-0.
        val shots = (0 until 20).map { i ->
            shot(offsetMs = i * 2 * 60_000L, type = if (i < 16) ShotType.BANDEJA else ShotType.FOREHAND)
        }
        val ganado = (1..24).fold(MatchScore.start()) { s, _ -> s.pointTo(Side.US) }
        return PadelSession(
            sessionId = "s1",
            source = SourceInfo(Platform.WEAROS, "Pixel Watch", "1.0"),
            startedAtEpochMs = 1_754_000_000_000,
            endedAtEpochMs = 1_754_000_000_000 + 40 * 60_000L,
            profile = PlayerProfile(),
            shots = shots,
            score = ganado,
        )
    }

    @Test
    fun `la sesion se convierte en el mismo partido que en iOS`() {
        val match = LigaMapper.matchFrom(sesion(), playerAverage = 3.4f, objetivos = emptyList())

        assertEquals(1_754_000_000_000, match.id)
        assertEquals("competitivo", match.tipo)
        assertEquals("victoria", match.resultado)
        assertTrue(match.sets.startsWith("6-0"))
        assertEquals(20, match.totalGolpes)
        assertEquals(3.4, match.bandMediaJugador)
        // El volumen viaja con el catálogo de la liga, ordenado por cantidad.
        assertEquals("Bandeja", match.golpesVolumen?.first()?.nombre)
        assertEquals(16, match.golpesVolumen?.first()?.cantidad)
        // 40 minutos a 10 por intervalo = 4 cubos.
        assertEquals(4, match.frecuenciaGolpeo?.cuentas?.size)
    }

    @Test
    fun `los objetivos medibles se marcan solos y los demas quedan a mano`() {
        val match = LigaMapper.matchFrom(
            sesion(),
            playerAverage = null,
            objetivos = listOf(
                "Hacer 15 bandejas",              // medible: 16 >= 15 → cumplido
                "Mínimo 10 derechas",             // medible: 4 < 10 → no cumplido
                "Actitud: no protestar ningún punto", // no medible → a mano (false)
            ),
        )
        assertEquals(listOf(true, false, false), match.objetivos)
    }
}
