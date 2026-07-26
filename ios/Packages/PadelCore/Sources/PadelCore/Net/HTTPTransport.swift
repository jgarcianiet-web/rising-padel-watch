import Foundation

public struct HTTPResponse: Equatable, Sendable {
    public let code: Int
    public let body: String
    public let headers: [String: String]

    public init(code: Int, body: String, headers: [String: String] = [:]) {
        self.code = code
        self.body = body
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Se lanza ante fallos de red. Los códigos HTTP no son errores: son `HTTPResponse`.
public struct HTTPTransportError: Error, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Abstracción mínima de HTTP. Existe para poder testear el cliente de la liga y la cola
/// de sincronización sin red ni servidor.
public protocol HTTPTransport: Sendable {
    func request(
        method: String,
        url: String,
        headers: [String: String],
        body: String?
    ) async throws -> HTTPResponse
}

/// Implementación sobre `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        // La cola de sincronización ya reintenta con su propia política; que URLSession
        // espere por su cuenta solo retrasaría el diagnóstico.
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    public func request(
        method: String,
        url: String,
        headers: [String: String],
        body: String?
    ) async throws -> HTTPResponse {
        guard let parsed = URL(string: url) else {
            throw HTTPTransportError("URL no válida: \(url)")
        }
        var request = URLRequest(url: parsed)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpBody = Data(body.utf8)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPTransportError("Respuesta no HTTP de \(url)")
            }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                if let key = entry.key as? String, let value = entry.value as? String {
                    result[key] = value
                }
            }
            return HTTPResponse(
                code: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "",
                headers: headers
            )
        } catch let error as HTTPTransportError {
            throw error
        } catch {
            throw HTTPTransportError("Fallo de red en \(method) \(url): \(error.localizedDescription)")
        }
    }
}
