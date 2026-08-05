import Foundation

/// Las tres familias de ideas que la app enseña al acabar una sesión.
public enum InsightCategory: String, Sendable, CaseIterable {
    /// Qué pasó en el partido: los momentos que lo movieron.
    case matchAnalysis
    /// Cómo juegas: en qué eres fuerte y en qué no.
    case strengths
    /// Qué hacer la próxima vez.
    case training

    public var title: String {
        switch self {
        case .matchAnalysis: return "Análisis del partido"
        case .strengths: return "Fortalezas y debilidades"
        case .training: return "Sugerencias de entrenamiento"
        }
    }

    public var symbol: String {
        switch self {
        case .matchAnalysis: return "target"
        case .strengths: return "figure.strengthtraining.traditional"
        case .training: return "trophy.fill"
        }
    }
}

/// Una idea concreta sobre la sesión, con el número que la sostiene.
public struct Insight: Equatable, Sendable, Identifiable {
    public let category: InsightCategory
    public let headline: String
    public let detail: String
    /// Golpeos (o lecturas) que respaldan la idea. La UI lo enseña porque una afirmación
    /// sobre 12 golpeos y otra sobre 300 no valen lo mismo.
    public let evidence: Int

    public var id: String { "\(category.rawValue)-\(headline)" }

    public init(category: InsightCategory, headline: String, detail: String, evidence: Int) {
        self.category = category
        self.headline = headline
        self.detail = detail
        self.evidence = evidence
    }
}

/// Saca conclusiones en lenguaje llano de una sesión.
///
/// **Cada frase sale de una cuenta sobre los datos del jugador, no de un texto genérico.**
/// Es la diferencia entre un consejo que se puede comprobar ("en los puntos largos tu
/// nivel sube de 3.4 a 4.1") y uno de horóscopo ("sé más paciente"). Una regla que no
/// llega al mínimo de evidencia no dice nada: preferimos tres ideas sólidas a diez
/// inventadas.
///
/// Todo se calcula en el dispositivo: no hace falta red ni mandar la sesión a ningún
/// sitio para tener las ideas. Un modelo de lenguaje puede después redactar el resumen a
/// partir de estos hechos —esa es la parte que hace bien—, pero los hechos salen de aquí.
public struct InsightEngine: Sendable {

    private let estimator: LevelEstimator
    private let analytics: SessionAnalytics

    public init(
        estimator: LevelEstimator = LevelEstimator(),
        analytics: SessionAnalytics = SessionAnalytics()
    ) {
        self.estimator = estimator
        self.analytics = analytics
    }

    public func insights(for session: PadelSession) -> [Insight] {
        serveInsights(session)
            + rallyInsight(session.shots)
            + heartRateInsight(session)
            + fatigueInsight(session)
            + shotQualityInsights(session)
            + trainingSuggestions(session)
    }

    // MARK: Con el saque en la mano contra al resto

    /// Cuánto rindes sacando y cuánto restando.
    ///
    /// En pádel son dos partidos distintos: con el saque subes a la red desde el primer
    /// golpe, y restando tienes que ganártela. Un jugador que gana el 80% de sus juegos
    /// al saque y el 20% al resto no tiene un problema de golpeo, tiene un problema de
    /// subida.
    ///
    /// Se miran dos cosas por separado porque responden a preguntas distintas: **los
    /// juegos ganados** dicen el resultado, y **la calidad del golpeo** dice por qué.
    private func serveInsights(_ session: PadelSession) -> [Insight] {
        let games = session.games
        guard games.count >= Self.minGames else { return [] }
        var result: [Insight] = []

        let serving = games.filter { $0.server == .us }
        let returning = games.filter { $0.server == .them }
        if serving.count >= Self.minGamesPerSide, returning.count >= Self.minGamesPerSide {
            let wonServing = serving.filter { $0.winner == .us }.count
            let wonReturning = returning.filter { $0.winner == .us }.count
            let pctServing = Int((Float(wonServing) * 100 / Float(serving.count)).rounded())
            let pctReturning = Int((Float(wonReturning) * 100 / Float(returning.count)).rounded())

            if pctServing >= pctReturning {
                result.append(Insight(
                    category: .matchAnalysis,
                    headline: "Aguantas tu saque",
                    detail: "Ganaste \(wonServing) de \(serving.count) juegos con el saque en la "
                        + "mano (\(pctServing)%) y \(wonReturning) de \(returning.count) al resto "
                        + "(\(pctReturning)%). El partido se te va en los juegos de resto: ahí es "
                        + "donde más tienes que ganar.",
                    evidence: games.count
                ))
            } else {
                result.append(Insight(
                    category: .matchAnalysis,
                    headline: "Se te escapa tu saque",
                    detail: "Ganaste solo \(wonServing) de \(serving.count) juegos sacando "
                        + "(\(pctServing)%) frente a \(wonReturning) de \(returning.count) al "
                        + "resto (\(pctReturning)%). Perder el saque cuesta doble: revisa la "
                        + "subida a la red después de sacar.",
                    evidence: games.count
                ))
            }
        }

        // Calidad del golpeo en cada situación: explica el resultado de arriba.
        let servingShots = shotsWhileServing(session, server: .us)
        let returningShots = shotsWhileServing(session, server: .them)
        if servingShots.count >= Self.minEvidence, returningShots.count >= Self.minEvidence,
           let servingGrade = meanGrade(servingShots), let returningGrade = meanGrade(returningShots) {
            let delta = servingGrade - returningGrade
            if abs(delta) >= Self.minLevelDelta {
                let percent = percentChange(from: returningGrade, to: servingGrade)
                let advice = delta > 0
                    ? "Aprovecha los juegos de saque para ir por el partido; al resto, juega más "
                        + "seguro hasta poder subir."
                    : "Sacando te precipitas: el saque es solo la puesta en juego, el punto se "
                        + "gana en la red."
                result.append(Insight(
                    category: .strengths,
                    headline: delta > 0 ? "Juegas mejor sacando" : "Juegas mejor restando",
                    detail: "Con el saque tu nivel medio es \(format(servingGrade)) y al resto "
                        + "\(format(returningGrade)) (\(percent)%). " + advice,
                    evidence: servingShots.count + returningShots.count
                ))
            }
        }
        return result
    }

    /// Golpeos dados mientras sacaba un lado.
    ///
    /// Cada juego cubre desde el final del anterior hasta el suyo; el primero arranca en
    /// el inicio de la sesión. Los golpeos posteriores al último juego cerrado quedan
    /// fuera: pertenecen a un juego sin terminar y no se sabe quién lo ganará.
    public func shotsWhileServing(_ session: PadelSession, server: Side) -> [Shot] {
        var previousEnd: Int64 = 0
        var result: [Shot] = []
        for game in session.games {
            if game.server == server {
                result += session.shots.filter {
                    $0.offsetMs > previousEnd && $0.offsetMs <= game.offsetMs
                }
            }
            previousEnd = game.offsetMs
        }
        return result
    }

    // MARK: Puntos largos contra puntos cortos

    /// Agrupa los golpeos en puntos: un hueco largo entre dos golpeos significa que el
    /// punto acabó y se está sacando otra vez.
    public func rallies(_ shots: [Shot], gapMs: Int64 = 4_000) -> [[Shot]] {
        guard !shots.isEmpty else { return [] }
        let ordered = shots.sorted { $0.offsetMs < $1.offsetMs }
        var result: [[Shot]] = []
        var current: [Shot] = [ordered[0]]
        for shot in ordered.dropFirst() {
            if shot.offsetMs - (current.last?.offsetMs ?? 0) > gapMs {
                result.append(current)
                current = [shot]
            } else {
                current.append(shot)
            }
        }
        result.append(current)
        return result
    }

    private func rallyInsight(_ shots: [Shot]) -> [Insight] {
        let groups = rallies(shots)
        let longShots = groups.filter { $0.count >= Self.longRallyShots }.flatMap { $0 }
        let shortShots = groups.filter { $0.count <= Self.shortRallyShots }.flatMap { $0 }

        guard longShots.count >= Self.minEvidence, shortShots.count >= Self.minEvidence,
              let longGrade = meanGrade(longShots), let shortGrade = meanGrade(shortShots)
        else { return [] }

        let delta = longGrade - shortGrade
        guard abs(delta) >= Self.minLevelDelta else { return [] }
        let percent = percentChange(from: shortGrade, to: longGrade)

        if delta > 0 {
            return [Insight(
                category: .strengths,
                headline: "Creces en los puntos largos",
                detail: "En los puntos de \(Self.longRallyShots) golpeos o más tu nivel medio es "
                    + "\(format(longGrade)) frente a \(format(shortGrade)) en los cortos "
                    + "(\(percent)% mejor). Alargar el punto te favorece: ten paciencia y deja "
                    + "que el error lo cometa el rival.",
                evidence: longShots.count
            )]
        }
        return [Insight(
            category: .strengths,
            headline: "Te desgastan los puntos largos",
            detail: "En los puntos de \(Self.longRallyShots) golpeos o más tu nivel medio cae a "
                + "\(format(longGrade)) desde \(format(shortGrade)) en los cortos (\(percent)%). "
                + "Busca cerrar antes el punto, o entrena el aguante en el intercambio largo.",
            evidence: longShots.count
        )]
    }

    // MARK: Pulso contra rendimiento

    /// Cruza la serie de pulso con la calidad de los golpeos.
    ///
    /// La frontera es el pulso **medio de la sesión** y no un número fijo (160 ppm, por
    /// ejemplo) porque el pulso al que cada jugador se rompe depende de su edad y su
    /// forma física. Media y no mediana: una sesión suele tener dos mesetas de pulso, y
    /// con dos mesetas la mediana cae dentro de una y deja el otro lado vacío.
    private func heartRateInsight(_ session: PadelSession) -> [Insight] {
        let series = session.health.heartRateSeries
        guard series.count >= Self.minHrSamples else { return [] }

        let threshold = Float(series.map(\.bpm).reduce(0, +)) / Float(series.count)
        var high: [Float] = []
        var low: [Float] = []
        for shot in session.shots {
            guard let bpm = bpmAt(shot.offsetMs, series), let grade = estimator.grade(shot) else {
                continue
            }
            if Float(bpm) > threshold { high.append(grade) } else { low.append(grade) }
        }
        guard high.count >= Self.minEvidence, low.count >= Self.minEvidence else { return [] }

        let highGrade = high.reduce(0, +) / Float(high.count)
        let lowGrade = low.reduce(0, +) / Float(low.count)
        let delta = highGrade - lowGrade
        guard abs(delta) >= Self.minLevelDelta else { return [] }

        let bpmLabel = Int(threshold.rounded())
        let percent = percentChange(from: lowGrade, to: highGrade)

        if delta < 0 {
            return [Insight(
                category: .matchAnalysis,
                headline: "El pulso te pasa factura",
                detail: "Con el pulso por encima de \(bpmLabel) ppm tu nivel baja de "
                    + "\(format(lowGrade)) a \(format(highGrade)) (\(percent)%). Trabajar el "
                    + "fondo físico te daría más que cualquier cambio técnico.",
                evidence: high.count
            )]
        }
        return [Insight(
            category: .matchAnalysis,
            headline: "Juegas mejor enchufado",
            detail: "Con el pulso por encima de \(bpmLabel) ppm tu nivel sube de "
                + "\(format(lowGrade)) a \(format(highGrade)) (\(percent)%). Te cuesta arrancar: "
                + "calienta más antes de empezar.",
            evidence: high.count
        )]
    }

    /// Pulso vigente en un instante: la última lectura anterior o igual a él.
    private func bpmAt(_ offsetMs: Int64, _ series: [HeartRateSample]) -> Int? {
        series.last { $0.offsetMs <= offsetMs }?.bpm
    }

    // MARK: Cómo llegaste al final

    private func fatigueInsight(_ session: PadelSession) -> [Insight] {
        let points = analytics.levelProgression(
            session.shots,
            durationMs: session.durationSeconds * 1000
        )
        guard points.count >= 4 else { return [] }

        let third = points.count / 3
        guard third > 0 else { return [] }
        let start = points.prefix(third).map(\.level).reduce(0, +) / Float(third)
        let end = points.suffix(third).map(\.level).reduce(0, +) / Float(third)
        let delta = end - start
        guard abs(delta) >= Self.minLevelDelta else { return [] }

        let evidence = points.reduce(0) { $0 + $1.gradedShots }
        if delta < 0 {
            return [Insight(
                category: .matchAnalysis,
                headline: "Te fuiste apagando",
                detail: "Empezaste jugando a \(format(start)) y acabaste a \(format(end)). La "
                    + "diferencia está en el último tercio: o es cansancio o es concentración, "
                    + "y las dos se entrenan.",
                evidence: evidence
            )]
        }
        return [Insight(
            category: .matchAnalysis,
            headline: "Fuiste a más",
            detail: "Empezaste a \(format(start)) y acabaste a \(format(end)): entraste en calor "
                + "tarde. Un calentamiento más largo te ahorraría los primeros juegos.",
            evidence: evidence
        )]
    }

    // MARK: Tu mejor y tu peor golpe

    private func shotQualityInsights(_ session: PadelSession) -> [Insight] {
        let ranked = gradesByType(session)
            .sorted { $0.value.grade > $1.value.grade }
        guard ranked.count >= 2, let best = ranked.first, let worst = ranked.last else { return [] }
        guard best.value.grade - worst.value.grade >= Self.minLevelDelta else { return [] }

        return [Insight(
            category: .strengths,
            headline: "Tu golpe fuerte es \(label(best.key).lowercased())",
            detail: "\(label(best.key)) te sale a \(format(best.value.grade)) sobre "
                + "\(best.value.count) golpeos, mientras que \(label(worst.key).lowercased()) se "
                + "queda en \(format(worst.value.grade)). Construye el punto con el primero y "
                + "evita que el rival te busque el segundo.",
            evidence: best.value.count + worst.value.count
        )]
    }

    // MARK: Qué entrenar

    private func trainingSuggestions(_ session: PadelSession) -> [Insight] {
        let level = session.level
        guard level.gradedShots >= Self.minEvidence else { return [] }
        var result: [Insight] = []

        // Regularidad antes que potencia: en pádel el nivel es repetir.
        if level.consistency < Self.lowConsistency {
            result.append(Insight(
                category: .training,
                headline: "Repite, no pegues más fuerte",
                detail: "Tu regularidad es del \(Int((level.consistency * 100).rounded()))%: los "
                    + "golpeos del mismo tipo te salen muy distintos entre sí. Series de 20 bolas "
                    + "cruzadas buscando el mismo golpe, sin subir la potencia.",
                evidence: level.gradedShots
            ))
        }

        // Repertorio: solo suma. Que falte un golpe no es un defecto, es una oportunidad.
        let played = Set(session.shotsByType.keys.filter { $0 != .unknown })
        let missing: [ShotType] = [.bandeja, .vibora, .smash].filter { !played.contains($0) }
        if !missing.isEmpty, session.totalShots >= Self.minShotsForRepertoire {
            let list = missing.map { label($0).lowercased() }.joined(separator: " ni ")
            result.append(Insight(
                category: .training,
                headline: "Te falta el juego alto",
                detail: "En \(session.totalShots) golpeos no apareció \(list). O no te suben "
                    + "globos o los estás dejando botar: media hora de globos y salida de pared "
                    + "cambia el partido.",
                evidence: session.totalShots
            ))
        }

        // El golpe más flojo con muestras suficientes es lo más accionable que hay.
        if let worst = gradesByType(session).min(by: { $0.value.grade < $1.value.grade }),
           worst.value.grade < level.overall - Self.minLevelDelta {
            result.append(Insight(
                category: .training,
                headline: "Dedica la próxima sesión a \(label(worst.key).lowercased())",
                detail: "\(label(worst.key)) va a \(format(worst.value.grade)), por debajo de tu "
                    + "\(format(level.overall)) global. Es donde menos esfuerzo cuesta ganar "
                    + "nivel: 15 minutos de ese golpe al empezar, con el brazo fresco.",
                evidence: worst.value.count
            ))
        }
        return result
    }

    // MARK: Utilidades

    private struct TypeGrade {
        let grade: Float
        let count: Int
    }

    private func gradesByType(_ session: PadelSession) -> [ShotType: TypeGrade] {
        var grouped: [ShotType: [Shot]] = [:]
        for shot in session.shots where shot.type != .unknown {
            grouped[shot.type, default: []].append(shot)
        }
        var result: [ShotType: TypeGrade] = [:]
        for (type, shots) in grouped where shots.count >= Self.minShotsPerType {
            if let grade = meanGrade(shots) {
                result[type] = TypeGrade(grade: grade, count: shots.count)
            }
        }
        return result
    }

    private func meanGrade(_ shots: [Shot]) -> Float? {
        let grades = shots.compactMap { estimator.grade($0) }
        guard !grades.isEmpty else { return nil }
        return grades.reduce(0, +) / Float(grades.count)
    }

    /// Cambio porcentual con signo explícito, ya redondeado.
    private func percentChange(from: Float, to: Float) -> String {
        guard from > 0 else { return "+0" }
        let percent = Int((((to - from) / from) * 100).rounded())
        return percent >= 0 ? "+\(percent)" : "\(percent)"
    }

    private func format(_ level: Float) -> String { String(format: "%.1f", level) }

    private func label(_ type: ShotType) -> String {
        switch type {
        case .forehand: return "La derecha"
        case .backhand: return "El revés"
        case .forehandVolley: return "La volea de derecha"
        case .backhandVolley: return "La volea de revés"
        case .bandeja: return "La bandeja"
        case .vibora: return "La víbora"
        case .smash: return "El remate"
        case .serve: return "El saque"
        case .unknown: return "Sin clasificar"
        }
    }

    private static let longRallyShots = 5
    private static let shortRallyShots = 3
    /// Por debajo de esto la comparación es anécdota, no dato.
    private static let minEvidence = 15
    private static let minShotsPerType = 8
    private static let minShotsForRepertoire = 60
    private static let minHrSamples = 6
    private static let minGames = 4
    private static let minGamesPerSide = 2
    /// Media décima de nivel no la nota nadie; media unidad sí.
    private static let minLevelDelta: Float = 0.3
    private static let lowConsistency: Float = 0.6
}
