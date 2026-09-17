import ImageIO
import MapKit
import SwiftUI

// MARK: - Player map selection
struct DiscoverPlayerMapItem: Identifiable {
    let id: String
    let userID: String
    let areaID: String
    let anchorCoordinate: CLLocationCoordinate2D
    let coordinate: CLLocationCoordinate2D
    let areaLabel: String
    let displayName: String
    let avatarPath: String?
    let sports: [Sport]
    let sportLevels: [String: Int]
}

// MapKit supplies unordered membership annotations; resolve against the current ranked items.
enum DiscoverPlayerMapSelection {
    static func userIDs(in items: [DiscoverPlayerMapItem], membershipIDs: [String]) -> [String] {
        let requested = Set(membershipIDs)
        var seen = Set<String>()
        return items.compactMap { item in
            guard requested.contains(item.id), seen.insert(item.userID).inserted else { return nil }
            return item.userID
        }
    }
}
// A tree mirrors native clusters without depending on MapKit's annotation order.
indirect enum DiscoverPlayerMapMembershipNode {
    case member(String)
    case group([DiscoverPlayerMapMembershipNode])
}

enum DiscoverPlayerMapCluster {
    static func membershipIDs(in items: [DiscoverPlayerMapItem], nodes: [DiscoverPlayerMapMembershipNode]) -> [String] {
        var requested = Set<String>()
        func collect(_ node: DiscoverPlayerMapMembershipNode) {
            switch node {
            case .member(let id): requested.insert(id)
            case .group(let children): children.forEach(collect)
            }
        }
        nodes.forEach(collect)
        var seen = Set<String>()
        return items.compactMap { item in
            requested.contains(item.id) && seen.insert(item.id).inserted ? item.id : nil
        }
    }

    static func zoomRect(current: MKMapRect, coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !current.isNull, !current.isEmpty,
              current.width.isFinite, current.height.isFinite,
              current.origin.x.isFinite, current.origin.y.isFinite else { return nil }
        let points = coordinates.filter(CLLocationCoordinate2DIsValid).map(MKMapPoint.init)
            .filter { $0.x.isFinite && $0.y.isFinite }
        guard let first = points.first else { return nil }
        // Keep dateline neighbours on the same world copy as the first member.
        let worldWidth = MKMapRect.world.width
        let xs = points.map { point -> Double in
            var x = point.x
            while x - first.x > worldWidth / 2 { x -= worldWidth }
            while x - first.x < -worldWidth / 2 { x += worldWidth }
            return x
        }
        let ys = points.map(\.y)
        let centerX = ((xs.min() ?? first.x) + (xs.max() ?? first.x)) / 2
        let centerY = ((ys.min() ?? first.y) + (ys.max() ?? first.y)) / 2
        // Preserve the current aspect ratio and shrink on every activation. Refitting
        // the same padded member bounds would get stuck before card collisions split.
        let minimumDimension = 32.0
        let scale = min(1, max(0.5, minimumDimension / min(current.width, current.height)))
        let width = current.width * scale
        let height = current.height * scale
        var target = MKMapRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        let unwrappedPoints = zip(xs, ys).map { MKMapPoint(x: $0.0, y: $0.1) }
        if !unwrappedPoints.contains(where: { target.contains($0) }) {
            // Widely separated colliding cards can straddle the shrinking viewport.
            // Keep an actual member in view instead of zooming into empty map space.
            let nearest = unwrappedPoints.min { a, b in
                let da = pow(a.x - centerX, 2) + pow(a.y - centerY, 2)
                let db = pow(b.x - centerX, 2) + pow(b.y - centerY, 2)
                if da == db { return a.x == b.x ? a.y < b.y : a.x < b.x }
                return da < db
            } ?? first
            target.origin = MKMapPoint(x: nearest.x - width / 2, y: nearest.y - height / 2)
        }
        return target
    }
}
// MARK: - End player map selection

/// Annotation content is decorative UIKit content. MapKit owns every touch,
/// including a pinch that begins inside a player card.
struct DiscoverPlayersMap: UIViewRepresentable {
    let items: [DiscoverPlayerMapItem]
    let selectedPlayerID: String?
    let isEnabled: Bool
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsTraffic = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isScrollEnabled = true
        map.isZoomEnabled = true
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.register(DiscoverPlayerAnnotationView.self, forAnnotationViewWithReuseIdentifier: DiscoverPlayerAnnotationView.reuseID)
        map.register(DiscoverPlayerClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuseID)
        map.accessibilityIdentifier = "similar-players-map"
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(map, items: items, selectedPlayerID: selectedPlayerID, isEnabled: isEnabled, onSelect: onSelect)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        map.delegate = nil
        map.removeAnnotations(map.annotations)
        coordinator.annotations.removeAll()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        fileprivate static let clusterReuseID = "discover-player-count"
        fileprivate var annotations: [String: DiscoverPlayerAnnotation] = [:]
        private var orderedIDs: [String] = []
        private var selectedPlayerID: String?
        private var isEnabled = true
        private var isUpdating = false
        private var coordinateSignature: [String] = []
        private var onSelect: (String) -> Void = { _ in }

        fileprivate func update(
            _ map: MKMapView,
            items: [DiscoverPlayerMapItem],
            selectedPlayerID: String?,
            isEnabled: Bool,
            onSelect: @escaping (String) -> Void
        ) {
            self.onSelect = onSelect
            self.selectedPlayerID = selectedPlayerID
            self.isEnabled = isEnabled
            isUpdating = true
            defer { isUpdating = false }

            let validItems = items.filter { CLLocationCoordinate2DIsValid($0.coordinate) }
            orderedIDs = validItems.map(\.id)
            let itemIDs = Set(orderedIDs)
            let removedIDs = annotations.keys.filter { !itemIDs.contains($0) }
            for id in removedIDs {
                if let annotation = annotations.removeValue(forKey: id) { map.removeAnnotation(annotation) }
            }
            for item in validItems {
                if let annotation = annotations[item.id] {
                    annotation.update(item)
                    if let view = map.view(for: annotation) as? DiscoverPlayerAnnotationView {
                        configurePlayer(view, annotation: annotation, on: map)
                    }
                } else {
                    let annotation = DiscoverPlayerAnnotation(item)
                    annotations[item.id] = annotation
                    map.addAnnotation(annotation)
                }
            }
            for annotation in map.annotations {
                if let cluster = annotation as? MKClusterAnnotation,
                   let view = map.view(for: cluster) as? DiscoverPlayerClusterAnnotationView {
                    configureCluster(view, annotation: cluster, on: map)
                }
            }
            // Sorting makes an order-only or metadata update camera-neutral.
            let signature = validItems.map { "\($0.id)|\($0.coordinate.latitude)|\($0.coordinate.longitude)" }.sorted()
            if signature != coordinateSignature {
                coordinateSignature = signature
                if !validItems.isEmpty { fit(validItems.map(\.coordinate), on: map, animated: false, minimumMeters: 800) }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.clusterReuseID, for: cluster) as! DiscoverPlayerClusterAnnotationView
                configureCluster(view, annotation: cluster, on: mapView)
                return view
            }
            guard let annotation = annotation as? DiscoverPlayerAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: DiscoverPlayerAnnotationView.reuseID, for: annotation) as! DiscoverPlayerAnnotationView
            configurePlayer(view, annotation: annotation, on: mapView)
            return view
        }

        private func configurePlayer(_ view: DiscoverPlayerAnnotationView, annotation: DiscoverPlayerAnnotation, on map: MKMapView) {
            view.configure(annotation.item, selected: annotation.item.userID == selectedPlayerID, enabled: isEnabled)
            view.onAccessibilityActivate = { [weak self, weak map, weak view, weak annotation] in
                guard let self, let map, let view, let annotation,
                      view.annotation === annotation else { return false }
                return self.activatePlayer(annotation, on: map)
            }
        }

        private func configureCluster(_ view: DiscoverPlayerClusterAnnotationView, annotation: MKClusterAnnotation, on map: MKMapView) {
            let userIDs = DiscoverPlayerMapSelection.userIDs(in: currentItems, membershipIDs: memberIDs(annotation))
            let selected = userIDs.contains(selectedPlayerID ?? "")
            view.configure(count: userIDs.count, selected: selected)
            view.onAccessibilityActivate = { [weak self, weak map, weak view, weak annotation] in
                guard let self, let map, let view, let annotation,
                      view.annotation === annotation else { return false }
                return self.activateCluster(annotation, on: map)
            }
            view.isAccessibilityElement = true
            view.accessibilityLabel = L10n.string("\(userIDs.count) players", "Игроков: \(userIDs.count)")
            view.accessibilityHint = L10n.string("Zooms in to show player cards", "Приближает карту, чтобы показать карточки игроков")
            view.accessibilityTraits = selected ? [.button, .selected] : .button
            if !isEnabled { view.accessibilityTraits.insert(.notEnabled) }
            view.accessibilityIdentifier = "similar-players-map-cluster-\(userIDs.joined(separator: "-"))"
        }

        private func memberIDs(_ cluster: MKClusterAnnotation) -> [String] {
            func node(_ annotation: MKAnnotation) -> DiscoverPlayerMapMembershipNode {
                if let member = annotation as? DiscoverPlayerAnnotation { return .member(member.item.id) }
                if let group = annotation as? MKClusterAnnotation { return .group(group.memberAnnotations.map(node)) }
                return .group([])
            }
            return DiscoverPlayerMapCluster.membershipIDs(in: currentItems, nodes: [node(cluster)])
        }

        private var currentItems: [DiscoverPlayerMapItem] {
            orderedIDs.compactMap { annotations[$0]?.item }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard !isUpdating, isEnabled else {
                mapView.deselectAnnotation(annotation, animated: false)
                return
            }
            if let cluster = annotation as? MKClusterAnnotation {
                _ = activateCluster(cluster, on: mapView)
                return
            }
            guard let annotation = annotation as? DiscoverPlayerAnnotation else { return }
            _ = activatePlayer(annotation, on: mapView)
        }

        @discardableResult
        private func activatePlayer(_ annotation: DiscoverPlayerAnnotation, on map: MKMapView) -> Bool {
            guard !isUpdating, isEnabled, map.delegate === self,
                  annotations[annotation.item.id] === annotation else { return false }
            // Persistent highlighting comes from selectedPlayerID, so native
            // deselection allows another tap without toggling the stored selection.
            map.deselectAnnotation(annotation, animated: false)
            deliverSelection([annotation.item.id])
            return true
        }

        @discardableResult
        private func activateCluster(_ cluster: MKClusterAnnotation, on map: MKMapView) -> Bool {
            guard !isUpdating, isEnabled, map.delegate === self else { return false }
            let ids = memberIDs(cluster)
            guard !ids.isEmpty else { return false }
            map.deselectAnnotation(cluster, animated: false)
            // Both native selection and VoiceOver use this one zoom path. Returning
            // true from accessibilityActivate avoids a second default activation.
            DispatchQueue.main.async { [weak self, weak map] in
                guard let self, let map, self.isEnabled, map.delegate === self else { return }
                let currentIDs = Set(ids)
                let coordinates = self.currentItems.filter { currentIDs.contains($0.id) }.map(\.coordinate)
                guard let target = DiscoverPlayerMapCluster.zoomRect(current: map.visibleMapRect, coordinates: coordinates) else { return }
                map.setVisibleMapRect(target, animated: !UIAccessibility.isReduceMotionEnabled)
            }
            return true
        }

        private func deliverSelection(_ membershipIDs: [String]) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEnabled else { return }
                let userIDs = DiscoverPlayerMapSelection.userIDs(in: self.currentItems, membershipIDs: membershipIDs)
                guard let first = userIDs.first else { return }
                self.onSelect(first)
            }
        }

        private func fit(
            _ coordinates: [CLLocationCoordinate2D], on map: MKMapView, animated: Bool, minimumMeters: Double,
            edgePadding: UIEdgeInsets = UIEdgeInsets(top: 72, left: 108, bottom: 72, right: 108)
        ) {
            guard let first = coordinates.first else { return }
            var rect = MKMapRect.null
            for coordinate in coordinates {
                let point = MKMapPoint(coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            let minimumPoints = minimumMeters * MKMapPointsPerMeterAtLatitude(first.latitude)
            rect = rect.insetBy(dx: -max(0, (minimumPoints - rect.width) / 2), dy: -max(0, (minimumPoints - rect.height) / 2))
            map.setVisibleMapRect(rect, edgePadding: edgePadding, animated: animated)
        }
    }
}

private final class DiscoverPlayerAnnotation: NSObject, MKAnnotation {
    private(set) var item: DiscoverPlayerMapItem
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { item.displayName }
    var subtitle: String? { item.areaLabel }

    init(_ item: DiscoverPlayerMapItem) {
        self.item = item
        coordinate = item.coordinate
        super.init()
    }

    func update(_ item: DiscoverPlayerMapItem) {
        self.item = item
        if coordinate.latitude != item.coordinate.latitude || coordinate.longitude != item.coordinate.longitude {
            coordinate = item.coordinate
        }
    }
}

/// A rendered UIKit badge stays visible independently of MapKit's base-map style.
/// It has no interactive subviews; MapKit handles the whole 54-point hit area.
private final class DiscoverPlayerClusterAnnotationView: MKAnnotationView {
    var onAccessibilityActivate: (() -> Bool)?

    override func prepareForReuse() {
        super.prepareForReuse()
        onAccessibilityActivate = nil
    }

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? false
    }

    func configure(count: Int, selected: Bool) {
        let font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 18, weight: .bold), maximumPointSize: 26)
        let diameter: CGFloat = font.pointSize > 22 ? 64 : 54
        let size = CGSize(width: diameter, height: diameter)
        image = UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
            (selected ? DiscoverPlayerAnnotationView.accent : UIColor(white: 0.15, alpha: 1)).setFill()
            circle.fill()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            circle.lineWidth = 2
            circle.stroke()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let text = String(count) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: selected ? UIColor.black : UIColor.white, .paragraphStyle: paragraph
            ]
            let height = text.size(withAttributes: attributes).height
            text.draw(in: CGRect(x: 4, y: (diameter - height) / 2, width: diameter - 8, height: height), withAttributes: attributes)
        }
        bounds = CGRect(origin: .zero, size: size)
        centerOffset = .zero
        canShowCallout = false
        clusteringIdentifier = nil
        displayPriority = .required
        zPriority = .max
        collisionMode = .circle
        isUserInteractionEnabled = true
        isEnabled = true
    }
}

private final class DiscoverPlayerAnnotationView: MKAnnotationView {
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? false
    }

    static let reuseID = "discover-player-card"
    static let accent = UIColor(red: 0.63, green: 0.93, blue: 0.75, alpha: 1)
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private let surface = UIView()
    private let avatar = UIImageView()
    private let initials = UILabel()
    private let nameLabel = UILabel()
    private let sportsLabel = UILabel()
    private let areaLabel = UILabel()
    private var avatarTask: URLSessionDataTask?
    private var avatarURL: URL?
    private var avatarUserID: String?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "discover-players"
        collisionMode = .rectangle
        displayPriority = .defaultHigh
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -8)
        isAccessibilityElement = true
        surface.layer.cornerRadius = 15
        surface.layer.borderWidth = 1.5
        surface.layer.shadowColor = UIColor.black.cgColor
        surface.layer.shadowOpacity = 0.3
        surface.layer.shadowRadius = 5
        surface.layer.shadowOffset = CGSize(width: 0, height: 3)
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 16
        avatar.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        initials.textAlignment = .center
        initials.font = .systemFont(ofSize: 15, weight: .bold)
        initials.textColor = .white
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        sportsLabel.numberOfLines = 2
        sportsLabel.lineBreakMode = .byTruncatingTail
        areaLabel.numberOfLines = 1
        areaLabel.lineBreakMode = .byTruncatingTail
        addSubview(surface)
        for view in [avatar, initials, nameLabel, sportsLabel, areaLabel] { surface.addSubview(view) }
        // These views must never intercept MapKit's native gesture recognizers.
        for view in [surface, avatar, initials, nameLabel, sportsLabel, areaLabel] {
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAccessibilityActivate = nil
        avatarTask?.cancel()
        avatarTask = nil
        avatarURL = nil
        avatarUserID = nil
        avatar.image = nil
    }

    deinit { avatarTask?.cancel() }

    func configure(_ item: DiscoverPlayerMapItem, selected: Bool, enabled: Bool) {
        clusteringIdentifier = "discover-players"
        nameLabel.text = item.displayName
        sportsLabel.text = Self.sportsSummary(item)
        areaLabel.text = item.areaLabel
        initials.text = item.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        surface.backgroundColor = selected ? Self.accent : UIColor(white: 0.10, alpha: 1)
        surface.layer.borderColor = (selected ? UIColor.white.withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.2)).cgColor
        nameLabel.textColor = selected ? .black : .white
        sportsLabel.textColor = selected ? UIColor.black.withAlphaComponent(0.75) : Self.accent
        areaLabel.textColor = selected ? UIColor.black.withAlphaComponent(0.65) : UIColor.white.withAlphaComponent(0.65)
        accessibilityLabel = [item.displayName, Self.sportsSummary(item, includeAll: true), item.areaLabel].joined(separator: ", ")
        accessibilityHint = L10n.string("Opens the full player card. Schematic placement in a play area.", "Открывает полную карточку игрока. Условное размещение в районе для игры.")
        accessibilityTraits = selected ? [.button, .selected] : .button
        if !enabled { accessibilityTraits.insert(.notEnabled) }
        accessibilityIdentifier = "similar-players-map-player-\(item.id)"
        updateMetrics()
        loadAvatar(item.avatarPath, userID: item.userID)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateMetrics()
        }
    }

    private func updateMetrics() {
        nameLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13, weight: .bold), maximumPointSize: 18)
        sportsLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 10.5, weight: .medium), maximumPointSize: 15)
        areaLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 10), maximumPointSize: 14)
        let width: CGFloat = nameLabel.font.pointSize > 15 ? 210 : 182
        let height = max(92, 26 + nameLabel.font.lineHeight + sportsLabel.font.lineHeight * 2 + areaLabel.font.lineHeight)
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
        avatar.frame = CGRect(x: 9, y: 10, width: 32, height: 32)
        initials.frame = avatar.frame
        nameLabel.frame = CGRect(x: 49, y: 9, width: bounds.width - 58, height: nameLabel.font.lineHeight)
        sportsLabel.frame = CGRect(x: 49, y: nameLabel.frame.maxY + 3, width: bounds.width - 58, height: sportsLabel.font.lineHeight * 2)
        areaLabel.frame = CGRect(x: 9, y: sportsLabel.frame.maxY + 4, width: bounds.width - 18, height: areaLabel.font.lineHeight)
        surface.layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 15).cgPath
    }

    private func loadAvatar(_ path: String?, userID: String) {
        let url = resolveAppRemoteURL(path)
        guard avatarURL != url || avatarUserID != userID else { return }
        avatarTask?.cancel()
        avatarTask = nil
        avatarURL = url
        avatarUserID = userID
        avatar.image = nil
        initials.isHidden = false
        guard let url else { return }
        if let cached = Self.imageCache.object(forKey: url.absoluteString as NSString) {
            avatar.image = cached
            initials.isHidden = true
            return
        }
        avatarTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard error == nil, let data,
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 112,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return }
            let image = UIImage(cgImage: cgImage)
            Self.imageCache.setObject(image, forKey: url.absoluteString as NSString, cost: cgImage.bytesPerRow * cgImage.height)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.avatarURL == url, self.avatarUserID == userID else { return }
                self.avatar.image = image
                self.initials.isHidden = true
                self.avatarTask = nil
            }
        }
        avatarTask?.resume()
    }

    private static func sportsSummary(_ item: DiscoverPlayerMapItem, includeAll: Bool = false) -> String {
        guard !item.sports.isEmpty else { return L10n.string("Sport not specified", "Спорт не указан") }
        let sports = includeAll ? item.sports : Array(item.sports.prefix(2))
        let summary = sports.map { sport in
            sport.title + (item.sportLevels[sport.rawValue].map { " \($0)/10" } ?? "")
        }.joined(separator: " · ")
        return summary + (!includeAll && item.sports.count > 2 ? " +\(item.sports.count - 2)" : "")
    }

}
