import Foundation

/// Un aviso corto para la muñeca, a mitad de partido.
public struct LiveTip: Equatable, Sendable {
    /// Identifica la regla, para no repetir el mismo aviso dos veces.
    public let key: String
    /// Lo que se lee de reojo entre puntos. Corto a propósito.
    public let text: String

    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

/// El entrenador en vivo: mira los juegos cerrados y, si hay un patrón claro, suelta un
/// aviso de una línea.
///
/// Es el `InsightEngine` con dos diferencias: pasa **durante** el partido, así que solo
/// puede mirar juegos completos (nunca golpeos, que a mitad de juego no dicen nada), y
/// habla poquísimo. Un aviso a mitad de partido interrumpe; si no cambia lo que vas a
/// hacer en el siguiente juego, no se dice.
///
/// Espejo de `LiveCoach.kt`; los tests viven en el core Kotlin.
public enum LiveCoach {

    /// Sin esto una racha de dos juegos ya "sería un patrón", y no lo es.
    public static let minGames = 4

    /// Tres por lado, uno más que el `InsightEngine` de después del partido: un aviso en
    /// vivo interrumpe, y con dos juegos por lado un 50%-0% es todavía una moneda.
    public static let minGamesPerSide = 3

    /// Diferencia de puntos porcentuales que hace que saque y resto sean dos partidos.
    public static let minSideGap = 40

    /// Juegos seguidos perdidos que merecen un aviso.
    public static let losingStreak = 3

    /// Devuelve el aviso que toca ahora, o nil si no hay nada que decir.
    public static func tip(games: [GameRecord], alreadySaid: Set<String>) -> LiveTip? {
        guard games.count >= minGames else { return nil }

        // La racha manda sobre el resto: es lo más urgente y lo más accionable.
        let streak = games.suffix(losingStreak)
        if streak.count == losingStreak, streak.allSatisfy({ $0.winner == .them }) {
            let key = "racha-\(games.count)"
            if !alreadySaid.contains(key) {
                return LiveTip(
                    key: key,
                    text: "\(losingStreak) juegos seguidos. Cambia el patrón: globo y a la red."
                )
            }
        }

        let serving = games.filter { $0.server == .us }
        let returning = games.filter { $0.server == .them }
        if serving.count >= minGamesPerSide, returning.count >= minGamesPerSide {
            let pctServing = pct(serving)
            let pctReturning = pct(returning)
            if pctServing - pctReturning >= minSideGap, !alreadySaid.contains("saque-mejor") {
                return LiveTip(
                    key: "saque-mejor",
                    text: "Aguantas tu saque (\(pctServing)%) pero al resto vas a "
                        + "\(pctReturning)%. Presiona la primera bola."
                )
            }
            if pctReturning - pctServing >= minSideGap, !alreadySaid.contains("resto-mejor") {
                return LiveTip(
                    key: "resto-mejor",
                    text: "Restando ganas el \(pctReturning)% y sacando el \(pctServing)%. "
                        + "Asegura el primer saque y sube."
                )
            }
        }

        return nil
    }

    private static func pct(_ games: [GameRecord]) -> Int {
        Int((Float(games.filter { $0.winner == .us }.count) * 100 / Float(games.count)).rounded())
    }
}
