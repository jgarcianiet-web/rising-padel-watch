import PadelCore
import SwiftUI

/// El partido de otro, en vivo: la misma información que la página del espectador del
/// worker, pero dentro de la app. Se llega desde la notificación de "está jugando" o
/// desde el muro, y se refresca solo cada pocos segundos hasta el FINAL.
struct LiveSpectatorView: View {
    let vivo: ComunidadEnVivo

    @Environment(\.dismiss) private var dismiss
    @AppStorage("leagueBaseURL") private var baseURL = ""
    @State private var estado: LiveScorePayload?
    @State private var fallos = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let estado {
                        marcador(estado)
                    } else {
                        ProgressView("Buscando el partido…")
                            .padding(.top, 60)
                    }
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("@\(vivo.alias)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .task { await seguir() }
    }

    private func marcador(_ estado: LiveScorePayload) -> some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if estado.completed {
                        OutcomeBadge(text: "final", color: T.tintaSuave)
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(T.rojo).frame(width: 8, height: 8).modifier(Pulse())
                            Text("EN VIVO")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .kerning(1.4)
                                .foregroundStyle(T.rojo)
                        }
                    }
                    Spacer()
                    Text(formatDuration(estado.elapsedSeconds))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(T.tintaSuave)
                }

                // El mismo marcador de retransmisión que la portada del propio partido:
                // una fila por equipo, sets en columnas y el punto en juego en grande.
                // "us" es el lado del que juega, no el del que mira.
                if let score = estado.score {
                    VStack(spacing: 6) {
                        filaEquipo(
                            nombre: "@\(vivo.alias)", color: .blue,
                            sets: score.sets.map(\.us),
                            puntos: estado.completed ? nil : estado.pointsUs,
                            saca: estado.serving == "us"
                        )
                        filaEquipo(
                            nombre: "RIVALES", color: .orange,
                            sets: score.sets.map(\.them),
                            puntos: estado.completed ? nil : estado.pointsThem,
                            saca: estado.serving == "them"
                        )
                    }
                }

                HStack(spacing: 12) {
                    Label("\(estado.shotCount) golpeos", systemImage: "figure.tennis")
                    if let bpm = estado.heartRateBpm {
                        Label("\(bpm) ppm", systemImage: "heart.fill")
                            .foregroundStyle(T.rojo)
                    }
                    Spacer()
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private func filaEquipo(
        nombre: String, color: Color, sets: [Int], puntos: String?, saca: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(saca ? T.bola : .clear)
                .frame(width: 8, height: 8)
            Text(nombre)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(color)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)
            ForEach(Array(sets.enumerated()), id: \.offset) { index, juego in
                Text("\(juego)")
                    .font(.system(size: 18, weight: index == sets.count - 1 ? .heavy : .semibold,
                                  design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(index == sets.count - 1 ? T.tinta : T.tintaSuave)
                    .frame(width: 20)
            }
            Spacer()
            if let puntos {
                Text(puntos)
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

    /// El mismo bucle que la página web del espectador: GET cada 5 s hasta el FINAL.
    private func seguir() async {
        var raiz = baseURL.trimmingCharacters(in: .whitespaces)
        while raiz.hasSuffix("/") { raiz.removeLast() }
        guard let url = URL(string: "\(raiz)/v1/live/\(vivo.sessionId)") else { return }

        while !Task.isCancelled {
            if let (data, respuesta) = try? await URLSession.shared.data(from: url),
               (respuesta as? HTTPURLResponse)?.statusCode == 200,
               let nuevo = try? JSONDecoder().decode(LiveScorePayload.self, from: data) {
                estado = nuevo
                fallos = 0
                if nuevo.completed { return }
            } else {
                fallos += 1
                if fallos > 6 { return }
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
