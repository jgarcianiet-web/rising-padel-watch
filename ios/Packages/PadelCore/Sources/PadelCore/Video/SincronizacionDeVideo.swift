import Foundation

/// Casar los golpes que se ven en un vídeo con los que midió el reloj.
///
/// ## Para qué sirve, y por qué es el cuello de botella de todo lo demás
///
/// El Video Lab marca golpes a mano, y marcar a mano es carísimo: un partido son
/// trescientos golpes y nadie etiqueta trescientas cosas dos sábados seguidos. Pero si el
/// jugador llevaba el reloj mientras se grababa el vídeo, **el reloj ya sabe qué golpe fue
/// cada uno y en qué milisegundo**. Cruzar las dos listas convierte una tarde de
/// etiquetado manual en un botón.
///
/// Eso abre las dos cosas que el laboratorio existe para hacer:
///
/// 1. **Medir el detector de verdad.** Los pares dicen en qué acertó; las marcas sin par
///    dicen qué golpes se le escaparon al reloj, y los golpes del reloj sin par, qué se
///    inventó.
/// 2. **Entrenar la detección por visión.** Cada par es un ejemplo etiquetado: esta
///    postura, este golpe. Sin este emparejador no hay corpus, y sin corpus no hay modelo.
///
/// ## El problema real: los dos relojes no marcan la misma hora
///
/// El vídeo trae la hora del iPhone que grabó, con resolución de segundo. Los golpes traen
/// la del Apple Watch. Entre los dos hay un desfase de uno o dos segundos con toda
/// naturalidad — y dos golpes seguidos de una tanda van a segundo y medio, así que un
/// desfase de dos segundos no desordena un poco: empareja cada golpe con el anterior y da
/// un informe limpio y completamente falso. **Un emparejamiento mal alineado es peor que
/// ninguno**, porque parece correcto. Por eso cada par guarda su `restoMs`: restos todos
/// pegados al borde de la ventana es la señal de que está corrido.
///
/// Espejo de `SincronizacionDeVideo` en el core Kotlin, con los tests allí.
public enum SincronizacionDeVideo {

    /// Cuánto se admite entre un golpe visto y el mismo golpe medido, una vez alineados.
    ///
    /// 300 ms y no más: el detector del reloj tiene 320 ms de tiempo muerto tras cada
    /// impacto, así que con una ventana más ancha un golpe del vídeo podría caer a tiro de
    /// dos golpes del reloj y la elección dejaría de estar determinada por los datos.
    public static let ventanaMs: Int64 = 300

    /// Hasta dónde se busca el desfase automático. Más de seis segundos ya no es desfase
    /// de relojes, es que el vídeo y la sesión no son del mismo partido.
    public static let rangoAutomaticoMs: Int64 = 6_000

    /// Paso de la búsqueda. 50 ms es bastante más fino que la ventana.
    public static let pasoAutomaticoMs: Int64 = 50

    /// Un golpe situado en tiempo de reloj de pared, venga del vídeo o de la muñeca.
    public struct GolpeEnTiempo: Equatable, Sendable {
        public let epochMs: Int64
        /// Nil en una marca de vídeo que todavía no tiene tipo puesto.
        public let tipo: ShotType?

        public init(epochMs: Int64, tipo: ShotType? = nil) {
            self.epochMs = epochMs
            self.tipo = tipo
        }
    }

    /// Un golpe del vídeo casado con uno del reloj, por sus posiciones en cada lista.
    public struct Par: Equatable, Sendable {
        public let indiceVideo: Int
        public let indiceReloj: Int
        /// Lo que quedó sin cuadrar entre los dos, ya alineados. Con signo.
        public let restoMs: Int64

        public init(indiceVideo: Int, indiceReloj: Int, restoMs: Int64) {
            self.indiceVideo = indiceVideo
            self.indiceReloj = indiceReloj
            self.restoMs = restoMs
        }
    }

    /// El resultado de cruzar las dos listas.
    ///
    /// Las tres listas juntas cuentan la historia entera, y por eso no se devuelven solo
    /// los pares: `soloEnVideo` son golpes que se vieron y el reloj no midió, y
    /// `soloEnReloj` son golpes que el reloj midió y no se ven. Quedarse con los pares
    /// sería quedarse con la parte en la que el detector acierta.
    public struct Cruce: Equatable, Sendable {
        public let pares: [Par]
        public let soloEnVideo: [Int]
        public let soloEnReloj: [Int]
        public let desfaseMs: Int64
        public let escala: Double

        /// Qué fracción de lo que se ve en el vídeo encontró su golpe en el reloj.
        public var cobertura: Double {
            let total = pares.count + soloEnVideo.count
            return total == 0 ? 0 : Double(pares.count) / Double(total)
        }

        /// El resto típico de los pares, en valor absoluto. **Es la cifra que dice si el
        /// alineamiento es bueno**: con restos de decenas de ms cuadra de verdad; con
        /// restos pegados a la ventana está corrido un golpe y no hay que creérselo.
        public var restoMedianoMs: Int64? {
            guard !pares.isEmpty else { return nil }
            let restos = pares.map { abs($0.restoMs) }.sorted()
            return restos[restos.count / 2]
        }

        /// De los pares emparejados, en cuántos coincidió el tipo de golpe.
        ///
        /// Nil si ningún par tiene tipo en los dos lados: sin tipos no se puede hablar de
        /// acierto, y un 0 % diría que falla todo cuando lo que pasa es que no se sabe.
        public func aciertoDeTipo(
            video: [GolpeEnTiempo], reloj: [GolpeEnTiempo]
        ) -> Double? {
            let comparables = pares.filter {
                video[$0.indiceVideo].tipo != nil && reloj[$0.indiceReloj].tipo != nil
            }
            guard !comparables.isEmpty else { return nil }
            let iguales = comparables.filter {
                video[$0.indiceVideo].tipo == reloj[$0.indiceReloj].tipo
            }.count
            return Double(iguales) / Double(comparables.count)
        }
    }

    /// Desfase a partir de **una** claqueta: el mismo golpe señalado en los dos lados.
    ///
    /// Positivo significa que el reloj va por delante del vídeo.
    public static func desfaseConUnaAncla(marcaEpochMs: Int64, golpeEpochMs: Int64) -> Int64 {
        golpeEpochMs - marcaEpochMs
    }

    /// Desfase **y escala** a partir de dos claquetas, una al principio y otra al final.
    ///
    /// La escala corrige la deriva: si entre las dos claquetas el vídeo mide 600 s y el
    /// reloj 600,4 s, los relojes no corren igual y los golpes del final se desplazan casi
    /// medio segundo — más de la ventana de emparejado.
    ///
    /// Nil si las dos claquetas están pegadas o del revés: con dos puntos juntos la escala
    /// sale de dividir por casi cero y amplifica cualquier error de señalar el fotograma.
    public static func desfaseConDosAnclas(
        marca1EpochMs: Int64,
        golpe1EpochMs: Int64,
        marca2EpochMs: Int64,
        golpe2EpochMs: Int64,
        separacionMinimaMs: Int64 = 30_000
    ) -> (desfaseMs: Int64, escala: Double)? {
        let vanoVideo = marca2EpochMs - marca1EpochMs
        let vanoReloj = golpe2EpochMs - golpe1EpochMs
        guard vanoVideo >= separacionMinimaMs, vanoReloj >= separacionMinimaMs else {
            return nil
        }
        let escala = Double(vanoReloj) / Double(vanoVideo)
        let desfase = golpe1EpochMs - Int64((Double(marca1EpochMs) * escala).rounded())
        return (desfase, escala)
    }

    /// Prueba desfases y devuelve el que empareja más golpes, con cuántos emparejó.
    ///
    /// El recuento se devuelve a propósito: es lo que permite desconfiar. Si de cuarenta
    /// marcas solo cuadran seis, el desfase "mejor" no significa nada y lo que hay que
    /// hacer es señalar una claqueta, no aceptar el número.
    public static func estimarDesfaseMs(
        video: [GolpeEnTiempo],
        reloj: [GolpeEnTiempo],
        rangoMs: Int64 = rangoAutomaticoMs,
        pasoMs: Int64 = pasoAutomaticoMs,
        ventanaMs: Int64 = ventanaMs
    ) -> (desfaseMs: Int64, emparejados: Int) {
        guard !video.isEmpty, !reloj.isEmpty else { return (0, 0) }
        let tiemposReloj = reloj.map(\.epochMs).sorted()

        var mejorDesfase: Int64 = 0
        var mejorCuenta = -1
        var mejorError = Int64.max
        var desfase = -rangoMs
        while desfase <= rangoMs {
            var cuenta = 0
            var error: Int64 = 0
            for marca in video {
                let buscado = marca.epochMs + desfase
                if let cercano = masCercano(tiemposReloj, a: buscado),
                   abs(cercano - buscado) <= ventanaMs {
                    cuenta += 1
                    error += abs(cercano - buscado)
                }
            }
            // Más pares gana; a igualdad, el que cuadra más fino. Sin el desempate por
            // error, dos desfases vecinos empatan y se queda el primero por casualidad.
            if cuenta > mejorCuenta || (cuenta == mejorCuenta && error < mejorError) {
                mejorDesfase = desfase
                mejorCuenta = cuenta
                mejorError = error
            }
            desfase += pasoMs
        }
        return (mejorDesfase, mejorCuenta)
    }

    /// El valor de la lista ordenada más cercano a `objetivo`, por búsqueda binaria.
    private static func masCercano(_ ordenados: [Int64], a objetivo: Int64) -> Int64? {
        guard !ordenados.isEmpty else { return nil }
        var bajo = 0
        var alto = ordenados.count - 1
        while bajo < alto {
            let medio = (bajo + alto) / 2
            if ordenados[medio] < objetivo { bajo = medio + 1 } else { alto = medio }
        }
        let candidato = ordenados[bajo]
        let anterior = bajo > 0 ? ordenados[bajo - 1] : nil
        if let anterior, abs(anterior - objetivo) < abs(candidato - objetivo) {
            return anterior
        }
        return candidato
    }

    /// Cruza las dos listas con un desfase y una escala dados.
    ///
    /// **El emparejamiento respeta el orden y es uno a uno**, y las dos condiciones son
    /// necesarias. Uno a uno porque un golpe del reloj no puede explicar dos del vídeo. En
    /// orden porque las dos listas son cronológicas: si la marca 5 casa con el golpe 9, la
    /// marca 6 no puede casar con el 8 — eso sería el tiempo andando hacia atrás, y es
    /// exactamente el error que comete un emparejador voraz cuando dos golpes van pegados.
    ///
    /// Con esas dos condiciones el óptimo sale de una tabla y no de ir eligiendo lo que
    /// mejor pinta en cada paso: se maximiza el número de pares y, a igualdad, se minimiza
    /// lo que queda sin cuadrar.
    public static func cruzar(
        video: [GolpeEnTiempo],
        reloj: [GolpeEnTiempo],
        desfaseMs: Int64,
        escala: Double = 1,
        ventanaMs: Int64 = ventanaMs
    ) -> Cruce {
        let ordenVideo = video.indices.sorted { video[$0].epochMs < video[$1].epochMs }
        let ordenReloj = reloj.indices.sorted { reloj[$0].epochMs < reloj[$1].epochMs }
        let n = ordenVideo.count
        let m = ordenReloj.count

        // Instantes del vídeo llevados al tiempo del reloj.
        let alineados = ordenVideo.map {
            Int64((Double(video[$0].epochMs) * escala).rounded()) + desfaseMs
        }
        let tiemposReloj = ordenReloj.map { reloj[$0].epochMs }

        // pares[i][j] = cuántos pares se pueden formar con las i primeras marcas y los j
        // primeros golpes; error[i][j] = lo que cuesta ese mejor emparejamiento.
        var pares = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        var error = [[Int64]](repeating: [Int64](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    var mejorPares = pares[i - 1][j]
                    var mejorError = error[i - 1][j]
                    if pares[i][j - 1] > mejorPares
                        || (pares[i][j - 1] == mejorPares && error[i][j - 1] < mejorError) {
                        mejorPares = pares[i][j - 1]
                        mejorError = error[i][j - 1]
                    }
                    let resto = abs(alineados[i - 1] - tiemposReloj[j - 1])
                    if resto <= ventanaMs {
                        let conPar = pares[i - 1][j - 1] + 1
                        let errorConPar = error[i - 1][j - 1] + resto
                        if conPar > mejorPares
                            || (conPar == mejorPares && errorConPar < mejorError) {
                            mejorPares = conPar
                            mejorError = errorConPar
                        }
                    }
                    pares[i][j] = mejorPares
                    error[i][j] = mejorError
                }
            }
        }

        // Se recorre la tabla hacia atrás para saber QUÉ se emparejó, no solo cuánto.
        var resultado: [Par] = []
        var i = n
        var j = m
        while i > 0, j > 0 {
            let resto = abs(alineados[i - 1] - tiemposReloj[j - 1])
            let conPar = resto <= ventanaMs ? pares[i - 1][j - 1] + 1 : -1
            let errorConPar = resto <= ventanaMs ? error[i - 1][j - 1] + resto : Int64.max
            if conPar == pares[i][j], errorConPar == error[i][j] {
                resultado.append(
                    Par(
                        indiceVideo: ordenVideo[i - 1],
                        indiceReloj: ordenReloj[j - 1],
                        restoMs: alineados[i - 1] - tiemposReloj[j - 1]
                    )
                )
                i -= 1
                j -= 1
            } else if pares[i - 1][j] == pares[i][j], error[i - 1][j] == error[i][j] {
                i -= 1
            } else {
                j -= 1
            }
        }

        let emparejadosVideo = Set(resultado.map(\.indiceVideo))
        let emparejadosReloj = Set(resultado.map(\.indiceReloj))
        return Cruce(
            pares: resultado.sorted { video[$0.indiceVideo].epochMs < video[$1.indiceVideo].epochMs },
            soloEnVideo: ordenVideo.filter { !emparejadosVideo.contains($0) },
            soloEnReloj: ordenReloj.filter { !emparejadosReloj.contains($0) },
            desfaseMs: desfaseMs,
            escala: escala
        )
    }

    /// Cruza estimando el desfase sola. Atajo para el caso cómodo.
    public static func cruzarAutomatico(
        video: [GolpeEnTiempo],
        reloj: [GolpeEnTiempo],
        ventanaMs: Int64 = ventanaMs
    ) -> Cruce {
        let (desfase, _) = estimarDesfaseMs(video: video, reloj: reloj, ventanaMs: ventanaMs)
        return cruzar(video: video, reloj: reloj, desfaseMs: desfase, ventanaMs: ventanaMs)
    }
}
