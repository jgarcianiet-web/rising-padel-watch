import Foundation
import PadelCore
import WatchConnectivity

/// Envía la sesión terminada al iPhone.
///
/// Se usa `transferUserInfo` y no `sendMessage` porque **encola**: si el iPhone está
/// apagado o fuera de alcance al acabar el partido, watchOS entrega la sesión cuando
/// vuelva a haber conexión. Un mensaje se perdería.
final class PhoneTransport: NSObject {

    private let session: WCSession = .default
    private let encoder = JSONEncoder()

    /// Sesiones que no se han podido encolar todavía (sin WCSession disponible).
    private(set) var pending: [PadelSession] = []

    /// Ajustes replicados desde el iPhone. Lo consume `SessionController`.
    var onSettingsReceived: ((DeviceSettings) -> Void)?

    /// Órdenes del mando de tandas. El manejador responde con el estado del reloj, que
    /// viaja de vuelta en la misma llamada: una orden, una foto fresca de cómo quedó.
    var onTrainingCommand: ((OrdenDeTanda, @escaping (EstadoDeTanda) -> Void) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        // Al activar puede haber un contexto pendiente de una edición hecha con el reloj
        // apagado: WatchConnectivity no lo reentrega por delegado, hay que leerlo.
        applyContext(session.receivedApplicationContext)
    }

    fileprivate func applyContext(_ context: [String: Any]) {
        guard let data = context[Self.settingsKey] as? Data,
              let settings = DeviceSettings.decode(data) else { return }
        onSettingsReceived?(settings)
    }

    /// - Returns: true si la sesión quedó encolada para entrega.
    @discardableResult
    func send(_ session: PadelSession) -> Bool {
        guard WCSession.isSupported(), self.session.activationState == .activated else {
            pending.append(session)
            return false
        }
        guard let data = try? encoder.encode(session) else { return false }
        // La clave lleva el sessionId: dos sesiones distintas no se pisan en la cola.
        self.session.transferUserInfo([
            Self.payloadKey: data,
            Self.sessionIdKey: session.sessionId,
        ])
        return true
    }

    /// Reintenta lo que se quedó fuera por no tener WCSession lista.
    func flushPending() {
        guard !pending.isEmpty else { return }
        let queued = pending
        pending.removeAll()
        for session in queued {
            send(session)
        }
    }

    /// Envía el estado en vivo del partido al iPhone.
    ///
    /// Dos canales a la vez y a propósito: `sendMessage` llega al instante si el iPhone
    /// está alcanzable, y `updateApplicationContext` guarda **el último** estado para
    /// cuando no lo esté (el sistema entrega solo el más reciente al reconectar, que es
    /// exactamente la semántica de un marcador). Perder mensajes intermedios da igual:
    /// cada estado es completo.
    func sendLiveState(_ state: LiveMatchState) {
        guard WCSession.isSupported(), session.activationState == .activated,
              let data = try? encoder.encode(state) else { return }
        if session.isReachable {
            session.sendMessage([Self.liveScoreKey: data], replyHandler: nil, errorHandler: nil)
        }
        try? session.updateApplicationContext([Self.liveScoreKey: data])
    }

    /// Devuelve el estado de la tanda al iPhone por la vía encolada.
    ///
    /// Se usa cuando la orden llegó dormida (`transferUserInfo`): entonces no hay a quién
    /// contestar en el momento, y sin este camino de vuelta el móvil se quedaría con un
    /// "esperando" para siempre aunque la tanda ya estuviera grabando.
    func enviarEstadoDeTanda(_ estado: EstadoDeTanda) {
        guard WCSession.isSupported(), session.activationState == .activated,
              let data = try? encoder.encode(estado) else { return }
        session.transferUserInfo([EstadoDeTanda.clave: data])
    }

    /// Envía el fichero de datos de entrenamiento al iPhone.
    ///
    /// `transferFile` y no `transferUserInfo` porque el fichero puede pesar decenas de
    /// megas: es la señal cruda de miles de golpeos, no un resumen.
    @discardableResult
    func sendTrainingFile(_ url: URL) -> Bool {
        guard WCSession.isSupported(), session.activationState == .activated else { return false }
        session.transferFile(url, metadata: [Self.trainingFileKey: true])
        return true
    }

    static let payloadKey = "padel_session"
    static let sessionIdKey = "padel_session_id"
    static let trainingFileKey = "padel_training_data"
    static let settingsKey = "padel_settings"
    static let liveScoreKey = "padel_live_score"
}

extension PhoneTransport: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            flushPending()
            applyContext(session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        applyContext(context)
    }

    /// Las órdenes del mando cuando el reloj está despierto. Se contesta **siempre**,
    /// aunque sea con un diccionario vacío: si no, el móvil se queda esperando hasta que
    /// expire el mensaje y el usuario ve un botón que no responde sin saber por qué.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let orden = Self.orden(en: message), let manejador = onTrainingCommand else {
            replyHandler([:])
            return
        }
        manejador(orden) { estado in
            guard let respuesta = try? JSONEncoder().encode(estado) else {
                replyHandler([:])
                return
            }
            replyHandler([OrdenDeTanda.clave: respuesta])
        }
    }

    /// Las órdenes encoladas, que llegan con el reloj dormido y despiertan la app en
    /// segundo plano. Es el camino que hace que el mando funcione de verdad: mirar el
    /// móvil apaga la pantalla del reloj, y con ella la vía directa.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let orden = Self.orden(en: userInfo), let manejador = onTrainingCommand else {
            return
        }
        manejador(orden) { [weak self] estado in
            self?.enviarEstadoDeTanda(estado)
        }
    }

    private static func orden(en payload: [String: Any]) -> OrdenDeTanda? {
        guard let data = payload[OrdenDeTanda.clave] as? Data else { return nil }
        return try? JSONDecoder().decode(OrdenDeTanda.self, from: data)
    }
}
