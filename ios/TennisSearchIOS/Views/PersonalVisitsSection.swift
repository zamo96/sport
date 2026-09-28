import SwiftUI

extension PersonalActivity {
    var visitMoment: PersonalVisitMoment? {
        scheduledDate.map { PersonalVisitMoment(id: id, start: $0, durationMinutes: durationMinutes ?? 60, status: status) }
    }

    var visitTimeRange: String? {
        guard let start = scheduledDate else { return nil }
        let end = start.addingTimeInterval(TimeInterval((durationMinutes ?? 60) * 60))
        return "\(start.formattedHourMinute())–\(end.formattedHourMinute())"
    }
}

extension Court {
    /// The club on a map: its Yandex page when known, else Apple Maps at its coordinates.
    var visitMapURL: URL? {
        if let yandexMapsUrl, let url = URL(string: yandexMapsUrl) {
            return url
        }
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(locationLat),\(locationLng)"),
            URLQueryItem(name: "q", value: name)
        ]
        return components?.url
    }
}

enum PersonalVisitMark: Equatable {
    case saving(happened: Bool)
    case checked(happened: Bool)
}

/// "Personal visits" in Upcoming: the week, then the plans. A visit is marked right in its
/// card: the check draws, a ball flies into the day on the week, the card folds away. A visit
/// planned from a club rises into its place. All motion state lives here, so Discover itself
/// is not rebuilt frame by frame.
struct PersonalVisitsSection: View {
    let activities: [PersonalActivity]
    let currentUserID: String
    let arrivingID: String?
    let onArrivalShown: () -> Void
    /// Saves "happened" (true) or "didn't happen" (false). Throws after presenting the error.
    let onMark: (PersonalActivity, Bool) async throws -> PersonalActivity
    /// The marked card has started folding away: the caller takes the updated visit into its list.
    let onSettled: (PersonalActivity) -> Void
    let onOpenDetails: (PersonalActivity) -> Void
    let onAddToCalendar: (PersonalActivity) -> Void
    let onPlanAnother: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var marks: [String: PersonalVisitMark] = [:]
    @State private var marked: [String: PersonalActivity] = [:]
    @State private var landed: Set<String> = []
    @State private var leaving: Set<String> = []
    @State private var flight: VisitFlight?
    @State private var pulseDayIndex: Int?
    @State private var arrival: VisitArrival?

    var body: some View {
        ScrollViewReader { proxy in
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .onAppear { startArrivalIfNeeded(proxy) }
            .onChange(of: arrivingID) { _ in startArrivalIfNeeded(proxy) }
            .onChange(of: activities.map(\.id)) { _ in startArrivalIfNeeded(proxy) }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let week = makeWeek(now: now)
        let visible = visibleActivities(now: now)
        if !visible.isEmpty || !week.completed.isEmpty || !marks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("Personal visits", "Личные визиты"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                PersonalVisitWeekStrip(week: week, now: now, pulseDayIndex: pulseDayIndex)

                ForEach(visible) { activity in
                    card(for: activity, week: week, now: now)
                        .id("personal-visit-\(activity.id)")
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
                        ))
                }

                if visible.isEmpty {
                    Button(action: onPlanAnother) {
                        Label(L10n.string("Plan another visit", "Запланировать ещё визит"), systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VisitStyle.accent)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlayPreferenceValue(VisitAnchorKey.self) { anchors in
                flightLayer(anchors)
            }
        }
    }

    private func card(for activity: PersonalActivity, week: SportHomeWeek, now: Date) -> some View {
        let phase = activity.visitMoment.map { PersonalVisitTimeline.phase(of: $0, now: now) } ?? .later
        let isArriving = arrival?.id == activity.id && arrival?.isShown == false
        let isGlowing = arrival?.id == activity.id && arrival?.isGlowing == true
        let highlighted = arrival?.id == activity.id
        let weekDay = dayIndex(of: activity, in: week)

        return PersonalVisitCard(
            activity: activity,
            phase: phase,
            now: now,
            countsThisWeek: weekDay != nil,
            mark: marks[activity.id],
            onOpen: { onOpenDetails(activity) },
            onMark: { happened in
                mark(activity, happened: happened, dayIndex: weekDay)
            },
            onRoute: activity.court?.visitMapURL.map { url in
                {
                    AppHaptics.selection()
                    openURL(url)
                }
            },
            onAddToCalendar: { onAddToCalendar(activity) }
        )
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(VisitStyle.accent, lineWidth: 2)
                    .scaleEffect(isGlowing ? 1.05 : 1)
                    .opacity(isGlowing ? 0 : 0.85)
                    .allowsHitTesting(false)
            }
        }
        .offset(y: isArriving ? 140 : 0)
        .scaleEffect(isArriving ? 0.92 : 1)
        .opacity(isArriving ? 0 : 1)
    }

    // MARK: Data

    /// Plans in list order; a card being marked stays until its motion is over.
    private func visibleActivities(now: Date) -> [PersonalActivity] {
        let byID = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = PersonalVisitTimeline.upcomingOrder(activities.compactMap(\.visitMoment), now: now)
            .compactMap { byID[$0] }
        let undated = activities.filter { $0.scheduledDate == nil && PersonalVisitTimeline.isPlanned(status: $0.status) }
        return (ordered + undated).filter { !leaving.contains($0.id) }
    }

    /// The week counts a mark only once its ball has landed.
    private func makeWeek(now: Date) -> SportHomeWeek {
        let records = activities.map { activity -> SportHomeRecord in
            let status = landed.contains(activity.id) ? (marked[activity.id]?.status ?? activity.status) : activity.status
            return SportHomeRecord(
                id: activity.id, rootRequestID: nil, kind: .activity, ownerID: activity.userId,
                participantIDs: [], date: activity.scheduledDate, status: status, outcome: nil,
                durationMinutes: activity.durationMinutes, title: activity.sport.title, location: activity.court?.name
            )
        }
        return SportHomeWeek.make(records: records, currentUserID: currentUserID, now: now)
    }

    private func dayIndex(of activity: PersonalActivity, in week: SportHomeWeek) -> Int? {
        guard let start = activity.scheduledDate else { return nil }
        return week.days.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: start) }
    }

    // MARK: Marking

    private func mark(_ activity: PersonalActivity, happened: Bool, dayIndex: Int?) {
        guard marks[activity.id] == nil else { return }
        AppHaptics.impact(happened ? .rigid : .soft)
        withAnimation(AppMotion.quick) {
            marks[activity.id] = .saving(happened: happened)
        }

        Task { @MainActor in
            let updated: PersonalActivity
            do {
                updated = try await onMark(activity, happened)
            } catch {
                withAnimation(AppMotion.quick) {
                    _ = marks.removeValue(forKey: activity.id)
                }
                return
            }
            marked[activity.id] = updated
            withAnimation(.easeOut(duration: 0.3)) {
                marks[activity.id] = .checked(happened: happened)
            }
            if happened {
                await land(activity.id, dayIndex: dayIndex)
            } else {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            fold(activity.id)
        }
    }

    /// The ball leaves the card's button and fills the day on the week.
    private func land(_ id: String, dayIndex: Int?) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let dayIndex, !reduceMotion {
            flight = VisitFlight(id: id, dayIndex: dayIndex, progress: 0)
            withAnimation(.timingCurve(0.3, 0.7, 0.35, 1, duration: 0.45)) {
                flight?.progress = 1
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            flight = nil
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.55)) {
            _ = landed.insert(id)
            pulseDayIndex = dayIndex
        }
        AppHaptics.notification(.success)
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    /// The card folds away while the caller takes the marked visit into its list: the card
    /// has already left this list, so the caller's update cannot make it jump.
    private func fold(_ id: String) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)) {
            _ = leaving.insert(id)
        }
        if let updated = marked[id] {
            onSettled(updated)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            marks.removeValue(forKey: id)
            marked.removeValue(forKey: id)
            landed.remove(id)
            leaving.remove(id)
            if marks.isEmpty { pulseDayIndex = nil }
        }
    }

    @ViewBuilder
    private func flightLayer(_ anchors: [String: Anchor<CGPoint>]) -> some View {
        GeometryReader { proxy in
            if let flight, let from = anchors["mark-\(flight.id)"], let to = anchors["day-\(flight.dayIndex)"] {
                Circle()
                    .fill(VisitStyle.accent)
                    .frame(width: 18, height: 18)
                    .shadow(color: VisitStyle.accent.opacity(0.7), radius: 8)
                    .modifier(VisitArcFlight(progress: flight.progress, from: proxy[from], to: proxy[to]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Arrival

    /// A visit planned from a club rises into its place once, glows and taps its day.
    private func startArrivalIfNeeded(_ proxy: ScrollViewProxy) {
        guard arrival == nil, let id = arrivingID,
              let activity = activities.first(where: { $0.id == id }),
              PersonalVisitTimeline.isPlanned(status: activity.status) else { return }
        onArrivalShown()
        let dayIndex = dayIndex(of: activity, in: makeWeek(now: Date()))
        arrival = VisitArrival(id: id, isShown: reduceMotion, isGlowing: false)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo("personal-visit-\(id)", anchor: .center)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(AppMotion.emphasized) {
                arrival?.isShown = true
            }
            try? await Task.sleep(nanoseconds: 380_000_000)
            AppHaptics.impact(.soft)
            withAnimation(.easeOut(duration: 0.7)) {
                arrival?.isGlowing = true
                pulseDayIndex = dayIndex
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            arrival = nil
            if marks.isEmpty { pulseDayIndex = nil }
        }
    }
}

private struct VisitFlight: Equatable {
    let id: String
    let dayIndex: Int
    var progress: CGFloat
}

private struct VisitArrival: Equatable {
    let id: String
    var isShown: Bool
    var isGlowing: Bool
}

private struct VisitAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGPoint>] = [:]

    static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Moves along a curve that swings out past the card's edge before rising to the week.
private struct VisitArcFlight: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGPoint
    let to: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = min(max(progress, 0), 1)
        let control = CGPoint(x: min(from.x, to.x) - 44, y: (from.y + to.y) / 2 + 24)
        let u = 1 - t
        let x = u * u * from.x + 2 * u * t * control.x + t * t * to.x
        let y = u * u * from.y + 2 * u * t * control.y + t * t * to.y
        let scale = t < 0.15 ? 0.4 + 4 * t : 1 - 0.15 * t
        return content
            .scaleEffect(scale)
            .position(x: x, y: y)
    }
}

// MARK: - Week

struct PersonalVisitWeekStrip: View {
    let week: SportHomeWeek
    let now: Date
    let pulseDayIndex: Int?

    private enum DayState { case done, waiting, planned, empty }

    private var markedCount: Int { week.completed.count }

    private var countText: String {
        guard markedCount > 0 else { return L10n.string("nothing marked yet", "пока без отметок") }
        return L10n.string(
            "\(markedCount) \(markedCount == 1 ? "visit" : "visits")",
            "\(markedCount) \(RussianPlural.form(markedCount, one: "визит", few: "визита", many: "визитов"))"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("This week", "Эта неделя"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(countText)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(markedCount > 0 ? VisitStyle.accent : VisitStyle.secondaryText)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 0) {
                ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                    let isToday = Calendar.current.isDate(day.date, inSameDayAs: now)
                    VStack(spacing: 6) {
                        dot(state(of: day), isToday: isToday, index: index)
                        Text(CachedDateFormatters.display(format: "EEEEEE").string(from: day.date).capitalized)
                            .font(.system(size: 12, weight: isToday ? .bold : .semibold))
                            .foregroundStyle(isToday ? VisitStyle.accent : Color.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(VisitStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(VisitStyle.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("This week: \(countText)", "Эта неделя: \(countText)"))
    }

    private func state(of day: SportHomeDay) -> DayState {
        if day.completedCount > 0 { return .done }
        if day.reviewCount > 0 { return .waiting }
        if day.plannedCount > 0 { return .planned }
        return .empty
    }

    private func dot(_ state: DayState, isToday: Bool, index: Int) -> some View {
        ZStack {
            switch state {
            case .done:
                Circle()
                    .fill(VisitStyle.accent)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(VisitStyle.onAccent)
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .waiting:
                Circle()
                    .strokeBorder(VisitStyle.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [3.5, 3]))
            case .planned:
                Circle()
                    .strokeBorder(isToday ? VisitStyle.accent : Color.white.opacity(0.42), lineWidth: 2)
            case .empty:
                Circle()
                    .strokeBorder(isToday ? VisitStyle.accent.opacity(0.6) : Color.white.opacity(0.14), lineWidth: 1.5)
            }
            if pulseDayIndex == index {
                VisitRipple()
            }
        }
        .frame(width: 28, height: 28)
        .anchorPreference(key: VisitAnchorKey.self, value: .center) { ["day-\(index)": $0] }
    }
}

private struct VisitRipple: View {
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .stroke(VisitStyle.accent, lineWidth: 2)
            .scaleEffect(isExpanded ? 2.2 : 1)
            .opacity(isExpanded ? 0 : 0.7)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55)) {
                    isExpanded = true
                }
            }
    }
}

// MARK: - Card

struct PersonalVisitCard: View {
    let activity: PersonalActivity
    let phase: PersonalVisitPhase
    let now: Date
    /// Whether the visit's day is on the week strip above, so "counted in this week" is true.
    let countsThisWeek: Bool
    let mark: PersonalVisitMark?
    let onOpen: () -> Void
    let onMark: (Bool) -> Void
    let onRoute: (() -> Void)?
    let onAddToCalendar: () -> Void

    private var isRussian: Bool { L10n.string("en", "ru") == "ru" }

    private var title: String {
        guard let start = activity.scheduledDate, let range = activity.visitTimeRange else {
            return L10n.string("Time to be set", "Время уточняется")
        }
        return "\(PersonalVisitDateText.day(start, now: now, style: .short)) · \(range)"
    }

    private var subtitle: String {
        [activity.sport.title, activity.court?.name].compactMap { $0 }.joined(separator: " · ")
    }

    private var isChecked: Bool {
        if case .checked = mark { return true }
        return false
    }

    private var checkedHappened: Bool { mark == .checked(happened: true) }
    private var choseHappened: Bool { mark == .saving(happened: true) || mark == .checked(happened: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("personal-activity-details-\(activity.id)")

            switch phase {
            case .needsMark:
                statusLine
                markButtons
            case .today, .inProgress:
                countdown
                planActions
            case .later, .completed, .canceled:
                EmptyView()
            }
        }
        .padding(15)
        .background(VisitStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(phase == .needsMark && !isChecked ? VisitStyle.accent.opacity(0.55) : VisitStyle.line, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            PersonalVisitArtwork(court: activity.court, sport: activity.sport, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(VisitStyle.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .contentShape(Rectangle())
    }

    private var statusLine: some View {
        ZStack(alignment: .leading) {
            Text(L10n.string("The session is over — mark it", "Занятие закончилось — отметь его"))
                .foregroundStyle(VisitStyle.accent)
                .opacity(isChecked ? 0 : 1)
                .offset(y: isChecked ? -8 : 0)
            Text(checkedText)
                .foregroundStyle(Color.white.opacity(0.72))
                .opacity(isChecked ? 1 : 0)
                .offset(y: isChecked ? 0 : 8)
        }
        .font(.system(size: 13, weight: .semibold))
    }

    private var checkedText: String {
        guard checkedHappened else { return L10n.string("Marked as not happened", "Отметили: не получилось") }
        return countsThisWeek
            ? L10n.string("Marked · counted in this week", "Отмечено · засчитано в эту неделю")
            : L10n.string("Marked · saved to your history", "Отмечено · сохранили в историю")
    }

    private var markButtons: some View {
        HStack(spacing: 10) {
            Button {
                onMark(true)
            } label: {
                ZStack {
                    Text(L10n.string("Happened", "Состоялось"))
                        .opacity(mark == nil || mark == .saving(happened: false) || mark == .checked(happened: false) ? 1 : 0)
                    if mark == .saving(happened: true) {
                        ProgressView().tint(VisitStyle.onAccent)
                    }
                    VisitCheckmark()
                        .trim(from: 0, to: checkedHappened ? 1 : 0)
                        .stroke(VisitStyle.onAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(VisitStyle.onAccent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(VisitStyle.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(VisitPressStyle())
            .disabled(mark != nil)
            .anchorPreference(key: VisitAnchorKey.self, value: .center) { ["mark-\(activity.id)": $0] }
            .accessibilityIdentifier("visit-mark-done-\(activity.id)")

            Button {
                onMark(false)
            } label: {
                ZStack {
                    Text(L10n.string("Didn't happen", "Не получилось"))
                        .opacity(mark == .saving(happened: false) ? 0 : 1)
                    if mark == .saving(happened: false) {
                        ProgressView().tint(.white)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(VisitStyle.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(VisitPressStyle())
            .disabled(mark != nil)
            .opacity(choseHappened ? 0.35 : 1)
            .accessibilityIdentifier("visit-mark-missed-\(activity.id)")
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(countdownText(at: context.date))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(VisitStyle.accent)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(VisitStyle.accent.opacity(0.12), in: Capsule())
        }
    }

    private func countdownText(at date: Date) -> String {
        guard let start = activity.scheduledDate, start > date else {
            return L10n.string("On now", "Идёт сейчас")
        }
        return PersonalVisitTimeline.countdown(to: start, now: date, russian: isRussian)
    }

    private var planActions: some View {
        HStack(spacing: 10) {
            if let onRoute {
                actionButton(L10n.string("Directions", "Маршрут"), icon: "arrow.triangle.turn.up.right.diamond", action: onRoute)
            }
            actionButton(L10n.string("Add to calendar", "В календарь"), icon: "calendar.badge.plus", action: onAddToCalendar)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(VisitStyle.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(VisitPressStyle())
    }
}

private struct VisitCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.76))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.28))
        return path
    }
}

private struct VisitPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(AppMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Snackbar

struct PersonalVisitNotice: Identifiable {
    let id = UUID()
    let text: String
    /// Offers "Add photos" for a visit that has just been marked.
    let photoTarget: PersonalActivity?
}

/// One quiet line at the bottom instead of a celebration and a toast at once.
struct PersonalVisitSnackbar: View {
    let notice: PersonalVisitNotice
    let onAddPhotos: (PersonalActivity) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(VisitStyle.onAccent)
                .frame(width: 26, height: 26)
                .background(VisitStyle.accent, in: Circle())
            Text(notice.text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let activity = notice.photoTarget {
                Button {
                    onAddPhotos(activity)
                } label: {
                    Text(L10n.string("Add photos", "Добавить фото"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(VisitStyle.accent)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("visit-notice-add-photos")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Hide", "Скрыть"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 60)
        .background(Color(red: 0.11, green: 0.15, blue: 0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VisitStyle.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .task {
            // Long enough to reach "Add photos".
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }
}
