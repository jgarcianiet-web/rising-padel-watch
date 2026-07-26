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

    /// Pide permiso solo para lo que se usa. Si el usuario deniega, la sesión sigue
    /// contando golpeos: los datos de salud son opcionales por diseño.
    func requestAuthorization() async -> Bool {
        guard Self.isSupported else { return false }

        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKObjectType.activitySummaryType(),
        ]

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: share, read: read) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder

        let startDate = Date()
        session.startActivity(with: startDate)
        builder.beginCollection(withStart: startDate) { _, _ in }
    }

    /// Cierra el workout y lo guarda en Salud. No propaga errores: una sesión medida es
    /// más valiosa que un fallo al archivarla, y los golpeos ya están en memoria.
    func end() async {
        guard let session, let builder else { return }
        let endDate = Date()
        session.end()
        await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: endDate) { _, _ in
                builder.finishWorkout { _, _ in
                    continuation.resume()
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
