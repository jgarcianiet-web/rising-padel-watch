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
    /// Objetivos de la liga que el reloj puede seguir él solo, con su progreso en vivo.
    @Published private(set) var objectiveProgress: [ObjectiveProgress] = []
    /// Rutina guiada en marcha, si la sesión se arrancó con una. Nil = partido normal.
    @Published private(set) var rutina: Rutina?
    /// El ejercicio que toca ahora y cómo va. Nil si no hay rutina o ya terminó.
    @Published private(set) var pasoDeRutina: ProgresoDeRutina?
    /// La rutina se completó entera. Se queda a la vista hasta cerrar la sesión.
    @Published private(set) var rutinaTerminada = false
    /// Sesión en pausa: el workout de Salud se congela y los golpeos no cuentan. El
    /// reloj del partido sigue corriendo — el tiempo de pista es tiempo de pista.
    @Published private(set) var isPaused = false
    /// Copia de `isPaused` legible desde la cola de sensores sin saltar de hilo. Se
    /// escribe solo desde el hilo principal; leer un Bool desfasado un instante es
    /// inofensivo (como mucho cuenta o descarta un golpeo fronterizo).
    nonisolated(unsafe) private var pausedFlag = false

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
    /// Los objetivos por partido que replica el iPhone, serializados con `\n` porque
    /// `@AppStorage` no guarda arrays.
    @AppStorage("matchObjectives") private var matchObjectivesRaw = ""

    private var matchObjectives: [String] {
        matchObjectivesRaw.split(separator: "\n").map(String.init)
    }

    private let motionRecorder = MotionRecorder()
    private let workoutManager = WorkoutManager()
    private let transport = PhoneTransport()

    private var recorder: SessionRecorder?
    private var rutinaEnCurso: RutinaEnCurso?
    /// Nivel de batería al empezar la sesión, 0-100. Nil si el reloj no supo darlo.
    private var bateriaAlEmpezar: Int?
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
    /// para que el eje efectivo sea el mismo en las dos muñecas.
    ///
    /// **El signo se giró con datos de pista (ago 2026).** Cuarenta golpes etiquetados,
    /// ocho tipos de cinco: los golpes altos —remate, bandeja, víbora— medían −40° de
    /// preparación y −12° de pico, y los de fondo +16° y +46°. Es decir, exactamente al
    /// revés de lo que pasa en una pista. Con el signo girado, la puerta de "¿fue un
    /// golpe alto?" acierta 38 de 40; antes no pasaba ni uno.
    ///
    /// El valor anterior se había "validado" en la época en que la autocalificación del
    /// signo oscilaba dentro de una misma tanda, así que se validó contra ruido.
    private func detectorConfig() -> DetectorConfig {
        var config = DetectorConfig.default.withSensitivity(
            Sensitivity(rawValue: sensitivityRaw) ?? .medium
        )
        config.forearmAxis = profile.watchWrist == .right ? Vector3(0, 1, 0) : Vector3(0, -1, 0)
        // Girar el eje del antebrazo arregló la elevación y **rompió el lado**.
        //
        // Es la misma cuenta: la rotación axial se mide proyectando el giro sobre ese
        // eje, así que darle la vuelta al eje le da la vuelta al signo. Al arreglar la
        // elevación se invirtió sin querer el convenio "positivo = derecha", y desde
        // entonces todas las derechas salían como revés y al revés.
        //
        // Lo dice una tanda etiquetada (ago 2026) sin margen de duda: los cinco reveses
        // reales midieron entre +3,5 y +6,5 de rotación axial y las cinco derechas entre
        // −4,9 y −9,7. Exactamente al contrario de lo que espera el clasificador.
        //
        // Se corrige aquí y no en el core porque es de este reloj: en Wear OS el eje no
        // se ha tocado, y girarle el signo por simetría sería repetir el error que esto
        // arregla. Allí lo detectará la calibración por tandas cuando las haya.
        config.invertAxialSign = true
        // Los umbrales del jugador, sacados de sus tandas etiquetadas: la calibración
        // se calcula en el móvil (que tiene el fichero) y viaja con los ajustes.
        if let calibration = storedCalibration {
            config = config.applying(calibration)
        }
        return config
    }

    /// La calibración replicada desde el iPhone. Se guarda serializada porque
    /// `@AppStorage` no entiende de structs.
    @AppStorage("detectorCalibration") private var calibrationJSON = ""

    var storedCalibration: DetectorCalibration? {
        guard let data = calibrationJSON.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(DetectorCalibration.self, from: data)
    }

    init() {
        transport.onSettingsReceived = { [weak self] settings in
            Task { @MainActor in self?.applyRemoteSettings(settings) }
        }
        transport.onTrainingCommand = { [weak self] orden, responder in
            Task { @MainActor in
                guard let self else { return }
                responder(await self.atender(orden))
            }
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
            matchObjectives: matchObjectives,
            calibration: storedCalibration,
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
        matchObjectivesRaw = merged.matchObjectives.joined(separator: "\n")
        if let calibration = merged.calibration,
           let data = try? JSONEncoder().encode(calibration),
           let texto = String(data: data, encoding: .utf8) {
            calibrationJSON = texto
        }
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

        // Se envía solo al acabar la tanda. Depender de que el usuario se acuerde de
        // pulsar un botón es cómo los golpeos se quedaban en el reloj: la transferencia
        // va en cola del sistema, así que si el iPhone no está cerca sale cuando vuelva.
        _ = sendTrainingDataToPhone()
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

    // MARK: Mando de tandas desde el móvil

    /// Atiende una orden del mando y devuelve el estado resultante.
    ///
    /// Quien graba la tanda casi nunca es quien lleva el reloj: se lo pones a otro y le
    /// vas cantando los ejercicios. Con los botones solo en la muñeca había que parar,
    /// quitarle el reloj y cambiar el tipo entre tanda y tanda, y eso se traduce en menos
    /// tandas grabadas — justo lo contrario de lo que necesita el detector.
    ///
    /// No se toca nada si hay un partido en marcha: una tanda de datos y una sesión de
    /// juego usan el mismo sensor, y arrancar una encima de la otra estropearía las dos.
    func atender(_ orden: OrdenDeTanda) async -> EstadoDeTanda {
        // Una orden encolada puede llegar tarde: el reloj estaba sin cobertura, o en la
        // muñeca de otro. Arrancar una tanda diez minutos después de pedirla sorprende
        // más de lo que ayuda, así que caduca. Preguntar el estado nunca caduca.
        guard orden.vigente(ahoraEpochMs: Int64(Date().timeIntervalSince1970 * 1000)) else {
            return estadoDeTanda(motivo: "La orden llegó tarde y no se ha ejecutado")
        }

        var motivo: String?
        switch orden.accion {
        case .estado:
            break
        case .iniciar:
            if let etiqueta = orden.etiqueta { trainingLabel = etiqueta }
            if trainingRecording {
                motivo = nil // Ya estaba grabando: la orden repetida no es un error.
            } else if status != .idle && status != .saved {
                motivo = "Hay un partido en marcha en el reloj"
            } else if !collectTrainingData {
                motivo = "El modo de datos de entrenamiento está apagado"
            } else if !motionRecorder.isAvailable {
                motivo = "Este reloj no tiene los sensores necesarios"
            } else {
                await startTraining()
            }
        case .parar:
            await stopTraining()
        case .enviar:
            if !sendTrainingDataToPhone() { motivo = "No se pudo enviar al móvil" }
        }
        return estadoDeTanda(motivo: motivo)
    }

    private func estadoDeTanda(motivo: String? = nil) -> EstadoDeTanda {
        EstadoDeTanda(
            grabando: trainingRecording,
            etiqueta: trainingLabel,
            capturadosEnTanda: trainingCapturedInBatch,
            guardadosEnTotal: trainingTotalStored,
            kilobytes: trainingStoredKB,
            alias: playerAlias,
            nivel: playerLevelRaw > 0 ? playerLevelRaw : nil,
            sensoresPuedenPararse: sensorsMayStop,
            motivo: motivo,
            descartes: trainingRecorder?.descartes
        )
    }

    /// Arranca la sesión. Con [rutina] es una sesión guiada; sin ella, un entreno o un
    /// partido normal.
    ///
    /// Una sesión con rutina no es una sesión distinta: se guarda igual en el historial
    /// y cuenta igual para el nivel. Lo único que cambia es que el reloj lleva el guion.
    ///
    /// La rutina se monta **aquí y siempre**, también cuando es nil: arrancar un entreno
    /// suelto después de una rutina tiene que dejar la pantalla limpia, y si solo se
    /// tocara al pasar una, la anterior seguiría en pantalla ya terminada.
    func start(rutina: Rutina? = nil) async {
        guard status == .idle || status == .saved else { return }
        self.rutina = rutina
        rutinaEnCurso = rutina.map { RutinaEnCurso($0) }
        pasoDeRutina = rutinaEnCurso?.progreso
        rutinaTerminada = false
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
                firstServer: firstServer
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
            // cuando hay un golpeo que enseñar. En pausa, la muestra se descarta: el
            // peloteo de calentamiento o los botes en la mano no son golpeos.
            guard self?.pausedFlag != true else { return }
            guard let shot = recorder.onMotion(sample) else { return }
            Task { @MainActor in
                self?.shotCount = recorder.shots.count
                self?.lastShotType = shot.type
                self?.refreshObjectives(recorder.shots)
                self?.avanzarRutina(shot.type)
            }
        }

        // La batería, antes de que el workout empiece a gastarla: es el "de dónde
        // partimos" con el que se calcula el gasto de la sesión.
        bateriaAlEmpezar = Self.nivelDeBateria()

        startTicker()
        status = .recording
        publishLiveState(completed: false)
    }

    // MARK: Batería

    /// Nivel de batería del reloj, 0-100, o nil si el sistema no lo sabe.
    ///
    /// Hay que encender la monitorización antes de leer; sin ella `batteryLevel`
    /// devuelve -1 siempre. Se enciende aquí y no en el arranque de la app porque solo
    /// se lee en dos instantes: al empezar y al acabar la sesión.
    private static func nivelDeBateria() -> Int? {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let nivel = device.batteryLevel
        guard nivel >= 0 else { return nil }
        return Int((nivel * 100).rounded())
    }

    // MARK: Rutina guiada

    /// Mete el golpe recién detectado en la rutina y avisa con el motor cuando toca.
    ///
    /// El háptico es la parte importante: en la pista no se mira el reloj entre golpe y
    /// golpe, así que el "ya está, pasa al siguiente" tiene que entrar por la muñeca.
    /// Cada golpe válido da un toque flojo, terminar un ejercicio uno claro, y acabar la
    /// rutina el de éxito — tres avisos distintos que se distinguen sin mirar.
    private func avanzarRutina(_ type: ShotType) {
        guard let curso = rutinaEnCurso else { return }
        switch curso.onShot(type) {
        case .cuenta:
            WKInterfaceDevice.current().play(.click)
        case .pasoCompletado:
            WKInterfaceDevice.current().play(.directionUp)
        case .terminada:
            WKInterfaceDevice.current().play(.success)
            rutinaTerminada = true
        case .noCuenta, .yaTerminada:
            break
        }
        pasoDeRutina = curso.progreso
    }

    /// Salta el ejercicio en curso. La máquina se queda sin bolas, al compañero le duele
    /// el hombro, o el detector no reconoce el golpe y el ejercicio se atasca: sin una
    /// salida, la rutina pasa de ayudar a estorbar.
    func saltarPasoDeRutina() {
        guard let curso = rutinaEnCurso else { return }
        if curso.saltarPaso() == .terminada { rutinaTerminada = true }
        pasoDeRutina = curso.progreso
        WKInterfaceDevice.current().play(.directionUp)
    }

    // MARK: Objetivo del día

    /// Objetivos ya cumplidos, para no repetir el aviso en cada golpe posterior.
    private var objectivesCelebrated = Set<String>()

    /// Recalcula el progreso de los objetivos medibles y avisa al cumplirse uno.
    ///
    /// El aviso es háptico y no visual a propósito: en pista no se mira el reloj, se
    /// nota. Solo suena una vez por objetivo — un "¡lo tienes!" repetido cada bandeja
    /// posterior sería un castigo, no un premio.
    private func refreshObjectives(_ shots: [Shot]) {
        let objetivos = matchObjectives
        guard !objetivos.isEmpty else { return }

        var byType: [ShotType: Int] = [:]
        for shot in shots { byType[shot.type, default: 0] += 1 }

        let progreso = ObjectiveEvaluator.progress(
            objetivos: objetivos, shotsByType: byType, totalShots: shots.count
        )
        objectiveProgress = progreso

        for objetivo in progreso where objetivo.measurement.met {
            // Solo se celebran los de llegar: cumplir un "máximo 10 remates" mientras
            // juegas es el estado normal, no un logro — y dejaría de serlo al golpe 11.
            guard objetivo.measurement.actual >= objetivo.measurement.target,
                  objectivesCelebrated.insert(objetivo.text).inserted else { continue }
            WKInterfaceDevice.current().play(.success)
        }
    }

    /// Manda el estado del partido al iPhone. Estado completo, no eventos: perder una
    /// actualización da igual porque la siguiente trae la verdad entera.
    private func publishLiveState(completed: Bool) {
        guard trackScore, let recorder, let id = recorder.currentSessionId else { return }
        transport.sendLiveState(LiveMatchState(
            sessionId: id,
            updatedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            completed: completed,
            score: score,
            shotCount: shotCount,
            heartRateBpm: heartRateBpm,
            elapsedSeconds: elapsedSeconds
        ))
    }

    /// Pausa el partido: el workout de Salud se congela y los golpeos dejan de contar.
    /// El marcador y el reloj siguen — pausar es "estamos parados", no "no pasó".
    func pause() {
        guard status == .recording, !isPaused else { return }
        isPaused = true
        pausedFlag = true
        workoutManager.pause()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        pausedFlag = false
        workoutManager.resume()
    }

    func stop() async {
        guard let recorder, recorder.isRecording else { return }
        // Finalizar en pausa es válido: se reanuda el workout para poder cerrarlo bien.
        if isPaused { resume() }
        status = .saving
        stopTicker()
        motionRecorder.stop()
        await workoutManager.end()

        // La última publicación en vivo lleva `completed`: el que mira deja de esperar.
        publishLiveState(completed: true)

        // El marcador se adjunta antes de cerrar para que el resultado viaje dentro de la
        // sesión y no en un mensaje aparte que pueda perderse.
        recorder.score = scoreBoard?.current
        scoreBoard = nil
        score = nil

        var session = recorder.finish(
            endedAtEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            monotonicMs: Self.monotonicMs(),
            shareHealth: shareHealth
        )
        // Cuánto costó medir esta sesión. No es un dato de salud —no sale del cuerpo de
        // nadie— así que no depende del consentimiento: es una propiedad del reloj.
        if let inicio = bateriaAlEmpezar, let fin = Self.nivelDeBateria() {
            session.battery = BatteryUse(startPercent: inicio, endPercent: fin)
        }
        bateriaAlEmpezar = nil
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

    /// Quién saca el primer juego. Se pregunta al empezar el partido porque sin ello no
    /// se puede separar el rendimiento al saque del rendimiento al resto, que en pádel
    /// son dos partidos distintos. Ver `docs/insights.md`.
    @Published var firstServer: Side = .us

    /// Anota un punto y devuelve la vibración correspondiente al evento.
    func pointTo(_ side: Side) {
        guard let board = scoreBoard, !board.current.isFinished else { return }
        let before = board.current
        let after = board.point(to: side)
        score = after
        // El registro de juegos vive en el core: aquí solo se le pasan los dos
        // marcadores y él decide si se cerró alguno y quién sacaba.
        recorder?.onScoreChanged(previous: before, current: after, monotonicMs: Self.monotonicMs())
        ScoreHaptics.play(ScoreEvent.between(before: before, after: after))
        checkLiveTip()
        publishLiveState(completed: after.isFinished)
    }

    /// Avisos del entrenador en vivo, al cerrarse un juego.
    ///
    /// El aviso se queda en pantalla hasta el siguiente punto y vibra una vez: en pista
    /// no se lee un párrafo, se nota que el reloj tiene algo que decir y se mira de
    /// reojo entre puntos. Las reglas y sus mínimos de evidencia viven en el core.
    private func checkLiveTip() {
        guard let games = recorder?.games, !games.isEmpty else { return }
        guard let tip = LiveCoach.tip(games: games, alreadySaid: tipsSaid) else { return }
        tipsSaid.insert(tip.key)
        liveTip = tip.text
        WKInterfaceDevice.current().play(.notification)
    }

    /// Aviso del entrenador en curso, o nil si no hay ninguno.
    @Published private(set) var liveTip: String?
    private var tipsSaid = Set<String>()

    /// El jugador ya lo ha leído: fuera de la pantalla.
    func dismissLiveTip() { liveTip = nil }

    func undoPoint() {
        guard let board = scoreBoard, let restored = board.undo() else { return }
        score = restored
        ScoreHaptics.play(.undo)
        publishLiveState(completed: false)
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
        objectiveProgress = []
        objectivesCelebrated.removeAll()
        rutina = nil
        rutinaEnCurso = nil
        pasoDeRutina = nil
        rutinaTerminada = false
        liveTip = nil
        tipsSaid.removeAll()
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
