import Foundation
import PadelCore

/// El dominio del VIDEO LAB: un vídeo de entrenamiento con sus golpes marcados a mano.
///
/// Esto es verdad-terreno hecha por el ojo humano. El reloj dice "aquí hubo una bandeja"
/// mirando una señal de acelerómetro; el vídeo dice "aquí hubo una bandeja" porque se ve.
/// Cruzar las dos listas es lo que permitirá medir de verdad cuánto acierta el detector,
/// en vez de fiarse de la etiqueta que el jugador puso a la tanda entera.
///
/// Por eso el formato está pensado para salir de la app (`exportar`) y no solo para
/// pintarse en pantalla: el consumidor final es el entrenamiento del clasificador.

/// Quién puso la marca.
///
/// El análisis de vídeo no marca nada: propone. Una marca `propuesta` es una propuesta que
/// el usuario miró y confirmó — sigue siendo suya, pero conviene poder distinguirlas
/// cuando esto se use como verdad-terreno, porque confirmar de un toque es más barato (y
/// por tanto más descuidado) que marcar mirando el vídeo.
enum OrigenDeMarca: String, Codable {
    case manual
    case propuesta
}

/// Un golpe visto en el vídeo, en el segundo en que ocurre.
struct MarcaDeVideo: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Segundos desde el primer fotograma. Con decimales a propósito: un golpe dura
    /// menos de medio segundo y redondear a segundos enteros machacaría dos golpes
    /// seguidos en la misma marca.
    var segundos: Double
    var tipo: ShotType
    var origen: OrigenDeMarca = .manual
    /// La postura del jugador en ese instante, si se ha pasado el análisis de vídeo.
    /// Opcional para siempre: marcar a mano sigue siendo el camino principal y no
    /// requiere análisis ninguno.
    var postura: PosturaDetectada?
    /// Dónde estaba el jugador en la pista al dar ese golpe. Necesita postura **y**
    /// calibración de las esquinas; sin una de las dos, nil — nunca un punto aproximado
    /// "para que el mapa no salga vacío".
    var posicion: PosicionEnPista?

    /// `00:03`, el formato de la línea temporal del documento de producto.
    ///
    /// Los minutos no se recortan a 60: un vídeo de entreno de 75 minutos sale como
    /// `75:12` y no como `15:12`, que sería mentira.
    var tiempo: String {
        let total = Int(segundos.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    init(
        id: UUID = UUID(),
        segundos: Double,
        tipo: ShotType,
        origen: OrigenDeMarca = .manual,
        postura: PosturaDetectada? = nil,
        posicion: PosicionEnPista? = nil
    ) {
        self.id = id
        self.segundos = segundos
        self.tipo = tipo
        self.origen = origen
        self.postura = postura
        self.posicion = posicion
    }

    /// Decodificación tolerante, por lo mismo que en `EtiquetadoDeVideo`: las marcas que
    /// ya están en disco se escribieron antes de que existieran `origen`, `postura` y
    /// `posicion`, y Swift **no** usa los valores por defecto de las propiedades al
    /// decodificar. Sin esto, todos los etiquetados viejos dejarían de abrirse.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        segundos = try c.decodeIfPresent(Double.self, forKey: .segundos) ?? 0
        tipo = (try c.decodeIfPresent(String.self, forKey: .tipo)).map(ShotType.fromWire) ?? .unknown
        origen = (try c.decodeIfPresent(String.self, forKey: .origen))
            .flatMap(OrigenDeMarca.init(rawValue:)) ?? .manual
        // Con `try?`: un bloque de análisis corrupto (una homografía a medias, por
        // ejemplo) puede costar la postura de una marca, pero no el etiquetado entero,
        // que son horas de trabajo manual.
        postura = (try? c.decodeIfPresent(PosturaDetectada.self, forKey: .postura)) ?? nil
        posicion = (try? c.decodeIfPresent(PosicionEnPista.self, forKey: .posicion)) ?? nil
    }
}

/// De dónde salió el instante en que empieza el vídeo.
enum OrigenDelAncla: String, Codable {
    /// La fecha de grabación que trae el propio fichero (metadatos QuickTime).
    case metadatos
    /// La puso el usuario a mano porque el fichero no la traía.
    case manual
    /// Todavía no hay ancla: el vídeo se puede etiquetar igual, pero no se podrá
    /// cruzar con las tandas del reloj.
    case ninguno
}

/// El instante de época (ms) en que ocurre el **primer fotograma** del vídeo.
///
/// Sin esto las marcas son segundos relativos a un fichero y no significan nada fuera de
/// él. Con esto, `ancla + marca.segundos` es un instante de reloj de pared, que es la
/// única moneda común con una tanda del reloj (`TandaCruda.startedAtEpochMs + offsetMs`).
struct AnclaDeVideo: Codable, Equatable {
    var epochMs: Int64?
    var origen: OrigenDelAncla = .ninguno

    var fecha: Date? {
        epochMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }

    static let sinFijar = AnclaDeVideo()
}

/// Un vídeo importado al laboratorio, con su línea temporal de golpes.
struct EtiquetadoDeVideo: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Lo que el usuario llama a este vídeo. Editable: el nombre que da el carrete
    /// (`IMG_4312.MOV`) no dice nada dentro de tres semanas.
    var nombre: String
    /// Nombre del fichero dentro de la carpeta de medios, **no** una URL completa: el
    /// contenedor de la app cambia de ruta en cada actualización, así que una URL
    /// absoluta guardada en disco deja de resolver y el vídeo "desaparece".
    var fichero: String
    /// Segundos de vídeo. Se guarda al importar para no tener que abrir el asset solo
    /// para pintar la lista.
    var duracion: Double = 0
    /// El golpe que el usuario dice que contiene el vídeo ("este vídeo contiene
    /// bandejas"). Es el tipo por defecto de cada marca nueva.
    var tipo: ShotType = .bandeja
    var marcas: [MarcaDeVideo] = []
    /// Cuándo se importó, en ms de época. Ordena la lista.
    var creado: Int64
    var ancla = AnclaDeVideo.sinFijar
    /// La sesión del reloj que se grabó en este vídeo, si se ha enlazado.
    ///
    /// Es lo que convierte el laboratorio en algo usable: con la sesión enlazada, los
    /// golpes y sus tipos los pone el reloj y no la mano del usuario. Nil = vídeo
    /// suelto, que sigue siendo válido y se marca a mano como siempre.
    var sesionId: String?
    /// Cuánto va por delante el reloj respecto al vídeo, en ms. Ver
    /// `SincronizacionDeVideo`: la hora del fichero y la del reloj no son la misma.
    var desfaseMs: Int64 = 0
    /// Corrección de deriva entre los dos relojes. 1 = sin corregir, que es lo que sale
    /// de una sola claqueta o del ajuste automático.
    var escala: Double = 1
    /// Versión del formato exportado, como en `TandaCruda`: quien lea el JSON más
    /// adelante tiene que poder distinguir de qué generación viene.
    var formato = 1

    /// Las marcas siempre en orden de reproducción: la línea temporal se lee de arriba
    /// abajo y marcar un golpe que se te pasó (rebobinando) no puede colarse al final.
    var marcasOrdenadas: [MarcaDeVideo] {
        marcas.sorted { $0.segundos < $1.segundos }
    }

    init(
        id: UUID = UUID(),
        nombre: String,
        fichero: String,
        duracion: Double = 0,
        tipo: ShotType = .bandeja,
        marcas: [MarcaDeVideo] = [],
        creado: Int64,
        ancla: AnclaDeVideo = .sinFijar,
        sesionId: String? = nil,
        desfaseMs: Int64 = 0,
        escala: Double = 1,
        formato: Int = 1
    ) {
        self.id = id
        self.nombre = nombre
        self.fichero = fichero
        self.duracion = duracion
        self.tipo = tipo
        self.marcas = marcas
        self.creado = creado
        self.ancla = ancla
        self.sesionId = sesionId
        self.desfaseMs = desfaseMs
        self.escala = escala
        self.formato = formato
    }

    /// Decodificación tolerante, como en la liga: el fichero del laboratorio se escribe
    /// una y otra vez a lo largo de meses y un campo que se añada mañana no puede dejar
    /// ilegibles los etiquetados de hoy — que son horas de marcar a mano.
    ///
    /// Swift **no** usa los valores por defecto de las propiedades al decodificar: hay
    /// que escribir el `decodeIfPresent` a mano, campo a campo.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nombre = try c.decodeIfPresent(String.self, forKey: .nombre) ?? "Vídeo"
        fichero = try c.decodeIfPresent(String.self, forKey: .fichero) ?? ""
        duracion = try c.decodeIfPresent(Double.self, forKey: .duracion) ?? 0
        // Por `fromWire` y no por el `Codable` del enum: así un tipo que ya no exista
        // (o el "overhead" de las sesiones viejas) cae en algo válido en vez de tirar
        // el etiquetado entero.
        tipo = (try c.decodeIfPresent(String.self, forKey: .tipo)).map(ShotType.fromWire) ?? .bandeja
        marcas = try c.decodeIfPresent([MarcaDeVideo].self, forKey: .marcas) ?? []
        creado = try c.decodeIfPresent(Int64.self, forKey: .creado) ?? 0
        ancla = try c.decodeIfPresent(AnclaDeVideo.self, forKey: .ancla) ?? .sinFijar
        sesionId = try c.decodeIfPresent(String.self, forKey: .sesionId)
        desfaseMs = try c.decodeIfPresent(Int64.self, forKey: .desfaseMs) ?? 0
        escala = try c.decodeIfPresent(Double.self, forKey: .escala) ?? 1
        formato = try c.decodeIfPresent(Int.self, forKey: .formato) ?? 1
    }

    // MARK: Sincronización con el reloj

    /// El instante de época de una marca, o nil si el vídeo todavía no tiene ancla.
    ///
    /// Es la mitad del puente hacia el reloj. La otra mitad ya existe en PadelCore: una
    /// `TandaCruda` guarda `startedAtEpochMs` y cada golpe suyo un `offsetMs`, así que
    /// el golpe del reloj también se puede expresar en época. Casar las dos listas es
    /// emparejar instantes cercanos.
    ///
    /// LO QUE FALTA para cerrar la sincronización (a propósito, no está hecho aquí):
    ///
    /// 1. **Precisión del ancla.** La fecha de grabación del fichero tiene resolución de
    ///    segundo y es la del móvil que grabó, que no es el reloj que llevaba el jugador.
    ///    Un desfase de 1-2 s ya desordena golpes que van a 1,5 s uno de otro. Hace falta
    ///    un gesto de claqueta: empezar la tanda con un golpe seco y evidente, marcarlo en
    ///    el vídeo y usar ese par (marca, golpe del reloj) para estimar el desfase real.
    /// 2. **Deriva.** Los relojes de iPhone y Apple Watch no corren exactamente igual, y
    ///    en 20 minutos de vídeo la diferencia se nota. Con dos claquetas (principio y
    ///    final) se estima además de desfase una escala; con una sola, solo desfase.
    /// 3. **El emparejador.** Una función que, dados el etiquetado y una `TandaCruda`,
    ///    devuelva pares (marca de vídeo, golpe del reloj) por cercanía dentro de una
    ///    ventana —del orden de ±300 ms una vez corregido el desfase— y deje fuera los
    ///    golpes que el reloj no vio y las marcas que el reloj se inventó. Ese es el
    ///    informe que de verdad mide el detector.
    /// 4. **Dónde vive.** El emparejador es lógica de dominio y debería acabar en
    ///    PadelCore (junto a `DetectorAccuracy`) para que el core Kotlin pueda hacer lo
    ///    mismo, no en la capa de vistas.
    ///
    /// Nada de esto necesita visión artificial: el ojo del usuario ya pone la etiqueta.
    func epochMs(de marca: MarcaDeVideo) -> Int64? {
        guard let inicio = ancla.epochMs else { return nil }
        return inicio + Int64((marca.segundos * 1000).rounded())
    }

    /// El instante de época en que termina el vídeo, para acotar qué tandas pueden
    /// solaparse con él sin tener que abrirlas todas.
    var finEpochMs: Int64? {
        guard let inicio = ancla.epochMs else { return nil }
        return inicio + Int64((duracion * 1000).rounded())
    }

    // MARK: Enlazar con una sesión del reloj

    /// Si esta sesión del reloj pudo grabarse en este vídeo: que se solapen en el tiempo.
    ///
    /// El margen es generoso (un minuto por cada lado) porque el ancla del fichero tiene
    /// resolución de segundo y la sesión se arranca y se para a mano: pedir solape exacto
    /// descartaría justo los casos buenos.
    func puedeSer(_ sesion: PadelSession, margenMs: Int64 = 60_000) -> Bool {
        guard let inicio = ancla.epochMs, let fin = finEpochMs else { return false }
        let finSesion = sesion.startedAtEpochMs + sesion.durationSeconds * 1000
        return sesion.startedAtEpochMs <= fin + margenMs && finSesion >= inicio - margenMs
    }

    /// Los golpes de una sesión en tiempo de reloj de pared, para dárselos al emparejador.
    static func golpesDelReloj(_ sesion: PadelSession) -> [SincronizacionDeVideo.GolpeEnTiempo] {
        sesion.shots.map {
            SincronizacionDeVideo.GolpeEnTiempo(
                epochMs: sesion.startedAtEpochMs + $0.offsetMs, tipo: $0.type
            )
        }
    }

    /// Las marcas de este vídeo en tiempo de reloj de pared. Vacío sin ancla.
    var marcasEnTiempo: [SincronizacionDeVideo.GolpeEnTiempo] {
        guard ancla.epochMs != nil else { return [] }
        return marcasOrdenadas.compactMap { marca in
            epochMs(de: marca).map {
                SincronizacionDeVideo.GolpeEnTiempo(epochMs: $0, tipo: marca.tipo)
            }
        }
    }

    /// Qué segundo del vídeo le toca a un instante del reloj, con el desfase y la escala
    /// de este etiquetado aplicados. Nil sin ancla, o si cae fuera del vídeo.
    func segundosDeVideo(paraEpoch epochMs: Int64) -> Double? {
        guard let inicio = ancla.epochMs, escala != 0 else { return nil }
        // Inversa de lo que hace `SincronizacionDeVideo.cruzar`: allí el vídeo se estira
        // y se desplaza hasta el reloj; aquí se deshace para volver al fichero.
        let enVideoEpoch = Double(epochMs - desfaseMs) / escala
        let segundos = (enVideoEpoch - Double(inicio)) / 1000
        guard segundos >= -0.5, segundos <= duracion + 0.5 else { return nil }
        return max(segundos, 0)
    }

    /// **Trae los golpes del reloj como marcas de este vídeo.**
    ///
    /// Es el botón entero: donde antes había que ver el vídeo y marcar trescientos golpes
    /// a mano, la sesión los pone con su tipo y su instante.
    ///
    /// Dos decisiones que importan:
    ///
    /// **No se pisa nada marcado a mano.** Un golpe del reloj que cae encima de una marca
    /// que ya existe se salta: lo que puso el ojo humano manda sobre lo que puso una señal
    /// de acelerómetro, que es justo el motivo de que este laboratorio exista.
    ///
    /// **Las marcas traídas nacen como `propuesta`**, no como `manual`. Vienen de un
    /// detector con su porcentaje de error, así que no son verdad-terreno: son un punto de
    /// partida que el usuario confirma o corrige. Mezclarlas con las suyas sin distinguir
    /// contaminaría el corpus con el que luego se entrena el clasificador, y el corpus
    /// quedaría midiéndose contra sí mismo.
    ///
    /// - Returns: cuántas marcas nuevas se añadieron.
    @discardableResult
    mutating func traerGolpes(
        de sesion: PadelSession,
        ventanaDeDuplicadoSegundos: Double = 0.4
    ) -> Int {
        guard ancla.epochMs != nil else { return 0 }
        var añadidas = 0
        for golpe in Self.golpesDelReloj(sesion) {
            guard let segundos = segundosDeVideo(paraEpoch: golpe.epochMs) else { continue }
            let yaEsta = marcas.contains { abs($0.segundos - segundos) < ventanaDeDuplicadoSegundos }
            if yaEsta { continue }
            marcas.append(
                MarcaDeVideo(
                    segundos: segundos,
                    tipo: golpe.tipo ?? .unknown,
                    origen: .propuesta
                )
            )
            añadidas += 1
        }
        return añadidas
    }
}
