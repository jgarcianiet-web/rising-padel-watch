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
    public var prepOverheadElevationDeg: Float?
    public var smashPeakGyroRadS: Float?
    public var viboraAxialRadS: Float?
    public var volleyAxialMaxRadS: Float?
    /// Cuántos golpeos etiquetados la sostienen.
    public var muestras: Int
    public var creadoEpochMs: Int64

    public init(
        prepOverheadElevationDeg: Float? = nil,
        smashPeakGyroRadS: Float? = nil,
        viboraAxialRadS: Float? = nil,
        volleyAxialMaxRadS: Float? = nil,
        ejeDeElevacionInvertido: Bool? = nil,
        muestras: Int = 0,
        creadoEpochMs: Int64 = 0
    ) {
        self.prepOverheadElevationDeg = prepOverheadElevationDeg
        self.smashPeakGyroRadS = smashPeakGyroRadS
        self.viboraAxialRadS = viboraAxialRadS
        self.volleyAxialMaxRadS = volleyAxialMaxRadS
        self.ejeDeElevacionInvertido = ejeDeElevacionInvertido
        self.muestras = muestras
        self.creadoEpochMs = creadoEpochMs
    }

    public var vacia: Bool {
        prepOverheadElevationDeg == nil && smashPeakGyroRadS == nil
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

        // Víbora contra bandeja: el efecto lateral.
        let axialVibora = etiquetados.filter { $0.0 == .vibora }
            .map { abs($0.1.axialRotationRadS) }
        let axialBandeja = etiquetados.filter { $0.0 == .bandeja }
            .map { abs($0.1.axialRotationRadS) }
        let vibora = frontera(bajos: axialBandeja, altos: axialVibora, rango: 2...12)

        // Volea contra golpe de fondo: la pala quieta.
        let axialVoleas = etiquetados.filter { voleas.contains($0.0) }
            .map { abs($0.1.axialRotationRadS) }
        let axialFondo = etiquetados.filter { fondo.contains($0.0) }
            .map { abs($0.1.axialRotationRadS) }
        let volea = frontera(bajos: axialVoleas, altos: axialFondo, rango: 1.5...8)

        let calibracion = DetectorCalibration(
            prepOverheadElevationDeg: prep,
            smashPeakGyroRadS: smash,
            viboraAxialRadS: vibora,
            volleyAxialMaxRadS: volea,
            ejeDeElevacionInvertido: invertido,
            muestras: etiquetados.count,
            creadoEpochMs: ahoraEpochMs
        )

        return ResultadoCalibracion(
            calibracion: calibracion,
            aciertoAntes: acierto(etiquetados, config: base),
            aciertoDespues: acierto(etiquetados, config: base.applying(calibracion)),
            porTipo: porTipo
        )
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
