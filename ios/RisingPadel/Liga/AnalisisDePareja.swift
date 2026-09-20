import Foundation

/// El análisis de pareja del §36.11: **"¿juego mejor con este?"**
///
/// Es la pregunta que la liga no sabía contestar. El panel de temporada ya enseñaba
/// victorias y derrotas por compañero (`LigaMetrics.conPareja`), pero un 60 % de
/// victorias con alguien no dice nada si no se sabe cuánto ganas con los demás: puede ser
/// que juegues mejor con él, o que con él te toquen rivales más flojos. Lo que contesta la
/// pregunta es **la diferencia** entre jugar con esa pareja y jugar con cualquier otra.
///
/// ### Lo que NO se mide, y por qué
///
/// **El rendimiento del compañero no existe aquí.** El ejemplo del documento de producto
/// pone una nota para los dos jugadores, y hoy eso es imposible: la app solo tiene lo que
/// midió **el reloj de su dueño**. Ponerle una nota al compañero sería inventarla a partir
/// del resultado del partido, que es justo lo que este repo no hace. El documento describe
/// un futuro con dos cuentas conectadas; el hueco está preparado en
/// `RendimientoConPareja.nivelMedioDelCompanero`, que hoy es siempre nil y lo seguirá
/// siendo hasta que exista ese emparejamiento de cuentas.
///
/// **El lado del compañero tampoco.** Del ejemplo del documento ("el lado derecho genera
/// más ataque, el izquierdo asume la defensa") aquí solo sale la mitad que se puede medir:
/// el reparto de TUS golpes según con quién juegas, en `RepartoDeGolpe`. Si con él das más
/// bandejas y menos globos, eso sí está medido, porque son golpes tuyos. Lo que hace él al
/// otro lado de la pista no lo ha visto nadie.
///
/// ### El mínimo de partidos
///
/// Cinco, `AnalisisDeParejas.minimoPartidos`. Por debajo, un partido solo mueve el
/// porcentaje de victorias más de veinte puntos: con tres partidos, ganar uno más pasa de
/// 33 % a 66 % y el veredicto "juegas mejor con él" cambia con un sábado. Cinco es además
/// la ventana con la que ya se mide el nivel de un golpe (`ProgresoDeGolpes.ventana`), por
/// el mismo motivo — un partido suelto se mueve mucho, hay días.
///
/// El mínimo se aplica **a los partidos que traen el dato, no al total**. Cinco partidos
/// juntos de los que solo dos midieron nivel dan una media de dos partidos, no de cinco.
///
/// Espejo de `AnalisisDePareja` en el core Kotlin, con los tests allí. Vive en el target
/// de la app y no en PadelCore porque los modelos de la liga en Swift viven aquí — la liga
/// es de la app de iPhone, el reloj no la conoce.
struct AnalisisDePareja {
    /// La grafía del compañero tal como se pidió el análisis.
    let companero: String
    let juntos: RendimientoConPareja
    /// Con esa pareja contra con cualquier otra. Nil cuando no hay con qué comparar:
    /// hace falta el mínimo de partidos **a los dos lados**. Comparar contra tres
    /// partidos con otros es comparar contra nada.
    let comparacion: ComparacionDePareja?
    /// Qué golpes das más con esa pareja que con el resto. Vacío sin muestra.
    let reparto: [RepartoDeGolpe]
    let posicion: EquilibrioDePosicion
    /// El mínimo con el que se calculó, para que la vista pueda decir cuánto falta.
    let minimo: Int

    /// ¿Hay partidos suficientes para decir algo de esta pareja?
    var suficiente: Bool { juntos.partidos >= minimo }

    /// Cuántos partidos faltan para poder analizarla. 0 si ya llega.
    var partidosQueFaltan: Int { max(0, minimo - juntos.partidos) }
}

/// Lo que rindes en un conjunto de partidos: **lo tuyo**, que es lo único que el reloj
/// midió.
///
/// Los recuentos (`partidos`, `victorias`…) van siempre: son hechos, no estimaciones, y
/// decirle a alguien "solo lleváis 3 partidos juntos" es precisamente lo honesto. Lo que
/// se calla por debajo del mínimo son los números derivados — el porcentaje y la media —,
/// que son los que aparentan una precisión que no tienen.
struct RendimientoConPareja {
    let partidos: Int
    /// Partidos con resultado anotado. Un entreno guardado sin marcador no cuenta como
    /// derrota: metido en el denominador, entrenar bajaría tu porcentaje de victorias.
    let conResultado: Int
    let victorias: Int
    let derrotas: Int
    /// Partidos en los que el reloj llegó a medir nivel de sesión.
    let conNivel: Int
    /// % de victorias sobre `conResultado`. Nil si no llega al mínimo.
    let pctVictorias: Int?
    /// Tu nivel medio de sesión en esos partidos. Nil si no llega al mínimo.
    ///
    /// Es el nivel que mide el reloj (`LigaMetrics.nivelDeSesion`) y **no** el nivel
    /// Playtomic del partido. La diferencia decide el análisis entero: el Playtomic es
    /// acumulativo y apenas se mueve, así que comparar dos compañeros con él compararía
    /// las fechas en las que jugaste con cada uno —quien te tocó en junio "sale mejor"
    /// que quien te tocó en enero— en vez de cómo jugaste tú.
    let nivelMedio: Double?
    /// El nivel medio del compañero: **hoy siempre nil, y a propósito**.
    ///
    /// La app solo tiene los datos del reloj de su dueño. Hasta que existan dos cuentas
    /// conectadas (el futuro que describe el §36.11), esto no se puede medir, y una nota
    /// deducida del resultado del partido sería un número inventado con aspecto de dato.
    /// El hueco queda aquí para que el día que llegue el emparejamiento se rellene sin
    /// mover nada más.
    let nivelMedioDelCompanero: Double?

    init(
        partidos: Int,
        conResultado: Int,
        victorias: Int,
        derrotas: Int,
        conNivel: Int,
        pctVictorias: Int?,
        nivelMedio: Double?,
        nivelMedioDelCompanero: Double? = nil
    ) {
        self.partidos = partidos
        self.conResultado = conResultado
        self.victorias = victorias
        self.derrotas = derrotas
        self.conNivel = conNivel
        self.pctVictorias = pctVictorias
        self.nivelMedio = nivelMedio
        self.nivelMedioDelCompanero = nivelMedioDelCompanero
    }
}

/// Cómo juegas con esa pareja comparado con el resto.
enum VeredictoDePareja {
    case mejor
    case igual
    case peor
}

/// Jugar con esa pareja frente a jugar con cualquier otra.
struct ComparacionDePareja {
    let con: RendimientoConPareja
    let sin: RendimientoConPareja

    /// Cuánto sube (o baja) tu nivel medio con esa pareja. Nil si falta algún lado.
    var deltaNivel: Double? {
        guard let a = con.nivelMedio, let b = sin.nivelMedio else { return nil }
        return a - b
    }

    /// Lo mismo con el porcentaje de victorias, en puntos.
    var deltaPctVictorias: Int? {
        guard let a = con.pctVictorias, let b = sin.pctVictorias else { return nil }
        return a - b
    }

    /// El veredicto, que es lo que el jugador viene a leer. Nil cuando no se puede decir.
    ///
    /// Lo decide **el nivel y no el porcentaje de victorias**: ganar depende de quién
    /// estaba al otro lado de la red, y la app no sabe el nivel de los rivales. El nivel
    /// de sesión se mide en tu muñeca y no depende de contra quién juegues, así que es lo
    /// único que compara dos compañeros de forma justa.
    var veredicto: VeredictoDePareja? {
        guard let delta = deltaNivel else { return nil }
        // Por debajo de una décima no hay diferencia que enseñar: el nivel se guarda
        // redondeado a una décima (ver LigaMapper), así que un delta de 0,03 es ruido de
        // redondeo con pinta de hallazgo.
        if abs(delta) < AnalisisDeParejas.umbralNivel { return .igual }
        return delta > 0 ? .mejor : .peor
    }
}

/// Un golpe dentro del reparto de tu juego con esa pareja.
///
/// Se compara **cuota** (qué parte de tus golpes son de ese tipo) y no volumen bruto, y la
/// diferencia importa: si con esa pareja juegas partidos más largos, das más de todo, y un
/// "+12 bandejas" solo estaría midiendo que el partido duró más. La cuota se normaliza
/// sola y es la que enseña el papel que ocupas en la pista, que es lo que pregunta el
/// documento. El volumen por partido se da igual porque es lo que el jugador reconoce.
struct RepartoDeGolpe: Identifiable {
    let golpe: String
    /// Golpes de ese tipo por partido con esa pareja.
    let porPartidoCon: Double
    /// Qué parte de tus golpes son de ese tipo con esa pareja, de 0 a 1.
    let cuotaCon: Double
    /// La misma cuota jugando con cualquier otro. Nil si no hay base para comparar.
    let cuotaSin: Double?

    var id: String { golpe }

    /// Cuánto pesa más (o menos) ese golpe con esa pareja. Nil sin comparación.
    var diferencia: Double? { cuotaSin.map { cuotaCon - $0 } }

    /// La diferencia en puntos porcentuales, que es como se enseña.
    var diferenciaEnPuntos: Int? { diferencia.map { Int(($0 * 100).rounded()) } }
}

/// De qué lado de la pista juegas con esa pareja.
///
/// **Aviso sobre el dato**: `posicion` tiene "reves" por defecto en `LigaMatch` —lo exige
/// la compatibilidad con la copia de seguridad de la app Expo, donde el campo siempre
/// viene— así que un partido en el que nadie tocó el selector es indistinguible de uno
/// jugado de revés. Esto describe lo que hay apuntado, no afirma dónde estuviste.
struct EquilibrioDePosicion {
    let enDerecha: Int
    let enReves: Int
    /// Qué parte de los partidos juegas de derecha (drive), 0 a 1. Nil bajo el mínimo.
    let cuotaDerecha: Double?
    /// "derecha", "reves" o nil. Solo se afirma un lado fijo cuando cuatro de cada cinco
    /// partidos caen del mismo (`AnalisisDeParejas.umbralLado`); con un 60/40 el sitio os
    /// lo vais repartiendo y decir "juegas de revés" sería redondear una costumbre que no
    /// existe.
    let ladoHabitual: String?

    var partidos: Int { enDerecha + enReves }
}

/// Un compañero con lo que rindes a su lado: el mejor y el peor del ranking.
struct CompaneroDestacado: Identifiable {
    let nombre: String
    let rendimiento: RendimientoConPareja

    var id: String { nombre }
}

/// El motor del análisis de pareja. Funciones puras: entran partidos, sale el análisis.
enum AnalisisDeParejas {

    /// Partidos mínimos para que un número derivado se pueda enseñar. Ver la cabecera.
    static let minimoPartidos = 5

    /// Por debajo de una décima, el nivel no ha cambiado: se guarda con una decimal.
    static let umbralNivel = 0.1

    /// Cuatro de cada cinco partidos del mismo lado para llamarlo tu lado.
    static let umbralLado = 0.8

    /// La posición de drive, tal como la guarda el formulario de partido.
    static let derecha = "derecha"
    static let reves = "reves"

    /// El análisis completo de una pareja.
    ///
    /// - Parameters:
    ///   - companero: el nombre, con la grafía que sea: se compara sin mayúsculas.
    ///   - partidos: todos los partidos de los que se quiere sacar la comparación —
    ///     normalmente los de la temporada en curso. Se reparten aquí en "con él" y "con
    ///     cualquier otro".
    static func de(
        _ companero: String,
        partidos: [LigaMatch],
        minimo: Int = AnalisisDeParejas.minimoPartidos
    ) -> AnalisisDePareja {
        let con = partidos.filter { juegaCon($0, companero) }
        // "Con cualquier otro" son los partidos con OTRO compañero apuntado, no todos los
        // demás. Un partido sin compañero escrito no es un partido con otra persona: es un
        // partido del que no se sabe con quién fue, y bien pudo ser con él. Meterlo en la
        // base de comparación sería decidir por el jugador.
        let sin = partidos.filter {
            !$0.companero.trimmingCharacters(in: .whitespaces).isEmpty && !juegaCon($0, companero)
        }

        let rendimientoCon = rendimiento(con, minimo: minimo)
        let rendimientoSin = rendimiento(sin, minimo: minimo)

        return AnalisisDePareja(
            companero: companero.trimmingCharacters(in: .whitespaces),
            juntos: rendimientoCon,
            comparacion: con.count >= minimo && sin.count >= minimo
                ? ComparacionDePareja(con: rendimientoCon, sin: rendimientoSin)
                : nil,
            reparto: reparto(con: con, sin: sin, minimo: minimo),
            posicion: equilibrio(con, minimo: minimo),
            minimo: minimo
        )
    }

    /// Los compañeros con los que has jugado, el que más veces primero. La lista del
    /// selector de la pantalla. Sin filtro de mínimo: esconder a alguien del selector
    /// haría imposible ver cuántos partidos os faltan para poder analizarlo.
    static func companeros(_ partidos: [LigaMatch]) -> [String] {
        LigaMetrics.conPareja(partidos).map(\.nombre)
    }

    /// Los compañeros ordenados por cómo juegas tú a su lado, el mejor primero.
    ///
    /// Ordena por **nivel medio de sesión** y deja fuera a quien no llegue al mínimo de
    /// partidos o a quien no tenga nivel medido: ver `ComparacionDePareja.veredicto` sobre
    /// por qué el porcentaje de victorias no sirve para comparar compañeros entre sí. Sin
    /// niveles el ranking no existe, y caer al porcentaje de victorias cambiaría
    /// calladamente lo que significa "el mejor compañero".
    static func ranking(
        _ partidos: [LigaMatch],
        minimo: Int = AnalisisDeParejas.minimoPartidos
    ) -> [CompaneroDestacado] {
        companeros(partidos)
            .map { nombre in
                CompaneroDestacado(
                    nombre: nombre,
                    rendimiento: rendimiento(partidos.filter { juegaCon($0, nombre) }, minimo: minimo)
                )
            }
            .filter { $0.rendimiento.partidos >= minimo && $0.rendimiento.nivelMedio != nil }
            .sorted { a, b in
                let na = a.rendimiento.nivelMedio ?? 0
                let nb = b.rendimiento.nivelMedio ?? 0
                if na != nb { return na > nb }
                return a.nombre < b.nombre
            }
    }

    /// El compañero con el que mejor juegas. Nil si nadie llega al mínimo.
    static func mejorCompanero(
        _ partidos: [LigaMatch],
        minimo: Int = AnalisisDeParejas.minimoPartidos
    ) -> CompaneroDestacado? {
        ranking(partidos, minimo: minimo).first
    }

    /// El compañero con el que peor juegas.
    ///
    /// Nil si solo hay un compañero con muestra: el único que tienes no es "el peor" de
    /// nada, y enseñarlo a la vez como mejor y como peor es una tontería que además suena
    /// a reproche hacia una persona real.
    static func peorCompanero(
        _ partidos: [LigaMatch],
        minimo: Int = AnalisisDeParejas.minimoPartidos
    ) -> CompaneroDestacado? {
        let lista = ranking(partidos, minimo: minimo)
        return lista.count >= 2 ? lista.last : nil
    }

    /// true si ese partido se jugó con esa persona. `companero` es texto libre.
    static func juegaCon(_ match: LigaMatch, _ companero: String) -> Bool {
        let buscado = companero.trimmingCharacters(in: .whitespaces)
        guard !buscado.isEmpty else { return false }
        return LigaMetrics.partirNombres(match.companero)
            .contains { $0.lowercased() == buscado.lowercased() }
    }

    /// El rendimiento tuyo en un conjunto de partidos. Ver `RendimientoConPareja`.
    static func rendimiento(
        _ partidos: [LigaMatch],
        minimo: Int = AnalisisDeParejas.minimoPartidos
    ) -> RendimientoConPareja {
        let conResultado = partidos.filter { ResultadoDePartido.cuenta($0.resultado) }
        let victorias = conResultado.filter { $0.resultado == "victoria" }.count
        let derrotas = conResultado.filter { $0.resultado == "derrota" }.count
        let niveles = partidos.compactMap(LigaMetrics.nivelDeSesion)

        return RendimientoConPareja(
            partidos: partidos.count,
            conResultado: conResultado.count,
            victorias: victorias,
            derrotas: derrotas,
            conNivel: niveles.count,
            // El mínimo se mide sobre los partidos que traen el dato, no sobre el total:
            // cinco partidos de los que dos midieron nivel son una media de dos.
            pctVictorias: conResultado.count >= minimo
                ? Int((Double(victorias) * 100 / Double(conResultado.count)).rounded())
                : nil,
            nivelMedio: niveles.count >= minimo
                ? niveles.reduce(0, +) / Double(niveles.count)
                : nil
        )
    }

    /// El reparto de golpes con esa pareja frente al resto.
    ///
    /// **Un partido sin `golpesVolumen` no entra**: no es un partido de cero golpes, es un
    /// partido que no se midió (se apuntó a mano, o el reloj no estaba). Dentro de un
    /// partido que sí trae volumen, en cambio, un golpe que no aparece **sí** es un cero
    /// de verdad: el reloj estuvo puesto y no vio ninguno.
    ///
    /// Lista vacía si no hay partidos medidos suficientes con esa pareja. La cuota de
    /// comparación es nil si los que no son con ella tampoco llegan.
    static func reparto(
        con: [LigaMatch],
        sin: [LigaMatch],
        minimo: Int = AnalisisDeParejas.minimoPartidos
    ) -> [RepartoDeGolpe] {
        let medidosCon = con.filter { !($0.golpesVolumen ?? []).isEmpty }
        guard medidosCon.count >= minimo else { return [] }
        let medidosSin = sin.filter { !($0.golpesVolumen ?? []).isEmpty }

        let sumasCon = sumaPorGolpe(medidosCon)
        let totalCon = sumasCon.porClave.values.reduce(0, +)
        guard totalCon > 0 else { return [] }

        let sumasSin = sumaPorGolpe(medidosSin)
        let totalSin = sumasSin.porClave.values.reduce(0, +)
        let haySin = medidosSin.count >= minimo && totalSin > 0

        return sumasCon.orden
            .map { clave in
                let cantidad = sumasCon.porClave[clave] ?? 0
                return RepartoDeGolpe(
                    golpe: sumasCon.grafias[clave] ?? clave,
                    porPartidoCon: Double(cantidad) / Double(medidosCon.count),
                    cuotaCon: Double(cantidad) / Double(totalCon),
                    // Un golpe que nunca das con los demás es una cuota de 0 legítima:
                    // esos partidos sí se midieron. Distinto de no tener base, que es el
                    // nil de arriba.
                    cuotaSin: haySin
                        ? Double(sumasSin.porClave[clave] ?? 0) / Double(totalSin)
                        : nil
                )
            }
            // Primero lo que más destaca con esa pareja, que es lo que se viene a leer.
            // Los golpes sin comparación caen al final: no se han ganado un titular.
            .sorted { a, b in
                let da = a.diferencia ?? -Double.infinity
                let db = b.diferencia ?? -Double.infinity
                if da != db { return da > db }
                if a.cuotaCon != b.cuotaCon { return a.cuotaCon > b.cuotaCon }
                return a.golpe < b.golpe
            }
    }

    /// De qué lado juegas con esa pareja. Ver el aviso de `EquilibrioDePosicion`.
    static func equilibrio(
        _ con: [LigaMatch],
        minimo: Int = AnalisisDeParejas.minimoPartidos
    ) -> EquilibrioDePosicion {
        let enDerecha = con.filter { $0.posicion == derecha }.count
        let enReves = con.filter { $0.posicion == reves }.count
        let total = enDerecha + enReves
        guard total >= minimo else {
            return EquilibrioDePosicion(
                enDerecha: enDerecha, enReves: enReves, cuotaDerecha: nil, ladoHabitual: nil
            )
        }
        let cuota = Double(enDerecha) / Double(total)
        let lado: String?
        if cuota >= umbralLado {
            lado = derecha
        } else if cuota <= 1 - umbralLado {
            lado = reves
        } else {
            lado = nil
        }
        return EquilibrioDePosicion(
            enDerecha: enDerecha, enReves: enReves, cuotaDerecha: cuota, ladoHabitual: lado
        )
    }

    /// Golpes sumados por clave en minúsculas, con la grafía de la primera vez aparte.
    ///
    /// Las dos cosas hacen falta: la clave es la que cruza los dos conjuntos (los partidos
    /// importados traen los nombres como los escribió quien los metió a mano, y un
    /// "Bandeja" con esa pareja y un "bandeja" con el resto tienen que cruzarse o la cuota
    /// de comparación saldría cero); la grafía es la que se le enseña al jugador.
    private struct SumaDeGolpes {
        var porClave: [String: Int] = [:]
        var grafias: [String: String] = [:]
        /// Las claves en el orden en que aparecieron: los diccionarios de Swift no lo
        /// conservan y el orden final tiene que ser el mismo que en el core Kotlin.
        var orden: [String] = []
    }

    private static func sumaPorGolpe(_ partidos: [LigaMatch]) -> SumaDeGolpes {
        var suma = SumaDeGolpes()
        for partido in partidos {
            for golpe in partido.golpesVolumen ?? [] where golpe.cantidad > 0 {
                let clave = golpe.nombre.lowercased()
                if suma.grafias[clave] == nil {
                    suma.grafias[clave] = golpe.nombre
                    suma.orden.append(clave)
                }
                suma.porClave[clave, default: 0] += golpe.cantidad
            }
        }
        return suma
    }
}
