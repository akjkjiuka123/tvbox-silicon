import Foundation
import Observation

/// Subscription-qualified hides. The same key scheme as `PinnedSources`.
@MainActor @Observable public final class HiddenSources {
    private var keys: [String]
    /// Bumps when a source is hidden or shown, so a cached source row can be reused until then.
    public private(set) var revision = 0
    private let defaults: UserDefaults
    private static let storageKey = "hiddenSources.v1"
    private static let backfillKey = "hiddenSources.backfill.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys = defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    private func key(_ site: Site, origin: URL) -> String {
        EpisodeSkipSettings.scope(origin: site.origin(or: origin), source: site.sourceKey, video: "")
    }

    public func contains(_ site: Site, origin: URL) -> Bool { keys.contains(key(site, origin: origin)) }

    public func toggle(_ site: Site, origin: URL) {
        let key = key(site, origin: origin)
        if keys.contains(key) { keys.removeAll { $0 == key } } else { keys.append(key) }
        defaults.set(keys, forKey: Self.storageKey)
        revision += 1
    }

    public func insert(_ site: Site, origin: URL) {
        let key = key(site, origin: origin)
        guard !keys.contains(key) else { return }
        keys.append(key)
        defaults.set(keys, forKey: Self.storageKey)
        revision += 1
    }

    /// Writes a hide when this counted failure leaves the source red. Success, cancellation,
    /// a busy runtime, and a yellow-dot failure do nothing. A later success does not remove the hide.
    public func note(_ site: Site, origin: URL, error: Error?, health: SourceHealth, now: Date = Date()) {
        guard let error, SourceHealth.counts(error) else { return }
        guard health.status(site, origin: origin, now: now) == .failing else { return }
        insert(site, origin: origin)
    }

    /// One pass over the sources already loaded. An empty list waits for the real subscription.
    public func backfill(_ sites: [Site], origin: URL, health: SourceHealth, now: Date = Date()) {
        guard !defaults.bool(forKey: Self.backfillKey), !sites.isEmpty else { return }
        for site in sites where health.status(site, origin: origin, now: now) == .failing {
            insert(site, origin: origin)
        }
        defaults.set(true, forKey: Self.backfillKey)
    }
}

/// Set by the app so catalog requests can hide a source without TVCore owning the defaults suite.
@MainActor public enum SourceHideReports {
    public static var report: ((Site, URL, Error?) -> Void)?
}
