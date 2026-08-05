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
    /// true si no se pudo arrancar el workout: sin él watchOS suspende la app al
    /// apagarse la pantalla y se dejan de contar golpeos.
    @Published private(set) var sensorsMayStop = false
    /// Marcador en curso, o nil si se juega sin llevarlo.
    @Published private(set) var score: MatchScore?
    /// Nivel técnico de la sesión recién cerrada. Nil mientras se juega.
    @Published private(set) var sessionLevel: SessionLevel?

    @AppStorage("shareHealth") private var shareHealth = false
    @AppStorage("playerHand") private var playerHandRaw = Hand.right.rawValue
    @AppStorage("watchWrist") private var watchWristRaw = Hand.right.rawValue
    @AppStorage("sensitivity") private var sensitivityRaw = Sensitivity.medium.rawValue
    @AppStorage("trackScore") private var trackScore = false
    @AppStorage("deuceFormat") private var deuceFormatRaw = DeuceFormat.goldenPoint.rawValue
    @AppStorage("setsToWin") private var setsToWin = 2
    @AppStorage("collectTrainingData") var collectTrainingData = false
    @AppStorage("playerAlias") private var playerAlias = "anon"
    /// Nivel de pádel del jugador (1-7); 0 = sin configurar. Viaja con cada muestra.
    @AppStorage("playerLevel") private var playerLevelRaw = 0

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

    /// Configuración del detector con el eje del antebrazo corregido para watchOS.
    ///
    /// En watchOS el marco de CoreMotion sigue la orientación de la pantalla, y con la
    /// corona bien configurada las 12 del reloj miran **siempre al codo**, en las dos
    /// muñecas: el eje codo → mano es **-Y**. El convenio por defecto del core asume +Y
    /// para la muñeca derecha, y en pista eso salía al revés: las derechas se leían como
    /// revés y los golpes altos nunca aparecían (la elevación salía negativa con el
    /// brazo levantado).
    ///
    /// El clasificador invierte el eje él solo para la muñeca izquierda (modela el
    /// hardware girado, cosa que watchOS ya normaliza), así que aquí se le pre-compensa
    /// para que el eje efectivo sea -Y en las dos muñecas.
    private func detectorConfig() -> DetectorConfig {
        var config = DetectorConfig.default.withSensitivity(
            Sensitivity(rawValue: sensitivityRaw) ?? .medium
        )
        config.forearmAxis = profile.watchWrist == .right ? Vector3(0, -1, 0) : Vector3(0, 1, 0)
        return config
    }

    init() {
        transport.onSettingsReceived = { [weak self] settings in
            Task { @MainActor in self?.applyRemoteSettings(settings) }
        }
        transport.activate()
        refreshTrainingCounts()
    }

    // MARK: Ajustes replicados desde el iPhone

    /// Marca de tiempo de los ajustes que tiene el reloj, para resolver la replicación.
    ///
    /// `Double` y no `Int` a propósito: en los relojes arm64_32 (Series 4-6, SE) `Int`
    /// es de 32 bits, y una época en milisegundos no cabe — la conversión hacía trap y
    /// la app crasheaba en cada arranque en cuanto el iPhone replicaba ajustes. Un
    /// `Double` representa milisegundos de época exactos hasta 2^53.
    @AppStorage("settingsUpdatedAt") private var settingsUpdatedAtMs: Double = 0

    /// Ajustes que llegaron a mitad de partido y esperan a que termine.
    private var pendingRemoteSettings: DeviceSettings?

    /// Aplica los ajustes que llegan del iPhone.
    ///
    /// El merge por marca de tiempo lo decide `DeviceSettings`: si lo que llega es más
    /// viejo que lo que hay, no se toca nada. Hace falta porque `updateApplicationContext`
    /// reentrega el último estado al reconectar, y sin esto una reconexión revertiría un
    /// cambio posterior.
    private func applyRemoteSettings(_ incoming: DeviceSettings) {
        let local = DeviceSettings(
            profile: profile,
            sensitivity: Sensitivity(rawValue: sensitivityRaw) ?? .medium,
            shareHealth: shareHealth,
            collectTrainingData: collectTrainingData,
            playerAlias: playerAlias,
            playerLevel: playerLevelRaw > 0 ? playerLevelRaw : nil,
            updatedAtEpochMs: Int64(settingsUpdatedAtMs)
        )
        let merged = local.merged(with: incoming)
        guard merged.updatedAtEpochMs != Int64(settingsUpdatedAtMs) else { return }

        // No se cambian los ajustes a mitad de partido: el detector ya está corriendo con
        // una configuración y cambiarla en caliente daría una sesión medida con dos
        // criterios distintos. Se guardan y se aplican al acabar.
        guard status == .idle || status == .saved else {
            pendingRemoteSettings = merged
            return
        }

        // `objectWillChange` a mano: `@AppStorage` dentro de un `ObservableObject` no
        // publica por su cuenta, así que sin esto la vista no se enteraría del cambio.
        objectWillChange.send()
        playerHandRaw = merged.profile.hand.rawValue
        watchWristRaw = merged.profile.watchWrist.rawValue
        sensitivityRaw = merged.sensitivity.rawValue
        shareHealth = merged.shareHealth
        collectTrainingData = merged.collectTrainingData
        playerAlias = merged.playerAlias
        playerLevelRaw = merged.playerLevel ?? 0
        settingsUpdatedAtMs = Double(merged.updatedAtEpochMs)
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
            config: detectorConfig()
        )
        recorder.label = trainingLabel
        recorder.playerAlias = playerAlias
        recorder.playerLevel = playerLevelRaw > 0 ? playerLevelRaw : nil
        recorder.start(monotonicMs: Self.monotonicMs())
        trainingRecorder = recorder
        trainingRecording = true
        trainingCapturedInBatch = 0

        // Igual que en un partido: sin workout, watchOS suspende la app al apagarse la
        // pantalla y la tanda se queda en los primeros golpes. Sin métricas: una tanda
        // de datos no es un entrenamiento que haya que guardar en Salud.
        await startWorkoutRuntime(collectMetrics: false)

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

    /// Arranca el workout que mantiene vivos los sensores y avisa si no se pudo.
    ///
    /// Que falle no aborta la sesión —se siguen contando los golpeos que lleguen— pero
    /// el usuario tiene que saberlo: sin workout la captura se corta al apagarse la
    /// pantalla, y un conteo silenciosamente incompleto es peor que un aviso.
    private func startWorkoutRuntime(collectMetrics: Bool) async {
        sensorsMayStop = true
        guard WorkoutManager.isSupported,
              await workoutManager.requestAuthorization(includeMetrics: collectMetrics)
        else { return }
        do {
            try workoutManager.start(collectMetrics: collectMetrics)
            sensorsMayStop = false
        } catch {
            sensorsMayStop = true
        }
    }

    func stopTraining() async {
        guard let recorder = trainingRecorder else { return }
        motionRecorder.stop()
        await workoutManager.end()
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

        let recorder = SessionRecorder(
            source: SourceInfo(
                platform: .watchos,
                device: WKInterfaceDevice.current().model,
                appVersion: Bundle.main.appVersion
            ),
            profile: profile,
            config: detectorConfig()
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

        // El workout se arranca **siempre**, con o sin consentimiento de salud: en
        // watchOS es lo único que impide que el sistema suspenda la app y corte el
        // acelerómetro en cuanto se apaga la pantalla. Sin él se pierden la mayoría de
        // los golpeos de un partido.
        //
        // El consentimiento sigue mandando sobre lo que importa: con `shareHealth` en
        // false no se pide permiso de lectura, no se recoge ninguna métrica y no queda
        // entrenamiento guardado en Salud.
        if shareHealth {
            workoutManager.onMetrics = { [weak self] metrics in
                Task { @MainActor in self?.apply(metrics) }
            }
        }
        await startWorkoutRuntime(collectMetrics: shareHealth)

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
        sessionLevel = session.level
        statusMessage = queued ? nil : "Guardada en el reloj; se enviará al iPhone al reconectar"
        status = .saved
        applyPendingRemoteSettings()
    }

    /// Aplica los ajustes que llegaron mientras se jugaba, ya con el partido cerrado.
    private func applyPendingRemoteSettings() {
        guard let pending = pendingRemoteSettings else { return }
        pendingRemoteSettings = nil
        applyRemoteSettings(pending)
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
        sessionLevel = nil
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
