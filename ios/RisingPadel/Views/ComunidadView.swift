import PadelCore
import PhotosUI
import UIKit
import SwiftUI

/// Envoltorio Identifiable para abrir el perfil de un alias en un sheet.
struct PerfilRef: Identifiable {
    let alias: String
    var id: String { alias }
}

/// La comunidad: el muro, quién está jugando ahora mismo y la gente que sigues.
struct ComunidadView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @EnvironmentObject private var liga: LigaModel

    /// Muro (0) o La semana (1): el muro es para leer; lo competitivo, a su sitio.
    @State private var seccion = 0
    @State private var publicando = false
    @State private var buscando = false
    @State private var comentando: ComunidadPost?
    @State private var retando = false
    @State private var torneando = false
    @State private var perfilDe: PerfilRef?

    var body: some View {
        NavigationStack {
            Group {
                if comunidad.tieneCuenta {
                    VStack(spacing: 0) {
                        Picker("", selection: $seccion) {
                            Text("Muro").tag(0)
                            Text("La semana").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        if seccion == 0 { muro } else { semana }
                    }
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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            publicando = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Publicar")
                    }
                }
            }
            .sheet(isPresented: $buscando) {
                ComunidadBuscarView().environmentObject(comunidad)
            }
            .sheet(isPresented: $publicando) {
                ComunidadComposerView()
                    .environmentObject(comunidad)
                    .environmentObject(liga)
            }
            .sheet(item: $comunidad.espectador) { vivo in
                LiveSpectatorView(vivo: vivo)
            }
            .sheet(item: $comentando) { post in
                ComentariosView(post: post).environmentObject(comunidad)
            }
            .sheet(isPresented: $retando) {
                RetosView().environmentObject(comunidad)
            }
            .sheet(isPresented: $torneando) {
                TorneoView().environmentObject(comunidad)
            }
            .sheet(item: $perfilDe) { ref in
                PerfilView(alias: ref.alias).environmentObject(comunidad)
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
                ForEach(comunidad.posts) { post in
                    postCard(post)
                }
                if comunidad.posts.isEmpty {
                    Text("El muro está vacío: sigue a alguien con el botón de arriba, "
                         + "o publica tú el primero con el lápiz.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Lo competitivo, en su sitio: el ranking semanal y las puertas a retos y torneo.
    private var semana: some View {
        ScrollView {
            VStack(spacing: 12) {
                if comunidad.ranking.count >= 2 {
                    rankingCard
                } else {
                    Text("El ranking se enciende cuando tú y los tuyos termináis "
                         + "partidos en vivo esta semana.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                        .padding(.top, 12)
                }
                puerta("Retos", icono: "bolt.fill",
                       detalle: "Reta a quien sigues: bandejas, víboras, victorias…") {
                    retando = true
                }
                puerta("Torneo", icono: "trophy",
                       detalle: "Monta un cuadro con tu grupo y que salga un campeón.") {
                    torneando = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func puerta(
        _ titulo: String, icono: String, detalle: String, accion: @escaping () -> Void
    ) -> some View {
        Button(action: accion) {
            PadelCard {
                HStack(spacing: 12) {
                    Image(systemName: icono)
                        .font(.system(size: 20))
                        .foregroundStyle(T.pista)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titulo)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(T.tinta)
                        Text(detalle)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(T.tintaSuave)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Quién de los tuyos está en pista ahora: chips compactos, un toque y a mirar.
    private var jugandoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(comunidad.jugando) { vivo in
                    Button {
                        comunidad.espectador = vivo
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(T.rojo).frame(width: 7, height: 7).modifier(Pulse())
                            Text("@\(vivo.alias)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(T.tinta)
                            Text("EN VIVO")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .kerning(0.8)
                                .foregroundStyle(T.rojo)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(T.superficie, in: Capsule())
                        .overlay(Capsule().strokeBorder(T.rojo.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// La semana en curso entre tú y los tuyos, con partidos de verdad (los que el
    /// servidor apunta al terminar cada partido en vivo).
    private var rankingCard: some View {
        PadelCard(title: "La semana", icon: "chart.bar.fill") {
            VStack(spacing: 6) {
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text("PJ").frame(width: 36)
                    Text("V").frame(width: 36)
                    Text("Golpeos").frame(width: 62)
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(T.tintaSuave)
                ForEach(Array(comunidad.ranking.enumerated()), id: \.element.id) { index, fila in
                    HStack {
                        Text("\(medalla(index)) @\(fila.alias)")
                            .font(.system(size: 13, weight: fila.alias == comunidad.alias ? .bold : .medium, design: .rounded))
                            .foregroundStyle(T.tinta)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(fila.partidos)").frame(width: 36)
                        Text("\(fila.victorias)").foregroundStyle(T.verde).frame(width: 36)
                        Text("\(fila.golpeos)").foregroundStyle(T.pista).frame(width: 62)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                }
            }
        }
    }

    private func medalla(_ index: Int) -> String {
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return " "
        }
    }

    private func postCard(_ post: ComunidadPost) -> some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // El alias abre su perfil: números, duelo de retos y seguir.
                    Button {
                        perfilDe = PerfilRef(alias: post.alias)
                    } label: {
                        Text("@\(post.alias)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(T.pista)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(post.creado)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
                Text(post.texto)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(T.tinta)
                    .fixedSize(horizontal: false, vertical: true)
                if let foto = post.foto, let url = comunidad.fotoURL(foto) {
                    AsyncImage(url: url) { imagen in
                        imagen.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(T.borde)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
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

                HStack(spacing: 16) {
                    Button {
                        Task { await comunidad.reaccionar(post) }
                    } label: {
                        HStack(spacing: 4) {
                            Text("🎾")
                            if post.reacciones > 0 {
                                Text("\(post.reacciones)").monospacedDigit()
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(post.miReaccion != nil ? T.pista : T.tintaSuave)
                    }
                    Button {
                        comentando = post
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.right")
                            if post.comentarios > 0 {
                                Text("\(post.comentarios)").monospacedDigit()
                            }
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                    }
                    Spacer()
                }
                .buttonStyle(.plain)
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
/// La hoja de publicar: con su propio foco y su botón de cerrar, el teclado nunca
/// secuestra el muro. La foto se comprime aquí a JPEG de verdad antes de subir — el
/// original del carrete puede ser HEIC de varios megas, que el servidor rechaza.
struct ComunidadComposerView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @EnvironmentObject private var liga: LigaModel
    @Environment(\.dismiss) private var dismiss

    @State private var texto = ""
    @State private var adjuntarPartido = false
    @State private var fotoElegida: PhotosPickerItem?
    @State private var fotoData: Data?
    @State private var enviando = false
    @FocusState private var enfocado: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Cuenta algo… (@alias para etiquetar)", text: $texto, axis: .vertical)
                        .font(.system(size: 15, design: .rounded))
                        .lineLimit(4...10)
                        .focused($enfocado)
                        .padding(12)
                        .background(T.superficie, in: RoundedRectangle(cornerRadius: 12))

                    if let fotoData, let imagen = UIImage(data: fotoData) {
                        Image(uiImage: imagen)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    self.fotoData = nil
                                    fotoElegida = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                        .padding(8)
                                }
                            }
                    }

                    HStack(spacing: 8) {
                        PhotosPicker(selection: $fotoElegida, matching: .images) {
                            Label("Foto", systemImage: "photo")
                                .font(.system(size: 13, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                        .onChange(of: fotoElegida) {
                            Task {
                                let crudo = try? await fotoElegida?
                                    .loadTransferable(type: Data.self)
                                fotoData = crudo.flatMap(Self.comprimir)
                            }
                        }
                        if liga.matches.first != nil {
                            Toggle(isOn: $adjuntarPartido) {
                                Label("Último partido", systemImage: "trophy")
                                    .font(.system(size: 13, design: .rounded))
                            }
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                }
                .padding(16)
            }
            .background(T.fondo)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Publicar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        enviando = true
                        let tarjeta = adjuntarPartido ? liga.matches.first : nil
                        Task {
                            await comunidad.publicar(
                                texto: texto, tarjeta: tarjeta, foto: fotoData
                            )
                            dismiss()
                        }
                    } label: {
                        if enviando {
                            ProgressView()
                        } else {
                            Text("Publicar").fontWeight(.bold)
                        }
                    }
                    .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty || enviando)
                }
            }
            .onAppear { enfocado = true }
        }
    }

    /// JPEG de verdad y tamaño de red social: lado mayor a 1600 px y calidad 0.8.
    /// Un original de 8 MB queda en unos cientos de KB, muy por debajo del límite
    /// de 3 MB del servidor, y lo puede pintar cualquier cliente.
    private static func comprimir(_ data: Data) -> Data? {
        guard let imagen = UIImage(data: data) else { return nil }
        let maximo: CGFloat = 1600
        let escala = min(1, maximo / max(imagen.size.width, imagen.size.height))
        let destino = CGSize(width: imagen.size.width * escala,
                             height: imagen.size.height * escala)
        let render = UIGraphicsImageRenderer(size: destino)
        let redimensionada = render.image { _ in
            imagen.draw(in: CGRect(origin: .zero, size: destino))
        }
        return redimensionada.jpegData(compressionQuality: 0.8)
    }
}

struct ComunidadRegistroView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @AppStorage("leagueBaseURL") private var servidor = ""
    @State private var alias = ""
    @State private var creando = false
    @State private var servidorPropio = false
    /// Modo "ya tenía cuenta": alias + código de recuperación en vez de crear una.
    @State private var recuperando = false
    @State private var codigo = ""

    /// El servidor oficial, de serie: nadie debería tener que teclear una URL para
    /// unirse. El campo solo aparece si se quiere apuntar a un servidor propio.
    static let servidorOficial = "https://rising-padel-live.rising-padel-2d82dd5fe2.workers.dev"

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
                        TextField("Tu alias (ej: jesus-g)", text: $alias)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if recuperando {
                            TextField("Código de recuperación", text: $codigo)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .font(.system(.body, design: .monospaced))
                        }
                        // El servidor viene de serie: la URL solo aparece para quien
                        // monte el suyo. Nadie teclea un workers.dev para unirse.
                        if servidorPropio {
                            TextField("https://tu-servidor.workers.dev", text: $servidor)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                }

                Button {
                    recuperando.toggle()
                } label: {
                    Text(recuperando ? "Quiero crear una cuenta nueva"
                                     : "Ya tenía cuenta (tengo mi código)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
                .buttonStyle(.plain)

                Button {
                    servidorPropio.toggle()
                } label: {
                    Text(servidorPropio ? "Usar el servidor oficial" : "Tengo mi propio servidor")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
                .buttonStyle(.plain)

                Button {
                    creando = true
                    if !servidorPropio || servidor.isEmpty {
                        servidor = Self.servidorOficial
                    }
                    Task {
                        if recuperando {
                            await comunidad.recuperar(
                                servidor: servidor, alias: alias, codigo: codigo
                            )
                        } else {
                            await comunidad.registrar(servidor: servidor, alias: alias)
                        }
                        creando = false
                    }
                } label: {
                    if creando {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(recuperando ? "Recuperar mi cuenta" : "Crear mi cuenta")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(alias.count < 2 || creando || (recuperando && codigo.count < 6))
            }
            .padding(20)
        }
    }
}

/// Los comentarios de un post: hilo simple, del más viejo al más nuevo.
struct ComentariosView: View {
    @EnvironmentObject private var comunidad: ComunidadModel
    @Environment(\.dismiss) private var dismiss
    let post: ComunidadPost

    @State private var comentarios: [ComunidadComentario] = []
    @State private var texto = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("@\(post.alias): \(post.texto)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                        Divider()
                        ForEach(comentarios) { comentario in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(comentario.alias)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(T.pista)
                                Text(comentario.texto)
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(T.tinta)
                            }
                        }
                        if comentarios.isEmpty {
                            Text("Sé el primero en comentar.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(T.tintaSuave)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                HStack(spacing: 8) {
                    TextField("Comenta…", text: $texto)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let contenido = texto
                        texto = ""
                        Task {
                            await comunidad.comentar(post, texto: contenido)
                            comentarios = await comunidad.comentarios(de: post)
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
            }
            .background(T.fondo)
            .navigationTitle("Comentarios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task { comentarios = await comunidad.comentarios(de: post) }
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
