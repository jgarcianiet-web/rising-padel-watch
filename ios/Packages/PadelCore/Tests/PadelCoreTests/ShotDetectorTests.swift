import XCTest
@testable import PadelCore

final class ShotDetectorTests: XCTestCase {

    private func detect(_ samples: [MotionSample], config: DetectorConfig = .default) -> [Shot] {
        let detector = ShotDetector(config: config)
        detector.reset(referenceTimestampMs: samples.first?.timestampMs)
        var shots = samples.compactMap { detector.process($0) }
        if let trailing = detector.flush() { shots.append(trailing) }
        return shots
    }

    /// Swing corto para poder encadenar dos sin que se solapen en el tiempo.
    private func golpeoCorto(startMs: Int64) -> [MotionSample] {
        MotionFixtures.swing(
            startMs: startMs,
            peakGyroRadS: 20,
            swingDurationMs: 160,
            impactG: 6,
            axialFraction: 0.8,
            elevationDeg: 10
        )
    }

    func testDetectaUnGolpeoAislado() {
        let shots = detect(MotionFixtures.rest(startMs: 0, durationMs: 400)
            + MotionFixtures.forehand(startMs: 400))
        XCTAssertEqual(shots.count, 1, "un swing con impacto debería dar exactamente un golpeo")
    }

    func testNoCuentaCorrerPorLaPista() {
        let shots = detect(MotionFixtures.running(startMs: 0, durationMs: 6_000))
        XCTAssertEqual(shots.count, 0, "el braceo de correr no debe contar como golpeo")
    }

    func testNoCuentaUnImpactoSinSwing() {
        let shots = detect(MotionFixtures.rest(startMs: 0, durationMs: 400)
            + MotionFixtures.tapWithoutSwing(startMs: 400))
        XCTAssertEqual(shots.count, 0, "un pico de aceleración sin rotación no es un golpeo")
    }

    func testNoCuentaUnSwingQueNoLlegaAImpactar() {
        let amago = MotionFixtures.swing(
            startMs: 400, peakGyroRadS: 18, swingDurationMs: 300, impactG: 0,
            axialFraction: 0.8, elevationDeg: 10
        )
        XCTAssertEqual(detect(MotionFixtures.rest(startMs: 0, durationMs: 400) + amago).count, 0)
    }

    func testElPeriodoRefractarioEvitaContarDosVecesElMismoGolpeo() {
        // Impactos a 200 ms: por debajo del refractario de 320 ms, es el rebote del mismo
        // golpeo y no dos golpeos distintos.
        let samples = MotionFixtures.rest(startMs: 0, durationMs: 400)
            + golpeoCorto(startMs: 400)
            + golpeoCorto(startMs: 600)
        XCTAssertEqual(detect(samples).count, 1)
    }

    func testCuentaDosGolpeosSeparadosPorUnIntercambioNormal() {
        // Impactos a 400 ms: por encima del refractario, son dos golpeos.
        let samples = MotionFixtures.rest(startMs: 0, durationMs: 400)
            + golpeoCorto(startMs: 400)
            + golpeoCorto(startMs: 800)
        XCTAssertEqual(detect(samples).count, 2)
    }

    func testCuentaTodosLosGolpeosDeUnPeloteoLargo() {
        var samples: [MotionSample] = []
        var t: Int64 = 0
        samples += MotionFixtures.rest(startMs: t, durationMs: 500); t += 500
        for _ in 0..<12 {
            samples += MotionFixtures.forehand(startMs: t); t += 320
            samples += MotionFixtures.rest(startMs: t, durationMs: 700); t += 700
        }
        XCTAssertEqual(detect(samples).count, 12)
    }

    func testElOffsetDelGolpeoEsRelativoAlInicioDeLaSesion() {
        let detector = ShotDetector()
        detector.reset(referenceTimestampMs: 10_000)
        let samples = MotionFixtures.rest(startMs: 10_000, durationMs: 400)
            + MotionFixtures.forehand(startMs: 10_400)
        let shot = samples.compactMap { detector.process($0) }.first
        let offset = try? XCTUnwrap(shot?.offsetMs)
        // El impacto cae al 75% de un swing de 300 ms que empieza en +400 ms.
        XCTAssertTrue((550...700).contains(offset ?? -1), "offset inesperado: \(String(describing: offset))")
    }

    func testEstimaVelocidadDePalaYGDeImpacto() throws {
        let shot = try XCTUnwrap(detect(MotionFixtures.rest(startMs: 0, durationMs: 400)
            + MotionFixtures.forehand(startMs: 400)).first)
        // 20 rad/s * 0.65 m * 3.6 ≈ 47 km/h
        XCTAssertTrue((40...55).contains(shot.racketSpeedKmh), "velocidad inesperada: \(shot.racketSpeedKmh)")
        XCTAssertTrue((5...8).contains(shot.impactG), "impacto inesperado: \(shot.impactG)")
    }

    func testLaSensibilidadBajaDescartaGolpeosFlojosQueLaAltaSiDetecta() {
        let flojo = MotionFixtures.rest(startMs: 0, durationMs: 400) + MotionFixtures.swing(
            startMs: 400, peakGyroRadS: 6.5, swingDurationMs: 280, impactG: 3.4,
            axialFraction: 0.7, elevationDeg: 10
        )
        XCTAssertEqual(detect(flojo, config: .default.withSensitivity(.low)).count, 0,
                       "con sensibilidad baja no debería contar")
        XCTAssertEqual(detect(flojo, config: .default.withSensitivity(.high)).count, 1,
                       "con sensibilidad alta sí debería contar")
    }

    func testUnHuecoEnLasMuestrasNoInflaElAnguloBarrido() {
        // Simula la app suspendida 2 s en mitad del swing: el dt se acota a 100 ms.
        let swing = MotionFixtures.forehand(startMs: 400)
        let conHueco = swing.prefix(6) + swing.dropFirst(6).map {
            MotionSample(timestampMs: $0.timestampMs + 2_000, accel: $0.accel,
                         gyro: $0.gyro, gravity: $0.gravity)
        }
        for shot in detect(MotionFixtures.rest(startMs: 0, durationMs: 400) + Array(conHueco)) {
            XCTAssertLessThan(shot.features.sweptAngleDeg, 720,
                              "el hueco infló el ángulo barrido: \(shot.features.sweptAngleDeg)")
        }
    }

    func testResetLimpiaElEstadoEntreSesiones() throws {
        let detector = ShotDetector()
        detector.reset(referenceTimestampMs: 0)
        for sample in MotionFixtures.forehand(startMs: 0) { detector.process(sample) }
        detector.reset(referenceTimestampMs: 10_000)
        let shots = (MotionFixtures.rest(startMs: 10_000, durationMs: 400)
            + MotionFixtures.forehand(startMs: 10_400)).compactMap { detector.process($0) }
        XCTAssertEqual(shots.count, 1)
        XCTAssertLessThan(try XCTUnwrap(shots.first).offsetMs, 1_000)
    }

    func testClasificaLosGolpeosTipo() throws {
        let cases: [(ShotType, [MotionSample])] = [
            (.forehand, MotionFixtures.forehand(startMs: 400)),
            (.backhand, MotionFixtures.backhand(startMs: 400)),
            (.forehandVolley, MotionFixtures.forehandVolley(startMs: 400)),
            (.backhandVolley, MotionFixtures.backhandVolley(startMs: 400)),
            (.bandeja, MotionFixtures.bandeja(startMs: 400)),
            (.vibora, MotionFixtures.vibora(startMs: 400)),
            (.smash, MotionFixtures.smash(startMs: 400)),
            (.serve, MotionFixtures.serve(startMs: 400)),
        ]
        for (expected, samples) in cases {
            let detected = detect(MotionFixtures.rest(startMs: 0, durationMs: 400) + samples)
            let shot = try XCTUnwrap(detected.first, "no se detectó el golpeo esperado \(expected)")
            XCTAssertEqual(shot.type, expected,
                           "clasificación incorrecta (confianza \(shot.confidence), rasgos \(shot.features))")
        }
    }
}
