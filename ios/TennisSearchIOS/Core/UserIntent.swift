import Foundation

enum UserIntent: String, CaseIterable, Identifiable {
    case partner
    case group
    case activity
    case centers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .partner: return L10n.string("Find a partner", "Найти партнёра")
        case .group: return L10n.string("Join a game", "Играть в компании")
        case .activity: return L10n.string("Plan my visits", "Ходить в клуб")
        case .centers: return L10n.string("Explore sports centers", "Найти спортцентр")
        }
    }

    var subtitle: String {
        switch self {
        case .partner: return L10n.string("Find someone to play your sport with.", "Найти человека для совместной игры.")
        case .group: return L10n.string("Find players and join their games.", "Найти игроков и присоединиться к игре.")
        case .activity: return L10n.string("Plan visits and keep your activity history.", "Планировать визиты и видеть свою историю.")
        case .centers: return L10n.string("Choose a place and save your favorites.", "Выбрать место и сохранить понравившиеся.")
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .partner: return L10n.string("Find a partner", "Найти партнёра")
        case .group: return L10n.string("Explore games", "Посмотреть игры")
        case .activity: return L10n.string("Plan a visit", "Запланировать визит")
        case .centers: return L10n.string("Explore centers", "Посмотреть центры")
        }
    }

    var systemImage: String {
        switch self {
        case .partner: return "person.2.fill"
        case .group: return "sportscourt.fill"
        case .activity: return "calendar.badge.plus"
        case .centers: return "map.fill"
        }
    }
}
