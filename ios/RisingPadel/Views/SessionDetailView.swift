import PadelCore
import SwiftUI

struct SessionDetailView: View {
    let session: PadelSession

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var matchId = ""
    @State private var leagueId = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                heroCard
                if let score = session.score { scoreCard(score) }
                // Las ideas van arriba, antes que las gráficas: son la conclusión, y las
                // gráficas son la prueba. Quien solo mira diez segundos el móvil al salir
                // de la pista se lleva lo importante.
                InsightsCard(session: session)
                levelCard
                if !session.shots.isEmpty {
                    PadelCard(title: "Frecuencia de golpeo", icon: "chart.bar.fill") {
                        SessionFrequencyChart(session: session)
                    }
                    PadelCard(title: "Progreso de la sesión", icon: "chart.xyaxis.line") {
                        SessionProgressChart(
                            session: session,
                            playerAverage: model.playerAverageLevel
                        )
                    }
                }
                shotBreakdownCard
                if !session.health.isEmpty { healthCard }
                // Los rasgos crudos golpe a golpe: la herramienta para validar en pista
                // los convenios del giróscopo sin depurador. Solo en modo desarrollador.
                if model.developerMode { diagnosticsCard }
                leagueCard
                matchLinkCard
                syncCard
                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(T.fondo)
        .scrollContentBackground(.hidden)
        .navigationTitle(formatSessionDate(session.startedAtEpochMs))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            matchId = session.matchRef?.matchId ?? ""
            leagueId = session.matchRef?.leagueId ?? ""
        }
    }

    // MARK: Portada

    /// Lo primero y lo más grande: cuántos golpeos y en cuánto tiempo. El resto de la
    /// pantalla matiza ese titular.
    private var heroCard: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: -4) {
                        Text("\(session.totalShots)")
                            .font(.padelDisplay(56))
                            .monospacedDigit()
                            .foregroundStyle(T.pista)
                        Text("golpeos")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                    Spacer()
                    if let score = session.score {
                        OutcomeBadge(text: outcomeLabel(score), color: outcomeColor(score))
                    }
                }

                Divider().overlay(T.borde)

                HStack(spacing: 8) {
                    StatTile(
                        label: "Duración",
                        value: formatDuration(session.durationSeconds),
                        icon: "clock"
                    )
                    StatTile(
                        label: "Ritmo",
                        value: String(format: "%.1f/min", session.shotsPerMinute),
                        icon: "metronome"
                    )
                    StatTile(
                        label: "Media pala",
                        value: String(format: "%.0f km/h", session.intensity.meanRacketSpeedKmh),
                        icon: "speedometer"
                    )
                    StatTile(
                        label: "Máx pala",
                        value: String(format: "%.0f km/h", session.intensity.maxRacketSpeedKmh),
                        icon: "bolt.fill",
                        tint: T.bola
                    )
                }

                if !session.profile.watchOnRacketArm {
                    warning("El reloj no estaba en el brazo de la pala: el conteo es orientativo.")
                }
            }
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(T.rojo)
    }

    // MARK: Resultado

    private func scoreCard(_ score: MatchScore) -> some View {
        PadelCard(title: "Resultado", icon: "trophy.fill") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(Array(score.allSets.enumerated()), id: \.offset) { _, set in
                        VStack(spacing: 2) {
                            Text("\(set.us)-\(set.them)")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(set.us > set.them ? T.pista : T.tintaSuave)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            set.us > set.them ? T.pistaTinte : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                }
                Text(rulesLabel(score))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private func outcomeLabel(_ score: MatchScore) -> String {
        guard score.isFinished else { return "sin terminar" }
        return score.winner == .us ? "ganado" : "perdido"
    }

    private func outcomeColor(_ score: MatchScore) -> Color {
        guard score.isFinished else { return T.tintaSuave }
        return score.winner == .us ? T.verde : T.rojo
    }

    private func rulesLabel(_ score: MatchScore) -> String {
        "\(score.rules.deuceFormat.label) · al mejor de \(score.rules.setsToWin * 2 - 1) sets"
    }

    // MARK: Nivel

    @ViewBuilder
    private var levelCard: some View {
        let level = session.level
        if level.gradedShots > 0 {
            PadelCard(title: "Nivel técnico", icon: "gauge.with.needle") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 16) {
                        LevelDial(level: level.overall)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("sobre \(level.gradedShots) golpeos puntuados")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(T.tintaSuave)
                            HStack(spacing: 8) {
                                StatTile(
                                    label: "Regularidad",
                                    value: "\(Int(level.consistency * 100))%"
                                )
                                StatTile(
                                    label: "Repertorio",
                                    value: "\(Int(level.repertoire * 100))%"
                                )
                            }
                        }
                    }

                    // El desglose por golpe es lo accionable: el número global dice poco;
                    // saber que el revés va dos puntos por debajo de la derecha dice qué
                    // entrenar.
                    if !level.byShotType.isEmpty {
                        Divider().overlay(T.borde)
                        VStack(spacing: 9) {
                            ForEach(level.byShotType.sorted { $0.value > $1.value }, id: \.key) { entry in
                                PadelBar(
                                    label: entry.key.label,
                                    value: String(format: "%.1f", entry.value),
                                    fraction: entry.value / 7,
                                    color: entry.value >= level.overall ? T.pista : T.bola
                                )
                            }
                        }
                    }

                    if !level.reliable {
                        warning("Pocos golpeos para una estimación firme: juega una sesión más larga.")
                    }
                    Text("""
                        Estimado a partir de la velocidad y la forma del swing. No mide \
                        colocación ni táctica, y está sin calibrar contra jugadores de \
                        nivel conocido.
                        """)
                        .font(.system(size: 11))
                        .foregroundStyle(T.tintaSuave)
                }
            }
        }
    }

    // MARK: Golpeos por tipo

    private var shotBreakdownCard: some View {
        let byType = session.shotsByType.sorted { $0.value > $1.value }
        let maxCount = byType.first?.value ?? 1

        return Group {
            if !byType.isEmpty {
                PadelCard(title: "Golpeos por tipo", icon: "list.bullet") {
                    VStack(spacing: 9) {
                        ForEach(byType, id: \.key) { type, count in
                            PadelBar(
                                label: type.label,
                                value: "\(count)",
                                fraction: Float(count) / Float(maxCount)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: Salud

    private var healthCard: some View {
        PadelCard(title: "Salud", icon: "heart.fill") {
            VStack(alignment: .leading, spacing: 14) {
                // Rejilla y no fila: con siete métricas posibles una HStack se sale de
                // la pantalla justo cuando la sesión trae todos los datos.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                    alignment: .leading,
                    spacing: 14
                ) {
                    if let heartRate = session.health.heartRate {
                        StatTile(label: "FC media", value: "\(heartRate.meanBpm) ppm",
                                 icon: "heart", tint: T.rojo)
                        StatTile(label: "FC máx", value: "\(heartRate.maxBpm) ppm",
                                 icon: "heart.fill", tint: T.rojo)
                        if let resting = heartRate.restingBpm {
                            StatTile(label: "FC reposo", value: "\(resting) ppm", icon: "bed.double")
                        }
                    }
                    if let kcal = session.health.activeEnergyKcal {
                        StatTile(label: "Activas", value: String(format: "%.0f kcal", kcal),
                                 icon: "flame.fill", tint: T.bola)
                    }
                    if let kcal = session.health.totalEnergyKcal {
                        StatTile(label: "Totales", value: String(format: "%.0f kcal", kcal),
                                 icon: "flame")
                    }
                    if let steps = session.health.steps {
                        StatTile(label: "Pasos", value: "\(steps)", icon: "figure.walk")
                    }
                    if let meters = session.health.distanceMeters {
                        StatTile(label: "Distancia", value: String(format: "%.1f km", meters / 1000),
                                 icon: "location.fill")
                    }
                }

                let zones = session.health.zones.secondsPerZone
                if !zones.isEmpty {
                    Divider().overlay(T.borde)
                    let maxSeconds = zones.values.max() ?? 1
                    VStack(spacing: 9) {
                        ForEach(HeartRateZones.zoneKeys, id: \.self) { key in
                            if let seconds = zones[key] {
                                PadelBar(
                                    label: zoneLabel(key),
                                    value: formatDuration(Int64(seconds)),
                                    fraction: Float(seconds) / Float(maxSeconds),
                                    color: T.rojo
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Diagnóstico (modo desarrollador)

    private var diagnosticsCard: some View {
        PadelCard(title: "Diagnóstico · \(session.shots.count) golpeos", icon: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(session.shots.enumerated()), id: \.offset) { index, shot in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(index + 1). \(shot.type.label)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(T.tinta)
                            Spacer()
                            Text(String(format: "conf %.2f", shot.confidence))
                                .font(.system(size: 11))
                                .foregroundStyle(T.tintaSuave)
                        }
                        // El signo del axial valida el convenio (positivo = lado de
                        // derecha) y la elevación de pico es la que decide si el golpeo
                        // es alto: es la que hay que mirar en una tanda de bandejas.
                        Text(String(
                            format: "elev %+.0f° · alto %+.0f° · axial %+.1f · barrido %.0f° · pico %.1f",
                            shot.features.elevationDeg,
                            shot.features.peakElevationDeg,
                            shot.features.axialRotationRadS,
                            shot.features.sweptAngleDeg,
                            shot.features.peakGyroRadS
                        ))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(T.tintaSuave)
                    }
                }
                Text("""
                    Da 10 golpes de un solo tipo y comprueba que el tipo, el signo del \
                    axial y la elevación cuadran. "alto" es la elevación máxima del \
                    swing: por encima de \(Int(DetectorConfig.default.overheadElevationDeg))° \
                    el golpeo se trata como golpe alto.
                    """)
                    .font(.system(size: 11))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    // MARK: Liga y sincronización

    private var leagueCard: some View {
        PadelCard(title: "Liga", icon: "trophy.fill") {
            VStack(alignment: .leading, spacing: 10) {
                // La liga vive en esta misma app: guardar es local e instantáneo.
                Button {
                    liga.saveMatch(from: session, playerAverage: model.playerAverageLevel)
                } label: {
                    Label(
                        liga.hasMatch(for: session)
                            ? "Actualizar el partido en la liga"
                            : "Guardar como partido de liga",
                        systemImage: "trophy.fill"
                    )
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(T.pista, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // El deep link a la app Expo se mantiene durante la transición: quien
                // aún lleve la liga allí no pierde el puente.
                Button {
                    if let url = model.leagueDeepLink(for: session) {
                        openURL(url)
                    }
                } label: {
                    Label("Enviar a la app Liga Pádel", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(T.pista)

                Text("Resultado, nivel, golpes y gráficas quedan en la pestaña Liga.")
                    .font(.system(size: 11))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private var matchLinkCard: some View {
        PadelCard(title: "Vincular con un partido", icon: "link") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("ID del partido", text: $matchId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("ID de la liga (opcional)", text: $leagueId)
                    .textFieldStyle(.roundedBorder)
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
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(T.pista)
                Text("Al vincularla, la liga puede asociar estas estadísticas al partido.")
                    .font(.system(size: 11))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private var syncCard: some View {
        PadelCard(title: "Sincronización", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(syncColor)
                        .frame(width: 8, height: 8)
                    Text(session.sync.state.label)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(T.tinta)
                }
                if let error = session.sync.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(T.rojo)
                }
                if session.sync.state != .synced {
                    Button("Reintentar ahora") {
                        Task { await model.retry(session.sessionId) }
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.pista)
                }
            }
        }
    }

    private var syncColor: Color {
        switch session.sync.state {
        case .synced: return T.verde
        case .pending: return T.tintaSuave
        case .failed, .needsAuth: return T.rojo
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.delete(session.sessionId)
            dismiss()
        } label: {
            Text("Borrar sesión del móvil")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(T.rojo)
        .padding(.top, 4)
    }
}

/// Marcador circular del nivel, de 1 a 7. Un número grande dentro de un arco: se lee de
/// un vistazo y sitúa el valor en la escala sin tener que recordarla.
struct LevelDial: View {
    let level: Float

    private var fraction: Double {
        Double((level - 1) / 6).clamped()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(T.borde, lineWidth: 9)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [T.pista, T.bola],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text(String(format: "%.1f", level))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(T.tinta)
                Text("de 7")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
            }
        }
        .frame(width: 92, height: 92)
    }
}

private extension Double {
    func clamped() -> Double { min(max(self, 0), 1) }
}
