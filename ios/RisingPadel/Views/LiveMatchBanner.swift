import PadelCore
import SwiftUI

/// El partido que se está jugando ahora mismo en el reloj, visto desde el iPhone.
///
/// Es la vista del que se quedó en el banquillo: marcador por sets, punto en juego,
/// quién saca, golpeos y pulso, actualizado en cada punto que se anota en la muñeca.
struct LiveMatchBanner: View {
    let state: LiveMatchState

    var body: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if state.completed {
                        OutcomeBadge(text: "final", color: T.tintaSuave)
                    } else {
                        HStack(spacing: 6) {
                            // El punto rojo que parpadea es el lenguaje universal de
                            // "esto está pasando ahora": no hay que explicarlo.
                            Circle()
                                .fill(T.rojo)
                                .frame(width: 8, height: 8)
                                .modifier(Pulse())
                            Text("EN VIVO")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .kerning(1.4)
                                .foregroundStyle(T.rojo)
                        }
                    }
                    Spacer()
                    Text(formatDuration(state.elapsedSeconds))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(T.tintaSuave)
                }

                if let score = state.score {
                    HStack(alignment: .center, spacing: 14) {
                        ForEach(Array(score.allSets.enumerated()), id: \.offset) { _, set in
                            Text("\(set.us)-\(set.them)")
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(T.tinta)
                        }
                        if !score.isFinished {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(score.pointsLabel(.us)) – \(score.pointsLabel(.them))")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(T.pista)
                                Text(score.server == .us ? "sacamos" : "sacan")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(T.tintaSuave)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    label("\(state.shotCount) golpeos", icon: "figure.tennis")
                    if let bpm = state.heartRateBpm {
                        label("\(bpm) ppm", icon: "heart.fill", tint: T.rojo)
                    }
                    Spacer()
                }
            }
        }
    }

    private func label(_ text: String, icon: String, tint: Color = T.tintaSuave) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(T.tintaSuave)
        }
    }
}

/// Parpadeo suave del indicador de directo.
private struct Pulse: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}
