import Foundation

/// Tipos de golpeo que distingue el clasificador v1.
public enum ShotType: String, Codable, CaseIterable, Sendable {
    case forehand
    case backhand

    /// El globo, con su lado: recorrido completo y sin velocidad, el golpe defensivo
    /// del pádel.
    ///
    /// Se detecta por esa contradicción —swing largo pero lento— y solo cuando el
    /// jugador ha grabado su tanda de globos: "lento" no significa lo mismo para dos
    /// muñecas. Ver `DetectorConfig.lobMaxPeakGyroRadS`.
    ///
    /// El lado sale del signo de la rotación axial, igual que en la volea. A diferencia
    /// de la volea, aquí el signo tiene una oportunidad razonable de acertar: un globo
    /// es un swing completo con muñeca, no un bloqueo. Pero es una expectativa, no una
    /// medida — no hay todavía ninguna tanda de globos con la que comprobarlo.
    case forehandLob
    case backhandLob
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
    /// Pico de rotación axial durante el swing, no la media.
    ///
    /// La media no distingue una víbora de una bandeja: en pista (ago 2026) las dos
    /// dieron −2,0 y −1,9 rad/s. Y es lógico — una víbora **no** rota todo el rato, da
    /// un latigazo al final, y promediarlo sobre 200° de arco lo borra. El pico sí lo ve.
    /// Nil en sesiones grabadas antes de medirlo.
    public let peakAxialRotationRadS: Float?
    /// Cuánto **baja** el brazo entre lo más alto del swing y el impacto, en grados.
    ///
    /// Es lo que separa el remate de la bandeja, que con los rasgos agregados salían
    /// idénticos: el remate se pega desde arriba hacia abajo y cae en picado; la bandeja
    /// es un golpe de control que se mantiene plano. Nil en sesiones viejas.
    public let elevationDropDeg: Float?

    public init(
        sweptAngleDeg: Float,
        peakGyroRadS: Float,
        elevationDeg: Float,
        axialRotationRadS: Float,
        swingDurationMs: Int64,
        peakElevationDeg: Float? = nil,
        prepElevationDeg: Float? = nil,
        peakAxialRotationRadS: Float? = nil,
        elevationDropDeg: Float? = nil
    ) {
        self.sweptAngleDeg = sweptAngleDeg
        self.peakGyroRadS = peakGyroRadS
        self.elevationDeg = elevationDeg
        self.axialRotationRadS = axialRotationRadS
        self.swingDurationMs = swingDurationMs
        self.peakElevationDeg = peakElevationDeg ?? elevationDeg
        self.prepElevationDeg = prepElevationDeg
        self.peakAxialRotationRadS = peakAxialRotationRadS
        self.elevationDropDeg = elevationDropDeg
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
        peakAxialRotationRadS =
            try container.decodeIfPresent(Float.self, forKey: .peakAxialRotationRadS)
        elevationDropDeg = try container.decodeIfPresent(Float.self, forKey: .elevationDropDeg)
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
    /// Dónde cayó este golpe dentro del partido y con qué pulso. Nil cuando se jugó sin
    /// marcador o sin permiso de salud. Ver `ShotContext`.
    public let context: ShotContext?
    /// Qué versión del clasificador decidió `type`. Nil en sesiones grabadas antes de
    /// que se apuntara.
    ///
    /// Es lo que permite comparar el historial consigo mismo: el día que el modelo
    /// cambie, las notas de antes y las de después salen de criterios distintos, y sin
    /// esta etiqueta no habría forma de saber cuáles son cuáles.
    public let modelVersion: String?

    public init(
        offsetMs: Int64,
        type: ShotType,
        racketSpeedKmh: Float,
        impactG: Float,
        confidence: Float,
        features: ShotFeatures,
        context: ShotContext? = nil,
        modelVersion: String? = nil
    ) {
        self.offsetMs = offsetMs
        self.type = type
        self.racketSpeedKmh = racketSpeedKmh
        self.impactG = impactG
        self.confidence = confidence
        self.features = features
        self.context = context
        self.modelVersion = modelVersion
    }

    /// Los campos nuevos tienen que poder faltar: una sesión grabada antes de que
    /// existieran no puede fallar al abrirse desde el backup.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offsetMs = try c.decode(Int64.self, forKey: .offsetMs)
        type = try c.decode(ShotType.self, forKey: .type)
        racketSpeedKmh = try c.decode(Float.self, forKey: .racketSpeedKmh)
        impactG = try c.decode(Float.self, forKey: .impactG)
        confidence = try c.decode(Float.self, forKey: .confidence)
        features = try c.decode(ShotFeatures.self, forKey: .features)
        context = try c.decodeIfPresent(ShotContext.self, forKey: .context)
        modelVersion = try c.decodeIfPresent(String.self, forKey: .modelVersion)
    }

    /// Identidad estable del golpeo dentro de su sesión.
    ///
    /// Se **deriva** de la sesión y el instante en vez de guardar un UUID por golpe: un
    /// partido largo pasa de 300 golpeos y un identificador aleatorio en cada uno
    /// engorda el fichero, el backup y cada subida sin añadir nada. El par (sesión,
    /// milisegundo) ya es único, porque el detector tiene 320 ms de tiempo muerto tras
    /// cada impacto y no puede emitir dos golpes en el mismo milisegundo.
    public func id(en sessionId: String) -> String { "\(sessionId):\(offsetMs)" }
}

/// El contexto de juego de un golpeo: lo que el detector **no** puede saber mirando solo
/// el movimiento, y que solo conoce quien lleva la sesión.
///
/// Por qué vive aparte de `ShotFeatures`: los rasgos son una función pura de la señal
/// del sensor —los mismos milisegundos dan siempre los mismos rasgos— y eso es lo que
/// permite reclasificar mañana una tanda grabada hoy. El contexto depende del marcador y
/// del pulso; mezclarlo con los rasgos haría el reentrenamiento irreproducible.
///
/// Y por qué se guarda ya, aunque casi nada lo use: **no se puede rellenar después**. El
/// punto en el que ocurrió un golpe de hace tres meses no se recupera de ninguna parte.
public struct ShotContext: Codable, Equatable, Sendable {
    /// Punto del partido, empezando en 1. Nil si se jugó sin marcador.
    public let pointIndex: Int?
    /// Juego del partido, empezando en 1.
    public let gameIndex: Int?
    /// Set del partido, empezando en 1.
    public let setIndex: Int?
    /// Pulso en el momento del golpeo. Nil sin permiso de salud o sin lectura aún.
    public let heartRateBpm: Int?

    public init(
        pointIndex: Int? = nil,
        gameIndex: Int? = nil,
        setIndex: Int? = nil,
        heartRateBpm: Int? = nil
    ) {
        self.pointIndex = pointIndex
        self.gameIndex = gameIndex
        self.setIndex = setIndex
        self.heartRateBpm = heartRateBpm
    }
}
