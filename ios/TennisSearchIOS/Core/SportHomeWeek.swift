import Foundation

/// Presentation data only. Completion is always supplied by the domain, never inferred from time.
struct SportHomeRecord: Equatable {
    enum Kind: String { case game, activity }

    let id: String
    let rootRequestID: String?
    let kind: Kind
    let ownerID: String?
    let participantIDs: [String]
    let date: Date?
    let status: String
    let outcome: String?
    let durationMinutes: Int?
    let title: String
    let location: String?

    var canonicalID: String {
        let root = rootRequestID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return kind.rawValue + ":" + ((root?.isEmpty == false ? root : nil) ?? id)
    }
}

struct SportHomeEvent: Identifiable, Equatable {
    enum State { case planned, pending, needsReview, completed, canceled, notPlayed }

    let id: String
    let sourceID: String
    let kind: SportHomeRecord.Kind
    let date: Date
    let title: String
    let location: String?
    let state: State
}

struct SportHomeDay: Identifiable, Equatable {
    let date: Date
    let completedCount: Int
    let plannedCount: Int
    let reviewCount: Int
    let otherCount: Int
    var id: Date { date }
}

struct SportHomeWeek {
    let interval: DateInterval
    let days: [SportHomeDay]
    let completed: [SportHomeEvent]
    let events: [SportHomeEvent]
    let nearestPlan: SportHomeEvent?
    let needsReview: SportHomeEvent?

    func events(on day: Date, calendar: Calendar = .current) -> [SportHomeEvent] {
        events.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    static func make(
        records: [SportHomeRecord],
        currentUserID: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SportHomeWeek {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let start = weekCalendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? weekCalendar.startOfDay(for: now)
        let end = weekCalendar.date(byAdding: .day, value: 7, to: start) ?? start
        let interval = DateInterval(start: start, end: end)

        let owned = records.filter { record in
            guard !currentUserID.isEmpty else { return false }
            if record.kind == .activity { return record.ownerID == currentUserID }
            return record.ownerID == currentUserID || record.participantIDs.contains(currentUserID)
        }
        let grouped = Dictionary(grouping: owned, by: \.canonicalID)
        let events = grouped.values.compactMap { records -> SportHomeEvent? in
            // Prefer the root over its transport copies. Stable IDs make duplicate resolution deterministic.
            let record = records.sorted { lhs, rhs in
                let lhsRoot = lhs.rootRequestID == nil || lhs.rootRequestID == lhs.id
                let rhsRoot = rhs.rootRequestID == nil || rhs.rootRequestID == rhs.id
                if lhsRoot != rhsRoot { return lhsRoot }
                return lhs.id < rhs.id
            }.first!
            guard let date = record.date else { return nil }
            let status = record.status.lowercased()
            let outcome = record.outcome?.lowercased()
            let state: SportHomeEvent.State

            if record.kind == .activity {
                guard ["planned", "completed", "canceled"].contains(status) else { return nil }
                if status == "canceled" {
                    state = .canceled
                } else if status == "completed" {
                    guard date <= now else { return nil }
                    state = .completed
                } else {
                    let duration = max(record.durationMinutes ?? 60, 1)
                    state = date.addingTimeInterval(TimeInterval(duration * 60)) <= now ? .needsReview : .planned
                }
            } else {
                guard ["accepted", "approved", "pending", "canceled"].contains(status) else { return nil }
                if status == "canceled" {
                    state = .canceled
                } else if outcome == "not_played" {
                    guard date <= now, status != "pending" else { return nil }
                    state = .notPlayed
                } else if outcome == "played" {
                    guard date <= now, status != "pending" else { return nil }
                    state = .completed
                } else if outcome != nil {
                    return nil
                } else if status == "pending" {
                    guard date >= now else { return nil }
                    state = .pending
                } else {
                    let duration = max(record.durationMinutes ?? 90, 1)
                    state = date.addingTimeInterval(TimeInterval(duration * 60)) <= now ? .needsReview : .planned
                }
            }
            return SportHomeEvent(
                id: record.canonicalID, sourceID: record.id, kind: record.kind,
                date: date, title: record.title, location: record.location, state: state
            )
        }
        let completed = events.filter { $0.state == .completed && $0.date >= start && $0.date < end }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        let plans = events.filter { $0.state == .planned || $0.state == .pending }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let weekEvents = events.filter { $0.date >= start && $0.date < end }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let days = (0..<7).compactMap { offset -> SportHomeDay? in
            guard let date = weekCalendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return SportHomeDay(
                date: date,
                completedCount: completed.filter { weekCalendar.isDate($0.date, inSameDayAs: date) }.count,
                plannedCount: plans.filter { weekCalendar.isDate($0.date, inSameDayAs: date) }.count,
                reviewCount: weekEvents.filter { $0.state == .needsReview && weekCalendar.isDate($0.date, inSameDayAs: date) }.count,
                otherCount: weekEvents.filter { ($0.state == .canceled || $0.state == .notPlayed) && weekCalendar.isDate($0.date, inSameDayAs: date) }.count
            )
        }
        return SportHomeWeek(
            interval: interval, days: days, completed: completed, events: weekEvents, nearestPlan: plans.first,
            needsReview: events.filter { $0.state == .needsReview }
                .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }.first
        )
    }
}
