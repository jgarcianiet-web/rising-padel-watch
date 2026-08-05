import Foundation

// Las métricas de temporada de la liga, portadas de `lib/metrics.ts` de la app Expo.
//
// Sobre los nombres: los campos `nivelBand`, `bandInicio`… conservan su nombre en el
// JSON porque son el puente con el backup de la app Expo, pero **el dato es el nivel
// que mide el reloj** (en partidos antiguos, el capturado de Padel Band). La interfaz
// ya no dice "Band" en ningún sitio: dice nivel del reloj, o nivel de la sesión.

struct LigaStatsFila: Identifiable {
    let etiqueta: String
    let n: Int
    let pctVictorias: Int?
    let pctBienJugados: Int?
    var id: String { etiqueta }
}

struct LigaGolpeAgregado: Identifiable {
    let golpe: String
    let veces: Int
    let media: Double
    var id: String { golpe }
}

enum LigaMetrics {

    // MARK: Rachas

    /// Racha actual: partidos bien jugados consecutivos desde el más reciente.
    /// La métrica estrella de la liga.
    static func racha(_ matches: [LigaMatch]) -> Int {
        var racha = 0
        for match in cronologico(matches).reversed() {
            guard match.bienJugado else { break }
            racha += 1
        }
        return racha
    }

    static func mejorRacha(_ matches: [LigaMatch]) -> Int {
        var mejor = 0
        var actual = 0
        for match in cronologico(matches) {
            actual = match.bienJugado ? actual + 1 : 0
            mejor = max(mejor, actual)
        }
        return mejor
    }

    static func pctVictorias(_ matches: [LigaMatch]) -> Int {
        guard !matches.isEmpty else { return 0 }
        let victorias = matches.filter { $0.resultado == "victoria" }.count
        return Int((Double(victorias) * 100 / Double(matches.count)).rounded())
    }

    // MARK: Nivel Playtomic y meta

    static func nivelActual(_ matches: [LigaMatch], perfil: LigaPerfil) -> Double? {
        if let ultimo = cronologico(matches).last(where: { $0.nivel != nil })?.nivel {
            return ultimo
        }
        return Double(perfil.nivelPlaytomic.replacingOccurrences(of: ",", with: "."))
    }

    static func nivelInicial(_ matches: [LigaMatch], perfil: LigaPerfil) -> Double? {
        if let inicial = Double(perfil.nivelPlaytomic.replacingOccurrences(of: ",", with: ".")) {
            return inicial
        }
        return cronologico(matches).first(where: { $0.nivel != nil })?.nivel
    }

    static func deltaNivel(_ matches: [LigaMatch], perfil: LigaPerfil) -> Double? {
        guard let actual = nivelActual(matches, perfil: perfil),
              let inicial = nivelInicial(matches, perfil: perfil) else { return nil }
        return actual - inicial
    }

    /// Progreso hacia la meta de temporada, 0-100. Nil si falta algún dato o la meta
    /// no supera el nivel inicial.
    static func progresoMeta(_ matches: [LigaMatch], perfil: LigaPerfil) -> Int? {
        guard let objetivo = Double(perfil.nivelObjetivo.replacingOccurrences(of: ",", with: ".")),
              let inicial = nivelInicial(matches, perfil: perfil),
              let actual = nivelActual(matches, perfil: perfil),
              objetivo > inicial else { return nil }
        let pct = (actual - inicial) / (objetivo - inicial) * 100
        return min(100, max(0, Int(pct.rounded())))
    }

    // MARK: Nivel del reloj por sesión

    /// Nivel de la sesión de un partido: el campo directo si existe y, si no, derivado
    /// de la curva (media de inicio y fin).
    static func nivelDeSesion(_ m: LigaMatch) -> Double? {
        if let nivel = m.nivelBand { return nivel }
        let puntos = [m.bandInicio, m.bandFin].compactMap { $0 }
        guard !puntos.isEmpty else { return nil }
        return puntos.reduce(0, +) / Double(puntos.count)
    }

    // MARK: Stats por grupo

    static func statsTipo(_ matches: [LigaMatch]) -> [LigaStatsFila] {
        [
            stats("Competitivo", matches.filter { $0.tipo == "competitivo" }),
            stats("Amistoso", matches.filter { $0.tipo == "amistoso" }),
        ]
    }

    static func statsPosicion(_ matches: [LigaMatch]) -> [LigaStatsFila] {
        [
            stats("Revés", matches.filter { $0.posicion == "reves" }),
            stats("Derecha", matches.filter { $0.posicion == "derecha" }),
        ]
    }

    static func statsCompanero(_ matches: [LigaMatch]) -> [LigaStatsFila] {
        var vistos = Set<String>()
        let companeros = matches.map(\.companero)
            .filter { !$0.isEmpty && vistos.insert($0).inserted }
        return companeros
            .map { companero in stats(companero, matches.filter { $0.companero == companero }) }
            .sorted { $0.n > $1.n }
            .prefix(4)
            .map { $0 }
    }

    private static func stats(_ etiqueta: String, _ ms: [LigaMatch]) -> LigaStatsFila {
        let victorias = ms.filter { $0.resultado == "victoria" }.count
        let bien = ms.filter(\.bienJugado).count
        return LigaStatsFila(
            etiqueta: etiqueta,
            n: ms.count,
            pctVictorias: ms.isEmpty ? nil : Int((Double(victorias) * 100 / Double(ms.count)).rounded()),
            pctBienJugados: ms.isEmpty ? nil : Int((Double(bien) * 100 / Double(ms.count)).rounded())
        )
    }

    // MARK: Golpes que se repiten

    static func topMejores(_ matches: [LigaMatch]) -> [LigaGolpeAgregado] {
        agrega(matches, golpe: \.mejorGolpe, punt: \.mejorPunt)
    }

    static func topPeores(_ matches: [LigaMatch]) -> [LigaGolpeAgregado] {
        agrega(matches, golpe: \.peorGolpe, punt: \.peorPunt)
    }

    private static func agrega(
        _ matches: [LigaMatch],
        golpe: (LigaMatch) -> String?,
        punt: (LigaMatch) -> Double?
    ) -> [LigaGolpeAgregado] {
        var mapa: [String: (veces: Int, suma: Double)] = [:]
        for m in matches {
            guard let nombre = golpe(m), !nombre.isEmpty, let nota = punt(m) else { continue }
            let previo = mapa[nombre] ?? (0, 0)
            mapa[nombre] = (previo.veces + 1, previo.suma + nota)
        }
        return mapa
            .map { LigaGolpeAgregado(golpe: $0.key, veces: $0.value.veces, media: $0.value.suma / Double($0.value.veces)) }
            .sorted { $0.veces > $1.veces }
            .prefix(3)
            .map { $0 }
    }

    // MARK: Objetivos

    /// % de cumplimiento de cada uno de los 3 objetivos sobre todos los partidos.
    static func cumplimientoObjetivos(_ matches: [LigaMatch]) -> [Int?] {
        (0..<3).map { index in
            guard !matches.isEmpty else { return nil }
            let cumplidos = matches.filter { index < $0.objetivos.count && $0.objetivos[index] }.count
            return Int((Double(cumplidos) * 100 / Double(matches.count)).rounded())
        }
    }

    // MARK: Evolución

    struct PuntoEvolucion: Identifiable {
        let fecha: String
        let nivel: Double?
        let sesion: Double?
        var id: String { fecha + "\(nivel ?? -1)-\(sesion ?? -1)" }
    }

    /// Un punto por partido con dato: el Playtomic (acumulativo) y el nivel de sesión
    /// del reloj, para pintarlos juntos como hacía la gráfica de evolución de la liga.
    static func evolucion(_ matches: [LigaMatch]) -> [PuntoEvolucion] {
        cronologico(matches)
            .filter { $0.nivel != nil || nivelDeSesion($0) != nil }
            .map {
                PuntoEvolucion(
                    fecha: LigaFechas.corta($0.fecha),
                    nivel: $0.nivel,
                    sesion: nivelDeSesion($0)
                )
            }
    }

    /// Orden cronológico ascendente, el que usan racha y evolución.
    private static func cronologico(_ matches: [LigaMatch]) -> [LigaMatch] {
        matches.sorted { $0.fecha < $1.fecha }
    }
}
