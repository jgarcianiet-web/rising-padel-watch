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

    var body: some View {
        TabView {
            LastSessionView()
                .tabItem { Label("Última sesión", systemImage: "figure.tennis") }
            SessionListView()
                .tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
            LigaView()
                .tabItem { Label("Liga", systemImage: "trophy.fill") }
        }
        .environmentObject(liga)
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Todavía no hay sesiones", systemImage: "figure.tennis")
        } description: {
            Text("Abre Rising Padel en el reloj y elige Partido o Entreno. "
                 + "Al terminar, la sesión aparecerá aquí sola.")
        }
    }
}

#Preview {
    RootTabView().environmentObject(AppModel(store: InMemorySessionStore()))
}
