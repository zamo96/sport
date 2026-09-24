import AVKit
import SwiftUI

struct ActivityMediaGalleryItem: Identifiable {
    let id = UUID()
    let media: [PlayerMediaItem]
    let initialIndex: Int
    let title: String
    let subtitle: String?
    let comment: String?

    init(media: [PlayerMediaItem], initialIndex: Int = 0, title: String, subtitle: String? = nil, comment: String? = nil) {
        self.media = media
        self.initialIndex = min(max(initialIndex, 0), max(media.count - 1, 0))
        self.title = title
        self.subtitle = subtitle
        self.comment = comment
    }

    static func media(photos: [String], videos: [String]) -> [PlayerMediaItem] {
        photos.map { PlayerMediaItem(kind: .photo, path: $0) }
            + videos.map { PlayerMediaItem(kind: .video, path: $0) }
    }
}

struct ActivityMediaGallerySheet: View {
    let item: ActivityMediaGalleryItem
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedIndex: Int

    init(item: ActivityMediaGalleryItem) {
        self.item = item
        _selectedIndex = State(initialValue: item.initialIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.headline)
                    if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.65)) }
                }
                Spacer(minLength: 4)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L10n.string("Close media", "Закрыть медиа"))
                .accessibilityIdentifier("activity-media-close")
            }
            .padding(16)
            if item.media.isEmpty {
                Text(L10n.string("No media added", "Медиа не добавлены"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(item.media.indices, id: \.self) { index in
                        let media = item.media[index]
                        Group {
                            if media.kind == .video && selectedIndex == index {
                                ActivityVideoPlayer(path: media.path)
                            } else if media.kind == .photo {
                                ActivityMediaPhoto(path: media.path, contentMode: .fit)
                            } else {
                                ActivityMediaThumbnail(item: media)
                            }
                        }
                        .padding(.horizontal, 12)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack {
                    Button { selectedIndex = max(0, selectedIndex - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .disabled(selectedIndex == 0)
                    .accessibilityLabel(L10n.string("Previous attachment", "Предыдущее вложение"))
                    .accessibilityIdentifier("activity-media-previous")
                    Spacer()
                    Text("\(selectedIndex + 1) / \(item.media.count)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("activity-media-count")
                    Spacer()
                    Button { selectedIndex = min(item.media.count - 1, selectedIndex + 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .disabled(selectedIndex == item.media.count - 1)
                    .accessibilityLabel(L10n.string("Next attachment", "Следующее вложение"))
                    .accessibilityIdentifier("activity-media-next")
                }
                .padding(.horizontal, 16)
            }
            if let comment = item.comment, !comment.isEmpty {
                ScrollView { Text(comment).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 150).padding(16)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: appModel.sessionGeneration) { _ in dismiss() }
    }
}

struct ActivityMediaStrip: View {
    let media: [PlayerMediaItem]
    var identifierPrefix = "activity-media"
    let onOpen: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(media.indices.prefix(4)), id: \.self) { index in
                    Button { onOpen(index) } label: {
                        ActivityMediaThumbnail(item: media[index])
                            .frame(width: 150, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(index + 1)/\(media.count)")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                                    .padding(6).background(.black.opacity(0.65), in: Capsule()).padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(media[index].kind == .video
                        ? L10n.string("Open video \(index + 1) of \(media.count)", "Открыть видео \(index + 1) из \(media.count)")
                        : L10n.string("Open photo \(index + 1) of \(media.count)", "Открыть фото \(index + 1) из \(media.count)"))
                    .accessibilityIdentifier("\(identifierPrefix)-\(index)")
                }
                if media.count > 4 {
                    Button { onOpen(4) } label: {
                        Label(L10n.string("\(media.count - 4) more", "Ещё \(media.count - 4)"), systemImage: "square.stack")
                            .font(.subheadline).foregroundStyle(.white)
                            .padding(16).frame(minWidth: 96, minHeight: 108)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ActivityMediaThumbnail: View {
    let item: PlayerMediaItem

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let url = resolveAppRemoteURL(item.path) {
                if item.kind == .video {
                    VideoThumbnailView(url: url)
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle).foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 4)
                } else {
                    ActivityMediaPhoto(path: item.path, contentMode: .fill)
                }
            } else { ActivityMediaUnavailable() }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct ActivityMediaPhoto: View {
    let path: String
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            #if DEBUG
            if AppConfig.useMockData, let url = URL(string: path), url.isFileURL,
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                remotePhoto
            }
            #else
            remotePhoto
            #endif
        }
    }

    private var remotePhoto: some View {
        RemoteImage(url: resolveAppRemoteURL(path), contentMode: contentMode, indicator: .spinner) { phase in
            if phase == .failed { ActivityMediaUnavailable() }
        }
    }
}

private struct ActivityVideoPlayer: View {
    let path: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var loadedPath: String?
    @State private var failed = false

    var body: some View {
        // Keep appearance callbacks on one persistent container while loading/failure branches change.
        ZStack {
            if failed {
                VStack(spacing: 16) {
                    ActivityMediaUnavailable()
                    Button(L10n.string("Try again", "Повторить")) { prepare(force: true) }.frame(minHeight: 44)
                }
            } else if let player {
                VideoPlayer(player: player)
                    .onReceive(player.publisher(for: \.status).receive(on: DispatchQueue.main)) { status in
                        if status == .failed && !failed { failed = true }
                    }
                    .onReceive(player.publisher(for: \.currentItem)
                        .compactMap { $0 }
                        .map { $0.publisher(for: \.status) }
                        .switchToLatest()
                        .receive(on: DispatchQueue.main)) { status in
                        if status == .failed && !failed { failed = true }
                    }
            } else { ProgressView().tint(.white) }
        }
        .onAppear { prepare() }
        .onDisappear { stop() }
        .onChange(of: path) { _ in prepare(force: true) }
        .onChange(of: scenePhase) { phase in if phase != .active { player?.pause() } }
    }

    private func prepare(force: Bool = false) {
        guard force || player == nil || loadedPath != path else { return }
        stop()
        guard let url = resolveAppRemoteURL(path) else { failed = true; return }
        failed = false
        loadedPath = path
        // Playback starts only from the native player controls.
        player = AVPlayer(url: url)
    }

    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        loadedPath = nil
    }
}

private struct ActivityMediaUnavailable: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title2)
            Text(L10n.string("Media unavailable", "Медиа недоступно")).font(.caption)
        }
        .foregroundStyle(.white.opacity(0.65))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
