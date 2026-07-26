import Foundation

/// Referencias por tipo de golpe para puntuar de 1 a 7.
public struct ShotBand: Equatable, Sendable {
    /// Velocidad estimada de pala (km/h) de un golpe de nivel 1.
    public let speedAtLevel1: Float
    /// La de un nivel 7. Entre las dos se interpola.
    public let speedAtLevel7: Float
    /// Ángulo barrido de referencia.
    public let idealSweptDeg: Float
    /// Si es true, pasarse del ángulo ideal **resta**. Es el caso de las voleas: en pádel
    /// la volea se bloquea, no se golpea, y un swing largo en la red es precisamente el
    /// error que separa a un jugador de nivel bajo de uno de nivel alto.
    public let compactIsBetter: Bool

    public init(
        speedAtLevel1: Float,
        speedAtLevel7: Float,
        idealSweptDeg: Float,
        compactIsBetter: Bool = false
    ) {
        self.speedAtLevel1 = speedAtLevel1
        self.speedAtLevel7 = speedAtLevel7
        self.idealSweptDeg = idealSweptDeg
        self.compactIsBetter = compactIsBetter
    }
}

/// Todos los parámetros del estimador de nivel.
///
/// Están en un solo sitio y son datos, no constantes sueltas, porque **hay que
/// calibrarlos**: las bandas de abajo son estimaciones razonadas a partir de rangos
/// publicados de velocidad angular de muñeca, no medidas contra jugadores de nivel
/// conocido. Ver `docs/level.md`.
public struct LevelConfig: Sendable {

    public var bands: [ShotType: ShotBand]
    /// Peso de la velocidad frente a la amplitud del swing.
    public var speedWeight: Float
    /// Golpeos por debajo de esta confianza no puntúan: el tipo no está claro.
    public var minConfidence: Float
    /// Por debajo de esto el nivel no se reporta como fiable.
    public var minShotsForEstimate: Int
    /// Cuántos niveles llega a restar la falta de regularidad.
    public var maxConsistencyPenalty: Float
    /// Cuántos niveles llega a sumar tener repertorio completo.
    public var maxRepertoireBonus: Float
    /// Golpeos mínimos de un tipo para contarlo como parte del repertorio.
    public var minShotsPerTypeForRepertoire: Int

    public init(
        bands: [ShotType: ShotBand] = LevelConfig.defaultBands,
        speedWeight: Float = 0.65,
        minConfidence: Float = 0.45,
        minShotsForEstimate: Int = 30,
        maxConsistencyPenalty: Float = 0.8,
        maxRepertoireBonus: Float = 0.4,
        minShotsPerTypeForRepertoire: Int = 5
    ) {
        self.bands = bands
        self.speedWeight = speedWeight
        self.minConfidence = minConfidence
        self.minShotsForEstimate = minShotsForEstimate
        self.maxConsistencyPenalty = maxConsistencyPenalty
        self.maxRepertoireBonus = maxRepertoireBonus
        self.minShotsPerTypeForRepertoire = minShotsPerTypeForRepertoire
    }

    /// Bandas por defecto.
    ///
    /// Salen de convertir los rangos de velocidad angular de muñeca documentados en
    /// `shot-detection.md` (volea 5-10 rad/s, derecha 15-25, smash 25-35) con el mismo
    /// brazo de palanca que usa el detector, y de ensanchar los extremos para que el 1 y
    /// el 7 sean alcanzables sin saturar a la mitad de los jugadores.
    public static let defaultBands: [ShotType: ShotBand] = [
        .forehand: ShotBand(speedAtLevel1: 28, speedAtLevel7: 65, idealSweptDeg: 200),
        .backhand: ShotBand(speedAtLevel1: 26, speedAtLevel7: 60, idealSweptDeg: 180),
        // La volea se puntúa al revés en amplitud: compacta es mejor.
        .forehandVolley: ShotBand(
            speedAtLevel1: 10, speedAtLevel7: 26, idealSweptDeg: 45, compactIsBetter: true
        ),
        .backhandVolley: ShotBand(
            speedAtLevel1: 10, speedAtLevel7: 24, idealSweptDeg: 45, compactIsBetter: true
        ),
        .overhead: ShotBand(speedAtLevel1: 45, speedAtLevel7: 90, idealSweptDeg: 200),
        .serve: ShotBand(speedAtLevel1: 32, speedAtLevel7: 72, idealSweptDeg: 240),
    ]

    public static let `default` = LevelConfig()

    public static let minLevel: Float = 1
    public static let maxLevel: Float = 7
}
