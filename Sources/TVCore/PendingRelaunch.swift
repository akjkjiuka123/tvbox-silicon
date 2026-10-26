import Foundation
import Perception

/// The Mac update the app was relaunching to install, kept until the next launch so that launch can say how it
/// went. A relaunch that hung until someone force-quit the app shows up as slow, or as the old version (#122).
public struct PendingRelaunch: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    /// The update's CFBundleVersion, which Sparkle compares.
    public var build: String
    public var requested: Date
    public init(from: String, to: String, build: String, requested: Date) {
        self.from = from; self.to = to; self.build = build; self.requested = requested
    }

    /// Installing and reopening takes seconds; a relaunch slower than this most likely waited for someone to quit.
    public static let slow: TimeInterval = 60

    /// What the next launch logs, running `version` (`build`): errors get reported.
    public func outcome(version: String, build current: String, now: Date = Date()) -> (level: LogLevel, message: String) {
        let seconds = Int(max(0, now.timeIntervalSince(requested)).rounded())
        guard current == build else {
            return (.error, "Update to \(to) (\(build)) didn't install: opened \(version) (\(current)) \(seconds) s after Relaunch")
        }
        if Double(seconds) > Self.slow {
            return (.error, "Update from \(from) to \(to) took \(seconds) s to relaunch; the app likely didn't quit by itself")
        }
        return (.info, "Updated from \(from) to \(to); relaunched in \(seconds) s")
    }
}
