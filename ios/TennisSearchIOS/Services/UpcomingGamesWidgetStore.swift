import ActivityKit
import Foundation
import WidgetKit

enum UpcomingGamesWidgetStore {
    static let appGroupIdentifier = "group.shop.sportsearch.app"
    static let payloadKey = "upcomingGamesWidget.payload.v1"
    static let currentUserIdKey = "upcomingGamesWidget.currentUserId.v1"
    static let widgetKind = "UpcomingGamesWidget"

    @MainActor private static var activeAccountID: String?

    @MainActor
    static func setCurrentAccount(_ accountID: String) {
        if activeAccountID != accountID {
            clear()
            activeAccountID = accountID
        }
    }

    @MainActor
    static func save(
        gameRequests: [MatchGameRequest],
        personalActivities: [PersonalActivity] = [],
        currentUserId: String?
    ) {
        guard let currentUserId, currentUserId == activeAccountID else { return }
        write(makePayload(gameRequests: gameRequests, personalActivities: personalActivities, currentUserId: currentUserId))
        UserDefaults(suiteName: appGroupIdentifier)?.set(currentUserId, forKey: currentUserIdKey)
        UpcomingGameLiveActivityManager.sync(gameRequests: gameRequests, currentUserId: currentUserId)
    }

    private static func makePayload(
        gameRequests: [MatchGameRequest],
        personalActivities: [PersonalActivity],
        currentUserId: String?,
        referenceDate: Date = Date()
    ) -> UpcomingGamesWidgetPayload {
        let gameItems = gameRequests
            .filter { !["cancelled", "canceled", "declined", "rejected", "withdrawn", "completed"].contains($0.status.lowercased()) && $0.outcome != "played" && $0.outcome != "not_played" }
            .map { request in
                UpcomingGamesWidgetGame(
                    id: request.id,
                    title: request.upcomingDisplayName(currentUserId: currentUserId),
                    sportTitle: request.sport.title,
                    startsAt: request.proposedDate,
                    durationMinutes: UpcomingGamesWidgetSchedule.durationMinutes(request.durationMinutes, fallback: 90),
                    dateText: widgetDateText(for: request.proposedDate),
                    timeText: widgetTimeText(for: request.proposedDate),
                    courtName: request.proposedCourt?.name ?? request.sport.venuePendingTitle,
                    courtAddress: request.proposedCourt?.address,
                    statusLabel: request.statusLabel,
                    eventType: "game"
                )
            }

        let personalItems = personalActivities
            .filter { !["cancelled", "canceled", "completed"].contains($0.status.lowercased()) }
            .map { activity in
                UpcomingGamesWidgetGame(
                    id: activity.id,
                    title: "Личный визит",
                    sportTitle: activity.sport.title,
                    startsAt: activity.scheduledDate,
                    durationMinutes: UpcomingGamesWidgetSchedule.durationMinutes(activity.durationMinutes, fallback: activity.sport.defaultDurationMinutes),
                    dateText: widgetDateText(for: activity.scheduledDate),
                    timeText: widgetTimeText(for: activity.scheduledDate),
                    courtName: activity.court?.name ?? activity.sport.venuePendingTitle,
                    courtAddress: activity.court?.address,
                    statusLabel: activity.widgetStatusLabel,
                    eventType: "personal"
                )
            }

        let games = (gameItems + personalItems)
            .filter { UpcomingGamesWidgetSchedule.isUpcoming(startsAt: $0.startsAt, durationMinutes: $0.durationMinutes, at: referenceDate) }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .prefix(3)

        return UpcomingGamesWidgetPayload(updatedAt: referenceDate, games: Array(games))
    }

    @MainActor
    static func clear() {
        activeAccountID = nil
        write(UpcomingGamesWidgetPayload(updatedAt: Date(), games: []))
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: currentUserIdKey)
        UpcomingGameLiveActivityManager.endAll()
    }

    private static func write(_ payload: UpcomingGamesWidgetPayload) {
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }

        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: payloadKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private static func widgetDateText(for date: Date?) -> String {
        guard let date else {
            return "Дата уточняется"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

        if Calendar.current.isDateInToday(date) {
            return "Сегодня"
        }

        if Calendar.current.isDateInTomorrow(date) {
            return "Завтра"
        }

        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private static func widgetTimeText(for date: Date?) -> String {
        guard let date else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// Widget eligibility is independent of the in-app history and Live Activity grace period.
private enum UpcomingGamesWidgetSchedule {
    static func durationMinutes(_ value: Int?, fallback: Int) -> Int {
        guard let value, value > 0, value <= 24 * 60 else { return fallback }
        return value
    }

    static func isUpcoming(startsAt: Date?, durationMinutes: Int?, at referenceDate: Date) -> Bool {
        guard let startsAt else { return false }
        let duration = Self.durationMinutes(durationMinutes, fallback: 90)
        return startsAt.addingTimeInterval(TimeInterval(duration) * 60) > referenceDate
    }
}

private struct UpcomingGamesWidgetPayload: Codable {
    let updatedAt: Date
    let games: [UpcomingGamesWidgetGame]
}

private struct UpcomingGamesWidgetGame: Codable {
    let id: String
    let title: String
    let sportTitle: String
    let startsAt: Date?
    let durationMinutes: Int?
    let dateText: String
    let timeText: String
    let courtName: String
    let courtAddress: String?
    let statusLabel: String
    let eventType: String?
}

private enum UpcomingGameLiveActivityManager {
    @MainActor private static var generation = UUID()
    @MainActor private static var updateTask: Task<Void, Never>?
    private static let launchWindow: TimeInterval = 60 * 60
    private static let postGameDisplayInterval: TimeInterval = 2 * 60 * 60

    @MainActor
    static func sync(gameRequests: [MatchGameRequest], currentUserId: String?) {
        updateTask?.cancel()
        let revision = UUID()
        generation = revision
        updateTask = Task {
            await syncAsync(gameRequests: gameRequests, currentUserId: currentUserId, revision: revision)
        }
    }

    @MainActor
    static func endAll() {
        generation = UUID()
        updateTask?.cancel()
        updateTask = nil
        // Capture only the old activities so an asynchronous logout cleanup cannot
        // end a replacement activity created by the next signed-in account.
        let activities = Activity<UpcomingGameLiveActivityAttributes>.activities
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    @MainActor
    private static func syncAsync(gameRequests: [MatchGameRequest], currentUserId: String?, revision: UUID) async {
        guard revision == generation, !Task.isCancelled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        guard let request = liveActivityCandidate(in: gameRequests) else {
            await endAllAsync()
            return
        }

        let state = liveActivityState(for: request, currentUserId: currentUserId)
        let content = ActivityContent(
            state: state,
            staleDate: state.endsAt.addingTimeInterval(postGameDisplayInterval),
            relevanceScore: 1
        )

        let activities = Activity<UpcomingGameLiveActivityAttributes>.activities
        for activity in activities where activity.attributes.gameId != request.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard revision == generation, !Task.isCancelled else { return }
        guard let proposedDate = request.proposedDate else {
            return
        }

        if let activity = activities.first(where: { $0.attributes.gameId == request.id }) {
            if shouldRecreatePendingActivity(activity, proposedDate: proposedDate) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.update(content)
                if revision != generation || Task.isCancelled {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                return
            }
        }

        guard revision == generation, !Task.isCancelled else { return }
        do {
            if shouldStartImmediately(proposedDate: proposedDate) {
                _ = try Activity.request(
                    attributes: UpcomingGameLiveActivityAttributes(gameId: request.id),
                    content: content,
                    pushType: nil
                )
            } else {
                try requestScheduledLiveActivity(gameId: request.id, content: content, startsAt: proposedDate)
            }
        } catch {
            return
        }
    }

    @MainActor
    private static func endAllAsync() async {
        for activity in Activity<UpcomingGameLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func liveActivityCandidate(in gameRequests: [MatchGameRequest]) -> MatchGameRequest? {
        let now = Date()

        return gameRequests
            .filter { request in
                let rawStatus = request.status.lowercased()
                guard rawStatus == "accepted" || rawStatus == "approved" else {
                    return false
                }
                guard let proposedDate = request.proposedDate else {
                    return false
                }
                let duration = TimeInterval((request.durationMinutes ?? 90) * 60)
                let endsAt = proposedDate.addingTimeInterval(duration)
                return now < endsAt.addingTimeInterval(postGameDisplayInterval)
            }
            .sorted { ($0.proposedDate ?? .distantFuture) < ($1.proposedDate ?? .distantFuture) }
            .first
    }

    private static func shouldStartImmediately(proposedDate: Date) -> Bool {
        proposedDate.timeIntervalSinceNow <= launchWindow
    }

    private static func shouldRecreatePendingActivity(
        _ activity: Activity<UpcomingGameLiveActivityAttributes>,
        proposedDate: Date
    ) -> Bool {
        guard #available(iOS 26.0, *) else {
            return false
        }

        guard activity.activityState == .pending else {
            return false
        }

        let scheduledTimeDidChange = abs(activity.content.state.startsAt.timeIntervalSince(proposedDate)) > 60
        return scheduledTimeDidChange || shouldStartImmediately(proposedDate: proposedDate)
    }

    private static func requestScheduledLiveActivity(
        gameId: String,
        content: ActivityContent<UpcomingGameLiveActivityAttributes.ContentState>,
        startsAt: Date
    ) throws {
        guard #available(iOS 26.0, *) else {
            return
        }

        let scheduledStart = startsAt.addingTimeInterval(-launchWindow)
        guard scheduledStart > Date() else {
            _ = try Activity.request(
                attributes: UpcomingGameLiveActivityAttributes(gameId: gameId),
                content: content,
                pushType: nil
            )
            return
        }

        _ = try Activity.request(
            attributes: UpcomingGameLiveActivityAttributes(gameId: gameId),
            content: content,
            pushType: nil,
            style: .standard,
            alertConfiguration: AlertConfiguration(
                title: "Игра через час",
                body: "Проверьте время и место в НаТреню.",
                sound: .default
            ),
            start: scheduledStart
        )
    }

    private static func liveActivityState(
        for request: MatchGameRequest,
        currentUserId: String?
    ) -> UpcomingGameLiveActivityAttributes.ContentState {
        UpcomingGameLiveActivityAttributes.ContentState(
            title: request.upcomingDisplayName(currentUserId: currentUserId),
            sportTitle: request.sport.title,
            courtName: request.proposedCourt?.name ?? request.sport.venuePendingTitle,
            courtAddress: request.proposedCourt?.address,
            statusLabel: request.statusLabel,
            startsAt: request.proposedDate ?? Date(),
            durationMinutes: request.durationMinutes ?? 90,
            updatedAt: Date()
        )
    }
}

private extension PersonalActivity {
    var widgetStatusLabel: String {
        switch status.lowercased() {
        case "completed":
            return "Визит завершён"
        case "canceled", "cancelled":
            return "Отменён"
        default:
            return hasEnded ? "Визит завершён" : "Визит запланирован"
        }
    }
}
