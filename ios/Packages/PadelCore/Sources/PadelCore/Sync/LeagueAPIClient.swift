import Foundation

/// Configuración de la app de liga con la que se sincroniza.
///
/// El token **no** se persiste junto a las sesiones: vive en el Keychain y se inyecta
/// aquí en el momento de sincronizar.
public struct LeagueConfig: Equatable, Sendable {
    public let baseURL: String
    public let token: String

    public init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    public var isUsable: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum UploadOutcome: Equatable, Sendable {
    /// El servidor la aceptó. `created` es false si ya existía (respuesta 200 idempotente).
    case success(remoteId: String?, created: Bool)
    /// 400/409/esquema no soportado: reintentar no lo va a arreglar.
    case permanentFailure(code: String?, message: String)
    /// 401: hace falta que el usuario vuelva a conectar la liga.
    case authFailure(message: String)
    /// 429: reintentar respetando Retry-After.
    case rateLimited(retryAfterSeconds: Int64?)
    /// Red caída o 5xx: reintentar con backoff.
    case transientFailure(message: String)
}

public struct LeagueAPIClient: Sendable {
    private let transport: HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Sube una sesión. Es idempotente vía cabecera `Idempotency-Key`, así que reintentar
    /// la misma sesión nunca duplica.
    ///
    /// Si el servidor responde 413 se reintenta una sola vez sin la serie de golpeos, que
    /// es lo único que puede hacer grande el payload.
    public func upload(
        config: LeagueConfig,
        session: PadelSession,
        shareHealth: Bool,
        includeEvents: Bool = true
    ) async -> UploadOutcome {
        switch await post(config: config, session: session, shareHealth: shareHealth, includeEvents: includeEvents) {
        case .done(let outcome):
            return outcome
        case .tooLarge:
            guard includeEvents else { return tooLargeFailure }
            switch await post(config: config, session: session, shareHealth: shareHealth, includeEvents: false) {
            case .done(let outcome): return outcome
            case .tooLarge: return tooLargeFailure
            }
        }
    }

    /// Partidos del jugador en una ventana temporal, para poder vincular la sesión.
    /// Devuelve nil si la liga no implementa el endpoint (404): la app degrada a
    /// introducir el identificador a mano.
    public func matches(
        config: LeagueConfig,
        fromEpochMs: Int64,
        toEpochMs: Int64
    ) async -> [MatchSummary]? {
        let url = Self.buildURL(config.baseURL, "v1/me/matches")
            + "?from=\(isoUTC(fromEpochMs))&to=\(isoUTC(toEpochMs))"
        guard let response = try? await transport.request(
            method: "GET",
            url: url,
            headers: authHeaders(config),
            body: nil
        ) else {
            return nil
        }
        guard (200...299).contains(response.code) else { return nil }
        return try? decoder.decode(MatchesResponse.self, from: Data(response.body.utf8)).matches
    }

    /// 413 no es un desenlace final: dispara el reintento sin la serie de golpeos.
    private enum PostResult {
        case done(UploadOutcome)
        case tooLarge
    }

    private var tooLargeFailure: UploadOutcome {
        .permanentFailure(
            code: "payload_too_large",
            message: "El servidor rechazó el payload por tamaño incluso sin la serie de golpeos"
        )
    }

    private func post(
        config: LeagueConfig,
        session: PadelSession,
        shareHealth: Bool,
        includeEvents: Bool
    ) async -> PostResult {
        let payload = session.toPayload(shareHealth: shareHealth, includeEvents: includeEvents)
        guard let data = try? encoder.encode(payload),
              let body = String(data: data, encoding: .utf8) else {
            return .done(.permanentFailure(code: "encode_failed", message: "No se pudo serializar la sesión"))
        }

        var headers = authHeaders(config)
        headers["Content-Type"] = "application/json"
        // La clave de idempotencia es el propio sessionId: reintentar no duplica.
        headers["Idempotency-Key"] = session.sessionId

        let response: HTTPResponse
        do {
            response = try await transport.request(
                method: "POST",
                url: Self.buildURL(config.baseURL, "v1/padel-sessions"),
                headers: headers,
                body: body
            )
        } catch {
            return .done(.transientFailure(message: error.localizedDescription))
        }

        if response.code == 413 { return .tooLarge }

        switch response.code {
        case 200, 201:
            let ref = try? decoder.decode(SessionRefResponse.self, from: Data(response.body.utf8))
            return .done(.success(remoteId: ref?.id, created: response.code == 201))

        case 401, 403:
            return .done(.authFailure(message: errorMessage(response.body) ?? "Token no válido"))

        case 400, 409, 422:
            return .done(.permanentFailure(
                code: errorCode(response.body),
                message: errorMessage(response.body)
                    ?? "El servidor rechazó la sesión (\(response.code))"
            ))

        case 429:
            return .done(.rateLimited(retryAfterSeconds: response.header("Retry-After").flatMap(Int64.init)))

        default:
            return .done(.transientFailure(
                message: errorMessage(response.body) ?? "Error del servidor (\(response.code))"
            ))
        }
    }

    private func authHeaders(_ config: LeagueConfig) -> [String: String] {
        [
            "Authorization": "Bearer \(config.token)",
            "Accept": "application/json",
        ]
    }

    private func errorBody(_ body: String) -> APIErrorBody? {
        try? decoder.decode(APIErrorResponse.self, from: Data(body.utf8)).error
    }

    private func errorCode(_ body: String) -> String? { errorBody(body)?.code }

    private func errorMessage(_ body: String) -> String? {
        errorBody(body)?.message.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func buildURL(_ baseURL: String, _ path: String) -> String {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        var suffix = path
        while suffix.hasPrefix("/") { suffix.removeFirst() }
        return base + "/" + suffix
    }
}
