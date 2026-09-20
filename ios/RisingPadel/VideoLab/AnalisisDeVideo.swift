import CoreGraphics
import Foundation

/// Lo que el VIDEO LAB saca de un vídeo con visión artificial, y —tan importante como
/// eso— lo que **no** saca.
///
/// QUÉ SE DETECTA DE VERDAD
///
/// 1. **Personas y su postura**, con `VNDetectHumanBodyPoseRequest` (framework Vision,
///    en el dispositivo, sin red). Devuelve articulaciones en coordenadas normalizadas
///    con una confianza por punto. Funciona razonablemente con el jugador entero en
///    cuadro y luz de día; con un jugador de fondo, pequeño en la imagen, las muñecas y
///    los tobillos bajan de 0,3 de confianza y dejan de servir.
/// 2. **Posición de los pies en la pista**, proyectando los tobillos con la homografía
///    que sale de la calibración manual de las cuatro esquinas (ver `Homografia`). El
///    error típico es de decenas de centímetros cerca de la cámara y crece hasta el metro
///    largo en el fondo contrario, porque allí un píxel cubre mucho más suelo.
/// 3. **Candidatos a golpe** por picos de velocidad de muñeca. Son *propuestas* para que
///    el usuario las confirme o las tire, nunca marcas dadas por buenas.
///
/// QUÉ NO SE HACE, Y POR QUÉ NO ESTÁ FINGIDO
///
/// - **Seguimiento de la pelota: no está, y no es un descuido.** Una pelota de pádel a
///   100 km/h recorre unos 28 m/s; en un vídeo de móvil a 30 fps eso es casi un metro
///   entre fotograma y fotograma, y con el obturador normal de un iPhone sale como una
///   raya borrosa de unos pocos píxeles —cuando no desaparece directamente contra el
///   cristal, la pared verde o la propia línea de la pista. Vision **no trae** ningún
///   detector de pelota (`VNDetectTrajectoriesRequest` detecta trayectorias de objetos en
///   movimiento sobre cámara fija y está pensado para lanzamientos lentos y limpios; en
///   pádel devuelve trayectorias de brazos, sombras y reflejos con el mismo aplomo que
///   las de la pelota) y entrenar un detector propio necesitaría miles de fotogramas
///   etiquetados a mano que no existen. Un detector de manchas ajustado a ojo daría
///   posiciones de pelota inventadas que **parecen** datos: velocidades, alturas de bote,
///   mapas de impacto. Eso es exactamente lo que el documento de producto prohíbe. Se
///   queda fuera hasta que haya un modelo entrenado y medido.
/// - **Clasificar el tipo de golpe desde el vídeo: tampoco.** No hay modelo entrenado
///   para distinguir bandeja de víbora ni derecha de revés a partir de la postura, y la
///   diferencia entre esos golpes está en la muñeca y en el plano de la pala, que son
///   justo lo que una postura de 19 puntos no resuelve. Lo único que se puede decir con
///   honestidad mirando las articulaciones es si la muñeca estaba **por encima o por
///   debajo del hombro** (`PosturaDetectada.brazoPorEncimaDelHombro`), y eso se enseña
///   como lo que es: una pista, no una clasificación. El tipo de cada marca lo sigue
///   poniendo el usuario.
/// - **Quién es quién.** En una pista hay cuatro jugadores. El seguidor elige uno y lo
///   mantiene por cercanía entre fotogramas; cuando dos se cruzan puede cambiar de
///   persona sin avisar. Por eso cada resultado lleva confianza y todo es corregible.

// MARK: Punto de imagen

/// Un punto de la postura en coordenadas **normalizadas de la imagen ya orientada**:
/// 0-1 en cada eje, origen arriba-izquierda.
///
/// Vision las da con el origen abajo-izquierda; se voltean una sola vez, al detectar, para
/// que estos puntos y los toques del usuario en la pantalla de calibración vivan en el
/// mismo sistema. Tener dos convenios de `y` dando vueltas por el módulo es el fallo que
/// acaba con el mapa de pista del revés y nadie sabe dónde.
struct PuntoDeImagen: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    /// La que da Vision para ese punto, 0-1.
    var confianza: Double

    var cg: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: Postura

/// La postura de un jugador en un instante del vídeo.
///
/// Solo se guardan seis articulaciones de las diecinueve que da Vision, a propósito: son
/// las únicas que consume algo (muñecas → candidatos a golpe; tobillos → posición en
/// pista; hombros → la pista de brazo arriba/abajo). Guardar las diecinueve multiplicaría
/// por tres el peso del JSON del laboratorio sin que nada lo leyera.
struct PosturaDetectada: Codable, Equatable, Sendable {
    /// Por debajo de esto un punto de Vision es ruido: coloca articulaciones en la valla.
    static let confianzaMinimaDePunto: Double = 0.1
    /// Para proyectar un tobillo al suelo hace falta bastante más: un tobillo a 0,2 se
    /// mueve medio metro entre fotogramas y la posición en pista saldría bailando.
    static let confianzaMinimaDeTobillo: Double = 0.3

    var segundos: Double
    var munecaIzquierda: PuntoDeImagen?
    var munecaDerecha: PuntoDeImagen?
    var tobilloIzquierdo: PuntoDeImagen?
    var tobilloDerecho: PuntoDeImagen?
    var hombroIzquierdo: PuntoDeImagen?
    var hombroDerecho: PuntoDeImagen?
    /// Cuántas personas vio Vision en ese fotograma. Se guarda porque explica los fallos:
    /// con cuatro personas en cuadro, el seguidor puede haber cambiado de jugador.
    var personas: Int = 1

    /// La muñeca que más confianza tiene en este fotograma.
    ///
    /// No se usa la mano hábil del perfil del jugador: el vídeo puede ser de otra persona,
    /// y en un golpe a dos manos manda la que Vision vea mejor.
    var munecaFiable: PuntoDeImagen? {
        let candidatas = [munecaIzquierda, munecaDerecha].compactMap { $0 }
        return candidatas.max { $0.confianza < $1.confianza }
    }

    /// El punto del suelo entre los dos pies, ponderado por confianza, o el único tobillo
    /// visible si solo hay uno.
    ///
    /// Es una aproximación: el punto de apoyo real durante un golpe no está entre los dos
    /// pies, y Vision marca el tobillo, no la planta. Con una cámara a la altura de la
    /// cabeza eso son del orden de 10-15 cm de sesgo hacia el fondo. Se asume y se dice.
    var pies: PuntoDeImagen? {
        let tobillos = [tobilloIzquierdo, tobilloDerecho]
            .compactMap { $0 }
            .filter { $0.confianza >= Self.confianzaMinimaDeTobillo }
        guard !tobillos.isEmpty else { return nil }
        let peso = tobillos.reduce(0) { $0 + $1.confianza }
        guard peso > 0 else { return nil }
        return PuntoDeImagen(
            x: tobillos.reduce(0) { $0 + $1.x * $1.confianza } / peso,
            y: tobillos.reduce(0) { $0 + $1.y * $1.confianza } / peso,
            confianza: peso / Double(tobillos.count)
        )
    }

    /// Si la muñeca estaba por encima del hombro del mismo lado.
    ///
    /// **Esto no clasifica el golpe.** Dice si el brazo iba alto (bandeja, víbora, remate,
    /// saque) o bajo (derecha, revés, volea baja), que es todo lo que una postura permite
    /// afirmar sin un modelo entrenado. Nil cuando faltan los puntos, que es mejor que un
    /// falso "abajo" por no haber visto el hombro.
    var brazoPorEncimaDelHombro: Bool? {
        var mejor: (muneca: PuntoDeImagen, hombro: PuntoDeImagen)?
        for (muneca, hombro) in [
            (munecaIzquierda, hombroIzquierdo),
            (munecaDerecha, hombroDerecho),
        ] {
            guard let muneca, let hombro,
                  muneca.confianza >= 0.3, hombro.confianza >= 0.3 else { continue }
            if muneca.confianza > (mejor?.muneca.confianza ?? 0) {
                mejor = (muneca: muneca, hombro: hombro)
            }
        }
        guard let mejor else { return nil }
        // `y` crece hacia abajo (origen arriba-izquierda), así que "más arriba" es menor.
        return mejor.muneca.y < mejor.hombro.y
    }
}

// MARK: Posición en pista

/// Dónde estaba el jugador, en metros de pista (ver `PistaDePadel`).
struct PosicionEnPista: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    /// Heredada de los tobillos que la produjeron. No mide el error en metros —mide
    /// cuánto se fía Vision de haber visto los pies—, y así hay que enseñarla.
    var confianza: Double
    /// Si cae dentro de la pista con margen. Fuera no se tira: el jugador se sale a
    /// buscar la pared, y además una posición fuera es la señal de que la calibración
    /// está mal.
    var dentro: Bool

    /// Distancia a la red, que es la lectura táctica que de verdad se usa ("juegas
    /// demasiado en la media pista").
    var distanciaALaRed: Double { abs(x - PistaDePadel.red) }

    /// Proyecta los pies de una postura al suelo de la pista.
    ///
    /// Nil si no hay tobillos fiables, si la homografía manda el punto al infinito o si
    /// el resultado cae absurdamente lejos (más de 3 m fuera): eso no es un jugador
    /// pisando fuera, es una detección mala o una calibración mal hecha, y colarla en el
    /// mapa sería inventar.
    static func desde(_ postura: PosturaDetectada, con homografia: Homografia) -> PosicionEnPista? {
        guard let pies = postura.pies,
              let metros = homografia.aplicar(pies.cg),
              PistaDePadel.dentro(metros, margen: 3) else { return nil }
        return PosicionEnPista(
            x: Double(metros.x),
            y: Double(metros.y),
            confianza: pies.confianza,
            dentro: PistaDePadel.dentro(metros)
        )
    }
}

// MARK: Calibración

/// Las cuatro esquinas de la pista tocadas a mano sobre un fotograma, y la homografía que
/// sale de ellas.
///
/// Se guardan las dos cosas: las esquinas porque son el dato original y hay que poder
/// reeditarlas, y la matriz porque quien lea el JSON exportado no tiene por qué rehacer el
/// álgebra para entenderlo.
///
/// **Vale mientras la cámara no se mueva.** El móvil apoyado en la valla es el caso normal
/// y aguanta; si alguien coge el móvil a media grabación, la calibración deja de valer a
/// partir de ahí y no hay forma de detectarlo automáticamente. Por eso la pantalla de
/// calibración pinta las líneas de la pista sobre el fotograma: es una comprobación a ojo
/// que el usuario puede repetir en cualquier segundo del vídeo.
struct CalibracionDePista: Codable, Equatable, Sendable {
    /// Normalizadas 0-1, origen arriba-izquierda, en el orden de `PistaDePadel.esquinas`.
    var esquinas: [CGPoint]
    /// Imagen → metros de pista.
    var homografia: Homografia
    /// De qué segundo del vídeo se sacó el fotograma, para poder volver a él.
    var segundoDelFotograma: Double
    var hecha: Int64

    /// Nil cuando las esquinas no definen una pista: menos de cuatro, cruzadas, o
    /// alineadas. Antes de guardar basura, nada.
    init?(esquinas: [CGPoint], segundoDelFotograma: Double, hecha: Int64) {
        guard esquinas.count == 4,
              Homografia.esConvexo(esquinas),
              let h = Homografia(origen: esquinas, destino: PistaDePadel.esquinas) else { return nil }
        self.esquinas = esquinas
        self.homografia = h
        self.segundoDelFotograma = segundoDelFotograma
        self.hecha = hecha
    }

    /// La transformación contraria (metros → imagen), para pintar las líneas de la pista
    /// encima del fotograma y poder comprobar la calibración a ojo.
    ///
    /// Se resuelve otra vez desde los mismos cuatro pares en vez de invertir la matriz:
    /// son cuatro puntos y ocho ecuaciones, cuesta microsegundos, y ahorra escribir (y
    /// revisar) una inversión de 3×3 que solo se usaría aquí.
    var aImagen: Homografia? {
        Homografia(origen: PistaDePadel.esquinas, destino: esquinas)
    }
}

// MARK: Candidatos

/// Un instante en el que el análisis **cree** que puede haber un golpe.
///
/// No es una marca. Entra en la lista de propuestas y solo se convierte en marca cuando el
/// usuario la confirma, eligiendo además el tipo de golpe —que el vídeo no sabe.
struct CandidatoAGolpe: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var segundos: Double
    /// Cuánto destaca el pico de velocidad de la muñeca sobre el movimiento normal de
    /// este vídeo, en veces la mediana.
    ///
    /// **No es una probabilidad**, y no se va a enseñar como un porcentaje. Un 6× dice
    /// "aquí la muñeca iba seis veces más rápida de lo habitual", que en un vídeo de
    /// tandas suele ser un golpe y en un vídeo con gente pasando por delante puede ser
    /// cualquier cosa.
    var prominencia: Double
    /// La confianza de Vision en la muñeca que produjo el pico.
    var confianzaPostura: Double
    var postura: PosturaDetectada?
    var posicion: PosicionEnPista?

    /// Mismo formato que `MarcaDeVideo.tiempo`, para que la lista de propuestas y la línea
    /// temporal se lean igual.
    var tiempo: String {
        let total = Int(max(0, segundos).rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: Resultado

/// El resumen de una pasada de análisis sobre un vídeo.
///
/// Lo que **no** guarda: la secuencia completa de posturas. Un vídeo de 15 minutos
/// muestreado a 12 Hz son ~10.800 posturas; en JSON, varios megas que habría que reescribir
/// entero en cada cambio del laboratorio (el almacén guarda todo el fichero de una vez).
/// Se conserva lo que tiene consumidor: la postura del instante de cada marca, la de cada
/// candidato, y estas cifras de calidad. Si alguien necesita la secuencia entera, se
/// vuelve a analizar.
struct ResultadoDeAnalisis: Codable, Equatable, Sendable {
    var hecho: Int64
    var muestreoHz: Double
    /// Fotogramas efectivamente pasados por Vision (no los del vídeo: se muestrea).
    var fotogramasAnalizados: Int
    /// De esos, en cuántos se encontró a alguien. La proporción es la medida honesta de
    /// si este vídeo sirve: por debajo de la mitad, el jugador sale demasiado lejos o
    /// demasiado a contraluz y lo que salga de aquí no vale gran cosa.
    var fotogramasConPostura: Int
    /// El máximo de personas que Vision vio a la vez. Con más de una, el seguimiento del
    /// jugador puede haberse cambiado de persona.
    var personasMaximas: Int
    var candidatos: [CandidatoAGolpe] = []
    /// Generación del análisis, por si cambia el muestreo o el detector: un resultado
    /// viejo tiene que poder reconocerse para no compararlo con uno nuevo.
    var version: Int = 1

    var cobertura: Double {
        fotogramasAnalizados > 0
            ? Double(fotogramasConPostura) / Double(fotogramasAnalizados)
            : 0
    }

    /// Decodificación tolerante, por la misma razón que en `EtiquetadoDeVideo`: este
    /// bloque se añadió después y va a seguir creciendo.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hecho = try c.decodeIfPresent(Int64.self, forKey: .hecho) ?? 0
        muestreoHz = try c.decodeIfPresent(Double.self, forKey: .muestreoHz) ?? 0
        fotogramasAnalizados = try c.decodeIfPresent(Int.self, forKey: .fotogramasAnalizados) ?? 0
        fotogramasConPostura = try c.decodeIfPresent(Int.self, forKey: .fotogramasConPostura) ?? 0
        personasMaximas = try c.decodeIfPresent(Int.self, forKey: .personasMaximas) ?? 0
        candidatos = try c.decodeIfPresent([CandidatoAGolpe].self, forKey: .candidatos) ?? []
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    init(
        hecho: Int64,
        muestreoHz: Double,
        fotogramasAnalizados: Int,
        fotogramasConPostura: Int,
        personasMaximas: Int,
        candidatos: [CandidatoAGolpe] = [],
        version: Int = 1
    ) {
        self.hecho = hecho
        self.muestreoHz = muestreoHz
        self.fotogramasAnalizados = fotogramasAnalizados
        self.fotogramasConPostura = fotogramasConPostura
        self.personasMaximas = personasMaximas
        self.candidatos = candidatos
        self.version = version
    }
}
