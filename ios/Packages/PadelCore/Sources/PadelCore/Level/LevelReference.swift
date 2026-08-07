import Foundation

/// Una referencia de nivel: lo que mide el reloj a alguien de nivel **técnico** conocido.
///
/// La fuente son las tandas del modo de datos: le pones el reloj a un jugador, dices qué
/// nivel técnico tiene y le pides diez golpes de cada tipo. Eso, y no el resultado de sus
/// partidos, es lo que define la escala.
///
/// Deliberadamente **no** se usa el nivel de una plataforma de partidos (Playtomic y
/// similares): ese número mide con quién ganas, no cómo golpeas. Un jugador puede tener
/// técnica de 4 y estar en un 3 competitivo porque juega poco, le toca mala pareja o le
/// falta táctica — anclar la técnica ahí mezclaría dos cosas distintas y la medición
/// dejaría de significar nada. Espejo del core Kotlin, con tests allí.
public struct ReferenciaNivel: Codable, Equatable, Sendable {
    /// Nivel técnico de quien dio estos golpes, de 1 a 7.
    public let nivelTecnico: Float
    /// Mediana de velocidad de pala (km/h) por tipo de golpe en su tanda.
    public let velocidadPorTipo: [String: Float]
    /// Cuántos golpes la sostienen.
    public let golpes: Int

    public init(nivelTecnico: Float, velocidadPorTipo: [String: Float], golpes: Int) {
        self.nivelTecnico = nivelTecnico
        self.velocidadPorTipo = velocidadPorTipo
        self.golpes = golpes
    }
}

/// Convierte referencias de jugadores de nivel conocido en las bandas del estimador.
///
/// Para cada tipo de golpe se ajusta una recta velocidad = a + b·nivel por mínimos
/// cuadrados, y de ahí salen las velocidades de nivel 1 y de nivel 7. Es el paso que
/// convierte la escala de "estimación razonada" en "medida contra jugadores reales".
///
/// Cinturones, porque una banda mal puesta miente sobre el nivel de alguien: dos niveles
/// distintos como mínimo, pendiente positiva (más nivel, más velocidad) y un mínimo de
/// golpes por referencia.
public enum LevelReferenceCalibrator {

    /// Golpes mínimos de un tipo en una referencia para que cuente.
    public static let minGolpes = 10
    /// Niveles técnicos distintos mínimos para poder ajustar una recta.
    public static let minNiveles = 2

    /// Las bandas calibradas por tipo de golpe. Vacío si las referencias no dan para
    /// nada: entonces se quedan las de fábrica, que es lo honesto.
    public static func bandas(_ referencias: [ReferenciaNivel]) -> [ShotType: ShotBand] {
        let utiles = referencias.filter { $0.golpes >= minGolpes }
        guard Set(utiles.map(\.nivelTecnico)).count >= minNiveles else { return [:] }

        var salida: [ShotType: ShotBand] = [:]
        for tipo in ShotType.allCases where tipo != .unknown {
            guard let base = LevelConfig.defaultBands[tipo] else { continue }

            let puntos: [(Float, Float)] = utiles.compactMap { referencia in
                referencia.velocidadPorTipo[tipo.wireName].map { (referencia.nivelTecnico, $0) }
            }
            guard Set(puntos.map(\.0)).count >= minNiveles,
                  let (a, b) = ajustar(puntos), b > 0 else { continue }

            salida[tipo] = ShotBand(
                speedAtLevel1: max(a + b * 1, 5),
                speedAtLevel7: min(a + b * 7, 200),
                idealSweptDeg: base.idealSweptDeg,
                compactIsBetter: base.compactIsBetter
            )
        }
        return salida
    }

    /// Mínimos cuadrados: devuelve (ordenada, pendiente) o nil si no hay varianza.
    private static func ajustar(_ puntos: [(Float, Float)]) -> (Float, Float)? {
        guard puntos.count >= 2 else { return nil }
        let n = Float(puntos.count)
        let mediaX = puntos.map(\.0).reduce(0, +) / n
        let mediaY = puntos.map(\.1).reduce(0, +) / n
        var num: Float = 0
        var den: Float = 0
        for (x, y) in puntos {
            num += (x - mediaX) * (y - mediaY)
            den += (x - mediaX) * (x - mediaX)
        }
        guard den != 0 else { return nil }
        let b = num / den
        return (mediaY - b * mediaX, b)
    }
}
