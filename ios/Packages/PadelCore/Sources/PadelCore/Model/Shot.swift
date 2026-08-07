import Foundation

/// Tipos de golpeo que distingue el clasificador v1.
public enum ShotType: String, Codable, CaseIterable, Sendable {
    case forehand
    case backhand
    case forehandVolley
    case backhandVolley

    /// Golpe alto de control, el techo defensivo del pádel.
    case bandeja

    /// Golpe alto con mucho efecto lateral: lo define la rotación axial, no la fuerza.
    case vibora

    /// El remate: máxima violencia, pico de giro por encima de todo lo demás.
    case smash
    case serve
    case unknown

    /// Nombre en el contrato con la liga. Coincide con el `rawValue`.
    public var wireName: String { rawValue }

    public static func fromWire(_ value: String) -> ShotType {
        if let type = ShotType(rawValue: value) { return type }
        // Sesiones anteriores a separar los golpes altos: "overhead" agrupaba bandeja,
        // víbora y smash. Se mapea a bandeja, que es el más común.
        return value == "overhead" ? .bandeja : .unknown
    }
}

/// Rasgos crudos del golpeo. No se suben a la liga: sirven para depurar la detección y
/// para poder reentrenar el clasificador más adelante.
public struct ShotFeatures: Codable, Equatable, Sendable {
    public let sweptAngleDeg: Float
    public let peakGyroRadS: Float
    /// Elevación **mediana** del antebrazo durante el swing: la postura del golpe.
    public let elevationDeg: Float
    public let axialRotationRadS: Float
    public let swingDurationMs: Int64
    /// Hasta dónde subió el brazo durante el swing (percentil 80 de la elevación).
    ///
    /// Es lo que de verdad distingue un golpe alto de uno de fondo: no "cómo estaba el
    /// brazo en el impacto" —que la estimación de gravedad del sistema mide fatal en
    /// mitad de un swing violento— sino **si la mano pasó por encima del hombro**. Se
    /// usa el percentil 80 y no el máximo porque un solo pico del filtro de fusión no
    /// puede convertir una derecha en una bandeja.
    public let peakElevationDeg: Float
    /// Elevación del antebrazo en la **preparación** (mediana de los ~400 ms previos
    /// al arranque del swing), medida con el brazo aún calmado — donde la estimación
    /// de gravedad sí es fiable. Validado en pista (ago 2026): durante un remate real
    /// el filtro de gravedad se corrompe y `peakElevationDeg` salía a +3° o −41°; la
    /// postura de preparación es el testigo honesto de si el golpe se armó en alto.
    /// Nil en sesiones grabadas antes de que existiera el rasgo.
    public let prepElevationDeg: Float?

    public init(
        sweptAngleDeg: Float,
        peakGyroRadS: Float,
        elevationDeg: Float,
        axialRotationRadS: Float,
        swingDurationMs: Int64,
        peakElevationDeg: Float? = nil,
        prepElevationDeg: Float? = nil
    ) {
        self.sweptAngleDeg = sweptAngleDeg
        self.peakGyroRadS = peakGyroRadS
        self.elevationDeg = elevationDeg
        self.axialRotationRadS = axialRotationRadS
        self.swingDurationMs = swingDurationMs
        self.peakElevationDeg = peakElevationDeg ?? elevationDeg
        self.prepElevationDeg = prepElevationDeg
    }

    /// Sesiones grabadas antes de que existiera `peakElevationDeg` no lo traen: cae a la
    /// elevación mediana, que es lo que había entonces.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sweptAngleDeg = try container.decode(Float.self, forKey: .sweptAngleDeg)
        peakGyroRadS = try container.decode(Float.self, forKey: .peakGyroRadS)
        elevationDeg = try container.decode(Float.self, forKey: .elevationDeg)
        axialRotationRadS = try container.decode(Float.self, forKey: .axialRotationRadS)
        swingDurationMs = try container.decode(Int64.self, forKey: .swingDurationMs)
        peakElevationDeg =
            try container.decodeIfPresent(Float.self, forKey: .peakElevationDeg) ?? elevationDeg
        prepElevationDeg = try container.decodeIfPresent(Float.self, forKey: .prepElevationDeg)
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
