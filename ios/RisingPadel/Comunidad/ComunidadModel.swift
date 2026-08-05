import Foundation
import Security
import SwiftUI
import UserNotifications

// La comunidad: tu cuenta, a quién sigues, el muro y quién está jugando ahora.
// Habla con el worker de `server/live` (rutas /v1/comunidad).

struct ComunidadPost: Identifiable, Equatable {
    let id: Int
    let alias: String
    let texto: String
    let tarjeta: LigaMatch?
    let etiquetas: [String]
    let creado: String
    var reacciones: Int
    var miReaccion: String?
    var comentarios: Int
}

struct ComunidadComentario: Identifiable, Equatable {
    let id: Int
    let alias: String
    let texto: String
}

struct ComunidadRankingFila: Identifiable, Equatable {
    let alias: String
    let partidos: Int
    let victorias: Int
    let golpeos: Int
    var id: String { alias }
}

struct ComunidadUsuario: Identifiable, Equatable {
    let alias: String
    var siguiendo: Bool
    var id: String { alias }
}

struct ComunidadEnVivo: Identifiable, Equatable {
    let alias: String
    let sessionId: String
    var id: String { sessionId }
}

/// La cuenta en el Llavero: el token ES la identidad, así que va donde los secretos.
enum ComunidadCuenta {
    private static let service = "com.risingpadel.watch.comunidad"

    static func read(_ campo: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: campo,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ campo: String, _ valor: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: campo,
        ]
        SecItemDelete(base as CFDictionary)
        guard let valor, !valor.isEmpty else { return }
        var attrs = base
        attrs[kSecValueData as String] = Data(valor.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }
}

@MainActor
final class ComunidadModel: ObservableObject {

    @Published private(set) var alias: String?
    @Published private(set) var posts: [ComunidadPost] = []
    @Published private(set) var usuarios: [ComunidadUsuario] = []
    @Published private(set) var jugando: [ComunidadEnVivo] = []
    /// La semana en curso entre tú y los que sigues, con datos de partidos reales.
    @Published private(set) var ranking: [ComunidadRankingFila] = []
    @Published var message: String?
    /// Partido ajeno abierto desde una notificación o desde el muro.
    @Published var espectador: ComunidadEnVivo?

    @AppStorage("leagueBaseURL") private var baseURL = ""

    init() {
        alias = ComunidadCuenta.read("alias")
        // El token APNs llega por el delegate de la app; aquí solo se escucha.
        NotificationCenter.default.addObserver(
            forName: .apnsToken, object: nil, queue: .main
        ) { [weak self] aviso in
            guard let token = aviso.object as? String else { return }
            Task { @MainActor in await self?.registrarDispositivo(token) }
        }
        NotificationCenter.default.addObserver(
            forName: .abrirEnVivo, object: nil, queue: .main
        ) { [weak self] aviso in
            guard let vivo = aviso.object as? ComunidadEnVivo else { return }
            Task { @MainActor in self?.espectador = vivo }
        }
    }

    var tieneCuenta: Bool { alias != nil }

    // MARK: Cuenta

    /// Crea la cuenta y deja configurada la liga entera: el mismo token sirve para el
    /// marcador en vivo, la subida de sesiones y la comunidad. Un registro, todo listo.
    func registrar(servidor: String, alias: String) async {
        guard let respuesta: [String: String] = await llamar(
            "POST", "v1/comunidad/registro", base: servidor,
            body: ["alias": alias.lowercased()], auth: false
        ) else { return }
        guard let token = respuesta["token"], let alias = respuesta["alias"] else {
            message = "Respuesta rara del servidor"
            return
        }
        ComunidadCuenta.write("alias", alias)
        ComunidadCuenta.write("token", token)
        self.alias = alias
        baseURL = servidor
        // El token de la liga pasa a ser el de la cuenta: todo por el mismo sitio.
        KeychainTokenStore.write(token)
        await pedirPermisoDePush()
        await refrescar()
    }

    private func pedirPermisoDePush() async {
        let concedido = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard concedido else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    private func registrarDispositivo(_ token: String) async {
        guard tieneCuenta else { return }
        let _: [String: String]? = await llamar(
            "POST", "v1/comunidad/dispositivo", body: ["token": token]
        )
    }

    // MARK: Muro y gente

    func refrescar() async {
        struct Muro: Decodable {
            struct Fila: Decodable {
                let id: Int
                let alias: String
                let text: String
                let card: String?
                let creado: String
                let etiquetas: String?
                let reacciones: Int?
                let miReaccion: String?
                let comentarios: Int?
            }
            let posts: [Fila]
        }
        if let muro: Muro = await llamar("GET", "v1/comunidad/muro") {
            posts = muro.posts.map { fila in
                ComunidadPost(
                    id: fila.id,
                    alias: fila.alias,
                    texto: fila.text,
                    tarjeta: fila.card.flatMap {
                        try? JSONDecoder().decode(LigaMatch.self, from: Data($0.utf8))
                    },
                    etiquetas: fila.etiquetas?.split(separator: ",").map(String.init) ?? [],
                    creado: String(fila.creado.prefix(10)),
                    reacciones: fila.reacciones ?? 0,
                    miReaccion: fila.miReaccion,
                    comentarios: fila.comentarios ?? 0
                )
            }
        }
        struct Ranking: Decodable {
            struct Fila: Decodable {
                let alias: String
                let partidos: Int
                let victorias: Int?
                let golpeos: Int?
            }
            let ranking: [Fila]
        }
        if let lista: Ranking = await llamar("GET", "v1/comunidad/ranking") {
            ranking = lista.ranking.map {
                ComunidadRankingFila(
                    alias: $0.alias, partidos: $0.partidos,
                    victorias: $0.victorias ?? 0, golpeos: $0.golpeos ?? 0
                )
            }
        }
        struct Jugando: Decodable {
            struct Fila: Decodable { let alias: String; let sessionId: String }
            let jugando: [Fila]
        }
        if let vivo: Jugando = await llamar("GET", "v1/comunidad/en-vivo") {
            jugando = vivo.jugando.map { ComunidadEnVivo(alias: $0.alias, sessionId: $0.sessionId) }
        }
    }

    func buscar(_ q: String) async {
        struct Lista: Decodable {
            struct Fila: Decodable { let alias: String; let siguiendo: Int }
            let usuarios: [Fila]
        }
        guard let lista: Lista = await llamar(
            "GET", "v1/comunidad/usuarios?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        ) else { return }
        usuarios = lista.usuarios.map { ComunidadUsuario(alias: $0.alias, siguiendo: $0.siguiendo != 0) }
    }

    func seguir(_ usuario: ComunidadUsuario) async {
        let metodo = usuario.siguiendo ? "DELETE" : "POST"
        let _: [String: String]? = await llamar(metodo, "v1/comunidad/seguir/\(usuario.alias)")
        if let index = usuarios.firstIndex(of: usuario) {
            usuarios[index].siguiendo.toggle()
        }
    }

    /// Publica en el muro. La tarjeta es un partido de la liga tal cual: quien lo
    /// recibe lo pinta con la misma tarjeta compartible.
    func publicar(texto: String, tarjeta: LigaMatch?) async {
        // Las @etiquetas se sacan del propio texto, como en cualquier red.
        let etiquetas = texto.split(separator: " ")
            .filter { $0.hasPrefix("@") }
            .map { String($0.dropFirst()).lowercased() }
        var body: [String: Any] = ["texto": texto, "etiquetas": etiquetas]
        if let tarjeta, let data = try? JSONEncoder().encode(tarjeta) {
            body["tarjeta"] = try? JSONSerialization.jsonObject(with: data)
        }
        let _: [String: Int]? = await llamarCrudo("POST", "v1/comunidad/publicar", json: body)
        await refrescar()
    }

    /// Reacciona (o quita la reacción repitiéndola). El estado local se adelanta al
    /// servidor: una reacción que tarda un segundo en pintarse no parece tuya.
    func reaccionar(_ post: ComunidadPost, emoji: String = "🎾") async {
        if let index = posts.firstIndex(of: post) {
            if posts[index].miReaccion == emoji {
                posts[index].miReaccion = nil
                posts[index].reacciones -= 1
            } else {
                if posts[index].miReaccion == nil { posts[index].reacciones += 1 }
                posts[index].miReaccion = emoji
            }
        }
        let _: [String: String]? = await llamarCrudo(
            "POST", "v1/comunidad/reaccion", json: ["postId": post.id, "emoji": emoji]
        )
    }

    func comentarios(de post: ComunidadPost) async -> [ComunidadComentario] {
        struct Lista: Decodable {
            struct Fila: Decodable { let id: Int; let alias: String; let text: String }
            let comentarios: [Fila]
        }
        guard let lista: Lista = await llamar("GET", "v1/comunidad/comentarios/\(post.id)")
        else { return [] }
        return lista.comentarios.map {
            ComunidadComentario(id: $0.id, alias: $0.alias, texto: $0.text)
        }
    }

    func comentar(_ post: ComunidadPost, texto: String) async {
        let _: [String: String]? = await llamarCrudo(
            "POST", "v1/comunidad/comentar", json: ["postId": post.id, "texto": texto]
        )
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index].comentarios += 1
        }
    }

    func borrar(_ post: ComunidadPost) async {
        let _: [String: String]? = await llamar("DELETE", "v1/comunidad/publicacion/\(post.id)")
        posts.removeAll { $0.id == post.id }
    }

    func reportar(_ post: ComunidadPost) async {
        let _: [String: String]? = await llamar(
            "POST", "v1/comunidad/reportar", body: ["postId": String(post.id)]
        )
        message = "Denunciado. Gracias por avisar."
    }

    func bloquear(_ alias: String) async {
        let _: [String: String]? = await llamar("POST", "v1/comunidad/bloquear/\(alias)")
        posts.removeAll { $0.alias == alias }
        message = "No verás más a \(alias)"
    }

    // MARK: HTTP

    private func llamar<T: Decodable>(
        _ metodo: String, _ ruta: String, base: String? = nil,
        body: [String: String]? = nil, auth: Bool = true
    ) async -> T? {
        await llamarCrudo(metodo, ruta, base: base, json: body, auth: auth)
    }

    private func llamarCrudo<T: Decodable>(
        _ metodo: String, _ ruta: String, base: String? = nil,
        json: Any? = nil, auth: Bool = true
    ) async -> T? {
        var raiz = (base ?? baseURL).trimmingCharacters(in: .whitespaces)
        while raiz.hasSuffix("/") { raiz.removeLast() }
        guard !raiz.isEmpty, let url = URL(string: raiz + "/" + ruta) else {
            message = "Configura el servidor de la comunidad"
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = metodo
        request.timeoutInterval = 15
        if auth, let token = ComunidadCuenta.read("token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        do {
            let (data, respuesta) = try await URLSession.shared.data(for: request)
            guard let http = respuesta as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else {
                message = (try? JSONDecoder().decode(FalloServidor.self, from: data))?.error.message
                    ?? "Error \(http.statusCode)"
                return nil
            }
            if data.isEmpty, let vacio = [String: String]() as? T { return vacio }
            return try? JSONDecoder().decode(T.self, from: data)
        } catch {
            message = "Sin conexión con la comunidad"
            return nil
        }
    }
}

/// El shape de error del worker. A nivel de fichero: Swift no permite declarar tipos
/// dentro de una función genérica.
private struct FalloServidor: Decodable {
    struct Detalle: Decodable { let message: String }
    let error: Detalle
}

extension Notification.Name {
    static let apnsToken = Notification.Name("apnsToken")
    static let abrirEnVivo = Notification.Name("abrirEnVivo")
}
