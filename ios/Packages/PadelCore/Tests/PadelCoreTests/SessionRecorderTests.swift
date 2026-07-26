import XCTest
@testable import PadelCore

final class SessionRecorderTests: XCTestCase {

    private let source = SourceInfo(platform: .watchos, device: "Apple Watch Series 9", appVersion: "1.0.0")
    private let profile = PlayerProfile(
        hand: .right,
        watchWrist: .right,
        maxHeartRate: 180,
        restingHeartRate: 55
    )

    private func makeRecorder() -> SessionRecorder {
        SessionRecorder(source: source, profile: profile, sessionIdProvider: { "test-session" })
    }

    func testAcumulaGolpeosYCierraLaSesion() {
        let recorder = makeRecorder()
        recorder.start(startedAtEpochMs: 1_000_000, monotonicMs: 0)
        for sample in MotionFixtures.rest(startMs: 0, durationMs: 400)
            + MotionFixtures.forehand(startMs: 400) {
            recorder.onMotion(sample)
        }
        let session = recorder.finish(endedAtEpochMs: 1_600_000, monotonicMs: 600_000, shareHealth: true)

        XCTAssertEqual(session.sessionId, "test-session")
        XCTAssertEqual(session.totalShots, 1)
        XCTAssertEqual(session.durationSeconds, 600)
        XCTAssertEqual(session.shotsByType, [.forehand: 1])
    }

    func testReparteElTiempoEnZonasDeFrecuenciaCardiaca() {
        let recorder = makeRecorder()
        recorder.start(startedAtEpochMs: 0, monotonicMs: 0)
        // FC máx 180: 100 bpm = 55% (z1), 130 = 72% (z3), 170 = 94% (z5).
        recorder.onHeartRate(100, monotonicMs: 0)
        recorder.onHeartRate(130, monotonicMs: 10_000)   // 10 s en z1
        recorder.onHeartRate(170, monotonicMs: 40_000)   // 30 s en z3
        let session = recorder.finish(endedAtEpochMs: 60_000, monotonicMs: 60_000, shareHealth: true)

        let zones = session.health.zones.secondsPerZone
        XCTAssertEqual(zones["z1"], 10)
        XCTAssertEqual(zones["z3"], 30)
        XCTAssertEqual(zones["z5"], 20)  // 20 s hasta el fin
        XCTAssertNil(zones["z2"])
    }

    func testLaMediaDeFrecuenciaCardiacaEstaPonderadaPorTiempo() throws {
        let recorder = makeRecorder()
        recorder.start(startedAtEpochMs: 0, monotonicMs: 0)
        recorder.onHeartRate(100, monotonicMs: 0)
        recorder.onHeartRate(160, monotonicMs: 30_000)  // 30 s a 100 bpm
        let session = recorder.finish(endedAtEpochMs: 40_000, monotonicMs: 40_000, shareHealth: true)

        let hr = try XCTUnwrap(session.health.heartRate)
        // Media simple daría 130; ponderada por tiempo son 115.
        XCTAssertEqual(hr.meanBpm, 115)
        XCTAssertEqual(hr.maxBpm, 160)
        XCTAssertEqual(hr.restingBpm, 55)
    }

    func testSinConsentimientoLaSesionSaleSinDatosDeSalud() {
        let recorder = makeRecorder()
        recorder.start(startedAtEpochMs: 0, monotonicMs: 0)
        recorder.onHeartRate(150, monotonicMs: 0)
        recorder.onEnergy(activeKcal: 400)
        recorder.onSteps(5_000)
        for sample in MotionFixtures.rest(startMs: 0, durationMs: 400)
            + MotionFixtures.forehand(startMs: 400) {
            recorder.onMotion(sample)
        }
        let session = recorder.finish(endedAtEpochMs: 60_000, monotonicMs: 60_000, shareHealth: false)

        XCTAssertTrue(session.health.isEmpty, "no debe quedar ningún dato de salud")
        XCTAssertEqual(session.totalShots, 1, "los golpeos sí se conservan")
    }

    func testLasMetricasAcumuladasSeSustituyenNoSeSuman() {
        let recorder = makeRecorder()
        recorder.start(startedAtEpochMs: 0, monotonicMs: 0)
        recorder.onEnergy(activeKcal: 100, totalKcal: 150)
        recorder.onEnergy(activeKcal: 400, totalKcal: 520)
        recorder.onDistance(1_200)
        recorder.onDistance(3_400)
        let session = recorder.finish(endedAtEpochMs: 60_000, monotonicMs: 60_000, shareHealth: true)

        XCTAssertEqual(session.health.activeEnergyKcal, 400)
        XCTAssertEqual(session.health.totalEnergyKcal, 520)
        XCTAssertEqual(session.health.distanceMeters, 3_400)
    }

    func testElSnapshotEnVivoReflejaElEstadoActual() {
        let recorder = makeRecorder()
        recorder.start(startedAtEpochMs: 0, monotonicMs: 0)
        recorder.onHeartRate(142, monotonicMs: 0)
        for sample in MotionFixtures.rest(startMs: 0, durationMs: 400)
            + MotionFixtures.forehand(startMs: 400) {
            recorder.onMotion(sample)
        }

        let snapshot = recorder.liveSnapshot(monotonicMs: 30_000)
        XCTAssertEqual(snapshot.elapsedSeconds, 30)
        XCTAssertEqual(snapshot.shotCount, 1)
        XCTAssertEqual(snapshot.currentHeartRate, 142)
        XCTAssertEqual(snapshot.lastShot?.type, .forehand)
    }

    func testLaFCMaximaSeEstimaPorEdadSiNoSeHaConfigurado() {
        XCTAssertEqual(PlayerProfile(birthYear: 1990).effectiveMaxHeartRate(currentYear: 2026), 184)
        XCTAssertEqual(
            PlayerProfile(birthYear: 1990, maxHeartRate: 195).effectiveMaxHeartRate(currentYear: 2026),
            195
        )
        XCTAssertEqual(PlayerProfile().effectiveMaxHeartRate(currentYear: 2026), 190)
    }
}
