import Foundation

public struct SniffRule: Hashable, Sendable {
    public let hosts: [String]
    public let regex: [String]
    public let script: [String]
    public let exclude: [String]
    public let click: [String]
    public init(hosts: [String] = [], regex: [String] = [], script: [String] = [], exclude: [String] = [], click: [String] = []) {
        self.hosts = hosts
        self.regex = regex
        self.script = script
        self.exclude = exclude
        self.click = click
    }
}

public enum SniffDecision: Equatable, Sendable {
    case allow, block, follow, video
}

/// TVBox sniff decisions without a web view.
///
/// `decision` matches `ParseWebView.shouldInterceptRequest`:
/// 1. `about:` and `data:` load.
/// 2. An empty host is blocked. Any other host on the subscription `ads` list is blocked,
///    unless the address is a Cloudflare challenge resource.
/// 3. With `detect` on, an address matching `player.*https?://` is followed while this page
///    has followed fewer than five. The page's own address is not followed: a child page for it
///    would follow itself again. Following wins over the video test.
/// 4. A video address wins and stops the sniff.
/// 5. Anything else loads.
///
/// `isVideo` matches `Sniffer.isVideoFormat`, and does not call a spider `isVideoFormat`:
/// 1. With `detect` off, the page's own address is not a video.
/// 2. The first rule whose `hosts` match this address is used. The address host and the host
///    inside its `url` query are joined with a comma. A host pattern matches when the joined
///    text contains it, or when it is a regex that finds a match. An invalid regex does not match.
/// 3. `exclude` rejects the address before `regex` can accept it.
/// 4. `regex` accepts it before the default pattern.
/// 5. `url=http`, `v=http`, or `.html` in the path (query and fragment removed) reject it.
/// 6. The TVBox `SNIFFER` pattern then accepts `.m3u8`, `.mp4`, `.mkv`, `.flv`, `.mp3`,
///    `.m4a`, `.aac`, `.mpd`, `video/tos`, and `rtmp:`.
public enum SniffRules {
    public static let cloudflareCheck = "Boolean(window._cf_chl_opt && window._cf_chl_opt.cType)"
    private static let player = try! NSRegularExpression(pattern: "player.*https?://")
    private static let sniffer = try! NSRegularExpression(pattern: #"https?://[^\s]{12,}\.(?:m3u8|mp4|mkv|flv|mp3|m4a|aac|mpd)|https?://.*?video/tos[^\s]*|rtmp:[^\s]+"#)

    public static func decision(url: String, pageURL: String, detect: Bool, followedCount: Int, ads: [String], rules: [SniffRule]) -> SniffDecision {
        if let scheme = URL(string: url)?.scheme?.lowercased(), scheme == "about" || scheme == "data" { return .allow }
        let parsed = URL(string: url)
        let host = parsed?.host ?? ""
        let cloudflare = parsed.map(isCloudflareResource) ?? false
        if host.isEmpty || (!cloudflare && isAd(host: host, ads: ads)) { return .block }
        if detect, followedCount < 5, url != pageURL, matches(url, expression: player) { return .follow }
        if isVideo(url: url, pageURL: pageURL, detect: detect, rules: rules) { return .video }
        return .allow
    }

    public static func isVideo(url: String, pageURL: String, detect: Bool, rules: [SniffRule]) -> Bool {
        if !detect, url == pageURL { return false }
        if let rule = matchingRule(for: url, rules: rules) {
            if rule.exclude.contains(where: { matches(url, pattern: $0) }) { return false }
            if rule.regex.contains(where: { matches(url, pattern: $0) }) { return true }
        }
        if url.contains("url=http") || url.contains("v=http") || pathContainsHTML(url) { return false }
        return matches(url, expression: sniffer)
    }

    public static func pageScripts(pageURL: String, click: String, rules: [SniffRule]) -> [String] {
        var scripts = matchingRule(for: pageURL, rules: rules)?.script ?? []
        let extra = click.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty, !scripts.contains(extra) { scripts.insert(extra, at: 0) }
        return scripts
    }

    public static func pageClicks(pageURL: String, rules: [SniffRule]) -> [String] {
        matchingRule(for: pageURL, rules: rules)?.click ?? []
    }

    static func isCloudflareResource(_ url: URL) -> Bool {
        if url.host?.caseInsensitiveCompare("challenges.cloudflare.com") == .orderedSame { return true }
        return url.path.contains("/cdn-cgi/challenge-platform/")
    }

    private static func isAd(host: String, ads: [String]) -> Bool {
        ads.contains { matches(host, pattern: $0) }
    }

    private static func matchingRule(for url: String, rules: [SniffRule]) -> SniffRule? {
        let components = URLComponents(string: url)
        let nested = components?.queryItems?.first { $0.name == "url" }?.value
        let nestedHost = nested.flatMap { URL(string: $0)?.host } ?? ""
        let hosts = [components?.host ?? "", nestedHost].filter { !$0.isEmpty }.joined(separator: ",")
        guard !hosts.isEmpty else { return nil }
        return rules.first { rule in rule.hosts.contains { matches(hosts, pattern: $0) } }
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        if pattern.isEmpty { return false }
        if text.contains(pattern) { return true }
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        return matches(text, expression: expression)
    }

    private static func matches(_ text: String, expression: NSRegularExpression) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func pathContainsHTML(_ url: String) -> Bool {
        let path = URLComponents(string: url)?.path ?? url
        return path.contains(".html")
    }
}
