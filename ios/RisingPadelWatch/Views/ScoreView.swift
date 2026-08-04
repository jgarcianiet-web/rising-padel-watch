import PadelCore
import SwiftUI
import WatchKit

/// Marcador del partido.
///
/// La pantalla entera son dos zonas de toque: **mitad de arriba, punto nuestro; mitad de
/// abajo, punto suyo**. No hay botones que acertar porque entre punto y punto hay tres
/// segundos y una pala en la mano.
///
/// **Mantener pulsado deshace el último punto**, directo y sin menús: es la corrección
/// frecuente y en mitad de un partido no hay tiempo que perder. Finalizar tiene su
/// propio botón pequeño en la franja central — es la acción rara, y pasa por una
/// confirmación porque un punto mal anotado se deshace pero una sesión cerrada no.
///
/// No se usa deslizar para nada: el deslizamiento horizontal está tomado por la
/// navegación del sistema.
struct ScoreView: View {
    let score: MatchScore
    let shotCount: Int
    let onPoint: (Side) -> Void
    let onUndo: () -> Void
    let onStop: () -> Void

    @State private var confirmStop = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 2) {
                Text(setsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 10) {
                    pointsBlock(.us)
                    Text("·").font(.title2).foregroundStyle(.secondary)
                    pointsBlock(.them)
                }

                // El botón vive en la franja central, la zona neutra entre las dos
                // mitades de toque: un dedo que acabe aquí ya era ambiguo como punto.
                HStack(spacing: 6) {
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !score.isFinished {
                        Button {
                            confirmStop = true
                        } label: {
                            Image(systemName: "stop.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // El punto decisivo hay que saber que se está jugando: con star point
                // llega sin avisar tras dos ventajas.
                if score.isGoldenPoint {
                    Text("PUNTO DE ORO")
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.red)
                }

                if score.changeEndsPending {
                    Text("Cambio de pista")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }

                if score.isFinished {
                    Text(score.winner == .us ? "¡Partido ganado!" : "Partido perdido")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.tint)
                    // Con el partido cerrado ya no hay puntos que anotar: el botón de
                    // finalizar puede ocupar el sitio sin robarle nada a nadie.
                    Button("Finalizar sesión", action: onStop)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 2)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                // `sequenced` no hace falta: un tap y un long press se distinguen solos,
                // y así el toque no espera a descartar la pulsación larga.
                SpatialTapGesture()
                    .onEnded { event in
                        onPoint(event.location.y < geometry.size.height / 2 ? .us : .them)
                    }
            )
            .onLongPressGesture(minimumDuration: 0.6) {
                onUndo()
            }
            .confirmationDialog("¿Finalizar la sesión?", isPresented: $confirmStop) {
                Button("Finalizar", role: .destructive) { onStop() }
                Button("Seguir jugando", role: .cancel) {}
            }
        }
    }

    private var setsLine: String {
        score.allSets.map { "\($0.us)-\($0.them)" }.joined(separator: "  ")
    }

    private var statusLine: String {
        var parts = [score.server == .us ? "Sacamos" : "Sacan"]
        if score.isTieBreak { parts.append("tie-break") }
        parts.append("\(shotCount) golpeos")
        return parts.joined(separator: " · ")
    }

    private func pointsBlock(_ side: Side) -> some View {
        VStack(spacing: 3) {
            Text(score.pointsLabel(side))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(side == .us ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            // Punto de saque: a quién le toca sacar es la pregunta que más veces surge
            // en mitad de un partido.
            Circle()
                .fill(score.server == side ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                .frame(width: 6, height: 6)
        }
    }
}

/// Vibraciones distintas para cada cosa que puede pasar al puntuar.
///
/// Es lo que hace usable el marcador: entre punto y punto el jugador está colocándose,
/// no mirando el reloj. Un patrón reconocible confirma que el toque se registró y qué
/// significó, sin obligar a levantar la muñeca.
enum ScoreHaptics {
    static func play(_ event: ScoreEvent) {
        let type: WKHapticType
        switch event {
        case .point: type = .click
        case .game: type = .directionUp
        case .set: type = .success
        case .match: type = .notification
        case .undo: type = .retry
        }
        WKInterfaceDevice.current().play(type)
    }
}

#Preview {
    ScoreView(
        score: MatchScore.start().pointTo(.us).pointTo(.us).pointTo(.them),
        shotCount: 128,
        onPoint: { _ in },
        onUndo: {},
        onStop: {}
    )
}
