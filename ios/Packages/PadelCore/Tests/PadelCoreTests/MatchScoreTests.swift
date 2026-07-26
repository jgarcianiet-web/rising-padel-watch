import XCTest
@testable import PadelCore

/// Traducción exacta de `MatchScoreTest.kt`: los dos cores deben puntuar igual.
final class MatchScoreTests: XCTestCase {

    private func play(_ score: MatchScore, _ sides: [Side]) -> MatchScore {
        sides.reduce(score) { $0.pointTo($1) }
    }

    /// Cuatro puntos seguidos ganan un juego desde 0-0 con cualquier reglamento.
    private func winGame(_ score: MatchScore, _ side: Side) -> MatchScore {
        (1...4).reduce(score) { state, _ in state.pointTo(side) }
    }

    private func winGames(_ score: MatchScore, _ side: Side, _ count: Int) -> MatchScore {
        (1...count).reduce(score) { state, _ in winGame(state, side) }
    }

    /// Deja el set en 6-6, listo para tie-break.
    private func sixAll() -> MatchScore {
        (1...6).reduce(MatchScore.start()) { state, _ in
            winGame(winGame(state, .us), .them)
        }
    }

    // MARK: Puntuación dentro del juego

    func testLosPuntosVan0153040YJuego() {
        var score = MatchScore.start()
        XCTAssertEqual(score.pointsLabel(.us), "0")
        score = score.pointTo(.us)
        XCTAssertEqual(score.pointsLabel(.us), "15")
        score = score.pointTo(.us)
        XCTAssertEqual(score.pointsLabel(.us), "30")
        score = score.pointTo(.us)
        XCTAssertEqual(score.pointsLabel(.us), "40")
        score = score.pointTo(.us)
        XCTAssertEqual(score.currentSet.us, 1, "el cuarto punto cierra el juego")
        XCTAssertEqual(score.pointsLabel(.us), "0", "el marcador de juego se reinicia")
    }

    func testConPuntoDeOroEl40IgualesLoDecideElSiguientePunto() {
        let deuce = play(MatchScore.start(), [.us, .us, .us, .them, .them, .them])
        XCTAssertEqual(deuce.pointsLabel(.us), "40")
        XCTAssertEqual(deuce.pointsLabel(.them), "40")

        let decided = deuce.pointTo(.them)
        XCTAssertEqual(decided.currentSet.them, 1, "el punto de oro cierra el juego sin ventaja")
        XCTAssertEqual(decided.currentSet.us, 0)
    }

    func testSinPuntoDeOroHaceFaltaSacarDosDeDiferencia() {
        let rules = ScoreRules(goldenPoint: false)
        let deuce = play(MatchScore.start(rules: rules), [.us, .us, .us, .them, .them, .them])

        let advantage = deuce.pointTo(.us)
        XCTAssertEqual(advantage.pointsLabel(.us), "AD")
        XCTAssertEqual(advantage.currentSet.us, 0, "la ventaja todavía no es juego")

        let backToDeuce = advantage.pointTo(.them)
        XCTAssertEqual(backToDeuce.pointsLabel(.us), "40", "se vuelve a iguales")
        XCTAssertEqual(backToDeuce.pointsLabel(.them), "40")

        let game = play(backToDeuce, [.us, .us])
        XCTAssertEqual(game.currentSet.us, 1, "dos puntos seguidos desde iguales sí ganan el juego")
    }

    func testElSaqueAlternaEnCadaJuego() {
        let start = MatchScore.start(firstServer: .us)
        XCTAssertEqual(start.server, .us)
        XCTAssertEqual(winGame(start, .us).server, .them)
        XCTAssertEqual(winGame(winGame(start, .us), .them).server, .us)
    }

    // MARK: Sets

    func testGanaElSetASeisJuegosConDosDeDiferencia() {
        let score = winGames(MatchScore.start(), .us, 6)
        XCTAssertEqual(score.completedSets, [SetScore(us: 6, them: 0)])
        XCTAssertEqual(score.setsWon(.us), 1)
    }

    func testA65ElSetSigueEnJuego() {
        var score = MatchScore.start()
        for _ in 0..<5 { score = winGame(winGame(score, .us), .them) }
        score = winGame(score, .us)

        XCTAssertEqual(score.currentSet, SetScore(us: 6, them: 5))
        XCTAssertTrue(score.completedSets.isEmpty, "6-5 no cierra el set")
        XCTAssertFalse(score.isTieBreak)

        score = winGame(score, .us)
        XCTAssertEqual(score.completedSets, [SetScore(us: 7, them: 5)], "7-5 sí lo cierra")
    }

    // MARK: Tie-break

    func testA66SeJuegaTieBreakYLosPuntosSeCuentanCrudos() {
        let score = sixAll()
        XCTAssertTrue(score.isTieBreak)
        XCTAssertEqual(score.pointTo(.us).pointsLabel(.us), "1", "en tie-break no hay 15/30/40")
    }

    func testElTieBreakSeGanaASieteConDosDeDiferencia() {
        var score = sixAll()
        for _ in 0..<6 { score = play(score, [.us, .them]) }
        XCTAssertEqual(score.usPoints, 6)
        XCTAssertEqual(score.themPoints, 6)

        score = score.pointTo(.us)
        XCTAssertTrue(score.completedSets.isEmpty, "7-6 no cierra el tie-break")

        score = score.pointTo(.us)
        XCTAssertEqual(score.completedSets, [SetScore(us: 7, them: 6)], "8-6 sí lo cierra")
    }

    func testEnElTieBreakSacaUnoUnPuntoYLuegoSeAlternaCadaDos() {
        let start = sixAll()
        let first = start.server

        var servers: [Side] = [start.server]
        var score = start
        for _ in 0..<4 {
            score = score.pointTo(.us)
            servers.append(score.server)
        }

        // Punto 1 lo saca quien abre; 2 y 3 el otro; 4 y 5 vuelve el primero.
        XCTAssertEqual(servers[0], first)
        XCTAssertEqual(servers[1], first.other)
        XCTAssertEqual(servers[2], first.other)
        XCTAssertEqual(servers[3], first)
        XCTAssertEqual(servers[4], first)
    }

    func testQuienAbreElTieBreakRestaPrimeroEnElSetSiguiente() {
        let tieBreak = sixAll()
        let opener = tieBreak.server

        let afterSet = (1...7).reduce(tieBreak) { state, _ in state.pointTo(.us) }
        XCTAssertEqual(afterSet.completedSets, [SetScore(us: 7, them: 6)])
        XCTAssertEqual(afterSet.server, opener.other, "el que abrió el tie-break resta")
    }

    // MARK: Partido

    func testGanaElPartidoQuienGanaDosSets() {
        let score = winGames(MatchScore.start(), .us, 12)
        XCTAssertEqual(score.winner, .us)
        XCTAssertTrue(score.isFinished)
        XCTAssertEqual(score.completedSets.count, 2)
    }

    func testUnPartidoAUnSetSeDecideConEseSet() {
        let score = winGames(MatchScore.start(rules: ScoreRules(setsToWin: 1)), .us, 6)
        XCTAssertEqual(score.winner, .us)
    }

    func testConElPartidoTerminadoNoSeAnotanMasPuntos() {
        let finished = winGames(MatchScore.start(), .us, 12)
        XCTAssertEqual(finished, finished.pointTo(.them), "el estado no cambia")
    }

    // MARK: Cambio de pista

    func testSeCambiaDePistaTrasCadaJuegoImpar() {
        let afterFirst = winGame(MatchScore.start(), .us)
        XCTAssertTrue(afterFirst.changeEndsPending, "tras el juego 1 se cambia")

        let afterSecond = winGame(afterFirst, .them)
        XCTAssertFalse(afterSecond.changeEndsPending, "tras el juego 2 no")

        let afterThird = winGame(afterSecond, .us)
        XCTAssertTrue(afterThird.changeEndsPending, "tras el juego 3 sí")
    }

    func testElAvisoDeCambioDePistaSeApagaAlSiguientePunto() {
        let afterGame = winGame(MatchScore.start(), .us)
        XCTAssertTrue(afterGame.changeEndsPending)
        XCTAssertFalse(afterGame.pointTo(.us).changeEndsPending)
    }

    func testEnElTieBreakSeCambiaDePistaCadaSeisPuntos() {
        var score = sixAll()
        for _ in 0..<5 { score = score.pointTo(.us) }
        XCTAssertFalse(score.changeEndsPending, "a los 5 puntos todavía no")

        score = score.pointTo(.them)
        XCTAssertTrue(score.changeEndsPending, "a los 6 puntos sí")
    }

    // MARK: Lectura del marcador

    func testAllSetsIncluyeElSetEnJuegoSoloSiYaTieneJuegos() {
        XCTAssertEqual(MatchScore.start().allSets, [SetScore(us: 0, them: 0)])

        let midSecondSet = winGame(winGames(MatchScore.start(), .us, 6), .them)
        XCTAssertEqual(
            midSecondSet.allSets,
            [SetScore(us: 6, them: 0), SetScore(us: 0, them: 1)]
        )
    }

    func testElGanadorEsNuloMientrasElPartidoSigue() {
        XCTAssertNil(winGames(MatchScore.start(), .us, 6).winner, "un set no gana el partido")
    }
}
