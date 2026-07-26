import Foundation

/// Marcador con historial para deshacer.
///
/// Puntuar mal es constante: se anota un punto al bando equivocado, o se anota dos veces
/// el mismo. Sin deshacer, un marcador en el reloj es inservible en cuanto pasa una vez,
/// porque no hay forma de recomponer el estado a mano.
///
/// Guarda el estado completo antes de cada punto en vez de intentar invertir la
/// transición. Un partido son unos 200 puntos: la memoria es irrelevante y a cambio
/// deshacer es exacto aunque el punto cerrara un juego, un set o el partido.
public final class ScoreBoard {
    private var history: [MatchScore] = []

    public private(set) var current: MatchScore

    public init(rules: ScoreRules = .default, firstServer: Side = .us) {
        self.current = MatchScore.start(rules: rules, firstServer: firstServer)
    }

    public var canUndo: Bool { !history.isEmpty }

    @discardableResult
    public func point(to side: Side) -> MatchScore {
        guard !current.isFinished else { return current }
        history.append(current)
        current = current.pointTo(side)
        return current
    }

    /// Devuelve el estado restaurado, o nil si no había nada que deshacer.
    @discardableResult
    public func undo() -> MatchScore? {
        guard let previous = history.popLast() else { return nil }
        current = previous
        return previous
    }

    public func reset(rules: ScoreRules? = nil, firstServer: Side = .us) {
        history.removeAll()
        current = MatchScore.start(rules: rules ?? current.rules, firstServer: firstServer)
    }

    /// Restaura un marcador ya empezado, por ejemplo al recuperar una sesión interrumpida.
    public func restore(_ score: MatchScore) {
        history.removeAll()
        current = score
    }
}
