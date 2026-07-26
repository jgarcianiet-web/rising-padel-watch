import CoreMotion
import Foundation
import PadelCore

/// Entrega `MotionSample` normalizadas desde CoreMotion.
///
/// Se usa `deviceMotion` y no el acelerómetro crudo porque CoreMotion ya separa la
/// gravedad de la aceleración del usuario con la fusión de sensores: hacerlo a mano con
/// un filtro paso alto sería peor y más caro en batería.
///
/// El handler llega en una `OperationQueue` propia, así que el detector corre fuera del
/// hilo principal y la UI del reloj no se resiente.
final class MotionRecorder {

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.risingpadel.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    var isAvailable: Bool { motionManager.isDeviceMotionAvailable }

    /// - Parameter onSample: se llama en la cola de sensores, **no** en la principal.
    func start(sampleRateHz: Int, onSample: @escaping (MotionSample) -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / Double(sampleRateHz)
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: queue
        ) { motion, _ in
            guard let motion else { return }
            onSample(Self.sample(from: motion))
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    private static func sample(from motion: CMDeviceMotion) -> MotionSample {
        MotionSample(
            // `motion.timestamp` son segundos desde el arranque del dispositivo: es
            // monótono, que es justo lo que necesita el detector.
            timestampMs: Int64(motion.timestamp * 1000),
            accel: Vector3(
                Float(motion.userAcceleration.x),
                Float(motion.userAcceleration.y),
                Float(motion.userAcceleration.z)
            ),
            gyro: Vector3(
                Float(motion.rotationRate.x),
                Float(motion.rotationRate.y),
                Float(motion.rotationRate.z)
            ),
            gravity: Vector3(
                Float(motion.gravity.x),
                Float(motion.gravity.y),
                Float(motion.gravity.z)
            )
        )
    }
}
