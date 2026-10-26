import Foundation
import Perception

/// Titles to offer while someone types a search, as FongMi's TV search does. iQiyi's suggestion service matches pinyin
/// initials ("xyj"), full pinyin ("qingyunian") or a few characters to real titles ("西游记", "庆余年"), so a remote needs only
/// a few letters; choosing a title then searches the sources for exactly that, which they match far better than a
/// fragment. 360kan's chart fills the list before anything is typed. Both are unofficial endpoints: any failure is an
/// empty list, and what was typed is never logged.
public enum SearchSuggestions {
    public static let limit = 8

    /// Titles for what was typed; empty when there is nothing to ask or the service doesn't answer.
    public static func titles(for query: String, session: URLSession = .shared) async -> [String] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, var components = URLComponents(string: "https://suggest.video.iqiyi.com/") else { return [] }
        components.queryItems = [URLQueryItem(name: "if", value: "mobile"), URLQueryItem(name: "key", value: query)]
        guard let url = components.url, let data = await fetch(url, session: session) else { return [] }
        return titles(in: data, key: "name")
    }

    /// What is popular now, for an empty search field.
    public static func trending(session: URLSession = .shared) async -> [String] {
        guard let url = URL(string: "https://api.web.360kan.com/v1/rank?cat=1"),
              let data = await fetch(url, headers: ["Referer": "https://www.360kan.com/rank/general"], session: session) else { return [] }
        return titles(in: data, key: "title")
    }

    /// The titles in a `{"data": [{key: …}]}` answer, trimmed, without blanks or repeats, at most `limit`.
    static func titles(in data: Data, key: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["data"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        let titles = items.compactMap { ($0[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return Array(titles.prefix(limit))
    }

    /// A short wait: a suggestion that arrives after the next keystroke is no use.
    private static func fetch(_ url: URL, headers: [String: String] = [:], session: URLSession) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return nil }
        return data
    }
}
