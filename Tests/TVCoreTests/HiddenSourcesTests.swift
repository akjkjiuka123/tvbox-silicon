import Foundation
import Testing
@testable import TVCore

private let origin = URL(string: "https://one.example/a.json")!
private func source(_ key: String) -> Site {
    Site(key: key, name: key, type: 1, api: "https://api.example/" + key, raw: ["key": .string(key)])
}

@Test @MainActor func hiddenSourcesPersistAndStayQualifiedBySubscription() throws {
    let suite = "hidden." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let site = source("a")
    let hidden = HiddenSources(defaults: defaults)
    #expect(!hidden.contains(site, origin: origin))
    hidden.toggle(site, origin: origin)
    #expect(hidden.contains(site, origin: origin))
    #expect(HiddenSources(defaults: defaults).contains(site, origin: origin))
    #expect(!hidden.contains(site, origin: URL(string: "https://other.example/a.json")!))
    hidden.toggle(site, origin: origin)
    #expect(!hidden.contains(site, origin: origin))
    hidden.insert(site, origin: origin)
    hidden.insert(site, origin: origin)
    #expect(hidden.contains(site, origin: origin))
}

private struct Failure: Error {}

@Test @MainActor func failingSourcesGoRedWithoutBeingHidden() throws {
    let suite = "hidden.red." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hidden = HiddenSources(defaults: defaults)
    let health = SourceHealth(file: nil)
    let now = Date()
    for site in [source("a")] + Site.builtInSites {
        health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
        health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
        #expect(health.status(site, origin: origin, now: now) == .failing)
        #expect(!hidden.contains(site, origin: origin))
    }
    hidden.restoreAutoHidden([source("a")] + Site.builtInSites, origin: origin, health: health)
    #expect(!hidden.contains(source("a"), origin: origin))
}

@Test @MainActor func sourcesHiddenForFailingShowAgainOnce() throws {
    let suite = "hidden.auto." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hidden = HiddenSources(defaults: defaults)
    let health = SourceHealth(file: nil)
    let failed = source("failed"), once = source("once"), chosen = source("chosen"), later = source("later")
    let now = Date()
    // 1.7.13 hid `failed` when it went red; the viewer hid the others by hand.
    for _ in 0..<2 { health.record(failed, origin: origin, seconds: 1, error: Failure(), now: now) }
    health.record(once, origin: origin, seconds: 1, error: Failure(), now: now)
    health.record(chosen, origin: origin, seconds: 1, error: nil, now: now)
    for site in [failed, once, chosen] { hidden.insert(site, origin: origin) }
    #expect(health.failedRepeatedly(failed, origin: origin))
    #expect(!health.failedRepeatedly(once, origin: origin))
    // An empty list waits for the real subscription.
    hidden.restoreAutoHidden([], origin: origin, health: health)
    #expect(hidden.contains(failed, origin: origin))
    let sites = [failed, once, chosen, later]
    hidden.restoreAutoHidden(sites, origin: origin, health: health)
    #expect(!hidden.contains(failed, origin: origin))
    #expect(hidden.contains(once, origin: origin))
    #expect(hidden.contains(chosen, origin: origin))
    #expect(!HiddenSources(defaults: defaults).contains(failed, origin: origin))
    // Only once: a failing source the viewer hides afterwards stays hidden.
    for _ in 0..<2 { health.record(later, origin: origin, seconds: 1, error: Failure(), now: now) }
    hidden.insert(later, origin: origin)
    hidden.restoreAutoHidden(sites, origin: origin, health: health)
    #expect(hidden.contains(later, origin: origin))
}

@Test @MainActor func builtInsHiddenBeforeShowAgainOnce() throws {
    let suite = "hidden.restore." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hidden = HiddenSources(defaults: defaults)
    let site = source("a")
    hidden.insert(.hongguo, origin: origin)
    hidden.insert(site, origin: origin)
    hidden.restoreBuiltIns([], origin: origin)
    #expect(hidden.contains(.hongguo, origin: origin))
    let sites = [site] + Site.builtInSites
    hidden.restoreBuiltIns(sites, origin: origin)
    #expect(!hidden.contains(.hongguo, origin: origin))
    #expect(hidden.contains(site, origin: origin))
    #expect(!HiddenSources(defaults: defaults).contains(.hongguo, origin: origin))
    hidden.toggle(.hongguo, origin: origin)
    hidden.restoreBuiltIns(sites, origin: origin)
    #expect(hidden.contains(.hongguo, origin: origin))
}
