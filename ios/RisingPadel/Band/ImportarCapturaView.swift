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
    @State private var pasos = ""
    @State private var mediaJugador = ""
    @State private var mejorGolpe = ""
    @State private var golpes: [GolpeEditable] = []
    @State private var entrenamiento: UUID?

    /// Un golpe del repertorio con lo que se leyó de él, editable. Los dos campos son
    /// texto y no números: un campo numérico vacío tendría que valer algo, y "no lo sé"
    /// no es un número.
    private struct GolpeEditable: Identifiable {
        /// Lo que ponía en la captura, y lo que se guarda: la liga guarda los golpes por
        /// nombre y no por enum, así que un "Volea" sin lado cabe igual que una "Volea de
        /// revés".
        let nombre: String
        /// La correspondencia con nuestro repertorio, si la hay. Nil en los agregados que
        /// la captura da sin lado — y eso se le dice al jugador, no se parte en dos.
        let golpe: GolpeVisible?
        var nota: String
        var cantidad: String
        /// El texto de la captura del que salió. Es lo que permite ver si se leyó bien.
        var origen: String

        var id: String { nombre }
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
            campo("Calidad media del jugador", texto: $mediaJugador, pista: "3,45",
                  origen: leida?.mediaDelJugador?.origen)
            if !mejorGolpe.isEmpty {
                LabeledContent("Mejor golpe") { Text(mejorGolpe).foregroundStyle(T.tintaSuave) }
            }
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
                            VStack(alignment: .leading, spacing: 0) {
                                Text(golpe.nombre)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                if golpe.golpe == nil {
                                    // La captura lo dio sin lado. Se dice, no se reparte:
                                    // partir 175 voleas en dos mitades serían dos números
                                    // inventados.
                                    Text("sin lado en la captura")
                                        .font(.caption2)
                                        .foregroundStyle(T.tintaSuave)
                                }
                            }
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

    /// El esfuerzo del partido.
    ///
    /// **La captura ya lo trae casi todo.** La Padel Band calcula por su cuenta el
    /// tiempo, las calorías y los pasos, y los enseña en su pantalla de actividad, así
    /// que salen leídos de la imagen como cualquier otro número. Lo único que no da es el
    /// **pulso**: eso no lo mide una pulsera de pala.
    ///
    /// Y no lo da por otro sitio tampoco: **la Band no escribe nada en Apple Salud**. Su
    /// cálculo se queda en su app. Por eso buscar en Salud está abajo y como extra, no
    /// como el camino principal: solo encuentra algo si ese día llevabas además un reloj
    /// —el Apple Watch con la app de Entreno, por ejemplo— que sí escribiera el
    /// entrenamiento. Es el único modo de que un partido con pulsera tenga pulso.
    private var saludSection: some View {
        Section {
            campo("Pulso medio", texto: $pulsoMedio, pista: "138", origen: leida?.pulsoMedio?.origen)
            campo("Pulso máximo", texto: $pulsoMax, pista: "176", origen: leida?.pulsoMax?.origen)
            campo("Calorías", texto: $calorias, pista: "898", origen: leida?.calorias?.origen)
            campo("Pasos", texto: $pasos, pista: "8861", origen: leida?.pasos?.origen)

            Button {
                Task {
                    if await salud.pedirPermiso() { await salud.buscar(enElDia: fecha) }
                }
            } label: {
                Label("Buscar pulso en Apple Salud", systemImage: "heart.text.square")
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

        } header: {
            Text("Esfuerzo")
        } footer: {
            Text("El tiempo, las calorías y los pasos salen de la captura: la pulsera los "
                 + "calcula ella. El pulso no lo mide, y tampoco escribe en Apple Salud, "
                 + "así que buscar ahí solo sirve si ese día llevabas además un reloj que "
                 + "sí guardara el entrenamiento.")
        }
    }

    private func resumen(_ entreno: SaludDelIPhone.Entrenamiento) -> String {
        var piezas: [String] = []
        if let medio = entreno.pulsoMedio { piezas.append("\(medio) ppm medios") }
        if let calorias = entreno.calorias { piezas.append("\(calorias) kcal") }
        if let dados = entreno.pasos { piezas.append("\(dados) pasos") }
        piezas.append("según \(entreno.origen)")
        return piezas.joined(separator: " · ")
    }

    private func elegir(_ entreno: SaludDelIPhone.Entrenamiento) {
        entrenamiento = entreno.id
        // **Solo lo que esté vacío.** La captura manda sobre Salud en lo que las dos
        // saben: la pulsera cuenta los golpes del partido y su duración es la del
        // partido, mientras que el entrenamiento de Salud puede incluir el calentamiento
        // o lo que tardaste en acordarte de pararlo. Lo que de verdad viene a aportar
        // Salud es el pulso, que la pulsera no mide.
        func poner(_ campo: inout String, _ valor: Int?) {
            guard campo.isEmpty, let valor else { return }
            campo = String(valor)
        }
        poner(&pulsoMedio, entreno.pulsoMedio)
        poner(&pulsoMax, entreno.pulsoMax)
        poner(&duracion, entreno.duracionMin)
        poner(&calorias, entreno.calorias)
        poner(&pasos, entreno.pasos)
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
        poner(&pasos, resultado.pasos, entero: true)
        poner(&mediaJugador, resultado.mediaDelJugador, entero: false)
        if mejorGolpe.isEmpty, let mejor = resultado.mejorGolpe { mejorGolpe = mejor }

        // El orden ya lo pone el core (el repertorio primero y los agregados detrás), así
        // que aquí solo se añade lo que falte: reordenar otra vez movería de sitio lo que
        // el jugador ya está mirando al importar la segunda captura.
        for leido in resultado.golpes where !golpes.contains(where: { $0.nombre == leido.nombre }) {
            golpes.append(
                GolpeEditable(
                    nombre: leido.nombre,
                    golpe: leido.golpe,
                    nota: leido.nota.map { textoDe($0.valor) } ?? "",
                    cantidad: leido.cantidad.map { String(Int($0.valor.rounded())) } ?? "",
                    origen: leido.nota?.origen ?? leido.cantidad?.origen ?? ""
                )
            )
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
            return LigaGolpeSesion(nombre: editable.nombre, nota: nota)
        }
        let volumen = golpes.compactMap { editable -> LigaGolpeVolumen? in
            guard let cantidad = numero(editable.cantidad) else { return nil }
            return LigaGolpeVolumen(nombre: editable.nombre, cantidad: Int(cantidad))
        }

        // La salud solo se guarda si hay algo que guardar: un `LigaSaludPartido` con todo
        // a nil y cero minutos ocuparía sitio en el backup para decir "no se sabe nada".
        let minutos = numero(duracion).map { Int($0) } ?? 0
        let medio = numero(pulsoMedio).map { Int($0) }
        let maximo = numero(pulsoMax).map { Int($0) }
        let kcal = numero(calorias).map { Int($0) }
        let dados = numero(pasos).map { Int($0) }
        let haySalud = minutos > 0 || medio != nil || maximo != nil || kcal != nil || dados != nil

        liga.guardarDesdeCaptura(
            fecha: fecha,
            nivelSesion: numero(nivel),
            mediaDelJugador: numero(mediaJugador),
            mejorGolpe: mejorGolpe.isEmpty ? nil : mejorGolpe,
            totalGolpes: numero(totalGolpes).map { Int($0) },
            golpes: notas,
            volumen: volumen,
            salud: haySalud
                ? LigaSaludPartido(
                    duracionMin: minutos, pulsoMedio: medio, pulsoMax: maximo,
                    calorias: kcal, pasos: dados
                )
                : nil
        )
        dismiss()
    }
}
