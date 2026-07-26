import Foundation

public enum Platform: String, Codable, Sendable {
    case watchos
    case wearos

    public var wireName: String { rawValue }
}

public struct SourceInfo: Codable, Equatable, Sendable {
    public let platform: Platform
    public let device: String
    public let appVersion: String

    public init(platform: Platform, device: String, appVersion: String) {
        self.platform = platform
        self.device = device
        self.appVersion = appVersion
    }
}

public struct MatchRef: Codable, Equatable, Sendable {
    public let matchId: String
    public let leagueId: String?

    public init(matchId: String, leagueId: String? = nil) {
        self.matchId = matchId
        self.leagueId = leagueId
    }
}

public struct ShotIntensity: Codable, Equatable, Sendable {
    public let meanRacketSpeedKmh: Float
    public let maxRacketSpeedKmh: Float
    public let meanImpactG: Float
    public let maxImpactG: Float

    public static let empty = ShotIntensity(
        meanRacketSpeedKmh: 0, maxRacketSpeedKmh: 0, meanImpactG: 0, maxImpactG: 0
    )

    public init(
        meanRacketSpeedKmh: Float,
        maxRacketSpeedKmh: Float,
        meanImpactG: Float,
        maxImpactG: Float
    ) {
        self.meanRacketSpeedKmh = meanRacketSpeedKmh
        self.maxRacketSpeedKmh = maxRacketSpeedKmh
        self.meanImpactG = meanImpactG
        self.maxImpactG = maxImpactG
    }

    public static func from(_ shots: [Shot]) -> ShotIntensity {
        guard !shots.isEmpty else { return .empty }
        let speeds = shots.map(\.racketSpeedKmh)
        let impacts = shots.map(\.impactG)
        return ShotIntensity(
            meanRacketSpeedKmh: speeds.reduce(0, +) / Float(speeds.count),
            maxRacketSpeedKmh: speeds.max() ?? 0,
            meanImpactG: impacts.reduce(0, +) / Float(impacts.count),
            maxImpactG: impacts.max() ?? 0
        )
    }
}

/// Zonas de FC como % de la máxima: z1 <60, z2 60-70, z3 70-80, z4 80-90, z5 >=90.
public struct HeartRateZones: Codable, Equatable, Sendable {
    public let secondsPerZone: [String: Int]

    public static let empty = HeartRateZones(secondsPerZone: [:])
    public static let zoneKeys = ["z1", "z2", "z3", "z4", "z5"]

    public init(secondsPerZone: [String: Int]) {
        self.secondsPerZone = secondsPerZone
    }

    public static func zone(for bpm: Int, maxHeartRate: Int) -> String {
        let pct = Float(bpm) / Float(maxHeartRate)
        switch pct {
        case ..<0.60: return "z1"
        case ..<0.70: return "z2"
        case ..<0.80: return "z3"
        case ..<0.90: return "z4"
        default: return "z5"
        }
    }
}

public struct HeartRateSummary: Codable, Equatable, Sendable {
    public let meanBpm: Int
    public let maxBpm: Int
    public let restingBpm: Int?

    public init(meanBpm: Int, maxBpm: Int, restingBpm: Int? = nil) {
        self.meanBpm = meanBpm
        self.maxBpm = maxBpm
        self.restingBpm = restingBpm
    }
}

/// Métricas de salud del entrenamiento. Se omiten por completo del payload si el usuario
/// no ha dado el consentimiento de compartir datos de salud.
public struct HealthMetrics: Codable, Equatable, Sendable {
    public let heartRate: HeartRateSummary?
    public let activeEnergyKcal: Float?
    public let totalEnergyKcal: Float?
    public let steps: Int?
    public let distanceMeters: Float?
    public let zones: HeartRateZones

    public static let empty = HealthMetrics()

    public init(
        heartRate: HeartRateSummary? = nil,
        activeEnergyKcal: Float? = nil,
        totalEnergyKcal: Float? = nil,
        steps: Int? = nil,
        distanceMeters: Float? = nil,
        zones: HeartRateZones = .empty
    ) {
        self.heartRate = heartRate
        self.activeEnergyKcal = activeEnergyKcal
        self.totalEnergyKcal = totalEnergyKcal
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.zones = zones
    }

    public var isEmpty: Bool {
        heartRate == nil && activeEnergyKcal == nil && totalEnergyKcal == nil
            && steps == nil && distanceMeters == nil && zones.secondsPerZone.isEmpty
    }
}

/// Estado de sincronización de una sesión con la app de liga.
public enum SyncState: String, Codable, Sendable {
    /// Aún no se ha intentado, o se reintentará.
    case pending
    /// Confirmada por el servidor.
    case synced
    /// Fallo permanente (400/409/versión de esquema): no se reintenta solo.
    case failed
    /// El token no vale: hace falta que el usuario vuelva a conectar la liga.
    case needsAuth
}

public struct SyncStatus: Codable, Equatable, Sendable {
    public var state: SyncState
    public var attempts: Int
    public var lastAttemptAtEpochMs: Int64?
    public var nextAttemptAtEpochMs: Int64?
    public var lastError: String?
    public var remoteId: String?

    public init(
        state: SyncState = .pending,
        attempts: Int = 0,
        lastAttemptAtEpochMs: Int64? = nil,
        nextAttemptAtEpochMs: Int64? = nil,
        lastError: String? = nil,
        remoteId: String? = nil
    ) {
        self.state = state
        self.attempts = attempts
        self.lastAttemptAtEpochMs = lastAttemptAtEpochMs
        self.nextAttemptAtEpochMs = nextAttemptAtEpochMs
        self.lastError = lastError
        self.remoteId = remoteId
    }
}

/// Una sesión de pádel completa, tal y como la construye el reloj.
public struct PadelSession: Codable, Equatable, Identifiable, Sendable {
    public static let schemaVersion = 1

    public let sessionId: String
    public let source: SourceInfo
    public let startedAtEpochMs: Int64
    public let endedAtEpochMs: Int64
    public let profile: PlayerProfile
    public let shots: [Shot]
    public let health: HealthMetrics
    public var matchRef: MatchRef?
    public var sync: SyncStatus

    public var id: String { sessionId }

    public init(
        sessionId: String,
        source: SourceInfo,
        startedAtEpochMs: Int64,
        endedAtEpochMs: Int64,
        profile: PlayerProfile,
        shots: [Shot],
        health: HealthMetrics = .empty,
        matchRef: MatchRef? = nil,
        sync: SyncStatus = SyncStatus()
    ) {
        self.sessionId = sessionId
        self.source = source
        self.startedAtEpochMs = startedAtEpochMs
        self.endedAtEpochMs = endedAtEpochMs
        self.profile = profile
        self.shots = shots
        self.health = health
        self.matchRef = matchRef
        self.sync = sync
    }

    public var durationSeconds: Int64 {
        max((endedAtEpochMs - startedAtEpochMs) / 1000, 0)
    }

    public var totalShots: Int { shots.count }

    public var shotsByType: [ShotType: Int] {
        shots.reduce(into: [:]) { counts, shot in counts[shot.type, default: 0] += 1 }
    }

    public var intensity: ShotIntensity { .from(shots) }

    /// Golpeos por minuto: la métrica más comparable entre sesiones de distinta duración.
    public var shotsPerMinute: Float {
        durationSeconds <= 0 ? 0 : Float(totalShots) * 60 / Float(durationSeconds)
    }
}
