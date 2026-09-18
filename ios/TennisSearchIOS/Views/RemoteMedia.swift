import AVFoundation
import ImageIO
import SwiftUI
import UIKit

// MARK: - Image pipeline

/// Where the bytes of a remote image come from. Public media goes through the shared
/// disk-cached session; authenticated media (chat attachments) passes its own fetch.
struct RemoteImageSource {
    let key: String
    let fetch: (URLSession) async throws -> Data

    static func url(_ url: URL) -> RemoteImageSource {
        RemoteImageSource(key: url.absoluteString) { session in
            let (data, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }
}

/// Downloads, downsamples and caches remote images, so revisiting a screen shows
/// them at once instead of reloading every photo like `AsyncImage` does.
final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RemoteMedia", isDirectory: true)
        // Uploaded media is UUID-named and served as immutable, so the protocol policy keeps it on disk.
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, directory: directory)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    func cachedImage(forKey key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
    }

    func cachedImage(for request: RemoteImageRequest) -> UIImage? {
        cachedImage(forKey: request.cacheKey)
    }

    func image(for request: RemoteImageRequest) async throws -> UIImage {
        if let cached = cachedImage(for: request) {
            return cached
        }

        let key = request.cacheKey
        let task: Task<UIImage, Error> = lock.withLock {
            if let existing = inFlight[key] {
                return existing
            }
            // Detached so a row scrolling away does not throw away a nearly finished download.
            let task = Task.detached(priority: .userInitiated) { [session] () throws -> UIImage in
                defer { self.lock.withLock { self.inFlight[key] = nil } }
                #if DEBUG
                // `-RemoteMediaDebugDelay 2` slows every image load down to review the loading animation.
                let debugDelay = UserDefaults.standard.double(forKey: "RemoteMediaDebugDelay")
                if debugDelay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(debugDelay * 1_000_000_000))
                }
                #endif
                let data = try await request.source.fetch(session)
                guard let image = Self.decode(data, fitting: request.pixelSize, contentMode: request.contentMode) else {
                    throw URLError(.cannotDecodeContentData)
                }
                self.store(image, forKey: key)
                return image
            }
            inFlight[key] = task
            return task
        }
        return try await task.value
    }

    /// Warms the cache for media the user is about to see (the next stories of a card).
    func prefetch(_ requests: [RemoteImageRequest]) {
        for request in requests where cachedImage(for: request) == nil {
            Task.detached(priority: .utility) { _ = try? await self.image(for: request) }
        }
    }

    private static func decode(_ data: Data, fitting pixelSize: CGSize, contentMode: ContentMode) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }

        var maxPixelSize = max(pixelSize.width, pixelSize.height)
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
           var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
           width > 0, height > 0 {
            // EXIF orientations 5...8 are rotated by 90°, so the displayed width is the stored height.
            if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
                swap(&width, &height)
            }
            let horizontal = pixelSize.width / width
            let vertical = pixelSize.height / height
            let scale = contentMode == .fill ? max(horizontal, vertical) : min(horizontal, vertical)
            maxPixelSize = min(max(width, height) * scale, max(width, height)).rounded(.up)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

struct RemoteImageRequest {
    let source: RemoteImageSource
    let pixelSize: CGSize
    let contentMode: ContentMode

    init(source: RemoteImageSource, pointSize: CGSize, scale: CGFloat, contentMode: ContentMode) {
        self.source = source
        self.contentMode = contentMode
        // Rounding up to 64 px lets views of almost the same size share one decoded bitmap.
        func bucket(_ value: CGFloat) -> CGFloat { (max(value * scale, 1) / 64).rounded(.up) * 64 }
        pixelSize = CGSize(width: bucket(pointSize.width), height: bucket(pointSize.height))
    }

    var cacheKey: String {
        "\(source.key)#\(Int(pixelSize.width))x\(Int(pixelSize.height))\(contentMode == .fill ? "f" : "t")"
    }
}

// MARK: - Loading indicators

/// How a media placeholder signals that loading is in progress.
struct MediaLoadingIndicator {
    var shimmerTint: Color?
    var spinnerTint: Color?

    static let shimmer = MediaLoadingIndicator(shimmerTint: .white, spinnerTint: nil)
    static let spinner = MediaLoadingIndicator(shimmerTint: nil, spinnerTint: MediaSpinner.brandTint)
    static let shimmerAndSpinner = MediaLoadingIndicator(shimmerTint: .white, spinnerTint: MediaSpinner.brandTint)

    static func shimmer(_ tint: Color) -> MediaLoadingIndicator {
        MediaLoadingIndicator(shimmerTint: tint, spinnerTint: nil)
    }
}

/// A soft band of light gliding across a gently breathing placeholder. All shimmers share
/// one clock, so a screen full of loading avatars moves in unison instead of flickering.
struct MediaShimmer: View {
    var tint: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                tint.opacity(0.08)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let period = 1.9
                    let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    // The band glides across in the first 65% of the period (eased at both ends)
                    // and rests off-screen for the rest, which reads calmer than a constant scroll.
                    let sweep = min(time / 0.65, 1)
                    let eased = sweep * sweep * (3 - 2 * sweep)
                    let center = -0.7 + eased * 2.4
                    let breath = 0.5 - 0.5 * cos(time * 2 * .pi)

                    ZStack {
                        tint.opacity(0.03 + 0.05 * breath)
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(0), location: 0),
                                .init(color: tint.opacity(0.08), location: 0.3),
                                .init(color: tint.opacity(0.32), location: 0.5),
                                .init(color: tint.opacity(0.08), location: 0.7),
                                .init(color: tint.opacity(0), location: 1)
                            ],
                            startPoint: UnitPoint(x: center - 0.45, y: 0.15),
                            endPoint: UnitPoint(x: center + 0.45, y: 0.85)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Branded loader: a glowing comet arc orbiting inside a frosted glass disc. It waits a
/// moment before appearing, so fast loads never flash it.
struct MediaSpinner: View {
    static let brandTint = Color(red: 0.58, green: 0.96, blue: 0.36)

    var tint: Color = MediaSpinner.brandTint
    var diameter: CGFloat = 50
    @State private var isVisible = false

    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.95) / 0.95 * 360

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 3)
                    .padding(diameter * 0.22)

                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [tint.opacity(0), tint.opacity(0.55), tint]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(0.72 * 360)
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .padding(diameter * 0.22)
                    .shadow(color: tint.opacity(0.7), radius: 5)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: diameter, height: diameter)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
            .environment(\.colorScheme, .dark)
        }
        .scaleEffect(isVisible ? 1 : 0.6)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { isVisible = true }
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.string("Loading", "Загрузка"))
    }
}

private struct MediaLoadingOverlay: ViewModifier {
    let indicator: MediaLoadingIndicator
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive, let tint = indicator.shimmerTint {
                    MediaShimmer(tint: tint)
                }
            }
            .overlay {
                if isActive, let tint = indicator.spinnerTint {
                    MediaSpinner(tint: tint)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
    }
}

extension View {
    func mediaLoadingOverlay(_ indicator: MediaLoadingIndicator, isActive: Bool = true) -> some View {
        modifier(MediaLoadingOverlay(indicator: indicator, isActive: isActive))
    }
}

// MARK: - Reveal transitions

/// A photo arriving over the network comes into focus: it sharpens out of a blur and
/// settles from a slight zoom while fading in.
private struct MediaRevealEffect: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isHidden ? 18 : 0, opaque: true)
            .scaleEffect(isHidden ? 1.08 : 1)
            .opacity(isHidden ? 0 : 1)
    }
}

/// The placeholder dissolves (blurs away) instead of just blinking out.
private struct MediaDissolveEffect: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isHidden ? 12 : 0)
            .opacity(isHidden ? 0 : 1)
    }
}

extension AnyTransition {
    static func mediaReveal(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .modifier(active: MediaRevealEffect(isHidden: true), identity: MediaRevealEffect(isHidden: false))
    }

    static func mediaPlaceholder(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity,
            removal: .modifier(active: MediaDissolveEffect(isHidden: true), identity: MediaDissolveEffect(isHidden: false))
        )
    }
}

extension Animation {
    static let mediaReveal = Animation.spring(response: 0.7, dampingFraction: 0.92)
}

// MARK: - Remote image

enum RemoteMediaPhase: Equatable {
    /// No source at all: the placeholder is the final state.
    case empty
    case loading
    case success
    case failed
}

/// Replacement for `AsyncImage`: cached and downsampled, animates the placeholder while
/// loading and cross-fades into the photo once it arrives.
struct RemoteImage<Placeholder: View>: View {
    private let source: RemoteImageSource?
    private let contentMode: ContentMode
    private let indicator: MediaLoadingIndicator
    private let onPhaseChange: ((RemoteMediaPhase) -> Void)?
    private let placeholder: (RemoteMediaPhase) -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: (key: String, image: UIImage)?
    @State private var failedKey: String?

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        indicator: MediaLoadingIndicator = .shimmer,
        onPhaseChange: ((RemoteMediaPhase) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping (RemoteMediaPhase) -> Placeholder
    ) {
        self.init(source: url.map(RemoteImageSource.url), contentMode: contentMode, indicator: indicator, onPhaseChange: onPhaseChange, placeholder: placeholder)
    }

    init(
        source: RemoteImageSource?,
        contentMode: ContentMode = .fill,
        indicator: MediaLoadingIndicator = .shimmer,
        onPhaseChange: ((RemoteMediaPhase) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping (RemoteMediaPhase) -> Placeholder
    ) {
        self.source = source
        self.contentMode = contentMode
        self.indicator = indicator
        self.onPhaseChange = onPhaseChange
        self.placeholder = placeholder
    }

    var body: some View {
        GeometryReader { proxy in
            let request = makeRequest(size: proxy.size)
            let image = request.flatMap(currentImage)
            let phase = phase(for: request, image: image)

            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.mediaReveal(reduceMotion: reduceMotion))
                } else {
                    // The clear base keeps the loading overlay visible when the placeholder itself is empty.
                    ZStack {
                        Color.clear
                        placeholder(phase)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mediaLoadingOverlay(indicator, isActive: phase == .loading)
                    .transition(.mediaPlaceholder(reduceMotion: reduceMotion))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: request?.cacheKey) {
                await load(request)
            }
            .onAppear { onPhaseChange?(phase) }
            .onChange(of: phase) { onPhaseChange?($0) }
        }
    }

    private func makeRequest(size: CGSize) -> RemoteImageRequest? {
        guard let source, size.width > 0, size.height > 0 else { return nil }
        return RemoteImageRequest(source: source, pointSize: size, scale: displayScale, contentMode: contentMode)
    }

    private func currentImage(for request: RemoteImageRequest) -> UIImage? {
        if let loaded, loaded.key == request.cacheKey {
            return loaded.image
        }
        return RemoteImagePipeline.shared.cachedImage(for: request)
    }

    private func phase(for request: RemoteImageRequest?, image: UIImage?) -> RemoteMediaPhase {
        if image != nil { return .success }
        guard let request else { return source == nil ? .empty : .loading }
        return failedKey == request.cacheKey ? .failed : .loading
    }

    private func load(_ request: RemoteImageRequest?) async {
        guard let request, currentImage(for: request) == nil else { return }
        do {
            let image = try await RemoteImagePipeline.shared.image(for: request)
            guard !Task.isCancelled else { return }
            withAnimation(.mediaReveal) {
                loaded = (request.cacheKey, image)
            }
        } catch {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                failedKey = request.cacheKey
            }
        }
    }
}

// MARK: - Remote video

enum RemoteVideoPhase: Equatable {
    case loading
    case playing
    case buffering
    case failed
}

/// Muted looping video that keeps its placeholder (with a shimmer) until the first frame
/// is on screen, then fades it away; a spinner shows while playback stalls on the network.
struct RemoteLoopingVideo<Placeholder: View>: View {
    let url: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var indicator: MediaLoadingIndicator = .shimmerAndSpinner
    var onPhaseChange: ((RemoteVideoPhase) -> Void)?
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: RemoteVideoPhase = .loading

    private var isShowingVideo: Bool {
        phase == .playing || phase == .buffering
    }

    var body: some View {
        ZStack {
            MutedLoopingVideoView(url: url, videoGravity: videoGravity) { newPhase in
                guard newPhase != phase else { return }
                withAnimation(.mediaReveal) { phase = newPhase }
                onPhaseChange?(newPhase)
            }
            // The first frame settles from a slight zoom as the placeholder dissolves above it.
            .scaleEffect(isShowingVideo || reduceMotion ? 1 : 1.08)

            if !isShowingVideo {
                ZStack {
                    Color.clear
                    placeholder()
                }
                .mediaLoadingOverlay(indicator, isActive: phase == .loading)
                .transition(.mediaPlaceholder(reduceMotion: reduceMotion))
            }

            if phase == .buffering, let tint = indicator.spinnerTint {
                MediaSpinner(tint: tint)
                    .transition(.opacity)
            }
        }
        .clipped()
        .onAppear { onPhaseChange?(phase) }
    }
}

struct MutedLoopingVideoView: UIViewRepresentable {
    let url: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var onPhaseChange: ((RemoteVideoPhase) -> Void)?

    func makeUIView(context: Context) -> LoopingPlayerLayerView {
        let view = LoopingPlayerLayerView()
        view.playerLayer.videoGravity = videoGravity
        view.onPhaseChange = onPhaseChange
        configure(view)
        return view
    }

    func updateUIView(_ view: LoopingPlayerLayerView, context: Context) {
        view.playerLayer.videoGravity = videoGravity
        view.onPhaseChange = onPhaseChange
        guard view.currentURL != url else {
            // Resume after the system paused playback (e.g. backgrounding), without re-commanding
            // a playing player on every SwiftUI update of the story card.
            if let player = view.playerLayer.player, player.timeControlStatus == .paused {
                player.play()
            }
            return
        }
        configure(view)
    }

    static func dismantleUIView(_ view: LoopingPlayerLayerView, coordinator: ()) {
        view.tearDown()
    }

    private func configure(_ view: LoopingPlayerLayerView) {
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        view.attach(player, url: url)
        player.play()
    }
}

final class LoopingPlayerLayerView: UIView {
    var currentURL: URL?
    var onPhaseChange: ((RemoteVideoPhase) -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var lastPhase: RemoteVideoPhase?

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func attach(_ player: AVPlayer, url: URL) {
        tearDown()
        currentURL = url
        playerLayer.player = player
        lastPhase = nil
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loopVideo),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        var observations = [
            playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in self?.schedulePhaseUpdate() },
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in self?.schedulePhaseUpdate() }
        ]
        if let item = player.currentItem {
            observations.append(item.observe(\.status, options: [.new]) { [weak self] _, _ in self?.schedulePhaseUpdate() })
        }
        self.observations = observations
    }

    func tearDown() {
        observations.forEach { $0.invalidate() }
        observations = []
        NotificationCenter.default.removeObserver(self)
        playerLayer.player?.pause()
        playerLayer.player = nil
        currentURL = nil
    }

    @objc func loopVideo() {
        playerLayer.player?.seek(to: .zero)
        playerLayer.player?.play()
    }

    private func schedulePhaseUpdate() {
        DispatchQueue.main.async { [weak self] in self?.publishPhase() }
    }

    private func publishPhase() {
        guard let player = playerLayer.player else { return }
        let phase: RemoteVideoPhase
        if player.currentItem?.status == .failed {
            phase = .failed
        } else if !playerLayer.isReadyForDisplay {
            phase = .loading
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                  player.reasonForWaitingToPlay == .toMinimizeStalls {
            phase = .buffering
        } else {
            phase = .playing
        }
        guard phase != lastPhase else { return }
        lastPhase = phase
        onPhaseChange?(phase)
    }

    deinit {
        observations.forEach { $0.invalidate() }
        NotificationCenter.default.removeObserver(self)
        playerLayer.player?.pause()
    }
}
