import Foundation

@main
struct SportHomeWeekTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    static func record(
        _ id: String, at timestamp: String? = "2026-09-22T10:00:00+03:00",
        kind: SportHomeRecord.Kind = .activity, owner: String? = "A", participants: [String] = [],
        status: String = "completed", outcome: String? = nil, root: String? = nil,
        duration: Int? = 60
    ) -> SportHomeRecord {
        SportHomeRecord(
            id: id, rootRequestID: root, kind: kind, ownerID: owner, participantIDs: participants,
            date: timestamp.map(date), status: status, outcome: outcome, durationMinutes: duration,
            title: id, location: nil
        )
    }

    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        calendar.firstWeekday = 1
        let now = date("2026-09-23T12:00:00+03:00")
        func project(_ records: [SportHomeRecord], user: String = "A") -> SportHomeWeek {
            SportHomeWeek.make(records: records, currentUserID: user, now: now, calendar: calendar)
        }

        let empty = project([])
        expect(empty.completed.isEmpty && empty.nearestPlan == nil && empty.needsReview == nil,
               "An empty account has no fabricated activity or suggested plan")
        expect(empty.days.count == 7, "An empty week still supplies all seven calendar days")
        expect(empty.days.allSatisfy { $0.completedCount == 0 && $0.plannedCount == 0 },
               "An empty week does not fabricate progress")
        expect(empty.interval.start == date("2026-09-21T00:00:00+03:00"),
               "The sports week starts on local Monday even with a Sunday-first calendar")
        expect(empty.interval.end == date("2026-09-28T00:00:00+03:00"),
               "The week ends at the next local Monday")
        expect(calendar.firstWeekday == 1, "Projecting the week does not mutate the caller's calendar")

        let ownVisit = record("visit-without-photo")
        let visits = project([
            ownVisit,
            record("past-plan", status: "planned"),
            record("cancelled", status: "cancelled"),
            record("canceled", status: "canceled"),
            record("unknown", status: "unknown"),
            record("future-completed", at: "2026-09-24T12:00:00+03:00"),
            record("without-date", at: nil),
            record("foreign-visit", owner: "B", participants: ["A"])
        ])
        expect(visits.completed.map(\.sourceID) == ["visit-without-photo"],
               "Only the owner's completed past visit enters history; photos are not a prerequisite")
        expect(visits.needsReview?.sourceID == "past-plan", "An elapsed plan asks for a result")
        expect(visits.nearestPlan == nil, "Ended and canceled visits cannot be offered as the next plan")
        expect(visits.days.reduce(0) { $0 + $1.completedCount } == 1,
               "An elapsed unconfirmed plan cannot increase the weekly completion count")
        expect(project([ownVisit], user: "").completed.isEmpty, "A missing account never receives personal history")
        expect(project([ownVisit], user: "B").completed.isEmpty, "Account switching cannot reuse another owner's visits")

        let nowISO = "2026-09-23T12:00:00+03:00"
        let plans = project([
            record("ongoing", at: "2026-09-23T11:30:00+03:00", status: "planned", duration: 60),
            record("ended-exactly", at: "2026-09-23T11:00:00+03:00", status: "planned", duration: 60),
            record("later", at: "2026-09-24T10:00:00+03:00", status: "planned")
        ])
        expect(plans.nearestPlan?.sourceID == "ongoing" && plans.nearestPlan?.state == .planned,
               "An ongoing visit remains a plan until its duration has elapsed")
        expect(plans.needsReview?.sourceID == "ended-exactly", "At its exact end a plan needs confirmation")
        expect(plans.completed.isEmpty, "Neither reaching the start nor the end proves attendance")
        expect(plans.days[2].plannedCount == 1 && plans.days[3].plannedCount == 1,
               "Calendar dots distinguish plans from completed activities")

        let gameRecords = [
            record("played-owner", kind: .game, status: "accepted", outcome: "played"),
            record("played-participant", kind: .game, owner: "B", participants: ["A"], status: "approved", outcome: "played"),
            record("foreign-game", kind: .game, owner: "B", participants: ["C"], status: "accepted", outcome: "played"),
            record("not-played", kind: .game, status: "accepted", outcome: "not_played"),
            record("declined", kind: .game, status: "declined", outcome: "played"),
            record("cancelled-game", kind: .game, status: "cancelled", outcome: "played"),
            record("pending-with-result", kind: .game, status: "pending", outcome: "played"),
            record("unknown-outcome", kind: .game, status: "accepted", outcome: "disputed")
        ]
        let games = project(gameRecords)
        expect(Set(games.completed.map(\.sourceID)) == ["played-owner", "played-participant"],
               "Completed games require accepted participation and a played result")
        expect(games.nearestPlan == nil && games.needsReview == nil,
               "Terminal or disputed results do not become new plans or review prompts")
        let pending = project([
            record("pending-past", kind: .game, status: "pending"),
            record("pending-now", at: nowISO, kind: .game, status: "pending"),
            record("future-accepted", at: "2026-09-24T12:00:00+03:00", kind: .game, status: "accepted"),
            record("past-accepted", kind: .game, status: "accepted")
        ])
        expect(pending.nearestPlan?.sourceID == "pending-now" && pending.nearestPlan?.state == .pending,
               "An invitation remains pending rather than becoming confirmed automatically")
        expect(pending.needsReview?.sourceID == "past-accepted", "An accepted ended game without outcome needs review")
        expect(pending.completed.isEmpty, "Acceptance and elapsed time alone do not count as a played game")
        expect(pending.days.reduce(0) { $0 + $1.plannedCount } == 2,
               "Expired unanswered invitations are absent from planned calendar counts")

        let duplicateRows = [
            record("group", kind: .game, status: "accepted", outcome: "played"),
            record("copy-B", kind: .game, status: "accepted", outcome: "played", root: "group"),
            record("copy-C", kind: .game, status: "accepted", outcome: "played", root: "group"),
            ownVisit, ownVisit
        ]
        let deduplicated = project(duplicateRows)
        expect(deduplicated.completed.count == 2, "One group game and one visit count once despite duplicate transport rows")
        expect(deduplicated.completed.first { $0.kind == .game }?.sourceID == "group",
               "The canonical group record supplies the action target when available")
        expect(project(Array(duplicateRows.reversed())).completed.first { $0.kind == .game }?.sourceID == "group",
               "Reordering a response cannot change the group action target")
        expect(project([
            record("group", kind: .game, status: "canceled"),
            record("copy", kind: .game, status: "accepted", outcome: "played", root: "group")
        ]).completed.isEmpty, "A canceled canonical event cannot be revived by a stale transport copy")
        expect(project([
            record("same-id", kind: .game, status: "accepted", outcome: "played"),
            record("same-id")
        ]).completed.count == 2, "Unrelated visit/game identifiers use separate namespaces")

        let boundary = project([
            record("before-week", at: "2026-09-20T23:59:59+03:00"),
            record("week-start", at: "2026-09-21T00:00:00+03:00"),
            record("current-week", at: "2026-09-22T23:59:59+03:00"),
            record("next-week-plan", at: "2026-09-28T00:00:00+03:00", status: "planned")
        ])
        expect(boundary.completed.map(\.sourceID) == ["current-week", "week-start"],
               "History includes the exact local start and excludes the preceding second")
        expect(boundary.days[0].completedCount == 1 && boundary.days[1].completedCount == 1,
               "Completion dots use the user's local date rather than the UTC date")
        expect(boundary.days.reduce(0) { $0 + $1.plannedCount } == 0,
               "Next Monday is outside this week's day counts")
        expect(boundary.nearestPlan?.sourceID == "next-week-plan", "The next real plan can be beyond this week")
        let many = project((1...9).map { record("visit-\($0)") })
        expect(many.completed.count == 9 && many.days.reduce(0) { $0 + $1.completedCount } == 9,
               "Weekly totals do not inherit a six-card profile presentation limit")

        let wholeDay = project([
            record("completed"),
            record("review", status: "planned"),
            record("canceled", status: "canceled"),
            record("not-played", kind: .game, status: "accepted", outcome: "not_played"),
            record("foreign-canceled", owner: "B", status: "canceled"),
            record("tomorrow-plan", at: "2026-09-24T10:00:00+03:00", status: "planned")
        ])
        let selectedDay = wholeDay.events(on: date("2026-09-22T23:00:00+03:00"), calendar: calendar)
        expect(selectedDay.count == 4 && Set(selectedDay.map(\.state)) == [.completed, .needsReview, .canceled, .notPlayed],
               "Selecting a day includes its results, unmarked visits and cancellations but no other account or date")
        expect(wholeDay.days[1].completedCount == 1 && wholeDay.days[1].reviewCount == 1 && wholeDay.days[1].otherCount == 2,
               "Pending marks and cancellations have their own counts without inflating workouts")
        expect(wholeDay.events(on: date("2026-09-24T00:00:00+03:00"), calendar: calendar).first?.state == .planned,
               "A future day with a plan opens a real event rather than an empty completed-only list")
        expect(selectedDay.map(\.id) == selectedDay.map(\.id).sorted(), "Tied event times sort by canonical ID")
        let canceledRoot = project([record("root-cancel", kind: .game, status: "canceled"),
                                    record("stale-copy", kind: .game, status: "accepted", outcome: "played", root: "root-cancel")])
        expect(canceledRoot.events.count == 1 && canceledRoot.events[0].state == .canceled,
               "The day uses canonical cancellation instead of a stale played child")
        expect(boundary.events.allSatisfy { $0.date >= boundary.interval.start && $0.date < boundary.interval.end },
               "Daily event collection obeys exclusive local week boundaries")

        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstWeek = SportHomeWeek.make(records: [], currentUserID: "A",
            now: date("2026-03-08T12:00:00-04:00"), calendar: dstCalendar)
        expect(dstWeek.interval.start == date("2026-03-02T00:00:00-05:00") &&
               dstWeek.interval.end == date("2026-03-09T00:00:00-04:00"),
               "A daylight-saving week follows local boundaries rather than fixed seven-day seconds")
        expect(dstWeek.days.count == 7 && dstCalendar.component(.hour, from: dstWeek.days.last!.date) == 0,
               "Daylight-saving transitions retain seven midnight-based day cells")
        print("Sport home week: \(checks) checks passed")
    }
}
