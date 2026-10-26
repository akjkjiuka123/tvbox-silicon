import Foundation
import Perception

/// Messages to the people using the app, published with the website (`website/public/messages.json`).
/// Unlike release notes they reach every build, App Store and TestFlight ones too, and each shows once.
public struct MessageFeed: Codable, Sendable, Equatable {
    public static let address = URL(string: "https://yingxia.getmegaportal.com/messages.json")!
    public var messages: [Message]
    public init(messages: [Message]) { self.messages = messages }

    public struct Message: Codable, Sendable, Equatable, Identifiable {
        /// Never reuse one: a device remembers the IDs it has shown.
        public var id: String
        public var title: LocalizedText
        public var body: LocalizedText
        /// Opened by a second button; Apple TV can't open web pages, so it leaves the button out.
        public var link: URL?
        /// That button's title; Learn More if left out.
        public var linkTitle: LocalizedText?
        /// Values of `ReleaseFeed.platform`; nil means every platform.
        public var platforms: [String]?
        /// `direct` (downloads and sideloading) or `appstore` (App Store and TestFlight); nil means both.
        public var channels: [String]?
        /// Inclusive version bounds, e.g. "1.7.9".
        public var minVersion: String?
        public var maxVersion: String?
        /// Inclusive build number bounds. TestFlight builds all carry version 1.7.7, so builds tell them apart.
        public var minBuild: Int?
        public var maxBuild: Int?
        /// Shown from `start` until `end`: ISO 8601 times ("2026-10-24T09:00:00+08:00") or dates ("2026-10-24", UTC).
        public var start: String?
        public var end: String?

        public init(id: String, title: LocalizedText, body: LocalizedText, link: URL? = nil, linkTitle: LocalizedText? = nil,
                    platforms: [String]? = nil, channels: [String]? = nil, minVersion: String? = nil, maxVersion: String? = nil,
                    minBuild: Int? = nil, maxBuild: Int? = nil, start: String? = nil, end: String? = nil) {
            self.id = id; self.title = title; self.body = body; self.link = link; self.linkTitle = linkTitle
            self.platforms = platforms; self.channels = channels; self.minVersion = minVersion; self.maxVersion = maxVersion
            self.minBuild = minBuild; self.maxBuild = maxBuild; self.start = start; self.end = end
        }

        /// Whether this build should show the message at `now`. A time that doesn't parse hides it.
        public func applies(to build: Build, at now: Date = Date()) -> Bool {
            if let platforms, !platforms.contains(build.platform) { return false }
            if let channels, !channels.contains(build.appStore ? "appstore" : "direct") { return false }
            let version = AppVersion(build.version)
            if let minVersion, version < AppVersion(minVersion) { return false }
            if let maxVersion, version > AppVersion(maxVersion) { return false }
            if let minBuild, build.number < minBuild { return false }
            if let maxBuild, build.number > maxBuild { return false }
            if let start { guard let date = Self.date(start), now >= date else { return false } }
            if let end { guard let date = Self.date(end), now < date else { return false } }
            return true
        }

        public static func date(_ text: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withFullDate]
            return formatter.date(from: text)
        }
    }

    /// What a message can be aimed at.
    public struct Build: Sendable {
        public var platform: String
        public var appStore: Bool
        public var version: String
        public var number: Int
        public init(platform: String = ReleaseFeed.platform, appStore: Bool, version: String, number: Int) {
            self.platform = platform; self.appStore = appStore; self.version = version; self.number = number
        }
    }

    /// Messages for `build` that it hasn't shown yet, in the feed's order.
    public func pending(for build: Build, seen: Set<String>, at now: Date = Date()) -> [Message] {
        messages.filter { !seen.contains($0.id) && $0.applies(to: build, at: now) }
    }

    /// The response headers that name a version of the file. Sent back, they let the server answer
    /// 304 Not Modified without a body when nothing changed (the website sends an ETag).
    public struct Validator: Codable, Sendable, Equatable {
        public var etag: String?
        public var lastModified: String?
        public init(etag: String? = nil, lastModified: String? = nil) { self.etag = etag; self.lastModified = lastModified }
    }

    public enum Fetched: Sendable, Equatable {
        /// The copy behind the validator that was sent is still current.
        case unchanged
        case changed(MessageFeed, Validator)
    }

    /// Reads the feed, or only learns that the copy `known` names is still current.
    public static func fetch(_ url: URL = address, ifChangedFrom known: Validator? = nil, session: URLSession = .shared) async throws -> Fetched {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let etag = known?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = known?.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 { return .unchanged }
        if let http, !(200..<300).contains(http.statusCode) { throw TVError.http(http.statusCode) }
        let feed = try JSONDecoder().decode(MessageFeed.self, from: data)
        return .changed(feed, Validator(etag: http?.value(forHTTPHeaderField: "ETag"), lastModified: http?.value(forHTTPHeaderField: "Last-Modified")))
    }
}
