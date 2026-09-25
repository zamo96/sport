import SwiftUI

/// Что человек разрешает показывать. Анкета без описания, фото и видео
/// показывается всегда, если человек вообще согласился на показ.
struct ConsentScope: Equatable {
    var visibleToGuests = true
    var showsBio = true
    var showsPhotos = true
    var showsVideos = true
    var showsSearches = true
    var showOnMap = true

    /// До ответа «Настроить» предлагает показывать всё: человек соглашается
    /// кнопкой на то, что видит в превью, а настройка позволяет только сузить
    /// показ. После ответа экран открывается с тем, что человек выбрал.
    init(profile: UserProfile) {
        guard let consents = profile.consents, consents.profileVisibility == "visible" else {
            showOnMap = profile.showOnMap
            return
        }
        visibleToGuests = consents.visibleToGuests
        showsBio = consents.showsBio
        showsPhotos = consents.showsPhotos
        showsVideos = consents.showsVideos
        showsSearches = consents.showsSearches
        showOnMap = profile.showOnMap
    }
}

enum ConsentNameValidator {
    /// Как на сервере: хотя бы два слова из букв (фамилия и имя).
    static func normalized(_ value: String) -> String? {
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let pattern = #"^[\p{L}][\p{L}'’-]*(?:\s+[\p{L}][\p{L}'’-]*)+$"#
        return collapsed.range(of: pattern, options: .regularExpression) != nil ? collapsed : nil
    }
}

/// Экран согласия на показ анкеты (ст. 10.1 152-ФЗ). Кнопка «Показывать
/// анкету» — само согласие. Принятие новой редакции соглашения и аналитика —
/// отдельные отметки и отдельные поля запроса.
struct ConsentReviewView: View {
    enum Mode {
        /// После анкеты или при первом открытии: закрыть без ответа нельзя.
        case required
        /// Из настроек профиля: можно закрыть без изменений.
        case settings
    }

    let mode: Mode
    let profile: UserProfile
    var onFinished: () -> Void = {}

    @EnvironmentObject private var appModel: AppModel
    @State private var scope: ConsentScope
    @State private var fullName: String
    @State private var analytics: Bool
    @State private var termsAccepted = false
    @State private var isCustomizing = false
    @State private var errorText: String?
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    init(mode: Mode, profile: UserProfile, onFinished: @escaping () -> Void = {}) {
        self.mode = mode
        self.profile = profile
        self.onFinished = onFinished
        _scope = State(initialValue: ConsentScope(profile: profile))
        _fullName = State(initialValue: profile.consents?.fullName ?? "")
        _analytics = State(initialValue: profile.consents?.analytics ?? false)
    }

    private var consents: ConsentState { profile.consents ?? ConsentState() }
    private var isLegacy: Bool { consents.isLegacy }
    private var hidesAsSecondary: Bool { isLegacy || consents.profileVisibility == "visible" }
    /// Имя подставлено из анкеты — остаётся дописать фамилию.
    private var needsSurname: Bool { fullName.split(whereSeparator: \.isWhitespace).count == 1 }

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    previewCard
                    Text(scope.visibleToGuests
                         ? L10n.string("Players and guests will see you like this in search and on the map. The map shows a district point, not your location.", "Так вас увидят игроки и гости в поиске и на карте. На карте — точка района, не ваше местоположение.")
                         : L10n.string("Signed-in players will see you like this in search and on the map. The map shows a district point, not your location.", "Так вас увидят игроки, вошедшие в аккаунт, в поиске и на карте. На карте — точка района, не ваше местоположение."))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)

                    customizeSection

                    if consents.termsUpdateRequired {
                        termsCheckbox
                    }

                    nameField
                    analyticsCheckbox

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    actions
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Экран светлый, а главный экран включает тёмную тему — без этого поле
        // ввода и переключатели рисовались бы светлым по белому.
        .environment(\.colorScheme, .light)
        .interactiveDismissDisabled(mode == .required)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isLegacy
                 ? L10n.string("We've updated our terms", "Мы обновили правила")
                 : L10n.string("Show your profile?", "Показывать вашу анкету?"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            if isLegacy {
                Text(L10n.string("Consent to showing your profile is now a separate decision. Right now other players can see your profile.", "Согласие на показ анкеты теперь отдельное решение. Сейчас ваша анкета видна другим игрокам."))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var previewCard: some View {
        let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = [name.isEmpty ? nil : name, profile.age.map(String.init)].compactMap { $0 }.joined(separator: ", ")
        let sports = profile.preferredSports.map { sport -> String in
            if let level = profile.sportLevels[sport.rawValue] {
                return "\(sport.title) \(level)"
            }
            return sport.title
        }.joined(separator: ", ")
        let place = [profile.city, localizedDistrictName(profile.district)].compactMap { $0 }.joined(separator: " · ")

        return HStack(spacing: 12) {
            Text(String(name.prefix(1)).uppercased())
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.court)
                .frame(width: 46, height: 46)
                .background(AppTheme.court.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text([sports, place].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    isCustomizing.toggle()
                }
                AppHaptics.selection()
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.string("Choose what is shown and to whom", "Настроить, что и кому видно"))
                        .underline()
                    Image(systemName: isCustomizing ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.court)
            }
            .buttonStyle(.plain)

            if isCustomizing {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Switch off anything you don't want to show.", "Выключите то, что не хотите показывать."))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .padding(.bottom, 4)

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string("Profile card", "Анкета"))
                                .font(.subheadline.weight(.semibold))
                            Text(L10n.string("name, age, city, districts, sport and level, schedule, format", "имя, возраст, город, районы, спорт и уровень, расписание, формат"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        Spacer()
                        Label(L10n.string("Always", "Всегда"), systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    .padding(.vertical, 6)

                    scopeToggle(L10n.string("Description", "Описание"), isOn: $scope.showsBio)
                    scopeToggle(L10n.string("Photos", "Фото"), isOn: $scope.showsPhotos)
                    scopeToggle(L10n.string("Videos", "Видео"), isOn: $scope.showsVideos)
                    scopeToggle(L10n.string("District point on the map", "Точка района на карте"), isOn: $scope.showOnMap)
                    scopeToggle(L10n.string("My game searches", "Мои игровые поиски"), isOn: $scope.showsSearches)
                    scopeToggle(L10n.string("Guests without an account", "Гостям без входа"), isOn: $scope.visibleToGuests)
                }
                .padding(14)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func scopeToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.subheadline)
            .foregroundStyle(AppTheme.ink)
            .tint(AppTheme.court)
    }

    private var termsCheckbox: some View {
        let terms = LegalDocuments.userAgreementURL?.absoluteString ?? "https://sportsearch.shop/legal/terms"
        let markdown = L10n.string(
            "I accept the new version of the [User Agreement](\(terms))",
            "Принимаю новую редакцию [пользовательского соглашения](\(terms))"
        )
        return checkbox(isOn: $termsAccepted, markdown: markdown)
    }

    private var analyticsCheckbox: some View {
        let details = LegalDocuments.analyticsConsentURL?.absoluteString ?? "https://sportsearch.shop/legal/analytics"
        let markdown = L10n.string(
            "Allow usage analytics ([details](\(details)))",
            "Разрешить аналитику использования ([подробнее](\(details)))"
        )
        return checkbox(isOn: $analytics, markdown: markdown)
    }

    private func checkbox(isOn: Binding<Bool>, markdown: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                isOn.wrappedValue.toggle()
                AppHaptics.selection()
            } label: {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? AppTheme.court : AppTheme.ink.opacity(0.45))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])

            Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .tint(AppTheme.court)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "",
                text: $fullName,
                prompt: Text(L10n.string("Surname and first name", "Фамилия и имя"))
                    .foregroundColor(AppTheme.ink.opacity(0.4))
            )
                .foregroundStyle(AppTheme.ink)
                .tint(AppTheme.court)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isNameFocused)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isNameFocused ? AppTheme.court.opacity(0.7) : Color(.systemGray4), lineWidth: 1)
                )
            Text(needsSurname
                 ? L10n.string("Add your surname — your first name is taken from your profile. Not shown on your profile.", "Добавьте фамилию — имя уже взяли из анкеты. В анкете её не покажем.")
                 : L10n.string("Needed for the consent. Not shown on your profile.", "Нужны для согласия. В анкете не показываем."))
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                submit(visible: true)
            } label: {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(isLegacy
                         ? L10n.string("Keep my profile visible", "Оставить анкету видимой")
                         : L10n.string("Show my profile", "Показывать анкету"))
                }
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(isSaving)

            Button(hidesAsSecondary
                   ? L10n.string("Hide my profile", "Скрыть анкету")
                   : L10n.string("Not now", "Пока не показывать")) {
                submit(visible: false)
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(isSaving)

            if mode == .settings {
                Button(L10n.string("Cancel", "Отмена")) { onFinished() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .padding(.top, 2)
            }

            let consentURL = LegalDocuments.profileVisibilityConsentURL?.absoluteString ?? "https://sportsearch.shop/legal/profile-visibility"
            Text((try? AttributedString(markdown: L10n.string(
                "This button is your [consent to showing your profile](\(consentURL))",
                "Кнопка — это [согласие на показ](\(consentURL))"
            ))) ?? AttributedString(""))
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .tint(AppTheme.court)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    private func submit(visible: Bool) {
        errorText = nil
        if consents.termsUpdateRequired && !termsAccepted {
            errorText = L10n.string("Accept the new version of the agreement to continue", "Примите новую редакцию соглашения, чтобы продолжить")
            AppHaptics.notification(.warning)
            return
        }

        var update = ConsentUpdate(
            acceptAgreementVersion: consents.termsUpdateRequired ? LegalDocuments.userAgreementVersion : nil,
            analytics: analytics
        )
        if visible {
            guard let name = ConsentNameValidator.normalized(fullName) else {
                errorText = L10n.string("Enter your surname and first name", "Укажите фамилию и имя")
                isNameFocused = true
                AppHaptics.notification(.warning)
                return
            }
            update.profile = ConsentUpdate.Profile(
                decision: "visible",
                fullName: name,
                visibleToGuests: scope.visibleToGuests,
                showsBio: scope.showsBio,
                showsPhotos: scope.showsPhotos,
                showsVideos: scope.showsVideos,
                showsSearches: scope.showsSearches,
                showOnMap: scope.showOnMap
            )
        } else {
            update.profile = ConsentUpdate.Profile(decision: "hidden")
        }

        isSaving = true
        Task {
            let failure = await appModel.submitConsents(update)
            isSaving = false
            if let failure {
                errorText = failure
                AppHaptics.notification(.error)
            } else {
                AppHaptics.notification(.success)
                onFinished()
            }
        }
    }
}
