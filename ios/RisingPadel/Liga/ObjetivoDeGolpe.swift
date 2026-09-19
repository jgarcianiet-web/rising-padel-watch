import Foundation

/// Un objetivo técnico de la temporada: **"Bandeja 2,6 → 3,5"**.
///
/// Es distinto de los objetivos de partido que ya existían ("hacer 15 bandejas"), y los
/// dos hacen falta. El de partido es una tarea para hoy y se mide contando golpes; este
/// es una meta de nivel para la temporada entera y se mide con la nota del golpe, que es
/// la unidad en la que el jugador piensa su progreso.
///
/// El golpe se guarda por **nombre** y no como enum, igual que en `LigaGolpeSesion`: es
/// lo que hace que una copia de seguridad de la app Expo entre aquí sin transformar, y
/// lo que permite que un objetivo sobre un golpe que hoy no existe (una chiquita, una
/// salida de pared) se guarde y espere sin romper nada.
///
/// Espejo de `ObjetivoDeGolpe` en el core Kotlin, con los tests allí. Vive en el
/// target de la app y no en PadelCore porque los modelos de la liga en Swift viven
/// aquí — la liga es de la app de iPhone, el reloj no la conoce.
struct ObjetivoDeGolpe: Codable, Equatable, Hashable, Sendable {
    /// El nombre del golpe, tal como lo escribe `GolpeVisible`.
    var golpe: String
    /// La nota de partida, la que tenía el jugador cuando se fijó el objetivo.
    var notaInicial: Double
    var notaObjetivo: Double

    init(golpe: String, notaInicial: Double, notaObjetivo: Double) {
        self.golpe = golpe
        self.notaInicial = notaInicial
        self.notaObjetivo = notaObjetivo
    }
}

/// Un objetivo de golpe con lo que ha pasado desde que se fijó.
struct ProgresoDeObjetivo: Equatable, Sendable {
    let objetivo: ObjetivoDeGolpe
    /// Media de las últimas `ProgresoDeGolpes.ventana` veces que se midió ese golpe, o
    /// nil si no se ha vuelto a medir desde que se fijó el objetivo.
    let notaActual: Double?
    /// Las notas recientes, de la más vieja a la más nueva.
    let ultimas: [Double]
    /// Cuánto del camino está hecho, de 0 a 1.
    let fraccion: Double
    /// Cuántas décimas se ha subido desde el inicio. Puede ser negativo.
    let avance: Double

    var cumplido: Bool {
        guard let notaActual else { return false }
        return notaActual >= objetivo.notaObjetivo
    }

    /// El porcentaje que ve el jugador. **Redondeado, no truncado**: con truncamiento,
    /// ir justo por la mitad de camino (2,6 → 3,05 con meta en 3,5) salía "49 %" porque
    /// la resta en coma flotante da 0,4999999 en vez de 0,5.
    var porcentaje: Int { Int((fraccion * 100).rounded()) }
}

/// Mide los objetivos técnicos de una temporada contra los partidos jugados.
///
/// **La nota actual es la media de los últimos cinco partidos, no la del último.** Un
/// partido suelto se mueve mucho —hay días— y un objetivo que sube y baja medio punto
/// entre dos sábados no dice nada útil.
///
/// **Los partidos que no traen ese golpe no cuentan.** Si en tres partidos seguidos no
/// diste ni una bandeja, tu bandeja no ha empeorado: no hay dato. Rellenar ese hueco con
/// un cero sería inventarse una regresión.
enum ProgresoDeGolpes {

    /// Cuántos partidos entran en la media de "cómo estás ahora".
    static let ventana = 5

    /// La ventana larga, para comparar contra la tendencia de fondo.
    static let ventanaLarga = 20

    /// El progreso de un objetivo. Los partidos pueden venir en cualquier orden.
    static func progreso(
        _ objetivo: ObjetivoDeGolpe,
        partidos: [LigaMatch],
        ventana: Int = ProgresoDeGolpes.ventana
    ) -> ProgresoDeObjetivo {
        let ultimas = Array(notasDe(objetivo.golpe, partidos: partidos).suffix(ventana))
        let actual = ultimas.isEmpty
            ? nil
            : ultimas.reduce(0, +) / Double(ultimas.count)

        let camino = objetivo.notaObjetivo - objetivo.notaInicial
        let fraccion: Double
        if let actual {
            // Un objetivo que no pide subir nada ya está cumplido; sin esta guardia el
            // porcentaje sería una división por cero.
            fraccion = camino <= 0
                ? 1
                : min(max((actual - objetivo.notaInicial) / camino, 0), 1)
        } else {
            fraccion = 0
        }

        return ProgresoDeObjetivo(
            objetivo: objetivo,
            notaActual: actual,
            ultimas: ultimas,
            fraccion: fraccion,
            avance: actual.map { $0 - objetivo.notaInicial } ?? 0
        )
    }

    /// El progreso de todos los objetivos de una temporada, en su orden.
    static func deTemporada(
        _ temporada: LigaTemporada,
        partidos: [LigaMatch]
    ) -> [ProgresoDeObjetivo] {
        let suyos = partidos.filter { temporada.contiene($0) }
        return temporada.objetivosDeGolpe.map { progreso($0, partidos: suyos) }
    }

    /// El objetivo en el que menos se ha avanzado: la tarjeta de "principal área de
    /// mejora" de la pantalla de inicio.
    ///
    /// Se elige por fracción de camino recorrido y no por nota más baja, y la diferencia
    /// importa: el golpe con peor nota puede ser uno que el jugador ya está subiendo a
    /// buen ritmo, y el que de verdad le bloquea es aquel en el que **no se mueve**.
    static func principalAreaDeMejora(
        _ progresos: [ProgresoDeObjetivo]
    ) -> ProgresoDeObjetivo? {
        progresos.filter { !$0.cumplido }.min { $0.fraccion < $1.fraccion }
    }

    /// Las notas de un golpe a lo largo de los partidos, de la más vieja a la más nueva.
    /// Los partidos que no midieron ese golpe no aparecen.
    static func notasDe(_ golpe: String, partidos: [LigaMatch]) -> [Double] {
        partidos
            .sorted { $0.fecha < $1.fecha }
            .compactMap { partido in
                partido.golpesSesion?
                    .first { $0.nombre.lowercased() == golpe.lowercased() }?
                    .nota
            }
    }

    /// Media de un golpe en los últimos `ultimos` partidos que lo midieron, o nil si no
    /// hay ninguno. Con esto se arman las comparativas: el último partido contra la
    /// media de 5 y contra la de 20.
    static func media(_ golpe: String, partidos: [LigaMatch], ultimos: Int) -> Double? {
        let notas = notasDe(golpe, partidos: partidos).suffix(ultimos)
        guard !notas.isEmpty else { return nil }
        return notas.reduce(0, +) / Double(notas.count)
    }
}
