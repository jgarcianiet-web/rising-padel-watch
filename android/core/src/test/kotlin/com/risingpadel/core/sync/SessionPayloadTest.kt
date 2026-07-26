package com.risingpadel.core.sync

import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.HealthMetrics
import com.risingpadel.core.model.HeartRateSummary
import com.risingpadel.core.model.HeartRateZones
import com.risingpadel.core.model.MatchRef
import com.risingpadel.core.model.PadelSession
import com.risingpadel.core.model.Platform
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.model.Shot
import com.risingpadel.core.model.ShotFeatures
import com.risingpadel.core.model.ShotType
import com.risingpadel.core.model.SourceInfo
import com.risingpadel.core.score.MatchScore
import com.risingpadel.core.score.DeuceFormat
import com.risingpadel.core.score.ScoreRules
import com.risingpadel.core.score.Side
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SessionPayloadTest {

    private fun shot(offsetMs: Long, type: ShotType, speed: Float = 47.55f) = Shot(
        offsetMs = offsetMs,
        type = type,
        racketSpeedKmh = speed,
        impactG = 6.44f,
        confidence = 0.876f,
        features = ShotFeatures(185f, 20f, 10f, 12f, 200),
    )

    private val session = PadelSession(
        sessionId = "9f1b4c2e-6f7a-4a1e-9c3d-2b5e8a0d7c11",
        source = SourceInfo(Platform.WATCHOS, "Apple Watch Series 9", "1.0.0"),
        // 2026-07-25T18:04:12Z
        startedAtEpochMs = 1_785_002_652_000,
        endedAtEpochMs = 1_785_008_208_000,
        profile = PlayerProfile(hand = Hand.RIGHT, watchWrist = Hand.RIGHT, restingHeartRate = 58),
        shots = listOf(
            shot(18_420, ShotType.FOREHAND),
            shot(21_100, ShotType.BACKHAND, speed = 40f),
            shot(24_800, ShotType.FOREHAND, speed = 55f),
        ),
        health = HealthMetrics(
            heartRate = HeartRateSummary(meanBpm = 132, maxBpm = 171, restingBpm = 58),
            activeEnergyKcal = 806.44f,
            steps = 6_114,
            distanceMeters = 3_980.2f,
            zones = HeartRateZones(mapOf("z2" to 1_980, "z3" to 1_910)),
        ),
        matchRef = MatchRef(matchId = "match_8842", leagueId = "liga_2026_a"),
    )

    private val json = LeagueApiClient.defaultJson

    @Test
    fun `las fechas van en ISO-8601 UTC`() {
        val payload = session.toPayload(shareHealth = true)
        assertEquals("2026-07-25T18:04:12Z", payload.startedAt)
        assertEquals("2026-07-25T19:36:48Z", payload.endedAt)
        assertEquals(5_556, payload.durationSeconds)
    }

    @Test
    fun `agrega los golpeos por tipo con los nombres del contrato`() {
        val payload = session.toPayload(shareHealth = true)
        assertEquals(3, payload.shots.total)
        assertEquals(mapOf("forehand" to 2, "backhand" to 1), payload.shots.byType)
    }

    @Test
    fun `calcula la intensidad agregada`() {
        val intensity = assertNotNull(session.toPayload(shareHealth = true).shots.intensity)
        assertEquals(55f, intensity.maxRacketSpeedKmh)
        assertEquals(47.5f, intensity.meanRacketSpeedKmh)
        assertEquals(6.4f, intensity.maxImpactG)
    }

    @Test
    fun `los eventos llevan offset relativo y valores redondeados`() {
        val events = session.toPayload(shareHealth = true).shots.events
        assertEquals(3, events.size)
        assertEquals(18_420, events[0].offsetMs)
        assertEquals("forehand", events[0].type)
        assertEquals(47.6f, events[0].racketSpeedKmh) // 47.55 redondeado a un decimal
        assertEquals(0.88f, events[0].confidence)
    }

    @Test
    fun `sin consentimiento el bloque health se omite entero`() {
        val payload = session.toPayload(shareHealth = false)
        assertNull(payload.health)

        val encoded = json.encodeToString(SessionPayload.serializer(), payload)
        assertFalse(encoded.contains("health"), "el JSON no debe llevar ni la clave: $encoded")
        assertFalse(encoded.contains("171"), "no debe filtrarse ninguna métrica de salud")
    }

    @Test
    fun `con consentimiento el bloque health viaja completo`() {
        val health = assertNotNull(session.toPayload(shareHealth = true).health)
        assertEquals(132, health.heartRate?.meanBpm)
        assertEquals(171, health.heartRate?.maxBpm)
        assertEquals(58, health.heartRate?.restingBpm)
        assertEquals(806.4f, health.activeEnergyKcal)
        assertEquals(6_114, health.steps)
        assertEquals(mapOf("z2" to 1_980, "z3" to 1_910), health.zonesSeconds)
    }

    @Test
    fun `includeEvents false deja solo los agregados`() {
        val payload = session.toPayload(shareHealth = true, includeEvents = false)
        assertTrue(payload.shots.events.isEmpty())
        assertEquals(3, payload.shots.total, "los agregados se conservan")
        assertNotNull(payload.shots.intensity)
    }

    @Test
    fun `el JSON tiene la forma del contrato`() {
        val encoded = json.encodeToString(
            SessionPayload.serializer(),
            session.toPayload(shareHealth = true),
        )
        val root = Json.parseToJsonElement(encoded).jsonObject

        assertEquals(1, root["schemaVersion"]?.jsonPrimitive?.content?.toInt())
        assertEquals("watchos", root["source"]?.jsonObject?.get("platform")?.jsonPrimitive?.content)
        assertEquals("right", root["player"]?.jsonObject?.get("hand")?.jsonPrimitive?.content)
        assertEquals("match_8842", root["matchRef"]?.jsonObject?.get("matchId")?.jsonPrimitive?.content)
        assertNotNull(root["shots"]?.jsonObject?.get("byType"))
        assertNotNull(root["health"]?.jsonObject?.get("zonesSeconds"))
    }

    @Test
    fun `una sesion sin golpeos no manda intensidad`() {
        val vacia = session.copy(shots = emptyList())
        val payload = vacia.toPayload(shareHealth = true)
        assertEquals(0, payload.shots.total)
        assertNull(payload.shots.intensity)
    }

    // --- marcador ---

    private fun finishedMatch(): MatchScore =
        (1..12).fold(MatchScore.start()) { state, _ ->
            (1..4).fold(state) { inner, _ -> inner.pointTo(Side.US) }
        }

    @Test
    fun `una sesion sin marcador declara la version 1`() {
        val payload = session.toPayload(shareHealth = true)
        assertEquals(1, payload.schemaVersion)
        assertNull(payload.score)
    }

    @Test
    fun `una sesion con marcador declara la version 2`() {
        val payload = session.copy(score = finishedMatch()).toPayload(shareHealth = true)
        // Solo sube de versión cuando lleva marcador: así una liga que solo entiende v1
        // sigue aceptando los entrenos, y en cambio rechaza de forma visible lo que no
        // sabe interpretar en vez de perder el resultado en silencio.
        assertEquals(2, payload.schemaVersion)
        assertNotNull(payload.score)
    }

    @Test
    fun `el marcador viaja con sets, ganador y reglas`() {
        val payload = session.copy(score = finishedMatch()).toPayload(shareHealth = true)
        val score = assertNotNull(payload.score)

        assertEquals(listOf(SetScorePayload(6, 0), SetScorePayload(6, 0)), score.sets)
        assertEquals("us", score.winner)
        assertTrue(score.completed)
        assertEquals("goldenPoint", score.rules.deuceFormat)
        assertEquals(2, score.rules.setsToWin)
    }

    @Test
    fun `un partido sin terminar viaja sin ganador`() {
        val unfinished = MatchScore.start().pointTo(Side.US)
        val score = assertNotNull(session.copy(score = unfinished).toPayload(shareHealth = true).score)

        assertNull(score.winner)
        assertFalse(score.completed)
    }

    @Test
    fun `el formato de 40-40 viaja con su nombre del contrato`() {
        DeuceFormat.entries.forEach { format ->
            val marcador = MatchScore.start(ScoreRules(deuceFormat = format)).pointTo(Side.US)
            val payload = session.copy(score = marcador).toPayload(shareHealth = true)
            assertEquals(format.wireName, assertNotNull(payload.score).rules.deuceFormat)
        }
    }

    @Test
    fun `el marcador se serializa dentro del JSON del contrato`() {
        val encoded = json.encodeToString(
            SessionPayload.serializer(),
            session.copy(score = finishedMatch()).toPayload(shareHealth = true),
        )
        val score = assertNotNull(Json.parseToJsonElement(encoded).jsonObject["score"]).jsonObject

        assertEquals("us", score["winner"]?.jsonPrimitive?.content)
        assertNotNull(score["sets"])
        assertNotNull(score["rules"])
    }

    @Test
    fun `la URL base se compone bien con y sin barra final`() {
        assertEquals(
            "https://liga.example.com/api/v1/padel-sessions",
            LeagueApiClient.buildUrl("https://liga.example.com/api", "v1/padel-sessions"),
        )
        assertEquals(
            "https://liga.example.com/api/v1/padel-sessions",
            LeagueApiClient.buildUrl("https://liga.example.com/api/", "/v1/padel-sessions"),
        )
    }
}
