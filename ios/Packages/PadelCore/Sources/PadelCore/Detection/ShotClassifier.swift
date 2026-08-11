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

    /// El bosque entrenado, si esta versión lleva uno.
    private let modelo: ModeloDeGolpes? = ModeloEntrenado.actual

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
        // El modelo entrenado manda cuando lo hay y cuando está seguro; si no, la
        // heurística, que además es la que sabe decir por qué. Ver `ModeloDeGolpes`.
        if let delModelo = modelo?.clasificar(features),
           delModelo.confidence >= ModeloEntrenado.minVotos {
            return delModelo
        }
        return porHeuristica(features)
    }

    private func porHeuristica(_ features: ShotFeatures) -> Classification {
        // La pregunta que separa un golpe alto de uno de fondo es "¿pasó la mano por
        // encima del hombro?", y esa la responde el recorrido del swing, no la postura
        // en el instante del impacto. Ver el comentario de `peakElevationDeg`.
        // Dos testigos de golpe alto: hasta dónde subió el brazo durante el swing, y
        // cómo estaba armado en la preparación. El segundo manda cuando existe: se
        // mide con el brazo calmado, donde la gravedad es fiable — en pista (ago
        // 2026) los remates reales salían con el pico corrupto (+3°, −41°) y solo la
        // preparación los delataba.
        let isOverhead = features.peakElevationDeg > config.overheadElevationDeg
            || (features.prepElevationDeg ?? -90) > config.prepOverheadElevationDeg
        // El margen se mide sobre el MISMO rasgo que decide, el pico. Antes se medía
        // sobre el máximo de pico y preparación, y eso mezclaba dos escalas: la
        // preparación se compara contra su propio umbral, no contra el del pico. Con la
        // puerta en la horizontal el error se volvió visible — una volea de revés se
        // arma a +20° de preparación, así que su "margen" salía cero y el golpe acababa
        // sin clasificar por dudoso cuando de dudoso no tenía nada.
        let elevationMargin = margin(
            value: features.peakElevationDeg,
            threshold: config.overheadElevationDeg,
            scale: 15
        )

        if isOverhead {
            return classifyOverhead(features, elevationMargin: elevationMargin)
        }

        // El saque se decide DESPUÉS de descartar el golpe alto, y a propósito.
        //
        // Estuvo antes durante una tanda, cuando la elevación llegaba con el eje girado
        // y no se podía confiar en ella: entonces adelantar el saque salvaba tres de
        // cinco. Con el eje ya bien, la elevación es el rasgo más limpio que hay —los
        // altos y los bajos no se solapan ni en un grado— y adelantar el saque cuesta
        // más de lo que da: el saque del pádel se golpea **a la cintura**, así que un
        // golpe que pica a +33° no puede serlo por mucho que barra. En la tanda limpia
        // (ago 2026) la regla del saque se estaba llevando una víbora que barrió 348°.
        //
        // La firma sigue siendo la misma —barrido largo con mucha pronación—, solo que
        // ahora se le pide además no haber pasado por encima de la cabeza.
        let axialDelSaque = abs(features.axialRotationRadS)
        if axialDelSaque >= config.serveAxialRadS,
           features.sweptAngleDeg >= config.serveSweptDeg {
            // Base alta a propósito: pasar dos puertas independientes —rotar como un
            // saque Y barrer como un saque— ya es prueba de sobra. Con la fórmula de
            // solo márgenes, un saque justo en la frontera salía con 0,16 de confianza
            // y el detector lo tiraba por dudoso, que es lo contrario de lo que pasaba.
            let axialMargin = margin(
                value: axialDelSaque,
                threshold: config.serveAxialRadS,
                scale: config.serveAxialRadS * 0.5
            )
            let sweptMargin = margin(
                value: features.sweptAngleDeg,
                threshold: config.serveSweptDeg,
                scale: config.serveSweptDeg * 0.3
            )
            return finalize(.serve, 0.5 + 0.25 * axialMargin + 0.25 * sweptMargin)
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
            // Base alta, como en el saque y por el mismo motivo: haber pasado la puerta
            // de la volea —compacta o con la pala quieta— y no ser un golpe alto ya son
            // dos pruebas independientes. Sin base, una volea con acompañamiento salía a
            // 0,38 y el detector la tiraba por dudosa; y una volea con acompañamiento es
            // una volea de manual, no una duda.
            confidence = 0.5 + 0.2 * compactMargin + 0.15 * quietMargin
                + 0.15 * elevationMargin
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
        // Aquí ya no vive el saque: el saque del pádel es BAJO (se arma a la cintura),
        // así que se decide antes, por su pronación.
        //
        // Entre los tres golpes altos manda la ALTURA DEL GOLPEO, no el efecto. La
        // bandeja y la víbora empiezan igual —brazo arriba— pero la víbora se golpea
        // más baja: es un golpe cortado que sale más plano. Con la tanda de ocho tipos
        // en la mano, la bandeja pica a +25° de mediana y la víbora a +4°.
        //
        // El efecto NO sirve para separarlas, aunque parezca lo lógico: la rotación
        // axial media de las víboras (−2,0) y la de las bandejas (−1,9) son el mismo
        // número. Una víbora no rota todo el swing, da un latigazo al final, y
        // promediarlo sobre 200° de arco lo borra.
        let alturaMargin = margin(
            value: features.peakElevationDeg,
            threshold: config.viboraElevationDeg,
            scale: config.viboraElevationDeg
        )
        let peakMargin = margin(
            value: features.peakGyroRadS,
            threshold: config.smashPeakGyroRadS,
            scale: config.smashPeakGyroRadS * 0.35
        )

        let type: ShotType
        if features.peakGyroRadS > config.smashPeakGyroRadS {
            type = .smash
        } else if features.peakElevationDeg >= config.viboraElevationDeg {
            type = .bandeja
        } else {
            type = .vibora
        }
        // Dos rasgos y ya: el que decidió el tipo, y la certeza de que fue golpe alto.
        let decisionMargin = type == .smash ? peakMargin : alturaMargin
        // Misma base que la volea: si el golpe pasó la puerta de altura, es uno de los
        // tres altos con seguridad; lo único que queda por decidir es cuál. Reportarlo
        // como "sin clasificar" tiraría un golpe del que se sabe casi todo — una víbora
        // justo en la frontera (+15°) salía a 0,36 y desaparecía.
        return finalize(type, 0.5 + 0.25 * decisionMargin + 0.25 * elevationMargin)
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
