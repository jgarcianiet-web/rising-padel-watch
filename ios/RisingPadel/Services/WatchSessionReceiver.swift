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

    init(onSessionReceived: @escaping (PadelSession) -> Void) {
        self.onSessionReceived = onSessionReceived
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
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
}
