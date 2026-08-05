import SwiftUI

// Las piezas sociales que no caben en el muro: retos, torneo y perfil público.

/// Retos entre amigos: una métrica del reloj, una ventana de días, y el servidor
/// arbitrando con partidos reales — nadie infla un reto a mano.
struct RetosView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @Environment(\.dismiss) private var dismiss

    @State private var retos: [ComunidadReto] = []
    @State private var alias = ""
    @State private var metrica = "bandeja"
    @State private var dias = 7

    private static let metricas = [
        ("bandeja", "Bandejas"), ("vibora", "Víboras"), ("smash", "Remates"),
        ("golpes", "Golpeos"), ("victorias", "Victorias"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    nuevoReto
                    ForEach(retos) { retoCard($0) }
                    if retos.isEmpty {
                        Text("Reta a alguien: el reloj mide, el servidor arbitra.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("Retos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
            }
            .task { retos = await comunidad.retos() }
        }
    }

    private var nuevoReto: some View {
        PadelCard(title: "Nuevo reto", icon: "bolt.fill") {
            VStack(spacing: 10) {
                TextField("Alias del rival", text: $alias)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Picker("Métrica", selection: $metrica) {
                    ForEach(Self.metricas, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                Stepper("Durante \(dias) días", value: $dias, in: 1...30)
                    .font(.system(size: 13, design: .rounded))
                Button {
                    let rival = alias
                    alias = ""
                    Task {
                        await comunidad.retar(alias: rival, metrica: metrica, dias: dias)
                        retos = await comunidad.retos()
                    }
                } label: {
                    Label("Retar", systemImage: "bolt.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(alias.count < 2)
            }
        }
    }

    private func retoCard(_ reto: ComunidadReto) -> some View {
        let ganaRetador = reto.marcadorRetador >= reto.marcadorRetado
        return PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Más \(reto.metric) · hasta el \(LigaFechas.corta(reto.hasta))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .kerning(1)
                        .foregroundStyle(T.tintaSuave)
                    Spacer()
                    if reto.terminado {
                        OutcomeBadge(text: "final", color: T.tintaSuave)
                    }
                }
                HStack {
                    marcador(reto.retador, reto.marcadorRetador, destacado: ganaRetador)
                    Text("–")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                    marcador(reto.retado, reto.marcadorRetado, destacado: !ganaRetador)
                }
                if reto.terminado {
                    let ganador = reto.marcadorRetador == reto.marcadorRetado
                        ? "Empate"
                        : "Gana @\(ganaRetador ? reto.retador : reto.retado) 🏆"
                    Text(ganador)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(T.verde)
                }
            }
        }
    }

    private func marcador(_ alias: String, _ valor: Int, destacado: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(valor)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(destacado ? T.pista : T.tinta)
            Text("@\(alias)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// El torneo entre amigos: bracket de 2, 4 u 8, cruces que avanzan al reportar.
struct TorneoView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @Environment(\.dismiss) private var dismiss

    @State private var torneo: ComunidadTorneo?
    @State private var nombre = ""
    @State private var jugadores = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let torneo {
                        bracket(torneo)
                    }
                    crearCard
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("Torneo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
            }
            .task { torneo = await comunidad.torneo() }
        }
    }

    private func bracket(_ torneo: ComunidadTorneo) -> some View {
        let rondas = Dictionary(grouping: torneo.cruces, by: \.ronda).sorted { $0.key < $1.key }
        return PadelCard(title: torneo.nombre, icon: "trophy.fill") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rondas, id: \.key) { ronda, cruces in
                    SectionLabel(nombreRonda(ronda, total: rondas.count))
                    ForEach(cruces) { cruceRow($0) }
                }
                if torneo.status == "terminado",
                   let campeon = torneo.cruces.last?.ganador {
                    Text("🏆 Campeón: @\(campeon)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(T.verde)
                }
            }
        }
    }

    private func cruceRow(_ cruce: ComunidadTorneo.Cruce) -> some View {
        HStack(spacing: 8) {
            jugador(cruce.p1, ganador: cruce.ganador)
            Text("vs")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(T.tintaSuave)
            jugador(cruce.p2, ganador: cruce.ganador)
            Spacer()
            // Reportar solo tiene sentido con los dos jugadores puestos y sin ganador.
            if cruce.ganador == nil, let p1 = cruce.p1, let p2 = cruce.p2,
               [p1, p2].contains(comunidad.alias ?? "") {
                Menu {
                    Button("Ganó @\(p1)") { reportar(cruce, p1) }
                    Button("Ganó @\(p2)") { reportar(cruce, p2) }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(T.pista)
                }
            }
        }
    }

    private func jugador(_ alias: String?, ganador: String?) -> some View {
        Text(alias.map { "@\($0)" } ?? "—")
            .font(.system(size: 13, weight: alias != nil && alias == ganador ? .heavy : .medium,
                          design: .rounded))
            .foregroundStyle(alias != nil && alias == ganador ? T.verde : T.tinta)
            .lineLimit(1)
    }

    private func reportar(_ cruce: ComunidadTorneo.Cruce, _ alias: String) {
        Task {
            await comunidad.reportarGanador(cruce: cruce, alias: alias)
            torneo = await comunidad.torneo()
        }
    }

    private func nombreRonda(_ ronda: Int, total: Int) -> String {
        switch total - ronda {
        case 0: return "Final"
        case 1: return "Semifinales"
        default: return "Ronda \(ronda)"
        }
    }

    private var crearCard: some View {
        PadelCard(title: "Nuevo torneo", icon: "plus.circle") {
            VStack(spacing: 10) {
                TextField("Nombre (ej: Liguilla de agosto)", text: $nombre)
                TextField("Rivales por alias, separados por comas", text: $jugadores)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("Tú entras solo. En total tenéis que ser 2, 4 u 8.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Crear torneo") {
                    let lista = jugadores.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }
                    Task {
                        await comunidad.crearTorneo(nombre: nombre, jugadores: lista)
                        torneo = await comunidad.torneo()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(jugadores.isEmpty)
            }
        }
    }
}

/// La ficha pública de un jugador: sus números y el duelo de retos contra ti.
struct PerfilView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @Environment(\.dismiss) private var dismiss
    let alias: String

    @State private var perfil: ComunidadPerfil?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let perfil {
                        PadelCard {
                            HStack(spacing: 8) {
                                StatTile(label: "Partidos", value: "\(perfil.partidos)")
                                StatTile(label: "Victorias", value: "\(perfil.victorias)", tint: T.verde)
                                StatTile(label: "Golpeos", value: "\(perfil.golpeos)", tint: T.pista)
                            }
                        }
                        if perfil.duelo.yo + perfil.duelo.el > 0 {
                            PadelCard(title: "Vuestro duelo de retos", icon: "bolt.fill") {
                                Text("\(perfil.duelo.yo) – \(perfil.duelo.el)")
                                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(perfil.duelo.yo >= perfil.duelo.el ? T.verde : T.rojo)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        Text("En la comunidad desde el \(LigaFechas.corta(perfil.desde))"
                             + (perfil.ultimo.map { " · último partido el \(LigaFechas.corta($0))" } ?? ""))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                        if !perfil.siguiendo {
                            Button {
                                Task {
                                    await comunidad.seguirAlias(alias)
                                    self.perfil = await comunidad.perfil(de: alias)
                                }
                            } label: {
                                Label("Seguir a @\(alias)", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ProgressView().padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .background(T.fondo)
            .navigationTitle("@\(alias)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
            }
            .task { perfil = await comunidad.perfil(de: alias) }
        }
    }
}
