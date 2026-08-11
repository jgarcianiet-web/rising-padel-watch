import SwiftUI

/// El perfil de la liga y los 3 objetivos por partido — la parte de la liga del
/// `AjustesScreen` de la app Expo. Los objetivos son los textos que puntúan cada
/// partido (cumple 2 de 3 = bien jugado) y los que lee el entrenador.
struct LigaAjustesView: View {
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss

    @State private var perfil: LigaPerfil
    @State private var objetivos: [String]
    @State private var metaPartidos: String
    @State private var confirmandoTemporada = false
    /// Las fechas de la temporada en curso, editables. Antes solo se podía saber cuándo
    /// empezó —el día que le diste al botón— y nunca cuándo pensabas acabarla.
    @State private var inicioTemporada = Date()
    @State private var finTemporada = Date()
    @State private var conFinPrevisto = false

    init(liga: LigaModel) {
        _perfil = State(initialValue: liga.state.perfil)
        var textos = liga.state.objetivos
        while textos.count < 3 { textos.append("") }
        _objetivos = State(initialValue: textos)
        _metaPartidos = State(
            initialValue: liga.temporadaActual?.objetivoPartidos.map(String.init) ?? ""
        )
        let actual = liga.temporadaActual
        _inicioTemporada = State(
            initialValue: actual.flatMap { LigaFechas.fecha($0.fechaInicio) } ?? Date()
        )
        let previsto = actual.flatMap { LigaFechas.fecha($0.fechaFinPrevista) }
        _conFinPrevisto = State(initialValue: previsto != nil)
        // Por defecto, la temporada de pádel de toda la vida: unos nueve meses.
        _finTemporada = State(
            initialValue: previsto ?? Calendar.current.date(byAdding: .month, value: 9, to: Date()) ?? Date()
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                temporadaSection
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

    private var temporadaSection: some View {
        Section {
            if let actual = liga.temporadaActual {
                LabeledContent(actual.nombre) {
                    Text(actual.rangoCorto)
                        .foregroundStyle(T.tintaSuave)
                }
                // Editable: la fecha de inicio la ponía el botón (el día que lo pulsaste)
                // y a veces no es la que quieres — la temporada empezó en septiembre
                // aunque la app la estrenaras en noviembre.
                DatePicker(
                    "Empieza",
                    selection: $inicioTemporada,
                    displayedComponents: .date
                )
                Toggle("Tiene fecha de fin", isOn: $conFinPrevisto)
                if conFinPrevisto {
                    DatePicker(
                        "Acaba",
                        selection: $finTemporada,
                        in: inicioTemporada...,
                        displayedComponents: .date
                    )
                }
                LabeledContent("Meta de partidos") {
                    TextField("20", text: $metaPartidos)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
            } else {
                LabeledContent("Meta de partidos") {
                    TextField("20", text: $metaPartidos)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
            }
            Button {
                confirmandoTemporada = true
            } label: {
                Label(
                    liga.temporadaActual == nil
                        ? "Empezar la primera temporada"
                        : "Empezar la siguiente temporada",
                    systemImage: "flag.checkered"
                )
            }
            .confirmationDialog(
                liga.temporadaActual == nil
                    ? "La temporada empieza hoy; los partidos anteriores quedan como historial previo."
                    : "Se cierra \(liga.temporadaActual?.nombre ?? "la actual") con lo jugado hasta ayer y la nueva empieza hoy.",
                isPresented: $confirmandoTemporada,
                titleVisibility: .visible
            ) {
                Button("Empezar temporada") {
                    liga.startTemporada(objetivoPartidos: Int(metaPartidos))
                }
            }
        } header: {
            Text("Temporadas")
        } footer: {
            Text("Cada temporada agrupa sus partidos por fecha. La fecha de fin es la "
                 + "que piensas cerrarla: sirve para la cuenta atrás y para saber si vas "
                 + "en hora con la meta, y no cierra la temporada por su cuenta — los "
                 + "partidos posteriores siguen contando hasta que empieces la siguiente. "
                 + "El entrenador analiza la temporada en curso y la compara con las "
                 + "anteriores, y el panel las enfrenta temporada a temporada.")
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
        // La meta de la temporada en curso también se guarda desde aquí: cambiarla no
        // exige abrir temporada nueva.
        liga.setObjetivoPartidos(Int(metaPartidos))
        if liga.temporadaActual != nil {
            liga.setFechasDeTemporada(
                inicio: LigaFechas.iso(inicioTemporada),
                finPrevisto: conFinPrevisto ? LigaFechas.iso(finTemporada) : ""
            )
        }
        dismiss()
    }
}
