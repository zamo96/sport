import Foundation

@main
@MainActor
struct UpcomingGamesWidgetTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard value() else { fatalError(message) }
    }

    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_789_300_017.375)
#if STORE_TESTS
        let tennis = Sport(title: "Теннис", defaultDurationMinutes: 90)
        let yoga = Sport(title: "Йога", defaultDurationMinutes: 60)
        func visit(_ id: String, _ start: Date, sport: Sport = tennis, status: String = "planned") -> PersonalActivity {
            PersonalActivity(id: id, userId: "user", courtId: "court", sport: sport,
                scheduledAt: ISO8601DateFormatter().string(from: start), durationMinutes: nil,
                comment: nil, status: status, reportComment: nil, createdAt: nil,
                updatedAt: nil, court: nil, photos: [])
        }
        let oldVisit = visit("old-visit", now.addingTimeInterval(-7 * 86400))
        expect(!oldVisit.isArchivedForTimeline, "Fixture must retain a past personal visit in actual app history")
        let oldGame = MatchGameRequest(id: "old-game", proposedDate: now.addingTimeInterval(-86400), durationMinutes: nil, status: "accepted", outcome: nil, sport: tennis)
        let nextGame = MatchGameRequest(id: "next-game", proposedDate: now.addingTimeInterval(3600), durationMinutes: nil, status: "accepted", outcome: nil, sport: tennis)
        let payload = UpcomingGamesWidgetStore.makePayload(gameRequests: [oldGame, nextGame], personalActivities: [oldVisit, visit("old-visit2", now.addingTimeInterval(-6 * 86400)), visit("old-visit3", now.addingTimeInterval(-5 * 86400))], currentUserId: "user", referenceDate: now)
        expect(payload.games.map(\.id) == ["next-game"], "History rows must not mask the next game")
        let empty = UpcomingGamesWidgetStore.makePayload(gameRequests: [oldGame], personalActivities: [oldVisit], currentUserId: nil, referenceDate: now)
        expect(empty.games.isEmpty, "Both user-reported events past must leave an empty widget")
        let visits = [visit("yoga-old", now.addingTimeInterval(-3700), sport: yoga), visit("completed", now.addingTimeInterval(3600), status: "completed"), visit("cancelled", now.addingTimeInterval(3600), status: "cancelled"), visit("next", now.addingTimeInterval(3600), sport: yoga)]
        let filtered = UpcomingGamesWidgetStore.makePayload(gameRequests: [], personalActivities: visits, currentUserId: nil, referenceDate: now)
        expect(filtered.games.map(\.id) == ["next"], "Personal defaults and terminal statuses must be filtered before cap")
        expect(filtered.games.first?.durationMinutes == 60, "Store persists resolved sport duration for the extension")
        expect(!oldVisit.isArchivedForTimeline, "Widget projection must leave app history unchanged")
        let defaults = UserDefaults(suiteName: UpcomingGamesWidgetStore.appGroupIdentifier)!
        defer { defaults.removePersistentDomain(forName: UpcomingGamesWidgetStore.appGroupIdentifier) }
        let liveGame = MatchGameRequest(id: "private-game", proposedDate: Date().addingTimeInterval(3600), durationMinutes: 90, status: "accepted", outcome: nil, sport: tennis)
        UpcomingGamesWidgetStore.setCurrentAccount("A")
        UpcomingGamesWidgetStore.save(gameRequests: [liveGame], currentUserId: "A")
        func storedGames() -> [UpcomingGamesWidgetGame] {
            let data = defaults.data(forKey: UpcomingGamesWidgetStore.payloadKey)!
            return try! JSONDecoder().decode(UpcomingGamesWidgetPayload.self, from: data).games
        }
        expect(storedGames().count == 1, "An authenticated account can publish its widget")
        UpcomingGamesWidgetStore.clear()
        expect(storedGames().isEmpty && defaults.string(forKey: UpcomingGamesWidgetStore.currentUserIdKey) == nil, "Logout clears payload and account identifier synchronously")
        UpcomingGamesWidgetStore.save(gameRequests: [liveGame], currentUserId: "A")
        expect(storedGames().isEmpty, "A delayed logged-out view cannot republish a widget")
        UpcomingGamesWidgetStore.setCurrentAccount("B")
        UpcomingGamesWidgetStore.save(gameRequests: [liveGame], currentUserId: "A")
        expect(storedGames().isEmpty, "The previous account cannot publish into the next account's widget")
        UpcomingGamesWidgetStore.save(gameRequests: [liveGame], currentUserId: "B")
        expect(storedGames().count == 1 && defaults.string(forKey: UpcomingGamesWidgetStore.currentUserIdKey) == "B", "The next account can publish its own widget")
        print("Upcoming widget app-store tests: \(checks) checks passed")
#else
        func game(_ id: String, _ start: Date?, duration: Int? = 90, sport: String = "Теннис", type: String = "game", status: String = "Игра подтверждена") -> UpcomingGamesWidgetGame {
            UpcomingGamesWidgetGame(id: id, title: id, sportTitle: sport, startsAt: start, durationMinutes: duration, dateText: "Устаревшая дата", timeText: "00:00", courtName: "Корт", courtAddress: nil, statusLabel: status, eventType: type)
        }
        func payload(_ games: [UpcomingGamesWidgetGame]) -> UpcomingGamesWidgetPayload {
            UpcomingGamesWidgetPayload(updatedAt: now.addingTimeInterval(-7 * 86400), games: games)
        }
        let old = game("old-visit", now.addingTimeInterval(-7 * 86400), type: "personal")
        let later = game("next-game", now.addingTimeInterval(3600))
        let source = payload([old, later])
        expect(source.upcoming(at: now).games.map(\.id) == ["next-game"], "Stale personal cache cannot mask a later game")
        let provider = UpcomingGamesProvider()
        let entries = provider.timelineEntries(for: source, from: now)
        expect(entries.first?.payload.games.first?.id == "next-game", "Offline initial entry filters stale cache")
        let end = later.endsAt!
        expect(source.upcoming(at: end.addingTimeInterval(-0.001)).games.count == 1, "Keep ongoing event until exact end")
        expect(source.upcoming(at: end).games.isEmpty, "Expire at exact end including fractional seconds")
        expect(entries.contains { $0.date == end && $0.payload.games.isEmpty }, "Schedule empty entry at exact expiry")
        expect(provider.timelineEntries(for: payload([old]), from: now).first?.payload.games.isEmpty == true, "All past means empty")
        let after = game("after", end.addingTimeInterval(86400))
        let rollover = provider.timelineEntries(for: payload([later, after]), from: now)
        expect(rollover.first { $0.date == end }?.payload.games.first?.id == "after", "Next cached game replaces ended game without networking")
        let malformed = payload([game("undated", nil), old, old, old, later, game("cancelled", now, status: "Отменена")])
        expect(malformed.upcoming(at: now).games.map(\.id) == ["next-game"], "Filter old/undated/terminal entries before prefix")
        for sport in ["Фитнес", "Бокс", "Йога", "Бадминтон", "Настольный теннис", "Сквош", "Бег", "Сапборд"] {
            let personal = game(sport, now.addingTimeInterval(-3600), duration: nil, sport: sport, type: "personal")
            expect(payload([personal]).upcoming(at: now).games.isEmpty, "Legacy personal \(sport) must use60min")
        }
        expect(!payload([game("tennis", now.addingTimeInterval(-3600), duration: nil, type: "personal")]).upcoming(at: now).games.isEmpty, "Tennis personal defaults90")
        for invalid in [0, -10, Int.max] {
            let item = game("invalid", now.addingTimeInterval(-90 * 60), duration: invalid)
            expect(payload([item]).upcoming(at: now).games.isEmpty, "Invalid duration falls back safely without overflow")
        }
        let distant = (1...3).map { game("future\($0)", now.addingTimeInterval(Double($0) * 100 * 86400)) }
        let capped = provider.timelineEntries(for: payload(distant), from: now)
        expect(capped.count <= 90, "Countdown timeline cap remains bounded")
        for item in distant {
            expect(capped.contains { $0.date == item.endsAt && !$0.payload.games.contains { $0.id == item.id } }, "Expiry must survive countdown cap")
        }
        expect(provider.nextRefreshDate(for: payload(distant), from: now) <= now.addingTimeInterval(900), "Far-future entries cannot postpone remote refresh")
        expect(provider.nextRefreshDate(for: payload([]), from: now) == now.addingTimeInterval(900), "Empty cache refreshes15minutes from now")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let midnight = Calendar.current.startOfDay(for: tomorrow)
        let tomorrowGame = game("tomorrow", midnight.addingTimeInterval(12 * 3600))
        let dayEntries = provider.timelineEntries(for: payload([tomorrowGame]), from: now)
        expect(dayEntries.first?.payload.games.first?.dateText == "Завтра", "Date label refreshed relative to initial entry")
        expect(dayEntries.first { $0.date == midnight }?.payload.games.first?.dateText == "Сегодня", "Midnight updates date text offline")
        let overnight = game("overnight", midnight.addingTimeInterval(-30 * 60), duration: 120)
        let overnightEntries = provider.timelineEntries(for: payload([overnight]), from: midnight.addingTimeInterval(-20 * 60))
        expect(overnightEntries.first { $0.date == midnight }?.payload.games.first?.dateText != "Сегодня", "Ongoing overnight event stops claiming Today after midnight")
        expect(overnightEntries.first { $0.date == midnight }?.payload.games.first?.id == "overnight", "Overnight event remains visible until its end")
        let countdown = game("countdown", now.addingTimeInterval(1800))
        expect(provider.nextRefreshDate(for: payload([countdown]), from: now) == now.addingTimeInterval(900), "Local countdown ticks do not cause minute-by-minute networking")
        // No token means remote loading is disabled and the same cached projection is used.
        // Use an isolated process-level defaults suite, never real app-group defaults in this harness.
        let disabledRemote = await provider.loadRemotePayload()
        expect(disabledRemote == nil, "Disabled remote loading returns cache fallback signal")
        let fallback = source.upcoming(at: now)
        expect(fallback.games.map(\.id) == ["next-game"], "Disabled network fallback still drops expired cache")
        let json = """
        {"gameRequests":[{"id":"old","status":"accepted","proposedDatetime":"2000-01-01T00:00:00Z"},{"id":"old2","status":"accepted","proposedDatetime":"2000-01-02T00:00:00Z"},{"id":"old3","status":"accepted","proposedDatetime":"2000-01-03T00:00:00Z"},{"id":"later","status":"accepted","proposedDatetime":"2099-01-01T00:00:00Z"}]}
        """
        let remote = try JSONDecoder().decode(WidgetGameRequestsEnvelope.self, from: Data(json.utf8))
        expect(payload(remote.gameRequests.widgetGames(currentUserId: nil)).upcoming(at: now).games.map(\.id) == ["later"], "Remote mapping also filters before cap")
        print("Upcoming widget extension tests: \(checks) checks passed")
#endif
    }
}
