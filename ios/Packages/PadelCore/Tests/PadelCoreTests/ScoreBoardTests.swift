import XCTest
@testable import PadelCore

/// Traducción exacta de `ScoreBoardTest.kt`.
final class ScoreBoardTests: XCTestCase {

    func testDeshacerDevuelveExactamenteElEstadoAnterior() {
        let board = ScoreBoard()
        board.point(to: .us)
        let before = board.current
        board.point(to: .them)

        XCTAssertEqual(board.undo(), before)
        XCTAssertEqual(board.current, before)
    }

    func testDeshacerFuncionaATravesDeUnJuegoCerrado() {
        let board = ScoreBoard()
        for _ in 0..<3 { board.point(to: .us) }
        let atForty = board.current
        XCTAssertEqual(atForty.pointsLabel(.us), "40")

        board.point(to: .us)
        XCTAssertEqual(board.current.currentSet.us, 1, "el juego se cerró")

        board.undo()
        XCTAssertEqual(board.current, atForty, "deshacer reabre el juego")
        XCTAssertEqual(board.current.currentSet.us, 0)
    }

    func testDeshacerFuncionaATravesDeUnSetCerrado() {
        let board = ScoreBoard()
        for _ in 0..<5 { for _ in 0..<4 { board.point(to: .us) } }
        for _ in 0..<3 { board.point(to: .us) }
        let beforeSetPoint = board.current
        XCTAssertEqual(beforeSetPoint.currentSet.us, 5)

        board.point(to: .us)
        XCTAssertEqual(board.current.completedSets.count, 1, "el set se cerró")

        board.undo()
        XCTAssertEqual(board.current, beforeSetPoint, "deshacer reabre el set")
        XCTAssertTrue(board.current.completedSets.isEmpty)
    }

    func testDeshacerVariasVecesSeguidasRetrocedePuntoAPunto() {
        let board = ScoreBoard()
        let start = board.current
        board.point(to: .us)
        let afterFirst = board.current
        board.point(to: .them)
        board.point(to: .us)

        board.undo()
        board.undo()
        XCTAssertEqual(board.current, afterFirst)

        board.undo()
        XCTAssertEqual(board.current, start)
    }

    func testSinPuntosAnotadosNoHayNadaQueDeshacer() {
        let board = ScoreBoard()
        XCTAssertFalse(board.canUndo)
        XCTAssertNil(board.undo())
    }

    func testCanUndoReflejaSiQuedaHistorial() {
        let board = ScoreBoard()
        XCTAssertFalse(board.canUndo)
        board.point(to: .us)
        XCTAssertTrue(board.canUndo)
        board.undo()
        XCTAssertFalse(board.canUndo)
    }

    func testUnPartidoTerminadoNoAceptaMasPuntosNiCreceElHistorial() {
        let board = ScoreBoard(rules: ScoreRules(setsToWin: 1))
        for _ in 0..<(6 * 4) { board.point(to: .us) }
        XCTAssertEqual(board.current.winner, .us)

        let finished = board.current
        board.point(to: .them)
        XCTAssertEqual(board.current, finished)

        board.undo()
        XCTAssertEqual(
            board.current.currentSet.us,
            5,
            "deshacer sobre un partido terminado retrocede el punto que lo cerró"
        )
    }

    func testResetVuelveAlPrincipioYLimpiaElHistorial() {
        let board = ScoreBoard()
        for _ in 0..<5 { board.point(to: .us) }
        board.reset(firstServer: .them)

        XCTAssertFalse(board.canUndo)
        XCTAssertEqual(board.current.currentSet.us, 0)
        XCTAssertEqual(board.current.server, .them)
    }

    func testRestoreRecuperaUnMarcadorYaEmpezado() {
        let board = ScoreBoard()
        board.point(to: .us)
        let saved = board.current

        let other = ScoreBoard()
        other.restore(saved)

        XCTAssertEqual(other.current, saved)
        XCTAssertFalse(other.canUndo, "un marcador restaurado no arrastra historial ajeno")
    }
}
