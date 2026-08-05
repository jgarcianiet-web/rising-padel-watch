import PadelCore
import SwiftUI

/// La comunidad: el muro, quién está jugando ahora mismo y la gente que sigues.
struct ComunidadView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @EnvironmentObject private var liga: LigaModel

    @State private var texto = ""
    @State private var adjuntarPartido = false
    @State private var buscando = false

    var body: some View {
        NavigationStack {
            Group {
                if comunidad.tieneCuenta {
                    muro
                } else {
                    ComunidadRegistroView()
                }
            }
            .background(T.fondo)
            .navigationTitle("Comunidad")
            .toolbar {
                if comunidad.tieneCuenta {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            buscando = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityLabel("Buscar gente")
                    }
                }
            }
            .sheet(isPresented: $buscando) {
                ComunidadBuscarView().environmentObject(comunidad)
            }
            .sheet(item: $comunidad.espectador) { vivo in
                LiveSpectatorView(vivo: vivo)
            }
            .alert(
                comunidad.message ?? "",
                isPresented: Binding(
                    get: { comunidad.message != nil },
                    set: { if !$0 { comunidad.message = nil } }
                )
            ) {
                Button("Vale", role: .cancel) { comunidad.message = nil }
            }
            .task { await comunidad.refrescar() }
            .refreshable { await comunidad.refrescar() }
        }
    }

    private var muro: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !comunidad.jugando.isEmpty {
                    jugandoStrip
                }
                composer
                ForEach(comunidad.posts) { post in
                    postCard(post)
                }
                if comunidad.posts.isEmpty {
                    Text("El muro está vacío: sigue a alguien con el botón de arriba, "
                         + "o publica tú el primero.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// Quién de los tuyos está en pista ahora: un toque y a mirar.
    private var jugandoStrip: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(comunidad.jugando) { vivo in
                    Button {
                        comunidad.espectador = vivo
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(T.rojo).frame(width: 8, height: 8)
                            Text("\(vivo.alias) está jugando ahora")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(T.tinta)
                            Spacer()
                            Text("VER")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .kerning(1.2)
                                .foregroundStyle(T.pista)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composer: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Cuenta algo… (@alias para etiquetar)", text: $texto, axis: .vertical)
                    .font(.system(size: 14, design: .rounded))
                HStack {
                    if liga.matches.first != nil {
                        Toggle(isOn: $adjuntarPartido) {
                            Label("Adjuntar mi último partido", systemImage: "trophy")
                                .font(.system(size: 12, design: .rounded))
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                    Button {
                        let tarjeta = adjuntarPartido ? liga.matches.first : nil
                        let contenido = texto
                        texto = ""
                        adjuntarPartido = false
                        Task { await comunidad.publicar(texto: contenido, tarjeta: tarjeta) }
                    } label: {
                        Label("Publicar", systemImage: "paperplane.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func postCard(_ post: ComunidadPost) -> some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("@\(post.alias)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(T.pista)
                    Spacer()
                    Text(post.creado)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
                Text(post.texto)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(T.tinta)
                    .fixedSize(horizontal: false, vertical: true)
                if let tarjeta = post.tarjeta {
                    MatchShareCard(match: tarjeta)
                        .scaleEffect(0.78, anchor: .topLeading)
                        .frame(maxHeight: 200, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !post.etiquetas.isEmpty {
                    Text(post.etiquetas.map { "@\($0)" }.joined(separator: " "))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
            }
        }
        .contextMenu {
            if post.alias == comunidad.alias {
                Button(role: .destructive) {
                    Task { await comunidad.borrar(post) }
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            } else {
                Button {
                    Task { await comunidad.reportar(post) }
                } label: {
                    Label("Denunciar", systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) {
                    Task { await comunidad.bloquear(post.alias) }
                } label: {
                    Label("Bloquear a @\(post.alias)", systemImage: "hand.raised")
                }
            }
        }
    }
}

/// El alta: servidor + alias. El token que devuelve el servidor es la cuenta entera y
/// se guarda en el Llavero; el mismo registro deja configurados el marcador en vivo y
/// la subida de sesiones.
struct ComunidadRegistroView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @AppStorage("leagueBaseURL") private var servidor = ""
    @State private var alias = ""
    @State private var creando = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(T.pista)
                Text("Únete a la comunidad")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                Text("Sigue a tus amigos, mira sus partidos en vivo y comparte los "
                     + "tuyos en el muro. Solo hace falta un alias.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .multilineTextAlignment(.center)

                PadelCard {
                    VStack(spacing: 10) {
                        TextField("https://rising-padel-live.….workers.dev", text: $servidor)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Tu alias (ej: jesus-g)", text: $alias)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Button {
                    creando = true
                    Task {
                        await comunidad.registrar(servidor: servidor, alias: alias)
                        creando = false
                    }
                } label: {
                    if creando {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Crear mi cuenta")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(servidor.isEmpty || alias.count < 2 || creando)
            }
            .padding(20)
        }
    }
}

/// Buscar gente y seguirla.
struct ComunidadBuscarView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""

    var body: some View {
        NavigationStack {
            List(comunidad.usuarios) { usuario in
                HStack {
                    Text("@\(usuario.alias)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Button(usuario.siguiendo ? "Siguiendo" : "Seguir") {
                        Task { await comunidad.seguir(usuario) }
                    }
                    .buttonStyle(.bordered)
                    .tint(usuario.siguiendo ? T.tintaSuave : T.pista)
                }
            }
            .searchable(text: $q, prompt: "Buscar por alias")
            .onChange(of: q) {
                Task { await comunidad.buscar(q) }
            }
            .task { await comunidad.buscar("") }
            .navigationTitle("Gente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") {
                        dismiss()
                        Task { await comunidad.refrescar() }
                    }
                }
            }
        }
    }
}
