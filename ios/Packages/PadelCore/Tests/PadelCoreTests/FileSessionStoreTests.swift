import XCTest
@testable import PadelCore

final class FileSessionStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("padel-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSession(id: String, startedAtEpochMs: Int64 = 1_000_000) -> PadelSession {
        PadelSession(
            sessionId: id,
            source: SourceInfo(platform: .watchos, device: "Apple Watch Series 9", appVersion: "1.0.0"),
            startedAtEpochMs: startedAtEpochMs,
            endedAtEpochMs: startedAtEpochMs + 600_000,
            profile: PlayerProfile(),
            shots: [
                Shot(offsetMs: 1_000, type: .forehand, racketSpeedKmh: 47.5, impactG: 6.4,
                     confidence: 0.9,
                     features: ShotFeatures(sweptAngleDeg: 185, peakGyroRadS: 20, elevationDeg: 10,
                                            axialRotationRadS: 12, swingDurationMs: 200))
            ],
            health: HealthMetrics(heartRate: HeartRateSummary(meanBpm: 132, maxBpm: 171))
        )
    }

    func testGuardaYRecuperaUnaSesionCompleta() {
        let store = FileSessionStore(directory: directory)
        let original = makeSession(id: "s-1")
        store.upsert(original)

        XCTAssertEqual(store.get("s-1"), original)
    }

    func testSobrescribeAlVolverAGuardarLaMismaSesion() throws {
        let store = FileSessionStore(directory: directory)
        store.upsert(makeSession(id: "s-1"))
        var updated = makeSession(id: "s-1")
        updated.sync.state = .synced
        store.upsert(updated)

        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(try XCTUnwrap(store.get("s-1")).sync.state, .synced)
    }

    func testListaLasSesionesDeMasRecienteAMasAntigua() {
        let store = FileSessionStore(directory: directory)
        store.upsert(makeSession(id: "vieja", startedAtEpochMs: 1_000_000))
        store.upsert(makeSession(id: "nueva", startedAtEpochMs: 9_000_000))

        XCTAssertEqual(store.all().map(\.sessionId), ["nueva", "vieja"])
    }

    func testBorraUnaSesion() {
        let store = FileSessionStore(directory: directory)
        store.upsert(makeSession(id: "s-1"))
        store.delete("s-1")

        XCTAssertNil(store.get("s-1"))
        XCTAssertTrue(store.all().isEmpty)
    }

    func testUnaSesionCorruptaNoSeLlevaPorDelanteElHistorial() throws {
        let store = FileSessionStore(directory: directory)
        store.upsert(makeSession(id: "buena"))
        try "{ esto no es JSON válido".write(
            to: directory.appendingPathComponent("corrupta.session.json"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(store.all().map(\.sessionId), ["buena"])
        XCTAssertNil(store.get("corrupta"))
    }

    func testUnDirectorioInexistenteSeCreaAlVuelo() {
        let nested = directory.appendingPathComponent("a/b/c")
        let store = FileSessionStore(directory: nested)
        store.upsert(makeSession(id: "s-1"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
        XCTAssertEqual(store.all().count, 1)
    }

    func testNoEscribeFueraDelDirectorioAunqueElIdLleveSeparadores() throws {
        let store = FileSessionStore(directory: directory)
        store.upsert(makeSession(id: "../../fuera"))

        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(written, ["______fuera.session.json"])
    }
}
