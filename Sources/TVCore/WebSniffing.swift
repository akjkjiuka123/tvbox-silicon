import Foundation

/// A hidden web view that returns the first video address TVBox would accept.
/// Nil means the page produced nothing before the timeout.
public protocol WebSniffing: Sendable {
    func sniff(url: String, headers: [String: String], click: String, detect: Bool, ads: [String], rules: [SniffRule]) async -> (url: URL, headers: [String: String])?
}

/// The sniffer registered for this process. Apple TV leaves it empty.
/// A client can still carry its own, which wins over this one.
public enum WebSniff: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var shared: (any WebSniffing)?
    public static func install(_ sniffer: (any WebSniffing)?) {
        lock.lock()
        shared = sniffer
        lock.unlock()
    }
    static var current: (any WebSniffing)? {
        lock.lock()
        defer { lock.unlock() }
        return shared
    }
}
