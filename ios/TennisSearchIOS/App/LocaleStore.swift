import Foundation

enum AppLocale: String, CaseIterable, Identifiable {
    case en
    case ru

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

final class LocaleStore: ObservableObject {
    static let manualOverrideKey = "ios.locale-override.v1"

    @Published private(set) var manualOverride: AppLocale?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        manualOverride = defaults.string(forKey: Self.manualOverrideKey).flatMap(AppLocale.init(rawValue:))
    }

    var effectiveLocale: AppLocale {
        manualOverride ?? Self.deviceLocale
    }

    var locale: Locale {
        effectiveLocale.locale
    }

    var hasManualOverride: Bool {
        manualOverride != nil
    }

    func setManualOverride(_ locale: AppLocale) {
        defaults.set(locale.rawValue, forKey: Self.manualOverrideKey)
        manualOverride = locale
    }

    func clearManualOverride() {
        defaults.removeObject(forKey: Self.manualOverrideKey)
        manualOverride = nil
    }

    static var currentEffectiveLocale: AppLocale {
        UserDefaults.standard.string(forKey: manualOverrideKey)
            .flatMap(AppLocale.init(rawValue:))
            ?? deviceLocale
    }

    private static var deviceLocale: AppLocale {
        let preferredIdentifier = Locale.preferredLanguages.first ?? "en"
        let languageCode = Locale(identifier: preferredIdentifier).language.languageCode?.identifier.lowercased()
        return languageCode == AppLocale.ru.rawValue ? .ru : .en
    }
}

enum L10n {
    static func string(
        _ english: String,
        _ russian: String,
        locale: AppLocale = LocaleStore.currentEffectiveLocale
    ) -> String {
        locale == .ru ? russian : english
    }
}
