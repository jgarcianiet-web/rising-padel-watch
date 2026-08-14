import Foundation

/// El mando a distancia de las tandas de entrenamiento: el móvil ordena, el reloj obedece.
///
/// Existe porque la tanda de datos casi nunca la graba quien lleva el reloj. Lo normal es
/// ponérselo a otra persona y dirigirla desde fuera —"ahora treinta derechas", "ahora
/// bandejas"— y con los botones solo en la muñeca hay que parar el ejercicio, quitarle el
/// reloj, cambiar el tipo y volver a empezar. Eso rompe la tanda y, peor, invita a grabar
/// menos tandas de las que hacen falta.
///
/// Las órdenes viajan por dos caminos y **nunca** por contexto de aplicación: un contexto
/// se reentrega al reconectar, y una orden reentregada arrancaría una tanda que nadie ha
/// pedido.
///
/// - Con el reloj a mano (su app en primer plano) va por `sendMessage`, que contesta al
///   instante con el estado entero.
/// - Con el reloj dormido va por `transferUserInfo`, que **encola** y despierta la app del
///   reloj en segundo plano. Cada elemento se entrega una sola vez, así que no hay riesgo
///   de reentrega, y el reloj devuelve su estado por el mismo camino.
///
/// El segundo camino es el que hace que el mando sirva para algo: mirar el móvil apaga la
/// pantalla del reloj, y exigir que estuviera despierto era exigirlo justo en el momento
/// en que no puede estarlo.
public enum AccionDeTanda: String, Codable, Sendable {
    /// No cambia nada: solo pregunta cómo va. Es lo que refresca el contador.
    case estado
    case iniciar
    case parar
    /// Manda al móvil lo que haya guardado.
    case enviar
}

/// Una orden del móvil al reloj.
public struct OrdenDeTanda: Codable, Sendable {
    public let accion: AccionDeTanda
    /// Tipo de golpe que se va a grabar. Solo lo mira `iniciar`.
    public let etiqueta: ShotType?
    /// Cuándo se dio la orden. Nil en órdenes de versiones viejas.
    public let creadoEpochMs: Int64?

    public init(accion: AccionDeTanda, etiqueta: ShotType? = nil, creadoEpochMs: Int64? = nil) {
        self.accion = accion
        self.etiqueta = etiqueta
        self.creadoEpochMs = creadoEpochMs
    }

    /// La clave del mensaje en WatchConnectivity. Una sola, compartida por los dos lados.
    public static let clave = "padel_mando_tanda"

    /// Una orden encolada puede tardar en llegar si el reloj estaba sin cobertura. Pasado
    /// este rato ya no se obedece: arrancar una tanda diez minutos después de pedirla, con
    /// el reloj otra vez en la muñeca de otro, es peor que no arrancarla.
    public static let maxAntiguedadMs: Int64 = 3 * 60_000

    /// ¿Sigue vigente esta orden? Las de `estado` siempre lo están: no cambian nada.
    public func vigente(ahoraEpochMs: Int64) -> Bool {
        if accion == .estado { return true }
        guard let creadoEpochMs else { return true }
        return ahoraEpochMs - creadoEpochMs <= Self.maxAntiguedadMs
    }
}

/// Lo que el reloj contesta a cualquier orden: su estado entero.
public struct EstadoDeTanda: Codable, Sendable, Equatable {
    public let grabando: Bool
    public let etiqueta: ShotType
    /// Golpeos capturados en la tanda en curso.
    public let capturadosEnTanda: Int
    /// Golpeos guardados en el reloj, de todas las tandas.
    public let guardadosEnTotal: Int
    public let kilobytes: Int
    /// Quién lleva el reloj ahora mismo, según los ajustes replicados.
    public let alias: String
    /// Su nivel técnico declarado, que es lo que ancla la escala. Nil = sin declarar.
    public let nivel: Int?
    /// El reloj avisa de que sin permiso de entreno la tanda puede cortarse al apagarse
    /// la pantalla. Devolver diez golpes de cincuenta en silencio sería peor que fallar.
    public let sensoresPuedenPararse: Bool
    /// Por qué la última orden no hizo lo que se le pidió, si es que no lo hizo. Nil =
    /// todo en orden. Sin esto, pulsar "Grabar" durante un partido deja un botón que
    /// parece roto en vez de una explicación.
    public let motivo: String?
    /// Los swings que el detector tiró en esta tanda, con el motivo. Es lo que convierte
    /// "no me coge la mitad de las bandejas" en un número con su umbral culpable al lado.
    public let descartes: DescartesDelDetector?
    /// Segundos de tanda grabados, si hay una en marcha. Es el contador que siempre
    /// avanza: la prueba de que se está guardando algo, vea el detector lo que vea.
    public let segundosDeTanda: Int?

    /// La clave con la que el reloj devuelve su estado cuando la orden vino encolada y
    /// no había a quién contestar en el momento.
    public static let clave = "padel_estado_tanda"

    public init(
        grabando: Bool,
        etiqueta: ShotType,
        capturadosEnTanda: Int,
        guardadosEnTotal: Int,
        kilobytes: Int,
        alias: String,
        nivel: Int?,
        sensoresPuedenPararse: Bool,
        motivo: String? = nil,
        descartes: DescartesDelDetector? = nil,
        segundosDeTanda: Int? = nil
    ) {
        self.grabando = grabando
        self.etiqueta = etiqueta
        self.capturadosEnTanda = capturadosEnTanda
        self.guardadosEnTotal = guardadosEnTotal
        self.kilobytes = kilobytes
        self.alias = alias
        self.nivel = nivel
        self.sensoresPuedenPararse = sensoresPuedenPararse
        self.motivo = motivo
        self.descartes = descartes
        self.segundosDeTanda = segundosDeTanda
    }
}
