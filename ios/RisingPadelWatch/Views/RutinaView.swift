import PadelCore
import SwiftUI

/// Elegir la rutina del día. Cuatro tarjetas y a la pista.
struct RutinaChooserView: View {
    @EnvironmentObject private var controller: SessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("RUTINAS")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .kerning(1.4)
                    .foregroundStyle(.tint)

                ForEach(Rutina.deFabrica) { rutina in
                    Button {
                        dismiss()
                        Task { await controller.start(rutina: rutina) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rutina.nombre)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(rutina.proposito)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                            Text("\(rutina.pasos.count) ejercicios · \(rutina.golpesTotales) golpes")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Volver") { dismiss() }
                    .font(.caption2)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)
        }
    }
}

/// El ejercicio que toca, en grande, mientras se entrena.
///
/// La pantalla está pensada para verse de reojo con la pala en la mano: el número que
/// falta ocupa media esfera y todo lo demás es contexto. Lo que de verdad guía no es
/// esta pantalla sino el motor —un toque por golpe, otro distinto al terminar el
/// ejercicio—, porque entre golpe y golpe nadie mira el reloj.
struct RutinaEnCursoView: View {
    @EnvironmentObject private var controller: SessionController

    var body: some View {
        ScrollView {
            VStack(spacing: 3) {
                if controller.rutinaTerminada {
                    terminada
                } else if let paso = controller.pasoDeRutina {
                    enMarcha(paso)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func enMarcha(_ paso: ProgresoDeRutina) -> some View {
        Text("\(paso.indice + 1) de \(paso.totalPasos)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)

        Text(paso.paso.type.label)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(.tint)
            .multilineTextAlignment(.center)

        // Lo que falta y no lo que llevas: en mitad de un ejercicio la pregunta es
        // "¿cuánto queda?", y restar de cabeza entre golpe y golpe no es gratis.
        Text("\(paso.restantes)")
            .font(.system(size: 52, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: paso.restantes)

        Text("por dar")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

        ProgressView(value: Double(paso.fraccion))
            .tint(.green)
            .padding(.vertical, 2)

        if paso.fueraDeTipo > 3 {
            // Si se cuelan muchos golpes de otro tipo, o el jugador está haciendo otra
            // cosa o el detector no reconoce el que toca. Las dos merecen saberse.
            Text("\(paso.fueraDeTipo) golpes de otro tipo")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
        }

        Button("Saltar ejercicio") { controller.saltarPasoDeRutina() }
            .font(.caption2)
            .buttonStyle(.bordered)
    }

    private var terminada: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundStyle(.green)
            Text("Rutina completa")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(controller.rutina?.nombre ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Desliza a la izquierda para finalizar")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
}
