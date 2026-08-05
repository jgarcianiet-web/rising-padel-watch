import PadelCore
import SwiftUI

/// La tarjeta del entrenador IA en la pestaña Liga: el análisis vigente y el botón para
/// pedir uno nuevo.
///
/// El análisis se pide, no se genera solo: cuesta dinero del usuario (su clave de API) y
/// tiene sentido después de añadir partidos, no en cada apertura de la app.
struct CoachCard: View {
    @EnvironmentObject private var liga: LigaModel
    @EnvironmentObject private var model: AppModel

    @State private var generating = false

    var body: some View {
        PadelCard(title: "Entrenador", icon: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 12) {
                if let analisis = liga.state.analisis {
                    analysisBody(analisis)
                } else {
                    Text("Pide tu primer análisis: el entrenador lee todos tus partidos "
                         + "y los hechos que mide el reloj, y te devuelve patrones, un "
                         + "plan y tres objetivos.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(T.tintaSuave)
                }
                generateButton
            }
        }
    }

    // MARK: El análisis vigente

    @ViewBuilder
    private func analysisBody(_ analisis: LigaAnalisis) -> some View {
        if !analisis.fecha.isEmpty {
            Text("\(analisis.fecha) · sobre \(analisis.nPartidos) partidos")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(T.tintaSuave)
        }

        Text(analisis.lectura)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(T.tinta)
            .fixedSize(horizontal: false, vertical: true)

        if !analisis.patrones.isEmpty {
            section("Patrones", icon: "waveform.path.ecg", items: analisis.patrones)
        }
        if !analisis.plan.isEmpty {
            section("Plan", icon: "list.number", items: analisis.plan)
        }

        if !analisis.foco.isEmpty {
            // El foco es la única consigna que hay que recordar en pista: se enseña
            // como lo que es, la frase grande de la tarjeta.
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(T.pista)
                Text(analisis.foco)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(T.tinta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.pistaTinte, in: RoundedRectangle(cornerRadius: 10))
        }

        if !analisis.objetivos.isEmpty {
            section("Objetivos que te prescribe", icon: "checklist", items: analisis.objetivos)
            if analisis.objetivos != liga.state.objetivos {
                Button {
                    liga.adoptObjetivos(analisis.objetivos)
                } label: {
                    Label("Adoptar como mis objetivos", systemImage: "checkmark.circle")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    private func section(_ title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(T.pista)
                        .padding(.top, 2)
                    Text(item)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(T.tinta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Generar

    @ViewBuilder
    private var generateButton: some View {
        if generating {
            HStack(spacing: 8) {
                ProgressView()
                Text("El entrenador está leyendo tus partidos…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(T.tintaSuave)
            }
        } else if !hasKey {
            Text("Añade tu clave de API de Anthropic en Ajustes para usar el entrenador.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(T.tintaSuave)
        } else {
            Button {
                generar()
            } label: {
                Label(
                    liga.state.analisis == nil ? "Pedir análisis" : "Analizar otra vez",
                    systemImage: "sparkles"
                )
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .disabled(liga.matches.isEmpty)
        }
    }

    private var hasKey: Bool { CoachKeyStore.read() != nil }

    private func generar() {
        generating = true
        // Los hechos del reloj se calculan antes de llamar: salen del InsightEngine
        // sobre las sesiones recientes, y son lo único de sensores que ve el modelo.
        let hechos = CoachService.hechosReloj(sessions: model.sessions)
        let state = liga.state
        Task {
            do {
                let analisis = try await CoachService().analizar(state: state, hechosReloj: hechos)
                liga.applyAnalisis(analisis)
            } catch {
                liga.message = error.localizedDescription
            }
            generating = false
        }
    }
}
