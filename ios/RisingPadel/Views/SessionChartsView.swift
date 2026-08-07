import Charts
import PadelCore
import SwiftUI

/// Las tres gráficas de análisis. Los datos salen de `SessionAnalytics` en el core; aquí
/// solo se dibuja, para que Android pinte exactamente las mismas curvas.

// MARK: Frecuencia de golpeo

struct SessionFrequencyChart: View {
    let session: PadelSession

    /// Minutos por intervalo. Dos zooms fijos, como se mira un partido: por tramos
    /// cortos (calentamiento, bajones) o por bloques de set.
    @State private var intervalMinutes = 10

    private var buckets: [FrequencyBucket] {
        SessionAnalytics().shotFrequency(
            session.shots,
            durationMs: session.durationSeconds * 1000,
            intervalMs: Int64(intervalMinutes) * 60_000
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Intervalo", selection: $intervalMinutes) {
                Text("5 min").tag(5)
                Text("10 min").tag(10)
            }
            .pickerStyle(.segmented)

            Chart(buckets, id: \.startMs) { bucket in
                BarMark(
                    x: .value("Tiempo", offsetLabel(bucket.endMs)),
                    y: .value("Golpeos", bucket.count)
                )
                .foregroundStyle(T.pista)
                .cornerRadius(3)
            }
            .chartYAxisLabel("golpeos")
            .frame(height: 180)
        }
        .padding(.vertical, 4)
    }
}

// MARK: Progreso de la sesión

struct SessionProgressChart: View {
    let session: PadelSession
    /// Nivel medio del jugador en su historial, la línea de referencia. Nil si todavía
    /// no hay historial que promediar.
    let playerAverage: Float?

    private var points: [LevelPoint] {
        SessionAnalytics().levelProgression(
            session.shots,
            durationMs: session.durationSeconds * 1000
        )
    }

    var body: some View {
        let points = self.points
        if points.count < 2 {
            Text("Hacen falta más de \(Int(SessionAnalytics.defaultStepMs / 60_000)) minutos de juego para dibujar el progreso.")
                .font(.caption)
                .foregroundStyle(T.tintaSuave)
        } else {
            Chart {
                ForEach(points, id: \.offsetMs) { point in
                    AreaMark(
                        x: .value("Tiempo", minutes(point.offsetMs)),
                        y: .value("Nivel", point.level)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(T.pista.opacity(0.15))
                    LineMark(
                        x: .value("Tiempo", minutes(point.offsetMs)),
                        y: .value("Nivel", point.level)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(T.pista)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                if let playerAverage {
                    RuleMark(y: .value("Tu media", playerAverage))
                        .foregroundStyle(T.bola)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(format: "tu media %.2f", playerAverage))
                                .font(.caption2)
                                .foregroundStyle(T.tintaSuave)
                        }
                }
            }
            // La escala se ciñe a la zona con datos: en la escala 1-7 entera, la
            // variación dentro de una sesión sería una raya plana que no cuenta nada.
            .chartYScale(domain: yDomain(points))
            .chartXAxisLabel("minutos")
            .frame(height: 180)
            .padding(.vertical, 4)
        }
    }

    private func yDomain(_ points: [LevelPoint]) -> ClosedRange<Float> {
        var low = points.map(\.level).min() ?? 1
        var high = points.map(\.level).max() ?? 7
        if let playerAverage {
            low = min(low, playerAverage)
            high = max(high, playerAverage)
        }
        return max(low - 0.2, 1)...min(high + 0.2, 7)
    }
}

// MARK: Nivel de los últimos partidos

struct LevelHistoryChart: View {
    /// Sesiones del historial, en cualquier orden.
    let sessions: [PadelSession]

    /// Nil = nivel global de cada sesión; un tipo = solo la nota de ese golpe.
    @State private var filter: ShotType?

    private struct HistoryPoint: Identifiable {
        let id: String
        let date: Date
        let level: Float
    }

    private var points: [HistoryPoint] {
        let analytics = SessionAnalytics()
        // Se ordena antes de recortar para no depender del orden en que llegue la
        // lista: siempre son las N sesiones más recientes, de vieja a nueva.
        return sessions
            .sorted { $0.startedAtEpochMs < $1.startedAtEpochMs }
            .suffix(Self.maxSessions)
            .compactMap { session -> HistoryPoint? in
                let level: Float?
                if let filter {
                    level = analytics.typeGrade(session.shots, type: filter)
                } else {
                    let estimate = session.level
                    level = estimate.gradedShots > 0 ? estimate.overall : nil
                }
                guard let level else { return nil }
                return HistoryPoint(
                    id: session.sessionId,
                    date: Date(timeIntervalSince1970: Double(session.startedAtEpochMs) / 1000),
                    level: level
                )
            }
    }

    var body: some View {
        let points = self.points
        VStack(alignment: .leading, spacing: 8) {
            Picker("Filtro por golpe", selection: $filter) {
                Text("Todos").tag(ShotType?.none)
                ForEach(Self.filterableTypes, id: \.self) { type in
                    Text(type.label).tag(ShotType?.some(type))
                }
            }
            .pickerStyle(.menu)

            if points.count < 2 {
                Text("Con dos o más sesiones aparecerá aquí la evolución de tu nivel.")
                    .font(.caption)
                    .foregroundStyle(T.tintaSuave)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Fecha", point.date),
                            y: .value("Nivel", point.level)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(T.pista.opacity(0.15))
                        LineMark(
                            x: .value("Fecha", point.date),
                            y: .value("Nivel", point.level)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(T.pista)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(
                            x: .value("Fecha", point.date),
                            y: .value("Nivel", point.level)
                        )
                        .foregroundStyle(T.pista)
                    }
                }
                .chartYScale(domain: yDomain(points))
                .frame(height: 180)
            }
        }
        .padding(.vertical, 4)
    }

    private func yDomain(_ points: [HistoryPoint]) -> ClosedRange<Float> {
        let low = points.map(\.level).min() ?? 1
        let high = points.map(\.level).max() ?? 7
        return max(low - 0.2, 1)...min(high + 0.2, 7)
    }

    /// Sin `unknown` (no se puntúa) y sin más criba: si un golpe no aparece en ninguna
    /// sesión, su gráfica sale vacía con el aviso, que ya explica qué pasa.
    private static let filterableTypes = ShotType.allCases.filter { $0 != .unknown }

    /// Más allá de esto la gráfica en un móvil es una raya apretada sin lectura.
    private static let maxSessions = 15
}

private func minutes(_ offsetMs: Int64) -> Double {
    Double(offsetMs) / 60_000
}

private func offsetLabel(_ offsetMs: Int64) -> String {
    let totalMinutes = Int(offsetMs / 60_000)
    return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
}

// MARK: Golpe a golpe

/// El partido entero como una línea de tiempo: cada golpeo es una barra en el minuto en
/// que ocurrió, con la altura de su velocidad de pala y el color de su tipo.
///
/// Antes era una nube de círculos de tamaño variable y no se entendía nada: había que
/// descifrar tres codificaciones a la vez (posición, color y área) para leer un golpe.
/// Una barra apoyada en el suelo se lee sola — se ven las ráfagas, los huecos y los
/// picos sin pensar, como el sismograma del partido.
struct ShotScatterChart: View {
    let session: PadelSession

    /// Los colores fijos por tipo: los mismos en la leyenda y sesión tras sesión.
    private static let colores: KeyValuePairs<String, Color> = [
        "Derecha": T.pista,
        "Revés": Color(red: 0.49, green: 0.30, blue: 0.75),
        "Volea": T.verde,
        "Bandeja": Color.orange,
        "Víbora": Color(red: 0.70, green: 0.27, blue: 0.44),
        "Smash": T.rojo,
        "Saque": T.tintaSuave,
        "Otro": T.borde,
    ]

    private func etiqueta(_ type: ShotType) -> String {
        switch type {
        case .forehand: return "Derecha"
        case .backhand: return "Revés"
        case .forehandVolley, .backhandVolley: return "Volea"
        case .bandeja: return "Bandeja"
        case .vibora: return "Víbora"
        case .smash: return "Smash"
        case .serve: return "Saque"
        case .unknown: return "Otro"
        }
    }

    /// La media de la sesión, para que cada barra se lea contra algo.
    private var mediaKmh: Float {
        guard !session.shots.isEmpty else { return 0 }
        return session.shots.map(\.racketSpeedKmh).reduce(0, +) / Float(session.shots.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(session.shots, id: \.offsetMs) { shot in
                    BarMark(
                        x: .value("Minuto", Double(shot.offsetMs) / 60_000),
                        y: .value("km/h", shot.racketSpeedKmh),
                        width: 2
                    )
                    .foregroundStyle(by: .value("Tipo", etiqueta(shot.type)))
                }
                // La referencia: de un vistazo se ve qué golpes fueron por encima de
                // tu media del día y cuáles se quedaron cortos.
                RuleMark(y: .value("Media", mediaKmh))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(T.tintaSuave)
                    .annotation(position: .top, alignment: .leading) {
                        Text(String(format: "media %.0f km/h", mediaKmh))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
            }
            .chartForegroundStyleScale(Self.colores)
            .chartXAxisLabel("minuto")
            .chartYAxisLabel("km/h de pala")
            .chartLegend(position: .bottom, spacing: 6)
            .frame(height: 200)

            Text("Cada barra es un golpe, en el minuto en que lo diste. La altura es la "
                 + "velocidad de pala y el color, el tipo de golpe.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

// MARK: Fatiga — pulso contra ritmo

/// El pulso medio por tramo frente al ritmo de golpeo del mismo tramo: la gráfica que
/// enseña tu umbral físico — dónde el motor aprieta y el juego afloja.
struct FatigueChart: View {
    let session: PadelSession

    private struct Tramo: Identifiable {
        let id: Int
        let etiqueta: String
        let golpeos: Int
        let bpm: Int?
    }

    private var tramos: [Tramo] {
        let intervalo: Int64 = SessionAnalytics.interval10MinMs
        let buckets = SessionAnalytics().shotFrequency(
            session.shots,
            durationMs: session.durationSeconds * 1000,
            intervalMs: intervalo
        )
        return buckets.enumerated().map { index, bucket in
            let lecturas = session.health.heartRateSeries
                .filter { $0.offsetMs >= bucket.startMs && $0.offsetMs < bucket.endMs }
                .map(\.bpm)
            return Tramo(
                id: index,
                etiqueta: "\(bucket.endMs / 60_000)'",
                golpeos: bucket.count,
                bpm: lecturas.isEmpty ? nil : lecturas.reduce(0, +) / lecturas.count
            )
        }
    }

    /// Solo tiene sentido con serie de pulso: sin consentimiento de salud no existe.
    static func disponible(_ session: PadelSession) -> Bool {
        session.health.heartRateSeries.count >= 2 && !session.shots.isEmpty
    }

    var body: some View {
        let datos = tramos
        VStack(alignment: .leading, spacing: 10) {
            Chart(datos) { tramo in
                BarMark(
                    x: .value("Tramo", tramo.etiqueta),
                    y: .value("Golpeos", tramo.golpeos)
                )
                .foregroundStyle(T.pista.opacity(0.75))
                .cornerRadius(3)
            }
            .chartYAxisLabel("golpeos")
            .frame(height: 120)

            Chart(datos.filter { $0.bpm != nil }) { tramo in
                LineMark(
                    x: .value("Tramo", tramo.etiqueta),
                    y: .value("ppm", tramo.bpm ?? 0)
                )
                .foregroundStyle(T.rojo)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(
                    x: .value("Tramo", tramo.etiqueta),
                    y: .value("ppm", tramo.bpm ?? 0)
                )
                .foregroundStyle(T.rojo)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel("pulso (ppm)")
            .frame(height: 110)

            if let aviso = lecturaFatiga(datos) {
                Text(aviso)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    /// La conclusión en una frase, solo cuando los datos la sostienen: el tramo de
    /// pulso más alto frente al mejor tramo de ritmo.
    private func lecturaFatiga(_ datos: [Tramo]) -> String? {
        let conPulso = datos.filter { $0.bpm != nil }
        guard conPulso.count >= 3,
              let caliente = conPulso.max(by: { ($0.bpm ?? 0) < ($1.bpm ?? 0) }),
              let mejor = datos.max(by: { $0.golpeos < $1.golpeos }),
              let bpm = caliente.bpm,
              mejor.golpeos > 0,
              caliente.id != mejor.id
        else { return nil }
        let caida = 100 - caliente.golpeos * 100 / mejor.golpeos
        guard caida >= 20 else { return nil }
        return "En tu tramo de más pulso (\(bpm) ppm) el ritmo cayó un \(caida)% "
            + "respecto a tu mejor tramo. Ahí está tu umbral físico."
    }
}
