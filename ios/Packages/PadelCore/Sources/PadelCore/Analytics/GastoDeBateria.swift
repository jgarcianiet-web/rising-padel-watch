import Foundation

/// Cuánta batería gasta medir una sesión, en porcentaje por hora.
///
/// Es la primera pregunta que hace cualquiera antes de fiarse de un reloj deportivo, y la
/// única que no se puede contestar leyendo código: depende del modelo de reloj, de su
/// edad, del frío que haga y de si el pulso estaba encendido. La única respuesta honesta
/// es medirla en el reloj de quien pregunta.
///
/// Se descartan las sesiones que no pueden decir nada:
///
/// - **Cortas.** En quince minutos el sistema puede no haber movido el indicador ni un
///   punto, y dividir 1 punto entre 0,25 h da un 4%/h inventado.
/// - **Cargando.** Si el reloj estuvo en el cargador, la batería sube y el gasto sale
///   negativo. Eso no es "gastó poco", es que no se midió nada.
/// - **Sin dato.** Un reloj que no supo dar el nivel no cuenta como que gastó cero.
///
/// Espejo del core Kotlin, con tests allí.
public struct GastoDeBateria: Equatable, Sendable {
    /// Porcentaje por hora, la cifra que se enseña.
    public let porHora: Float
    /// Sobre cuántas sesiones se calculó: es lo que dice si el número vale algo.
    public let sesiones: Int
    /// Horas de juego que sostienen la media.
    public let horas: Float

    /// Por debajo de esta duración, la resolución del indicador de batería manda.
    public static let minMinutos = 30
    /// Con una sesión suelta no se promedia nada: fue un día, no una medida.
    public static let minSesiones = 2

    public init(porHora: Float, sesiones: Int, horas: Float) {
        self.porHora = porHora
        self.sesiones = sesiones
        self.horas = horas
    }

    /// Horas de reloj a este ritmo, partiendo de la batería llena. Es el número que la
    /// gente quiere de verdad: "¿me llega para el torneo del sábado?".
    public var horasDeAutonomia: Float { porHora <= 0 ? 0 : 100 / porHora }

    /// Nil si todavía no hay con qué contestar. Mejor eso que un número inventado.
    public static func de(_ sesiones: [PadelSession]) -> GastoDeBateria? {
        let utiles: [(Int, Float)] = sesiones.compactMap { sesion in
            guard let bateria = sesion.battery else { return nil }
            let horas = Float(sesion.durationSeconds) / 3600
            guard horas * 60 >= Float(minMinutos) else { return nil }
            // Cargando durante la sesión: el dato no vale. Un consumo de cero sí vale —
            // es raro, pero es una medida.
            guard bateria.consumido >= 0 else { return nil }
            return (bateria.consumido, horas)
        }
        guard utiles.count >= minSesiones else { return nil }

        let puntos = utiles.reduce(0) { $0 + $1.0 }
        let horas = utiles.reduce(Float(0)) { $0 + $1.1 }
        guard horas > 0 else { return nil }

        return GastoDeBateria(
            // Se suman puntos y horas y se divide una vez, en vez de promediar los
            // ritmos de cada sesión: así una sesión de veinte minutos no pesa lo mismo
            // que una de tres horas para decidir el ritmo del reloj.
            porHora: Float(puntos) / horas,
            sesiones: utiles.count,
            horas: horas
        )
    }
}
