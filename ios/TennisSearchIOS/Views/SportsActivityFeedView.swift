import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import CoreTransferable
import ImageIO
import MapKit

/// Feed access is temporarily disabled, including the Debug launch shortcut.
enum SportsActivityFeedPreview {
    static var isEnabled: Bool { false }

    static var videoFixtureURL: URL? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard isEnabled, let index = arguments.firstIndex(of: "-activity-feed-video-fixture"),
              arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/"),
              FileManager.default.fileExists(atPath: arguments[index + 1]) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
        #else
        return nil
        #endif
    }
}

private enum ActivityFeedStyle {
    static let card = Color(red: 0.075, green: 0.085, blue: 0.078)
    static let muted = Color.white.opacity(0.6)
    static let maximumMediaCount = 5
}

#if DEBUG
private final class ActivityFeedCounterStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = ["mainThreadPhotoDecodes": 0]
    func increment(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key, default: 0] += 1
    }
    func snapshot() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}
#endif

private enum ActivityFeedPerformance {
    #if DEBUG
    static let isEnabled = SportsActivityFeedPreview.videoFixtureURL != nil
    private static let storage = ActivityFeedCounterStorage()
    #endif
    static func increment(_ key: String) {
        #if DEBUG
        if isEnabled { storage.increment(key) }
        #endif
    }
    static func snapshot() -> [String: Int] {
        #if DEBUG
        return storage.snapshot()
        #else
        return [:]
        #endif
    }
}

/// One serial loader coalesces simultaneous requests through a bounded, decoded-image cache.
private final class ActivityPhotoLoader: @unchecked Sendable {
    static let shared = ActivityPhotoLoader()
    private let queue = DispatchQueue(label: "tennissearch.activity-photos", qos: .userInitiated)
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 12
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func bundledImage(named name: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let cached = self.cache.object(forKey: name as NSString) {
                    ActivityFeedPerformance.increment("bundledCacheHits")
                    continuation.resume(returning: cached)
                    return
                }
                ActivityFeedPerformance.increment("bundledCacheMisses")
                guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
                      let image = Self.decode(url) else {
                    continuation.resume(returning: nil)
                    return
                }
                let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                self.cache.setObject(image, forKey: name as NSString, cost: cost)
                continuation.resume(returning: image)
            }
        }
    }

    func importedImage(file: ActivityOwnedFile) async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                let image = withExtendedLifetime(file) { Self.decode(file.url) }
                continuation.resume(returning: image)
            }
        }
    }

    private static func decode(_ url: URL) -> UIImage? {
        ActivityFeedPerformance.increment("photoDecodes")
        if Thread.isMainThread { ActivityFeedPerformance.increment("mainThreadPhotoDecodes") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

/// Transfer results own their temporary file, even when an import finishes after cancellation.
private final class ActivityOwnedFile: @unchecked Sendable {
    let url: URL
    init(url: URL) { self.url = url }
    func remove() { try? FileManager.default.removeItem(at: url) }
    deinit { remove() }
}

private enum ActivityMedia {
    case bundledPhoto(String)
    case photo(UIImage)
    case video(ActivityOwnedFile)

    func removeOwnedFile() {
        if case .video(let file) = self { file.remove() }
    }
}

private struct ActivityMediaItem: Identifiable {
    let id = UUID()
    let media: ActivityMedia
}

private struct ActivityAuthor: Identifiable {
    let id: String
    let name: String
    let initials: String
    let bio: String
    let sports: [Sport]
    var isCurrent: Bool { id == Self.current.id }

    static let current = ActivityAuthor(
        id: "local-you", name: L10n.string("You", "Вы"), initials: L10n.string("ME", "Я"),
        bio: L10n.string("Your sporting moments appear here when you share a post.", "Здесь собираются ваши спортивные моменты, которыми вы поделились в ленте."), sports: []
    )
    static let anna = ActivityAuthor(
        id: "demo-anna", name: L10n.string("Anna Morozova", "Анна Морозова"), initials: "АМ",
        bio: L10n.string("Tennis, training and the joy of getting a little better each day.", "Теннис, тренировки и удовольствие от маленьких шагов вперёд."), sports: [.tennis, .fitness]
    )
    static let max = ActivityAuthor(
        id: "demo-max", name: L10n.string("Max Sokolov", "Максим Соколов"), initials: "МС",
        bio: L10n.string("Learning padel and enjoying every rally.", "Осваиваю падел и радуюсь каждому хорошему розыгрышу."), sports: [.padel]
    )
}

private struct ActivityPlaceTag: Identifiable {
    let id = UUID()
    let clubID: String?
    let title: String
    let address: String
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct SportsActivityPost: Identifiable {
    let id = UUID()
    let authorID: String
    let sport: Sport
    let time: String
    let caption: String
    let media: [ActivityMediaItem]
    var likes: Int
    var isLiked = false
    var place: ActivityPlaceTag? = nil
    var isOwn: Bool { authorID == ActivityAuthor.current.id }
}

private struct ActivityVideoEligibility: Equatable {
    let isActive: Bool
    let visibleFraction: Double
    let centerDistance: Double
}

#if DEBUG
private final class ActivityDiagnosticTimerOwner {
    var timer: Timer?
    deinit { timer?.invalidate() }
}
#endif

@MainActor
private final class ActivityPlaybackCoordinator: ObservableObject {
    struct Candidate {
        let renderID: UUID
        let mediaID: UUID
        let file: ActivityOwnedFile
        let visibility: Double
        let centerDistance: Double
    }

    let player = AVPlayer()
    @Published private(set) var activeRenderID: UUID?
    @Published private(set) var activeMediaID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var isMuted = true
    @Published private(set) var manuallyPaused = Set<UUID>()
    private var candidates: [UUID: Candidate] = [:]
    private var retiredMediaIDs = Set<UUID>()
    private var blockedModals = Set<UUID>()
    private var sceneIsActive = true
    private var loadedMediaID: UUID?
    private var needsPlaybackReconciliation = false
    private var selectionTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    #if DEBUG
    private let diagnosticTimerOwner = ActivityDiagnosticTimerOwner()
    private var registrationDiagnostics: [String: [String: Any]] = [:]
    private let diagnosticQueue = DispatchQueue(label: "tennissearch.activity-diagnostics", qos: .utility)
    private var diagnosticWriteInFlight = false
    #endif

    init() {
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isPlaying = self.player.timeControlStatus != .paused
                if self.isPlaying != isPlaying {
                    self.isPlaying = isPlaying
                    ActivityFeedPerformance.increment("playbackStatePublications")
                }
            }
        }
        #if DEBUG
        if SportsActivityFeedPreview.videoFixtureURL != nil {
            diagnosticTimerOwner.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.writeDiagnostics() }
            }
        }
        #endif
    }

    deinit {
        selectionTask?.cancel()
    }

    func recordEligibility(renderID: UUID, mediaID: UUID?, eligibility: ActivityVideoEligibility, isVideo: Bool) {
        #if DEBUG
        guard ActivityFeedPerformance.isEnabled else { return }
        registrationDiagnostics[renderID.uuidString] = [
            "mediaID": mediaID?.uuidString ?? "", "isActive": eligibility.isActive,
            "visibleFraction": eligibility.visibleFraction, "centerDistance": eligibility.centerDistance,
            "isVideo": isVideo, "timestamp": Date().timeIntervalSince1970
        ]
        if registrationDiagnostics.count > 20, let oldest = registrationDiagnostics.keys.sorted().first {
            registrationDiagnostics.removeValue(forKey: oldest)
        }
        #endif
    }

    func update(renderID: UUID, mediaID: UUID, file: ActivityOwnedFile, eligibility: ActivityVideoEligibility) {
        ActivityFeedPerformance.increment("candidateUpdates")
        guard !retiredMediaIDs.contains(mediaID), eligibility.isActive, eligibility.visibleFraction >= 0.6 else { remove(renderID); return }
        if let current = candidates[renderID], current.mediaID == mediaID,
           current.visibility == eligibility.visibleFraction, current.centerDistance == eligibility.centerDistance {
            ActivityFeedPerformance.increment("unchangedCandidatesSkipped")
            return
        }
        candidates[renderID] = Candidate(renderID: renderID, mediaID: mediaID, file: file,
                                         visibility: eligibility.visibleFraction, centerDistance: eligibility.centerDistance)
        scheduleSelection()
    }

    func remove(_ renderID: UUID) {
        guard candidates.removeValue(forKey: renderID) != nil else { return }
        if activeRenderID == renderID {
            pauseIfNeeded()
            needsPlaybackReconciliation = true
        }
        scheduleSelection()
    }

    func removeMedia(_ ids: Set<UUID>) {
        retiredMediaIDs.formUnion(ids)
        let previousCount = candidates.count
        candidates = candidates.filter { !ids.contains($0.value.mediaID) }
        let paused = manuallyPaused.subtracting(ids)
        if paused != manuallyPaused { manuallyPaused = paused }
        if candidates.count != previousCount || loadedMediaID.map(ids.contains) == true { selectCandidate() }
    }

    func setSceneActive(_ active: Bool) {
        guard sceneIsActive != active else { return }
        sceneIsActive = active
        selectCandidate()
    }

    func setModalBlocked(_ id: UUID, _ blocked: Bool) {
        let changed: Bool
        if blocked { changed = blockedModals.insert(id).inserted }
        else { changed = blockedModals.remove(id) != nil }
        if changed { selectCandidate() }
    }

    func togglePlayback(_ renderID: UUID) {
        guard renderID == activeRenderID, let mediaID = activeMediaID else { return }
        if player.timeControlStatus == .playing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            manuallyPaused.insert(mediaID)
            pauseIfNeeded()
        } else {
            manuallyPaused.remove(mediaID)
            if let duration = player.currentItem?.duration.seconds, duration.isFinite,
               player.currentTime().seconds >= duration - 0.1 { player.seek(to: .zero) }
            playIfNeeded()
        }
    }

    func toggleMute() { isMuted.toggle(); player.isMuted = isMuted }

    private func playIfNeeded() {
        guard player.timeControlStatus == .paused else { return }
        ActivityFeedPerformance.increment("playCommands")
        player.play()
    }

    private func pauseIfNeeded() {
        guard player.timeControlStatus != .paused || player.rate != 0 else { return }
        ActivityFeedPerformance.increment("pauseCommands")
        player.pause()
    }

    private func scheduleSelection() {
        guard selectionTask == nil else { return }
        selectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled, let self else { return }
            self.selectionTask = nil
            self.selectCandidate()
        }
    }

    private func selectCandidate() {
        ActivityFeedPerformance.increment("candidateSelections")
        let ranked = candidates.values.sorted {
            if $0.visibility != $1.visibility { return $0.visibility > $1.visibility }
            if $0.centerDistance != $1.centerDistance { return $0.centerDistance < $1.centerDistance }
            return $0.renderID.uuidString < $1.renderID.uuidString
        }
        var winner = sceneIsActive && blockedModals.isEmpty ? ranked.first : nil
        // Small geometry changes should not bounce playback between neighboring cards.
        if let best = winner, let activeRenderID, let current = candidates[activeRenderID],
           current.visibility >= best.visibility - 0.08, current.centerDistance <= best.centerDistance + 80 {
            winner = current
        }
        guard let winner else {
            pauseIfNeeded()
            if player.currentItem != nil {
                player.replaceCurrentItem(with: nil)
                ActivityFeedPerformance.increment("playerItemReplacements")
            }
            if activeRenderID != nil { activeRenderID = nil; ActivityFeedPerformance.increment("playbackStatePublications") }
            if activeMediaID != nil { activeMediaID = nil; ActivityFeedPerformance.increment("playbackStatePublications") }
            loadedMediaID = nil
            needsPlaybackReconciliation = false
            return
        }
        let didChangeMedia = loadedMediaID != winner.mediaID
        let didChangeRender = activeRenderID != winner.renderID
        if didChangeMedia {
            pauseIfNeeded()
            player.replaceCurrentItem(with: AVPlayerItem(url: winner.file.url))
            ActivityFeedPerformance.increment("playerItemReplacements")
            loadedMediaID = winner.mediaID
            if !isMuted { isMuted = true; ActivityFeedPerformance.increment("playbackStatePublications") }
            player.isMuted = true
        }
        if didChangeRender { activeRenderID = winner.renderID; ActivityFeedPerformance.increment("playbackStatePublications") }
        if activeMediaID != winner.mediaID { activeMediaID = winner.mediaID; ActivityFeedPerformance.increment("playbackStatePublications") }
        // Geometry alone must not repeatedly command playback or override a user's pause.
        if didChangeMedia || didChangeRender || needsPlaybackReconciliation {
            if manuallyPaused.contains(winner.mediaID) { pauseIfNeeded() } else { playIfNeeded() }
            needsPlaybackReconciliation = false
        }
    }

    private func writeDiagnostics() {
        #if DEBUG
        guard ActivityFeedPerformance.isEnabled, !diagnosticWriteInFlight,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let time = player.currentTime().seconds
        let snapshot: [String: Any] = [
            "activeMediaID": activeMediaID?.uuidString ?? "",
            "activeRenderID": activeRenderID?.uuidString ?? "",
            "loadedMediaID": loadedMediaID?.uuidString ?? "",
            "playerIdentity": String(describing: ObjectIdentifier(player)),
            "playerInstances": 1,
            "loadedItems": player.currentItem == nil ? 0 : 1,
            "isMuted": player.isMuted,
            "timeControlStatus": player.timeControlStatus.rawValue,
            "currentTime": time.isFinite ? time : 0,
            "manuallyPaused": activeMediaID.map { manuallyPaused.contains($0) } ?? false,
            "manuallyPausedMediaIDs": manuallyPaused.map(\.uuidString).sorted(),
            "sceneEligible": sceneIsActive,
            "modalBlocks": blockedModals.count,
            "candidateCount": candidates.count,
            "registrations": registrationDiagnostics,
            "performanceCounters": ActivityFeedPerformance.snapshot(),
            "timestamp": Date().timeIntervalSince1970
        ]
        diagnosticWriteInFlight = true
        diagnosticQueue.async { [weak self] in
            if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) {
                try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
                try? data.write(to: documents.appendingPathComponent("activity-feed-playback.json"), options: .atomic)
            }
            Task { @MainActor [weak self] in self?.diagnosticWriteInFlight = false }
        }
        #endif
    }
}

@MainActor
final class SportsActivityFeedStore: ObservableObject {
    fileprivate let playback = ActivityPlaybackCoordinator()
    private let authors = [ActivityAuthor.current, .anna, .max]
    @Published fileprivate var interestedAuthorIDs = Set<String>()
    @Published fileprivate var posts: [SportsActivityPost] = [
        SportsActivityPost(
            authorID: ActivityAuthor.anna.id, sport: .tennis,
            time: L10n.string("35 min ago", "35 мин назад"),
            caption: L10n.string("Tennis and a little fitness. A good evening of training 🎾", "Теннис и немного физподготовки. Хороший тренировочный вечер 🎾"),
            media: [.init(media: .bundledPhoto("hero-tennis")), .init(media: .bundledPhoto("hero-fitness"))], likes: 24
        ),
        SportsActivityPost(
            authorID: ActivityAuthor.max.id, sport: .padel,
            time: L10n.string("2 hours ago", "2 часа назад"),
            caption: L10n.string("That feeling after a great practice. Finally getting the hang of playing off the glass!", "То самое чувство после хорошей тренировки. Наконец-то получается играть от стекла!"),
            media: [.init(media: .bundledPhoto("hero-padel"))], likes: 18
        )
    ]

    init() {
        #if DEBUG
        if let source = SportsActivityFeedPreview.videoFixtureURL {
            for index in (1...2).reversed() {
                guard let imported = try? ActivityImportedFile.copy(source, isVideo: true) else { continue }
                posts.insert(SportsActivityPost(
                    authorID: ActivityAuthor.current.id, sport: .tennis,
                    time: L10n.string("Local QA fixture", "Локальный QA-пример"),
                    caption: "QA \(index) · \(L10n.string("Video and photo", "Видео и фото"))",
                    media: [.init(media: .video(imported.file)), .init(media: .bundledPhoto(index == 1 ? "hero-tennis" : "hero-fitness"))],
                    likes: 0
                ), at: 0)
            }
        }
        #endif
    }

    fileprivate func toggleInterest(_ authorID: String) {
        guard authorID != ActivityAuthor.current.id, author(authorID) != nil else { return }
        if interestedAuthorIDs.contains(authorID) { interestedAuthorIDs.remove(authorID) }
        else { interestedAuthorIDs.insert(authorID) }
    }

    fileprivate func author(_ id: String) -> ActivityAuthor? { authors.first { $0.id == id } }

    fileprivate func toggleLike(_ id: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].isLiked.toggle()
        posts[index].likes += posts[index].isLiked ? 1 : -1
    }

    @discardableResult
    fileprivate func publish(media: [ActivityMediaItem], caption: String, sport: Sport, place: ActivityPlaceTag?) -> Bool {
        guard (1...ActivityFeedStyle.maximumMediaCount).contains(media.count) else { return false }
        posts.insert(SportsActivityPost(
            authorID: ActivityAuthor.current.id, sport: sport,
            time: L10n.string("Just now", "Только что"), caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
            media: media, likes: 0, place: place
        ), at: 0)
        return true
    }

    fileprivate func delete(_ id: UUID) {
        guard let post = posts.first(where: { $0.id == id }), post.isOwn else { return }
        playback.removeMedia(Set(post.media.map(\.id)))
        post.media.forEach { $0.media.removeOwnedFile() }
        posts.removeAll { $0.id == id }
    }
}

struct SportsActivityFeedView: View {
    @ObservedObject var store: SportsActivityFeedStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsComposer = false
    @State private var selectedAuthor: ActivityAuthor?
    @State private var isVisible = false

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header.id("feed-top")
                        Button { showsComposer = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(AppTheme.court, in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.string("How was your workout?", "Как прошла тренировка?"))
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(L10n.string("Share up to 5 photos and videos", "До 5 фото и видео в одном посте"))
                                        .font(.system(size: 13)).foregroundStyle(ActivityFeedStyle.muted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 21))
                                    .foregroundStyle(ActivityFeedStyle.muted)
                            }
                            .padding(16)
                            .background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        ForEach(store.posts) { post in
                            if let author = store.author(post.authorID) {
                                ActivityPostCard(
                                    post: post, author: author, playback: store.playback,
                                    viewport: viewport.frame(in: .global), isActive: isVisible && !showsComposer && selectedAuthor == nil,
                                    onLike: { store.toggleLike(post.id) }, onDelete: { store.delete(post.id) },
                                    onAuthor: { selectedAuthor = author }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
                }
                .onChange(of: store.posts.first?.id) { _ in
                    withAnimation { proxy.scrollTo("feed-top", anchor: .top) }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .navigationTitle(L10n.string("Activity", "Лента"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showsComposer = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel(L10n.string("New post", "Новая публикация"))
            }
        }
        .sheet(isPresented: $showsComposer) {
            ActivityPostComposer(playback: store.playback) { media, caption, sport, place in
                store.publish(media: media, caption: caption, sport: sport, place: place)
            }
        }
        .sheet(item: $selectedAuthor) { author in
            ActivityAuthorProfileView(author: author, store: store)
        }
        .onAppear { isVisible = true; store.playback.setSceneActive(scenePhase == .active) }
        .onChange(of: scenePhase) { store.playback.setSceneActive($0 == .active) }
        .onDisappear { isVisible = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.string("In motion", "В движении"))
                .font(.system(size: 30, weight: .bold))
            Text(L10n.string("Training, progress and moments in sport", "Тренировки, прогресс и моменты в спорте"))
                .font(.system(size: 14)).foregroundStyle(ActivityFeedStyle.muted)
            Text(L10n.string("Prototype · posts are visible only to you", "Макет · публикации видны только вам"))
                .font(.system(size: 11)).foregroundStyle(ActivityFeedStyle.muted).padding(.top, 2)
        }
        .padding(.bottom, 2)
    }
}

private struct ActivityAuthorProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let author: ActivityAuthor
    @ObservedObject var store: SportsActivityFeedStore
    @State private var isVisible = false

    private var posts: [SportsActivityPost] { store.posts.filter { $0.authorID == author.id } }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(author.initials)
                                .font(.system(size: 24, weight: .semibold))
                                .frame(width: 76, height: 76)
                                .background(AppTheme.court.opacity(0.42), in: Circle())
                            Text(author.name).font(.system(size: 26, weight: .bold))
                            Text(author.isCurrent ? L10n.string("Your local profile", "Ваш локальный профиль") : L10n.string("Demo profile", "Демонстрационный профиль"))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(ActivityFeedStyle.muted)
                            Text(author.bio).font(.system(size: 15)).lineSpacing(4)
                            if !author.sports.isEmpty {
                                Text(author.sports.map(\.title).joined(separator: " · "))
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(AppTheme.court)
                            }
                            if !author.isCurrent {
                                let hasInterest = store.interestedAuthorIDs.contains(author.id)
                                Button { store.toggleInterest(author.id) } label: {
                                    Label(hasInterest ? L10n.string("Cancel interest", "Отменить интерес") : L10n.string("I'd like to play", "Хочу сыграть"),
                                          systemImage: hasInterest ? "checkmark.circle.fill" : "sportscourt")
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                                        .background(AppTheme.court.opacity(hasInterest ? 0.22 : 0.7), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                Text(hasInterest
                                     ? L10n.string("Interest saved in this prototype. No request was sent and no match was created.", "Интерес сохранён в макете. Заявка не отправлена, взаимный матч не создан.")
                                     : L10n.string("Try expressing interest. This demo profile cannot receive requests.", "Попробуйте проявить интерес. Демонстрационный профиль не получает заявки."))
                                    .font(.system(size: 12)).foregroundStyle(ActivityFeedStyle.muted)
                            }
                            Text(L10n.string("Prototype · posts are visible only to you", "Макет · публикации видны только вам"))
                                .font(.system(size: 12)).foregroundStyle(ActivityFeedStyle.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        .background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 26))
                        Text("\(L10n.string("Posts", "Публикации")) · \(posts.count)")
                            .font(.system(size: 20, weight: .bold))
                        if posts.isEmpty {
                            Text(L10n.string("No posts yet", "Пока нет публикаций"))
                                .foregroundStyle(ActivityFeedStyle.muted).padding(.vertical, 20)
                        }
                        ForEach(posts) { post in
                            ActivityPostCard(
                                post: post, author: author, playback: store.playback,
                                viewport: viewport.frame(in: .global), isActive: isVisible,
                                onLike: { store.toggleLike(post.id) }, onDelete: { store.delete(post.id) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.black.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle(L10n.string("Profile", "Профиль"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.string("Done", "Готово")) { dismiss() }.tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

private struct ActivityPostCard: View {
    let post: SportsActivityPost
    let author: ActivityAuthor
    let playback: ActivityPlaybackCoordinator
    let viewport: CGRect
    let isActive: Bool
    let onLike: () -> Void
    let onDelete: () -> Void
    var onAuthor: (() -> Void)?
    @State private var selectedPlace: ActivityPlaceTag?
    @State private var placeModalID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                if let onAuthor {
                    Button(action: onAuthor) { authorLabel }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(L10n.string("Open profile", "Открыть профиль")): \(author.name)")
                } else {
                    authorLabel
                }
                Spacer(minLength: 0)
                if post.isOwn {
                    Menu {
                        Button(L10n.string("Delete post", "Удалить публикацию"), role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 36, height: 44)
                    }
                    .accessibilityLabel(L10n.string("Post actions", "Действия с публикацией"))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            ActivityMediaCarousel(items: post.media, playback: playback, viewport: viewport, isActive: isActive && selectedPlace == nil)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipped()
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Button(action: onLike) {
                        HStack(spacing: 7) {
                            Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 22)).foregroundStyle(post.isLiked ? Color.red : .white)
                            Text("\(post.likes)").font(.system(size: 14, weight: .medium))
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(post.isLiked ? L10n.string("Unlike", "Убрать отметку нравится") : L10n.string("Like", "Нравится"))
                    .accessibilityValue("\(post.likes)")
                    Spacer()
                    Text(post.sport.title)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(AppTheme.court.opacity(0.24), in: Capsule())
                }
                if let place = post.place {
                    Button { selectedPlace = place } label: {
                        Label(place.title, systemImage: place.clubID == nil ? "mappin.and.ellipse" : "sportscourt")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(AppTheme.court)
                            .frame(minHeight: 36, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(L10n.string("Training location", "Место тренировки")): \(place.title)")
                }
                if !post.caption.isEmpty {
                    Text(post.caption).font(.system(size: 14)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 18).padding(.top, 4)
        }
        .background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 26))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .sheet(item: $selectedPlace) { place in
            ActivityPlaceDetailView(place: place)
                .onAppear { playback.setModalBlocked(placeModalID, true) }
                .onDisappear { playback.setModalBlocked(placeModalID, false) }
        }
    }

    private var authorLabel: some View {
        HStack(spacing: 11) {
            Text(author.initials)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(AppTheme.court.opacity(0.42), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(author.name).font(.system(size: 15, weight: .semibold))
                Text("\(post.sport.title) · \(post.time)")
                    .font(.system(size: 12)).foregroundStyle(ActivityFeedStyle.muted)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ActivityMediaCarousel: View {
    let items: [ActivityMediaItem]
    let playback: ActivityPlaybackCoordinator
    let viewport: CGRect
    let isActive: Bool
    var onRemove: ((UUID) -> Void)?
    @State private var selectedID: UUID?
    @State private var isVisible = false
    @State private var renderID = UUID()
    @State private var hasRegisteredVideo = false

    private var currentID: UUID? {
        items.contains(where: { $0.id == selectedID }) ? selectedID : items.first?.id
    }
    private var currentIndex: Int { items.firstIndex { $0.id == currentID } ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let intersection = frame.intersection(viewport)
            let fraction = frame.height > 0 && frame.width > 0 && !intersection.isNull
                ? Double(intersection.height * intersection.width / (frame.height * frame.width)) : 0
            let visibleFraction = (fraction * 100).rounded() / 100
            let distance = Double(abs(frame.midY - viewport.midY)).rounded()
            let eligibility = ActivityVideoEligibility(isActive: isActive, visibleFraction: visibleFraction, centerDistance: distance)
            Group {
                if items.count == 1, let item = items.first {
                    ActivityMediaView(item: item, playback: playback, renderID: renderID)
                } else {
                    TabView(selection: Binding(get: { currentID }, set: { selectedID = $0 })) {
                        ForEach(items) { item in
                            ActivityMediaView(item: item, playback: playback, renderID: renderID)
                                .tag(Optional(item.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
            }
            .onAppear { isVisible = true; updateCandidate(eligibility) }
            .onChange(of: eligibility) { value in if isVisible { updateCandidate(value) } }
            .onChange(of: currentID) { _ in if isVisible { updateCandidate(eligibility) } }
            .overlay(alignment: .bottom) {
                if items.count > 1 {
                    HStack {
                        pageButton(offset: -1, symbol: "chevron.left", label: L10n.string("Previous photo or video", "Предыдущее фото или видео"))
                        Spacer()
                        pageButton(offset: 1, symbol: "chevron.right", label: L10n.string("Next photo or video", "Следующее фото или видео"))
                    }
                    .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !items.isEmpty {
                    Text("\(currentIndex + 1)/\(items.count)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.black.opacity(0.62), in: Capsule())
                        .padding(12)
                        .accessibilityLabel(L10n.string("Post media", "Медиа публикации"))
                        .accessibilityValue("\(currentIndex + 1) \(L10n.string("of", "из")) \(items.count)")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: movePage(by: 1)
                            case .decrement: movePage(by: -1)
                            @unknown default: break
                            }
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let onRemove, let currentID {
                    Button { onRemove(currentID) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.62), in: Circle())
                    }
                    .buttonStyle(.plain).padding(8)
                    .accessibilityLabel(L10n.string("Remove selected photo or video", "Удалить выбранное фото или видео"))
                }
            }
        }
        .onDisappear {
            isVisible = false
            if hasRegisteredVideo { playback.remove(renderID); hasRegisteredVideo = false }
        }
    }

    private func updateCandidate(_ eligibility: ActivityVideoEligibility) {
        let item = items.first { $0.id == currentID }
        if let item, case .video(let file) = item.media {
            if !hasRegisteredVideo { hasRegisteredVideo = true }
            playback.recordEligibility(renderID: renderID, mediaID: item.id, eligibility: eligibility, isVideo: true)
            playback.update(renderID: renderID, mediaID: item.id, file: file, eligibility: eligibility)
        } else if hasRegisteredVideo {
            hasRegisteredVideo = false
            playback.recordEligibility(renderID: renderID, mediaID: item?.id, eligibility: eligibility, isVideo: false)
            playback.remove(renderID)
        }
    }

    private func movePage(by offset: Int) {
        guard !items.isEmpty else { return }
        let index = min(max(currentIndex + offset, 0), items.count - 1)
        withAnimation { selectedID = items[index].id }
    }

    private func pageButton(offset: Int, symbol: String, label: String) -> some View {
        Button { movePage(by: offset) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(!(0..<items.count).contains(currentIndex + offset))
        .opacity((0..<items.count).contains(currentIndex + offset) ? 1 : 0.3)
    }
}

private struct ActivityMediaView: View {
    let item: ActivityMediaItem
    let playback: ActivityPlaybackCoordinator
    let renderID: UUID

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch item.media {
                case .bundledPhoto(let name):
                    ActivityBundledPhotoView(name: name)
                case .photo(let image):
                    Image(uiImage: image).resizable().scaledToFill()
                case .video(let file):
                    ActivityVideoView(file: file, mediaID: item.id, playback: playback, renderID: renderID)
                        .id(item.id)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .accessibilityLabel(L10n.string("Training media", "Фото или видео с тренировки"))
    }
}

private struct ActivityBundledPhotoView: View {
    let name: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.gray.opacity(0.2).overlay(Image(systemName: "photo")) }
        }
        .task(id: name) {
            let loadedImage = await ActivityPhotoLoader.shared.bundledImage(named: name)
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}

private struct ActivityPlayerSurface: UIViewRepresentable {
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.playerLayer.player = nil }
}

private struct ActivityVideoView: View {
    let file: ActivityOwnedFile
    let mediaID: UUID
    @ObservedObject var playback: ActivityPlaybackCoordinator
    let renderID: UUID

    private var isSelected: Bool { playback.activeRenderID == renderID && playback.activeMediaID == mediaID }

    var body: some View {
        ZStack {
            Color.black
            if isSelected {
                ActivityPlayerSurface(player: playback.player)
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Button { playback.togglePlayback(renderID) } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 46, height: 46)
                                .background(.black.opacity(0.65), in: Circle())
                        }
                        .accessibilityLabel(playback.isPlaying ? L10n.string("Pause video", "Пауза видео") : L10n.string("Play video", "Воспроизвести видео"))
                        Button { playback.toggleMute() } label: {
                            Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .frame(width: 46, height: 46)
                                .background(.black.opacity(0.65), in: Circle())
                        }
                        .accessibilityLabel(playback.isMuted ? L10n.string("Unmute video", "Включить звук") : L10n.string("Mute video", "Выключить звук"))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom, 42)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill").font(.system(size: 30))
                    Text(L10n.string("Video", "Видео")).font(.system(size: 13))
                }
                .foregroundStyle(ActivityFeedStyle.muted)
            }
        }
    }
}

private struct ActivityImportedFile: Transferable {
    let file: ActivityOwnedFile
    let isVideo: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try copy(received.file, isVideo: true)
        }
        FileRepresentation(importedContentType: .image) { received in
            try copy(received.file, isVideo: false)
        }
    }

    fileprivate static func copy(_ source: URL, isVideo: Bool) throws -> Self {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= (isVideo ? 200 : 30) * 1_024 * 1_024 else { throw ActivityImportError.tooLarge }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SportsActivityFeed", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
        let ownedFile = ActivityOwnedFile(url: target)
        try FileManager.default.copyItem(at: source, to: target)
        return Self(file: ownedFile, isVideo: isVideo)
    }
}

private enum ActivityImportError: Error { case tooLarge, invalidMedia }

private struct ActivityPostComposer: View {
    @Environment(\.dismiss) private var dismiss
    let playback: ActivityPlaybackCoordinator
    @EnvironmentObject private var appModel: AppModel
    let onPublish: ([ActivityMediaItem], String, Sport, ActivityPlaceTag?) -> Bool
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var media: [ActivityMediaItem] = []
    @State private var caption = ""
    @State private var sport: Sport = .tennis
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var published = false
    @State private var isVisible = false
    @State private var importTask: Task<Void, Never>?
    @State private var importGeneration = UUID()
    @State private var place: ActivityPlaceTag?
    @State private var showsPlacePicker = false
    @State private var showsPhotosPicker = false
    @State private var pickerModalID = UUID()
    @State private var didSeedFixture = false

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !media.isEmpty {
                            ActivityMediaCarousel(
                                items: media, playback: playback, viewport: viewport.frame(in: .global),
                                isActive: isVisible && !showsPlacePicker && !showsPhotosPicker, onRemove: remove
                            )
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        HStack {
                            Text(L10n.string("Photos and videos", "Фото и видео"))
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("\(media.count)/\(ActivityFeedStyle.maximumMediaCount)")
                                .font(.system(size: 14, weight: .medium).monospacedDigit())
                                .foregroundStyle(ActivityFeedStyle.muted)
                        }
                        Button { showsPhotosPicker = true } label: {
                            VStack(spacing: 12) {
                                if isLoading {
                                    ProgressView().tint(.white)
                                    Text(L10n.string("Loading…", "Загружаем…"))
                                } else {
                                    Image(systemName: "photo.badge.plus").font(.system(size: media.isEmpty ? 34 : 20))
                                    Text(pickerTitle).font(.system(size: 15, weight: .semibold))
                                    if media.isEmpty {
                                        Text(L10n.string("Choose 1–5 photos and videos in order", "Выберите от 1 до 5 фото и видео по порядку"))
                                            .font(.system(size: 13)).foregroundStyle(ActivityFeedStyle.muted)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, media.isEmpty ? 40 : 16)
                            .background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5])))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || media.count >= ActivityFeedStyle.maximumMediaCount)
                        .opacity(media.count >= ActivityFeedStyle.maximumMediaCount ? 0.55 : 1)
                        .photosPicker(isPresented: $showsPhotosPicker, selection: $selectedItems,
                                      maxSelectionCount: max(1, ActivityFeedStyle.maximumMediaCount - media.count),
                                      selectionBehavior: .ordered, matching: .any(of: [.images, .videos]))
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.string("Caption", "Подпись")).font(.system(size: 14, weight: .semibold))
                            TextField(L10n.string("How did it go?", "Как всё прошло?"), text: $caption, axis: .vertical)
                                .lineLimit(3...6).font(.system(size: 15))
                                .onChange(of: caption) { value in if value.count > 1_000 { caption = String(value.prefix(1_000)) } }
                        }
                        .padding(18).background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 24))
                        HStack {
                            Text(L10n.string("Sport", "Вид спорта")).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Picker(L10n.string("Sport", "Вид спорта"), selection: $sport) {
                                ForEach(Sport.allCases) { Text($0.title).tag($0) }
                            }
                            .tint(.white)
                        }
                        .padding(14).background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 24))
                        HStack(spacing: 12) {
                            Button { showsPlacePicker = true } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(place?.title ?? L10n.string("Add club or location", "Добавить клуб или место"), systemImage: "mappin.and.ellipse")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(place?.address ?? L10n.string("Optional · choose where you played", "Необязательно · выберите, где играли"))
                                        .font(.system(size: 12)).foregroundStyle(ActivityFeedStyle.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            if place != nil {
                                Button { place = nil } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L10n.string("Remove location", "Убрать место"))
                            }
                        }
                        .padding(16).background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 24))
                        Text(L10n.string("Prototype · posts are visible only to you", "Макет · публикации видны только вам"))
                            .font(.system(size: 12)).foregroundStyle(ActivityFeedStyle.muted)
                    }
                    .padding(16)
                }
            }
            .background(Color.black.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle(L10n.string("New post", "Новый пост"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.string("Cancel", "Отмена")) { cancelImport(); dismiss() }.tint(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.string("Post", "Опубликовать")) {
                        guard !media.isEmpty, !isLoading, !published else { return }
                        guard onPublish(media, caption, sport, place) else { return }
                        published = true
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold)).tint(AppTheme.court)
                    .disabled(media.isEmpty || isLoading || published)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsPlacePicker) {
            ActivityPlacePicker(
                repository: SportsActivityFeedPreview.isEnabled ? MockRepository() : appModel.repository,
                initialCity: appModel.currentUser?.city ?? appModel.guestDraft.city,
                isDemo: SportsActivityFeedPreview.isEnabled
            ) { place = $0 }
        }
        .onChange(of: showsPhotosPicker) { playback.setModalBlocked(pickerModalID, $0 || showsPlacePicker) }
        .onChange(of: showsPlacePicker) { playback.setModalBlocked(pickerModalID, $0 || showsPhotosPicker) }
        .onChange(of: selectedItems) { items in if !items.isEmpty { startImport(items) } }
        .onAppear {
            isVisible = true
            #if DEBUG
            if !didSeedFixture, let source = SportsActivityFeedPreview.videoFixtureURL {
                didSeedFixture = true
                if let imported = try? ActivityImportedFile.copy(source, isVideo: true) {
                    media = [.init(media: .video(imported.file))]
                    caption = L10n.string("QA · local composer example", "QA · локальный пример публикации")
                }
            }
            #endif
        }
        .onDisappear {
            isVisible = false
            cancelImport()
            playback.setModalBlocked(pickerModalID, false)
            if !published {
                playback.removeMedia(Set(media.map(\.id)))
                media.forEach { $0.media.removeOwnedFile() }
                media = []
            }
        }
    }

    private var pickerTitle: String {
        if media.count >= ActivityFeedStyle.maximumMediaCount { return L10n.string("All 5 added", "Добавлено 5 из 5") }
        return media.isEmpty ? L10n.string("Photo or video from training", "Фото или видео с тренировки") : L10n.string("Add photos or videos", "Добавить фото или видео")
    }

    private func remove(_ id: UUID) {
        guard let item = media.first(where: { $0.id == id }) else { return }
        playback.removeMedia([id])
        item.media.removeOwnedFile()
        media.removeAll { $0.id == id }
    }

    private func cancelImport() {
        importGeneration = UUID()
        importTask?.cancel()
        importTask = nil
        isLoading = false
    }

    @MainActor
    private func startImport(_ items: [PhotosPickerItem]) {
        cancelImport()
        let generation = importGeneration
        let batch = Array(items.prefix(ActivityFeedStyle.maximumMediaCount - media.count))
        isLoading = true
        errorMessage = nil
        importTask = Task { @MainActor in
            var failedCount = 0
            for item in batch {
                do {
                    try Task.checkCancellation()
                    guard let file = try await item.loadTransferable(type: ActivityImportedFile.self) else { throw ActivityImportError.invalidMedia }
                    try Task.checkCancellation()
                    let newMedia: ActivityMedia
                    if file.isVideo {
                        let asset = AVURLAsset(url: file.file.url)
                        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
                            throw ActivityImportError.invalidMedia
                        }
                        newMedia = .video(file.file)
                    } else {
                        guard let image = await ActivityPhotoLoader.shared.importedImage(file: file.file) else {
                            throw ActivityImportError.invalidMedia
                        }
                        newMedia = .photo(image)
                    }
                    try Task.checkCancellation()
                    guard generation == importGeneration else { return }
                    if media.count < ActivityFeedStyle.maximumMediaCount { media.append(.init(media: newMedia)) }
                } catch {
                    guard !Task.isCancelled, generation == importGeneration else { return }
                    failedCount += 1
                }
            }
            guard !Task.isCancelled, generation == importGeneration else { return }
            isLoading = false
            selectedItems = []
            importTask = nil
            if failedCount > 0 {
                errorMessage = L10n.string(
                    "Couldn't load \(failedCount) file(s). Other selections were kept. Try photos up to 30 MB or videos up to 200 MB.",
                    "Не удалось загрузить: \(failedCount). Остальные файлы сохранены. Попробуйте фото до 30 МБ или видео до 200 МБ."
                )
            }
        }
    }
}

private struct ActivityPlacePicker: View {
    @Environment(\.dismiss) private var dismiss
    let repository: TennisRepository
    let isDemo: Bool
    let onSelect: (ActivityPlaceTag) -> Void
    @State private var city: String
    @State private var query = ""
    @State private var courts: [Court] = []
    @State private var suggestions: [AddressSuggestion] = []
    @State private var isLoadingCourts = false
    @State private var isLoadingSuggestions = false
    @State private var courtError: String?
    @State private var addressError: String?
    @State private var retryRevision = 0

    init(repository: TennisRepository, initialCity: String, isDemo: Bool, onSelect: @escaping (ActivityPlaceTag) -> Void) {
        self.repository = repository
        self.isDemo = isDemo
        self.onSelect = onSelect
        _city = State(initialValue: initialCity)
    }

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cityName: String? {
        let value = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    private var filteredCourts: [Court] {
        let query = normalizedQuery
        return courts.filter {
            query.isEmpty || [$0.name, $0.address, $0.city ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.string("Choose the club, park or address where you played. Location is added only when you select it.", "Выберите клуб, парк или адрес, где играли. Место добавится только после вашего выбора."))
                        .font(.system(size: 13)).foregroundStyle(ActivityFeedStyle.muted)
                    if isDemo {
                        Text(L10n.string("Demo location catalog", "Демонстрационный каталог мест"))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.court)
                    }
                    VStack(spacing: 12) {
                        TextField(L10n.string("City", "Город"), text: $city)
                            .accessibilityLabel(L10n.string("Location search city", "Город поиска места"))
                        Divider().overlay(.white.opacity(0.15))
                        TextField(L10n.string("Club, park or address", "Клуб, парк или адрес"), text: $query)
                            .accessibilityLabel(L10n.string("Search training location", "Поиск места тренировки"))
                    }
                    .font(.system(size: 15)).padding(16)
                    .background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 20))
                    Text(L10n.string("Clubs", "Клубы")).font(.system(size: 19, weight: .bold))
                    if isLoadingCourts { ProgressView().tint(.white) }
                    if let courtError { errorRow(courtError) }
                    if !isLoadingCourts, courtError == nil, filteredCourts.isEmpty {
                        Text(L10n.string("No matching clubs. Search for a park or address below.", "Подходящих клубов нет. Найдите парк или адрес ниже."))
                            .font(.system(size: 13)).foregroundStyle(ActivityFeedStyle.muted)
                    }
                    ForEach(filteredCourts.prefix(30)) { court in
                        placeButton(title: court.name, subtitle: court.address, icon: "sportscourt") {
                            choose(ActivityPlaceTag(clubID: court.id, title: court.name, address: court.address,
                                                    latitude: court.locationLat, longitude: court.locationLng))
                        }
                    }
                    if normalizedQuery.count >= 3 {
                        Text(L10n.string("Places and addresses", "Места и адреса")).font(.system(size: 19, weight: .bold))
                        if isLoadingSuggestions { ProgressView().tint(.white) }
                        if let addressError { errorRow(addressError) }
                        ForEach(suggestions.prefix(10)) { suggestion in
                            placeButton(title: suggestion.title, subtitle: suggestion.address, icon: "mappin.and.ellipse") {
                                choose(ActivityPlaceTag(clubID: nil, title: suggestion.title, address: suggestion.address,
                                                        latitude: suggestion.lat, longitude: suggestion.lng))
                            }
                        }
                        if !isLoadingSuggestions, suggestions.isEmpty {
                            placeButton(
                                title: "\(L10n.string("Use", "Использовать")): \(normalizedQuery)",
                                subtitle: L10n.string("Text label only · no map point", "Только текстовая отметка · без точки на карте"), icon: "text.bubble"
                            ) {
                                let address = [normalizedQuery, cityName].compactMap { $0 }.joined(separator: ", ")
                                choose(ActivityPlaceTag(clubID: nil, title: normalizedQuery, address: address, latitude: nil, longitude: nil))
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle(L10n.string("Training location", "Место тренировки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.string("Cancel", "Отмена")) { dismiss() }.tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: "\(cityName ?? "")|\(retryRevision)") { await loadCourts() }
        .task(id: "\(cityName ?? "")|\(normalizedQuery)|\(retryRevision)") { await searchPlaces() }
        .onChange(of: city) { value in if value.count > 100 { city = String(value.prefix(100)) } }
        .onChange(of: query) { value in if value.count > 200 { query = String(value.prefix(200)) } }
    }

    private func placeButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(AppTheme.court).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(ActivityFeedStyle.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle").foregroundStyle(ActivityFeedStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(ActivityFeedStyle.card, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func errorRow(_ message: String) -> some View {
        HStack {
            Text(message).font(.system(size: 12)).foregroundStyle(.orange)
            Spacer()
            Button(L10n.string("Retry", "Повторить")) { retryRevision += 1 }.font(.system(size: 13, weight: .semibold))
        }
    }

    private func choose(_ tag: ActivityPlaceTag) { onSelect(tag); dismiss() }

    @MainActor
    private func loadCourts() async {
        courts = []
        courtError = nil
        isLoadingCourts = true
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            let result = try await repository.fetchCourts(city: cityName)
            try Task.checkCancellation()
            courts = result
            isLoadingCourts = false
        } catch {
            guard !Task.isCancelled else { return }
            isLoadingCourts = false
            courtError = L10n.string("Couldn't load clubs. You can still add an address.", "Не удалось загрузить клубы. Можно указать адрес.")
        }
    }

    @MainActor
    private func searchPlaces() async {
        suggestions = []
        addressError = nil
        guard normalizedQuery.count >= 3 else { isLoadingSuggestions = false; return }
        isLoadingSuggestions = true
        let query = normalizedQuery
        let city = cityName
        do {
            try await Task.sleep(nanoseconds: 350_000_000)
            let result = try await repository.fetchAddressSuggestions(query: query, city: city)
            try Task.checkCancellation()
            guard query == normalizedQuery, city == cityName else { return }
            suggestions = result
            isLoadingSuggestions = false
        } catch {
            guard !Task.isCancelled else { return }
            isLoadingSuggestions = false
            addressError = L10n.string("Address search is unavailable. You can add a text label.", "Поиск адресов недоступен. Можно добавить текстовую отметку.")
        }
    }
}

private struct ActivityPlaceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let place: ActivityPlaceTag

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(place.clubID == nil ? L10n.string("Training location", "Место тренировки") : L10n.string("Club", "Клуб"),
                          systemImage: place.clubID == nil ? "mappin.and.ellipse" : "sportscourt")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(AppTheme.court)
                    Text(place.title).font(.system(size: 26, weight: .bold))
                    Text(place.address).font(.system(size: 15)).foregroundStyle(ActivityFeedStyle.muted)
                    if let coordinate = place.coordinate {
                        Map(coordinateRegion: .constant(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))),
                            interactionModes: [.pan, .zoom], annotationItems: [place]) { _ in
                            MapMarker(coordinate: coordinate, tint: .green)
                        }
                        .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 24))
                        .accessibilityLabel("\(L10n.string("Selected training location on the map", "Выбранное место тренировки на карте")): \(place.title)")
                    } else {
                        Text(L10n.string("Text label only · no map point", "Только текстовая отметка · без точки на карте"))
                            .font(.system(size: 13)).foregroundStyle(ActivityFeedStyle.muted)
                    }
                    Text(L10n.string("Location was selected by the post author.", "Место выбрано автором публикации."))
                        .font(.system(size: 12)).foregroundStyle(ActivityFeedStyle.muted)
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea()).foregroundStyle(.white)
            .navigationTitle(L10n.string("Location", "Место"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.string("Done", "Готово")) { dismiss() }.tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
