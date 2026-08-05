import SwiftUI

/// El perfil de la liga y los 3 objetivos por partido — la parte de la liga del
/// `AjustesScreen` de la app Expo. Los objetivos son los textos que puntúan cada
/// partido (cumple 2 de 3 = bien jugado) y los que lee el entrenador.
struct LigaAjustesView: View {
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss

    @State private var perfil: LigaPerfil
    @State private var objetivos: [String]

    init(liga: LigaModel) {
        _perfil = State(initialValue: liga.state.perfil)
        var textos = liga.state.objetivos
        while textos.count < 3 { textos.append("") }
        _objetivos = State(initialValue: textos)
    }

    var body: some View {
        NavigationStack {
            Form {
                perfilSection
                objetivosSection
            }
            .scrollContentBackground(.hidden)
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle("Objetivos y perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                }
            }
        }
    }

    private var perfilSection: some View {
        Section {
            LabeledContent("Inicio de la liga") {
                TextField("2026-01-15", text: $perfil.fechaInicio)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            LabeledContent("Nivel Playtomic inicial") {
                TextField("2.75", text: $perfil.nivelPlaytomic)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Meta de la temporada") {
                TextField("3.5", text: $perfil.nivelObjetivo)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            // El campo se llama nivelBand en el backup (herencia de Padel Band), pero
            // el dato es el nivel de sesión que mide el reloj.
            LabeledContent("Nivel de sesión habitual") {
                TextField("3.2", text: $perfil.nivelBand)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Perfil")
        } footer: {
            Text("El punto de partida de tu temporada: es lo que el entrenador usa para "
                 + "medir tu progreso. Son campos de texto — el formato es el de la liga "
                 + "original.")
        }
    }

    private var objetivosSection: some View {
        Section {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField("Objetivo \(index + 1)", text: $objetivos[index], axis: .vertical)
                        .font(.system(size: 14, design: .rounded))
                    // Las ideas del catálogo original, a un toque: escribir un objetivo
                    // medible desde cero cuesta más que elegirlo.
                    Menu {
                        ForEach(LigaCatalogos.catalogoObjetivos, id: \.self) { idea in
                            Button(idea) { objetivos[index] = idea }
                        }
                    } label: {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 14))
                            .foregroundStyle(T.pista)
                    }
                }
            }
        } header: {
            Text("Tus 3 objetivos por partido")
        } footer: {
            Text("Cumple 2 de 3 para que el partido cuente como bien jugado. El entrenador "
                 + "los revisa y te prescribe nuevos cuando toca subir la exigencia.")
        }
    }

    private func guardar() {
        liga.savePerfil(perfil)
        liga.saveObjetivos(objetivos.map { $0.trimmingCharacters(in: .whitespaces) })
        dismiss()
    }
}
