import Foundation

/// Tipos de golpeo que distingue el clasificador v1.
public enum ShotType: String, Codable, CaseIterable, Sendable {
    case forehand
    case backhand
    case forehandVolley
    case backhandVolley
    case overhead
    case serve
    case unknown

    /// Nombre en el contrato con la liga. Coincide con el `rawValue`.
    public var wireName: String { rawValue }

    public static func fromWire(_ value: String) -> ShotType {
        ShotType(rawValue: value) ?? .unknown
    }
}

/// Rasgos crudos del golpeo. No se suben a la liga: sirven para depurar la detección y
/// para poder reentrenar el clasificador más adelante.
public struct ShotFeatures: Codable, Equatable, Sendable {
    public let sweptAngleDeg: Float
    public let peakGyroRadS: Float
    public let elevationDeg: Float
    public let axialRotationRadS: Float
    public let swingDurationMs: Int64

    public init(
        sweptAngleDeg: Float,
        peakGyroRadS: Float,
        elevationDeg: Float,
        axialRotationRadS: Float,
        swingDurationMs: Int64
    ) {
        self.sweptAngleDeg = sweptAngleDeg
        self.peakGyroRadS = peakGyroRadS
        self.elevationDeg = elevationDeg
        self.axialRotationRadS = axialRotationRadS
        self.swingDurationMs = swingDurationMs
    }
}

/// Un golpeo detectado.
///
/// `racketSpeedKmh` es una **estimación** de la velocidad del centro de la pala a partir
/// de la velocidad angular de la muñeca: sirve para comparar golpeos entre sí, no como
/// velocímetro absoluto.
public struct Shot: Codable, Equatable, Sendable {
    /// Milisegundos desde el inicio de la sesión.
    public let offsetMs: Int64
    public let type: ShotType
    public let racketSpeedKmh: Float
    public let impactG: Float
    public let confidence: Float
    public let features: ShotFeatures

    public init(
        offsetMs: Int64,
        type: ShotType,
        racketSpeedKmh: Float,
        impactG: Float,
        confidence: Float,
        features: ShotFeatures
    ) {
        self.offsetMs = offsetMs
        self.type = type
        self.racketSpeedKmh = racketSpeedKmh
        self.impactG = impactG
        self.confidence = confidence
        self.features = features
    }
}
