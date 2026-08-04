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

    public init(config: DetectorConfig = .default, profile: PlayerProfile = PlayerProfile()) {
        self.config = config
        self.classifier = ShotClassifier(config: config, profile: profile)
        self.windowCapacity = max(Int(config.axialWindowMs / config.sampleIntervalMs), 4) + 4
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

            let duration = current.timestampMs - swingStartMs
            let isImpact = accelMag > config.impactG
                && accelMag >= (before?.accel.magnitude() ?? 0)
                && accelMag > next.accel.magnitude()

            if isImpact, duration >= config.minSwingMs, peakGyroRadS >= config.minPeakGyroRadS {
                return emitShot(impact: current, impactG: accelMag, durationMs: duration)
            }
            if isImpact {
                // Impacto sin swing con energía suficiente: botar la pelota, chocar la
                // pala. No es un golpeo.
                goIdle()
                return nil
            }
            if duration > config.maxSwingMs {
                goIdle()
                return nil
            }
            // El swing se apaga sin llegar a impactar: amago o preparación.
            if gyroMag < config.swingOnsetRadS * 0.5 {
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
            // El ángulo barrido arranca en el inicio real del swing, no en la muestra
            // que lo confirma.
            sweptAngleRad = pendingSweptRad
            peakGyroRadS = gyroMag
            onsetCount = 0
            pendingSweptRad = 0
        }
    }

    private func emitShot(impact: MotionSample, impactG: Float, durationMs: Int64) -> Shot {
        let features = ShotFeatures(
            sweptAngleDeg: sweptAngleRad * 180 / .pi,
            peakGyroRadS: peakGyroRadS,
            // La gravedad se promedia sobre la ventana previa, igual que el giro axial:
            // en la muestra del impacto (5-10 g, 15+ rad/s) la estimación de gravedad
            // del sistema se va decenas de grados y las derechas salían como "altas".
            elevationDeg: classifier.elevationDeg(gravity: meanGravityBefore(impact)),
            axialRotationRadS: classifier.axialRotation(meanGyro: meanGyroBefore(impact.timestampMs)),
            swingDurationMs: durationMs
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
    }

    /// Media de la gravedad en la ventana previa al impacto, sin entrar en la
    /// preparación: en un golpeo corto (un smash dura ~170 ms) las muestras de antes
    /// del swing describen cómo esperaba el brazo, no cómo golpeó, y arrastran la
    /// elevación decenas de grados.
    private func meanGravityBefore(_ impact: MotionSample) -> Vector3 {
        let from = max(impact.timestampMs - config.axialWindowMs, swingStartMs)
        var sum = Vector3.zero
        var count = 0
        for sample in window where sample.timestampMs >= from && sample.timestampMs <= impact.timestampMs {
            sum = sum + sample.gravity
            count += 1
        }
        return count == 0 ? impact.gravity : sum * (1 / Float(count))
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
