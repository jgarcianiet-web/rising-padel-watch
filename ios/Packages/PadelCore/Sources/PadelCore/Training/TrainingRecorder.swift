import Foundation

/// Graba tandas de golpeos etiquetados para entrenar el clasificador.
///
/// El jugador elige un tipo de golpe y da 30-40 seguidos solo de ese tipo. Cada golpeo
/// que detecta la heurística se guarda con su ventana cruda y la etiqueta ya puesta.
///
/// Reutiliza el mismo `ShotDetector` de siempre: interesa entrenar el clasificador con
/// los golpeos que el detector **realmente** encuentra en pista, no con una selección
/// ideal. Si el detector se deja golpeos, eso es un problema del detector y se arregla
/// ahí, no maquillando el conjunto de entrenamiento.
///
/// Ver `docs/training-data.md`.
public final class TrainingRecorder {
    private let source: SourceInfo
    private let profile: PlayerProfile
    private let config: DetectorConfig
    private let detector: ShotDetector
    private let capture: TrainingCapture
    private let sampleIdProvider: () -> String
    private let nowEpochMs: () -> Int64

    private var referenceMs: Int64 = 0
    private var recording = false
    private var captured = 0

    /// Tipo de golpe de la tanda en curso. Es la etiqueta que se guarda.
    public var label: ShotType = .forehand

    /// Alias del jugador, para poder validar dejando fuera a una persona entera.
    public var playerAlias: String = "anon"

    /// Nivel de pádel (1-7) del jugador que graba, si se conoce.
    public var playerLevel: Int?

    public var capturedCount: Int { captured }
    public var isRecording: Bool { recording }

    public init(
        source: SourceInfo,
        profile: PlayerProfile,
        config: DetectorConfig = .default,
        sampleIdProvider: @escaping () -> String = { UUID().uuidString },
        nowEpochMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.source = source
        self.profile = profile
        self.config = config
        self.detector = ShotDetector(config: config, profile: profile)
        self.capture = TrainingCapture(sampleRateHz: config.sampleRateHz)
        self.sampleIdProvider = sampleIdProvider
        self.nowEpochMs = nowEpochMs
    }

    public func start(monotonicMs: Int64) {
        detector.reset(referenceTimestampMs: monotonicMs)
        capture.reset()
        referenceMs = monotonicMs
        captured = 0
        recording = true
    }

    /// Devuelve las muestras de entrenamiento que han quedado completas con esta señal.
    public func onMotion(_ sample: MotionSample) -> [TrainingSample] {
        guard recording else { return [] }

        // Primero se empuja la muestra —puede cerrar la cola de un golpeo anterior— y
        // luego se mira si esta muestra cierra un golpeo nuevo.
        let ready = capture.onSample(sample)
        if let shot = detector.process(sample) {
            capture.onShotDetected(shot, impactTimestampMs: referenceMs + shot.offsetMs)
        }
        let samples = ready.map { toTrainingSample($0) }
        captured += samples.count
        return samples
    }

    /// Cierra la tanda. Incluye el último golpeo aunque le falte cola.
    @discardableResult
    public func stop() -> [TrainingSample] {
        guard recording else { return [] }
        if let shot = detector.flush() {
            capture.onShotDetected(shot, impactTimestampMs: referenceMs + shot.offsetMs)
        }
        recording = false
        let samples = capture.flush().map { toTrainingSample($0) }
        captured += samples.count
        return samples
    }

    private func toTrainingSample(_ window: CapturedWindow) -> TrainingSample {
        TrainingSample(
            sampleId: sampleIdProvider(),
            label: label,
            recordedAtEpochMs: nowEpochMs(),
            playerAlias: playerAlias,
            playerLevel: playerLevel,
            hand: profile.hand,
            watchWrist: profile.watchWrist,
            platform: source.platform,
            device: source.device,
            sampleRateHz: config.sampleRateHz,
            impactIndex: window.impactIndex,
            // Offsets relativos al impacto: así la ventana es comparable entre golpeos
            // aunque los relojes arranquen su reloj monótono donde les dé la gana.
            offsetsMs: window.samples.map { Int($0.timestampMs - window.impactTimestampMs) },
            accel: window.samples.map { [$0.accel.x, $0.accel.y, $0.accel.z] },
            gyro: window.samples.map { [$0.gyro.x, $0.gyro.y, $0.gyro.z] },
            gravity: window.samples.map { [$0.gravity.x, $0.gravity.y, $0.gravity.z] },
            heuristicFeatures: window.shot.features,
            heuristicPrediction: window.shot.type,
            heuristicConfidence: window.shot.confidence
        )
    }
}
