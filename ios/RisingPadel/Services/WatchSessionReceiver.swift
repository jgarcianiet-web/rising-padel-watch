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
    /// Estado de la tanda que devuelve el reloj cuando la orden fue encolada.
    var onEstadoDeTanda: ((EstadoDeTanda) -> Void)?

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

    /// ¿Está la app del reloj despierta ahora mismo? Decide si la orden va directa o
    /// encolada, pero ya no decide si se manda: encolada también llega.
    var relojDespierto: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isReachable
    }

    /// Cómo salió la orden.
    enum EnvioDeOrden {
        /// Fue directa y el reloj ya contestó.
        case directa(EstadoDeTanda)
        /// El reloj estaba dormido: queda encolada y contestará cuando despierte.
        case encolada
        /// El reloj estaba dormido y no se encoló nada. Es lo que pasa con los sondeos
        /// de estado: preguntar "¿cómo vas?" no merece despertar un reloj, y encolar uno
        /// cada dos segundos llenaría la cola de preguntas viejas.
        case dormido
        /// No hay reloj emparejado o WatchConnectivity no está disponible.
        case imposible
    }

    /// Manda una orden al reloj.
    ///
    /// Dos caminos y **nunca** contexto de aplicación: un contexto se reentrega al
    /// reconectar, y una orden reentregada arrancaría una tanda que nadie pidió.
    ///
    /// - Con el reloj despierto, `sendMessage` contesta al instante.
    /// - Con el reloj dormido, `transferUserInfo` **encola y despierta** la app del reloj
    ///   en segundo plano, y cada elemento se entrega una sola vez. Este camino es el que
    ///   hace que el mando sirva: mirar el móvil apaga la pantalla del reloj, así que
    ///   exigir que estuviera despierto era exigirlo justo cuando no puede estarlo.
    /// - Parameter encolarSiDuerme: false para los sondeos de estado, que no deben
    ///   despertar al reloj ni acumularse en la cola.
    func enviarOrden(
        _ orden: OrdenDeTanda,
        encolarSiDuerme: Bool,
        respuesta: @escaping (EnvioDeOrden) -> Void
    ) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(orden) else {
            respuesta(.imposible)
            return
        }

        guard WCSession.default.isReachable else {
            guard encolarSiDuerme else {
                respuesta(.dormido)
                return
            }
            WCSession.default.transferUserInfo([OrdenDeTanda.clave: data])
            respuesta(.encolada)
            return
        }

        WCSession.default.sendMessage(
            [OrdenDeTanda.clave: data],
            replyHandler: { payload in
                if let cuerpo = payload[OrdenDeTanda.clave] as? Data,
                   let estado = try? JSONDecoder().decode(EstadoDeTanda.self, from: cuerpo) {
                    respuesta(.directa(estado))
                    return
                }
                // Respuesta ilegible. Para una orden que cambia algo no se puede dar por
                // "dormida" y ya: eso la descartaba en silencio, y un "parar" descartado
                // en silencio es un botón que no hace nada. Se reenvía por la cola, que
                // es idempotente — parar dos veces es parar.
                guard encolarSiDuerme else {
                    respuesta(.dormido)
                    return
                }
                WCSession.default.transferUserInfo([OrdenDeTanda.clave: data])
                respuesta(.encolada)
            },
            // Si el mensaje directo falla (el reloj se durmió entre el `isReachable` y
            // el envío, que pasa constantemente), se reintenta por la cola en vez de
            // dar la orden por perdida.
            errorHandler: { _ in
                guard encolarSiDuerme else {
                    respuesta(.dormido)
                    return
                }
                WCSession.default.transferUserInfo([OrdenDeTanda.clave: data])
                respuesta(.encolada)
            }
        )
    }

    private func handleLive(_ payload: [String: Any]) {
        guard let data = payload[PhoneTransportKeys.liveScore] as? Data,
              let state = try? decoder.decode(LiveMatchState.self, from: data) else { return }
        onLiveState(state)
    }

    private func handle(_ userInfo: [String: Any]) {
        // El estado de la tanda que el reloj devuelve tras una orden encolada.
        if let data = userInfo[EstadoDeTanda.clave] as? Data,
           let estado = try? decoder.decode(EstadoDeTanda.self, from: data) {
            onEstadoDeTanda?(estado)
            return
        }
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
