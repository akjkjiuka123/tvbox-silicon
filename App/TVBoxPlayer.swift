import SwiftUI
import TVCore
import Perception

// The TVBox player: the existing player, unchanged, with a TVBox episode drawer laid over it.
//
// Everything that makes playback work stays where it is — AVKit on the Apple TV and the Mac,
// MobilePlayerView on iPhone and iPad, plus danmaku, quality, skip-intro and the next-episode
// queue. What TVBox adds is the "选集" drawer: a black panel down the right edge listing the current
// line's episodes, which switches episode through Store.selectEpisode (the same call the native
// player's episode buttons use).

/// What the TVBox player cover shows. The id never changes, so an episode switch replaces the
/// channel inside one presentation instead of dismissing and presenting again.
struct TVBoxPlayerSlot: Identifiable {
    let channel: Channel
    var id: String { "tvbox-player" }
}

/// Presented by `TVBoxRoot` while anything plays.
struct TVBoxPlayer: View {
    let channel: Channel
    @Environment(Store.self) private var store
    @State private var showsEpisodes = false

    /// The video and line this channel belongs to; nil for live TV, cloud files and plain URLs.
    private var catalog: PlaybackCatalog? { store.catalog(for: channel) }

    private var episodes: [Episode] {
        guard let catalog else { return [] }
        let flag = channel.historyContext?.episodeFlag ?? ""
        let line = catalog.playlist.episodes(for: flag)
        return line.isEmpty ? catalog.video.episodes : line
    }

    private var currentEpisodeName: String? { channel.historyContext?.episodeName }

    var body: some View {
        withPerceptionTracking {
        ZStack(alignment: .trailing) {
            PlaybackView(channel: channel)
            if showsEpisodes {
                drawer
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Color.black)
        .animation(.easeOut(duration: 0.22), value: showsEpisodes)
        .overlay(alignment: .topTrailing) {
            if !episodes.isEmpty && !showsEpisodes { openButton }
        }
        }
     }

    /// The drawer's handle. The system player keeps its own bar on the left, so this sits opposite it.
    private var openButton: some View {
        Button { showsEpisodes = true } label: {
            Label("选集", systemImage: "list.bullet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.22))
                }
        }
        .buttonStyle(.plain)
        .padding(.top, 24)
        .padding(.trailing, 24)
        .accessibilityIdentifier("tvbox.player.episodes.open")
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalog?.video.name ?? channel.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let currentEpisodeName, !currentEpisodeName.isEmpty {
                        Text("正在播放 \(currentEpisodeName)")
                            .font(.system(size: 11))
                            .foregroundStyle(TVBoxTheme.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button { showsEpisodes = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭选集")
                .accessibilityIdentifier("tvbox.player.episodes.close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().overlay(TVBoxTheme.hairline)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(episodes) { episode in
                        Button {
                            store.selectEpisode(episode, from: channel) { message in
                                Diagnostics.shared.record(.warning, "player", "tvbox episode switch failed: \(message)")
                            }
                        } label: {
                            Text(episode.name).lineLimit(1)
                        }
                        .buttonStyle(TVBoxEpisodeStyle(loaded: isCurrent(episode)))
                        .accessibilityIdentifier("tvbox.player.episode." + episode.id)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: drawerWidth)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .leading) { Divider().overlay(TVBoxTheme.hairline) }
    }

    private var drawerWidth: CGFloat {
        #if os(tvOS)
        460
        #elseif os(macOS)
        380
        #else
        320
        #endif
    }

    private func isCurrent(_ episode: Episode) -> Bool {
        guard let name = currentEpisodeName else { return false }
        return episode.name == name
    }
}
