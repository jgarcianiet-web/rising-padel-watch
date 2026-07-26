import XCTest
@testable import PadelCore

/// Transporte falso: guarda lo que se le pide y devuelve respuestas programadas.
private final class FakeTransport: HTTPTransport, @unchecked Sendable {
    enum Programmed {
        case response(HTTPResponse)
        case networkError
    }

    struct Request: Equatable {
        let method: String
        let url: String
        let headers: [String: String]
        let body: String?
    }

    private var programmed: [Programmed] = []
    private(set) var requests: [Request] = []

    func enqueue(_ response: HTTPResponse) {
        programmed.append(.response(response))
    }

    func enqueueNetworkError() {
        programmed.append(.networkError)
    }

    func request(
        method: String,
        url: String,
        headers: [String: String],
        body: String?
    ) async throws -> HTTPResponse {
        requests.append(Request(method: method, url: url, headers: headers, body: body))
        let next = programmed.isEmpty ? Programmed.response(FakeTransport.ok()) : programmed.removeFirst()
        switch next {
        case .response(let response): return response
        case .networkError: throw HTTPTransportError("sin red")
        }
    }

    static func ok(id: String = "psession_1", code: Int = 201) -> HTTPResponse {
        HTTPResponse(code: code, body: #"{"id":"\#(id)","sessionId":"s"}"#)
    }
}

final class SyncQueueTests: XCTestCase {

    private let config = LeagueConfig(baseURL: "https://liga.example.com/api", token: "tok_123")

    private func makeSession(
        id: String = "s-1",
        startedAtEpochMs: Int64 = 1_000_000,
        endedAtEpochMs: Int64 = 1_600_000
    ) -> PadelSession {
        PadelSession(
            sessionId: id,
            source: SourceInfo(platform: .watchos, device: "Apple Watch Series 9", appVersion: "1.0.0"),
            startedAtEpochMs: startedAtEpochMs,
            endedAtEpochMs: endedAtEpochMs,
            profile: PlayerProfile(hand: .right, watchWrist: .right),
            shots: [
                Shot(
                    offsetMs: 1_000, type: .forehand, racketSpeedKmh: 47.5, impactG: 6.4,
                    confidence: 0.9,
                    features: ShotFeatures(sweptAngleDeg: 185, peakGyroRadS: 20, elevationDeg: 10,
                                           axialRotationRadS: 12, swingDurationMs: 200)
                )
            ],
            health: HealthMetrics(heartRate: HeartRateSummary(meanBpm: 132, maxBpm: 171))
        )
    }

    private func makeQueue(
        store: SessionStore,
        transport: FakeTransport,
        now: Int64 = 2_000_000
    ) -> SyncQueue {
        SyncQueue(
            store: store,
            client: LeagueAPIClient(transport: transport),
            clock: { now },
            retryPolicy: RetryPolicy(jitterFraction: 0, randomProvider: { _ in 0 })
        )
    }

    func testSubeUnaSesionPendienteYLaMarcaComoSincronizada() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueue(FakeTransport.ok())

        let report = await makeQueue(store: store, transport: transport)
            .sync(config: config, shareHealth: true)

        XCTAssertEqual(report.uploaded, 1)
        let stored = try XCTUnwrap(store.get("s-1"))
        XCTAssertEqual(stored.sync.state, .synced)
        XCTAssertEqual(stored.sync.remoteId, "psession_1")
    }

    func testMandaLaClaveDeIdempotenciaYElToken() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueue(FakeTransport.ok())

        await makeQueue(store: store, transport: transport).sync(config: config, shareHealth: true)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://liga.example.com/api/v1/padel-sessions")
        XCTAssertEqual(request.headers["Idempotency-Key"], "s-1")
        XCTAssertEqual(request.headers["Authorization"], "Bearer tok_123")
    }

    func testSinLigaConfiguradaNoSeIntentaNada() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()

        let report = await makeQueue(store: store, transport: transport)
            .sync(config: nil, shareHealth: true)

        XCTAssertTrue(report.skipped)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(try XCTUnwrap(store.get("s-1")).sync.state, .pending)
    }

    func testUnFalloDeRedDejaLaSesionPendienteConReintentoProgramado() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueueNetworkError()

        let report = await makeQueue(store: store, transport: transport, now: 2_000_000)
            .sync(config: config, shareHealth: true)

        XCTAssertEqual(report.retryLater, 1)
        let stored = try XCTUnwrap(store.get("s-1"))
        XCTAssertEqual(stored.sync.state, .pending)
        XCTAssertEqual(stored.sync.attempts, 1)
        XCTAssertEqual(stored.sync.nextAttemptAtEpochMs, 2_000_000 + 2_000)
    }

    func testNoReintentaAntesDeLaHoraProgramada() async {
        var session = makeSession()
        session.sync.nextAttemptAtEpochMs = 5_000_000
        let store = InMemorySessionStore([session])
        let transport = FakeTransport()

        let report = await makeQueue(store: store, transport: transport, now: 2_000_000)
            .sync(config: config, shareHealth: true)

        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(report.uploaded, 0)
    }

    func testUn400EsFalloPermanenteYNoSeReintenta() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueue(HTTPResponse(
            code: 400,
            body: #"{"error":{"code":"invalid_payload","message":"shots.total inválido"}}"#
        ))

        let report = await makeQueue(store: store, transport: transport)
            .sync(config: config, shareHealth: true)

        XCTAssertEqual(report.failed, 1)
        let stored = try XCTUnwrap(store.get("s-1"))
        XCTAssertEqual(stored.sync.state, .failed)
        XCTAssertEqual(stored.sync.lastError, "shots.total inválido")
        XCTAssertNil(stored.sync.nextAttemptAtEpochMs)
    }

    func testUn401CortaLaColaEnteraYPideReautenticacion() async throws {
        let store = InMemorySessionStore([
            makeSession(id: "s-1", startedAtEpochMs: 1_000_000, endedAtEpochMs: 1_100_000),
            makeSession(id: "s-2", startedAtEpochMs: 1_500_000, endedAtEpochMs: 1_600_000),
        ])
        let transport = FakeTransport()
        transport.enqueue(HTTPResponse(
            code: 401,
            body: #"{"error":{"code":"unauthorized","message":"token caducado"}}"#
        ))

        let report = await makeQueue(store: store, transport: transport)
            .sync(config: config, shareHealth: true)

        XCTAssertTrue(report.needsAuth)
        XCTAssertEqual(transport.requests.count, 1, "no debe seguir intentando con un token roto")
        XCTAssertEqual(try XCTUnwrap(store.get("s-1")).sync.state, .needsAuth)
        XCTAssertEqual(try XCTUnwrap(store.get("s-2")).sync.state, .pending)
    }

    func testUn429RespetaRetryAfter() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueue(HTTPResponse(code: 429, body: "", headers: ["Retry-After": "120"]))

        await makeQueue(store: store, transport: transport, now: 2_000_000)
            .sync(config: config, shareHealth: true)

        let stored = try XCTUnwrap(store.get("s-1"))
        XCTAssertEqual(stored.sync.state, .pending)
        XCTAssertEqual(stored.sync.nextAttemptAtEpochMs, 2_000_000 + 120_000)
    }

    func testUn413ReintentaSinLaSerieDeGolpeos() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueue(HTTPResponse(code: 413, body: ""))
        transport.enqueue(FakeTransport.ok())

        let report = await makeQueue(store: store, transport: transport)
            .sync(config: config, shareHealth: true)

        XCTAssertEqual(report.uploaded, 1)
        XCTAssertEqual(transport.requests.count, 2)
        let first = try XCTUnwrap(transport.requests[0].body)
        let second = try XCTUnwrap(transport.requests[1].body)
        XCTAssertTrue(first.contains("\"offsetMs\""))
        XCTAssertFalse(second.contains("\"offsetMs\""),
                       "el reintento debe ir sin eventos: \(second)")
    }

    func testUnaSesionMasViejaQue72HorasSeDaPorPerdida() async throws {
        let store = InMemorySessionStore([makeSession(endedAtEpochMs: 0)])
        let transport = FakeTransport()

        let report = await makeQueue(store: store, transport: transport, now: 80 * 60 * 60 * 1000)
            .sync(config: config, shareHealth: true)

        XCTAssertEqual(report.failed, 1)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(try XCTUnwrap(store.get("s-1")).sync.state, .failed)
    }

    func testSubeLasSesionesMasAntiguasPrimero() async {
        let store = InMemorySessionStore([
            makeSession(id: "nueva", startedAtEpochMs: 1_900_000, endedAtEpochMs: 1_950_000),
            makeSession(id: "vieja", startedAtEpochMs: 1_000_000, endedAtEpochMs: 1_100_000),
        ])
        let transport = FakeTransport()
        transport.enqueue(FakeTransport.ok())
        transport.enqueue(FakeTransport.ok())

        await makeQueue(store: store, transport: transport).sync(config: config, shareHealth: true)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].headers["Idempotency-Key"], "vieja")
        XCTAssertEqual(transport.requests[1].headers["Idempotency-Key"], "nueva")
    }

    func testRequeueDevuelveALaColaUnaSesionFallada() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueue(HTTPResponse(code: 400, body: ""))
        let queue = makeQueue(store: store, transport: transport)

        await queue.sync(config: config, shareHealth: true)
        XCTAssertEqual(try XCTUnwrap(store.get("s-1")).sync.state, .failed)

        queue.requeue("s-1")
        let stored = try XCTUnwrap(store.get("s-1"))
        XCTAssertEqual(stored.sync.state, .pending)
        XCTAssertNil(stored.sync.nextAttemptAtEpochMs)
    }

    func testRequeueNoTocaUnaSesionYaSincronizada() async throws {
        let store = InMemorySessionStore([makeSession()])
        let transport = FakeTransport()
        transport.enqueue(FakeTransport.ok())
        let queue = makeQueue(store: store, transport: transport)

        await queue.sync(config: config, shareHealth: true)
        queue.requeue("s-1")

        XCTAssertEqual(try XCTUnwrap(store.get("s-1")).sync.state, .synced)
    }

    func testElBackoffCreceConLosIntentos() {
        let policy = RetryPolicy(jitterFraction: 0, randomProvider: { _ in 0 })
        XCTAssertEqual(policy.delayMs(attempt: 1), 2_000)
        XCTAssertEqual(policy.delayMs(attempt: 2), 4_000)
        XCTAssertEqual(policy.delayMs(attempt: 3), 8_000)
        XCTAssertEqual(policy.delayMs(attempt: 6), 60_000)
        XCTAssertEqual(policy.delayMs(attempt: 7), 15 * 60_000)
        XCTAssertEqual(policy.delayMs(attempt: 30), 15 * 60_000)
    }
}
