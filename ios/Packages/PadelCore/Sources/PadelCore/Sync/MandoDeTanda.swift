import Foundation

/// El mando a distancia de las tandas de entrenamiento: el móvil ordena, el reloj obedece.
///
/// Existe porque la tanda de datos casi nunca la graba quien lleva el reloj. Lo normal es
/// ponérselo a otra persona y dirigirla desde fuera —"ahora treinta derechas", "ahora
/// bandejas"— y con los botones solo en la muñeca hay que parar el ejercicio, quitarle el
/// reloj, cambiar el tipo y volver a empezar. Eso rompe la tanda y, peor, invita a grabar
/// menos tandas de las que hacen falta.
///
/// Las órdenes van por `sendMessage` con respuesta y **nunca** por contexto de aplicación:
/// un contexto se reentrega al reconectar, y una orden reentregada arrancaría una tanda
/// que nadie ha pedido. Cada orden devuelve el estado completo del reloj, así que el
/// móvil nunca tiene que adivinar en qué punto está.
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

    public init(accion: AccionDeTanda, etiqueta: ShotType? = nil) {
        self.accion = accion
        self.etiqueta = etiqueta
    }

    /// La clave del mensaje en WatchConnectivity. Una sola, compartida por los dos lados.
    public static let clave = "padel_mando_tanda"
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

    public init(
        grabando: Bool,
        etiqueta: ShotType,
        capturadosEnTanda: Int,
        guardadosEnTotal: Int,
        kilobytes: Int,
        alias: String,
        nivel: Int?,
        sensoresPuedenPararse: Bool,
        motivo: String? = nil
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
    }
}
