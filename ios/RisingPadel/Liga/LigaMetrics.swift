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

/// El cara a cara con una persona: cuántas veces has jugado contra (o con) ella y cómo
/// fue. `ultimos` son los resultados más recientes, true = victoria, el último el más
/// nuevo — para pintar la mini-racha VVDVV. Espejo del core Kotlin, con tests allí.
struct LigaCaraACara: Identifiable {
    let nombre: String
    let partidos: Int
    let victorias: Int
    let ultimos: [Bool]

    var id: String { nombre }
    var pctVictorias: Int { partidos == 0 ? 0 : victorias * 100 / partidos }
}

enum LigaMetrics {

    /// Estadísticas contra cada rival. `rivales` es texto libre ("Juan y Pedro"): se
    /// separa por comas, " y ", "/" o "&" y se agrupa por nombre normalizado; se
    /// enseña la grafía de la primera vez. Más partidos primero; a igualdad, alfabético.
    static func caraACara(_ matches: [LigaMatch]) -> [LigaCaraACara] {
        agrupa(matches) { partirNombres($0.rivales ?? "") }
    }

    /// Lo mismo, pero con la pareja: con quién juegas y cómo os va.
    static func conPareja(_ matches: [LigaMatch]) -> [LigaCaraACara] {
        agrupa(matches) { partirNombres($0.companero) }
    }

    /// "Juan y Pedro" → ["Juan", "Pedro"]. Separadores: coma, " y ", "/", "&".
    static func partirNombres(_ texto: String) -> [String] {
        texto.replacingOccurrences(of: " y ", with: ",")
            .replacingOccurrences(of: "/", with: ",")
            .replacingOccurrences(of: "&", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func agrupa(
        _ matches: [LigaMatch], nombresDe: (LigaMatch) -> [String]
    ) -> [LigaCaraACara] {
        var grafias: [String: String] = [:]
        var resultados: [String: [Bool]] = [:]
        for match in cronologico(matches) {
            for nombre in nombresDe(match) {
                let clave = nombre.lowercased()
                if grafias[clave] == nil { grafias[clave] = nombre }
                resultados[clave, default: []].append(match.resultado == "victoria")
            }
        }
        return resultados
            .map { clave, lista in
                LigaCaraACara(
                    nombre: grafias[clave] ?? clave,
                    partidos: lista.count,
                    victorias: lista.filter { $0 }.count,
                    ultimos: Array(lista.suffix(5))
                )
            }
            .sorted { ($0.partidos, $1.nombre) > ($1.partidos, $0.nombre) }
    }

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

    /// Porcentaje de victorias sobre los partidos **con resultado**.
    ///
    /// Los entrenos sin marcador quedan fuera del denominador: si contaran, entrenar
    /// bajaría tu porcentaje de victorias, que es exactamente al revés de lo que pasa.
    static func pctVictorias(_ matches: [LigaMatch]) -> Int {
        let jugados = matches.filter { ResultadoDePartido.cuenta($0.resultado) }
        guard !jugados.isEmpty else { return 0 }
        let victorias = jugados.filter { $0.resultado == "victoria" }.count
        return Int((Double(victorias) * 100 / Double(jugados.count)).rounded())
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

    // MARK: Evolución de un golpe

    struct PuntoGolpe: Identifiable {
        let fechaISO: String
        let fecha: String
        let nota: Double
        let cantidad: Int?
        var id: String { fechaISO }
    }

    struct EvolucionGolpe {
        let puntos: [PuntoGolpe]
        var veces: Int { puntos.count }
        var media: Double? { promedia(puntos.map(\.nota)) }
        var mejor: Double? { puntos.map(\.nota).max() }
        var peor: Double? { puntos.map(\.nota).min() }
    }

    /// Trayectoria de un golpe a través de las sesiones: su nota media y cuántos se
    /// dieron cada día que aparece. El puerto de `calcEvolucionGolpe`.
    static func evolucionGolpe(_ matches: [LigaMatch], nombre: String) -> EvolucionGolpe {
        let clave = nombre.lowercased()
        let puntos: [PuntoGolpe] = cronologico(matches).compactMap { m in
            let notas = (m.golpesSesion ?? [])
                .filter { $0.nombre.lowercased() == clave }
                .map(\.nota)
            guard !notas.isEmpty else { return nil }
            let cantidades = (m.golpesVolumen ?? [])
                .filter { $0.nombre.lowercased() == clave }
                .map(\.cantidad)
            return PuntoGolpe(
                fechaISO: m.fecha,
                fecha: LigaFechas.corta(m.fecha),
                nota: ((notas.reduce(0, +) / Double(notas.count)) * 10).rounded() / 10,
                cantidad: cantidades.isEmpty ? nil : cantidades.reduce(0, +)
            )
        }
        return EvolucionGolpe(puntos: puntos)
    }

    // MARK: Resumen mensual

    struct ResumenMes {
        let clave: String
        let n: Int
        let pctVictorias: Int?
        let pctBienJugados: Int?
        let nivelCierre: Double?
    }

    /// Mes en curso contra el anterior, para ver de un vistazo si el mes va mejor.
    static func resumenMensual(_ matches: [LigaMatch], hoyISO: String) -> (actual: ResumenMes, anterior: ResumenMes)? {
        let trozos = hoyISO.split(separator: "-").compactMap { Int($0) }
        guard trozos.count >= 2 else { return nil }
        let (ano, mes) = (trozos[0], trozos[1])
        let actualKey = String(format: "%04d-%02d", ano, mes)
        let prevKey = mes == 1
            ? String(format: "%04d-12", ano - 1)
            : String(format: "%04d-%02d", ano, mes - 1)
        return (
            resumenDeMes(matches, anoMes: actualKey),
            resumenDeMes(matches, anoMes: prevKey)
        )
    }

    private static func resumenDeMes(_ matches: [LigaMatch], anoMes: String) -> ResumenMes {
        let ms = cronologico(matches).filter { $0.fecha.hasPrefix(anoMes) }
        let victorias = ms.filter { $0.resultado == "victoria" }.count
        let bien = ms.filter(\.bienJugado).count
        return ResumenMes(
            clave: LigaFechas.mes("\(anoMes)-15"),
            n: ms.count,
            pctVictorias: ms.isEmpty ? nil : Int((Double(victorias) * 100 / Double(ms.count)).rounded()),
            pctBienJugados: ms.isEmpty ? nil : Int((Double(bien) * 100 / Double(ms.count)).rounded()),
            nivelCierre: ms.last(where: { $0.nivel != nil })?.nivel
        )
    }

    private static func promedia(_ valores: [Double]) -> Double? {
        valores.isEmpty ? nil : valores.reduce(0, +) / Double(valores.count)
    }

    /// Orden cronológico ascendente, el que usan racha y evolución.
    private static func cronologico(_ matches: [LigaMatch]) -> [LigaMatch] {
        matches.sorted { $0.fecha < $1.fecha }
    }
}
