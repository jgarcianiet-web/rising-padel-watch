import PadelCore
import PhotosUI
import SwiftUI

/// Importar un partido que se jugó **sin nuestro reloj**: las capturas de la app de la
/// pulsera, más el pulso que haya en Apple Salud.
///
/// ## Varias capturas a la vez, porque un partido no cabe en una pantalla
///
/// La app de la pulsera reparte el resumen en siete u ocho pantallas: la actividad, el
/// volumen, el radar de calidad y una por cada golpe. Pedirlas de una en una obligaba a
/// entrar y salir ocho veces para un solo partido. Se eligen todas de golpe y se leen
/// seguidas, **fundiéndose en el mismo partido**.
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
/// la que se leyó —y con varias pantallas eso pasa a importar más, porque un dato puede
/// venir de cualquiera de ellas—, en un campo que se puede corregir, y nada entra en la
/// liga hasta que se pulsa Guardar. Un número mal leído es peor que un hueco: entra con la misma pinta que
/// uno medido y nadie lo cuestiona meses después. Ver `LecturaDeCaptura`.
///
/// Las capturas no se guardan en ningún sitio: se leen en el dispositivo, se saca el
/// texto y las imágenes se sueltan.
struct ImportarCapturaView: View {
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var salud = SaludDelIPhone()

    @State private var elegidas: [PhotosPickerItem] = []
    @State private var imagenes: [UIImage] = []
    /// Cuántas capturas se han leído ya. Con varias, "leída" deja de ser un sí o un no.
    @State private var leidas = 0
    /// De qué texto salió cada campo, por campo.
    ///
    /// Con una sola captura bastaba con guardar la última lectura y preguntarle. Con
    /// varias no: el nivel puede venir de la pantalla de actividad y las calorías de
    /// otra, así que el origen hay que apuntarlo en el momento de rellenar cada campo o
    /// se pierde cuál fue.
    @State private var origenes: [String: String] = [:]
    /// Lo que no se entendió, de todas las capturas juntas.
    @State private var sinEntender: [String] = []
    @State private var leyendo = false
    @State private var progreso = ""
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
                if leidas > 0 {
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
            .onChange(of: elegidas) { _, nuevas in
                guard !nuevas.isEmpty else { return }
                Task { await cargar(nuevas) }
            }
        }
    }

    // MARK: La captura

    private var capturaSection: some View {
        Section {
            // `maxSelectionCount` sin poner significa sin límite, y aquí es lo que
            // interesa: el resumen de la pulsera ocupa las pantallas que ocupe y no me
            // toca a mí decidir que son ocho.
            PhotosPicker(selection: $elegidas, matching: .images) {
                Label(
                    elegidas.isEmpty
                        ? "Elegir capturas de la pulsera"
                        : "Cambiar las capturas (\(elegidas.count))",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
            if !imagenes.isEmpty {
                // En tira y pequeñas: con ocho pantallas, enseñarlas a tamaño grande
                // dejaba los campos a un scroll de distancia. Lo que importa mirar son
                // los números, no las capturas.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imagenes.indices, id: \.self) { indice in
                            Image(uiImage: imagenes[indice])
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if leyendo {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(progreso).font(.caption)
                }
            }
            if leidas > 0, !leyendo {
                Text(leidas == 1
                     ? "1 captura leída."
                     : "\(leidas) capturas leídas y fundidas en el mismo partido.")
                    .font(.caption)
                    .foregroundStyle(T.tintaSuave)
            }
            if let aviso {
                Text(aviso)
                    .font(.caption)
                    .foregroundStyle(T.rojo)
            }
            if !sinEntender.isEmpty {
                // Lo que no se entendió, por si falta un dato que el jugador sí ve en su
                // captura: sin esto, el dato desaparecido no tiene explicación.
                DisclosureGroup("Líneas que no se entendieron (\(sinEntender.count))") {
                    ForEach(sinEntender, id: \.self) { linea in
                        Text(linea)
                            .font(.caption2)
                            .foregroundStyle(T.tintaSuave)
                    }
                }
            }
        } header: {
            Text("Las capturas")
        } footer: {
            Text("Elige de una vez todas las pantallas del partido —actividad, volumen, "
                 + "calidad y las de cada golpe—: se leen seguidas y se juntan en un solo "
                 + "partido. Se leen en el móvil y no salen de aquí: se saca el texto y "
                 + "las imágenes se sueltan. Lo que se guarda son los números que "
                 + "confirmes abajo.")
        }
    }

    // MARK: Los números

    private var datosSection: some View {
        Section {
            DatePicker("Día del partido", selection: $fecha, displayedComponents: .date)
            campo("Nivel de la sesión", texto: $nivel, pista: "3,5", origen: origenes["nivel"])
            campo("Golpes totales", texto: $totalGolpes, pista: "284", origen: origenes["total"])
            campo("Duración (min)", texto: $duracion, pista: "90", origen: origenes["duracion"])
            campo("Calidad media del jugador", texto: $mediaJugador, pista: "3,45",
                  origen: origenes["media"])
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
                Text("Las capturas no traían golpes por tipo. Están en las pantallas de "
                     + "cada golpe y en la de volumen: elígelas también en el selector de "
                     + "arriba y se añaden a este mismo partido.")
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
                        if duplicaSusLados(golpe) {
                            Text("sus dos lados ya están en la lista: esto los cuenta "
                                 + "otra vez. Deslízalo a la izquierda para quitarlo.")
                                .font(.caption2)
                                .foregroundStyle(T.rojo)
                        }
                    }
                }
                .onDelete { indices in golpes.remove(atOffsets: indices) }
            } header: {
                Text("Golpes (nota y cantidad)")
            } footer: {
                Text("Desliza a la izquierda para quitar un golpe que no quieras guardar.")
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
            campo("Pulso medio", texto: $pulsoMedio, pista: "138", origen: origenes["pulsoMedio"])
            campo("Pulso máximo", texto: $pulsoMax, pista: "176", origen: origenes["pulsoMax"])
            campo("Calorías", texto: $calorias, pista: "898", origen: origenes["calorias"])
            campo("Pasos", texto: $pasos, pista: "8861", origen: origenes["pasos"])

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
        func poner(_ clave: String, _ campo: inout String, _ valor: Int?) {
            guard campo.isEmpty, let valor else { return }
            campo = String(valor)
            origenes[clave] = "Apple Salud · \(entreno.origen)"
        }
        poner("pulsoMedio", &pulsoMedio, entreno.pulsoMedio)
        poner("pulsoMax", &pulsoMax, entreno.pulsoMax)
        poner("duracion", &duracion, entreno.duracionMin)
        poner("calorias", &calorias, entreno.calorias)
        poner("pasos", &pasos, entreno.pasos)
    }

    // MARK: Cargar y guardar

    /// Lee las capturas elegidas **una detrás de otra**, fundiendo cada una en los mismos
    /// campos.
    ///
    /// Seguidas y no en paralelo a propósito. El orden importa: `volcar` solo rellena lo
    /// que está vacío, así que la primera captura que traiga un dato es la que lo pone, y
    /// con lecturas simultáneas eso dependería de cuál acabara antes — el mismo partido
    /// daría números distintos en cada importación. Leídas en fila, gana la captura que el
    /// jugador puso primero y el resultado es siempre el mismo.
    ///
    /// Reelegir no borra lo tecleado: la selección nueva se vuelve a leer completa y lo
    /// corregido a mano sigue mandando, porque sigue sin estar vacío.
    private func cargar(_ items: [PhotosPickerItem]) async {
        leyendo = true
        aviso = nil
        sinEntender = []
        defer {
            leyendo = false
            progreso = ""
        }

        var fotos: [UIImage] = []
        var leidasAhora = 0
        var ilegibles = 0
        var vacias = 0

        for (indice, item) in items.enumerated() {
            progreso = items.count == 1
                ? "Leyendo la captura…"
                : "Leyendo la captura \(indice + 1) de \(items.count)…"
            guard let datos = try? await item.loadTransferable(type: Data.self),
                  let foto = UIImage(data: datos) else {
                ilegibles += 1
                continue
            }
            fotos.append(foto)
            do {
                let resultado = try await LectorDeCapturas.leer(foto)
                volcar(resultado)
                leidasAhora += 1
                if resultado.vacia { vacias += 1 }
            } catch {
                ilegibles += 1
            }
        }

        imagenes = fotos
        leidas = leidasAhora
        aviso = parteDeLectura(total: items.count, ilegibles: ilegibles, vacias: vacias)
    }

    /// Qué contar de la tanda. Con varias capturas, "ha fallado" ya no vale: hay que decir
    /// cuántas y de qué manera, o el jugador no sabe si le falta un dato o le falta una
    /// pantalla.
    private func parteDeLectura(total: Int, ilegibles: Int, vacias: Int) -> String? {
        if ilegibles == total {
            return total == 1
                ? "Esa imagen no se pudo leer."
                : "Ninguna de las \(total) imágenes se pudo leer."
        }
        var partes: [String] = []
        if ilegibles > 0 {
            partes.append(ilegibles == 1
                          ? "1 imagen no se pudo leer."
                          : "\(ilegibles) imágenes no se pudieron leer.")
        }
        if vacias > 0 {
            partes.append(vacias == 1
                          ? "En 1 captura no se reconoció ningún número."
                          : "En \(vacias) capturas no se reconoció ningún número.")
        }
        if partes.isEmpty { return nil }
        partes.append("Lo que falte, escríbelo a mano abajo.")
        return partes.joined(separator: " ")
    }

    /// Pasa lo leído a los campos editables. **Solo lo que esté vacío**: si el jugador ya
    /// corrigió algo y luego importa una segunda captura del mismo partido, su corrección
    /// manda sobre la lectura nueva.
    private func volcar(_ resultado: LecturaDeCaptura.CapturaLeida) {
        // El origen se apunta **aquí**, al rellenar. Con una sola captura bastaba con
        // preguntárselo luego a la lectura; con ocho, la lectura que tienes en la mano no
        // es la que puso el dato, y la etiqueta "leído de" acabaría señalando a la línea
        // de otra pantalla. Y una procedencia equivocada es peor que ninguna: es lo único
        // con lo que el jugador puede comprobar si el número se leyó bien.
        func poner(
            _ clave: String, _ campo: inout String, _ dato: LecturaDeCaptura.Dato?, entero: Bool
        ) {
            guard campo.isEmpty, let dato else { return }
            campo = entero ? String(Int(dato.valor.rounded())) : textoDe(dato.valor)
            origenes[clave] = dato.origen
        }
        poner("nivel", &nivel, resultado.nivelSesion, entero: false)
        poner("total", &totalGolpes, resultado.totalGolpes, entero: true)
        poner("duracion", &duracion, resultado.duracionMin, entero: true)
        poner("pulsoMedio", &pulsoMedio, resultado.pulsoMedio, entero: true)
        poner("pulsoMax", &pulsoMax, resultado.pulsoMax, entero: true)
        poner("calorias", &calorias, resultado.calorias, entero: true)
        poner("pasos", &pasos, resultado.pasos, entero: true)
        poner("media", &mediaJugador, resultado.mediaDelJugador, entero: false)
        if mejorGolpe.isEmpty, let mejor = resultado.mejorGolpe { mejorGolpe = mejor }

        for linea in resultado.sinEntender where !sinEntender.contains(linea) {
            sinEntender.append(linea)
        }

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

    /// ¿Este golpe sin lado ya está contado por sus dos mitades?
    ///
    /// Al importar todas las pantallas de golpe aparece solo: la de volumen da "Volea
    /// 175" y las de detalle dan "Volea de revés 74" y "Volea de derecha 101". Los tres
    /// son lecturas buenas y los tres entran, porque el nombre es distinto — pero juntos
    /// cuentan 350 voleas donde hubo 175.
    ///
    /// No se quita solo: con una sola pantalla de las dos, el agregado es el único dato
    /// que hay, y descartarlo por su cuenta borraría un número que el jugador sí tiene.
    /// Se marca, y lo quita quien sabe cuál de los dos quiere.
    private func duplicaSusLados(_ golpe: GolpeEditable) -> Bool {
        guard golpe.golpe == nil else { return false }
        let raiz = golpe.nombre.lowercased() + " "
        for otro in golpes where otro.golpe != nil {
            if otro.nombre.lowercased().hasPrefix(raiz) { return true }
        }
        return false
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
