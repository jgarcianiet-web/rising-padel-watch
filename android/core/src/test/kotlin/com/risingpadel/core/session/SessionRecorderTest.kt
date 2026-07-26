package com.risingpadel.core.session

import com.risingpadel.core.MotionFixtures
import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionRecorderTest {

    private val source = SourceInfo(Platform.WEAROS, "Pixel Watch 3", "1.0.0")
    private val profile = PlayerProfile(
        hand = Hand.RIGHT,
        watchWrist = Hand.RIGHT,
        maxHeartRate = 180,
        restingHeartRate = 55,
    )

    private fun recorder() = SessionRecorder(
        source = source,
        profile = profile,
        sessionIdProvider = { "test-session" },
    )

    @Test
    fun `acumula golpeos y cierra la sesion`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 1_000_000, monotonicMs = 0)
        (MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400)).forEach { recorder.onMotion(it) }
        val session = recorder.finish(endedAtEpochMs = 1_600_000, monotonicMs = 600_000, shareHealth = true)

        assertEquals("test-session", session.sessionId)
        assertEquals(1, session.totalShots)
        assertEquals(600, session.durationSeconds)
        assertEquals(mapOf(ShotType.FOREHAND to 1), session.shotsByType)
    }

    @Test
    fun `reparte el tiempo en zonas de frecuencia cardiaca`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        // FC máx 180: 100 bpm = 55% (z1), 130 = 72% (z3), 170 = 94% (z5).
        recorder.onHeartRate(100, 0)
        recorder.onHeartRate(130, 10_000)   // 10 s en z1
        recorder.onHeartRate(170, 40_000)   // 30 s en z3
        val session = recorder.finish(60_000, 60_000, shareHealth = true) // 20 s en z5

        val zones = session.health.zones.secondsPerZone
        assertEquals(10, zones["z1"])
        assertEquals(30, zones["z3"])
        assertEquals(20, zones["z5"])
        assertNull(zones["z2"])
    }

    @Test
    fun `la media de frecuencia cardiaca esta ponderada por tiempo`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        recorder.onHeartRate(100, 0)
        recorder.onHeartRate(160, 30_000)  // 30 s a 100 bpm
        val session = recorder.finish(40_000, 40_000, shareHealth = true) // 10 s a 160 bpm

        val hr = assertNotNull(session.health.heartRate)
        // Media simple daría 130; ponderada por tiempo son 115.
        assertEquals(115, hr.meanBpm)
        assertEquals(160, hr.maxBpm)
        assertEquals(55, hr.restingBpm)
    }

    @Test
    fun `sin consentimiento la sesion sale sin datos de salud`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        recorder.onHeartRate(150, 0)
        recorder.onEnergy(activeKcal = 400f)
        recorder.onSteps(5_000)
        (MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400)).forEach { recorder.onMotion(it) }
        val session = recorder.finish(60_000, 60_000, shareHealth = false)

        assertTrue(session.health.isEmpty, "no debe quedar ningún dato de salud")
        assertEquals(1, session.totalShots, "los golpeos sí se conservan")
    }

    @Test
    fun `las metricas acumuladas del workout se sustituyen, no se suman`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        recorder.onEnergy(activeKcal = 100f, totalKcal = 150f)
        recorder.onEnergy(activeKcal = 400f, totalKcal = 520f)
        recorder.onDistance(1_200f)
        recorder.onDistance(3_400f)
        val session = recorder.finish(60_000, 60_000, shareHealth = true)

        assertEquals(400f, session.health.activeEnergyKcal)
        assertEquals(520f, session.health.totalEnergyKcal)
        assertEquals(3_400f, session.health.distanceMeters)
    }

    @Test
    fun `el snapshot en vivo refleja el estado actual`() {
        val recorder = recorder()
        recorder.start(startedAtEpochMs = 0, monotonicMs = 0)
        recorder.onHeartRate(142, 0)
        (MotionFixtures.rest(0, 400) + MotionFixtures.forehand(400)).forEach { recorder.onMotion(it) }

        val snapshot = recorder.liveSnapshot(monotonicMs = 30_000)
        assertEquals(30, snapshot.elapsedSeconds)
        assertEquals(1, snapshot.shotCount)
        assertEquals(142, snapshot.currentHeartRate)
        assertEquals(ShotType.FOREHAND, snapshot.lastShot?.type)
    }

    @Test
    fun `la FC maxima se estima por edad si no se ha configurado`() {
        val porEdad = PlayerProfile(birthYear = 1990)
        assertEquals(184, porEdad.effectiveMaxHeartRate(currentYear = 2026)) // 220 - 36

        val explicita = PlayerProfile(birthYear = 1990, maxHeartRate = 195)
        assertEquals(195, explicita.effectiveMaxHeartRate(currentYear = 2026))

        assertEquals(190, PlayerProfile().effectiveMaxHeartRate(currentYear = 2026))
    }
}
