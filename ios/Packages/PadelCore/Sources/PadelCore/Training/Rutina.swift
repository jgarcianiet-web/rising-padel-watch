import Foundation

/// Un ejercicio: tantos golpes de un tipo.
public struct PasoDeRutina: Codable, Equatable, Sendable {
    public let type: ShotType
    public let golpes: Int

    public init(_ type: ShotType, _ golpes: Int) {
        precondition(golpes > 0, "un paso sin golpes no es un ejercicio")
        self.type = type
        self.golpes = golpes
    }
}

/// Un entrenamiento con estructura: la lista de ejercicios que el reloj va cantando.
///
/// Es lo que separa a esta app de un contador de golpes. Un contador te dice, al acabar,
/// que diste 312 golpes; una rutina te dice **qué hacer ahora** y lleva la cuenta ella
/// sola, que es lo que hace falta cuando estás en la pista con la pala en la mano y no
/// puedes ir mirando el móvil ni acordarte de por dónde ibas.
///
/// No tiene nada que ver con el modo de datos de entrenamiento, aunque se parezcan: aquel
/// graba señal cruda para etiquetar y solo lo usa quien construye el dataset. Esto es una
/// sesión normal, que se guarda en el historial y cuenta para el nivel, con un guion.
/// Espejo del core Kotlin, con tests allí.
public struct Rutina: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let nombre: String
    /// Para qué sirve, en una línea. Es lo que se lee al elegirla.
    public let proposito: String
    public let pasos: [PasoDeRutina]

    public init(id: String, nombre: String, proposito: String, pasos: [PasoDeRutina]) {
        self.id = id
        self.nombre = nombre
        self.proposito = proposito
        self.pasos = pasos
    }

    public var golpesTotales: Int { pasos.reduce(0) { $0 + $1.golpes } }

    /// Las rutinas de fábrica.
    ///
    /// Cuatro y no veinte a propósito: en una pantalla de 45 mm una lista larga es una
    /// lista que no se lee. Cubren las tres cosas que se entrenan en pádel —fondo, red y
    /// golpes altos— más una completa para el día que hay pista y ganas.
    public static let deFabrica: [Rutina] = [
        Rutina(
            id: "calentamiento",
            nombre: "Calentamiento",
            proposito: "Entrar en calor sin forzar, de fondo a red",
            pasos: [
                PasoDeRutina(.forehand, 20),
                PasoDeRutina(.backhand, 20),
                PasoDeRutina(.forehandVolley, 15),
                PasoDeRutina(.backhandVolley, 15),
            ]
        ),
        Rutina(
            id: "red",
            nombre: "Red",
            proposito: "Volea y bandeja: el juego de la red",
            pasos: [
                PasoDeRutina(.forehandVolley, 30),
                PasoDeRutina(.backhandVolley, 30),
                PasoDeRutina(.bandeja, 25),
            ]
        ),
        Rutina(
            id: "altos",
            nombre: "Golpes altos",
            proposito: "Bandeja, víbora y remate, que es donde se decide el punto",
            pasos: [
                PasoDeRutina(.bandeja, 25),
                PasoDeRutina(.vibora, 20),
                PasoDeRutina(.smash, 15),
            ]
        ),
        Rutina(
            id: "completa",
            nombre: "Completa",
            proposito: "Todo el repertorio, una vez cada golpe",
            pasos: [
                PasoDeRutina(.serve, 15),
                PasoDeRutina(.forehand, 25),
                PasoDeRutina(.backhand, 25),
                PasoDeRutina(.forehandVolley, 20),
                PasoDeRutina(.backhandVolley, 20),
                PasoDeRutina(.bandeja, 20),
                PasoDeRutina(.vibora, 15),
                PasoDeRutina(.smash, 15),
            ]
        ),
    ]
}

/// Cómo va el paso que se está haciendo ahora mismo.
public struct ProgresoDeRutina: Equatable, Sendable {
    public let paso: PasoDeRutina
    /// Índice del paso, empezando en 0.
    public let indice: Int
    public let totalPasos: Int
    /// Golpes válidos dados en este paso.
    public let hechos: Int
    /// Golpes de otro tipo que se dieron durante el paso: no cuentan, pero se avisan.
    public let fueraDeTipo: Int

    public init(paso: PasoDeRutina, indice: Int, totalPasos: Int, hechos: Int, fueraDeTipo: Int) {
        self.paso = paso
        self.indice = indice
        self.totalPasos = totalPasos
        self.hechos = hechos
        self.fueraDeTipo = fueraDeTipo
    }

    public var restantes: Int { max(paso.golpes - hechos, 0) }
    public var fraccion: Float { min(max(Float(hechos) / Float(paso.golpes), 0), 1) }
}

/// Qué acaba de pasar al registrar un golpe. Es lo que decide si el reloj vibra.
public enum EventoDeRutina: Sendable {
    /// Golpe del tipo que tocaba: se suma y sigue.
    case cuenta
    /// Golpe de otro tipo: no cuenta.
    case noCuenta
    /// Con este se completó el paso y ya se pasó al siguiente.
    case pasoCompletado
    /// Con este se completó el último paso: la rutina ha terminado.
    case terminada
    /// Ya estaba terminada; no hay nada que contar.
    case yaTerminada
}

/// El estado de una rutina en marcha.
///
/// Cuenta **solo los golpes del tipo que toca**. Un revés durante la tanda de derechas no
/// suma, y no suma a propósito: si contara cualquier golpe, la rutina se completaría sola
/// peloteando y dejaría de ser un entrenamiento para ser un cronómetro. Lo que sí hace es
/// llevar la cuenta de los golpes fuera de tipo, que es información útil al acabar.
public final class RutinaEnCurso {

    public let rutina: Rutina

    private var indice = 0
    private var hechos = 0
    private var fueraDeTipo = 0
    /// Golpes válidos de cada paso ya cerrado, en orden. Es el resumen del final.
    private var completados: [Int] = []

    public private(set) var terminada = false

    public init(_ rutina: Rutina) {
        self.rutina = rutina
    }

    public var progreso: ProgresoDeRutina? {
        guard !terminada else { return nil }
        return ProgresoDeRutina(
            paso: rutina.pasos[indice],
            indice: indice,
            totalPasos: rutina.pasos.count,
            hechos: hechos,
            fueraDeTipo: fueraDeTipo
        )
    }

    /// Golpes válidos totales de toda la rutina.
    public var golpesValidos: Int { completados.reduce(0, +) + hechos }

    /// Registra un golpe detectado y dice qué ha pasado.
    ///
    /// Un golpe `.unknown` nunca cuenta: el detector no supo qué era, y darlo por bueno
    /// sería completar el ejercicio con golpes que a lo mejor ni eran del tipo pedido.
    @discardableResult
    public func onShot(_ type: ShotType) -> EventoDeRutina {
        guard !terminada else { return .yaTerminada }
        let paso = rutina.pasos[indice]
        guard type == paso.type, type != .unknown else {
            fueraDeTipo += 1
            return .noCuenta
        }

        hechos += 1
        if hechos < paso.golpes { return .cuenta }
        return cerrarPaso()
    }

    /// Salta al siguiente paso sin terminarlo.
    ///
    /// Hace falta de verdad: la máquina de bolas se queda sin pelotas, al compañero le
    /// duele el hombro, o el detector no está reconociendo un golpe y el ejercicio se
    /// queda atascado. Sin una salida, la rutina pasa de ayudar a estorbar.
    @discardableResult
    public func saltarPaso() -> EventoDeRutina {
        guard !terminada else { return .yaTerminada }
        return cerrarPaso()
    }

    private func cerrarPaso() -> EventoDeRutina {
        completados.append(hechos)
        hechos = 0
        fueraDeTipo = 0
        indice += 1
        if indice >= rutina.pasos.count {
            terminada = true
            return .terminada
        }
        return .pasoCompletado
    }

    /// Cuántos golpes válidos se hicieron en cada paso, para el resumen final.
    public func resumen() -> [(PasoDeRutina, Int)] {
        var hechosPorPaso = completados
        if !terminada { hechosPorPaso.append(hechos) }
        return zip(rutina.pasos.prefix(hechosPorPaso.count), hechosPorPaso).map { ($0, $1) }
    }
}
