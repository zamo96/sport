import Foundation

// Minimal transport fixtures; the production projection itself is compiled unchanged.
enum Sport: String { case tennis, padel }
struct Court { let name: String }
struct DiscoverUser { let id: String }
struct GameReport {
    var comment: String? = nil
    var visibility = "private"
    var photoUrls: [String] = []
}
struct MatchGameRequest {
    let id: String
    var rootRequestId: String? = nil
    var createdByUserId: String? = "A"
    var matchedUserId: String? = nil
    var participants: [DiscoverUser] = []
    var proposedDate: Date? = nil
    var status = "accepted"
    var outcome: String? = "played"
    var sport: Sport = .tennis
    var proposedCourt: Court? = nil
    var durationMinutes: Int? = nil
    var comment: String? = nil
    var report: GameReport? = nil
}
struct PersonalActivity {
    let id: String
    var userId = "A"
    var scheduledDate: Date? = nil
    var status = "completed"
    var sport: Sport = .tennis
    var court: Court? = nil
    var durationMinutes: Int? = nil
    var reportComment: String? = nil
    var comment: String? = nil
    var photoUrls: [String] = []
    var videoUrls: [String] = []
}

@main
struct ProfileWorkoutHistoryTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func game(_ id: String, at timestamp: String = "2026-09-22T10:00:00+03:00") -> MatchGameRequest {
        MatchGameRequest(id: id, proposedDate: date(timestamp))
    }
    static func visit(_ id: String, at timestamp: String = "2026-09-22T10:00:00+03:00") -> PersonalActivity {
        PersonalActivity(id: id, scheduledDate: date(timestamp))
    }

    static func main() {
        let now = date("2026-09-23T12:00:00+03:00")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        calendar.firstWeekday = 1
        func history(_ games: [MatchGameRequest] = [], _ visits: [PersonalActivity] = [], owner: String = "A") -> [ProfileWorkoutHistoryItem] {
            ProfileWorkoutHistoryItem.make(games: games, visits: visits, ownerID: owner, now: now)
        }

        let noPhoto = visit("no-photo")
        let single = history([], [noPhoto])
        expect(single.count == 1 && single[0].photoPaths.isEmpty, "An owner's completed visit is included without photos")
        var videoVisit = visit("video"); videoVisit.videoUrls = ["/visit.mp4"]
        expect(history([], [videoVisit])[0].videoPaths == ["/visit.mp4"], "Personal videos survive the completed history projection")
        expect(history([game("legacy")])[0].videoPaths.isEmpty, "Photo-only games have an empty compatible video list")
        expect(single[0].durationMinutes == nil, "Unknown duration remains unknown instead of using a sports default")
        expect(history([], [noPhoto], owner: "").isEmpty, "No account means no private history")
        expect(history([], [noPhoto], owner: "B").isEmpty, "Another account cannot see this visit")

        var planned = visit("planned"); planned.status = "planned"
        var canceled = visit("canceled"); canceled.status = "canceled"
        var invalid = visit("invalid"); invalid.scheduledDate = nil
        let future = visit("future", at: "2026-09-24T10:00:00+03:00")
        expect(history([], [planned, canceled, invalid, future]).isEmpty, "Elapsed plans, cancellations, invalid dates and future completions are excluded")

        var privateGame = game("private")
        privateGame.report = GameReport(comment: " Personal notes ", visibility: "private", photoUrls: ["/private.jpg"])
        privateGame.durationMinutes = 90
        let privateItems = history([privateGame])
        expect(privateItems.count == 1 && privateItems[0].photoPaths == ["/private.jpg"], "The owner's played game may include its private report")
        expect(privateItems[0].comment == "Personal notes" && privateItems[0].durationMinutes == 90, "Recorded notes and exact duration survive projection")
        var reportOnly = privateGame; reportOnly.outcome = nil
        expect(history([reportOnly]).isEmpty, "A report alone cannot establish that a game was played")
        var declined = privateGame; declined.status = "declined"
        var pending = privateGame; pending.status = "pending"
        var notPlayed = privateGame; notPlayed.outcome = "not_played"
        expect(history([declined, pending, notPlayed]).isEmpty, "Unaccepted or not-played games stay out of completed history")
        var approved = game("approved"); approved.status = "approved"
        expect(history([approved]).count == 1, "Approved played games match the accepted legacy state")

        var participant = game("participant")
        participant.createdByUserId = "B"; participant.matchedUserId = "A"
        var roster = game("roster")
        roster.createdByUserId = "B"; roster.participants = [DiscoverUser(id: "A")]
        var foreign = game("foreign"); foreign.createdByUserId = "B"
        expect(Set(history([participant, roster, foreign]).map(\.sourceID)) == ["participant", "roster"], "Only an owner's or participant's games are included")

        var root = game("root")
        var copy = game("copy"); copy.rootRequestId = "root"
        let duplicates = history([copy, root], [noPhoto, noPhoto])
        expect(duplicates.count == 2 && duplicates.first(where: { $0.kind == .game })?.sourceID == "root", "Group transport copies and duplicate visits count once")
        expect(duplicates.map(\.id) == history([root, copy], [noPhoto]).map(\.id), "Same-time records and duplicate input order resolve deterministically")
        root.status = "canceled"
        expect(history([copy, root]).isEmpty, "A stale played copy cannot revive a canceled canonical root")
        expect(history([game("same")], [visit("same")]).count == 2, "Game and visit IDs use separate namespaces")

        var noteVisit = visit("note")
        noteVisit.comment = "  Earlier note  "; noteVisit.reportComment = "   "
        noteVisit.durationMinutes = -1
        expect(history([], [noteVisit])[0].comment == "Earlier note", "An empty report note falls back to the original note")
        expect(history([], [noteVisit])[0].durationMinutes == nil, "An invalid recorded duration is not displayed as a real duration")

        let many = history([], (0..<12).map { visit("visit-\($0)") })
        expect(many.count == 12, "The full history is not truncated to the old six-card limit")
        expect(many.map(\.id) == many.map(\.id).sorted(), "Equal timestamps are ordered by stable canonical IDs")
        let month = ProfileWorkoutHistoryMonth.make(containing: now, items: many, calendar: calendar)
        expect(month.days.count == 30 && month.leadingEmptyDays == 1, "September 2026 has thirty local days on a Monday-first grid")
        expect(month.days.reduce(0) { $0 + $1.count } == 12, "Month counts use the full untruncated history")
        expect(ProfileWorkoutHistoryItem.onDay(date("2026-09-22T00:00:00+03:00"), from: many, calendar: calendar).count == 12, "Selecting one day preserves every workout on it")
        expect(ProfileWorkoutHistoryItem.onDay(now, from: many, calendar: calendar).isEmpty, "A day without workouts is an honest empty selection")
        expect(calendar.firstWeekday == 1, "Generating a grid does not mutate the caller's calendar")

        let boundary = history([], [
            visit("previous-month", at: "2026-08-31T23:59:59+03:00"),
            visit("month-start", at: "2026-08-31T21:00:00Z"),
            visit("day-boundary", at: "2026-09-21T21:30:00Z")
        ])
        let boundaryMonth = ProfileWorkoutHistoryMonth.make(containing: now, items: boundary, calendar: calendar)
        expect(boundaryMonth.interval.start == date("2026-09-01T00:00:00+03:00"), "Month boundaries use the viewer's local timezone")
        expect(boundaryMonth.days[0].count == 1 && boundaryMonth.days[21].count == 1, "UTC timestamps are assigned to their local calendar days")
        expect(boundaryMonth.days.reduce(0) { $0 + $1.count } == 2, "The previous month's final second is excluded")
        expect(boundary.count == 3, "Changing the displayed month does not discard older history")

        let twoInOneDay = history([], [
            visit("morning", at: "2026-09-22T09:00:00+03:00"),
            visit("evening", at: "2026-09-22T19:00:00+03:00")
        ])
        expect(ProfileWorkoutHistoryItem.onDay(date("2026-09-22T12:00:00+03:00"), from: twoInOneDay, calendar: calendar).map(\.sourceID) == ["evening", "morning"], "A day's separate workouts retain their individual reverse-chronological cards")
        let newYear = ProfileWorkoutHistoryItem.make(games: [], visits: [
            visit("before-december", at: "2026-11-30T23:59:59+03:00"),
            visit("december-start", at: "2026-12-01T00:00:00+03:00"),
            visit("year-end", at: "2026-12-31T23:59:59+03:00"),
            visit("new-year", at: "2027-01-01T00:00:00+03:00")
        ], ownerID: "A", now: date("2027-01-02T12:00:00+03:00"))
        let december = ProfileWorkoutHistoryMonth.make(containing: date("2026-12-15T12:00:00+03:00"), items: newYear, calendar: calendar)
        let january = ProfileWorkoutHistoryMonth.make(containing: december.interval.end, items: newYear, calendar: calendar)
        expect(december.interval.end == date("2027-01-01T00:00:00+03:00") && december.days.reduce(0) { $0 + $1.count } == 2, "December includes its exact start and final second but excludes the next year's midnight")
        expect(january.days[0].count == 1 && january.days.count == 31, "Advancing across December to January preserves the local year boundary")

        let leap = ProfileWorkoutHistoryMonth.make(containing: date("2028-02-14T12:00:00Z"), items: [], calendar: calendar)
        expect(leap.days.count == 29 && leap.days.allSatisfy { $0.count == 0 }, "Leap February supplies 29 honest empty days")
        var dst = Calendar(identifier: .gregorian)
        dst.timeZone = TimeZone(identifier: "America/New_York")!
        let dstMonth = ProfileWorkoutHistoryMonth.make(containing: date("2026-03-14T12:00:00-04:00"), items: [], calendar: dst)
        expect(dstMonth.days.count == 31 && dstMonth.days.allSatisfy { dst.component(.hour, from: $0.date) == 0 }, "A DST month uses calendar midnights instead of fixed-day seconds")

        let crossGames = [game("root"), copy, privateGame, reportOnly, foreign, approved]
        let crossVisits = [noPhoto, planned, canceled, future, invalid]
        let homeRecords = crossGames.map { item in
            SportHomeRecord(id: item.id, rootRequestID: item.rootRequestId, kind: .game,
                ownerID: item.createdByUserId, participantIDs: item.participants.map(\.id) + [item.matchedUserId].compactMap { $0 },
                date: item.proposedDate, status: item.status, outcome: item.outcome, durationMinutes: item.durationMinutes,
                title: item.sport.rawValue, location: item.proposedCourt?.name)
        } + crossVisits.map { item in
            SportHomeRecord(id: item.id, rootRequestID: nil, kind: .activity, ownerID: item.userId, participantIDs: [],
                date: item.scheduledDate, status: item.status, outcome: nil, durationMinutes: item.durationMinutes,
                title: item.sport.rawValue, location: item.court?.name)
        }
        let home = SportHomeWeek.make(records: homeRecords, currentUserID: "A", now: now, calendar: calendar)
        expect(Set(history(crossGames, crossVisits).map(\.id)) == Set(home.completed.map(\.id)), "History and the existing sports week agree on ownership, completion and canonical IDs")
        print("Profile workout history: \(checks) checks passed")
    }

}
