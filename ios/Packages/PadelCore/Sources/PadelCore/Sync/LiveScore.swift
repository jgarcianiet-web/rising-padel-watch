import Foundation

/// Estado en vivo del partido que el reloj comparte con el iPhone (y el iPhone, si hay
/// liga configurada, con el mundo).
///
/// Es **estado completo, no eventos**: cada actualización sustituye del todo a la
/// anterior, así que perder una no rompe nada — la siguiente trae la verdad entera. Esa
/// propiedad es la que permite mandarlo por canales sin garantía (mensajes de
/// WatchConnectivity, un PUT sin reintentos) sin que el marcador pueda quedarse mal.
public struct LiveMatchState: Codable, Equatable, Sendable {
    public let sessionId: String
    public let updatedAtEpochMs: Int64
    /// true en la última publicación: el partido acabó.
    public let completed: Bool
    public let score: MatchScore?
    public let shotCount: Int
    public let heartRateBpm: Int?
    public let elapsedSeconds: Int64

    public init(
        sessionId: String,
        updatedAtEpochMs: Int64,
        completed: Bool,
        score: MatchScore?,
        shotCount: Int,
        heartRateBpm: Int?,
        elapsedSeconds: Int64
    ) {
        self.sessionId = sessionId
        self.updatedAtEpochMs = updatedAtEpochMs
        self.completed = completed
        self.score = score
        self.shotCount = shotCount
        self.heartRateBpm = heartRateBpm
        self.elapsedSeconds = elapsedSeconds
    }
}

/// DTO del contrato `PUT /v1/live/{sessionId}`.
public struct LiveScorePayload: Codable, Equatable, Sendable {
    public let sessionId: String
    public let updatedAt: String
    public let completed: Bool
    public let score: ScorePayload?
    /// Puntos del juego en curso, ya como etiqueta ("40", "Ad"): el `ScorePayload` del
    /// contrato solo lleva sets, y un marcador en vivo sin el 30-40 no es un marcador.
    public let pointsUs: String?
    public let pointsThem: String?
    /// "us" | "them": quién saca ahora mismo.
    public let serving: String?
    public let shotCount: Int
    public let heartRateBpm: Int?
    public let elapsedSeconds: Int64

    public init(_ state: LiveMatchState) {
        sessionId = state.sessionId
        updatedAt = isoUTC(state.updatedAtEpochMs)
        completed = state.completed
        score = state.score.map { $0.toPayload() }
        pointsUs = state.score.map { $0.pointsLabel(.us) }
        pointsThem = state.score.map { $0.pointsLabel(.them) }
        serving = state.score.map { $0.server == .us ? "us" : "them" }
        shotCount = state.shotCount
        heartRateBpm = state.heartRateBpm
        elapsedSeconds = state.elapsedSeconds
    }
}

/// Publica el estado en vivo en la liga. Fuego y olvido a propósito: un marcador viejo
/// reenviado con retraso sería peor que un hueco, así que no hay cola ni reintentos —
/// la siguiente actualización corrige sola.
public struct LiveScorePublisher: Sendable {

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func publish(_ state: LiveMatchState, config: LeagueConfig) async {
        guard let url = URL(string: LeagueAPIClient.buildURL(config.baseURL, "v1/live/\(state.sessionId)"))
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        request.httpBody = try? JSONEncoder().encode(LiveScorePayload(state))
        // El resultado se ignora: si el servidor no está, el partido sigue igual.
        _ = try? await urlSession.data(for: request)
    }
}
