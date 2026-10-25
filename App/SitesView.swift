import SwiftUI
import TVCore

struct SitesView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    /// A group is open only when its id is here, so a group that shows up later starts folded.
    /// Reset with the page, not with a pushed source: the state lives here and `prepared` keeps the default fold to once per visit.
    @State private var expanded: Set<String> = Self.defaultExpanded
    @State private var prepared = false
    private static let defaultExpanded: Set<String> = ["pinned", "builtIn"]
    /// The fold as it was when a search began; restored when the search is cleared.
    @State private var foldBeforeSearch: Set<String>?
    @State private var arranging = false
    var body: some View {
        Group {
            if let config = store.subscription {
                let groups = store.sourceGroups(includeHidden: false).filtered(by: query)
                let sites = store.orderedSites(config)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Layout.cardSpacing) {
                        if query.isEmpty && sites.count > 1 {
                            SourceOrderCard(sites: sites) { arranging = true }.tvFocusSection()
                        }
                        ForEach(groups) { group in
                            groupHeader(group)
                            if expanded.contains(group.id) {
                                LazyVGrid(columns: Layout.cardColumns, spacing: Layout.cardSpacing) {
                                    ForEach(group.sites) { site in
                                        RouteLink { SiteView(site: site, origin: config.origin, jarURL: config.spiderURL) } label: { SiteCard(site: site, dimmed: group.kind == .hidden) }.tileButton()
                                            .contextMenu {
                                                PinSourceButton(site: site, origin: config.origin)
                                                HideSourceButton(site: site, origin: config.origin)
                                                if store.sourceOrder.enabled { MoveSourceButtons(site: site, sites: sites) }
                                            }
                                    }
                                }
                                // Unfolds from under its header; folding only fades, as the groups below slide up.
                                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -16)), removal: .opacity))
                            }
                        }
                    }.pageContainer()
                }
                .sheet(isPresented: $arranging) { SourceOrderEditor(sites: sites, automatic: store.automaticSites(config)) }
                #if DEBUG
                // `-qaArrangeSources 1` opens the editor for screenshots.
                .task {
                    guard UserDefaults.standard.bool(forKey: "qaArrangeSources") else { return }
                    store.setCustomSourceOrder(true)
                    // Let launch settle first: on tvOS a sheet asked for straight away never appeared.
                    try? await Task.sleep(for: .seconds(2))
                    arranging = true
                }
                #endif
            } else { ContentUnavailableView(L10n.text("No Sources Yet"), systemImage: "square.grid.2x2", description: Text(L10n.text("Add a TVBox subscription in Settings."))) }
        }
        .screenBackdrop()
        .catalogSearchable(text: $query, prompt: L10n.text("Find a source")).tabTitle(L10n.text("Sources"))
        .task(id: store.section) {
            if store.section == .sites && !prepared {
                applyDefaultFold()
                prepared = true
            }
        }
        .onChange(of: store.section) { _, new in
            if new != .sites { prepared = false }
        }
        .onChange(of: query) { old, new in
            if old.isEmpty && !new.isEmpty {
                foldBeforeSearch = expanded
                expanded.formUnion(store.sourceGroups(includeHidden: false).map(\.id))
            } else if !old.isEmpty && new.isEmpty, let saved = foldBeforeSearch {
                expanded = saved
                foldBeforeSearch = nil
            }
        }
    }

    @ViewBuilder
    private func groupHeader(_ group: SourceGroup) -> some View {
        let open = expanded.contains(group.id)
        let header = Button {
            withAnimation(.snappy(duration: 0.3)) {
                if open { expanded.remove(group.id) } else { expanded.insert(group.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(L10n.text(group.title)).font(.headline).lineLimit(1)
                Text("\(group.sites.count)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                Spacer(minLength: 8)
                // One chevron that turns, rather than two symbols swapped.
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("sources.group." + group.id)
        #if !os(tvOS)
        if case .subscription = group.kind, query.isEmpty {
            header
                .draggable(group.id)
                .dropDestination(for: String.self) { items, _ in
                    guard query.isEmpty, let address = items.first else { return false }
                    store.moveSourceGroup(address, onto: group.id, includeHidden: false)
                    return true
                }
        } else {
            header
        }
        #else
        header
        #endif
    }

    /// The default view of the page: subscription groups and hidden sources folded.
    private func applyDefaultFold() {
        expanded = Self.defaultExpanded
        foldBeforeSearch = nil
    }
}

private extension Array where Element == SourceGroup {
    /// Sites whose name contains the query, ignoring case; groups left empty drop out.
    func filtered(by query: String) -> [SourceGroup] {
        guard !query.isEmpty else { return self }
        return compactMap { group in
            var kept = group
            kept.sites = group.sites.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return kept.sites.isEmpty ? nil : kept
        }
    }
}

extension Store {
    /// How a source has been answering lately; see `SourceHealth`.
    func health(of site: Site) -> SourceHealth.Status {
        subscription.map { SourceHealth.shared.status(site, origin: $0.origin) } ?? .unknown
    }
}

extension SourceHealth.Status {
    /// The dot that marks it; none until the source has been asked.
    var tint: Color? {
        switch self {
        case .unknown: nil
        case .healthy: .green
        case .unstable: Brand.amber
        case .failing: Brand.rose
        }
    }
    /// Only trouble: in search results every listed source has just answered.
    var warning: Color? { self == .unstable || self == .failing ? tint : nil }
    var summary: String {
        switch self {
        case .unknown: ""
        case .healthy: L10n.text("Responding normally")
        case .unstable: L10n.text("Slow or unreliable lately")
        case .failing: L10n.text("Failing; searched last for now")
        }
    }
}

/// A source's health as a dot beside its name.
struct SourceHealthDot: View {
    let status: SourceHealth.Status
    #if os(tvOS)
    private let size: CGFloat = 14
    #else
    private let size: CGFloat = 8
    #endif
    var body: some View {
        if let tint = status.tint {
            Image(systemName: "circle.fill").font(.system(size: size)).foregroundStyle(tint).accessibilityLabel(status.summary)
        }
    }
}

/// A source as an app-icon tile plus its name: the name's emoji becomes the icon, its taglines
/// ("不卡", "秒播") and engine a quiet second line, so a page of sources reads like a launcher
/// rather than a wall of identical badges. Use with `tileButton()`: on tvOS the card lights up itself.
struct SiteCard: View {
    @Environment(Store.self) private var store
    @Environment(\.isFocused) private var isFocused
    let site: Site
    /// A source the viewer hid, shown only while hidden sources are revealed.
    var dimmed = false
    #if os(tvOS)
    private var focused: Bool { isFocused }
    private let icon: CGFloat = 88, padding: CGFloat = 20, radius: CGFloat = 28
    #else
    private let icon: CGFloat = 48, padding: CGFloat = 12, radius: CGFloat = 16
    // Keyboard focus on the Mac must not turn the text black on a dark panel.
    private let focused = false
    #endif
    var body: some View {
        let label = SourceLabel(site.name)
        let pinned = store.subscription.map { store.pinnedSources.contains(site, origin: $0.origin) } ?? false
        let runs = site.isBuiltIn || site.canBrowse(jarURL: store.subscription?.spiderURL)
        let detail = runs ? (label.parts.dropFirst() + [engine].compactMap { $0 }).joined(separator: " · ") : site.compatibility
        HStack(spacing: padding) {
            SourceIcon(site: site, label: label, size: icon)
                .opacity(runs ? 1 : 0.45)
                // A badge on the icon, not another line, so pinned cards keep the grid's height.
                .overlay(alignment: .bottomTrailing) {
                    if pinned {
                        Image(systemName: "pin.fill").font(.system(size: icon * 0.18, weight: .bold)).foregroundStyle(Brand.onAccent)
                            .frame(width: icon * 0.36, height: icon * 0.36).background(Brand.accent, in: Circle())
                            .overlay { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1) }
                            .offset(x: icon * 0.1, y: icon * 0.1)
                            .accessibilityLabel(L10n.text("Pinned"))
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label.parts[0]).font(.headline).lineLimit(1)
                        .foregroundStyle(focused ? Color.black : runs ? Color.primary : Color.secondary)
                    if runs { SourceHealthDot(status: store.health(of: site)) }
                    if dimmed { Text(L10n.text("Hidden")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                if !detail.isEmpty {
                    Text(detail).font(.subheadline).lineLimit(1)
                        .foregroundStyle(focused ? Color.black.opacity(0.6) : runs ? Color.secondary : Brand.amber)
                }
            }
            Spacer(minLength: 0)
            #if !os(tvOS)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            #endif
        }
        .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
        .background { TileSurface(focused: focused, radius: radius) }
        .accessibilityElement(children: .combine)
        .opacity(dimmed ? 0.45 : 1)
    }

    /// Which engine runs a source is an implementation detail; only built-in sources say so.
    private var engine: String? { site.isBuiltIn ? L10n.text("Built-in") : nil }
}

/// A launcher tile's own surface (source cards, live playlists).
struct TileSurface: View {
    var focused: Bool
    var radius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if os(tvOS)
        // Like the system's focused buttons: a quiet tile at rest, a bright plate under focus.
        shape.fill(focused ? Color.white : Color.white.opacity(0.07))
            .overlay { shape.strokeBorder(.white.opacity(focused ? 0 : 0.06), lineWidth: 1) }
        #else
        Color.clear.contentPanel(cornerRadius: radius)
        #endif
    }
}

/// A source's icon: Bilibili's own mark, otherwise a `MonogramIcon`.
struct SourceIcon: View {
    let site: Site
    let label: SourceLabel
    var size: CGFloat
    var body: some View {
        if site.isBilibili { BilibiliMark(size: size) } else {
            MonogramIcon(seed: site.name, label: label, size: size, systemImage: site.key == Hongguo.siteKey ? "play.rectangle.fill" : nil)
        }
    }
}

/// The emoji a name starts with (or its first character, or a symbol) on a tile whose colour is
/// derived from the name, so neighbours differ.
struct MonogramIcon: View {
    let seed: String
    let label: SourceLabel
    var size: CGFloat
    var systemImage: String?
    private static let tints: [Color] = [
        Brand.indigo, Brand.amber, Brand.rose,
        Color(red: 0.30, green: 0.66, blue: 0.60), Color(red: 0.42, green: 0.56, blue: 0.92),
        Color(red: 0.62, green: 0.48, blue: 0.88), Color(red: 0.52, green: 0.72, blue: 0.38),
    ]
    var body: some View {
        // A stable hash: `hashValue` changes every launch.
        let tint = Self.tints[seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Self.tints.count]
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Group {
            if let systemImage {
                // Sized by frame rather than font: font-sized symbols sit off-center (baseline/ascent padding) before macOS 26.
                Image(systemName: systemImage).resizable().scaledToFit().fontWeight(.semibold)
                    .frame(width: size * 0.46, height: size * 0.46).foregroundStyle(.white)
            } else if let symbol = label.symbol {
                Text(symbol).font(.system(size: size * 0.5))
            } else {
                Text(String(label.parts[0].prefix(1)).uppercased()).font(.system(size: size * 0.44, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .background(LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
        .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

struct PinSourceButton: View {
    @Environment(Store.self) private var store
    let site: Site
    let origin: URL
    var body: some View {
        let pinned = store.pinnedSources.contains(site, origin: origin)
        Button { store.pinnedSources.toggle(site, origin: origin) } label: {
            Label(L10n.text(pinned ? "Unpin source" : "Pin source"), systemImage: pinned ? "pin.slash" : "pin")
        }.accessibilityIdentifier("source.pin." + site.key)
    }
}

struct HideSourceButton: View {
    @Environment(Store.self) private var store
    let site: Site
    let origin: URL
    var body: some View {
        let hidden = store.hiddenSources.contains(site, origin: origin)
        Button { store.hiddenSources.toggle(site, origin: origin) } label: {
            Label(L10n.text(hidden ? "Unhide Source" : "Hide Source"), systemImage: hidden ? "eye" : "eye.slash")
        }.accessibilityIdentifier("source.hide." + site.key)
    }
}

/// Context-menu moves within the viewer's own source order.
struct MoveSourceButtons: View {
    @Environment(Store.self) private var store
    let site: Site
    let sites: [Site]
    var body: some View {
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            if index > 0 {
                Button { store.moveSource(site, to: 0) } label: { Label(L10n.text("Move to Top"), systemImage: "arrow.up.to.line") }
            }
            if index < sites.count - 1 {
                Button { store.moveSource(site, to: sites.count) } label: { Label(L10n.text("Move to Bottom"), systemImage: "arrow.down.to.line") }
            }
        }
    }
}

/// The Sources page's header: the switch for the viewer's own order (`SourceOrder`), the top of
/// that order at a glance, and the way into arranging it.
struct SourceOrderCard: View {
    @Environment(Store.self) private var store
    let sites: [Site]
    let arrange: () -> Void
    private var enabled: Binding<Bool> {
        Binding { store.sourceOrder.enabled } set: { on in withAnimation(.smooth) { store.setCustomSourceOrder(on) } }
    }
    private var detail: String {
        L10n.text(store.sourceOrder.enabled ? "Sources at the top are searched first, and their results are listed first."
                                            : "Yingxia searches quick, reliable sources first.")
    }
    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 8) {
            TVSettingsToggle(title: L10n.text("Custom Search Order"), detail: detail, isOn: enabled)
                .accessibilityIdentifier("sources.order.toggle")
            if store.sourceOrder.enabled {
                Button(action: arrange) {
                    TVSettingsRowLabel(title: L10n.text("Arrange Sources"), chevron: true) { SourceOrderPreview(sites: sites) }
                }
                .glassRow()
                .accessibilityIdentifier("sources.order.arrange")
            }
        }
        #else
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconTile(symbol: "arrow.up.arrow.down", tint: Brand.indigo, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("Custom Search Order")).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(L10n.text("Custom Search Order"), isOn: enabled).labelsHidden().toggleStyle(.switch).settingsSwitch()
                    .accessibilityIdentifier("sources.order.toggle")
            }
            if store.sourceOrder.enabled {
                Divider()
                HStack(spacing: 12) {
                    // As many icons as fit beside the button.
                    ViewThatFits(in: .horizontal) {
                        SourceOrderPreview(sites: sites, limit: 5)
                        SourceOrderPreview(sites: sites, limit: 4)
                        SourceOrderPreview(sites: sites, limit: 3)
                    }
                    Spacer(minLength: 8)
                    Button(action: arrange) {
                        Label(L10n.text("Arrange"), systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.onAccent)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Brand.accent, in: Capsule())
                    }
                    .buttonStyle(LiftButtonStyle())
                    .accessibilityIdentifier("sources.order.arrange")
                }
            }
        }
        .padding(16)
        .contentPanel(cornerRadius: 22)
        #endif
    }
}

/// The first sources of an order, as numbered icons.
struct SourceOrderPreview: View {
    let sites: [Site]
    var limit = 5
    #if os(tvOS)
    private let size: CGFloat = 44
    #else
    private let size: CGFloat = 30
    #endif
    var body: some View {
        let shown = Array(sites.prefix(limit))
        HStack(spacing: size * 0.32) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, site in
                SourceIcon(site: site, label: SourceLabel(site.name), size: size)
                    .overlay(alignment: .topLeading) {
                        SourceRankBadge(rank: index + 1, size: size * 0.52).offset(x: -size * 0.18, y: -size * 0.18)
                    }
            }
            if sites.count > shown.count {
                Text(verbatim: "+\(sites.count - shown.count)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        // Room for the badges that stick out.
        .padding(.top, size * 0.18).padding(.leading, size * 0.18)
        .accessibilityHidden(true)
    }
}

struct SourceRankBadge: View {
    let rank: Int
    var size: CGFloat
    var body: some View {
        Text(rank, format: .number).font(.system(size: size * 0.62, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(Brand.onAccent)
            .padding(.horizontal, size * 0.2)
            .frame(minWidth: size, minHeight: size)
            .background(Brand.accent, in: Capsule())
            .overlay { Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 1) }
    }
}

/// One source in the order editor: its place, icon, name and health.
private struct SourceOrderRow: View {
    @Environment(Store.self) private var store
    let site: Site
    let rank: Int
    #if os(tvOS)
    private let icon: CGFloat = 56, rankWidth: CGFloat = 44
    private let title = Font.system(size: 29, weight: .medium), caption = Font.system(size: 22)
    #else
    private let icon: CGFloat = 32, rankWidth: CGFloat = 26
    private let title = Font.body.weight(.medium), caption = Font.caption
    #endif
    var body: some View {
        let label = SourceLabel(site.name)
        let detail = (label.parts.dropFirst() + [site.isBuiltIn ? L10n.text("Built-in") : nil].compactMap { $0 }).joined(separator: " · ")
        HStack(spacing: 12) {
            Text(rank, format: .number).font(caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(rank <= 3 ? Color.primary : Color.secondary)
                .frame(minWidth: rankWidth, alignment: .trailing)
            SourceIcon(site: site, label: label, size: icon)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(label.parts[0]).font(title).lineLimit(1)
                    SourceHealthDot(status: store.health(of: site))
                }
                if !detail.isEmpty { Text(detail).font(caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            #if os(macOS)
            // macOS lists draw no handle of their own; any part of the row drags.
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            #endif
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// The viewer's source order as a list to drag into place. tvOS has no dragging: there, choose a
/// source, then where it goes; each move is saved at once.
struct SourceOrderEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sites: [Site]
    /// What Reset goes back to.
    private let automatic: [Site]
    #if os(tvOS)
    @State private var moving: Site?
    #endif

    init(sites: [Site], automatic: [Site]) {
        _sites = State(initialValue: sites)
        self.automatic = automatic
    }

    private var isAutomatic: Bool { sites.map(\.id) == automatic.map(\.id) }

    private func save() {
        if let config = store.subscription { store.sourceOrder.save(sites, origin: config.origin) }
    }

    var body: some View {
        #if os(tvOS)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Choose a source to move it. Sources at the top are searched first, and their results are listed first."))
                        .font(.system(size: 24)).foregroundStyle(.secondary).padding(.bottom, 12)
                    ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                        Button { moving = site } label: { SourceOrderRow(site: site, rank: index + 1).frame(maxWidth: .infinity) }
                            .glassRow()
                            .accessibilityIdentifier("sources.order.row." + site.key)
                    }
                    TVSettingsAction(title: L10n.text("Reset"), destructive: true) {
                        withAnimation(.smooth) { sites = automatic }
                        save()
                    }
                    .disabled(isAutomatic)
                    .padding(.top, 16)
                }
                .glassRowInsets()
            }
            .screenTitle(L10n.text("Arrange Sources"))
            .screenBackdrop()
            .confirmationDialog(moving.map { SourceLabel($0.name).parts[0] } ?? "",
                                isPresented: Binding { moving != nil } set: { if !$0 { moving = nil } },
                                titleVisibility: .visible, presenting: moving) { site in
                let index = sites.firstIndex { $0.id == site.id } ?? 0
                if index > 0 {
                    Button(L10n.text("Move to Top")) { move(site, to: 0) }
                    Button(L10n.text("Move Up")) { move(site, to: index - 1) }
                }
                if index < sites.count - 1 {
                    Button(L10n.text("Move Down")) { move(site, to: index + 2) }
                    Button(L10n.text("Move to Bottom")) { move(site, to: sites.count) }
                }
            }
        }
        .frame(width: 1100, height: 800)
        .onExitCommand { dismiss() }
        #else
        NavigationStack {
            List {
                Section {
                    ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                        SourceOrderRow(site: site, rank: index + 1)
                            #if os(iOS)
                            .listRowBackground(Surface())
                            #endif
                            .accessibilityIdentifier("sources.order.row." + site.key)
                    }
                    .onMove { sites.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text(L10n.text("Drag sources to reorder them. Sources at the top are searched first, and their results are listed first."))
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background { Backdrop() }
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(L10n.text("Arrange Sources"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Done")) { save(); dismiss() }.fontWeight(.semibold)
                        .accessibilityIdentifier("sources.order.done")
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Button(L10n.text("Reset")) { withAnimation(.smooth) { sites = automatic } }.disabled(isAutomatic)
                }
                #else
                ToolbarItem(placement: .destructiveAction) {
                    Button(L10n.text("Reset")) { withAnimation(.smooth) { sites = automatic } }.disabled(isAutomatic)
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 600)
        #endif
        #endif
    }

    #if os(tvOS)
    private func move(_ site: Site, to offset: Int) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }) else { return }
        withAnimation(.smooth) { sites.move(fromOffsets: [index], toOffset: offset) }
        save()
    }
    #endif
}

struct SiteView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let site: Site
    let origin: URL
    let jarURL: URL?
    var initialQuery: String = ""
    private var canLoad: Bool { site.canBrowse(jarURL: jarURL) }
    private var isIndex: Bool { (site.raw["indexs"]?.int ?? 0) == 1 }
    @State private var browser = CatalogBrowser()
    @State private var query = ""
    /// The Bilibili login this page loaded with; signing in or out reloads it with the account's lists.
    @State private var bilibiliLogin = BilibiliAccount.load().cookie
    private var initialLoading: Bool { browser.videos.isEmpty && browser.error == nil && (browser.busy || !browser.loaded) }
    private var client: CatalogClient { CatalogClient(site: site, origin: origin, jarURL: jarURL) }
    @State private var requestTask: Task<Void, Never>?

    private func startRequest(_ operation: @escaping @MainActor () async -> Void) {
        requestTask?.cancel()
        requestTask = Task {
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    var body: some View {
        Group {
            if !canLoad {
                ContentUnavailableView {
                    Label(site.compatibility, systemImage: "puzzlepiece.extension")
                } description: {
                    if site.type != 3 {
                        Text(L10n.text("This source format is not supported. Choose another source."))
                    } else {
                        Text(site.runtime == .jar ? L10n.text("This source uses a plugin that requires Android DEX and native libraries. This platform does not yet have the required compatibility layer.\n\n%@", site.api)
                             : site.runtime == .python ? L10n.text("This source requires a Python runtime, which is not available on this platform.")
                             : L10n.text("This source requires a JavaScript engine, which is not supported yet."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(tvOS)
                .focusable()
                .onExitCommand { dismiss() }
                #endif
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        #if os(tvOS)
                        // The remote's keyboard has no return key, so typing only edits the query; as in
                        // the Search tab, a focusable button below the keyboard runs the search.
                        let pending = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !pending.isEmpty, pending != browser.query {
                            SearchQueryButton(query: pending) { startRequest { await search() } }
                                .accessibilityIdentifier("site.search.submit")
                        }
                        #endif
                        if site.isBilibili && !BilibiliAccount.load().signedIn { BilibiliSignInBanner() }
                        if !browser.categories.isEmpty { categoryBar } else if initialLoading { ChipSkeletonRow() }
                        if isIndex && !browser.videos.isEmpty {
                            Text(L10n.text("Choose a title to find it across your sources.")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if browser.busy {
                            LoadingCard { .source(site, origin: origin, title: L10n.text("Loading source content…")) }
                        }
                        if initialLoading { PosterSkeletonGrid().loadingFocus { dismiss() } }
                        if let error = browser.error {
                            ErrorStateCard(
                                title: L10n.text("Unable to load this source"),
                                message: L10n.text("Try again, or choose another source to keep watching."),
                                details: error,
                                retry: { startRequest { await browser.load(browser.request, client: client) } },
                                goBack: { dismiss() },
                                busy: browser.busy
                            )
                            .padding(.vertical, browser.videos.isEmpty ? 24 : 8)
                        }
                        if browser.videos.isEmpty && browser.loaded && !browser.busy && browser.error == nil { ContentUnavailableView(L10n.text("No Videos"), systemImage: "film", description: Text(L10n.text("Try selecting a category or searching."))).frame(maxWidth: .infinity) }
                        LazyVGrid(columns: Layout.posterColumns, spacing: Layout.gridRowSpacing) {
                            ForEach(browser.videos) { video in
                                // An index source (a ranking or list site) names titles; other sources play them.
                                if isIndex {
                                    Button { store.searchVideos(video.name) } label: { PosterCard(video: video) }.cardButton()
                                } else {
                                    RouteLink { VideoDetailView(video: video, client: client) } label: { PosterCard(video: video) }.cardButton()
                                }
                            }
                        }
                        .opacity(browser.busy && !browser.videos.isEmpty ? 0.55 : 1).animation(.smooth, value: browser.busy)
                    }.pageContainer()
                }
                .safeAreaInset(edge: .bottom) { if browser.pageCount > 1 { pager } }
                .catalogSearchable(text: Binding(get: { query }, set: { value in
                    query = value
                    if value.isEmpty && !browser.query.isEmpty { startRequest { await home() } }
                }), prompt: L10n.text("Search videos"))
                .onSubmit(of: .search) { startRequest { await search() } }
            }
        }
        .onDisappear { requestTask?.cancel(); browser.cancel() }
        .toolbar {
            PinSourceButton(site: site, origin: origin)
            HideSourceButton(site: site, origin: origin)
        }
        .screenBackdrop()
        .onAppear {
            guard site.isBilibili, browser.loaded else { return }
            let login = BilibiliAccount.load().cookie
            if login != bilibiliLogin { bilibiliLogin = login; query = ""; startRequest { await home(); await browser.loadCategories(client: client) } }
        }
        .screenTitle(site.name).task {
            store.searchModel.suspend()
            if canLoad && !browser.loaded {
                if browser.request != .home {
                    await browser.load(browser.request, client: client)
                } else if initialQuery.isEmpty {
                    await home()
                    #if DEBUG
                    // `-qaCategory <type id>` opens that category, for screenshots.
                    if let category = UserDefaults.standard.string(forKey: "qaCategory") {
                        await browser.load(.list(category: category, query: "", page: 1), client: client)
                    }
                    // `-qaSearchDraft <text>` types a query without running it, for the remote's Search button.
                    if let draft = UserDefaults.standard.string(forKey: "qaSearchDraft") { query = draft }
                    #endif
                }
                else { query = initialQuery; await search(); await browser.loadCategories(client: client) }
            }
        }
    }
    private var categoryBar: some View {
        ChipRow {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Chip(title: L10n.text("Recommendations"), selected: browser.query.isEmpty && browser.category.isEmpty) { query = ""; startRequest { await home() } }
                    ForEach(browser.categories) { item in
                        Chip(title: item.name, selected: browser.query.isEmpty && browser.category == item.id) {
                            query = ""
                            startRequest { await browser.load(.list(category: item.id, query: "", page: 1), client: client) }
                        }
                    }
                }
            }.padding(.vertical, 4)
        }
    }
    private var pager: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button { startRequest { await load(page: browser.page - 1) } } label: { Image(systemName: "chevron.left").frame(width: 22) }
                    .controlButton().disabled(browser.page <= 1 || browser.busy).accessibilityLabel(L10n.text("Previous"))
                Text(L10n.text("Page %lld of %lld", browser.page, browser.pageCount)).font(.subheadline.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                Button { startRequest { await load(page: browser.page + 1) } } label: { Image(systemName: "chevron.right").frame(width: 22) }
                    .controlButton().disabled(browser.page >= browser.pageCount || browser.busy).accessibilityLabel(L10n.text("Next"))
            }
        }.controlSize(.large)
        #if os(tvOS)
        .padding(.vertical, 20).frame(maxWidth: .infinity).background(TVStyle.background).focusSection()
        #else
        .padding(.vertical, 8).frame(maxWidth: .infinity).controlBackdrop()
        #endif
    }
    private func home() async { await browser.load(.home, client: client) }
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { await home() }
        else { await browser.load(.list(category: nil, query: text, page: 1), client: client) }
    }
    private func load(page next: Int) async {
        await browser.load(.list(category: browser.category.isEmpty ? nil : browser.category, query: browser.query, page: next), client: client)
    }
}

struct VideoDetailView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    let video: Video
    let client: CatalogClient
    @State private var requestTask: Task<Void, Never>?
    @State private var detail: Video?
    @State private var error: String?
    @State private var busy = false
    @State private var pendingPlan: PlaybackPlan?
    @State private var pendingEpisode: Episode?
    @State private var choosingQuality = false
    @State private var synopsisExpanded = false
    @State private var selectedFlag: String?
    /// Play takes over focus from the loading placeholder; otherwise nothing is focused once details load.
    @FocusState private var playFocused: Bool
    @State private var containerWidth: CGFloat = 0
    /// The episode whose playback is being prepared; its row and the Play button show progress.
    @State private var loadingEpisode: Episode.ID?
    /// A failed or blocked playback attempt, shown as an inline banner beside the artwork.
    @State private var playbackIssue: PlaybackIssue?
    @State private var signingIn: CloudDrive?
    @State private var choosingDownloads = false
    /// How many episodes were just queued, shown briefly under the header.
    @State private var queuedNotice: Int?
    private var flags: [String] {
        var seen = Set<String>()
        return (detail?.episodes ?? []).map(\.flag).filter { seen.insert($0).inserted }
    }
    private var activeFlag: String { flags.contains(selectedFlag ?? "\u{0}") ? selectedFlag! : (flags.first ?? "") }
    private var railWidth: CGFloat {
        #if os(tvOS)
        560
        #else
        348
        #endif
    }
    private var wideMinWidth: CGFloat {
        #if os(tvOS)
        1200
        #else
        760
        #endif
    }
    private func startRequest(_ operation: @escaping @MainActor () async -> Void) {
        let previous = requestTask
        previous?.cancel()
        requestTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    var body: some View {
        Group {
            if splitLayout {
                // Watch-page split: artwork, Play and synopsis on the left; the episode rail
                // scrolls on its own so the title and playback state stay in view.
                HStack(alignment: .top, spacing: Layout.gutter + 8) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) { header }
                        .padding(.vertical, Layout.gutter)
                    }
                    .scrollIndicators(.never)
                    // Each column is a full-height focus section: with a few episodes the rail ends
                    // above Play, and the remote found nothing to its right (no way to the source chips).
                    .tvFocusSection()
                    episodePanel(scrolls: true).padding(.top, Layout.gutter)
                        .frame(width: railWidth).frame(maxHeight: .infinity, alignment: .top)
                        .tvFocusSection()
                }
                .padding(.horizontal, Layout.gutter)
                .frame(maxWidth: Layout.maxWidth).frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if detail != nil {
                            episodePanel(scrolls: false)
                        } else if let error {
                            errorCard(error).padding(.top, 12)
                        } else {
                            // The Play placeholder in the header holds focus while details load.
                            DetailSkeleton()
                        }
                    }
                    .pageContainer()
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if !splitLayout { loadingCard } }
        // The split has no outer scroll view to absorb a bottom inset: one appearing when Play
        // starts pushed both columns up under the toolbar. Float the card over it instead.
        .overlay(alignment: .bottom) { if splitLayout { loadingCard } }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .screenBackdrop()
        .screenTitle(video.name).task {
            store.searchModel.suspend()
            if detail == nil { await loadDetail() }
            #if DEBUG
            // `-qaDownloadPicker 1` opens the episode picker, for screenshots.
            if UserDefaults.standard.bool(forKey: "qaDownloadPicker") { choosingDownloads = true }
            #endif
        }
        .onDisappear { requestTask?.cancel() }
        .onChange(of: choosingQuality) { _, open in if !open && !busy { loadingEpisode = nil } }
        // Sign in where playback failed, then resume the episode that needed the account.
        #if os(macOS)
        .sheet(item: $signingIn) { drive in
            CloudLoginView(provider: drive.provider) { cookie, ticket in
                try await drive.provider.saveLogin(cookie, ticket: ticket)
                if let episode = playbackIssue?.episode { startRequest { await play(episode) } }
            }
        }
        #elseif os(iOS)
        // The drive's own sign-in page; the code is for signing in with another phone.
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
            DownloadPicker(video: video, site: client.site, flag: activeFlag,
                           episodes: (detail?.episodes ?? []).filter { $0.flag == activeFlag }) { count in
                guard count > 0 else { return }
                withAnimation(.smooth(duration: 0.2)) { queuedNotice = count }
                Task { try? await Task.sleep(for: .seconds(6)); withAnimation(.smooth(duration: 0.2)) { queuedNotice = nil } }
            }
        }
        .confirmationDialog(L10n.text("Choose quality"), isPresented: $choosingQuality, titleVisibility: .visible) {
            if let plan = pendingPlan, let episode = pendingEpisode {
                ForEach(plan.choices) { choice in
                    Button(choice.name) { startRequest { await resolve(plan, choice: choice, episode: episode) } }
                }
            }
        }
    }
    private var splitLayout: Bool { detail != nil && isWide }
    @ViewBuilder private var loadingCard: some View {
        if busy {
            // Keyed by the step, so the timer restarts when details turn into resolving a link.
            LoadingCard { .source(client.site, origin: client.origin, title: busyTitle) }
                .id(busyTitle)
                .frame(maxWidth: .infinity).padding(.horizontal, Layout.gutter).padding(.bottom, 24)
        }
    }
    @ViewBuilder private var playbackBanner: some View {
        if let count = queuedNotice {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Brand.accent)
                Text(count == 1 ? L10n.text("1 episode added to Downloads.") : L10n.text("%lld episodes added to Downloads.", count)).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Button(L10n.text("Show Downloads")) { store.section = .downloads }.settingsButton()
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if let issue = playbackIssue {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: issue.drive != nil ? "person.crop.circle.badge.exclamationmark.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.amber)
                    .frame(width: 36, height: 36)
                    .background(Brand.amber.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("Couldn't play %@", EpisodeRow.title(issue.episode.name)))
                            .font(.headline).lineLimit(2)
                        Text(issue.message).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).selectable()
                    }
                    HStack(spacing: 8) {
                        if let drive = issue.drive {
                            Button(drive.signInTitle) { signingIn = drive }.settingsButton(prominent: true)
                        }
                        Button(L10n.text(issue.blockedBeforeRequest ? "Try Anyway" : "Retry")) {
                            startRequest { await play(issue.episode, skipAccountCheck: true) }
                        }
                        .settingsButton(prominent: issue.drive == nil)
                        #if os(tvOS)
                        // A focusable action instead of the small corner close button.
                        Button(L10n.text("Dismiss")) { withAnimation(.smooth(duration: 0.2)) { playbackIssue = nil } }.settingsButton()
                        #endif
                    }
                }
                Spacer(minLength: 0)
                #if !os(tvOS)
                Button { withAnimation(.smooth(duration: 0.2)) { playbackIssue = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.07), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(L10n.text("Dismiss")).help(L10n.text("Dismiss"))
                #endif
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)) }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    private func errorCard(_ error: String) -> some View {
                    ErrorStateCard(
                        title: detail == nil ? L10n.text("Unable to load video details") : L10n.text("Unable to start playback"),
                        message: detail == nil
                            ? L10n.text("Try again, or go back and choose another video.")
                            : L10n.text("Try another episode or playback source."),
                        details: error,
                        retry: detail == nil ? { startRequest { await loadDetail() } } : nil,
                        goBack: { dismiss() },
                        busy: busy,
                        backTitle: L10n.text("Go back")
                    )
    }
    private var busyTitle: String {
        if detail == nil { return L10n.text("Loading video details…") }
        let episode = detail?.episodes.first { $0.id == loadingEpisode }
        return episode.map { L10n.text("Getting the video link for %@…", EpisodeRow.title($0.name)) } ?? L10n.text("Getting the video link…")
    }
    private func loadDetail() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try await client.detail(video.id, cached: client.site.type == 3 || client.site.type == 4)
            try Task.checkCancellation()
            detail = value
            // Start on a line that can play: not one from a drive the viewer has no way to sign in to.
            if selectedFlag == nil { selectedFlag = CloudDrive.preferredFlag(flags) }
            #if os(tvOS)
            Task { try? await Task.sleep(for: .milliseconds(100)); playFocused = true }
            #endif
        } catch {
            guard !Task.isCancelled else { return }
            Diagnostics.shared.failure("catalog", "detail \(client.reportContext)", error)
            self.error = error.localizedDescription
            #if os(tvOS)
            // The loading placeholder that held focus is gone: Retry in the hero takes it.
            Task { try? await Task.sleep(for: .milliseconds(100)); playFocused = true }
            #endif
        }
    }
    private var headerLayout: AnyLayout {
        #if os(iOS)
        if sizeClass == .compact { return AnyLayout(HStackLayout(alignment: .top, spacing: 16)) }
        #endif
        return AnyLayout(HStackLayout(alignment: .top, spacing: 24))
    }
    private var compactDetail: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
    @ViewBuilder private func synopsis(_ detail: Video) -> some View {
        if !detail.synopsis.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.synopsis).foregroundStyle(.secondary)
                    .lineLimit(synopsisExpanded ? nil : synopsisLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                if detail.synopsis.count > 100 {
                    let toggle = Button(L10n.text(synopsisExpanded ? "Show Less" : "Show Full Synopsis")) { synopsisExpanded.toggle() }
                    #if os(tvOS)
                    toggle.controlButton()
                    #else
                    toggle.buttonStyle(.plain).font(.subheadline.weight(.semibold)).frame(minHeight: 44, alignment: .leading)
                    #endif
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var synopsisLineLimit: Int {
        #if os(tvOS)
        4
        #else
        3
        #endif
    }
    private var posterWidth: CGFloat {
        #if os(macOS)
        150
        #elseif os(iOS)
        compactDetail ? 104 : 150
        #else
        Layout.detailPoster
        #endif
    }
    private var isWide: Bool { containerWidth >= wideMinWidth }
    private var heroTitleSize: CGFloat {
        #if os(tvOS)
        52
        #else
        34
        #endif
    }
    /// The details, with the list's poster when the details came without one.
    private func currentVideo() -> Video { (detail ?? video).keepingPoster(video.poster, headers: video.posterHeaders) }

    private func videoFavorite() -> FavoriteItem {
        .video(FavoriteVideo(origin: client.origin, site: client.site, video: currentVideo()))
    }

    private func episodeFavorite(_ episode: Episode) -> FavoriteItem {
        .episode(FavoriteEpisode(video: FavoriteVideo(origin: client.origin, site: client.site, video: currentVideo()), episodeFlag: episode.flag, episodeName: episode.name, episodeID: episode.id))
    }

    @ViewBuilder private var playControl: some View {
        if let detail {
            if let first = detail.episodes.first(where: { $0.flag == activeFlag }) ?? detail.episodes.first {
                // Beside the poster on a phone there is no room for both labels: Download drops to its icon.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { playButton(first); downloadButton(iconOnly: false); videoFavoriteButton }
                    HStack(spacing: 10) { playButton(first); downloadButton(iconOnly: true); videoFavoriteButton }
                }
            } else {
                #if os(tvOS)
                // No episodes, so no Play: without a button here nothing on the page could take focus, and Back
                // did nothing at all.
                goBackButton(prominent: true).focused($playFocused)
                #endif
            }
        } else if error == nil {
            // On Apple TV the hero fills the screen and the skeleton below it is off-screen: the
            // Play button's placeholder holds focus, so Back leaves the page instead of the app.
            SkeletonBlock(cornerRadius: 10).frame(width: 150, height: 40).loadingFocus(takeFocus: true) { dismiss() }
        } else {
            #if os(tvOS)
            // The details failed. The error card's buttons are below the full-screen hero, out of the remote's reach,
            // so the hero offers them too; they hold focus, and Back leaves the page again.
            HStack(spacing: 10) {
                Button { startRequest { await loadDetail() } } label: { Label(L10n.text("Retry"), systemImage: "arrow.clockwise") }
                    .controlButton(prominent: true).tint(Brand.accent).controlSize(.large)
                    .disabled(busy)
                    .focused($playFocused)
                    .accessibilityIdentifier("detail.retry")
                goBackButton(prominent: false)
            }
            #endif
        }
    }
    #if os(tvOS)
    private func goBackButton(prominent: Bool) -> some View {
        Button { dismiss() } label: { Label(L10n.text("Go back"), systemImage: "chevron.backward") }
            .controlButton(prominent: prominent).controlSize(.large)
            .accessibilityIdentifier("detail.goBack")
    }
    #endif
    private func playButton(_ episode: Episode) -> some View {
        Button { startRequest { await play(episode) } } label: {
            HStack(spacing: 8) {
                if loadingEpisode == episode.id { ProgressView().controlSize(.small) } else { Image(systemName: "play.fill") }
                Text(L10n.text("Play"))
            }
            .font(.headline).lineLimit(1).fixedSize().padding(.horizontal, 8)
        }
        .controlButton(prominent: true).tint(Brand.accent).controlSize(.large)
        .focused($playFocused)
    }
    private func downloadButton(iconOnly: Bool) -> some View {
        Button { choosingDownloads = true } label: {
            Label(L10n.text("Download"), systemImage: "arrow.down.circle")
                .labelStyle(DownloadLabelStyle(iconOnly: iconOnly))
                .font(.headline).lineLimit(1).fixedSize()
        }
        .controlButton().controlSize(.large).accessibilityLabel(L10n.text("Download"))
    }
    /// Icon-only, beside Play and Download. An empty heart keeps the control color; a saved one is rose.
    private var videoFavoriteButton: some View {
        let saved = store.favorites.contains(videoFavorite())
        let title = saved ? L10n.text("Remove %@ from favorites", currentVideo().name) : L10n.text("Add %@ to favorites", currentVideo().name)
        return Button { store.favorites.toggle(videoFavorite()) } label: {
            if saved {
                Image(systemName: "heart.fill").foregroundStyle(Brand.rose)
            } else {
                Image(systemName: "heart")
            }
        }
        .controlButton().controlSize(.large)
        .accessibilityLabel(title).help(title)
        .accessibilityIdentifier("detail.favorite")
    }
    /// Stands in for a watch-page player: a 16:9 stage with the artwork, title and the primary action.
    private var hero: some View {
        Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        PosterImage(url: video.poster, headers: video.posterHeaders)
                            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                            .blur(radius: 40).scaleEffect(1.35)
                            .overlay(Color.black.opacity(0.5))
                        HStack(alignment: .center, spacing: 32) {
                            Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
                                .overlay { PosterImage(url: video.poster, headers: video.posterHeaders) }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                                .frame(height: max(proxy.size.height - 56, 60))
                            VStack(alignment: .leading, spacing: 14) {
                                Text(video.name).font(.system(size: heroTitleSize, weight: .bold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                if !video.remarks.isEmpty { Text(video.remarks).font(.title3).foregroundStyle(.white.opacity(0.75)) }
                                playControl.padding(.top, 6)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(28).frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    }
                }
            }
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isWide {
                hero
                playbackBanner
                if let detail, !detail.synopsis.isEmpty {
                    synopsis(detail).font(.body).padding(.horizontal, 18).padding(.vertical, 14)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit).frame(width: posterWidth)
                        .overlay { PosterImage(url: video.poster, headers: video.posterHeaders) }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    // As tall as the 2:3 poster, so the buttons line up with its bottom edge.
                    MinHeightLayout(minHeight: posterWidth * 1.5) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(video.name).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                            if !video.remarks.isEmpty { Text(video.remarks).font(.subheadline).foregroundStyle(.secondary) }
                            Spacer(minLength: 0)
                            playControl
                        }
                    }
                    Spacer(minLength: 0)
                }
                playbackBanner
                if let detail { synopsis(detail) }
            }
        }
    }
    @ViewBuilder private func episodePanel(scrolls: Bool) -> some View {
        if let detail {
            if detail.episodes.isEmpty {
                Text(L10n.text("No playable sources were found for this video.")).foregroundStyle(.secondary)
            } else {
                let items = detail.episodes.filter { $0.flag == activeFlag }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(L10n.text("Episodes")).font(.headline)
                        Text("\(items.count)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if flags.count == 1, !activeFlag.isEmpty {
                            Text(SourceLabel(activeFlag).text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    flagPicker
                    if scrolls {
                        ScrollView { episodeList(items).padding(.bottom, Layout.gutter) }
                            .scrollIndicators(.automatic)
                    } else {
                        episodeList(items)
                    }
                }
            }
        }
    }
    @ViewBuilder private var flagPicker: some View {
        if flags.count > 1 {
            #if os(tvOS)
            ChipRow {
                HStack(spacing: 8) {
                    ForEach(flags, id: \.self) { flag in
                        Chip(title: flag.isEmpty ? L10n.text("Play") : flag, selected: flag == activeFlag) { selectedFlag = flag }
                    }
                }
            }.tvFocusSection()
            #else
            SourceStrip(items: flags.map { .init(id: $0, name: $0.isEmpty ? L10n.text("Play") : $0) }, selection: activeFlag) { selectedFlag = $0 }
            #endif
        }
    }
    private func episodeList(_ items: [Episode]) -> some View {
        let longNames = isWide || (items.map { $0.name.count }.max() ?? 0) > 9
        return LazyVGrid(columns: longNames ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: episodeMin), spacing: 8)], spacing: longNames ? 4 : 8) {
            ForEach(items) { episode in
                let saved = download(episode)
                Group {
                    if longNames {
                        EpisodeRow(name: episode.name, loading: loadingEpisode == episode.id, download: saved) { startRequest { await play(episode) } }
                    } else {
                        Chip(title: episode.name, selected: loadingEpisode == episode.id, fill: true) { startRequest { await play(episode) } }
                            .overlay(alignment: .topTrailing) { if saved?.status == .completed { DownloadedBadge() } }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if store.favorites.contains(episodeFavorite(episode)) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: DownloadMetrics.thumb > 60 ? 18 : 12, weight: .semibold))
                            .foregroundStyle(Brand.rose)
                            .padding(4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .contextMenu {
                    FavoriteMenuButton(item: episodeFavorite(episode), name: episode.name)
                    if saved == nil || saved?.status == .failed {
                        Button(L10n.text("Download"), systemImage: "arrow.down.circle") {
                            DownloadLibrary.shared.download(DownloadSource(site: client.site, videoID: video.id, episode: episode),
                                                            title: video.name, poster: video.poster, posterHeaders: video.posterHeaders)
                        }
                    } else if let saved {
                        Button(L10n.text(saved.status == .completed ? "Delete Download" : "Cancel Download"), systemImage: "trash", role: .destructive) {
                            DownloadLibrary.shared.remove([saved.id])
                        }
                    }
                }
            }
        }
        #if os(tvOS)
        // Room for the focused glass row, which grows toward the trailing edge.
        .padding(.trailing, 16).padding(.vertical, 6)
        #endif
        .tvFocusSection()
    }
    private var episodeMin: CGFloat {
        #if os(tvOS)
        170
        #else
        74
        #endif
    }
    private func download(_ episode: Episode) -> DownloadItem? {
        DownloadLibrary.shared.item(for: DownloadSource(site: client.site, videoID: video.id, episode: episode))
    }
    private func play(_ episode: Episode, skipAccountCheck: Bool = false) async {
        guard !busy else { return }
        // A downloaded episode plays from the device: no link to fetch, and it works offline.
        if let saved = download(episode), saved.status == .completed {
            store.playing = DownloadLibrary.shared.channel(for: saved)
            return
        }
        // Cloud-drive plugins wait for an in-app login that cannot appear on this platform,
        // which surfaces only as a 60-second timeout. Ask for the account up front instead.
        if !skipAccountCheck, let drive = CloudDrive.missingLogin(forFlag: episode.flag) {
            withAnimation(.smooth(duration: 0.25)) {
                playbackIssue = PlaybackIssue(episode: episode, message: drive.loginHint, drive: drive, blockedBeforeRequest: true)
            }
            return
        }
        busy = true; loadingEpisode = episode.id
        withAnimation(.smooth(duration: 0.2)) { playbackIssue = nil }
        defer { busy = false; if !choosingQuality { loadingEpisode = nil } }
        do {
            let plan = try await client.preparePlayback(episode)
            try Task.checkCancellation()
            if plan.choices.count > 1 {
                pendingPlan = plan; pendingEpisode = episode; choosingQuality = true
            } else {
                let playback = store.subscription.map { client.applying($0) } ?? client
                let resolved = try await playback.resolvePlayback(plan, choice: plan.choices[0])
                try Task.checkCancellation()
                store.playing = store.catalogChannel(resolved, video: currentVideo(), episode: episode, client: playback)
            }
        } catch { fail(episode, error) }
    }
    private func resolve(_ plan: PlaybackPlan, choice: PlaybackChoice, episode: Episode) async {
        busy = true; loadingEpisode = episode.id
        defer { busy = false; pendingPlan = nil; pendingEpisode = nil; loadingEpisode = nil }
        do {
            let playback = store.subscription.map { client.applying($0) } ?? client
            let resolved = try await playback.resolvePlayback(plan, choice: choice)
            try Task.checkCancellation()
            store.playing = store.catalogChannel(resolved, video: currentVideo(), episode: episode, client: playback)
        } catch { fail(episode, error) }
    }
    #if !os(macOS)
    private func retryAfterSignIn() {
        if let episode = playbackIssue?.episode { startRequest { await play(episode) } }
    }
    #endif
    private func fail(_ episode: Episode, _ error: Error) {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        // A drive that needs signing in is expected, not a failure to report.
        if !(error is CloudDriveLoginRequired) {
            Diagnostics.shared.failure("catalog", "play \(client.reportContext) flag=\(episode.flag)", error)
        }
        withAnimation(.smooth(duration: 0.25)) {
            // Plugins report a missing or expired drive login in their own words ("夸克授权失败，请扫码登录");
            // say what happened and offer the sign-in instead of echoing them.
            if let login = error as? CloudDriveLoginRequired, let drive = CloudDrive(rawValue: login.rawValue) {
                playbackIssue = PlaybackIssue(episode: episode, message: drive.expiredHint, drive: drive, blockedBeforeRequest: false)
            } else if let drive = CloudDrive(flag: episode.flag), CloudDrive.isLoginFailure(error.localizedDescription) {
                playbackIssue = PlaybackIssue(episode: episode, message: drive.expiredHint, drive: drive, blockedBeforeRequest: false)
            } else {
                playbackIssue = PlaybackIssue(episode: episode, message: error.localizedDescription,
                                              drive: CloudDrive.missingLogin(forFlag: episode.flag), blockedBeforeRequest: false)
            }
        }
    }
}

private struct PlaybackIssue {
    let episode: Episode
    let message: String
    let drive: CloudDrive?
    /// True when playback was not attempted because a required account is missing.
    let blockedBeforeRequest: Bool
}

/// Cloud drives whose plugins need a saved login before they can return a stream.
private enum CloudDrive: String, Identifiable {
    case quark, uc
    var id: String { rawValue }
    /// FTY names its lines after drive nicknames: 夸父 is Quark, 优汐 is UC.
    init?(flag: String) {
        let text = flag.lowercased()
        if text.contains("夸克") || text.contains("夸父") || text.contains("quark") { self = .quark }
        else if text.hasPrefix("uc") || text.contains("uc网盘") || text.contains("优汐") { self = .uc }
        else { return nil }
    }
    /// Lines from drives that sign in through the plugin's own QR code (FTY's 嘟嘟 is Baidu, 阿狸 is
    /// Aliyun). They ask for a scan the first time, so they never start a title on their own.
    static func withoutSignIn(_ flag: String) -> Bool {
        let text = flag.lowercased()
        return ["嘟嘟", "百度", "度盘", "baidu", "阿狸", "阿里", "aliyun"].contains { text.contains($0) }
    }
    /// The first line that can play now: not from a drive without a sign-in, nor one whose sign-in is missing.
    static func preferredFlag(_ flags: [String]) -> String? {
        let accounts = (try? CloudDriveAccounts.load()) ?? CloudDriveAccounts()
        return flags.first { flag in
            if withoutSignIn(flag) { return false }
            guard let drive = CloudDrive(flag: flag) else { return true }
            let cookie = drive == .quark ? accounts.quarkCookie : accounts.ucCookie
            return !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    var name: String { self == .quark ? L10n.text("Quark") : "UC" }
    var signInTitle: String { L10n.text(self == .quark ? "Sign In to Quark" : "Sign In to UC") }
    #if os(macOS)
    var provider: CloudProvider { self == .quark ? .quark : .uc }
    #else
    var qrDrive: CloudDriveQRLogin.Drive { self == .quark ? .quark : .uc }
    var webSignIn: WebSignIn { self == .quark ? .quark : .uc }
    #endif
    var loginHint: String { L10n.text("This source plays from %@ and needs you to sign in first.", name) }
    var expiredHint: String { L10n.text("Your %@ sign-in is missing or has expired. Sign in again to play this episode.", name) }
    static func missingLogin(forFlag flag: String) -> CloudDrive? {
        guard let drive = CloudDrive(flag: flag) else { return nil }
        let accounts = (try? CloudDriveAccounts.load()) ?? CloudDriveAccounts()
        let cookie = drive == .quark ? accounts.quarkCookie : accounts.ucCookie
        return cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? drive : nil
    }
    static func isLoginFailure(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["授权", "登录", "扫码", "cookie", "login", "unauthorized"].contains { text.contains($0) }
    }
}

/// Episode names often lead with a size tag ("[1.18GB] S01E41.mkv"); show it as trailing detail.
private struct EpisodeRow: View {
    let name: String
    let loading: Bool
    var download: DownloadItem? = nil
    let action: () -> Void
    @State private var hovering = false
    static func split(_ name: String) -> (title: String, detail: String?) {
        if let match = name.firstMatch(of: /^\s*\[([^\]]+)\]\s*(.+)$/) { return (String(match.2), String(match.1)) }
        return (name, nil)
    }
    static func title(_ name: String) -> String { split(name).title }
    /// Row type and height per platform: a Mac list size is unreadable from a sofa.
    private static var metrics: (text: CGFloat, icon: CGFloat, height: CGFloat, inset: CGFloat) {
        #if os(tvOS)
        (28, 18, 42, 0) // GlassRowStyle adds its own padding and focus glass
        #elseif os(iOS)
        (15, 11, 44, 14)
        #else
        (13, 10, 36, 12)
        #endif
    }
    private var parts: (title: String, detail: String?) { Self.split(name) }
    var body: some View {
        let parts = parts
        let button = Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if loading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "play.fill").font(.system(size: Self.metrics.icon)).foregroundStyle(hovering ? .primary : .tertiary) }
                }
                .frame(width: Self.metrics.icon + 6)
                Text(parts.title).font(.system(size: Self.metrics.text, weight: loading ? .semibold : .medium))
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let detail = parts.detail {
                    Text(detail).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
                if let download { DownloadState(item: download) }
            }
            .padding(.horizontal, Self.metrics.inset).frame(minHeight: Self.metrics.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if !os(tvOS)
            .background(Color.primary.opacity(loading ? 0.12 : (hovering ? 0.08 : 0.04)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            #endif
            .contentShape(Rectangle())
        }
        .accessibilityLabel(name)
        #if os(tvOS)
        button.glassRow()
        #else
        button.buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.smooth(duration: 0.15), value: hovering)
        #endif
    }
}

private struct DownloadLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { configuration.icon } else { HStack(spacing: 6) { configuration.icon; configuration.title } }
    }
}

/// Gives its one subview at least `minHeight`, even in a scroll view, where `frame(minHeight:)`
/// leaves the content at its ideal height and spacers inside it never grow.
private struct MinHeightLayout: SwiftUI.Layout {
    var minHeight: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: max(size.height, minHeight))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
