import SwiftUI
import TVCore
import Perception

// The TVBox detail page: a background from the artwork, the cover on the left, the title, tags and
// synopsis on the right, then the line row and the episode grid.
//
// Playback goes through the same path as VideoDetailView: preparePlayback → resolvePlayback →
// store.playing, so the catalog, history, resume position and the queue all behave as before. What
// this file does not re-implement (cloud-drive sign-in, the download picker, the playback source
// chips) still lives in the native page; see Docs/TVBox-Skin.md.

struct TVBoxVideoDetail: View {
    @Environment(Store.self) private var store
    let video: Video
    let client: CatalogClient

    @State private var detail: Video?
    @State private var error: String?
    @State private var busy = false
    @State private var loadingEpisode: Episode.ID?
    @State private var selectedFlag: String?
    @State private var pendingPlan: PlaybackPlan?
    @State private var pendingEpisode: Episode?
    @State private var choosingQuality = false
    @State private var synopsisExpanded = false
    @State private var requestTask: Task<Void, Never>?
    /// A drive that needs a sign-in before its line can play.
    @State private var signingIn: CloudDrive?
    /// Why the last attempt did not play, shown as a card under the hero.
    @State private var issue: TVBoxPlaybackIssue?
    @State private var choosingDownloads = false
    /// How many episodes were just queued, shown briefly beside the buttons.
    @State private var queuedNotice: Int?

    private var shown: Video { detail ?? video }

    private var flags: [String] {
        var seen = Set<String>()
        return shown.episodes.map(\.flag).filter { seen.insert($0).inserted }
    }

    /// The line whose episodes the grid lists: the chosen one, or the source's first.
    private var activeFlag: String {
        if let selectedFlag, flags.contains(selectedFlag) { return selectedFlag }
        return flags.first ?? ""
    }

    private var episodes: [Episode] { shown.episodes.filter { $0.flag == activeFlag } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if let issue { issueCard(issue) }
                if flags.count > 1 { lineBar }
                episodesSection
                if let error { errorCard(error) }
            }
            .frame(maxWidth: TVBoxTheme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TVBoxTheme.gutter)
            .padding(.vertical, 24)
        }
        .background(TVBoxTheme.canvas)
        .task {
            guard detail == nil else { return }
            await load()
        }
        .onDisappear { requestTask?.cancel() }
        .confirmationDialog("选择画质", isPresented: $choosingQuality, titleVisibility: .visible) {
            if let plan = pendingPlan, let episode = pendingEpisode {
                ForEach(plan.choices) { choice in
                    Button(choice.name) {
                        requestTask?.cancel()
                        requestTask = Task { await resolve(plan, choice: choice, episode: episode) }
                    }
                }
            }
        }
        // Sign in where playback failed, then resume the episode that needed the account.
        #if os(macOS)
        .sheet(item: $signingIn) { drive in
            CloudLoginView(provider: drive.provider) { cookie, ticket in
                try await drive.provider.saveLogin(cookie, ticket: ticket)
                retryAfterSignIn()
            }
        }
        #elseif os(iOS)
        .sheet(item: $signingIn) { drive in
            WebSignInView(service: drive.webSignIn, signedIn: retryAfterSignIn) {
                CloudQRLoginView(drive: drive.qrDrive) { retryAfterSignIn() }
            }
        }
        #else
        .fullScreenCover(item: $signingIn) { drive in
            CloudQRLoginView(drive: drive.qrDrive) { retryAfterSignIn() }
        }
        #endif
        .downloadPicker(isPresented: $choosingDownloads) {
            DownloadPicker(video: shown, site: client.site, flag: activeFlag, episodes: episodes) { count in
                guard count > 0 else { return }
                queuedNotice = count
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    if queuedNotice == count { queuedNotice = nil }
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 22) {
            poster
            VStack(alignment: .leading, spacing: 14) {
                Text(shown.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                HStack(spacing: 8) { tags }
                synopsis
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var poster: some View {
        Color.clear
            .frame(width: posterWidth)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { PosterImage(url: shown.poster, headers: shown.posterHeaders) }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TVBoxTheme.hairline)
            }
            .overlay(alignment: .topTrailing) {
                if !shown.remarks.isEmpty {
                    Text(shown.remarks)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(TVBoxTheme.accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(8)
                }
            }
            .frame(width: posterWidth)
    }

    private var posterWidth: CGFloat {
        #if os(tvOS)
        260
        #elseif os(macOS)
        190
        #else
        120
        #endif
    }

    private var tags: some View {
        HStack(spacing: 8) {
            if let year = shown.year, !year.isEmpty { tag(year) }
            if !client.site.name.isEmpty { tag(client.site.name) }
            if episodes.count > 1 { tag("\(episodes.count) 集") }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(TVBoxTheme.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(TVBoxTheme.panel, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    @ViewBuilder private var synopsis: some View {
        if !shown.synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(shown.synopsis)
                    .font(.system(size: 13))
                    .foregroundStyle(TVBoxTheme.secondary)
                    .lineLimit(synopsisExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                Button { synopsisExpanded.toggle() } label: {
                    Text(synopsisExpanded ? "收起" : "展开")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TVBoxTheme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tvbox.detail.synopsis")
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                guard let first = episodes.first ?? shown.episodes.first else { return }
                requestTask?.cancel()
                requestTask = Task { await play(first) }
            } label: {
                Label(busy ? "准备中…" : firstEpisodeTitle, systemImage: "play.fill")
            }
            .buttonStyle(TVBoxChipStyle(selected: true))
            .disabled(busy || shown.episodes.isEmpty)
            .accessibilityIdentifier("tvbox.detail.play")

            Button { choosingDownloads = true } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
            .buttonStyle(TVBoxChipStyle())
            .disabled(episodes.isEmpty)
            .accessibilityIdentifier("tvbox.detail.download")

            favoriteButton

            if queuedNotice != nil {
                Text("已加入 \(queuedNotice ?? 0) 集")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TVBoxTheme.accent)
            }

            if shown.episodes.isEmpty && detail == nil && !busy {
                ProgressView().controlSize(.small).tint(TVBoxTheme.accent)
            }
        }
    }

    /// A failed or blocked attempt: the reason, plus sign-in or retry.
    private func issueCard(_ issue: TVBoxPlaybackIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: issue.drive != nil ? "person.crop.circle.badge.exclamationmark.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(issue.drive != nil ? TVBoxTheme.accent : Brand.amber)
                Text("无法播放 \(issue.episode.name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Text(issue.message)
                .font(.system(size: 12))
                .foregroundStyle(TVBoxTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let drive = issue.drive {
                    Button(drive.signInTitle) { signingIn = drive }
                        .buttonStyle(TVBoxChipStyle(selected: true))
                }
                Button(issue.blockedBeforeRequest ? "仍然尝试" : "重试") {
                    requestTask?.cancel()
                    requestTask = Task { await play(issue.episode, skipAccountCheck: true) }
                }
                .buttonStyle(TVBoxChipStyle(selected: issue.drive == nil))
                Button("关闭") { self.issue = nil }
                    .buttonStyle(TVBoxChipStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVBoxTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TVBoxTheme.hairline)
        }
    }

    private var firstEpisodeTitle: String {
        if let first = episodes.first ?? shown.episodes.first {
            return "播放 \(first.name)"
        }
        return "播放"
    }

    /// The show as Favorites stores it: the same identity the native page saves, so a title saved in
    /// either page shows once.
    private var videoFavorite: FavoriteItem {
        .video(FavoriteVideo(origin: client.origin, site: client.site, video: shown))
    }

    private var favoriteButton: some View {
        let saved = store.favorites.contains(videoFavorite)
        return Button { store.favorites.toggle(videoFavorite) } label: {
            Label(saved ? "已收藏" : "收藏", systemImage: saved ? "heart.fill" : "heart")
        }
        .buttonStyle(TVBoxChipStyle(selected: saved))
        .accessibilityIdentifier("tvbox.detail.favorite")
    }

    // MARK: Lines and episodes

    private var lineBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            TVBoxSectionTitle(text: "线路", count: flags.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(flags, id: \.self) { flag in
                        Button { selectedFlag = flag } label: {
                            Text(flag.isEmpty ? "默认线路" : flag).lineLimit(1)
                        }
                        .buttonStyle(TVBoxChipStyle(selected: activeFlag == flag))
                        .accessibilityIdentifier("tvbox.detail.line." + flag)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TVBoxSectionTitle(text: "选集", count: episodes.isEmpty ? nil : episodes.count)
            if episodes.isEmpty {
                if detail == nil {
                    PosterSkeletonGrid(count: 6)
                } else {
                    Text("这个站点没有返回剧集。")
                        .font(.system(size: 13))
                        .foregroundStyle(TVBoxTheme.secondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: episodeMin), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(episodes) { episode in
                        Button {
                            requestTask?.cancel()
                            requestTask = Task { await play(episode) }
                        } label: {
                            episodeLabel(episode)
                        }
                        .buttonStyle(TVBoxEpisodeStyle(loaded: loadingEpisode == episode.id))
                        .disabled(busy)
                        .accessibilityIdentifier("tvbox.detail.episode." + episode.id)
                    }
                }
            }
        }
    }

    private var episodeMin: CGFloat {
        #if os(tvOS)
        120
        #else
        92
        #endif
    }

    private func episodeLabel(_ episode: Episode) -> some View {
        HStack(spacing: 6) {
            if loadingEpisode == episode.id {
                ProgressView().controlSize(.small).tint(.white)
            }
            Text(episode.name).lineLimit(1)
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("播放失败").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text(error).font(.system(size: 12)).foregroundStyle(TVBoxTheme.secondary).lineLimit(5)
            HStack(spacing: 8) {
                Button("重试") { self.error = nil; requestTask?.cancel(); requestTask = Task { await load() } }
                    .buttonStyle(TVBoxChipStyle(selected: true))
                Button("关闭") { self.error = nil }
                    .buttonStyle(TVBoxChipStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVBoxTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Loading

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            let loaded = try await client.detail(video.id)
            detail = loaded.keepingPoster(video.poster, headers: video.posterHeaders)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            Diagnostics.shared.failure("catalog", "detail \(client.reportContext) id=\(video.id)", error)
            self.error = error.localizedDescription
        }
    }

    private func play(_ episode: Episode, skipAccountCheck: Bool = false) async {
        guard !busy else { return }
        // Cloud-drive lines wait for a sign-in that cannot appear by itself; ask up front instead of
        // letting the plugin time out. `skipAccountCheck` is the viewer saying "try anyway".
        if !skipAccountCheck, let drive = CloudDrive.missingLogin(forFlag: episode.flag) {
            issue = TVBoxPlaybackIssue(episode: episode, message: drive.loginHint, drive: drive, blockedBeforeRequest: true)
            return
        }
        busy = true
        loadingEpisode = episode.id
        error = nil
        issue = nil
        defer { busy = false; if !choosingQuality { loadingEpisode = nil } }
        do {
            let plan = try await client.preparePlayback(episode)
            try Task.checkCancellation()
            guard let choice = plan.choices.first else {
                throw TVError.unsupported("这个站点没有可用的播放线路。")
            }
            if plan.choices.count > 1 {
                pendingPlan = plan
                pendingEpisode = episode
                choosingQuality = true
                return
            }
            let playback = store.subscription.map { client.applying($0) } ?? client
            let resolved = try await playback.resolvePlayback(plan, choice: choice)
            try Task.checkCancellation()
            store.playing = store.catalogChannel(resolved, video: shown, episode: episode, client: playback)
        } catch {
            fail(episode, error)
        }
    }

    private func resolve(_ plan: PlaybackPlan, choice: PlaybackChoice, episode: Episode) async {
        busy = true
        loadingEpisode = episode.id
        defer { busy = false; pendingPlan = nil; pendingEpisode = nil; loadingEpisode = nil }
        do {
            let playback = store.subscription.map { client.applying($0) } ?? client
            let resolved = try await playback.resolvePlayback(plan, choice: choice)
            try Task.checkCancellation()
            store.playing = store.catalogChannel(resolved, video: shown, episode: episode, client: playback)
        } catch {
            fail(episode, error)
        }
    }

    /// Replays the episode that needed an account, once the sign-in sheet closes.
    private func retryAfterSignIn() {
        guard let episode = issue?.episode else { return }
        requestTask?.cancel()
        requestTask = Task { await play(episode) }
    }

    private func fail(_ episode: Episode, _ error: Error) {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        // A drive that needs signing in is expected, not a failure to report.
        if !(error is CloudDriveLoginRequired) {
            Diagnostics.shared.failure("catalog", "play \(client.reportContext) flag=\(episode.flag)", error)
        }
        // Plugins report a missing or expired login in their own words; say what happened and offer
        // the sign-in instead of echoing them.
        if let login = error as? CloudDriveLoginRequired, let drive = CloudDrive(rawValue: login.rawValue) {
            issue = TVBoxPlaybackIssue(episode: episode, message: drive.expiredHint, drive: drive, blockedBeforeRequest: false)
        } else if let drive = CloudDrive(flag: episode.flag), CloudDrive.isLoginFailure(error.localizedDescription) {
            issue = TVBoxPlaybackIssue(episode: episode, message: drive.expiredHint, drive: drive, blockedBeforeRequest: false)
        } else {
            issue = TVBoxPlaybackIssue(episode: episode, message: error.localizedDescription,
                                       drive: CloudDrive.missingLogin(forFlag: episode.flag), blockedBeforeRequest: false)
        }
    }
}

/// Why the TVBox detail page could not start an episode.
private struct TVBoxPlaybackIssue {
    let episode: Episode
    let message: String
    let drive: CloudDrive?
    /// True when playback was not attempted because a required account is missing.
    let blockedBeforeRequest: Bool
}

/// An episode cell: flat panel at rest, blue while it is the one loading, white on focus.
struct TVBoxEpisodeStyle: ButtonStyle {
    var loaded = false
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, loaded: loaded)
    }
    struct Content: View {
        let configuration: ButtonStyleConfiguration
        let loaded: Bool
        // isFocused exists on tvOS and macOS only; a phone has no focus to draw.
        #if os(tvOS)
        @Environment(\.isFocused) private var focused
        #else
        private var focused: Bool { false }
        #endif
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(focused ? Color.black : Color.white.opacity(0.9))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white, lineWidth: focused ? 2 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(enabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.14), value: focused)
        }
        private var fill: Color {
            if focused { return .white }
            return loaded ? TVBoxTheme.accent : TVBoxTheme.panel
        }
    }
}
