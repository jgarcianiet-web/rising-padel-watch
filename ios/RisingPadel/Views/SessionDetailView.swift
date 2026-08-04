import PadelCore
import SwiftUI

struct SessionDetailView: View {
    let session: PadelSession

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var matchId = ""
    @State private var leagueId = ""
    @State private var leagueOpenFailed = false

    var body: some View {
        List {
            headlineSection
            if let score = session.score { scoreSection(score) }
            levelSection
            shotBreakdownSection
            if !session.health.isEmpty { healthSection }
            leagueExportSection
            matchLinkSection
            syncSection
            deleteSection
        }
        .navigationTitle(formatSessionDate(session.startedAtEpochMs))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            matchId = session.matchRef?.matchId ?? ""
            leagueId = session.matchRef?.leagueId ?? ""
        }
    }

    private var headlineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(session.totalShots)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("golpeos en \(formatDuration(session.durationSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    stat("Ritmo", String(format: "%.1f/min", session.shotsPerMinute))
                    Spacer()
                    stat("Media pala", String(format: "%.0f km/h", session.intensity.meanRacketSpeedKmh))
                    Spacer()
                    stat("Máx pala", String(format: "%.0f km/h", session.intensity.maxRacketSpeedKmh))
                }
                .padding(.top, 4)

                if !session.profile.watchOnRacketArm {
                    Text("El reloj no estaba en el brazo de la pala: el conteo es orientativo.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var levelSection: some View {
        let level = session.level
        if level.gradedShots > 0 {
            Section("Nivel técnico") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", level.rounded))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.tint)
                        Text("de 7").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("sobre \(level.gradedShots) golpeos")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        stat("Regularidad", "\(Int(level.consistency * 100))%")
                        Spacer()
                        stat("Repertorio", "\(Int(level.repertoire * 100))%")
                        Spacer()
                    }
                    .padding(.top, 4)

                    // El desglose por golpe es lo accionable: el número global dice poco,
                    // saber que el revés va dos puntos por debajo de la derecha dice qué
                    // entrenar.
                    ForEach(level.byShotType.sorted { $0.value > $1.value }, id: \.key) { entry in
                        HStack {
                            Text(entry.key.label)
                            Spacer()
                            Text(String(format: "%.1f", entry.value)).monospacedDigit()
                        }
                        .font(.subheadline)
                    }

                    if !level.reliable {
                        Text("Pocos golpeos para una estimación firme: juega una sesión más larga.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("""
                        Estimado a partir de la velocidad y la forma del swing. No mide \
                        colocación ni táctica, y está sin calibrar contra jugadores de \
                        nivel conocido.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func scoreSection(_ score: MatchScore) -> some View {
        Section("Resultado") {
            VStack(alignment: .leading, spacing: 4) {
                Text(score.allSets.map { "\($0.us)-\($0.them)" }.joined(separator: "   "))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(outcomeLabel(score))
                    .font(.subheadline)
                    .foregroundStyle(score.winner == .us ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(rulesLabel(score))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func outcomeLabel(_ score: MatchScore) -> String {
        guard score.isFinished else { return "Partido sin terminar" }
        return score.winner == .us ? "Ganado" : "Perdido"
    }

    private func rulesLabel(_ score: MatchScore) -> String {
        let format = score.rules.deuceFormat.label
        return "\(format) · al mejor de \(score.rules.setsToWin * 2 - 1) sets"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var shotBreakdownSection: some View {
        let byType = session.shotsByType.sorted { $0.value > $1.value }
        let maxCount = byType.first?.value ?? 1

        return Section("Golpeos por tipo") {
            ForEach(byType, id: \.key) { type, count in
                bar(label: type.label, value: "\(count)",
                    fraction: Float(count) / Float(maxCount), color: .accentColor)
            }
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section("Salud") {
            HStack {
                if let heartRate = session.health.heartRate {
                    stat("FC media", "\(heartRate.meanBpm) ppm")
                    Spacer()
                    stat("FC máx", "\(heartRate.maxBpm) ppm")
                }
                if let kcal = session.health.activeEnergyKcal {
                    Spacer()
                    stat("Activas", String(format: "%.0f kcal", kcal))
                }
                if let meters = session.health.distanceMeters {
                    Spacer()
                    stat("Distancia", String(format: "%.1f km", meters / 1000))
                }
            }

            let zones = session.health.zones.secondsPerZone
            if !zones.isEmpty {
                let maxSeconds = zones.values.max() ?? 1
                ForEach(HeartRateZones.zoneKeys, id: \.self) { key in
                    if let seconds = zones[key] {
                        bar(label: zoneLabel(key), value: formatDuration(Int64(seconds)),
                            fraction: Float(seconds) / Float(maxSeconds), color: .orange)
                    }
                }
            }
        }
    }

    private func bar(label: String, value: String, fraction: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(value).font(.subheadline).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(color)
                        // Un mínimo visible: una barra de 0 px no comunica "casi nada",
                        // comunica "nada".
                        .frame(width: geometry.size.width * CGFloat(min(max(fraction, 0.02), 1)))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }

    // Volcado local a Liga Personal Pádel (mismo iPhone): abre la liga con la sesión
    // y ella prerrellena el partido. No usa red ni token; ver LeagueDeepLink.
    private var leagueExportSection: some View {
        Section {
            Button("Enviar a Liga Personal Pádel") {
                guard let url = LeagueDeepLink.url(for: session, shareHealth: model.shareHealth)
                else { return }
                leagueOpenFailed = false
                openURL(url) { accepted in leagueOpenFailed = !accepted }
            }
            if leagueOpenFailed {
                Text("No se pudo abrir Liga Personal Pádel. ¿Está instalada en este iPhone?")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text(
                model.shareHealth
                    ? "Abre la app de liga de este iPhone con el partido prerrellenado (golpeos, marcador, nivel y salud)."
                    : "Abre la app de liga de este iPhone con el partido prerrellenado. La salud no se incluye: el consentimiento está desactivado en Ajustes."
            )
        }
    }

    private var matchLinkSection: some View {
        Section {
            TextField("ID del partido", text: $matchId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("ID de la liga (opcional)", text: $leagueId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Guardar y volver a subir") {
                Task {
                    await model.linkToMatch(
                        sessionId: session.sessionId,
                        matchId: matchId,
                        leagueId: leagueId.isEmpty ? nil : leagueId
                    )
                }
            }
        } header: {
            Text("Vincular con un partido")
        } footer: {
            Text("Al vincularla, la liga puede asociar estas estadísticas al partido.")
        }
    }

    private var syncSection: some View {
        Section("Sincronización") {
            Text(session.sync.state.label)
            if let error = session.sync.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if session.sync.state != .synced {
                Button("Reintentar ahora") {
                    Task { await model.retry(session.sessionId) }
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Borrar sesión del móvil", role: .destructive) {
                model.delete(session.sessionId)
                dismiss()
            }
        }
    }
}
