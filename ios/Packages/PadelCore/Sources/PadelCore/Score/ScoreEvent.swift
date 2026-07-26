import Foundation

/// Qué acaba de pasar al anotar un punto.
///
/// Los relojes lo usan para elegir la vibración: el jugador tiene que enterarse de que ha
/// cerrado un juego o un set sin mirar la pantalla. Vive en el core y no en cada app
/// porque es una comparación entre dos marcadores, no una decisión de interfaz.
public enum ScoreEvent: Sendable {
    case point
    case game
    case set
    case match
    case undo

    public static func between(before: MatchScore, after: MatchScore) -> ScoreEvent {
        if after.isFinished { return .match }
        if after.completedSets.count > before.completedSets.count { return .set }
        if after.currentSet != before.currentSet { return .game }
        return .point
    }
}
