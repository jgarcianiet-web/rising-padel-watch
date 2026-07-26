import Foundation
import PadelCore
import SwiftUI

/// Estado de la app de iPhone: historial de sesiones, ajustes y sincronización.
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var sessions: [PadelSession] = []
    @Published var message: String?

    @AppStorage("leagueBaseURL") var leagueBaseURL = ""
    @AppStorage("shareHealth") var shareHealth = false
    @AppStorage("shareShotEvents") var shareShotEvents = true
    @AppStorage("playerHand") var playerHandRaw = Hand.right.rawValue
    @AppStorage("watchWrist") var watchWristRaw = Hand.right.rawValue
    @AppStorage("sensitivity") var sensitivityRaw = Sensitivity.medium.rawValue
    @AppStorage("collectTrainingData") var collectTrainingData = false
    @AppStorage("playerAlias") var playerAlias = "anon"

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
            }
        )
        receiver.activate()
        self.receiver = receiver
        refreshTrainingData()
    }

    func refresh() {
        sessions = store.all()
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
