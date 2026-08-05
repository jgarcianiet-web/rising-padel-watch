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
