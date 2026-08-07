import Foundation

/// Un intervalo de la sesión y cuántos golpeos cayeron dentro.
public struct FrequencyBucket: Equatable, Sendable {
    public let startMs: Int64
    public let endMs: Int64
    public let count: Int

    public init(startMs: Int64, endMs: Int64, count: Int) {
        self.startMs = startMs
        self.endMs = endMs
        self.count = count
    }
}

/// El nivel estimado en un instante de la sesión, mirando la ventana que lo precede.
public struct LevelPoint: Equatable, Sendable {
    public let offsetMs: Int64
    public let level: Float
    /// Golpeos que puntuaron en la ventana: con pocos, el punto es orientativo.
    public let gradedShots: Int

    public init(offsetMs: Int64, level: Float, gradedShots: Int) {
        self.offsetMs = offsetMs
        self.level = level
        self.gradedShots = gradedShots
    }
}

/// Todo lo que se puede decir de **un tipo de golpe** en una sesión.
///
/// Es la unidad que lee el jugador: nadie mira un golpeo suelto, mira "cómo fue mi
/// derecha hoy". Reúne las tres preguntas —cuántos, a qué velocidad y con qué
/// calidad— en un solo objeto para que la app no tenga que recalcular nada ni pueda
/// hacerlo distinto en iPhone y en Android.
public struct ShotBreakdown: Equatable, Sendable, Identifiable {
    public let type: ShotType
    public let count: Int
    public let meanKmh: Float
    public let maxKmh: Float
    /// Fracción del total de golpeos de la sesión, 0 a 1.
    public let share: Float
    /// Nota del golpe en la escala 1-7, o nil si ninguno puntuó (poca confianza del
    /// detector o tipo sin banda). Nil es "no lo sé", que no es lo mismo que un 1.
    public let grade: Float?
    /// Regularidad de ese golpe: 0 = cada uno de su padre y de su madre, 1 = calcados.
    /// Nil con menos de dos golpeos puntuados — con uno solo no hay regularidad de la
    /// que hablar.
    public let consistency: Float?
    /// Milisegundo de la sesión de cada golpeo, para pintar cuándo se dieron.
    public let offsetsMs: [Int64]

    public var id: ShotType { type }

    public init(
        type: ShotType, count: Int, meanKmh: Float, maxKmh: Float, share: Float,
        grade: Float?, consistency: Float?, offsetsMs: [Int64]
    ) {
        self.type = type
        self.count = count
        self.meanKmh = meanKmh
        self.maxKmh = maxKmh
        self.share = share
        self.grade = grade
        self.consistency = consistency
        self.offsetsMs = offsetsMs
    }
}

/// Series listas para pintar a partir de los golpeos de una sesión.
///
/// Vive en el core y no en las apps por la misma razón que el nivel: las dos plataformas
/// tienen que enseñar exactamente las mismas curvas para los mismos golpeos, y los tests
/// del core Kotlin fijan el comportamiento. Las apps solo dibujan.
public struct SessionAnalytics: Sendable {

    public static let defaultStepMs: Int64 = 5 * 60_000
    public static let defaultWindowMs: Int64 = 15 * 60_000

    /// Los dos zooms que ofrece la UI de frecuencia.
    public static let interval5MinMs: Int64 = 5 * 60_000
    public static let interval10MinMs: Int64 = 10 * 60_000

    private let estimator: LevelEstimator

    public init(estimator: LevelEstimator = LevelEstimator()) {
        self.estimator = estimator
    }

    /// Golpeos por intervalo de tiempo, cubriendo la sesión entera.
    ///
    /// Devuelve **todos** los intervalos, también los vacíos: en la gráfica un hueco de
    /// cinco minutos sin golpeos es información (un descanso, un set perdido de paliza),
    /// no un dato que falte.
    public func shotFrequency(
        _ shots: [Shot], durationMs: Int64, intervalMs: Int64
    ) -> [FrequencyBucket] {
        precondition(intervalMs > 0, "intervalMs debe ser positivo")
        guard durationMs > 0 else { return [] }

        let bucketCount = Int((durationMs + intervalMs - 1) / intervalMs)
        var counts = [Int](repeating: 0, count: bucketCount)
        for shot in shots {
            // Un offset fuera de rango (relojes con redondeos raros) se acota al borde
            // en vez de descartarse: el golpeo existió y tiene que contar en algún sitio.
            let index = min(max(Int(shot.offsetMs / intervalMs), 0), bucketCount - 1)
            counts[index] += 1
        }
        return (0..<bucketCount).map { index in
            FrequencyBucket(
                startMs: Int64(index) * intervalMs,
                endMs: min(Int64(index + 1) * intervalMs, durationMs),
                count: counts[index]
            )
        }
    }

    /// El nivel de la sesión a lo largo del tiempo: un punto cada `stepMs`, estimado
    /// sobre los golpeos de la ventana de `windowMs` anterior a ese instante.
    ///
    /// Es una ventana deslizante y no un acumulado a propósito: el acumulado converge a
    /// la media y se aplana, y lo que interesa ver es si el jugador vino arriba, se cayó
    /// en el segundo set o remontó. Los instantes sin ningún golpeo puntuado en la
    /// ventana no emiten punto: dibujar un nivel sin golpeos sería inventar.
    public func levelProgression(
        _ shots: [Shot],
        durationMs: Int64,
        stepMs: Int64 = SessionAnalytics.defaultStepMs,
        windowMs: Int64 = SessionAnalytics.defaultWindowMs
    ) -> [LevelPoint] {
        precondition(stepMs > 0, "stepMs debe ser positivo")
        precondition(windowMs > 0, "windowMs debe ser positivo")
        guard durationMs > 0, !shots.isEmpty else { return [] }

        // Bucle a mano y no `stride`: el `Stride` de Int64 es `Int`, que en los relojes
        // arm64_32 es de 32 bits — la misma trampa que ya mordió con las épocas.
        var instants: [Int64] = []
        var next = stepMs
        while next < durationMs {
            instants.append(next)
            next += stepMs
        }
        instants.append(durationMs) // El último punto cae en el final real, no en el múltiplo.

        return instants.compactMap { instant in
            let window = shots.filter { $0.offsetMs > instant - windowMs && $0.offsetMs <= instant }
            let level = estimator.estimate(window)
            guard level.gradedShots > 0 else { return nil }
            return LevelPoint(offsetMs: instant, level: level.overall, gradedShots: level.gradedShots)
        }
    }

    /// Nota media (1-7) de un tipo de golpe en la sesión, o nil si no hay ninguno que
    /// puntúe. Es lo que alimenta el filtro "por golpe" del histórico.
    public func typeGrade(_ shots: [Shot], type: ShotType) -> Float? {
        let grades = shots.filter { $0.type == type }.compactMap { estimator.grade($0) }
        guard !grades.isEmpty else { return nil }
        return grades.reduce(0, +) / Float(grades.count)
    }

    /// Un resumen por tipo de golpe, del más usado al menos usado.
    ///
    /// Ordenado por cantidad a propósito: lo primero que quiere saber cualquiera es en
    /// qué golpe se le fue el partido, y ese es casi siempre el que más repitió. Los
    /// tipos sin ningún golpeo no aparecen — una fila a cero no es información, es ruido.
    public func shotBreakdown(_ shots: [Shot]) -> [ShotBreakdown] {
        guard !shots.isEmpty else { return [] }
        let total = Float(shots.count)
        let porTipo = Dictionary(grouping: shots, by: { $0.type })
        let orden = ShotType.allCases

        return porTipo.map { type, delTipo -> ShotBreakdown in
            let grades = delTipo.compactMap { estimator.grade($0) }
            return ShotBreakdown(
                type: type,
                count: delTipo.count,
                meanKmh: delTipo.reduce(0) { $0 + $1.racketSpeedKmh } / Float(delTipo.count),
                maxKmh: delTipo.map(\.racketSpeedKmh).max() ?? 0,
                share: Float(delTipo.count) / total,
                grade: grades.isEmpty ? nil : grades.reduce(0, +) / Float(grades.count),
                consistency: grades.count < 2 ? nil : Self.regularidad(grades),
                offsetsMs: delTipo.map(\.offsetMs).sorted()
            )
        }
        // A igualdad de golpeos manda el orden del enum, para que dos sesiones iguales
        // no salgan en orden distinto según cómo cayeron en el diccionario.
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            let a = orden.firstIndex(of: $0.type) ?? 0
            let b = orden.firstIndex(of: $1.type) ?? 0
            return a < b
        }
    }

    /// La misma regularidad que usa el nivel, pero de un solo golpe: cuánto se parecen
    /// entre sí sus notas. Se comparte la escala (1,5 niveles de desviación ya es mucho)
    /// para que "regular" signifique lo mismo en la ficha del golpe y en el nivel global.
    private static func regularidad(_ grades: [Float]) -> Float {
        let mean = grades.reduce(0, +) / Float(grades.count)
        let variance = grades.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(grades.count)
        return min(max(1 - sqrt(variance) / maxMeaningfulDeviation, 0), 1)
    }

    /// Misma escala que la regularidad del nivel: sin esto, dos "regular" distintos.
    public static let maxMeaningfulDeviation: Float = 1.5
}
