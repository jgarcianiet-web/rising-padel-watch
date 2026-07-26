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
                trainingDataSection
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

    @ViewBuilder
    private var trainingDataSection: some View {
        Section {
            Toggle("Recoger datos de entrenamiento", isOn: $model.collectTrainingData)
            if model.collectTrainingData {
                TextField("Alias del jugador", text: $model.playerAlias)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let url = model.trainingDataURL {
                    // ShareLink en vez de subir a ningún sitio: el fichero solo sale del
                    // móvil si el usuario lo comparte a mano.
                    ShareLink(item: url) {
                        Label("Exportar \(model.trainingDataSizeKB) KB", systemImage: "square.and.arrow.up")
                    }
                    Button("Borrar datos recogidos", role: .destructive) {
                        model.deleteTrainingData()
                    }
                } else {
                    Text("Todavía no ha llegado ningún dato del reloj.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Datos de entrenamiento")
        } footer: {
            Text("Graba tandas de golpes etiquetados en el reloj para entrenar un "
                 + "clasificador propio. Guarda la señal cruda de los sensores, que en el "
                 + "resto de la app nunca sale del dispositivo. **No se sube a la liga**: "
                 + "solo sale de aquí si lo exportas tú.")
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
