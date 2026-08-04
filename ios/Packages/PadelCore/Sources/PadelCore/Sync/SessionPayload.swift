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
    public let score: ScorePayload?
    public let level: LevelPayload?
}

/// Nivel técnico estimado, en la escala de pádel de 1 a 7.
///
/// Es **derivado**: la liga puede recalcularlo de los golpeos si algún día quiere usar su
/// propia fórmula. Viaja en el payload para que no tenga que hacerlo.
public struct LevelPayload: Codable, Equatable, Sendable {
    public let overall: Float
    public let byShotType: [String: Float]
    /// 0 a 1. En pádel la regularidad es tanto del nivel como la potencia.
    public let consistency: Float
    public let repertoire: Float
    public let gradedShots: Int
    /// false si hubo pocos golpeos: el número está, pero no hay que fiarse de él.
    public let reliable: Bool
}

public struct ScorePayload: Codable, Equatable, Sendable {
    public let rules: ScoreRulesPayload
    public let sets: [SetScorePayload]
    /// "us" | "them", o ausente si el partido no llegó a terminarse.
    public let winner: String?
    public let completed: Bool
}

public struct ScoreRulesPayload: Codable, Equatable, Sendable {
    /// "advantage" | "goldenPoint" | "starPoint".
    public let deuceFormat: String
    public let setsToWin: Int
}

public struct SetScorePayload: Codable, Equatable, Sendable {
    public let us: Int
    public let them: Int
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
            schemaVersion: schemaVersion,
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
            health: shareHealth ? health.toPayload() : nil,
            score: score.map { $0.toPayload() },
            level: level.toPayload()
        )
    }
}

extension SessionLevel {
    /// Sin golpeos puntuables no hay nivel que mandar: se omite en vez de mandar un 1 falso.
    func toPayload() -> LevelPayload? {
        guard gradedShots > 0 else { return nil }
        return LevelPayload(
            overall: round1(overall),
            byShotType: Dictionary(
                uniqueKeysWithValues: byShotType.map { ($0.key.wireName, round1($0.value)) }
            ),
            consistency: round2(consistency),
            repertoire: round2(repertoire),
            gradedShots: gradedShots,
            reliable: reliable
        )
    }
}

extension MatchScore {
    func toPayload() -> ScorePayload {
        ScorePayload(
            rules: ScoreRulesPayload(
                deuceFormat: rules.deuceFormat.wireName,
                setsToWin: rules.setsToWin
            ),
            sets: allSets.map { SetScorePayload(us: $0.us, them: $0.them) },
            winner: winner?.wireName,
            completed: isFinished
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
///
/// Sin pasar por `Int`: en los relojes arm64_32 `Int` es de 32 bits, y aunque los
/// segundos de época caben hoy, dejan de caber en 2038. Con épocas, siempre `Int64`.
func isoUTC(_ epochMs: Int64) -> String {
    let seconds = (Double(epochMs) / 1000).rounded(.down)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: Date(timeIntervalSince1970: seconds))
}

func round1(_ value: Float) -> Float { (value * 10).rounded() / 10 }

func round2(_ value: Float) -> Float { (value * 100).rounded() / 100 }
