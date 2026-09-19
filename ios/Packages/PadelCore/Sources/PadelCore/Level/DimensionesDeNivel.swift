import Foundation

/// Las dimensiones del nivel que **se pueden sostener con lo que miden los sensores**.
///
/// El enum existe para que la UI pinte solo los ejes que tienen dato: una rueda de seis
/// radios con dos huecos es honesta; una de ocho con dos radios inventados, no.
public enum DimensionDeNivel: String, CaseIterable, Sendable {
    case ataque
    case defensa
    case juegoDeRed
    case juegoDeFondo
    case consistencia
    case rendimientoFisico

    public var etiqueta: String {
        switch self {
        case .ataque: return "Ataque"
        case .defensa: return "Defensa"
        case .juegoDeRed: return "Juego de red"
        case .juegoDeFondo: return "Juego de fondo"
        case .consistencia: return "Consistencia"
        case .rendimientoFisico: return "Rendimiento físico"
        }
    }
}

/// El nivel de una sesión abierto por dimensiones, todas en la misma escala 1-7.
///
/// Un número global dice poco: saber que el juego de red va dos puntos por debajo del de
/// fondo dice qué entrenar. Cada dimensión es `nil` cuando la sesión no trae evidencia
/// suficiente, y un `nil` se enseña como hueco, nunca como cero.
///
/// ### Lo que el producto pide y aquí no está, a propósito
///
/// **Toma de decisiones: no se implementa.** No es una dimensión que falte por hacer, es
/// una dimensión que este hardware **no puede medir**. Decidir bien en pádel es elegir el
/// golpe adecuado para dónde está la bola, dónde están los rivales y dónde está tu
/// compañero; un acelerómetro y un giróscopo en una muñeca no ven ninguna de las tres
/// cosas. Ven que el brazo se movió así de rápido y describió este arco — y con eso se
/// puede saber cómo se ejecutó un golpe, jamás si tocaba jugarlo. Cualquier número que
/// pusiéramos aquí sería una función de la velocidad y el arco con una etiqueta que
/// promete otra cosa, que es la peor clase de mentira: la que parece un dato. Se queda
/// fuera hasta que haya una fuente que vea la pista (vídeo, o bola instrumentada).
///
/// **Técnica: no se duplica.** Sería `SessionLevel.overall` con otro nombre. El estimador
/// puntúa exactamente dos cosas —velocidad de pala y forma del swing— y las dos son
/// técnica de ejecución; no hay ningún otro ingrediente del que separarla. Enseñar
/// "técnica 4,2" al lado de "nivel 4,2" no añade información, añade la sospecha de que
/// son medidas distintas. La técnica **es** el nivel global; la UI que quiera un eje de
/// técnica debe pintar `session.level.overall`.
///
/// **El saque no entra en ninguna dimensión.** No es juego de fondo —no es un peloteo— ni
/// juego de red, y en pádel es un golpe de inicio que se juega a media pista. Meterlo en
/// cualquiera de las dos ensuciaría esa dimensión sin dar ninguna a cambio. Su nota sigue
/// disponible tal cual en `SessionLevel.byShotType`.
public struct DimensionesDeNivel: Equatable, Sendable {

    /// Notas de smash, víbora y bandeja: los golpes con los que se ataca.
    ///
    /// La bandeja entra aquí aunque sea un golpe de control porque es la respuesta al
    /// globo del rival y se juega desde la posición atacante — con ella no se ataca, se
    /// **sostiene** el ataque, y sin ella la dimensión se quedaría en los remates sueltos
    /// de una sesión. Su banda ya premia el control y no la fuerza (ver `LevelConfig`),
    /// así que incluirla no infla la nota.
    public let ataque: Float?

    /// Notas de los globos. El globo es **el** golpe defensivo del pádel: es con lo que se
    /// sale de una bola apurada y se recupera la red.
    ///
    /// Mide la ejecución del globo, no la defensa como concepto: la lectura de la pared,
    /// la colocación y el aguante no los ve el reloj. Y dentro del propio globo, lo que lo
    /// hace bueno —altura y profundidad— tampoco se mide; lo que se mide es el recorrido
    /// limpio a poca velocidad, que es el rasgo del globo bien pegado que sí llega al
    /// giróscopo.
    public let defensa: Float?

    /// Notas de las dos voleas.
    ///
    /// Solo las voleas: bandeja, víbora y smash también se juegan en la red, pero cuentan
    /// en `ataque` y **una sola vez**. Si un golpe alimentara dos dimensiones, las dos
    /// serían casi el mismo número con dos nombres y la rueda mentiría sobre lo
    /// independientes que son sus ejes.
    public let juegoDeRed: Float?

    /// Notas de derecha y revés: el peloteo desde el fondo de la pista.
    public let juegoDeFondo: Float?

    /// La regularidad que ya calcula el estimador (`SessionLevel.consistency`), reescalada
    /// de 0-1 a 1-7.
    ///
    /// No es una medida nueva y no se recalcula aquí: sería el mismo número dos veces con
    /// riesgo de que se separaran al tocar uno. Solo se reescala, y se reescala porque las
    /// seis dimensiones se pintan en el mismo eje — un radar con cinco radios de 1 a 7 y
    /// uno de 0 a 1 se lee mal. Quien quiera el valor crudo lo tiene en
    /// `SessionLevel.consistency`.
    public let consistencia: Float?

    /// Cuánto esfuerzo sostuvo el jugador, a partir del reparto por zonas de pulso.
    ///
    /// Nil sin permiso de salud: sin pulso no hay absolutamente nada que decir aquí.
    ///
    /// Ojo con el nombre, que es el del documento de producto y promete más de lo que da:
    /// **no mide la forma física del jugador**, mide la intensidad a la que jugó esta
    /// sesión. Para hablar de forma física haría falta comparar el mismo esfuerzo con su
    /// propio pulso a lo largo de meses, que es otra función y otra pantalla.
    public let rendimientoFisico: Float?

    public init(
        ataque: Float? = nil,
        defensa: Float? = nil,
        juegoDeRed: Float? = nil,
        juegoDeFondo: Float? = nil,
        consistencia: Float? = nil,
        rendimientoFisico: Float? = nil
    ) {
        self.ataque = ataque
        self.defensa = defensa
        self.juegoDeRed = juegoDeRed
        self.juegoDeFondo = juegoDeFondo
        self.consistencia = consistencia
        self.rendimientoFisico = rendimientoFisico
    }

    public func valor(_ dimension: DimensionDeNivel) -> Float? {
        switch dimension {
        case .ataque: return ataque
        case .defensa: return defensa
        case .juegoDeRed: return juegoDeRed
        case .juegoDeFondo: return juegoDeFondo
        case .consistencia: return consistencia
        case .rendimientoFisico: return rendimientoFisico
        }
    }

    /// Solo las dimensiones con dato, en el orden del enum y no en el de un diccionario:
    /// la rueda de un partido tiene que leerse igual siempre. Es lo que debe pintar la UI.
    public var medidas: [(DimensionDeNivel, Float)] {
        DimensionDeNivel.allCases.compactMap { dimension in
            guard let nota = self.valor(dimension) else { return nil }
            return (dimension, nota)
        }
    }

    /// Si no hay ni una dimensión, no hay rueda que pintar: mejor no enseñar el bloque.
    public var hayAlgoQueEnsenar: Bool { !medidas.isEmpty }

    // MARK: - Cálculo

    /// Los golpes con los que se ataca. Ver `ataque`.
    public static let golpesDeAtaque: [ShotType] = [.smash, .vibora, .bandeja]

    /// El globo, con sus dos lados. Ver `defensa`.
    public static let golpesDeDefensa: [ShotType] = [.forehandLob, .backhandLob]

    public static let golpesDeRed: [ShotType] = [.forehandVolley, .backhandVolley]

    public static let golpesDeFondo: [ShotType] = [.forehand, .backhand]

    /// Por debajo de esto una sesión no dice nada del esfuerzo sostenido.
    ///
    /// Un partido de pádel dura entre una hora y hora y media; veinte minutos es el
    /// calentamiento. Medir "cuánto aguantó" en un rato que no exige aguantar nada daría
    /// notas altísimas a quien solo peloteó fuerte cinco minutos.
    public static let minSegundosParaFisico: Int64 = 20 * 60

    /// Intensidad representativa de cada zona, como fracción de la FC máxima.
    ///
    /// Son los puntos medios de las bandas que define `HeartRateZones.zone(for:maxHeartRate:)`
    /// (z2 = 60-70 %, z3 = 70-80 %, z4 = 80-90 %). Las dos zonas abiertas por arriba y por
    /// abajo llevan un representante prudente: a z1 se le da 0,55 y no 0,30 porque en
    /// pista, entre punto y punto, el pulso baja poco; y a z5 se le da 0,93 y no 1,00
    /// porque estar en z5 es pasar del 90 %, no estar clavado en el máximo.
    public static let intensidadDeZona: [String: Float] = [
        "z1": 0.55,
        "z2": 0.65,
        "z3": 0.75,
        "z4": 0.85,
        "z5": 0.93,
    ]

    /// Los dos extremos de la escala física, en fracción de FC máxima.
    ///
    /// Una sesión entera por debajo del 55 % es un paseo (nivel 1); sostener el 90 % de la
    /// FC máxima durante todo un partido es de jugador muy en forma jugando muy en serio
    /// (nivel 7). Igual que las bandas de golpeo, **son estimaciones razonadas y no
    /// medidas contra jugadores de nivel conocido**: se calibran con el mismo
    /// procedimiento descrito en `docs/level.md`.
    public static let fcMaxNivel1: Float = 0.55
    public static let fcMaxNivel7: Float = 0.90

    /// La fracción de la sesión que tiene que venir con pulso para fiarse del reparto por
    /// zonas.
    ///
    /// Si el reloj solo midió pulso en diez minutos de una hora, ese reparto describe diez
    /// minutos, no la sesión, y esos diez minutos suelen ser justo los del principio — los
    /// más suaves. Con menos cobertura que esto no se reporta.
    public static let minCoberturaDePulso: Float = 0.5

    /// Las dimensiones de `sesion`, cada una nil si no hay con qué sostenerla.
    ///
    /// Se apoya en `LevelEstimator` y no reimplementa ninguna nota: si mañana cambia la
    /// forma de puntuar un golpeo, estas dimensiones cambian con ella.
    public static func de(
        _ sesion: PadelSession,
        config: LevelConfig = LevelConfig.current
    ) -> DimensionesDeNivel {
        let estimador = LevelEstimator(config: config)

        var notasPorTipo: [ShotType: [Float]] = [:]
        for golpe in sesion.shots {
            // Los golpeos sin clasificar o mal clasificados no cuentan, ni siquiera para
            // llegar al mínimo: son los mismos que el estimador descarta.
            guard let nota = estimador.grade(golpe) else { continue }
            notasPorTipo[golpe.type, default: []].append(nota)
        }

        // Mismo listón que para entrar en el repertorio. Aquí se aplica al grupo entero y
        // no a cada tipo a propósito: la dimensión habla del ataque, no del smash, y pedir
        // cinco de cada uno dejaría sin ataque a una sesión con tres remates y cuatro
        // bandejas, que sí tiene ataque de sobra que contar.
        let minimoGolpeos = config.minShotsPerTypeForRepertoire

        return DimensionesDeNivel(
            ataque: Self.notaDeGrupo(
                notasPorTipo, tipos: Self.golpesDeAtaque, minimoGolpeos: minimoGolpeos
            ),
            defensa: Self.notaDeGrupo(
                notasPorTipo, tipos: Self.golpesDeDefensa, minimoGolpeos: minimoGolpeos
            ),
            juegoDeRed: Self.notaDeGrupo(
                notasPorTipo, tipos: Self.golpesDeRed, minimoGolpeos: minimoGolpeos
            ),
            juegoDeFondo: Self.notaDeGrupo(
                notasPorTipo, tipos: Self.golpesDeFondo, minimoGolpeos: minimoGolpeos
            ),
            consistencia: Self.regularidadReescalada(
                notasPorTipo, sesion: sesion, estimador: estimador, minimoGolpeos: minimoGolpeos
            ),
            rendimientoFisico: Self.intensidadSostenida(sesion)
        )
    }

    /// Nota media de un grupo de golpes, o nil si el grupo no llega al mínimo.
    ///
    /// Promedia **por tipo y no por golpeo**, igual que el estimador y que
    /// `GolpeVisible.agruparNotas`: si no, cuarenta bandejas dejarían mudos a cinco
    /// remates y "ataque" sería "bandeja" con otro nombre.
    private static func notaDeGrupo(
        _ notasPorTipo: [ShotType: [Float]],
        tipos: [ShotType],
        minimoGolpeos: Int
    ) -> Float? {
        let presentes = tipos.compactMap { notasPorTipo[$0] }
        let golpeos = presentes.reduce(0) { $0 + $1.count }
        guard golpeos >= minimoGolpeos else { return nil }
        let medias = presentes.map { Self.redondear1(Self.mean($0)) }
        return Self.redondear1(Self.mean(medias))
    }

    /// La regularidad del estimador, reescalada, o nil si no la sostiene nada.
    ///
    /// Solo la sostienen los tipos con dos golpeos o más: con un golpeo suelto no hay nada
    /// que comparar y el estimador devuelve un 0,5 de relleno que ni premia ni castiga.
    /// Ese 0,5 es correcto dentro del cálculo global —donde se mezcla con la media y el
    /// repertorio— pero enseñado como "tu consistencia es un 4" sería un número inventado
    /// con cara de medida.
    private static func regularidadReescalada(
        _ notasPorTipo: [ShotType: [Float]],
        sesion: PadelSession,
        estimador: LevelEstimator,
        minimoGolpeos: Int
    ) -> Float? {
        let golpeosQueLaSostienen = notasPorTipo.values
            .filter { $0.count >= 2 }
            .reduce(0) { $0 + $1.count }
        guard golpeosQueLaSostienen >= minimoGolpeos else { return nil }
        return Self.aEscalaDeNivel(estimador.estimate(sesion.shots).consistency)
    }

    /// Intensidad sostenida a partir del reparto por zonas de pulso.
    ///
    /// Se usan las zonas y no el pulso medio porque las zonas ya vienen normalizadas por la
    /// FC máxima del jugador (ver `SessionRecorder`), y comparar pulsos en bruto entre dos
    /// personas no significa nada: 150 pulsaciones son un trote para uno y el límite para
    /// otro.
    ///
    /// La duración entra **solo como puerta** y no como multiplicador: un partido de dos
    /// horas no es más nivel físico que uno de una hora a la misma intensidad, es más
    /// volumen, que es otra cosa y merece su propia métrica.
    private static func intensidadSostenida(_ sesion: PadelSession) -> Float? {
        let segundosPorZona = sesion.health.zones.secondsPerZone
        let segundosConPulso = HeartRateZones.zoneKeys.reduce(0) { $0 + (segundosPorZona[$1] ?? 0) }
        guard segundosConPulso > 0 else { return nil }
        guard sesion.durationSeconds >= Self.minSegundosParaFisico else { return nil }
        let coberturaMinima = Float(sesion.durationSeconds) * Self.minCoberturaDePulso
        guard Float(segundosConPulso) >= coberturaMinima else { return nil }

        var acumulado: Double = 0
        for zona in HeartRateZones.zoneKeys {
            let segundos = segundosPorZona[zona] ?? 0
            acumulado += Double(segundos) * Double(Self.intensidadDeZona[zona] ?? 0)
        }
        let fraccionMedia = Float(acumulado / Double(segundosConPulso))

        let normalizado = min(
            max((fraccionMedia - Self.fcMaxNivel1) / (Self.fcMaxNivel7 - Self.fcMaxNivel1), 0), 1
        )
        return Self.aEscalaDeNivel(normalizado)
    }

    /// Un 0..1 pasado a la escala 1..7, igual que hace el estimador con sus notas.
    private static func aEscalaDeNivel(_ normalizado: Float) -> Float {
        Self.redondear1(
            LevelConfig.minLevel + normalizado * (LevelConfig.maxLevel - LevelConfig.minLevel)
        )
    }

    private static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func redondear1(_ valor: Float) -> Float { (valor * 10).rounded() / 10 }
}
