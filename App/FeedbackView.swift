import SwiftUI
import TVCore
import Perception

/// Where people talk with the developer and each other, besides Send Feedback's public issues.
enum Support {
    static let telegram = URL(string: "https://t.me/+knKAmySfMycyMzg5")!
}

/// Settings › Send Feedback: a problem or an idea in the user's own words, posted as a public GitHub
/// issue (Feedback). Under the message go the subscriptions and what was played lately
/// (Feedback.context), filled in when the page opens, for the viewer to edit or remove. Once the issue
/// is up, the page shows its number and, off Apple TV, a link to it.
struct FeedbackView: View {
    @Environment(Store.self) private var store
    @State private var kind = Feedback.Kind.bug
    @State private var message = ""
    @State private var context = ""
    @State private var contextLoaded = false
    @State private var sending = false
    @State private var sent: Feedback.Issue?
    @State private var error: String?

    static var note: String {
        L10n.text("Your feedback becomes a public issue on Yingxia's GitHub page, with the app and system versions, the device model, the language and the included details. Please don't include accounts or passwords.")
    }
    static var contextNote: String {
        L10n.text("Your subscriptions and what you played lately help find the problem. Edit or remove anything you'd rather keep private.")
    }
    private var freshContext: String {
        Feedback.context(subscriptions: store.subscriptions, errors: store.subscriptionErrors, history: store.playbackHistory.entries)
    }
    private var empty: Bool { message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var thanks: String? { sent.map { L10n.text("Thanks! Your feedback is issue #%lld.", $0.number) } }

    #if DEBUG
    private static var qaDrafted = false
    #endif

    var body: some View {
        content
            .onAppear {
                guard !contextLoaded else { return }
                contextLoaded = true
                context = freshContext
            }
            #if DEBUG
            // `-qaFeedbackDraft <text>` fills in the message (typing on the TV's keyboard is slow), and
            // `-qaFeedbackSend 1` sends it, to the server named by `-qaFeedback <url>`. Once per launch: the
            // page can appear more than once.
            .onAppear {
                guard !Self.qaDrafted, let draft = UserDefaults.standard.string(forKey: "qaFeedbackDraft") else { return }
                Self.qaDrafted = true
                message = draft
                if UserDefaults.standard.bool(forKey: "qaFeedbackSend") { send() }
            }
            #endif
    }

    @ViewBuilder private var content: some View {
        #if os(tvOS)
        // The note goes under the rows: the hero's subtitle stops at three lines.
        TVSettingsSubpage(symbol: "bubble.left.and.text.bubble.right", title: L10n.text("Send Feedback")) {
            TVSettingsSection(title: L10n.text("Feedback"), footer: [error ?? thanks, Self.note].compactMap { $0 }.joined(separator: "\n\n")) {
                TVSettingsAction(title: L10n.text("Type"), value: kind.title) {
                    let kinds = Feedback.Kind.allCases
                    kind = kinds[((kinds.firstIndex(of: kind) ?? 0) + 1) % kinds.count]
                }
                TVSettingsField(title: L10n.text("Message"), text: $message, prose: true)
                TVSettingsAction(title: sending ? L10n.text("Sending…") : L10n.text("Send"), busy: sending, action: send)
                    .disabled(sending || empty)
            }
            // Typing a dozen lines with the remote is no way to edit them: the TV shows the details
            // and sends them or not.
            TVSettingsSection(title: L10n.text("Included Details"), footer: context.isEmpty ? Self.contextNote : context + "\n\n" + Self.contextNote) {
                TVSettingsToggle(title: L10n.text("Include Details"), isOn: Binding {
                    !context.isEmpty
                } set: { context = $0 ? freshContext : "" })
            }
        }
        #else
        FeedbackPage(kind: $kind, message: $message, context: $context, freshContext: freshContext, sending: sending,
                     sent: $sent, error: error, send: send)
        #endif
    }

    private func send() {
        guard !sending, !empty else { return }
        sending = true; error = nil; sent = nil
        Task {
            defer { sending = false }
            do {
                sent = try await Feedback.send(Feedback.combined(message, context: context), kind: kind)
                message = ""
                context = freshContext
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

#if !os(tvOS)
// MARK: Send Feedback on the Mac, iPhone and iPad
// A page of its own rather than a form: a short invitation, the three kinds as cards, a roomy editor
// with Send in its bottom bar (⌘↩), the included details in an editor of their own, and what goes
// with the message spelled out. Once the issue is
// up, a thank-you card links to it. iPhone keeps the layout with smaller type and cards without
// their blurbs, on the app's navy canvas.

private struct FeedbackPage: View {
    @Binding var kind: Feedback.Kind
    @Binding var message: String
    @Binding var context: String
    let freshContext: String
    let sending: Bool
    @Binding var sent: Feedback.Issue?
    let error: String?
    let send: () -> Void
    @FocusState private var editing: Bool
    @Environment(\.openURL) private var openURL
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var empty: Bool { message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private static let card = RoundedRectangle(cornerRadius: 14, style: .continuous)
    /// Cards and chips: a faint grey on the Mac, the settings rows' fill on iPhone and iPad.
    static var fill: Color {
        #if os(iOS)
        SettingsStyle.rowFill
        #else
        Color.primary.opacity(0.05)
        #endif
    }
    /// iPhone, or iPad in a narrow window.
    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: compact ? 22 : 28) {
                header
                if let sent {
                    thanks(sent).transition(.scale(scale: 0.97).combined(with: .opacity))
                } else {
                    form.transition(.opacity)
                }
            }
            .padding(.horizontal, compact ? Layout.gutter : 32).padding(.top, compact ? 20 : 32).padding(.bottom, 40)
            .frame(maxWidth: Layout.settingsWidth)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.22), value: sent)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .background { Backdrop() }
        #endif
        .screenTitle(L10n.text("Send Feedback"), width: Layout.settingsWidth)
    }

    private var header: some View {
        let tile = RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous)
        return VStack(spacing: compact ? 6 : 8) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: compact ? 26 : 30, weight: .semibold)).foregroundStyle(.white)
                .frame(width: compact ? 60 : 68, height: compact ? 60 : 68)
                .background(LinearGradient(colors: [Brand.cyan, Brand.indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: tile)
                .overlay { tile.strokeBorder(.white.opacity(0.22), lineWidth: 0.5) }
                .shadow(color: Brand.indigo.opacity(0.45), radius: 18, y: 8)
                .padding(.bottom, 8)
            Text(L10n.text("Help Make Yingxia Better")).font(compact ? .title2.weight(.bold) : .title.weight(.bold))
            Text(L10n.text("Report a problem or share an idea. It goes straight to the developer."))
                .font(compact ? .body : .title3).foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 20) {
            HStack(spacing: compact ? 10 : 12) {
                ForEach(Feedback.Kind.allCases, id: \.self) { option in
                    FeedbackKindCard(kind: option, selected: option == kind, compact: compact) { kind = option; editing = true }
                }
            }
            composer
            included
            if let error {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.amber)
                    Text(error)
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            details
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // TextEditor has no prompt: this sits where its first line starts.
                if message.isEmpty {
                    Text(kind.prompt).foregroundStyle(.tertiary).padding(.leading, 5)
                        #if os(iOS)
                        .padding(.top, 8)
                        #endif
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .focused($editing)
            }
            #if os(macOS)
            .font(.system(size: 14))
            #endif
            .frame(minHeight: compact ? 150 : 200)
            .padding(compact ? 10 : 14)
            Divider()
            HStack(spacing: 10) {
                // What is sent: the message and the included details.
                let count = Feedback.combined(message, context: context).count
                Text(verbatim: "\(count.formatted()) / \(Feedback.limit.formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(count > Feedback.limit ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.tertiary))
                Spacer()
                if sending { ProgressView().controlSize(.small) }
                #if os(macOS)
                Text(verbatim: "⌘↩").font(.callout).foregroundColor(.tertiary)
                #endif
                Button(action: send) {
                    Label(sending ? L10n.text("Sending…") : L10n.text("Send"), systemImage: "paperplane.fill").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent).tint(systemAccent).feedbackButton(compact ? .regular : .large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(sending || empty)
            }
            .padding(.horizontal, compact ? 10 : 14).padding(.vertical, 10)
        }
        .background { Self.card.fill(Self.fill) }
        .overlay { Self.card.strokeBorder(editing ? systemAccent.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: editing ? 1.5 : 1) }
        .animation(.easeOut(duration: 0.15), value: editing)
        #if os(macOS)
        // Not on iPhone: the keyboard would cover the page before it has been read.
        .onAppear { editing = true }
        #endif
    }

    /// The subscriptions and recent plays, sent after the message as they read here.
    private var included: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label(L10n.text("Included Details"), systemImage: "list.bullet.rectangle.portrait")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if context != freshContext { Button(L10n.text("Reset")) { context = freshContext } }
                if !context.isEmpty { Button(L10n.text("Remove"), role: .destructive) { context = "" } }
            }
            .buttonStyle(.borderless).font(.subheadline)
            if !context.isEmpty {
                TextEditor(text: $context)
                    .font(.system(compact ? .footnote : .callout, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: compact ? 160 : 180)
                    .padding(compact ? 8 : 10)
                    .background { Self.card.fill(Self.fill) }
                    .overlay { Self.card.strokeBorder(Color.primary.opacity(0.08)) }
            }
            Text(FeedbackView.contextNote).font(compact ? .footnote : .callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.2), value: context.isEmpty)
    }

    private var details: some View {
        let details = Feedback.details
        let language = Locale(identifier: details.language).localizedString(forIdentifier: details.language) ?? details.language
        let app = chip("app.badge.fill", "\(L10n.text("Yingxia")) \(details.app)"), system = chip(deviceSymbol, details.system)
        let model = chip("cpu", details.model), lang = chip("character.bubble", language)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Sent with your message")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { app; system; model; lang }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { app; system }
                    HStack(spacing: 8) { model; lang }
                }
                VStack(alignment: .leading, spacing: 8) { app; system; model; lang }
            }
            Label(FeedbackView.note, systemImage: "globe").font(compact ? .footnote : .callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Support.telegram) {
                Label(L10n.text("Prefer to chat? Join the Telegram group."), systemImage: "paperplane")
            }
            .font(compact ? .footnote : .callout)
        }
        .padding(.horizontal, 4)
    }

    private var deviceSymbol: String {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
        "desktopcomputer"
        #endif
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(compact ? .footnote : .callout).lineLimit(1).fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Self.fill, in: Capsule())
    }

    private func thanks(_ issue: Feedback.Issue) -> some View {
        let another = Button(L10n.text("Send Another")) { sent = nil; editing = true }
            .buttonStyle(.bordered).feedbackButton(.large)
        let open = Button { openURL(issue.url) } label: { Label(L10n.text("View on GitHub"), systemImage: "arrow.up.right") }
            .buttonStyle(.borderedProminent).tint(systemAccent).feedbackButton(.large)
        return VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: compact ? 48 : 56)).symbolRenderingMode(.palette).foregroundStyle(.white, .green)
                .shadow(color: .green.opacity(0.45), radius: 18, y: 6)
                .padding(.bottom, 4)
            Text(L10n.text("Thank You!")).font(.title2.weight(.bold))
            Text(L10n.text("Your feedback is now issue #%lld on GitHub.", issue.number)).font(compact ? .body : .title3).foregroundColor(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { another; open }
                VStack(spacing: 10) { open; another }
            }
            .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, compact ? 32 : 40).padding(.horizontal, compact ? 16 : 24)
        .frame(maxWidth: .infinity)
        .background {
            Self.card.fill(Self.fill)
                .overlay { Self.card.fill(RadialGradient(colors: [Color.green.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 260)) }
        }
        .overlay { Self.card.strokeBorder(Color.primary.opacity(0.08)) }
    }
}

private extension View {
    /// The page's buttons: capsules on iPhone and iPad, like the app's other buttons there.
    @ViewBuilder func feedbackButton(_ size: ControlSize) -> some View {
        #if os(iOS)
        controlSize(size).buttonBorderShape(.capsule)
        #else
        controlSize(size)
        #endif
    }
}

/// One kind of feedback as a card: its symbol, name and (with room) a line on what it is for.
private struct FeedbackKindCard: View {
    let kind: Feedback.Kind
    let selected: Bool
    var compact = false
    let action: () -> Void
    @State private var hovering = false
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                HStack(alignment: .top) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: compact ? 14 : 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: compact ? 30 : 32, height: compact ? 30 : 32)
                        .background(kind.tint.gradient, in: RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? AnyShapeStyle(kind.tint) : AnyShapeStyle(.tertiary))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(compact ? .subheadline.weight(.semibold) : .headline).lineLimit(1)
                    if !compact { Text(kind.blurb).font(.callout).foregroundColor(.secondary).lineLimit(1) }
                }
            }
            .padding(compact ? 12 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(FeedbackPage.fill)
                    .overlay { shape.fill(selected ? kind.tint.opacity(0.14) : Color.primary.opacity(hovering ? 0.03 : 0)) }
            }
            .overlay { shape.strokeBorder(selected ? kind.tint.opacity(0.85) : Color.primary.opacity(hovering ? 0.14 : 0.08), lineWidth: selected ? 1.5 : 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension Feedback.Kind {
    var symbol: String {
        switch self {
        case .bug: "ladybug.fill"
        case .idea: "lightbulb.fill"
        case .other: "ellipsis.bubble.fill"
        }
    }
    var tint: Color {
        switch self {
        case .bug: Brand.rose
        case .idea: .orange
        case .other: Brand.indigo
        }
    }
    var blurb: String {
        switch self {
        case .bug: L10n.text("Something isn't working")
        case .idea: L10n.text("An idea or a wish")
        case .other: L10n.text("Anything else")
        }
    }
    /// The editor's prompt, asking for what helps most with this kind.
    var prompt: String {
        switch self {
        case .bug: L10n.text("What happened? What did you expect instead?")
        case .idea: L10n.text("What would make Yingxia better for you?")
        case .other: L10n.text("What's on your mind?")
        }
    }
}
#endif

#if os(tvOS)
/// Settings › Telegram Group: Apple TV can't open the invite, so it goes to a phone as a QR code.
struct TelegramGroupView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TVSettingsSubpage(symbol: "paperplane", title: L10n.text("Telegram Group"), subtitle: L10n.text("Chat with the developer and other users")) {
            VStack(spacing: 24) {
                if let image = QRCode.image(Support.telegram.absoluteString) {
                    Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 320, height: 320).padding(24)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        // Nothing else here takes focus, and Back with nothing focused would leave the app.
                        .loadingFocus(takeFocus: true) { dismiss() }
                }
                Text(L10n.text("Scan with your iPhone to join the group.")).font(.system(size: 24)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
#endif
