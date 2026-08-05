import PadelCore
import SwiftUI
import WatchKit

/// Marcador del partido.
///
/// Dos zonas de toque con **identidad fija**: NOSOTROS arriba en azul, ELLOS abajo en
/// naranja, cada una con su nombre — el color te sigue aunque cambiéis de pista. Entre
/// las dos hay una franja neutra que no anota: antes la mitad superior llegaba hasta el
/// centro exacto y un toque ambiguo caía en "nosotros".
///
/// **Mantener pulsado una zona deshace el último punto**, directo y sin menús: es la
/// corrección frecuente. Finalizar exige **mantener pulsado el icono Y confirmar** —
/// un punto mal anotado se deshace, una sesión cerrada no, así que un roce no puede
/// cerrarla.
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

    /// Colores fijos de identidad: nosotros azul, ellos naranja. La pareja azul/naranja
    /// se distingue también con daltonismo, y como es identidad y no posición, el cambio
    /// de pista no la mueve: tu color te sigue.
    private static let nosotros = Color.blue
    private static let ellos = Color.orange

    var body: some View {
        if score.isFinished {
            finishedContent
        } else {
            VStack(spacing: 3) {
                zone(.us)
                centerStrip
                zone(.them)
            }
            .confirmationDialog("¿Finalizar la sesión?", isPresented: $confirmStop) {
                Button("Sí, finalizar", role: .destructive) { onStop() }
                Button("Seguir jugando", role: .cancel) {}
            }
        }
    }

    /// Una zona de toque con nombre y color propios. Cada zona gestiona sus gestos:
    /// tocar fuera de las dos (la franja central) no anota nada — antes la mitad
    /// superior llegaba hasta el centro exacto y un toque ambiguo caía en "nosotros".
    private func zone(_ side: Side) -> some View {
        let color = side == .us ? Self.nosotros : Self.ellos
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(side == .us ? "NOSOTROS" : "ELLOS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(color)
                if score.server == side {
                    // El saque, en palabra y no en un punto de 6 px: es la pregunta
                    // que más veces surge en mitad de un partido.
                    Text("saque")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(score.pointsLabel(side))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(score.server == side ? 0.9 : 0.35), lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onPoint(side) }
        // Mantener pulsado deshace el último punto, desde cualquiera de las dos zonas.
        .onLongPressGesture(minimumDuration: 0.6) { onUndo() }
    }

    /// La franja neutra: sets, estado y el control de finalizar. Aquí un toque no hace
    /// nada; finalizar exige mantener pulsado Y confirmar — un punto mal anotado se
    /// deshace, una sesión cerrada no.
    private var centerStrip: some View {
        HStack(spacing: 6) {
            Text("\(setsLine) · \(statusLine)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            if score.isGoldenPoint {
                Text("ORO")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.red)
            }
            if score.changeEndsPending {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tint)
            }
            Image(systemName: "stop.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .onLongPressGesture(minimumDuration: 0.8) { confirmStop = true }
        }
        .padding(.horizontal, 4)
        .frame(height: 20)
    }

    private var finishedContent: some View {
        VStack(spacing: 6) {
            Text(setsLine)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(score.winner == .us ? "¡Partido ganado!" : "Partido perdido")
                .font(.caption)
                .bold()
                .foregroundStyle(score.winner == .us ? Self.nosotros : Self.ellos)
            Button("Finalizar sesión", action: onStop)
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
        }
    }

    private var setsLine: String {
        score.allSets.map { "\($0.us)-\($0.them)" }.joined(separator: "  ")
    }

    private var statusLine: String {
        var parts = [score.server == .us ? "sacamos" : "sacan"]
        if score.isTieBreak { parts.append("tie-break") }
        parts.append("\(shotCount) golpeos")
        return parts.joined(separator: " · ")
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
