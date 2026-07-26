import PadelCore
import SwiftUI
import WatchKit

/// Marcador del partido.
///
/// La pantalla entera son dos zonas de toque: **mitad de arriba, punto nuestro; mitad de
/// abajo, punto suyo**. No hay botones que acertar porque entre punto y punto hay tres
/// segundos y una pala en la mano.
///
/// **Mantener pulsado deshace.** No se usa deslizar, que sería más natural, porque el
/// deslizamiento horizontal está tomado por la navegación del sistema en watchOS y por
/// el gesto de volver atrás en Wear OS. Mantener pulsado está libre en las dos
/// plataformas y no se dispara por accidente.
struct ScoreView: View {
    let score: MatchScore
    let shotCount: Int
    let onPoint: (Side) -> Void
    let onUndo: () -> Void

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

                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

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
        onUndo: {}
    )
}
