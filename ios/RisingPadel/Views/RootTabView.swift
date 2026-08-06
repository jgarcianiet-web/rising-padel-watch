import PadelCore
import SwiftUI

/// Raíz de la app: dos pestañas. Lo primero que se ve al abrir es la última sesión con
/// todos sus datos — es lo que se viene a mirar al salir de la pista —; el histórico
/// completo vive en su propia pestaña.
struct RootTabView: View {
    @EnvironmentObject private var model: AppModel
    /// La liga vive aquí y no en AppModel: es un dominio con su propio fichero y su
    /// propio ciclo de vida, y el día que tenga cuentas será su propio módulo.
    @StateObject private var liga = LigaModel()
    @StateObject private var comunidad = ComunidadModel()
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        TabView {
            LastSessionView()
                .tabItem { Label("Última sesión", systemImage: "figure.tennis") }
            SessionListView()
                .tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
            LigaView()
                .tabItem { Label("Liga", systemImage: "trophy.fill") }
            ComunidadView()
                .tabItem { Label("Comunidad", systemImage: "person.3.fill") }
        }
        .environmentObject(liga)
        .environmentObject(comunidad)
        // Con el guardado automático activado, cada sesión con marcador que llega del
        // reloj se convierte en partido de la liga sin tocar nada. El id del partido es
        // la fecha de inicio, así que repetirse es inocuo (actualiza, no duplica).
        .onChange(of: model.sessions.first?.sessionId) {
            if UserDefaults.standard.bool(forKey: "ligaAutoGuardar"),
               let session = model.sessions.first,
               session.score != nil {
                liga.saveMatch(from: session, playerAverage: model.playerAverageLevel)
            }
            // Cada sesión nueva renueva la copia de seguridad del servidor: reinstalar
            // la app nunca vuelve a costar el historial.
            Task { await subirCopia() }
        }
        // Al arrancar con la app vacía pero con cuenta en el Llavero (una
        // reinstalación), el historial vuelve solo del servidor.
        .task { await restaurarSiHaceFalta() }
        // El azul de pista es el color de marca: tiñe pestañas, enlaces y controles.
        .tint(T.pista)
        // El aviso vive en la raíz y no en una pestaña: un mensaje de sincronización
        // tiene que verse igual desde cualquiera de las dos.
        .alert(
            model.message ?? "",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )
        ) {
            Button("Vale", role: .cancel) { model.message = nil }
        }
        // El onboarding solo existe para quien de verdad empieza de cero: con sesiones
        // o cuenta previas se da por hecho sin enseñarlo.
        .onAppear {
            if !model.sessions.isEmpty || comunidad.tieneCuenta {
                onboardingDone = true
            }
        }
        .fullScreenCover(
            isPresented: Binding(get: { !onboardingDone }, set: { _ in })
        ) {
            OnboardingView()
                .environmentObject(model)
                .environmentObject(liga)
                .environmentObject(comunidad)
        }
    }

    // MARK: Copia de seguridad

    private func subirCopia() async {
        guard comunidad.tieneCuenta,
              let data = CopiaSeguridad.construir(
                  sesiones: model.sessions, liga: liga.backupData()
              ) else { return }
        if await comunidad.subirCopia(data) {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ultimaCopia")
        }
    }

    private func restaurarSiHaceFalta() async {
        guard model.sessions.isEmpty, comunidad.tieneCuenta,
              let data = await comunidad.descargarCopia(),
              let copia = CopiaSeguridad.abrir(data) else { return }
        let añadidas = model.restoreSessions(copia.sesiones)
        if let ligaJson = copia.ligaJson?.data(using: .utf8) {
            liga.restoreBackup(ligaJson)
        }
        if añadidas > 0 {
            model.message = "Copia restaurada: \(añadidas) sesión(es) y tu liga"
        }
    }
}

/// La sesión más reciente, abierta directamente con todo su detalle: resultado, nivel,
/// gráficas, salud. Sin pasos intermedios.
struct LastSessionView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liga: LigaModel
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let live = model.liveMatch {
                    // Con un partido en marcha, la portada es el partido: nadie abre la
                    // app a mitad de un set para ver la sesión de ayer.
                    ScrollView {
                        VStack(spacing: 12) {
                            LiveMatchBanner(state: live)
                            // El enlace del espectador: cualquiera que lo reciba ve el
                            // marcador refrescándose solo, sin instalar nada.
                            if let url = model.liveSpectatorURL(for: live.sessionId) {
                                ShareLink(item: url) {
                                    Label("Compartir el partido en vivo",
                                          systemImage: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                } else if let last = model.sessions.first {
                    inicio(last)
                } else {
                    emptyState
                }
            }
            .background(T.fondo)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environmentObject(model)
            }
        }
    }

    // MARK: La portada de tres segundos

    /// Lo que un jugador quiere saber al abrir la app, sin buscarlo: su nivel y si
    /// sube, cómo viene la racha y cómo va la temporada. La última sesión completa
    /// queda a un toque, no encima.
    private func inicio(_ last: PadelSession) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                heroInicio
                NavigationLink {
                    SessionDetailView(session: last)
                } label: {
                    resumenUltima(last)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Inicio")
    }

    /// Nivel de la última sesión puntuable; sin ella, la media del historial.
    private var nivelActual: Float? {
        model.sessions.first { $0.level.gradedShots > 0 }?.level.overall
            ?? model.playerAverageLevel
    }

    private var heroInicio: some View {
        PadelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: -2) {
                        Text(nivelActual.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.padelDisplay(54))
                            .monospacedDigit()
                            .foregroundStyle(T.lima)
                        Text("nivel actual")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.tintaSuave)
                    }
                    Spacer()
                    tendencia
                }

                racha

                // La meta de la temporada, si la hay: el "12 de 20" que empuja a jugar.
                if let temporada = liga.temporadaActual,
                   let objetivo = temporada.objetivoPartidos, objetivo > 0 {
                    let jugados = liga.matchesTemporadaActual.count
                    PadelBar(
                        label: "Partidos de la temporada",
                        value: "\(jugados)/\(objetivo)",
                        fraction: Float(jugados) / Float(objetivo),
                        color: T.lima
                    )
                }

                if let objetivo = liga.state.objetivos.first {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(T.lima)
                        Text(objetivo)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(T.tinta)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(T.limaTinte, in: Capsule())
                }
            }
        }
    }

    /// Flecha de tendencia: la última sesión contra la media del historial.
    @ViewBuilder
    private var tendencia: some View {
        if let nivel = nivelActual, let media = model.playerAverageLevel,
           abs(nivel - media) >= 0.05 {
            let sube = nivel >= media
            HStack(spacing: 4) {
                Image(systemName: sube ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .heavy))
                Text(String(format: "%+.1f", nivel - media))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(sube ? T.verde : T.rojo)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((sube ? T.verde : T.rojo).opacity(0.12), in: Capsule())
        }
    }

    /// Los últimos cinco partidos de la liga, como letras: V V D V V.
    @ViewBuilder
    private var racha: some View {
        let ultimos = liga.matches.sorted { $0.id > $1.id }.prefix(5)
        if !ultimos.isEmpty {
            HStack(spacing: 6) {
                Text("RACHA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(T.tintaSuave)
                ForEach(Array(ultimos.enumerated()), id: \.offset) { _, match in
                    let victoria = match.resultado == "victoria"
                    Text(victoria ? "V" : "D")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(victoria ? T.verde : T.rojo, in: Circle())
                }
            }
        }
    }

    private func resumenUltima(_ last: PadelSession) -> some View {
        PadelCard(title: "Última sesión", icon: "figure.tennis") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatSessionDate(last.startedAtEpochMs))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(T.tinta)
                    Text("\(last.totalShots) golpeos · \(formatDuration(last.durationSeconds))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
                Spacer()
                if let score = last.score, score.isFinished {
                    OutcomeBadge(
                        text: score.winner == .us ? "ganado" : "perdido",
                        color: score.winner == .us ? T.verde : T.rojo
                    )
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.tintaSuave)
            }
        }
    }

    /// La portada de un usuario recién llegado: en vez de un "no hay nada", el camino.
    /// Desaparece sola con la primera sesión del reloj.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "figure.tennis")
                    .font(.system(size: 44))
                    .foregroundStyle(T.pista)
                    .padding(.top, 24)
                Text("Bienvenido a Rising Padel")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(T.tinta)

                PadelCard(title: "Primeros pasos", icon: "flag.checkered") {
                    VStack(alignment: .leading, spacing: 12) {
                        paso("1", "Juega con el reloj",
                             "Abre Rising Padel en el Apple Watch y elige Partido o "
                             + "Entreno. Al acabar, la sesión aparece aquí sola, con "
                             + "golpeos, nivel y salud.")
                        paso("2", "Únete a la comunidad",
                             "En la pestaña Comunidad: pega la URL del servidor, elige "
                             + "tu alias y listo — eso enciende también el marcador en "
                             + "vivo para que tus amigos te sigan.")
                        paso("3", "Monta tu temporada",
                             "En Liga → menú ⋯ → Objetivos y perfil: tu meta de "
                             + "partidos y tus 3 objetivos. Los que el reloj pueda "
                             + "medir se marcarán solos.")
                        paso("4", "Dale voz al entrenador",
                             "En Ajustes → Entrenador IA, pega tu clave de API: "
                             + "análisis de temporada y crónicas para el muro.")
                    }
                }
            }
            .padding(16)
        }
    }

    private func paso(_ numero: String, _ titulo: String, _ detalle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(numero)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(T.pista, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(T.tinta)
                Text(detalle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    RootTabView().environmentObject(AppModel(store: InMemorySessionStore()))
}
