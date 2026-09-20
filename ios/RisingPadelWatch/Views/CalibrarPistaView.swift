import PadelCore
import SwiftUI

/// **Medir la pista.** Cuatro esquinas y un número al final.
///
/// La pantalla existe para contestar una pregunta con un dato y no con una promesa:
/// ¿puede el GPS de este reloj decir dónde estabas en esta pista? Se mide plantándose
/// en las cuatro esquinas, y lo que el reloj falle al reconstruir un rectángulo que por
/// reglamento es de 20×10 m es su error aquí.
///
/// **Puede salir que no.** Está previsto y es el resultado más probable en una pista
/// cubierta: el veredicto lo dice con todas las letras en vez de pintar un mapa bonito
/// con posiciones inventadas.
struct CalibrarPistaView: View {
    @StateObject private var calibrador = CalibradorDePista()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let resultado = calibrador.resultado {
                    veredicto(resultado)
                } else {
                    medicion
                }
            }
            .padding(.horizontal, 8)
        }
        .onAppear { calibrador.despertar() }
        .onDisappear { calibrador.dormir() }
    }

    // MARK: Midiendo

    private var medicion: some View {
        VStack(spacing: 8) {
            Text("MEDIR LA PISTA")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .kerning(1.3)
                .foregroundStyle(.tint)

            if let aviso = calibrador.aviso {
                Text(aviso)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if let esquina = calibrador.siguienteEsquina {
                Text("Ponte en")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(esquina)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }

            // La precisión que declara el reloj. No es el error de la pista —ese sale
            // al final— pero sí dice si merece la pena marcar ya o esperar un poco.
            Text(calibrador.precisionActualM.map { String(format: "señal ±%.0f m", $0) }
                 ?? "buscando señal…")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                calibrador.marcarEsquina()
            } label: {
                Text(calibrador.midiendo ? "Midiendo…" : "Marcar esquina")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .disabled(calibrador.midiendo)

            if calibrador.midiendo {
                Text("Quieto unos segundos")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            progreso

            if !calibrador.esquinas.isEmpty, !calibrador.midiendo {
                Button("Deshacer") { calibrador.deshacer() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Las cuatro esquinas como cuatro puntos: en una muñeca, "2 de 4" se lee peor que
    /// dos círculos llenos y dos vacíos.
    private var progreso: some View {
        HStack(spacing: 6) {
            ForEach(0..<CalibradorDePista.nombresDeEsquina.count, id: \.self) { i in
                Image(systemName: i < calibrador.esquinas.count
                      ? "circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(i < calibrador.esquinas.count ? .tint : .secondary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: El resultado

    private func veredicto(_ calibracion: CalibracionGpsDePista) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icono(calibracion.fiabilidad))
                .font(.system(size: 24))
                .foregroundStyle(color(calibracion.fiabilidad))

            Text(String(format: "±%.1f m", calibracion.errorMedioM))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()

            Text(calibracion.veredicto)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Guardar") {
                calibrador.guardar()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 14, weight: .semibold, design: .rounded))

            Button("Medir otra vez") { calibrador.empezarDeCero() }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private func icono(_ fiabilidad: CalibracionGpsDePista.Fiabilidad) -> String {
        switch fiabilidad {
        case .zonas: return "checkmark.circle.fill"
        case .redOFondo: return "exclamationmark.triangle.fill"
        case .ninguna: return "xmark.circle.fill"
        }
    }

    private func color(_ fiabilidad: CalibracionGpsDePista.Fiabilidad) -> Color {
        switch fiabilidad {
        case .zonas: return .green
        case .redOFondo: return .yellow
        case .ninguna: return .red
        }
    }
}

#Preview {
    CalibrarPistaView()
}
