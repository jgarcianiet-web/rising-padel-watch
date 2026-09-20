import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import Vision

/// Qué puede fallar al analizar un vídeo, en palabras que se puedan enseñar en pantalla.
enum ErrorDeAnalisis: LocalizedError {
    case sinFichero
    case sinPistaDeVideo
    case noSePuedeLeer

    var errorDescription: String? {
        switch self {
        case .sinFichero:
            return "El fichero de vídeo ya no está en el móvil."
        case .sinPistaDeVideo:
            return "Ese fichero no tiene imagen (solo audio, o está corrupto)."
        case .noSePuedeLeer:
            return "No se pudo leer el vídeo fotograma a fotograma."
        }
    }
}

/// Lo que devuelve una pasada del detector.
struct PasadaDePosturas: Sendable {
    var posturas: [PosturaDetectada]
    var fotogramasAnalizados: Int
    var personasMaximas: Int
    var muestreoHz: Double
}

/// Recorre el vídeo fotograma a fotograma y saca la postura del jugador con Vision.
///
/// **Fuera del hilo principal y cancelable**: una pasada sobre 10 minutos de vídeo son
/// unos 7.000 fotogramas por la red neuronal de posturas, del orden de varios minutos en
/// un iPhone reciente. Quien lo llame lo hace desde una tarea aparte y mira
/// `Task.isCancelled` a través del `CancellationError` que sale de aquí.
///
/// Por qué `AVAssetReader` y no capturar en tiempo real: aquí no hay tiempo real que valga
/// —el vídeo ya está grabado— y leer secuencialmente decodifica una sola vez y a la
/// velocidad que dé el aparato. Tampoco se usa `AVAssetImageGenerator` para ir saltando a
/// los instantes del muestreo: cada salto obliga al decodificador a volver al fotograma
/// clave anterior y a decodificar hasta el pedido, así que muestrear con saltos acaba
/// decodificando **más** fotogramas que leerlos todos de corrido.
enum DetectorDePosturas {

    /// Fotogramas por segundo que se pasan por Vision.
    ///
    /// Es el compromiso central de todo esto. El pico de velocidad de muñeca de un golpe
    /// dura del orden de 150-250 ms: por debajo de unos 10 Hz el pico se cuela entre dos
    /// muestras y el detector de candidatos se queda ciego. Por encima de 15 Hz el
    /// análisis tarda más de lo que nadie espera mirando una barra de progreso, y la
    /// ganancia es pequeña porque las posturas consecutivas se parecen mucho. 12 Hz es
    /// donde se queda, y se guarda en el resultado para poder comparar pasadas.
    static let muestreoPorDefecto: Double = 12

    static func analizar(
        url: URL,
        muestreoHz: Double = muestreoPorDefecto,
        progreso: (Double) -> Void
    ) async throws -> PasadaDePosturas {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ErrorDeAnalisis.sinFichero
        }

        let asset = AVURLAsset(url: url)
        guard let pista = try await asset.loadTracks(withMediaType: .video).first else {
            throw ErrorDeAnalisis.sinPistaDeVideo
        }
        let transformacion = try await pista.load(.preferredTransform)
        let duracion = CMTimeGetSeconds(try await asset.load(.duration))
        let orientacion = Self.orientacion(transformacion)

        guard let lector = try? AVAssetReader(asset: asset) else {
            throw ErrorDeAnalisis.noSePuedeLeer
        }
        // Formato nativo de la cámara del iPhone: Vision acepta el bi-planar YUV tal cual,
        // así que pedir BGRA solo añadiría una conversión de color por fotograma.
        let salida = AVAssetReaderTrackOutput(
            track: pista,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        // El buffer solo se usa dentro de la iteración, antes de pedir el siguiente.
        salida.alwaysCopiesSampleData = false
        guard lector.canAdd(salida) else { throw ErrorDeAnalisis.noSePuedeLeer }
        lector.add(salida)
        guard lector.startReading() else { throw ErrorDeAnalisis.noSePuedeLeer }

        // Una sola petición reutilizada: crear una `VNDetectHumanBodyPoseRequest` por
        // fotograma vuelve a montar el grafo de la red y multiplica el coste.
        let peticion = VNDetectHumanBodyPoseRequest()

        var posturas: [PosturaDetectada] = []
        var seguidor = SeguidorDeJugador()
        var fotogramas = 0
        var personasMaximas = 0
        let intervalo = 1 / max(muestreoHz, 1)
        var proximoInstante: Double = 0

        while let muestra = salida.copyNextSampleBuffer() {
            if Task.isCancelled {
                lector.cancelReading()
                throw CancellationError()
            }
            let instante = CMSampleBufferGetPresentationTimeStamp(muestra).seconds
            guard instante.isFinite, instante >= proximoInstante else { continue }
            proximoInstante = instante + intervalo
            guard let imagen = CMSampleBufferGetImageBuffer(muestra) else { continue }

            // Sin el pool, los buffers intermedios de Vision se acumulan durante toda la
            // pasada y el consumo de memoria crece sin parar en vídeos largos.
            autoreleasepool {
                let manejador = VNImageRequestHandler(
                    cvPixelBuffer: imagen,
                    orientation: orientacion,
                    options: [:]
                )
                // Un fotograma que Vision no pueda procesar no puede tirar la pasada
                // entera: se cuenta como fotograma sin postura y se sigue.
                try? manejador.perform([peticion])
                let observaciones = peticion.results ?? []
                fotogramas += 1
                personasMaximas = max(personasMaximas, observaciones.count)
                if let postura = seguidor.elegir(observaciones, segundos: instante) {
                    posturas.append(postura)
                }
            }

            if duracion > 0 {
                progreso(min(max(instante / duracion, 0), 1))
            }
        }

        if lector.status == .failed {
            throw ErrorDeAnalisis.noSePuedeLeer
        }
        progreso(1)

        return PasadaDePosturas(
            posturas: posturas,
            fotogramasAnalizados: fotogramas,
            personasMaximas: personasMaximas,
            muestreoHz: muestreoHz
        )
    }

    /// La orientación con la que hay que leer los fotogramas crudos.
    ///
    /// `AVAssetReader` entrega el buffer tal y como está codificado, **sin** aplicar la
    /// transformación de la pista: un vídeo grabado en vertical llega tumbado. Pasarle la
    /// orientación a Vision hace dos cosas de golpe: la red ve a la persona derecha (con
    /// el jugador tumbado, la detección de postura falla mucho más) y las coordenadas
    /// normalizadas que devuelve son las de la imagen ya enderezada — las mismas en las
    /// que el usuario toca las esquinas en la pantalla de calibración, que sale de
    /// `AVAssetImageGenerator` con `appliesPreferredTrackTransform`. Sin esto, la
    /// calibración y las posturas vivirían en sistemas distintos y el mapa saldría girado.
    private static func orientacion(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        // Los valores reales son exactamente 0 y ±1, pero se redondean para no depender de
        // la igualdad exacta entre números en coma flotante.
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): return .right   // vertical, cámara girada 90º
        case (0, -1, 1, 0): return .left    // vertical del revés
        case (-1, 0, 0, -1): return .down   // horizontal boca abajo
        default: return .up                 // horizontal, lo normal apoyado en la valla
        }
    }
}

/// Decide, fotograma a fotograma, cuál de las personas que ve Vision es "el jugador".
///
/// EL PROBLEMA, dicho claro: en una pista hay hasta cuatro jugadores y Vision devuelve una
/// observación por persona, **sin identidad** — no dice cuál es cuál entre un fotograma y
/// el siguiente. Un seguimiento de verdad (re-identificación por apariencia) es otro
/// modelo que aquí no hay.
///
/// LO QUE SE HACE en su lugar, que es lo que se puede hacer con honestidad: se elige al
/// principio a la persona **más grande en la imagen** (la más cercana a la cámara, que en
/// un vídeo de tandas es quien graba el entrenamiento) y a partir de ahí se sigue al
/// más cercano al anterior, con un salto máximo. Si nadie cae dentro del salto, o si se
/// perdió más de un segundo, se vuelve a elegir desde cero.
///
/// LO QUE FALLA: cuando dos jugadores se cruzan, el seguidor puede cambiar de persona sin
/// enterarse. Por eso el resultado guarda cuántas personas había en cuadro y la pantalla
/// lo avisa: con más de una persona, lo que sale hay que mirarlo.
struct SeguidorDeJugador {
    /// En fracción de imagen. A 12 Hz, un jugador corriendo a 4 m/s recorre bastante menos
    /// de un quinto del cuadro entre muestras; un salto mayor que eso es otra persona.
    private static let saltoMaximo: Double = 0.2
    /// Si se pierde al jugador más de un segundo, la continuidad ya no significa nada.
    private static let huecoMaximo: Double = 1

    private var ultimoCentro: CGPoint?
    private var ultimoInstante: Double?

    mutating func elegir(
        _ observaciones: [VNHumanBodyPoseObservation],
        segundos: Double
    ) -> PosturaDetectada? {
        var candidatas: [(postura: PosturaDetectada, centro: CGPoint, tamano: Double)] = []
        for observacion in observaciones {
            guard let candidata = Self.leer(observacion, segundos: segundos) else { continue }
            candidatas.append(candidata)
        }
        guard !candidatas.isEmpty else { return nil }

        var elegida: (postura: PosturaDetectada, centro: CGPoint, tamano: Double)?

        let hueco = ultimoInstante.map { segundos - $0 } ?? .greatestFiniteMagnitude
        if let ultimoCentro, hueco <= Self.huecoMaximo {
            var mejorDistancia = Self.saltoMaximo
            for candidata in candidatas {
                let dx = Double(candidata.centro.x - ultimoCentro.x)
                let dy = Double(candidata.centro.y - ultimoCentro.y)
                let distancia = (dx * dx + dy * dy).squareRoot()
                if distancia <= mejorDistancia {
                    mejorDistancia = distancia
                    elegida = candidata
                }
            }
        }

        // Primera vez, o se perdió: la más grande, que es la más cercana a la cámara.
        if elegida == nil {
            elegida = candidatas.max { $0.tamano < $1.tamano }
        }

        guard let elegida else { return nil }
        ultimoCentro = elegida.centro
        ultimoInstante = segundos
        var postura = elegida.postura
        postura.personas = observaciones.count
        return postura
    }

    /// Pasa una observación de Vision a las seis articulaciones que el laboratorio usa.
    ///
    /// Nil si no hay ninguna utilizable: una persona de la que solo se ve una oreja no
    /// sirve ni para posición ni para golpes, y meterla en la lista solo añadiría huecos.
    private static func leer(
        _ observacion: VNHumanBodyPoseObservation,
        segundos: Double
    ) -> (postura: PosturaDetectada, centro: CGPoint, tamano: Double)? {
        guard let puntos = try? observacion.recognizedPoints(.all) else { return nil }

        var postura = PosturaDetectada(segundos: segundos)
        postura.munecaIzquierda = punto(puntos[.leftWrist])
        postura.munecaDerecha = punto(puntos[.rightWrist])
        postura.tobilloIzquierdo = punto(puntos[.leftAnkle])
        postura.tobilloDerecho = punto(puntos[.rightAnkle])
        postura.hombroIzquierdo = punto(puntos[.leftShoulder])
        postura.hombroDerecho = punto(puntos[.rightShoulder])

        let usables = [
            postura.munecaIzquierda, postura.munecaDerecha,
            postura.tobilloIzquierdo, postura.tobilloDerecho,
            postura.hombroIzquierdo, postura.hombroDerecho,
        ].compactMap { $0 }
        guard !usables.isEmpty else { return nil }

        let centro = CGPoint(
            x: usables.reduce(0) { $0 + $1.x } / Double(usables.count),
            y: usables.reduce(0) { $0 + $1.y } / Double(usables.count)
        )
        // El alto en pantalla como medida de cercanía: una persona el doble de alta en la
        // imagen está aproximadamente a la mitad de distancia.
        let alto = (usables.map(\.y).max() ?? 0) - (usables.map(\.y).min() ?? 0)
        return (postura, centro, alto)
    }

    private static func punto(_ reconocido: VNRecognizedPoint?) -> PuntoDeImagen? {
        guard let reconocido,
              Double(reconocido.confidence) >= PosturaDetectada.confianzaMinimaDePunto
        else { return nil }
        return PuntoDeImagen(
            x: Double(reconocido.location.x),
            // Vision normaliza con el origen abajo-izquierda; el resto del módulo trabaja
            // con el origen arriba-izquierda, como la pantalla. Se voltea aquí, una vez.
            y: 1 - Double(reconocido.location.y),
            confianza: Double(reconocido.confidence)
        )
    }
}
