import Foundation

/// Lo que sabemos del acierto del reloj en **un** tipo de golpe.
///
/// Junta las dos únicas fuentes de verdad que existen, y las mantiene separadas porque no
/// valen lo mismo:
///
/// - **Las tandas etiquetadas** son verdad-terreno perfecta: alguien dijo "esto van a ser
///   treinta bandejas" *antes* de pegar, así que se sabe golpe a golpe si acertó y con qué
///   se confundió. Es el dato bueno.
/// - **Las revisiones de partido** son recuentos: el jugador dijo "fueron 12 bandejas, no
///   14". No dicen *cuál* falló, solo cuántos de más o de menos contó el reloj. Es un dato
///   más pobre, pero es el único que sale de jugar de verdad.
///
/// Mezclarlas en un solo porcentaje daría un número más gordo y más falso. Aquí conviven.
/// Espejo del core Kotlin, con tests allí.
public struct PrecisionDeGolpe: Equatable, Sendable, Identifiable {
    public let type: ShotType
    /// Golpes de este tipo en tandas etiquetadas.
    public let enTandas: Int
    /// De esos, cuántos clasificó bien.
    public let acertadosEnTandas: Int
    /// El tipo con el que más se lo confunde. Nil si no falla nunca.
    public let seConfundeCon: ShotType?
    public let vecesConfundido: Int
    /// Golpes de este tipo que contó el reloj en partidos revisados.
    public let contadosEnPartidos: Int
    /// Los que dijo el jugador que fueron de verdad.
    public let realesEnPartidos: Int

    public var id: ShotType { type }

    /// Con menos de esto, el porcentaje es una anécdota y no se debe presumir de él.
    public static let minTandasParaJuzgar = 15

    public init(
        type: ShotType,
        enTandas: Int,
        acertadosEnTandas: Int,
        seConfundeCon: ShotType?,
        vecesConfundido: Int,
        contadosEnPartidos: Int,
        realesEnPartidos: Int
    ) {
        self.type = type
        self.enTandas = enTandas
        self.acertadosEnTandas = acertadosEnTandas
        self.seConfundeCon = seConfundeCon
        self.vecesConfundido = vecesConfundido
        self.contadosEnPartidos = contadosEnPartidos
        self.realesEnPartidos = realesEnPartidos
    }

    /// 0 a 1 sobre tandas. Nil sin tandas de este golpe: no se inventa un cero.
    public var aciertoEnTandas: Float? {
        enTandas == 0 ? nil : Float(acertadosEnTandas) / Float(enTandas)
    }

    /// Cuánto se pasa o se queda corto el reloj contando este golpe en partido.
    /// +0,25 = cuenta un 25% de más. Nil si el jugador nunca corrigió este tipo.
    ///
    /// Es distinto del acierto: un reloj puede contar exactamente 12 bandejas y que sean
    /// doce bandejas *distintas* de las que fueron. El desvío no lo detecta y por eso no
    /// sustituye a las tandas — pero un desvío grande sí es prueba de que algo va mal.
    public var desvioEnPartidos: Float? {
        realesEnPartidos == 0 ? nil
            : Float(contadosEnPartidos - realesEnPartidos) / Float(realesEnPartidos)
    }

    /// Lo que hay que grabar. Un golpe sin tandas no se puede ni juzgar ni arreglar.
    public var faltanTandas: Bool { enTandas < Self.minTandasParaJuzgar }
}

/// El informe de precisión del detector: la única pregunta que decide si esta app vale.
///
/// Todo lo demás —el nivel, la liga, las gráficas, la comunidad— se apoya en que el reloj
/// acierte al decir qué golpe fue. Ese número existía ya, pero repartido: dentro de cada
/// sesión revisada y dentro de cada tanda. Suelto no cambia ninguna decisión; junto dice
/// exactamente qué golpe está roto y qué tanda toca grabar el sábado.
public struct InformeDePrecision: Equatable, Sendable {
    public let golpes: [PrecisionDeGolpe]
    /// Cuántas sesiones ha revisado el jugador. Sin revisiones, esa mitad está vacía.
    public let sesionesRevisadas: Int
    public let golpesEnTandas: Int
    /// Acierto global sobre tandas, 0 a 1. Nil sin tandas.
    public let aciertoGlobal: Float?
    /// Fracción de golpes de tanda que el reloj dejó sin clasificar. Se cuenta aparte del
    /// acierto porque no es lo mismo equivocarse que rendirse: un "sin clasificar" no
    /// ensucia las estadísticas del jugador, solo le quita un golpe.
    public let sinClasificar: Float?

    public var hayDatos: Bool { golpesEnTandas > 0 || sesionesRevisadas > 0 }

    /// El golpe que peor va, de los que tienen tandas suficientes para juzgarlos. Es la
    /// respuesta a "¿y ahora qué arreglo?".
    public var peorGolpe: PrecisionDeGolpe? {
        golpes
            .filter { !$0.faltanTandas && $0.aciertoEnTandas != nil }
            .min { ($0.aciertoEnTandas ?? 2) < ($1.aciertoEnTandas ?? 2) }
    }

    /// Los golpes de los que no hay tandas suficientes: lo que hay que ir a grabar.
    public var golpesSinTandas: [ShotType] {
        ShotType.allCases
            .filter { $0 != .unknown }
            .filter { tipo in golpes.first { $0.type == tipo }?.faltanTandas ?? true }
    }

    /// Construye el informe.
    ///
    /// - Parameters:
    ///   - sesiones: el historial; solo cuentan las que el jugador haya revisado.
    ///   - tandas: pares (lo que era, lo que dijo el reloj) sacados de las muestras
    ///     etiquetadas volviendo a pasar el clasificador por sus rasgos. Se pide ya
    ///     emparejado y no en crudo para que el core no dependa de dónde vive el fichero.
    public static func de(
        sesiones: [PadelSession],
        tandas: [(ShotType, ShotType)]
    ) -> InformeDePrecision {
        let revisadas = sesiones.filter { $0.review != nil }

        // --- tandas: verdad-terreno golpe a golpe ---
        let porReal = Dictionary(grouping: tandas, by: { $0.0 })
        var aciertos = 0
        var desconocidos = 0
        for (real, dicho) in tandas {
            if dicho == real { aciertos += 1 }
            if dicho == .unknown { desconocidos += 1 }
        }

        // --- revisiones: recuentos de partido ---
        var contados: [ShotType: Int] = [:]
        var reales: [ShotType: Int] = [:]
        for sesion in revisadas {
            for (tipo, n) in sesion.shotsByType { contados[tipo, default: 0] += n }
            for (tipo, n) in sesion.effectiveShotsByType { reales[tipo, default: 0] += n }
        }

        let tipos = Set(porReal.keys).union(contados.keys).union(reales.keys)
            .filter { $0 != .unknown }

        let golpes = tipos.map { tipo -> PrecisionDeGolpe in
            let delTipo = porReal[tipo] ?? []
            // La confusión más repetida, ignorando los aciertos y los "no lo sé": que un
            // golpe se escape sin clasificar es otro problema, y mezclarlo taparía con
            // quién se está confundiendo de verdad.
            var fallos: [ShotType: Int] = [:]
            for (_, dicho) in delTipo where dicho != tipo && dicho != .unknown {
                fallos[dicho, default: 0] += 1
            }
            let peor = fallos.max { a, b in
                a.value != b.value
                    ? a.value < b.value
                    // Empate: manda el orden del enum, para que el informe no baile.
                    : (ShotType.allCases.firstIndex(of: a.key) ?? 0)
                        > (ShotType.allCases.firstIndex(of: b.key) ?? 0)
            }
            return PrecisionDeGolpe(
                type: tipo,
                enTandas: delTipo.count,
                acertadosEnTandas: delTipo.filter { $0.1 == tipo }.count,
                seConfundeCon: peor?.key,
                vecesConfundido: peor?.value ?? 0,
                contadosEnPartidos: contados[tipo] ?? 0,
                realesEnPartidos: reales[tipo] ?? 0
            )
        }
        // Primero lo que peor va y se puede juzgar; después lo que no tiene tandas
        // suficientes; dentro de cada grupo, por golpes medidos.
        .sorted { a, b in
            if a.faltanTandas != b.faltanTandas { return !a.faltanTandas }
            let ga = a.aciertoEnTandas ?? 2
            let gb = b.aciertoEnTandas ?? 2
            if ga != gb { return ga < gb }
            return (a.enTandas + a.realesEnPartidos) > (b.enTandas + b.realesEnPartidos)
        }

        return InformeDePrecision(
            golpes: golpes,
            sesionesRevisadas: revisadas.count,
            golpesEnTandas: tandas.count,
            aciertoGlobal: tandas.isEmpty ? nil : Float(aciertos) / Float(tandas.count),
            sinClasificar: tandas.isEmpty ? nil : Float(desconocidos) / Float(tandas.count)
        )
    }

    public init(
        golpes: [PrecisionDeGolpe],
        sesionesRevisadas: Int,
        golpesEnTandas: Int,
        aciertoGlobal: Float?,
        sinClasificar: Float?
    ) {
        self.golpes = golpes
        self.sesionesRevisadas = sesionesRevisadas
        self.golpesEnTandas = golpesEnTandas
        self.aciertoGlobal = aciertoGlobal
        self.sinClasificar = sinClasificar
    }
}
