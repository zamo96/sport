import ActivityKit
import Foundation
import WidgetKit

enum UpcomingGamesWidgetStore {
    static let appGroupIdentifier = "group.shop.sportsearch.app"
    static let payloadKey = "upcomingGamesWidget.payload.v1"
    static let currentUserIdKey = "upcomingGamesWidget.currentUserId.v1"
    static let widgetKind = "UpcomingGamesWidget"

    static func save(
        gameRequests: [MatchGameRequest],
        personalActivities: [PersonalActivity] = [],
        currentUserId: String?
    ) {
        let gameItems = gameRequests
            .filter { !$0.isArchivedForTimeline }
            .map { request in
                UpcomingGamesWidgetGame(
                    id: request.id,
                    title: request.upcomingDisplayName(currentUserId: currentUserId),
                    sportTitle: request.sport.title,
                    startsAt: request.proposedDate,
                    durationMinutes: request.durationMinutes,
                    dateText: widgetDateText(for: request.proposedDate),
                    timeText: widgetTimeText(for: request.proposedDate),
                    courtName: request.proposedCourt?.name ?? request.sport.venuePendingTitle,
                    courtAddress: request.proposedCourt?.address,
                    statusLabel: request.statusLabel,
                    eventType: "game"
                )
            }

        let personalItems = personalActivities
            .filter { !$0.isArchivedForTimeline }
            .map { activity in
                UpcomingGamesWidgetGame(
                    id: activity.id,
                    title: "Личный визит",
                    sportTitle: activity.sport.title,
                    startsAt: activity.scheduledDate,
                    durationMinutes: activity.durationMinutes,
                    dateText: widgetDateText(for: activity.scheduledDate),
                    timeText: widgetTimeText(for: activity.scheduledDate),
                    courtName: activity.court?.name ?? activity.sport.venuePendingTitle,
                    courtAddress: activity.court?.address,
                    statusLabel: activity.widgetStatusLabel,
                    eventType: "personal"
                )
            }

        let games = (gameItems + personalItems)
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .prefix(3)

        write(UpcomingGamesWidgetPayload(updatedAt: Date(), games: Array(games)))
        if let currentUserId {
            UserDefaults(suiteName: appGroupIdentifier)?.set(currentUserId, forKey: currentUserIdKey)
        }
        UpcomingGameLiveActivityManager.sync(gameRequests: gameRequests, currentUserId: currentUserId)
    }

    static func clear() {
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
    private static let launchWindow: TimeInterval = 60 * 60
    private static let postGameDisplayInterval: TimeInterval = 2 * 60 * 60

    static func sync(gameRequests: [MatchGameRequest], currentUserId: String?) {
        Task {
            await syncAsync(gameRequests: gameRequests, currentUserId: currentUserId)
        }
    }

    static func endAll() {
        Task {
            await endAllAsync()
        }
    }

    private static func syncAsync(gameRequests: [MatchGameRequest], currentUserId: String?) async {
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
            staleDate: state.endsAt.addingTimeInterval(postGameDisplayInterval)
        )

        let activities = Activity<UpcomingGameLiveActivityAttributes>.activities
        for activity in activities where activity.attributes.gameId != request.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if let activity = activities.first(where: { $0.attributes.gameId == request.id }) {
            await activity.update(content)
            return
        }

        do {
            _ = try Activity.request(
                attributes: UpcomingGameLiveActivityAttributes(gameId: request.id),
                content: content,
                pushType: nil
            )
        } catch {
            return
        }
    }

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
                let secondsUntilStart = proposedDate.timeIntervalSince(now)
                let endsAt = proposedDate.addingTimeInterval(duration)
                let isBeforeStartWindow = secondsUntilStart > 0 && secondsUntilStart <= launchWindow
                let isActiveOrRecentlyEnded = secondsUntilStart <= 0 && now < endsAt.addingTimeInterval(postGameDisplayInterval)
                return isBeforeStartWindow || isActiveOrRecentlyEnded
            }
            .sorted { ($0.proposedDate ?? .distantFuture) < ($1.proposedDate ?? .distantFuture) }
            .first
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
