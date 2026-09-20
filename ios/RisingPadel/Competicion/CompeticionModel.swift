import Foundation
import SwiftUI

// Competición: clubes y ligas contra otros (§36.14, §36.16 y §36.19 del documento de
// producto). Habla con el worker de `server/live` (rutas /v1/competicion).
//
// ## Esto NO es la "Liga Personal" que ya tiene la app
//
// Conviene tenerlo claro antes de tocar nada, porque los dos se llaman "liga":
//
// - La **Liga Personal** (`Liga/LigaModel.swift`) es el jugador **contra sí mismo**: su
//   historial de partidos, sus temporadas, sus tres objetivos y su nivel medido. Vive
//   **dentro del móvil**, en un JSON local, y funciona sin cuenta ni cobertura. Contesta
//   a "¿estoy mejorando?".
// - Esto de aquí es la **competición contra otros**: clubes, inscripciones, calendario de
//   todos contra todos y clasificación compartida. Vive **en el servidor** y necesita la
//   cuenta de la comunidad. Contesta a "¿quién va primero?".
//
// No comparten modelos ni almacenamiento a propósito: un partido de allí es una entrada
// del diario de un jugador, y uno de aquí es una fila de una tabla que ven diez personas.
// Fusionarlos obligaría a que el diario personal dependiera de la red, que es justo lo
// que la Liga Personal no quiere.

// MARK: Modelos del contrato

/// Un club en la lista de "mis clubes". `papel` es el mío dentro de él.
struct ClubResumido: Identifiable, Decodable, Equatable {
    let id: Int
    let nombre: String
    let ciudad: String?
    let papel: String?
}

struct FichaDeClub: Decodable, Equatable {
    let id: Int
    let nombre: String
    let ciudad: String?
}

struct MiembroDeClub: Identifiable, Decodable, Equatable {
    let id: Int
    let alias: String
    let papel: String
}

struct LigaDeClub: Identifiable, Decodable, Equatable {
    let id: Int
    let nombre: String
    let estado: String
}

/// Las cuentas del panel del §36.19. Vienen calculadas del servidor y son cuentas
/// exactas, no estimaciones: no se recalculan aquí.
struct ResumenDeClub: Decodable, Equatable {
    let jugadores: Int
    let entrenadores: Int
    let ligas: Int
}

struct PanelDeClub: Decodable, Equatable {
    let club: FichaDeClub
    let miembros: [MiembroDeClub]
    let ligas: [LigaDeClub]
    let resumen: ResumenDeClub
}

struct LigaResumida: Identifiable, Decodable, Equatable {
    let id: Int
    let nombre: String
    let formato: String
    let estado: String
    let desde: String?
    let hasta: String?
}

struct FichaDeLiga: Decodable, Equatable {
    let id: Int
    let nombre: String
    let formato: String
    let estado: String
    let desde: String?
    let hasta: String?
    let soyOrganizador: Bool

    var esDeParejas: Bool { formato == "parejas" }
    var estaAbierta: Bool { estado == "abierta" }
}

struct InscripcionDeLiga: Identifiable, Decodable, Equatable {
    let id: Int
    let nombre: String
}

struct PartidoDeLiga: Identifiable, Decodable, Equatable {
    let id: Int
    let ronda: Int
    let local: String
    let visitante: String
    /// Nulos mientras no se ha jugado. Un 0-0 **no** es un partido jugado: el servidor ni
    /// siquiera lo acepta (rechaza los empates), así que el único "sin jugar" es el nulo.
    let juegosLocal: Int?
    let juegosVisitante: Int?
    let fecha: String?
    let sesion: String?

    var jugado: Bool { juegosLocal != nil && juegosVisitante != nil }

    /// "6-4" o "—" si aún no se ha jugado.
    var marcador: String {
        guard let local = juegosLocal, let visitante = juegosVisitante else { return "—" }
        return "\(local)-\(visitante)"
    }
}

struct FilaDeClasificacion: Identifiable, Decodable, Equatable {
    let puesto: Int
    let entryId: Int
    let nombre: String
    let jugados: Int
    let ganados: Int
    let perdidos: Int
    let juegosFavor: Int
    let juegosContra: Int
    let diferencia: Int
    let puntos: Int

    var id: Int { entryId }
}

struct DetalleDeLiga: Decodable, Equatable {
    let liga: FichaDeLiga
    let inscripciones: [InscripcionDeLiga]
    let calendario: [PartidoDeLiga]
    let clasificacion: [FilaDeClasificacion]
}

// MARK: El modelo

/// El estado de competición del usuario: sus ligas, sus clubes y las llamadas al
/// servidor.
///
/// No guarda nada en disco. Es deliberado: la clasificación y el calendario son de
/// todos, cambian cuando un rival apunta su resultado, y una copia local solo serviría
/// para enseñar una tabla que ya no es verdad. Lo único que se recuerda entre arranques
/// es lo que ya recordaba la app — la URL del servidor y el token de la cuenta.
@MainActor
final class CompeticionModel: ObservableObject {

    @Published private(set) var ligas: [LigaResumida] = []
    @Published private(set) var clubes: [ClubResumido] = []
    /// Mi alias de la comunidad: hace falta para saber qué partidos del calendario son
    /// míos, porque el servidor manda los nombres ya compuestos ("ana / luis") y no ids.
    @Published private(set) var alias: String?
    @Published private(set) var cargando = false
    @Published var mensaje: String?

    @AppStorage("leagueBaseURL") private var baseURL = ""

    init() {
        alias = ComunidadCuenta.read("alias")
    }

    /// La competición entera va con la cuenta de la comunidad: sin ella no hay a quién
    /// inscribir ni a nombre de quién apuntar un resultado.
    var tieneCuenta: Bool { ComunidadCuenta.read("token") != nil }

    // MARK: Lectura

    func refrescar() async {
        alias = ComunidadCuenta.read("alias")
        guard tieneCuenta else { return }
        cargando = true
        defer { cargando = false }

        struct ListaDeLigas: Decodable { let ligas: [LigaResumida] }
        if let lista: ListaDeLigas = await llamar("GET", "v1/competicion/ligas") {
            ligas = lista.ligas
        }
        struct ListaDeClubes: Decodable { let clubes: [ClubResumido] }
        if let lista: ListaDeClubes = await llamar("GET", "v1/competicion/clubes") {
            clubes = lista.clubes
        }
    }

    func liga(_ id: Int) async -> DetalleDeLiga? {
        await llamar("GET", "v1/competicion/ligas/\(id)")
    }

    func club(_ id: Int) async -> PanelDeClub? {
        await llamar("GET", "v1/competicion/clubes/\(id)")
    }

    // MARK: Clubes

    /// Crea el club y devuelve su id. Quien lo crea queda de administrador.
    @discardableResult
    func crearClub(nombre: String, ciudad: String) async -> Int? {
        struct Creado: Decodable { let id: Int; let nombre: String }
        let creado: Creado? = await llamar(
            "POST", "v1/competicion/clubes",
            json: ["nombre": nombre, "ciudad": ciudad]
        )
        guard let creado else { return nil }
        await refrescar()
        return creado.id
    }

    @discardableResult
    func unirmeAlClub(_ id: Int) async -> Bool {
        guard await confirmar("POST", "v1/competicion/clubes/\(id)/unirme") else { return false }
        await refrescar()
        return true
    }

    // MARK: Ligas

    /// Crea la liga y devuelve su id. Nace "abierta": admite inscripciones hasta que su
    /// organizador genera el calendario.
    @discardableResult
    func crearLiga(
        nombre: String, formato: String, club: Int?, desde: String?, hasta: String?
    ) async -> Int? {
        var cuerpo: [String: Any] = ["nombre": nombre, "formato": formato]
        if let club { cuerpo["club"] = club }
        if let desde, !desde.isEmpty { cuerpo["desde"] = desde }
        if let hasta, !hasta.isEmpty { cuerpo["hasta"] = hasta }

        struct Creada: Decodable { let id: Int; let nombre: String; let formato: String }
        let creada: Creada? = await llamar("POST", "v1/competicion/ligas", json: cuerpo)
        guard let creada else { return nil }
        await refrescar()
        return creada.id
    }

    /// Me inscribe. En una liga de parejas el alias del compañero es obligatorio y lo
    /// exige el servidor, así que aquí se manda tal cual y se deja que él conteste si no
    /// existe esa cuenta.
    @discardableResult
    func inscribirme(liga: Int, pareja: String?) async -> Bool {
        var cuerpo: [String: Any] = [:]
        if let pareja, !pareja.isEmpty { cuerpo["pareja"] = pareja }
        guard await confirmar(
            "POST", "v1/competicion/ligas/\(liga)/inscribirme", json: cuerpo
        ) else { return false }
        await refrescar()
        return true
    }

    /// Genera el calendario de todos contra todos y arranca la liga. Solo el organizador,
    /// y solo una vez: a partir de aquí ya no entra nadie más.
    @discardableResult
    func generarCalendario(liga: Int) async -> Bool {
        struct Generado: Decodable { let rondas: Int; let partidos: Int }
        // Sin cuerpo: esta ruta no lleva parámetros y el worker ya trata el POST vacío
        // como `{}`.
        let generado: Generado? = await llamar(
            "POST", "v1/competicion/ligas/\(liga)/calendario"
        )
        guard let generado else { return false }
        mensaje = "Calendario listo: \(generado.rondas) rondas y \(generado.partidos) partidos"
        await refrescar()
        return true
    }

    /// Apunta el resultado de un partido. Solo lo acepta de quien lo jugó, y no admite
    /// empates — en pádel no se empata, así que la pantalla ya no deja mandarlos.
    @discardableResult
    func apuntarResultado(
        liga: Int, partido: Int, juegosLocal: Int, juegosVisitante: Int, fecha: String?
    ) async -> Bool {
        guard juegosLocal != juegosVisitante else {
            mensaje = "Un partido de pádel no acaba en empate"
            return false
        }
        var cuerpo: [String: Any] = [
            "partido": partido,
            "juegosLocal": juegosLocal,
            "juegosVisitante": juegosVisitante,
        ]
        if let fecha, !fecha.isEmpty { cuerpo["fecha"] = fecha }
        return await confirmar(
            "POST", "v1/competicion/ligas/\(liga)/resultado", json: cuerpo
        )
    }

    // MARK: Quién soy en una liga

    /// Si aparezco en un nombre de inscripción. El servidor compone los nombres de
    /// parejas como "ana / luis", así que hay que mirar dentro; comparar la cadena entera
    /// dejaría fuera a media pareja.
    func participo(en nombre: String) -> Bool {
        guard let alias, !alias.isEmpty else { return false }
        return nombre.split(separator: "/").contains {
            $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(alias) == .orderedSame
        }
    }

    func esMio(_ partido: PartidoDeLiga) -> Bool {
        participo(en: partido.local) || participo(en: partido.visitante)
    }

    // MARK: HTTP

    /// Para las respuestas que solo dicen `{ok:true}`: interesa si salió bien, no qué
    /// devolvió.
    private func confirmar(_ metodo: String, _ ruta: String, json: Any? = nil) async -> Bool {
        struct Vale: Decodable { let ok: Bool }
        let vale: Vale? = await llamar(metodo, ruta, json: json)
        return vale?.ok == true
    }

    /// Mismo patrón que `ComunidadModel`: token del Llavero, base de `leagueBaseURL` y el
    /// mensaje de error del servidor tal cual, que ya viene en español.
    private func llamar<T: Decodable>(
        _ metodo: String, _ ruta: String, json: Any? = nil
    ) async -> T? {
        var raiz = baseURL.trimmingCharacters(in: .whitespaces)
        while raiz.hasSuffix("/") { raiz.removeLast() }
        guard !raiz.isEmpty, let url = URL(string: raiz + "/" + ruta) else {
            mensaje = "Configura el servidor de la comunidad antes de competir"
            return nil
        }
        // Se comprueba aquí para no gastar un viaje y un 401 en decir algo que ya se
        // sabe: sin cuenta no hay competición.
        guard let token = ComunidadCuenta.read("token") else {
            mensaje = "Hace falta una cuenta de la comunidad para competir"
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = metodo
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }

        do {
            let (data, respuesta) = try await URLSession.shared.data(for: request)
            guard let http = respuesta as? HTTPURLResponse else {
                mensaje = "Respuesta rara del servidor"
                return nil
            }
            guard (200..<300).contains(http.statusCode) else {
                mensaje = (try? JSONDecoder().decode(FalloDeCompeticion.self, from: data))?
                    .error.message ?? Self.mensaje(estado: http.statusCode)
                return nil
            }
            guard let decodificado = try? JSONDecoder().decode(T.self, from: data) else {
                mensaje = "El servidor contestó algo que esta versión no entiende"
                return nil
            }
            return decodificado
        } catch {
            mensaje = "Sin conexión con la competición"
            return nil
        }
    }

    /// Red de seguridad para cuando el fallo no trae cuerpo (un proxy, un 502 de la CDN).
    /// Con cuerpo manda siempre el mensaje del servidor, que es más concreto que esto.
    private static func mensaje(estado: Int) -> String {
        switch estado {
        case 401: return "Tu cuenta no vale aquí: vuelve a entrar desde Comunidad"
        case 403: return "No tienes permiso para hacer eso"
        case 404: return "Eso ya no existe en el servidor"
        case 409: return "Llegas tarde: eso ya se hizo"
        default: return "El servidor respondió \(estado)"
        }
    }
}

/// El shape de error del worker (`{error:{code,message}}`). A nivel de fichero porque
/// Swift no deja declarar tipos dentro de una función genérica.
private struct FalloDeCompeticion: Decodable {
    struct Detalle: Decodable {
        let code: String
        let message: String
    }
    let error: Detalle
}

// MARK: Textos compartidos

/// Las traducciones de los valores que el servidor guarda en inglés o en clave. Aquí y
/// no en cada vista: el mismo "player" sale en el panel del club y en la lista de
/// miembros, y dos traducciones distintas de lo mismo se notan.
enum CompeticionTextos {

    static func papel(_ papel: String?) -> String {
        switch papel {
        case "admin": return "Administrador"
        case "coach": return "Entrenador"
        case "player": return "Jugador"
        default: return "Miembro"
        }
    }

    static func formato(_ formato: String) -> String {
        formato == "parejas" ? "Parejas" : "Individual"
    }

    static func estado(_ estado: String) -> String {
        estado == "abierta" ? "Abierta" : "En curso"
    }

    /// Abierta en azul de pista (se puede entrar), en curso en verde (está viva).
    static func colorDeEstado(_ estado: String) -> Color {
        estado == "abierta" ? T.pista : T.verde
    }

    /// "12 mar – 30 jun", o vacío si la liga no tiene fechas. El servidor guarda cadena
    /// vacía cuando no se le dan, no nulo, así que hay que filtrar las dos cosas.
    static func fechas(desde: String?, hasta: String?) -> String {
        let inicio = corta(desde)
        let fin = corta(hasta)
        if !inicio.isEmpty && !fin.isEmpty { return "\(inicio) – \(fin)" }
        return inicio.isEmpty ? fin : inicio
    }

    /// "12 mar" de una fecha del servidor, reutilizando el formateador de la liga.
    static func corta(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        return LigaFechas.corta(iso)
    }
}
