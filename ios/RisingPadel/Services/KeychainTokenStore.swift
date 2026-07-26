import Foundation
import Security

/// Guarda el token de la liga en el Keychain.
///
/// El token es una credencial, no una preferencia: en `UserDefaults` acabaría en los
/// backups en claro y en cualquier volcado de diagnóstico. `kSecAttrAccessible` es
/// `AfterFirstUnlock` para que la sincronización en segundo plano pueda leerlo con el
/// móvil bloqueado, pero no antes del primer desbloqueo tras un reinicio.
enum KeychainTokenStore {

    private static let service = "com.risingpadel.watch.league"
    private static let account = "league_token"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    static func write(_ token: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        guard let token, !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        var attributes = base
        attributes[kSecValueData as String] = Data(token.trimmingCharacters(in: .whitespaces).utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
