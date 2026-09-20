import CoreGraphics
import Foundation

/// La pista de pádel como sistema de coordenadas, y la transformación que lleva un punto
/// del vídeo a esas coordenadas.
///
/// Esto es lo único de todo el análisis de vídeo que se apoya en un dato **cierto**: una
/// pista de pádel mide 20 × 10 m por reglamento (FIP), así que en cuanto se sabe dónde
/// caen sus cuatro esquinas en la imagen, la geometría de la escena queda determinada sin
/// necesidad de calibrar la cámara ni de conocer su lente. Todo lo demás en este módulo
/// (posturas, candidatos a golpe) es estimación con su confianza; esto no.

/// Medidas del reglamento y el sistema de coordenadas que usa toda la app para la pista.
///
/// Eje `x`: a lo largo de la pista, 0 en el fondo del lado desde el que se graba y 20 en
/// el fondo contrario. Eje `y`: a lo ancho, 0 en la pared izquierda vista desde la cámara
/// y 10 en la derecha. Metros en los dos casos, sin más escalas: un metro es un metro y
/// así las distancias del mapa se leen tal cual.
enum PistaDePadel {
    static let largo: Double = 20
    static let ancho: Double = 10
    /// La línea de saque está a 6,95 m de la red. Sirve de comprobación visual de la
    /// calibración: si al pintarla sobre el fotograma no cae encima de la línea de
    /// verdad, las esquinas están mal puestas.
    static let lineaDeSaque: Double = 6.95
    /// La red parte la pista por la mitad.
    static let red: Double = 10

    /// Las cuatro esquinas del **suelo**, en metros, en el orden en que se le piden al
    /// usuario. El orden importa: la homografía empareja la esquina i de la imagen con la
    /// esquina i de la pista, y cambiarlo da una transformación girada o volteada.
    static let esquinas: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 0, y: ancho),
        CGPoint(x: largo, y: ancho),
        CGPoint(x: largo, y: 0),
    ]

    /// Cómo se le nombran esas cuatro esquinas al usuario mientras las toca.
    static let nombresDeEsquina = [
        "Fondo cercano (el de la cámara), izquierda",
        "Fondo cercano (el de la cámara), derecha",
        "Fondo contrario, derecha",
        "Fondo contrario, izquierda",
    ]

    /// Un punto está dentro de la pista con un margen de tolerancia: un pie pisando la
    /// línea o un error de medio metro de la homografía no pueden convertir una posición
    /// buena en "fuera".
    static func dentro(_ punto: CGPoint, margen: Double = 0.5) -> Bool {
        punto.x >= -margen && punto.x <= largo + margen
            && punto.y >= -margen && punto.y <= ancho + margen
    }
}

/// Una homografía plana: la transformación proyectiva que lleva los puntos de un plano a
/// los de otro. Aquí, del plano del **suelo de la pista visto por la cámara** al plano de
/// la pista en metros (y al revés, para pintar las líneas sobre el fotograma).
///
/// LA MATEMÁTICA, porque no hay biblioteca que la traiga y conviene poder revisarla:
///
/// En coordenadas homogéneas la transformación es una matriz 3×3
///
///     ⎡ h11 h12 h13 ⎤
///     ⎢ h21 h22 h23 ⎥ ,  y el punto (x,y) va a (x', y') con
///     ⎣ h31 h32  1  ⎦
///
///     x' = (h11·x + h12·y + h13) / (h31·x + h32·y + 1)
///     y' = (h21·x + h22·y + h23) / (h31·x + h32·y + 1)
///
/// La matriz está definida salvo escala (multiplicarla entera por un número da el mismo
/// punto), así que se fija h33 = 1 y quedan **8 incógnitas**. Quitando denominadores,
/// cada pareja de puntos conocidos aporta dos ecuaciones lineales:
///
///     h11·x + h12·y + h13                     − h31·x·x' − h32·y·x' = x'
///                     h21·x + h22·y + h23     − h31·x·y' − h32·y·y' = y'
///
/// Cuatro parejas → 8 ecuaciones y 8 incógnitas → un sistema cuadrado que se resuelve con
/// eliminación gaussiana. Con pivoteo parcial, porque los coeficientes de las dos últimas
/// columnas (los x·x') son de un orden de magnitud muy distinto al de las primeras y sin
/// pivotar la eliminación pierde precisión.
///
/// h33 = 1 falla en un caso: si la transformación manda el origen al infinito. Con las
/// cuatro esquinas de una pista real vista por una cámara que está *fuera* del plano del
/// suelo eso no pasa; si pasara, el sistema sale singular y el `init` devuelve nil en vez
/// de inventarse una matriz.
///
/// LO QUE LA HOMOGRAFÍA **NO** HACE, y hay que respetarlo al usarla: solo vale para
/// puntos que están **en el plano del suelo**. Un tobillo lo está (con el error del
/// grosor del pie); una muñeca a metro y medio de altura no, y aplicarle esta
/// transformación da un punto de pista que no significa nada — el error crece con la
/// altura y con lo rasante que sea la cámara, y puede irse varios metros. Por eso la
/// posición en pista se calcula solo desde los tobillos.
struct Homografia: Codable, Equatable, Sendable {
    /// `[h11, h12, h13, h21, h22, h23, h31, h32]`, por filas, con h33 = 1 implícito.
    /// Se guarda como lista plana y no como matriz para que el JSON exportado sea legible
    /// y para no tener que decodificar una estructura anidada.
    let coeficientes: [Double]

    init?(coeficientes: [Double]) {
        guard coeficientes.count == 8, coeficientes.allSatisfy({ $0.isFinite }) else { return nil }
        self.coeficientes = coeficientes
    }

    /// Se valida al decodificar: una matriz guardada a medias (ocho coeficientes es el
    /// único tamaño con sentido) tiene que dar error aquí y no un mapa de pista torcido
    /// veinte pantallas más allá. Quien la lee lo hace con `try?` y se queda sin
    /// calibración, que es lo honesto.
    init(from decoder: Decoder) throws {
        let contenedor = try decoder.container(keyedBy: CodingKeys.self)
        let valores = try contenedor.decode([Double].self, forKey: .coeficientes)
        guard valores.count == 8, valores.allSatisfy({ $0.isFinite }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .coeficientes,
                in: contenedor,
                debugDescription: "Una homografía son 8 coeficientes finitos"
            )
        }
        coeficientes = valores
    }

    /// Resuelve la homografía que lleva `origen[i]` a `destino[i]`, con exactamente cuatro
    /// parejas. Devuelve nil si los puntos son degenerados (tres alineados, dos iguales,
    /// cuadrilátero cruzado): ahí el sistema es singular y cualquier matriz que saliera
    /// sería ruido.
    init?(origen: [CGPoint], destino: [CGPoint]) {
        guard origen.count == 4, destino.count == 4 else { return nil }

        var matriz = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var terminos = [Double](repeating: 0, count: 8)

        for i in 0..<4 {
            let x = Double(origen[i].x)
            let y = Double(origen[i].y)
            let u = Double(destino[i].x)
            let v = Double(destino[i].y)
            guard x.isFinite, y.isFinite, u.isFinite, v.isFinite else { return nil }

            // Fila de x': h11·x + h12·y + h13 − h31·x·u − h32·y·u = u
            matriz[2 * i] = [x, y, 1, 0, 0, 0, -x * u, -y * u]
            terminos[2 * i] = u
            // Fila de y': h21·x + h22·y + h23 − h31·x·v − h32·y·v = v
            matriz[2 * i + 1] = [0, 0, 0, x, y, 1, -x * v, -y * v]
            terminos[2 * i + 1] = v
        }

        guard let solucion = Self.resolver(matriz, terminos) else { return nil }
        // Delegación a un `init?`: si la solución no vale, este `init` falla solo.
        self.init(coeficientes: solucion)
    }

    /// Lleva un punto de un plano al otro. Nil cuando cae en la línea del horizonte de la
    /// transformación (denominador ≈ 0): ahí la proyección se va al infinito y devolver un
    /// número enorme sería peor que no devolver nada.
    func aplicar(_ punto: CGPoint) -> CGPoint? {
        let h = coeficientes
        let x = Double(punto.x)
        let y = Double(punto.y)
        let w = h[6] * x + h[7] * y + 1
        guard abs(w) > 1e-9 else { return nil }
        let u = (h[0] * x + h[1] * y + h[2]) / w
        let v = (h[3] * x + h[4] * y + h[5]) / w
        guard u.isFinite, v.isFinite else { return nil }
        return CGPoint(x: u, y: v)
    }

    // MARK: Álgebra

    /// Eliminación gaussiana con pivoteo parcial y sustitución hacia atrás.
    ///
    /// El umbral del pivote (1e-12) es lo que distingue "sistema resoluble" de "los cuatro
    /// puntos no definen una homografía". No se baja más: con números del orden de 1 (las
    /// coordenadas van normalizadas 0-1 y los metros hasta 20), un pivote más pequeño que
    /// eso ya es ruido de redondeo y la solución no significaría nada.
    private static func resolver(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = a
        var t = b
        let n = t.count

        for columna in 0..<n {
            var mejor = columna
            for fila in (columna + 1)..<n where abs(m[fila][columna]) > abs(m[mejor][columna]) {
                mejor = fila
            }
            guard abs(m[mejor][columna]) > 1e-12 else { return nil }
            if mejor != columna {
                m.swapAt(columna, mejor)
                t.swapAt(columna, mejor)
            }

            let pivote = m[columna][columna]
            for fila in (columna + 1)..<n {
                let factor = m[fila][columna] / pivote
                if factor == 0 { continue }
                for k in columna..<n {
                    m[fila][k] -= factor * m[columna][k]
                }
                t[fila] -= factor * t[columna]
            }
        }

        var x = [Double](repeating: 0, count: n)
        for fila in stride(from: n - 1, through: 0, by: -1) {
            var suma = t[fila]
            for k in (fila + 1)..<n {
                suma -= m[fila][k] * x[k]
            }
            x[fila] = suma / m[fila][fila]
        }
        return x.allSatisfy { $0.isFinite } ? x : nil
    }

    /// Si los cuatro puntos, en el orden dado, forman un cuadrilátero convexo sin cruces.
    ///
    /// Se comprueba **antes** de resolver porque es el error humano típico de la pantalla
    /// de calibración: tocar las esquinas en aspa en vez de en orden. El sistema con
    /// puntos cruzados tiene solución (una homografía que voltea la pista), así que sin
    /// esta comprobación el fallo no se ve hasta que el mapa sale del revés.
    static func esConvexo(_ puntos: [CGPoint]) -> Bool {
        guard puntos.count == 4 else { return false }
        var signo = 0
        for i in 0..<4 {
            let a = puntos[i]
            let b = puntos[(i + 1) % 4]
            let c = puntos[(i + 2) % 4]
            let cruz = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            // Un vértice casi recto (cruz ≈ 0) no decide: puede pasar con una cámara muy
            // de frente y no es un error del usuario.
            if abs(cruz) < 1e-9 { continue }
            let actual = cruz > 0 ? 1 : -1
            if signo == 0 {
                signo = actual
            } else if signo != actual {
                return false
            }
        }
        return signo != 0
    }
}
