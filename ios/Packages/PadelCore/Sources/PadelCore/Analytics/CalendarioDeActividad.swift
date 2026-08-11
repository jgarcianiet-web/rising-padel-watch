import Foundation

/// Aritmética de fechas `yyyy-mm-dd`, sin `Calendar` ni husos horarios.
///
/// Existe porque las fechas de la liga son cadenas y lo que hace falta de ellas es
/// **restar**: cuántos días quedan de temporada, en qué casilla del calendario cae un día.
/// Hacerlo con `Calendar` mete husos y horarios de verano en un problema que no los tiene:
/// "del 1 de septiembre al 30 de junio" son los mismos días en Madrid que en Buenos Aires.
///
/// El algoritmo es el `days_from_civil` de Howard Hinnant. Espejo del core Kotlin, con
/// tests allí.
public enum Fechas {

    /// Día 0 = 1970-01-01. Nil si la cadena no es una fecha.
    public static func diasDesdeEpoca(_ iso: String) -> Int? {
        guard let (anno, mes, dia) = partes(iso) else { return nil }
        // Marzo pasa a ser el primer mes: así el 29 de febrero cae al final del año y los
        // bisiestos dejan de necesitar un caso aparte.
        let y = mes <= 2 ? anno - 1 : anno
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = mes > 2 ? mes - 3 : mes + 9
        let doy = (153 * mp + 2) / 5 + dia - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// El inverso: de día de época a `yyyy-mm-dd`.
    public static func isoDesdeDias(_ dias: Int) -> String {
        let z = dias + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let dia = doy - (153 * mp + 2) / 5 + 1
        let mes = mp < 10 ? mp + 3 : mp - 9
        let anno = mes <= 2 ? y + 1 : y
        return String(format: "%04d-%02d-%02d", anno, mes, dia)
    }

    /// Días de `desde` a `hasta`, negativo si `hasta` es anterior.
    public static func diasEntre(_ desde: String, _ hasta: String) -> Int? {
        guard let a = diasDesdeEpoca(desde), let b = diasDesdeEpoca(hasta) else { return nil }
        return b - a
    }

    /// 0 = lunes … 6 = domingo. El 1970-01-01 fue jueves.
    public static func diaDeLaSemana(_ iso: String) -> Int? {
        guard let dias = diasDesdeEpoca(iso) else { return nil }
        return ((dias + 3) % 7 + 7) % 7
    }

    /// `yyyy-mm-dd` de una fecha en el huso del dispositivo. Es la única función que sí
    /// mira el calendario del sistema: convertir un instante a "qué día fue aquí" es
    /// justo lo que depende del sitio donde estés.
    public static func isoLocal(_ fecha: Date, calendario: Calendar = .current) -> String {
        let c = calendario.dateComponents([.year, .month, .day], from: fecha)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func hoyISO(calendario: Calendar = .current) -> String {
        isoLocal(Date(), calendario: calendario)
    }

    private static func partes(_ iso: String) -> (Int, Int, Int)? {
        let trozos = iso.split(separator: "-")
        guard trozos.count == 3,
              let anno = Int(trozos[0]), let mes = Int(trozos[1]), let dia = Int(trozos[2]),
              (1...12).contains(mes), (1...31).contains(dia) else { return nil }
        return (anno, mes, dia)
    }
}

/// Un día del calendario. `golpes == 0` es un día sin jugar, no un hueco.
public struct DiaDeActividad: Sendable, Equatable, Identifiable {
    public let fechaISO: String
    public let sesiones: Int
    public let golpes: Int
    public let minutos: Int

    public var id: String { fechaISO }
    public var jugado: Bool { sesiones > 0 }

    public init(fechaISO: String, sesiones: Int, golpes: Int, minutos: Int) {
        self.fechaISO = fechaISO
        self.sesiones = sesiones
        self.golpes = golpes
        self.minutos = minutos
    }
}

/// Las últimas semanas de juego en una cuadrícula, un cuadro por día.
///
/// El histórico es una lista y una lista contesta "¿qué hice el martes?" pero no "¿estoy
/// jugando menos que el mes pasado?". Esa segunda pregunta es la que hace que alguien
/// vuelva a abrir la app, y se contesta de un vistazo o no se contesta: un hueco de dos
/// semanas se ve, no se lee.
///
/// Espejo del core Kotlin, con tests allí.
public struct CalendarioDeActividad: Sendable {
    /// Una lista por semana, de lunes a domingo, siempre siete días.
    public let semanas: [[DiaDeActividad]]
    /// El día con más golpes del periodo, para escalar la intensidad del color.
    public let maxGolpes: Int
    public let diasJugados: Int
    /// Días seguidos jugando que acaban hoy o ayer.
    public let rachaActual: Int
    public let mejorRacha: Int

    public var hayDatos: Bool { diasJugados > 0 }

    public var diasPorSemana: Float {
        semanas.isEmpty ? 0 : Float(diasJugados) / Float(semanas.count)
    }

    /// Doce semanas: un trimestre entra en el ancho de un móvil sin apretar.
    public static let semanasPorDefecto = 12

    /// - Parameter porDia: lo que se jugó cada día, con la fecha ya en local. La
    ///   conversión de instante a fecha la hace la app porque depende del huso del móvil.
    public static func de(
        _ porDia: [DiaDeActividad],
        hastaISO: String,
        semanas: Int = semanasPorDefecto
    ) -> CalendarioDeActividad? {
        guard let hasta = Fechas.diasDesdeEpoca(hastaISO),
              let diaSemana = Fechas.diaDeLaSemana(hastaISO) else { return nil }

        // Se termina el domingo de la semana en curso y se retrocede N semanas enteras:
        // así todas las columnas tienen siete días y ninguna sale coja.
        let ultimo = hasta + (6 - diaSemana)
        let primero = ultimo - (semanas * 7 - 1)

        var indice: [String: DiaDeActividad] = [:]
        for dia in porDia { indice[dia.fechaISO] = dia }

        let cuadricula: [[DiaDeActividad]] = (0..<semanas).map { semana in
            (0..<7).map { dia in
                let fecha = Fechas.isoDesdeDias(primero + semana * 7 + dia)
                return indice[fecha]
                    ?? DiaDeActividad(fechaISO: fecha, sesiones: 0, golpes: 0, minutos: 0)
            }
        }

        let enOrden = cuadricula.flatMap { $0 }.filter {
            (Fechas.diasDesdeEpoca($0.fechaISO) ?? 0) <= hasta
        }
        let jugados = enOrden.filter(\.jugado).count

        // La racha en curso se cuenta hacia atrás desde hoy, y se le perdona el día de
        // hoy: a las nueve de la mañana nadie ha jugado todavía, y romperle la racha a
        // alguien por eso sería castigarle por madrugar.
        var racha = 0
        var desde = enOrden.count - 1
        if desde >= 0, !enOrden[desde].jugado { desde -= 1 }
        while desde >= 0, enOrden[desde].jugado {
            racha += 1
            desde -= 1
        }

        var mejor = 0
        var seguidos = 0
        for dia in enOrden {
            if dia.jugado {
                seguidos += 1
                if seguidos > mejor { mejor = seguidos }
            } else {
                seguidos = 0
            }
        }

        return CalendarioDeActividad(
            semanas: cuadricula,
            maxGolpes: enOrden.map(\.golpes).max() ?? 0,
            diasJugados: jugados,
            rachaActual: racha,
            mejorRacha: mejor
        )
    }

    /// Agrupa sesiones por día en el huso del dispositivo. El puente entre el historial y
    /// la cuadrícula, que el core no puede cruzar solo porque no sabe dónde estás.
    public static func porDia(
        _ sesiones: [PadelSession], calendario: Calendar = .current
    ) -> [DiaDeActividad] {
        var acumulado: [String: (Int, Int, Int)] = [:]
        for sesion in sesiones {
            let fecha = Date(timeIntervalSince1970: Double(sesion.startedAtEpochMs) / 1000)
            let clave = Fechas.isoLocal(fecha, calendario: calendario)
            let previo = acumulado[clave] ?? (0, 0, 0)
            acumulado[clave] = (
                previo.0 + 1,
                previo.1 + sesion.totalShots,
                previo.2 + Int(sesion.durationSeconds / 60)
            )
        }
        return acumulado.map {
            DiaDeActividad(fechaISO: $0.key, sesiones: $0.value.0, golpes: $0.value.1, minutos: $0.value.2)
        }
    }
}
