import XCTest
@testable import PadelCore

final class LeagueDeepLinkTests: XCTestCase {

    private func shot(offsetMs: Int64, type: ShotType) -> Shot {
        Shot(
            offsetMs: offsetMs,
            type: type,
            racketSpeedKmh: 47.5,
            impactG: 6.4,
            confidence: 0.87,
            features: ShotFeatures(sweptAngleDeg: 185, peakGyroRadS: 20, elevationDeg: 10,
                                   axialRotationRadS: 12, swingDurationMs: 200)
        )
    }

    private lazy var session = PadelSession(
        sessionId: "9f1b4c2e-6f7a-4a1e-9c3d-2b5e8a0d7c11",
        source: SourceInfo(platform: .watchos, device: "Apple Watch Series 9", appVersion: "1.0.0"),
        startedAtEpochMs: 1_785_002_652_000,
        endedAtEpochMs: 1_785_008_208_000,
        profile: PlayerProfile(hand: .right, watchWrist: .right, restingHeartRate: 58),
        shots: [
            shot(offsetMs: 18_420, type: .forehand),
            shot(offsetMs: 21_100, type: .backhand),
            shot(offsetMs: 24_800, type: .forehand),
        ],
        health: HealthMetrics(
            heartRate: HeartRateSummary(meanBpm: 132, maxBpm: 171, restingBpm: 58),
            activeEnergyKcal: 806.4,
            steps: 6_114,
            distanceMeters: 3_980.2,
            zones: HeartRateZones(secondsPerZone: ["z2": 1_980])
        ),
        matchRef: nil
    )

    private func datosDecodificados(_ url: URL) throws -> SessionPayload {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        // URLComponents ya devuelve el valor percent-DECODED: es exactamente lo que verá
        // el receptor de la liga tras su decode de la query.
        let datos = try XCTUnwrap(components.queryItems?.first { $0.name == "datos" }?.value)
        return try JSONDecoder().decode(SessionPayload.self, from: Data(datos.utf8))
    }

    func testLaURLLlevaElPayloadDelContratoRoundTrip() throws {
        let url = try XCTUnwrap(LeagueDeepLink.url(for: session, shareHealth: true))
        XCTAssertEqual(url.scheme, "ligapadel")
        XCTAssertEqual(url.host, "importar")

        let payload = try datosDecodificados(url)
        XCTAssertEqual(payload.sessionId, session.sessionId)
        XCTAssertEqual(payload.startedAt, "2026-07-25T18:04:12Z")
        XCTAssertEqual(payload.shots.total, 3)
        XCTAssertEqual(payload.shots.byType, ["forehand": 2, "backhand": 1])
        XCTAssertEqual(payload.health?.heartRate?.meanBpm, 132)
    }

    func testLosEventosGolpeAGolpeNuncaViajanEnLaURL() throws {
        let url = try XCTUnwrap(LeagueDeepLink.url(for: session, shareHealth: true))
        let payload = try datosDecodificados(url)
        XCTAssertTrue(payload.shots.events.isEmpty)
    }

    func testSinConsentimientoLaSaludNoViaja() throws {
        let url = try XCTUnwrap(LeagueDeepLink.url(for: session, shareHealth: false))
        XCTAssertFalse(url.absoluteString.contains("171"), "no debe filtrarse ninguna métrica")
        let payload = try datosDecodificados(url)
        XCTAssertNil(payload.health)
    }

    func testLaQueryNoContieneCaracteresSinEscapar() throws {
        let url = try XCTUnwrap(LeagueDeepLink.url(for: session, shareHealth: true))
        let query = try XCTUnwrap(url.absoluteString.components(separatedBy: "?datos=").last)
        // Solo alfanuméricos y '%': nada del JSON puede romper la URL en el receptor.
        XCTAssertTrue(query.allSatisfy { $0.isLetter || $0.isNumber || $0 == "%" }, query)
    }
}
