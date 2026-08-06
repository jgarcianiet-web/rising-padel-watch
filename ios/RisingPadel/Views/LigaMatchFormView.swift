import SwiftUI

/// El formulario completo de partido de la liga, portado de `PartidoScreen` de la app
/// Expo: sirve para dar de alta un partido a mano y para editar cualquiera, venga del
/// reloj, de un backup o de esta misma pantalla.
///
/// Las series del reloj (curva, frecuencia, volumen, salud, notas por golpe) no se
/// editan a mano — se conservan tal cual al guardar, igual que hacía la app Expo.
struct LigaMatchFormView: View {
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss

    /// Nil = alta de un partido nuevo.
    let editing: LigaMatch?

    @State private var fecha: Date
    @State private var tipo: String
    @State private var resultadoManual: String
    @State private var posicion: String
    @State private var marcador: [LigaSetMarcador]
    @State private var club: String
    @State private var companero: String
    @State private var rivales: String
    @State private var nivel: String
    @State private var nivelBand: String
    @State private var mejorGolpe: String
    @State private var mejorPunt: Int
    @State private var peorGolpe: String
    @State private var peorPunt: Int
    @State private var objsCumplidos: [Bool]
    @State private var nota: String

    init(editing: LigaMatch? = nil) {
        self.editing = editing
        _fecha = State(initialValue: editing.flatMap { LigaFechas.fecha($0.fecha) } ?? Date())
        _tipo = State(initialValue: editing?.tipo ?? "competitivo")
        _resultadoManual = State(initialValue: editing?.resultado ?? "victoria")
        _posicion = State(initialValue: editing?.posicion ?? "reves")
        var sets = LigaMarcadorForm.vacio()
        for (index, set) in (editing?.marcador ?? []).prefix(3).enumerated() {
            sets[index] = set
        }
        _marcador = State(initialValue: sets)
        _club = State(initialValue: editing?.club ?? "")
        _companero = State(initialValue: editing?.companero ?? "")
        _rivales = State(initialValue: editing?.rivales ?? "")
        _nivel = State(initialValue: editing?.nivel.map { String(format: "%.2f", $0) } ?? "")
        _nivelBand = State(initialValue: editing?.nivelBand.map { String(format: "%.1f", $0) } ?? "")
        _mejorGolpe = State(initialValue: editing?.mejorGolpe ?? "")
        _mejorPunt = State(initialValue: editing?.mejorPunt.map { Int($0) } ?? 0)
        _peorGolpe = State(initialValue: editing?.peorGolpe ?? "")
        _peorPunt = State(initialValue: editing?.peorPunt.map { Int($0) } ?? 0)
        var cumplidos = editing?.objetivos ?? [false, false, false]
        while cumplidos.count < 3 { cumplidos.append(false) }
        _objsCumplidos = State(initialValue: cumplidos)
        _nota = State(initialValue: editing?.nota ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                matchSection
                scoreSection
                levelsSection
                strokesSection
                goalsSection
            }
            .scrollContentBackground(.hidden)
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle(editing == nil ? "Nuevo partido" : "Editar partido")
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

    // MARK: Secciones

    private var matchSection: some View {
        Section("El partido") {
            DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
            Picker("Tipo", selection: $tipo) {
                Text("Competitivo").tag("competitivo")
                Text("Amistoso").tag("amistoso")
            }
            .pickerStyle(.segmented)
            Picker("Posición", selection: $posicion) {
                Text("Revés").tag("reves")
                Text("Derecha").tag("derecha")
            }
            .pickerStyle(.segmented)

            TextField("Club / pista", text: $club)
            if !liga.clubesPrevios.isEmpty {
                chipsPrevios(liga.clubesPrevios, seleccion: $club)
            }
            TextField("Compañero (opcional)", text: $companero)
            if !liga.companerosPrevios.isEmpty {
                chipsPrevios(liga.companerosPrevios, seleccion: $companero)
            }
            // Los rivales alimentan el cara a cara: "Juan y Pedro" cuenta un partido
            // contra cada uno.
            TextField("Rivales (ej: Juan y Pedro)", text: $rivales)
            if !liga.rivalesPrevios.isEmpty {
                chipsPrevios(liga.rivalesPrevios, seleccion: $rivales)
            }
        }
    }

    private var scoreSection: some View {
        Section {
            ForEach(0..<3, id: \.self) { index in
                setRow(index)
            }
            if let calculado = LigaMarcadorForm.calcularResultado(marcador) {
                HStack {
                    Text("Resultado")
                        .foregroundStyle(T.tintaSuave)
                    Spacer()
                    OutcomeBadge(
                        text: "\(calculado) \(LigaMarcadorForm.setsGanados(marcador))–\(LigaMarcadorForm.setsPerdidos(marcador))",
                        color: badgeColor(calculado)
                    )
                }
            } else {
                Picker("Resultado", selection: $resultadoManual) {
                    Text("Victoria").tag("victoria")
                    Text("Empate").tag("empate")
                    Text("Derrota").tag("derrota")
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Marcador")
        } footer: {
            Text("Con algún set anotado el resultado se calcula solo; sin marcador, elígelo a mano.")
        }
    }

    private func setRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Text("Set \(index + 1)")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .frame(width: 44, alignment: .leading)
            TextField("Yo", text: $marcador[index].yo)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 44)
            Text("–").foregroundStyle(T.tintaSuave)
            TextField("Ellos", text: $marcador[index].rival)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 44)
            if LigaMarcadorForm.esTiebreak(marcador[index]) {
                Spacer(minLength: 4)
                Text("TB")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(T.pista)
                TextField("0", text: $marcador[index].tbYo)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 36)
                Text("–").foregroundStyle(T.tintaSuave)
                TextField("0", text: $marcador[index].tbRival)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 36)
            } else {
                Spacer()
            }
        }
    }

    private var levelsSection: some View {
        Section {
            LabeledContent("Playtomic tras el partido") {
                TextField("3.42", text: $nivel)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            LabeledContent("Nivel de la sesión (1-7)") {
                TextField("3.5", text: $nivelBand)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        } header: {
            Text("Niveles de la sesión")
        } footer: {
            if editing?.bandPuntos != nil || editing?.golpesVolumen != nil || editing?.salud != nil {
                Text("Las curvas, el volumen y la salud que midió el reloj se conservan tal cual al guardar.")
            }
        }
    }

    private var strokesSection: some View {
        Section {
            golpePicker("👍 Mejor golpe", golpe: $mejorGolpe, punt: $mejorPunt)
            golpePicker("👎 Peor golpe", golpe: $peorGolpe, punt: $peorPunt)
        } header: {
            Text("Golpes destacados")
        } footer: {
            Text("Escala: 1 peor · 7 mejor")
        }
    }

    @ViewBuilder
    private func golpePicker(_ titulo: String, golpe: Binding<String>, punt: Binding<Int>) -> some View {
        Picker(titulo, selection: golpe) {
            Text("Sin elegir").tag("")
            ForEach(LigaCatalogos.golpes, id: \.self) { nombre in
                Text(nombre).tag(nombre)
            }
        }
        if !golpe.wrappedValue.isEmpty {
            Picker("Puntuación", selection: punt) {
                Text("–").tag(0)
                ForEach(1...7, id: \.self) { Text("\($0)/7").tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var goalsSection: some View {
        Section {
            ForEach(Array(liga.state.objetivos.prefix(3).enumerated()), id: \.offset) { index, texto in
                Toggle(isOn: $objsCumplidos[index]) {
                    Text(texto)
                        .font(.system(size: 13, design: .rounded))
                }
            }
            TextField("Nota (opcional)", text: $nota, axis: .vertical)
        } header: {
            Text("Tus objetivos")
        } footer: {
            Text("Cumple 2 de 3 para mantener la racha. Los objetivos se cambian en "
                 + "Objetivos y perfil, en el menú de la Liga.")
        }
    }

    private func chipsPrevios(_ opciones: [String], seleccion: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(opciones, id: \.self) { opcion in
                    Button {
                        seleccion.wrappedValue = opcion
                    } label: {
                        Text(opcion)
                            .font(.system(size: 12, design: .rounded))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 9)
                            .background(
                                seleccion.wrappedValue == opcion ? T.pistaTinte : T.fondo,
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(T.borde, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Guardar

    private func guardar() {
        let setsStr = LigaMarcadorForm.formatearSets(marcador)
        let jugados = LigaMarcadorForm.setsJugados(marcador)
        // Como en la Expo: con sets anotados manda el cálculo; sin ellos, la elección
        // manual (que al editar se precarga con el resultado guardado).
        let resultado = setsStr.isEmpty
            ? resultadoManual
            : (LigaMarcadorForm.calcularResultado(marcador) ?? resultadoManual)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let match = LigaMatch(
            // Como en la Expo: `Date.now()` para un alta, el id original al editar.
            id: editing?.id ?? Int64(Date().timeIntervalSince1970 * 1000),
            fecha: formatter.string(from: fecha),
            tipo: tipo,
            resultado: resultado,
            posicion: posicion,
            sets: setsStr.isEmpty ? (editing?.sets ?? "") : setsStr,
            marcador: setsStr.isEmpty ? editing?.marcador : jugados,
            club: club.trimmingCharacters(in: .whitespaces),
            companero: companero.trimmingCharacters(in: .whitespaces),
            rivales: rivales.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : rivales.trimmingCharacters(in: .whitespaces),
            nivel: Double(nivel.replacingOccurrences(of: ",", with: ".")),
            nivelBand: Double(nivelBand.replacingOccurrences(of: ",", with: ".")),
            mejorGolpe: mejorGolpe.isEmpty ? nil : mejorGolpe,
            mejorPunt: mejorGolpe.isEmpty || mejorPunt == 0 ? nil : Double(mejorPunt),
            peorGolpe: peorGolpe.isEmpty ? nil : peorGolpe,
            peorPunt: peorGolpe.isEmpty || peorPunt == 0 ? nil : Double(peorPunt),
            golpesSesion: editing?.golpesSesion,
            objetivos: objsCumplidos,
            nota: nota.trimmingCharacters(in: .whitespaces),
            bandInicio: editing?.bandInicio,
            bandFin: editing?.bandFin,
            bandMediaJugador: editing?.bandMediaJugador,
            golpesVolumen: editing?.golpesVolumen,
            totalGolpes: editing?.totalGolpes,
            salud: editing?.salud,
            bandPuntos: editing?.bandPuntos,
            frecuenciaGolpeo: editing?.frecuenciaGolpeo
        )
        liga.upsert(match)
        liga.message = editing == nil ? "Partido guardado" : "Cambios guardados"
        dismiss()
    }

    private func badgeColor(_ resultado: String) -> Color {
        switch resultado {
        case "victoria": return T.verde
        case "empate": return T.tintaSuave
        default: return T.rojo
        }
    }
}
