import Foundation
import Perception

/// What an iPhone, iPad or Apple TV launch was doing while on screen. ErrorReports saves it as it goes
/// (every 30 seconds, on memory pressure, and when playback starts or stops), so that when a launch ends
/// on screen the next one can say why: the device restarted (not reported), the system was short of
/// memory, or neither (a crash or a watchdog). Apple TV has no MetricKit, so this is all there is about such an exit.
struct QuitContext: Codable, Equatable, Sendable {
    struct Playback: Codable, Equatable, Sendable {
        var live: Bool
        var format: String
        var source: String
        var since: Int
        var danmaku: Bool
        var sharper: Bool
    }

    var launch: String
    var started: Int
    var saved: Int
    /// Megabytes: this app's footprint, and how much more the system lets it use before ending it.
    var footprint: Int?
    var available: Int?
    var pressure: Int?
    var pressureLevel: String?
    var playback: Playback?

    /// Megabytes left at the last sample below which a launch counts as ended for memory.
    static let lowMemory = 64
    /// What builds without this context report, so that their reports stay in the group they had.
    static let unknown = "Quit unexpectedly while on screen (a crash, or the system ended it for memory)"

    /// The report for a launch that ended on screen, or nil when the device started up after its last
    /// sample (a restart, a power cut, an update). Only the first line groups reports, so it has no numbers.
    static func report(_ context: QuitContext?, bootTime: Int) -> String? {
        guard let context else { return unknown }
        if bootTime > context.saved { return nil }
        let pressured = context.pressure.map { context.saved - $0 <= 60 } ?? false
        let low = pressured || (context.available.map { $0 <= lowMemory } ?? false)
        var lines = ["Quit unexpectedly while on screen (\(low ? "low on memory" : "not low on memory"), \(context.playback == nil ? "browsing" : "during playback"))"]
        var memory = "memory: footprint=\(context.footprint.map { "\($0)MB" } ?? "-") available=\(context.available.map { "\($0)MB" } ?? "-")"
        if let pressure = context.pressure, let level = context.pressureLevel {
            memory += " pressure=\(level) \(context.saved - pressure)s before the last sample"
        }
        lines.append(memory)
        if let playback = context.playback {
            lines.append("playing: \(playback.live ? "live" : "vod") format=\(playback.format) source=\(playback.source) "
                + "for=\((context.saved - playback.since) / 60)min danmaku=\(playback.danmaku ? "on" : "off") sharper=\(playback.sharper ? "on" : "off")")
        }
        lines.append("launched \((context.saved - context.started) / 60)min before the last sample (taken every 30s on screen)")
        return lines.joined(separator: "\n")
    }
}
