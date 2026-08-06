import Foundation

/// Un récord personal: el valor y la sesión en la que cayó.
public struct PersonalRecord: Equatable, Sendable {
    public let valor: Float
    public let sessionId: String
    public let startedAtEpochMs: Int64
}

/// Los récords del jugador sobre su historial: pura motivación, cero coste de captura.
/// Se recalculan de las sesiones cada vez — como el nivel, no pueden desincronizarse.
/// Espejo del core Kotlin, con tests allí.
public struct PersonalRecords: Equatable, Sendable {
    /// Pala más rápida (km/h).
    public let velocidadMax: PersonalRecord?
    /// Más golpeos en una sesión.
    public let golpeosMax: PersonalRecord?
    /// Mejor ritmo (golpeos/minuto) en sesiones de al menos 10 minutos.
    public let ritmoMax: PersonalRecord?
    /// Mejor nivel de sesión (solo sesiones con nivel fiable).
    public let nivelMax: PersonalRecord?
    /// Más smashes en una sesión.
    public let smashesMax: PersonalRecord?

    /// Sesiones muy cortas fuera del ritmo: 3 golpeos en 1 min no son un récord.
    public static let minRitmoDurationS: Int64 = 10 * 60

    /// ¿Esta sesión ostenta alguno de los récords? Para el distintivo 🏆 en su ficha.
    public func esDe(_ sessionId: String) -> Bool {
        [velocidadMax, golpeosMax, ritmoMax, nivelMax, smashesMax]
            .compactMap { $0 }
            .contains { $0.sessionId == sessionId }
    }

    public static func from(_ sessions: [PadelSession]) -> PersonalRecords {
        func mejor(_ valorDe: (PadelSession) -> Float?) -> PersonalRecord? {
            sessions.compactMap { s -> PersonalRecord? in
                guard let valor = valorDe(s), valor > 0 else { return nil }
                return PersonalRecord(
                    valor: valor, sessionId: s.sessionId, startedAtEpochMs: s.startedAtEpochMs
                )
            }
            .max { $0.valor < $1.valor }
        }

        return PersonalRecords(
            velocidadMax: mejor { $0.intensity.maxRacketSpeedKmh },
            golpeosMax: mejor { Float($0.totalShots) },
            ritmoMax: mejor { s in
                s.durationSeconds >= Self.minRitmoDurationS ? s.shotsPerMinute : nil
            },
            nivelMax: mejor { s in
                let level = s.level
                return level.gradedShots > 0 && level.reliable ? level.overall : nil
            },
            smashesMax: mejor { s in
                s.shotsByType[.smash].map(Float.init)
            }
        )
    }
}
