import Foundation

/// Volcado local a Liga Personal Pádel: el "adaptador" del contrato para cuando la app
/// de liga vive en el mismo teléfono y no hay servidor de por medio.
///
/// La URL lleva el MISMO JSON que el cuerpo de `POST /v1/padel-sessions`
/// (`docs/api-contract.md`), percent-encoded:
///
///     ligapadel://importar?datos=<payload>
///
/// Los eventos golpe a golpe se omiten siempre: la liga solo usa agregados y las URLs
/// tienen un límite práctico de tamaño (el equivalente al reintento `413` del contrato).
/// El lado receptor está documentado en `docs/INTEGRACION-RELOJ.md` del repo `padel`.
public enum LeagueDeepLink {
    public static let scheme = "ligapadel"

    /// - Parameter shareHealth: mismo consentimiento que en la subida HTTP. Si es false
    ///   el bloque `health` no viaja en absoluto.
    public static func url(for session: PadelSession, shareHealth: Bool) -> URL? {
        let payload = session.toPayload(shareHealth: shareHealth, includeEvents: false)
        let encoder = JSONEncoder()
        // Claves ordenadas: la URL es visible en logs del sistema y así es comparable.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8),
              // Solo alfanuméricos sin escapar: lo más conservador que existe, para que
              // ningún carácter del JSON (`{`, `"`, `&`…) pueda romper la query.
              let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "\(scheme)://importar?datos=\(encoded)")
    }
}
