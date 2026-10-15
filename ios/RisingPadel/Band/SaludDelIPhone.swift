import Foundation
import HealthKit
import PadelCore

/// Lee entrenamientos de **Apple Salud en el iPhone**, para los partidos que no se
/// jugaron con nuestro reloj.
///
/// ## Por qué hace falta y qué no es
///
/// Hasta ahora solo el reloj hablaba con Salud, y lo hacía para **escribir** el
/// entrenamiento. Esto es lo contrario: leer lo que haya escrito otro. Si el jugador juega
/// con una pulsera ajena y su app guarda el entrenamiento en Salud, de ahí sale la
/// duración, el pulso y las calorías de ese partido sin que nadie los copie a mano.
///
/// **No sustituye al reloj ni de lejos.** Salud no tiene ningún tipo de dato para "golpe
/// de pádel": no hay golpes, ni tipos de golpe, ni nivel técnico. Lo que da es el esfuerzo
/// —cuánto duró, a qué pulso, cuántas calorías— y eso es exactamente lo que le falta a una
/// captura de pantalla, que trae los golpes y no el esfuerzo. Las dos piezas juntas hacen
/// un partido completo; cada una por separado, medio.
///
/// ## Quién escribe no se filtra, a propósito
///
/// No se pregunta qué app escribió el entrenamiento. Podría ser la de la pulsera, podría
/// ser el propio Apple Watch con la app de Entreno de Apple, podría ser una app de
/// terceros. Filtrar por origen obligaría a mantener una lista de nombres de apps que
/// cambia cada actualización, y el dato es igual de bueno venga de donde venga: lo que
/// importa es que el entrenamiento esté en las horas que el jugador dice que jugó. Lo que
/// sí se enseña es la app que lo escribió, para que pueda reconocerlo.
@MainActor
final class SaludDelIPhone: ObservableObject {

    /// Un entrenamiento de Salud, ya resumido en lo que la liga sabe guardar.
    struct Entrenamiento: Identifiable, Equatable {
        let id: UUID
        let inicio: Date
        let duracionMin: Int
        let pulsoMedio: Int?
        let pulsoMax: Int?
        let calorias: Int?
        let pasos: Int?
        /// Qué actividad declaró la app que lo escribió ("Tenis", "Entrenamiento
        /// funcional"…). Se enseña porque es lo que permite reconocer el partido.
        let actividad: String
        /// La app que lo escribió. Misma razón.
        let origen: String

        /// Lo que la liga guarda de la salud de un partido.
        var comoSalud: LigaSaludPartido {
            LigaSaludPartido(
                duracionMin: duracionMin,
                pulsoMedio: pulsoMedio,
                pulsoMax: pulsoMax,
                calorias: calorias,
                pasos: pasos
            )
        }
    }

    @Published private(set) var entrenamientos: [Entrenamiento] = []
    @Published private(set) var buscando = false
    /// Lo que hay que contarle al jugador cuando no se puede hacer lo que pidió.
    @Published var aviso: String?

    private let store = HKHealthStore()

    static var disponible: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Los tipos que se piden, y **solo** esos.
    ///
    /// Nada de escritura: esta app, en el iPhone, no guarda nada en Salud. Y de lectura,
    /// lo mínimo que hace falta para rellenar `LigaSaludPartido` — pedir más datos "por si
    /// acaso" es pedirle al usuario permiso sobre su salud para nada.
    private var aLeer: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
        ]
    }

    /// Pide permiso. Devuelve false si el usuario lo deniega o si el dispositivo no tiene
    /// Salud.
    ///
    /// Ojo con una trampa de HealthKit: para los datos de **lectura**, el sistema no dice
    /// nunca si el usuario concedió o denegó — es deliberado, porque saberlo ya filtraría
    /// información de salud. Así que `true` aquí significa "la pantalla de permisos se
    /// mostró sin error", no "hay acceso". Si luego no aparece ningún entrenamiento, puede
    /// ser que no haya ninguno o que no haya permiso, y las dos cosas se le cuentan igual
    /// porque no se pueden distinguir.
    func pedirPermiso() async -> Bool {
        guard Self.disponible else {
            aviso = "Este dispositivo no tiene Salud."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: [], read: aLeer)
            return true
        } catch {
            aviso = "No se pudo pedir permiso a Salud."
            return false
        }
    }

    /// Busca entrenamientos en un día concreto, de la medianoche a la medianoche local.
    ///
    /// El día entero y no una ventana estrecha: el jugador se acuerda del día que jugó, no
    /// de la hora a la que empezó. Luego elige el entrenamiento de la lista.
    func buscar(enElDia dia: Date) async {
        guard Self.disponible else {
            aviso = "Este dispositivo no tiene Salud."
            return
        }
        buscando = true
        defer { buscando = false }

        let calendario = Calendar.current
        let desde = calendario.startOfDay(for: dia)
        guard let hasta = calendario.date(byAdding: .day, value: 1, to: desde) else { return }

        let encontrados = await workouts(desde: desde, hasta: hasta)
        var resumidos: [Entrenamiento] = []
        for workout in encontrados {
            resumidos.append(await resumir(workout))
        }
        // El más largo primero: entre un partido de hora y media y un paseo de diez
        // minutos del mismo día, el partido es el que se está buscando.
        entrenamientos = resumidos.sorted { $0.duracionMin > $1.duracionMin }
        if entrenamientos.isEmpty {
            aviso = "No hay entrenamientos ese día en Salud. Puede ser que no los haya o "
                + "que la app no tenga permiso: Salud no permite distinguirlo."
        } else {
            aviso = nil
        }
    }

    // MARK: Consultas

    private func workouts(desde: Date, hasta: Date) async -> [HKWorkout] {
        let predicado = HKQuery.predicateForSamples(withStart: desde, end: hasta)
        return await withCheckedContinuation { continuacion in
            let consulta = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicado,
                limit: 50,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, muestras, _ in
                continuacion.resume(returning: (muestras as? [HKWorkout]) ?? [])
            }
            store.execute(consulta)
        }
    }

    private func resumir(_ workout: HKWorkout) async -> Entrenamiento {
        let (medio, maximo) = await pulso(en: workout)
        return Entrenamiento(
            id: workout.uuid,
            inicio: workout.startDate,
            duracionMin: Int((workout.duration / 60).rounded()),
            pulsoMedio: medio,
            pulsoMax: maximo,
            calorias: calorias(de: workout),
            pasos: await pasos(en: workout),
            actividad: Self.nombreDeActividad(workout.workoutActivityType),
            origen: workout.sourceRevision.source.name
        )
    }

    /// Pulso medio y máximo dentro del entrenamiento.
    ///
    /// Se pregunta por el rango del entrenamiento y no se usa ninguna media global del
    /// día: el pulso de la comida posterior no es el del partido.
    private func pulso(en workout: HKWorkout) async -> (Int?, Int?) {
        let predicado = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate
        )
        return await withCheckedContinuation { continuacion in
            let consulta = HKStatisticsQuery(
                quantityType: HKQuantityType(.heartRate),
                quantitySamplePredicate: predicado,
                options: [.discreteAverage, .discreteMax]
            ) { _, estadisticas, _ in
                let unidad = HKUnit.count().unitDivided(by: .minute())
                let medio = estadisticas?.averageQuantity()?.doubleValue(for: unidad)
                let maximo = estadisticas?.maximumQuantity()?.doubleValue(for: unidad)
                continuacion.resume(
                    returning: (medio.map { Int($0.rounded()) }, maximo.map { Int($0.rounded()) })
                )
            }
            store.execute(consulta)
        }
    }

    /// Los pasos dados durante el entrenamiento.
    ///
    /// Por consulta aparte y no desde el workout porque la mayoría de las apps no
    /// adjuntan los pasos al entrenamiento: los escribe el móvil o el reloj por su
    /// cuenta, y lo único que los relaciona con el partido es caer en sus horas.
    private func pasos(en workout: HKWorkout) async -> Int? {
        let predicado = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate
        )
        return await withCheckedContinuation { continuacion in
            let consulta = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicado,
                options: [.cumulativeSum]
            ) { _, estadisticas, _ in
                let suma = estadisticas?.sumQuantity()?.doubleValue(for: .count())
                continuacion.resume(returning: suma.map { Int($0.rounded()) })
            }
            store.execute(consulta)
        }
    }

    /// Las calorías activas que declara el propio entrenamiento.
    ///
    /// Del workout y no de una consulta aparte: la app que lo escribió ya hizo su cuenta,
    /// y sumar las muestras del rango por nuestra cuenta daría un número distinto del que
    /// el jugador ve en su propia app de salud. Dos números distintos para lo mismo es
    /// peor que un número.
    private func calorias(de workout: HKWorkout) -> Int? {
        let tipo = HKQuantityType(.activeEnergyBurned)
        guard let suma = workout.statistics(for: tipo)?.sumQuantity() else { return nil }
        return Int(suma.doubleValue(for: .kilocalorie()).rounded())
    }

    /// El nombre en español de los tipos de actividad que puede traer un partido de pádel.
    ///
    /// Pádel no existe como tipo en HealthKit, así que las apps usan lo que más se parece
    /// —tenis, squash, raqueta genérica— y nuestro propio reloj usa tenis. Los que no están
    /// en la lista salen como "Entrenamiento": inventar una traducción para los ciento y
    /// pico tipos de HealthKit no aporta nada aquí.
    private static func nombreDeActividad(_ tipo: HKWorkoutActivityType) -> String {
        switch tipo {
        case .tennis: return "Tenis"
        case .squash: return "Squash"
        case .racquetball: return "Racquetball"
        case .badminton: return "Bádminton"
        case .pickleball: return "Pickleball"
        case .tableTennis: return "Tenis de mesa"
        case .cardioDance, .highIntensityIntervalTraining: return "Cardio"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Fuerza"
        case .running: return "Carrera"
        case .walking: return "Caminar"
        case .other: return "Otro"
        default: return "Entrenamiento"
        }
    }
}
