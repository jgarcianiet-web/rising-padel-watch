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
        // La pregunta que separa un golpe alto de uno de fondo es "¿pasó la mano por
        // encima del hombro?", y esa la responde el recorrido del swing, no la postura
        // en el instante del impacto. Ver el comentario de `peakElevationDeg`.
        let isOverhead = features.peakElevationDeg > config.overheadElevationDeg
        let elevationMargin = margin(
            value: features.peakElevationDeg,
            threshold: config.overheadElevationDeg,
            scale: 15
        )

        if isOverhead {
            return classifyOverhead(features, elevationMargin: elevationMargin)
        }

        let axial = features.axialRotationRadS
        let axialAbs = abs(axial)
        // La firma de la volea es doble (validado en pista, ago 2026): swing corto, o
        // swing medio con la pala quieta — voleas reales con acompañamiento barrían
        // 147-170° pero con axial 0.3-3.8, mientras un golpe de fondo lleva efecto de
        // sobra (7.9-10.5 en derechas reales).
        let isVolley = features.sweptAngleDeg < config.volleySweptDeg
            || (features.sweptAngleDeg < config.volleyMaxSweptDeg
                && axialAbs < config.volleyAxialMaxRadS)

        let confidence: Float
        if isVolley {
            // A una volea no se le puede pedir efecto: la vieja fórmula castigaba el
            // axial bajo — que es justo lo que define una volea — y ejecutaba golpes
            // bien clasificados. Aquí la confianza premia lo compacta (lejos del techo
            // de barrido) y lo quieta (poco axial) que es.
            let compactMargin = margin(
                value: features.sweptAngleDeg,
                threshold: config.volleyMaxSweptDeg,
                scale: config.volleyMaxSweptDeg
            )
            let quietMargin = 1 - min(max(axialAbs / config.volleyAxialMaxRadS, 0), 1)
            confidence = 0.4 * compactMargin + 0.3 * quietMargin + 0.3 * elevationMargin
        } else {
            let sweptMargin = margin(
                value: features.sweptAngleDeg,
                threshold: config.volleySweptDeg,
                scale: config.volleySweptDeg
            )
            let axialMargin = min(max(axialAbs / config.axialConfidenceScaleRadS, 0), 1)
            confidence = 0.35 * sweptMargin + 0.35 * axialMargin + 0.30 * elevationMargin
        }

        let type: ShotType
        switch (isVolley, axial > 0) {
        case (true, true): type = .forehandVolley
        case (true, false): type = .backhandVolley
        case (false, true): type = .forehand
        case (false, false): type = .backhand
        }
        return finalize(type, confidence)
    }

    /// Los cuatro golpeos por encima de la cabeza, en orden de decisión:
    ///
    /// 1. **Saque**: swing completo (barre mucho más ángulo que cualquier otro alto).
    /// 2. **Smash**: violencia — pico de giro por encima de `smashPeakGyroRadS`.
    /// 3. **Víbora**: efecto — rotación axial alta sin la violencia del smash.
    /// 4. **Bandeja**: el resto; el golpe alto de control, plano y sin exceso.
    ///
    /// El orden importa: un smash suele llevar también algo de efecto, pero la violencia
    /// lo define antes de que la rotación axial pueda confundirlo con una víbora.
    private func classifyOverhead(
        _ features: ShotFeatures, elevationMargin: Float
    ) -> Classification {
        // La escala del margen es media frontera y no la frontera entera: una bandeja de
        // 140° está lejos del saque en términos prácticos aunque en valor absoluto se
        // quede a menos de la mitad del umbral.
        let sweptMargin = margin(
            value: features.sweptAngleDeg,
            threshold: config.serveSweptDeg,
            scale: config.serveSweptDeg * 0.5
        )

        let isServe = features.sweptAngleDeg > config.serveSweptDeg
            && features.peakGyroRadS > config.servePeakGyroRadS
        if isServe {
            // En el saque la rotación axial no participa en la decisión, así que no debe
            // penalizar la confianza: se reparte entre los dos rasgos que sí deciden.
            return finalize(.serve, 0.5 * sweptMargin + 0.5 * elevationMargin)
        }

        let axialAbs = abs(features.axialRotationRadS)
        let peakMargin = margin(
            value: features.peakGyroRadS,
            threshold: config.smashPeakGyroRadS,
            scale: config.smashPeakGyroRadS * 0.35
        )
        // Media frontera, como el saque: una víbora real promedia 10-14 rad/s de axial
        // y con la frontera entera de escala nunca pasaría de la confianza mínima.
        let axialMargin = margin(
            value: axialAbs, threshold: config.viboraAxialRadS, scale: config.viboraAxialRadS * 0.5
        )

        let type: ShotType
        if features.peakGyroRadS > config.smashPeakGyroRadS {
            type = .smash
        } else if axialAbs > config.viboraAxialRadS {
            type = .vibora
        } else {
            type = .bandeja
        }
        // El rasgo que decidió cada tipo es el que más pesa en su confianza; la distancia
        // al saque y la elevación completan el reparto.
        let decisionMargin = type == .smash ? peakMargin : axialMargin
        return finalize(type, 0.4 * decisionMargin + 0.3 * sweptMargin + 0.3 * elevationMargin)
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
