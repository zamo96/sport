import EventKit
import SwiftUI

/// A personal visit as a day pass to the club: the place on top, a perforation, then the
/// day and the time set large. A marked visit carries a stamp; a visit with photos shows
/// its first photo instead of the club.
struct PersonalVisitPass: View {
    let activity: PersonalActivity
    let now: Date
    /// The stamp slams down instead of simply being there: the visit was just marked here.
    var stampAnimates = false
    var onOpenCourt: (() -> Void)?

    private var phase: PersonalVisitPhase {
        activity.visitMoment.map { PersonalVisitTimeline.phase(of: $0, now: now) } ?? .later
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PersonalVisitPassHero(activity: activity, height: 150)
                .overlay(alignment: .topTrailing) {
                    switch phase {
                    case .completed:
                        PersonalVisitStamp(completed: true, animatesIn: stampAnimates).padding(16)
                    case .canceled:
                        PersonalVisitStamp(completed: false, canceledAhead: !activity.hasEnded, animatesIn: stampAnimates).padding(16)
                    default:
                        EmptyView()
                    }
                }

            clubRow
            perforation
            details
        }
        .background(VisitStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(VisitStyle.line, lineWidth: 1))
        .saturation(phase == .canceled ? 0.35 : 1)
        .accessibilityElement(children: .combine)
    }

    private var clubRow: some View {
        Button {
            onOpenCourt?()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.court?.name ?? L10n.string("Sports center", "Спортивный центр"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let place {
                        Text(place)
                            .font(.system(size: 13))
                            .foregroundStyle(VisitStyle.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if onOpenCourt != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpenCourt == nil)
    }

    private var place: String? {
        guard let court = activity.court else { return nil }
        let parts = [court.metroDisplayName, court.displayAddress, court.distanceLabel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A dashed tear line between two notches cut out of the pass.
    private var perforation: some View {
        ZStack {
            Line()
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(height: 2)
                .padding(.horizontal, 22)
            HStack {
                Circle().fill(VisitStyle.sheet).frame(width: 24, height: 24).offset(x: -12)
                Spacer()
                Circle().fill(VisitStyle.sheet).frame(width: 24, height: 24).offset(x: 12)
            }
        }
        .frame(height: 28)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(phase == .canceled ? VisitStyle.secondaryText : VisitStyle.accent)

            Text(activity.visitTimeRange ?? L10n.string("Time to be set", "Время уточняется"))
                .font(.system(size: activity.visitTimeRange == nil ? 28 : 44, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
                .strikethrough(phase == .canceled, color: Color.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 10) {
                Text(sportLine)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusPill
            }
            .padding(.top, 2)

            if let plan = activity.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 20)
    }

    private var eyebrow: String {
        guard let start = activity.scheduledDate else { return activity.sport.title.uppercased() }
        let date = CachedDateFormatters.display(format: "EEEE, d MMMM").string(from: start)
        guard let relative = PersonalVisitDateText.relative(start, now: now) else { return date.uppercased() }
        return "\(relative) · \(date)".uppercased()
    }

    private var sportLine: String {
        let duration = activity.durationMinutes.map {
            PersonalVisitPlanner.durationLabel($0, russian: L10n.string("en", "ru") == "ru")
        }
        return [activity.sport.title, duration].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusPill: some View {
        switch phase {
        case .today:
            TimelineView(.periodic(from: .now, by: 30)) { context in
                pill(countdown(at: context.date), tint: VisitStyle.accent)
            }
        case .inProgress:
            pill(L10n.string("On now", "Идёт сейчас"), tint: VisitStyle.accent)
        case .needsMark:
            pill(L10n.string("Waiting for a mark", "Ждёт отметки"), tint: VisitStyle.accent)
        case .later:
            pill(L10n.string("Planned", "Запланировано"), tint: Color.white.opacity(0.8))
        case .completed, .canceled:
            EmptyView()
        }
    }

    private func countdown(at date: Date) -> String {
        guard let start = activity.scheduledDate, start > date else { return L10n.string("On now", "Идёт сейчас") }
        return PersonalVisitTimeline.countdown(to: start, now: date, russian: L10n.string("en", "ru") == "ru")
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tint.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The visit's first photo when it has one (it develops in when it has just been added),
/// else the club's photo, else the sport drawn.
struct PersonalVisitPassHero: View {
    let activity: PersonalActivity
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDeveloped = true

    private var photoPath: String? { activity.photoUrls.first }

    private var courtPhotoURL: URL? {
        guard let court = activity.court else { return nil }
        return resolveAppRemoteURL(court.photoUrls.first ?? court.primaryPhotoUrl)
    }

    var body: some View {
        ZStack {
            if let photoPath {
                ActivityMediaPhoto(path: photoPath, contentMode: .fill)
                    .blur(radius: isDeveloped ? 0 : 14)
                    .saturation(isDeveloped ? 1 : 0)
                    .brightness(isDeveloped ? 0 : -0.25)
            } else if let courtPhotoURL {
                RemoteImage(url: courtPhotoURL, contentMode: .fill) { _ in
                    PersonalVisitScene(sport: activity.sport)
                }
            } else {
                PersonalVisitScene(sport: activity.sport)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
        .onChange(of: photoPath) { newValue in
            guard newValue != nil, !reduceMotion else { return }
            isDeveloped = false
            withAnimation(.easeOut(duration: 0.9).delay(0.2)) {
                isDeveloped = true
            }
        }
    }
}

/// "Happened" or "Didn't happen", set on the pass like a stamp.
struct PersonalVisitStamp: View {
    let completed: Bool
    /// Canceled before it started: "Canceled" rather than "Didn't happen".
    var canceledAhead = false
    let animatesIn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded: Bool

    init(completed: Bool, canceledAhead: Bool = false, animatesIn: Bool) {
        self.completed = completed
        self.canceledAhead = canceledAhead
        self.animatesIn = animatesIn
        _hasLanded = State(initialValue: !animatesIn)
    }

    private var label: String {
        if completed { return L10n.string("Happened", "Состоялось") }
        return canceledAhead ? L10n.string("Canceled", "Отменён") : L10n.string("Didn't happen", "Не состоялось")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: completed ? "checkmark.seal.fill" : "xmark.seal.fill")
            Text(label)
                .textCase(.uppercase)
                .tracking(1)
        }
        .font(.system(size: 14, weight: .heavy))
        .foregroundStyle(completed ? VisitStyle.onAccent : Color.white.opacity(0.9))
        .accessibilityLabel(label)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(completed ? VisitStyle.accent : Color(white: 0.22).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(completed ? VisitStyle.onAccent.opacity(0.35) : Color.white.opacity(0.35), lineWidth: 2)
        )
        .rotationEffect(.degrees(-10))
        .scaleEffect(hasLanded ? 1 : 1.9)
        .opacity(hasLanded ? 1 : 0)
        .onAppear {
            guard !hasLanded else { return }
            if reduceMotion {
                hasLanded = true
                return
            }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                hasLanded = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                AppHaptics.impact(.rigid)
            }
        }
    }
}

/// The sport's place drawn from above, for clubs without a photo.
struct PersonalVisitScene: View {
    let sport: Sport

    private enum Layout { case court(net: Bool), pitch, track, water, ring, mat, floor }

    private var layout: Layout {
        switch sport {
        case .tennis, .padel, .badminton, .tableTennis, .volleyball: return .court(net: true)
        case .squash: return .court(net: false)
        case .football: return .pitch
        case .running: return .track
        case .supboard: return .water
        case .boxing: return .ring
        case .yoga: return .mat
        case .fitness: return .floor
        }
    }

    private var colors: (ground: Color, surface: Color) {
        switch sport {
        case .tennis: return (Color(red: 0.145, green: 0.38, blue: 0.31), AppTheme.court)
        case .padel: return (Color(red: 0.12, green: 0.27, blue: 0.40), Color(red: 0.18, green: 0.37, blue: 0.53))
        case .badminton: return (Color(red: 0.17, green: 0.31, blue: 0.49), Color(red: 0.23, green: 0.44, blue: 0.69))
        case .tableTennis: return (Color(red: 0.10, green: 0.14, blue: 0.20), Color(red: 0.12, green: 0.31, blue: 0.55))
        case .volleyball: return (Color(red: 0.65, green: 0.47, blue: 0.24), Color(red: 0.77, green: 0.60, blue: 0.32))
        case .squash: return (Color(red: 0.55, green: 0.36, blue: 0.19), Color(red: 0.73, green: 0.51, blue: 0.29))
        case .football, .running: return (Color(red: 0.12, green: 0.37, blue: 0.23), Color(red: 0.18, green: 0.55, blue: 0.34))
        case .supboard: return (Color(red: 0.08, green: 0.36, blue: 0.52), Color(red: 0.11, green: 0.43, blue: 0.59))
        case .boxing: return (Color(red: 0.13, green: 0.14, blue: 0.16), Color(red: 0.20, green: 0.33, blue: 0.62))
        case .yoga: return (Color(red: 0.36, green: 0.27, blue: 0.20), Color(red: 0.48, green: 0.37, blue: 0.65))
        case .fitness: return (Color(red: 0.15, green: 0.19, blue: 0.17), Color(red: 0.21, green: 0.26, blue: 0.24))
        }
    }

    var body: some View {
        let colors = colors
        let layout = layout
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(colors.ground))
            let line = GraphicsContext.Shading.color(.white.opacity(0.85))
            let ball = GraphicsContext.Shading.color(VisitStyle.accent)

            switch layout {
            case .court(let net):
                let court = rect.insetBy(dx: size.width * 0.12, dy: size.height * 0.1)
                context.fill(Path(court), with: .color(colors.surface))
                context.stroke(Path(court), with: line, lineWidth: 2)
                let singles = court.insetBy(dx: 0, dy: court.height * 0.12)
                var lines = Path()
                lines.move(to: CGPoint(x: singles.minX, y: singles.minY)); lines.addLine(to: CGPoint(x: singles.maxX, y: singles.minY))
                lines.move(to: CGPoint(x: singles.minX, y: singles.maxY)); lines.addLine(to: CGPoint(x: singles.maxX, y: singles.maxY))
                let serviceLeft = court.minX + court.width * 0.25
                let serviceRight = court.maxX - court.width * 0.25
                lines.move(to: CGPoint(x: serviceLeft, y: singles.minY)); lines.addLine(to: CGPoint(x: serviceLeft, y: singles.maxY))
                lines.move(to: CGPoint(x: serviceRight, y: singles.minY)); lines.addLine(to: CGPoint(x: serviceRight, y: singles.maxY))
                lines.move(to: CGPoint(x: serviceLeft, y: court.midY)); lines.addLine(to: CGPoint(x: serviceRight, y: court.midY))
                context.stroke(lines, with: line, lineWidth: 1.5)
                if net {
                    var netPath = Path()
                    netPath.move(to: CGPoint(x: court.midX, y: court.minY - 8))
                    netPath.addLine(to: CGPoint(x: court.midX, y: court.maxY + 8))
                    context.stroke(netPath, with: .color(.white), lineWidth: 3)
                } else {
                    var tin = Path()
                    tin.move(to: CGPoint(x: court.minX + 4, y: court.minY)); tin.addLine(to: CGPoint(x: court.minX + 4, y: court.maxY))
                    context.stroke(tin, with: .color(Color(red: 0.85, green: 0.25, blue: 0.2)), lineWidth: 4)
                }
                let dot = CGRect(x: court.maxX - court.width * 0.2 - 7, y: court.minY + court.height * 0.28 - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: dot), with: ball)
            case .pitch:
                let pitch = rect.insetBy(dx: size.width * 0.08, dy: size.height * 0.1)
                context.fill(Path(pitch), with: .color(colors.surface))
                context.stroke(Path(pitch), with: line, lineWidth: 2)
                var lines = Path()
                lines.move(to: CGPoint(x: pitch.midX, y: pitch.minY)); lines.addLine(to: CGPoint(x: pitch.midX, y: pitch.maxY))
                lines.addEllipse(in: CGRect(x: pitch.midX - pitch.height * 0.2, y: pitch.midY - pitch.height * 0.2, width: pitch.height * 0.4, height: pitch.height * 0.4))
                let box = CGSize(width: pitch.width * 0.13, height: pitch.height * 0.5)
                lines.addRect(CGRect(x: pitch.minX, y: pitch.midY - box.height / 2, width: box.width, height: box.height))
                lines.addRect(CGRect(x: pitch.maxX - box.width, y: pitch.midY - box.height / 2, width: box.width, height: box.height))
                context.stroke(lines, with: line, lineWidth: 1.5)
                context.fill(Path(ellipseIn: CGRect(x: pitch.midX + pitch.width * 0.18, y: pitch.midY - 10, width: 14, height: 14)), with: ball)
            case .track:
                let outer = rect.insetBy(dx: size.width * 0.07, dy: size.height * 0.1)
                context.fill(Path(roundedRect: outer, cornerRadius: outer.height / 2), with: .color(Color(red: 0.71, green: 0.32, blue: 0.23)))
                let field = outer.insetBy(dx: outer.height * 0.22, dy: outer.height * 0.22)
                context.fill(Path(roundedRect: field, cornerRadius: field.height / 2), with: .color(colors.surface))
                for lane in 1 ... 3 {
                    let inset = outer.height * 0.22 * CGFloat(lane) / 4
                    let laneRect = outer.insetBy(dx: inset, dy: inset)
                    context.stroke(Path(roundedRect: laneRect, cornerRadius: laneRect.height / 2), with: .color(.white.opacity(0.55)), lineWidth: 1)
                }
                context.fill(Path(ellipseIn: CGRect(x: outer.midX + outer.width * 0.2, y: outer.minY + outer.height * 0.05, width: 12, height: 12)), with: ball)
            case .water:
                context.fill(Path(rect), with: .color(colors.surface))
                for row in 0 ..< 5 {
                    var wave = Path()
                    let y = size.height * (0.15 + 0.18 * CGFloat(row))
                    wave.move(to: CGPoint(x: 0, y: y))
                    stride(from: CGFloat(0), through: size.width, by: 36).forEach { x in
                        wave.addQuadCurve(to: CGPoint(x: x + 36, y: y), control: CGPoint(x: x + 18, y: y - 6))
                    }
                    context.stroke(wave, with: .color(.white.opacity(0.18)), lineWidth: 1.5)
                }
                let board = CGRect(x: size.width * 0.3, y: size.height * 0.44, width: size.width * 0.4, height: size.height * 0.14)
                context.fill(Path(roundedRect: board, cornerRadius: board.height / 2), with: ball)
            case .ring:
                let ring = rect.insetBy(dx: (size.width - size.height * 0.8) / 2, dy: size.height * 0.1)
                context.fill(Path(ring), with: .color(colors.surface))
                for index in 0 ..< 3 {
                    let inset = CGFloat(index) * 6
                    context.stroke(Path(ring.insetBy(dx: inset, dy: inset)), with: .color(.white.opacity(0.75 - Double(index) * 0.2)), lineWidth: 2)
                }
                context.fill(Path(ellipseIn: CGRect(x: ring.minX - 6, y: ring.minY - 6, width: 12, height: 12)), with: .color(Color(red: 0.86, green: 0.24, blue: 0.2)))
                context.fill(Path(ellipseIn: CGRect(x: ring.maxX - 6, y: ring.maxY - 6, width: 12, height: 12)), with: .color(Color(red: 0.2, green: 0.42, blue: 0.86)))
            case .mat:
                for index in 0 ..< Int(size.width / 28) + 1 {
                    var plank = Path()
                    plank.move(to: CGPoint(x: CGFloat(index) * 28, y: 0)); plank.addLine(to: CGPoint(x: CGFloat(index) * 28, y: size.height))
                    context.stroke(plank, with: .color(.black.opacity(0.18)), lineWidth: 1)
                }
                let mat = CGRect(x: size.width * 0.22, y: size.height * 0.28, width: size.width * 0.56, height: size.height * 0.44)
                context.fill(Path(roundedRect: mat, cornerRadius: 10), with: .color(colors.surface))
                context.stroke(Path(roundedRect: mat.insetBy(dx: 6, dy: 6), cornerRadius: 6), with: .color(.white.opacity(0.25)), lineWidth: 1)
            case .floor:
                for index in 0 ..< Int(size.width / 32) + 1 {
                    var plank = Path()
                    plank.move(to: CGPoint(x: CGFloat(index) * 32, y: 0)); plank.addLine(to: CGPoint(x: CGFloat(index) * 32, y: size.height))
                    context.stroke(plank, with: .color(.white.opacity(0.05)), lineWidth: 1)
                }
            }
        }
        .overlay {
            if case .floor = layout {
                SportIconView(sport: sport, color: .white.opacity(0.22), size: 64)
            }
        }
    }
}

/// Adds a visit to the phone's calendar.
enum PersonalVisitCalendar {
    enum Failure: LocalizedError {
        case noTime
        case accessDenied
        case calendarUnavailable

        var errorDescription: String? {
            switch self {
            case .noTime:
                return L10n.string("This visit has no time yet.", "У визита пока нет времени.")
            case .accessDenied:
                return L10n.string("Allow calendar access to add visits.", "Разрешите доступ к календарю, чтобы добавлять визиты.")
            case .calendarUnavailable:
                return L10n.string("Could not find a calendar for new events.", "Не удалось найти календарь для новых событий.")
            }
        }
    }

    static func add(_ activity: PersonalActivity) async throws {
        guard let start = activity.scheduledDate else { throw Failure.noTime }
        let store = EKEventStore()
        guard try await requestAccess(store: store) else { throw Failure.accessDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw Failure.calendarUnavailable }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = [activity.sport.title, activity.court?.name].compactMap { $0 }.joined(separator: " · ")
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval((activity.durationMinutes ?? 60) * 60))
        event.location = [activity.court?.name, activity.court?.address].compactMap { $0 }.joined(separator: ", ")
        event.notes = [activity.comment, "НаТреню: sportsearch://upcoming"]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: "\n\n")
        try store.save(event, span: .thisEvent)
    }

    private static func requestAccess(store: EKEventStore) async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await store.requestWriteOnlyAccessToEvents()
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
