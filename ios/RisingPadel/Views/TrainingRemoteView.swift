import PadelCore
import SwiftUI

/// El mando de tandas: se lleva el reloj otra persona y tú diriges desde el móvil.
///
/// Nace de cómo se graban las tandas de verdad. El que apunta los datos casi nunca es el
/// que pega: le pones el reloj a alguien, te quedas fuera de la pista y le vas cantando
/// "treinta derechas", "ahora bandejas". Con los botones solo en la muñeca hay que parar
/// el ejercicio, acercarse, quitarle el reloj y cambiar el tipo entre tanda y tanda — y
/// eso se traduce en menos tandas grabadas, que es justo lo que peor le viene al detector.
struct TrainingRemoteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// Tipo que se va a grabar en la siguiente tanda. Arranca en el que tenga el reloj.
    @State private var etiqueta: ShotType = .forehand
    @State private var latido: Timer?

    /// Los tipos que tiene sentido pedirle a alguien. `unknown` no se graba a propósito:
    /// no es un golpe, es la ausencia de clasificación.
    private var grabables: [ShotType] { ShotType.allCases.filter { $0 != .unknown } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    conexionBanner
                    // Los controles están siempre, conteste el reloj o no. Antes, sin
                    // respuesta no había pantalla, y como mirar el móvil apaga la
                    // pantalla del reloj, eso pasaba casi siempre: el mando se quedaba
                    // en un "no se puede conectar" del que no se salía.
                    estadoCard(model.estadoTanda)
                    quienCard
                    ayudaCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(T.fondo)
            .scrollContentBackground(.hidden)
            .navigationTitle("Mando de tandas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onAppear {
            model.ordenarTanda(.estado)
            // Un latido corto mientras la pantalla está delante: el contador de golpes es
            // la única forma de saber desde fuera que la tanda va bien. Se para al salir
            // para no estar despertando el reloj en balde.
            latido = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in model.ordenarTanda(.estado) }
            }
        }
        .onDisappear {
            latido?.invalidate()
            latido = nil
        }
        .onChange(of: model.estadoTanda?.etiqueta) { _, nueva in
            // Si el reloj cambia de tipo por su cuenta (alguien tocó su pantalla), el
            // móvil le sigue: manda lo que hay en la muñeca, no lo que el móvil creía.
            if let nueva, !(model.estadoTanda?.grabando ?? false) { etiqueta = nueva }
        }
    }

    // MARK: El mando

    private func estadoCard(_ estado: EstadoDeTanda?) -> some View {
        PadelCard {
            VStack(spacing: 14) {
                // Una orden que no hizo nada tiene que decir por qué: si no, el botón
                // parece roto y lo siguiente es dejar de usar el mando.
                if let motivo = model.avisoTanda {
                    Label(motivo, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.rojo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if estado?.grabando == true {
                    Text("\(estado?.capturadosEnTanda ?? 0)")
                        .font(.padelDisplay(64))
                        .monospacedDigit()
                        .foregroundStyle(T.lima)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: estado?.capturadosEnTanda ?? 0)
                    Text("golpes de \(etiquetaLarga(estado?.etiqueta ?? etiqueta)) en esta tanda")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .multilineTextAlignment(.center)

                    if estado?.sensoresPuedenPararse == true {
                        // Sin permiso de entreno la app se suspende al apagarse la
                        // pantalla y la tanda se queda a medias. Mejor decirlo que
                        // devolver 10 golpes de 50 como si fueran todos.
                        Text("Sin permiso de entreno en el reloj: la tanda puede cortarse al apagarse la pantalla")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(T.rojo)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let descartes = estado?.descartes, descartes.total > 0 {
                        descartesCard(descartes, capturados: estado?.capturadosEnTanda ?? 0)
                    }

                    Button {
                        model.ordenarTanda(.parar)
                    } label: {
                        Label("Parar tanda", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(T.rojo)
                    .controlSize(.large)
                } else {
                    Text("Qué le pides")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Rejilla y no un selector: pulsar el golpe que quieres es un toque,
                    // y desde fuera de la pista no se anda uno abriendo menús.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(grabables, id: \.self) { tipo in
                            Button {
                                etiqueta = tipo
                            } label: {
                                Text(etiquetaLarga(tipo))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        etiqueta == tipo ? T.limaTinte : T.borde.opacity(0.4),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .foregroundStyle(etiqueta == tipo ? T.lima : T.tinta)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        model.ordenarTanda(.iniciar, etiqueta: etiqueta)
                    } label: {
                        Label("Grabar \(etiquetaLarga(etiqueta).lowercased())", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack {
                        Text(estado.map {
                            "\($0.guardadosEnTotal) golpes guardados en el reloj · \($0.kilobytes) KB"
                        } ?? "El reloj todavía no ha dicho qué tiene guardado")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                        Spacer()
                        if (estado?.guardadosEnTotal ?? 0) > 0 {
                            Button("Traer al móvil") { model.ordenarTanda(.enviar) }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        }
    }

    // MARK: Lo que se le escapa

    /// Los swings que el detector vio y tiró, con el motivo.
    ///
    /// Es la mitad que faltaba para poder arreglar el detector. Las tandas solo guardan
    /// lo que sí se detecta, así que un golpe perdido no dejaba rastro en ningún sitio y
    /// solo quedaba adivinar qué umbral bajar. Cada línea apunta a un umbral concreto.
    private func descartesCard(_ d: DescartesDelDetector, capturados: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let vistos = capturados + d.total
            Text("Ha cogido \(capturados) de \(vistos) movimientos")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(capturados * 2 >= vistos ? T.tinta : T.rojo)
            if d.swingSinImpacto > 0 {
                lineaDescarte("\(d.swingSinImpacto) swings sin impacto claro",
                              "el golpe fue demasiado suave para el umbral de impacto")
            }
            if d.impactoConSwingCorto > 0 {
                lineaDescarte("\(d.impactoConSwingCorto) impactos con swing corto",
                              "poco recorrido o poca velocidad de pala")
            }
            if d.amago > 0 {
                lineaDescarte("\(d.amago) amagos", "el brazo se paró sin llegar a golpear")
            }
            if d.enRefractario > 0 {
                lineaDescarte("\(d.enRefractario) demasiado seguidos",
                              "llegaron dentro del tiempo muerto del golpe anterior")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(T.borde.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func lineaDescarte(_ que: String, _ porque: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(que)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(T.tinta)
            Text(porque)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Quién lleva el reloj

    /// Sin esto el mando sería medio inútil: las muestras se guardan con el alias y el
    /// nivel técnico de quien las pegó, y son exactamente los dos datos que hay que
    /// cambiar al pasarle el reloj a otra persona. Enterrados en Ajustes se olvidan, y
    /// una tanda con el nivel de otro contamina la escala en vez de anclarla.
    private var quienCard: some View {
        PadelCard(title: "Quién lleva el reloj", icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nombre")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(T.tinta)
                    Spacer()
                    TextField("alias", text: $model.playerAlias)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 160)
                }

                Picker("Nivel técnico", selection: $model.playerLevelRaw) {
                    Text("Sin declarar").tag(0)
                    ForEach(1...7, id: \.self) { nivel in
                        Text("Nivel \(nivel)").tag(nivel)
                    }
                }
                .pickerStyle(.menu)

                Text(model.playerLevelRaw <= 0
                     ? "Sin nivel declarado esta tanda mide golpes, pero no ancla la escala de nivel."
                     : "Estas tandas se guardarán como nivel \(model.playerLevelRaw), que es lo que ancla la escala.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cómo va la conexión

    /// Un aviso, no una pared. El reloj dormido no impide mandar la orden — solo hace
    /// que tarde en confirmarse.
    @ViewBuilder
    private var conexionBanner: some View {
        switch model.conexionDelMando {
        case .directa:
            EmptyView()
        case .enCola:
            if model.ordenEsperando {
                aviso(
                    icono: "paperplane.fill",
                    color: T.pista,
                    texto: "Orden enviada. El reloj la atenderá en cuanto despierte — "
                        + "levanta la muñeca o abre la app para que sea ahora."
                )
            } else {
                aviso(
                    icono: "clock.arrow.circlepath",
                    color: T.tintaSuave,
                    texto: model.estadoTanda == nil
                        ? "El reloj está dormido. Las órdenes se le mandan igual y las atiende al despertar; para verlo al instante, abre la app en el reloj."
                        : "El reloj está dormido: lo que ves es lo último que dijo. Las órdenes le llegan igual."
                )
            }
        case .imposible:
            aviso(
                icono: "applewatch.slash",
                color: T.rojo,
                texto: "No hay ningún Apple Watch emparejado con la app instalada."
            )
        }
    }

    private func aviso(icono: String, color: Color, texto: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .semibold))
            Text(texto)
                .font(.system(size: 11, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var ayudaCard: some View {
        PadelCard(title: "Cómo sacarle partido", icon: "lightbulb") {
            VStack(alignment: .leading, spacing: 8) {
                linea("1.", "Pon el reloj en la muñeca de quien va a pegar y pon aquí su nombre y su nivel técnico.")
                linea("2.", "Elige el golpe, dale a grabar y que pegue 30-40 seguidos solo de ese tipo.")
                linea("3.", "Para la tanda, cambia de golpe y repite. Cada tipo con al menos una tanda.")
                linea("4.", "Al terminar, en Ajustes → Datos de entrenamiento pulsa «Calibrar con las tandas».")
            }
        }
    }

    private func linea(_ numero: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(numero)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(T.lima)
            Text(texto)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func etiquetaLarga(_ tipo: ShotType) -> String {
        ShotBreakdownChart.etiqueta(tipo)
    }
}
