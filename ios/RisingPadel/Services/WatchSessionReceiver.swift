import Foundation
import PadelCore
import WatchConnectivity

/// Recibe las sesiones que envía el Apple Watch.
///
/// `transferUserInfo` se entrega aunque la app esté cerrada: iOS la despierta en segundo
/// plano, así que la sesión se guarda al acabar el partido sin que el usuario tenga que
/// abrir nada.
final class WatchSessionReceiver: NSObject {

    private let decoder = JSONDecoder()
    private let onSessionReceived: (PadelSession) -> Void
    private let onTrainingFileReceived: (URL) -> Void
    private let onLiveState: (LiveMatchState) -> Void

    init(
        onSessionReceived: @escaping (PadelSession) -> Void,
        onTrainingFileReceived: @escaping (URL) -> Void = { _ in },
        onLiveState: @escaping (LiveMatchState) -> Void = { _ in }
    ) {
        self.onSessionReceived = onSessionReceived
        self.onTrainingFileReceived = onTrainingFileReceived
        self.onLiveState = onLiveState
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Replica los ajustes al reloj.
    ///
    /// `updateApplicationContext` y no `sendMessage` porque **sustituye y persiste**: el
    /// reloj recibe el último estado en cuanto vuelve a estar a tiro, aunque estuviera
    /// apagado cuando se cambió el ajuste. Solo interesa el estado actual, no el historial
    /// de ediciones, que es exactamente lo que este primitivo modela.
    ///
    /// Va aquí y no en una clase aparte porque WatchConnectivity admite **un solo
    /// delegado** por proceso, y en el iPhone es este.
    func replicate(_ settings: DeviceSettings) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = DeviceSettings.encode(settings) else { return }
        // Sin reloj emparejado esto lanza, y no es un error que deba ver el usuario: la
        // app de iPhone funciona igual sin reloj.
        try? WCSession.default.updateApplicationContext([PhoneTransportKeys.settings: data])
    }

    private func handleLive(_ payload: [String: Any]) {
        guard let data = payload[PhoneTransportKeys.liveScore] as? Data,
              let state = try? decoder.decode(LiveMatchState.self, from: data) else { return }
        onLiveState(state)
    }

    private func handle(_ userInfo: [String: Any]) {
        guard let data = userInfo[PhoneTransportKeys.payload] as? Data,
              let session = try? decoder.decode(PadelSession.self, from: data) else {
            return
        }
        onSessionReceived(session)
    }
}

extension WatchSessionReceiver: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    /// Canal rápido del marcador en vivo, cuando las dos apps están despiertas.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleLive(message)
    }

    /// Canal lento del marcador: el sistema entrega el **último** contexto al reconectar,
    /// que es exactamente la semántica de un marcador (solo importa el estado actual).
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        handleLive(context)
    }

    /// El fichero llega a una ubicación temporal que el sistema borra al volver de este
    /// método, así que hay que copiarlo aquí mismo.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[PhoneTransportKeys.trainingFile] != nil else { return }
        onTrainingFileReceived(file.fileURL)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Al cambiar de reloj hay que reactivar para seguir recibiendo sesiones del nuevo.
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

/// Claves compartidas con la app del reloj. Duplicadas a mano y no en PadelCore porque
/// son un detalle del transporte de Apple, no del dominio.
enum PhoneTransportKeys {
    static let payload = "padel_session"
    static let sessionId = "padel_session_id"
    static let trainingFile = "padel_training_data"
    static let settings = "padel_settings"
    static let liveScore = "padel_live_score"
}
