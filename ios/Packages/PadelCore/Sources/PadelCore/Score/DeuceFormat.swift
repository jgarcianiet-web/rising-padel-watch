import Foundation

/// Qué se juega al llegar a 40-40. Cambia de una liga a otra y cambia el conteo, no solo
/// la etiqueta.
///
/// Los tres formatos se reducen a un único parámetro: **cuántas ventajas se permiten
/// antes de que el siguiente 40-40 sea decisivo**. Con eso, la regla del juego es la
/// misma en los tres casos y solo cambia dónde está la frontera.
public enum DeuceFormat: String, Codable, CaseIterable, Sendable {
    /// Ventaja clásica: hay que sacar dos puntos seguidos, sin límite de ventajas.
    case advantage

    /// Punto de oro: a 40-40 el siguiente punto cierra el juego.
    case goldenPoint

    /// Star point: se juegan hasta **dos** ventajas. Si ninguna se convierte, el tercer
    /// 40-40 es punto de oro.
    ///
    /// La secuencia completa es: 40-40 → ventaja → 40-40 → ventaja → 40-40 decisivo.
    case starPoint

    public var wireName: String { rawValue }

    /// Ventajas permitidas antes del punto decisivo. nil = sin límite.
    public var advantagesAllowed: Int? {
        switch self {
        case .advantage: return nil
        case .goldenPoint: return 0
        case .starPoint: return 2
        }
    }

    /// Puntos crudos a los que el 40-40 pasa a ser decisivo, o nil si nunca lo es.
    ///
    /// 40-40 son 3 puntos cada uno, así que cada ventaja consumida sube la frontera en
    /// uno: punto de oro decide en 3-3, star point en 5-5.
    public var decisiveDeuceAt: Int? {
        advantagesAllowed.map { 3 + $0 }
    }

    /// Nombre corto para la UI. Vive junto a la regla para que las tres apps digan lo mismo.
    public var label: String {
        switch self {
        case .advantage: return "Ventajas"
        case .goldenPoint: return "Punto de oro"
        case .starPoint: return "Star point"
        }
    }

    public static func fromWire(_ value: String) -> DeuceFormat {
        DeuceFormat(rawValue: value) ?? .goldenPoint
    }
}
