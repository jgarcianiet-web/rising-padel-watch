import Foundation

/// Los umbrales personales de un jugador, sacados de sus propias tandas etiquetadas.
///
/// Nace de un problema real: los umbrales de fábrica salen de una técnica media, y en
/// pista (ago 2026) las víboras de un jugador promediaban |4-5| de rotación axial cuando
/// el umbral estaba en 9 — ninguna llegaba. Cada jugador tiene su muñeca: lo que hay que
/// medir no es "cuánto efecto lleva una víbora" sino "cuánto efecto llevan LAS TUYAS".
///
/// Los campos nil se quedan con el valor de fábrica: se calibra solo lo que las tandas
/// pueden sostener. Espejo del core Kotlin, con tests allí.
public struct DetectorCalibration: Codable, Equatable, Sendable {
    /// La puerta de golpe alto de ESTE jugador. La de fábrica (+14) sale de una tanda
    /// donde altos y bajos no se rozaban; en la tanda de 40 en bloques (ago 2026) el
    /// mismo jugador impactó sus golpes altos entre +4 y +31 — cuatro de ellos por
    /// debajo de la puerta de fábrica, perdidos como voleas. Se fija en el punto medio
    /// del HUECO entre el bajo más alto y el alto más bajo (no entre medianas: es una
    /// puerta, y una puerta que deja un golpe al otro lado ya está mal puesta), y solo
    /// si el hueco existe.
    public var overheadElevationDeg: Float?
    public var prepOverheadElevationDeg: Float?
    public var smashPeakGyroRadS: Float?
    public var viboraElevationDeg: Float?
    /// Frontera bandeja/víbora por pronación (con signo) en vez de por altura, para los
    /// jugadores cuyas tandas demuestran que a ellos las separa el efecto. Ver
    /// `DetectorConfig.viboraAxialRadS`.
    public var viboraAxialRadS: Float?
    public var volleyAxialMaxRadS: Float?
    /// El eje del antebrazo lee la elevación al revés en este reloj.
    ///
    /// Se decide **con tandas etiquetadas** y no en vivo. Antes lo decidía una media
    /// larga de la sesión: si el brazo salía "en alto" un rato, se daba por invertido.
    /// Esa regla no puede distinguir "el sensor está al revés" de "este jugador acaba de
    /// dar treinta bandejas", y una tanda de golpes altos es exactamente el caso que la
    /// dispara en falso — justo cuando la elevación más falta hace. En pista (ago 2026)
    /// llegó a oscilar dentro de una misma tanda: cinco saques seguidos salieron tres
    /// con preparación +45..+49 y dos con −46..−49.
    ///
    /// Aquí no hay ambigüedad: si en las tandas los golpes altos se preparan más abajo
    /// que los bajos, el eje está invertido. Lo dice la etiqueta, no una suposición.
    public var ejeDeElevacionInvertido: Bool?
    /// Cuántos golpeos etiquetados la sostienen.
    public var muestras: Int
    public var creadoEpochMs: Int64

    public init(
        overheadElevationDeg: Float? = nil,
        prepOverheadElevationDeg: Float? = nil,
        smashPeakGyroRadS: Float? = nil,
        viboraElevationDeg: Float? = nil,
        viboraAxialRadS: Float? = nil,
        volleyAxialMaxRadS: Float? = nil,
        ejeDeElevacionInvertido: Bool? = nil,
        muestras: Int = 0,
        creadoEpochMs: Int64 = 0
    ) {
        self.overheadElevationDeg = overheadElevationDeg
        self.prepOverheadElevationDeg = prepOverheadElevationDeg
        self.smashPeakGyroRadS = smashPeakGyroRadS
        self.viboraElevationDeg = viboraElevationDeg
        self.viboraAxialRadS = viboraAxialRadS
        self.volleyAxialMaxRadS = volleyAxialMaxRadS
        self.ejeDeElevacionInvertido = ejeDeElevacionInvertido
        self.muestras = muestras
        self.creadoEpochMs = creadoEpochMs
    }

    public var vacia: Bool {
        overheadElevationDeg == nil && prepOverheadElevationDeg == nil
            && smashPeakGyroRadS == nil && viboraElevationDeg == nil
            && viboraAxialRadS == nil && volleyAxialMaxRadS == nil
            && ejeDeElevacionInvertido == nil
    }
}

/// El resultado de calibrar: los umbrales y cuánto mejoran sobre las propias tandas.
public struct ResultadoCalibracion: Sendable {
    public let calibracion: DetectorCalibration
    /// Acierto de la heurística de fábrica sobre las tandas, 0..1.
    public let aciertoAntes: Float
    /// Acierto con los umbrales calibrados, 0..1.
    public let aciertoDespues: Float
    /// Cuántos golpeos etiquetados de cada tipo entraron.
    public let porTipo: [ShotType: Int]
}

/// Deriva umbrales personales a partir de golpeos etiquetados por el jugador (las tandas
/// del modo de datos, donde la etiqueta la eligió él antes de dar el golpe).
///
/// El método es deliberadamente simple y explicable: para separar dos familias por un
/// rasgo se toma el **punto medio entre sus medianas**. Con tres cinturones: mínimo de
/// golpeos por familia, medianas que de verdad se separen, y umbral acotado a un rango
/// sensato para que una tanda mal etiquetada no deje el detector inservible.
public enum ThresholdCalibrator {

    /// Con menos de esto por familia, el rasgo no se toca.
    public static let minPorFamilia = 5

    /// Grados que tienen que separar a los altos de los bajos para creerse el signo.
    /// Por debajo, la diferencia puede ser ruido y girar el eje sería peor que no hacer
    /// nada: se rompería un detector que a lo mejor estaba bien.
    public static let minSeparacionEjeDeg: Float = 15

    private static let altos: Set<ShotType> = [.bandeja, .vibora, .smash]
    private static let voleas: Set<ShotType> = [.forehandVolley, .backhandVolley]
    private static let fondo: Set<ShotType> = [.forehand, .backhand]

    public static func calibrar(
        _ etiquetados: [(ShotType, ShotFeatures)],
        base: DetectorConfig = .default,
        ahoraEpochMs: Int64 = 0
    ) -> ResultadoCalibracion {
        var porTipo: [ShotType: Int] = [:]
        for (tipo, _) in etiquetados { porTipo[tipo, default: 0] += 1 }

        // Golpe alto: la elevación de preparación de los altos contra la del resto.
        let prepAltos = etiquetados.filter { altos.contains($0.0) }
            .compactMap { $0.1.prepElevationDeg }
        let prepBajos = etiquetados.filter { voleas.contains($0.0) || fondo.contains($0.0) }
            .compactMap { $0.1.prepElevationDeg }
        // ¿Está el eje al revés? Si los golpes altos se **preparan más abajo** que los
        // bajos, la elevación llega con el signo cambiado. Lo dice la etiqueta del
        // jugador, que es la única fuente que no se puede confundir con "hoy tocaba
        // tanda de bandejas".
        let invertido = ejeInvertido(altos: prepAltos, bajos: prepBajos)
        // Con el eje corregido, la frontera se calcula sobre los valores ya girados: si
        // no, se derivaría un umbral para un signo y se aplicaría al contrario.
        let giro: Float = invertido == true ? -1 : 1
        let prep = frontera(
            bajos: prepBajos.map { $0 * giro }, altos: prepAltos.map { $0 * giro },
            rango: 20...70
        )

        // Smash contra el resto de altos: la violencia del pico de giro.
        let picoSmash = etiquetados.filter { $0.0 == .smash }.map { $0.1.peakGyroRadS }
        let picoOtrosAltos = etiquetados.filter { $0.0 == .bandeja || $0.0 == .vibora }
            .map { $0.1.peakGyroRadS }
        let smash = frontera(bajos: picoOtrosAltos, altos: picoSmash, rango: 10...30)

        // Víbora contra bandeja: la ALTURA del golpeo. Las dos se preparan igual; la
        // víbora se golpea más baja. Ojo al orden de los argumentos: aquí la familia
        // "alta" es la BANDEJA, al revés que en los demás rasgos, porque lo que define
        // a la víbora es quedarse por debajo.
        let alturaVibora = etiquetados.filter { $0.0 == .vibora }
            .map { $0.1.peakElevationDeg * giro }
        let alturaBandeja = etiquetados.filter { $0.0 == .bandeja }
            .map { $0.1.peakElevationDeg * giro }
        let vibora = frontera(bajos: alturaVibora, altos: alturaBandeja, rango: -10...45)

        // Volea contra golpe de fondo: la pala quieta.
        let axialVoleas = etiquetados.filter { voleas.contains($0.0) }
            .map { abs($0.1.axialRotationRadS) }
        let axialFondo = etiquetados.filter { fondo.contains($0.0) }
            .map { abs($0.1.axialRotationRadS) }
        let volea = frontera(bajos: axialVoleas, altos: axialFondo, rango: 1.5...8)

        // La puerta de golpe alto: el pico de elevación de los altos contra TODO lo
        // demás, saques incluidos. Los saques no son ni voleas ni fondo, pero viven
        // debajo de la puerta: si se calibrara sin contarlos, una puerta baja los
        // mandaría a la rama alta y los mataría a todos. Y es una PUERTA, no una
        // frontera de medianas: se pone en el punto medio del hueco real, porque un
        // solo golpe al otro lado ya es un golpe mal clasificado.
        let alturaAltos = etiquetados.filter { altos.contains($0.0) }
            .map { $0.1.peakElevationDeg * giro }
        let alturaBajos = etiquetados.filter { !altos.contains($0.0) }
            .map { $0.1.peakElevationDeg * giro }
        let puerta = hueco(bajos: alturaBajos, altos: alturaAltos, rango: 0...40)

        // Víbora contra bandeja por pronación, la frontera alternativa. Con signo: la
        // víbora se corta con pronación de derecha; el valor absoluto mezclaría un
        // corte con su contrario. Solo sobrevivirá (ver la validación de abajo) si en
        // las tandas de ESTE jugador separa mejor que la altura.
        let viboraPorAxial = frontera(
            bajos: etiquetados.filter { $0.0 == .bandeja }.map { $0.1.axialRotationRadS },
            altos: etiquetados.filter { $0.0 == .vibora }.map { $0.1.axialRotationRadS },
            rango: 1...6
        )

        let candidata = DetectorCalibration(
            overheadElevationDeg: puerta,
            prepOverheadElevationDeg: prep,
            smashPeakGyroRadS: smash,
            viboraElevationDeg: vibora,
            viboraAxialRadS: viboraPorAxial,
            volleyAxialMaxRadS: volea,
            ejeDeElevacionInvertido: invertido,
            muestras: etiquetados.count,
            creadoEpochMs: ahoraEpochMs
        )

        // Cada umbral se queda solo si NO EMPEORA las tandas del jugador. Esto no es
        // adorno: en la tanda de 40 en bloques, la elevación de preparación calibraba a
        // +20° (el punto medio entre familias, acotado al rango) y a +20° se preparan
        // los saques de ese jugador — tres saques muertos por un umbral "bien" derivado.
        let calibracion = validada(candidata, etiquetados: etiquetados, base: base)

        return ResultadoCalibracion(
            calibracion: calibracion,
            aciertoAntes: acierto(etiquetados, config: base),
            aciertoDespues: acierto(etiquetados, config: base.applying(calibracion)),
            porTipo: porTipo
        )
    }

    /// Deja en nil todo umbral candidato que empeore el acierto sobre las propias
    /// tandas. Se evalúan uno a uno, en orden fijo y de forma acumulada: cada umbral se
    /// juzga con los ya aceptados puestos. Empate = se queda (personalizado no es peor
    /// que de fábrica). El eje invertido no se valida por acierto: es una corrección de
    /// signo, y sin él puestos los umbrales de elevación no significan nada.
    private static func validada(
        _ candidata: DetectorCalibration,
        etiquetados: [(ShotType, ShotFeatures)],
        base: DetectorConfig
    ) -> DetectorCalibration {
        var aceptada = DetectorCalibration(
            ejeDeElevacionInvertido: candidata.ejeDeElevacionInvertido,
            muestras: candidata.muestras,
            creadoEpochMs: candidata.creadoEpochMs
        )
        var mejorAcierto = acierto(etiquetados, config: base.applying(aceptada))

        let pasos: [(inout DetectorCalibration) -> Void] = [
            { $0.overheadElevationDeg = candidata.overheadElevationDeg },
            { $0.prepOverheadElevationDeg = candidata.prepOverheadElevationDeg },
            { $0.smashPeakGyroRadS = candidata.smashPeakGyroRadS },
            { $0.viboraElevationDeg = candidata.viboraElevationDeg },
            { $0.viboraAxialRadS = candidata.viboraAxialRadS },
            { $0.volleyAxialMaxRadS = candidata.volleyAxialMaxRadS },
        ]
        for aplicar in pasos {
            var prueba = aceptada
            aplicar(&prueba)
            guard prueba != aceptada else { continue }
            let conEste = acierto(etiquetados, config: base.applying(prueba))
            if conEste >= mejorAcierto {
                aceptada = prueba
                mejorAcierto = conEste
            }
        }
        return aceptada
    }

    /// El punto medio del **hueco** entre dos familias: entre el mayor de los bajos y
    /// el menor de los altos. Para una puerta —donde un solo golpe al otro lado ya
    /// cuenta como error— el hueco es lo que importa, no las medianas. Nil si no hay
    /// material o si las familias se pisan.
    private static func hueco(
        bajos: [Float], altos: [Float], rango: ClosedRange<Float>
    ) -> Float? {
        guard bajos.count >= minPorFamilia, altos.count >= minPorFamilia,
              let techoBajos = bajos.max(), let sueloAltos = altos.min(),
              sueloAltos > techoBajos
        else { return nil }
        let punto = (techoBajos + sueloAltos) / 2
        guard rango.contains(punto) else { return nil }
        return punto
    }

    /// ¿Lee este reloj la elevación al revés?
    ///
    /// Un golpe alto se arma con el brazo por encima del hombro y uno de fondo o una
    /// volea, no. Si las medianas dicen lo contrario —y por un margen que no se explica
    /// por ruido— el eje está invertido. Nil si no hay material suficiente o si la
    /// separación es pequeña: ante la duda, no se toca nada.
    private static func ejeInvertido(altos: [Float], bajos: [Float]) -> Bool? {
        guard altos.count >= minPorFamilia, bajos.count >= minPorFamilia else { return nil }
        let separacion = mediana(altos) - mediana(bajos)
        guard abs(separacion) >= minSeparacionEjeDeg else { return nil }
        return separacion < 0
    }

    /// El punto medio entre las medianas de dos familias, o nil si no hay material o
    /// las dos familias se solapan en ese rasgo.
    private static func frontera(
        bajos: [Float], altos: [Float], rango: ClosedRange<Float>
    ) -> Float? {
        guard bajos.count >= minPorFamilia, altos.count >= minPorFamilia else { return nil }
        let medianaBajos = mediana(bajos)
        let medianaAltos = mediana(altos)
        // Solapadas o al revés de lo esperado: este rasgo no separa a este jugador.
        guard medianaAltos > medianaBajos else { return nil }
        let punto = (medianaBajos + medianaAltos) / 2
        return min(max(punto, rango.lowerBound), rango.upperBound)
    }

    private static func mediana(_ valores: [Float]) -> Float {
        let ordenados = valores.sorted()
        return ordenados[ordenados.count / 2]
    }

    /// Qué fracción de las tandas clasifica bien una configuración dada.
    private static func acierto(
        _ etiquetados: [(ShotType, ShotFeatures)], config: DetectorConfig
    ) -> Float {
        guard !etiquetados.isEmpty else { return 0 }
        let classifier = ShotClassifier(config: config)
        let buenos = etiquetados.filter { etiqueta, rasgos in
            classifier.classify(rasgos).type == etiqueta
        }.count
        return Float(buenos) / Float(etiquetados.count)
    }
}
