import Foundation
import PadelCore

/// La copia de seguridad entera: el historial de sesiones y la liga, en un JSON.
///
/// Vive en el servidor de la comunidad, un hueco por usuario, y hace que reinstalar la
/// app no borre nada: el token sobrevive en el Llavero y con él vuelve todo. La copia
/// es por plataforma (los enums de iOS y Android no serializan igual): al cambiar de
/// sistema, lo que se comparte es la cuenta, no el historial local.
struct CopiaSeguridad: Codable {
    var version = 1
    var creadaEpochMs: Int64
    var sesiones: [PadelSession]
    /// El estado de la liga tal cual, el mismo shape que el backup manual de Ajustes.
    var ligaJson: String?

    static func construir(sesiones: [PadelSession], liga: Data?) -> Data? {
        let copia = CopiaSeguridad(
            creadaEpochMs: Int64(Date().timeIntervalSince1970 * 1000),
            sesiones: sesiones,
            ligaJson: liga.flatMap { String(data: $0, encoding: .utf8) }
        )
        return try? JSONEncoder().encode(copia)
    }

    static func abrir(_ data: Data) -> CopiaSeguridad? {
        try? JSONDecoder().decode(CopiaSeguridad.self, from: data)
    }
}
