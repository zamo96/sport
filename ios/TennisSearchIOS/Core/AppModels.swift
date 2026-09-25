import Foundation
import CoreLocation
import UserNotifications
import SwiftUI

enum SupportedCity: String, CaseIterable, Codable, Identifiable {
    case saintPetersburg = "Санкт-Петербург"
    case moscow = "Москва"
    case kazan = "Казань"

    static let selectableCases: [SupportedCity] = [
        .saintPetersburg,
        .moscow
    ]

    var id: String { rawValue }

    var mapCenter: CLLocationCoordinate2D {
        switch self {
        case .saintPetersburg:
            return CLLocationCoordinate2D(latitude: 59.9386, longitude: 30.3141)
        case .moscow:
            return CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
        case .kazan:
            return CLLocationCoordinate2D(latitude: 55.7961, longitude: 49.1064)
        }
    }

    var mapDiameterMeters: CLLocationDistance {
        switch self {
        case .saintPetersburg:
            return 70_000
        case .moscow:
            return 90_000
        case .kazan:
            return 55_000
        }
    }

    var supportsDistrictSelection: Bool {
        true
    }

    static func resolve(_ value: String?) -> SupportedCity? {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "-", with: " ")

        if normalized.contains("петербург") || normalized.contains("petersburg") {
            return .saintPetersburg
        }
        if normalized.contains("москва") || normalized.contains("moscow") {
            return .moscow
        }
        if normalized.contains("казан") || normalized.contains("kazan") {
            return .kazan
        }

        return nil
    }
}

enum LocationSource: String, Codable {
    case manual
    case geolocation
    case legacy
}

struct GeoCountry: Codable, Identifiable, Equatable {
    let code: String
    let name: String

    var id: String { code }

    var flagEmoji: String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scalars = Array(normalized.unicodeScalars)
        guard scalars.count == 2,
              scalars.allSatisfy({ (65...90).contains($0.value) }),
              let first = UnicodeScalar(0x1F1E6 + scalars[0].value - 65),
              let second = UnicodeScalar(0x1F1E6 + scalars[1].value - 65) else {
            return "🌐"
        }
        return String(first) + String(second)
    }
}

struct LocationCoverage: Codable, Equatable {
    let isSupported: Bool
    let clubsEnabled: Bool
    let districtsEnabled: Bool
    let legacyCity: String?

    static let unavailable = LocationCoverage(
        isSupported: false,
        clubsEnabled: false,
        districtsEnabled: false,
        legacyCity: nil
    )
}

struct GeoPlace: Codable, Identifiable, Equatable {
    let id: String
    let provider: String
    let countryCode: String
    let countryName: String
    let region: String?
    let city: String
    let latitude: Double
    let longitude: Double
    let coverage: LocationCoverage
    var recommendedLocale: String? = nil

    var displayTitle: String { city }

    // The catalog stores country names in English, so the display name comes from the country code
    // in the language the app is currently showing. The backend only ever sends codes it validated
    // against the ISO list, and the stored name stays as the fallback.
    var localizedCountryName: String {
        LocaleStore.currentEffectiveLocale.locale.localizedString(forRegionCode: countryCode) ?? countryName
    }

    var displaySubtitle: String {
        [region, localizedCountryName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(city) != .orderedSame }
            .joined(separator: ", ")
    }
}

private let districtDisplayNamesMap: [String: String] = [
    "admiralteysky": "Адмиралтейский",
    "vasileostrovsky": "Василеостровский",
    "vyborgsky": "Выборгский",
    "kalininsky": "Калининский",
    "kirovsky": "Кировский",
    "kolpinsky": "Колпинский",
    "krasnogvardeysky": "Красногвардейский",
    "krasnoselsky": "Красносельский",
    "kronshtadtsky": "Кронштадтский",
    "kurortny": "Курортный",
    "moskovsky": "Московский",
    "nevsky": "Невский",
    "petrogradsky": "Петроградский",
    "petrodvortsovy": "Петродворцовый",
    "primorsky": "Приморский",
    "pushkinsky": "Пушкинский",
    "frunzensky": "Фрунзенский",
    "central": "Центральный",
    "moscow_central": "Центральный административный округ",
    "moscow_northern": "Северный административный округ",
    "moscow_northeastern": "Северо-Восточный административный округ",
    "moscow_eastern": "Восточный административный округ",
    "moscow_southeastern": "Юго-Восточный административный округ",
    "moscow_southern": "Южный административный округ",
    "moscow_southwestern": "Юго-Западный административный округ",
    "moscow_western": "Западный административный округ",
    "moscow_northwestern": "Северо-Западный административный округ",
    "moscow_zelenograd": "Зеленоградский административный округ",
    "moscow_novomoskovsky": "Новомосковский административный округ",
    "moscow_troitsky": "Троицкий административный округ",
    "kazan_aviastroitelny": "Авиастроительный",
    "kazan_vakhitovsky": "Вахитовский",
    "kazan_kirovsky": "Кировский",
    "kazan_moskovsky": "Московский",
    "kazan_novo_savinovsky": "Ново-Савиновский",
    "kazan_privolzhsky": "Приволжский",
    "kazan_sovetsky": "Советский"
]

func localizedDistrictName(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }

    if let mapped = districtDisplayNamesMap[value.lowercased()] {
        return mapped
    }

    return value
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
}

func districtBelongsToCity(_ districtID: String, city: SupportedCity) -> Bool {
    switch city {
    case .saintPetersburg:
        return !districtID.hasPrefix("moscow_") && !districtID.hasPrefix("kazan_")
    case .moscow:
        return districtID.hasPrefix("moscow_")
    case .kazan:
        return districtID.hasPrefix("kazan_")
    }
}

func resolvedDistrictID(forDisplayName value: String?, city: SupportedCity? = nil) -> String? {
    guard let value else {
        return nil
    }

    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "ё", with: "е")
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: ",", with: " ")
        .replacingOccurrences(of: ".", with: " ")

    guard !normalized.isEmpty else {
        return nil
    }

    let aliases: [String: [String]] = [
        "moscow_central": ["цао", "центральный административный"],
        "moscow_northern": ["сао", "северный административный"],
        "moscow_northeastern": ["свао", "северо восточный административный"],
        "moscow_eastern": ["вао", "восточный административный"],
        "moscow_southeastern": ["ювао", "юго восточный административный"],
        "moscow_southern": ["юао", "южный административный"],
        "moscow_southwestern": ["юзао", "юго западный административный"],
        "moscow_western": ["зао", "западный административный"],
        "moscow_northwestern": ["сзао", "северо западный административный"],
        "moscow_zelenograd": ["зелено град", "зеленоград"],
        "moscow_novomoskovsky": ["нао", "новомосков"],
        "moscow_troitsky": ["тао", "троиц"],
        "kazan_aviastroitelny": ["авиастроитель"],
        "kazan_vakhitovsky": ["вахитов"],
        "kazan_kirovsky": ["киров"],
        "kazan_moskovsky": ["москов"],
        "kazan_novo_savinovsky": ["ново савинов"],
        "kazan_privolzhsky": ["приволж"],
        "kazan_sovetsky": ["советск"]
    ]

    let eligibleIDs = districtDisplayNamesMap.keys.filter { districtID in
        city.map { districtBelongsToCity(districtID, city: $0) } ?? true
    }
    let exactOnlyAliases: Set<String> = ["цао", "сао", "свао", "вао", "ювао", "юао", "юзао", "зао", "сзао", "нао", "тао"]
    let normalizedTokens = Set(
        normalized
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    )

    if let aliasMatch = eligibleIDs.first(where: { districtID in
        aliases[districtID, default: []].contains(where: { alias in
            if exactOnlyAliases.contains(alias) {
                return normalized == alias || normalizedTokens.contains(alias)
            }

            return normalized.contains(alias)
        })
    }) {
        return aliasMatch
    }

    return districtDisplayNamesMap.first { districtID, displayName in
        guard eligibleIDs.contains(districtID) else {
            return false
        }
        let normalizedDisplayName = displayName
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "-", with: " ")
        return normalized.contains(normalizedDisplayName)
    }?.key
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male:
            return L10n.string("Man", "Мужчина")
        case .female:
            return L10n.string("Woman", "Женщина")
        case .other:
            return L10n.string("Other", "Другое")
        }
    }
}

enum PlayerMediaKind: String {
    case photo
    case video
}

struct PlayerMediaItem: Identifiable, Hashable {
    let kind: PlayerMediaKind
    let path: String

    var id: String {
        "\(kind.rawValue)-\(path)"
    }
}

enum Sport: String, Codable, CaseIterable, Identifiable {
    case tableTennis = "table_tennis"
    case tennis
    case padel
    case squash
    case badminton
    case volleyball
    case fitness
    case boxing
    case yoga
    case football
    case running
    case supboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tableTennis:
            return L10n.string("Table tennis", "Настольный теннис")
        case .tennis:
            return L10n.string("Tennis", "Теннис")
        case .padel:
            return L10n.string("Padel", "Падел")
        case .squash:
            return L10n.string("Squash", "Сквош")
        case .badminton:
            return L10n.string("Badminton", "Бадминтон")
        case .volleyball:
            return L10n.string("Volleyball", "Волейбол")
        case .fitness:
            return L10n.string("Fitness", "Фитнес")
        case .boxing:
            return L10n.string("Boxing", "Бокс")
        case .yoga:
            return L10n.string("Yoga", "Йога")
        case .football:
            return L10n.string("Football", "Футбол")
        case .running:
            return L10n.string("Running", "Бег")
        case .supboard:
            return L10n.string("SUP", "Сапборд")
        }
    }
}

struct SportPlaybook {
    let allowedFormats: [PlayFormat]
    let defaultFormat: PlayFormat
    let defaultDurationMinutes: Int
    let defaultPlayersNeededByFormat: [PlayFormat: Int]
    let maxPlayersNeeded: Int
}

extension Sport {
    var playbook: SportPlaybook {
        switch self {
        case .tennis:
            return SportPlaybook(
                allowedFormats: [.singles, .doubles, .both],
                defaultFormat: .singles,
                defaultDurationMinutes: 90,
                defaultPlayersNeededByFormat: [.singles: 1, .doubles: 3, .both: 1],
                maxPlayersNeeded: 8
            )
        case .padel:
            return SportPlaybook(
                allowedFormats: [.doubles],
                defaultFormat: .doubles,
                defaultDurationMinutes: 90,
                defaultPlayersNeededByFormat: [.singles: 3, .doubles: 3, .both: 3],
                maxPlayersNeeded: 8
            )
        case .badminton:
            return SportPlaybook(
                allowedFormats: [.singles, .doubles, .both],
                defaultFormat: .both,
                defaultDurationMinutes: 60,
                defaultPlayersNeededByFormat: [.singles: 1, .doubles: 3, .both: 1],
                maxPlayersNeeded: 8
            )
        case .tableTennis:
            return SportPlaybook(
                allowedFormats: [.singles],
                defaultFormat: .singles,
                defaultDurationMinutes: 60,
                defaultPlayersNeededByFormat: [.singles: 1, .doubles: 1, .both: 1],
                maxPlayersNeeded: 8
            )
        case .squash:
            return SportPlaybook(
                allowedFormats: [.singles],
                defaultFormat: .singles,
                defaultDurationMinutes: 60,
                defaultPlayersNeededByFormat: [.singles: 1, .doubles: 1, .both: 1],
                maxPlayersNeeded: 8
            )
        case .football:
            return SportPlaybook(
                allowedFormats: [.doubles],
                defaultFormat: .doubles,
                defaultDurationMinutes: 90,
                defaultPlayersNeededByFormat: [.singles: 9, .doubles: 9, .both: 9],
                maxPlayersNeeded: 12
            )
        case .volleyball:
            return SportPlaybook(
                allowedFormats: [.doubles],
                defaultFormat: .doubles,
                defaultDurationMinutes: 90,
                defaultPlayersNeededByFormat: [.singles: 5, .doubles: 5, .both: 5],
                maxPlayersNeeded: 12
            )
        case .fitness, .boxing, .yoga, .running, .supboard:
            return SportPlaybook(
                allowedFormats: [.singles, .both],
                defaultFormat: .singles,
                defaultDurationMinutes: 60,
                defaultPlayersNeededByFormat: [.singles: 1, .doubles: 1, .both: 1],
                maxPlayersNeeded: 8
            )
        }
    }

    var allowedFormats: [PlayFormat] { playbook.allowedFormats }
    var defaultFormat: PlayFormat { playbook.defaultFormat }
    var defaultDurationMinutes: Int { playbook.defaultDurationMinutes }
    var maxPlayersNeeded: Int { playbook.maxPlayersNeeded }

    func resolveFormat(_ requested: PlayFormat) -> PlayFormat {
        allowedFormats.contains(requested) ? requested : defaultFormat
    }

    func defaultPlayersNeeded(format: PlayFormat) -> Int {
        let resolved = resolveFormat(format)
        return playbook.defaultPlayersNeededByFormat[resolved] ?? 1
    }

    var venueTitle: String {
        switch self {
        case .tennis, .padel, .badminton, .squash:
            return L10n.string("Court", "Корт")
        case .tableTennis:
            return L10n.string("Venue", "Зал")
        case .football, .volleyball:
            return L10n.string("Field", "Площадка")
        case .fitness, .boxing:
            return L10n.string("Gym", "Зал")
        case .yoga:
            return L10n.string("Studio", "Студия")
        case .running, .supboard:
            return L10n.string("Route", "Маршрут")
        }
    }

    var isRouteSport: Bool {
        self == .running || self == .supboard
    }

    var routeFollowsRoads: Bool {
        self == .running
    }

    var routeDefaultTitle: String {
        self == .supboard ? L10n.string("Water route", "Маршрут по воде") : L10n.string("Running route", "Маршрут бега")
    }

    var venueFieldTitle: String {
        venueTitle
    }

    private enum VenueNounGender {
        case masculine
        case feminine
        case neuter
    }

    private var venueGender: VenueNounGender {
        switch venueTitle {
        case "Студия", "Площадка":
            return .feminine
        case "Здание", "Место":
            return .neuter
        default:
            return .masculine
        }
    }

    var venueBookedTitle: String {
        if LocaleStore.currentEffectiveLocale == .en {
            return "\(venueTitle) already booked"
        }
        switch venueGender {
        case .feminine:
            return "\(venueTitle) уже забронирована"
        case .neuter:
            return "\(venueTitle) уже забронировано"
        case .masculine:
            return "\(venueTitle) уже забронирован"
        }
    }

    var venuePendingTitle: String {
        L10n.string("\(venueTitle) to be selected", "\(venueTitle) подбирается")
    }

    var venueUnspecifiedTitle: String {
        L10n.string("\(venueTitle) to be confirmed", "\(venueTitle) уточняется")
    }

    var venueExistsTitle: String {
        L10n.string("\(venueTitle) available", "\(venueTitle) есть")
    }

    private var isTeamSport: Bool {
        self == .football || self == .volleyball
    }

    func formatTitle(format: PlayFormat, playersNeeded: Int? = nil) -> String {
        if format == .both {
            return L10n.string("Any", "Любой")
        }

        let resolvedPlayersNeeded = playersNeeded ?? defaultPlayersNeeded(format: format)
        let isGroup = resolvedPlayersNeeded > 1

        if isTeamSport {
            return L10n.string("Team", "Командная")
        }

        switch self {
        case .fitness, .boxing, .yoga, .running, .supboard:
            return isGroup ? L10n.string("Group", "Групповая") : L10n.string("Individual", "Индивидуально")
        default:
            if isGroup, resolvedPlayersNeeded > 3 {
                return L10n.string("Group", "Групповая")
            }

            switch format {
            case .singles:
                return isGroup ? L10n.string("Group", "Групповая") : L10n.string("Singles", "Одиночная")
            case .doubles:
                return resolvedPlayersNeeded > 3 ? L10n.string("Group", "Групповая") : L10n.string("Doubles", "Парная")
            case .both:
                return L10n.string("Any", "Любой")
            }
        }
    }
}

enum SwipeAction: String, Codable {
    case like
    case dislike
    case superlike
}

enum PlayFormat: String, Codable, CaseIterable, Identifiable {
    case singles
    case doubles
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singles:
            return L10n.string("Singles", "Одиночный")
        case .doubles:
            return L10n.string("Doubles", "Парный")
        case .both:
            return L10n.string("Any", "Любой")
        }
    }
}

enum Surface: String, Codable, CaseIterable, Identifiable {
    case hard
    case clay
    case grass
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hard:
            return L10n.string("Hard", "Хард")
        case .clay:
            return L10n.string("Clay", "Грунт")
        case .grass:
            return L10n.string("Grass", "Трава")
        case .any:
            return L10n.string("Any", "Любое")
        }
    }
}

enum SearchType: String, Codable, CaseIterable, Identifiable {
    case regular
    case hot

    var id: String { rawValue }

    static var userVisibleCases: [SearchType] {
        [.hot]
    }

    var title: String {
        switch self {
        case .regular:
            return L10n.string("Regular", "Регулярный")
        case .hot:
            return L10n.string("Urgent", "Срочный")
        }
    }
}

enum HotWindow: String, Codable, CaseIterable, Identifiable {
    case today
    case tomorrow
    case dayAfterTomorrow = "day_after_tomorrow"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return L10n.string("Today", "Сегодня")
        case .tomorrow:
            return L10n.string("Tomorrow", "Завтра")
        case .dayAfterTomorrow:
            return L10n.string("Day after tomorrow", "Послезавтра")
        }
    }
}

enum TimeRange: String, Codable, CaseIterable, Identifiable {
    case morning
    case day
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:
            return L10n.string("Morning", "Утро")
        case .day:
            return L10n.string("Afternoon", "День")
        case .evening:
            return L10n.string("Evening", "Вечер")
        }
    }
}

func localizedTimePreferenceTitle(_ value: String) -> String {
    if let paired = localizedPairedTimePreference(value) {
        return paired
    }

    if let range = TimeRange(rawValue: value) {
        return range.title
    }

    return value
}

func localizedTimePreferenceDetailTitle(_ value: String) -> String {
    if let paired = localizedPairedTimePreference(value) {
        return paired
    }

    if let range = TimeRange(rawValue: value) {
        switch range {
        case .morning:
            return L10n.string("Morning", "Утро")
        case .day:
            return L10n.string("Afternoon", "День")
        case .evening:
            return L10n.string("Evening (after 6:00 PM)", "Вечер (после 18:00)")
        }
    }

    return value
}

private func localizedPairedTimePreference(_ value: String) -> String? {
    let parts = value.split(separator: "@", maxSplits: 1).map(String.init)
    guard parts.count == 2,
          let day = DayOfWeek(rawValue: parts[0]) else {
        return nil
    }

    return "\(day.shortTitle) \(parts[1])"
}

enum DayOfWeek: String, Codable, CaseIterable, Identifiable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .monday:
            return L10n.string("Mon", "Пн")
        case .tuesday:
            return L10n.string("Tue", "Вт")
        case .wednesday:
            return L10n.string("Wed", "Ср")
        case .thursday:
            return L10n.string("Thu", "Чт")
        case .friday:
            return L10n.string("Fri", "Пт")
        case .saturday:
            return L10n.string("Sat", "Сб")
        case .sunday:
            return L10n.string("Sun", "Вс")
        }
    }

    var title: String {
        switch self {
        case .monday:
            return L10n.string("Monday", "Понедельник")
        case .tuesday:
            return L10n.string("Tuesday", "Вторник")
        case .wednesday:
            return L10n.string("Wednesday", "Среда")
        case .thursday:
            return L10n.string("Thursday", "Четверг")
        case .friday:
            return L10n.string("Friday", "Пятница")
        case .saturday:
            return L10n.string("Saturday", "Суббота")
        case .sunday:
            return L10n.string("Sunday", "Воскресенье")
        }
    }
}

enum DiscoverTab: String, CaseIterable, Identifiable {
    case upcoming
    case swipe
    case likes
    case seeking
    case hot

    var id: String { rawValue }

    static var userVisibleCases: [DiscoverTab] {
        [.swipe, .upcoming, .hot]
    }

    var title: String {
        switch self {
        case .upcoming:
            return L10n.string("Upcoming games", "Ближайшие игры")
        case .swipe:
            return L10n.string("Similar players", "Похожие игроки")
        case .likes:
            return L10n.string("Want to play with you", "Хотят с тобой поиграть")
        case .seeking:
            return L10n.string("Regular", "Регулярно")
        case .hot:
            return L10n.string("Searches", "Поиски")
        }
    }

    var systemImage: String {
        switch self {
        case .upcoming:
            return "calendar.badge.clock"
        case .swipe:
            return "person.2.fill"
        case .likes:
            return "heart.text.square"
        case .seeking:
            return "calendar"
        case .hot:
            return "magnifyingglass"
        }
    }
}

enum AuthStep: String, Identifiable {
    case intro
    case profile
    case availability
    case email
    case code

    var id: String { rawValue }
}

enum LegalDocuments {
    /// Редакция без встроенного согласия на обработку данных: соглашение
    /// принимается кнопкой входа, согласия спрашиваются отдельно.
    static let userAgreementVersion = "2026-09-24"
    static var acceptanceError: String {
        L10n.string(
            "Accept the User Agreement.",
            "Нужно принять пользовательское соглашение."
        )
    }

    static var userAgreementURL: URL? { url("terms") }
    static var privacyPolicyURL: URL? { url("privacy") }
    static var profileVisibilityConsentURL: URL? { url("profile-visibility") }
    static var analyticsConsentURL: URL? { url("analytics") }

    private static func url(_ document: String) -> URL? {
        if let baseURL = AppConfig.apiBaseURL {
            return baseURL
                .appendingPathComponent("legal")
                .appendingPathComponent(document)
        }

        return URL(string: "https://sportsearch.shop/legal/\(document)")
    }

    /// Текст под кнопками входа: нажатие означает принятие соглашения. Согласия
    /// на обработку данных здесь нет — оно не может быть частью соглашения.
    static var signInNotice: some View {
        let terms = userAgreementURL?.absoluteString ?? "https://sportsearch.shop/legal/terms"
        let privacy = privacyPolicyURL?.absoluteString ?? "https://sportsearch.shop/legal/privacy"
        let markdown = L10n.string(
            "By continuing, you accept the [User Agreement](\(terms)). How we process data is described in the [Privacy Policy](\(privacy)).",
            "Нажимая кнопку, вы принимаете [пользовательское соглашение](\(terms)). Как мы обрабатываем данные — в [политике конфиденциальности](\(privacy))."
        )
        return Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
            .font(.footnote)
            .foregroundStyle(AppTheme.ink.opacity(0.6))
            .tint(AppTheme.court)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UserSafetyContext: Codable {
    let type: String
    let id: String?

    static func profile(userId: String) -> UserSafetyContext {
        UserSafetyContext(type: "profile", id: userId)
    }

    static func chat(messageId: String?) -> UserSafetyContext {
        UserSafetyContext(type: "chat", id: messageId)
    }
}

enum UserSafetyReason: String, Codable, CaseIterable, Identifiable {
    case harassment
    case hateSpeech = "hate_speech"
    case sexualContent = "sexual_content"
    case violence
    case spam
    case impersonation
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment: return L10n.string("Harassment or bullying", "Оскорбления или травля")
        case .hateSpeech: return L10n.string("Hate speech", "Язык ненависти")
        case .sexualContent: return L10n.string("Inappropriate content", "Неприемлемый контент")
        case .violence: return L10n.string("Threats or violence", "Угрозы или насилие")
        case .spam: return L10n.string("Spam or fraud", "Спам или мошенничество")
        case .impersonation: return L10n.string("Impersonation", "Выдаёт себя за другого")
        case .other: return L10n.string("Other reason", "Другая причина")
        }
    }
}

struct UserSafetyReport: Codable, Identifiable {
    let id: String
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let dueAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, status, createdAt, updatedAt, dueAt
    }

    init(id: String, status: String, createdAt: String? = nil, updatedAt: String? = nil, dueAt: String? = nil) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueAt = dueAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
    }
}

struct SessionUser: Codable {
    let id: String
    let email: String
    let onboardingCompleted: Bool
}

struct AuthChallenge: Codable {
    let message: String
    let debugCode: String?
}

// MARK: - Required onboarding fields

enum OnboardingRequirements {
    static func hasProfileBasics(name: String?, age: Int?, hasSports: Bool) -> Bool {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && (18 ... 100).contains(age ?? 0)
            && hasSports
    }

    static func hasSelectedCity(city: String?, locationPlaceID: String?, locationCity: String?) -> Bool {
        // A resolved global place is valid even outside the legacy city catalog.
        if let locationPlaceID {
            return locationPlaceID.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                && !(locationCity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let city = SupportedCity.resolve(city) else { return false }
        return SupportedCity.selectableCases.contains(city)
    }

    static func isComplete(completed: Bool, hasProfileBasics: Bool, hasSelectedCity: Bool) -> Bool {
        completed && hasProfileBasics && hasSelectedCity
    }
}

// MARK: - End required onboarding fields

struct GuestOnboardingDraft: Codable, Equatable {
    var name: String
    var age: Int
    var gender: Gender?
    var city: String
    var location: GeoPlace?
    var locationSource: LocationSource?
    var district: String?
    var preferredDistricts: [String]
    var preferredSports: [Sport]
    var sportLevels: [String: Int]
    var preferredPlayFormat: PlayFormat
    var preferredSurface: Surface
    var searchRadiusKm: Int
    var isLookingForGame: Bool
    var showOnMap: Bool
    var availableDays: [String]
    var availableTimeRanges: [String]
    var availabilityByDay: [String: [String]]
    var onboardingCompleted: Bool

    init(
        name: String,
        age: Int,
        gender: Gender?,
        city: String,
        location: GeoPlace? = nil,
        locationSource: LocationSource? = nil,
        district: String?,
        preferredDistricts: [String],
        preferredSports: [Sport],
        sportLevels: [String: Int],
        preferredPlayFormat: PlayFormat,
        preferredSurface: Surface,
        searchRadiusKm: Int,
        isLookingForGame: Bool,
        showOnMap: Bool = true,
        availableDays: [String],
        availableTimeRanges: [String],
        availabilityByDay: [String: [String]],
        onboardingCompleted: Bool
    ) {
        self.name = name
        self.age = age
        self.gender = gender
        self.city = city
        self.location = location
        self.locationSource = locationSource
        self.district = district
        self.preferredDistricts = preferredDistricts
        self.preferredSports = preferredSports
        self.sportLevels = sportLevels
        self.preferredPlayFormat = preferredPlayFormat
        self.preferredSurface = preferredSurface
        self.searchRadiusKm = searchRadiusKm
        self.isLookingForGame = isLookingForGame
        self.showOnMap = showOnMap
        self.availableDays = availableDays
        self.availableTimeRanges = availableTimeRanges
        self.availabilityByDay = availabilityByDay
        self.onboardingCompleted = onboardingCompleted
    }

    static let `default` = GuestOnboardingDraft(
        name: "",
        age: 0,
        gender: nil,
        city: "",
        location: nil,
        locationSource: nil,
        district: nil,
        preferredDistricts: [],
        preferredSports: [],
        sportLevels: [:],
        preferredPlayFormat: .both,
        preferredSurface: .any,
        searchRadiusKm: 20,
        isLookingForGame: true,
        availableDays: [],
        availableTimeRanges: [],
        availabilityByDay: [:],
        onboardingCompleted: false
    )

    var hasProfileBasics: Bool {
        OnboardingRequirements.hasProfileBasics(name: name, age: age, hasSports: !preferredSports.isEmpty)
    }

    var hasSelectedCity: Bool {
        OnboardingRequirements.hasSelectedCity(city: city, locationPlaceID: location?.id, locationCity: location?.city)
    }

    var hasRequiredOnboardingFields: Bool {
        hasProfileBasics && hasSelectedCity
    }

    var isOnboardingComplete: Bool {
        OnboardingRequirements.isComplete(completed: onboardingCompleted, hasProfileBasics: hasProfileBasics, hasSelectedCity: hasSelectedCity)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case age
        case gender
        case city
        case location
        case locationSource
        case district
        case preferredDistricts
        case preferredSports
        case sportLevels
        case preferredPlayFormat
        case preferredSurface
        case searchRadiusKm
        case isLookingForGame
        case showOnMap
        case availableDays
        case availableTimeRanges
        case availabilityByDay
        case onboardingCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        age = try container.decodeIfPresent(Int.self, forKey: .age) ?? 0
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        location = try container.decodeIfPresent(GeoPlace.self, forKey: .location)
        locationSource = try container.decodeIfPresent(LocationSource.self, forKey: .locationSource)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        preferredSports = try container.decodeFlexibleSportArray(forKey: .preferredSports)
        sportLevels = try container.decodeFlexibleIntDictionary(forKey: .sportLevels)
        preferredPlayFormat = try container.decodeIfPresent(PlayFormat.self, forKey: .preferredPlayFormat) ?? .both
        preferredSurface = try container.decodeIfPresent(Surface.self, forKey: .preferredSurface) ?? .any
        searchRadiusKm = try container.decodeIfPresent(Int.self, forKey: .searchRadiusKm) ?? 20
        isLookingForGame = try container.decodeIfPresent(Bool.self, forKey: .isLookingForGame) ?? true
        showOnMap = try container.decodeIfPresent(Bool.self, forKey: .showOnMap) ?? true
        availableDays = try container.decodeIfPresent([String].self, forKey: .availableDays) ?? []
        availableTimeRanges = try container.decodeIfPresent([String].self, forKey: .availableTimeRanges) ?? []
        availabilityByDay = try container.decodeFlexibleStringArrayDictionary(forKey: .availabilityByDay)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
    }
}

enum OnboardingMapVisibility {
    static func resolved(stored: Bool, draft: Bool, completed: Bool) -> Bool {
        completed ? stored : stored && draft
    }
}

/// Тело `POST /me/consents`. nil-поля не попадают в JSON — сервер их не меняет.
struct ConsentUpdate: Encodable {
    struct Profile: Encodable {
        /// "visible" — согласие на показ анкеты, "hidden" — отказ или отзыв.
        let decision: String
        var fullName: String?
        var visibleToGuests: Bool?
        var showsBio: Bool?
        var showsPhotos: Bool?
        var showsVideos: Bool?
        var showsSearches: Bool?
        var showOnMap: Bool?
    }

    let source = "ios"
    var acceptAgreementVersion: String?
    var profile: Profile?
    var analytics: Bool?
}

/// Состояние отдельных согласий из `GET /me` (`user.consents`).
struct ConsentState: Codable, Equatable {
    /// legacy — аккаунт старше раздельных согласий, виден как раньше до ответа;
    /// pending — ещё не отвечал; visible / hidden — ответ дан.
    var profileVisibility: String
    var visibleToGuests: Bool
    var showsBio: Bool
    var showsPhotos: Bool
    var showsVideos: Bool
    var showsSearches: Bool
    var analytics: Bool
    var fullName: String?
    var termsUpdateRequired: Bool
    var reviewRequired: Bool

    var isLegacy: Bool { profileVisibility == "legacy" }
    var isVisible: Bool { profileVisibility == "visible" || profileVisibility == "legacy" }

    init(
        profileVisibility: String = "pending",
        visibleToGuests: Bool = false,
        showsBio: Bool = false,
        showsPhotos: Bool = false,
        showsVideos: Bool = false,
        showsSearches: Bool = false,
        analytics: Bool = false,
        fullName: String? = nil,
        termsUpdateRequired: Bool = false,
        reviewRequired: Bool = false
    ) {
        self.profileVisibility = profileVisibility
        self.visibleToGuests = visibleToGuests
        self.showsBio = showsBio
        self.showsPhotos = showsPhotos
        self.showsVideos = showsVideos
        self.showsSearches = showsSearches
        self.analytics = analytics
        self.fullName = fullName
        self.termsUpdateRequired = termsUpdateRequired
        self.reviewRequired = reviewRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileVisibility = try container.decodeIfPresent(String.self, forKey: .profileVisibility) ?? "legacy"
        visibleToGuests = try container.decodeIfPresent(Bool.self, forKey: .visibleToGuests) ?? false
        showsBio = try container.decodeIfPresent(Bool.self, forKey: .showsBio) ?? false
        showsPhotos = try container.decodeIfPresent(Bool.self, forKey: .showsPhotos) ?? false
        showsVideos = try container.decodeIfPresent(Bool.self, forKey: .showsVideos) ?? false
        showsSearches = try container.decodeIfPresent(Bool.self, forKey: .showsSearches) ?? false
        analytics = try container.decodeIfPresent(Bool.self, forKey: .analytics) ?? false
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        termsUpdateRequired = try container.decodeIfPresent(Bool.self, forKey: .termsUpdateRequired) ?? false
        reviewRequired = try container.decodeIfPresent(Bool.self, forKey: .reviewRequired) ?? false
    }
}

struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String?
    var name: String?
    var age: Int?
    var gender: Gender?
    var city: String?
    var location: GeoPlace?
    var coverage: LocationCoverage
    var locationSource: LocationSource?
    var district: String?
    var preferredDistricts: [String]
    var bio: String?
    var avatarUrl: String?
    var profilePhotoUrls: [String]
    var profileVideoUrls: [String]
    /// Порядок фото и видео в карточке; пустой — прежний «фото, потом видео».
    var profileMediaOrder: [String]
    var tennisLevel: Int?
    var preferredSports: [Sport]
    var sportLevels: [String: Int]
    var preferredPlayFormat: PlayFormat
    var preferredSurface: Surface
    var availableDays: [String]
    var availableTimeRanges: [String]
    var availabilityByDay: [String: [String]]
    var isLookingForGame: Bool
    var showOnMap: Bool
    var searchRadiusKm: Int
    var onboardingCompleted: Bool
    var isVerified: Bool
    var notificationMatches: Bool
    var notificationMessages: Bool
    var notificationGames: Bool
    var notificationSound: Bool
    var localeOverride: String?
    /// Нет у ответов старого сервера — тогда экран согласий не показывается.
    var consents: ConsentState?

    var isOnboardingComplete: Bool {
        OnboardingRequirements.isComplete(
            completed: onboardingCompleted,
            hasProfileBasics: OnboardingRequirements.hasProfileBasics(name: name, age: age, hasSports: !preferredSports.isEmpty),
            hasSelectedCity: OnboardingRequirements.hasSelectedCity(city: city, locationPlaceID: location?.id, locationCity: location?.city)
        )
    }

    init(
        id: String,
        email: String? = nil,
        name: String? = nil,
        age: Int? = nil,
        gender: Gender? = nil,
        city: String? = nil,
        location: GeoPlace? = nil,
        coverage: LocationCoverage = .unavailable,
        locationSource: LocationSource? = nil,
        district: String? = nil,
        preferredDistricts: [String] = [],
        bio: String? = nil,
        avatarUrl: String? = nil,
        profilePhotoUrls: [String] = [],
        profileVideoUrls: [String] = [],
        profileMediaOrder: [String] = [],
        tennisLevel: Int? = nil,
        preferredSports: [Sport] = [],
        sportLevels: [String: Int] = [:],
        preferredPlayFormat: PlayFormat = .both,
        preferredSurface: Surface = .any,
        availableDays: [String] = [],
        availableTimeRanges: [String] = [],
        availabilityByDay: [String: [String]] = [:],
        isLookingForGame: Bool = true,
        showOnMap: Bool = false,
        searchRadiusKm: Int = 20,
        onboardingCompleted: Bool = false,
        isVerified: Bool = false,
        notificationMatches: Bool = true,
        notificationMessages: Bool = true,
        notificationGames: Bool = true,
        notificationSound: Bool = true,
        localeOverride: String? = nil,
        consents: ConsentState? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.age = age
        self.gender = gender
        self.city = city
        self.location = location
        self.coverage = location?.coverage ?? coverage
        self.locationSource = locationSource
        self.district = district
        self.preferredDistricts = preferredDistricts
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.profilePhotoUrls = profilePhotoUrls
        self.profileVideoUrls = profileVideoUrls
        self.profileMediaOrder = profileMediaOrder
        self.tennisLevel = tennisLevel
        self.preferredSports = preferredSports
        self.sportLevels = sportLevels
        self.preferredPlayFormat = preferredPlayFormat
        self.preferredSurface = preferredSurface
        self.availableDays = availableDays
        self.availableTimeRanges = availableTimeRanges
        self.availabilityByDay = availabilityByDay
        self.isLookingForGame = isLookingForGame
        self.showOnMap = showOnMap
        self.searchRadiusKm = searchRadiusKm
        self.onboardingCompleted = onboardingCompleted
        self.isVerified = isVerified
        self.notificationMatches = notificationMatches
        self.notificationMessages = notificationMessages
        self.notificationGames = notificationGames
        self.notificationSound = notificationSound
        self.localeOverride = localeOverride
        self.consents = consents
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case age
        case gender
        case city
        case location
        case coverage
        case locationSource
        case district
        case preferredDistricts
        case bio
        case avatarUrl
        case profilePhotoUrls
        case profileVideoUrls
        case profileMediaOrder
        case tennisLevel
        case preferredSports
        case sportLevels
        case preferredPlayFormat
        case preferredSurface
        case availableDays
        case availableTimeRanges
        case availabilityByDay
        case isLookingForGame
        case showOnMap
        case searchRadiusKm
        case onboardingCompleted
        case isVerified
        case notificationMatches
        case notificationMessages
        case notificationGames
        case notificationSound
        case localeOverride
        case consents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        location = try container.decodeIfPresent(GeoPlace.self, forKey: .location)
        coverage = try container.decodeIfPresent(LocationCoverage.self, forKey: .coverage)
            ?? location?.coverage
            ?? .unavailable
        locationSource = try container.decodeIfPresent(LocationSource.self, forKey: .locationSource)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        profilePhotoUrls = try container.decodeIfPresent([String].self, forKey: .profilePhotoUrls) ?? []
        profileVideoUrls = try container.decodeIfPresent([String].self, forKey: .profileVideoUrls) ?? []
        profileMediaOrder = try container.decodeIfPresent([String].self, forKey: .profileMediaOrder) ?? []
        tennisLevel = try container.decodeIfPresent(Int.self, forKey: .tennisLevel)
        preferredSports = try container.decodeFlexibleSportArray(forKey: .preferredSports)
        sportLevels = try container.decodeFlexibleIntDictionary(forKey: .sportLevels)
        preferredPlayFormat = try container.decodeIfPresent(PlayFormat.self, forKey: .preferredPlayFormat) ?? .both
        preferredSurface = try container.decodeIfPresent(Surface.self, forKey: .preferredSurface) ?? .any
        availableDays = try container.decodeIfPresent([String].self, forKey: .availableDays) ?? []
        availableTimeRanges = try container.decodeIfPresent([String].self, forKey: .availableTimeRanges) ?? []
        availabilityByDay = try container.decodeFlexibleStringArrayDictionary(forKey: .availabilityByDay)
        isLookingForGame = try container.decodeIfPresent(Bool.self, forKey: .isLookingForGame) ?? true
        showOnMap = try container.decodeIfPresent(Bool.self, forKey: .showOnMap) ?? false
        searchRadiusKm = try container.decodeIfPresent(Int.self, forKey: .searchRadiusKm) ?? 20
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        notificationMatches = try container.decodeIfPresent(Bool.self, forKey: .notificationMatches) ?? true
        notificationMessages = try container.decodeIfPresent(Bool.self, forKey: .notificationMessages) ?? true
        notificationGames = try container.decodeIfPresent(Bool.self, forKey: .notificationGames) ?? true
        notificationSound = try container.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? true
        localeOverride = try container.decodeIfPresent(String.self, forKey: .localeOverride)
        consents = try container.decodeIfPresent(ConsentState.self, forKey: .consents)
    }
}

struct NearbyResult: Codable {
    let originCity: String
    let radiusKm: Double
    let distanceKm: Double

    var areaLabel: String {
        L10n.string("Within \(Int(radiusKm)) km of \(originCity)", "В радиусе \(Int(radiusKm)) км от \(originCity)")
    }

    var distanceLabel: String {
        let value = String(format: "%.1f", distanceKm)
        return L10n.string("\(value) km in a straight line", "\(value) км по прямой")
    }
}

/// Server-authoritative coarse areas. Never reconstruct these from a home district or device location.
struct DiscoverMapArea: Codable, Identifiable, Equatable {
    let id: String
    let cityId: String
    let cityName: String
    let kind: String
    let districtId: String?
    let label: String
    let latitude: Double
    let longitude: Double

    var mapID: String { "\(cityId)::\(id)" }

    var isValid: Bool {
        !id.isEmpty && !cityId.isEmpty && !cityName.isEmpty && !label.isEmpty
            && (kind == "city" || (kind == "district" && districtId?.isEmpty == false))
            && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct DiscoverUser: Codable, Identifiable {
    let id: String
    let showOnMap: Bool
    let mapAreas: [DiscoverMapArea]
    let name: String?
    let age: Int?
    let city: String?
    let district: String?
    let districtLabel: String?
    let preferredDistricts: [String]
    let bio: String?
    let avatarUrl: String?
    let profilePhotoUrls: [String]
    let profileVideoUrls: [String]
    let profileMediaOrder: [String]
    let lastActiveAt: String?
    let tennisLevel: Int?
    let preferredSports: [Sport]
    let sportLevels: [String: Int]
    let preferredPlayFormat: PlayFormat
    let preferredSurface: Surface
    let availableDays: [String]
    let availableTimeRanges: [String]
    let distanceLabel: String
    var nearby: NearbyResult? = nil
    let score: Double?
    let explainabilityReasons: [String]
    let gameSearches: [GameSearch]

    enum CodingKeys: String, CodingKey {
        case id
        case showOnMap
        case mapAreas
        case name
        case age
        case city
        case district
        case districtLabel
        case preferredDistricts
        case bio
        case avatarUrl
        case profilePhotoUrls
        case profileVideoUrls
        case profileMediaOrder
        case lastActiveAt
        case tennisLevel
        case preferredSports
        case sportLevels
        case preferredPlayFormat
        case preferredSurface
        case availableDays
        case availableTimeRanges
        case distanceLabel
        case nearby
        case score
        case explainabilityReasons
        case gameSearches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        showOnMap = try container.decodeIfPresent(Bool.self, forKey: .showOnMap) ?? false
        mapAreas = showOnMap ? (try container.decodeIfPresent([DiscoverMapArea].self, forKey: .mapAreas) ?? []) : []
        name = try container.decodeIfPresent(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        districtLabel = try container.decodeIfPresent(String.self, forKey: .districtLabel)
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        profilePhotoUrls = try container.decodeIfPresent([String].self, forKey: .profilePhotoUrls) ?? []
        profileVideoUrls = try container.decodeIfPresent([String].self, forKey: .profileVideoUrls) ?? []
        profileMediaOrder = try container.decodeIfPresent([String].self, forKey: .profileMediaOrder) ?? []
        lastActiveAt = try container.decodeIfPresent(String.self, forKey: .lastActiveAt)
        tennisLevel = try container.decodeIfPresent(Int.self, forKey: .tennisLevel)
        preferredSports = try container.decodeFlexibleSportArray(forKey: .preferredSports)
        sportLevels = try container.decodeFlexibleIntDictionary(forKey: .sportLevels)
        preferredPlayFormat = try container.decodeIfPresent(PlayFormat.self, forKey: .preferredPlayFormat) ?? .both
        preferredSurface = try container.decodeIfPresent(Surface.self, forKey: .preferredSurface) ?? .any
        availableDays = try container.decodeIfPresent([String].self, forKey: .availableDays) ?? []
        availableTimeRanges = try container.decodeIfPresent([String].self, forKey: .availableTimeRanges) ?? []
        distanceLabel = try container.decodeIfPresent(String.self, forKey: .distanceLabel) ?? L10n.string("Nearby", "Рядом")
        nearby = try container.decodeIfPresent(NearbyResult.self, forKey: .nearby)
        score = try container.decodeFlexibleDoubleIfPresent(forKey: .score)
        explainabilityReasons = try container.decodeIfPresent([String].self, forKey: .explainabilityReasons) ?? []
        gameSearches = try container.decodeIfPresent([GameSearch].self, forKey: .gameSearches) ?? []
    }
}

extension DiscoverUser {
    init(profile: UserProfile) {
        id = profile.id
        showOnMap = profile.showOnMap
        mapAreas = []
        name = profile.name
        age = profile.age
        city = profile.city
        district = profile.district
        districtLabel = localizedDistrictName(profile.district)
        preferredDistricts = profile.preferredDistricts
        bio = profile.bio
        avatarUrl = profile.avatarUrl
        profilePhotoUrls = profile.profilePhotoUrls
        profileVideoUrls = profile.profileVideoUrls
        profileMediaOrder = profile.profileMediaOrder
        lastActiveAt = nil
        tennisLevel = profile.tennisLevel
        preferredSports = profile.preferredSports
        sportLevels = profile.sportLevels
        preferredPlayFormat = profile.preferredPlayFormat
        preferredSurface = profile.preferredSurface
        availableDays = profile.availableDays
        availableTimeRanges = profile.availableTimeRanges
        distanceLabel = localizedDistrictName(profile.district) ?? profile.city ?? L10n.string("Location not specified", "Локация не указана")
        score = nil
        explainabilityReasons = []
        gameSearches = []
    }

    var lastActiveDate: Date? {
        lastActiveAt?.parsedISODateValue()
    }

    var isOnline: Bool {
        guard let lastActiveDate else {
            return false
        }

        return Date().timeIntervalSince(lastActiveDate) <= 5 * 60
    }

    var presenceLabel: String {
        guard let lastActiveDate else {
            return L10n.string("Active recently", "Был недавно")
        }

        if isOnline {
            return L10n.string("Online", "Онлайн")
        }

        let minutes = Int(Date().timeIntervalSince(lastActiveDate) / 60)
        if minutes < 60 {
            return L10n.string("Active \(max(minutes, 1)) min ago", "Был \(max(minutes, 1)) мин назад")
        }

        if Calendar.current.isDateInToday(lastActiveDate) {
            return L10n.string("Active at \(lastActiveDate.formattedHourMinute())", "Был \(lastActiveDate.formattedHourMinute())")
        }

        let day = CachedDateFormatters.display(template: "d MMM").string(from: lastActiveDate)
        return L10n.string("Active \(day)", "Был \(day)")
    }
}

struct MatchSummary: Codable, Identifiable {
    let id: String
    let status: String
    let createdAt: String
    let otherUser: DiscoverUser
    let lastMessage: ChatMessage?
    let latestGameRequest: MatchGameRequest?
}

struct ChatMessage: Codable, Identifiable, ChatReceiptMessage {
    let id: String
    let senderUserId: String
    let gameRequestId: String?
    let text: String
    let createdAt: String
    let senderUser: ChatSender?
    let attachments: [ChatMediaAttachment]
    var receipt: ChatReceipt?

    init(
        id: String,
        senderUserId: String,
        gameRequestId: String? = nil,
        text: String,
        createdAt: String,
        senderUser: ChatSender?,
        attachments: [ChatMediaAttachment] = [],
        receipt: ChatReceipt? = nil
    ) {
        self.id = id
        self.senderUserId = senderUserId
        self.gameRequestId = gameRequestId
        self.text = text
        self.createdAt = createdAt
        self.senderUser = senderUser
        self.attachments = attachments
        self.receipt = receipt
    }

    private enum CodingKeys: String, CodingKey {
        case id, senderUserId, gameRequestId, text, createdAt, senderUser, attachments, receipt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        senderUserId = try container.decode(String.self, forKey: .senderUserId)
        gameRequestId = try container.decodeIfPresent(String.self, forKey: .gameRequestId)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decode(String.self, forKey: .createdAt)
        senderUser = try container.decodeIfPresent(ChatSender.self, forKey: .senderUser)
        attachments = try container.decodeIfPresent([ChatMediaAttachment].self, forKey: .attachments) ?? []
        receipt = try container.decodeIfPresent(ChatReceipt.self, forKey: .receipt)
    }
}

struct ChatMediaAttachment: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let url: String
    let mimeType: String
    let byteSize: Int
    let position: Int
}

struct ChatSender: Codable {
    let id: String?
    let name: String?
    let avatarUrl: String?
}

struct SearchResponse: Codable, Identifiable {
    let id: String
    let status: String
    let responderUser: DiscoverUser
    let matchId: String?
}

struct SearchResponseUpdateResult: Codable {
    let response: SearchResponse
    let matchId: String?
    let gameRequestId: String?
    let regularPairId: String?
    let gameSearch: SearchStatusUpdate?
}

struct SearchStatusUpdate: Codable {
    let id: String
    let status: String
    let isActive: Bool?
}

struct SearchLobbyMessage: Codable, Identifiable, ChatReceiptMessage {
    let id: String
    let senderUserId: String
    let text: String
    let createdAt: String
    let senderUser: ChatSender?
    let attachments: [ChatMediaAttachment]
    var receipt: ChatReceipt?

    init(
        id: String,
        senderUserId: String,
        text: String,
        createdAt: String,
        senderUser: ChatSender?,
        attachments: [ChatMediaAttachment] = [],
        receipt: ChatReceipt? = nil
    ) {
        self.id = id
        self.senderUserId = senderUserId
        self.text = text
        self.createdAt = createdAt
        self.senderUser = senderUser
        self.attachments = attachments
        self.receipt = receipt
    }

    private enum CodingKeys: String, CodingKey {
        case id, senderUserId, text, createdAt, senderUser, attachments, receipt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        senderUserId = try container.decode(String.self, forKey: .senderUserId)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decode(String.self, forKey: .createdAt)
        senderUser = try container.decodeIfPresent(ChatSender.self, forKey: .senderUser)
        attachments = try container.decodeIfPresent([ChatMediaAttachment].self, forKey: .attachments) ?? []
        receipt = try container.decodeIfPresent(ChatReceipt.self, forKey: .receipt)
    }
}

struct SearchLobbySummary: Codable {
    let gameSearch: SearchLobbyGameSearch
}

struct SearchSlotProposalVote: Codable, Identifiable {
    let id: String
    let userId: String
    let createdAt: String
}

struct SearchSlotProposalOption: Codable, Identifiable {
    let id: String
    let scheduledAt: String
    let durationMinutes: Int?
    let proposedCourt: Court?
    let votes: [SearchSlotProposalVote]

    var voteCount: Int {
        votes.count
    }
}

struct SearchSlotProposalSummary: Codable, Identifiable {
    let id: String
    let comment: String?
    let status: String
    let createdAt: String
    let options: [SearchSlotProposalOption]

    func selectedOptionIDs(for userId: String?) -> Set<String> {
        guard let userId else {
            return []
        }

        return Set(
            options.compactMap { option in
                option.votes.contains(where: { $0.userId == userId }) ? option.id : nil
            }
        )
    }
}

struct SearchLobbyGameSearch: Codable, Identifiable {
    let id: String
    let createdByUserId: String
    let createdByUser: DiscoverUser?
    let searchType: SearchType
    let status: String
    let isActive: Bool
    let sport: Sport
    let format: PlayFormat
    let preferredDistricts: [String]
    let preferredDays: [String]
    let preferredTimeRanges: [String]
    let hotStartsAt: String?
    let durationMinutes: Int?
    let playersNeeded: Int
    let desiredLevelMin: Int?
    let desiredLevelMax: Int?
    let comment: String?
    let scheduledAt: String?
    let scheduledDurationMinutes: Int?
    let preferredCourt: Court?
    let scheduledCourt: Court?
    let activeSlotProposal: SearchSlotProposalSummary?
    let responses: [SearchResponse]
    var messages: [SearchLobbyMessage]

    var preferredDistrictsLabel: String {
        let names = preferredDistricts.compactMap(localizedDistrictName)
        return names.isEmpty ? "Любой район" : names.joined(separator: ", ")
    }
}

extension SearchLobbyGameSearch {
    enum CodingKeys: String, CodingKey {
        case id
        case createdByUserId
        case createdByUser
        case searchType
        case status
        case isActive
        case sport
        case format
        case preferredDistricts
        case preferredDays
        case preferredTimeRanges
        case hotStartsAt
        case durationMinutes
        case playersNeeded
        case desiredLevelMin
        case desiredLevelMax
        case comment
        case scheduledAt
        case scheduledDurationMinutes
        case preferredCourt
        case scheduledCourt
        case activeSlotProposal
        case responses
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdByUserId = try container.decode(String.self, forKey: .createdByUserId)
        createdByUser = try container.decodeIfPresent(DiscoverUser.self, forKey: .createdByUser)
        searchType = try container.decodeIfPresent(SearchType.self, forKey: .searchType) ?? .regular
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        sport = try container.decodeIfPresent(Sport.self, forKey: .sport) ?? .tennis
        format = try container.decodeIfPresent(PlayFormat.self, forKey: .format) ?? .singles
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        preferredDays = try container.decodeIfPresent([String].self, forKey: .preferredDays) ?? []
        preferredTimeRanges = try container.decodeIfPresent([String].self, forKey: .preferredTimeRanges) ?? []
        hotStartsAt = try container.decodeIfPresent(String.self, forKey: .hotStartsAt)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        playersNeeded = try container.decodeIfPresent(Int.self, forKey: .playersNeeded) ?? 1
        desiredLevelMin = try container.decodeIfPresent(Int.self, forKey: .desiredLevelMin)
        desiredLevelMax = try container.decodeIfPresent(Int.self, forKey: .desiredLevelMax)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        scheduledAt = try container.decodeIfPresent(String.self, forKey: .scheduledAt)
        scheduledDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .scheduledDurationMinutes)
        preferredCourt = try container.decodeIfPresent(Court.self, forKey: .preferredCourt)
        scheduledCourt = try container.decodeIfPresent(Court.self, forKey: .scheduledCourt)
        activeSlotProposal = try container.decodeIfPresent(SearchSlotProposalSummary.self, forKey: .activeSlotProposal)
        responses = try container.decodeIfPresent([SearchResponse].self, forKey: .responses) ?? []
        messages = try container.decodeIfPresent([SearchLobbyMessage].self, forKey: .messages) ?? []
    }
}

struct SearchGameScheduleResult: Codable {
    let gameSearch: GameSearch
    let gameRequestId: String?
}

struct RegularPairSummary: Codable, Identifiable {
    let id: String
    let matchId: String
    let partnerUser: DiscoverUser
    let preferredCourt: Court?
    let preferredDays: [String]
    let preferredTimeRanges: [String]
    let comment: String?
    let occurrences: [RegularPairOccurrence]

    init(
        id: String,
        matchId: String,
        partnerUser: DiscoverUser,
        preferredCourt: Court?,
        preferredDays: [String] = [],
        preferredTimeRanges: [String] = [],
        comment: String? = nil,
        occurrences: [RegularPairOccurrence] = []
    ) {
        self.id = id
        self.matchId = matchId
        self.partnerUser = partnerUser
        self.preferredCourt = preferredCourt
        self.preferredDays = preferredDays
        self.preferredTimeRanges = preferredTimeRanges
        self.comment = comment
        self.occurrences = occurrences
    }

    enum CodingKeys: String, CodingKey {
        case id
        case matchId
        case partnerUser
        case preferredCourt
        case preferredDays
        case preferredTimeRanges
        case comment
        case occurrences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        matchId = try container.decode(String.self, forKey: .matchId)
        partnerUser = try container.decode(DiscoverUser.self, forKey: .partnerUser)
        preferredCourt = try container.decodeIfPresent(Court.self, forKey: .preferredCourt)
        preferredDays = try container.decodeIfPresent([String].self, forKey: .preferredDays) ?? []
        preferredTimeRanges = try container.decodeIfPresent([String].self, forKey: .preferredTimeRanges) ?? []
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        occurrences = try container.decodeIfPresent([RegularPairOccurrence].self, forKey: .occurrences) ?? []
    }
}

struct RegularPairOccurrence: Codable, Identifiable {
    let id: String
    let scheduledAt: String
    let scheduleAnchor: String?
    let durationMinutes: Int?
    let status: String
    let proposedCourt: Court?
    let confirmations: [RegularPairOccurrenceConfirmation]
}

struct RegularPairOccurrenceConfirmation: Codable, Identifiable {
    let id: String
    let user: DiscoverUser
    let status: String
}

struct MatchGameRequest: Codable, Identifiable {
    let id: String
    let matchId: String?
    let rootRequestId: String?
    let searchLobbyId: String?
    let sourceType: String?
    let regularPairId: String?
    let status: String
    let proposedDatetime: String
    let createdByUserId: String?
    let matchedUserId: String?
    let durationMinutes: Int?
    let comment: String?
    let outcome: String?
    let report: GameReport?
    let sport: Sport
    let format: PlayFormat
    let runningRoute: String?
    let runningRoutePoints: [RunningRoutePoint]
    let proposedCourt: Court?
    let createdByUser: ChatSender?
    let matchedUser: ChatSender?
    let participants: [DiscoverUser]
    let invitees: [GameRequestInvitee]

    enum CodingKeys: String, CodingKey {
        case id
        case matchId
        case rootRequestId
        case searchLobbyId
        case sourceType
        case regularPairId
        case status
        case proposedDatetime
        case createdByUserId
        case matchedUserId
        case durationMinutes
        case comment
        case outcome
        case report
        case sport
        case format
        case runningRoute
        case runningRoutePoints
        case proposedCourt
        case createdByUser
        case matchedUser
        case participants
        case invitees
    }

    init(
        id: String,
        matchId: String?,
        rootRequestId: String? = nil,
        searchLobbyId: String? = nil,
        sourceType: String? = nil,
        regularPairId: String? = nil,
        status: String,
        proposedDatetime: String,
        createdByUserId: String?,
        matchedUserId: String?,
        durationMinutes: Int?,
        comment: String?,
        outcome: String?,
        sport: Sport,
        format: PlayFormat,
        runningRoute: String? = nil,
        runningRoutePoints: [RunningRoutePoint] = [],
        proposedCourt: Court?,
        createdByUser: ChatSender?,
        matchedUser: ChatSender?,
        participants: [DiscoverUser] = [],
        invitees: [GameRequestInvitee] = [],
        report: GameReport? = nil
    ) {
        self.id = id
        self.matchId = matchId
        self.rootRequestId = rootRequestId
        self.searchLobbyId = searchLobbyId
        self.sourceType = sourceType
        self.regularPairId = regularPairId
        self.status = status
        self.proposedDatetime = proposedDatetime
        self.createdByUserId = createdByUserId
        self.matchedUserId = matchedUserId
        self.durationMinutes = durationMinutes
        self.comment = comment
        self.outcome = outcome
        self.report = report
        self.sport = sport
        self.format = format
        self.runningRoute = runningRoute
        self.runningRoutePoints = runningRoutePoints
        self.proposedCourt = proposedCourt
        self.createdByUser = createdByUser
        self.matchedUser = matchedUser
        self.participants = participants
        self.invitees = invitees
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        matchId = try container.decodeIfPresent(String.self, forKey: .matchId)
        rootRequestId = try container.decodeIfPresent(String.self, forKey: .rootRequestId)
        searchLobbyId = try container.decodeIfPresent(String.self, forKey: .searchLobbyId)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        regularPairId = try container.decodeIfPresent(String.self, forKey: .regularPairId)
        status = try container.decode(String.self, forKey: .status)
        proposedDatetime = try container.decode(String.self, forKey: .proposedDatetime)
        createdByUserId = try container.decodeIfPresent(String.self, forKey: .createdByUserId)
        matchedUserId = try container.decodeIfPresent(String.self, forKey: .matchedUserId)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        report = try container.decodeIfPresent(GameReport.self, forKey: .report)
        sport = try container.decodeIfPresent(Sport.self, forKey: .sport) ?? .tennis
        format = try container.decodeIfPresent(PlayFormat.self, forKey: .format) ?? .singles
        runningRoute = try container.decodeIfPresent(String.self, forKey: .runningRoute)
        runningRoutePoints = try container.decodeIfPresent([RunningRoutePoint].self, forKey: .runningRoutePoints) ?? []
        proposedCourt = try container.decodeIfPresent(Court.self, forKey: .proposedCourt)
        createdByUser = try container.decodeIfPresent(ChatSender.self, forKey: .createdByUser)
        matchedUser = try container.decodeIfPresent(ChatSender.self, forKey: .matchedUser)
        participants = try container.decodeIfPresent([DiscoverUser].self, forKey: .participants) ?? []
        invitees = try container.decodeIfPresent([GameRequestInvitee].self, forKey: .invitees) ?? []
    }

    var effectivePlayersNeeded: Int {
        max(participants.count - 1, 1)
    }

    var effectiveFormatTitle: String {
        sport.formatTitle(format: format, playersNeeded: effectivePlayersNeeded)
    }
}

struct GameReport: Codable, Identifiable {
    let id: String
    let gameRequestId: String
    let createdByUserId: String
    let comment: String?
    let visibility: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let createdByUser: DiscoverUser?
    let photos: [GameReportPhoto]
    let confirmations: [GameReportConfirmation]

    var photoUrls: [String] {
        photos.sorted { $0.position < $1.position }.map(\.url)
    }

    var confirmedCount: Int {
        confirmations.filter { $0.status.lowercased() == "confirmed" }.count
    }

    var statusTitle: String {
        switch status.lowercased() {
        case "confirmed":
            return L10n.string("Photo report saved", "Фотоотчёт сохранён")
        case "disputed":
            return L10n.string("Disputed", "Есть спор")
        default:
            return L10n.string("Photo report saved", "Фотоотчёт сохранён")
        }
    }
}

struct GameReportPhoto: Codable, Identifiable {
    let id: String
    let url: String
    let position: Int
}

struct GameReportConfirmation: Codable, Identifiable {
    let id: String
    let userId: String
    let status: String
    let user: DiscoverUser?
}

struct PersonalActivity: Codable, Identifiable {
    let id: String
    let userId: String
    let courtId: String
    let sport: Sport
    let scheduledAt: String
    let durationMinutes: Int?
    let comment: String?
    let status: String
    let reportComment: String?
    let createdAt: String?
    let updatedAt: String?
    let court: Court?
    let photos: [PersonalActivityPhoto]
    // Optional backing storage preserves decoding of photo-only responses from older servers.
    private var storedVideoUrls: [String]? = nil

    var videoUrls: [String] { storedVideoUrls ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, userId, courtId, sport, scheduledAt, durationMinutes, comment, status
        case reportComment, createdAt, updatedAt, court, photos
        case storedVideoUrls = "videoUrls"
    }

    init(id: String, userId: String, courtId: String, sport: Sport, scheduledAt: String,
         durationMinutes: Int?, comment: String?, status: String, reportComment: String?,
         createdAt: String?, updatedAt: String?, court: Court?, photos: [PersonalActivityPhoto],
         videoUrls: [String] = []) {
        self.id = id; self.userId = userId; self.courtId = courtId; self.sport = sport
        self.scheduledAt = scheduledAt; self.durationMinutes = durationMinutes; self.comment = comment
        self.status = status; self.reportComment = reportComment; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.court = court; self.photos = photos; self.storedVideoUrls = videoUrls
    }

    var scheduledDate: Date? {
        scheduledAt.parsedISODateValue()
    }

    var hasEnded: Bool {
        guard let scheduledDate else {
            return false
        }
        let duration = TimeInterval((durationMinutes ?? 60) * 60)
        return Date().timeIntervalSince(scheduledDate) >= duration
    }

    var isArchivedForTimeline: Bool {
        let rawStatus = status.lowercased()
        if rawStatus == "canceled" {
            return true
        }
        return false
    }

    var canComplete: Bool {
        status.lowercased() == "planned" && hasEnded
    }

    var photoUrls: [String] {
        photos.sorted { $0.position < $1.position }.map(\.url)
    }
}

struct PersonalActivityPhoto: Codable, Identifiable {
    let id: String
    let url: String
    let position: Int
}

struct PersonalActivityDraft {
    var courtId: String
    var sport: Sport
    var scheduledAt: Date
    var durationMinutes: Int?
    var comment: String
}

struct PersonalActivityUpdateDraft {
    var scheduledAt: Date?
    var durationMinutes: Int?
    var comment: String?
    var status: String?
    var reportComment: String?
    var photoUrls: [String]?
    var videoUrls: [String]? = nil
}

struct GameRequestInvitee: Codable, Identifiable {
    let id: String
    let matchId: String?
    let status: String
    let user: DiscoverUser
}

struct GameProposalDraft {
    var proposedCourtId: String?
    var proposedDatetime: Date
    var durationMinutes: Int?
    var levelRangeMin: Int?
    var levelRangeMax: Int?
    var sport: Sport
    var format: PlayFormat
    var comment: String
}

struct GameSearch: Codable, Identifiable {
    let id: String
    let createdByUserId: String?
    let inviteSlug: String?
    let status: String
    let searchType: SearchType
    let hotWindow: HotWindow?
    let hotStartsAt: String?
    let durationMinutes: Int?
    let hasCourtBooked: Bool
    let sport: Sport
    let selfLevel: Int?
    let selfLevelUnknown: Bool?
    let desiredLevelMin: Int?
    let desiredLevelMax: Int?
    let format: PlayFormat
    let playersNeeded: Int
    let preferredDays: [String]
    let preferredTimeRanges: [String]
    let comment: String?
    let isActive: Bool?
    let isExpired: Bool?
    let preferredCourt: Court?
    let customVenueTitle: String?
    let customVenueAddress: String?
    let runningRoute: String?
    let runningRoutePoints: [RunningRoutePoint]
    let preferredDistricts: [String]
    let activeSlotProposal: SearchSlotProposalSummary?
    let regularPair: RegularPairSummary?
    let responses: [SearchResponse]

    init(
        id: String,
        createdByUserId: String? = nil,
        inviteSlug: String? = nil,
        status: String,
        searchType: SearchType,
        hotWindow: HotWindow?,
        hotStartsAt: String?,
        durationMinutes: Int?,
        hasCourtBooked: Bool,
        sport: Sport,
        selfLevel: Int?,
        selfLevelUnknown: Bool?,
        desiredLevelMin: Int?,
        desiredLevelMax: Int?,
        format: PlayFormat,
        playersNeeded: Int,
        preferredDays: [String],
        preferredTimeRanges: [String],
        comment: String?,
        isActive: Bool?,
        isExpired: Bool?,
        preferredCourt: Court?,
        customVenueTitle: String? = nil,
        customVenueAddress: String? = nil,
        runningRoute: String? = nil,
        runningRoutePoints: [RunningRoutePoint] = [],
        preferredDistricts: [String] = [],
        activeSlotProposal: SearchSlotProposalSummary? = nil,
        regularPair: RegularPairSummary?,
        responses: [SearchResponse]
    ) {
        self.id = id
        self.createdByUserId = createdByUserId
        self.inviteSlug = inviteSlug
        self.status = status
        self.searchType = searchType
        self.hotWindow = hotWindow
        self.hotStartsAt = hotStartsAt
        self.durationMinutes = durationMinutes
        self.hasCourtBooked = hasCourtBooked
        self.sport = sport
        self.selfLevel = selfLevel
        self.selfLevelUnknown = selfLevelUnknown
        self.desiredLevelMin = desiredLevelMin
        self.desiredLevelMax = desiredLevelMax
        self.format = format
        self.playersNeeded = playersNeeded
        self.preferredDays = preferredDays
        self.preferredTimeRanges = preferredTimeRanges
        self.comment = comment
        self.isActive = isActive
        self.isExpired = isExpired
        self.preferredCourt = preferredCourt
        self.customVenueTitle = customVenueTitle
        self.customVenueAddress = customVenueAddress
        self.runningRoute = runningRoute
        self.runningRoutePoints = runningRoutePoints
        self.preferredDistricts = preferredDistricts
        self.activeSlotProposal = activeSlotProposal
        self.regularPair = regularPair
        self.responses = responses
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdByUserId
        case inviteSlug
        case status
        case searchType
        case hotWindow
        case hotStartsAt
        case durationMinutes
        case hasCourtBooked
        case sport
        case selfLevel
        case selfLevelUnknown
        case desiredLevelMin
        case desiredLevelMax
        case format
        case playersNeeded
        case preferredDays
        case preferredTimeRanges
        case comment
        case isActive
        case isExpired
        case preferredCourt
        case customVenueTitle
        case customVenueAddress
        case runningRoute
        case runningRoutePoints
        case preferredDistricts
        case activeSlotProposal
        case regularPair
        case responses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdByUserId = try container.decodeIfPresent(String.self, forKey: .createdByUserId)
        inviteSlug = try container.decodeIfPresent(String.self, forKey: .inviteSlug)
        status = try container.decode(String.self, forKey: .status)
        searchType = try container.decode(SearchType.self, forKey: .searchType)
        hotWindow = try container.decodeIfPresent(HotWindow.self, forKey: .hotWindow)
        hotStartsAt = try container.decodeIfPresent(String.self, forKey: .hotStartsAt)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        hasCourtBooked = try container.decodeIfPresent(Bool.self, forKey: .hasCourtBooked) ?? false
        sport = try container.decodeIfPresent(Sport.self, forKey: .sport) ?? .tennis
        selfLevel = try container.decodeIfPresent(Int.self, forKey: .selfLevel)
        selfLevelUnknown = try container.decodeIfPresent(Bool.self, forKey: .selfLevelUnknown)
        desiredLevelMin = try container.decodeIfPresent(Int.self, forKey: .desiredLevelMin)
        desiredLevelMax = try container.decodeIfPresent(Int.self, forKey: .desiredLevelMax)
        format = try container.decodeIfPresent(PlayFormat.self, forKey: .format) ?? .singles
        playersNeeded = try container.decodeIfPresent(Int.self, forKey: .playersNeeded) ?? 1
        preferredDays = try container.decodeIfPresent([String].self, forKey: .preferredDays) ?? []
        preferredTimeRanges = try container.decodeIfPresent([String].self, forKey: .preferredTimeRanges) ?? []
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
        isExpired = try container.decodeIfPresent(Bool.self, forKey: .isExpired)
        preferredCourt = try container.decodeIfPresent(Court.self, forKey: .preferredCourt)
        customVenueTitle = try container.decodeIfPresent(String.self, forKey: .customVenueTitle)
        customVenueAddress = try container.decodeIfPresent(String.self, forKey: .customVenueAddress)
        runningRoute = try container.decodeIfPresent(String.self, forKey: .runningRoute)
        runningRoutePoints = try container.decodeIfPresent([RunningRoutePoint].self, forKey: .runningRoutePoints) ?? []
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        activeSlotProposal = try container.decodeIfPresent(SearchSlotProposalSummary.self, forKey: .activeSlotProposal)
        regularPair = try container.decodeIfPresent(RegularPairSummary.self, forKey: .regularPair)
        responses = try container.decodeIfPresent([SearchResponse].self, forKey: .responses) ?? []
    }
}

struct RunningRoutePoint: Codable, Hashable, Identifiable {
    let lat: Double
    let lng: Double

    var id: String {
        "\(lat.rounded(toPlaces: 6)):\(lng.rounded(toPlaces: 6))"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    init(coordinate: CLLocationCoordinate2D) {
        lat = coordinate.latitude
        lng = coordinate.longitude
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension SearchResponse {
    func applying(responseUpdate result: SearchResponseUpdateResult) -> SearchResponse {
        guard id == result.response.id else {
            return self
        }

        return SearchResponse(
            id: result.response.id,
            status: result.response.status,
            responderUser: result.response.responderUser,
            matchId: result.response.matchId ?? result.matchId ?? matchId
        )
    }
}

extension Array where Element == GameSearch {
    func applying(responseUpdate result: SearchResponseUpdateResult) -> [GameSearch] {
        map { $0.applying(responseUpdate: result) }
    }
}

func isOwnedActiveHotSearchForAttention(_ search: GameSearch, currentUserId: String?) -> Bool {
    guard let currentUserId,
          search.createdByUserId == currentUserId,
          search.searchType == .hot,
          (search.isActive ?? true) else {
        return false
    }
    return ["active", "in_review"].contains(search.status.lowercased())
}

extension GameSearch {
    func applying(responseUpdate result: SearchResponseUpdateResult) -> GameSearch {
        guard responses.contains(where: { $0.id == result.response.id }) || result.gameSearch?.id == id else {
            return self
        }

        let nextResponses = responses.map { $0.applying(responseUpdate: result) }
        let nextStatus: String
        let nextIsActive: Bool?
        if let searchUpdate = result.gameSearch, searchUpdate.id == id {
            nextStatus = searchUpdate.status
            nextIsActive = searchUpdate.isActive ?? isActive
        } else {
            nextStatus = status
            nextIsActive = isActive
        }

        return GameSearch(
            id: id,
            createdByUserId: createdByUserId,
            inviteSlug: inviteSlug,
            status: nextStatus,
            searchType: searchType,
            hotWindow: hotWindow,
            hotStartsAt: hotStartsAt,
            durationMinutes: durationMinutes,
            hasCourtBooked: hasCourtBooked,
            sport: sport,
            selfLevel: selfLevel,
            selfLevelUnknown: selfLevelUnknown,
            desiredLevelMin: desiredLevelMin,
            desiredLevelMax: desiredLevelMax,
            format: format,
            playersNeeded: playersNeeded,
            preferredDays: preferredDays,
            preferredTimeRanges: preferredTimeRanges,
            comment: comment,
            isActive: nextIsActive,
            isExpired: isExpired,
            preferredCourt: preferredCourt,
            customVenueTitle: customVenueTitle,
            customVenueAddress: customVenueAddress,
            runningRoute: runningRoute,
            runningRoutePoints: runningRoutePoints,
            preferredDistricts: preferredDistricts,
            activeSlotProposal: activeSlotProposal,
            regularPair: regularPair,
            responses: nextResponses
        )
    }
}

extension SearchLobbyGameSearch {
    func applying(responseUpdate result: SearchResponseUpdateResult) -> SearchLobbyGameSearch {
        guard responses.contains(where: { $0.id == result.response.id }) || result.gameSearch?.id == id else {
            return self
        }

        let nextResponses = responses.map { $0.applying(responseUpdate: result) }
        let nextStatus: String
        let nextIsActive: Bool
        if let searchUpdate = result.gameSearch, searchUpdate.id == id {
            nextStatus = searchUpdate.status
            nextIsActive = searchUpdate.isActive ?? isActive
        } else {
            nextStatus = status
            nextIsActive = isActive
        }

        return SearchLobbyGameSearch(
            id: id,
            createdByUserId: createdByUserId,
            createdByUser: createdByUser,
            searchType: searchType,
            status: nextStatus,
            isActive: nextIsActive,
            sport: sport,
            format: format,
            preferredDistricts: preferredDistricts,
            preferredDays: preferredDays,
            preferredTimeRanges: preferredTimeRanges,
            hotStartsAt: hotStartsAt,
            durationMinutes: durationMinutes,
            playersNeeded: playersNeeded,
            desiredLevelMin: desiredLevelMin,
            desiredLevelMax: desiredLevelMax,
            comment: comment,
            scheduledAt: scheduledAt,
            scheduledDurationMinutes: scheduledDurationMinutes,
            preferredCourt: preferredCourt,
            scheduledCourt: scheduledCourt,
            activeSlotProposal: activeSlotProposal,
            responses: nextResponses,
            messages: messages
        )
    }
}

/// Клубы для экрана без карточек: ряд на каждый вид спорта из анкеты.
struct EmptyDeckSection: Codable, Identifiable {
    let sport: Sport
    let total: Int
    let courts: [EmptyDeckCourt]

    var id: String { sport.rawValue }
}

struct EmptyDeckCourt: Codable, Identifiable {
    var city: String? = nil
    var nearby: NearbyResult? = nil
    let id: String
    let name: String
    let distanceLabel: String?
    let activeSearchesCount: Int
    let memberCount: Int
    let searchers: [EmptyDeckSearcher]
}

struct EmptyDeckSearcher: Codable, Identifiable {
    let id: String
    let name: String?
    let avatarUrl: String?
}

struct EmptyDeckContent: Codable {
    let sections: [EmptyDeckSection]
    let invite: InviteSummary?
}

/// Личная ссылка-приглашение и её счётчики.
struct InviteSummary: Codable {
    let code: String?
    let url: String
    let visits: Int
    let registered: Int?
    let joined: Int
}

struct Court: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let city: String?
    let district: String?
    let locationLat: Double
    let locationLng: Double
    var nearby: NearbyResult? = nil
    let distanceLabel: String?
    let nearestMetroName: String?
    let metroNames: [String]
    let supportedSports: [Sport]?
    let phone: String?
    let workingHours: String?
    let yandexMapsUrl: String?
    let websiteUrl: String?
    let bookingUrl: String?
    let about: String?
    let amenities: [String]
    let messengerType: String?
    let messengerUrl: String?
    let photoUrl: String?
    let photoUrls: [String]
    let priceRange: String?
    let rating: Double?
    let isMember: Bool
    let memberCount: Int
    let members: [DiscoverUser]
    let activeSearchesCount: Int
    let activeSearchPlayersCount: Int
    let activeSearchPreviewUsers: [DiscoverUser]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: locationLat, longitude: locationLng)
    }

    var primaryPhotoUrl: String? {
        photoUrls.first ?? photoUrl
    }

    var metroDisplayName: String? {
        metroNames.isEmpty ? nil : metroNames.joined(separator: " · ")
    }

    var phoneURL: URL? {
        guard let normalizedPhone = Self.normalizedRussianPhone(phone) else {
            return nil
        }

        return URL(string: "tel:\(normalizedPhone)")
    }

    static func normalizedRussianPhone(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let separators = CharacterSet(charactersIn: "|;,\n/")
        let candidates = value.components(separatedBy: separators)

        for candidate in candidates {
            let digits = candidate.filter(\.isNumber)

            switch digits.count {
            case 10:
                return "+7\(digits)"
            case 11 where digits.first == "7":
                return "+\(digits)"
            case 11 where digits.first == "8":
                return "+7\(digits.dropFirst())"
            default:
                continue
            }
        }

        return nil
    }

    init(
        id: String,
        name: String,
        address: String,
        city: String? = nil,
        district: String?,
        locationLat: Double,
        locationLng: Double,
        distanceLabel: String?,
        nearestMetroName: String?,
        metroNames: [String] = [],
        supportedSports: [Sport]?,
        phone: String? = nil,
        workingHours: String? = nil,
        yandexMapsUrl: String? = nil,
        websiteUrl: String? = nil,
        bookingUrl: String? = nil,
        about: String? = nil,
        amenities: [String] = [],
        messengerType: String? = nil,
        messengerUrl: String? = nil,
        photoUrl: String? = nil,
        photoUrls: [String] = [],
        priceRange: String? = nil,
        rating: Double? = nil,
        isMember: Bool = false,
        memberCount: Int = 0,
        members: [DiscoverUser] = [],
        activeSearchesCount: Int = 0,
        activeSearchPlayersCount: Int = 0,
        activeSearchPreviewUsers: [DiscoverUser] = []
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.district = district
        self.locationLat = locationLat
        self.locationLng = locationLng
        self.distanceLabel = distanceLabel
        let normalizedMetroNames = Self.normalizedTextValues(metroNames + [nearestMetroName].compactMap { $0 }, limit: 8)
        self.nearestMetroName = nearestMetroName ?? normalizedMetroNames.first
        self.metroNames = normalizedMetroNames
        self.supportedSports = supportedSports
        self.phone = phone
        self.workingHours = workingHours
        self.yandexMapsUrl = yandexMapsUrl
        self.websiteUrl = websiteUrl
        self.bookingUrl = bookingUrl
        self.about = about
        self.amenities = Self.normalizedTextValues(amenities, limit: 12)
        self.messengerType = messengerType
        self.messengerUrl = messengerUrl
        self.photoUrl = photoUrl
        self.photoUrls = Self.normalizedPhotoUrls(photoUrls, fallback: photoUrl)
        self.priceRange = priceRange
        self.rating = rating
        self.isMember = isMember
        self.memberCount = memberCount
        self.members = members
        self.activeSearchesCount = activeSearchesCount
        self.activeSearchPlayersCount = activeSearchPlayersCount
        self.activeSearchPreviewUsers = activeSearchPreviewUsers
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case city
        case district
        case locationLat
        case locationLng
        case nearby
        case distanceLabel
        case nearestMetroName
        case metroNames
        case supportedSports
        case phone
        case workingHours
        case yandexMapsUrl
        case websiteUrl
        case bookingUrl
        case about
        case amenities
        case messengerType
        case messengerUrl
        case photoUrl
        case photoUrls
        case priceRange
        case rating
        case isMember
        case memberCount
        case members
        case activeSearchesCount
        case activeSearchPlayersCount
        case activeSearchPreviewUsers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        locationLat = try container.decode(Double.self, forKey: .locationLat)
        locationLng = try container.decode(Double.self, forKey: .locationLng)
        nearby = try container.decodeIfPresent(NearbyResult.self, forKey: .nearby)
        distanceLabel = try container.decodeIfPresent(String.self, forKey: .distanceLabel)
        let decodedNearestMetroName = try container.decodeIfPresent(String.self, forKey: .nearestMetroName)
        let decodedMetroNames = (try? container.decode([String].self, forKey: .metroNames)) ?? []
        let normalizedMetroNames = Self.normalizedTextValues(decodedMetroNames + [decodedNearestMetroName].compactMap { $0 }, limit: 8)
        nearestMetroName = decodedNearestMetroName ?? normalizedMetroNames.first
        metroNames = normalizedMetroNames
        supportedSports = try container.decodeFlexibleSportArrayIfPresent(forKey: .supportedSports)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        workingHours = try container.decodeIfPresent(String.self, forKey: .workingHours)
        yandexMapsUrl = try container.decodeIfPresent(String.self, forKey: .yandexMapsUrl)
        websiteUrl = try container.decodeIfPresent(String.self, forKey: .websiteUrl)
        bookingUrl = try container.decodeIfPresent(String.self, forKey: .bookingUrl)
        about = try container.decodeIfPresent(String.self, forKey: .about)
        amenities = Self.normalizedTextValues((try? container.decode([String].self, forKey: .amenities)) ?? [], limit: 12)
        messengerType = try container.decodeIfPresent(String.self, forKey: .messengerType)
        messengerUrl = try container.decodeIfPresent(String.self, forKey: .messengerUrl)
        let legacyPhotoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
        let decodedPhotoUrls = (try? container.decode([String].self, forKey: .photoUrls)) ?? []
        photoUrls = Self.normalizedPhotoUrls(decodedPhotoUrls, fallback: legacyPhotoUrl)
        photoUrl = legacyPhotoUrl ?? photoUrls.first
        priceRange = try container.decodeIfPresent(String.self, forKey: .priceRange)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        isMember = try container.decodeIfPresent(Bool.self, forKey: .isMember) ?? false
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        members = try container.decodeIfPresent([DiscoverUser].self, forKey: .members) ?? []
        activeSearchesCount = try container.decodeIfPresent(Int.self, forKey: .activeSearchesCount) ?? 0
        activeSearchPlayersCount = try container.decodeIfPresent(Int.self, forKey: .activeSearchPlayersCount) ?? 0
        activeSearchPreviewUsers = try container.decodeIfPresent([DiscoverUser].self, forKey: .activeSearchPreviewUsers) ?? []
    }

    private static func normalizedPhotoUrls(_ photoUrls: [String], fallback: String?) -> [String] {
        var result: [String] = []
        let candidates = [fallback].compactMap { $0 } + photoUrls

        for candidate in candidates {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !result.contains(normalized) else {
                continue
            }
            result.append(normalized)
            if result.count >= 8 {
                break
            }
        }

        return result
    }

    private static func normalizedTextValues(_ values: [String], limit: Int) -> [String] {
        var result: [String] = []

        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !result.contains(normalized) else {
                continue
            }
            result.append(normalized)
            if result.count >= limit {
                break
            }
        }

        return result
    }
}

struct AddressSuggestion: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let address: String
    let subtitle: String?
    let lat: Double?
    let lng: Double?
}

struct SearchDraft: Codable {
    var inviteSlug: String?
    var preferredCourtId: String?
    var customVenueTitle: String? = nil
    var customVenueAddress: String? = nil
    var runningRoute: String? = nil
    var runningRoutePoints: [RunningRoutePoint]? = nil
    var preferredDistricts: [String]
    var preferredDays: [String]
    var preferredTimeRanges: [String]
    var searchType: SearchType
    var hotWindow: HotWindow?
    var hotStartTime: String?
    var hotStartsAt: String? = nil
    var durationMinutes: Int?
    var hasCourtBooked: Bool
    var sport: Sport
    var selfLevel: Int?
    var selfLevelUnknown: Bool
    var desiredLevelMin: Int
    var desiredLevelMax: Int
    var format: PlayFormat
    var playersNeeded: Int
    var comment: String
}

enum AppNotificationType: String, Codable, CaseIterable {
    case new_match
    case new_message
    case incoming_like
    case search_response
    case application_result
    case hot_event
}

struct AppNotification: Codable, Identifiable {
    let id: String
    let type: AppNotificationType
    let createdAt: String
    let title: String
    let description: String
    let href: String
    let status: String?
}

struct RealtimeEvent: Codable, Identifiable {
    var id: String?
    let type: String
    let createdAt: String?
    let title: String?
    let body: String?
    let href: String?
    let matchId: String?
    let searchId: String?
    let messageId: String?
    let gameRequestId: String?
    let status: String?
}

extension Notification.Name {
    static let tennisRealtimeEventReceived = Notification.Name("TennisSearchRealtimeEventReceived")
    static let tennisNotificationRouteRequested = Notification.Name("TennisSearchNotificationRouteRequested")
}

struct ActivitySummary: Codable {
    let inboxBadgeCount: Int
    let incomingLikesCount: Int
    let hotBadgeCount: Int
    let discoverBadgeCount: Int
    let activeSearchesCount: Int
    let searchesBadgeCount: Int
    let notificationSound: Bool

    init(
        inboxBadgeCount: Int,
        incomingLikesCount: Int,
        hotBadgeCount: Int,
        discoverBadgeCount: Int,
        activeSearchesCount: Int = 0,
        searchesBadgeCount: Int = 0,
        notificationSound: Bool
    ) {
        self.inboxBadgeCount = inboxBadgeCount
        self.incomingLikesCount = incomingLikesCount
        self.hotBadgeCount = hotBadgeCount
        self.discoverBadgeCount = discoverBadgeCount
        self.activeSearchesCount = activeSearchesCount
        self.searchesBadgeCount = searchesBadgeCount
        self.notificationSound = notificationSound
    }

    private enum CodingKeys: String, CodingKey {
        case inboxBadgeCount
        case incomingLikesCount
        case hotBadgeCount
        case discoverBadgeCount
        case activeSearchesCount
        case searchesBadgeCount
        case notificationSound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inboxBadgeCount = try container.decodeIfPresent(Int.self, forKey: .inboxBadgeCount) ?? 0
        incomingLikesCount = try container.decodeIfPresent(Int.self, forKey: .incomingLikesCount) ?? 0
        hotBadgeCount = try container.decodeIfPresent(Int.self, forKey: .hotBadgeCount) ?? 0
        discoverBadgeCount = try container.decodeIfPresent(Int.self, forKey: .discoverBadgeCount) ?? 0
        activeSearchesCount = try container.decodeIfPresent(Int.self, forKey: .activeSearchesCount) ?? 0
        searchesBadgeCount = try container.decodeIfPresent(Int.self, forKey: .searchesBadgeCount) ?? 0
        notificationSound = try container.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? true
    }
}

struct AppStats: Codable {
    let registeredPlayersCount: Int
    let seekingPlayersCount: Int
}

struct AppVersionInfo: Codable {
    let latestVersion: String
    let minVersion: String
}

enum APNSEnvironment: String, Codable {
    case development
    case production
}

extension ActivitySummary {
    static let empty = ActivitySummary(
        inboxBadgeCount: 0,
        incomingLikesCount: 0,
        hotBadgeCount: 0,
        discoverBadgeCount: 0,
        activeSearchesCount: 0,
        searchesBadgeCount: 0,
        notificationSound: true
    )

    func removingHotEvents() -> ActivitySummary {
        ActivitySummary(
            inboxBadgeCount: inboxBadgeCount,
            incomingLikesCount: incomingLikesCount,
            hotBadgeCount: 0,
            discoverBadgeCount: max(discoverBadgeCount - hotBadgeCount, 0),
            activeSearchesCount: activeSearchesCount,
            searchesBadgeCount: searchesBadgeCount,
            notificationSound: notificationSound
        )
    }
}

extension DiscoverUser {
    var displayName: String {
        guard let name, !name.isEmpty else {
            return L10n.string("Player", "Игрок")
        }
        return name
    }

    var districtDisplayNames: [String] {
        let base = preferredDistricts.isEmpty ? [districtLabel ?? district].compactMap { $0 } : preferredDistricts
        return base
            .compactMap(localizedDistrictName)
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) {
                    result.append(item)
                }
            }
    }

    var districtDisplaySummary: String {
        let values = districtDisplayNames
        return values.isEmpty ? L10n.string("Areas not specified", "Районы не указаны") : values.prefix(3).joined(separator: ", ")
    }

    var sportChips: [String] {
        preferredSports.prefix(2).map { sport in
            let level = sportLevels[sport.rawValue] ?? tennisLevel ?? 5
            return "\(sport.title) \(level)"
        }
    }

    var profilePhotoPaths: [String] {
        uniqueNonEmptyMediaPaths(profilePhotoUrls + [avatarUrl].compactMap { $0 })
    }

    var profileHeroImagePath: String? {
        profilePhotoPaths.first
    }

    var playerCardMediaItems: [PlayerMediaItem] {
        orderedPlayerMediaItems(
            profilePhotoPaths.map { PlayerMediaItem(kind: .photo, path: $0) }
                + uniqueNonEmptyMediaPaths(profileVideoUrls).map { PlayerMediaItem(kind: .video, path: $0) },
            order: profileMediaOrder
        )
    }
}

extension UserProfile {
    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return email ?? L10n.string("Profile", "Профиль")
    }

    var profilePhotoPaths: [String] {
        uniqueNonEmptyMediaPaths(profilePhotoUrls + [avatarUrl].compactMap { $0 })
    }

    var profileHeroImagePath: String? {
        profilePhotoPaths.first
    }

    var playerCardMediaItems: [PlayerMediaItem] {
        orderedPlayerMediaItems(
            profilePhotoPaths.map { PlayerMediaItem(kind: .photo, path: $0) }
                + uniqueNonEmptyMediaPaths(profileVideoUrls).map { PlayerMediaItem(kind: .video, path: $0) },
            order: profileMediaOrder
        )
    }
}

/// Порядок из профиля поверх прежнего «фото, потом видео». Чего в порядке нет —
/// новое медиа или профиль, сохранённый старой сборкой, — идёт следом как раньше.
private func orderedPlayerMediaItems(_ items: [PlayerMediaItem], order: [String]) -> [PlayerMediaItem] {
    guard !order.isEmpty else { return items }
    let ordered = uniqueNonEmptyMediaPaths(order).compactMap { path in
        items.first { $0.path == path }
    }
    let orderedPaths = Set(ordered.map(\.path))
    return ordered + items.filter { !orderedPaths.contains($0.path) }
}

private func uniqueNonEmptyMediaPaths(_ paths: [String]) -> [String] {
    paths.reduce(into: [String]()) { result, path in
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
        result.append(trimmed)
    }
}

extension GuestOnboardingDraft {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.string("Your profile", "Твой профиль") : trimmed
    }
}

extension GameSearch {
    var scheduleLine: String {
        if searchType == .hot {
            let day = hotWindow?.title
            let time = hotStartsAt?.formattedDateTime()
            return [day, time].compactMap { $0 }.joined(separator: ", ")
        }

        let days = preferredDays.prefix(2).map { DayOfWeek(rawValue: $0)?.shortTitle ?? $0.capitalized }
        let times = preferredTimeRanges.prefix(2).map(localizedTimePreferenceTitle)
        return (days + times).joined(separator: " • ")
    }

    var statusLabel: String {
        switch status.lowercased() {
        case "active":
            return L10n.string("Recruiting", "Идет набор")
        case "in_review":
            return L10n.string("Awaiting decision", "Ожидает решения")
        case "matched":
            return L10n.string("Players found", "Игроки найдены")
        case "closed":
            return L10n.string("Closed", "Закрыт")
        default:
            return status
        }
    }
}

extension MatchGameRequest {
    var participantCount: Int {
        var seen = Set<String>()
        return participants.reduce(into: 0) { count, participant in
            if seen.contains(participant.id) {
                return
            }
            seen.insert(participant.id)
            count += 1
        }
    }

    func visibleParticipants(currentUserId: String?) -> [DiscoverUser] {
        let filtered = participants.filter { participant in
            guard let currentUserId else {
                return true
            }
            return participant.id != currentUserId
        }

        var seen = Set<String>()
        return filtered.filter { participant in
            if seen.contains(participant.id) {
                return false
            }
            seen.insert(participant.id)
            return true
        }
    }

    func upcomingDisplayName(currentUserId: String?) -> String {
        let people = visibleParticipants(currentUserId: currentUserId)

        if people.count >= 3, let first = people.first {
            return L10n.string("\(first.displayName) and \(people.count - 1) more", "\(first.displayName) и еще \(people.count - 1)")
        }

        if people.count == 2 {
            return people.map(\.displayName).joined(separator: L10n.string(" and ", " и "))
        }

        if let first = people.first {
            return first.displayName
        }

        return otherUser(currentUserId: currentUserId)?.name ?? L10n.string("Player", "Игрок")
    }

    func upcomingAvatarURL(currentUserId: String?) -> String? {
        visibleParticipants(currentUserId: currentUserId).first?.avatarUrl ?? otherUser(currentUserId: currentUserId)?.avatarUrl
    }

    func participantNamesLine(currentUserId: String?) -> String? {
        let names = visibleParticipants(currentUserId: currentUserId)
            .map(\.displayName)
            .filter { !$0.isEmpty }

        guard !names.isEmpty else {
            return nil
        }

        return names.joined(separator: ", ")
    }

    var isRegularOccurrence: Bool {
        sourceType == "regular_occurrence"
    }

    var proposedDate: Date? {
        proposedDatetime.parsedISODateValue()
    }

    func otherUser(currentUserId: String?) -> ChatSender? {
        guard let currentUserId else {
            return matchedUser ?? createdByUser
        }
        if createdByUserId == currentUserId {
            return matchedUser
        }
        return createdByUser
    }

    func isPendingForRecipient(currentUserId: String?) -> Bool {
        guard status.lowercased() == "pending", let currentUserId else {
            return false
        }
        return matchedUserId == currentUserId
    }

    func canCancel(currentUserId: String?) -> Bool {
        guard let currentUserId else {
            return false
        }
        return createdByUserId == currentUserId || matchedUserId == currentUserId
    }

    var isArchivedForTimeline: Bool {
        let rawStatus = status.lowercased()
        if ["cancelled", "canceled", "declined", "rejected", "withdrawn"].contains(rawStatus) {
            return true
        }

        if needsOutcomeReview {
            return false
        }

        guard let proposedDate else {
            return false
        }

        let duration = TimeInterval((durationMinutes ?? 90) * 60)
        let postGameDisplayInterval: TimeInterval = 2 * 60 * 60
        return Date().timeIntervalSince(proposedDate) >= duration + postGameDisplayInterval
    }

    func hasEnded(referenceDate: Date = Date()) -> Bool {
        guard let proposedDate else {
            return false
        }

        let duration = TimeInterval((durationMinutes ?? 90) * 60)
        return referenceDate.timeIntervalSince(proposedDate) >= duration
    }

    var needsOutcomeReview: Bool {
        let rawStatus = status.lowercased()
        guard rawStatus == "accepted" || rawStatus == "approved" else {
            return false
        }
        return outcome == nil && hasEnded()
    }

    var canAddPhotoReport: Bool {
        let rawStatus = status.lowercased()
        guard rawStatus == "accepted" || rawStatus == "approved" else {
            return false
        }
        return report == nil && outcome != "not_played" && hasEnded()
    }

    var hasPhotoReport: Bool {
        report != nil
    }

    var outcomeLabel: String? {
        switch outcome {
        case "played":
            return L10n.string("Game played", "Игра прошла")
        case "not_played":
            return L10n.string("Not played", "Не сыграли")
        default:
            return nil
        }
    }

    var statusLabel: String {
        if let outcomeLabel {
            return outcomeLabel
        }

        let startDate = proposedDate
        let now = Date()
        let duration = TimeInterval((durationMinutes ?? 90) * 60)

        switch status.lowercased() {
        case "cancelled", "canceled", "declined", "rejected", "withdrawn":
            return L10n.string("Canceled", "Отменена")
        case "pending", "proposed":
            if matchedUserId != nil {
                return L10n.string("Awaiting confirmation", "Ждёт подтверждения")
            }
            if format == .doubles || format == .both {
                return L10n.string("Finding players", "Подбор игроков")
            }
            return L10n.string("Search", "Поиск")
        case "accepted", "approved":
            guard let startDate else {
                return L10n.string("Game confirmed", "Игра подтверждена")
            }

            let secondsUntilStart = startDate.timeIntervalSince(now)
            if secondsUntilStart <= 2 * 60 * 60, secondsUntilStart > 0 {
                return L10n.string("Starting soon", "Скоро начнется")
            }

            let secondsSinceStart = now.timeIntervalSince(startDate)
            if secondsSinceStart >= 0, secondsSinceStart <= 10 * 60 {
                return L10n.string("Game started", "Игра началась")
            }
            if secondsSinceStart > 10 * 60, secondsSinceStart < duration {
                return L10n.string("Game in progress", "Игра идет")
            }
            if secondsSinceStart >= duration {
                return L10n.string("Game ended", "Игра закончилась")
            }

            return L10n.string("Game confirmed", "Игра подтверждена")
        default:
            return L10n.string("Search", "Поиск")
        }
    }

    var nextStepLabel: String {
        let rawStatus = status.lowercased()

        if isRegularOccurrence, rawStatus == "accepted" || rawStatus == "approved" {
            return L10n.string("The game is confirmed. Open the regular pair to change the next time slot.", "Игра подтверждена. Если нужно поменять следующий слот, открой регулярную пару.")
        }

        switch rawStatus {
        case "pending", "proposed":
            if matchedUserId != nil {
                return L10n.string("Proposal sent. Waiting for the other player's confirmation.", "Предложение отправлено. Ждём подтверждение второго игрока.")
            }
            return L10n.string("Gather the players and turn this search into a scheduled game.", "Нужно собрать состав и перевести поиск в конкретную игру.")
        case "accepted", "approved":
            return L10n.string("The game is confirmed. Open the chat to finalize the remaining details.", "Игра подтверждена. Дальше открой чат и договорись только о последних нюансах.")
        case "declined", "rejected", "withdrawn", "canceled", "cancelled":
            return L10n.string("This arrangement is no longer active. Start a new one if you still want to play.", "Эта договоренность уже не активна. Если всё ещё хочешь сыграть, начни новую.")
        default:
            return L10n.string("Open the details and continue toward your next game.", "Открой детали и продолжай путь к следующей игре.")
        }
    }

    var statusTintColor: Color {
        switch statusLabel {
        case "Поиск", "Search":
            return Color(red: 0.34, green: 0.47, blue: 0.68)
        case "В процессе набора", "В процессе набора людей", "Подбор игроков", "Recruiting", "Finding players":
            return Color(red: 0.72, green: 0.48, blue: 0.18)
        case "В ожидании принятия", "Ждём подтверждение", "Игра назначается", "Ждёт подтверждения", "Awaiting decision", "Awaiting confirmation":
            return Color(red: 0.49, green: 0.45, blue: 0.78)
        case "Игрок найден", "Игроки найдены", "Игра подтверждена", "Игра прошла", "Player found", "Players found", "Game confirmed", "Game played":
            return Color(red: 0.16, green: 0.58, blue: 0.33)
        case "Скоро начнется", "Starting soon":
            return Color(red: 0.78, green: 0.52, blue: 0.18)
        case "Игра началась", "Игра идет", "Game started", "Game in progress":
            return Color(red: 0.17, green: 0.50, blue: 0.72)
        case "Игра закончилась", "Game ended":
            return Color(red: 0.33, green: 0.33, blue: 0.38)
        case "Не сыграли", "Not played":
            return Color(red: 0.72, green: 0.22, blue: 0.20)
        case "Подтверждена", "Confirmed":
            return Color(red: 0.16, green: 0.58, blue: 0.33)
        case "Отменена", "Canceled":
            return Color(red: 0.72, green: 0.22, blue: 0.20)
        default:
            return AppTheme.court
        }
    }

    var statusSurfaceColor: Color {
        switch statusLabel {
        case "Поиск", "Search":
            return Color(red: 0.88, green: 0.92, blue: 0.98)
        case "В процессе набора", "В процессе набора людей", "Подбор игроков", "Recruiting", "Finding players":
            return Color(red: 0.98, green: 0.93, blue: 0.84)
        case "В ожидании принятия", "Ждём подтверждение", "Игра назначается", "Ждёт подтверждения", "Awaiting decision", "Awaiting confirmation":
            return Color(red: 0.91, green: 0.90, blue: 0.99)
        case "Игрок найден", "Игроки найдены", "Игра подтверждена", "Игра прошла", "Player found", "Players found", "Game confirmed", "Game played":
            return Color(red: 0.86, green: 0.95, blue: 0.89)
        case "Скоро начнется", "Starting soon":
            return Color(red: 0.99, green: 0.94, blue: 0.83)
        case "Игра началась", "Игра идет", "Game started", "Game in progress":
            return Color(red: 0.86, green: 0.93, blue: 0.98)
        case "Игра закончилась", "Game ended":
            return Color(red: 0.90, green: 0.90, blue: 0.92)
        case "Не сыграли", "Not played":
            return Color(red: 0.96, green: 0.88, blue: 0.88)
        case "Подтверждена", "Confirmed":
            return Color(red: 0.86, green: 0.95, blue: 0.89)
        case "Отменена", "Canceled":
            return Color(red: 0.96, green: 0.88, blue: 0.88)
        default:
            return AppTheme.mint.opacity(0.68)
        }
    }

    func startsInMinutesText(referenceDate: Date = Date()) -> String? {
        guard let proposedDate else {
            return nil
        }

        let secondsUntilStart = proposedDate.timeIntervalSince(referenceDate)
        guard secondsUntilStart > 0 else {
            return nil
        }

        let totalMinutes = max(Int(ceil(secondsUntilStart / 60)), 1)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0
                ? L10n.string("Game in \(days)d \(hours)h", "До игры \(days) д \(hours) ч")
                : L10n.string("Game in \(days)d", "До игры \(days) д")
        }

        if hours > 0 {
            return minutes > 0
                ? L10n.string("Game in \(hours)h \(minutes)min", "До игры \(hours) ч \(minutes) мин")
                : L10n.string("Game in \(hours)h", "До игры \(hours) ч")
        }

        return L10n.string("Game in \(minutes) min", "До игры \(minutes) мин")
    }
}

extension RegularPairOccurrence {
    var statusLabel: String {
        switch status.lowercased() {
        case "confirmed":
            return L10n.string("Confirmed", "Подтверждено")
        case "declined":
            return L10n.string("Someone can't make it", "Кто-то не может")
        case "canceled", "cancelled":
            return L10n.string("Canceled", "Отменено")
        case "expired":
            return L10n.string("Already passed", "Уже прошло")
        default:
            return L10n.string("Awaiting confirmation", "Ждёт подтверждения")
        }
    }

    var statusTintColor: Color {
        switch status.lowercased() {
        case "confirmed":
            return AppTheme.court
        case "declined":
            return .red.opacity(0.9)
        case "canceled", "cancelled", "expired":
            return AppTheme.ink.opacity(0.72)
        default:
            return AppTheme.ink
        }
    }

    var statusSurfaceColor: Color {
        switch status.lowercased() {
        case "confirmed":
            return AppTheme.mint
        case "declined":
            return Color.red.opacity(0.12)
        case "canceled", "cancelled", "expired":
            return Color.gray.opacity(0.18)
        default:
            return AppTheme.cream
        }
    }
}

extension GameRequestInvitee {
    var statusLabel: String {
        switch status.lowercased() {
        case "accepted":
            return L10n.string("Accepted", "Принял")
        case "declined", "rejected":
            return L10n.string("Declined", "Отклонил")
        case "canceled", "cancelled", "withdrawn":
            return L10n.string("Canceled", "Отменено")
        default:
            return L10n.string("Awaiting response", "Ожидаем ответ")
        }
    }

    var statusTint: Color {
        switch status.lowercased() {
        case "accepted":
            return AppTheme.court
        case "declined", "rejected":
            return .red.opacity(0.88)
        case "canceled", "cancelled", "withdrawn":
            return .gray.opacity(0.82)
        default:
            return Color(red: 1.0, green: 0.70, blue: 0.30)
        }
    }
}

extension Sport {
    static let defaultAuthSports: [Sport] = [.tennis, .padel, .running, .supboard, .squash, .badminton, .tableTennis, .volleyball, .fitness, .boxing, .yoga, .football]
}

/// Creating a formatter costs far more than using one, and the Discover body parsed
/// every game date again for each filter, sort comparison and badge — a fresh pair of
/// ISO formatters per call took a third of the main thread on a real account.
/// Both formatter classes are thread-safe for parsing and formatting.
enum CachedDateFormatters {
    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let parsedDates: NSCache<NSString, NSDate> = {
        let cache = NSCache<NSString, NSDate>()
        cache.countLimit = 4000
        return cache
    }()
    private static let displayFormatters = NSCache<NSString, DateFormatter>()

    static func isoDate(from string: String) -> Date? {
        let key = string as NSString
        if let cached = parsedDates.object(forKey: key) {
            return cached as Date
        }
        guard let date = isoWithFractionalSeconds.date(from: string) ?? iso.date(from: string) else {
            return nil
        }
        parsedDates.setObject(date as NSDate, forKey: key)
        return date
    }

    /// A fixed pattern such as "d MMM", in the app's current language.
    static func display(format: String) -> DateFormatter {
        displayFormatter(key: "format:" + format) { $0.dateFormat = format }
    }

    /// A template such as "d MMM", reordered for the app's current language.
    static func display(template: String) -> DateFormatter {
        displayFormatter(key: "template:" + template) { $0.setLocalizedDateFormatFromTemplate(template) }
    }

    private static func displayFormatter(key: String, configure: (DateFormatter) -> Void) -> DateFormatter {
        let locale = LocaleStore.currentEffectiveLocale
        let timeZone = TimeZone.current
        let cacheKey = "\(locale.rawValue)|\(timeZone.identifier)|\(key)" as NSString
        if let cached = displayFormatters.object(forKey: cacheKey) {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = locale.locale
        formatter.timeZone = timeZone
        configure(formatter)
        displayFormatters.setObject(formatter, forKey: cacheKey)
        return formatter
    }
}

extension String {
    func parsedISODateValue() -> Date? {
        CachedDateFormatters.isoDate(from: self)
    }

    func formattedDateTime() -> String {
        guard let date = parsedISODateValue() else {
            return self
        }

        return CachedDateFormatters.display(format: "d MMM, HH:mm").string(from: date)
    }

    func formattedNumericDateTime() -> String {
        guard let date = parsedISODateValue() else {
            return self
        }

        return CachedDateFormatters.display(format: "dd.MM.yyyy HH:mm").string(from: date)
    }
}

extension Date {
    func formattedHourMinute() -> String {
        CachedDateFormatters.display(format: "HH:mm").string(from: self)
    }
}

extension UNAuthorizationStatus {
    var title: String {
        switch self {
        case .notDetermined:
            return L10n.string("Not requested", "Не запрошено")
        case .denied:
            return L10n.string("Denied", "Запрещено")
        case .authorized:
            return L10n.string("Allowed", "Разрешено")
        case .provisional:
            return L10n.string("Provisionally allowed", "Временно разрешено")
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return L10n.string("Unknown", "Неизвестно")
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntDictionary(forKey key: Key) throws -> [String: Int] {
        if let intDict = try? decodeIfPresent([String: Int].self, forKey: key) {
            return intDict
        }

        if let optionalIntDict = try? decodeIfPresent([String: Int?].self, forKey: key) {
            return optionalIntDict.compactMapValues { $0 }
        }

        if let doubleDict = try? decodeIfPresent([String: Double].self, forKey: key) {
            return doubleDict.mapValues { Int($0.rounded()) }
        }

        if let optionalDoubleDict = try? decodeIfPresent([String: Double?].self, forKey: key) {
            return optionalDoubleDict.compactMapValues { value in
                guard let value else { return nil }
                return Int(value.rounded())
            }
        }

        return [:]
    }

    func decodeFlexibleStringArrayDictionary(forKey key: Key) throws -> [String: [String]] {
        if let value = try decodeIfPresent([String: [String]].self, forKey: key) {
            return value
        }

        return [:]
    }

    func decodeFlexibleSportArray(forKey key: Key) throws -> [Sport] {
        if let sports = try decodeIfPresent([Sport].self, forKey: key) {
            return sports
        }

        if let strings = try decodeIfPresent([String].self, forKey: key) {
            return strings.compactMap(Sport.init(rawValue:))
        }

        return []
    }

    func decodeFlexibleSportArrayIfPresent(forKey key: Key) throws -> [Sport]? {
        if contains(key) == false {
            return nil
        }

        return try decodeFlexibleSportArray(forKey: key)
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return value
        }

        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }

        return nil
    }
}

// MARK: - Chat receipt state
protocol ChatReceiptMessage: Identifiable where ID == String {
    var receipt: ChatReceipt? { get set }
}

func mergeChatReceipts<Message: ChatReceiptMessage>(current: [Message], fetched: [Message]) -> [Message] {
    let previous = Dictionary(current.map { ($0.id, $0.receipt) }, uniquingKeysWith: { _, latest in latest })
    return fetched.map { message in
        var updated = message
        updated.receipt = ChatReceipt.merged(previous[message.id] ?? nil, message.receipt)
        return updated
    }
}

struct ChatReceipt: Codable, Equatable {
    let status: String
    let deliveredCount: Int
    let readCount: Int

    static func merged(_ previous: ChatReceipt?, _ next: ChatReceipt?) -> ChatReceipt? {
        guard let previous else { return next }
        guard let next else { return previous }
        let readCount = max(previous.readCount, next.readCount)
        let deliveredCount = max(previous.deliveredCount, next.deliveredCount, readCount)
        let status = previous.status == "read" || next.status == "read" || readCount > 0
            ? "read" : (previous.status == "delivered" || next.status == "delivered" || deliveredCount > 0 ? "delivered" : "sent")
        return ChatReceipt(status: status, deliveredCount: deliveredCount, readCount: readCount)
    }
}

enum ChatReceiptScope: Equatable {
    case match(String)
    case search(String)
}

struct ChatReceiptAcknowledgementState {
    var incomingIDs: Set<String> = []
    var visibleIDs: Set<String> = []
    var isActive = false
    private(set) var deliveredIDs: Set<String> = []
    private(set) var readIDs: Set<String> = []

    func pendingIDs(status: String) -> [String] {
        let candidates = status == "read"
            ? (isActive ? incomingIDs.intersection(visibleIDs).subtracting(readIDs) : [])
            : incomingIDs.subtracting(deliveredIDs)
        return Array(candidates.sorted().prefix(200))
    }

    mutating func confirm(_ ids: [String], status: String) {
        deliveredIDs.formUnion(ids)
        if status == "read" { readIDs.formUnion(ids) }
    }

    static func isVisible(row: CGRect, viewport: CGRect) -> Bool {
        guard !row.isEmpty, !viewport.isEmpty, !row.isNull, !viewport.isNull else { return false }
        let intersection = row.intersection(viewport)
        return !intersection.isNull && intersection.width > 0
            && intersection.height >= min(row.height, viewport.height) * 0.5
    }
}
// MARK: - End chat receipt state
