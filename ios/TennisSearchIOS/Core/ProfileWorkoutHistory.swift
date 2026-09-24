import Foundation

/// Private, completed activity history. Photos and elapsed plans never establish completion.
struct ProfileWorkoutHistoryItem: Identifiable {
    enum Kind: String { case game, activity }

    let id: String
    let sourceID: String
    let kind: Kind
    let date: Date
    let sport: Sport
    let courtName: String?
    let durationMinutes: Int?
    let comment: String?
    let photoPaths: [String]
    var videoPaths: [String] = []

    static func make(
        games: [MatchGameRequest],
        visits: [PersonalActivity],
        ownerID: String,
        now: Date = Date()
    ) -> [Self] {
        guard !ownerID.isEmpty else { return [] }
        let gameCandidates = games.filter { game in
            game.createdByUserId == ownerID || game.matchedUserId == ownerID
                || game.participants.contains { $0.id == ownerID }
        }.map { game in
            Candidate(
                sourceID: game.id, rootID: game.rootRequestId, kind: .game,
                date: game.proposedDate, status: game.status, outcome: game.outcome,
                sport: game.sport, courtName: game.proposedCourt?.name,
                durationMinutes: game.durationMinutes,
                comment: nonempty(game.report?.comment) ?? nonempty(game.comment),
                photoPaths: game.report?.photoUrls ?? [], videoPaths: []
            )
        }
        let visitCandidates = visits.filter { $0.userId == ownerID }.map { visit in
            Candidate(
                sourceID: visit.id, rootID: nil, kind: .activity,
                date: visit.scheduledDate, status: visit.status, outcome: nil,
                sport: visit.sport, courtName: visit.court?.name,
                durationMinutes: visit.durationMinutes,
                comment: nonempty(visit.reportComment) ?? nonempty(visit.comment),
                photoPaths: visit.photoUrls, videoPaths: visit.videoUrls
            )
        }

        // Resolve the canonical source before testing completion, as SportHomeWeek does.
        // A stale played child cannot revive a canceled root game.
        return Dictionary(grouping: gameCandidates + visitCandidates, by: \.canonicalID)
            .values.compactMap { candidates -> Self? in
                guard let source = candidates.sorted(by: Candidate.prefersCanonical).first,
                      let date = source.date, date <= now else { return nil }
                if source.kind == .activity {
                    guard source.status.lowercased() == "completed" else { return nil }
                } else {
                    guard ["accepted", "approved"].contains(source.status.lowercased()),
                          source.outcome?.lowercased() == "played" else { return nil }
                }
                return Self(
                    id: source.canonicalID, sourceID: source.sourceID, kind: source.kind,
                    date: date, sport: source.sport, courtName: source.courtName,
                    durationMinutes: source.durationMinutes.flatMap { $0 > 0 ? $0 : nil },
                    comment: source.comment, photoPaths: source.photoPaths, videoPaths: source.videoPaths
                )
            }
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date > rhs.date
            }
    }

    static func onDay(_ day: Date, from items: [Self], calendar: Calendar = .current) -> [Self] {
        items.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private struct Candidate {
        let sourceID: String
        let rootID: String?
        let kind: Kind
        let date: Date?
        let status: String
        let outcome: String?
        let sport: Sport
        let courtName: String?
        let durationMinutes: Int?
        let comment: String?
        let photoPaths: [String]
        let videoPaths: [String]

        var canonicalID: String {
            let root = rootID?.trimmingCharacters(in: .whitespacesAndNewlines)
            return kind.rawValue + ":" + ((root?.isEmpty == false ? root : nil) ?? sourceID)
        }

        static func prefersCanonical(_ lhs: Self, _ rhs: Self) -> Bool {
            let lhsRoot = lhs.rootID == nil || lhs.rootID == lhs.sourceID
            let rhsRoot = rhs.rootID == nil || rhs.rootID == rhs.sourceID
            if lhsRoot != rhsRoot { return lhsRoot }
            return lhs.sourceID < rhs.sourceID
        }
    }
}

struct ProfileWorkoutHistoryDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct ProfileWorkoutHistoryMonth {
    let interval: DateInterval
    let leadingEmptyDays: Int
    let days: [ProfileWorkoutHistoryDay]

    static func make(
        containing date: Date,
        items: [ProfileWorkoutHistoryItem],
        calendar: Calendar = .current
    ) -> Self {
        var monthCalendar = calendar
        monthCalendar.firstWeekday = 2
        let start = monthCalendar.dateInterval(of: .month, for: date)?.start
            ?? monthCalendar.startOfDay(for: date)
        let end = monthCalendar.date(byAdding: .month, value: 1, to: start) ?? start
        let counts = Dictionary(grouping: items.filter { $0.date >= start && $0.date < end }) {
            monthCalendar.startOfDay(for: $0.date)
        }.mapValues(\.count)
        let dayCount = monthCalendar.range(of: .day, in: .month, for: start)?.count ?? 0
        let days = (0..<dayCount).compactMap { offset -> ProfileWorkoutHistoryDay? in
            guard let day = monthCalendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return ProfileWorkoutHistoryDay(date: day, count: counts[day] ?? 0)
        }
        let leading = (monthCalendar.component(.weekday, from: start) - monthCalendar.firstWeekday + 7) % 7
        return Self(interval: DateInterval(start: start, end: end), leadingEmptyDays: leading, days: days)
    }
}
