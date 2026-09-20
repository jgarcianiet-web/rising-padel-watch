import Foundation

/// Una lectura de posición del reloj.
///
/// `accuracyM` es el error que el propio sistema declara para esa lectura. No es un
/// adorno: es el primer filtro, porque una lectura que se dice mala lo es.
public struct PuntoGeo: Codable, Equatable, Sendable {
    public var latitud: Double
    public var longitud: Double
    public var accuracyM: Double

    public init(latitud: Double, longitud: Double, accuracyM: Double = 0) {
        self.latitud = latitud
        self.longitud = longitud
        self.accuracyM = accuracyM
    }
}

/// Dónde estaba el jugador dentro de la pista, en metros.
///
/// **El sistema de coordenadas es el mismo que usa el análisis de vídeo** (`PistaDePadel`
/// en el módulo VideoLab de la app): `x` a lo largo de la pista, de 0 a 20, con la red en
/// el 10; `y` a lo ancho, de 0 a 10. Que las dos fuentes —la cámara y el GPS— cuenten los
/// metros igual es lo que permitirá algún día pintarlas en el mismo mapa sin traducir
/// nada; el día que una de las dos cambie de criterio, el mapa mezclará dos pistas
/// distintas sin avisar.
public struct PosicionGpsEnPista: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Medidas de reglamento de una pista de pádel, en metros.
    public static let largo = 20.0
    public static let ancho = 10.0
    /// La red parte la pista por la mitad.
    public static let red = largo / 2

    /// Metros hasta la red, que es la lectura táctica que de verdad se usa.
    public var distanciaALaRed: Double { abs(x - Self.red) }

    /// Las seis zonas gruesas del mapa de pista: red / medio / fondo, por lado.
    ///
    /// La profundidad se mide **contra la red**, que está en el centro de los veinte
    /// metros y no en un extremo: en una pista entera los dos fondos son fondo, y contar
    /// desde una punta pondría "fondo" en la mitad contraria de la red.
    public var zona: String {
        let profundidad: String
        switch distanciaALaRed {
        case ..<(Self.largo / 6): profundidad = "red"
        case ..<(Self.largo / 3): profundidad = "medio"
        default: profundidad = "fondo"
        }
        return y < Self.ancho / 2 ? "\(profundidad) izquierda" : "\(profundidad) derecha"
    }
}

/// La pista, situada sobre el mundo a partir de cuatro lecturas de GPS en sus esquinas.
///
/// ## Para qué sirve de verdad: para medir si el GPS llega
///
/// La pregunta "¿puede el reloj decir dónde estaba el jugador?" no se contesta con una
/// opinión sobre el GPS, se contesta con un número. Y hay una forma limpia de sacarlo:
/// **una pista de pádel mide 20×10 m por reglamento**, así que sus dimensiones son un
/// patrón de medida conocido. Si el jugador se planta en las cuatro esquinas y el reloj
/// toma una lectura en cada una, lo que falle al reconstruir ese rectángulo **es** el
/// error del GPS en esa pista concreta, con su multitrayecto, su techo y su día.
///
/// Ese número es `errorMedioM`, y es lo que decide qué se puede enseñar:
///
/// - por debajo de ~1,5 m se pueden separar las seis zonas de `PosicionGpsEnPista.zona`;
/// - entre 1,5 y 3 m solo se sostiene "cerca de la red" contra "en el fondo";
/// - por encima de 3 m no se sostiene nada, y hay que decirlo en vez de pintar puntos.
///
/// Las paredes de cristal y la malla metálica producen multitrayecto —la señal rebota
/// antes de llegar al reloj— y muchas pistas están cubiertas, así que este número va a
/// ser peor que el del GPS en campo abierto. Por eso se mide en la pista de cada uno.
///
/// ## Por qué lleva "Gps" en el nombre
///
/// Porque hay otra calibración de pista en la app —la del vídeo, que saca la homografía
/// de las cuatro esquinas tocadas sobre un fotograma— y son cosas distintas con el mismo
/// apellido. Dos tipos llamados igual en dos módulos que algún día van a alimentar el
/// mismo mapa es una confusión esperando su turno.
///
/// ## Cómo se ajusta
///
/// Las cuatro lecturas se pasan a metros y se busca la rotación y el desplazamiento que
/// mejor las encajan sobre el rectángulo ideal (Procrustes en dos dimensiones, **sin
/// escala**: el tamaño de la pista lo da el reglamento y no el GPS — dejar que la escala
/// se ajuste escondería justo el error que se quiere medir).
///
/// Espejo de `CalibracionGpsDePista` en el core Kotlin, con los tests allí.
public struct CalibracionGpsDePista: Codable, Equatable, Sendable {
    /// Latitud y longitud del centro de la pista: el origen del sistema local.
    public var centroLatitud: Double
    public var centroLongitud: Double
    /// Giro de la pista respecto al norte, en radianes.
    public var rotacionRad: Double
    /// Cuánto se desvían de media las cuatro esquinas medidas respecto al rectángulo
    /// ideal, en metros. **Es la cifra que dice si el mapa de pista se puede enseñar.**
    public var errorMedioM: Double
    /// El peor error declarado por el sistema entre las cuatro lecturas.
    public var peorAccuracyM: Double

    public init(
        centroLatitud: Double,
        centroLongitud: Double,
        rotacionRad: Double,
        errorMedioM: Double,
        peorAccuracyM: Double
    ) {
        self.centroLatitud = centroLatitud
        self.centroLongitud = centroLongitud
        self.rotacionRad = rotacionRad
        self.errorMedioM = errorMedioM
        self.peorAccuracyM = peorAccuracyM
    }

    public enum Fiabilidad: String, Codable, Sendable {
        /// Las seis zonas de la pista.
        case zonas
        /// Solo "cerca de la red" contra "en el fondo".
        case redOFondo
        /// Nada. No se pinta un mapa con esto.
        case ninguna
    }

    /// Qué se puede enseñar con este error. Ver la cabecera del tipo.
    public var fiabilidad: Fiabilidad {
        switch errorMedioM {
        case ...1.5: return .zonas
        case ...3.0: return .redOFondo
        default: return .ninguna
        }
    }

    /// Lo que se le dice al jugador después de calibrar. Se redacta aquí y no en la
    /// vista para que el reloj y el móvil digan exactamente lo mismo.
    public var veredicto: String {
        switch fiabilidad {
        case .zonas:
            return String(format: "Buena señal: %.1f m de error. ", errorMedioM)
                + "Se pueden separar las seis zonas de la pista."
        case .redOFondo:
            return String(format: "Señal regular: %.1f m de error. ", errorMedioM)
                + "Solo se puede distinguir red de fondo, no el lado."
        case .ninguna:
            return String(format: "Señal insuficiente: %.1f m de error. ", errorMedioM)
                + "En esta pista no se puede situar los golpes, y no se va a inventar."
        }
    }

    /// Las cuatro esquinas de la pista, **en orden**, tal como se le piden al jugador.
    ///
    /// Son las cuatro esquinas del rectángulo de 20×10, o sea los dos fondos — no los
    /// postes de la red. Es un error fácil de cometer y caro: plantarse en los postes
    /// mide un segmento de diez metros, no una pista, y de ahí no sale una rotación sino
    /// un disparate.
    public static let nombresDeEsquina = [
        "Fondo de tu lado, izquierda",
        "Fondo de tu lado, derecha",
        "Fondo contrario, derecha",
        "Fondo contrario, izquierda",
    ]

    /// Pasa una lectura del reloj a coordenadas de la pista, o nil si cae claramente
    /// fuera.
    ///
    /// El margen de 3 m no es generosidad: con el error del GPS, un jugador pegado a la
    /// pared de fondo puede medirse un par de metros fuera, y descartar esa lectura
    /// borraría justo los golpes de defensa.
    public func aPista(_ punto: PuntoGeo) -> PosicionGpsEnPista? {
        let (este, norte) = Self.aMetros(punto, origenLat: centroLatitud, origenLon: centroLongitud)
        // Deshacer el giro de la pista: se rota en sentido contrario.
        let cosR = cos(-rotacionRad)
        let senR = sin(-rotacionRad)
        let x = este * cosR - norte * senR + PosicionGpsEnPista.largo / 2
        let y = este * senR + norte * cosR + PosicionGpsEnPista.ancho / 2

        let margen = 3.0
        if x < -margen || x > PosicionGpsEnPista.largo + margen { return nil }
        if y < -margen || y > PosicionGpsEnPista.ancho + margen { return nil }
        return PosicionGpsEnPista(
            x: min(max(x, 0), PosicionGpsEnPista.largo),
            y: min(max(y, 0), PosicionGpsEnPista.ancho)
        )
    }

    /// Calibra con las cuatro esquinas, en el orden de `nombresDeEsquina` (recorriendo
    /// la pista, no en aspa).
    ///
    /// Devuelve nil con menos de cuatro lecturas: con tres esquinas el rectángulo sale
    /// de una suposición, y una suposición es lo que este fichero existe para evitar.
    public static func de(esquinas: [PuntoGeo]) -> CalibracionGpsDePista? {
        guard esquinas.count == 4 else { return nil }

        let centroLat = esquinas.reduce(0) { $0 + $1.latitud } / 4
        let centroLon = esquinas.reduce(0) { $0 + $1.longitud } / 4
        let medidas = esquinas.map { aMetros($0, origenLat: centroLat, origenLon: centroLon) }

        // El rectángulo ideal, centrado en el origen y en el mismo orden: primero el
        // fondo cercano de izquierda a derecha, luego el contrario de derecha a
        // izquierda.
        let mitadLargo = PosicionGpsEnPista.largo / 2
        let mitadAncho = PosicionGpsEnPista.ancho / 2
        let ideal: [(Double, Double)] = [
            (-mitadLargo, -mitadAncho),
            (-mitadLargo, mitadAncho),
            (mitadLargo, mitadAncho),
            (mitadLargo, -mitadAncho),
        ]

        // Procrustes en 2D sin escala: el ángulo que mejor alinea las dos nubes sale de
        // la suma de productos cruzados contra la de productos escalares.
        var cruz = 0.0
        var escalar = 0.0
        for i in 0..<4 {
            let (mx, my) = medidas[i]
            let (ix, iy) = ideal[i]
            cruz += ix * my - iy * mx
            escalar += ix * mx + iy * my
        }
        let rotacion = atan2(cruz, escalar)

        // Con el giro puesto, lo que quede entre cada esquina medida y su ideal es el
        // error del GPS en esta pista.
        let cosR = cos(rotacion)
        let senR = sin(rotacion)
        var sumaCuadrados = 0.0
        for i in 0..<4 {
            let (ix, iy) = ideal[i]
            let giradoX = ix * cosR - iy * senR
            let giradoY = ix * senR + iy * cosR
            let (mx, my) = medidas[i]
            sumaCuadrados += (giradoX - mx) * (giradoX - mx) + (giradoY - my) * (giradoY - my)
        }

        return CalibracionGpsDePista(
            centroLatitud: centroLat,
            centroLongitud: centroLon,
            rotacionRad: rotacion,
            errorMedioM: (sumaCuadrados / 4).squareRoot(),
            peorAccuracyM: esquinas.map(\.accuracyM).max() ?? 0
        )
    }

    /// Radio medio de la Tierra, en metros.
    private static let radioTierraM = 6_371_000.0

    /// Proyección plana alrededor del origen.
    ///
    /// A escala de veinte metros la curvatura de la Tierra no se nota —el error de esta
    /// aproximación está en los micrómetros—, así que una proyección cilíndrica simple
    /// sobra y evita arrastrar una biblioteca geodésica al reloj.
    static func aMetros(
        _ punto: PuntoGeo, origenLat: Double, origenLon: Double
    ) -> (Double, Double) {
        let radianes = Double.pi / 180
        let norte = (punto.latitud - origenLat) * radianes * radioTierraM
        let este = (punto.longitud - origenLon) * radianes * radioTierraM
            * cos(origenLat * radianes)
        return (este, norte)
    }
}
