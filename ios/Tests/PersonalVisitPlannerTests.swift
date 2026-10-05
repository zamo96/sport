import Foundation

@main
struct PersonalVisitPlannerTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let now = date("2026-10-01T07:40:00+03:00")
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Hours
        expect(ClubHours.parse("07:00-23:00") == ClubHours(open: 420, close: 1380), "Plain hours parse")
        expect(ClubHours.parse("Открыто 6.30 – 23.30") == ClubHours(open: 390, close: 1410), "Dots and dashes parse")
        expect(ClubHours.parse("08:00-00:00") == ClubHours(open: 480, close: 1440), "Midnight closes the day at 24:00")
        expect(ClubHours.parse("10:00-02:00")?.close == 1440, "Hours past midnight stay within the day")
        expect(ClubHours.parse("Круглосуточно") == ClubHours(open: 0, close: 1440), "Round the clock")
        expect(ClubHours.parse("часы работы") == nil && ClubHours.parse(nil) == nil, "Unreadable hours are unknown, not invented")
        expect(ClubHours.parse("25:00-26:00") == nil, "Impossible hours are rejected")
        expect(ClubHours(open: 480, close: 1440).label == "08:00–00:00", "Label writes midnight as 00:00")

        // Slots
        let hours = ClubHours(open: 420, close: 1380)
        let morningToday = PersonalVisitPlanner.startMinutes(on: today, part: .morning, hours: hours, durationMinutes: 90, now: now, calendar: calendar)
        expect(morningToday.first == 480, "Today's morning starts after the current time, not at a past slot")
        expect(!morningToday.contains(420) && !morningToday.contains(450), "Past slots are not offered")
        let morningTomorrow = PersonalVisitPlanner.startMinutes(on: tomorrow, part: .morning, hours: hours, durationMinutes: 90, now: now, calendar: calendar)
        expect(morningTomorrow.first == 420 && morningTomorrow.last == 690, "Morning follows the club's opening, not a fixed 09:00")
        let evening = PersonalVisitPlanner.startMinutes(on: tomorrow, part: .evening, hours: hours, durationMinutes: 90, now: now, calendar: calendar)
        expect(evening.last == 1290, "The last start still ends by closing time (21:30 + 1.5 h = 23:00)")
        let longEvening = PersonalVisitPlanner.startMinutes(on: tomorrow, part: .evening, hours: hours, durationMinutes: 120, now: now, calendar: calendar)
        expect(longEvening.last == 1260, "A longer visit starts earlier")
        let unknown = PersonalVisitPlanner.allStartMinutes(on: tomorrow, hours: nil, durationMinutes: 120, now: now, calendar: calendar)
        expect(unknown.first == 360 && unknown.last == 1380, "Unknown hours offer 06:00–23:00 starts")
        let odd = PersonalVisitPlanner.allStartMinutes(on: tomorrow, hours: ClubHours(open: 415, close: 1380), durationMinutes: 60, now: now, calendar: calendar)
        expect(odd.first == 420, "Starts snap to the half hour after opening")
        expect(PersonalVisitPlanner.allStartMinutes(on: yesterday, hours: hours, durationMinutes: 60, now: now, calendar: calendar).isEmpty,
               "A past day has no slots")
        let late = date("2026-10-01T22:10:00+03:00")
        expect(PersonalVisitPlanner.allStartMinutes(on: today, hours: hours, durationMinutes: 60, now: late, calendar: calendar).isEmpty,
               "Late in the evening today has nothing left")
        let exact = date("2026-10-01T08:00:30+03:00")
        expect(PersonalVisitPlanner.allStartMinutes(on: today, hours: hours, durationMinutes: 60, now: exact, calendar: calendar).first == 510,
               "A slot that started half a minute ago is already past")

        // Defaults
        let fallback = PersonalVisitPlanner.defaultStart(hours: hours, durationMinutes: 90, now: now, calendar: calendar)
        expect(fallback?.day == tomorrow && fallback?.minute == 540, "A new plan starts tomorrow at 09:00")
        let lateClub = PersonalVisitPlanner.defaultStart(hours: ClubHours(open: 600, close: 1320), durationMinutes: 90, now: now, calendar: calendar)
        expect(lateClub?.minute == 600, "A club opening at 10:00 starts the plan at 10:00")
        let eveningClub = PersonalVisitPlanner.defaultStart(hours: ClubHours(open: 360, close: 600), durationMinutes: 90, now: now, calendar: calendar)
        expect(eveningClub?.minute == 360, "A club closing before 09:00 + duration falls back to its first slot")
        expect(PersonalVisitPlanner.quickDays(from: now, calendar: calendar) == [0, 1, 2, 3].map { calendar.date(byAdding: .day, value: $0, to: today)! },
               "Quick days are today and the next three")
        expect(PersonalVisitPlanner.durationOptions(including: 75) == [45, 60, 75, 90, 120], "An edited visit keeps its own duration")
        expect(PersonalVisitPlanner.durationOptions(including: 90) == [45, 60, 90, 120], "A preset duration is not duplicated")
        expect(PersonalVisitPlanner.durationLabel(90, russian: true) == "1,5 ч" && PersonalVisitPlanner.durationLabel(45, russian: true) == "45 мин"
               && PersonalVisitPlanner.durationLabel(120, russian: true) == "2 ч" && PersonalVisitPlanner.durationLabel(75, russian: true) == "75 мин",
               "Durations read naturally")
        expect(VisitDayPart.containing(minute: 11 * 60 + 30) == .morning && VisitDayPart.containing(minute: 12 * 60) == .afternoon
               && VisitDayPart.containing(minute: 17 * 60) == .evening, "Day parts split at 12:00 and 17:00")

        // Timeline
        func visit(_ id: String, _ start: String, _ duration: Int = 60, _ status: String = "planned") -> PersonalVisitMoment {
            PersonalVisitMoment(id: id, start: date(start), durationMinutes: duration, status: status)
        }
        let visits = [
            visit("later", "2026-10-03T18:00:00+03:00"),
            visit("done", "2026-09-29T10:00:00+03:00", 60, "completed"),
            visit("waiting-old", "2026-09-28T19:00:00+03:00"),
            visit("today", "2026-10-01T09:00:00+03:00", 90),
            visit("canceled", "2026-10-02T10:00:00+03:00", 60, "canceled"),
            visit("waiting-new", "2026-09-30T19:00:00+03:00"),
            visit("running", "2026-10-01T07:00:00+03:00", 60)
        ]
        expect(PersonalVisitTimeline.upcomingOrder(visits, now: now) == ["waiting-new", "waiting-old", "running", "today", "later"],
               "Marked and canceled visits leave Upcoming; waiting ones come first, newest first")
        expect(PersonalVisitTimeline.phase(of: visits[3], now: now, calendar: calendar) == .today, "Later today")
        expect(PersonalVisitTimeline.phase(of: visits[6], now: now, calendar: calendar) == .inProgress, "Started, not ended")
        expect(PersonalVisitTimeline.phase(of: visits[5], now: now, calendar: calendar) == .needsMark, "Ended plan waits for a mark")
        expect(PersonalVisitTimeline.phase(of: visits[0], now: now, calendar: calendar) == .later, "Another day")
        expect(PersonalVisitTimeline.phase(of: visit("x", "2026-10-01T10:00:00+03:00", 60, "cancelled"), now: now) == .canceled,
               "Both cancel spellings")
        expect(PersonalVisitTimeline.countdown(to: date("2026-10-01T09:00:00+03:00"), now: now, russian: true) == "через 1 ч 20 мин", "Countdown")
        expect(PersonalVisitTimeline.countdown(to: date("2026-10-01T07:45:00+03:00"), now: now, russian: true) == "через 5 мин", "Minutes only")
        expect(PersonalVisitTimeline.countdown(to: date("2026-10-01T09:40:00+03:00"), now: now, russian: true) == "через 2 ч", "Whole hours")

        // Plural
        let forms = [1, 2, 5, 11, 12, 21, 22, 25, 111].map { RussianPlural.form($0, one: "визит", few: "визита", many: "визитов") }
        expect(forms == ["визит", "визита", "визитов", "визитов", "визитов", "визит", "визита", "визитов", "визитов"], "Russian plural forms")

        print("Personal visit planner tests: \(checks) checks passed")
    }
}
