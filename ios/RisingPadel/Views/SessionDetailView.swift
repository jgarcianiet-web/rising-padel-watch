import PadelCore
import SwiftUI

struct SessionDetailView: View {
    let session: PadelSession

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var matchId = ""
    @State private var leagueId = ""

    var body: some View {
        List {
            headlineSection
            if let score = session.score { scoreSection(score) }
            levelSection
            if !session.shots.isEmpty {
                Section("Frecuencia de golpeo") {
                    SessionFrequencyChart(session: session)
                }
                Section("Progreso de la sesión") {
                    SessionProgressChart(session: session, playerAverage: model.playerAverageLevel)
                }
            }
            shotBreakdownSection
            // Los rasgos crudos golpe a golpe: es la herramienta para validar en pista
            // los convenios de ejes del giróscopo sin depurador. Solo existe en modo
            // desarrollador.
            if model.developerMode {
                diagnosticsSection
            }
            if !session.health.isEmpty { healthSection }
            sendToLeagueSection
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

    private var diagnosticsSection: some View {
        Section {
            ForEach(Array(session.shots.enumerated()), id: \.offset) { index, shot in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(index + 1). \(shot.type.label)")
                        Spacer()
                        Text(String(format: "conf %.2f", shot.confidence))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    // El signo del axial valida el convenio (positivo = lado de
                    // derecha) y la elevación de pico es la que decide si el golpeo es
                    // alto: es la que hay que mirar en una tanda de bandejas.
                    Text(String(
                        format: "elev %+.0f° · alto %+.0f° · axial %+.1f rad/s · barrido %.0f° · pico %.1f rad/s",
                        shot.features.elevationDeg,
                        shot.features.peakElevationDeg,
                        shot.features.axialRotationRadS,
                        shot.features.sweptAngleDeg,
                        shot.features.peakGyroRadS
                    ))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Diagnóstico · \(session.shots.count) golpeos")
        } footer: {
            Text("""
                Para validar los convenios: da 10 golpes de un solo tipo y comprueba que \
                el tipo, el signo del axial y la elevación cuadran con lo que jugaste. \
                "alto" es la elevación máxima del swing: por encima de \
                \(Int(DetectorConfig.default.overheadElevationDeg))° el golpeo se trata \
                como golpe alto.
                """)
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
            // Rejilla y no fila: con siete métricas posibles una HStack se sale de la
            // pantalla justo cuando la sesión trae todos los datos.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                alignment: .leading,
                spacing: 14
            ) {
                if let heartRate = session.health.heartRate {
                    stat("FC media", "\(heartRate.meanBpm) ppm")
                    stat("FC máx", "\(heartRate.maxBpm) ppm")
                    if let resting = heartRate.restingBpm {
                        stat("FC reposo", "\(resting) ppm")
                    }
                }
                if let kcal = session.health.activeEnergyKcal {
                    stat("Activas", String(format: "%.0f kcal", kcal))
                }
                if let kcal = session.health.totalEnergyKcal {
                    stat("Totales", String(format: "%.0f kcal", kcal))
                }
                if let steps = session.health.steps {
                    stat("Pasos", "\(steps)")
                }
                if let meters = session.health.distanceMeters {
                    stat("Distancia", String(format: "%.1f km", meters / 1000))
                }
            }
            .padding(.vertical, 4)

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

    @Environment(\.openURL) private var openURL

    private var sendToLeagueSection: some View {
        Section {
            Button {
                if let url = model.leagueDeepLink(for: session) {
                    openURL(url)
                }
            } label: {
                Label("Enviar a Liga Pádel", systemImage: "arrow.up.forward.app")
            }
        } footer: {
            Text("Abre la app de la liga con esta sesión lista para guardar como partido.")
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
