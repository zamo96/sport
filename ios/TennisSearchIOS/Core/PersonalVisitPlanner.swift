import Foundation

/// A club's opening hours as minutes from midnight. `close` may be 24:00.
struct ClubHours: Equatable {
    let open: Int
    let close: Int

    private static let range = try? NSRegularExpression(
        pattern: #"(\d{1,2})[:.](\d{2})\s*[-–—]\s*(\d{1,2})[:.](\d{2})"#
    )

    /// Reads a court's free-text hours such as "07:00-23:00" or "08:00–00:00".
    /// Hours past midnight end the day at 24:00: a visit is planned within one day.
    static func parse(_ text: String?) -> ClubHours? {
        guard let text = text?.lowercased(), !text.isEmpty else { return nil }
        if text.contains("круглосуточ") || text.contains("24/7") || text.contains("24 hours") {
            return ClubHours(open: 0, close: 24 * 60)
        }
        let nsText = text as NSString
        guard let match = range?.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        let numbers = (1...4).compactMap { Int(nsText.substring(with: match.range(at: $0))) }
        guard numbers.count == 4, numbers[0] < 24, numbers[2] <= 24, numbers[1] < 60, numbers[3] < 60 else {
            return nil
        }
        let open = numbers[0] * 60 + numbers[1]
        var close = numbers[2] * 60 + numbers[3]
        if close <= open { close = 24 * 60 }
        guard close - open >= PersonalVisitPlanner.slotStep else { return nil }
        return ClubHours(open: open, close: close)
    }

    var label: String {
        "\(PersonalVisitPlanner.clock(open))–\(PersonalVisitPlanner.clock(close))"
    }
}

enum VisitDayPart: Int, CaseIterable, Identifiable {
    case morning, afternoon, evening

    var id: Int { rawValue }

    var minutes: Range<Int> {
        switch self {
        case .morning: return 0 ..< 12 * 60
        case .afternoon: return 12 * 60 ..< 17 * 60
        case .evening: return 17 * 60 ..< 24 * 60
        }
    }

    static func containing(minute: Int) -> VisitDayPart {
        allCases.first { $0.minutes.contains(minute) } ?? .evening
    }
}

/// Where a visit could start, so the composer never offers a time the server will refuse.
enum PersonalVisitPlanner {
    static let slotStep = 30
    static let durationPresets = [45, 60, 90, 120]
    static let preferredStartMinute = 9 * 60
    /// Unknown hours: anything from 06:00 with the last start at 23:00.
    static let fallbackHours = ClubHours(open: 6 * 60, close: 24 * 60)
    private static let fallbackLastStart = 23 * 60

    /// Start times on `day` in `part`: inside the club's hours and ending by closing time,
    /// and strictly after `now` when `day` is today.
    static func startMinutes(
        on day: Date,
        part: VisitDayPart,
        hours: ClubHours?,
        durationMinutes: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [Int] {
        allStartMinutes(on: day, hours: hours, durationMinutes: durationMinutes, now: now, calendar: calendar)
            .filter { part.minutes.contains($0) }
    }

    static func allStartMinutes(
        on day: Date,
        hours: ClubHours?,
        durationMinutes: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [Int] {
        let known = hours ?? fallbackHours
        let first = (known.open + slotStep - 1) / slotStep * slotStep
        let last = hours == nil ? fallbackLastStart : known.close - max(durationMinutes, slotStep)
        guard first <= last else { return [] }
        let dayStart = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        if dayStart < today { return [] }
        let nowMinute = dayStart == today ? minuteOfDay(now, calendar: calendar) : -1
        return stride(from: first, through: last, by: slotStep).filter { $0 > nowMinute }
    }

    /// The first days offered as chips: today and the three after it.
    static func quickDays(from now: Date, count: Int = 4, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0 ..< count).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// A fresh plan starts tomorrow at 09:00, or at the club's first free time that day.
    static func defaultStart(
        hours: ClubHours?,
        durationMinutes: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> (day: Date, minute: Int)? {
        for offset in 1 ... 7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let starts = allStartMinutes(on: day, hours: hours, durationMinutes: durationMinutes, now: now, calendar: calendar)
            if let minute = starts.first(where: { $0 >= preferredStartMinute }) ?? starts.first {
                return (day, minute)
            }
        }
        return nil
    }

    static func durationOptions(including current: Int?) -> [Int] {
        guard let current, !durationPresets.contains(current) else { return durationPresets }
        return (durationPresets + [current]).sorted()
    }

    static func date(on day: Date, minute: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: day))
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60 % 24, minute % 60)
    }

    /// "45 мин", "1 ч", "1,5 ч", "2 ч".
    static func durationLabel(_ minutes: Int, russian: Bool) -> String {
        if minutes < 60 || minutes % 30 != 0 {
            return russian ? "\(minutes) мин" : "\(minutes) min"
        }
        let hours = minutes / 60
        if minutes % 60 == 0 {
            return russian ? "\(hours) ч" : "\(hours) h"
        }
        return russian ? "\(hours),5 ч" : "\(hours).5 h"
    }
}

/// Where a personal visit is in its life, as the upcoming list shows it.
enum PersonalVisitPhase: Equatable {
    /// Ended and still planned: waiting for "happened" or "didn't happen".
    case needsMark
    case inProgress
    case today
    case later
    case completed
    case canceled
}

struct PersonalVisitMoment: Equatable {
    let id: String
    let start: Date
    let durationMinutes: Int
    let status: String
}

enum PersonalVisitTimeline {
    static func isPlanned(status: String) -> Bool {
        status.lowercased() == "planned"
    }

    static func phase(of visit: PersonalVisitMoment, now: Date, calendar: Calendar = .current) -> PersonalVisitPhase {
        switch visit.status.lowercased() {
        case "completed": return .completed
        case "canceled", "cancelled": return .canceled
        default: break
        }
        let end = visit.start.addingTimeInterval(TimeInterval(max(visit.durationMinutes, 1) * 60))
        if end <= now { return .needsMark }
        if visit.start <= now { return .inProgress }
        return calendar.isDate(visit.start, inSameDayAs: now) ? .today : .later
    }

    /// Only plans stay in "Upcoming": the ones waiting for a mark first, newest first,
    /// then the rest by start time. Marked and canceled visits live in the week and history.
    static func upcomingOrder(_ visits: [PersonalVisitMoment], now: Date) -> [String] {
        let planned = visits.filter { isPlanned(status: $0.status) }
        let waiting = planned.filter { phase(of: $0, now: now) == .needsMark }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start > $1.start }
        let ahead = planned.filter { phase(of: $0, now: now) != .needsMark }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        return (waiting + ahead).map(\.id)
    }

    /// "через 1 ч 20 мин" until the start, rounded up to the minute.
    static func countdown(to start: Date, now: Date, russian: Bool) -> String {
        let minutes = max(1, Int((start.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        let rest = minutes % 60
        if russian {
            if hours == 0 { return "через \(rest) мин" }
            return rest == 0 ? "через \(hours) ч" : "через \(hours) ч \(rest) мин"
        }
        if hours == 0 { return "in \(rest) min" }
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
    }
}

enum RussianPlural {
    /// 1 визит, 2 визита, 5 визитов, 11 визитов, 21 визит.
    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        let tens = abs(count) % 100
        let units = abs(count) % 10
        if (11 ... 14).contains(tens) { return many }
        if units == 1 { return one }
        if (2 ... 4).contains(units) { return few }
        return many
    }
}
