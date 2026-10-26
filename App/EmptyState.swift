import SwiftUI
import TVCore

/// iOS 16 replacement for `EmptyState` (iOS 17+).
/// Same call shapes as the system type, so call sites only need the type name changed.
struct EmptyState: View {
    private let content: AnyView

    init(_ title: String, systemImage: String, description: Text? = nil) {
        content = AnyView(
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                if let description {
                    description
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 420)
            .padding()
        )
    }

    static func search(text: String) -> EmptyState {
        EmptyState(
            text.isEmpty ? L10n.text("No Results") : L10n.text("No Results for \"\(text)\""),
            systemImage: "magnifyingglass"
        )
    }

    init<L: View>(@ViewBuilder label: () -> L) {
        content = AnyView(VStack(spacing: 12) { label() }.padding())
    }

    init<L: View, D: View>(@ViewBuilder label: () -> L, @ViewBuilder description: () -> D) {
        content = AnyView(
            VStack(spacing: 12) {
                label()
                description()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420)
            .padding()
        )
    }

    init<L: View, D: View, A: View>(
        @ViewBuilder label: () -> L,
        @ViewBuilder description: () -> D,
        @ViewBuilder actions: () -> A
    ) {
        content = AnyView(
            VStack(spacing: 14) {
                label()
                description()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                actions()
            }
            .frame(maxWidth: 420)
            .padding()
        )
    }

    var body: some View { content }
}
