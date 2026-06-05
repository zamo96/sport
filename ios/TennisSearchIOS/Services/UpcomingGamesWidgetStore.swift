import Foundation
import WidgetKit

enum UpcomingGamesWidgetStore {
    static let appGroupIdentifier = "group.shop.sportsearch.app"
    static let payloadKey = "upcomingGamesWidget.payload.v1"
    static let currentUserIdKey = "upcomingGamesWidget.currentUserId.v1"
    static let widgetKind = "UpcomingGamesWidget"

    static func save(gameRequests: [MatchGameRequest], currentUserId: String?) {
        let games = gameRequests
            .filter { !$0.isArchivedForTimeline }
            .sorted { ($0.proposedDate ?? .distantFuture) < ($1.proposedDate ?? .distantFuture) }
            .prefix(3)
            .map { request in
                UpcomingGamesWidgetGame(
                    id: request.id,
                    title: request.upcomingDisplayName(currentUserId: currentUserId),
                    sportTitle: request.sport.title,
                    dateText: widgetDateText(for: request.proposedDate),
                    timeText: widgetTimeText(for: request.proposedDate),
                    courtName: request.proposedCourt?.name ?? request.sport.venuePendingTitle,
                    statusLabel: request.statusLabel
                )
            }

        write(UpcomingGamesWidgetPayload(updatedAt: Date(), games: Array(games)))
        if let currentUserId {
            UserDefaults(suiteName: appGroupIdentifier)?.set(currentUserId, forKey: currentUserIdKey)
        }
    }

    static func clear() {
        write(UpcomingGamesWidgetPayload(updatedAt: Date(), games: []))
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: currentUserIdKey)
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
    let dateText: String
    let timeText: String
    let courtName: String
    let statusLabel: String
}
