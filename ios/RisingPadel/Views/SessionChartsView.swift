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

/// Colores fijos por tipo de golpe: los mismos en toda la app y sesión tras sesión.
///
/// Van atados al tipo y no al orden en que aparecen: si un día no juegas ninguna volea,
/// el resto de golpes **no** cambian de color. Un color que se mueve deja de identificar.
enum ColorDeGolpe {
    static func color(_ type: ShotType) -> Color {
        switch type {
        case .forehand: return T.pista
        case .backhand: return Color(red: 0.49, green: 0.30, blue: 0.75)
        case .forehandVolley, .backhandVolley: return T.verde
        case .bandeja: return .orange
        case .vibora: return Color(red: 0.70, green: 0.27, blue: 0.44)
        case .smash: return T.rojo
        case .serve: return T.tintaSuave
        case .unknown: return T.borde
        }
    }
}

/// El desglose de la sesión golpe a golpe: una fila por tipo, y al pulsar una se abre
/// con todo lo que sabemos de ese golpe.
///
/// Antes esto era la sesión entera en una sola gráfica —un golpeo por barra, cientos de
/// barras de dos píxeles— y no había forma de sacar nada en claro: se veía el ruido del
/// partido, no cómo había jugado uno. La pregunta que la gente se hace no es "¿qué pasó
/// en el minuto 37?" sino "¿cómo fue hoy mi derecha?", y esa se responde por tipo de
/// golpe, no por instante.
///
/// Así que la fila es la unidad y el detalle está a un toque: cuántos, a qué velocidad
/// media y máxima, con qué calidad, con qué regularidad y en qué momentos del partido.
/// El relato temporal no se pierde — vive dentro del golpe que lo interesa.
struct ShotBreakdownChart: View {
    let session: PadelSession

    @State private var abierto: ShotType?

    private var desglose: [ShotBreakdown] {
        SessionAnalytics().shotBreakdown(session.shots)
    }

    static func etiqueta(_ type: ShotType) -> String {
        switch type {
        case .forehand: return "Derecha"
        case .backhand: return "Revés"
        case .forehandVolley: return "Volea de derecha"
        case .backhandVolley: return "Volea de revés"
        case .bandeja: return "Bandeja"
        case .vibora: return "Víbora"
        case .smash: return "Smash"
        case .serve: return "Saque"
        case .unknown: return "Sin clasificar"
        }
    }

    var body: some View {
        let filas = desglose
        let maximo = filas.first?.count ?? 1

        VStack(alignment: .leading, spacing: 0) {
            ForEach(filas) { dato in
                fila(dato, maximo: maximo)
                if dato.id != filas.last?.id {
                    Divider().overlay(T.borde).padding(.vertical, 2)
                }
            }

            Text(abierto == nil
                 ? "Pulsa un golpe para ver su velocidad, su calidad y en qué momentos lo diste."
                 : "La calidad es la nota de 1 a 7 de ese golpe; la regularidad, cuánto se "
                   + "parecen entre sí los que diste.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    // MARK: La fila

    @ViewBuilder
    private func fila(_ dato: ShotBreakdown, maximo: Int) -> some View {
        let seleccionado = abierto == dato.type
        let color = ColorDeGolpe.color(dato.type)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                // Volver a pulsar cierra: la fila abierta es un interruptor, no un modo
                // del que haya que salir por otro sitio.
                withAnimation(.snappy(duration: 0.22)) {
                    abierto = seleccionado ? nil : dato.type
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(color).frame(width: 9, height: 9)
                        Text(Self.etiqueta(dato.type))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(T.tinta)
                        Spacer(minLength: 6)
                        Text("\(dato.count)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(T.tinta)
                        Text(String(format: "%.0f km/h", dato.meanKmh))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(T.tintaSuave)
                        Image(systemName: seleccionado ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(T.tintaSuave)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(T.borde)
                            Capsule()
                                .fill(color)
                                .frame(
                                    width: geo.size.width
                                        * CGFloat(min(max(Double(dato.count) / Double(max(maximo, 1)), 0.02), 1))
                                )
                        }
                    }
                    .frame(height: 7)
                }
                // Toda la fila es zona de toque, no solo el texto: en el móvil se pulsa
                // con el pulgar, no con un puntero.
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(Self.etiqueta(dato.type)), \(dato.count) golpes, "
                + String(format: "%.0f kilómetros por hora de media", dato.meanKmh)
            )

            if seleccionado {
                detalle(dato, color: color)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: El detalle del golpe

    @ViewBuilder
    private func detalle(_ dato: ShotBreakdown, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                tarjetaDato(titulo: "Golpes", valor: "\(dato.count)",
                      pie: String(format: "%.0f%% del total", dato.share * 100))
                tarjetaDato(titulo: "Media", valor: String(format: "%.0f", dato.meanKmh), pie: "km/h")
                tarjetaDato(titulo: "Máxima", valor: String(format: "%.0f", dato.maxKmh), pie: "km/h")
            }

            HStack(spacing: 8) {
                medidor(
                    titulo: "Calidad",
                    // La nota vive en 1-7, así que la barra tiene que empezar en 1: un
                    // 1 no es "cero calidad", es el primer nivel de la escala.
                    fraccion: dato.grade.map { ($0 - 1) / 6 },
                    texto: dato.grade.map { String(format: "%.1f", $0) } ?? "—",
                    pie: dato.grade == nil ? "sin golpes fiables" : "de 7",
                    color: color
                )
                medidor(
                    titulo: "Regularidad",
                    fraccion: dato.consistency,
                    texto: dato.consistency.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                    pie: dato.consistency == nil ? "hace falta más de uno" : lecturaRegularidad(dato.consistency ?? 0),
                    color: color
                )
            }

            momentos(dato, color: color)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private func lecturaRegularidad(_ valor: Float) -> String {
        switch valor {
        case ..<0.4: return "muy dispares"
        case ..<0.7: return "irregulares"
        case ..<0.9: return "bastante regulares"
        default: return "calcados"
        }
    }

    /// Un número con su título y su unidad.
    private func tarjetaDato(titulo: String, valor: String, pie: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titulo)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(T.tintaSuave)
            Text(valor)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(T.tinta)
            Text(pie)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(T.tintaSuave)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(T.borde.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Una barra de 0 a 1 con su lectura en palabras: sirve para la calidad y para la
    /// regularidad, que son las dos cosas que no se leen bien como número suelto.
    private func medidor(
        titulo: String, fraccion: Float?, texto: String, pie: String, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(titulo)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                Spacer(minLength: 2)
                Text(texto)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(T.tinta)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.borde)
                    if let fraccion {
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(min(max(fraccion, 0.02), 1)))
                    }
                }
            }
            .frame(height: 6)
            Text(pie)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(T.tintaSuave)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(T.borde.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Cuándo se dieron esos golpes: una marca por golpeo sobre la duración del partido.
    /// Es lo que enseña si fue un golpe de todo el partido o de una racha de diez minutos.
    @ViewBuilder
    private func momentos(_ dato: ShotBreakdown, color: Color) -> some View {
        let duracion = max(Double(session.durationSeconds) * 1000, 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("Cuándo los diste")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(T.tintaSuave)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.borde.opacity(0.5))
                    ForEach(Array(dato.offsetsMs.enumerated()), id: \.offset) { _, offset in
                        Capsule()
                            .fill(color)
                            .frame(width: 2.5, height: 18)
                            .offset(
                                x: (geo.size.width - 2.5)
                                    * CGFloat(min(max(Double(offset) / duracion, 0), 1))
                            )
                    }
                }
            }
            .frame(height: 18)
            HStack {
                Text("inicio")
                Spacer()
                Text(offsetLabel(Int64(duracion)))
            }
            .font(.system(size: 9, design: .rounded))
            .foregroundStyle(T.tintaSuave)
        }
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
