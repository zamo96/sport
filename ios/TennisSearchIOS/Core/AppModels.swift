import Foundation
import CoreLocation
import UserNotifications
import SwiftUI

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
    "central": "Центральный"
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

enum Gender: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male:
            return "Мужчина"
        case .female:
            return "Женщина"
        case .other:
            return "Другое"
        }
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tableTennis:
            return "Настольный теннис"
        case .tennis:
            return "Теннис"
        case .padel:
            return "Падел"
        case .squash:
            return "Сквош"
        case .badminton:
            return "Бадминтон"
        case .volleyball:
            return "Волейбол"
        case .fitness:
            return "Фитнес"
        case .boxing:
            return "Бокс"
        case .yoga:
            return "Йога"
        case .football:
            return "Футбол"
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
        case .fitness, .boxing, .yoga:
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
            return "Корт"
        case .tableTennis:
            return "Зал"
        case .football, .volleyball:
            return "Площадка"
        case .fitness, .boxing:
            return "Зал"
        case .yoga:
            return "Студия"
        }
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
        "\(venueTitle) подбирается"
    }

    var venueUnspecifiedTitle: String {
        "\(venueTitle) уточняется"
    }

    var venueExistsTitle: String {
        "\(venueTitle) есть"
    }

    private var isTeamSport: Bool {
        self == .football || self == .volleyball
    }

    func formatTitle(format: PlayFormat, playersNeeded: Int? = nil) -> String {
        if format == .both {
            return "Любой"
        }

        let resolvedPlayersNeeded = playersNeeded ?? defaultPlayersNeeded(format: format)
        let isGroup = resolvedPlayersNeeded > 1

        if isTeamSport {
            return "Командная"
        }

        switch self {
        case .fitness, .boxing, .yoga:
            return isGroup ? "Групповая" : "Индивидуально"
        default:
            if isGroup, resolvedPlayersNeeded > 3 {
                return "Групповая"
            }

            switch format {
            case .singles:
                return isGroup ? "Групповая" : "Одиночная"
            case .doubles:
                return resolvedPlayersNeeded > 3 ? "Групповая" : "Парная"
            case .both:
                return "Любой"
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
            return "Одиночный"
        case .doubles:
            return "Парный"
        case .both:
            return "Любой"
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
            return "Хард"
        case .clay:
            return "Грунт"
        case .grass:
            return "Трава"
        case .any:
            return "Любое"
        }
    }
}

enum SearchType: String, Codable, CaseIterable, Identifiable {
    case regular
    case hot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular:
            return "Регулярный"
        case .hot:
            return "Срочный"
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
            return "Сегодня"
        case .tomorrow:
            return "Завтра"
        case .dayAfterTomorrow:
            return "Послезавтра"
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
            return "Утро"
        case .day:
            return "День"
        case .evening:
            return "Вечер"
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
            return "Утро"
        case .day:
            return "День"
        case .evening:
            return "Вечер (после 18:00)"
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
            return "Пн"
        case .tuesday:
            return "Вт"
        case .wednesday:
            return "Ср"
        case .thursday:
            return "Чт"
        case .friday:
            return "Пт"
        case .saturday:
            return "Сб"
        case .sunday:
            return "Вс"
        }
    }

    var title: String {
        switch self {
        case .monday:
            return "Понедельник"
        case .tuesday:
            return "Вторник"
        case .wednesday:
            return "Среда"
        case .thursday:
            return "Четверг"
        case .friday:
            return "Пятница"
        case .saturday:
            return "Суббота"
        case .sunday:
            return "Воскресенье"
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

    var title: String {
        switch self {
        case .upcoming:
            return "Ближайшие игры"
        case .swipe:
            return "Похожие игроки"
        case .likes:
            return "Хотят с тобой поиграть"
        case .seeking:
            return "Регулярно"
        case .hot:
            return "Срочно"
        }
    }

    var systemImage: String {
        switch self {
        case .upcoming:
            return "calendar.badge.clock"
        case .swipe:
            return "sparkles"
        case .likes:
            return "heart.text.square"
        case .seeking:
            return "calendar"
        case .hot:
            return "flame"
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

struct SessionUser: Codable {
    let id: String
    let email: String
    let onboardingCompleted: Bool
}

struct AuthChallenge: Codable {
    let message: String
    let debugCode: String?
}

struct GuestOnboardingDraft: Codable, Equatable {
    var name: String
    var age: Int
    var gender: Gender?
    var city: String
    var district: String?
    var preferredDistricts: [String]
    var preferredSports: [Sport]
    var sportLevels: [String: Int]
    var preferredPlayFormat: PlayFormat
    var preferredSurface: Surface
    var searchRadiusKm: Int
    var isLookingForGame: Bool
    var availableDays: [String]
    var availableTimeRanges: [String]
    var availabilityByDay: [String: [String]]
    var onboardingCompleted: Bool

    init(
        name: String,
        age: Int,
        gender: Gender?,
        city: String,
        district: String?,
        preferredDistricts: [String],
        preferredSports: [Sport],
        sportLevels: [String: Int],
        preferredPlayFormat: PlayFormat,
        preferredSurface: Surface,
        searchRadiusKm: Int,
        isLookingForGame: Bool,
        availableDays: [String],
        availableTimeRanges: [String],
        availabilityByDay: [String: [String]],
        onboardingCompleted: Bool
    ) {
        self.name = name
        self.age = age
        self.gender = gender
        self.city = city
        self.district = district
        self.preferredDistricts = preferredDistricts
        self.preferredSports = preferredSports
        self.sportLevels = sportLevels
        self.preferredPlayFormat = preferredPlayFormat
        self.preferredSurface = preferredSurface
        self.searchRadiusKm = searchRadiusKm
        self.isLookingForGame = isLookingForGame
        self.availableDays = availableDays
        self.availableTimeRanges = availableTimeRanges
        self.availabilityByDay = availabilityByDay
        self.onboardingCompleted = onboardingCompleted
    }

    static let `default` = GuestOnboardingDraft(
        name: "",
        age: 28,
        gender: nil,
        city: "Санкт-Петербург",
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
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && age >= 18 && !preferredSports.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case name
        case age
        case gender
        case city
        case district
        case preferredDistricts
        case preferredSports
        case sportLevels
        case preferredPlayFormat
        case preferredSurface
        case searchRadiusKm
        case isLookingForGame
        case availableDays
        case availableTimeRanges
        case availabilityByDay
        case onboardingCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        age = try container.decodeIfPresent(Int.self, forKey: .age) ?? 28
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? "Санкт-Петербург"
        district = try container.decodeIfPresent(String.self, forKey: .district)
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        preferredSports = try container.decodeFlexibleSportArray(forKey: .preferredSports)
        sportLevels = try container.decodeFlexibleIntDictionary(forKey: .sportLevels)
        preferredPlayFormat = try container.decodeIfPresent(PlayFormat.self, forKey: .preferredPlayFormat) ?? .both
        preferredSurface = try container.decodeIfPresent(Surface.self, forKey: .preferredSurface) ?? .any
        searchRadiusKm = try container.decodeIfPresent(Int.self, forKey: .searchRadiusKm) ?? 20
        isLookingForGame = try container.decodeIfPresent(Bool.self, forKey: .isLookingForGame) ?? true
        availableDays = try container.decodeIfPresent([String].self, forKey: .availableDays) ?? []
        availableTimeRanges = try container.decodeIfPresent([String].self, forKey: .availableTimeRanges) ?? []
        availabilityByDay = try container.decodeFlexibleStringArrayDictionary(forKey: .availabilityByDay)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
    }
}

struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String?
    var name: String?
    var age: Int?
    var gender: Gender?
    var city: String?
    var district: String?
    var preferredDistricts: [String]
    var bio: String?
    var avatarUrl: String?
    var tennisLevel: Int?
    var preferredSports: [Sport]
    var sportLevels: [String: Int]
    var preferredPlayFormat: PlayFormat
    var preferredSurface: Surface
    var availableDays: [String]
    var availableTimeRanges: [String]
    var availabilityByDay: [String: [String]]
    var isLookingForGame: Bool
    var searchRadiusKm: Int
    var onboardingCompleted: Bool
    var isVerified: Bool
    var notificationMatches: Bool
    var notificationMessages: Bool
    var notificationGames: Bool
    var notificationSound: Bool

    init(
        id: String,
        email: String? = nil,
        name: String? = nil,
        age: Int? = nil,
        gender: Gender? = nil,
        city: String? = nil,
        district: String? = nil,
        preferredDistricts: [String] = [],
        bio: String? = nil,
        avatarUrl: String? = nil,
        tennisLevel: Int? = nil,
        preferredSports: [Sport] = [],
        sportLevels: [String: Int] = [:],
        preferredPlayFormat: PlayFormat = .both,
        preferredSurface: Surface = .any,
        availableDays: [String] = [],
        availableTimeRanges: [String] = [],
        availabilityByDay: [String: [String]] = [:],
        isLookingForGame: Bool = true,
        searchRadiusKm: Int = 20,
        onboardingCompleted: Bool = false,
        isVerified: Bool = false,
        notificationMatches: Bool = true,
        notificationMessages: Bool = true,
        notificationGames: Bool = true,
        notificationSound: Bool = true
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.age = age
        self.gender = gender
        self.city = city
        self.district = district
        self.preferredDistricts = preferredDistricts
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.tennisLevel = tennisLevel
        self.preferredSports = preferredSports
        self.sportLevels = sportLevels
        self.preferredPlayFormat = preferredPlayFormat
        self.preferredSurface = preferredSurface
        self.availableDays = availableDays
        self.availableTimeRanges = availableTimeRanges
        self.availabilityByDay = availabilityByDay
        self.isLookingForGame = isLookingForGame
        self.searchRadiusKm = searchRadiusKm
        self.onboardingCompleted = onboardingCompleted
        self.isVerified = isVerified
        self.notificationMatches = notificationMatches
        self.notificationMessages = notificationMessages
        self.notificationGames = notificationGames
        self.notificationSound = notificationSound
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case age
        case gender
        case city
        case district
        case preferredDistricts
        case bio
        case avatarUrl
        case tennisLevel
        case preferredSports
        case sportLevels
        case preferredPlayFormat
        case preferredSurface
        case availableDays
        case availableTimeRanges
        case availabilityByDay
        case isLookingForGame
        case searchRadiusKm
        case onboardingCompleted
        case isVerified
        case notificationMatches
        case notificationMessages
        case notificationGames
        case notificationSound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        tennisLevel = try container.decodeIfPresent(Int.self, forKey: .tennisLevel)
        preferredSports = try container.decodeFlexibleSportArray(forKey: .preferredSports)
        sportLevels = try container.decodeFlexibleIntDictionary(forKey: .sportLevels)
        preferredPlayFormat = try container.decodeIfPresent(PlayFormat.self, forKey: .preferredPlayFormat) ?? .both
        preferredSurface = try container.decodeIfPresent(Surface.self, forKey: .preferredSurface) ?? .any
        availableDays = try container.decodeIfPresent([String].self, forKey: .availableDays) ?? []
        availableTimeRanges = try container.decodeIfPresent([String].self, forKey: .availableTimeRanges) ?? []
        availabilityByDay = try container.decodeFlexibleStringArrayDictionary(forKey: .availabilityByDay)
        isLookingForGame = try container.decodeIfPresent(Bool.self, forKey: .isLookingForGame) ?? true
        searchRadiusKm = try container.decodeIfPresent(Int.self, forKey: .searchRadiusKm) ?? 20
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        notificationMatches = try container.decodeIfPresent(Bool.self, forKey: .notificationMatches) ?? true
        notificationMessages = try container.decodeIfPresent(Bool.self, forKey: .notificationMessages) ?? true
        notificationGames = try container.decodeIfPresent(Bool.self, forKey: .notificationGames) ?? true
        notificationSound = try container.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? true
    }
}

struct DiscoverUser: Codable, Identifiable {
    let id: String
    let name: String?
    let age: Int?
    let city: String?
    let district: String?
    let districtLabel: String?
    let preferredDistricts: [String]
    let bio: String?
    let avatarUrl: String?
    let tennisLevel: Int?
    let preferredSports: [Sport]
    let sportLevels: [String: Int]
    let preferredPlayFormat: PlayFormat
    let preferredSurface: Surface
    let availableDays: [String]
    let availableTimeRanges: [String]
    let distanceLabel: String
    let score: Double?
    let explainabilityReasons: [String]
    let gameSearches: [GameSearch]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case age
        case city
        case district
        case districtLabel
        case preferredDistricts
        case bio
        case avatarUrl
        case tennisLevel
        case preferredSports
        case sportLevels
        case preferredPlayFormat
        case preferredSurface
        case availableDays
        case availableTimeRanges
        case distanceLabel
        case score
        case explainabilityReasons
        case gameSearches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        districtLabel = try container.decodeIfPresent(String.self, forKey: .districtLabel)
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        tennisLevel = try container.decodeIfPresent(Int.self, forKey: .tennisLevel)
        preferredSports = try container.decodeFlexibleSportArray(forKey: .preferredSports)
        sportLevels = try container.decodeFlexibleIntDictionary(forKey: .sportLevels)
        preferredPlayFormat = try container.decodeIfPresent(PlayFormat.self, forKey: .preferredPlayFormat) ?? .both
        preferredSurface = try container.decodeIfPresent(Surface.self, forKey: .preferredSurface) ?? .any
        availableDays = try container.decodeIfPresent([String].self, forKey: .availableDays) ?? []
        availableTimeRanges = try container.decodeIfPresent([String].self, forKey: .availableTimeRanges) ?? []
        distanceLabel = try container.decodeIfPresent(String.self, forKey: .distanceLabel) ?? "Рядом"
        score = try container.decodeFlexibleDoubleIfPresent(forKey: .score)
        explainabilityReasons = try container.decodeIfPresent([String].self, forKey: .explainabilityReasons) ?? []
        gameSearches = try container.decodeIfPresent([GameSearch].self, forKey: .gameSearches) ?? []
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

struct ChatMessage: Codable, Identifiable {
    let id: String
    let senderUserId: String
    let text: String
    let createdAt: String
    let senderUser: ChatSender?
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

struct SearchLobbyMessage: Codable, Identifiable {
    let id: String
    let senderUserId: String
    let text: String
    let createdAt: String
    let senderUser: ChatSender?
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
    let messages: [SearchLobbyMessage]

    var preferredDistrictsLabel: String {
        let names = preferredDistricts.compactMap(localizedDistrictName)
        return names.isEmpty ? "Любой район" : names.joined(separator: ", ")
    }
}

extension SearchLobbyGameSearch {
    enum CodingKeys: String, CodingKey {
        case id
        case createdByUserId
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
    let sport: Sport
    let format: PlayFormat
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
        case sport
        case format
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
        proposedCourt: Court?,
        createdByUser: ChatSender?,
        matchedUser: ChatSender?,
        participants: [DiscoverUser] = [],
        invitees: [GameRequestInvitee] = []
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
        self.sport = sport
        self.format = format
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
        sport = try container.decodeIfPresent(Sport.self, forKey: .sport) ?? .tennis
        format = try container.decodeIfPresent(PlayFormat.self, forKey: .format) ?? .singles
        proposedCourt = try container.decodeIfPresent(Court.self, forKey: .proposedCourt)
        createdByUser = try container.decodeIfPresent(ChatSender.self, forKey: .createdByUser)
        matchedUser = try container.decodeIfPresent(ChatSender.self, forKey: .matchedUser)
        participants = try container.decodeIfPresent([DiscoverUser].self, forKey: .participants) ?? []
        invitees = try container.decodeIfPresent([GameRequestInvitee].self, forKey: .invitees) ?? []
    }
}

struct GameRequestInvitee: Codable, Identifiable {
    let id: String
    let matchId: String?
    let status: String
    let user: DiscoverUser
}

struct GameProposalDraft {
    var proposedCourtId: String
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
    let preferredDistricts: [String]
    let activeSlotProposal: SearchSlotProposalSummary?
    let regularPair: RegularPairSummary?
    let responses: [SearchResponse]

    init(
        id: String,
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
        preferredDistricts: [String] = [],
        activeSlotProposal: SearchSlotProposalSummary? = nil,
        regularPair: RegularPairSummary?,
        responses: [SearchResponse]
    ) {
        self.id = id
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
        self.preferredDistricts = preferredDistricts
        self.activeSlotProposal = activeSlotProposal
        self.regularPair = regularPair
        self.responses = responses
    }

    enum CodingKeys: String, CodingKey {
        case id
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
        case preferredDistricts
        case activeSlotProposal
        case regularPair
        case responses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
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
        preferredDistricts = try container.decodeIfPresent([String].self, forKey: .preferredDistricts) ?? []
        activeSlotProposal = try container.decodeIfPresent(SearchSlotProposalSummary.self, forKey: .activeSlotProposal)
        regularPair = try container.decodeIfPresent(RegularPairSummary.self, forKey: .regularPair)
        responses = try container.decodeIfPresent([SearchResponse].self, forKey: .responses) ?? []
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

struct Court: Codable, Identifiable {
    let id: String
    let name: String
    let address: String
    let district: String?
    let locationLat: Double
    let locationLng: Double
    let distanceLabel: String?
    let nearestMetroName: String?
    let supportedSports: [Sport]?
    let phone: String?
    let workingHours: String?
    let yandexMapsUrl: String?
    let websiteUrl: String?
    let bookingUrl: String?
    let photoUrl: String?
    let priceRange: String?
    let rating: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: locationLat, longitude: locationLng)
    }

    init(
        id: String,
        name: String,
        address: String,
        district: String?,
        locationLat: Double,
        locationLng: Double,
        distanceLabel: String?,
        nearestMetroName: String?,
        supportedSports: [Sport]?,
        phone: String? = nil,
        workingHours: String? = nil,
        yandexMapsUrl: String? = nil,
        websiteUrl: String? = nil,
        bookingUrl: String? = nil,
        photoUrl: String? = nil,
        priceRange: String? = nil,
        rating: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.district = district
        self.locationLat = locationLat
        self.locationLng = locationLng
        self.distanceLabel = distanceLabel
        self.nearestMetroName = nearestMetroName
        self.supportedSports = supportedSports
        self.phone = phone
        self.workingHours = workingHours
        self.yandexMapsUrl = yandexMapsUrl
        self.websiteUrl = websiteUrl
        self.bookingUrl = bookingUrl
        self.photoUrl = photoUrl
        self.priceRange = priceRange
        self.rating = rating
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case district
        case locationLat
        case locationLng
        case distanceLabel
        case nearestMetroName
        case supportedSports
        case phone
        case workingHours
        case yandexMapsUrl
        case websiteUrl
        case bookingUrl
        case photoUrl
        case priceRange
        case rating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        district = try container.decodeIfPresent(String.self, forKey: .district)
        locationLat = try container.decode(Double.self, forKey: .locationLat)
        locationLng = try container.decode(Double.self, forKey: .locationLng)
        distanceLabel = try container.decodeIfPresent(String.self, forKey: .distanceLabel)
        nearestMetroName = try container.decodeIfPresent(String.self, forKey: .nearestMetroName)
        supportedSports = try container.decodeFlexibleSportArrayIfPresent(forKey: .supportedSports)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        workingHours = try container.decodeIfPresent(String.self, forKey: .workingHours)
        yandexMapsUrl = try container.decodeIfPresent(String.self, forKey: .yandexMapsUrl)
        websiteUrl = try container.decodeIfPresent(String.self, forKey: .websiteUrl)
        bookingUrl = try container.decodeIfPresent(String.self, forKey: .bookingUrl)
        photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
        priceRange = try container.decodeIfPresent(String.self, forKey: .priceRange)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
    }
}

struct SearchDraft: Codable {
    var inviteSlug: String?
    var preferredCourtId: String?
    var preferredDistricts: [String]
    var preferredDays: [String]
    var preferredTimeRanges: [String]
    var searchType: SearchType
    var hotWindow: HotWindow?
    var hotStartTime: String?
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

struct ActivitySummary: Codable {
    let inboxBadgeCount: Int
    let incomingLikesCount: Int
    let hotBadgeCount: Int
    let discoverBadgeCount: Int
    let notificationSound: Bool
}

struct AppStats: Codable {
    let registeredPlayersCount: Int
    let seekingPlayersCount: Int
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
        notificationSound: true
    )

    func removingHotEvents() -> ActivitySummary {
        ActivitySummary(
            inboxBadgeCount: inboxBadgeCount,
            incomingLikesCount: incomingLikesCount,
            hotBadgeCount: 0,
            discoverBadgeCount: max(discoverBadgeCount - hotBadgeCount, 0),
            notificationSound: notificationSound
        )
    }
}

extension DiscoverUser {
    var displayName: String {
        guard let name, !name.isEmpty else {
            return "Игрок"
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
        return values.isEmpty ? "Районы не указаны" : values.prefix(3).joined(separator: ", ")
    }

    var sportChips: [String] {
        preferredSports.prefix(2).map { sport in
            let level = sportLevels[sport.rawValue] ?? tennisLevel ?? 5
            return "\(sport.title) \(level)"
        }
    }
}

extension UserProfile {
    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return email ?? "Профиль"
    }
}

extension GuestOnboardingDraft {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Твой профиль" : trimmed
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
            return "Идет набор"
        case "in_review":
            return "Ожидает решения"
        case "matched":
            return "Игроки найдены"
        case "closed":
            return "Закрыт"
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
            return "\(first.displayName) и еще \(people.count - 1)"
        }

        if people.count == 2 {
            return people.map(\.displayName).joined(separator: " и ")
        }

        if let first = people.first {
            return first.displayName
        }

        return otherUser(currentUserId: currentUserId)?.name ?? "Игрок"
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
        return Date().timeIntervalSince(proposedDate) >= duration
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

    var outcomeLabel: String? {
        switch outcome {
        case "played":
            return "Игра прошла"
        case "not_played":
            return "Не сыграли"
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
            return "Отменена"
        case "pending", "proposed":
            if format == .doubles || format == .both {
                return "Подбор игроков"
            }
            if matchedUserId != nil {
                return "Игра назначается"
            }
            return "Поиск"
        case "accepted", "approved":
            guard let startDate else {
                return "Игра подтверждена"
            }

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
        default:
            return "Поиск"
        }
    }

    var nextStepLabel: String {
        let rawStatus = status.lowercased()

        if isRegularOccurrence, rawStatus == "accepted" || rawStatus == "approved" {
            return "Игра подтверждена. Если нужно поменять следующий слот, открой регулярную пару."
        }

        switch rawStatus {
        case "pending", "proposed":
            if matchedUserId != nil {
                return "Игра создана. Открой чат и уточни детали, если что-то нужно поменять."
            }
            return "Нужно собрать состав и перевести поиск в конкретную игру."
        case "accepted", "approved":
            return "Игра подтверждена. Дальше открой чат и договорись только о последних нюансах."
        case "declined", "rejected", "withdrawn", "canceled", "cancelled":
            return "Эта договоренность уже не активна. Если всё ещё хочешь сыграть, начни новую."
        default:
            return "Открой детали и продолжай путь к следующей игре."
        }
    }

    var statusTintColor: Color {
        switch statusLabel {
        case "Поиск":
            return Color(red: 0.34, green: 0.47, blue: 0.68)
        case "В процессе набора", "В процессе набора людей", "Подбор игроков":
            return Color(red: 0.72, green: 0.48, blue: 0.18)
        case "В ожидании принятия", "Ждём подтверждение", "Игра назначается":
            return Color(red: 0.49, green: 0.45, blue: 0.78)
        case "Игрок найден", "Игроки найдены", "Игра подтверждена", "Игра прошла":
            return Color(red: 0.16, green: 0.58, blue: 0.33)
        case "Скоро начнется":
            return Color(red: 0.78, green: 0.52, blue: 0.18)
        case "Игра началась", "Игра идет":
            return Color(red: 0.17, green: 0.50, blue: 0.72)
        case "Игра закончилась":
            return Color(red: 0.33, green: 0.33, blue: 0.38)
        case "Не сыграли":
            return Color(red: 0.72, green: 0.22, blue: 0.20)
        case "Подтверждена":
            return Color(red: 0.16, green: 0.58, blue: 0.33)
        case "Отменена":
            return Color(red: 0.72, green: 0.22, blue: 0.20)
        default:
            return AppTheme.court
        }
    }

    var statusSurfaceColor: Color {
        switch statusLabel {
        case "Поиск":
            return Color(red: 0.88, green: 0.92, blue: 0.98)
        case "В процессе набора", "В процессе набора людей", "Подбор игроков":
            return Color(red: 0.98, green: 0.93, blue: 0.84)
        case "В ожидании принятия", "Ждём подтверждение", "Игра назначается":
            return Color(red: 0.91, green: 0.90, blue: 0.99)
        case "Игрок найден", "Игроки найдены", "Игра подтверждена", "Игра прошла":
            return Color(red: 0.86, green: 0.95, blue: 0.89)
        case "Скоро начнется":
            return Color(red: 0.99, green: 0.94, blue: 0.83)
        case "Игра началась", "Игра идет":
            return Color(red: 0.86, green: 0.93, blue: 0.98)
        case "Игра закончилась":
            return Color(red: 0.90, green: 0.90, blue: 0.92)
        case "Не сыграли":
            return Color(red: 0.96, green: 0.88, blue: 0.88)
        case "Подтверждена":
            return Color(red: 0.86, green: 0.95, blue: 0.89)
        case "Отменена":
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
            return hours > 0 ? "До игры \(days) д \(hours) ч" : "До игры \(days) д"
        }

        if hours > 0 {
            return minutes > 0 ? "До игры \(hours) ч \(minutes) мин" : "До игры \(hours) ч"
        }

        return "До игры \(minutes) мин"
    }
}

extension RegularPairOccurrence {
    var statusLabel: String {
        switch status.lowercased() {
        case "confirmed":
            return "Подтверждено"
        case "declined":
            return "Кто-то не может"
        case "canceled", "cancelled":
            return "Отменено"
        case "expired":
            return "Уже прошло"
        default:
            return "Ждёт подтверждения"
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
            return "Принял"
        case "declined", "rejected":
            return "Отклонил"
        case "canceled", "cancelled", "withdrawn":
            return "Отменено"
        default:
            return "Ожидаем ответ"
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
    static let defaultAuthSports: [Sport] = [.tennis, .padel, .squash, .badminton, .tableTennis, .volleyball, .fitness, .boxing, .yoga, .football]
}

extension String {
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

    func formattedDateTime() -> String {
        guard let date = parsedISODateValue() else {
            return self
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "ru_RU")
        output.dateFormat = "d MMM, HH:mm"
        return output.string(from: date)
    }

    func formattedNumericDateTime() -> String {
        guard let date = parsedISODateValue() else {
            return self
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "ru_RU")
        output.dateFormat = "dd.MM.yyyy HH:mm"
        return output.string(from: date)
    }
}

extension Date {
    func formattedHourMinute() -> String {
        let output = DateFormatter()
        output.locale = Locale(identifier: "ru_RU")
        output.dateFormat = "HH:mm"
        return output.string(from: self)
    }
}

extension UNAuthorizationStatus {
    var title: String {
        switch self {
        case .notDetermined:
            return "Не запрошено"
        case .denied:
            return "Запрещено"
        case .authorized:
            return "Разрешено"
        case .provisional:
            return "Временно разрешено"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Неизвестно"
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
