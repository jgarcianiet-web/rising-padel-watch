import PadelCore
import SwiftUI

/// Modo de recogida de datos para entrenar el clasificador.
///
/// La pantalla es deliberadamente aburrida: elige tipo, dale a grabar, pega treinta
/// golpes de ese tipo y para. Lo que la hace útil es que **la etiqueta se pone antes de
/// golpear**, no después mirando gráficas — que es donde fracasa el enfoque de "grábalo
/// todo y ya lo etiquetaremos".
struct TrainingView: View {
    @EnvironmentObject private var controller: SessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            if controller.trainingRecording {
                Text("\(controller.trainingCapturedInBatch)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(controller.trainingLabel.label)
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("Da 30-40 golpes solo de este tipo")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Parar tanda") { controller.stopTraining() }
                    .buttonStyle(.bordered)
            } else {
                Text("Datos de entrenamiento")
                    .font(.caption)
                    .bold()
                    .multilineTextAlignment(.center)
                // Toque = siguiente tipo. Se recorre la lista de golpes de la misma
                // forma que se graban: uno detrás de otro.
                Button {
                    controller.trainingLabel = controller.trainingLabel.nextRecordable()
                } label: {
                    VStack(spacing: 0) {
                        Text(controller.trainingLabel.label).font(.caption2)
                        Text("Tipo a grabar").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)

                Text("\(controller.trainingTotalStored) guardados · \(controller.trainingStoredKB) KB")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Button("Grabar") { Task { await controller.startTraining() } }
                    .buttonStyle(.borderedProminent)
                Button("Salir") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 8)
    }
}

extension ShotType {
    /// Siguiente tipo de golpe, saltándose `.unknown`: no es algo que se pueda grabar
    /// a propósito.
    func nextRecordable() -> ShotType {
        let recordable = ShotType.allCases.filter { $0 != .unknown }
        let index = recordable.firstIndex(of: self) ?? 0
        return recordable[(index + 1) % recordable.count]
    }
}
