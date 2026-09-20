import SwiftUI

/// El detalle de una liga contra otros (§36.16): clasificación, calendario por rondas y
/// el formulario para apuntar el resultado de tus partidos.
///
/// Recordatorio, porque el nombre se presta: esto no tiene nada que ver con la "Liga
/// Personal" del móvil (ver la cabecera de `CompeticionModel.swift`). Aquí los números
/// los mueven también los demás, así que la pantalla se recarga del servidor cada vez
/// que se abre y después de cada acción — no hay estado que conservar entre visitas.
struct LigaCompeticionView: View {
    @EnvironmentObject private var competicion: CompeticionModel

    let ligaId: Int
    /// El nombre que ya se sabía al navegar, para pintar el título antes de que conteste
    /// el servidor. Vacío cuando se ha entrado por número.
    var nombreConocido: String = ""

    @State private var detalle: DetalleDeLiga?
    @State private var cargando = true
    @State private var pidiendoPareja = false
    @State private var pareja = ""
    @State private var trabajando = false
    @State private var apuntando: PartidoDeLiga?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let detalle {
                    cabecera(detalle)
                    acciones(detalle)
                    clasificacion(detalle)
                    calendario(detalle)
                } else if cargando {
                    ProgressView().padding(.top, 40)
                } else {
                    Text("No se pudo abrir esta liga. Comprueba el número y que sigues "
                         + "teniendo conexión.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(T.fondo)
        .navigationTitle(detalle?.liga.nombre ?? nombreConocido)
        .navigationBarTitleDisplayMode(.inline)
        .task { await cargar() }
        .refreshable { await cargar() }
        .alert("Con quién juegas", isPresented: $pidiendoPareja) {
            TextField("Alias de tu compañero", text: $pareja)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancelar", role: .cancel) { pareja = "" }
            Button("Inscribirnos") { inscribirme(pareja: pareja) }
        } message: {
            Text("En una liga de parejas os inscribís los dos a la vez. Tiene que tener "
                 + "cuenta en la comunidad.")
        }
        .sheet(item: $apuntando) { partido in
            ApuntarResultadoView(
                competicion: competicion, ligaId: ligaId, partido: partido
            ) {
                Task { await cargar() }
            }
        }
    }

    private func cargar() async {
        cargando = true
        detalle = await competicion.liga(ligaId)
        cargando = false
    }

    // MARK: Cabecera y acciones

    private func cabecera(_ detalle: DetalleDeLiga) -> some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(detalle.liga.nombre)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(T.tinta)
                        Text(subtitulo(detalle.liga))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                    Spacer(minLength: 4)
                    EstadoDeCompeticion(estado: detalle.liga.estado)
                }
                // El número es la invitación: sin directorio público, es lo único que
                // hace falta pasar para que alguien se apunte.
                Text("Liga nº \(detalle.liga.id) · pasa el número a quien quieras dentro")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private func subtitulo(_ liga: FichaDeLiga) -> String {
        let fechas = CompeticionTextos.fechas(desde: liga.desde, hasta: liga.hasta)
        let formato = CompeticionTextos.formato(liga.formato)
        let papel = liga.soyOrganizador ? "Organizas tú" : ""
        return [formato, fechas, papel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func acciones(_ detalle: DetalleDeLiga) -> some View {
        let inscrito = detalle.inscripciones.contains { competicion.participo(en: $0.nombre) }

        if detalle.liga.estaAbierta {
            PadelCard(title: "Antes de empezar", icon: "person.badge.plus") {
                VStack(alignment: .leading, spacing: 10) {
                    if inscrito {
                        Text("Ya estás dentro. Faltan los demás: sois "
                             + "\(detalle.inscripciones.count) por ahora.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button {
                            if detalle.liga.esDeParejas {
                                pidiendoPareja = true
                            } else {
                                inscribirme(pareja: nil)
                            }
                        } label: {
                            Text("Inscribirme")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trabajando)
                    }

                    if detalle.liga.soyOrganizador {
                        Divider()
                        Button {
                            generar()
                        } label: {
                            Text("Generar el calendario y empezar")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(T.lima)
                        .disabled(trabajando || detalle.inscripciones.count < 2)
                        // Se avisa antes y no después: generar el calendario cierra las
                        // inscripciones para siempre, y eso no se deshace desde la app.
                        Text(detalle.inscripciones.count < 2
                             ? "Hacen falta al menos dos inscripciones."
                             : "Al generarlo se reparten todos los partidos y la liga "
                               + "deja de admitir gente. No tiene vuelta atrás.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func inscribirme(pareja alias: String?) {
        trabajando = true
        Task {
            let limpio = alias?.trimmingCharacters(in: .whitespaces).lowercased()
            if await competicion.inscribirme(liga: ligaId, pareja: limpio) {
                pareja = ""
                await cargar()
            }
            trabajando = false
        }
    }

    private func generar() {
        trabajando = true
        Task {
            if await competicion.generarCalendario(liga: ligaId) {
                await cargar()
            }
            trabajando = false
        }
    }

    // MARK: Clasificación

    private func clasificacion(_ detalle: DetalleDeLiga) -> some View {
        PadelCard(title: "Clasificación", icon: "list.number") {
            VStack(spacing: 6) {
                encabezadoDeTabla
                ForEach(detalle.clasificacion) { fila in
                    filaDeClasificacion(fila)
                }
                if detalle.clasificacion.isEmpty {
                    Text("Todavía no hay nadie inscrito.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if detalle.clasificacion.allSatisfy({ $0.jugados == 0 }) {
                    // Sin partidos jugados la tabla es un empate a cero y el orden que
                    // se ve es alfabético: decirlo evita que parezca un ranking.
                    Text("Nadie ha jugado aún: la tabla se mueve con el primer resultado.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Un partido ganado, un punto. Se desempata por diferencia de "
                         + "juegos.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var encabezadoDeTabla: some View {
        HStack(spacing: 6) {
            Text("#")
                .frame(width: 18, alignment: .leading)
            Text("Jugador")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PJ").frame(width: 22, alignment: .trailing)
            Text("G").frame(width: 20, alignment: .trailing)
            Text("±").frame(width: 32, alignment: .trailing)
            Text("PT").frame(width: 24, alignment: .trailing)
        }
        .font(.system(size: 9.5, weight: .bold, design: .rounded))
        .kerning(0.8)
        .foregroundStyle(T.tintaSuave)
    }

    private func filaDeClasificacion(_ fila: FilaDeClasificacion) -> some View {
        let mia = competicion.participo(en: fila.nombre)
        return HStack(spacing: 6) {
            Text("\(fila.puesto)")
                .foregroundStyle(fila.puesto <= 3 ? T.lima : T.tintaSuave)
                .frame(width: 18, alignment: .leading)
            Text(fila.nombre)
                .foregroundStyle(T.tinta)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(fila.jugados)")
                .foregroundStyle(T.tintaSuave)
                .frame(width: 22, alignment: .trailing)
            Text("\(fila.ganados)")
                .foregroundStyle(T.tintaSuave)
                .frame(width: 20, alignment: .trailing)
            Text(fila.diferencia > 0 ? "+\(fila.diferencia)" : "\(fila.diferencia)")
                .foregroundStyle(colorDeDiferencia(fila.diferencia))
                .frame(width: 32, alignment: .trailing)
            Text("\(fila.puntos)")
                .foregroundStyle(T.tinta)
                .fontWeight(.heavy)
                .frame(width: 24, alignment: .trailing)
        }
        .font(.system(size: 13, weight: mia ? .heavy : .medium, design: .rounded))
        .monospacedDigit()
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(mia ? T.limaTinte : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func colorDeDiferencia(_ diferencia: Int) -> Color {
        if diferencia > 0 { return T.verde }
        if diferencia < 0 { return T.rojo }
        return T.tintaSuave
    }

    // MARK: Calendario

    @ViewBuilder
    private func calendario(_ detalle: DetalleDeLiga) -> some View {
        if detalle.calendario.isEmpty {
            PadelCard(title: "Calendario", icon: "calendar") {
                Text(detalle.liga.soyOrganizador
                     ? "Aún no hay calendario. Cuando estéis todos, genéralo arriba."
                     : "Aún no hay calendario: lo genera quien organiza la liga cuando "
                       + "se cierran las inscripciones.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ForEach(rondas(detalle.calendario), id: \.ronda) { grupo in
                PadelCard(title: "Ronda \(grupo.ronda)", icon: "calendar") {
                    VStack(spacing: 8) {
                        ForEach(grupo.partidos) { partido in
                            filaDePartido(partido)
                        }
                    }
                }
            }
        }
    }

    /// Los partidos agrupados por ronda y en orden. `Dictionary(grouping:)` no conserva
    /// ninguno, así que se ordena a mano antes de pintar.
    private func rondas(_ partidos: [PartidoDeLiga]) -> [GrupoDeRonda] {
        Dictionary(grouping: partidos, by: { $0.ronda })
            .map { GrupoDeRonda(ronda: $0.key, partidos: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.ronda < $1.ronda }
    }

    @ViewBuilder
    private func filaDePartido(_ partido: PartidoDeLiga) -> some View {
        let mio = competicion.esMio(partido)
        let apuntable = mio && !partido.jugado

        Button {
            if apuntable { apuntando = partido }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    Text(partido.local)
                        .font(.system(size: 13,
                                      weight: competicion.participo(en: partido.local)
                                          ? .heavy : .medium,
                                      design: .rounded))
                        .foregroundStyle(T.tinta)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(partido.marcador)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(partido.jugado ? T.tinta : T.tintaSuave)
                        .frame(width: 52)

                    Text(partido.visitante)
                        .font(.system(size: 13,
                                      weight: competicion.participo(en: partido.visitante)
                                          ? .heavy : .medium,
                                      design: .rounded))
                        .foregroundStyle(T.tinta)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if apuntable {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 10, weight: .bold))
                        Text("Apuntar el resultado")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(T.pista)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let fecha = partido.fecha, !fecha.isEmpty, partido.jugado {
                    Text(CompeticionTextos.corta(fecha))
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(mio ? T.pistaTinte : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!apuntable)
    }
}

/// Una ronda con sus partidos. Existe para poder recorrer el calendario agrupado con un
/// `ForEach` con identidad estable, que con una tupla no se puede.
struct GrupoDeRonda: Identifiable {
    let ronda: Int
    let partidos: [PartidoDeLiga]
    var id: Int { ronda }
}

// MARK: Apuntar el resultado

/// El formulario de resultado de un partido propio.
///
/// Se piden **juegos**, no sets, porque es lo que el servidor guarda y con lo que
/// desempata la clasificación. El botón de guardar está apagado mientras los dos números
/// sean iguales: en pádel no se empata, y el servidor rechazaría el envío de todas formas
/// — mejor decirlo antes de gastar el viaje.
struct ApuntarResultadoView: View {
    @ObservedObject var competicion: CompeticionModel
    let ligaId: Int
    let partido: PartidoDeLiga
    let alApuntar: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var juegosLocal = 0
    @State private var juegosVisitante = 0
    @State private var fecha = Date()
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $juegosLocal, in: 0...30) {
                        marcadorFila(nombre: partido.local, juegos: juegosLocal)
                    }
                    Stepper(value: $juegosVisitante, in: 0...30) {
                        marcadorFila(nombre: partido.visitante, juegos: juegosVisitante)
                    }
                } header: {
                    Text("Juegos de la ronda \(partido.ronda)")
                } footer: {
                    Text(juegosLocal == juegosVisitante
                         ? "Un partido de pádel no acaba en empate."
                         : "Juegos del partido entero, sumando los sets: 6-4 y 6-3 son "
                           + "12-7.")
                }

                Section {
                    DatePicker("Cuándo se jugó", selection: $fecha,
                               displayedComponents: .date)
                }
            }
            .scrollContentBackground(.hidden)
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle("Resultado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guardar()
                    } label: {
                        if guardando {
                            ProgressView()
                        } else {
                            Text("Guardar").fontWeight(.bold)
                        }
                    }
                    .disabled(guardando || juegosLocal == juegosVisitante)
                }
            }
        }
    }

    private func marcadorFila(nombre: String, juegos: Int) -> some View {
        HStack {
            Text(nombre)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Text("\(juegos)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(T.tinta)
        }
    }

    private func guardar() {
        guardando = true
        Task {
            let hecho = await competicion.apuntarResultado(
                liga: ligaId,
                partido: partido.id,
                juegosLocal: juegosLocal,
                juegosVisitante: juegosVisitante,
                fecha: LigaFechas.iso(fecha)
            )
            guardando = false
            guard hecho else { return }
            dismiss()
            alApuntar()
        }
    }
}
