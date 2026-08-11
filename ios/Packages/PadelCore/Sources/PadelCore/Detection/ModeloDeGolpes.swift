import Foundation

/// Un bosque de decisión pequeño, escrito como tablas de números.
///
/// Es el sustituto de la heurística cuando haya datos para entrenarlo. Se guarda como
/// **código generado** y no como Core ML, y esa es la decisión de diseño que más importa:
///
/// - Con dos runtimes distintos (Core ML aquí, TFLite en Wear), los dos relojes pueden
///   dar respuestas distintas al mismo golpe, y eso es imposible de depurar sin los dos
///   delante. Con tablas, la aritmética son cuatro líneas por lenguaje y los números son
///   literalmente los mismos.
/// - Se prueba en Kotlin como todo lo demás, con las tandas de pista de fixture.
/// - No añade dependencias ni peso de runtime a dos apps que ya pesan.
///
/// **Come exactamente `ShotFeatures`**, los mismos nueve rasgos que ya calcula el reloj
/// para cada golpe. Podría comer la ventana cruda y sacar más señal, pero entonces habría
/// que reimplementar la extracción en Kotlin, en Swift y en Python **sin poder comprobar
/// que las tres dan lo mismo** — y una discrepancia ahí no se ve, solo empeora los
/// números sin decir por qué. Se empieza por lo que no puede desincronizarse.
///
/// Espejo del core Kotlin, con tests allí.
public struct ModeloDeGolpes: Sendable {
    /// Los tipos que el modelo sabe decir, en el orden en que se entrenó.
    public let clases: [ShotType]
    /// Índice del nodo raíz de cada árbol dentro de las tablas.
    public let raices: [Int]
    /// Rasgo por el que corta cada nodo, o -1 si es una hoja.
    public let rasgo: [Int]
    /// Umbral del corte: se va a la izquierda si el valor es <= umbral.
    public let umbral: [Float]
    public let izquierda: [Int]
    public let derecha: [Int]
    /// Clase que vota cada hoja (índice en `clases`). -1 en los nodos internos.
    public let hoja: [Int]
    /// Cuántos golpeos etiquetados lo sostienen, para poder enseñarlo.
    public let muestras: Int
    /// Acierto dejando fuera a un jugador entero, 0 a 1. La única cifra que predice.
    public let aciertoFuera: Float

    public var arboles: Int { raices.count }

    public init(
        clases: [ShotType],
        raices: [Int],
        rasgo: [Int],
        umbral: [Float],
        izquierda: [Int],
        derecha: [Int],
        hoja: [Int],
        muestras: Int,
        aciertoFuera: Float
    ) {
        self.clases = clases
        self.raices = raices
        self.rasgo = rasgo
        self.umbral = umbral
        self.izquierda = izquierda
        self.derecha = derecha
        self.hoja = hoja
        self.muestras = muestras
        self.aciertoFuera = aciertoFuera
    }

    /// El voto del bosque: la clase más votada y qué fracción de árboles la votó.
    ///
    /// La confianza es la fracción de votos y no una probabilidad calibrada, a propósito:
    /// es lo que se puede explicar en una frase ("18 de 25 árboles dicen bandeja") y lo
    /// que se puede comparar con el `minConfidence` que ya usa la heurística.
    public func clasificar(_ features: ShotFeatures) -> Classification? {
        guard !clases.isEmpty, !raices.isEmpty else { return nil }
        let valores = Self.vectorDe(features)
        var votos = [Int](repeating: 0, count: clases.count)
        for raiz in raices {
            var nodo = raiz
            while rasgo[nodo] >= 0 {
                nodo = valores[rasgo[nodo]] <= umbral[nodo] ? izquierda[nodo] : derecha[nodo]
            }
            let clase = hoja[nodo]
            if clase >= 0, clase < votos.count { votos[clase] += 1 }
        }
        var mejor = 0
        for i in votos.indices where votos[i] > votos[mejor] { mejor = i }
        guard votos[mejor] > 0 else { return nil }
        return Classification(type: clases[mejor], confidence: Float(votos[mejor]) / Float(raices.count))
    }

    /// El orden de los rasgos. Es un contrato con `tools/exportar_modelo.py`: si cambia
    /// aquí y no allí, el modelo lee los números cambiados de sitio y falla en silencio
    /// — que es la peor forma de fallar. Hay un test que lo fija en el core Kotlin.
    public static let rasgos = [
        "sweptAngleDeg",
        "peakGyroRadS",
        "elevationDeg",
        "axialRotationRadS",
        "swingDurationMs",
        "peakElevationDeg",
        "prepElevationDeg",
        "peakAxialRotationRadS",
        "elevationDropDeg",
    ]

    /// Los nulos se rellenan con 0 y no se descartan: un golpe sin elevación de
    /// preparación es un golpe que hay que clasificar igual.
    public static func vectorDe(_ features: ShotFeatures) -> [Float] {
        [
            features.sweptAngleDeg,
            features.peakGyroRadS,
            features.elevationDeg,
            features.axialRotationRadS,
            Float(features.swingDurationMs),
            features.peakElevationDeg,
            features.prepElevationDeg ?? 0,
            features.peakAxialRotationRadS ?? 0,
            features.elevationDropDeg ?? 0,
        ]
    }
}
