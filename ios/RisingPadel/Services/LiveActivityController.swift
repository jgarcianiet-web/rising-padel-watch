import ActivityKit
import Foundation
import PadelCore

/// Mantiene la Live Activity del partido en curso: la arranca con el primer estado que
/// llega del reloj, la actualiza en cada punto y la cierra con el resultado.
///
/// La actividad se alimenta en local (la app está recibiendo el estado por
/// WatchConnectivity de todos modos); no hay push remoto que configurar.
@MainActor
final class LiveActivityController {

    private var activity: Activity<PadelMatchAttributes>?
    private var sessionId: String?

    func update(with state: LiveMatchState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = ActivityContent(state: contentState(state), staleDate: nil)

        if activity == nil || sessionId != state.sessionId {
            // Partido nuevo: si quedaba una actividad vieja colgada, fuera con ella.
            if let previa = activity {
                Task { await previa.end(nil, dismissalPolicy: .immediate) }
            }
            sessionId = state.sessionId
            let startedAt = Date(timeIntervalSinceNow: -Double(state.elapsedSeconds))
            activity = try? Activity.request(
                attributes: PadelMatchAttributes(startedAt: startedAt),
                content: content
            )
        } else {
            let actual = activity
            Task { await actual?.update(content) }
        }

        if state.completed {
            let actual = activity
            activity = nil
            sessionId = nil
            // El resultado se queda un rato en la pantalla de bloqueo y se retira solo.
            Task {
                await actual?.end(content, dismissalPolicy: .after(.now + 15 * 60))
            }
        }
    }

    private func contentState(_ state: LiveMatchState) -> PadelMatchAttributes.ContentState {
        let score = state.score
        return PadelMatchAttributes.ContentState(
            sets: score.map { $0.allSets.map { "\($0.us)-\($0.them)" }.joined(separator: " ") } ?? "",
            pointsUs: score.map { $0.pointsLabel(.us) } ?? "",
            pointsThem: score.map { $0.pointsLabel(.them) } ?? "",
            servingUs: score.map { $0.server == .us },
            shotCount: state.shotCount,
            heartRateBpm: state.heartRateBpm,
            elapsedSeconds: state.elapsedSeconds,
            completed: state.completed,
            winnerUs: score?.winner.map { $0 == .us }
        )
    }
}
