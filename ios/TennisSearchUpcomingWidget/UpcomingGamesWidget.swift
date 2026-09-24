import ActivityKit
import SwiftUI
import WidgetKit

private let appGroupIdentifier = "group.shop.sportsearch.app"
private let payloadKey = "upcomingGamesWidget.payload.v1"
private let currentUserIdKey = "upcomingGamesWidget.currentUserId.v1"
private let countdownLeadTime: TimeInterval = 60 * 60
private let countdownTimelineCadence: TimeInterval = 60
private let maximumTimelineEntryCount = 90

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

struct UpcomingGamesWidgetPayload: Codable {
    let updatedAt: Date
    let games: [UpcomingGamesWidgetGame]
}

struct UpcomingGamesWidgetGame: Codable, Identifiable {
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

private extension UpcomingGamesWidgetGame {
    var resolvedDurationMinutes: Int {
        let shortPersonalSports = ["Фитнес", "Бокс", "Йога", "Бадминтон", "Настольный теннис", "Сквош", "Бег", "Сапборд", "SUP", "Fitness", "Boxing", "Yoga", "Badminton", "Table tennis", "Table Tennis", "Squash", "Running", "SUP boarding", "SUP board"]
        let fallback = eventType == "personal" && shortPersonalSports.contains(sportTitle) ? 60 : 90
        return UpcomingGamesWidgetSchedule.durationMinutes(durationMinutes, fallback: fallback)
    }

    var endsAt: Date? {
        startsAt?.addingTimeInterval(TimeInterval(resolvedDurationMinutes) * 60)
    }

    func dated(at referenceDate: Date) -> UpcomingGamesWidgetGame {
        guard let startsAt else { return self }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        let dateLabel: String
        if calendar.isDate(startsAt, inSameDayAs: referenceDate) {
            dateLabel = "Сегодня"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
                  calendar.isDate(startsAt, inSameDayAs: tomorrow) {
            dateLabel = "Завтра"
        } else {
            dateLabel = formatter.string(from: startsAt)
        }
        formatter.dateFormat = "HH:mm"
        return UpcomingGamesWidgetGame(
            id: id, title: title, sportTitle: sportTitle, startsAt: startsAt,
            durationMinutes: resolvedDurationMinutes, dateText: dateLabel,
            timeText: formatter.string(from: startsAt), courtName: courtName,
            courtAddress: courtAddress, statusLabel: statusLabel, eventType: eventType
        )
    }
}

private extension UpcomingGamesWidgetPayload {
    func upcoming(at referenceDate: Date) -> UpcomingGamesWidgetPayload {
        let eligible = games.filter {
            !["Отменена", "Отменён", "Игра прошла", "Не сыграли", "Визит завершён"].contains($0.statusLabel)
                && UpcomingGamesWidgetSchedule.isUpcoming(
                    startsAt: $0.startsAt, durationMinutes: $0.resolvedDurationMinutes, at: referenceDate)
        }
        return UpcomingGamesWidgetPayload(updatedAt: updatedAt, games: eligible
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .prefix(3).map { $0.dated(at: referenceDate) })
    }
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
                        startsAt: Date(),
                        durationMinutes: 90,
                        dateText: "Сегодня",
                        timeText: "19:30",
                        courtName: "Крестовский корт",
                        courtAddress: "Крестовский проспект, 21",
                        statusLabel: "Игра подтверждена",
                        eventType: "game"
                    )
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingGamesEntry) -> Void) {
        Task {
            let payload = await loadRemotePayload() ?? loadPayload()
            let referenceDate = Date()
            completion(UpcomingGamesEntry(date: referenceDate, payload: payload.upcoming(at: referenceDate)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingGamesEntry>) -> Void) {
        Task {
            let payload = await loadRemotePayload() ?? loadPayload()
            let referenceDate = Date()
            let entries = timelineEntries(for: payload, from: referenceDate)
            let nextRefresh = nextRefreshDate(for: payload, from: referenceDate)
            completion(Timeline(entries: entries, policy: .after(nextRefresh)))
        }
    }

    private func timelineEntries(for payload: UpcomingGamesWidgetPayload, from referenceDate: Date) -> [UpcomingGamesEntry] {
        timelineRefreshDates(for: payload, from: referenceDate).map {
            UpcomingGamesEntry(date: $0, payload: payload.upcoming(at: $0))
        }
    }

    private func timelineRefreshDates(for payload: UpcomingGamesWidgetPayload, from referenceDate: Date) -> [Date] {
        let games = payload.upcoming(at: referenceDate).games
        // Essential transitions must survive the countdown entry budget, including offline expiry.
        var dates: Set<Date> = [referenceDate]
        for game in games {
            guard let startsAt = game.startsAt, let endsAt = game.endsAt else { continue }
            [startsAt.addingTimeInterval(-2 * 60 * 60),
             startsAt.addingTimeInterval(-countdownLeadTime), startsAt,
             startsAt.addingTimeInterval(10 * 60), endsAt]
                .filter { $0 > referenceDate && $0 <= endsAt }
                .forEach { dates.insert($0) }
            // Only these midnights can change this event's date label to Tomorrow or Today.
            let dayStart = Calendar.current.startOfDay(for: startsAt)
            [Calendar.current.date(byAdding: .day, value: -1, to: dayStart), dayStart,
             Calendar.current.date(byAdding: .day, value: 1, to: dayStart)]
                .compactMap { $0 }
                .filter { $0 > referenceDate && $0 < endsAt }
                .forEach { dates.insert($0) }
        }

        var countdownDates = Set<Date>()
        for game in games {
            guard let startsAt = game.startsAt, referenceDate < startsAt else { continue }
            var date = max(referenceDate, startsAt.addingTimeInterval(-countdownLeadTime)).roundedUpToWidgetMinute()
            while date < startsAt {
                if !dates.contains(date) { countdownDates.insert(date) }
                date = date.addingTimeInterval(countdownTimelineCadence)
            }
        }
        dates.formUnion(countdownDates.sorted().prefix(max(0, maximumTimelineEntryCount - dates.count)))
        return dates.sorted()
    }

    private func nextRefreshDate(for payload: UpcomingGamesWidgetPayload, from referenceDate: Date) -> Date {
        let fallback = referenceDate.addingTimeInterval(15 * 60)
        let nextTransition = payload.upcoming(at: referenceDate).games
            .flatMap { [$0.startsAt, $0.endsAt].compactMap { $0 } }
            .filter { $0 > referenceDate }
            .min()
        return min(fallback, nextTransition ?? fallback)
    }

    private func loadPayload() -> UpcomingGamesWidgetPayload {
        guard
            let baseURL = widgetAPIBaseURL,
            SecureSessionStore(baseURL: baseURL).read() != nil,
            UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: currentUserIdKey) != nil,
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
            let baseURL = widgetAPIBaseURL,
            let token = SecureSessionStore(baseURL: baseURL).read(),
            let currentUserId = defaults.string(forKey: currentUserIdKey)
        else {
            return nil
        }

        do {
            let gameRequestsData = try await authenticatedData(
                path: "game-requests/my",
                baseURL: baseURL,
                token: token
            )
            let gameRequestsEnvelope = try JSONDecoder().decode(WidgetGameRequestsEnvelope.self, from: gameRequestsData)

            let personalActivitiesEnvelope: WidgetPersonalActivitiesEnvelope?
            if let personalActivitiesData = try? await authenticatedData(
                path: "personal-activities",
                baseURL: baseURL,
                token: token
            ) {
                personalActivitiesEnvelope = try? JSONDecoder().decode(WidgetPersonalActivitiesEnvelope.self, from: personalActivitiesData)
            } else {
                personalActivitiesEnvelope = nil
            }

            let referenceDate = Date()
            guard !Task.isCancelled,
                  SecureSessionStore(baseURL: baseURL).read() == token,
                  defaults.string(forKey: currentUserIdKey) == currentUserId else { return nil }
            let games = gameRequestsEnvelope.gameRequests.widgetGames(currentUserId: currentUserId)
            let personalActivities = personalActivitiesEnvelope?.personalActivities.widgetGames() ?? []
            let payload = UpcomingGamesWidgetPayload(
                updatedAt: referenceDate,
                games: games + personalActivities
            ).upcoming(at: referenceDate)
            if let encoded = try? JSONEncoder().encode(payload) {
                defaults.set(encoded, forKey: payloadKey)
            }
            return payload
        } catch {
            return nil
        }
    }

    private func authenticatedData(path: String, baseURL: URL, token: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration, delegate: WidgetAuthenticatedSessionDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
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

private struct WidgetPersonalActivitiesEnvelope: Decodable {
    let personalActivities: [WidgetPersonalActivity]
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

private struct WidgetPersonalActivity: Decodable {
    let id: String
    let status: String
    let scheduledAt: String
    let durationMinutes: Int?
    let sport: String?
    let court: WidgetCourt?
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
        filter { !["cancelled", "canceled", "declined", "rejected", "withdrawn", "completed"].contains($0.status.lowercased()) && $0.outcome != "played" && $0.outcome != "not_played" }
            .map { request in
                UpcomingGamesWidgetGame(
                    id: request.id,
                    title: request.displayTitle(currentUserId: currentUserId),
                    sportTitle: request.sportTitle,
                    startsAt: request.proposedDate,
                    durationMinutes: UpcomingGamesWidgetSchedule.durationMinutes(request.durationMinutes, fallback: 90),
                    dateText: request.widgetDateText,
                    timeText: request.widgetTimeText,
                    courtName: request.proposedCourt?.name ?? request.venuePendingTitle,
                    courtAddress: request.proposedCourt?.address,
                    statusLabel: request.statusLabel,
                    eventType: "game"
                )
            }
    }
}

private extension Array where Element == WidgetPersonalActivity {
    func widgetGames() -> [UpcomingGamesWidgetGame] {
        filter { !["cancelled", "canceled", "completed"].contains($0.status.lowercased()) }
            .map { activity in
                UpcomingGamesWidgetGame(
                    id: activity.id,
                    title: "Личный визит",
                    sportTitle: activity.sportTitle,
                    startsAt: activity.scheduledDate,
                    durationMinutes: UpcomingGamesWidgetSchedule.durationMinutes(activity.durationMinutes, fallback: activity.defaultDurationMinutes),
                    dateText: activity.widgetDateText,
                    timeText: activity.widgetTimeText,
                    courtName: activity.court?.name ?? activity.venuePendingTitle,
                    courtAddress: activity.court?.address,
                    statusLabel: activity.statusLabel,
                    eventType: "personal"
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
        case "running": return "Бег"
        case "supboard": return "Сапборд"
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

private extension WidgetPersonalActivity {
    var scheduledDate: Date? {
        scheduledAt.parsedISODateValue()
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
        case "running": return "Бег"
        case "supboard": return "Сапборд"
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
        guard let date = scheduledDate else {
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
        guard let date = scheduledDate else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var statusLabel: String {
        switch status.lowercased() {
        case "completed":
            return "Визит завершён"
        case "canceled", "cancelled":
            return "Отменён"
        default:
            return hasEnded ? "Визит завершён" : "Визит запланирован"
        }
    }

    private var hasEnded: Bool {
        guard let scheduledDate else {
            return false
        }

        let duration = TimeInterval((durationMinutes ?? defaultDurationMinutes) * 60)
        return Date().timeIntervalSince(scheduledDate) >= duration
    }

    var defaultDurationMinutes: Int {
        switch sport {
        case "fitness", "boxing", "yoga", "badminton", "table_tennis", "squash", "running", "supboard":
            return 60
        case "football", "volleyball":
            return 90
        default:
            return 90
        }
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

private extension Date {
    func roundedUpToWidgetMinute() -> Date {
        let interval = ceil(timeIntervalSinceReferenceDate / countdownTimelineCadence) * countdownTimelineCadence
        return Date(timeIntervalSinceReferenceDate: interval)
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
                content(for: game, referenceDate: entry.date)
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

    private func content(for game: UpcomingGamesWidgetGame, referenceDate: Date) -> some View {
        if family == .systemSmall {
            return AnyView(compactContent(for: game, referenceDate: referenceDate))
        }

        return AnyView(regularContent(for: game, referenceDate: referenceDate))
    }

    private func compactContent(for game: UpcomingGamesWidgetGame, referenceDate: Date) -> some View {
        let statusStyle = game.statusStyle(referenceDate: referenceDate)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.green)
                    .frame(width: 16, height: 16)

                Text(game.isPersonalEvent ? "Визит" : "Игра")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                Text(game.compactStatusLabel(referenceDate: referenceDate))
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

    private func regularContent(for game: UpcomingGamesWidgetGame, referenceDate: Date) -> some View {
        let statusLabel = game.effectiveStatusLabel(referenceDate: referenceDate)
        let statusStyle = game.statusStyle(referenceDate: referenceDate)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.green)
                Text(game.isPersonalEvent ? "Ближайший визит" : "Ближайшая игра")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(statusLabel)
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
    var isPersonalEvent: Bool {
        eventType == "personal"
    }

    func effectiveStatusLabel(referenceDate: Date) -> String {
        guard let startsAt else {
            return statusLabel
        }

        if ["Отменена", "Отменён", "Игра прошла", "Не сыграли", "Визит завершён"].contains(statusLabel) {
            return statusLabel
        }

        let duration = TimeInterval((durationMinutes ?? 90) * 60)
        let secondsUntilStart = startsAt.timeIntervalSince(referenceDate)
        if secondsUntilStart > 0 {
            return secondsUntilStart <= 2 * 60 * 60 ? "Скоро начнется" : statusLabel
        }

        let secondsSinceStart = referenceDate.timeIntervalSince(startsAt)
        if secondsSinceStart <= 10 * 60 {
            return isPersonalEvent ? "Визит начался" : "Игра началась"
        }
        if secondsSinceStart < duration {
            return isPersonalEvent ? "Визит идет" : "Игра идет"
        }
        return isPersonalEvent ? "Визит завершён" : "Игра закончилась"
    }

    var compactVenueLine: String {
        let normalizedCourtName = courtName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCourtName.isEmpty else {
            return sportTitle
        }

        return "\(sportTitle) · \(normalizedCourtName)"
    }

    func compactStatusLabel(referenceDate: Date) -> String {
        let label = effectiveStatusLabel(referenceDate: referenceDate)
        switch label {
        case "Ждём подтверждение", "Ждёт подтверждения", "Требуется ответ", "Ожидает подтверждения":
            return "Ждём"
        case "Игра подтверждена":
            return "Подтв."
        case "Скоро начнется":
            return "Скоро"
        case "Игра началась", "Визит начался":
            return "Старт"
        case "Игра идет", "Визит идет":
            return "Идёт"
        case "Игра закончилась":
            return "Финиш"
        case "Игра прошла":
            return "Прошла"
        case "Визит запланирован":
            return "Визит"
        case "Визит завершён":
            return "Готово"
        default:
            return label
        }
    }

    func statusStyle(referenceDate: Date) -> WidgetStatusStyle {
        switch effectiveStatusLabel(referenceDate: referenceDate) {
        case "Ждём подтверждение", "Ждёт подтверждения", "Требуется ответ", "Ожидает подтверждения":
            return WidgetStatusStyle(
                foreground: Color(red: 0.49, green: 0.45, blue: 0.78),
                background: Color(red: 0.91, green: 0.90, blue: 0.99)
            )
        case "Игра подтверждена", "Игра прошла", "Визит запланирован":
            return WidgetStatusStyle(
                foreground: Color(red: 0.16, green: 0.58, blue: 0.33),
                background: Color(red: 0.86, green: 0.95, blue: 0.89)
            )
        case "Скоро начнется":
            return WidgetStatusStyle(
                foreground: Color(red: 0.78, green: 0.52, blue: 0.18),
                background: Color(red: 0.99, green: 0.94, blue: 0.83)
            )
        case "Игра началась", "Игра идет", "Визит начался", "Визит идет":
            return WidgetStatusStyle(
                foreground: Color(red: 0.17, green: 0.50, blue: 0.72),
                background: Color(red: 0.86, green: 0.93, blue: 0.98)
            )
        case "Игра закончилась", "Не сыграли", "Визит завершён":
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

struct UpcomingGamesWidget: Widget {
    let kind = "UpcomingGamesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingGamesProvider()) { entry in
            UpcomingGamesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(WidgetStrings.displayName)
        .description(WidgetStrings.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UpcomingGameLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UpcomingGameLiveActivityAttributes.self) { context in
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                UpcomingGameLiveActivityLockScreenView(context: context, referenceDate: timeline.date)
                    .activityBackgroundTint(Color.black.opacity(0.92))
                    .activitySystemActionForegroundColor(.white)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.state.liveStatusLabel(referenceDate: timeline.date))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(context.state.liveActivityAccent(referenceDate: timeline.date))
                            Text(context.state.sportTitle)
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(context.state.livePhaseTitle(referenceDate: timeline.date))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.58))
                            liveCountdown(for: context.state, referenceDate: timeline.date)
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.title) · \(context.state.courtName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.liveActivitySportSymbol)
                    .foregroundStyle(context.state.liveActivityAccent(referenceDate: Date()))
            } compactTrailing: {
                liveCountdown(for: context.state, referenceDate: Date())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(maxWidth: 42)
            } minimal: {
                Image(systemName: context.state.liveActivitySportSymbol)
                    .foregroundStyle(context.state.liveActivityAccent(referenceDate: Date()))
            }
            .widgetURL(URL(string: "sportsearch://upcoming"))
        }
    }

    @ViewBuilder
    private func liveCountdown(for state: UpcomingGameLiveActivityAttributes.ContentState, referenceDate: Date) -> some View {
        if state.startsAt > referenceDate {
            Text(timerInterval: referenceDate ... state.startsAt, countsDown: true)
        } else if referenceDate < state.endsAt {
            Text("Идёт")
        } else {
            Text("Финиш")
        }
    }
}

private struct UpcomingGameLiveActivityLockScreenView: View {
    let context: ActivityViewContext<UpcomingGameLiveActivityAttributes>
    let referenceDate: Date

    private var state: UpcomingGameLiveActivityAttributes.ContentState {
        context.state
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(state.liveStatusLabel(referenceDate: referenceDate))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(state.liveActivityAccent(referenceDate: referenceDate))
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.livePhaseTitle(referenceDate: referenceDate))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)

                    liveCountdown
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Text("\(state.sportTitle) · \(state.courtName)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let address = state.courtAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                    Text(address)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 10)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 74, height: 74)

                Circle()
                    .trim(
                        from: 0.12 + 0.80 * (1 - state.preStartProgress(referenceDate: referenceDate)),
                        to: 0.92
                    )
                    .stroke(
                        state.liveActivityAccent(referenceDate: referenceDate),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 56, height: 56)

                Image(systemName: state.liveActivitySportSymbol)
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(state.liveActivityAccent(referenceDate: referenceDate))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.09).opacity(0.96))
        )
    }

    @ViewBuilder
    private var liveCountdown: some View {
        if state.startsAt > referenceDate {
            Text(timerInterval: referenceDate ... state.startsAt, countsDown: true)
        } else if referenceDate < state.endsAt {
            Text("Идёт")
        } else {
            Text("Финиш")
        }
    }
}

private extension UpcomingGameLiveActivityAttributes.ContentState {
    func liveStatusLabel(referenceDate: Date) -> String {
        if ["Отменена", "Игра прошла", "Не сыграли"].contains(statusLabel) {
            return statusLabel
        }

        if referenceDate < startsAt {
            return statusLabel
        }

        let secondsSinceStart = referenceDate.timeIntervalSince(startsAt)
        if secondsSinceStart <= 10 * 60 {
            return "Игра началась"
        }
        if referenceDate < endsAt {
            return "Игра идет"
        }
        return "Игра закончилась"
    }

    func livePhaseTitle(referenceDate: Date) -> String {
        if referenceDate < startsAt {
            return "До игры"
        }
        if referenceDate < endsAt {
            return "Игра идет"
        }
        return "Игра закончилась"
    }

    func preStartProgress(referenceDate: Date) -> Double {
        let secondsUntilStart = startsAt.timeIntervalSince(referenceDate)
        guard secondsUntilStart > 0 else {
            return 0
        }

        return min(max(secondsUntilStart / (60 * 60), 0), 1)
    }

    func liveActivityAccent(referenceDate: Date) -> Color {
        switch liveStatusLabel(referenceDate: referenceDate) {
        case "Ждём подтверждение", "Ждёт подтверждения", "Требуется ответ", "Ожидает подтверждения":
            return Color(red: 1.0, green: 0.73, blue: 0.26)
        case "Отменена":
            return Color(red: 1.0, green: 0.31, blue: 0.35)
        case "Игра началась", "Игра идет":
            return Color(red: 0.39, green: 0.78, blue: 1.0)
        default:
            return Color(red: 0.18, green: 0.85, blue: 0.47)
        }
    }

    var liveActivitySportSymbol: String {
        switch sportTitle.lowercased() {
        case let value where value.contains("падел"):
            return "tennis.racket"
        case let value where value.contains("футбол"):
            return "soccerball"
        case let value where value.contains("волейбол"):
            return "volleyball.fill"
        case let value where value.contains("баскет"):
            return "basketball.fill"
        case let value where value.contains("фитнес"):
            return "dumbbell.fill"
        default:
            return "figure.tennis"
        }
    }
}

@main
struct SportSearchWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingGamesWidget()
        UpcomingGameLiveActivityWidget()
    }
}


private enum WidgetStrings {
    private static var isRussian: Bool {
        Locale.current.language.languageCode?.identifier == "ru"
    }

    static var displayName: String {
        isRussian ? "Ближайшие игры" : "Upcoming games"
    }

    static var description: String {
        isRussian
            ? "Показывает следующую подтверждённую игру."
            : "Shows your next confirmed game."
    }
}

private final class WidgetAuthenticatedSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let source = response.url, let destination = request.url,
              SecureSessionStore.origin(for: source) == SecureSessionStore.origin(for: destination) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
