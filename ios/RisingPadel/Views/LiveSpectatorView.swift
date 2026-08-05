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
                            Circle().fill(T.rojo).frame(width: 8, height: 8)
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

                if let score = estado.score {
                    HStack(spacing: 14) {
                        ForEach(Array(score.sets.enumerated()), id: \.offset) { _, set in
                            Text("\(set.us)-\(set.them)")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(T.tinta)
                        }
                        Spacer()
                        if !estado.completed, let pUs = estado.pointsUs, let pThem = estado.pointsThem {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(pUs) – \(pThem)")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(T.pista)
                                if let serving = estado.serving {
                                    // "us" es el lado del que juega, no el del que mira.
                                    Text(serving == "us" ? "saca @\(vivo.alias)" : "resta @\(vivo.alias)")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(T.tintaSuave)
                                }
                            }
                        }
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
