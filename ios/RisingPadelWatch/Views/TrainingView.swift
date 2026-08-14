import PadelCore
import SwiftUI

/// Modo de recogida de datos: elige el tipo, graba la tanda entera y para.
///
/// El número grande es el TIEMPO, no los golpes, y es una decisión de confianza: la
/// tanda se graba en crudo y el reloj siempre está guardando mientras el cronómetro
/// corre. Los golpes que el detector cree ver salen debajo, como información — si no ve
/// ninguno, la tanda vale igual.
struct TrainingView: View {
    @EnvironmentObject private var controller: SessionController
    @Environment(\.dismiss) private var dismiss

    private var grabables: [ShotType] { ShotType.allCases.filter { $0 != .unknown } }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if controller.trainingRecording {
                    Text(tiempo(controller.trainingSegundos))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(etiqueta(controller.trainingLabel))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tint)
                    Text("\(controller.trainingCapturedInBatch) golpes vistos")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                    if controller.sensorsMayStop {
                        Text("Sin permiso de entreno: no apagues la pantalla")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button("Parar tanda") {
                        Task { await controller.stopTraining() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Text("Datos de entrenamiento")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    // Toque = siguiente tipo, en el mismo orden en que se graban.
                    Button {
                        controller.trainingLabel = siguiente(controller.trainingLabel)
                    } label: {
                        VStack(spacing: 1) {
                            Text(etiqueta(controller.trainingLabel))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text("Tipo a grabar")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Text("\(controller.trainingTotalStored) tandas · \(controller.trainingStoredKB) KB")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    Button("Grabar") {
                        Task { await controller.startTraining() }
                    }
                    .buttonStyle(.borderedProminent)
                    if controller.trainingTotalStored > 0 {
                        Button("Enviar al móvil") {
                            _ = controller.sendTrainingDataToPhone()
                        }
                    }
                    Button("Salir") { dismiss() }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func tiempo(_ segundos: Int) -> String {
        String(format: "%d:%02d", segundos / 60, segundos % 60)
    }

    private func siguiente(_ tipo: ShotType) -> ShotType {
        let index = grabables.firstIndex(of: tipo) ?? 0
        return grabables[(index + 1) % grabables.count]
    }

    private func etiqueta(_ tipo: ShotType) -> String {
        switch tipo {
        case .forehand: return "Derecha"
        case .backhand: return "Revés"
        case .forehandVolley: return "Volea de derecha"
        case .backhandVolley: return "Volea de revés"
        case .bandeja: return "Bandeja"
        case .vibora: return "Víbora"
        case .smash: return "Smash"
        case .serve: return "Saque"
        case .unknown: return "Sin clasificar"
        }
    }
}
