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
    @State private var sendResult: String?

    var body: some View {
        // Con varios botones la columna no cabe en un reloj de 40 mm; sin scroll, lo de
        // abajo queda directamente inalcanzable.
        ScrollView {
            content
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
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
                if controller.sensorsMayStop {
                    // Sin workout la app se suspende al apagarse la pantalla y la tanda
                    // se queda a medias: mejor decirlo que devolver 10 de 50 golpes.
                    Text("Sin permiso de entreno: la grabación puede pararse al apagarse la pantalla")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button("Parar tanda") { Task { await controller.stopTraining() } }
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

                // Sin este botón los golpeos se quedan en el reloj para siempre: el
                // móvil no puede ir a buscarlos. Al parar una tanda se envían solos,
                // pero si el iPhone estaba lejos hace falta poder reintentar a mano.
                if controller.trainingTotalStored > 0 {
                    Button("Enviar al móvil") {
                        sendResult = controller.sendTrainingDataToPhone()
                            ? "Enviando al móvil…"
                            : "No se pudo enviar"
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
                if let sendResult {
                    Text(sendResult)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Salir") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
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
