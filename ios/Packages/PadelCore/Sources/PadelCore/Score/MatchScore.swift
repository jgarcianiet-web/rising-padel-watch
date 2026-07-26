import Foundation

/// Los dos bandos de un partido de pádel, desde el punto de vista del jugador.
public enum Side: String, Codable, CaseIterable, Sendable {
    case us
    case them

    public var wireName: String { rawValue }

    public var other: Side { self == .us ? .them : .us }

    public static func fromWire(_ value: String) -> Side {
        value == "them" ? .them : .us
    }
}

/// Reglas del partido. Cambian de una liga a otra, así que son configurables.
///
/// `goldenPoint` (punto de oro: a 40-40 el siguiente punto decide el juego, sin
/// ventajas) viene activado por defecto porque es lo habitual en ligas amateur y en
/// circuito profesional.
public struct ScoreRules: Codable, Equatable, Sendable {
    public let goldenPoint: Bool
    public let setsToWin: Int
    public let gamesToWinSet: Int
    public let tieBreakTarget: Int

    public init(
        goldenPoint: Bool = true,
        setsToWin: Int = 2,
        gamesToWinSet: Int = 6,
        tieBreakTarget: Int = 7
    ) {
        self.goldenPoint = goldenPoint
        self.setsToWin = setsToWin
        self.gamesToWinSet = gamesToWinSet
        self.tieBreakTarget = tieBreakTarget
    }

    public static let `default` = ScoreRules()
}

/// Juegos ganados por cada bando en un set.
public struct SetScore: Codable, Equatable, Sendable {
    public let us: Int
    public let them: Int

    public init(us: Int = 0, them: Int = 0) {
        self.us = us
        self.them = them
    }

    public func plus(_ side: Side) -> SetScore {
        side == .us ? SetScore(us: us + 1, them: them) : SetScore(us: us, them: them + 1)
    }

    public func forSide(_ side: Side) -> Int { side == .us ? us : them }

    public var isEmpty: Bool { us == 0 && them == 0 }
}

/// Estado completo del marcador. Es inmutable: `pointTo` devuelve un estado nuevo.
///
/// Toda la lógica del marcador vive aquí, sin nada de UI ni de plataforma, para poder
/// verificarla con tests. Ver `docs/scoring.md`.
public struct MatchScore: Codable, Equatable, Sendable {
    public let rules: ScoreRules
    public let completedSets: [SetScore]
    public let currentSet: SetScore
    public let usPoints: Int
    public let themPoints: Int
    public let server: Side
    /// Quién abrió el tie-break, para rotar el saque y decidir quién saca en el set siguiente.
    public let tieBreakFirstServer: Side?
    public let winner: Side?
    /// True justo cuando acaba de tocar cambio de pista. Se apaga al siguiente punto.
    public let changeEndsPending: Bool

    public init(
        rules: ScoreRules = .default,
        completedSets: [SetScore] = [],
        currentSet: SetScore = SetScore(),
        usPoints: Int = 0,
        themPoints: Int = 0,
        server: Side = .us,
        tieBreakFirstServer: Side? = nil,
        winner: Side? = nil,
        changeEndsPending: Bool = false
    ) {
        self.rules = rules
        self.completedSets = completedSets
        self.currentSet = currentSet
        self.usPoints = usPoints
        self.themPoints = themPoints
        self.server = server
        self.tieBreakFirstServer = tieBreakFirstServer
        self.winner = winner
        self.changeEndsPending = changeEndsPending
    }

    public static func start(rules: ScoreRules = .default, firstServer: Side = .us) -> MatchScore {
        MatchScore(rules: rules, server: firstServer)
    }

    public var isFinished: Bool { winner != nil }

    /// En pádel el tie-break se juega al llegar a 6-6 en juegos.
    public var isTieBreak: Bool {
        !isFinished
            && currentSet.us == rules.gamesToWinSet
            && currentSet.them == rules.gamesToWinSet
    }

    /// Todos los sets, incluido el que está en juego si ya tiene algún juego.
    public var allSets: [SetScore] {
        if currentSet.isEmpty && !completedSets.isEmpty { return completedSets }
        return completedSets + [currentSet]
    }

    public func setsWon(_ side: Side) -> Int {
        completedSets.filter { $0.forSide(side) > $0.forSide(side.other) }.count
    }

    public func points(for side: Side) -> Int {
        side == .us ? usPoints : themPoints
    }

    /// Etiqueta del marcador de juego: `0`, `15`, `30`, `40`, `AD` o el número crudo en
    /// tie-break. Con punto de oro `AD` no aparece nunca, porque a 40-40 el siguiente
    /// punto cierra el juego.
    public func pointsLabel(_ side: Side) -> String {
        if isTieBreak { return String(points(for: side)) }
        let mine = points(for: side)
        let theirs = points(for: side.other)
        if mine >= 3 && theirs >= 3 {
            if mine == theirs { return "40" }
            return mine > theirs ? "AD" : "40"
        }
        return Self.pointLabels.indices.contains(mine) ? Self.pointLabels[mine] : "40"
    }

    /// Anota un punto. Si el partido ya terminó, no hace nada.
    public func pointTo(_ side: Side) -> MatchScore {
        guard !isFinished else { return self }
        return isTieBreak ? tieBreakPoint(side) : gamePoint(side)
    }

    // MARK: Juego normal

    private func gamePoint(_ side: Side) -> MatchScore {
        let mine = points(for: side) + 1
        let theirs = points(for: side.other)

        if gameWon(mine: mine, theirs: theirs) {
            return afterGameWon(side)
        }
        return withPoints(side, mine).with(changeEndsPending: false)
    }

    private func gameWon(mine: Int, theirs: Int) -> Bool {
        if rules.goldenPoint {
            // Punto de oro: desde 40-40 el siguiente punto decide, así que basta con
            // llegar a 4 por delante sin exigir dos de diferencia.
            return mine >= 4 && mine > theirs
        }
        return mine >= 4 && mine - theirs >= 2
    }

    private func afterGameWon(_ side: Side) -> MatchScore {
        let newSet = currentSet.plus(side)
        let gamesTotal = newSet.us + newSet.them
        // Se cambia de pista tras cada juego impar del set.
        let changeEnds = gamesTotal % 2 == 1

        if setWon(newSet, side) {
            return afterSetWon(newSet, side)
        }

        let reachedTieBreak = newSet.us == rules.gamesToWinSet && newSet.them == rules.gamesToWinSet
        return MatchScore(
            rules: rules,
            completedSets: completedSets,
            currentSet: newSet,
            usPoints: 0,
            themPoints: 0,
            server: server.other,
            tieBreakFirstServer: reachedTieBreak ? server.other : nil,
            winner: nil,
            changeEndsPending: changeEnds
        )
    }

    private func setWon(_ set: SetScore, _ side: Side) -> Bool {
        let mine = set.forSide(side)
        let theirs = set.forSide(side.other)
        return mine >= rules.gamesToWinSet && mine - theirs >= 2
    }

    // MARK: Tie-break

    private func tieBreakPoint(_ side: Side) -> MatchScore {
        let mine = points(for: side) + 1
        let theirs = points(for: side.other)

        if mine >= rules.tieBreakTarget && mine - theirs >= 2 {
            return afterSetWon(currentSet.plus(side), side)
        }

        let playedPoints = mine + theirs
        var next = withPoints(side, mine)
        next = next.with(
            server: tieBreakServer(after: playedPoints),
            // En el tie-break se cambia de pista cada seis puntos.
            changeEndsPending: playedPoints % 6 == 0
        )
        return next
    }

    /// En el tie-break saca uno un punto y a partir de ahí se alterna cada dos, de modo
    /// que cada bando saca siempre desde el mismo lado de la pista.
    private func tieBreakServer(after playedPoints: Int) -> Side {
        let first = tieBreakFirstServer ?? server
        let blocks = (playedPoints + 1) / 2
        return blocks % 2 == 0 ? first : first.other
    }

    // MARK: Cierre de set y de partido

    private func afterSetWon(_ set: SetScore, _ side: Side) -> MatchScore {
        let sets = completedSets + [set]
        let won = sets.filter { $0.forSide(side) > $0.forSide(side.other) }.count

        // Quien abrió el tie-break resta primero en el set siguiente.
        let nextServer = tieBreakFirstServer?.other ?? server.other

        return MatchScore(
            rules: rules,
            completedSets: sets,
            currentSet: SetScore(),
            usPoints: 0,
            themPoints: 0,
            server: nextServer,
            tieBreakFirstServer: nil,
            winner: won >= rules.setsToWin ? side : nil,
            // Al empezar un set se cambia de pista salvo que el set anterior sumara un
            // número par de juegos.
            changeEndsPending: (set.us + set.them) % 2 == 1
        )
    }

    // MARK: Ayudas

    private func withPoints(_ side: Side, _ value: Int) -> MatchScore {
        MatchScore(
            rules: rules,
            completedSets: completedSets,
            currentSet: currentSet,
            usPoints: side == .us ? value : usPoints,
            themPoints: side == .them ? value : themPoints,
            server: server,
            tieBreakFirstServer: tieBreakFirstServer,
            winner: winner,
            changeEndsPending: changeEndsPending
        )
    }

    private func with(server: Side? = nil, changeEndsPending: Bool) -> MatchScore {
        MatchScore(
            rules: rules,
            completedSets: completedSets,
            currentSet: currentSet,
            usPoints: usPoints,
            themPoints: themPoints,
            server: server ?? self.server,
            tieBreakFirstServer: tieBreakFirstServer,
            winner: winner,
            changeEndsPending: changeEndsPending
        )
    }

    private static let pointLabels = ["0", "15", "30", "40"]
}
