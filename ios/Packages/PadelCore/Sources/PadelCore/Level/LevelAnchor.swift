import Foundation

/// Un punto de anclaje: qué mide el reloj, de media, en jugadores que declaran un nivel
/// conocido.
public struct AnclaDeNivel: Codable, Equatable, Sendable {
    /// Nivel declarado por el jugador (escala 1-7 tipo Playtomic).
    public let nivelDeclarado: Float
    /// Mediana de lo que midió el reloj a los jugadores de ese nivel.
    public let medidoMediana: Float
    /// Cuántos jugadores distintos lo sostienen.
    public let jugadores: Int

    public init(nivelDeclarado: Float, medidoMediana: Float, jugadores: Int) {
        self.nivelDeclarado = nivelDeclarado
        self.medidoMediana = medidoMediana
        self.jugadores = jugadores
    }
}

/// La tabla que traduce **lo que mide el reloj** a **nivel real de juego**.
///
/// Existe porque son dos cosas distintas y confundirlas sería mentir: el reloj mide
/// velocidad de pala, amplitud de swing y regularidad, y de ahí sale un número; lo que
/// un jugador quiere saber es a qué nivel de pista equivale eso. La única forma honesta
/// de unir las dos escalas es medir a jugadores cuyo nivel se conoce de antemano.
///
/// Por eso la tabla **no se inventa aquí**: la construye el servidor con los niveles que
/// declaran los usuarios de la comunidad, y va mejorando según juega más gente. Con dos
/// anclas o menos no se traduce nada — antes sin equivalencia que con una inventada.
/// Espejo del core Kotlin, con tests allí.
public struct LevelAnchorTable: Codable, Equatable, Sendable {
    public let puntos: [AnclaDeNivel]
    /// Cuándo se calculó, para poder refrescarla.
    public let creadoEpochMs: Int64

    public init(puntos: [AnclaDeNivel] = [], creadoEpochMs: Int64 = 0) {
        self.puntos = puntos
        self.creadoEpochMs = creadoEpochMs
    }

    /// Un ancla con menos jugadores que esto no cuenta: sería una anécdota.
    public static let minJugadoresPorAncla = 3
    /// Con menos anclas que esto no hay curva que interpolar.
    public static let minAnclas = 2

    /// Sin anclas suficientes no hay traducción posible.
    public var fiable: Bool {
        puntos.filter { $0.jugadores >= Self.minJugadoresPorAncla }.count >= Self.minAnclas
    }

    /// Traduce una medición del reloj al nivel de juego equivalente, interpolando entre
    /// las anclas conocidas. Nil si la tabla todavía no se sostiene.
    ///
    /// Fuera del rango medido no se extrapola a lo loco: se devuelve el nivel del ancla
    /// más cercana. Decirle a alguien que es un 7 porque pega más fuerte que la persona
    /// más fuerte que hemos medido sería exactamente el tipo de mentira que este tipo
    /// existe para evitar.
    public func equivalente(_ medido: Float) -> Float? {
        guard fiable else { return nil }
        let validos = puntos
            .filter { $0.jugadores >= Self.minJugadoresPorAncla }
            .sorted { $0.medidoMediana < $1.medidoMediana }

        if let primero = validos.first, medido <= primero.medidoMediana {
            return primero.nivelDeclarado
        }
        if let ultimo = validos.last, medido >= ultimo.medidoMediana {
            return ultimo.nivelDeclarado
        }

        for i in 0..<(validos.count - 1) {
            let bajo = validos[i]
            let alto = validos[i + 1]
            if medido >= bajo.medidoMediana, medido <= alto.medidoMediana {
                let rango = alto.medidoMediana - bajo.medidoMediana
                guard rango > 0 else { return bajo.nivelDeclarado }
                let t = (medido - bajo.medidoMediana) / rango
                return bajo.nivelDeclarado + t * (alto.nivelDeclarado - bajo.nivelDeclarado)
            }
        }
        return nil
    }
}

/// Lo que la app puede decir hoy sobre el nivel de un jugador, con lo que hay.
///
/// El percentil no necesita anclaje: comparar tu medición con la de los demás es cierto
/// desde el primer día. La equivalencia sí, y por eso puede venir vacía.
public struct LecturaDeNivel: Equatable, Sendable {
    public let medido: Float
    public let equivalente: Float?
    /// 0-100: qué porcentaje de la comunidad queda por debajo. Nil si no hay con quién.
    public let percentil: Int?

    /// Con menos gente que esto, un percentil no significa nada.
    public static let minComunidad = 8

    public static func calcular(
        medido: Float,
        tabla: LevelAnchorTable,
        medicionesComunidad: [Float]
    ) -> LecturaDeNivel {
        let percentil: Int? = medicionesComunidad.count >= minComunidad
            ? min(max(medicionesComunidad.filter { $0 < medido }.count * 100
                / medicionesComunidad.count, 0), 100)
            : nil
        return LecturaDeNivel(
            medido: medido,
            equivalente: tabla.equivalente(medido),
            percentil: percentil
        )
    }
}
