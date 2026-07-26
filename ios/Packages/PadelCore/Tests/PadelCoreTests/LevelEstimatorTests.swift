import XCTest
@testable import PadelCore

final class LevelEstimatorTests: XCTestCase {

    private let estimator = LevelEstimator()

    private func shot(
        type: ShotType = .forehand,
        speedKmh: Float = 45,
        sweptDeg: Float = 200,
        confidence: Float = 0.9,
        offsetMs: Int64 = 0
    ) -> Shot {
        Shot(
            offsetMs: offsetMs,
            type: type,
            racketSpeedKmh: speedKmh,
            impactG: 5,
            confidence: confidence,
            features: ShotFeatures(
                sweptAngleDeg: sweptDeg,
                peakGyroRadS: speedKmh / 2.34,
                elevationDeg: 20,
                axialRotationRadS: 3,
                swingDurationMs: 300
            )
        )
    }

    // MARK: nota de un golpeo suelto

    func testUnaDerechaEnElExtremoBajoDeLaBanda() throws {
        let grade = try XCTUnwrap(estimator.grade(shot(speedKmh: 28, sweptDeg: 200)))

        // Velocidad en el mínimo, swing perfecto: solo puntúa la parte de swing.
        XCTAssertEqual(grade, 1 + 0.35 * 6, accuracy: 0.1)
    }

    func testUnaDerechaEnElExtremoAltoPuntua7() {
        XCTAssertEqual(estimator.grade(shot(speedKmh: 65, sweptDeg: 200)), 7)
    }

    func testPasarseDeLaBandaNoPuntuaMasDe7() {
        XCTAssertEqual(estimator.grade(shot(speedKmh: 200, sweptDeg: 400)), 7)
    }

    func testUnGolpeoDeTipoDesconocidoNoPuntua() {
        XCTAssertNil(estimator.grade(shot(type: .unknown)))
    }

    /// Puntuar un golpeo que no se sabe qué es sería inventar.
    func testUnGolpeoMalClasificadoNoPuntua() {
        XCTAssertNil(estimator.grade(shot(confidence: 0.2)))
    }

    // MARK: la asimetría de la volea

    func testUnaVoleaCompactaPuntuaMejorQueUnaConSwingLargo() throws {
        let compacta = try XCTUnwrap(
            estimator.grade(shot(type: .forehandVolley, speedKmh: 18, sweptDeg: 40))
        )
        let larga = try XCTUnwrap(
            estimator.grade(shot(type: .forehandVolley, speedKmh: 18, sweptDeg: 85))
        )

        XCTAssertGreaterThan(compacta, larga, "la volea se bloquea, no se golpea")
    }

    func testEnLaDerechaEnCambioElSwingCortoPenaliza() throws {
        let completa = try XCTUnwrap(estimator.grade(shot(speedKmh: 45, sweptDeg: 200)))
        let corta = try XCTUnwrap(estimator.grade(shot(speedKmh: 45, sweptDeg: 80)))

        XCTAssertGreaterThan(completa, corta)
    }

    // MARK: nivel de la sesión

    func testSinGolpeosClasificablesElNivelNoEsFiable() {
        let level = estimator.estimate((0..<50).map { _ in shot(type: .unknown) })

        XCTAssertFalse(level.reliable)
        XCTAssertEqual(level.gradedShots, 0)
    }

    func testConPocosGolpeosSeCalculaPeroNoEsFiable() {
        let level = estimator.estimate((0..<10).map { _ in shot(speedKmh: 45) })

        XCTAssertFalse(level.reliable)
        XCTAssertGreaterThan(level.overall, 1, "se sigue dando una estimación, solo que avisando")
    }

    func testConGolpeosSuficientesElNivelEsFiable() {
        let level = estimator.estimate((0..<40).map { _ in shot(speedKmh: 45) })

        XCTAssertTrue(level.reliable)
        XCTAssertEqual(level.gradedShots, 40)
    }

    func testUnJugadorMasRapidoSacaMasNivel() {
        let flojo = estimator.estimate((0..<40).map { _ in shot(speedKmh: 32) })
        let fuerte = estimator.estimate((0..<40).map { _ in shot(speedKmh: 60) })

        XCTAssertGreaterThan(fuerte.overall, flojo.overall)
    }

    /// En pádel el nivel **es** regularidad: misma punta, distinta constancia.
    func testAIgualMediaElRegularSacaMasNivelQueElIrregular() {
        let regular = estimator.estimate((0..<40).map { _ in shot(speedKmh: 46) })
        let irregular = estimator.estimate(
            (0..<40).map { index in shot(speedKmh: index % 2 == 0 ? 30 : 62) }
        )

        XCTAssertGreaterThan(regular.overall, irregular.overall)
        XCTAssertGreaterThan(regular.consistency, irregular.consistency)
    }

    func testLaRegularidadSeMideDentroDeCadaTipo() {
        // Voleas lentas y derechas rápidas: es lo normal, no es irregularidad.
        let mixto = (0..<20).map { _ in shot(type: .forehand, speedKmh: 46) }
            + (0..<20).map { _ in shot(type: .forehandVolley, speedKmh: 18) }

        XCTAssertGreaterThan(estimator.estimate(mixto).consistency, 0.9)
    }

    /// Penalizar una sesión de solo derechas sería castigar entrenar.
    func testElRepertorioSumaPeroNuncaResta() {
        let soloDerechas = estimator.estimate((0..<40).map { _ in shot(speedKmh: 46) })
        let completo = estimator.estimate(
            ShotType.allCases.filter { $0 != .unknown }.flatMap { type in
                (0..<10).map { _ in
                    shot(type: type, speedKmh: midBandSpeed(type), sweptDeg: idealSwept(type))
                }
            }
        )

        XCTAssertGreaterThanOrEqual(soloDerechas.repertoire, 0)
        XCTAssertGreaterThan(completo.repertoire, soloDerechas.repertoire)
        XCTAssertGreaterThan(completo.overall, soloDerechas.overall)
    }

    func testLaMediaEsPorTipoDeGolpeYNoPorGolpeoSuelto() {
        // 100 derechas flojas y 10 smashes buenos. Si la media fuera por golpeo, los
        // smashes no se notarían; siendo por tipo, pesan igual que las derechas.
        let sesion = (0..<100).map { _ in shot(type: .forehand, speedKmh: 30) }
            + (0..<10).map { _ in shot(type: .overhead, speedKmh: 88, sweptDeg: 200) }

        let level = estimator.estimate(sesion)
        let soloDerechas = estimator.estimate((0..<100).map { _ in shot(type: .forehand, speedKmh: 30) })

        XCTAssertGreaterThan(level.overall, soloDerechas.overall)
    }

    func testElDesgloseSoloTraeLosTiposJugados() {
        let level = estimator.estimate(
            (0..<20).map { _ in shot(type: .forehand) } + (0..<20).map { _ in shot(type: .serve) }
        )

        XCTAssertEqual(Set(level.byShotType.keys), Set([ShotType.forehand, .serve]))
    }

    func testElNivelNuncaSeSaleDeLaEscala() {
        let bestial = estimator.estimate(
            ShotType.allCases.filter { $0 != .unknown }.flatMap { type in
                (0..<20).map { _ in shot(type: type, speedKmh: 500, sweptDeg: idealSwept(type)) }
            }
        )
        let flojisimo = estimator.estimate((0..<40).map { _ in shot(speedKmh: 1, sweptDeg: 1) })

        XCTAssertLessThanOrEqual(bestial.overall, 7)
        XCTAssertGreaterThanOrEqual(flojisimo.overall, 1)
    }

    func testElNivelRedondeadoVaDeMedioEnMedio() {
        let level = SessionLevel(
            overall: 4.37,
            byShotType: [:],
            consistency: 1,
            repertoire: 0,
            gradedShots: 40,
            reliable: true
        )

        XCTAssertEqual(level.rounded, 4.5)
    }

    func testUnaSesionVaciaNoRevienta() {
        let level = estimator.estimate([])

        XCTAssertEqual(level.gradedShots, 0)
        XCTAssertFalse(level.reliable)
    }

    private func midBandSpeed(_ type: ShotType) -> Float {
        let band = LevelConfig.defaultBands[type]!
        return (band.speedAtLevel1 + band.speedAtLevel7) / 2
    }

    private func idealSwept(_ type: ShotType) -> Float {
        LevelConfig.defaultBands[type]!.idealSweptDeg
    }
}
