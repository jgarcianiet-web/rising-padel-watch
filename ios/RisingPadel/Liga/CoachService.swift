import Foundation
import PadelCore
import Security

// El entrenador IA de la Liga Personal, portado de la app Expo (`padel`,
// src/lib/anthropic.ts) y mejorado con lo que la app Expo no tenía: los hechos que el
// reloj mide con sensores.
//
// El reparto de papeles es el de `docs/insights.md`: el `InsightEngine` produce hechos
// verificables en el dispositivo ("ganaste 2 de 6 juegos al resto"), y el modelo redacta
// y sintetiza sobre ellos y sobre el registro de partidos. El modelo no puede inventar
// números que no estén en el prompt — o está en los hechos, o no se dice.

// MARK: - Clave de API (Llavero, nunca en el backup)

/// La clave de la API de Anthropic, en el Llavero — el equivalente exacto del
/// `expo-secure-store` de la app Expo, que la guardaba con la misma regla: **nunca en la
/// copia de seguridad de la liga**. El backup viaja por AirDrop y por email; una
/// credencial de pago no puede ir dentro.
enum CoachKeyStore {

    private static let service = "com.risingpadel.watch.coach"
    private static let account = "anthropic_api_key"

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
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func write(_ key: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        guard let key, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        var attributes = base
        attributes[kSecValueData as String] = Data(key.trimmingCharacters(in: .whitespaces).utf8)
        // El análisis se pide con la app abierta: no hace falta leer con el móvil
        // bloqueado, así que la clave queda mejor protegida que el token de la liga.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

// MARK: - Errores

/// Los mismos mensajes que daba la app Expo, para que el entrenador se sienta igual.
enum CoachError: LocalizedError {
    case sinClave
    case sinConexion
    case api(Int)
    case respuestaVacia

    var errorDescription: String? {
        switch self {
        case .sinClave:
            return "Añade tu clave de API de Anthropic en Ajustes para usar el entrenador."
        case .sinConexion:
            return "Sin conexión. Comprueba tu red e inténtalo de nuevo."
        case .api(401):
            return "Clave de API inválida. Revísala en Ajustes."
        case .api(429):
            return "Límite de peticiones alcanzado. Espera un momento y reintenta."
        case .api(let status):
            return "Error de la API (\(status)). Inténtalo de nuevo."
        case .respuestaVacia:
            return "Respuesta vacía"
        }
    }
}

// MARK: - Servicio

struct CoachService {

    private static let apiURL = "https://api.anthropic.com/v1/messages"
    /// La app Expo usaba `claude-sonnet-4-6`; aquí el análisis pasa al modelo actual más
    /// capaz. Es la pieza donde el usuario quiere que la IA "tenga peso": merece el
    /// mejor razonamiento disponible, y un análisis se pide unas pocas veces al mes.
    private static let model = "claude-opus-5"

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: Llamada cruda a /v1/messages

    // Swift no tiene SDK oficial de Anthropic, así que la llamada es HTTP a pelo — la
    // misma forma que el `fetch` de la app Expo, con el thinking adaptativo del modelo
    // actual. La respuesta llega como bloques de contenido; solo interesan los de texto
    // (los de razonamiento se descartan, igual que hacía el `.map` del original).

    private struct RequestBody: Encodable {
        struct Thinking: Encodable { let type: String }
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let maxTokens: Int
        let thinking: Thinking
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, thinking, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct ResponseBody: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]?
    }

    private func callAnthropic(_ prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = CoachKeyStore.read() else { throw CoachError.sinClave }
        guard let url = URL(string: Self.apiURL) else { throw CoachError.sinConexion }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // El modelo piensa antes de responder y el análisis es largo: el timeout por
        // defecto (60 s) se queda corto un mal día.
        request.timeoutInterval = 300
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: Self.model,
            maxTokens: maxTokens,
            thinking: .init(type: "adaptive"),
            messages: [.init(role: "user", content: prompt)]
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw CoachError.sinConexion
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CoachError.api(http.statusCode)
        }

        let body = try? JSONDecoder().decode(ResponseBody.self, from: data)
        return (body?.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    /// El modelo a veces envuelve el JSON en una valla de Markdown aunque se le pida que
    /// no. El puerto de `limpiarJson`.
    static func limpiarJson(_ texto: String) -> String {
        texto
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Los datos que ve el entrenador

    // El espejo del array `datos` de `analizarLiga`: cada partido reducido a lo que el
    // entrenador necesita, con los mismos nombres de campo que en la app Expo — el
    // prompt explica esa semántica campo a campo y tiene que seguir siendo verdad.

    private struct DatosCurva: Encodable {
        let inicio: Double?
        let fin: Double?
        let mediaHistoricaJugador: Double?
    }

    private struct DatosVolumen: Encodable {
        let totalGolpes: Int?
        let porGolpe: [LigaGolpeVolumen]?
    }

    private struct DatosSalud: Encodable {
        let duracionMin: Int
        let pulsoMedio: Int?
        let pulsoMax: Int?
        let calorias: Int?
    }

    private struct DatosPartido: Encodable {
        let fecha: String
        let tipo: String
        let resultado: String
        let sets: String?
        let posicion: String?
        let club: String?
        let companero: String?
        let nivelPlaytomic: Double?
        let nivelSesionReloj: Double?
        let mejorGolpe: String?
        let peorGolpe: String?
        let golpesSesionReloj: [LigaGolpeSesion]?
        let curvaSesionReloj: DatosCurva?
        let volumenGolpeoSesion: DatosVolumen?
        let salud: DatosSalud?
        let objetivosCumplidos: [String]
        let objetivosFallados: [String]
        let bienJugado: Bool
        let nota: String?
    }

    private static func datos(_ match: LigaMatch, objetivos: [String]) -> DatosPartido {
        func objetivo(_ index: Int) -> String? {
            index < objetivos.count ? objetivos[index] : nil
        }
        return DatosPartido(
            fecha: match.fecha,
            tipo: match.tipo,
            resultado: match.resultado,
            sets: match.sets.isEmpty ? nil : match.sets,
            posicion: match.posicion.isEmpty ? nil : match.posicion,
            club: match.club.isEmpty ? nil : match.club,
            companero: match.companero.isEmpty ? nil : match.companero,
            nivelPlaytomic: match.nivel,
            nivelSesionReloj: match.nivelBand,
            mejorGolpe: match.mejorGolpe.map { golpe in
                "\(golpe) (\(match.mejorPunt.map { formato($0) } ?? "?")/7)"
            },
            peorGolpe: match.peorGolpe.map { golpe in
                "\(golpe) (\(match.peorPunt.map { formato($0) } ?? "?")/7)"
            },
            golpesSesionReloj: match.golpesSesion,
            curvaSesionReloj: match.bandInicio != nil || match.bandFin != nil
                ? DatosCurva(
                    inicio: match.bandInicio,
                    fin: match.bandFin,
                    mediaHistoricaJugador: match.bandMediaJugador
                )
                : nil,
            volumenGolpeoSesion: match.golpesVolumen != nil || match.totalGolpes != nil
                ? DatosVolumen(totalGolpes: match.totalGolpes, porGolpe: match.golpesVolumen)
                : nil,
            salud: match.salud.map {
                DatosSalud(
                    duracionMin: $0.duracionMin,
                    pulsoMedio: $0.pulsoMedio,
                    pulsoMax: $0.pulsoMax,
                    calorias: $0.calorias
                )
            },
            objetivosCumplidos: match.objetivos.enumerated()
                .compactMap { $0.element ? objetivo($0.offset) : nil },
            objetivosFallados: match.objetivos.enumerated()
                .compactMap { $0.element ? nil : objetivo($0.offset) },
            // La definición de la liga, citada en el propio prompt: 2 de 3 objetivos.
            bienJugado: match.objetivos.filter { $0 }.count >= 2,
            nota: match.nota.isEmpty ? nil : match.nota
        )
    }

    private static func formato(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: Hechos del reloj

    /// Lo que la app Expo no podía tener: los hechos que el `InsightEngine` calcula
    /// sobre los sensores de las sesiones recientes. Cada línea trae su evidencia; el
    /// prompt le prohíbe al modelo inventar hechos de reloj que no estén aquí.
    static func hechosReloj(sessions: [PadelSession], limit: Int = 5) -> String? {
        let engine = InsightEngine()
        let lineas: [String] = sessions.prefix(limit).compactMap { session in
            let insights = engine.insights(for: session)
            guard !insights.isEmpty else { return nil }
            let fecha = fechaLocal(session.startedAtEpochMs)
            let cuerpo = insights
                .map { "  - [\($0.category.title)] \($0.headline): \($0.detail) (evidencia: \($0.evidence) lecturas)" }
                .joined(separator: "\n")
            return "Sesión del \(fecha) (\(session.totalShots) golpeos):\n\(cuerpo)"
        }
        guard !lineas.isEmpty else { return nil }
        return lineas.joined(separator: "\n\n")
    }

    private static func fechaLocal(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
    }

    // MARK: El análisis

    /// El puerto de `analizarLiga`: mismo prompt (heredado literalmente de la web-app
    /// original y de la app Expo), con una sección nueva de hechos medidos por el reloj.
    ///
    /// Con temporadas, `partidos` son los de la temporada en curso y `contextoTemporada`
    /// le cuenta al modelo dónde está (meta de partidos, temporadas anteriores para
    /// comparar). Sin temporadas, se le pasa todo y no hay contexto: la liga de siempre.
    func analizar(
        state: LigaState,
        partidos: [LigaMatch]? = nil,
        contextoTemporada: String? = nil,
        hechosReloj: String?
    ) async throws -> LigaAnalisis {
        let matches = (partidos ?? state.matches).sorted { $0.fecha < $1.fecha }
        let datos = matches.map { Self.datos($0, objetivos: state.objetivos) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let registro = String(data: (try? encoder.encode(datos)) ?? Data(), encoding: .utf8) ?? "[]"
        let objetivosJson = String(
            data: (try? encoder.encode(state.objetivos)) ?? Data(), encoding: .utf8
        ) ?? "[]"
        let perfil = state.perfil

        let seccionTemporada = contextoTemporada.map { contexto in
            """

            \(contexto)

            """
        } ?? ""

        let seccionReloj = hechosReloj.map { hechos in
            """

            HECHOS MEDIDOS POR EL RELOJ (sesiones recientes; cada hecho sale de una cuenta \
            sobre los sensores de la muñeca, con su evidencia): úsalos para afinar patrones \
            y plan — dicen cosas que el registro no ve, como el rendimiento al saque frente \
            al resto, la fatiga por tramos o la calidad de cada golpe dentro de la sesión. \
            Puedes citarlos tal cual, pero tienes PROHIBIDO inventar hechos de reloj que no \
            estén en esta lista.
            \(hechos)

            """
        } ?? ""

        let prompt = """
        Eres un entrenador de pádel de alto nivel, con años en pista. Analizas el registro de partidos de tu jugador. Eres directo, técnico y trabajas SIEMPRE sobre sus datos concretos: cada afirmación debe apoyarse en un número o hecho del registro. Prohibido el consejo genérico que valdría para cualquier jugador.

        PERFIL INICIAL (punto de partida de su liga personal):
        - Nivel Playtomic inicial: \(perfil.nivelPlaytomic.isEmpty ? "desconocido" : perfil.nivelPlaytomic)
        - Meta de nivel Playtomic de la temporada: \(perfil.nivelObjetivo.isEmpty ? "sin definir" : perfil.nivelObjetivo)
        - Nivel de sesión habitual, medido por el reloj: \(perfil.nivelBand.isEmpty ? "desconocido" : perfil.nivelBand)
        - Inicio de la liga: \(perfil.fechaInicio.isEmpty ? "desconocido" : perfil.fechaInicio)
        \(seccionTemporada)
        SUS 3 OBJETIVOS POR PARTIDO: \(objetivosJson)
        (un partido se considera "bien jugado" si cumple 2 de 3)

        SEMÁNTICA DE LOS DATOS:
        - nivelPlaytomic es acumulativo: fluctúa con victorias/derrotas de partidos competitivos.
        - nivelSesionReloj mide la calidad de golpeo SOLO de esa sesión (escala 1 peor - 7 mejor). Lo mide el reloj con sus sensores; en partidos antiguos venía capturado de la app Padel Band. No es acumulativo.
        - mejorGolpe/peorGolpe van puntuados de 1 (peor) a 7 (mejor).
        - golpesSesionReloj: cuando existe, es el desglose completo de la sesión (todos los golpes con su nota 1-7), medido por el reloj o capturado de Padel Band en registros antiguos. Es el dato más rico: úsalo para analizar la evolución de cada golpe entre sesiones.
        - curvaSesionReloj: cuando existe, es la curva de progreso DENTRO de esa sesión (nivel al inicio, nivel al final y media histórica del jugador). Un fin muy por debajo del inicio sugiere fatiga o desconexión al final de la sesión; compara también inicio/fin con la media histórica.
        - volumenGolpeoSesion: cuando existe, es el recuento de golpes de la sesión (total y desglose por tipo de golpe). Úsalo para analizar el estilo y la carga: qué golpes domina en frecuencia, si abusa o infrautiliza alguno respecto a su calidad (mucho volumen con nota baja = urgencia de corregir; poco volumen con nota alta = arma desaprovechada), y si el volumen alto se asocia a caídas de nivel al final de la sesión o a derrotas.
        - salud: cuando existe, son los datos del Apple Watch del partido (duración en minutos, pulso medio y máximo, calorías). Correlaciona el esfuerzo físico con los resultados y la calidad de golpeo: ¿rinde peor en partidos largos o de pulso alto?, ¿su nivel de sesión cae cuando el esfuerzo se dispara?
        - posicion: lado en que jugó (reves o derecha).

        REGISTRO (orden cronológico):
        \(registro)
        \(seccionReloj)
        Antes de responder, calcula mentalmente: % de cumplimiento de cada objetivo, rendimiento por posición (victorias y bien jugados en revés vs derecha), rendimiento competitivo vs amistoso, rendimiento con cada compañero si hay datos, ritmo hacia la meta de nivel si está definida, evolución del Playtomic desde el inicial, media del nivel de sesión y su tendencia, golpes que más se repiten como peor golpe y su puntuación media, y patrones en los sets (¿pierde terceros sets?, ¿arranca frío el primero?).

        ANÁLISIS FÍSICO (dale peso cuando haya datos de salud): calcula también el pulso medio en victorias vs derrotas, el nivel de sesión en partidos de pulso alto vs bajo (usa la mediana de sus pulsos como corte), el rendimiento en partidos largos (por encima de su duración media) vs cortos, y la fatiga dentro de la sesión (curva que acaba por debajo de su inicio, sobre todo si coincide con pulso o duración altos, o con volumen de golpeo alto). Si 3 o más partidos tienen datos de salud, uno de los "patrones" debe ser físico con sus números (ej: 'En tus 3 partidos con pulso medio >140 tu nivel de sesión cae a 3,1 frente a 3,8 cuando vas más bajo'), y si detectas un patrón físico claro, al menos una acción del "plan" debe atacarlo (gestión de esfuerzo, ritmo de puntos, físico específico de pádel). Si hay menos de 3 partidos con salud, dilo y no fuerces conclusiones físicas.

        Responde SOLO con un objeto JSON válido, sin Markdown ni texto fuera del JSON, con esta estructura exacta:
        {
          "lectura": "párrafo de 60-90 palabras con la lectura general de la temporada, citando números concretos (niveles, porcentajes, rachas)",
          "patrones": ["3 o 4 patrones detectados, cada uno de 20-35 palabras, cada uno con su dato concreto (ej: 'Tu peor golpe es la bandeja: registrada 4 veces con media 2,5/7...')"],
          "plan": ["2 o 3 acciones concretas para los próximos partidos, cada una de 20-40 palabras, con ejercicios específicos de pádel (series, repeticiones, situaciones de juego) ligados a los patrones detectados"],
          "foco": "UNA sola consigna medible para el próximo partido, máximo 15 palabras",
          "objetivos": ["exactamente 3 objetivos de partido nuevos que prescribes al jugador para su siguiente ciclo, cada uno de máximo 12 palabras"]
        }

        Reglas para los 3 objetivos prescritos:
        - Deben salir de los patrones detectados: ataca su peor golpe, su objetivo más fallado o su punto débil por posición.
        - Cada uno debe ser evaluable con sí/no al acabar un partido (con número o condición clara, ej: "Máximo 3 fallos con la bandeja").
        - Si uno de sus objetivos actuales aún no lo domina (lo cumple menos del 70% de las veces), mantenlo; si ya lo cumple casi siempre, sube la exigencia o sustitúyelo.
        - Deben poder cumplirse independientemente del compañero o rival.

        Si hay pocos datos para algún cálculo, dilo honestamente en ese punto en vez de inventar. Trata al jugador de tú, tono de entrenador de club: cercano, exigente, sin paños calientes.
        """

        let texto = try await callAnthropic(prompt, maxTokens: 4000)
        let limpio = Self.limpiarJson(texto)

        // Parse tolerante, como el original: si el modelo no devolvió JSON, el texto
        // entero pasa a ser la lectura antes que perder el análisis.
        var analisis: LigaAnalisis
        if let data = limpio.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(LigaAnalisis.self, from: data),
           !parsed.lectura.isEmpty {
            analisis = parsed
        } else if !limpio.isEmpty {
            analisis = LigaAnalisis(lectura: limpio)
        } else {
            throw CoachError.respuestaVacia
        }
        analisis.fecha = Self.fechaLocal(Int64(Date().timeIntervalSince1970 * 1000))
        analisis.nPartidos = matches.count
        return analisis
    }
}
