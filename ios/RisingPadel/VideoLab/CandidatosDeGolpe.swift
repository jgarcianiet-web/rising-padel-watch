import Foundation

/// Propone instantes en los que **puede** haber un golpe, para que el usuario los
/// confirme.
///
/// LA IDEA, que es deliberadamente simple: en la secuencia de posturas, un golpe se ve
/// como un pico corto y muy alto de velocidad de la muñeca. No hace falta un modelo para
/// encontrar un pico; hace falta un modelo para decir *qué* golpe es, y ese no existe (ver
/// la cabecera de `AnalisisDeVideo`).
///
/// POR QUÉ EL UMBRAL ES RELATIVO Y NO UN NÚMERO FIJO: la velocidad se mide en fracciones
/// de imagen por segundo, y eso depende de dónde esté el móvil y de cuánto zoom tenga. La
/// misma bandeja da 0,9 en un vídeo grabado desde la valla de al lado y 0,25 en uno
/// grabado desde el fondo. Un umbral absoluto ajustado con un vídeo no valdría para el
/// siguiente. Por eso el pico se compara con la **mediana** de la velocidad de ese mismo
/// vídeo: la mediana es el movimiento normal de ese jugador en ese plano, y el golpe es lo
/// que la multiplica por varias veces. La mediana (y no la media) porque los propios picos
/// de golpe arrastrarían la media hacia arriba.
///
/// CUÁNDO ESTO NO FUNCIONA, y hay que decirlo en pantalla:
///
/// - **Cámara en la mano.** Si el móvil se mueve, todo se mueve: la mediana sube y los
///   golpes dejan de destacar. Esto necesita el móvil quieto (apoyado en la valla, que es
///   como se graba una tanda de todas formas).
/// - **Jugador pequeño en el cuadro.** Si la muñeca va con confianza baja, el punto salta
///   solo y produce picos que no son golpes.
/// - **Un golpe suave** (una dejada, un globo sin recorrido) puede no llegar al umbral y
///   no salir propuesto. Que no haya propuesta no significa que no hubiera golpe.
///
/// Nada de esto se corrige adivinando: se propone, el usuario mira el vídeo y decide.
enum CandidatosDeGolpe {

    /// Dos golpes seguidos de una tanda van a metro y medio de segundo; por debajo de esto
    /// el mismo golpe se propondría dos veces (la subida y la bajada del brazo).
    static let separacionMinima: Double = 0.45
    /// Cuántas veces la mediana tiene que valer un pico para proponerse. Con 2,5 entran
    /// golpes flojos y también algún movimiento brusco que no es golpe; es el lado bueno
    /// del error, porque descartar una propuesta cuesta un toque y encontrar un golpe que
    /// no se propuso cuesta rebobinar el vídeo entero.
    static let prominenciaMinima: Double = 2.5
    /// Un candidato a menos de esto de una marca que ya existe es esa misma marca.
    static let ventanaDeDuplicado: Double = 0.6
    /// Hueco máximo entre dos posturas para que su diferencia signifique una velocidad. A
    /// 12 Hz las muestras van a 83 ms; si hubo fotogramas sin jugador, el hueco es mayor y
    /// dividir por él daría una velocidad inventada.
    static let huecoMaximo: Double = 0.25
    /// Tope de propuestas. Una lista de mil elementos no la revisa nadie, y si salen mil
    /// es que el vídeo no sirve para esto.
    static let maximoDePropuestas = 300

    /// Un instante de la serie con la velocidad de muñeca que se midió ahí.
    private struct Pico {
        let segundos: Double
        let velocidad: Double
        let confianza: Double
        let postura: PosturaDetectada
    }

    /// Las propuestas, en orden de reproducción.
    ///
    /// `marcasExistentes` son los segundos de las marcas que el usuario ya puso: lo que ya
    /// está marcado no se vuelve a proponer.
    static func proponer(
        _ posturas: [PosturaDetectada],
        marcasExistentes: [Double] = []
    ) -> [CandidatoAGolpe] {
        guard posturas.count > 4 else { return [] }

        var serie: [Pico] = []
        for i in 1..<posturas.count {
            let previa = posturas[i - 1]
            let actual = posturas[i]
            let dt = actual.segundos - previa.segundos
            guard dt > 0, dt <= huecoMaximo else { continue }

            // La muñeca más rápida de las dos, no la de la mano hábil: el vídeo puede ser
            // de cualquiera, y en un revés a dos manos las dos se mueven.
            var velocidad: Double = 0
            var confianza: Double = 0
            for (antes, despues) in [
                (previa.munecaIzquierda, actual.munecaIzquierda),
                (previa.munecaDerecha, actual.munecaDerecha),
            ] {
                guard let antes, let despues else { continue }
                let v = hypot(despues.x - antes.x, despues.y - antes.y) / dt
                if v > velocidad {
                    velocidad = v
                    // La del punto peor de los dos: una muñeca que se vio mal en cualquiera
                    // de los dos fotogramas ya hace dudosa la velocidad.
                    confianza = min(antes.confianza, despues.confianza)
                }
            }
            guard velocidad > 0 else { continue }
            serie.append(
                Pico(segundos: actual.segundos, velocidad: velocidad, confianza: confianza, postura: actual)
            )
        }
        guard serie.count > 4 else { return [] }

        let ordenadas = serie.map(\.velocidad).sorted()
        let mediana = ordenadas[ordenadas.count / 2]
        // Un vídeo en el que la muñeca no se mueve (jugador parado, detección congelada)
        // no tiene golpes que proponer, y dividir por cero daría prominencias infinitas.
        guard mediana > 1e-6 else { return [] }

        // Máximos locales por encima del umbral. Sin suavizar la serie a propósito: a
        // 12 Hz un golpe ocupa una o dos muestras y un filtro de media móvil se lo come.
        var maximos: [Pico] = []
        for i in 1..<(serie.count - 1) {
            let pico = serie[i]
            guard pico.velocidad >= mediana * prominenciaMinima,
                  pico.velocidad >= serie[i - 1].velocidad,
                  pico.velocidad >= serie[i + 1].velocidad else { continue }
            maximos.append(pico)
        }

        // Se aceptan de mayor a menor velocidad respetando la separación mínima: así,
        // entre dos picos pegados gana el más marcado, y no el que venga antes en el
        // tiempo (que es lo que haría un recorrido lineal, y suele ser la subida del brazo
        // en vez del impacto).
        var aceptados: [Pico] = []
        for pico in maximos.sorted(by: { $0.velocidad > $1.velocidad }) {
            if aceptados.count >= maximoDePropuestas { break }
            let chocaConOtro = aceptados.contains { abs($0.segundos - pico.segundos) < separacionMinima }
            let yaMarcado = marcasExistentes.contains { abs($0 - pico.segundos) < ventanaDeDuplicado }
            if chocaConOtro || yaMarcado { continue }
            aceptados.append(pico)
        }

        return aceptados
            .sorted { $0.segundos < $1.segundos }
            .map { pico in
                CandidatoAGolpe(
                    segundos: pico.segundos,
                    prominencia: pico.velocidad / mediana,
                    confianzaPostura: pico.confianza,
                    postura: pico.postura
                )
            }
    }
}
