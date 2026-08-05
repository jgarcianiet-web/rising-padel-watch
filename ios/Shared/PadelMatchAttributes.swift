import ActivityKit
import Foundation

/// El contrato entre la app y la Live Activity: lo que la pantalla de bloqueo y la
/// Dynamic Island saben del partido. Este fichero se compila en los dos targets (app y
/// extensión de widgets), así que no depende de PadelCore — solo tipos planos.
struct PadelMatchAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// Sets en orden de juego, ya formateados ("6-4 3-2").
        var sets: String
        /// Puntos del juego en curso como etiqueta ("40", "Ad"). Vacíos si terminó.
        var pointsUs: String
        var pointsThem: String
        /// true = sacamos nosotros; nil sin marcador.
        var servingUs: Bool?
        var shotCount: Int
        var heartRateBpm: Int?
        var elapsedSeconds: Int64
        var completed: Bool
        /// true = ganamos; nil si el partido se cortó sin ganador.
        var winnerUs: Bool?
    }

    /// Cuándo empezó el partido, para el cronómetro de la isla.
    var startedAt: Date
}
