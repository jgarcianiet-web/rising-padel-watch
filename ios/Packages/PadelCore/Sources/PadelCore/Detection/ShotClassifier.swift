import Foundation

/// Resultado de clasificar un golpeo ya detectado.
public struct Classification: Equatable, Sendable {
    public let type: ShotType
    public let confidence: Float

    public init(type: ShotType, confidence: Float) {
        self.type = type
        self.confidence = confidence
    }
}

/// Decide de qué tipo es un golpeo a partir de sus rasgos. Ver `docs/shot-detection.md`.
///
/// Está separado de `ShotDetector` a propósito: la detección (¿hubo golpeo?) es estable,
/// mientras que la clasificación (¿de qué tipo?) es la pieza que se sustituirá por un
/// modelo Core ML cuando haya datos etiquetados.
public struct ShotClassifier: Sendable {
    private let config: DetectorConfig
    /// Eje codo → mano en coordenadas del dispositivo. Con el reloj en la muñeca
    /// izquierda el dispositivo está girado 180° sobre su eje Z respecto al brazo, así
    /// que el eje físico apunta al contrario.
    private let forearmAxis: Vector3
    /// Un jugador zurdo es la imagen especular de uno diestro, y una imagen especular
    /// invierte el signo de la rotación sobre el eje del antebrazo.
    private let axialSign: Float

    public init(config: DetectorConfig = .default, profile: PlayerProfile = PlayerProfile()) {
        self.config = config
        self.forearmAxis = (profile.watchWrist == .right ? config.forearmAxis : -config.forearmAxis)
            .normalized()
        let handSign: Float = profile.hand == .right ? 1 : -1
        self.axialSign = handSign * (config.invertAxialSign ? -1 : 1)
    }

    /// Elevación del antebrazo sobre la horizontal, en grados.
    /// +90 = antebrazo vertical hacia arriba, 0 = horizontal, -90 = hacia abajo.
    public func elevationDeg(gravity: Vector3) -> Float {
        let up = (-gravity).normalized()
        guard up != .zero else { return 0 }
        let sine = min(max(forearmAxis.dot(up), -1), 1)
        return asin(sine) * 180 / .pi
    }

    /// Rotación sobre el eje del antebrazo, normalizada para que **positivo = lado de
    /// derecha** y negativo = lado de revés, sea cual sea la mano y la muñeca.
    public func axialRotation(meanGyro: Vector3) -> Float {
        meanGyro.dot(forearmAxis) * axialSign
    }

    public func classify(_ features: ShotFeatures) -> Classification {
        let isOverhead = features.elevationDeg > config.overheadElevationDeg
        let elevationMargin = margin(
            value: features.elevationDeg,
            threshold: config.overheadElevationDeg,
            scale: 45
        )

        if isOverhead {
            let isServe = features.sweptAngleDeg > config.serveSweptDeg
                && features.peakGyroRadS > config.servePeakGyroRadS
            // La escala es media frontera y no la frontera entera: un smash de 140° está
            // lejos del saque en términos prácticos aunque en valor absoluto se quede a
            // menos de la mitad del umbral.
            let sweptMargin = margin(
                value: features.sweptAngleDeg,
                threshold: config.serveSweptDeg,
                scale: config.serveSweptDeg * 0.5
            )
            // En la rama alta la rotación axial no participa en la decisión, así que no
            // debe penalizar la confianza: se reparte entre los dos rasgos que sí deciden.
            let confidence = 0.5 * sweptMargin + 0.5 * elevationMargin
            return finalize(isServe ? .serve : .overhead, confidence)
        }

        let axial = features.axialRotationRadS
        let isVolley = features.sweptAngleDeg < config.volleySweptDeg
        let sweptMargin = margin(
            value: features.sweptAngleDeg,
            threshold: config.volleySweptDeg,
            scale: config.volleySweptDeg
        )
        let axialMargin = min(max(abs(axial) / config.axialConfidenceScaleRadS, 0), 1)
        let confidence = 0.35 * sweptMargin + 0.35 * axialMargin + 0.30 * elevationMargin

        let type: ShotType
        switch (isVolley, axial > 0) {
        case (true, true): type = .forehandVolley
        case (true, false): type = .backhandVolley
        case (false, true): type = .forehand
        case (false, false): type = .backhand
        }
        return finalize(type, confidence)
    }

    /// Un golpeo poco fiable se reporta como `.unknown`, pero conserva su confianza:
    /// sigue contando en el total y la UI puede mostrar por qué no se clasificó.
    private func finalize(_ type: ShotType, _ confidence: Float) -> Classification {
        let clamped = min(max(confidence, 0), 1)
        return clamped < config.minConfidence
            ? Classification(type: .unknown, confidence: clamped)
            : Classification(type: type, confidence: clamped)
    }

    /// Distancia normalizada de un rasgo a su umbral de decisión: 0 = justo en la frontera.
    private func margin(value: Float, threshold: Float, scale: Float) -> Float {
        min(max(abs(value - threshold) / scale, 0), 1)
    }
}
