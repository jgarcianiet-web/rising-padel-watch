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
            guard UserDefaults.standard.bool(forKey: "ligaAutoGuardar"),
                  let session = model.sessions.first,
                  session.score != nil else { return }
            liga.saveMatch(from: session, playerAverage: model.playerAverageLevel)
        }
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
}

/// La sesión más reciente, abierta directamente con todo su detalle: resultado, nivel,
/// gráficas, salud. Sin pasos intermedios.
struct LastSessionView: View {
    @EnvironmentObject private var model: AppModel
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
                    SessionDetailView(session: last)
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
