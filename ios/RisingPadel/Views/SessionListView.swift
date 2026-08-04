import PadelCore
import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    private var hasPending: Bool {
        model.sessions.contains { $0.sync.state != .synced }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.sessions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Mis sesiones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
                if hasPending {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            Task { await model.syncNow() }
                        } label: {
                            Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environmentObject(model)
            }
            .refreshable { await model.syncNow() }
            .alert(
                model.message ?? "",
                isPresented: Binding(
                    get: { model.message != nil },
                    set: { if !$0 { model.message = nil } }
                )
            ) {
                Button("Vale", role: .cancel) { model.message = nil }
            }
        }
    }

    private var list: some View {
        List {
            // La evolución vive encima de la lista: es la respuesta a "¿estoy
            // mejorando?", que es lo primero que se viene a mirar.
            Section("Nivel últimos partidos") {
                LevelHistoryChart(sessions: model.sessions)
            }
            Section {
                ForEach(model.sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session).environmentObject(model)
                    } label: {
                        row(session)
                    }
                }
            }
        }
    }

    private func row(_ session: PadelSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatSessionDate(session.startedAtEpochMs))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text("\(session.totalShots) golpeos")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(formatDuration(session.durationSeconds))
                    .font(.subheadline)
            }

            if let score = session.score {
                Text(score.allSets.map { "\($0.us)-\($0.them)" }.joined(separator: "  "))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                    .monospacedDigit()
            }

            Text(subtitle(session))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(session.sync.state.label)
                .font(.caption2)
                .foregroundStyle(color(for: session.sync.state))
        }
        .padding(.vertical, 4)
    }

    private func subtitle(_ session: PadelSession) -> String {
        var parts = [String(format: "%.1f golpeos/min", session.shotsPerMinute)]
        if let heartRate = session.health.heartRate {
            parts.append("\(heartRate.meanBpm) ppm medias")
        }
        return parts.joined(separator: " · ")
    }

    private func color(for state: SyncState) -> Color {
        switch state {
        case .synced: return .green
        case .pending: return .secondary
        case .failed, .needsAuth: return .red
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Todavía no hay sesiones", systemImage: "figure.tennis")
        } description: {
            Text("Abre Rising Padel en el reloj y pulsa Empezar antes del partido. "
                 + "Al terminar, la sesión aparecerá aquí sola.")
        }
    }
}

#Preview {
    SessionListView().environmentObject(AppModel(store: InMemorySessionStore()))
}
