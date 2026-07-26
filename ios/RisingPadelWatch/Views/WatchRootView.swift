import PadelCore
import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var controller: SessionController

    var body: some View {
        VStack(spacing: 6) {
            switch controller.status {
            case .idle:
                idleContent
            case .preparing:
                loadingContent("Preparando…")
            case .recording:
                recordingContent
            case .saving:
                loadingContent("Guardando…")
            case .saved:
                summaryContent
            case .error(let message):
                errorContent(message)
            }
        }
        .padding(.horizontal, 8)
    }

    private var idleContent: some View {
        VStack(spacing: 10) {
            Text("Rising Padel")
                .font(.headline)
            Button("Empezar") {
                Task { await controller.start() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadingContent(_ label: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(label).font(.caption)
        }
    }

    private var recordingContent: some View {
        VStack(spacing: 2) {
            Text("\(controller.shotCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                // El contador cambia constantemente; sin ancho fijo de dígito la cifra
                // "baila" en pantalla y cuesta leerla de reojo entre puntos.
                .monospacedDigit()
            Text("golpeos").font(.caption2).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(formatDuration(controller.elapsedSeconds)).monospacedDigit()
                if let bpm = controller.heartRateBpm {
                    Text("· \(bpm) ppm")
                }
            }
            .font(.caption2)

            if let shot = controller.lastShotType {
                Text(shot.label)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }

            if controller.wrongWristWarning {
                Text("Reloj en la muñeca sin pala")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Parar") {
                Task { await controller.stop() }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }

    private var summaryContent: some View {
        VStack(spacing: 6) {
            Text("Sesión guardada").font(.headline).multilineTextAlignment(.center)
            Text("\(controller.shotCount) golpeos · \(formatDuration(controller.elapsedSeconds))")
                .font(.caption)
            if let message = controller.statusMessage {
                Text(message)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("Hecho") { controller.acknowledge() }
                .buttonStyle(.bordered)
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
            Button("Cerrar") { controller.acknowledge() }
                .buttonStyle(.bordered)
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension ShotType {
    var label: String {
        switch self {
        case .forehand: return "Derecha"
        case .backhand: return "Revés"
        case .forehandVolley: return "Volea de derecha"
        case .backhandVolley: return "Volea de revés"
        case .overhead: return "Bandeja / smash"
        case .serve: return "Saque"
        case .unknown: return "Sin clasificar"
        }
    }
}

#Preview {
    WatchRootView()
        .environmentObject(SessionController())
}
