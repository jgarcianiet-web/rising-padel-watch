import Foundation

/// Backoff exponencial con jitter: 2s, 4s, 8s, 16s, 32s, 60s y a partir de ahí cada 15
/// minutos. El jitter evita que todos los relojes de una liga reintenten a la vez tras
/// una caída del servidor.
public struct RetryPolicy: Sendable {
    private let jitterFraction: Double
    private let randomProvider: @Sendable (ClosedRange<Double>) -> Double
    /// Pasado este tiempo desde el fin de la sesión se deja de reintentar.
    public let maxAgeMs: Int64

    public init(
        jitterFraction: Double = 0.2,
        maxAgeMs: Int64 = 72 * 60 * 60 * 1000,
        randomProvider: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) {
        self.jitterFraction = jitterFraction
        self.maxAgeMs = maxAgeMs
        self.randomProvider = randomProvider
    }

    public func delayMs(attempt: Int) -> Int64 {
        let ladder: [Int64] = [2_000, 4_000, 8_000, 16_000, 32_000, 60_000]
        let base: Int64
        if attempt <= 0 {
            base = ladder[0]
        } else if attempt <= ladder.count {
            base = ladder[attempt - 1]
        } else {
            base = 15 * 60 * 1000
        }
        let jitter = Double(base) * jitterFraction
        guard jitter > 0 else { return base }
        return base + Int64(randomProvider(-jitter...jitter))
    }
}

public struct SyncReport: Equatable, Sendable {
    public var uploaded = 0
    public var retryLater = 0
    public var failed = 0
    public var needsAuth = false
    public var skipped = false

    public var didWork: Bool { uploaded > 0 || retryLater > 0 || failed > 0 }
}

/// Sube al servidor de la liga todas las sesiones pendientes que ya tocan.
///
/// Es idempotente y reentrante: si se ejecuta dos veces a la vez, el `Idempotency-Key`
/// del cliente impide duplicados en el servidor.
public final class SyncQueue {
    private let store: SessionStore
    private let client: LeagueAPIClient
    private let clock: () -> Int64
    private let retryPolicy: RetryPolicy

    private static let maxDelayMs: Int64 = 6 * 60 * 60 * 1000

    public init(
        store: SessionStore,
        client: LeagueAPIClient,
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.store = store
        self.client = client
        self.clock = clock
        self.retryPolicy = retryPolicy
    }

    /// - Parameter config: nil o incompleta (sin liga configurada) ⇒ no se hace nada y
    ///   las sesiones se quedan esperando en local.
    /// - Parameter shareHealth: consentimiento de compartir datos de salud.
    @discardableResult
    public func sync(
        config: LeagueConfig?,
        shareHealth: Bool,
        includeEvents: Bool = true
    ) async -> SyncReport {
        guard let config, config.isUsable else {
            var report = SyncReport()
            report.skipped = true
            return report
        }

        let now = clock()
        let due = store.all()
            .filter { $0.sync.state == .pending }
            .filter { ($0.sync.nextAttemptAtEpochMs ?? 0) <= now }
            .sorted { $0.startedAtEpochMs < $1.startedAtEpochMs }

        var report = SyncReport()
        for session in due {
            // El token está roto: no tiene sentido seguir.
            if report.needsAuth { break }

            if now - session.endedAtEpochMs > retryPolicy.maxAgeMs {
                var expired = session
                expired.sync.state = .failed
                expired.sync.lastAttemptAtEpochMs = now
                expired.sync.lastError = "Caducada: no se pudo sincronizar en 72 h"
                store.upsert(expired)
                report.failed += 1
                continue
            }

            let attempt = session.sync.attempts + 1
            let outcome = await client.upload(
                config: config,
                session: session,
                shareHealth: shareHealth,
                includeEvents: includeEvents
            )
            apply(outcome, to: session, attempt: attempt, now: now, report: &report)
        }
        return report
    }

    private func apply(
        _ outcome: UploadOutcome,
        to session: PadelSession,
        attempt: Int,
        now: Int64,
        report: inout SyncReport
    ) {
        var updated = session
        updated.sync.attempts = attempt
        updated.sync.lastAttemptAtEpochMs = now

        switch outcome {
        case .success(let remoteId, _):
            updated.sync = SyncStatus(
                state: .synced,
                attempts: attempt,
                lastAttemptAtEpochMs: now,
                remoteId: remoteId
            )
            report.uploaded += 1

        case .permanentFailure(_, let message):
            updated.sync.state = .failed
            updated.sync.lastError = message
            report.failed += 1

        case .authFailure(let message):
            updated.sync.state = .needsAuth
            updated.sync.lastError = message
            report.needsAuth = true

        case .rateLimited(let retryAfterSeconds):
            let delay = retryAfterSeconds.map { $0 * 1000 } ?? retryPolicy.delayMs(attempt: attempt)
            updated.sync.state = .pending
            updated.sync.nextAttemptAtEpochMs = now + min(delay, Self.maxDelayMs)
            updated.sync.lastError = "Rate limit"
            report.retryLater += 1

        case .transientFailure(let message):
            updated.sync.state = .pending
            updated.sync.nextAttemptAtEpochMs = now + retryPolicy.delayMs(attempt: attempt)
            updated.sync.lastError = message
            report.retryLater += 1
        }

        store.upsert(updated)
    }

    /// Vuelve a poner en cola una sesión fallada. Lo dispara el usuario desde la UI, o la
    /// app tras reintroducir el token.
    public func requeue(_ sessionId: String) {
        guard var session = store.get(sessionId), session.sync.state != .synced else { return }
        session.sync.state = .pending
        session.sync.nextAttemptAtEpochMs = nil
        session.sync.lastError = nil
        store.upsert(session)
    }

    /// Tras reconectar la liga, todo lo que estaba bloqueado por auth vuelve a la cola.
    public func requeueAllNeedingAuth() {
        for session in store.all() where session.sync.state == .needsAuth {
            requeue(session.sessionId)
        }
    }
}
