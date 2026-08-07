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
        muestras: Int = 0,
        creadoEpochMs: Int64 = 0
    ) {
        self.prepOverheadElevationDeg = prepOverheadElevationDeg
        self.smashPeakGyroRadS = smashPeakGyroRadS
        self.viboraAxialRadS = viboraAxialRadS
        self.volleyAxialMaxRadS = volleyAxialMaxRadS
        self.muestras = muestras
        self.creadoEpochMs = creadoEpochMs
    }

    public var vacia: Bool {
        prepOverheadElevationDeg == nil && smashPeakGyroRadS == nil
            && viboraAxialRadS == nil && volleyAxialMaxRadS == nil
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
        let prep = frontera(bajos: prepBajos, altos: prepAltos, rango: 20...70)

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
