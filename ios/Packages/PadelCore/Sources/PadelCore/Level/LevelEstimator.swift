import Foundation

/// Nivel técnico estimado de una sesión, en la escala de pádel de 1 a 7.
public struct SessionLevel: Equatable, Sendable {
    /// Nivel global, ya con los ajustes de regularidad y repertorio.
    public let overall: Float
    /// Nivel medio de cada tipo de golpe con muestras suficientes.
    public let byShotType: [ShotType: Float]
    /// 0 = golpeos muy dispares, 1 = muy regular.
    public let consistency: Float
    /// 0 = un solo tipo de golpe, 1 = repertorio completo.
    public let repertoire: Float
    /// Golpeos que han puntuado. Los de tipo desconocido no cuentan.
    public let gradedShots: Int
    /// false si no hay golpeos suficientes. **El nivel se sigue calculando**, pero la UI
    /// debe presentarlo como provisional en vez de esconderlo: un jugador que ha dado 20
    /// golpes prefiere ver una estimación con aviso que un hueco.
    public let reliable: Bool

    public init(
        overall: Float,
        byShotType: [ShotType: Float],
        consistency: Float,
        repertoire: Float,
        gradedShots: Int,
        reliable: Bool
    ) {
        self.overall = overall
        self.byShotType = byShotType
        self.consistency = consistency
        self.repertoire = repertoire
        self.gradedShots = gradedShots
        self.reliable = reliable
    }

    /// El nivel redondeado a medio punto, que es como se habla de nivel en un club.
    public var rounded: Float { (overall * 2).rounded() / 2 }

    /// Etiqueta corta para enseñar el nivel sin decimales inventados.
    public var label: String {
        reliable ? "Nivel \(rounded)" : "Nivel ~\(rounded) (pocos golpeos)"
    }
}

/// Puntúa cada golpeo de 1 a 7 y saca el nivel técnico de la sesión.
///
/// Es una **heurística sin validar**: puntúa lo que el giróscopo puede ver —lo rápido que
/// va la pala y qué forma tiene el swing— y de ahí infiere un nivel. No ve la colocación,
/// ni la lectura de la pared, ni la táctica, que en pádel pesan tanto como el golpeo. Ver
/// `docs/level.md` para lo que mide, lo que no, y cómo calibrarlo.
public struct LevelEstimator: Sendable {

    private let config: LevelConfig

    public init(config: LevelConfig = .default) {
        self.config = config
    }

    /// Nota de un golpeo suelto, de 1 a 7.
    ///
    /// Devuelve nil si el tipo es desconocido o la clasificación no es fiable: puntuar un
    /// golpeo que no se sabe qué es sería inventar.
    public func grade(_ shot: Shot) -> Float? {
        guard shot.type != .unknown,
              shot.confidence >= config.minConfidence,
              let band = config.bands[shot.type] else { return nil }

        let speedScore = Self.interpolate(
            shot.racketSpeedKmh, from: band.speedAtLevel1, to: band.speedAtLevel7
        )
        let swing = Self.swingScore(shot.features.sweptAngleDeg, band: band)

        let blended = speedScore * config.speedWeight + swing * (1 - config.speedWeight)
        return Self.toLevel(blended)
    }

    public func estimate(_ shots: [Shot]) -> SessionLevel {
        let graded: [(ShotType, Float)] = shots.compactMap { shot in
            grade(shot).map { (shot.type, $0) }
        }

        guard !graded.isEmpty else {
            return SessionLevel(
                overall: LevelConfig.minLevel,
                byShotType: [:],
                consistency: 0,
                repertoire: 0,
                gradedShots: 0,
                reliable: false
            )
        }

        var byType: [ShotType: [Float]] = [:]
        for (type, value) in graded { byType[type, default: []].append(value) }

        // La media es por tipo de golpe y no por golpeo suelto: si no, una sesión con 200
        // derechas y 5 voleas sería "el nivel de derecha del jugador" con otro nombre.
        let perTypeMeans = byType.values.map { Self.mean($0) }
        let mean = Self.mean(perTypeMeans)

        let consistency = self.consistency(byType)
        let repertoire = self.repertoire(byType, total: graded.count)

        let overall = min(
            max(
                mean
                    - (1 - consistency) * config.maxConsistencyPenalty
                    + repertoire * config.maxRepertoireBonus,
                LevelConfig.minLevel
            ),
            LevelConfig.maxLevel
        )

        return SessionLevel(
            overall: overall,
            byShotType: byType.mapValues { Self.round1(Self.mean($0)) },
            consistency: Self.round2(consistency),
            repertoire: Self.round2(repertoire),
            gradedShots: graded.count,
            reliable: graded.count >= config.minShotsForEstimate
        )
    }

    /// Regularidad: cuánto se parecen entre sí los golpeos del mismo tipo.
    ///
    /// En pádel el nivel **es** regularidad. Dos jugadores con la misma derecha máxima no
    /// son el mismo nivel si uno la repite treinta veces y el otro una de cada cinco. Se
    /// mide dentro de cada tipo y no sobre el total, porque la diferencia natural entre
    /// una volea y un smash no es irregularidad del jugador.
    private func consistency(_ byType: [ShotType: [Float]]) -> Float {
        let deviations = byType.values
            .filter { $0.count >= 2 }
            .map { Self.standardDeviation($0) }
        guard !deviations.isEmpty else { return Self.noDataConsistency }

        let average = Self.mean(deviations)
        // Una desviación de 1.5 niveles dentro del mismo golpe es ya muy irregular.
        return min(max(1 - average / Self.maxMeaningfulDeviation, 0), 1)
    }

    /// Repertorio: cuántos tipos de golpe distintos usa con soltura.
    ///
    /// Solo **suma**, nunca resta: una sesión de entrenamiento de solo derechas no
    /// significa que el jugador no sepa volear, y penalizarla sería castigar entrenar.
    private func repertoire(_ byType: [ShotType: [Float]], total: Int) -> Float {
        guard total >= config.minShotsForEstimate else { return 0 }
        let used = byType.values.filter { $0.count >= config.minShotsPerTypeForRepertoire }.count
        return min(max(Float(used) / Float(config.bands.count), 0), 1)
    }

    /// Amplitud del swing: 0 = lejos de la referencia, 1 = en ella.
    private static func swingScore(_ sweptDeg: Float, band: ShotBand) -> Float {
        if band.compactIsBetter {
            // Por debajo del ideal no se penaliza: una volea muy corta es correcta.
            guard sweptDeg > band.idealSweptDeg else { return 1 }
            let excess = sweptDeg - band.idealSweptDeg
            return min(max(1 - excess / band.idealSweptDeg, 0), 1)
        }
        return min(max(sweptDeg / band.idealSweptDeg, 0), 1)
    }

    /// Posición de `value` en el rango, acotada a [0, 1].
    private static func interpolate(_ value: Float, from atLevel1: Float, to atLevel7: Float) -> Float {
        guard atLevel7 > atLevel1 else { return 0 }
        return min(max((value - atLevel1) / (atLevel7 - atLevel1), 0), 1)
    }

    /// Un 0..1 pasado a la escala 1..7.
    private static func toLevel(_ normalized: Float) -> Float {
        round1(LevelConfig.minLevel + normalized * (LevelConfig.maxLevel - LevelConfig.minLevel))
    }

    private static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func standardDeviation(_ values: [Float]) -> Float {
        let m = mean(values)
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(values.count)
        return variance.squareRoot()
    }

    private static func round1(_ value: Float) -> Float { (value * 10).rounded() / 10 }
    private static func round2(_ value: Float) -> Float { (value * 100).rounded() / 100 }

    /// Con un golpeo por tipo no se puede hablar de regularidad; ni premia ni castiga.
    private static let noDataConsistency: Float = 0.5
    private static let maxMeaningfulDeviation: Float = 1.5
}
