import Foundation

/// Los ajustes que el iPhone replica al Apple Watch.
///
/// Es el subconjunto de preferencias que **el reloj necesita para medir** y que solo se
/// pueden configurar cómodamente en el móvil: escribir un alias o elegir la muñeca en una
/// pantalla de 45 mm es una mala idea.
///
/// Deliberadamente **no** entran aquí:
/// - `trackScore`, `deuceFormat` y `setsToWin`: se deciden en el reloj al empezar el
///   partido, que es cuando el jugador sabe si va a llevar marcador. Replicarlos desde el
///   iPhone pisaría lo que acaba de elegir en la muñeca.
/// - La URL de la liga y el token: el reloj no habla con la liga, habla con el iPhone. Un
///   token es una credencial y cuantos menos sitios la tengan, mejor.
public struct DeviceSettings: Codable, Equatable, Sendable {

    public var profile: PlayerProfile
    public var sensitivity: Sensitivity
    /// Consentimiento explícito para medir y compartir datos de salud.
    public var shareHealth: Bool
    /// Modo de recogida de datos de entrenamiento. Ver `docs/training-data.md`.
    public var collectTrainingData: Bool
    /// Alias del jugador, para poder validar el modelo dejándolo fuera.
    public var playerAlias: String
    /// Cuándo se editaron estos ajustes en el dispositivo de origen.
    ///
    /// Es lo que hace que la replicación sea segura: `updateApplicationContext` **reentrega**
    /// el último estado al reconectar, así que sin marca de tiempo un cambio hecho en el
    /// reloj lo pisaría un contexto viejo del iPhone.
    public var updatedAtEpochMs: Int64

    public init(
        profile: PlayerProfile = PlayerProfile(),
        sensitivity: Sensitivity = .medium,
        shareHealth: Bool = false,
        collectTrainingData: Bool = false,
        playerAlias: String = DeviceSettings.defaultAlias,
        updatedAtEpochMs: Int64 = 0
    ) {
        self.profile = profile
        self.sensitivity = sensitivity
        self.shareHealth = shareHealth
        self.collectTrainingData = collectTrainingData
        self.playerAlias = playerAlias
        self.updatedAtEpochMs = updatedAtEpochMs
    }

    /// Decodifica campo a campo con valores por defecto.
    ///
    /// El `Codable` sintetizado falla si falta una clave, y aquí eso rompería la
    /// replicación en la actualización que estrena un ajuste: el reloj nuevo recibiría el
    /// payload del iPhone viejo, no lo sabría leer y se quedaría sin ajustes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(PlayerProfile.self, forKey: .profile)
            ?? PlayerProfile()
        sensitivity = try container.decodeIfPresent(Sensitivity.self, forKey: .sensitivity)
            ?? .medium
        shareHealth = try container.decodeIfPresent(Bool.self, forKey: .shareHealth) ?? false
        collectTrainingData = try container.decodeIfPresent(
            Bool.self, forKey: .collectTrainingData
        ) ?? false
        playerAlias = try container.decodeIfPresent(String.self, forKey: .playerAlias)
            ?? DeviceSettings.defaultAlias
        updatedAtEpochMs = try container.decodeIfPresent(
            Int64.self, forKey: .updatedAtEpochMs
        ) ?? 0
    }

    /// Aplica `incoming` solo si es más reciente que lo que ya hay.
    ///
    /// Empate = gana lo local. Dos ediciones en el mismo milisegundo en dos dispositivos
    /// distintos no pasa en la práctica, y ante la duda es preferible respetar lo que el
    /// jugador tiene delante.
    public func merged(with incoming: DeviceSettings) -> DeviceSettings {
        incoming.updatedAtEpochMs > updatedAtEpochMs ? incoming : self
    }

    public static let defaultAlias = "anon"
    public static let maxAliasLength = 24

    /// Normaliza el alias: minúsculas, sin espacios y acotado.
    ///
    /// El alias es la clave de agrupación en la validación leave-one-player-out, así que
    /// "Marta" y "marta " tienen que ser el mismo jugador; si no, el modelo se valida
    /// contra sí mismo y el número sale inflado.
    public static func sanitizeAlias(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
        guard !collapsed.isEmpty else { return defaultAlias }
        return String(collapsed.prefix(maxAliasLength))
    }

    public static func encode(_ settings: DeviceSettings) -> Data? {
        try? JSONEncoder().encode(settings)
    }

    /// Devuelve nil si el payload no es legible: mejor ignorarlo que romper.
    public static func decode(_ data: Data) -> DeviceSettings? {
        try? JSONDecoder().decode(DeviceSettings.self, from: data)
    }
}
