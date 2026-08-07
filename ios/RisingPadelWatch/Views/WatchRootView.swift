import PadelCore
import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var controller: SessionController
    @AppStorage("trackScore") private var trackScore = false
    @AppStorage("deuceFormat") private var deuceFormatRaw = DeuceFormat.goldenPoint.rawValue
    @State private var showTraining = false
    @State private var showRutinas = false
    /// La pantalla inicial es una decisión (¿partido o entreno?), no un formulario.
    @State private var choosingFormat = false
    /// Segundo paso del partido: quién saca. Es la única pregunta que no se puede
    /// deducir después y sin ella no hay análisis de saque contra resto.
    @State private var choosingServer = false

    /// Página visible durante la grabación: 0 = controles, 1 = partido. Se arranca en
    /// el partido; los controles viven deslizando a la izquierda, como en Entreno.
    @State private var paginaPartido = 1

    var body: some View {
        Group {
            // Grabando, la sesión son dos páginas: deslizar a la izquierda saca los
            // controles (pausar, reanudar, finalizar) y la de la derecha es el partido
            // — el marcador si se lleva, o el contador de golpeos si no. Así ninguna
            // pulsación de juego puede finalizar nada: finalizar es otra pantalla.
            if controller.status == .recording {
                TabView(selection: $paginaPartido) {
                    SessionControlsView(paginaPartido: $paginaPartido).tag(0)
                    Group {
                        if controller.rutina != nil {
                            RutinaEnCursoView()
                        } else if let score = controller.score {
                            ScoreView(
                                score: score,
                                shotCount: controller.shotCount,
                                onPoint: { controller.pointTo($0) },
                                onUndo: { controller.undoPoint() },
                                onStop: { Task { await controller.stop() } }
                            )
                        } else {
                            ScrollView {
                                recordingContent.padding(.horizontal, 8)
                            }
                        }
                    }
                    .tag(1)
                }
                .tabViewStyle(.page)
                // La pausa tapa la página del partido: se ve el estado de un vistazo y
                // ningún roce anota puntos. En la página de controles no estorba — allí
                // está el botón de reanudar.
                .overlay {
                    if controller.isPaused, paginaPartido == 1 {
                        pausedOverlay
                    }
                }
                // El aviso del entrenador tapa el marcador a propósito: si merece
                // interrumpir, merece leerse. Un toque y vuelve el partido.
                .overlay {
                    if let tip = controller.liveTip {
                        liveTipOverlay(tip)
                    }
                }
            } else {
                // Con varios botones la columna no cabe en un reloj de 40 mm; sin
                // scroll, lo de abajo queda directamente inalcanzable.
                ScrollView {
                    VStack(spacing: 6) {
                        switch controller.status {
                        case .idle:
                            idleContent
                        case .preparing:
                            loadingContent("Preparando…")
                        case .recording:
                            EmptyView()
                        case .saving:
                            loadingContent("Guardando…")
                        case .saved:
                            summaryContent
                        case .error(let message):
                            errorContent(message)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    /// El telón de pausa: en grande, y con el camino de vuelta escrito.
    private var pausedOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.yellow)
            Text("EN PAUSA")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .kerning(1.5)
            Text(formatDuration(controller.elapsedSeconds))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("Desliza a la derecha\npara reanudar")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.9))
        .contentShape(Rectangle())
        // Tocar lleva a los controles, no reanuda: que un roce no ponga el partido en
        // marcha. Reanudar es un botón con nombre, en su página.
        .onTapGesture { paginaPartido = 0 }
    }

    /// Dos decisiones y ya: Partido (elige el 40-40 y arranca con marcador) o Entreno
    /// (arranca sin marcador al momento). Nada de interruptores ni formularios: en la
    /// puerta de la pista se elige qué se va a jugar, no se configura nada.
    @ViewBuilder
    private var idleContent: some View {
        if choosingServer {
            serverChooser
        } else if choosingFormat {
            formatChooser
        } else {
            VStack(spacing: 8) {
                Text("RISING PADEL")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .kerning(1.4)
                    .foregroundStyle(.tint)

                bigButton("Partido", icon: "trophy.fill", prominent: true) {
                    choosingFormat = true
                }
                bigButton("Entreno", icon: "figure.tennis", prominent: false) {
                    trackScore = false
                    Task { await controller.start() }
                }
                // Un entreno con guion: el reloj canta el ejercicio y lleva la cuenta.
                // Es lo que separa esta app de un contador de golpes.
                bigButton("Rutina", icon: "list.bullet.rectangle", prominent: false) {
                    trackScore = false
                    showRutinas = true
                }

                // Solo con la recogida de datos activada en el iPhone: es un modo para
                // quien construye el dataset, no para jugar.
                if controller.collectTrainingData {
                    Button("Datos de entrenamiento") { showTraining = true }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                }
            }
            .sheet(isPresented: $showTraining) {
                TrainingView().environmentObject(controller)
            }
            .sheet(isPresented: $showRutinas) {
                RutinaChooserView().environmentObject(controller)
            }
        }
    }

    /// Botón ancho con icono: en una muñeca lo que importa es el área de toque, no la
    /// densidad. Un botón que ocupa el ancho se acierta sin mirar.
    ///
    /// El estilo se elige con un `if` y no con un ternario porque `.bordered` y
    /// `.borderedProminent` son tipos distintos y el ternario no compila.
    @ViewBuilder
    private func bigButton(
        _ title: String,
        icon: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) { bigLabel(title, icon: icon) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) { bigLabel(title, icon: icon) }
                .buttonStyle(.bordered)
        }
    }

    private func bigLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }

    /// Formato de 40-40. Ya no arranca el partido: falta saber quién saca, y preguntarlo
    /// después evita que un toque de más se lleve por delante la elección.
    private var formatChooser: some View {
        VStack(spacing: 6) {
            Text("¿A 40-40?")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(DeuceFormat.allCases, id: \.self) { format in
                if format == currentDeuceFormat {
                    formatButton(format).buttonStyle(.borderedProminent)
                } else {
                    formatButton(format).buttonStyle(.bordered)
                }
            }
            backButton { choosingFormat = false }
        }
    }

    /// Quién saca el primer juego. Es la única pregunta del partido que no se puede
    /// deducir después, y con ella el análisis separa lo que pasa sacando de lo que pasa
    /// restando — que en pádel son dos partidos distintos.
    private var serverChooser: some View {
        VStack(spacing: 6) {
            Text("¿Quién saca?")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            bigButton("Nosotros", icon: "figure.tennis", prominent: true) {
                start(server: .us)
            }
            bigButton("Ellos", icon: "person.2.fill", prominent: false) {
                start(server: .them)
            }
            backButton {
                choosingServer = false
                choosingFormat = true
            }
        }
    }

    private func start(server: Side) {
        controller.firstServer = server
        trackScore = true
        choosingServer = false
        Task { await controller.start() }
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button("Atrás", action: action)
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }

    private func formatButton(_ format: DeuceFormat) -> some View {
        Button {
            deuceFormatRaw = format.rawValue
            choosingFormat = false
            choosingServer = true
        } label: {
            HStack {
                Text(format.label).font(.caption)
                if format == currentDeuceFormat {
                    Spacer()
                    Image(systemName: "checkmark").font(.system(size: 10))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var currentDeuceFormat: DeuceFormat {
        DeuceFormat(rawValue: deuceFormatRaw) ?? .goldenPoint
    }

    private func loadingContent(_ label: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(label).font(.caption)
        }
    }

    private var recordingContent: some View {
        VStack(spacing: 2) {
            Text("\(controller.shotCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                // El contador cambia constantemente; sin ancho fijo de dígito la cifra
                // "baila" en pantalla y cuesta leerla de reojo entre puntos.
                .monospacedDigit()
            Text("golpeos").font(.caption2).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(formatDuration(controller.elapsedSeconds)).monospacedDigit()
                if let bpm = controller.heartRateBpm {
                    Text("· \(bpm) ppm")
                }
            }
            .font(.caption2)

            if let shot = controller.lastShotType {
                Text(shot.label)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }

            objectivesStrip

            if controller.wrongWristWarning {
                Text("Reloj en la muñeca sin pala")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if controller.sensorsMayStop {
                Text("Sin permiso de entreno: puede dejar de contar con la pantalla apagada")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Parar vive en la página de controles (desliza a la izquierda), como en
            // el partido: ningún toque de juego puede finalizar la sesión.
            Text("◀︎ desliza para pausar o finalizar")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    /// El aviso del entrenador en vivo, a pantalla completa hasta que se toca.
    private func liveTipOverlay(_ tip: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            Text(tip)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Toca para volver")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92))
        .contentShape(Rectangle())
        .onTapGesture { controller.dismissLiveTip() }
    }

    /// Los objetivos del día que el reloj puede medir, con su progreso.
    ///
    /// Solo aparecen los medibles y solo mientras se juega: es el dato que convierte
    /// "hacer 15 bandejas" en algo que se persigue en pista, no que se comprueba en casa.
    @ViewBuilder
    private var objectivesStrip: some View {
        if !controller.objectiveProgress.isEmpty {
            VStack(spacing: 2) {
                ForEach(controller.objectiveProgress) { objetivo in
                    HStack(spacing: 4) {
                        Image(systemName: objetivo.measurement.met
                              ? "checkmark.circle.fill" : "target")
                            .font(.system(size: 9))
                        Text(objetivo.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(objetivo.text)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(objetivo.measurement.met ? .green : .secondary)
                }
            }
            .padding(.top, 2)
        }
    }

    private var summaryContent: some View {
        VStack(spacing: 6) {
            Text("Sesión guardada").font(.headline).multilineTextAlignment(.center)
            Text("\(controller.shotCount) golpeos · \(formatDuration(controller.elapsedSeconds))")
                .font(.caption)
            // El nivel se enseña al acabar y no en vivo: mirarlo subir y bajar entre
            // puntos no aporta nada y distrae del partido.
            if let level = controller.sessionLevel, level.gradedShots > 0 {
                Text(level.label)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            // Si la sesión iba guiada, lo primero que se quiere saber es si se completó.
            if let rutina = controller.rutina {
                Text(controller.rutinaTerminada
                     ? "\(rutina.nombre) completa ✓"
                     : "\(rutina.nombre) sin terminar")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(controller.rutinaTerminada ? .green : .secondary)
            }
            if let message = controller.statusMessage {
                Text(message)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("Hecho") { controller.acknowledge() }
                .buttonStyle(.bordered)
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.red)
            Button("Cerrar") { controller.acknowledge() }
                .buttonStyle(.bordered)
        }
    }

}

/// A ámbito de fichero: la página de controles (SessionControlsView) enseña el mismo
/// crono que el resto de pantallas del reloj.
func formatDuration(_ seconds: Int64) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

extension ShotType {
    var label: String {
        switch self {
        case .forehand: return "Derecha"
        case .backhand: return "Revés"
        case .forehandVolley: return "Volea de derecha"
        case .backhandVolley: return "Volea de revés"
        case .bandeja: return "Bandeja"
        case .vibora: return "Víbora"
        case .smash: return "Smash"
        case .serve: return "Saque"
        case .unknown: return "Sin clasificar"
        }
    }
}

#Preview {
    WatchRootView()
        .environmentObject(SessionController())
}
