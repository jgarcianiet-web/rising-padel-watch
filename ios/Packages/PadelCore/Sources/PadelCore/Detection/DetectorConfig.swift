import Foundation

public enum Sensitivity: String, Codable, CaseIterable, Sendable {
    /// Menos falsos positivos, se pierden golpeos suaves.
    case low
    case medium
    /// Detecta golpeos más flojos a cambio de más falsos positivos.
    case high

    public var factor: Float {
        switch self {
        case .low: return 1.25
        case .medium: return 1.0
        case .high: return 0.75
        }
    }
}

/// Todos los umbrales del detector y del clasificador. Ver `docs/shot-detection.md`.
///
/// Los valores por defecto están fijados para un jugador adulto de nivel medio con el
/// reloj en la muñeca de la pala.
public struct DetectorConfig: Equatable, Sendable {
    public var sampleRateHz: Int

    // MARK: Detección

    /// rad/s a partir de los cuales se considera que ha empezado un swing.
    ///
    /// 3.5 rad/s deja fuera el braceo de correr y de colocarse (≈2 rad/s) pero no una
    /// volea bloqueada, que es el golpeo con menos velocidad angular de todos.
    public var swingOnsetRadS: Float
    /// Muestras consecutivas por encima de `swingOnsetRadS` para confirmar el swing.
    public var onsetSamples: Int
    /// Pico mínimo de |gyro| en el swing para que cuente como golpeo. Referencia: una
    /// volea ronda 5-10 rad/s, una derecha 15-25 y un smash 25-35.
    public var minPeakGyroRadS: Float
    /// Pico mínimo de |accel| (en g) para considerar que hubo impacto.
    public var impactG: Float
    /// Tiempo muerto tras un golpeo, para no contar el rebote del impacto.
    public var refractoryMs: Int64
    /// Si un swing dura más que esto sin impacto, era desplazamiento, no golpeo.
    public var maxSwingMs: Int64
    /// Un swing más corto que esto es ruido.
    public var minSwingMs: Int64

    // MARK: Clasificación

    /// Grados sobre la horizontal que tiene que alcanzar el brazo
    /// (`ShotFeatures.peakElevationDeg`) para que el golpeo sea por encima de la cabeza.
    ///
    /// Se compara contra el recorrido del swing y no contra la postura en el impacto:
    /// medida sobre el impacto, la elevación de una tanda de derechas (+41..+77 en
    /// pista, ago 2026) y la de una tanda de víboras (−20..+56) se solapaban por
    /// completo, así que ningún umbral sobre ese valor podía separarlas.
    public var overheadElevationDeg: Float
    /// Por debajo de este ángulo barrido el golpeo es una volea.
    public var volleySweptDeg: Float
    /// La segunda firma de la volea, validada en pista (ago 2026): swing medio con la
    /// pala quieta. Voleas de revés reales barrían 147-170° (por encima de
    /// volleySweptDeg) pero con axial 0.3-3.8, mientras las derechas de fondo reales
    /// promediaban 7.9-10.5: el efecto separa lo que el barrido solapa.
    public var volleyAxialMaxRadS: Float
    /// Techo de barrido para esa segunda firma: más allá ya es un swing completo.
    public var volleyMaxSweptDeg: Float
    /// Ángulo barrido a partir del cual un golpeo alto es un saque y no una bandeja.
    public var serveSweptDeg: Float
    /// Pico de |gyro| adicional que exige el saque.
    public var servePeakGyroRadS: Float
    /// Pico de |gyro| a partir del cual un golpeo alto es un smash. Una bandeja ronda
    /// 12-20 rad/s y una víbora 16-25; el remate vive por encima de 25.
    public var smashPeakGyroRadS: Float
    /// Rotación axial media (rad/s, en valor absoluto) a partir de la cual un golpeo
    /// alto que no es smash se considera víbora: el efecto lateral es su seña de
    /// identidad, la bandeja se pega mucho más plana.
    ///
    /// 9 y no 5: validado en pista (ago 2026), la pronación natural de una derecha
    /// plana ya promedia 6-11 rad/s de axial. Con el umbral de elevación en 60° esas
    /// derechas ya no llegan a esta rama; aquí solo compiten golpes altos de verdad, y
    /// la bandeja plana promedia 2-5 mientras la víbora vive por encima de 10.
    public var viboraAxialRadS: Float
    /// Ventana previa al impacto sobre la que se promedia la rotación axial.
    public var axialWindowMs: Int64
    /// Ventana previa al **arranque del swing** sobre la que se mide la elevación de
    /// preparación, con el brazo aún calmado (la gravedad ahí sí es fiable).
    public var prepWindowMs: Int64
    /// Elevación de preparación a partir de la cual el golpe se armó en alto.
    public var prepOverheadElevationDeg: Float
    /// Escala para normalizar la rotación axial al calcular la confianza.
    public var axialConfidenceScaleRadS: Float
    /// Por debajo de esta confianza el tipo se reporta como `.unknown` (el golpeo sigue contando).
    public var minConfidence: Float

    // MARK: Geometría

    /// Eje longitudinal del antebrazo en coordenadas del dispositivo, apuntando del codo
    /// hacia la mano, **con el reloj en la muñeca derecha**. Para la muñeca izquierda el
    /// detector lo invierte solo (el reloj va girado 180° respecto al brazo).
    ///
    /// Si en la validación en pista las derechas salen clasificadas como revés, la
    /// corrección es `invertAxialSign`, no tocar este eje.
    public var forearmAxis: Vector3
    /// Invierte el signo de la rotación axial. El convenio de signos del giróscopo debe
    /// validarse en pista una vez por plataforma; esta bandera es la corrección.
    public var invertAxialSign: Bool
    /// Brazo de palanca muñeca → centro del cordaje, en metros.
    public var armLeverM: Float

    public init(
        sampleRateHz: Int = 50,
        swingOnsetRadS: Float = 3.5,
        onsetSamples: Int = 2,
        minPeakGyroRadS: Float = 5.5,
        impactG: Float = 3.2,
        refractoryMs: Int64 = 320,
        maxSwingMs: Int64 = 900,
        minSwingMs: Int64 = 80,
        overheadElevationDeg: Float = 50,
        volleySweptDeg: Float = 70,
        volleyAxialMaxRadS: Float = 4.5,
        volleyMaxSweptDeg: Float = 190,
        serveSweptDeg: Float = 220,
        servePeakGyroRadS: Float = 18,
        smashPeakGyroRadS: Float = 16,
        viboraAxialRadS: Float = 4,
        axialWindowMs: Int64 = 200,
        prepWindowMs: Int64 = 400,
        prepOverheadElevationDeg: Float = 45,
        axialConfidenceScaleRadS: Float = 4.0,
        minConfidence: Float = 0.45,
        forearmAxis: Vector3 = Vector3(0, 1, 0),
        invertAxialSign: Bool = false,
        armLeverM: Float = 0.65
    ) {
        self.sampleRateHz = sampleRateHz
        self.swingOnsetRadS = swingOnsetRadS
        self.onsetSamples = onsetSamples
        self.minPeakGyroRadS = minPeakGyroRadS
        self.impactG = impactG
        self.refractoryMs = refractoryMs
        self.maxSwingMs = maxSwingMs
        self.minSwingMs = minSwingMs
        self.overheadElevationDeg = overheadElevationDeg
        self.volleySweptDeg = volleySweptDeg
        self.volleyAxialMaxRadS = volleyAxialMaxRadS
        self.volleyMaxSweptDeg = volleyMaxSweptDeg
        self.serveSweptDeg = serveSweptDeg
        self.servePeakGyroRadS = servePeakGyroRadS
        self.smashPeakGyroRadS = smashPeakGyroRadS
        self.viboraAxialRadS = viboraAxialRadS
        self.axialWindowMs = axialWindowMs
        self.prepWindowMs = prepWindowMs
        self.prepOverheadElevationDeg = prepOverheadElevationDeg
        self.axialConfidenceScaleRadS = axialConfidenceScaleRadS
        self.minConfidence = minConfidence
        self.forearmAxis = forearmAxis
        self.invertAxialSign = invertAxialSign
        self.armLeverM = armLeverM
    }

    public static let `default` = DetectorConfig()

    public var sampleIntervalMs: Int64 {
        max(Int64(1000 / sampleRateHz), 1)
    }

    /// Escala los umbrales de energía según la sensibilidad elegida por el usuario.
    public func withSensitivity(_ sensitivity: Sensitivity) -> DetectorConfig {
        var copy = self
        copy.swingOnsetRadS = swingOnsetRadS * sensitivity.factor
        copy.minPeakGyroRadS = minPeakGyroRadS * sensitivity.factor
        copy.impactG = impactG * sensitivity.factor
        return copy
    }

    /// La configuración con los umbrales personales del jugador encima. Lo que la
    /// calibración no sostiene se queda de fábrica.
    public func applying(_ calibracion: DetectorCalibration) -> DetectorConfig {
        var copy = self
        if let valor = calibracion.prepOverheadElevationDeg { copy.prepOverheadElevationDeg = valor }
        if let valor = calibracion.smashPeakGyroRadS { copy.smashPeakGyroRadS = valor }
        if let valor = calibracion.viboraAxialRadS { copy.viboraAxialRadS = valor }
        if let valor = calibracion.volleyAxialMaxRadS { copy.volleyAxialMaxRadS = valor }
        return copy
    }
}
