import PadelCore
import PhotosUI
import SwiftUI

/// Importar un partido que se jugó **sin nuestro reloj**: una captura de la app de la
/// pulsera, más el esfuerzo que haya en Apple Salud.
///
/// ## Por qué las dos cosas juntas
///
/// Cada fuente trae la mitad que a la otra le falta. La captura tiene los **golpes**
/// —cuántos, de qué tipo, con qué nota— y no sabe nada del esfuerzo. Salud tiene el
/// **esfuerzo** —duración, pulso, calorías— y no tiene ningún tipo de dato para "golpe de
/// pádel". Juntas hacen un partido completo; cada una por separado, medio.
///
/// ## Nada se guarda sin que lo mires
///
/// Esta pantalla **no importa: propone**. Cada número sale con la línea de la captura de
/// la que se leyó, en un campo que se puede corregir, y nada entra en la liga hasta que se
/// pulsa Guardar. Un número mal leído es peor que un hueco: entra con la misma pinta que
/// uno medido y nadie lo cuestiona meses después. Ver `LecturaDeCaptura`.
///
/// La captura no se guarda en ningún sitio: se lee en el dispositivo, se saca el texto y
/// la imagen se suelta.
struct ImportarCapturaView: View {
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var salud = SaludDelIPhone()

    @State private var elegida: PhotosPickerItem?
    @State private var imagen: UIImage?
    @State private var leida: LecturaDeCaptura.CapturaLeida?
    @State private var leyendo = false
    @State private var aviso: String?

    @State private var fecha = Date()
    @State private var nivel = ""
    @State private var totalGolpes = ""
    @State private var duracion = ""
    @State private var pulsoMedio = ""
    @State private var pulsoMax = ""
    @State private var calorias = ""
    @State private var golpes: [GolpeEditable] = []
    @State private var entrenamiento: UUID?

    /// Un golpe del repertorio con lo que se leyó de él, editable. Los dos campos son
    /// texto y no números: un campo numérico vacío tendría que valer algo, y "no lo sé"
    /// no es un número.
    private struct GolpeEditable: Identifiable {
        let golpe: GolpeVisible
        var nota: String
        var cantidad: String
        /// La línea de la captura de la que salió. Es lo que permite ver si se leyó bien.
        var origen: String

        var id: String { golpe.etiqueta }
    }

    var body: some View {
        NavigationStack {
            Form {
                capturaSection
                if leida != nil {
                    datosSection
                    golpesSection
                }
                saludSection
            }
            .scrollContentBackground(.hidden)
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle("Partido sin reloj")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(!hayAlgoQueGuardar)
                }
            }
            .onChange(of: elegida) { _, nueva in
                guard let nueva else { return }
                Task { await cargar(nueva) }
            }
        }
    }

    // MARK: La captura

    private var capturaSection: some View {
        Section {
            PhotosPicker(selection: $elegida, matching: .images) {
                Label(
                    imagen == nil ? "Elegir captura de la pulsera" : "Cambiar captura",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
            if let imagen {
                Image(uiImage: imagen)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if leyendo {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Leyendo la captura…").font(.caption)
                }
            }
            if let aviso {
                Text(aviso)
                    .font(.caption)
                    .foregroundStyle(T.rojo)
            }
            if let leida, !leida.sinEntender.isEmpty {
                // Lo que no se entendió, por si falta un dato que el jugador sí ve en su
                // captura: sin esto, el dato desaparecido no tiene explicación.
                DisclosureGroup("Líneas que no se entendieron (\(leida.sinEntender.count))") {
                    ForEach(leida.sinEntender, id: \.self) { linea in
                        Text(linea)
                            .font(.caption2)
                            .foregroundStyle(T.tintaSuave)
                    }
                }
            }
        } header: {
            Text("La captura")
        } footer: {
            Text("Se lee en el móvil y no sale de aquí: se saca el texto y la imagen se "
                 + "suelta. Lo que se guarda son los números que confirmes abajo.")
        }
    }

    // MARK: Los números

    private var datosSection: some View {
        Section {
            DatePicker("Día del partido", selection: $fecha, displayedComponents: .date)
            campo("Nivel de la sesión", texto: $nivel, pista: "3,5", origen: leida?.nivelSesion?.origen)
            campo("Golpes totales", texto: $totalGolpes, pista: "284", origen: leida?.totalGolpes?.origen)
            campo("Duración (min)", texto: $duracion, pista: "90", origen: leida?.duracionMin?.origen)
        } header: {
            Text("Lo que se ha leído")
        } footer: {
            Text("Debajo de cada campo está la línea de la captura de la que salió. Si "
                 + "algo se leyó torcido, corrígelo aquí — lo que dejes en blanco se queda "
                 + "fuera y no se guarda como cero.")
        }
    }

    @ViewBuilder
    private func campo(
        _ titulo: String, texto: Binding<String>, pista: String, origen: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(titulo) {
                TextField(pista, text: texto)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
            if let origen {
                Text("leído de «\(origen)»")
                    .font(.caption2)
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    @ViewBuilder
    private var golpesSection: some View {
        if golpes.isEmpty {
            Section {
                Text("La captura no traía golpes por tipo. Si tu app los enseña en otra "
                     + "pantalla, importa esa captura también: se guarda sobre el mismo día.")
                    .font(.caption)
                    .foregroundStyle(T.tintaSuave)
            } header: {
                Text("Golpes")
            }
        } else {
            Section {
                ForEach($golpes) { $golpe in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(golpe.golpe.etiqueta)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer(minLength: 4)
                            TextField("nota", text: $golpe.nota)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 52)
                            TextField("n.º", text: $golpe.cantidad)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 52)
                        }
                        Text("leído de «\(golpe.origen)»")
                            .font(.caption2)
                            .foregroundStyle(T.tintaSuave)
                    }
                }
            } header: {
                Text("Golpes (nota y cantidad)")
            }
        }
    }

    // MARK: Apple Salud

    private var saludSection: some View {
        Section {
            Button {
                Task {
                    if await salud.pedirPermiso() { await salud.buscar(enElDia: fecha) }
                }
            } label: {
                Label("Buscar el entrenamiento de ese día", systemImage: "heart.text.square")
            }
            .disabled(salud.buscando)

            if salud.buscando { ProgressView() }

            ForEach(salud.entrenamientos) { entreno in
                Button {
                    elegir(entreno)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: entrenamiento == entreno.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(T.pista)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(entreno.actividad) · \(entreno.duracionMin) min")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(resumen(entreno))
                                .font(.caption2)
                                .foregroundStyle(T.tintaSuave)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if let aviso = salud.aviso {
                Text(aviso)
                    .font(.caption)
                    .foregroundStyle(T.tintaSuave)
            }

            campo("Pulso medio", texto: $pulsoMedio, pista: "138", origen: leida?.pulsoMedio?.origen)
            campo("Pulso máximo", texto: $pulsoMax, pista: "176", origen: leida?.pulsoMax?.origen)
            campo("Calorías", texto: $calorias, pista: "610", origen: leida?.calorias?.origen)
        } header: {
            Text("Esfuerzo (Apple Salud)")
        } footer: {
            Text("Salud no guarda golpes de pádel: lo que aporta es el esfuerzo. Si eliges "
                 + "un entrenamiento, rellena los tres campos de abajo y puedes retocarlos.")
        }
    }

    private func resumen(_ entreno: SaludDelIPhone.Entrenamiento) -> String {
        var piezas: [String] = []
        if let medio = entreno.pulsoMedio { piezas.append("\(medio) ppm medios") }
        if let calorias = entreno.calorias { piezas.append("\(calorias) kcal") }
        piezas.append("según \(entreno.origen)")
        return piezas.joined(separator: " · ")
    }

    private func elegir(_ entreno: SaludDelIPhone.Entrenamiento) {
        entrenamiento = entreno.id
        // Se rellenan los campos en vez de guardarse aparte: así el jugador ve qué va a
        // entrar y lo puede cambiar, igual que con lo leído de la captura.
        duracion = String(entreno.duracionMin)
        if let medio = entreno.pulsoMedio { pulsoMedio = String(medio) }
        if let maximo = entreno.pulsoMax { pulsoMax = String(maximo) }
        if let kcal = entreno.calorias { calorias = String(kcal) }
    }

    // MARK: Cargar y guardar

    private func cargar(_ item: PhotosPickerItem) async {
        leyendo = true
        aviso = nil
        defer { leyendo = false }

        guard let datos = try? await item.loadTransferable(type: Data.self),
              let foto = UIImage(data: datos) else {
            aviso = "Esa imagen no se pudo abrir."
            return
        }
        imagen = foto
        do {
            let resultado = try await LectorDeCapturas.leer(foto)
            leida = resultado
            volcar(resultado)
            if resultado.vacia {
                aviso = "No se ha reconocido ningún número. Prueba con una captura más "
                    + "cercana o escribe los datos a mano."
            }
        } catch {
            aviso = (error as? LocalizedError)?.errorDescription
                ?? "No se ha podido leer la captura."
        }
    }

    /// Pasa lo leído a los campos editables. **Solo lo que esté vacío**: si el jugador ya
    /// corrigió algo y luego importa una segunda captura del mismo partido, su corrección
    /// manda sobre la lectura nueva.
    private func volcar(_ resultado: LecturaDeCaptura.CapturaLeida) {
        func poner(_ campo: inout String, _ dato: LecturaDeCaptura.Dato?, entero: Bool) {
            guard campo.isEmpty, let dato else { return }
            campo = entero ? String(Int(dato.valor.rounded())) : textoDe(dato.valor)
        }
        poner(&nivel, resultado.nivelSesion, entero: false)
        poner(&totalGolpes, resultado.totalGolpes, entero: true)
        poner(&duracion, resultado.duracionMin, entero: true)
        poner(&pulsoMedio, resultado.pulsoMedio, entero: true)
        poner(&pulsoMax, resultado.pulsoMax, entero: true)
        poner(&calorias, resultado.calorias, entero: true)

        for leido in resultado.golpes where !golpes.contains(where: { $0.golpe == leido.golpe }) {
            golpes.append(
                GolpeEditable(
                    golpe: leido.golpe,
                    nota: leido.nota.map { textoDe($0.valor) } ?? "",
                    cantidad: leido.cantidad.map { String(Int($0.valor.rounded())) } ?? "",
                    origen: leido.nota?.origen ?? leido.cantidad?.origen ?? ""
                )
            )
        }
        // En el orden del repertorio, como en el resto de la app.
        golpes.sort { a, b in
            let orden = GolpeVisible.allCases
            let i = orden.firstIndex(of: a.golpe) ?? 0
            let j = orden.firstIndex(of: b.golpe) ?? 0
            return i < j
        }
    }

    /// Con coma, que es como se escribe un nivel en español y como lo va a leer el jugador.
    private func textoDe(_ valor: Double) -> String {
        String(format: "%.1f", valor).replacingOccurrences(of: ".", with: ",")
    }

    private func numero(_ texto: String) -> Double? {
        Double(texto.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var hayAlgoQueGuardar: Bool {
        numero(nivel) != nil || numero(totalGolpes) != nil || numero(duracion) != nil
            || golpes.contains { numero($0.nota) != nil || numero($0.cantidad) != nil }
    }

    private func guardar() {
        let notas = golpes.compactMap { editable -> LigaGolpeSesion? in
            guard let nota = numero(editable.nota) else { return nil }
            return LigaGolpeSesion(nombre: editable.golpe.etiqueta, nota: nota)
        }
        let volumen = golpes.compactMap { editable -> LigaGolpeVolumen? in
            guard let cantidad = numero(editable.cantidad) else { return nil }
            return LigaGolpeVolumen(nombre: editable.golpe.etiqueta, cantidad: Int(cantidad))
        }

        // La salud solo se guarda si hay algo que guardar: un `LigaSaludPartido` con todo
        // a nil y cero minutos ocuparía sitio en el backup para decir "no se sabe nada".
        let minutos = numero(duracion).map { Int($0) } ?? 0
        let medio = numero(pulsoMedio).map { Int($0) }
        let maximo = numero(pulsoMax).map { Int($0) }
        let kcal = numero(calorias).map { Int($0) }
        let haySalud = minutos > 0 || medio != nil || maximo != nil || kcal != nil

        liga.guardarDesdeCaptura(
            fecha: fecha,
            nivelSesion: numero(nivel),
            totalGolpes: numero(totalGolpes).map { Int($0) },
            golpes: notas,
            volumen: volumen,
            salud: haySalud
                ? LigaSaludPartido(
                    duracionMin: minutos, pulsoMedio: medio, pulsoMax: maximo, calorias: kcal
                )
                : nil
        )
        dismiss()
    }
}
