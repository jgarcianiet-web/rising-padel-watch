import Foundation

// Catálogos y helpers de la liga, portados de la app Expo (`constants/catalogos.ts`,
// `lib/marcador.ts`, `lib/date.ts`, `lib/metrics.ts`). Los textos son literales de la
// web-app original — no modificar: los backups viejos los referencian tal cual.

enum LigaCatalogos {

    static let defaultObjetivos = [
        "Menos de 5 errores no forzados",
        "Ganar el 60% de puntos en la red",
        "Actitud: no protestar ningún punto",
    ]

    static let catalogoObjetivos = [
        "Meter el 80% de primeros saques",
        "Devolver el 90% de los saques del rival",
        "No fallar ningún globo defensivo",
        "Ganar al menos 2 puntos con bandeja",
        "Ganar al menos 1 punto con víbora",
        "No perder ningún juego en blanco",
        "Subir a la red tras cada globo ofensivo",
        "Comunicarme con mi compañero en cada punto (mía/tuya)",
        "Cero remates forzados: rematar solo con bola clara",
        "Ganar 3 puntos con dejada",
        "Usar la pared en defensa con máximo 2 fallos",
        "No mandar dos derechas seguidas a la red",
        "Volver al centro de la pista tras cada golpe",
        "Mantener la calma tras 2 errores seguidos",
        "Variar el saque: mínimo 3 saques a la T",
        "Ganar un juego que vaya iguales (40-40)",
        "Jugar cruzado en defensa: máximo 3 paralelas arriesgadas",
        "No dejar botar ninguna bola fácil en la red",
        "Chiquita: meter 4 bolas bajas a los pies del rival",
        "Calentar 10 min y acabar sin molestias físicas",
    ]

    /// Volea y Globo unificados: Padel Band los separa por lado pero la liga los agrupa.
    static let golpes = [
        "Derecha", "Revés", "Volea", "Bandeja", "Víbora", "Remate", "Globo",
        "Saque", "Resto", "Salida de pared", "Bajada de pared", "Chiquita", "Dejada",
    ]
}

extension LigaMatch {
    /// La definición de la liga, citada en el prompt del entrenador: 2 de 3 objetivos.
    var bienJugado: Bool { objetivos.filter { $0 }.count >= 2 }
}

// MARK: - Fechas

/// Mismas tablas fijas que la app Expo (su runtime no garantizaba el locale es-ES;
/// aquí se mantienen para que las dos apps escriban exactamente lo mismo).
enum LigaFechas {

    private static let cortos = ["ene", "feb", "mar", "abr", "may", "jun",
                                 "jul", "ago", "sep", "oct", "nov", "dic"]
    private static let largos = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                                 "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    /// yyyy-mm-dd de hoy en hora local, el formato de fecha de la liga.
    static func hoy() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func fecha(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }

    /// "12 mar"
    static func corta(_ iso: String) -> String {
        guard let (dia, mes, _) = partes(iso) else { return iso }
        return "\(dia) \(cortos[mes - 1])"
    }

    /// "Marzo de 2026"
    static func mes(_ iso: String) -> String {
        guard let (_, mes, anno) = partes(iso) else { return iso }
        return "\(largos[mes - 1].capitalized) de \(anno)"
    }

    private static func partes(_ iso: String) -> (Int, Int, Int)? {
        let trozos = iso.split(separator: "-")
        guard trozos.count == 3,
              let anno = Int(trozos[0]), let mes = Int(trozos[1]), let dia = Int(trozos[2]),
              (1...12).contains(mes) else { return nil }
        return (dia, mes, anno)
    }
}

// MARK: - Marcador anotado a mano

/// Helpers del marcador del formulario, portados de `lib/marcador.ts`. Operan sobre
/// strings porque los campos del formulario original eran de texto, y el backup los
/// guarda así.
enum LigaMarcadorForm {

    static func vacio() -> [LigaSetMarcador] {
        [LigaSetMarcador(), LigaSetMarcador(), LigaSetMarcador()]
    }

    static func esTiebreak(_ s: LigaSetMarcador) -> Bool {
        guard let a = Int(s.yo), let b = Int(s.rival) else { return false }
        return (a == 7 && b == 6) || (a == 6 && b == 7)
    }

    static func setCompleto(_ s: LigaSetMarcador) -> Bool {
        !s.yo.isEmpty && !s.rival.isEmpty
    }

    static func setsJugados(_ marcador: [LigaSetMarcador]) -> [LigaSetMarcador] {
        marcador.filter(setCompleto)
    }

    static func setsGanados(_ marcador: [LigaSetMarcador]) -> Int {
        setsJugados(marcador).filter { (Int($0.yo) ?? 0) > (Int($0.rival) ?? 0) }.count
    }

    static func setsPerdidos(_ marcador: [LigaSetMarcador]) -> Int {
        setsJugados(marcador).filter { (Int($0.yo) ?? 0) < (Int($0.rival) ?? 0) }.count
    }

    /// Nil cuando no hay ningún set completo: el resultado se elige a mano.
    static func calcularResultado(_ marcador: [LigaSetMarcador]) -> String? {
        guard !setsJugados(marcador).isEmpty else { return nil }
        let g = setsGanados(marcador)
        let p = setsPerdidos(marcador)
        if g == p { return "empate" }
        return g > p ? "victoria" : "derrota"
    }

    static func formatearSets(_ marcador: [LigaSetMarcador]) -> String {
        setsJugados(marcador).map { s in
            var t = "\(s.yo)-\(s.rival)"
            if esTiebreak(s), !s.tbYo.isEmpty, !s.tbRival.isEmpty {
                t += "(\(s.tbYo)-\(s.tbRival))"
            }
            return t
        }
        .joined(separator: ", ")
    }
}

// MARK: - Salud

extension LigaSaludPartido {
    /// "1h 32m · 131 ppm medio · 154 máx · 480 kcal", omitiendo lo que no haya.
    var resumen: String {
        var trozos: [String] = []
        trozos.append(duracionMin >= 60
            ? "\(duracionMin / 60)h \(duracionMin % 60)m"
            : "\(duracionMin) min")
        if let medio = pulsoMedio { trozos.append("\(medio) ppm medio") }
        if let max = pulsoMax { trozos.append("\(max) máx") }
        if let kcal = calorias { trozos.append("\(kcal) kcal") }
        return trozos.joined(separator: " · ")
    }
}
