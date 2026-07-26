import XCTest
@testable import PadelCore

final class SessionPayloadTests: XCTestCase {

    private func shot(offsetMs: Int64, type: ShotType, speed: Float = 47.55) -> Shot {
        Shot(
            offsetMs: offsetMs,
            type: type,
            racketSpeedKmh: speed,
            impactG: 6.44,
            confidence: 0.876,
            features: ShotFeatures(sweptAngleDeg: 185, peakGyroRadS: 20, elevationDeg: 10,
                                   axialRotationRadS: 12, swingDurationMs: 200)
        )
    }

    private lazy var session = PadelSession(
        sessionId: "9f1b4c2e-6f7a-4a1e-9c3d-2b5e8a0d7c11",
        source: SourceInfo(platform: .watchos, device: "Apple Watch Series 9", appVersion: "1.0.0"),
        // 2026-07-25T18:04:12Z
        startedAtEpochMs: 1_785_002_652_000,
        endedAtEpochMs: 1_785_008_208_000,
        profile: PlayerProfile(hand: .right, watchWrist: .right, restingHeartRate: 58),
        shots: [
            shot(offsetMs: 18_420, type: .forehand),
            shot(offsetMs: 21_100, type: .backhand, speed: 40),
            shot(offsetMs: 24_800, type: .forehand, speed: 55),
        ],
        health: HealthMetrics(
            heartRate: HeartRateSummary(meanBpm: 132, maxBpm: 171, restingBpm: 58),
            activeEnergyKcal: 806.44,
            steps: 6_114,
            distanceMeters: 3_980.2,
            zones: HeartRateZones(secondsPerZone: ["z2": 1_980, "z3": 1_910])
        ),
        matchRef: MatchRef(matchId: "match_8842", leagueId: "liga_2026_a")
    )

    func testLasFechasVanEnISO8601UTC() {
        let payload = session.toPayload(shareHealth: true)
        XCTAssertEqual(payload.startedAt, "2026-07-25T18:04:12Z")
        XCTAssertEqual(payload.endedAt, "2026-07-25T19:36:48Z")
        XCTAssertEqual(payload.durationSeconds, 5_556)
    }

    func testAgregaLosGolpeosPorTipoConLosNombresDelContrato() {
        let payload = session.toPayload(shareHealth: true)
        XCTAssertEqual(payload.shots.total, 3)
        XCTAssertEqual(payload.shots.byType, ["forehand": 2, "backhand": 1])
    }

    func testCalculaLaIntensidadAgregada() throws {
        let intensity = try XCTUnwrap(session.toPayload(shareHealth: true).shots.intensity)
        XCTAssertEqual(intensity.maxRacketSpeedKmh, 55)
        XCTAssertEqual(intensity.meanRacketSpeedKmh, 47.5)
        XCTAssertEqual(intensity.maxImpactG, 6.4)
    }

    func testLosEventosLlevanOffsetRelativoYValoresRedondeados() {
        let events = session.toPayload(shareHealth: true).shots.events
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].offsetMs, 18_420)
        XCTAssertEqual(events[0].type, "forehand")
        XCTAssertEqual(events[0].racketSpeedKmh, 47.6) // 47.55 redondeado a un decimal
        XCTAssertEqual(events[0].confidence, 0.88)
    }

    func testSinConsentimientoElBloqueHealthSeOmiteEntero() throws {
        let payload = session.toPayload(shareHealth: false)
        XCTAssertNil(payload.health)

        let data = try JSONEncoder().encode(payload)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains("health"), "el JSON no debe llevar ni la clave: \(encoded)")
        XCTAssertFalse(encoded.contains("171"), "no debe filtrarse ninguna métrica de salud")
    }

    func testConConsentimientoElBloqueHealthViajaCompleto() throws {
        let health = try XCTUnwrap(session.toPayload(shareHealth: true).health)
        XCTAssertEqual(health.heartRate?.meanBpm, 132)
        XCTAssertEqual(health.heartRate?.maxBpm, 171)
        XCTAssertEqual(health.heartRate?.restingBpm, 58)
        XCTAssertEqual(health.activeEnergyKcal, 806.4)
        XCTAssertEqual(health.steps, 6_114)
        XCTAssertEqual(health.zonesSeconds, ["z2": 1_980, "z3": 1_910])
    }

    func testIncludeEventsFalseDejaSoloLosAgregados() {
        let payload = session.toPayload(shareHealth: true, includeEvents: false)
        XCTAssertTrue(payload.shots.events.isEmpty)
        XCTAssertEqual(payload.shots.total, 3, "los agregados se conservan")
        XCTAssertNotNil(payload.shots.intensity)
    }

    func testElJSONTieneLaFormaDelContrato() throws {
        let data = try JSONEncoder().encode(session.toPayload(shareHealth: true))
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertEqual((root["source"] as? [String: Any])?["platform"] as? String, "watchos")
        XCTAssertEqual((root["player"] as? [String: Any])?["hand"] as? String, "right")
        XCTAssertEqual((root["matchRef"] as? [String: Any])?["matchId"] as? String, "match_8842")
        XCTAssertNotNil((root["shots"] as? [String: Any])?["byType"])
        XCTAssertNotNil((root["health"] as? [String: Any])?["zonesSeconds"])
    }

    func testUnaSesionSinGolpeosNoMandaIntensidad() {
        var vacia = session
        vacia = PadelSession(
            sessionId: vacia.sessionId,
            source: vacia.source,
            startedAtEpochMs: vacia.startedAtEpochMs,
            endedAtEpochMs: vacia.endedAtEpochMs,
            profile: vacia.profile,
            shots: [],
            health: vacia.health,
            matchRef: vacia.matchRef
        )
        let payload = vacia.toPayload(shareHealth: true)
        XCTAssertEqual(payload.shots.total, 0)
        XCTAssertNil(payload.shots.intensity)
    }

    // MARK: Marcador

    private func finishedMatch() -> MatchScore {
        (1...12).reduce(MatchScore.start()) { state, _ in
            (1...4).reduce(state) { inner, _ in inner.pointTo(.us) }
        }
    }

    private func sessionWithScore(_ score: MatchScore?) -> PadelSession {
        PadelSession(
            sessionId: session.sessionId,
            source: session.source,
            startedAtEpochMs: session.startedAtEpochMs,
            endedAtEpochMs: session.endedAtEpochMs,
            profile: session.profile,
            shots: session.shots,
            health: session.health,
            score: score,
            matchRef: session.matchRef
        )
    }

    func testUnaSesionSinMarcadorDeclaraLaVersion1() {
        let payload = session.toPayload(shareHealth: true)
        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertNil(payload.score)
    }

    func testUnaSesionConMarcadorDeclaraLaVersion2() {
        let payload = sessionWithScore(finishedMatch()).toPayload(shareHealth: true)
        // Solo sube de versión cuando lleva marcador: así una liga que solo entiende v1
        // sigue aceptando los entrenos, y en cambio rechaza de forma visible lo que no
        // sabe interpretar en vez de perder el resultado en silencio.
        XCTAssertEqual(payload.schemaVersion, 2)
        XCTAssertNotNil(payload.score)
    }

    func testElMarcadorViajaConSetsGanadorYReglas() throws {
        let payload = sessionWithScore(finishedMatch()).toPayload(shareHealth: true)
        let score = try XCTUnwrap(payload.score)

        XCTAssertEqual(score.sets, [SetScorePayload(us: 6, them: 0), SetScorePayload(us: 6, them: 0)])
        XCTAssertEqual(score.winner, "us")
        XCTAssertTrue(score.completed)
        XCTAssertEqual(score.rules.deuceFormat, "goldenPoint")
        XCTAssertEqual(score.rules.setsToWin, 2)
    }

    func testUnPartidoSinTerminarViajaSinGanador() throws {
        let unfinished = MatchScore.start().pointTo(.us)
        let score = try XCTUnwrap(sessionWithScore(unfinished).toPayload(shareHealth: true).score)

        XCTAssertNil(score.winner)
        XCTAssertFalse(score.completed)
    }

    func testElFormatoDe4040ViajaConSuNombreDelContrato() throws {
        for format in DeuceFormat.allCases {
            let marcador = MatchScore.start(rules: ScoreRules(deuceFormat: format)).pointTo(.us)
            let payload = sessionWithScore(marcador).toPayload(shareHealth: true)
            XCTAssertEqual(try XCTUnwrap(payload.score).rules.deuceFormat, format.wireName)
        }
    }

    func testElMarcadorSeSerializaDentroDelJSONDelContrato() throws {
        let data = try JSONEncoder().encode(
            sessionWithScore(finishedMatch()).toPayload(shareHealth: true)
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let score = try XCTUnwrap(root["score"] as? [String: Any])

        XCTAssertEqual(score["winner"] as? String, "us")
        XCTAssertNotNil(score["sets"])
        XCTAssertNotNil(score["rules"])
    }

    func testLaURLBaseSeComponeBienConYSinBarraFinal() {
        XCTAssertEqual(
            LeagueAPIClient.buildURL("https://liga.example.com/api", "v1/padel-sessions"),
            "https://liga.example.com/api/v1/padel-sessions"
        )
        XCTAssertEqual(
            LeagueAPIClient.buildURL("https://liga.example.com/api/", "/v1/padel-sessions"),
            "https://liga.example.com/api/v1/padel-sessions"
        )
    }
}
