import Foundation

public enum Hand: String, Codable, CaseIterable, Sendable {
    case right
    case left

    public var wireName: String { rawValue }

    public static func fromWire(_ value: String) -> Hand {
        value == "left" ? .left : .right
    }
}

public struct PlayerProfile: Codable, Equatable, Sendable {
    /// Mano con la que se empuña la pala.
    public let hand: Hand
    /// Muñeca donde se lleva el reloj. Para medir golpeos **tiene que coincidir con
    /// `hand`**: el reloj solo ve el brazo en el que está.
    public let watchWrist: Hand
    public let birthYear: Int?
    public let maxHeartRate: Int?
    public let restingHeartRate: Int?

    public init(
        hand: Hand = .right,
        watchWrist: Hand = .right,
        birthYear: Int? = nil,
        maxHeartRate: Int? = nil,
        restingHeartRate: Int? = nil
    ) {
        self.hand = hand
        self.watchWrist = watchWrist
        self.birthYear = birthYear
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
    }

    /// Si es false, la UI debe avisar de que el conteo no será fiable.
    public var watchOnRacketArm: Bool { hand == watchWrist }

    /// FC máxima configurada, o estimada con 220 - edad. Sin datos, 190.
    public func effectiveMaxHeartRate(currentYear: Int) -> Int {
        if let maxHeartRate { return maxHeartRate }
        guard let birthYear else { return 190 }
        return min(max(220 - (currentYear - birthYear), 120), 210)
    }
}
