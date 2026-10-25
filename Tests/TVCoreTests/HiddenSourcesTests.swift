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

@Test @MainActor func onlyACountedFailureThatLeavesTheSourceRedHidesIt() throws {
    let suite = "hidden.note." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hidden = HiddenSources(defaults: defaults)
    let health = SourceHealth(file: nil)
    let site = source("a")
    let now = Date()
    health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
    hidden.note(site, origin: origin, error: Failure(), health: health, now: now)
    #expect(!hidden.contains(site, origin: origin))
    health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
    hidden.note(site, origin: origin, error: Failure(), health: health, now: now)
    #expect(hidden.contains(site, origin: origin))
    hidden.toggle(site, origin: origin)
    health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
    hidden.note(site, origin: origin, error: Failure(), health: health, now: now)
    #expect(hidden.contains(site, origin: origin))
    hidden.toggle(site, origin: origin)
    hidden.note(site, origin: origin, error: CancellationError(), health: health, now: now)
    hidden.note(site, origin: origin, error: TVError.unsupported("The plugin runtime is busy. Wait for the current source."), health: health, now: now)
    #expect(!hidden.contains(site, origin: origin))
    health.record(site, origin: origin, seconds: 1, error: nil, now: now)
    hidden.note(site, origin: origin, error: nil, health: health, now: now)
    #expect(!hidden.contains(site, origin: origin))
    health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
    hidden.note(site, origin: origin, error: Failure(), health: health, now: now)
    #expect(!hidden.contains(site, origin: origin))
    health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
    hidden.note(site, origin: origin, error: Failure(), health: health, now: now)
    #expect(hidden.contains(site, origin: origin))
}

@Test @MainActor func backfillHidesCurrentRedSourcesOnce() throws {
    let suite = "hidden.backfill." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hidden = HiddenSources(defaults: defaults)
    let health = SourceHealth(file: nil)
    let site = source("a")
    let now = Date()
    hidden.backfill([], origin: origin, health: health, now: now)
    #expect(defaults.bool(forKey: "hiddenSources.backfill.v1") == false)
    health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
    health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
    hidden.backfill([site], origin: origin, health: health, now: now)
    #expect(hidden.contains(site, origin: origin))
    hidden.toggle(site, origin: origin)
    hidden.backfill([site], origin: origin, health: health, now: now)
    #expect(!hidden.contains(site, origin: origin))
}

@Test @MainActor func builtInSourcesGoRedWithoutBeingHidden() throws {
    let suite = "hidden.builtin." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let hidden = HiddenSources(defaults: defaults)
    let health = SourceHealth(file: nil)
    let now = Date()
    for site in Site.builtInSites {
        health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
        health.record(site, origin: origin, seconds: 1, error: Failure(), now: now)
        #expect(health.status(site, origin: origin, now: now) == .failing)
        hidden.note(site, origin: origin, error: Failure(), health: health, now: now)
        #expect(!hidden.contains(site, origin: origin))
    }
    hidden.backfill(Site.builtInSites, origin: origin, health: health, now: now)
    #expect(Site.builtInSites.allSatisfy { !hidden.contains($0, origin: origin) })
    hidden.toggle(.hongguo, origin: origin)
    #expect(hidden.contains(.hongguo, origin: origin))
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
