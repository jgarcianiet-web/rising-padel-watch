import Foundation

/// Una muestra de los sensores de la muñeca.
///
/// Las unidades están normalizadas para que watchOS y Wear OS entreguen exactamente lo
/// mismo al detector:
///
/// - `timestampMs`: instante monótono en milisegundos (no epoch: no debe saltar si el
///   reloj corrige su hora). En watchOS sale de `CMDeviceMotion.timestamp`.
/// - `accel`: aceleración del usuario en **g**, ya sin gravedad (`userAcceleration`).
/// - `gyro`: velocidad angular en **rad/s** (`rotationRate`).
/// - `gravity`: vector gravedad en **g** (`gravity`). Apunta hacia abajo.
public struct MotionSample: Equatable, Sendable {
    public let timestampMs: Int64
    public let accel: Vector3
    public let gyro: Vector3
    public let gravity: Vector3

    public init(timestampMs: Int64, accel: Vector3, gyro: Vector3, gravity: Vector3) {
        self.timestampMs = timestampMs
        self.accel = accel
        self.gyro = gyro
        self.gravity = gravity
    }
}
