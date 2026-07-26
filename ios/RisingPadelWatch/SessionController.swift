import Foundation
import PadelCore
import SwiftUI
import WatchKit

enum SessionStatus: Equatable {
    case idle
    case preparing
    case recording
    case saving
    case saved
    case error(String)
}

/// Orquesta la sesión en el reloj: workout + sensores + detección + envío al iPhone.
///
/// Es `@MainActor` porque es el estado que pinta la UI. El trabajo pesado (CoreMotion,
/// HealthKit) llega desde otras colas y se reencola aquí, así que la detección nunca
/// bloquea el render.
@MainActor
final class SessionController: ObservableObject {

    @Published private(set) var status: SessionStatus = .idle
    @Published private(set) var elapsedSeconds: Int64 = 0
    @Published private(set) var shotCount = 0
    @Published private(set) var heartRateBpm: Int?
    @Published private(set) var lastShotType: ShotType?
    @Published private(set) var statusMessage: String?
    /// Marcador en curso, o nil si se juega sin llevarlo.
    @Published private(set) var score: MatchScore?

    @AppStorage("shareHealth") private var shareHealth = false
    @AppStorage("playerHand") private var playerHandRaw = Hand.right.rawValue
    @AppStorage("watchWrist") private var watchWristRaw = Hand.right.rawValue
    @AppStorage("sensitivity") private var sensitivityRaw = Sensitivity.medium.rawValue
    @AppStorage("trackScore") private var trackScore = false
    @AppStorage("deuceFormat") private var deuceFormatRaw = DeuceFormat.goldenPoint.rawValue
    @AppStorage("setsToWin") private var setsToWin = 2
    @AppStorage("collectTrainingData") var collectTrainingData = false
    @AppStorage("playerAlias") private var playerAlias = "anon"

    private let motionRecorder = MotionRecorder()
    private let workoutManager = WorkoutManager()
    private let transport = PhoneTransport()

    private var recorder: SessionRecorder?
    private var ticker: Timer?
    private var scoreBoard: ScoreBoard?

    // --- modo de recogida de datos ---

    /// Los datos se quedan en el reloj hasta que el usuario los envía al iPhone a
    /// propósito, y no se suben nunca a la liga. Ver `docs/training-data.md`.
    private lazy var trainingStore = TrainingSampleStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("training/muestras.jsonl")
    )
    private var trainingRecorder: TrainingRecorder?

    @Published var trainingLabel: ShotType = .forehand
    @Published private(set) var trainingRecording = false
    @Published private(set) var trainingCapturedInBatch = 0
    @Published private(set) var trainingTotalStored = 0
    @Published private(set) var trainingStoredKB = 0

    var profile: PlayerProfile {
        PlayerProfile(
            hand: Hand(rawValue: playerHandRaw) ?? .right,
            watchWrist: Hand(rawValue: watchWristRaw) ?? .right
        )
    }

    var wrongWristWarning: Bool { !profile.watchOnRacketArm }

    init() {
        transport.activate()
        refreshTrainingCounts()
    }

    // MARK: Modo de recogida de datos

    func startTraining() async {
        guard motionRecorder.isAvailable, !trainingRecording else { return }

        let recorder = TrainingRecorder(
            source: SourceInfo(
                platform: .watchos,
                device: WKInterfaceDevice.current().model,
                appVersion: Bundle.main.appVersion
            ),
            profile: profile,
            config: DetectorConfig.default.withSensitivity(
                Sensitivity(rawValue: sensitivityRaw) ?? .medium
            )
        )
        recorder.label = trainingLabel
        recorder.playerAlias = playerAlias
        recorder.start(monotonicMs: Self.monotonicMs())
        trainingRecorder = recorder
        trainingRecording = true
        trainingCapturedInBatch = 0

        motionRecorder.start(sampleRateHz: DetectorConfig.default.sampleRateHz) { [weak self] sample in
            // Se escribe cada golpeo en cuanto está listo, no al final de la tanda: si
            // el reloj se queda sin batería a mitad, se pierde como mucho el último.
            let captured = recorder.onMotion(sample)
            guard !captured.isEmpty else { return }
            Task { @MainActor in
                self?.trainingStore.appendAll(captured)
                self?.trainingCapturedInBatch = recorder.capturedCount
            }
        }
    }

    func stopTraining() {
        guard let recorder = trainingRecorder else { return }
        motionRecorder.stop()
        trainingStore.appendAll(recorder.stop())
        trainingCapturedInBatch = recorder.capturedCount
        trainingRecorder = nil
        trainingRecording = false
        refreshTrainingCounts()
    }

    /// Envía el fichero de datos al iPhone. Es una acción explícita del usuario.
    func sendTrainingDataToPhone() -> Bool {
        guard trainingStore.exists, !trainingRecording else { return false }
        return transport.sendTrainingFile(trainingStore.url)
    }

    func clearTrainingData() {
        guard !trainingRecording else { return }
        trainingStore.clear()
        refreshTrainingCounts()
    }

    private func refreshTrainingCounts() {
        trainingTotalStored = trainingStore.count()
        trainingStoredKB = Int(trainingStore.sizeBytes / 1024)
    }

    func start() async {
        guard status == .idle || status == .saved else { return }
        status = .preparing
        statusMessage = nil

        guard motionRecorder.isAvailable else {
            status = .error("Este reloj no tiene los sensores necesarios")
            return
        }

        let sensitivity = Sensitivity(rawValue: sensitivityRaw) ?? .medium
        let recorder = SessionRecorder(
            source: SourceInfo(
                platform: .watchos,
                device: WKInterfaceDevice.current().model,
                appVersion: Bundle.main.appVersion
            ),
            profile: profile,
            config: DetectorConfig.default.withSensitivity(sensitivity)
        )
        self.recorder = recorder
        recorder.start(
            startedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            monotonicMs: Self.monotonicMs()
        )

        if trackScore {
            let board = ScoreBoard(
                rules: ScoreRules(
                    deuceFormat: DeuceFormat(rawValue: deuceFormatRaw) ?? .goldenPoint,
                    setsToWin: setsToWin
                ),
                firstServer: .us
            )
            scoreBoard = board
            score = board.current
        }

        // Los datos de salud son opcionales: si el usuario no ha dado consentimiento no
        // se arranca el workout, así que ni siquiera se miden.
        if shareHealth, WorkoutManager.isSupported, await workoutManager.requestAuthorization() {
            workoutManager.onMetrics = { [weak self] metrics in
                Task { @MainActor in self?.apply(metrics) }
            }
            try? workoutManager.start()
        }

        motionRecorder.start(sampleRateHz: DetectorConfig.default.sampleRateHz) { [weak self] sample in
            // El handler llega en la cola de sensores; solo se salta al hilo principal
            // cuando hay un golpeo que enseñar.
            guard let shot = recorder.onMotion(sample) else { return }
            Task { @MainActor in
                self?.shotCount = recorder.shots.count
                self?.lastShotType = shot.type
            }
        }

        startTicker()
        status = .recording
    }

    func stop() async {
        guard let recorder, recorder.isRecording else { return }
        status = .saving
        stopTicker()
        motionRecorder.stop()
        await workoutManager.end()

        // El marcador se adjunta antes de cerrar para que el resultado viaje dentro de la
        // sesión y no en un mensaje aparte que pueda perderse.
        recorder.score = scoreBoard?.current
        scoreBoard = nil
        score = nil

        let session = recorder.finish(
            endedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            monotonicMs: Self.monotonicMs(),
            shareHealth: shareHealth
        )
        self.recorder = nil

        let queued = transport.send(session)
        shotCount = session.totalShots
        elapsedSeconds = session.durationSeconds
        statusMessage = queued ? nil : "Guardada en el reloj; se enviará al iPhone al reconectar"
        status = .saved
    }

    /// Anota un punto y devuelve la vibración correspondiente al evento.
    func pointTo(_ side: Side) {
        guard let board = scoreBoard, !board.current.isFinished else { return }
        let before = board.current
        let after = board.point(to: side)
        score = after
        ScoreHaptics.play(ScoreEvent.between(before: before, after: after))
    }

    func undoPoint() {
        guard let board = scoreBoard, let restored = board.undo() else { return }
        score = restored
        ScoreHaptics.play(.undo)
    }

    func acknowledge() {
        status = .idle
        scoreBoard = nil
        score = nil
        elapsedSeconds = 0
        shotCount = 0
        heartRateBpm = nil
        lastShotType = nil
        statusMessage = nil
    }

    private func apply(_ metrics: WorkoutMetrics) {
        guard let recorder else { return }
        let now = Self.monotonicMs()
        if let bpm = metrics.heartRateBpm {
            recorder.onHeartRate(bpm, monotonicMs: now)
            heartRateBpm = bpm
        }
        recorder.onEnergy(activeKcal: metrics.activeEnergyKcal, totalKcal: metrics.totalEnergyKcal)
        if let steps = metrics.steps { recorder.onSteps(steps) }
        if let distance = metrics.distanceMeters { recorder.onDistance(distance) }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                let snapshot = recorder.liveSnapshot(monotonicMs: Self.monotonicMs())
                self.elapsedSeconds = snapshot.elapsedSeconds
                self.shotCount = snapshot.shotCount
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Reloj monótono: no salta si el reloj corrige su hora a mitad de partido. Es la
    /// misma base de tiempos que usa `CMDeviceMotion.timestamp`.
    private static func monotonicMs() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }
}

private extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
