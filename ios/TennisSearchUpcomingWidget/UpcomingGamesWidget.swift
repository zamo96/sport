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
    let courtAddress: String?
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
                        courtAddress: "Крестовский проспект, 21",
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
    let address: String?
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
                    courtAddress: request.proposedCourt?.address,
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
        if family == .systemSmall {
            return AnyView(compactContent(for: game))
        }

        return AnyView(regularContent(for: game))
    }

    private func compactContent(for game: UpcomingGamesWidgetGame) -> some View {
        let statusStyle = game.statusStyle

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.green)
                    .frame(width: 16, height: 16)

                Text("Игра")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Text(game.compactStatusLabel)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(statusStyle.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(statusStyle.background, in: Capsule())
            }

            Spacer(minLength: 0)

            Text(game.title)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(game.dateText)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(game.timeText)
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .foregroundStyle(Color.green)

                Text(game.compactVenueLine)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)

                Text(game.courtName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func regularContent(for game: UpcomingGamesWidgetGame) -> some View {
        let statusStyle = game.statusStyle

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.green)
                Text("Ближайшая игра")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(game.statusLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(statusStyle.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(statusStyle.background, in: Capsule())
            }

            Spacer(minLength: 2)

            Text(game.title)
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
                .allowsTightening(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(game.dateText), \(game.timeText)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text("\(game.sportTitle) · \(game.courtName)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)

                if let courtAddress = game.courtAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !courtAddress.isEmpty {
                    Text(courtAddress)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyContent: some View {
        if family == .systemSmall {
            return AnyView(compactEmptyContent)
        }

        return AnyView(regularEmptyContent)
    }

    private var compactEmptyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Color.green)

            Spacer(minLength: 0)

            Text("Игр пока нет")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text("Первая подтвержденная игра появится здесь.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var regularEmptyContent: some View {
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

private struct WidgetStatusStyle {
    let foreground: Color
    let background: Color
}

private extension UpcomingGamesWidgetGame {
    var compactVenueLine: String {
        let normalizedCourtName = courtName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCourtName.isEmpty else {
            return sportTitle
        }

        return "\(sportTitle) · \(normalizedCourtName)"
    }

    var compactStatusLabel: String {
        switch statusLabel {
        case "Ждём подтверждение", "Ждёт подтверждения", "Требуется ответ", "Ожидает подтверждения":
            return "Ждём"
        case "Игра подтверждена":
            return "Подтв."
        case "Скоро начнется":
            return "Скоро"
        case "Игра началась":
            return "Старт"
        case "Игра идет":
            return "Идёт"
        case "Игра закончилась":
            return "Финиш"
        case "Игра прошла":
            return "Прошла"
        default:
            return statusLabel
        }
    }

    var statusStyle: WidgetStatusStyle {
        switch statusLabel {
        case "Ждём подтверждение", "Ждёт подтверждения", "Требуется ответ", "Ожидает подтверждения":
            return WidgetStatusStyle(
                foreground: Color(red: 0.49, green: 0.45, blue: 0.78),
                background: Color(red: 0.91, green: 0.90, blue: 0.99)
            )
        case "Игра подтверждена", "Игра прошла":
            return WidgetStatusStyle(
                foreground: Color(red: 0.16, green: 0.58, blue: 0.33),
                background: Color(red: 0.86, green: 0.95, blue: 0.89)
            )
        case "Скоро начнется":
            return WidgetStatusStyle(
                foreground: Color(red: 0.78, green: 0.52, blue: 0.18),
                background: Color(red: 0.99, green: 0.94, blue: 0.83)
            )
        case "Игра началась", "Игра идет":
            return WidgetStatusStyle(
                foreground: Color(red: 0.17, green: 0.50, blue: 0.72),
                background: Color(red: 0.86, green: 0.93, blue: 0.98)
            )
        case "Игра закончилась", "Не сыграли":
            return WidgetStatusStyle(
                foreground: Color(red: 0.33, green: 0.33, blue: 0.38),
                background: Color(red: 0.90, green: 0.90, blue: 0.92)
            )
        case "Отменена":
            return WidgetStatusStyle(
                foreground: Color(red: 0.72, green: 0.22, blue: 0.20),
                background: Color(red: 0.96, green: 0.88, blue: 0.88)
            )
        default:
            return WidgetStatusStyle(
                foreground: Color(red: 0.16, green: 0.58, blue: 0.33),
                background: Color(red: 0.86, green: 0.95, blue: 0.89)
            )
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
