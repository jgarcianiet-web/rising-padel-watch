import Foundation

/// Un número puesto al lado de tu media: la diferencia y si es para bien.
///
/// "45 km/h" no significa nada para nadie que no lleve años midiéndose. "45 km/h, +3 sobre
/// tu media" sí: dice que hoy pegaste más fuerte de lo normal, que es la única forma en
/// que un número suelto se convierte en información. Es la diferencia entre una ficha que
/// hay que interpretar y una que se lee sola. Espejo del core Kotlin, con tests allí.
public struct Comparativa: Equatable, Sendable {
    /// Diferencia con la media, en las unidades del número.
    public let delta: Float
    public let media: Float
    /// La diferencia en tanto por uno de la media.
    public let fraccion: Float
    /// true = mejor que tu media, false = peor.
    public let mejor: Bool

    /// Cuántas sesiones ajenas hacen falta para hablar de "tu media".
    ///
    /// Con una sola sesión anterior, "tu media" es esa sesión, y comparar dos días
    /// sueltos no es una tendencia: es ruido con nombre de estadística.
    public static let minSesiones = 3

    /// Por debajo de esta diferencia relativa no se dice nada: sería ruido.
    public static let umbral: Float = 0.03

    public init(delta: Float, media: Float, fraccion: Float, mejor: Bool) {
        self.delta = delta
        self.media = media
        self.fraccion = fraccion
        self.mejor = mejor
    }

    /// Compara `valor` con `media`. Nil si no hay media, si es cero o si la diferencia es
    /// tan pequeña que enseñarla sería inventar una tendencia.
    ///
    /// - Parameter masEsMejor: false para métricas donde subir es peor.
    public static func de(_ valor: Float, _ media: Float?, masEsMejor: Bool = true) -> Comparativa? {
        guard let media, media != 0 else { return nil }
        let delta = valor - media
        let fraccion = delta / media
        guard abs(fraccion) >= umbral else { return nil }
        return Comparativa(
            delta: delta,
            media: media,
            fraccion: fraccion,
            mejor: masEsMejor ? delta > 0 : delta < 0
        )
    }

    /// El texto que va debajo del número: "+3 sobre tu media".
    ///
    /// - Parameter decimales: cuántos decimales tiene sentido enseñar en esa unidad.
    public func texto(decimales: Int = 0) -> String {
        let signo = delta > 0 ? "+" : "−"
        let magnitud = String(format: "%.\(decimales)f", abs(delta))
        return "\(signo)\(magnitud) sobre tu media"
    }
}

/// Las medias del jugador sobre su historial, para poner cada sesión en su sitio.
///
/// Se calculan **excluyendo la sesión que se va a comparar**. Sin eso, un jugador con tres
/// sesiones compara la de hoy contra una media que incluye la de hoy: la diferencia sale
/// diluida a un tercio y el día que reventó el récord la ficha dice "+2 sobre tu media"
/// cuando fueron seis. Cuantas menos sesiones, más grave el error — justo cuando el
/// jugador es nuevo y más está mirando.
public struct MediasDelJugador: Equatable, Sendable {
    public let golpeos: Float?
    public let minutos: Float?
    public let ritmo: Float?
    public let velocidadMedia: Float?
    public let velocidadMaxima: Float?
    public let nivel: Float?

    public static let vacias = MediasDelJugador(
        golpeos: nil, minutos: nil, ritmo: nil,
        velocidadMedia: nil, velocidadMaxima: nil, nivel: nil
    )

    public init(
        golpeos: Float?, minutos: Float?, ritmo: Float?,
        velocidadMedia: Float?, velocidadMaxima: Float?, nivel: Float?
    ) {
        self.golpeos = golpeos
        self.minutos = minutos
        self.ritmo = ritmo
        self.velocidadMedia = velocidadMedia
        self.velocidadMaxima = velocidadMaxima
        self.nivel = nivel
    }

    /// - Parameter excluyendo: id de la sesión que se va a comparar, para que no se
    ///   compare contra sí misma.
    public static func de(_ sesiones: [PadelSession], excluyendo: String? = nil) -> MediasDelJugador {
        let otras = sesiones.filter { $0.sessionId != excluyendo && $0.totalShots > 0 }
        guard otras.count >= Comparativa.minSesiones else { return .vacias }

        func media(_ valores: [Float]) -> Float {
            valores.reduce(0, +) / Float(valores.count)
        }

        let puntuables = otras.filter { $0.level.gradedShots > 0 }
        return MediasDelJugador(
            golpeos: media(otras.map { Float($0.totalShots) }),
            minutos: media(otras.map { Float($0.durationSeconds) / 60 }),
            ritmo: media(otras.map(\.shotsPerMinute)),
            velocidadMedia: media(otras.map { $0.intensity.meanRacketSpeedKmh }),
            velocidadMaxima: media(otras.map { $0.intensity.maxRacketSpeedKmh }),
            nivel: puntuables.count < Comparativa.minSesiones
                ? nil
                : media(puntuables.map { $0.level.overall })
        )
    }
}
