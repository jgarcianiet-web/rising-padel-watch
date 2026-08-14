import Foundation

/// Un golpe que el detector creyó ver durante la tanda, como metadato.
///
/// Es información, no puerta: la tanda se graba entera aunque el detector no vea ni uno.
public struct GolpeDeTanda: Codable, Equatable, Sendable {
    /// Milisegundos desde el arranque de la tanda.
    public let offsetMs: Int64
    public let tipo: ShotType
    public let confidence: Float
    public let features: ShotFeatures

    public init(offsetMs: Int64, tipo: ShotType, confidence: Float, features: ShotFeatures) {
        self.offsetMs = offsetMs
        self.tipo = tipo
        self.confidence = confidence
        self.features = features
    }
}

/// Una tanda de entrenamiento grabada **entera y en crudo**: del "grabar" al "parar",
/// toda la señal, con una sola etiqueta.
///
/// Sustituye a la captura por ventanas y es la respuesta a un fallo de diseño que salió
/// en pista: antes solo se guardaba una ventana alrededor de cada impacto que el detector
/// encontraba, así que si el detector no veía impactos —golpe suave, umbral alto, probar
/// sin bola— la tanda entera se quedaba en **cero** sin explicación posible. Grabar en
/// crudo lo invierte: el tiempo y los bytes siempre avanzan, no hay forma de "no recoger
/// nada", y los golpes que el detector se dejó siguen en la señal para segmentarlos
/// después con calma.
///
/// Espejo del core Kotlin, con tests allí.
public struct TandaCruda: Codable, Equatable, Sendable {
    public let tandaId: String
    /// El tipo de golpe de la tanda entera. Se fija ANTES de empezar a pegar.
    public let label: ShotType
    public let playerAlias: String
    public let playerLevel: Int?
    public let hand: Hand
    public let watchWrist: Hand
    public let platform: Platform
    public let device: String
    public let appVersion: String
    public let startedAtEpochMs: Int64
    public let sampleRateHz: Int
    /// Milisegundos desde el arranque, una entrada por muestra.
    public let offsetsMs: [Int64]
    /// Cada muestra como [x, y, z], alineada con `offsetsMs`.
    public let accel: [[Float]]
    public let gyro: [[Float]]
    public let gravity: [[Float]]
    /// Lo que el detector creyó ver, como metadato. Vacío no invalida nada.
    public let golpes: [GolpeDeTanda]
    public let descartes: DescartesDelDetector?
    /// Versión del formato: 2 = tanda cruda. Las líneas viejas (por golpe) no lo llevan.
    public let formato: Int

    public init(
        tandaId: String,
        label: ShotType,
        playerAlias: String = "anon",
        playerLevel: Int? = nil,
        hand: Hand = .right,
        watchWrist: Hand = .right,
        platform: Platform,
        device: String = "",
        appVersion: String = "",
        startedAtEpochMs: Int64,
        sampleRateHz: Int,
        offsetsMs: [Int64],
        accel: [[Float]],
        gyro: [[Float]],
        gravity: [[Float]],
        golpes: [GolpeDeTanda] = [],
        descartes: DescartesDelDetector? = nil,
        formato: Int = 2
    ) {
        self.tandaId = tandaId
        self.label = label
        self.playerAlias = playerAlias
        self.playerLevel = playerLevel
        self.hand = hand
        self.watchWrist = watchWrist
        self.platform = platform
        self.device = device
        self.appVersion = appVersion
        self.startedAtEpochMs = startedAtEpochMs
        self.sampleRateHz = sampleRateHz
        self.offsetsMs = offsetsMs
        self.accel = accel
        self.gyro = gyro
        self.gravity = gravity
        self.golpes = golpes
        self.descartes = descartes
        self.formato = formato
    }

    public var muestras: Int { offsetsMs.count }

    public var duracionSegundos: Int {
        guard let ultimo = offsetsMs.last else { return 0 }
        return Int(ultimo / 1000)
    }
}

/// Graba una tanda de entrenamiento entera y en crudo.
///
/// El contrato es deliberadamente a prueba de decepciones: **cada muestra que entra se
/// guarda**. El detector corre en paralelo pero solo como comentarista — sus golpes y
/// sus descartes se apuntan como metadatos y sirven de contador en vivo, sin poder vetar
/// ni una muestra. Espejo del core Kotlin, con tests allí.
public final class GrabadorDeTanda {

    private let source: SourceInfo
    private let profile: PlayerProfile
    private let detector: ShotDetector
    private let sampleRateHz: Int
    private let tandaIdProvider: () -> String
    private let nowEpochMs: () -> Int64

    private var offsets: [Int64] = []
    private var accel: [[Float]] = []
    private var gyro: [[Float]] = []
    private var gravity: [[Float]] = []
    private var golpesVistos: [GolpeDeTanda] = []

    private var referenceMs: Int64 = 0
    private var startedAtEpochMs: Int64 = 0
    private var recording = false

    /// Tipo de golpe de la tanda entera. Se fija antes de empezar a pegar.
    public var label: ShotType = .forehand
    public var playerAlias = "anon"
    public var playerLevel: Int?

    public var isRecording: Bool { recording }
    public var muestras: Int { offsets.count }
    public var segundos: Int { offsets.last.map { Int($0 / 1000) } ?? 0 }

    /// Golpes que el detector cree haber visto. Contador en vivo, no puerta.
    public var golpes: Int { golpesVistos.count }
    public var descartes: DescartesDelDetector { detector.descartes }

    /// La tanda está en el tope y ya no admite más muestras.
    public var llena: Bool { offsets.count >= Self.maxMuestras }

    /// Tope de cinco minutos a 50 Hz: sin él, un "grabar" olvidado se comería la
    /// memoria del reloj.
    public static let maxMuestras = 5 * 60 * 50

    public init(
        source: SourceInfo,
        profile: PlayerProfile,
        config: DetectorConfig = .default,
        tandaIdProvider: @escaping () -> String = { UUID().uuidString },
        nowEpochMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.source = source
        self.profile = profile
        self.detector = ShotDetector(config: config, profile: profile)
        self.sampleRateHz = config.sampleRateHz
        self.tandaIdProvider = tandaIdProvider
        self.nowEpochMs = nowEpochMs
    }

    public func start(monotonicMs: Int64) {
        detector.reset(referenceTimestampMs: monotonicMs)
        offsets.removeAll()
        accel.removeAll()
        gyro.removeAll()
        gravity.removeAll()
        golpesVistos.removeAll()
        referenceMs = monotonicMs
        startedAtEpochMs = nowEpochMs()
        recording = true
    }

    /// Guarda la muestra y devuelve el golpe si el detector creyó ver uno.
    ///
    /// El retorno es solo para vibrar o subir el contador: la muestra ya está guardada
    /// pase lo que pase.
    @discardableResult
    public func onMotion(_ sample: MotionSample) -> Shot? {
        guard recording, !llena else { return nil }

        offsets.append(sample.timestampMs - referenceMs)
        accel.append([sample.accel.x, sample.accel.y, sample.accel.z])
        gyro.append([sample.gyro.x, sample.gyro.y, sample.gyro.z])
        gravity.append([sample.gravity.x, sample.gravity.y, sample.gravity.z])

        guard let shot = detector.process(sample) else { return nil }
        golpesVistos.append(
            GolpeDeTanda(
                offsetMs: shot.offsetMs,
                tipo: shot.type,
                confidence: shot.confidence,
                features: shot.features
            )
        )
        return shot
    }

    /// Cierra la tanda. Nil si no llegó ni una muestra: no hay nada que guardar.
    public func stop() -> TandaCruda? {
        recording = false
        guard !offsets.isEmpty else { return nil }
        return TandaCruda(
            tandaId: tandaIdProvider(),
            label: label,
            playerAlias: playerAlias,
            playerLevel: playerLevel,
            hand: profile.hand,
            watchWrist: profile.watchWrist,
            platform: source.platform,
            device: source.device,
            appVersion: source.appVersion,
            startedAtEpochMs: startedAtEpochMs,
            sampleRateHz: sampleRateHz,
            offsetsMs: offsets,
            accel: accel,
            gyro: gyro,
            gravity: gravity,
            golpes: golpesVistos,
            descartes: detector.descartes
        )
    }
}
