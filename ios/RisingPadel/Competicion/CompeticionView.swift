import SwiftUI

/// La portada de la competición (§36.14): mis ligas y mis clubes.
///
/// Ojo con el nombre: esto **no** es la "Liga Personal" de la pestaña Partidos. Aquella
/// es el jugador contra sí mismo y vive en el móvil; esta es contra otros y vive en el
/// servidor. La explicación larga está en la cabecera de `CompeticionModel.swift`.
///
/// La vista es dueña de su modelo (`@StateObject`): la competición no la necesita nadie
/// más de la app, y colgarla del árbol entero obligaría a pedirle datos al servidor a
/// quien solo quiere ver sus golpeos.
struct CompeticionView: View {
    @StateObject private var competicion = CompeticionModel()

    /// Pila de navegación explícita porque hay empujes que no salen de un toque en una
    /// fila: crear una liga lleva a su liga, y "abrir por número" también.
    @State private var ruta: [DestinoDeCompeticion] = []
    @State private var creandoLiga = false
    @State private var creandoClub = false
    @State private var abriendoLiga = false
    @State private var abriendoClub = false

    var body: some View {
        NavigationStack(path: $ruta) {
            Group {
                if competicion.tieneCuenta {
                    contenido
                } else {
                    sinCuenta
                }
            }
            .background(T.fondo)
            .navigationTitle("Competición")
            .navigationDestination(for: DestinoDeCompeticion.self) { destino in
                switch destino {
                case .liga(let id, let nombre):
                    LigaCompeticionView(ligaId: id, nombreConocido: nombre)
                        .environmentObject(competicion)
                case .club(let id, let nombre):
                    ClubView(clubId: id, nombreConocido: nombre)
                        .environmentObject(competicion)
                }
            }
            .toolbar {
                if competicion.tieneCuenta {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                creandoLiga = true
                            } label: {
                                Label("Crear una liga", systemImage: "trophy")
                            }
                            Button {
                                creandoClub = true
                            } label: {
                                Label("Crear un club", systemImage: "building.2")
                            }
                            Divider()
                            Button {
                                abriendoLiga = true
                            } label: {
                                Label("Abrir una liga por su número", systemImage: "number")
                            }
                            Button {
                                abriendoClub = true
                            } label: {
                                Label("Abrir un club por su número", systemImage: "number")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Crear o abrir")
                    }
                }
            }
            .sheet(isPresented: $creandoLiga) {
                CrearLigaView(competicion: competicion) { id, nombre in
                    ruta.append(.liga(id, nombre))
                }
            }
            .sheet(isPresented: $creandoClub) {
                CrearClubView(competicion: competicion) { id, nombre in
                    ruta.append(.club(id, nombre))
                }
            }
            .sheet(isPresented: $abriendoLiga) {
                AbrirPorNumeroView(
                    titulo: "Abrir una liga",
                    explicacion: "El número de la liga te lo pasa quien la organiza. "
                        + "Dentro podrás inscribirte si sigue abierta."
                ) { id in
                    ruta.append(.liga(id, ""))
                }
            }
            .sheet(isPresented: $abriendoClub) {
                AbrirPorNumeroView(
                    titulo: "Abrir un club",
                    explicacion: "El número del club te lo pasa alguien de dentro. "
                        + "Desde su panel puedes unirte."
                ) { id in
                    ruta.append(.club(id, ""))
                }
            }
            .alert(
                competicion.mensaje ?? "",
                isPresented: Binding(
                    get: { competicion.mensaje != nil },
                    set: { if !$0 { competicion.mensaje = nil } }
                )
            ) {
                Button("Vale", role: .cancel) { competicion.mensaje = nil }
            }
            .task { await competicion.refrescar() }
            .refreshable { await competicion.refrescar() }
        }
        .tint(T.pista)
    }

    // MARK: Las dos secciones

    private var contenido: some View {
        ScrollView {
            VStack(spacing: 12) {
                seccionLigas
                seccionClubes
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var seccionLigas: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Mis ligas", icon: "trophy.fill")
            if competicion.ligas.isEmpty {
                PadelCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Todavía no compites contra nadie")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(T.tinta)
                        Text("Crea una liga con el + de arriba y pásale su número a tu "
                             + "grupo, o abre la que te hayan pasado a ti. Esto es "
                             + "aparte de tu Liga Personal: aquí hay clasificación.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(competicion.ligas) { liga in
                NavigationLink(value: DestinoDeCompeticion.liga(liga.id, liga.nombre)) {
                    filaDeLiga(liga)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filaDeLiga(_ liga: LigaResumida) -> some View {
        PadelCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(liga.nombre)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(T.tinta)
                        .lineLimit(1)
                    Text(detalleDeLiga(liga))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                EstadoDeCompeticion(estado: liga.estado)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    private func detalleDeLiga(_ liga: LigaResumida) -> String {
        let fechas = CompeticionTextos.fechas(desde: liga.desde, hasta: liga.hasta)
        let formato = CompeticionTextos.formato(liga.formato)
        return fechas.isEmpty ? formato : "\(formato) · \(fechas)"
    }

    private var seccionClubes: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Mis clubes", icon: "building.2.fill")
            if competicion.clubes.isEmpty {
                PadelCard {
                    Text("Un club agrupa a tu gente y a sus ligas. Crea el tuyo con el + "
                         + "de arriba: quien lo crea se queda de administrador.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(competicion.clubes) { club in
                NavigationLink(value: DestinoDeCompeticion.club(club.id, club.nombre)) {
                    filaDeClub(club)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filaDeClub(_ club: ClubResumido) -> some View {
        PadelCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(club.nombre)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(T.tinta)
                        .lineLimit(1)
                    Text(
                        [club.ciudad ?? "", CompeticionTextos.papel(club.papel)]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    /// Sin cuenta no hay competición, y el alta no se duplica aquí: la puerta sigue
    /// siendo Comunidad, que es donde ya se explica qué es un alias y para qué sirve.
    private var sinCuenta: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "trophy")
                    .font(.system(size: 40))
                    .foregroundStyle(T.pista)
                    .padding(.top, 24)
                Text("Compite contra los tuyos")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(T.tinta)
                PadelCard {
                    Text("Ligas de verdad contra otra gente: te inscribes, sale el "
                         + "calendario de todos contra todos y hay una clasificación que "
                         + "se mueve con cada resultado.\n\nHace falta la cuenta de la "
                         + "comunidad, que es la misma que usas para el muro y el "
                         + "marcador en vivo. Créala en Comunidad y vuelve.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }
}

/// A dónde se navega dentro de la competición. Lleva el nombre además del id para poder
/// pintar el título de la pantalla antes de que conteste el servidor — una cabecera
/// vacía durante un segundo parece una pantalla rota.
enum DestinoDeCompeticion: Hashable {
    case liga(Int, String)
    case club(Int, String)
}

/// Distintivo de estado de una liga. Reutiliza `OutcomeBadge`, que ya es exactamente
/// esto: una cápsula de color con una palabra en mayúsculas.
struct EstadoDeCompeticion: View {
    let estado: String

    var body: some View {
        OutcomeBadge(
            text: CompeticionTextos.estado(estado),
            color: CompeticionTextos.colorDeEstado(estado)
        )
    }
}

// MARK: Altas

struct CrearLigaView: View {
    @ObservedObject var competicion: CompeticionModel
    let alCrear: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nombre = ""
    @State private var formato = "parejas"
    /// 0 = sin club. Una liga suelta entre amigos es el caso normal; el club es lo raro.
    @State private var club = 0
    @State private var conFechas = false
    @State private var desde = Date()
    @State private var hasta = Date().addingTimeInterval(60 * 60 * 24 * 60)
    @State private var creando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre de la liga", text: $nombre)
                    Picker("Formato", selection: $formato) {
                        Text("Parejas").tag("parejas")
                        Text("Individual").tag("individual")
                    }
                } footer: {
                    Text("En parejas cada inscripción son dos personas y hay que decir "
                         + "con quién juegas. El formato no se puede cambiar después.")
                }

                if !competicion.clubes.isEmpty {
                    Section {
                        Picker("Club", selection: $club) {
                            Text("Sin club").tag(0)
                            ForEach(competicion.clubes) { candidato in
                                Text(candidato.nombre).tag(candidato.id)
                            }
                        }
                    } footer: {
                        Text("Si la cuelgas de un club, aparecerá en su panel.")
                    }
                }

                Section {
                    Toggle("Tiene fechas", isOn: $conFechas)
                    if conFechas {
                        DatePicker("Desde", selection: $desde, displayedComponents: .date)
                        DatePicker("Hasta", selection: $hasta, displayedComponents: .date)
                    }
                } footer: {
                    Text("Las fechas son informativas: el calendario no las reparte por "
                         + "días, solo ordena las rondas.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle("Nueva liga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        crear()
                    } label: {
                        if creando { ProgressView() } else { Text("Crear").fontWeight(.bold) }
                    }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || creando)
                }
            }
        }
    }

    private func crear() {
        creando = true
        let limpio = nombre.trimmingCharacters(in: .whitespaces)
        Task {
            let id = await competicion.crearLiga(
                nombre: limpio,
                formato: formato,
                club: club == 0 ? nil : club,
                desde: conFechas ? LigaFechas.iso(desde) : nil,
                hasta: conFechas ? LigaFechas.iso(hasta) : nil
            )
            creando = false
            guard let id else { return }
            dismiss()
            alCrear(id, limpio)
        }
    }
}

struct CrearClubView: View {
    @ObservedObject var competicion: CompeticionModel
    let alCrear: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nombre = ""
    @State private var ciudad = ""
    @State private var creando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre del club", text: $nombre)
                    TextField("Ciudad", text: $ciudad)
                } footer: {
                    Text("Quien crea el club se queda de administrador. Para que entre "
                         + "alguien, pásale el número del club.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle("Nuevo club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        crear()
                    } label: {
                        if creando { ProgressView() } else { Text("Crear").fontWeight(.bold) }
                    }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || creando)
                }
            }
        }
    }

    private func crear() {
        creando = true
        let limpio = nombre.trimmingCharacters(in: .whitespaces)
        Task {
            let id = await competicion.crearClub(
                nombre: limpio,
                ciudad: ciudad.trimmingCharacters(in: .whitespaces)
            )
            creando = false
            guard let id else { return }
            dismiss()
            alCrear(id, limpio)
        }
    }
}

/// Abrir una liga o un club del que solo se sabe el número.
///
/// Existe porque el servidor solo sabe listar *lo mío*: no hay directorio público de
/// clubes ni de ligas. Mientras no lo haya, el número es la invitación — quien organiza
/// lo pasa por el grupo y con esto se entra.
struct AbrirPorNumeroView: View {
    let titulo: String
    let explicacion: String
    let alAbrir: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var numero = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Número", text: $numero)
                        .keyboardType(.numberPad)
                } footer: {
                    Text(explicacion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(T.fondo)
            .tint(T.pista)
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Abrir") {
                        guard let id = Int(numero.trimmingCharacters(in: .whitespaces)) else {
                            return
                        }
                        dismiss()
                        alAbrir(id)
                    }
                    .fontWeight(.bold)
                    .disabled(Int(numero.trimmingCharacters(in: .whitespaces)) == nil)
                }
            }
        }
    }
}
