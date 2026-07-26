import Foundation

// DTOs del contrato con la app de liga (`docs/api-contract.md`).
//
// Están separados del modelo de dominio a propósito: el modelo puede evolucionar sin
// romper el contrato, y el contrato puede versionarse sin contaminar el dominio.

public struct SessionPayload: Codable, Equatable, Sendable {
    public let sessionId: String
    public let schemaVersion: Int
    public let source: SourcePayload
    public let startedAt: String
    public let endedAt: String
    public let durationSeconds: Int64
    public let player: PlayerPayload?
    public let matchRef: MatchRefPayload?
    public let shots: ShotsPayload
    public let health: HealthPayload?
}

public struct SourcePayload: Codable, Equatable, Sendable {
    public let platform: String
    public let device: String
    public let appVersion: String
}

public struct PlayerPayload: Codable, Equatable, Sendable {
    public let hand: String
    public let watchWrist: String
}

public struct MatchRefPayload: Codable, Equatable, Sendable {
    public let matchId: String
    public let leagueId: String?
}

public struct ShotsPayload: Codable, Equatable, Sendable {
    public let total: Int
    public let byType: [String: Int]
    public let intensity: IntensityPayload?
    public let events: [ShotEventPayload]
}

public struct IntensityPayload: Codable, Equatable, Sendable {
    public let meanRacketSpeedKmh: Float
    public let maxRacketSpeedKmh: Float
    public let meanImpactG: Float
    public let maxImpactG: Float
}

public struct ShotEventPayload: Codable, Equatable, Sendable {
    public let offsetMs: Int64
    public let type: String
    public let racketSpeedKmh: Float
    public let impactG: Float
    public let confidence: Float
}

public struct HealthPayload: Codable, Equatable, Sendable {
    public let heartRate: HeartRatePayload?
    public let activeEnergyKcal: Float?
    public let totalEnergyKcal: Float?
    public let steps: Int?
    public let distanceMeters: Float?
    public let zonesSeconds: [String: Int]?
}

public struct HeartRatePayload: Codable, Equatable, Sendable {
    public let meanBpm: Int
    public let maxBpm: Int
    public let restingBpm: Int?
}

public struct SessionRefResponse: Codable, Sendable {
    public let id: String
    public let sessionId: String?
    public let createdAt: String?
    public let matchRef: MatchRefPayload?
}

public struct APIErrorResponse: Codable, Sendable {
    public let error: APIErrorBody?
}

public struct APIErrorBody: Codable, Sendable {
    public let code: String?
    public let message: String?
}

public struct MatchesResponse: Codable, Sendable {
    public let matches: [MatchSummary]
}

public struct MatchSummary: Codable, Equatable, Sendable, Identifiable {
    public let matchId: String
    public let leagueId: String?
    public let scheduledAt: String?
    public let opponents: String?
    public let venue: String?

    public var id: String { matchId }
}

extension PadelSession {
    /// Convierte la sesión al payload del contrato.
    ///
    /// - Parameter shareHealth: consentimiento del usuario. Si es false el bloque
    ///   `health` no se incluye en absoluto (no se manda vacío: se omite).
    /// - Parameter includeEvents: si es false solo se suben los agregados. Se usa para
    ///   reintentar una sesión que el servidor rechazó por tamaño.
    public func toPayload(shareHealth: Bool, includeEvents: Bool = true) -> SessionPayload {
        SessionPayload(
            sessionId: sessionId,
            schemaVersion: PadelSession.schemaVersion,
            source: SourcePayload(
                platform: source.platform.wireName,
                device: source.device,
                appVersion: source.appVersion
            ),
            startedAt: isoUTC(startedAtEpochMs),
            endedAt: isoUTC(endedAtEpochMs),
            durationSeconds: durationSeconds,
            player: PlayerPayload(
                hand: profile.hand.wireName,
                watchWrist: profile.watchWrist.wireName
            ),
            matchRef: matchRef.map { MatchRefPayload(matchId: $0.matchId, leagueId: $0.leagueId) },
            shots: ShotsPayload(
                total: totalShots,
                byType: shotsByType.reduce(into: [String: Int]()) { result, entry in
                    result[entry.key.wireName] = entry.value
                },
                intensity: shots.isEmpty ? nil : IntensityPayload(
                    meanRacketSpeedKmh: round1(intensity.meanRacketSpeedKmh),
                    maxRacketSpeedKmh: round1(intensity.maxRacketSpeedKmh),
                    meanImpactG: round1(intensity.meanImpactG),
                    maxImpactG: round1(intensity.maxImpactG)
                ),
                events: includeEvents
                    ? shots.map { shot in
                        ShotEventPayload(
                            offsetMs: shot.offsetMs,
                            type: shot.type.wireName,
                            racketSpeedKmh: round1(shot.racketSpeedKmh),
                            impactG: round1(shot.impactG),
                            confidence: round2(shot.confidence)
                        )
                    }
                    : []
            ),
            health: shareHealth ? health.toPayload() : nil
        )
    }
}

extension HealthMetrics {
    func toPayload() -> HealthPayload? {
        guard !isEmpty else { return nil }
        return HealthPayload(
            heartRate: heartRate.map {
                HeartRatePayload(meanBpm: $0.meanBpm, maxBpm: $0.maxBpm, restingBpm: $0.restingBpm)
            },
            activeEnergyKcal: activeEnergyKcal.map(round1),
            totalEnergyKcal: totalEnergyKcal.map(round1),
            steps: steps,
            distanceMeters: distanceMeters.map(round1),
            zonesSeconds: zones.secondsPerZone.isEmpty ? nil : zones.secondsPerZone
        )
    }
}

/// ISO-8601 UTC truncado a segundos: `2026-07-25T18:04:12Z`.
func isoUTC(_ epochMs: Int64) -> String {
    let seconds = Int(floor(Double(epochMs) / 1000))
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
}

func round1(_ value: Float) -> Float { (value * 10).rounded() / 10 }

func round2(_ value: Float) -> Float { (value * 100).rounded() / 100 }
