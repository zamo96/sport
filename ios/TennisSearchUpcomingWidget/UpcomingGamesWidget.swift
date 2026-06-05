import SwiftUI
import WidgetKit

private let appGroupIdentifier = "group.shop.sportsearch.app"
private let payloadKey = "upcomingGamesWidget.payload.v1"
private let currentUserIdKey = "upcomingGamesWidget.currentUserId.v1"
private let sessionTokenKey = "SportSearch.sessionToken"

struct UpcomingGamesWidgetPayload: Codable {
    let updatedAt: Date
    let games: [UpcomingGamesWidgetGame]
}

struct UpcomingGamesWidgetGame: Codable, Identifiable {
    let id: String
    let title: String
    let sportTitle: String
    let dateText: String
    let timeText: String
    let courtName: String
    let statusLabel: String
}

struct UpcomingGamesEntry: TimelineEntry {
    let date: Date
    let payload: UpcomingGamesWidgetPayload
}

struct UpcomingGamesProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingGamesEntry {
        UpcomingGamesEntry(
            date: Date(),
            payload: UpcomingGamesWidgetPayload(
                updatedAt: Date(),
                games: [
                    UpcomingGamesWidgetGame(
                        id: "preview",
                        title: "Анна Волкова",
                        sportTitle: "Теннис",
                        dateText: "Сегодня",
                        timeText: "19:30",
                        courtName: "Крестовский корт",
                        statusLabel: "Игра подтверждена"
                    )
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingGamesEntry) -> Void) {
        Task {
            let payload = await loadRemotePayload() ?? loadPayload()
            completion(UpcomingGamesEntry(date: Date(), payload: payload))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingGamesEntry>) -> Void) {
        Task {
            let payload = await loadRemotePayload() ?? loadPayload()
            let entry = UpcomingGamesEntry(date: Date(), payload: payload)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func loadPayload() -> UpcomingGamesWidgetPayload {
        guard
            let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: payloadKey),
            let payload = try? JSONDecoder().decode(UpcomingGamesWidgetPayload.self, from: data)
        else {
            return UpcomingGamesWidgetPayload(updatedAt: Date(), games: [])
        }

        return payload
    }

    private func loadRemotePayload() async -> UpcomingGamesWidgetPayload? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let token = defaults.string(forKey: sessionTokenKey),
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let baseURL = widgetAPIBaseURL
        else {
            return nil
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("game-requests/my"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                return nil
            }

            let envelope = try JSONDecoder().decode(WidgetGameRequestsEnvelope.self, from: data)
            let payload = UpcomingGamesWidgetPayload(
                updatedAt: Date(),
                games: envelope.gameRequests.widgetGames(currentUserId: defaults.string(forKey: currentUserIdKey))
            )
            if let encoded = try? JSONEncoder().encode(payload) {
                defaults.set(encoded, forKey: payloadKey)
            }
            return payload
        } catch {
            return nil
        }
    }

    private var widgetAPIBaseURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }

        let scheme = (Bundle.main.object(forInfoDictionaryKey: "APIScheme") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "\((scheme?.isEmpty == false ? scheme : "https") ?? "https")://\(trimmed)")
    }
}

private struct WidgetGameRequestsEnvelope: Decodable {
    let gameRequests: [WidgetGameRequest]
}

private struct WidgetGameRequest: Decodable {
    let id: String
    let status: String
    let proposedDatetime: String
    let durationMinutes: Int?
    let outcome: String?
    let sport: String?
    let proposedCourt: WidgetCourt?
    let createdByUserId: String?
    let matchedUserId: String?
    let createdByUser: WidgetUser?
    let matchedUser: WidgetUser?
    let participants: [WidgetUser]?
}

private struct WidgetCourt: Decodable {
    let name: String?
}

private struct WidgetUser: Decodable, Identifiable {
    let id: String
    let name: String?

    var displayName: String {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Игрок" : value
    }
}

private extension Array where Element == WidgetGameRequest {
    func widgetGames(currentUserId: String?) -> [UpcomingGamesWidgetGame] {
        filter { !$0.isArchivedForTimeline }
            .sorted { ($0.proposedDate ?? .distantFuture) < ($1.proposedDate ?? .distantFuture) }
            .prefix(3)
            .map { request in
                UpcomingGamesWidgetGame(
                    id: request.id,
                    title: request.displayTitle(currentUserId: currentUserId),
                    sportTitle: request.sportTitle,
                    dateText: request.widgetDateText,
                    timeText: request.widgetTimeText,
                    courtName: request.proposedCourt?.name ?? request.venuePendingTitle,
                    statusLabel: request.statusLabel
                )
            }
    }
}

private extension WidgetGameRequest {
    var proposedDate: Date? {
        proposedDatetime.parsedISODateValue()
    }

    var sportTitle: String {
        switch sport {
        case "padel": return "Падел"
        case "squash": return "Сквош"
        case "badminton": return "Бадминтон"
        case "table_tennis": return "Настольный теннис"
        case "volleyball": return "Волейбол"
        case "fitness": return "Фитнес"
        case "boxing": return "Бокс"
        case "yoga": return "Йога"
        case "football": return "Футбол"
        default: return "Теннис"
        }
    }

    var venuePendingTitle: String {
        switch sport {
        case "fitness": return "Зал уточняется"
        case "boxing", "yoga": return "Студия уточняется"
        case "football", "volleyball": return "Площадка уточняется"
        default: return "Корт уточняется"
        }
    }

    var widgetDateText: String {
        guard let date = proposedDate else {
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

    var widgetTimeText: String {
        guard let date = proposedDate else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var statusLabel: String {
        if let outcomeLabel {
            return outcomeLabel
        }

        let rawStatus = status.lowercased()
        if ["cancelled", "canceled", "declined", "rejected", "withdrawn"].contains(rawStatus) {
            return "Отменена"
        }

        guard rawStatus == "accepted" || rawStatus == "approved" else {
            return matchedUserId != nil ? "Ждём подтверждение" : "Поиск"
        }

        guard let startDate = proposedDate else {
            return "Игра подтверждена"
        }

        let now = Date()
        let duration = TimeInterval((durationMinutes ?? 90) * 60)
        let secondsUntilStart = startDate.timeIntervalSince(now)
        if secondsUntilStart <= 2 * 60 * 60, secondsUntilStart > 0 {
            return "Скоро начнется"
        }

        let secondsSinceStart = now.timeIntervalSince(startDate)
        if secondsSinceStart >= 0, secondsSinceStart <= 10 * 60 {
            return "Игра началась"
        }
        if secondsSinceStart > 10 * 60, secondsSinceStart < duration {
            return "Игра идет"
        }
        if secondsSinceStart >= duration {
            return "Игра закончилась"
        }

        return "Игра подтверждена"
    }

    var isArchivedForTimeline: Bool {
        let rawStatus = status.lowercased()
        if ["cancelled", "canceled", "declined", "rejected", "withdrawn"].contains(rawStatus) {
            return true
        }

        guard let proposedDate else {
            return false
        }

        let duration = TimeInterval((durationMinutes ?? 90) * 60)
        return Date().timeIntervalSince(proposedDate) >= duration
    }

    private var outcomeLabel: String? {
        switch outcome {
        case "played": return "Игра прошла"
        case "not_played": return "Не сыграли"
        default: return nil
        }
    }

    func displayTitle(currentUserId: String?) -> String {
        let people = visibleParticipants(currentUserId: currentUserId)

        if people.count >= 3, let first = people.first {
            return "\(first.displayName) и еще \(people.count - 1)"
        }

        if people.count == 2 {
            return people.map(\.displayName).joined(separator: " и ")
        }

        if let first = people.first {
            return first.displayName
        }

        return otherUser(currentUserId: currentUserId)?.displayName ?? "Игрок"
    }

    private func visibleParticipants(currentUserId: String?) -> [WidgetUser] {
        let current = currentUserId ?? ""
        let people = participants ?? []
        return people.filter { $0.id != current }
    }

    private func otherUser(currentUserId: String?) -> WidgetUser? {
        guard let currentUserId else {
            return matchedUser ?? createdByUser
        }
        if createdByUserId == currentUserId {
            return matchedUser
        }
        return createdByUser
    }
}

private extension String {
    func parsedISODateValue() -> Date? {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: self) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}

struct UpcomingGamesWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingGamesProvider.Entry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.02, green: 0.11, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let game = entry.payload.games.first {
                content(for: game)
            } else {
                emptyContent
            }
        }
        .widgetContainerBackground {
            LinearGradient(
                colors: [Color.black, Color(red: 0.02, green: 0.11, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func content(for game: UpcomingGamesWidgetGame) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.green)
                Text("Ближайшая игра")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Text(game.title)
                .font(.system(size: family == .systemSmall ? 20 : 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(game.dateText), \(game.timeText)")
                    .font(.system(size: family == .systemSmall ? 15 : 17, weight: .black, design: .rounded))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)

                Text("\(game.sportTitle) · \(game.courtName)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(family == .systemSmall ? 1 : 2)
            }

            Text(game.statusLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.88))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.green, in: Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Color.green)

            Spacer(minLength: 0)

            Text("Ближайших игр пока нет")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.74)

            Text("Подтвержденная игра появится здесь автоматически.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private extension View {
    @ViewBuilder
    func widgetContainerBackground<Background: View>(
        @ViewBuilder _ background: () -> Background
    ) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                background()
            }
        } else {
            self.background(background())
        }
    }
}

@main
struct UpcomingGamesWidget: Widget {
    let kind = "UpcomingGamesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingGamesProvider()) { entry in
            UpcomingGamesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ближайшие игры")
        .description("Показывает следующую подтвержденную игру SportSearch.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
