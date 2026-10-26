import Foundation
import Perception

/// When each JAR source last answered its home or first category page with content. A plugin that
/// worked last week and now answers `{}` fails silently: the user sees an empty source and no error
/// is reported. Remembering the last answer with content tells that apart from a source that is always empty.
struct PluginAnswers: @unchecked Sendable {
    static let shared = PluginAnswers(defaults: .standard)
    /// An empty answer is reported when the source had content this recently.
    static let window: TimeInterval = 7 * 24 * 3600
    private static let key = "pluginAnswers"
    let defaults: UserDefaults

    /// Notes the answer. For an empty one from a source that recently had content, returns how long ago that was.
    func record(source: String, params: [String: String], answer: [String: JSONValue], now: Date = Date()) -> TimeInterval? {
        // Later category pages, searches, details and lines can be empty for one item; these pages can't.
        let kind = EmbeddedJarHost.kind(params)
        guard kind == "home" || (kind == "category" && (params["pg"] ?? "1") == "1") else { return nil }
        let id = source + "|" + kind
        let time = now.timeIntervalSince1970
        var seen = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        if LiteSites.unusable(answer, params: params) != nil {
            guard let last = seen[id], time - last < Self.window else { return nil }
            return time - last
        }
        seen[id] = time
        // Sources unseen for a month are forgotten, so removed subscriptions don't pile up.
        defaults.set(seen.filter { time - $0.value < 30 * 24 * 3600 }, forKey: Self.key)
        return nil
    }
}
