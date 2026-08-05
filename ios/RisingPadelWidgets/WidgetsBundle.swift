import ActivityKit
import SwiftUI
import WidgetKit

// La extensión de widgets: hoy su única pieza es la Live Activity del partido — el
// marcador en la pantalla de bloqueo y la Dynamic Island mientras se juega, sin abrir
// la app. La alimenta el iPhone con cada punto que llega del reloj.
//
// No enlaza PadelCore a propósito: la extensión solo pinta el ContentState plano que
// la app le da (ver ios/Shared/PadelMatchAttributes.swift).

@main
struct RisingPadelWidgets: WidgetBundle {
    var body: some Widget {
        PadelMatchLiveActivity()
    }
}

struct PadelMatchLiveActivity: Widget {

    // Colores propios: el Theme de la app vive en el otro target.
    private static let pista = Color(red: 0.12, green: 0.44, blue: 0.55)
    private static let bola = Color(red: 0.79, green: 0.84, blue: 0.13)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PadelMatchAttributes.self) { context in
            // Pantalla de bloqueo: la vista del banquillo.
            lockScreen(context)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.sets.isEmpty ? "0-0" : context.state.sets)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.completed {
                        Text(resultado(context.state))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                    } else {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(context.state.pointsUs) – \(context.state.pointsThem)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Self.bola)
                            if let servingUs = context.state.servingUs {
                                Text(servingUs ? "sacamos" : "sacan")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 14) {
                        Label("\(context.state.shotCount)", systemImage: "figure.tennis")
                        if let bpm = context.state.heartRateBpm {
                            Label("\(bpm)", systemImage: "heart.fill").foregroundStyle(.red)
                        }
                        Spacer()
                        Text(timerInterval: context.attributes.startedAt...Date(
                            timeInterval: 6 * 3600, since: context.attributes.startedAt))
                            .monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            } compactLeading: {
                Text(context.state.sets.isEmpty ? "🎾" : ultimoSet(context.state.sets))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            } compactTrailing: {
                Text(context.state.completed
                     ? "FIN"
                     : "\(context.state.pointsUs)-\(context.state.pointsThem)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.bola)
            } minimal: {
                Image(systemName: "figure.tennis")
                    .foregroundStyle(Self.pista)
            }
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<PadelMatchAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if context.state.completed {
                    Text(resultado(context.state))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .kerning(1.2)
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text("EN VIVO")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .kerning(1.4)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Text(timerInterval: context.attributes.startedAt...Date(
                    timeInterval: 6 * 3600, since: context.attributes.startedAt))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 60)
            }
            HStack(alignment: .center) {
                Text(context.state.sets.isEmpty ? "0-0" : context.state.sets)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Spacer()
                if !context.state.completed {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(context.state.pointsUs) – \(context.state.pointsThem)")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Self.bola)
                        if let servingUs = context.state.servingUs {
                            Text(servingUs ? "sacamos" : "sacan")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Label("\(context.state.shotCount) golpeos", systemImage: "figure.tennis")
                if let bpm = context.state.heartRateBpm {
                    Label("\(bpm) ppm", systemImage: "heart.fill").foregroundStyle(.red)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    private func resultado(_ state: PadelMatchAttributes.ContentState) -> String {
        guard let winnerUs = state.winnerUs else { return "FINAL" }
        return winnerUs ? "VICTORIA" : "DERROTA"
    }

    /// En el hueco compacto de la isla solo cabe el set en curso.
    private func ultimoSet(_ sets: String) -> String {
        sets.split(separator: " ").last.map(String.init) ?? sets
    }
}
