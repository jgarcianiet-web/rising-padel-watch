import Foundation
@testable import PadelCore

/// Generador de señales sintéticas de muñeca.
///
/// Modela un golpeo como media onda de seno en la velocidad angular (acelera, alcanza el
/// pico, frena) con un pico gaussiano corto de aceleración en el instante del impacto,
/// situado al 75% del swing. Es la forma que tienen las señales reales de un golpeo de
/// raqueta, y es suficiente para fijar el comportamiento del detector frente a
/// regresiones.
///
/// No sustituye a la validación en pista: sirve para que el algoritmo no cambie sin
/// querer, no para demostrar que acierta con jugadores reales.
///
/// Es la traducción exacta de `MotionFixtures.kt`: los dos cores deben dar el mismo
/// resultado ante la misma señal.
enum MotionFixtures {

    static let sampleRateHz = 50
    static let sampleIntervalMs: Int64 = 1000 / 50

    private static let baselineAccelG: Float = 0.2
    private static let impactSigmaMs: Float = 25
    private static let strideHz: Float = 2.8

    /// - Parameter axialFraction: fracción de la rotación sobre el eje del antebrazo, con
    ///   signo: positivo = lado de derecha, negativo = lado de revés.
    /// - Parameter elevationDeg: elevación del antebrazo sobre la horizontal en el impacto.
    ///   **Convenio medido en pista (ago 2026)** con el eje del antebrazo ya bien
    ///   orientado: los golpes de fondo y las voleas caen entre −3° y −75°, y los altos
    ///   entre −2° y +36°. La frontera está en la horizontal, no a 50° sobre ella.
    static func swing(
        startMs: Int64,
        peakGyroRadS: Float,
        swingDurationMs: Int64,
        impactG: Float,
        axialFraction: Float,
        elevationDeg: Float,
        impactFraction: Float = 0.75
    ) -> [MotionSample] {
        let steps = Int(swingDurationMs / sampleIntervalMs)
        precondition(steps >= 4, "swing demasiado corto para \(sampleRateHz) Hz")
        let impactIndex = Int((Float(steps) * impactFraction).rounded())

        let elevationRad = elevationDeg * .pi / 180
        // up = (cos e, sin e, 0) ⇒ el eje del antebrazo (+Y) forma `elevationDeg` con la horizontal.
        let gravity = Vector3(-cos(elevationRad), -sin(elevationRad), 0)

        let lateral = max(1 - axialFraction * axialFraction, 0).squareRoot()
        let gyroDirection = Vector3(lateral, axialFraction, 0)

        return (0...steps).map { i in
            let gyroMag = peakGyroRadS * Float(sin(Double.pi * Double(i) / Double(steps)))
            let fromImpactMs = Float(i - impactIndex) * Float(sampleIntervalMs)
            let normalized = fromImpactMs / impactSigmaMs
            let spike = impactG * exp(-(normalized * normalized))
            return MotionSample(
                timestampMs: startMs + Int64(i) * sampleIntervalMs,
                accel: Vector3(baselineAccelG + spike, 0, 0),
                gyro: gyroDirection * gyroMag,
                gravity: gravity
            )
        }
    }

    /// Muñeca quieta: el detector debe volver a IDLE.
    static func rest(startMs: Int64, durationMs: Int64, elevationDeg: Float = 0) -> [MotionSample] {
        let steps = Int(durationMs / sampleIntervalMs)
        let elevationRad = elevationDeg * .pi / 180
        let gravity = Vector3(-cos(elevationRad), -sin(elevationRad), 0)
        return (0..<steps).map { i in
            MotionSample(
                timestampMs: startMs + Int64(i) * sampleIntervalMs,
                accel: Vector3(baselineAccelG, 0, 0),
                gyro: Vector3(0.2, 0.1, 0.05),
                gravity: gravity
            )
        }
    }

    /// Correr por la pista: picos de aceleración grandes pero poca velocidad angular en
    /// la muñeca. El detector no debe contar golpeos.
    static func running(startMs: Int64, durationMs: Int64) -> [MotionSample] {
        let steps = Int(durationMs / sampleIntervalMs)
        return (0..<steps).map { i in
            let t = Float(Int64(i) * sampleIntervalMs) / 1000
            let stride = Float(sin(2 * Double.pi * Double(strideHz) * Double(t)))
            return MotionSample(
                timestampMs: startMs + Int64(i) * sampleIntervalMs,
                accel: Vector3(1.8 * stride, 1.2 * stride, 0.6 * stride) * 1.2,
                gyro: Vector3(1.6 * stride, 0.9 * stride, 0.4 * stride),
                gravity: Vector3(-1, 0, 0)
            )
        }
    }

    /// Golpe seco sin swing: chocar la pala con el compañero, botar la pelota fuerte.
    static func tapWithoutSwing(startMs: Int64, impactG: Float = 6) -> [MotionSample] {
        let steps = 20
        let impactIndex = 10
        return (0...steps).map { i in
            let fromImpactMs = Float(i - impactIndex) * Float(sampleIntervalMs)
            let normalized = fromImpactMs / impactSigmaMs
            let spike = impactG * exp(-(normalized * normalized))
            return MotionSample(
                timestampMs: startMs + Int64(i) * sampleIntervalMs,
                accel: Vector3(baselineAccelG + spike, 0, 0),
                gyro: Vector3(0.8, 0.5, 0.2),
                gravity: Vector3(-1, 0, 0)
            )
        }
    }

    // MARK: Golpeos tipo, con parámetros dentro del rango de un jugador adulto medio

    static func forehand(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 20, swingDurationMs: 300, impactG: 6.5,
              axialFraction: 0.8, elevationDeg: -40)
    }

    static func backhand(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 18, swingDurationMs: 300, impactG: 5.5,
              axialFraction: -0.8, elevationDeg: -40)
    }

    static func forehandVolley(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 7, swingDurationMs: 280, impactG: 4.0,
              axialFraction: 0.2, elevationDeg: -25)
    }

    static func backhandVolley(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 7, swingDurationMs: 280, impactG: 4.0,
              axialFraction: -0.2, elevationDeg: -25)
    }

    /// Bandeja: golpe alto de control, plano y sin violencia.
    static func bandeja(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 15, swingDurationMs: 250, impactG: 6,
              axialFraction: 0.2, elevationDeg: 20)
    }

    /// Víbora: golpe alto con efecto lateral claro sin la violencia del remate. Los
    /// números vienen de pista (ago 2026): las víboras reales picaron 9.2-14.3 rad/s
    /// (los remates, 10.6-21.4) con |axial| 4.1-5.4.
    static func vibora(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 13, swingDurationMs: 240, impactG: 8,
              axialFraction: 0.5, elevationDeg: 15)
    }

    /// Smash: el remate — violento y corto, con el pico de giro por encima de todo.
    static func smash(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 30, swingDurationMs: 170, impactG: 10,
              axialFraction: 0.3, elevationDeg: 25)
    }

    /// Saque: BAJO como el del pádel — se arma a la cintura — con un barrido enorme.
    static func serve(startMs: Int64) -> [MotionSample] {
        swing(startMs: startMs, peakGyroRadS: 28, swingDurationMs: 350, impactG: 9,
              axialFraction: 0.6, elevationDeg: -30)
    }
}
