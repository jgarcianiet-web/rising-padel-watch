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
            .background(T.fondo)
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
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                // La evolución vive encima de la lista: es la respuesta a "¿estoy
                // mejorando?", que es lo primero que se viene a mirar.
                PadelCard(title: "Nivel últimos partidos", icon: "chart.xyaxis.line") {
                    LevelHistoryChart(sessions: model.sessions)
                }

                ForEach(model.sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session).environmentObject(model)
                    } label: {
                        row(session)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func row(_ session: PadelSession) -> some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatSessionDate(session.startedAtEpochMs))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .kerning(1.2)
                            .foregroundStyle(T.tintaSuave)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(session.totalShots)")
                                .font(.padelDisplay(28))
                                .monospacedDigit()
                                .foregroundStyle(T.pista)
                            Text("golpeos")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(T.tintaSuave)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if let score = session.score {
                            Text(score.allSets.map { "\($0.us)-\($0.them)" }.joined(separator: "  "))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(T.tinta)
                        }
                        let level = session.level
                        if level.gradedShots > 0 {
                            Text("nivel \(String(format: "%.1f", level.rounded))")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(T.bola)
                        }
                    }
                }

                HStack(spacing: 12) {
                    tag(formatDuration(session.durationSeconds), icon: "clock")
                    tag(String(format: "%.1f/min", session.shotsPerMinute), icon: "metronome")
                    if let heartRate = session.health.heartRate {
                        tag("\(heartRate.meanBpm) ppm", icon: "heart.fill")
                    }
                    Spacer()
                    Circle()
                        .fill(color(for: session.sync.state))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    private func tag(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(T.tintaSuave)
    }

    private func color(for state: SyncState) -> Color {
        switch state {
        case .synced: return T.verde
        case .pending: return T.tintaSuave
        case .failed, .needsAuth: return T.rojo
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Todavía no hay sesiones", systemImage: "figure.tennis")
        } description: {
            Text("Abre Rising Padel en el reloj y elige Partido o Entreno. "
                 + "Al terminar, la sesión aparecerá aquí sola.")
        }
    }
}

#Preview {
    SessionListView().environmentObject(AppModel(store: InMemorySessionStore()))
}
