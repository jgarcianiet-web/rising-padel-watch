import PadelCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                leagueSection
                privacySection
                playerSection
                sensitivitySection
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { dismiss() }
                }
            }
        }
    }

    private var leagueSection: some View {
        Section {
            TextField("https://mi-liga.example.com/api", text: $model.leagueBaseURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField(model.hasToken ? "Token (ya guardado)" : "Token", text: $token)
            Button("Guardar token") {
                model.setToken(token)
                token = ""
            }
            .disabled(token.isEmpty)
        } header: {
            Text("Liga")
        } footer: {
            Text("La app enviará las sesiones a <URL>/v1/padel-sessions. "
                 + "El token se guarda cifrado en el Llavero y no se muestra nunca.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Compartir datos de salud", isOn: $model.shareHealth)
            Toggle("Compartir el detalle de cada golpeo", isOn: $model.shareShotEvents)
        } header: {
            Text("Privacidad")
        } footer: {
            Text("Sin el primero, el reloj ni siquiera mide frecuencia cardiaca ni calorías. "
                 + "Sin el segundo solo se suben los totales por tipo, no la secuencia de golpeos.")
        }
    }

    private var playerSection: some View {
        Section {
            Picker("Mano de la pala", selection: $model.playerHandRaw) {
                Text("Diestro").tag(Hand.right.rawValue)
                Text("Zurdo").tag(Hand.left.rawValue)
            }
            Picker("Muñeca del reloj", selection: $model.watchWristRaw) {
                Text("Derecha").tag(Hand.right.rawValue)
                Text("Izquierda").tag(Hand.left.rawValue)
            }
            if !model.profile.watchOnRacketArm {
                Text("Para contar golpeos el reloj tiene que ir en el brazo con el que juegas. "
                     + "En la otra muñeca no ve el swing.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Jugador")
        }
    }

    private var sensitivitySection: some View {
        Section {
            Picker("Sensibilidad", selection: $model.sensitivityRaw) {
                Text("Baja").tag(Sensitivity.low.rawValue)
                Text("Media").tag(Sensitivity.medium.rawValue)
                Text("Alta").tag(Sensitivity.high.rawValue)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Detección")
        } footer: {
            Text("Si la app cuenta golpeos de más, baja la sensibilidad. "
                 + "Si se deja golpeos flojos sin contar, súbela.")
        }
    }
}

#Preview {
    SettingsView().environmentObject(AppModel(store: InMemorySessionStore()))
}
