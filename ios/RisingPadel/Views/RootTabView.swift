import PadelCore
import SwiftUI

/// Raíz de la app: dos pestañas. Lo primero que se ve al abrir es la última sesión con
/// todos sus datos — es lo que se viene a mirar al salir de la pista —; el histórico
/// completo vive en su propia pestaña.
struct RootTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            LastSessionView()
                .tabItem { Label("Última sesión", systemImage: "figure.tennis") }
            SessionListView()
                .tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
        }
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
                if let last = model.sessions.first {
                    SessionDetailView(session: last)
                } else {
                    emptyState
                }
            }
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
