import Foundation
import Perception

/// Touch and hold the picture to play faster, as in Douyin, YouTube, X and Telegram. The hold starts at the speed
/// chosen in Settings; sliding sideways steps through `rates` (Telegram), down to half speed on the left, and sliding
/// down keeps the speed after the finger lifts (X), until its label is tapped.
public struct SpeedBoost: Equatable, Sendable {
    public static let key = "player.holdSpeed"
    public static let rates: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 4]
    /// The speeds a hold can start at: normal speed only on the way between slower and faster.
    public static let startRates = rates.filter { $0 != 1 }
    public static let standard = 2.0
    /// Sideways distance, in points, from one rate to the next.
    public static let step = 50.0
    /// Downward distance, in points, that keeps the speed.
    public static let lockDistance = 80.0

    private let start: Int
    public private(set) var rate: Double
    public private(set) var locked = false

    /// Starts at the rate in `rates` nearest to `rate`.
    public init(rate: Double) {
        let wanted = rate.isFinite ? rate : Self.standard
        start = Self.rates.indices.min { abs(Self.rates[$0] - wanted) < abs(Self.rates[$1] - wanted) } ?? 1
        self.rate = Self.rates[start]
    }

    /// The finger is `x` points right of and `y` points below where the hold began.
    public mutating func moved(x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return }
        if y >= Self.lockDistance { locked = true }
        let steps = Int((x / Self.step).rounded(.towardZero))
        rate = Self.rates[min(max(0, start + steps), Self.rates.count - 1)]
    }
}
