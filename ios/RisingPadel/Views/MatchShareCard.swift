import SwiftUI

/// El partido como imagen para compartir en el grupo: resultado, sets, nivel y esfuerzo
/// en una tarjeta con colores propios (fijos a propósito — la imagen tiene que verse
/// igual la comparta quien la comparta, con el tema que tenga).
struct MatchShareCard: View {
    let match: LigaMatch

    private let fondo = Color(red: 0.97, green: 0.96, blue: 0.92)
    private let tinta = Color(red: 0.11, green: 0.11, blue: 0.09)
    private let suave = Color(red: 0.47, green: 0.45, blue: 0.42)
    private let pista = Color(red: 0.12, green: 0.44, blue: 0.55)
    private let verde = Color(red: 0.18, green: 0.49, blue: 0.20)
    private let rojo = Color(red: 0.78, green: 0.16, blue: 0.16)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RISING PADEL")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .kerning(2)
                    .foregroundStyle(pista)
                Spacer()
                Text("\(LigaFechas.corta(match.fecha)) · \(LigaFechas.mes(match.fecha))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(suave)
            }

            HStack(spacing: 12) {
                Text(resultado)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .kerning(1.5)
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(colorResultado, in: Capsule())
                if match.bienJugado {
                    Text("bien jugado 🔥")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(tinta)
                }
                Spacer()
            }

            if !match.sets.isEmpty {
                Text(match.sets)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tinta)
            }

            HStack(spacing: 18) {
                if let nivel = LigaMetrics.nivelDeSesion(match) {
                    stat("NIVEL", String(format: "%.1f", nivel), pista)
                }
                if let total = match.totalGolpes {
                    stat("GOLPEOS", "\(total)", tinta)
                }
                if let salud = match.salud {
                    stat("MINUTOS", "\(salud.duracionMin)", tinta)
                    if let pulso = salud.pulsoMedio {
                        stat("PULSO", "\(pulso)", rojo)
                    }
                }
                Spacer()
            }

            if !match.club.isEmpty {
                Text(match.club)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(suave)
            }
        }
        .padding(22)
        .frame(width: 420, alignment: .leading)
        .background(fondo)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(1)
                .foregroundStyle(suave)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var resultado: String {
        switch match.resultado {
        case "victoria": return "VICTORIA"
        case "empate": return "EMPATE"
        default: return "DERROTA"
        }
    }

    private var colorResultado: Color {
        switch match.resultado {
        case "victoria": return verde
        case "empate": return suave
        default: return rojo
        }
    }

    /// La tarjeta como imagen, lista para un ShareLink.
    @MainActor
    static func imagen(for match: LigaMatch) -> Image? {
        let renderer = ImageRenderer(content: MatchShareCard(match: match))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}
