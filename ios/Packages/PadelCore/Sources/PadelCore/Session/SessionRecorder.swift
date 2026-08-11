import Foundation

/// Métricas parciales para la pantalla del reloj mientras se juega.
public struct LiveStats: Equatable, Sendable {
    public let elapsedSeconds: Int64
    public let shotCount: Int
    public let currentHeartRate: Int?
    public let activeEnergyKcal: Float?
    public let lastShot: Shot?

    public init(
        elapsedSeconds: Int64,
        shotCount: Int,
        currentHeartRate: Int?,
        activeEnergyKcal: Float?,
        lastShot: Shot?
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.shotCount = shotCount
        self.currentHeartRate = currentHeartRate
        self.activeEnergyKcal = activeEnergyKcal
        self.lastShot = lastShot
    }
}

/// Acumula una sesión en curso: golpeos detectados + métricas de salud del workout.
///
/// Vive en el reloj y es el único punto donde se junta todo. Las apps solo tienen que
/// bombear muestras y métricas; el resultado es una `PadelSession` lista para enviar al
/// iPhone.
///
/// Los tiempos vienen por duplicado a propósito: **epoch** para fechar la sesión y
/// **monótono** para medir dentro de ella (el epoch puede saltar si el reloj se
/// sincroniza a mitad de partido).
public final class SessionRecorder {
    private let source: SourceInfo
    private let profile: PlayerProfile
    private let detector: ShotDetector
    private let maxHeartRate: Int
    private let sessionIdProvider: () -> String

    private var sessionId: String?
    private var startedAtEpochMs: Int64 = 0
    private var startedAtMonotonicMs: Int64 = 0

    private var collectedShots: [Shot] = []

    private var lastHeartRateBpm: Int?
    private var lastHeartRateAtMs: Int64?
    private var maxObservedBpm = 0
    private var weightedBpmSum: Double = 0
    private var weightedSeconds: Double = 0
    private var zoneSeconds: [String: Double] = [:]
    private var heartRateSeries: [HeartRateSample] = []

    private var activeEnergyKcal: Float?
    private var totalEnergyKcal: Float?
    private var steps: Int?
    private var distanceMeters: Float?

    public var matchRef: MatchRef?

    /// Los movimientos que el detector vio y tiró en lo que va de sesión.
    ///
    /// Se expone en vivo y no solo al acabar porque es lo que hace falta para poder
    /// enseñarlo en la ficha de la sesión sin esperar a que termine.
    public var descartes: DescartesDelDetector { detector.descartes }

    private var gameRecords: [GameRecord] = []

    /// Juegos cerrados hasta ahora.
    public var games: [GameRecord] { gameRecords }

    /// Avisa de un cambio del marcador para anotar los juegos que se cierren.
    ///
    /// Se compara antes/después en vez de que el llamante decida: así el reloj solo tiene
    /// que pasar los dos marcadores y la regla de "cuándo se cerró un juego y quién
    /// sacaba" vive en un único sitio, con tests.
    ///
    /// El servidor del juego es el de **antes** del punto: al cerrarse un juego el
    /// marcador ya ha rotado el saque para el siguiente.
    public func onScoreChanged(previous: MatchScore, current: MatchScore, monotonicMs: Int64) {
        let winner: Side
        if current.gamesWon(.us) > previous.gamesWon(.us) {
            winner = .us
        } else if current.gamesWon(.them) > previous.gamesWon(.them) {
            winner = .them
        } else {
            return
        }
        gameRecords.append(GameRecord(
            offsetMs: max(monotonicMs - startedAtMonotonicMs, 0),
            server: previous.server,
            winner: winner
        ))
    }

    /// Marcador del partido, si el jugador lo está llevando. El reloj lo mantiene aparte
    /// del conteo de golpeos: se puede jugar con marcador y sin él, y una sesión sin
    /// marcador sigue siendo una sesión válida.
    public var score: MatchScore?

    public var shots: [Shot] { collectedShots }
    public var isRecording: Bool { sessionId != nil }

    /// Identificador de la sesión en curso, para etiquetar el estado en vivo.
    public var currentSessionId: String? { sessionId }

    public init(
        source: SourceInfo,
        profile: PlayerProfile = PlayerProfile(),
        config: DetectorConfig = .default,
        currentYear: Int = 2026,
        sessionIdProvider: @escaping () -> String = { UUID().uuidString }
    ) {
        self.source = source
        self.profile = profile
        self.detector = ShotDetector(config: config, profile: profile)
        self.maxHeartRate = profile.effectiveMaxHeartRate(currentYear: currentYear)
        self.sessionIdProvider = sessionIdProvider
    }

    public func start(startedAtEpochMs: Int64, monotonicMs: Int64) {
        sessionId = sessionIdProvider()
        self.startedAtEpochMs = startedAtEpochMs
        self.startedAtMonotonicMs = monotonicMs
        collectedShots.removeAll()
        gameRecords.removeAll()
        lastHeartRateBpm = nil
        lastHeartRateAtMs = nil
        maxObservedBpm = 0
        weightedBpmSum = 0
        weightedSeconds = 0
        zoneSeconds.removeAll()
        heartRateSeries.removeAll()
        activeEnergyKcal = nil
        totalEnergyKcal = nil
        steps = nil
        distanceMeters = nil
        detector.reset(referenceTimestampMs: monotonicMs)
    }

    /// Devuelve el golpeo si esta muestra cierra uno, para poder avisar en la UI al instante.
    @discardableResult
    public func onMotion(_ sample: MotionSample) -> Shot? {
        guard let shot = detector.process(sample) else { return nil }
        collectedShots.append(shot)
        return shot
    }

    /// Cada lectura de FC cierra el intervalo anterior: el tiempo transcurrido desde la
    /// lectura previa se atribuye a la zona de **esa** lectura previa, que es la que
    /// estuvo vigente durante el intervalo.
    public func onHeartRate(_ bpm: Int, monotonicMs: Int64) {
        guard bpm > 0 else { return }
        if let previousBpm = lastHeartRateBpm, let previousAt = lastHeartRateAtMs {
            let elapsed = min(max(Double(monotonicMs - previousAt) / 1000, 0), 60)
            if elapsed > 0 {
                let zone = HeartRateZones.zone(for: previousBpm, maxHeartRate: maxHeartRate)
                zoneSeconds[zone, default: 0] += elapsed
                weightedBpmSum += Double(previousBpm) * elapsed
                weightedSeconds += elapsed
            }
        }
        lastHeartRateBpm = bpm
        lastHeartRateAtMs = monotonicMs
        if bpm > maxObservedBpm { maxObservedBpm = bpm }

        // Una lectura por minuto para la serie: suficiente para cruzar pulso con
        // rendimiento y dos órdenes de magnitud menos de datos que guardarlas todas.
        let offset = max(monotonicMs - startedAtMonotonicMs, 0)
        if let last = heartRateSeries.last, offset - last.offsetMs < Self.hrSeriesIntervalMs {
            return
        }
        heartRateSeries.append(HeartRateSample(offsetMs: offset, bpm: bpm))
    }

    private static let hrSeriesIntervalMs: Int64 = 60_000

    /// Valores acumulados del workout; se sustituyen, no se suman.
    public func onEnergy(activeKcal: Float?, totalKcal: Float? = nil) {
        if let activeKcal { activeEnergyKcal = activeKcal }
        if let totalKcal { totalEnergyKcal = totalKcal }
    }

    public func onSteps(_ count: Int) {
        steps = count
    }

    public func onDistance(_ meters: Float) {
        distanceMeters = meters
    }

    /// Cierra la sesión. `shareHealth` es el consentimiento del usuario: si es false, la
    /// sesión sale sin ningún dato de salud (no se recorta después, no se construye).
    public func finish(endedAtEpochMs: Int64, monotonicMs: Int64, shareHealth: Bool) -> PadelSession {
        guard let id = sessionId else {
            preconditionFailure("finish() sin start()")
        }
        if let trailing = detector.flush() {
            collectedShots.append(trailing)
        }
        // Cierra el último intervalo de FC con el instante de fin.
        if let last = lastHeartRateBpm {
            onHeartRate(last, monotonicMs: monotonicMs)
        }

        let session = PadelSession(
            sessionId: id,
            source: source,
            startedAtEpochMs: startedAtEpochMs,
            endedAtEpochMs: endedAtEpochMs,
            profile: profile,
            shots: collectedShots,
            health: shareHealth ? buildHealth() : .empty,
            score: score,
            games: gameRecords,
            matchRef: matchRef,
            // Lo que se le escapó. Se guarda aunque sea cero: un cero es información
            // ("no se dejó nada") y un nulo es "esta sesión es de antes de medirlo".
            descartes: detector.descartes
        )
        sessionId = nil
        return session
    }

    public func liveSnapshot(monotonicMs: Int64) -> LiveStats {
        LiveStats(
            elapsedSeconds: max((monotonicMs - startedAtMonotonicMs) / 1000, 0),
            shotCount: collectedShots.count,
            currentHeartRate: lastHeartRateBpm,
            activeEnergyKcal: activeEnergyKcal,
            lastShot: collectedShots.last
        )
    }

    private func buildHealth() -> HealthMetrics {
        let heartRate: HeartRateSummary? = maxObservedBpm > 0
            ? HeartRateSummary(
                meanBpm: weightedSeconds > 0
                    ? Int((weightedBpmSum / weightedSeconds).rounded())
                    : maxObservedBpm,
                maxBpm: maxObservedBpm,
                restingBpm: profile.restingHeartRate
            )
            : nil

        return HealthMetrics(
            heartRate: heartRate,
            activeEnergyKcal: activeEnergyKcal,
            totalEnergyKcal: totalEnergyKcal,
            steps: steps,
            distanceMeters: distanceMeters,
            zones: HeartRateZones(secondsPerZone: zoneSeconds.mapValues { Int($0.rounded()) }),
            heartRateSeries: heartRateSeries
        )
    }
}
