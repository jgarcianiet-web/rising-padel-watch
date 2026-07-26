import Foundation

/// Un golpeo etiquetado con su señal cruda, para entrenar el clasificador.
///
/// La etiqueta viene puesta desde el momento de grabar: el jugador elige un tipo de golpe
/// y da una tanda solo de ese tipo. Etiquetar después, mirando gráficas, no funciona —
/// nadie distingue un revés de una volea alta en una serie de acelerómetro.
///
/// **Estos datos no salen del reloj solos.** Ver `docs/training-data.md`.
public struct TrainingSample: Codable, Equatable, Sendable {
    public let sampleId: String
    public let label: ShotType
    public let recordedAtEpochMs: Int64
    /// Alias que el jugador elige, no su nombre. Existe para poder validar el modelo
    /// dejando fuera a un jugador entero: si los golpeos de la misma persona caen a los
    /// dos lados de la partición, el modelo memoriza al jugador y la precisión que mides
    /// es mentira.
    public let playerAlias: String
    public let hand: Hand
    public let watchWrist: Hand
    public let platform: Platform
    public let device: String
    public let sampleRateHz: Int
    /// Índice del impacto dentro de las series.
    public let impactIndex: Int
    /// Milisegundos de cada muestra **relativos al impacto**: negativos antes, positivos después.
    public let offsetsMs: [Int]
    /// Aceleración sin gravedad, en g. Una lista de [x, y, z] por muestra.
    public let accel: [[Float]]
    /// Velocidad angular en rad/s.
    public let gyro: [[Float]]
    /// Vector gravedad en g.
    public let gravity: [[Float]]
    public let heuristicFeatures: ShotFeatures
    /// Lo que dijo el clasificador v1. Se guarda para medir cuánto mejora el modelo
    /// entrenado sobre la heurística, no para entrenar con ello.
    public let heuristicPrediction: ShotType
    public let heuristicConfidence: Float

    public init(
        sampleId: String,
        label: ShotType,
        recordedAtEpochMs: Int64,
        playerAlias: String,
        hand: Hand,
        watchWrist: Hand,
        platform: Platform,
        device: String,
        sampleRateHz: Int,
        impactIndex: Int,
        offsetsMs: [Int],
        accel: [[Float]],
        gyro: [[Float]],
        gravity: [[Float]],
        heuristicFeatures: ShotFeatures,
        heuristicPrediction: ShotType,
        heuristicConfidence: Float
    ) {
        self.sampleId = sampleId
        self.label = label
        self.recordedAtEpochMs = recordedAtEpochMs
        self.playerAlias = playerAlias
        self.hand = hand
        self.watchWrist = watchWrist
        self.platform = platform
        self.device = device
        self.sampleRateHz = sampleRateHz
        self.impactIndex = impactIndex
        self.offsetsMs = offsetsMs
        self.accel = accel
        self.gyro = gyro
        self.gravity = gravity
        self.heuristicFeatures = heuristicFeatures
        self.heuristicPrediction = heuristicPrediction
        self.heuristicConfidence = heuristicConfidence
    }

    public var sampleCount: Int { offsetsMs.count }

    /// True si la heurística ya acertaba. Sirve para medir la mejora del modelo.
    public var heuristicWasRight: Bool { heuristicPrediction == label }
}
