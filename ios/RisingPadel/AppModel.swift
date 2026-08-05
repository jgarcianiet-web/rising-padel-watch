import Foundation
import PadelCore
import SwiftUI

/// Estado de la app de iPhone: historial de sesiones, ajustes y sincronización.
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var sessions: [PadelSession] = []
    @Published var message: String?

    /// Partido en curso en el reloj, o nil si no hay ninguno. Alimenta el banner en vivo.
    @Published private(set) var liveMatch: LiveMatchState?

    @AppStorage("leagueBaseURL") var leagueBaseURL = ""
    @AppStorage("shareHealth") var shareHealth = false
    @AppStorage("shareShotEvents") var shareShotEvents = true
    @AppStorage("playerHand") var playerHandRaw = Hand.right.rawValue
    @AppStorage("watchWrist") var watchWristRaw = Hand.right.rawValue
    @AppStorage("sensitivity") var sensitivityRaw = Sensitivity.medium.rawValue
    @AppStorage("collectTrainingData") var collectTrainingData = false
    /// Desbloquea el modo de recogida de datos. Es una herramienta de quien construye
    /// el dataset, no de quien juega: para un usuario normal no existe. Siete toques en
    /// la versión lo activan; con cuentas de la liga pasará a depender de un rol real.
    @AppStorage("developerMode") var developerMode = false
    @AppStorage("playerAlias") var playerAlias = "anon"
    /// Nivel de pádel del jugador (1-7); 0 = sin configurar. Es el ancla para calibrar
    /// la escala: los golpes grabados llevan el nivel de quien los dio.
    @AppStorage("playerLevel") var playerLevelRaw = 0

    /// Fichero de datos de entrenamiento recibido del reloj. **Nunca se sube a la liga**:
    /// solo se exporta cuando el usuario lo comparte a mano. Ver `docs/training-data.md`.
    @Published private(set) var trainingDataURL: URL?
    @Published private(set) var trainingDataSizeKB = 0

    private let store: SessionStore
    private let syncQueue: SyncQueue
    private var receiver: WatchSessionReceiver?

    var hasToken: Bool { KeychainTokenStore.read() != nil }

    var profile: PlayerProfile {
        PlayerProfile(
            hand: Hand(rawValue: playerHandRaw) ?? .right,
            watchWrist: Hand(rawValue: watchWristRaw) ?? .right
        )
    }

    init(store: SessionStore? = nil) {
        let resolved = store ?? FileSessionStore(directory: Self.sessionsDirectory())
        self.store = resolved
        self.syncQueue = SyncQueue(store: resolved, client: LeagueAPIClient())
        self.sessions = resolved.all()

        // El receptor se activa aquí y no en la vista: las sesiones llegan aunque el
        // usuario nunca abra la pantalla del historial.
        let receiver = WatchSessionReceiver(
            onSessionReceived: { [weak self] session in
                Task { @MainActor in self?.receive(session) }
            },
            onTrainingFileReceived: { [weak self] url in
                // Se copia sincrónicamente: el sistema borra el temporal al volver.
                let destination = Self.trainingDataDestination()
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.copyItem(at: url, to: destination)
                Task { @MainActor in self?.refreshTrainingData() }
            },
            onLiveState: { [weak self] state in
                Task { @MainActor in self?.receiveLive(state) }
            }
        )
        receiver.activate()
        self.receiver = receiver
        refreshTrainingData()
        observeSettingsChanges()
    }

    func refresh() {
        sessions = store.all()
    }

    // MARK: Marcador en vivo

    /// Un estado viejo reentregado por el sistema no puede pisar uno más nuevo, y el
    /// partido terminado se queda en pantalla como resultado final hasta que llega la
    /// sesión completa del reloj (que lo sustituye con todo el detalle).
    private func receiveLive(_ state: LiveMatchState) {
        if let current = liveMatch, current.sessionId == state.sessionId,
           state.updatedAtEpochMs < current.updatedAtEpochMs {
            return
        }
        liveMatch = state

        // El marcador también vive en la pantalla de bloqueo y la Dynamic Island.
        liveActivity.update(with: state)

        // Si hay liga configurada, el estado se republica para que otros lo sigan.
        // Fuego y olvido: sin cola, la siguiente actualización corrige sola.
        if let config = leagueConfig() {
            Task { await LiveScorePublisher().publish(state, config: config) }
        }
    }

    private let liveActivity = LiveActivityController()

    /// Enlace público para seguir el partido: la página de espectador del servidor de
    /// la liga (`server/live`), que vive en la misma URL base. Nil sin liga configurada.
    func liveSpectatorURL(for sessionId: String) -> URL? {
        var base = leagueBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/" + sessionId)
    }

    /// Nivel medio del jugador sobre su historial: la línea de referencia de las
    /// gráficas ("calidad media"). Nil sin sesiones puntuables.
    var playerAverageLevel: Float? {
        let levels = sessions.map(\.level).filter { $0.gradedShots > 0 }.map(\.overall)
        guard !levels.isEmpty else { return nil }
        return levels.reduce(0, +) / Float(levels.count)
    }

    /// Siete toques en la versión. Apagarlo apaga también la recogida de datos, para
    /// que no quede la grabación activa escondida — la replicación quita el botón del
    /// reloj al propagarse el cambio.
    private var versionTaps = 0
    func versionTapped() {
        versionTaps += 1
        guard versionTaps >= 7 else { return }
        versionTaps = 0
        developerMode.toggle()
        if !developerMode {
            collectTrainingData = false
        }
        message = developerMode ? "Modo desarrollador activado" : "Modo desarrollador desactivado"
    }

    // MARK: Replicación de ajustes al reloj

    /// Marca de tiempo de la última edición de un ajuste replicado al reloj.
    ///
    /// `Double` y no `Int` por la misma razón que en el reloj: este valor viaja a
    /// relojes arm64_32 donde `Int` es de 32 bits y una época en milisegundos no cabe.
    /// En el iPhone `Int` habría funcionado, pero los dos lados usan el mismo tipo para
    /// que nadie pueda reintroducir el desbordamiento copiando código de un lado a otro.
    @AppStorage("settingsUpdatedAt") private var settingsUpdatedAtMs: Double = 0

    /// Lo último que se mandó, para no reenviar en cada escritura de UserDefaults.
    private var lastReplicated: DeviceSettings?
    private var settingsObserver: NSObjectProtocol?

    /// Los ajustes que el reloj necesita, con la marca de tiempo actual.
    var deviceSettings: DeviceSettings {
        DeviceSettings(
            profile: profile,
            sensitivity: Sensitivity(rawValue: sensitivityRaw) ?? .medium,
            shareHealth: shareHealth,
            collectTrainingData: collectTrainingData,
            // Se normaliza aquí y no en el campo de texto: reescribir mientras el usuario
            // teclea es hostil, y lo que importa es que lo que viaja sea consistente.
            playerAlias: DeviceSettings.sanitizeAlias(playerAlias),
            playerLevel: playerLevelRaw > 0 ? playerLevelRaw : nil,
            // Los objetivos de la liga viajan al reloj para que enseñe en vivo los que
            // puede medir. `LigaModel` los deja en UserDefaults al guardarlos, que es
            // además lo que dispara la replicación (se observa UserDefaults).
            matchObjectives: matchObjectivesRaw
                .split(separator: "\n").map(String.init),
            updatedAtEpochMs: Int64(settingsUpdatedAtMs)
        )
    }

    /// Espejo de los objetivos de la liga, en el formato que guarda `LigaModel`.
    @AppStorage("matchObjectives") private var matchObjectivesRaw = ""

    /// Replica al reloj cada cambio de ajustes.
    ///
    /// Se observa `UserDefaults` en vez de enganchar cada `Toggle` porque las vistas
    /// escriben directamente en `@AppStorage`: no hay un setter donde poner la llamada, y
    /// un ajuste nuevo se replicaría solo sin que haya que acordarse de nada.
    private func observeSettingsChanges() {
        // Se parte de lo que hay para que arrancar la app no cuente como una edición: si
        // no, el primer arranque mandaría los valores por defecto con marca reciente y
        // pisaría lo que el reloj tuviera configurado.
        var seed = deviceSettings
        seed.updatedAtEpochMs = 0
        lastReplicated = seed

        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.replicateSettingsIfChanged() }
        }

        // Si ya había ajustes editados, se reenvían tal cual: puede ser un reloj recién
        // emparejado que nunca los recibió. La marca no se toca, así que no pisa nada más
        // reciente que hubiera en la muñeca.
        if settingsUpdatedAtMs > 0 {
            receiver?.replicate(deviceSettings)
        }
    }

    private func replicateSettingsIfChanged() {
        var current = deviceSettings
        // La comparación ignora la marca de tiempo; si no, escribirla dispararía otra
        // notificación y el ciclo no pararía nunca.
        current.updatedAtEpochMs = 0
        guard current != lastReplicated else { return }
        lastReplicated = current

        // Solo se mueve la marca cuando cambia algo de verdad: es lo que decide quién gana
        // si el mismo ajuste se tocó en el reloj.
        settingsUpdatedAtMs = (Date().timeIntervalSince1970 * 1000).rounded()
        current.updatedAtEpochMs = Int64(settingsUpdatedAtMs)
        receiver?.replicate(current)
    }

    // MARK: Enviar a la liga (deep link)

    /// URL `ligapadel://importar?datos=<JSON>` con el payload del contrato.
    ///
    /// Es el puente con la app de liga (repositorio `padel`): su pantalla de importar
    /// consume exactamente el payload de `POST /v1/padel-sessions`. Sin eventos por
    /// golpeo — la liga no los usa y un deep link no es sitio para decenas de KB.
    func leagueDeepLink(for session: PadelSession) -> URL? {
        // La media del historial viaja con la sesión: es la línea "calidad media" de
        // las gráficas de la liga, y solo este lado la conoce.
        let payload = session.toPayload(
            shareHealth: shareHealth,
            includeEvents: false,
            playerAverageLevel: playerAverageLevel
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8),
              let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "ligapadel://importar?datos=\(encoded)")
    }

    // MARK: Datos de entrenamiento

    func refreshTrainingData() {
        let url = Self.trainingDataDestination()
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            trainingDataURL = nil
            trainingDataSizeKB = 0
            return
        }
        trainingDataURL = url
        trainingDataSizeKB = Int(size / 1024)
    }

    func deleteTrainingData() {
        try? FileManager.default.removeItem(at: Self.trainingDataDestination())
        refreshTrainingData()
    }

    private static func trainingDataDestination() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(
            at: base.appendingPathComponent("training"),
            withIntermediateDirectories: true
        )
        return base.appendingPathComponent("training/muestras.jsonl")
    }

    /// Una sesión reenviada por el reloj no debe volver a la cola si ya se subió.
    private func receive(_ session: PadelSession) {
        // La sesión completa sustituye al estado en vivo: mismo partido, más detalle.
        if liveMatch?.sessionId == session.sessionId {
            liveMatch = nil
        }
        guard store.get(session.sessionId) == nil else { return }
        store.upsert(session)
        refresh()
        Task { await syncNow() }
    }

    func syncNow() async {
        guard let config = leagueConfig() else {
            message = "Configura la URL de la liga y el token en Ajustes"
            return
        }
        let report = await syncQueue.sync(
            config: config,
            shareHealth: shareHealth,
            includeEvents: shareShotEvents
        )
        refresh()
        if report.needsAuth {
            message = "El token de la liga ya no vale. Vuelve a conectarla en Ajustes."
        } else if report.uploaded > 0 {
            message = "\(report.uploaded) sesión(es) enviada(s) a la liga"
        }
    }

    func retry(_ sessionId: String) async {
        syncQueue.requeue(sessionId)
        refresh()
        await syncNow()
    }

    func delete(_ sessionId: String) {
        store.delete(sessionId)
        refresh()
    }

    /// Vincula la sesión con un partido de la liga y la devuelve a la cola de subida.
    func linkToMatch(sessionId: String, matchId: String, leagueId: String?) async {
        guard var session = store.get(sessionId) else { return }
        let trimmed = matchId.trimmingCharacters(in: .whitespaces)
        session.matchRef = trimmed.isEmpty
            ? nil
            : MatchRef(
                matchId: trimmed,
                leagueId: leagueId?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
        store.upsert(session)
        syncQueue.requeue(sessionId)
        refresh()
        await syncNow()
    }

    func setToken(_ token: String) {
        KeychainTokenStore.write(token)
        // Un token nuevo desbloquea todo lo que se quedó esperando autenticación.
        syncQueue.requeueAllNeedingAuth()
        refresh()
        message = token.isEmpty ? "Token borrado" : "Token guardado"
        objectWillChange.send()
    }

    private func leagueConfig() -> LeagueConfig? {
        guard let token = KeychainTokenStore.read(),
              !leagueBaseURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return LeagueConfig(baseURL: leagueBaseURL.trimmingCharacters(in: .whitespaces), token: token)
    }

    private static func sessionsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("sessions", isDirectory: true)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
