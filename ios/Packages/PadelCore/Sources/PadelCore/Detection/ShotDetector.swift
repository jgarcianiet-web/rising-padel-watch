import Foundation

/// Detector de golpeos en streaming. Ver `docs/shot-detection.md`.
///
/// Consume muestras a `DetectorConfig.sampleRateHz` y devuelve un `Shot` en la muestra
/// en la que se cierra un golpeo, o nil. No reserva memoria por muestra más allá de una
/// ventana corta, así que puede correr en el reloj durante horas.
///
/// Trabaja con **una muestra de retardo** (20 ms a 50 Hz): para confirmar que el pico de
/// aceleración es un máximo local hace falta ver la muestra siguiente.
///
/// No es thread-safe: hay que llamarlo desde un único hilo (el de la cola de CoreMotion).
/// Los swings que el detector vio y tiró, con el motivo.
///
/// Existe porque hasta ahora los golpes que **no** se detectan eran invisibles: las
/// tandas de entrenamiento solo guardan ventanas alrededor de lo que sí se detectó, así
/// que un golpe perdido no deja rastro en ningún sitio. Se podía medir cuánto se
/// equivoca el clasificador, pero no cuánto se le escapa al detector — que es la pérdida
/// más grande y la que hace que nada converja.
///
/// Cada contador apunta a **un umbral concreto**, así que dejan de hacer falta las
/// conjeturas: si se acumulan en `swingSinImpacto`, sobra `impactG` para golpes suaves
/// como la bandeja o la volea; si es `impactoConSwingCorto`, sobran `minSwingMs` o
/// `minPeakGyroRadS`. Espejo del core Kotlin, con tests allí.
public struct DescartesDelDetector: Codable, Equatable, Sendable {
    /// Hubo impacto pero el swing fue corto o flojo: `minSwingMs` / `minPeakGyroRadS`.
    public var impactoConSwingCorto = 0
    /// El swing duró más de la cuenta sin que se viera impacto: `impactG` demasiado alto.
    public var swingSinImpacto = 0
    /// El giro se apagó sin llegar a impactar: amago o preparación.
    public var amago = 0
    /// Llegó dentro del tiempo muerto del golpe anterior: `refractoryMs`.
    public var enRefractario = 0

    public init(
        impactoConSwingCorto: Int = 0,
        swingSinImpacto: Int = 0,
        amago: Int = 0,
        enRefractario: Int = 0
    ) {
        self.impactoConSwingCorto = impactoConSwingCorto
        self.swingSinImpacto = swingSinImpacto
        self.amago = amago
        self.enRefractario = enRefractario
    }

    public var total: Int { impactoConSwingCorto + swingSinImpacto + amago + enRefractario }
}

public final class ShotDetector {
    private enum State { case idle, swinging }

    private let config: DetectorConfig
    private let classifier: ShotClassifier

    /// Ventana de muestras recientes, solo para promediar la rotación axial pre-impacto.
    private var window: [MotionSample] = []
    private let windowCapacity: Int

    private var referenceMs: Int64?
    private var prevPrev: MotionSample?
    private var prev: MotionSample?

    private var state: State = .idle
    private var onsetCount = 0
    private var candidateStartMs: Int64 = 0
    private var pendingSweptRad: Float = 0
    private var swingStartMs: Int64 = 0
    private var sweptAngleRad: Float = 0
    private var peakGyroRadS: Float = 0
    private var refractoryUntilMs: Int64 = .min

    /// Lo que se ha tirado desde el último `reset`, por motivo.
    public private(set) var descartes = DescartesDelDetector()

    /// Elevación del antebrazo en cada muestra del swing. Se guarda la serie entera
    /// —como mucho 45 valores a 50 Hz— porque las estadísticas robustas (mediana,
    /// percentil) necesitan verla completa, y un solo valor instantáneo no vale: la
    /// estimación de gravedad del sistema se va decenas de grados en mitad de un golpe.
    private var swingElevations: [Float] = []
    /// Elevación de preparación del swing en curso (nil si no hubo muestras calmadas).
    private var prepElevationDeg: Float?

    public init(config: DetectorConfig = .default, profile: PlayerProfile = PlayerProfile()) {
        self.config = config
        self.classifier = ShotClassifier(config: config, profile: profile)
        self.windowCapacity =
            max(Int(max(config.axialWindowMs, config.prepWindowMs + 200) / config.sampleIntervalMs), 4) + 4
        self.window.reserveCapacity(windowCapacity)
    }

    /// Reinicia el detector y fija el origen de tiempos de la sesión.
    public func reset(referenceTimestampMs: Int64? = nil) {
        window.removeAll(keepingCapacity: true)
        referenceMs = referenceTimestampMs
        prevPrev = nil
        prev = nil
        state = .idle
        onsetCount = 0
        pendingSweptRad = 0
        sweptAngleRad = 0
        peakGyroRadS = 0
        refractoryUntilMs = .min
        descartes = DescartesDelDetector()
    }

    /// Procesa una muestra. Devuelve el golpeo si esta muestra cierra uno.
    @discardableResult
    public func process(_ sample: MotionSample) -> Shot? {
        if referenceMs == nil { referenceMs = sample.timestampMs }
        var shot: Shot?
        if let pending = prev {
            shot = evaluate(before: prevPrev, current: pending, next: sample)
        }
        prevPrev = prev
        prev = sample
        return shot
    }

    /// Cierra el stream. Evalúa la última muestra pendiente contra una muestra sintética
    /// en reposo, para no perder un golpeo que caiga justo al final de la sesión.
    public func flush() -> Shot? {
        guard let pending = prev else { return nil }
        let synthetic = MotionSample(
            timestampMs: pending.timestampMs + config.sampleIntervalMs,
            accel: .zero,
            gyro: .zero,
            gravity: pending.gravity
        )
        let shot = evaluate(before: prevPrev, current: pending, next: synthetic)
        prevPrev = nil
        prev = nil
        return shot
    }

    private func evaluate(before: MotionSample?, current: MotionSample, next: MotionSample) -> Shot? {
        pushWindow(current)

        if current.timestampMs < refractoryUntilMs {
            // Solo cuenta como descarte si venía un swing en marcha: el silencio entre
            // golpes también cae aquí y no es nada que se esté perdiendo.
            if state == .swinging { descartes.enRefractario += 1 }
            state = .idle
            onsetCount = 0
            pendingSweptRad = 0
            return nil
        }

        let gyroMag = current.gyro.magnitude()
        let accelMag = current.accel.magnitude()
        let dt = deltaSeconds(before: before, current: current)

        switch state {
        case .idle:
            trackOnset(current, gyroMag: gyroMag, dt: dt)
            return nil

        case .swinging:
            sweptAngleRad += gyroMag * dt
            if gyroMag > peakGyroRadS { peakGyroRadS = gyroMag }
            swingElevations.append(classifier.elevationDeg(gravity: current.gravity))

            let duration = current.timestampMs - swingStartMs
            let isImpact = accelMag > config.impactG
                && accelMag >= (before?.accel.magnitude() ?? 0)
                && accelMag > next.accel.magnitude()

            if isImpact, duration >= config.minSwingMs, peakGyroRadS >= config.minPeakGyroRadS {
                return emitShot(impact: current, impactG: accelMag, durationMs: duration)
            }
            if isImpact {
                // Impacto sin swing con energía suficiente: botar la pelota, chocar la
                // pala. No es un golpeo... o sí lo era y el umbral pide demasiado.
                descartes.impactoConSwingCorto += 1
                goIdle()
                return nil
            }
            if duration > config.maxSwingMs {
                descartes.swingSinImpacto += 1
                goIdle()
                return nil
            }
            // El swing se apaga sin llegar a impactar: amago o preparación.
            if gyroMag < config.swingOnsetRadS * 0.5 {
                descartes.amago += 1
                goIdle()
                return nil
            }
            return nil
        }
    }

    private func trackOnset(_ sample: MotionSample, gyroMag: Float, dt: Float) {
        guard gyroMag > config.swingOnsetRadS else {
            onsetCount = 0
            pendingSweptRad = 0
            return
        }
        if onsetCount == 0 {
            candidateStartMs = sample.timestampMs
            pendingSweptRad = 0
        }
        onsetCount += 1
        pendingSweptRad += gyroMag * dt
        if onsetCount >= config.onsetSamples {
            state = .swinging
            swingStartMs = candidateStartMs
            // La preparación: mediana de la elevación en la ventana previa al arranque,
            // cuando el brazo aún estaba calmado y la gravedad era de fiar. Es el
            // testigo honesto de si el golpe se armó en alto — durante el swing
            // violento el filtro de gravedad se corrompe (validado en pista, ago 2026:
            // remates reales con pico de elevación medido a +3° o −41°).
            let calmadas = window
                .filter { $0.timestampMs >= candidateStartMs - config.prepWindowMs
                    && $0.timestampMs < candidateStartMs }
                .map { classifier.elevationDeg(gravity: $0.gravity) }
                .sorted()
            prepElevationDeg = calmadas.count >= 3 ? calmadas[calmadas.count / 2] : nil
            swingElevations.removeAll(keepingCapacity: true)
            swingElevations.append(classifier.elevationDeg(gravity: sample.gravity))
            // El ángulo barrido arranca en el inicio real del swing, no en la muestra
            // que lo confirma.
            sweptAngleRad = pendingSweptRad
            peakGyroRadS = gyroMag
            onsetCount = 0
            pendingSweptRad = 0
        }
    }

    private func emitShot(impact: MotionSample, impactG: Float, durationMs: Int64) -> Shot {
        let elevations = swingElevations.sorted()
        let features = ShotFeatures(
            sweptAngleDeg: sweptAngleRad * 180 / .pi,
            peakGyroRadS: peakGyroRadS,
            // Estadísticas sobre el swing entero, no un valor suelto: ni la muestra del
            // impacto (5-10 g de golpe descuadran el filtro de gravedad) ni la media de
            // la ventana previa (se promedia sobre un arco de 100-200°) describen la
            // postura del brazo. Ver `docs/shot-detection.md`.
            elevationDeg: Self.percentile(elevations, 0.5),
            axialRotationRadS: classifier.axialRotation(meanGyro: meanGyroBefore(impact.timestampMs)),
            swingDurationMs: durationMs,
            peakElevationDeg: Self.percentile(elevations, 0.8),
            prepElevationDeg: prepElevationDeg
        )
        let classification = classifier.classify(features)
        let shot = Shot(
            offsetMs: max(impact.timestampMs - (referenceMs ?? impact.timestampMs), 0),
            type: classification.type,
            racketSpeedKmh: peakGyroRadS * config.armLeverM * 3.6,
            impactG: impactG,
            confidence: classification.confidence,
            features: features
        )
        refractoryUntilMs = impact.timestampMs + config.refractoryMs
        goIdle()
        return shot
    }

    private func goIdle() {
        state = .idle
        onsetCount = 0
        pendingSweptRad = 0
        sweptAngleRad = 0
        peakGyroRadS = 0
        swingElevations.removeAll(keepingCapacity: true)
    }

    /// Percentil de un array **ya ordenado**. Vacío = 0.
    private static func percentile(_ sorted: [Float], _ fraction: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let index = min(max(Int(Float(sorted.count - 1) * fraction), 0), sorted.count - 1)
        return sorted[index]
    }

    /// Media vectorial del giróscopo en la ventana previa al impacto.
    private func meanGyroBefore(_ impactMs: Int64) -> Vector3 {
        let from = impactMs - config.axialWindowMs
        var sum = Vector3.zero
        var count = 0
        for sample in window where sample.timestampMs >= from && sample.timestampMs <= impactMs {
            sum = sum + sample.gyro
            count += 1
        }
        return count == 0 ? .zero : sum * (1 / Float(count))
    }

    private func pushWindow(_ sample: MotionSample) {
        window.append(sample)
        if window.count > windowCapacity {
            window.removeFirst(window.count - windowCapacity)
        }
    }

    /// dt real entre muestras, acotado: si el sistema entrega muestras con un hueco
    /// (app suspendida, sensor saturado) no debe inflar el ángulo barrido.
    private func deltaSeconds(before: MotionSample?, current: MotionSample) -> Float {
        let defaultDt = 1 / Float(config.sampleRateHz)
        guard let before else { return defaultDt }
        let dt = Float(current.timestampMs - before.timestampMs) / 1000
        return dt <= 0 ? defaultDt : min(dt, 0.1)
    }
}
