import Foundation

/// Persistencia local de sesiones. La liga es el destino final, no la fuente de verdad.
public protocol SessionStore: AnyObject {
    func all() -> [PadelSession]
    func get(_ sessionId: String) -> PadelSession?
    func upsert(_ session: PadelSession)
    func delete(_ sessionId: String)
}

/// Un fichero JSON por sesión.
///
/// Un fichero por sesión y no una base de datos porque el acceso siempre es "todas" o
/// "una por id", el volumen es de decenas de sesiones al año, y así una sesión corrupta
/// no se lleva por delante el historial entero.
///
/// Las escrituras son atómicas: si el móvil se apaga a mitad de escritura, la sesión
/// anterior sigue intacta.
public final class FileSessionStore: SessionStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func all() -> [PadelSession] {
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.lastPathComponent.hasSuffix(Self.extensionSuffix) }
            .compactMap(read)
            .sorted { $0.startedAtEpochMs > $1.startedAtEpochMs }
    }

    public func get(_ sessionId: String) -> PadelSession? {
        read(fileFor(sessionId))
    }

    public func upsert(_ session: PadelSession) {
        guard let data = try? encoder.encode(session) else { return }
        // `.atomic` escribe en un temporal y renombra: nunca queda un fichero a medias.
        try? data.write(to: fileFor(session.sessionId), options: .atomic)
    }

    public func delete(_ sessionId: String) {
        try? fileManager.removeItem(at: fileFor(sessionId))
    }

    private func fileFor(_ sessionId: String) -> URL {
        directory.appendingPathComponent(Self.sanitize(sessionId) + Self.extensionSuffix)
    }

    private func read(_ url: URL) -> PadelSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PadelSession.self, from: data)
    }

    /// El sessionId es un UUID generado por nosotros, pero nunca se construye una ruta
    /// con datos sin filtrar.
    private static func sanitize(_ sessionId: String) -> String {
        String(sessionId.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    private static let extensionSuffix = ".session.json"
}

/// Store en memoria para tests y para las previews de SwiftUI.
public final class InMemorySessionStore: SessionStore {
    private var sessions: [String: PadelSession] = [:]

    public init(_ initial: [PadelSession] = []) {
        for session in initial {
            sessions[session.sessionId] = session
        }
    }

    public func all() -> [PadelSession] {
        sessions.values.sorted { $0.startedAtEpochMs > $1.startedAtEpochMs }
    }

    public func get(_ sessionId: String) -> PadelSession? {
        sessions[sessionId]
    }

    public func upsert(_ session: PadelSession) {
        sessions[session.sessionId] = session
    }

    public func delete(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
    }
}
