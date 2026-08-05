import PadelCore
import SwiftUI

/// El partido en curso, visto desde el iPhone, con el lenguaje de una retransmisión:
/// una fila por equipo — NOSOTROS en azul, ELLOS en naranja, los mismos colores que el
/// reloj — con sus sets en columnas y el punto en juego en grande. La bolita amarilla
/// marca quién saca, como en la tele.
struct LiveMatchBanner: View {
    let state: LiveMatchState

    private static let nosotros = Color.blue
    private static let ellos = Color.orange

    var body: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let score = state.score {
                    VStack(spacing: 6) {
                        teamRow(.us, score: score)
                        teamRow(.them, score: score)
                    }
                    if score.isFinished {
                        Text(score.winner == .us ? "¡Victoria!" : "Derrota")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(score.winner == .us ? T.verde : T.rojo)
                    }
                }

                HStack(spacing: 14) {
                    label("\(state.shotCount) golpeos", icon: "figure.tennis")
                    if let bpm = state.heartRateBpm {
                        label("\(bpm) ppm", icon: "heart.fill", tint: T.rojo)
                    }
                    Spacer()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            if state.completed {
                OutcomeBadge(text: "final", color: T.tintaSuave)
            } else {
                HStack(spacing: 6) {
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
    }

    /// La fila de un equipo: nombre, saque, sets en columnas y el punto en juego.
    private func teamRow(_ side: Side, score: MatchScore) -> some View {
        let color = side == .us ? Self.nosotros : Self.ellos
        return HStack(spacing: 8) {
            // La bolita de saque, en columna fija para que las filas queden alineadas.
            Circle()
                .fill(score.server == side && !score.isFinished ? T.bola : .clear)
                .frame(width: 8, height: 8)

            Text(side == .us ? "NOSOTROS" : "ELLOS")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .kerning(1)
                .foregroundStyle(color)
                .frame(width: 92, alignment: .leading)

            ForEach(Array(score.allSets.enumerated()), id: \.offset) { index, set in
                Text("\(side == .us ? set.us : set.them)")
                    .font(.system(size: 18, weight: index == score.allSets.count - 1 ? .heavy : .semibold,
                                  design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(index == score.allSets.count - 1 ? T.tinta : T.tintaSuave)
                    .frame(width: 20)
            }

            Spacer()

            if !score.isFinished {
                Text(score.pointsLabel(side))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: 52)
                    .padding(.vertical, 3)
                    .background(color, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
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

    private func formatDuration(_ seconds: Int64) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Parpadeo suave del indicador de directo.
struct Pulse: ViewModifier {
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}
