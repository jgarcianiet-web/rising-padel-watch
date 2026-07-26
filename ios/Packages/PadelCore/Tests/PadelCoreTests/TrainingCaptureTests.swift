import XCTest
@testable import PadelCore

/// Traducción de `TrainingCaptureTest.kt`: los dos cores deben recortar la misma ventana.
final class TrainingCaptureTests: XCTestCase {

    private let source = SourceInfo(platform: .wearos, device: "Pixel Watch 3", appVersion: "1.0.0")

    private func makeRecorder(alias: String = "jugador-1", label: ShotType = .forehand) -> TrainingRecorder {
        let recorder = TrainingRecorder(
            source: source,
            profile: PlayerProfile(),
            sampleIdProvider: { "sample-fijo" },
            nowEpochMs: { 1_785_002_652_000 }
        )
        recorder.label = label
        recorder.playerAlias = alias
        return recorder
    }

    /// Un golpeo con reposo antes y después, para que la ventana quepa entera.
    private func golpeoConMargen() -> [MotionSample] {
        MotionFixtures.rest(startMs: 0, durationMs: 1_500)
            + MotionFixtures.forehand(startMs: 1_500)
            + MotionFixtures.rest(startMs: 1_820, durationMs: 1_500)
    }

    private func recordAll(_ recorder: TrainingRecorder, _ samples: [MotionSample]) -> [TrainingSample] {
        var captured = samples.flatMap { recorder.onMotion($0) }
        captured += recorder.stop()
        return captured
    }

    // MARK: Recorte de la ventana

    func testCapturaUnaMuestraPorGolpeoDetectado() {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        XCTAssertEqual(recordAll(recorder, golpeoConMargen()).count, 1)
        XCTAssertEqual(recorder.capturedCount, 1)
    }

    func testLaVentanaVaDeUnSegundoAntesAUnSegundoDespuesDelImpacto() throws {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        let sample = try XCTUnwrap(recordAll(recorder, golpeoConMargen()).first)

        XCTAssertLessThanOrEqual(try XCTUnwrap(sample.offsetsMs.first), -900, "falta señal previa")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sample.offsetsMs.last), 900, "falta señal posterior")
        // 2 s a 50 Hz son unas 100 muestras.
        XCTAssertTrue((95...106).contains(sample.sampleCount), "muestras inesperadas: \(sample.sampleCount)")
    }

    func testElImpactoQuedaEnElCentroYSuOffsetEsCero() throws {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        let sample = try XCTUnwrap(recordAll(recorder, golpeoConMargen()).first)

        XCTAssertEqual(sample.offsetsMs[sample.impactIndex], 0, "el impacto debe estar en el offset 0")
        XCTAssertLessThanOrEqual(
            abs(sample.impactIndex - sample.sampleCount / 2), 3,
            "el impacto debería quedar centrado"
        )
    }

    func testLaVentanaNoSeEmiteHastaQueLlegaLaColaPosterior() {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)

        let hastaElImpacto = MotionFixtures.rest(startMs: 0, durationMs: 1_500)
            + MotionFixtures.forehand(startMs: 1_500)
        XCTAssertTrue(
            hastaElImpacto.flatMap { recorder.onMotion($0) }.isEmpty,
            "no puede emitirse sin el segundo posterior"
        )

        let despues = MotionFixtures.rest(startMs: 1_820, durationMs: 1_500)
            .flatMap { recorder.onMotion($0) }
        XCTAssertEqual(despues.count, 1, "al llegar la cola sí se emite")
    }

    func testStopCierraElUltimoGolpeoAunqueLeFalteCola() {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        // La tanda acaba justo tras el golpeo: sin flush se perdería uno de cada treinta.
        for sample in MotionFixtures.rest(startMs: 0, durationMs: 1_500)
            + MotionFixtures.forehand(startMs: 1_500) {
            _ = recorder.onMotion(sample)
        }
        XCTAssertEqual(recorder.stop().count, 1)
    }

    func testUnaTandaDeTreintaGolpeosCapturaLosTreinta() {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)

        var samples: [MotionSample] = []
        var t: Int64 = 0
        samples += MotionFixtures.rest(startMs: t, durationMs: 1_500); t += 1_500
        for _ in 0..<30 {
            samples += MotionFixtures.forehand(startMs: t); t += 320
            samples += MotionFixtures.rest(startMs: t, durationMs: 1_200); t += 1_200
        }
        XCTAssertEqual(recordAll(recorder, samples).count, 30)
    }

    // MARK: Etiquetado y metadatos

    func testLaEtiquetaEsLaQueEligioElJugadorNoLaQueAdivinoLaHeuristica() throws {
        // Se graba una tanda de reveses pero la señal es de derecha: la etiqueta manda.
        let recorder = makeRecorder(label: .backhand)
        recorder.start(monotonicMs: 0)
        let sample = try XCTUnwrap(recordAll(recorder, golpeoConMargen()).first)

        XCTAssertEqual(sample.label, .backhand, "la etiqueta la pone el jugador")
        XCTAssertEqual(sample.heuristicPrediction, .forehand, "y se guarda lo que dijo la heurística")
        XCTAssertFalse(sample.heuristicWasRight, "aquí la heurística no acertaría")
    }

    func testGuardaElAliasDelJugadorParaPoderValidarDejandoloFuera() throws {
        let recorder = makeRecorder(alias: "marta")
        recorder.start(monotonicMs: 0)
        XCTAssertEqual(try XCTUnwrap(recordAll(recorder, golpeoConMargen()).first).playerAlias, "marta")
    }

    func testGuardaLasTresSeriesCrudasAlineadas() throws {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        let sample = try XCTUnwrap(recordAll(recorder, golpeoConMargen()).first)

        XCTAssertEqual(sample.accel.count, sample.sampleCount)
        XCTAssertEqual(sample.gyro.count, sample.sampleCount)
        XCTAssertEqual(sample.gravity.count, sample.sampleCount)
        XCTAssertTrue(sample.accel.allSatisfy { $0.count == 3 }, "cada muestra son tres ejes")
    }

    // MARK: Memoria y ciclo de vida

    func testElBufferNoCreceConLaDuracionDeLaSesion() {
        let capture = TrainingCapture(sampleRateHz: 50)
        // Media hora de señal sin ningún golpeo.
        for sample in MotionFixtures.rest(startMs: 0, durationMs: 1_800_000) {
            _ = capture.onSample(sample)
        }
        XCTAssertEqual(capture.pendingCount, 0)
        XCTAssertTrue(capture.flush().isEmpty)
    }

    func testSinStartNoSeCapturaNada() {
        let recorder = makeRecorder()
        XCTAssertTrue(golpeoConMargen().flatMap { recorder.onMotion($0) }.isEmpty)
        XCTAssertFalse(recorder.isRecording)
    }

    func testStartReiniciaElContadorEntreTandas() {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        _ = recordAll(recorder, golpeoConMargen())
        XCTAssertEqual(recorder.capturedCount, 1)

        recorder.start(monotonicMs: 10_000)
        XCTAssertEqual(recorder.capturedCount, 0, "cada tanda cuenta desde cero")
    }

    func testSoloSeCapturanLosGolpeosQueElDetectorEncuentra() {
        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        // Señal sin impacto: el detector no ve golpeo y no hay nada que capturar.
        let amago = MotionFixtures.swing(
            startMs: 1_500, peakGyroRadS: 18, swingDurationMs: 300, impactG: 0,
            axialFraction: 0.8, elevationDeg: 10
        )
        let samples = MotionFixtures.rest(startMs: 0, durationMs: 1_500)
            + amago
            + MotionFixtures.rest(startMs: 1_820, durationMs: 1_500)

        XCTAssertTrue(recordAll(recorder, samples).isEmpty)
    }

    func testElDetectorStandaloneYElDelGrabadorVenLosMismosGolpeos() {
        let detector = ShotDetector()
        detector.reset(referenceTimestampMs: 0)
        let samples = golpeoConMargen()
        var directos = samples.compactMap { detector.process($0) }.count
        if detector.flush() != nil { directos += 1 }

        let recorder = makeRecorder()
        recorder.start(monotonicMs: 0)
        let capturados = recordAll(recorder, samples).count

        XCTAssertEqual(directos, capturados, "grabar no debe cambiar qué golpeos se detectan")
    }
}
