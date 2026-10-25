import Foundation
import Testing
@testable import TVCore

private let media = "https://cdn.example/video/abcd.m3u8"
private let page = "https://player.example/watch/1"

@Test func sniffRulesRejectExcludedMediaAndAcceptARuleRegex() {
    let excluded = SniffRule(hosts: ["cdn.example"], exclude: [".m3u8"])
    #expect(SniffRules.isVideo(url: media, pageURL: page, detect: true, rules: [excluded]) == false)
    let forced = SniffRule(hosts: ["cdn.example"], regex: ["cdn.example"])
    #expect(SniffRules.isVideo(url: "https://cdn.example/no-extension", pageURL: page, detect: true, rules: [forced]))
}

@Test func sniffRulesUseTVBoxSuffixChecks() {
    #expect(SniffRules.isVideo(url: "https://jx.example/?url=http://cdn.example/a.m3u8", pageURL: page, detect: true, rules: []) == false)
    #expect(SniffRules.isVideo(url: "https://jx.example/?v=http://cdn.example/a.m3u8", pageURL: page, detect: true, rules: []) == false)
    #expect(SniffRules.isVideo(url: "https://site.example/play.html", pageURL: page, detect: true, rules: []) == false)
    #expect(SniffRules.isVideo(url: "https://cdn.example/video/tos/plain", pageURL: page, detect: true, rules: []))
    #expect(SniffRules.isVideo(url: "rtmp://live.example/app/stream", pageURL: page, detect: true, rules: []))
    #expect(SniffRules.isVideo(url: "https://a.co/b.m3u8", pageURL: page, detect: true, rules: []) == false)
    #expect(SniffRules.isVideo(url: media + "?file=play.html", pageURL: page, detect: true, rules: []))
}

@Test func sniffRulesIgnoreThePageItselfWhenDetectIsOff() {
    #expect(SniffRules.isVideo(url: media, pageURL: media, detect: false, rules: []) == false)
    #expect(SniffRules.isVideo(url: media, pageURL: media, detect: true, rules: []))
}

@Test func sniffRulesMatchTheHostInsideTheURLQuery() {
    let rule = SniffRule(hosts: ["cdn.example"], regex: ["cdn.example"])
    let wrapped = "https://jx.example/player?url=https://cdn.example/file"
    #expect(SniffRules.isVideo(url: wrapped, pageURL: page, detect: true, rules: [rule]))
}

@Test func sniffRulesDoNotFollowThePagesOwnAddress() {
    let player = "https://jx.example/player.php?url=https://v.example/1.html"
    #expect(SniffRules.decision(url: player, pageURL: player, detect: true, followedCount: 0, ads: [], rules: []) == .allow)
    #expect(SniffRules.decision(url: player, pageURL: page, detect: true, followedCount: 0, ads: [], rules: []) == .follow)
}

@Test func sniffRulesBlockAdsButNotCloudflareOrLocalDocuments() {
    let ads = ["ads.example"]
    #expect(SniffRules.decision(url: "https://ads.example/a.m3u8", pageURL: page, detect: true, followedCount: 0, ads: ads, rules: []) == .block)
    #expect(SniffRules.decision(url: "not a url", pageURL: page, detect: true, followedCount: 0, ads: ads, rules: []) == .block)
    #expect(SniffRules.decision(url: "about:blank", pageURL: page, detect: true, followedCount: 0, ads: ads, rules: []) == .allow)
    #expect(SniffRules.decision(url: "data:text/plain,hi", pageURL: page, detect: true, followedCount: 0, ads: ["data"], rules: []) == .allow)
    let cloudflare = "https://challenges.cloudflare.com/turnstile/v0"
    #expect(SniffRules.decision(url: cloudflare, pageURL: page, detect: true, followedCount: 0, ads: ["cloudflare"], rules: []) == .allow)
    let broken = SniffRule(exclude: ["("])
    #expect(SniffRules.isVideo(url: media, pageURL: page, detect: true, rules: [broken]))
}

@Test func sniffRulesFollowTheFirstFivePlayerPages() {
    let player = "https://player.example/embed/https://cdn.example/abcd.m3u8"
    #expect(SniffRules.decision(url: player, pageURL: page, detect: true, followedCount: 4, ads: [], rules: []) == .follow)
    #expect(SniffRules.decision(url: player, pageURL: page, detect: true, followedCount: 5, ads: [], rules: []) == .video)
    #expect(SniffRules.decision(url: player, pageURL: page, detect: false, followedCount: 0, ads: [], rules: []) == .video)
}

@Test func sniffPageScriptsPutThePlaybackClickFirst() {
    let rule = SniffRule(hosts: ["player.example"], script: ["rule()"], click: [".close", ".next"])
    #expect(SniffRules.pageScripts(pageURL: page, click: "play()", rules: [rule]) == ["play()", "rule()"])
    #expect(SniffRules.pageScripts(pageURL: page, click: "rule()", rules: [rule]) == ["rule()"])
    #expect(SniffRules.pageClicks(pageURL: page, rules: [rule]) == [".close", ".next"])
    #expect(SniffRules.cloudflareCheck == "Boolean(window._cf_chl_opt && window._cf_chl_opt.cType)")
}
