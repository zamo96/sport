import SwiftUI

struct SportHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @State private var isNotificationsPresented = false
    @State private var gameRequests: [MatchGameRequest] = []
    @State private var activities: [PersonalActivity] = []
    @State private var gameLoadFailed = false
    @State private var activityLoadFailed = false
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var loadToken = UUID()
    @State private var foregroundLoad: Task<Void, Never>?
    @State private var weekSnapshot: SportHomeWeek?
    @State private var workoutSnapshot: [ProfileWorkoutHistoryItem]?
    @State private var selectedWeekDay: Date?
    @State private var selectedWorkoutGallery: ActivityMediaGalleryItem?
    @State private var selectedPersonalActivityDetail: PersonalActivity?
    @State private var visibleWeekWorkouts = 3

    let onOpenIntent: (UserIntent) -> Void
    let onOpenUpcoming: (String?) -> Void

    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)
    private let surface = Color(red: 0.065, green: 0.08, blue: 0.065)

    private var loadIdentity: String {
        appModel.sessionGeneration.uuidString + ":" + (appModel.currentUser?.id ?? "guest")
    }

    private var week: SportHomeWeek {
        if let weekSnapshot { return weekSnapshot }
        let records = gameRequests.map { request in
            SportHomeRecord(
                id: request.id, rootRequestID: request.rootRequestId, kind: .game,
                ownerID: request.createdByUserId,
                participantIDs: request.participants.map(\.id) + [request.matchedUserId].compactMap { $0 },
                date: request.proposedDate, status: request.status, outcome: request.outcome,
                durationMinutes: request.durationMinutes, title: request.sport.title,
                location: request.proposedCourt?.name
            )
        } + activities.map { activity in
            SportHomeRecord(
                id: activity.id, rootRequestID: nil, kind: .activity, ownerID: activity.userId,
                participantIDs: [], date: activity.scheduledDate, status: activity.status, outcome: nil,
                durationMinutes: activity.durationMinutes,
                title: activity.sport.title, location: activity.court?.name
            )
        }
        return SportHomeWeek.make(records: records, currentUserID: appModel.currentUser?.id ?? "", calendar: calendar)
    }

    private var weekWorkouts: [ProfileWorkoutHistoryItem] {
        if let workoutSnapshot { return workoutSnapshot }
        let interval = week.interval
        return ProfileWorkoutHistoryItem.make(games: gameRequests, visits: activities, ownerID: appModel.currentUser?.id ?? "")
            .filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private var displayedWeekEvents: [SportHomeEvent] {
        guard let selectedWeekDay else { return week.events.sorted { $0.date > $1.date } }
        return week.events(on: selectedWeekDay, calendar: calendar)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if appModel.isAuthenticated {
                    accountContent
                } else {
                    guestCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(L10n.string("My week", "Моя неделя"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(lime)
        .navigationDestination(isPresented: $isNotificationsPresented) {
            NotificationsView()
                .toolbar(.visible, for: .navigationBar)
        }
        .sheet(item: $selectedWorkoutGallery) { ActivityMediaGallerySheet(item: $0) }
        .sheet(item: $selectedPersonalActivityDetail) { activity in
            PersonalActivityDetailSheet(activity: activity, onUpdated: { await load() }, onOpenCourt: { court in
                selectedPersonalActivityDetail = nil
                appModel.pendingCourtID = court.id
                appModel.navigate(to: .courts(sport: activity.sport))
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task(id: loadIdentity) { await load() }
        .refreshable { await load() }
        .onDisappear {
            foregroundLoad?.cancel()
            loadToken = UUID()
        }
        .onChange(of: loadIdentity) { _ in
            selectedWeekDay = nil
            selectedWorkoutGallery = nil
            selectedPersonalActivityDetail = nil
            visibleWeekWorkouts = 3
            weekSnapshot = nil
            workoutSnapshot = nil
        }
        .onChange(of: week.interval.start) { _ in
            selectedWeekDay = nil
            visibleWeekWorkouts = 3
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("НА ТРЕНЮ")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(lime)
                Text(greeting)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if appModel.isAuthenticated {
                Button { isNotificationsPresented = true } label: {
                    Image(systemName: "bell")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.075), in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if notificationManager.unreadNotificationCount > 0 {
                                Circle().fill(lime).frame(width: 9, height: 9)
                                    .padding(3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Notifications", "Уведомления"))
                .accessibilityValue("\(notificationManager.unreadNotificationCount)")
                .accessibilityIdentifier("sport-home-notifications")
            } else {
                Button(L10n.string("Sign in", "Войти")) { appModel.presentAuth(step: .email) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(lime)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private var greeting: String {
        let name = appModel.currentUser?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return L10n.string("Hi, \(name)", "Привет, \(name)")
        }
        return L10n.string("Your sport starts here", "Твой спорт начинается здесь")
    }

    @ViewBuilder
    private var accountContent: some View {
        if isLoading && !hasLoaded {
            ProgressView(L10n.string("Loading your week…", "Загружаем твою неделю…"))
                .tint(lime)
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            if gameLoadFailed || activityLoadFailed { loadError }
            if let event = week.needsReview {
                eventButton(event, heading: L10n.string("How did it go?", "Как всё прошло?"))
            }
            if let event = week.nearestPlan {
                eventButton(event, heading: L10n.string("Your next plan", "Ближайший план"))
            }
            if hasLoaded && !(gameLoadFailed && activityLoadFailed) {
                weekCard
            }
        }
    }

    private var loadError: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("Could not load everything", "Не всё удалось загрузить"), systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(gameLoadFailed && activityLoadFailed
                 ? L10n.string("Your games and visits are unavailable. This does not mean your history is empty.", "Игры и визиты пока недоступны. Это не значит, что история пустая.")
                 : gameLoadFailed
                    ? L10n.string("Games are unavailable. Only loaded visits are shown below.", "Игры пока недоступны. Ниже показаны только загруженные визиты.")
                    : L10n.string("Visits are unavailable. Only loaded games are shown below.", "Визиты пока недоступны. Ниже показаны только загруженные игры."))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
            Button(L10n.string("Try again", "Повторить")) {
                foregroundLoad?.cancel()
                foregroundLoad = Task { await load() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(lime)
            .frame(minHeight: 44)
            .disabled(isLoading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 21))
        .accessibilityIdentifier("sport-home-load-error")
    }

    private func eventButton(_ event: SportHomeEvent, heading: String) -> some View {
        Button { openEvent(event) } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: event.state == .needsReview ? "checkmark.bubble" : "calendar")
                    .font(.title2)
                    .foregroundStyle(lime)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading).font(.caption).foregroundStyle(.white.opacity(0.55))
                    Text(event.title).font(.headline).foregroundStyle(.white)
                    Text(event.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    if let location = event.location, !location.isEmpty {
                        Text(location).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Text(stateTitle(event)).font(.caption).foregroundStyle(lime.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(18)
            .background(surface, in: RoundedRectangle(cornerRadius: 21))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sport-home-event-\(event.id)")
    }

    private func stateTitle(_ event: SportHomeEvent) -> String {
        switch event.state {
        case .pending: return L10n.string("Waiting for confirmation", "Ждёт подтверждения")
        case .needsReview: return L10n.string("Mark the result · photo optional", "Отметить результат · можно без фото")
        case .completed: return L10n.string("Marked as completed", "Отмечено как состоявшееся")
        case .canceled: return L10n.string("Canceled · not counted as a workout", "Отменено · не учитывается как занятие")
        case .notPlayed: return L10n.string("Did not take place · not counted as a workout", "Не состоялось · не учитывается как занятие")
        case .planned:
            return event.kind == .game
                ? L10n.string("Game confirmed", "Игра согласована")
                : L10n.string("Personal plan · not a booking", "Личный план · не бронирование")
        }
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("My sports week", "Моя спортивная неделя"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(L10n.string("Your rhythm. No daily streak required.", "В твоём ритме. Без обязательной серии."))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(week.days) { day in weekDayButton(day, expanded: true) }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    weekTimeline.frame(minWidth: 308)
                    ScrollView(.horizontal, showsIndicators: false) {
                        weekTimeline
                    }
                }
            }
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 14))) {
                Label(L10n.string("Completed", "Состоялось"), systemImage: "checkmark")
                Label(L10n.string("Planned", "В планах"), systemImage: "circle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.55))

            if let selectedWeekDay {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedWeekDay, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Button(L10n.string("Entire week", "Вся неделя")) {
                        self.selectedWeekDay = nil
                        visibleWeekWorkouts = 3
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                    .accessibilityIdentifier("sport-home-entire-week")
                }
            }
            weekJournal
            Button { onOpenUpcoming(nil) } label: {
                HStack {
                    Text(L10n.string("My plans and results", "Мои планы и результаты"))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(lime)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            Text(L10n.string("Based on available records. Only marked results count; photos are optional.", "По доступным записям. Учитываются только отмеченные результаты; фото не обязательно."))
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .padding(20)
        .background(surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var weekTimeline: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { day in weekDayButton(day, expanded: false) }
        }
    }

    private func weekDayButton(_ day: SportHomeDay, expanded: Bool) -> some View {
        let selected = selectedWeekDay.map { calendar.isDate($0, inSameDayAs: day.date) } ?? false
        let dayWorkout = weekWorkouts.first { calendar.isDate($0.date, inSameDayAs: day.date) && (!$0.photoPaths.isEmpty || !$0.videoPaths.isEmpty) }
        let media = dayWorkout.flatMap { ActivityMediaGalleryItem.media(photos: $0.photoPaths, videos: $0.videoPaths).first }
        return Button {
            selectedWeekDay = day.date
            visibleWeekWorkouts = 3
            AppHaptics.selection()
        } label: {
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.subheadline.weight(.semibold)).foregroundStyle(selected ? lime : .white)
                    Text(daySummary(day))
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(selected ? lime.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 6) {
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    ZStack {
                        ZStack {
                            Circle().fill(day.completedCount > 0 ? lime : .white.opacity(0.08))
                            if let media {
                                ActivityMediaThumbnail(item: media).clipShape(Circle())
                                Text(day.date, format: .dateTime.day())
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 4).background(.black.opacity(0.68), in: Capsule())
                                    .offset(y: 8)
                            } else {
                                Text(day.date, format: .dateTime.day())
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(day.completedCount > 0 ? Color.black : .white)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(selected ? lime : .clear, lineWidth: 2))
                        .scaleEffect(selected ? 1.2 : 1)
                        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: selected)
                    }
                    .frame(width: 44, height: 44)
                    Image(systemName: day.completedCount > 0 ? "checkmark" : day.plannedCount > 0 ? "circle.fill" : day.reviewCount > 0 ? "questionmark" : day.otherCount > 0 ? "xmark" : "minus")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(day.completedCount > 0 || day.plannedCount > 0 || day.reviewCount > 0 ? lime : .white.opacity(0.3))
                }
                .frame(width: 44).padding(.vertical, 3)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(daySummary(day) + (calendar.isDateInToday(day.date) ? L10n.string(" Today.", " Сегодня.") : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
        .accessibilityIdentifier("sport-home-week-day-\(calendar.component(.weekday, from: day.date))")
    }

    private func daySummary(_ day: SportHomeDay) -> String {
        var text = L10n.string("Completed: \(day.completedCount). Planned: \(day.plannedCount).", "Состоялось: \(day.completedCount). В планах: \(day.plannedCount).")
        if day.reviewCount > 0 { text += L10n.string(" Awaiting result: \(day.reviewCount).", " Ждут результата: \(day.reviewCount).") }
        if day.otherCount > 0 { text += L10n.string(" Canceled or not played: \(day.otherCount).", "Отменены или не состоялись: \(day.otherCount).") }
        return text
    }

    private func openEvent(_ event: SportHomeEvent) {
        if event.kind == .activity, let activity = activities.first(where: { $0.id == event.sourceID }) {
            selectedPersonalActivityDetail = activity
        } else { onOpenUpcoming(event.kind == .game ? event.sourceID : nil) }
    }

    @ViewBuilder
    private var weekJournal: some View {
        if !displayedWeekEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(displayedWeekEvents.prefix(visibleWeekWorkouts))) { event in
                    if selectedWeekDay == nil {
                        Text(event.date, format: .dateTime.day().month(.wide))
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                    if let item = weekWorkouts.first(where: { $0.id == event.id }), event.state == .completed {
                        WorkoutJournalCard(item: item) { selectedWorkoutGallery = $0 }
                        Button { openEvent(event) } label: {
                            Label(L10n.string("Open details", "Открыть подробности"), systemImage: "arrow.up.right")
                                .font(.subheadline.weight(.medium)).foregroundStyle(lime).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sport-home-detail-\(event.id)")
                    } else {
                        eventButton(event, heading: event.kind == .activity
                            ? L10n.string("Personal visit", "Личный визит") : L10n.string("Game", "Игра"))
                    }
                }
                if displayedWeekEvents.count > visibleWeekWorkouts {
                    Button(L10n.string("Show more", "Показать ещё")) { visibleWeekWorkouts += 3 }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(lime).frame(minHeight: 44)
                }
            }
        } else if !gameLoadFailed && !activityLoadFailed {
            Text(selectedWeekDay == nil
                 ? L10n.string("No games or visits recorded for this week yet. Your plans and results will appear here.", "На этой неделе пока нет игр и визитов. Здесь появятся твои планы и результаты.")
                 : L10n.string("No games or visits recorded for this day.", "На этот день нет записей об играх и визитах."))
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        } else {
            Text(L10n.string("Not all activities could be loaded. Try again above to see the full day.", "Не все занятия удалось загрузить. Повтори загрузку выше, чтобы увидеть весь день."))
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("Your plans, all together", "Твои планы — в одном месте"), systemImage: "calendar")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(L10n.string("Explore the app now. Sign in to see your own games, visits and completed activities here.", "Знакомься с приложением уже сейчас. После входа здесь появятся твои игры, визиты и отмеченные занятия."))
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 21))
    }

    @MainActor
    private func load() async {
        let token = UUID()
        loadToken = token
        let generation = appModel.sessionGeneration
        guard let userID = appModel.currentUser?.id else {
            gameRequests = []
            activities = []
            invalidateProjections()
            gameLoadFailed = false
            activityLoadFailed = false
            hasLoaded = false
            isLoading = false
            return
        }
        isLoading = true
        defer { if loadToken == token { isLoading = false } }
        async let gamesResult = fetchGames()
        async let visitsResult = fetchVisits()
        let (games, visits) = await (gamesResult, visitsResult)
        guard appModel.isCurrentSession(generation), appModel.currentUser?.id == userID,
              loadToken == token else { return }
        switch games {
        case .success(let values): gameRequests = values; gameLoadFailed = false
        case .failure: gameRequests = []; gameLoadFailed = true
        }
        switch visits {
        case .success(let values): activities = values; activityLoadFailed = false
        case .failure: activities = []; activityLoadFailed = true
        }
        rebuildProjections()
        hasLoaded = true
    }

    @MainActor
    private func rebuildProjections() {
        let projectedWeek = SportHomeWeek.make(
            records: gameRequests.map { request in
                SportHomeRecord(
                    id: request.id, rootRequestID: request.rootRequestId, kind: .game,
                    ownerID: request.createdByUserId,
                    participantIDs: request.participants.map(\.id) + [request.matchedUserId].compactMap { $0 },
                    date: request.proposedDate, status: request.status, outcome: request.outcome,
                    durationMinutes: request.durationMinutes, title: request.sport.title,
                    location: request.proposedCourt?.name
                )
            } + activities.map { activity in
                SportHomeRecord(
                    id: activity.id, rootRequestID: nil, kind: .activity, ownerID: activity.userId,
                    participantIDs: [], date: activity.scheduledDate, status: activity.status, outcome: nil,
                    durationMinutes: activity.durationMinutes, title: activity.sport.title,
                    location: activity.court?.name
                )
            },
            currentUserID: appModel.currentUser?.id ?? "",
            calendar: calendar
        )
        weekSnapshot = projectedWeek
        let interval = projectedWeek.interval
        workoutSnapshot = ProfileWorkoutHistoryItem.make(
            games: gameRequests,
            visits: activities,
            ownerID: appModel.currentUser?.id ?? ""
        ).filter { $0.date >= interval.start && $0.date < interval.end }
    }

    @MainActor
    private func invalidateProjections() {
        weekSnapshot = nil
        workoutSnapshot = nil
    }

    @MainActor
    private func fetchGames() async -> Result<[MatchGameRequest], Error> {
        do { return .success(try await appModel.repository.fetchMyGameRequests()) }
        catch { return .failure(error) }
    }

    @MainActor
    private func fetchVisits() async -> Result<[PersonalActivity], Error> {
        do { return .success(try await appModel.repository.fetchPersonalActivities()) }
        catch { return .failure(error) }
    }
}
