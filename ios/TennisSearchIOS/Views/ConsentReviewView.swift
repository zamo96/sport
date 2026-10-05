import PhotosUI
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

    /// До ответа лента предлагает показывать всё: человек соглашается
    /// кнопкой на то, что видит в карточке, а лента позволяет только сузить
    /// показ. После ответа экран открывается с тем, что человек выбрал; у скрытой
    /// анкеты это прежний выбор, если он был.
    init(profile: UserProfile) {
        showOnMap = profile.showOnMap
        guard let consents = profile.consents,
              consents.profileVisibility == "visible" || (consents.isHidden && consents.hasChosenScope) else {
            return
        }
        visibleToGuests = consents.visibleToGuests
        showsBio = consents.showsBio
        showsPhotos = consents.showsPhotos
        showsVideos = consents.showsVideos
        showsSearches = consents.showsSearches
    }
}

/// Скрытая анкета везде выглядит одинаково: серая, чуть размытая, с замком.
struct HiddenProfileEffect: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .grayscale(isOn ? 0.75 : 0)
            .blur(radius: isOn ? 1.2 : 0)
            .opacity(isOn ? 0.62 : 1)
    }
}

extension View {
    func hiddenProfileEffect(_ isOn: Bool) -> some View { modifier(HiddenProfileEffect(isOn: isOn)) }
}

/// Замок с подписью поверх серой карточки.
struct HiddenProfileBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 14, weight: .bold))
            Text(L10n.string("Profile hidden", "Анкета скрыта")).font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppTheme.ink.opacity(0.85), in: Capsule())
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

/// Шесть пунктов ленты «что показывать».
enum ConsentScopeItem: CaseIterable, Identifiable {
    case bio, photos, videos, map, searches, guests

    var id: Self { self }

    var keyPath: WritableKeyPath<ConsentScope, Bool> {
        switch self {
        case .bio: return \.showsBio
        case .photos: return \.showsPhotos
        case .videos: return \.showsVideos
        case .map: return \.showOnMap
        case .searches: return \.showsSearches
        case .guests: return \.visibleToGuests
        }
    }

    /// Полное название: для подписи над лентой и для VoiceOver.
    var title: String {
        switch self {
        case .bio: return L10n.string("Description", "Описание")
        case .photos: return L10n.string("Photos", "Фото")
        case .videos: return L10n.string("Videos", "Видео")
        case .map: return L10n.string("Preferred districts on the map", "Удобные районы на карте")
        case .searches: return L10n.string("My game searches", "Мои игровые поиски")
        case .guests: return L10n.string("Guests without an account", "Гостям без входа")
        }
    }

    /// Короткая подпись на чипе. Чип по ширине равен подписи, поэтому ничего не вылезает.
    var chipTitle: String {
        switch self {
        case .map: return L10n.string("Districts on map", "Районы на карте")
        case .searches: return L10n.string("My searches", "Мои поиски")
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .bio: return "text.alignleft"
        case .photos: return "photo"
        case .videos: return "video"
        case .map: return "mappin.and.ellipse"
        case .searches: return "magnifyingglass"
        case .guests: return "eye"
        }
    }
}

/// Экран согласия на показ анкеты (ст. 10.1 152-ФЗ). Кнопка «Показывать
/// анкету» — само согласие. Принятие новой редакции соглашения — отдельная
/// отметка; аналитика спрашивается отдельно и позже (`AnalyticsAskCard`).
///
/// Всё помещается на один экран без прокрутки: имя и фамилию вводят в закреплённом
/// низу над кнопками, а при клавиатуре карточка сжимается. После «Показывать
/// анкету» карточка увеличивается и предлагает добавить фото.
struct ConsentReviewView: View {
    enum Mode {
        /// После анкеты или при первом открытии: закрыть без ответа нельзя.
        case required
        /// Из настроек профиля: можно закрыть без изменений.
        case settings
    }

    fileprivate enum Stage: Equatable {
        case form, confirmed, declined, media, added, done
    }

    let mode: Mode
    let profile: UserProfile
    var onFinished: () -> Void = {}

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scope: ConsentScope
    @State private var fullName: String
    @State private var termsAccepted = false
    @State private var lastToggled: (item: ConsentScopeItem, isOn: Bool)?
    @State private var stage = Stage.form
    @State private var appeared = false
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var localPhoto: UIImage?
    @State private var isPhotoDeveloped = true
    @State private var isUploadingPhoto = false
    @FocusState private var isNameFocused: Bool
    /// Photo height of the card at rest: shrinks on short screens so the switches stay above the footer.
    @State private var formPhotoHeight = ConsentProfileCard.restingPhotoHeight
    @State private var metrics = ConsentLayoutMetrics()
    @State private var viewportHeight: CGFloat = 0

    init(mode: Mode, profile: UserProfile, onFinished: @escaping () -> Void = {}) {
        self.mode = mode
        self.profile = profile
        self.onFinished = onFinished
        _scope = State(initialValue: ConsentScope(profile: profile))
        _fullName = State(initialValue: profile.consents?.fullName ?? "")
    }

    private var consents: ConsentState { profile.consents ?? ConsentState() }
    private var isLegacy: Bool { consents.isLegacy }
    private var hidesAsSecondary: Bool { isLegacy || consents.profileVisibility == "visible" }
    /// Экран открыт из настроек, а анкета уже скрыта / уже показывается: показываем это состояние.
    private var startsHidden: Bool { consents.isHidden }
    private var startsVisible: Bool { consents.profileVisibility == "visible" }
    private var isCompact: Bool { isNameFocused && stage == .form }
    private var needsSurname: Bool { fullName.split(whereSeparator: \.isWhitespace).count == 1 }
    /// Профиль с учётом загруженного на этом экране фото.
    private var liveProfile: UserProfile { appModel.currentUser ?? profile }
    private var hasPhoto: Bool { localPhoto != nil || !(liveProfile.profilePhotoUrls.isEmpty && liveProfile.avatarUrl == nil) }
    private var spring: Animation { reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.84) }

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                GeometryReader { viewport in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if stage == .form { header }

                        ConsentProfileCard(
                            profile: liveProfile,
                            scope: scope,
                            stage: stage,
                            isCompact: isCompact,
                            isHiddenNow: startsHidden && stage == .form,
                            showsVisibleBadge: startsVisible && stage == .form,
                            restingPhotoHeight: stage == .form ? formPhotoHeight : ConsentProfileCard.restingPhotoHeight,
                            hasPhoto: hasPhoto,
                            localPhoto: localPhoto,
                            isPhotoDeveloped: isPhotoDeveloped,
                            appeared: appeared,
                            reduceMotion: reduceMotion
                        )

                        if stage == .form {
                            if isCompact {
                                summaryRow
                            } else {
                                caption
                                scopeRail
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ConsentMetricsKey.self, value: ConsentLayoutMetrics(content: proxy.size.height))
                    })
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .onAppear { viewportHeight = viewport.size.height }
                .onChange(of: viewport.size.height) { viewportHeight = $0 }
                }
                .onPreferenceChange(ConsentMetricsKey.self) { metrics = $0 }
                .onChange(of: metrics) { _ in fitCard() }
                .onChange(of: viewportHeight) { _ in fitCard() }
                .onChange(of: stage) { _ in fitCard() }
                .onChange(of: isCompact) { _ in fitCard() }

                footer
            }
        }
        // Экран светлый, а главный экран включает тёмную тему — без этого поле
        // ввода и переключатели рисовались бы светлым по белому.
        .environment(\.colorScheme, .light)
        .interactiveDismissDisabled(mode == .required || stage != .form)
        .animation(spring, value: isNameFocused)
        .animation(spring, value: scope)
        .animation(spring, value: stage)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.62).delay(0.12)) {
                appeared = true
            }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
        }
    }

    /// Everything but the card's photo has a fixed height, so the photo takes what is left:
    /// on a tall phone it stays 110 pt, on a shorter one it gives up to 66 pt before the page scrolls.
    private func fitCard() {
        guard stage == .form, !isCompact, metrics.content > 0, metrics.photo > 0, viewportHeight > 0 else { return }
        let rest = metrics.content - metrics.photo
        let target = min(ConsentProfileCard.restingPhotoHeight, max(ConsentProfileCard.minimumPhotoHeight, viewportHeight - rest)).rounded(.down)
        if abs(target - formPhotoHeight) >= 1 { formPhotoHeight = target }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isLegacy
                 ? L10n.string("We've updated our terms", "Мы обновили правила")
                 : (startsHidden
                    ? L10n.string("You are hidden right now", "Сейчас вас не видно")
                    : (startsVisible
                       ? L10n.string("Your profile is visible", "Ваша анкета видна")
                       : L10n.string("Show your profile?", "Показывать вашу анкету?"))))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 6)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .accessibilityAddTraits(.isHeader)
            if startsHidden {
                Text(L10n.string("Your profile is hidden from search and the map. Turn showing on whenever you like.", "Анкета скрыта из поиска и с карты. Включите показ, когда захотите."))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 6)
            } else if isLegacy {
                Text(L10n.string("Consent to showing your profile is now a separate decision. Right now other players can see your profile.", "Согласие на показ анкеты теперь отдельное решение. Сейчас ваша анкета видна другим игрокам."))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 6)
            }
        }
    }

    private var caption: some View {
        let audience = scope.visibleToGuests
            ? L10n.string("Players and guests will see you like this in search and on the map.", "Так вас увидят игроки и гости в поиске и на карте.")
            : L10n.string("Signed-in players will see you like this in search and on the map.", "Так вас увидят игроки, вошедшие в аккаунт, в поиске и на карте.")
        let always = L10n.string("The map shows your chosen preferred districts. Name, age, city and sport are always visible.", "На карте — выбранные вами удобные районы для игры. Имя, возраст, город и спорт видны всегда.")
        let text = startsHidden
            ? L10n.string("Players and guests do not see your profile now. Choose what to show, then turn showing on.", "Игроки и гости вашу анкету сейчас не видят. Выберите, что показывать, и включите показ.")
            : "\(audience) \(always)"
        return Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(AppTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(reduceMotion ? 0 : 0.85), value: appeared)
            .transition(.opacity)
    }

    private var scopeRail: some View {
        let items = ConsentScopeItem.allCases
        let enabled = items.filter { scope[keyPath: $0.keyPath] }.count
        let label: String = lastToggled.map {
            $0.item.title + ($0.isOn ? L10n.string(" — shown", " — показываем") : L10n.string(" — hidden", " — скрыто"))
        } ?? L10n.string("Switch off anything you don't want to show", "Выключите то, что не хотите показывать")

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(L10n.string("\(enabled) of \(items.count)", "\(enabled) из \(items.count)"))
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink.opacity(0.5))
            }
            .padding(.horizontal, 6)

            ConsentScopeRail(scope: $scope, lastToggled: $lastToggled, reduceMotion: reduceMotion)
                .padding(.horizontal, -16)
        }
        .padding(.top, 4)
    }

    private var summaryRow: some View {
        let hidden = ConsentScopeItem.allCases.filter { !scope[keyPath: $0.keyPath] }
        return HStack {
            Text(hidden.isEmpty
                 ? L10n.string("Showing everything", "Показываем всё")
                 : L10n.string("Hidden: ", "Скрыто: ") + hidden.map { $0.chipTitle.lowercased() }.joined(separator: ", "))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.72))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(L10n.string("Change", "Изменить")) {
                isNameFocused = false
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.court)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 6)
        .transition(.opacity)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        switch stage {
        case .form:
            formFooter.transition(.move(edge: .bottom).combined(with: .opacity))
        case .confirmed, .declined:
            Color.clear.frame(height: 0)
        case .media:
            mediaFooter.transition(.move(edge: .bottom).combined(with: .opacity))
        case .added, .done:
            finishFooter.transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var formFooter: some View {
        let consentURL = LegalDocuments.profileVisibilityConsentURL?.absoluteString ?? "https://sportsearch.shop/legal/profile-visibility"
        return VStack(spacing: 0) {
            if consents.termsUpdateRequired {
                termsCheckbox.padding(.bottom, 10)
            }

            nameField

            Text(needsSurname
                 ? L10n.string("Add your surname. It is not shown on your profile.", "Добавьте фамилию. В анкете её не покажем.")
                 : L10n.string("Needed for the consent. Not shown on your profile.", "Нужны для согласия. В анкете не показываем."))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.top, 6)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }

            Button {
                submit(visible: true)
            } label: {
                ZStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(isLegacy
                             ? L10n.string("Keep my profile visible", "Оставить анкету видимой")
                             : (startsVisible
                                ? L10n.string("Save", "Сохранить")
                                : L10n.string("Show my profile", "Показывать анкету")))
                    }
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.top, 12)

            Button {
                if startsHidden { onFinished() } else { submit(visible: false) }
            } label: {
                Text(startsHidden
                     ? L10n.string("Keep it hidden", "Оставить скрытой")
                     : (hidesAsSecondary
                        ? L10n.string("Hide my profile", "Скрыть анкету")
                        : L10n.string("Not now", "Пока не показывать")))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.ink.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.top, 8)

            if mode == .settings, !startsHidden {
                Button(L10n.string("Cancel", "Отмена")) { onFinished() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(minHeight: 40)
            }

            if !isNameFocused {
                Text((try? AttributedString(markdown: L10n.string(
                    "This button is your [consent to showing your profile](\(consentURL)). You can withdraw it any time: Profile → Privacy.",
                    "Кнопка — это [согласие на показ](\(consentURL)). Отозвать можно в любой момент: Профиль → Приватность."
                ))) ?? AttributedString(""))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedInk)
                    .tint(AppTheme.court)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(AppTheme.cream.opacity(0.94))
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.ink.opacity(0.08)).frame(height: 1) }
        .offset(y: appeared ? 0 : 46)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(reduceMotion ? 0 : 0.9), value: appeared)
    }

    private var mediaFooter: some View {
        VStack(spacing: 8) {
            Text(L10n.string("Only people you allowed to see your profile will see the photo. Videos can be added in your Profile.", "Фото увидят те, кому вы разрешили показ анкеты. Видео можно добавить в Профиле."))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    if isUploadingPhoto {
                        ProgressView().tint(.white)
                    } else {
                        Text(L10n.string("Add a photo", "Добавить фото"))
                    }
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(isUploadingPhoto)
            .accessibilityIdentifier("consent-add-photo")

            Button {
                AppHaptics.selection()
                withAnimation(spring) { stage = .done }
            } label: {
                Text(L10n.string("Later", "Позже"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isUploadingPhoto)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.cream.opacity(0.94))
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.ink.opacity(0.08)).frame(height: 1) }
    }

    private var finishFooter: some View {
        VStack(spacing: 10) {
            Text(stage == .added
                 ? L10n.string("Done: this is how players will see you. More photos and videos can be added in your Profile.", "Готово: так вас увидят игроки. Ещё фото и видео можно добавить в Профиле.")
                 : L10n.string("Photos and videos can be added any time: Profile → Media.", "Фото и видео можно добавить в любой момент: Профиль → Медиа."))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            Button {
                finish()
            } label: {
                Text(L10n.string("Continue", "Продолжить"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("consent-continue")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.cream.opacity(0.94))
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.ink.opacity(0.08)).frame(height: 1) }
    }

    private var termsCheckbox: some View {
        let terms = LegalDocuments.userAgreementURL?.absoluteString ?? "https://sportsearch.shop/legal/terms"
        let markdown = L10n.string(
            "I accept the new version of the [User Agreement](\(terms))",
            "Принимаю новую редакцию [пользовательского соглашения](\(terms))"
        )
        return HStack(alignment: .top, spacing: 12) {
            Button {
                termsAccepted.toggle()
                AppHaptics.selection()
            } label: {
                Image(systemName: termsAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(termsAccepted ? AppTheme.court : AppTheme.ink.opacity(0.45))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(termsAccepted ? .isSelected : [])

            Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .tint(AppTheme.court)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private var nameField: some View {
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
        .submitLabel(.done)
        .onSubmit { isNameFocused = false }
        .focused($isNameFocused)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isNameFocused ? AppTheme.court.opacity(0.8) : Color(.systemGray4), lineWidth: 1)
        )
        .accessibilityLabel(L10n.string("Surname and first name", "Фамилия и имя"))
    }

    // MARK: Actions

    private func submit(visible: Bool) {
        errorText = nil
        if consents.termsUpdateRequired && !termsAccepted {
            errorText = L10n.string("Accept the new version of the agreement to continue", "Примите новую редакцию соглашения, чтобы продолжить")
            AppHaptics.notification(.warning)
            return
        }

        var update = ConsentUpdate(acceptAgreementVersion: consents.termsUpdateRequired ? LegalDocuments.userAgreementVersion : nil)
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

        isNameFocused = false
        isSaving = true
        // The server clears "review required" with the answer, which would close this screen
        // before its finish has played and before the photo is offered.
        if mode == .required { appModel.holdConsentFlow(true) }
        Task {
            let failure = await appModel.submitConsents(update)
            isSaving = false
            if let failure {
                if mode == .required { appModel.holdConsentFlow(false) }
                errorText = failure
                AppHaptics.notification(.error)
                return
            }
            await playFinish(visible: visible)
        }
    }

    @MainActor
    private func playFinish(visible: Bool) async {
        AppHaptics.notification(visible ? .success : .warning)
        withAnimation(spring) { stage = visible ? .confirmed : .declined }
        try? await Task.sleep(nanoseconds: reduceMotion ? 400_000_000 : 950_000_000)
        let offersPhoto = visible && mode == .required && scope.showsPhotos && !hasPhoto
        if offersPhoto {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.75, dampingFraction: 0.7)) {
                stage = .media
            }
        } else {
            finish()
        }
    }

    private func finish() {
        if mode == .required { appModel.holdConsentFlow(false) }
        onFinished()
    }

    @MainActor
    private func uploadPhoto(_ item: PhotosPickerItem) async {
        let generation = appModel.sessionGeneration
        errorText = nil
        isUploadingPhoto = true
        defer {
            isUploadingPhoto = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.88) else {
            errorText = L10n.string("Could not read the selected photo", "Не удалось прочитать выбранное фото")
            return
        }
        do {
            let result = try await appModel.repository.uploadProfileMedia(data: jpeg, fileName: "profile-photo-1.jpg", mimeType: "image/jpeg")
            guard appModel.isCurrentSession(generation) else { return }
            if var user = appModel.currentUser {
                user.profilePhotoUrls = result.profilePhotoUrls
                user.profileVideoUrls = result.profileVideoUrls
                user.avatarUrl = result.avatarUrl ?? result.profilePhotoUrls.first
                if let order = result.profileMediaOrder { user.profileMediaOrder = order }
                appModel.currentUser = user
            }
            localPhoto = image
            isPhotoDeveloped = false
            AppHaptics.notification(.success)
            withAnimation(spring) { stage = .added }
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { isPhotoDeveloped = true }
        } catch {
            guard appModel.isCurrentSession(generation), !error.isCancellationLike else { return }
            errorText = error.isServerIssue ? error.serverRecoveryMessage : error.detailedMessage
            AppHaptics.notification(.error)
        }
    }
}

// MARK: - Scope rail

/// The six "what to show" switches as one row of chips. Each chip is as wide as its label, so
/// nothing can spill out of it; the row scrolls sideways and hints at that once.
private struct ConsentScopeRail: View {
    @Binding var scope: ConsentScope
    @Binding var lastToggled: (item: ConsentScopeItem, isOn: Bool)?
    let reduceMotion: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ConsentScopeItem.allCases) { item in
                        chip(item).id(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.trailing, 40)
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                withAnimation(.easeInOut(duration: 0.55)) { proxy.scrollTo(ConsentScopeItem.searches, anchor: .trailing) }
                try? await Task.sleep(nanoseconds: 750_000_000)
                withAnimation(.easeInOut(duration: 0.55)) { proxy.scrollTo(ConsentScopeItem.bio, anchor: .leading) }
            }
        }
    }

    private func chip(_ item: ConsentScopeItem) -> some View {
        let isOn = scope[keyPath: item.keyPath]
        return Button {
            scope[keyPath: item.keyPath].toggle()
            lastToggled = (item, scope[keyPath: item.keyPath])
            AppHaptics.selection()
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                    Capsule()
                        .frame(width: 18, height: 2)
                        .rotationEffect(.degrees(-45))
                        .scaleEffect(x: isOn ? 0.001 : 1, y: 1)
                }
                .frame(width: 20, height: 20)
                Text(item.chipTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 11)
            .padding(.trailing, 14)
            .frame(height: 36)
            .foregroundStyle(isOn ? Color.white : AppTheme.ink.opacity(0.72))
            .background(isOn ? AppTheme.ink : Color.white.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(isOn ? AppTheme.ink : AppTheme.ink.opacity(0.28), lineWidth: 1))
            .animation(.easeOut(duration: 0.25), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(isOn ? L10n.string("shown", "показываем") : L10n.string("hidden", "скрыто"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Fitting

struct ConsentLayoutMetrics: Equatable {
    var content: CGFloat = 0
    var photo: CGFloat = 0
}

struct ConsentMetricsKey: PreferenceKey {
    static var defaultValue = ConsentLayoutMetrics()
    static func reduce(value: inout ConsentLayoutMetrics, nextValue: () -> ConsentLayoutMetrics) {
        let next = nextValue()
        value.content = max(value.content, next.content)
        value.photo = max(value.photo, next.photo)
    }
}

// MARK: - The card

/// How the profile looks to other players, live: it follows the switches, pops up on entry,
/// stamps itself on "Show", dims on "Not now" and grows to ask for a photo.
private struct ConsentProfileCard: View {
    let profile: UserProfile
    let scope: ConsentScope
    let stage: ConsentReviewView.Stage
    let isCompact: Bool
    /// Анкета уже скрыта и человек ещё не решил показывать: карточка серая, как после «Не сейчас».
    var isHiddenNow = false
    /// Анкета уже показывается: отметка вместо предложения.
    var showsVisibleBadge = false
    var restingPhotoHeight: CGFloat = ConsentProfileCard.restingPhotoHeight
    let hasPhoto: Bool
    let localPhoto: UIImage?
    let isPhotoDeveloped: Bool
    let appeared: Bool
    let reduceMotion: Bool

    @State private var isFloating = false
    @State private var isRingOut = false

    private var isBig: Bool { stage == .media || stage == .added }
    static let restingPhotoHeight: CGFloat = 110
    static let minimumPhotoHeight: CGFloat = 44
    private var photoHeight: CGFloat { isCompact ? 30 : (isBig ? 300 : restingPhotoHeight) }
    private var showsUserPhoto: Bool { hasPhoto && scope.showsPhotos }
    private var isConfirmed: Bool { stage == .confirmed }
    private var isDeclined: Bool { stage == .declined }
    private var isDimmed: Bool { isDeclined || isHiddenNow }
    private var sport: Sport { profile.preferredSports.first ?? .tennis }
    private let lime = Color(red: 0.84, green: 0.98, blue: 0.34)
    private let deep = Color(red: 0.055, green: 0.165, blue: 0.13)

    var body: some View {
        card
            .scaleEffect((isConfirmed ? 1.02 : (isDeclined ? 0.97 : 1)))
            .offset(y: isConfirmed ? -10 : 0)
            .hiddenProfileEffect(isDimmed)
            .shadow(color: AppTheme.ink.opacity(isConfirmed ? 0.36 : 0.26), radius: isConfirmed ? 26 : 20, y: isConfirmed ? 16 : 10)
            .overlay {
                if isConfirmed {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(lime, lineWidth: 3)
                        .padding(-6)
                        .scaleEffect(isRingOut ? 1.14 : 1)
                        .opacity(isRingOut ? 0 : 0.85)
                        .allowsHitTesting(false)
                        .onAppear { withAnimation(.easeOut(duration: 0.9)) { isRingOut = true } }
                        .onDisappear { isRingOut = false }
                }
            }
            .offset(y: (appeared ? 0 : 90) + (isFloating ? -3 : 0))
            .scaleEffect(appeared ? 1 : 0.86)
            .rotationEffect(.degrees(appeared ? 0 : -3.5))
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isConfirmed)
            .animation(.easeOut(duration: 0.5), value: isDimmed)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { isFloating = true }
            }
            .accessibilityElement(children: .combine)
    }

    private var card: some View {
        VStack(spacing: 0) {
            photoArea
                .frame(height: photoHeight)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ConsentMetricsKey.self, value: ConsentLayoutMetrics(photo: proxy.size.height))
                })
                .clipped()
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.72), value: photoHeight)
            info
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.165, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: Photo area

    private var photoArea: some View {
        ZStack {
            Color(red: 0.11, green: 0.29, blue: 0.24)

            if showsUserPhoto {
                userPhoto
                    .blur(radius: isPhotoDeveloped ? 0 : 16)
                    .saturation(isPhotoDeveloped ? 1 : 0)
                    .scaleEffect(isPhotoDeveloped ? 1 : 1.15)
                    .transition(.opacity)
            } else if stage != .media {
                avatar(size: isCompact ? 0 : min(stage == .done || showsVisibleBadge ? 76 : 92, restingPhotoHeight - 14))
                    .transition(.opacity)
            }

            if stage == .media, !showsUserPhoto {
                addFrame.transition(.opacity)
            }

            if scope.showsVideos, !profile.profileVideoUrls.isEmpty, stage == .form, !isCompact {
                Text("▶ " + L10n.string("Video", "Видео"))
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
            }

            if isConfirmed {
                stamp
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(14)
            }

            if stage == .media || stage == .added || stage == .done {
                Text("✓ " + L10n.string("Profile is visible", "Анкета видна"))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(lime, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isDeclined || (isHiddenNow && !isCompact) {
                HiddenProfileBadge()
                    .transition(.scale.combined(with: .opacity))
            }

            if showsVisibleBadge, !isCompact {
                Text("✓ " + L10n.string("Profile is visible", "Анкета видна"))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(lime, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: showsUserPhoto)
    }

    @ViewBuilder
    private var userPhoto: some View {
        if let localPhoto {
            // Fill the card without letting the picture's own size stretch it.
            Color.clear
                .overlay { Image(uiImage: localPhoto).resizable().scaledToFill() }
                .clipped()
        } else {
            let path = profile.profilePhotoUrls.first ?? profile.avatarUrl
            RemoteImage(url: resolveAppRemoteURL(path), contentMode: .fill) { _ in
                avatar(size: 92)
            }
        }
    }

    private func avatar(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(lime.opacity(0.10))
            SportAvatarView(sport: sport)
        }
        .frame(width: size, height: size)
        .opacity(size == 0 ? 0 : 1)
    }

    private var addFrame: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(lime.opacity(0.10))
                    SportAvatarView(sport: sport)
                }
                .frame(width: 112, height: 112)
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 34, height: 34)
                    .background(lime, in: Circle())
                    .overlay(Circle().stroke(Color(red: 0.08, green: 0.23, blue: 0.19), lineWidth: 3))
                    .offset(x: 2, y: 2)
            }
            Text(L10n.string("Add a photo", "Добавьте фото"))
                .font(.system(size: 18, weight: .heavy))
            Text(L10n.string("It makes you easier to recognise and choose to play with", "Так вас проще узнать и выбрать для игры"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(lime.opacity(isFloating ? 0.3 : 0.75), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .padding(14)
        )
    }

    private var stamp: some View {
        Text("✓ " + L10n.string("PROFILE IS VISIBLE", "АНКЕТА ВИДНА"))
            .font(.system(size: 13, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(lime, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.ink.opacity(0.35), lineWidth: 2))
            .rotationEffect(.degrees(-9))
            .transition(reduceMotion ? .opacity : .scale(scale: 2.2).combined(with: .opacity))
    }

    // MARK: Info

    private var info: some View {
        let title = [profile.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty, profile.age.map(String.init)]
            .compactMap { $0 }
            .joined(separator: ", ")
        let showsBio = scope.showsBio && !isCompact && (profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let showsMap = scope.showOnMap && !isCompact
        let showsSearch = scope.showsSearches && !isCompact && profile.isLookingForGame

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title.isEmpty ? L10n.string("Your profile", "Ваша анкета") : title)
                    .font(.system(size: 22, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if profile.isVerified {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 20, height: 20)
                        .background(lime, in: Circle())
                }
            }
            .reveal(appeared, index: 0, reduceMotion: reduceMotion)

            ConsentChipFlow(spacing: 6) {
                ForEach(Array(profile.preferredSports.prefix(3).enumerated()), id: \.offset) { index, sport in
                    let level = profile.sportLevels[sport.rawValue].map { " · \($0)" } ?? ""
                    chip(sport.title + level, tinted: index == 0)
                }
                if let city = profile.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
                    chip(city, tinted: false)
                }
            }
            .reveal(appeared, index: 1, reduceMotion: reduceMotion)

            if showsBio {
                Text(profile.bio ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showsMap {
                chip(mapText, tinted: false, symbol: "mappin.and.ellipse")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showsSearch {
                chip(L10n.string("Looking for a game", "Ищу игру"), tinted: true, symbol: "clock")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: showsBio)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: showsMap)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: showsSearch)
    }

    private var mapText: String {
        let names = profile.preferredDistricts.compactMap { localizedDistrictName($0) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return L10n.string("On the map: whole city", "На карте: весь город") }
        let shown = names.prefix(2).joined(separator: ", ")
        let rest = names.count > 2 ? " +\(names.count - 2)" : ""
        return L10n.string("On the map: ", "На карте: ") + shown + rest
    }

    private func chip(_ text: String, tinted: Bool, symbol: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
            Text(text).font(.system(size: 13, weight: tinted ? .bold : .semibold)).lineLimit(1)
        }
        .foregroundStyle(tinted ? lime : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(tinted ? lime.opacity(0.18) : .white.opacity(0.14), in: Capsule())
    }
}

private extension View {
    /// Rows of the card come in one after another once it has popped up.
    func reveal(_ appeared: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.55 + 0.1 * Double(index)), value: appeared)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Chips that wrap to the next line instead of overflowing.
private struct ConsentChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Привязка номера к уже открытому аккаунту, из настроек: ещё один способ входа,
/// пока на сервере включён вход по SMS.
struct PhoneLinkView: View {
    var onFinished: () -> Void = {}

    @EnvironmentObject private var appModel: AppModel
    @State private var phone = ""
    @State private var isPhoneFocused = false
    @State private var code = ""
    @State private var isCodeSent = false
    @State private var debugCode: String?
    @State private var errorText: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case phone, code }

    private var displayedPhone: String {
        RussianPhone.formatted(RussianPhone.normalized(phone) ?? phone)
    }

    var body: some View {
        // A NavigationStack only so the number pad can carry a "Done" button.
        NavigationStack {
            ZStack {
                AppTheme.pageBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.string("Add your phone number", "Добавьте номер телефона"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text(L10n.string(
                            "Add your phone number to sign in to this account with it.",
                            "Привяжите номер телефона, чтобы входить по нему в этот аккаунт."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text("+7")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                            RussianPhoneField(digits: $phone, isFocused: $isPhoneFocused)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 58)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isPhoneFocused ? AppTheme.court.opacity(0.7) : Color(.systemGray4), lineWidth: 1)
                        )
                        .disabled(isCodeSent)
                        .opacity(isCodeSent ? 0.6 : 1)

                        if isCodeSent {
                            Text(L10n.string("SMS code sent to \(displayedPhone)", "Код отправлен по SMS на \(displayedPhone)"))
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                            if let debugCode {
                                Text("Debug OTP: \(debugCode)")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.orange)
                            }
                            field(text: $code, prompt: "000000", keyboard: .numberPad, content: .oneTimeCode, focus: .code)
                        }

                        if let errorText {
                            Label(errorText, systemImage: "exclamationmark.triangle")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            if isCodeSent { confirm() } else { requestCode() }
                        } label: {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text(isCodeSent ? L10n.string("Confirm", "Подтвердить") : L10n.string("Get an SMS code", "Получить код по SMS"))
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                        .disabled(isSaving || (isCodeSent && code.filter(\.isNumber).count != 6))

                        if isCodeSent {
                            Button(L10n.string("Change number", "Изменить номер")) {
                                isCodeSent = false
                                code = ""
                                errorText = nil
                            }
                            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
                        }

                        Button(L10n.string("Cancel", "Отмена")) {
                            onFinished()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedInk)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.string("Done", "Готово")) { focusedField = nil }
                        .font(.headline.weight(.bold))
                }
            }
        }
        // Как экран согласия: светлый, даже если под ним тёмная тема.
        .environment(\.colorScheme, .light)
    }

    private func field(text: Binding<String>, prefix: String? = nil, prompt: String, keyboard: UIKeyboardType, content: UITextContentType, focus: Field) -> some View {
        HStack(spacing: 8) {
            if let prefix {
                Text(prefix)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
            }
            TextField("", text: text, prompt: Text(prompt).foregroundColor(AppTheme.ink.opacity(0.4)))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .tint(AppTheme.court)
                .keyboardType(keyboard)
                .textContentType(content)
                .focused($focusedField, equals: focus)
        }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focusedField == focus ? AppTheme.court.opacity(0.7) : Color(.systemGray4), lineWidth: 1)
            )
    }

    private func requestCode() {
        errorText = nil
        isSaving = true
        Task {
            let result = await appModel.requestPhoneLinkCode(phone: phone)
            isSaving = false
            if let error = result.error {
                errorText = error
                AppHaptics.notification(.warning)
            } else {
                debugCode = result.debugCode
                isCodeSent = true
                focusedField = .code
            }
        }
    }

    private func confirm() {
        errorText = nil
        isSaving = true
        Task {
            let failure = await appModel.verifyPhoneLink(phone: phone, code: code.filter(\.isNumber))
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
