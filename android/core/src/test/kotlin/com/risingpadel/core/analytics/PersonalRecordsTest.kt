package com.risingpadel.core.analytics

import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PersonalRecordsTest {

    private fun shot(offsetMs: Long, type: ShotType, speedKmh: Float) = Shot(
        offsetMs = offsetMs,
        type = type,
        racketSpeedKmh = speedKmh,
        impactG = 6f,
        confidence = 0.9f,
        features = ShotFeatures(200f, 19f, 20f, 3f, 300),
    )

    private fun sesion(id: String, empieza: Long, minutos: Long, shots: List<Shot>) =
        PadelSession(
            sessionId = id,
            source = SourceInfo(Platform.WEAROS, "Pixel Watch", "1.0"),
            startedAtEpochMs = empieza,
            endedAtEpochMs = empieza + minutos * 60_000,
            profile = PlayerProfile(),
            shots = shots,
        )

    @Test
    fun `cada record apunta a la sesion correcta`() {
        val corta = sesion(
            "s1", 1_000, 60,
            (0 until 30).map { shot(it * 60_000L, ShotType.FOREHAND, 40f) } +
                shot(1_900_000, ShotType.SMASH, 82f)
        )
        val larga = sesion(
            "s2", 2_000, 90,
            (0 until 200).map { shot(it * 20_000L, ShotType.BANDEJA, 50f) }
        )
        val records = PersonalRecords.from(listOf(corta, larga))

        assertEquals("s1", records.velocidadMax?.sessionId) // el smash a 82
        assertEquals(82f, records.velocidadMax?.valor)
        assertEquals("s2", records.golpeosMax?.sessionId)   // 200 golpeos
        assertEquals("s1", records.smashesMax?.sessionId)
        assertTrue(records.esDe("s1"))
        assertTrue(records.esDe("s2"))
        assertTrue(!records.esDe("s3"))
    }

    @Test
    fun `una sesion corta no puntua como record de ritmo`() {
        // 5 minutos a ritmo altísimo: no vale — el mínimo son 10 minutos.
        val sprint = sesion("s1", 1_000, 5, (0 until 50).map { shot(it * 5_000L, ShotType.FOREHAND, 40f) })
        assertNull(PersonalRecords.from(listOf(sprint)).ritmoMax)
    }
}
