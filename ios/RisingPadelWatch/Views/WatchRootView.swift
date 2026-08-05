import PadelCore
import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var controller: SessionController
    @AppStorage("trackScore") private var trackScore = false
    @AppStorage("deuceFormat") private var deuceFormatRaw = DeuceFormat.goldenPoint.rawValue
    @State private var showTraining = false
    /// La pantalla inicial es una decisión (¿partido o entreno?), no un formulario.
    @State private var choosingFormat = false
    /// Segundo paso del partido: quién saca. Es la única pregunta que no se puede
    /// deducir después y sin ella no hay análisis de saque contra resto.
    @State private var choosingServer = false

    var body: some View {
        Group {
            // Con marcador activo, el marcador **es** la pantalla del partido: es lo que
            // el jugador mira y toca entre puntos. El conteo de golpeos sigue corriendo
            // por debajo y aparece en la línea de estado.
            if controller.status == .recording, let score = controller.score {
                ScoreView(
                    score: score,
                    shotCount: controller.shotCount,
                    onPoint: { controller.pointTo($0) },
                    onUndo: { controller.undoPoint() },
                    onStop: { Task { await controller.stop() } }
                )
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
                            recordingContent
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

            Button("Parar") {
                Task { await controller.stop() }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
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

    private func formatDuration(_ seconds: Int64) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
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
