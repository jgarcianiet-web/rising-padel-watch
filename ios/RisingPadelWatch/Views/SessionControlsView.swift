import SwiftUI

/// La página de controles de la sesión, deslizando a la izquierda del partido — el
/// mismo lenguaje que la app Entreno de Apple: aquí viven Finalizar y Pausar/Reanudar,
/// lejos de las zonas de puntuar, así que ningún toque de juego puede cerrarte la
/// sesión ni pararte el partido sin querer.
struct SessionControlsView: View {
    @EnvironmentObject private var controller: SessionController
    @Binding var paginaPartido: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                control(
                    icono: "xmark",
                    titulo: "Finalizar",
                    color: .red
                ) {
                    Task { await controller.stop() }
                }

                if controller.isPaused {
                    control(
                        icono: "arrow.clockwise",
                        titulo: "Reanudar",
                        color: .yellow
                    ) {
                        controller.resume()
                        // Reanudado, de vuelta al partido: es a lo que se viene.
                        withAnimation { paginaPartido = 1 }
                    }
                } else {
                    control(
                        icono: "pause",
                        titulo: "Pausar",
                        color: .yellow
                    ) {
                        controller.pause()
                    }
                }
            }

            // El estado de la sesión, para decidir sin cambiar de página.
            VStack(spacing: 1) {
                Text(formatDuration(controller.elapsedSeconds))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("\(controller.shotCount) golpeos")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if controller.isPaused {
                    Text("EN PAUSA")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .kerning(1.2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    /// Botón redondo con etiqueta debajo, como los de Entreno: área grande, nombre claro.
    private func control(
        icono: String, titulo: String, color: Color, accion: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            Button(action: accion) {
                Image(systemName: icono)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .background(color.opacity(0.25), in: Circle())
            .foregroundStyle(color)
            Text(titulo)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }
}
