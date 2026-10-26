import SwiftUI
import TVCore
import Perception

// TVBox skin: the Android TV-box layout on top of the same catalog engine.
//
// The engine (subscription, sites, spiders, CatalogBrowser, playback) is untouched; this file only
// replaces the chrome: a narrow icon rail on the left, a category wall on the home page, and a
// source browser that is a category column beside a poster grid, in flat black with a blue accent.
//
// Switch: Settings ▸ Interface Style, or the rail's bottom button. Stored under `ui.skin`.

/// Which chrome the app draws.
enum SkinMode: String, CaseIterable, Identifiable, Sendable {
    case native
    case tvbox
    var id: String { rawValue }
    static let storageKey = "ui.skin"
    var title: String {
        switch self {
        case .native: "原生"
        case .tvbox: "TVBox"
        }
    }
    var summary: String {
        switch self {
        case .native: "Apple 风格：侧边栏、玻璃面板、横向卡片行。"
        case .tvbox: "电视盒风格：左侧图标栏、分类墙、海报网格、纯黑底。"
        }
    }
}

/// The scene's root: the skin is chosen here, so every modifier in `TVBoxApp` (tint, tasks,
/// environment objects) keeps applying to either chrome.
struct SkinSwitch: View {
    @AppStorage(SkinMode.storageKey) private var skin = SkinMode.native.rawValue
    var body: some View {
        if skin == SkinMode.tvbox.rawValue { TVBoxRoot() } else { RootView() }
    }
}

// MARK: - Theme

/// Flat dark palette: no glass, no blur, one accent, as on an Android TV box.
enum TVBoxTheme {
    static let canvas = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let rail = Color(red: 0.067, green: 0.071, blue: 0.082)
    static let panel = Color(red: 0.102, green: 0.110, blue: 0.125)
    static let panelRaised = Color(red: 0.145, green: 0.157, blue: 0.176)
    static let accent = Color(red: 0.176, green: 0.408, blue: 0.980)
    static let secondary = Color(white: 0.62)
    static let hairline = Color.white.opacity(0.08)
    /// Rail width on a page with room for labels (iPad, Mac, Apple TV).
    static let railWidth: CGFloat = 92
    /// Rail width on a phone, and in a narrow split: icons only.
    static let railCompactWidth: CGFloat = 56
    static let categoryWidth: CGFloat = 210
    static let contentMaxWidth: CGFloat = 1800

    /// Poster columns: tighter than the Apple layout, which suits a wall of covers.
    #if os(tvOS)
    static let posterMin: CGFloat = 210
    static let gutter: CGFloat = 40
    static let tileMin: CGFloat = 250
    #elseif os(macOS)
    static let posterMin: CGFloat = 150
    static let gutter: CGFloat = 28
    static let tileMin: CGFloat = 230
    #else
    static let posterMin: CGFloat = 88
    static let gutter: CGFloat = 16
    static let tileMin: CGFloat = 140
    #endif

    static var posterColumns: [GridItem] {
        [GridItem(.adaptive(minimum: posterMin), spacing: 16, alignment: .top)]
    }
    static var tileColumns: [GridItem] {
        [GridItem(.adaptive(minimum: tileMin), spacing: 12, alignment: .top)]
    }
}

// MARK: - Root

/// The TVBox shell: icon rail on the left, one page on the right.
///
/// Every iPhone, iPad window, Mac window and Apple TV gets the same shell; only the rail narrows to
/// icons on a compact width, so the layout holds from a 320 pt phone to a 4K television.
struct TVBoxRoot: View {
    @Environment(Store.self) private var store
    @AppStorage(SkinMode.storageKey) private var skin = SkinMode.native.rawValue
    @State private var section: AppSection = .home
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A phone, or an iPad in a narrow split: the rail keeps its icons and drops its labels.
    private var compact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    private var items: [AppSection] { [.home, .sites, .live, .search, .favorites, .history, .settings] }

    var body: some View {
        HStack(spacing: 0) {
            rail
            NavigationStack {
                page.routeDestinations()
            }
            // A different section is a different stack; the pushed pages go with the old one.
            .id(section)
            // A phone keeps the system bar, which is the only way back from a detail pushed here.
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
        }
        .background(TVBoxTheme.canvas)
        .tint(TVBoxTheme.accent)
        // One presentation while anything plays, so an episode switch replaces the channel inside the
        // player instead of dismissing and presenting it again.
        .fullScreenCover(item: Binding(
            get: { store.playing.map(TVBoxPlayerSlot.init) },
            set: { if $0 == nil { store.playing = nil } }
        )) { slot in
            TVBoxPlayer(channel: slot.channel)
        }
        #if os(tvOS)
        .preferredColorScheme(.dark)
        #endif
    }

    private var rail: some View {
        VStack(spacing: 4) {
            AppMark(size: compact ? 24 : 30)
                .padding(.top, compact ? 14 : 22)
                .padding(.bottom, compact ? 8 : 12)
            ForEach(items) { item in
                Button { section = item } label: { railLabel(item) }
                    .buttonStyle(TVBoxRailStyle(selected: section == item, compact: compact))
                    .accessibilityLabel(railTitle(item))
                    .accessibilityAddTraits(section == item ? [.isSelected] : [])
                    .accessibilityIdentifier("tvbox.rail." + item.rawValue)
            }
            Spacer(minLength: 8)
            Button { skin = SkinMode.native.rawValue } label: {
                VStack(spacing: 5) {
                    Image(systemName: "paintbrush.pointed.fill").font(.system(size: 16, weight: .semibold))
                    if !compact {
                        Text("原生").font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                }
                .frame(width: compact ? 44 : 64, height: compact ? 44 : 54)
            }
            .buttonStyle(TVBoxRailStyle(selected: false, compact: compact))
            .accessibilityLabel("切回原生界面")
            .accessibilityIdentifier("tvbox.skin.native")
        }
        .padding(.bottom, compact ? 6 : 14)
        .frame(width: compact ? TVBoxTheme.railCompactWidth : TVBoxTheme.railWidth)
        .frame(maxHeight: .infinity)
        .background(TVBoxTheme.rail)
    }

    private func railLabel(_ item: AppSection) -> some View {
        VStack(spacing: 5) {
            Image(systemName: item.icon).font(.system(size: compact ? 17 : 18, weight: .semibold))
            if !compact {
                Text(railTitle(item)).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
        }
        .frame(width: compact ? 44 : 64, height: compact ? 44 : 54)
    }

    private func railTitle(_ item: AppSection) -> String {
        switch item {
        case .home: "首页"
        case .sites: "影视"
        case .live: "直播"
        case .search: "搜索"
        case .favorites: "收藏"
        case .history: "历史"
        case .settings: "设置"
        default: item.title
        }
    }

    @ViewBuilder private var page: some View {
        switch section {
        case .home: TVBoxHome(section: $section)
        case .sites: TVBoxBrowse(section: $section)
        case .live: LiveView()
        case .search: GlobalSearchView()
        case .favorites: FavoritesView()
        case .history: PlaybackHistoryView()
        case .settings: SettingsView()
        default: TVBoxHome(section: $section)
        }
    }
}

// MARK: - Home: the category wall

/// TVBox's home page: every source as a tile, grouped by subscription.
struct TVBoxHome: View {
    @Environment(Store.self) private var store
    @Binding var section: AppSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                TVBoxPageHeader(title: "首页", subtitle: store.subscriptionName.isEmpty ? nil : store.subscriptionName)
                if let config = store.subscription {
                    let groups = store.sourceGroups(includeHidden: false)
                    if groups.isEmpty {
                        TVBoxNotice(symbol: "square.grid.2x2", title: "订阅里没有可用站点",
                                    message: "这份订阅的站点都需要 Android 插件或脚本引擎。换一份订阅，或在“设置”里再导入一个。")
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                TVBoxSectionTitle(text: group.title, count: group.sites.count)
                                LazyVGrid(columns: TVBoxTheme.tileColumns, spacing: 12) {
                                    ForEach(group.sites) { site in
                                        sourceTile(site, config: config)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    TVBoxNotice(symbol: "antenna.radiowaves.left.and.right", title: "还没有订阅",
                                message: "在“设置”里粘贴一个 TVBox 订阅地址，首页就会按分组列出全部站点。") {
                        Button("去添加订阅") { section = .settings }
                            .buttonStyle(TVBoxChipStyle(selected: true))
                    }
                }
            }
            .frame(maxWidth: TVBoxTheme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TVBoxTheme.gutter)
            .padding(.vertical, 28)
        }
        .background(TVBoxTheme.canvas)
    }

    private func sourceTile(_ site: Site, config: Subscription) -> some View {
        let origin = site.origin(or: config.origin)
        return RouteLink {
            TVBoxCatalog(site: site, origin: origin, jarURL: config.spiderURL, subscription: config)
        } label: {
            TVBoxSiteTile(site: site)
        }
        .buttonStyle(TVBoxTileStyle())
        .contextMenu { PinSourceButton(site: site, origin: config.origin) }
        .accessibilityIdentifier("tvbox.home.site." + site.key)
    }
}

// MARK: - Browse: category column beside a poster grid

/// TVBox's 影视 page: pick a source, then a category, then a title.
struct TVBoxBrowse: View {
    @Environment(Store.self) private var store
    @Binding var section: AppSection
    @State private var selectedKey: String?

    private var sites: [Site] {
        guard let config = store.subscription else { return [] }
        return store.orderedSites(config).filter { $0.canBrowse(jarURL: config.spiderURL) }
    }

    private var selected: Site? {
        if let selectedKey, let match = sites.first(where: { $0.key == selectedKey }) { return match }
        return sites.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let config = store.subscription, let site = selected {
                sourceBar(sites: sites)
                Divider().overlay(TVBoxTheme.hairline)
                TVBoxCatalog(site: site, origin: site.origin(or: config.origin), jarURL: config.spiderURL, subscription: config)
                    .id(site.key)
            } else {
                ScrollView {
                    TVBoxNotice(symbol: "square.stack.3d.up", title: "没有可浏览的站点",
                                message: "导入订阅后，这里会列出每个站点的分类和海报墙。") {
                        Button("去添加订阅") { section = .settings }
                            .buttonStyle(TVBoxChipStyle(selected: true))
                    }
                    .padding(.horizontal, TVBoxTheme.gutter)
                    .padding(.top, 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(TVBoxTheme.canvas)
            }
        }
    }

    private func sourceBar(sites: [Site]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sites) { site in
                    Button { selectedKey = site.key } label: {
                        HStack(spacing: 6) {
                            TVBoxMonogram(name: site.name, size: 20)
                            Text(site.name).lineLimit(1)
                        }
                    }
                    .buttonStyle(TVBoxChipStyle(selected: selected?.key == site.key))
                    .accessibilityIdentifier("tvbox.browse.source." + site.key)
                }
            }
            .padding(.horizontal, TVBoxTheme.gutter)
            .padding(.vertical, 12)
        }
        .background(TVBoxTheme.rail)
    }
}

/// One source's catalog: categories down the left, covers in a grid, a pager at the bottom.
struct TVBoxCatalog: View {
    let site: Site
    let origin: URL
    let jarURL: URL?
    let subscription: Subscription

    @State private var browser = CatalogBrowser()
    @State private var requestTask: Task<Void, Never>?
    /// The chosen value of each filter of the open category, keyed by the filter's `key`.
    @State private var filterValues: [String: String] = [:]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A phone has no room for a category column: the categories become a bar above the grid.
    private var compact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    private var client: CatalogClient {
        CatalogClient(site: site, origin: origin, jarURL: jarURL).applying(subscription)
    }

    var body: some View {
        Group {
            if compact {
                VStack(spacing: 0) {
                    compactCategoryBar
                    Divider().overlay(TVBoxTheme.hairline)
                    posterColumn
                }
            } else {
                HStack(spacing: 0) {
                    categoryColumn
                    Divider().overlay(TVBoxTheme.hairline)
                    posterColumn
                }
            }
        }
        .background(TVBoxTheme.canvas)
        .task {
            guard !browser.loaded else { return }
            await browser.load(.home, client: client)
        }
        .onChange(of: browser.category) { _ in filterValues = [:] }
        .onDisappear { requestTask?.cancel(); browser.cancel() }
    }

    /// The categories as a horizontal bar, for a phone.
    private var compactCategoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { openHome() } label: {
                    Text("推荐").lineLimit(1)
                }
                .buttonStyle(TVBoxChipStyle(selected: browser.query.isEmpty && browser.category.isEmpty))
                ForEach(browser.categories) { item in
                    Button { open(item) } label: {
                        Text(item.name).lineLimit(1)
                    }
                    .buttonStyle(TVBoxChipStyle(selected: browser.query.isEmpty && browser.category == item.id))
                    .accessibilityIdentifier("tvbox.category." + item.id)
                }
            }
            .padding(.horizontal, TVBoxTheme.gutter)
            .padding(.vertical, 10)
        }
        .background(TVBoxTheme.rail)
    }

    // MARK: Categories

    private var categoryColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TVBoxTheme.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                Button { openHome() } label: {
                    Text("推荐").lineLimit(1)
                }
                .buttonStyle(TVBoxCategoryStyle(selected: browser.query.isEmpty && browser.category.isEmpty))
                ForEach(browser.categories) { item in
                    Button { open(item) } label: {
                        Text(item.name).lineLimit(1)
                    }
                    .buttonStyle(TVBoxCategoryStyle(selected: browser.query.isEmpty && browser.category == item.id))
                    .accessibilityIdentifier("tvbox.category." + item.id)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        .frame(width: TVBoxTheme.categoryWidth)
        .background(TVBoxTheme.rail)
    }

    // MARK: Posters

    private var posterColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !activeFilters.isEmpty { filterBar }
                if browser.busy && browser.videos.isEmpty { PosterSkeletonGrid() }
                if let error = browser.error { errorCard(error) }
                LazyVGrid(columns: TVBoxTheme.posterColumns, spacing: 18) {
                    ForEach(browser.videos) { video in
                        RouteLink {
                            TVBoxVideoDetail(video: video, client: client)
                        } label: {
                            TVBoxPosterTile(video: video)
                        }
                        .buttonStyle(TVBoxTileStyle())
                        .accessibilityIdentifier("tvbox.poster." + video.id)
                    }
                }
                .opacity(browser.busy && !browser.videos.isEmpty ? 0.55 : 1)
                .animation(.easeOut(duration: 0.2), value: browser.busy)
                pager
            }
            .frame(maxWidth: TVBoxTheme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TVBoxTheme.gutter)
            .padding(.vertical, 24)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TVBoxSectionTitle(text: currentCategoryName, count: browser.videos.isEmpty ? nil : browser.videos.count)
            if browser.busy { ProgressView().controlSize(.small).tint(TVBoxTheme.accent) }
            Spacer(minLength: 0)
            if browser.pageCount > 1 {
                Text("第 \(browser.page) / \(browser.pageCount) 页")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TVBoxTheme.secondary)
            }
        }
    }

    private var currentCategoryName: String {
        if !browser.query.isEmpty { return "搜索 “\(browser.query)”" }
        if browser.category.isEmpty { return "推荐" }
        return browser.categories.first { $0.id == browser.category }?.name ?? site.name
    }

    /// The second-level filters the open category declares, as TVBox shows them under the category row.
    private var activeFilters: [CatalogFilter] {
        browser.filtersFor(browser.category)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(activeFilters) { filter in
                HStack(alignment: .center, spacing: 10) {
                    Text(filter.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TVBoxTheme.secondary)
                        .frame(width: 64, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filter.options) { option in
                                Button {
                                    filterValues[filter.key] = option.value
                                    loadFiltered()
                                } label: {
                                    Text(option.name).lineLimit(1)
                                }
                                .buttonStyle(TVBoxChipStyle(selected: filterValues[filter.key, default: ""] == option.value))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var pager: some View {
        if browser.pageCount > 1 {
            HStack(spacing: 10) {
                Button { load(page: browser.page - 1) } label: { Label("上一页", systemImage: "chevron.left") }
                    .buttonStyle(TVBoxChipStyle())
                    .disabled(browser.page <= 1 || browser.busy)
                Button { load(page: browser.page + 1) } label: { Label("下一页", systemImage: "chevron.right") }
                    .buttonStyle(TVBoxChipStyle())
                    .disabled(browser.page >= browser.pageCount || browser.busy)
            }
            .padding(.top, 12)
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这个站点没有响应").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text(error).font(.system(size: 12)).foregroundStyle(TVBoxTheme.secondary).lineLimit(4)
            Button { openHome() } label: { Text("重试") }
                .buttonStyle(TVBoxChipStyle(selected: true))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVBoxTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Loading

    private func openHome() {
        filterValues = [:]
        requestTask?.cancel()
        requestTask = Task { await browser.load(.home, client: client) }
    }

    private func open(_ category: Category) {
        filterValues = [:]
        requestTask?.cancel()
        requestTask = Task { await browser.load(.list(category: category.id, query: "", page: 1), client: client) }
    }

    /// The selection as the `extend` JSON a TVBox source expects: {"area":"大陆","year":"2024"}.
    private var selectedFilters: String? {
        CatalogFilters.extend(filterValues.filter { !$0.value.isEmpty })
    }

    private func loadFiltered() {
        requestTask?.cancel()
        let request = CatalogBrowser.Request.list(
            category: browser.category.isEmpty ? nil : browser.category,
            query: browser.query,
            page: 1
        )
        let extend = selectedFilters
        requestTask = Task { await browser.load(request, client: client, extend: extend) }
    }

    private func load(page: Int) {
        requestTask?.cancel()
        let request = CatalogBrowser.Request.list(
            category: browser.category.isEmpty ? nil : browser.category,
            query: browser.query,
            page: page
        )
        let extend = selectedFilters
        requestTask = Task { await browser.load(request, client: client, extend: extend) }
    }
}

// MARK: - Tiles

/// A source on the home wall: monogram, name, and its engine/compatibility line.
struct TVBoxSiteTile: View {
    let site: Site

    var body: some View {
        HStack(spacing: 10) {
            TVBoxMonogram(name: site.name, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(site.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(site.compatibility)
                    .font(.system(size: 11))
                    .foregroundStyle(TVBoxTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TVBoxTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TVBoxTheme.hairline)
        }
    }
}

/// A cover in the grid: 2:3 artwork, the source's remarks as a corner tag, the title under it.
struct TVBoxPosterTile: View {
    let name: String
    let poster: URL?
    let headers: [String: String]
    let remarks: String
    let year: String?

    init(video: Video) {
        name = video.name
        poster = video.poster
        headers = video.posterHeaders
        remarks = video.remarks
        year = video.year
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { PosterImage(url: poster, headers: headers) }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if !remarks.isEmpty {
                        Text(remarks)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(TVBoxTheme.accent.opacity(0.92), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .padding(6)
                    }
                }
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
            if let year, !year.isEmpty {
                Text(year)
                    .font(.system(size: 11))
                    .foregroundStyle(TVBoxTheme.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The first character as an icon: a source name's leading emoji is already artwork.
struct TVBoxMonogram: View {
    let name: String
    var size: CGFloat = 40
    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }
    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [TVBoxTheme.accent.opacity(0.9), TVBoxTheme.accent.opacity(0.42)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
    }
}

// MARK: - Headers and notices

struct TVBoxPageHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(TVBoxTheme.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TVBoxSectionTitle: View {
    let text: String
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(TVBoxTheme.accent)
                .frame(width: 3, height: 15)
            Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let count {
                Text("\(count)").font(.system(size: 12, weight: .medium)).foregroundStyle(TVBoxTheme.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct TVBoxNotice<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(TVBoxTheme.accent)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(TVBoxTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions.padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 620, alignment: .leading)
        .background(TVBoxTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension TVBoxNotice where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Styles

/// Rail item: grey at rest, blue while selected, white while focused.
struct TVBoxRailStyle: ButtonStyle {
    let selected: Bool
    /// Icons only on a phone: a tighter radius keeps the blue plate inside the narrow rail.
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, selected: selected, compact: compact)
    }
    private struct Body: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let compact: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            let radius: CGFloat = compact ? 8 : 10
            configuration.label
                .foregroundStyle(focused ? Color.white : (selected ? Color.white : TVBoxTheme.secondary))
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(focused ? TVBoxTheme.accent : (selected ? TVBoxTheme.panelRaised : Color.clear))
                }
                .overlay(alignment: .leading) {
                    if selected && !focused {
                        Capsule().fill(TVBoxTheme.accent).frame(width: 3, height: compact ? 18 : 22)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .animation(.easeOut(duration: 0.14), value: focused)
        }
    }
}

/// Category row in the left column of a source page.
struct TVBoxCategoryStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, selected: selected)
    }
    private struct Body: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(focused ? Color.black : (selected ? Color.white : TVBoxTheme.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(focused ? Color.white : (selected ? TVBoxTheme.panelRaised : Color.clear))
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(.easeOut(duration: 0.14), value: focused)
        }
    }
}

/// A chip or a small button: flat panel at rest, blue when selected, white on focus.
struct TVBoxChipStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, selected: selected)
    }
    private struct Body: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(focused ? Color.black : (selected ? Color.white : Color.white.opacity(0.74)))
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white, lineWidth: focused ? 2 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(enabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.14), value: focused)
        }
        private var fill: Color {
            if focused { return .white }
            return selected ? TVBoxTheme.accent : TVBoxTheme.panel
        }
    }
}

/// A card: the focused one lifts and takes a white edge, as a remote moves over the grid.
struct TVBoxTileStyle: ButtonStyle {
    var corner: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        Body(configuration: configuration, corner: corner)
    }
    private struct Body: View {
        let configuration: ButtonStyleConfiguration
        let corner: CGFloat
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.white, lineWidth: focused ? 3 : 0)
                }
                .scaleEffect(configuration.isPressed ? 0.97 : (focused ? 1.05 : 1))
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 22, y: 12)
                .animation(.easeOut(duration: 0.16), value: focused)
        }
    }
}
