import Foundation
import HealthKit
import PadelCore

/// Métricas de salud del entrenamiento, ya normalizadas.
struct WorkoutMetrics: Equatable {
    var heartRateBpm: Int?
    var activeEnergyKcal: Float?
    var totalEnergyKcal: Float?
    var steps: Int?
    var distanceMeters: Float?
}

/// Envoltorio de HealthKit para el workout del reloj.
///
/// El tipo de actividad es `.tennis`: HealthKit no tiene pádel, y tenis es el perfil más
/// parecido en patrón de esfuerzo (intervalos cortos e intensos con desplazamientos
/// laterales), así que es el que mejor estima calorías.
final class WorkoutManager: NSObject {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Se llama en cada actualización de HealthKit (≈1 Hz).
    var onMetrics: ((WorkoutMetrics) -> Void)?

    private var metrics = WorkoutMetrics()

    static var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Pide permiso solo para lo que se va a usar.
    ///
    /// Sin métricas se pide **únicamente** poder crear el workout, que es lo que
    /// mantiene viva la captura de sensores: no se pide leer frecuencia cardiaca ni
    /// nada más, así que el sistema no concede acceso a datos de salud que no se van a
    /// mirar.
    func requestAuthorization(includeMetrics: Bool) async -> Bool {
        guard Self.isSupported else { return false }

        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = includeMetrics
            ? [
                HKQuantityType(.heartRate),
                HKQuantityType(.activeEnergyBurned),
                HKQuantityType(.basalEnergyBurned),
                HKQuantityType(.stepCount),
                HKQuantityType(.distanceWalkingRunning),
                HKObjectType.activitySummaryType(),
            ]
            : []

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: share, read: read) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Arranca el workout.
    ///
    /// - Parameter collectMetrics: con `false` se crea la sesión **sin** recolector: no
    ///   se lee ni se guarda ningún dato de salud, y al cerrarla no queda entrenamiento
    ///   en la app Salud. La sesión se arranca igualmente porque en watchOS es lo que
    ///   impide que el sistema suspenda la app y corte el acelerómetro al apagarse la
    ///   pantalla — ver `docs/setup.md`.
    func start(collectMetrics: Bool) throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        session.delegate = self
        self.session = session

        let startDate = Date()

        if collectMetrics {
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            // Los pasos hay que pedirlos a mano: el recolector de un entrenamiento de
            // tenis trae de serie pulso, energía y distancia, pero no `stepCount`, así
            // que la casilla de pasos de la ficha salía siempre vacía. En pádel es un
            // dato con sentido — se anda mucho en una pista pequeña.
            dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
            builder.dataSource = dataSource
            builder.delegate = self
            self.builder = builder
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }
        } else {
            session.startActivity(with: startDate)
        }
    }

    /// Pausa y reanuda el workout del sistema: congela los anillos y las métricas de
    /// Salud mientras el partido está parado (agua, cambio de pista largo, charla).
    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    /// Cierra el workout y, si se estaban recogiendo métricas, lo guarda en Salud. No
    /// propaga errores: una sesión medida es más valiosa que un fallo al archivarla, y
    /// los golpeos ya están en memoria.
    func end() async {
        guard let session else { return }
        session.end()

        if let builder {
            let endDate = Date()
            await withCheckedContinuation { continuation in
                builder.endCollection(withEnd: endDate) { _, _ in
                    builder.finishWorkout { _, _ in
                        continuation.resume()
                    }
                }
            }
        }
        self.session = nil
        self.builder = nil
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            apply(statistics, for: quantityType)
        }
        onMetrics?(metrics)
    }

    private func apply(_ statistics: HKStatistics, for type: HKQuantityType) {
        switch type {
        case HKQuantityType(.heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            if let bpm = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
                metrics.heartRateBpm = Int(bpm.rounded())
            }

        case HKQuantityType(.activeEnergyBurned):
            if let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                metrics.activeEnergyKcal = Float(kcal)
            }

        case HKQuantityType(.basalEnergyBurned):
            if let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                metrics.totalEnergyKcal = (metrics.activeEnergyKcal ?? 0) + Float(kcal)
            }

        case HKQuantityType(.stepCount):
            if let steps = statistics.sumQuantity()?.doubleValue(for: .count()) {
                metrics.steps = Int(steps)
            }

        case HKQuantityType(.distanceWalkingRunning):
            if let meters = statistics.sumQuantity()?.doubleValue(for: .meter()) {
                metrics.distanceMeters = Float(meters)
            }

        default:
            break
        }
    }
}
