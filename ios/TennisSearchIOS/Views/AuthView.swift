import AuthenticationServices
import CoreLocation
import SwiftUI

private enum OnboardingProfileField: Hashable {
    case name
    case age
}

private let onboardingDefaultCity = SupportedCity.saintPetersburg.rawValue
private let onboardingSupportedCities = SupportedCity.selectableCases
private let onboardingCityOptions = onboardingSupportedCities.map(\.rawValue)
private let onboardingAvailableCities = Set(onboardingSupportedCities)
private let onboardingCityImageNames: [SupportedCity: String] = [
    .saintPetersburg: "OnboardingCitySaintPetersburg",
    .moscow: "OnboardingCityMoscow"
]

private func onboardingCityImageName(for cityName: String) -> String? {
    guard let city = SupportedCity.resolve(cityName) else {
        return nil
    }

    return onboardingCityImageNames[city]
}

private func isOnboardingCityAvailable(_ city: String) -> Bool {
    guard let city = SupportedCity.resolve(city.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return false
    }

    return onboardingAvailableCities.contains(city)
}

private func onboardingDistrictOptions(for cityName: String) -> [String] {
    guard let city = SupportedCity.resolve(cityName) else {
        return []
    }

    return districtAreasByID.values
        .filter { $0.city == city }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        .map(\.id)
}

private func filteredOnboardingDistricts(_ districts: [String], cityName: String) -> [String] {
    guard let city = SupportedCity.resolve(cityName) else {
        return []
    }

    return districts
        .map { $0.lowercased() }
        .filter { districtBelongsToCity($0, city: city) }
        .uniqued()
}

private func localizedOnboardingSportTitle(_ sport: Sport) -> String {
    let english: String
    switch sport {
    case .tennis: english = "Tennis"
    case .padel: english = "Padel"
    case .running: english = "Running"
    case .supboard: english = "SUP boarding"
    case .squash: english = "Squash"
    case .badminton: english = "Badminton"
    case .tableTennis: english = "Table tennis"
    case .volleyball: english = "Volleyball"
    case .fitness: english = "Fitness"
    case .boxing: english = "Boxing"
    case .yoga: english = "Yoga"
    case .football: english = "Football"
    }
    return L10n.string(english, sport.title)
}

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    /// Страница VK ID для входа в России открывается в ASWebAuthenticationSession.
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @EnvironmentObject private var appModel: AppModel

    @State private var code = ""
    @State private var codeVerdict = OTPCodeField.Verdict.none
    @State private var draft: GuestOnboardingDraft
    @State private var step: AuthStep
    @State private var appStats: AppStats?
    @State private var selectedLevelSport: Sport?
    @State private var selectedLocationChoice: OnboardingLocationChoice?
    @State private var showsLocationPicker = false
    @State private var locationPickerRequestsAutomatically = false
    @State private var showsDistrictPicker = false
    @State private var automaticallyDetectedDistrict: String?
    @State private var acceptsDetectedLocationUpdates = false
    @State private var isDetectedDistrictConfirmed = false
    @State private var didAutoRequestAvailabilityLocation = false
    @State private var hasEditedAge = false
    @State private var hasAttemptedProfileContinue = false
    @State private var isIntentStepPresented = false
    @State private var stepAfterIntents: AuthStep = .profile
    @StateObject private var locationPermission = OnboardingLocationPermission()
    @FocusState private var profileFocusedField: OnboardingProfileField?

    let embedded: Bool

    init(initialStep: AuthStep = .intro, embedded: Bool = true) {
        _step = State(initialValue: initialStep)
        _draft = State(initialValue: .default)
        self.embedded = embedded
    }

    var body: some View {
        NavigationStack {
            contentForStep
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded && step != .email {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.string("Close", "Закрыть")) {
                            appModel.dismissPresentedAuth()
                            dismiss()
                        }
                    }
                }

                if step == .profile && profileFocusedField != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button(L10n.string("Hide", "Скрыть")) {
                            profileFocusedField = nil
                        }

                        Spacer()

                        Button(L10n.string("Done", "Готово")) {
                            profileFocusedField = nil
                        }
                        .font(.headline.weight(.bold))
                    }
                }
            }
            .task {
                let savedDraft = appModel.guestDraft
                var normalizedSavedDraft = normalizedDraft(savedDraft)
                if let user = appModel.currentUser, !user.isOnboardingComplete {
                    normalizedSavedDraft.showOnMap = OnboardingMapVisibility.resolved(stored: user.showOnMap, draft: savedDraft.showOnMap, completed: false)
                }
                draft = normalizedSavedDraft
                if normalizedSavedDraft != savedDraft {
                    appModel.updateGuestDraft(normalizedSavedDraft)
                }
                selectedLocationChoice = draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.preferredDistricts.isEmpty ? nil : .districts
                if appModel.isAuthenticated && !appModel.isOnboardingComplete {
                    step = draft.hasProfileBasics ? .availability : .profile
                    if !appModel.hasChosenUserIntents {
                        stepAfterIntents = step
                        isIntentStepPresented = true
                    }
                } else if appModel.presentedAuthStep == .code {
                    step = .code
                }
                await loadAppStats()
            }
            .onChange(of: draft.showOnMap) { _ in persistDraft() }
            .onChange(of: appModel.presentedAuthStep) { newValue in
                guard let newValue else {
                    return
                }
                step = newValue
                isIntentStepPresented = false
            }
            .onChange(of: appModel.currentUser?.id) { newValue in
                if newValue != nil {
                    if !appModel.isOnboardingComplete {
                        draft = normalizedDraft(appModel.guestDraft)
                        step = draft.hasProfileBasics ? .availability : .profile
                        stepAfterIntents = step
                        isIntentStepPresented = !appModel.hasChosenUserIntents
                    } else {
                        isIntentStepPresented = false
                    }
                    if !embedded { dismiss() }
                }
            }
            .sheet(item: $selectedLevelSport) { sport in
                OnboardingLevelPickerSheet(
                    level: Binding(
                        get: { draft.sportLevels[sport.rawValue] ?? 5 },
                        set: { newValue in
                            if !draft.preferredSports.contains(sport) {
                                draft.preferredSports.append(sport)
                            }
                            draft.sportLevels[sport.rawValue] = newValue
                        }
                    )
                )
                .presentationDetents([.height(455)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsLocationPicker) {
                GlobalLocationPickerSheet(
                    repository: appModel.repository,
                    initialLocation: draft.location,
                    automaticallyRequestsLocation: locationPickerRequestsAutomatically,
                    onSelect: applySelectedLocation
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsDistrictPicker, onDismiss: {
                guard selectedLocationChoice != .nearby else {
                    return
                }
                selectedLocationChoice = draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.preferredDistricts.isEmpty ? nil : .districts
            }) {
                OnboardingDistrictPickerSheet(
                    selectedCity: $draft.city,
                    selectedDistricts: $draft.preferredDistricts,
                    automaticallyDetectedDistrict: automaticallyDetectedDistrict,
                    startsWithDistricts: true,
                    onDetectAutomatically: {
                        showsDistrictPicker = false
                        selectedLocationChoice = .nearby
                        isDetectedDistrictConfirmed = false
                        automaticallyDetectedDistrict = nil
                        acceptsDetectedLocationUpdates = true
                        draft.city = ""
                        draft.preferredDistricts.removeAll()
                        draft.district = nil
                        locationPermission.requestLocationAccess()
                        AppHaptics.selection()
                    },
                    onDone: {
                        draft.city = draft.city.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.preferredDistricts = filteredOnboardingDistricts(draft.preferredDistricts, cityName: draft.city)
                        draft.district = draft.preferredDistricts.first
                        if let detectedDistrict = automaticallyDetectedDistrict {
                            if let city = SupportedCity.resolve(draft.city) {
                                if !districtBelongsToCity(detectedDistrict, city: city) {
                                    automaticallyDetectedDistrict = nil
                                }
                            } else {
                                automaticallyDetectedDistrict = nil
                            }
                        }
                        selectedLocationChoice = draft.city.isEmpty && draft.preferredDistricts.isEmpty
                            ? nil
                            : (automaticallyDetectedDistrict == nil ? .districts : .nearby)
                        isDetectedDistrictConfirmed = automaticallyDetectedDistrict != nil
                        acceptsDetectedLocationUpdates = false
                        showsDistrictPicker = false
                        persistDraft()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: locationPermission.detectedDistrict) { district in
                guard acceptsDetectedLocationUpdates,
                      let district,
                      let detectedCityName = locationPermission.detectedCity,
                      let detectedCity = SupportedCity.resolve(detectedCityName),
                      onboardingAvailableCities.contains(detectedCity),
                      districtBelongsToCity(district, city: detectedCity) else {
                    return
                }
                guard step == .availability else {
                    return
                }

                let currentCity = SupportedCity.resolve(draft.city)
                guard draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentCity == detectedCity else {
                    return
                }

                selectedLocationChoice = .nearby
                draft.city = detectedCity.rawValue
                draft.preferredDistricts = [district]
                draft.district = district
                automaticallyDetectedDistrict = district
                isDetectedDistrictConfirmed = true
                presentDetectedDistrictPicker()
                AppHaptics.notification(.success)
            }
            .onChange(of: locationPermission.detectedCity) { city in
                guard acceptsDetectedLocationUpdates,
                      let city,
                      let detectedCity = SupportedCity.resolve(city),
                      onboardingAvailableCities.contains(detectedCity),
                      step == .availability else {
                    return
                }

                let currentCity = SupportedCity.resolve(draft.city)
                guard draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentCity == detectedCity else {
                    return
                }

                if currentCity != detectedCity {
                    draft.preferredDistricts.removeAll()
                    draft.district = nil
                    automaticallyDetectedDistrict = nil
                }
                draft.city = detectedCity.rawValue
                selectedLocationChoice = .nearby
                isDetectedDistrictConfirmed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard acceptsDetectedLocationUpdates,
                          step == .availability,
                          locationPermission.detectedDistrict == nil else {
                        return
                    }
                    presentDetectedDistrictPicker()
                }
                AppHaptics.notification(.success)
            }
            .onChange(of: step) { newValue in
                if newValue != .availability {
                    acceptsDetectedLocationUpdates = false
                } else {
                    requestAvailabilityLocationIfNeeded()
                }
            }
        }
    }

    @ViewBuilder
    private var contentForStep: some View {
        if isIntentStepPresented {
            UserIntentOnboardingView(
                initialSelection: appModel.selectedUserIntents,
                onContinue: { selection in
                    appModel.setUserIntents(selection)
                    isIntentStepPresented = false
                    step = stepAfterIntents
                },
                onBack: { isIntentStepPresented = false }
            )
        } else {
        switch step {
        case .intro:
            introScreen
        case .email:
            emailStep
                .task { await appModel.loadVkIdAvailability() }
        case .profile:
            profileStep
        case .availability:
            availabilityStep
        case .code:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stepProgressStrip

                    switch step {
                    case .code:
                        codeStep
                    case .intro, .email, .profile, .availability:
                        EmptyView()
                    }
                }
                .padding()
            }
        }
        }
    }

    private var introScreen: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let isCompact = geometry.size.height < 760
            let showsPrivacyNote = geometry.size.height >= 800
            let horizontalPadding: CGFloat = isCompact ? 16 : 20
            let contentWidth = max(280, geometry.size.width - horizontalPadding * 2)
            let heroHeight = isCompact
                ? min(max(geometry.size.height * 0.38, 270), 304)
                : min(max(geometry.size.height * 0.49, 400), 440)
            let titleTopOffset = isCompact ? max(18, safeTop + 2) : max(30, safeTop + 6)
            let verticalSpacing: CGFloat = isCompact ? 8 : 10
            let titleFontSize = min(isCompact ? 38 : 44, contentWidth / 9.15)
            let typewriterFontSize = min(isCompact ? 33 : 38, contentWidth / 10.2)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.03, blue: 0.05),
                        Color(red: 0.04, green: 0.05, blue: 0.07),
                        Color(red: 0.02, green: 0.03, blue: 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(AppTheme.court.opacity(0.18))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: -110, y: 110)

                Circle()
                    .fill(AppTheme.clay.opacity(0.18))
                    .frame(width: 300, height: 300)
                    .blur(radius: 96)
                    .offset(x: 140, y: -10)

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 220, height: 220)
                    .blur(radius: 120)
                    .offset(x: 20, y: -220)

                VStack(alignment: .leading, spacing: verticalSpacing) {
                    Spacer()
                        .frame(height: titleTopOffset)

                    VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                        Text(L10n.string("Find a partner", "Найди напарника"))
                            .font(.system(size: titleFontSize, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.64)

                        OnboardingTypewriterLine(fontSize: typewriterFontSize)

                        seekingPlayersStatus
                    }

                    OnboardingMotionHero(height: heroHeight)
                        .padding(.horizontal, -horizontalPadding)

                    Spacer(minLength: isCompact ? 6 : 10)

                    LiquidStartButton(title: L10n.string("Start searching", "Начать поиск"), subtitle: L10n.string("Let's find your starting point", "Найдём твой сценарий")) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                            stepAfterIntents = .profile
                            isIntentStepPresented = true
                        }
                    }
                    .frame(height: isCompact ? 76 : 82)

                    existingAccountButton

                    if showsPrivacyNote {
                        introPrivacyNote
                    }

                    Spacer()
                        .frame(height: max(isCompact ? 4 : 8, safeBottom))
                }
                .padding(.horizontal, horizontalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }

    private var seekingPlayersStatus: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(OnboardingStepPalette.lime.opacity(0.22))
                    .frame(width: 32, height: 32)
                    .blur(radius: 5)
                Circle()
                    .fill(OnboardingStepPalette.lime)
                    .frame(width: 14, height: 14)
                    .shadow(color: OnboardingStepPalette.lime.opacity(0.86), radius: 12, x: 0, y: 0)
            }

            Text(seekingPlayersLine)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private var existingAccountButton: some View {
        Button {
            AppHaptics.selection()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                step = .email
            }
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "person")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 34, height: 34)
                    Circle()
                        .fill(OnboardingStepPalette.lime)
                        .frame(width: 9, height: 9)
                        .shadow(color: OnboardingStepPalette.lime.opacity(0.7), radius: 6, x: 0, y: 0)
                }
                Text(L10n.string("Already have an account? Sign in", "Уже есть аккаунт? Войти"))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 24, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 62)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("Sign in to an existing account", "Войти в существующий аккаунт"))
    }

    private var introPrivacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 18, weight: .semibold))
            Text(L10n.string("You choose whether to appear on the player map", "Ты сам выбираешь, показывать ли себя на карте игроков"))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white.opacity(0.48))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private var stepProgressStrip: some View {
        Group {
            if showsOnboardingProgress {
                HStack(spacing: 8) {
                    ForEach([AuthStep.profile, .availability], id: \.self) { item in
                        Capsule()
                            .fill(progressColor(for: item))
                            .frame(height: 6)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingMotionHero()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Find a partner", "Найди напарника"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                OnboardingTypewriterLine()

                Text(L10n.string("Create a quick profile and browse players. You can add availability later; email is only needed for protected actions such as matches, chats, notifications, and saved responses.", "Соберём быстрый профиль и откроем подбор игроков. Доступность можно оставить пустой и заполнить позже, а email понадобится только для защищённых действий: мэтчей, чатов, уведомлений и сохранения."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(3)
            }

            LiquidStartButton(title: L10n.string("Start", "Начать"), subtitle: L10n.string("Let's find your starting point", "Найдём твой сценарий")) {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    stepAfterIntents = .profile
                    isIntentStepPresented = true
                }
            }

            existingAccountButton
        }
    }

    private var profileStep: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 800
            let horizontalPadding: CGFloat = isCompact ? 18 : 24
            let sectionSpacing: CGFloat = isCompact ? 9 : 12
            let titleSize: CGFloat = isCompact ? 28 : 31
            let subtitleSize: CGFloat = isCompact ? 13 : 15
            let cardHeight: CGFloat = isCompact ? 86 : 92
            let topPadding: CGFloat = max(isCompact ? 66 : 70, geometry.safeAreaInsets.top + (isCompact ? 30 : 36))
            let bottomPadding: CGFloat = max(18, geometry.safeAreaInsets.bottom + 14)

            ZStack {
                OnboardingDarkBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        OnboardingStepProgress(current: 1, total: 2)
                            .padding(.top, topPadding)

                        VStack(alignment: .leading, spacing: isCompact ? 5 : 7) {
                            Text(L10n.string("Step 1 of 2", "Шаг 1 из 2"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .overlay(alignment: .leading) {
                                    Text(L10n.string("Step 1", "Шаг 1"))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(OnboardingStepPalette.lime)
                                }

                            Text(L10n.string("What sports\ninterest you?", "Какой спорт\nтебе интересен?"))
                                .font(.system(size: titleSize, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineSpacing(-5)
                                .minimumScaleFactor(0.78)

                            Text(L10n.string("Choose your sports. Your level helps us suggest partners when you want to play together.", "Выбери виды спорта. Уровень поможет подобрать партнёров, когда захочешь сыграть вместе."))
                                .font(.system(size: subtitleSize, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: isCompact ? 7 : 8) {
                            Text(L10n.string("Sports", "Виды спорта"))
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)

                            OnboardingSportSelectionGrid(
                                sports: $draft.preferredSports,
                                levels: $draft.sportLevels,
                                cardHeight: cardHeight,
                                onSelectLevel: { sport in
                                    if !draft.preferredSports.contains(sport) {
                                        draft.preferredSports.append(sport)
                                        draft.sportLevels[sport.rawValue] = draft.sportLevels[sport.rawValue] ?? 5
                                    }
                                    selectedLevelSport = sport
                                }
                            )
                        }

                        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                            Text(L10n.string("Name and age", "Имя и возраст"))
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)

                            OnboardingProfileBasicsFields(
                                name: $draft.name,
                                age: $draft.age,
                                isCompact: isCompact,
                                focusedField: $profileFocusedField,
                                showsAgeValidation: hasEditedAge || hasAttemptedProfileContinue,
                                onAgeEdited: {
                                    hasEditedAge = true
                                },
                                onAgeSubmit: {
                                    profileFocusedField = nil
                                }
                            )

                            Text(L10n.string("Age is required: 18 to 100.", "Возраст обязателен: от 18 до 100 лет."))
                                .font(.system(size: isCompact ? 12 : 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.54))
                                .lineLimit(2)
                        }

                        OnboardingVisibilityToggle(isOn: $draft.isLookingForGame, isCompact: isCompact)

                        HStack {
                            if !embedded {
                                Button {
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                                        step = .intro
                                    }
                                } label: {
                                    Text(L10n.string("Back", "Назад"))
                                        .font(.headline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: isCompact ? 54 : 60)
                                }
                                .foregroundStyle(.white.opacity(0.78))
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .buttonStyle(.plain)
                            }

                            Button {
                                advanceFromProfile()
                            } label: {
                                HStack(spacing: 14) {
                                    Text(L10n.string("Next", "Дальше"))
                                    Image(systemName: "arrow.right")
                                }
                                .font(.system(size: isCompact ? 20 : 22, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: isCompact ? 54 : 60)
                            }
                            .foregroundStyle(Color.black.opacity(draft.hasProfileBasics ? 0.92 : 0.38))
                            .background(
                                LinearGradient(
                                    colors: draft.hasProfileBasics
                                        ? [OnboardingStepPalette.lime, Color(red: 0.55, green: 0.88, blue: 0.22)]
                                        : [Color.white.opacity(0.18), Color.white.opacity(0.12)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                            .buttonStyle(.plain)
                            .disabled(!draft.hasProfileBasics)
                        }
                        .padding(.bottom, bottomPadding + (isCompact ? 150 : 180))
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .ignoresSafeArea(.container)
    }

    private var availabilityStep: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 800
            let horizontalPadding: CGFloat = isCompact ? 16 : 20
            let topPadding: CGFloat = max(isCompact ? 58 : 64, geometry.safeAreaInsets.top + (isCompact ? 24 : 30))
            let bottomPadding: CGFloat = max(14, geometry.safeAreaInsets.bottom + 10)
            let verticalSpacing: CGFloat = isCompact ? 8 : 10
            let actionHeight: CGFloat = isCompact ? 48 : 52

            ZStack {
                OnboardingDarkBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: verticalSpacing) {
                        OnboardingStepProgress(current: 2, total: 2)
                            .padding(.top, topPadding)

                        VStack(alignment: .leading, spacing: isCompact ? 5 : 7) {
                            Text(L10n.string("Step 2 of 2", "Шаг 2 из 2"))
                                .font(.system(size: isCompact ? 22 : 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .overlay(alignment: .leading) {
                                    Text(L10n.string("Step 2", "Шаг 2"))
                                        .font(.system(size: isCompact ? 22 : 24, weight: .black, design: .rounded))
                                        .foregroundStyle(OnboardingStepPalette.lime)
                                }

                            Text(L10n.string("When do you have time for sport? You can leave this empty and set it later.", "Когда у тебя есть время на спорт? Можно оставить пустым и настроить позже."))
                                .font(.system(size: isCompact ? 13 : 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        OnboardingAvailabilityEditorCard {
                            DetailedAvailabilityEditor(availabilityByDay: $draft.availabilityByDay)
                        }

                        OnboardingSearchLocationSection(
                            selectedChoice: selectedLocationChoice,
                            selectedCity: draft.city,
                            selectedDistricts: draft.preferredDistricts,
                            isDetectingLocation: locationPermission.isResolvingDistrict,
                            locationDetectionFailed: locationPermission.didFailToDetectDistrict,
                            isDetectedDistrictConfirmed: isDetectedDistrictConfirmed,
                            onNearby: {
                                selectedLocationChoice = .nearby
                                isDetectedDistrictConfirmed = false
                                automaticallyDetectedDistrict = nil
                                acceptsDetectedLocationUpdates = false
                                locationPickerRequestsAutomatically = true
                                showsLocationPicker = true
                                AppHaptics.selection()
                            },
                            onDistricts: {
                                selectedLocationChoice = .districts
                                isDetectedDistrictConfirmed = false
                                acceptsDetectedLocationUpdates = false
                                locationPickerRequestsAutomatically = false
                                showsLocationPicker = true
                                AppHaptics.selection()
                            }
                        )

                        ProfileMapVisibilityControl(isOn: $draft.showOnMap, isDark: true, isOnboarding: true, identifier: "onboarding-show-on-map")

                        HStack(spacing: 12) {
                            Button {
                                persistDraft()
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                                    step = .profile
                                }
                            } label: {
                                Text(L10n.string("Back", "Назад"))
                                    .font(.system(size: isCompact ? 17 : 18, weight: .black, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: actionHeight)
                            }
                            .frame(maxWidth: 124)
                            .foregroundStyle(.white)
                            .background(OnboardingStepPalette.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .buttonStyle(.plain)

                            Button {
                                Task { await finishGuestOnboarding() }
                            } label: {
                                Text(embedded ? L10n.string("Browse players", "Смотреть игроков") : L10n.string("Continue", "Продолжить"))
                                    .font(.system(size: isCompact ? 17 : 18, weight: .black, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: actionHeight)
                            }
                            .foregroundStyle(Color.black.opacity(canFinishAvailability ? 0.92 : 0.38))
                            .background(
                                LinearGradient(
                                    colors: canFinishAvailability
                                        ? [OnboardingStepPalette.lime, Color(red: 0.55, green: 0.88, blue: 0.22)]
                                        : [Color.white.opacity(0.18), Color.white.opacity(0.12)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                            .buttonStyle(.plain)
                            .disabled(!canFinishAvailability)
                        }
                        .padding(.bottom, bottomPadding + 24)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .ignoresSafeArea()
    }

    private var emailStep: some View {
        AuthSignInReferenceScreen(
            email: $appModel.authEmail,
            country: $appModel.authCountry,
            phone: $appModel.authPhone,
            isVkIdAvailable: appModel.isVkIdAvailable,
            authMessage: appModel.authMessage,
            errorMessage: appModel.errorMessage,
            debugCode: appModel.debugCode,
            embedded: embedded,
            onClose: {
                appModel.dismissPresentedAuth()
                dismiss()
            },
            onAppleRequest: { request in
                appModel.authMessage = nil
                appModel.debugCode = nil
                appModel.errorMessage = nil
                request.requestedScopes = [.email, .fullName]
            },
            onAppleCompletion: handleAppleSignIn,
            onRequestCode: {
                persistDraft()
                Task {
                    let didRequestCode = await appModel.requestCode(userAgreementAccepted: true)
                    guard didRequestCode else {
                        return
                    }

                    withAnimation(AppMotion.standard) {
                        step = .code
                    }
                }
            },
            onRequestPhoneCode: {
                persistDraft()
                Task {
                    guard await appModel.requestPhoneCode() else { return }
                    withAnimation(AppMotion.standard) {
                        step = .code
                    }
                }
            },
            onVkSignIn: {
                persistDraft()
                Task {
                    await appModel.signInWithVk { url in
                        try await webAuthenticationSession.authenticate(
                            using: url,
                            callbackURLScheme: "sportsearch",
                            preferredBrowserSession: .shared
                        )
                    }
                }
            },
            onHaveCode: {
                appModel.authCodeTarget = .email
                guard !appModel.authEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    appModel.errorMessage = L10n.string("Enter your email first.", "Сначала укажи email для входа.")
                    return
                }

                withAnimation(AppMotion.standard) {
                    step = .code
                }
            },
            onBack: {
                persistDraft()
                withAnimation(AppMotion.standard) {
                    step = draft.hasProfileBasics ? .availability : .intro
                }
            }
        )
    }

    /// A wrong code shakes the boxes red and clears them for another try; a right one
    /// flashes them green on the way out.
    @MainActor
    private func showCodeVerdict(accepted: Bool) async {
        if !accepted {
            AppHaptics.notification(.error)
        }
        withAnimation(accepted ? .easeOut(duration: 0.2) : .linear(duration: 0.45)) {
            codeVerdict = accepted ? .accepted : .rejected(codeVerdict.attempt + 1)
        }
        guard !accepted else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.easeOut(duration: 0.2)) {
            code = ""
            codeVerdict = .none
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(
                title: L10n.string("Verification", "Подтверждение"),
                subtitle: appModel.authCodeTarget == .phone
                    ? L10n.string("Enter the 6-digit code from the SMS. After verification, your profile will be saved to your account.", "Введи 6 цифр из SMS. После проверки профиль будет сохранён в аккаунте.")
                    : L10n.string("Enter the 6-digit code from the email. After verification, your profile will be saved to your account.", "Введи 6 цифр из письма. После проверки профиль будет сохранён в аккаунте.")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    OTPCodeField(code: $code, verdict: codeVerdict)

                    // Only a local server without an SMS.ru / email key returns it.
                    if let debugCode = appModel.debugCode {
                        AuthInlineMessage(text: "Debug OTP: \(debugCode)", tint: .orange, icon: "number")
                    }

                    Button(L10n.string("Sign in", "Войти")) {
                        persistDraft()
                        Task {
                            if appModel.authCodeTarget == .phone {
                                await appModel.verifyPhone(code: code)
                            } else {
                                await appModel.verify(code: code, userAgreementAccepted: true)
                            }
                            await showCodeVerdict(accepted: appModel.isAuthenticated)
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).count != 6)

                    LegalDocuments.signInNotice
                }
            }

            HStack {
                Button(appModel.authCodeTarget == .phone
                       ? L10n.string("Change number", "Изменить номер")
                       : L10n.string("Change email", "Изменить email")) {
                    step = .email
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
    }

    private func persistDraft() {
        appModel.updateGuestDraft(normalizedDraft())
    }

    private func advanceFromProfile() {
        profileFocusedField = nil
        hasAttemptedProfileContinue = true
        guard draft.hasProfileBasics else { return }
        persistDraft()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            step = .availability
        }
    }

    private var canFinishAvailability: Bool {
        draft.hasRequiredOnboardingFields
    }

    private var seekingPlayersLine: String {
        guard let count = appStats?.registeredPlayersCount else {
            return L10n.string("Your next game starts here", "Следующая игра начинается здесь")
        }
        let formattedCount = count.formatted(.number.grouping(.automatic))
        return L10n.string("\(formattedCount) players in the app", "\(formattedCount) игроков в приложении")
    }

    private func loadAppStats() async {
        guard appStats == nil else { return }
        do {
            appStats = try await appModel.repository.fetchAppStats()
        } catch {
            // Leave the neutral message visible when a real count is unavailable.
        }
    }

    private func finishGuestOnboarding() async {
        var completedDraft = normalizedDraft()
        guard completedDraft.hasProfileBasics else {
            draft = completedDraft
            appModel.errorMessage = L10n.string("Enter your name, an age from 18 to 100, and at least one sport.", "Укажи имя, возраст от 18 до 100 и хотя бы один вид спорта.")
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                step = .profile
            }
            return
        }
        guard completedDraft.hasSelectedCity else {
            draft = completedDraft
            appModel.errorMessage = L10n.string("Choose a country and city.", "Выбери страну и город.")
            return
        }
        completedDraft.onboardingCompleted = true
        guard await appModel.completeGuestOnboarding(completedDraft) else { return }
        appModel.queueDiscoverSimilarPlayersHint()
        guard !embedded else {
            return
        }
        appModel.dismissPresentedAuth()
        dismiss()
    }

    private func requestAvailabilityLocationIfNeeded() {
        guard !didAutoRequestAvailabilityLocation else {
            return
        }
        guard step == .availability else {
            return
        }
        guard selectedLocationChoice != .districts else {
            return
        }
        guard draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.preferredDistricts.isEmpty else {
            return
        }

        didAutoRequestAvailabilityLocation = true
        selectedLocationChoice = .nearby
        isDetectedDistrictConfirmed = false
        automaticallyDetectedDistrict = nil
        acceptsDetectedLocationUpdates = false
        locationPickerRequestsAutomatically = true
        showsLocationPicker = true
    }

    private func presentDetectedDistrictPicker() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard acceptsDetectedLocationUpdates, step == .availability else {
                return
            }
            showsDistrictPicker = true
        }
    }

    private var currentStepLabel: String {
        switch step {
        case .intro:
            return L10n.string("Quick start", "Быстрый старт")
        case .profile:
            return L10n.string("Step 1 of 2", "Шаг 1 из 2")
        case .availability:
            return L10n.string("Step 2 of 2", "Шаг 2 из 2")
        case .email:
            return "Email"
        case .code:
            return L10n.string("Code", "Код")
        }
    }

    private var currentStepSubtitle: String {
        switch step {
        case .intro:
            return L10n.string("Create a profile draft, browse matches, and verify your email only when needed.", "Собери черновик профиля, посмотри подбор и подтверди email только когда нужно.")
        case .profile:
            return L10n.string("Basic player card: name, age, sport, and level.", "Базовая карточка игрока: имя, возраст, спорт и уровень.")
        case .availability:
            return L10n.string("Weekdays and time windows. You can leave them empty and fill them in later.", "Дни недели и окна времени. Можно оставить пустым и заполнить позже.")
        case .email:
            return L10n.string("Email is only required for protected actions: matches, chats, notifications, and saved responses.", "Email нужен только для защищённых действий: мэтчей, переписки, уведомлений и сохранения откликов.")
        case .code:
            return L10n.string("Verify the code and move the draft to a full account.", "Подтверждение кода и перенос черновика в полноценный аккаунт.")
        }
    }

    private func normalizedDraft(_ source: GuestOnboardingDraft? = nil) -> GuestOnboardingDraft {
        var next = source ?? draft
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.city = next.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.location?.coverage.districtsEnabled == true || next.location == nil {
            next.preferredDistricts = filteredOnboardingDistricts(next.preferredDistricts, cityName: next.city)
        } else {
            next.preferredDistricts.removeAll()
        }
        if let district = next.district?.lowercased(),
           let city = SupportedCity.resolve(next.city),
           districtBelongsToCity(district, city: city) {
            next.district = district
        } else {
            next.district = next.preferredDistricts.first
        }
        next.availabilityByDay = next.availabilityByDay.filter { !$0.value.isEmpty }
        let orderedDays = DayOfWeek.allCases.map(\.rawValue)
        if !next.availabilityByDay.isEmpty {
            next.availableDays = orderedDays.filter { next.availabilityByDay[$0]?.isEmpty == false }
            next.availableTimeRanges = orderedDays
                .flatMap { next.availabilityByDay[$0] ?? [] }
                .uniqued()
        } else {
            next.availableDays = next.availableDays.uniqued()
            next.availableTimeRanges = next.availableTimeRanges.uniqued()
        }
        if next.preferredDistricts.isEmpty, let district = next.district {
            next.preferredDistricts = [district]
        }
        return next
    }

    private func applySelectedLocation(_ place: GeoPlace, source: LocationSource) {
        let previousPlaceID = draft.location?.id
        draft.location = place
        draft.locationSource = source
        draft.city = place.coverage.legacyCity ?? place.city
        selectedLocationChoice = source == .geolocation ? .nearby : .districts
        isDetectedDistrictConfirmed = source != .geolocation
        automaticallyDetectedDistrict = nil
        acceptsDetectedLocationUpdates = source == .geolocation

        if previousPlaceID != place.id {
            draft.district = nil
            draft.preferredDistricts.removeAll()
        }

        persistDraft()
        appModel.considerLocaleRecommendation(for: place)

        guard place.coverage.districtsEnabled,
              SupportedCity.resolve(place.coverage.legacyCity ?? place.city) != nil else {
            acceptsDetectedLocationUpdates = false
            return
        }

        if source == .geolocation {
            locationPermission.requestLocationAccess()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showsDistrictPicker = true
        }
    }

    private func progressColor(for item: AuthStep) -> Color {
        let order: [AuthStep] = [.profile, .availability]
        let effectiveStep = step == .intro ? .profile : step
        let currentIndex = order.firstIndex(of: effectiveStep) ?? 0
        let itemIndex = order.firstIndex(of: item) ?? 0
        return itemIndex <= currentIndex ? AppTheme.court : Color(.systemGray4)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appModel.errorMessage = L10n.string("Could not read your Apple ID details. Try again or use email.", "Не удалось получить данные Apple ID. Попробуй ещё раз или используй email.")
                return
            }

            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                appModel.errorMessage = L10n.string("Apple did not provide an identity token. Try again.", "Apple не передал identity token. Попробуй ещё раз.")
                return
            }
            persistDraft()

            Task {
                await appModel.signInWithApple(
                    identityToken: identityToken,
                    email: credential.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName,
                    userAgreementAccepted: true
                )
            }

        case let .failure(error):
            if let authorizationError = error as? ASAuthorizationError {
                switch authorizationError.code {
                case .canceled:
                    appModel.errorMessage = nil
                case .unknown:
                    appModel.errorMessage = L10n.string("Apple sign-in could not be completed. Check that Sign in with Apple is enabled for App ID shop.sportsearch.app, then refresh the signing profile in Xcode.", "Вход через Apple не завершён. Проверь, что для App ID shop.sportsearch.app включен Sign in with Apple, затем обнови профиль подписи в Xcode.")
                default:
                    appModel.errorMessage = L10n.string("Apple sign-in could not be completed: \(authorizationError.localizedDescription)", "Вход через Apple не завершён: \(authorizationError.localizedDescription)")
                }
            } else {
                appModel.errorMessage = L10n.string("Apple sign-in could not be completed: \(error.localizedDescription)", "Вход через Apple не завершён: \(error.localizedDescription)")
            }
        }
    }

    private var showsOnboardingProgress: Bool {
        step == .profile || step == .availability
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.court)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    private func toggleSport(_ sport: Sport) {
        if draft.preferredSports.contains(sport) {
            draft.preferredSports.removeAll { $0 == sport }
            draft.sportLevels.removeValue(forKey: sport.rawValue)
        } else {
            draft.preferredSports.append(sport)
            draft.sportLevels[sport.rawValue] = draft.sportLevels[sport.rawValue] ?? 5
        }
    }

    @ViewBuilder
    private func segmentedChoice<Item: Identifiable & Hashable>(
        title: String,
        items: [Item],
        selection: Binding<Item>,
        titleForItem: KeyPath<Item, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .textCase(.uppercase)
                .tracking(1.4)

            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            selection.wrappedValue = item
                        }
                        AppHaptics.selection()
                    } label: {
                        Text(LocalizedStringKey(item[keyPath: titleForItem]))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection.wrappedValue == item ? .white : AppTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(selection.wrappedValue == item ? AppTheme.ink : .white.opacity(0.78))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(selection.wrappedValue == item ? 0.08 : 0.82), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AuthSignInReferenceScreen: View {
    @EnvironmentObject private var localeStore: LocaleStore
    @Binding var email: String
    @Binding var country: AuthCountry
    @Binding var phone: String
    let isVkIdAvailable: Bool
    let authMessage: String?
    let errorMessage: String?
    let debugCode: String?
    let embedded: Bool
    let onClose: () -> Void
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void
    let onRequestCode: () -> Void
    let onRequestPhoneCode: () -> Void
    let onVkSignIn: () -> Void
    let onHaveCode: () -> Void
    let onBack: () -> Void

    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPhoneFocused: Bool
    @State private var isEmailLoginExpanded = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AuthReferenceBackground()

                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        if !embedded {
                            Button(L10n.string("Close", "Закрыть"), action: onClose)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(height: 44)
                    .padding(.top, max(8, geometry.safeAreaInsets.top * 0.35))
                    .padding(.horizontal, 24)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 28) {
                            signInCard

                            Button(action: onBack) {
                                Label(L10n.string("Back", "Назад"), systemImage: "arrow.left")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .labelStyle(.titleAndIcon)
                                    .frame(width: min(geometry.size.width - 112, 270), height: 62)
                                    .background(.white.opacity(0.86), in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(.white.opacity(0.72), lineWidth: 1)
                                    )
                                    .shadow(color: AppTheme.ink.opacity(0.06), radius: 18, x: 0, y: 10)
                            }
                            .buttonStyle(AuthReferencePressStyle())
                            .padding(.bottom, max(18, geometry.safeAreaInsets.bottom + 4))
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("Sign in", "Вход в профиль"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(country == .russia
                     ? L10n.string("In Russia you sign in with a phone number or VK ID. Your profile, matches, chats, and notifications are saved to your account.", "В России вход — по номеру телефона или через VK ID. Профиль, матчи, переписки и уведомления сохранятся в аккаунте.")
                     : L10n.string("Sign in with Apple to save your profile, matches, chats, and notifications.", "Войди через Apple, чтобы сохранить профиль, матчи, переписки и уведомления."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Where are you?", "Где вы находитесь?"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Picker(L10n.string("Where are you?", "Где вы находитесь?"), selection: $country) {
                    ForEach(AuthCountry.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            if country == .russia {
                russianSignIn
            } else {
                otherCountrySignIn
            }

            if let authMessage {
                AuthInlineMessage(text: authMessage, tint: AppTheme.court, icon: "checkmark.circle")
            }

            if let errorMessage {
                AuthInlineMessage(text: errorMessage, tint: .red, icon: "exclamationmark.triangle")
            }

            if let debugCode {
                AuthInlineMessage(text: "Debug OTP: \(debugCode)", tint: .orange, icon: "number")
                    .fontDesign(.monospaced)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 30, x: 0, y: 18)
    }

    /// Для России (ч. 10 ст. 8 149-ФЗ): код по SMS на российский номер или VK ID.
    @ViewBuilder
    private var russianSignIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Phone number", "Номер телефона"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            TextField("", text: $phone, prompt: Text("+7 999 123-45-67").foregroundColor(Color(red: 0.72, green: 0.74, blue: 0.78)))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($isPhoneFocused)
                .padding(.horizontal, 18)
                .frame(height: 68)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isPhoneFocused ? AppTheme.court.opacity(0.72) : Color(.systemGray4), lineWidth: isPhoneFocused ? 1.5 : 1)
                )
        }

        Button {
            isPhoneFocused = false
            onRequestPhoneCode()
        } label: {
            Text(L10n.string("Get an SMS code", "Получить код по SMS"))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.32, blue: 0.23), AppTheme.court.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: AppTheme.court.opacity(0.2), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(AuthReferencePressStyle())

        if isVkIdAvailable {
            AuthDividerLabel(text: L10n.string("or", "или"))

            Button(action: onVkSignIn) {
                Text(L10n.string("Sign in with VK ID", "Войти через VK ID"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(Color(red: 0, green: 0.467, blue: 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(AuthReferencePressStyle())
        }

        LegalDocuments.signInNotice
    }

    @ViewBuilder
    private var otherCountrySignIn: some View {
            ZStack {
                SignInWithAppleButton(.continue, onRequest: onAppleRequest, onCompletion: onAppleCompletion)
                    .signInWithAppleButtonStyle(.black)
                    .environment(\.locale, localeStore.effectiveLocale.locale)
                    .id("apple-sign-in-\(localeStore.effectiveLocale.rawValue)")
                    .frame(height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            }

            LegalDocuments.signInNotice

            if isEmailLoginExpanded {
                AuthDividerLabel(text: L10n.string("or sign in with email", "или войти по Email"))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Email")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    ZStack(alignment: .leading) {
                        if email.isEmpty {
                            HStack(spacing: 14) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                Text("example@mail.com")
                                    .font(.system(size: 22, weight: .regular, design: .rounded))
                            }
                            .foregroundStyle(Color(red: 0.72, green: 0.74, blue: 0.78))
                            .padding(.horizontal, 18)
                        }

                        TextField("", text: $email)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isEmailFocused)
                            .padding(.horizontal, 18)
                    }
                    .frame(height: 68)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isEmailFocused ? AppTheme.court.opacity(0.72) : Color(.systemGray4), lineWidth: isEmailFocused ? 1.5 : 1)
                    )
                }

                Button {
                    onRequestCode()
                } label: {
                    Text(L10n.string("Get a code by email", "Получить код по email"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.06, green: 0.32, blue: 0.23), AppTheme.court.opacity(0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .shadow(color: AppTheme.court.opacity(0.2), radius: 16, x: 0, y: 10)
                }
                .buttonStyle(AuthReferencePressStyle())

                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.string("Use email sign-in if you previously registered without Apple ID.", "Email-вход нужен, если ты уже регистрировался без Apple ID."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Button {
                        onHaveCode()
                    } label: {
                        Text(L10n.string("I already have a code", "У меня уже есть код"))
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppTheme.court)
                    }
                }
            } else {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        isEmailLoginExpanded = true
                    }
                } label: {
                    Label(L10n.string("Sign in with email", "Войти по email"), systemImage: "envelope")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                }
                .buttonStyle(AuthReferencePressStyle())
            }
    }
}

private struct AuthReferenceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.94, blue: 0.88),
                    Color(red: 0.99, green: 0.98, blue: 0.95),
                    Color(red: 0.88, green: 0.95, blue: 0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.court.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 72)
                .offset(x: -140, y: 310)

            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 120, y: -210)
        }
    }
}

private struct AuthDividerLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 18) {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 1)
            Text(LocalizedStringKey(text))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 1)
        }
    }
}

private struct AuthInlineMessage: View {
    let text: String
    let tint: Color
    let icon: String

    var body: some View {
        Label(LocalizedStringKey(text), systemImage: icon)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AuthReferencePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct OnboardingTypewriterLine: View {
    var fontSize: CGFloat = 34

    private var phrases: [String] {
        [
            L10n.string("tennis", "в теннис"),
            L10n.string("football", "в футбол"),
            L10n.string("padel", "в падел"),
            L10n.string("a workout", "в зал")
        ]
    }

    @State private var displayedPhrase = ""
    @State private var typingTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.48)) { timeline in
            let cursorVisible = Int(timeline.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)

            HStack(spacing: 8) {
                Text(L10n.string("Play", "для игры"))
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(displayedPhrase.isEmpty ? " " : displayedPhrase)
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.88, green: 0.97, blue: 0.82),
                                OnboardingStepPalette.lime,
                                Color(red: 0.30, green: 0.84, blue: 0.50)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: fontSize * 0.82)
                    .opacity(cursorVisible ? 1 : 0.22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: fontSize + 10, alignment: .leading)
        .task {
            guard typingTask == nil else {
                return
            }
            typingTask = Task {
                var nextIndex = 0
                while !Task.isCancelled {
                    let phrase = phrases[nextIndex]

                    for count in 0 ... phrase.count {
                        await MainActor.run {
                            displayedPhrase = String(phrase.prefix(count))
                        }
                        try? await Task.sleep(for: .milliseconds(count == phrase.count ? 1150 : 64))
                    }

                    for count in stride(from: phrase.count - 1, through: 0, by: -1) {
                        await MainActor.run {
                            displayedPhrase = String(phrase.prefix(count))
                        }
                        try? await Task.sleep(for: .milliseconds(34))
                    }

                    nextIndex = (nextIndex + 1) % phrases.count
                    try? await Task.sleep(for: .milliseconds(180))
                }
            }
        }
        .onDisappear {
            typingTask?.cancel()
            typingTask = nil
        }
    }
}

private struct OnboardingMotionHero: View {
    var height: CGFloat = 360
    @State private var currentPage = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            OnboardingLoopingCards(currentIndex: currentPage)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                ForEach(0 ..< OnboardingLoopingCards.pageCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == currentPage ? OnboardingStepPalette.lime : Color.white.opacity(0.20))
                        .frame(width: index == currentPage ? 24 : 12, height: 6)
                        .shadow(
                            color: index == currentPage ? OnboardingStepPalette.lime.opacity(0.62) : .clear,
                            radius: 7,
                            x: 0,
                            y: 0
                        )
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: currentPage)
        }
        .frame(height: height)
        .task {
            currentPage = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.32)) {
                    currentPage = (currentPage + 1) % OnboardingLoopingCards.pageCount
                }
            }
        }
    }
}

private struct OnboardingLoopingCards: View {
    private var cards: [OnboardingPreviewCardData] {
        [
            .init(name: "Максим, 27", sport: L10n.string("Tennis", "Теннис"), level: L10n.string("Recreational", "Любитель"), metaLeft: L10n.string("Within 5 km", "До 5 км"), metaRight: L10n.string("Today, 18:30", "Сегодня, 18:30"), imageName: "hero-tennis"),
            .init(name: "Елена, 26", sport: L10n.string("Volleyball", "Волейбол"), level: L10n.string("Intermediate", "Средний"), metaLeft: L10n.string("Within 4 km", "До 4 км"), metaRight: L10n.string("Today, 19:30", "Сегодня, 19:30"), imageName: "OnboardingPlayerVolleyballWoman"),
            .init(name: "Дмитрий, 29", sport: L10n.string("Football", "Футбол"), level: L10n.string("Intermediate", "Средний"), metaLeft: L10n.string("Within 3 km", "До 3 км"), metaRight: L10n.string("Today, 19:00", "Сегодня, 19:00"), imageName: "hero-football"),
            .init(name: "Мария, 25", sport: L10n.string("Squash", "Сквош"), level: L10n.string("Recreational", "Любитель"), metaLeft: L10n.string("Within 3 km", "До 3 км"), metaRight: L10n.string("Tomorrow, 18:00", "Завтра, 18:00"), imageName: "OnboardingPlayerSquashWoman"),
            .init(name: "Антон, 31", sport: L10n.string("Fitness", "Зал"), level: L10n.string("Confident", "Уверенный"), metaLeft: L10n.string("Within 4 km", "До 4 км"), metaRight: L10n.string("Tomorrow, 7:10", "Завтра, 7:10"), imageName: "hero-fitness"),
            .init(name: "София, 29", sport: L10n.string("Padel", "Падел"), level: L10n.string("Intermediate", "Средний"), metaLeft: L10n.string("Within 5 km", "До 5 км"), metaRight: L10n.string("Tomorrow, 20:00", "Завтра, 20:00"), imageName: "OnboardingPlayerPadelWoman"),
            .init(name: "Никита, 28", sport: L10n.string("Padel", "Падел"), level: L10n.string("Recreational", "Любитель"), metaLeft: L10n.string("Within 6 km", "До 6 км"), metaRight: L10n.string("Today, 20:00", "Сегодня, 20:00"), imageName: "hero-padel")
        ]
    }

    static let pageCount = 7

    let currentIndex: Int

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = max(236, geometry.size.height - 4)
            let cardWidth = min(geometry.size.width * 0.82, cardHeight * 0.84)
            let unit = cardWidth + 10

            ZStack {
                ForEach(-1 ... 1, id: \.self) { slot in
                    let rawIndex = currentIndex + slot
                    let cardIndex = (rawIndex % cards.count + cards.count) % cards.count
                    let card = cards[cardIndex]
                    let isActive = slot == 0
                    let relativePosition = CGFloat(slot)

                    OnboardingPreviewCard(
                        card: card,
                        width: cardWidth,
                        height: cardHeight
                    )
                        .scaleEffect(isActive ? 1 : 0.88)
                        .opacity(isActive ? 1 : 0.24)
                        .rotation3DEffect(
                            .degrees(-relativePosition * 12),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.68
                        )
                        .shadow(
                            color: .black.opacity(isActive ? 0.40 : 0.16),
                            radius: isActive ? 30 : 14,
                            x: relativePosition * -8,
                            y: isActive ? 26 : 18
                        )
                        .offset(x: relativePosition * unit, y: isActive ? 0 : 8)
                        .zIndex(isActive ? 1 : 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .mask(
                Rectangle()
                    .frame(width: geometry.size.width, height: geometry.size.height + 44)
                    .offset(y: -14)
            )
        }
    }
}

private struct OnboardingPreviewCardData {
    let name: String
    let sport: String
    let level: String
    let metaLeft: String
    let metaRight: String
    let imageName: String
}

private struct OnboardingPreviewCard: View {
    let card: OnboardingPreviewCardData
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image = loadImage(named: card.imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: width, height: height)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.18), .black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(card.name)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(OnboardingStepPalette.lime)
                        .shadow(color: OnboardingStepPalette.lime.opacity(0.6), radius: 8, x: 0, y: 0)
                }

                HStack(spacing: 6) {
                    chip(text: card.sport, tint: OnboardingStepPalette.lime.opacity(0.42), isHighlighted: true)
                    chip(text: card.level, tint: .white.opacity(0.12), isHighlighted: false)
                }

                HStack(spacing: 6) {
                    metaChip(icon: "location.fill", text: card.metaLeft)
                    metaChip(icon: "clock", text: card.metaRight)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .padding(12)
        }
        .frame(width: width, height: height)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 16)
    }

    private func chip(text: String, tint: Color, isHighlighted: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isHighlighted ? OnboardingStepPalette.lime : Color.white.opacity(0.68))
                .frame(width: 7, height: 7)
            Text(LocalizedStringKey(text))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint, in: Capsule())
        .shadow(color: isHighlighted ? OnboardingStepPalette.lime.opacity(0.24) : .clear, radius: 10, x: 0, y: 0)
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(LocalizedStringKey(text))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func loadImage(named resourceName: String) -> UIImage? {
        if let image = UIImage(named: resourceName) {
            return image
        }

        for ext in ["jpg", "jpeg", "png", "webp"] {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: ext),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }

        return nil
    }
}

private struct LiquidStartButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    @State private var hasExpanded = false
    @State private var pulse = false
    @State private var splashTrigger = 0
    @State private var isTransitioning = false

    var body: some View {
        let buttonHeight: CGFloat = 82
        let cornerRadius: CGFloat = 31

        Button {
            guard !isTransitioning else {
                return
            }
            isTransitioning = true
            splashTrigger += 1
            AppHaptics.notification(.success)
            AppHaptics.impact(.rigid)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                isPressed = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isPressed = false
                }
                action()
                isTransitioning = false
            }
        } label: {
            GeometryReader { proxy in
                let expandedWidth = max(proxy.size.width, 72)
                let collapsedWidth: CGFloat = 26
                let width = hasExpanded ? expandedWidth : collapsedWidth

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(red: 0.42, green: 0.72, blue: 0.23), location: 0),
                                    .init(color: Color(red: 0.18, green: 0.63, blue: 0.44), location: 0.45),
                                    .init(color: Color(red: 0.08, green: 0.48, blue: 0.47), location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    RadialGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.07), .clear],
                        center: .leading,
                        startRadius: 0,
                        endRadius: expandedWidth * 0.56
                    )

                    Circle()
                        .fill(Color(red: 0.03, green: 0.41, blue: 0.40).opacity(0.46))
                        .frame(width: 128, height: 128)
                        .blur(radius: 20)
                        .position(x: expandedWidth * 0.84, y: buttonHeight * 0.72)

                    TennisBallAccent()
                        .frame(width: 78, height: 78)
                        .opacity(hasExpanded ? 1 : 0)
                        .position(x: expandedWidth * 0.69, y: buttonHeight * 0.71)

                    LinearGradient(
                        colors: [.white.opacity(0.24), .white.opacity(0.04), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    LiquidSplashLayer(trigger: splashTrigger)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(title))
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(LocalizedStringKey(subtitle))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(.white.opacity(0.28), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
                    }
                    .padding(.leading, 23)
                    .padding(.trailing, 16)
                    .opacity(hasExpanded ? 1 : 0)
                    .blur(radius: hasExpanded ? 0 : 8)
                }
                .frame(width: width, height: buttonHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.47, green: 0.86, blue: 0.24).opacity(pulse && !isTransitioning ? 0.34 : 0.22), radius: 18, x: -8, y: 8)
                .shadow(color: Color(red: 0.02, green: 0.42, blue: 0.38).opacity(0.34), radius: 22, x: 10, y: 14)
                .scaleEffect(isPressed ? 0.985 : (pulse && !isTransitioning && hasExpanded ? 1.012 : 1))
                .animation(.spring(response: 0.6, dampingFraction: 0.84), value: hasExpanded)
                .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: buttonHeight)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !hasExpanded else {
                return
            }

            withAnimation(.spring(response: 0.62, dampingFraction: 0.82).delay(0.16)) {
                hasExpanded = true
            }

            // The breathing glow is decorative; Reduce Motion leaves the button still.
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
                pulse = true
            }
        }
    }
}

private struct TennisBallAccent: View {
    var body: some View {
        Image("OnboardingTennisBall")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 4)
    }
}

private struct LiquidSplashLayer: View {
    let trigger: Int
    @State private var animate = true

    var body: some View {
        ZStack {
            splashDot(size: 20, x: -96, y: -4, color: AppTheme.court.opacity(0.88), dx: -30, dy: -12, delay: 0.0)
            splashDot(size: 15, x: -64, y: -18, color: AppTheme.clay.opacity(0.84), dx: -12, dy: -24, delay: 0.02)
            splashDot(size: 14, x: 70, y: -12, color: .white.opacity(0.66), dx: 22, dy: -22, delay: 0.03)
            splashDot(size: 18, x: 96, y: 2, color: AppTheme.court.opacity(0.82), dx: 30, dy: -10, delay: 0.05)
            splashDot(size: 12, x: 58, y: 10, color: AppTheme.clay.opacity(0.86), dx: 20, dy: 14, delay: 0.07)
        }
        .onChange(of: trigger) { _ in
            animate = false
            withAnimation(.easeOut(duration: 0.32)) {
                animate = true
            }
        }
        .allowsHitTesting(false)
    }

    private func splashDot(size: CGFloat, x: CGFloat, y: CGFloat, color: Color, dx: CGFloat, dy: CGFloat, delay: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(animate ? 0.12 : 1)
            .opacity(animate ? 0 : 0.9)
            .offset(x: animate ? x + dx : x, y: animate ? y + dy : y)
            .animation(.easeOut(duration: 0.32).delay(delay), value: animate)
            .blur(radius: animate ? 2 : 0)
    }
}

private struct SportCardPicker: View {
    @Binding var sports: [Sport]
    @Binding var levels: [String: Int]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private let orderedSports: [Sport] = [
        .tennis,
        .padel,
        .squash,
        .badminton,
        .volleyball,
        .fitness,
        .running,
        .supboard,
        .boxing,
        .yoga,
        .football,
        .tableTennis
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Sports", "Виды спорта"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .textCase(.uppercase)
                .tracking(1.4)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(orderedSports) { sport in
                    SportCard(
                        sport: sport,
                        isSelected: sports.contains(sport),
                        level: Binding(
                            get: { levels[sport.rawValue] ?? 5 },
                            set: { levels[sport.rawValue] = $0 }
                        )
                    ) {
                        AppHaptics.selection()
                        if sports.contains(sport) {
                            sports.removeAll { $0 == sport }
                            levels.removeValue(forKey: sport.rawValue)
                        } else {
                            sports.append(sport)
                            levels[sport.rawValue] = levels[sport.rawValue] ?? 5
                        }
                    }
                }
            }
        }
    }
}

private enum OnboardingStepPalette {
    static let lime = Color(red: 0.55, green: 0.92, blue: 0.25)
    static let limeSoft = Color(red: 0.42, green: 0.78, blue: 0.22)
    static let panel = Color(red: 0.06, green: 0.08, blue: 0.09)
    static let panelRaised = Color(red: 0.08, green: 0.10, blue: 0.11)
    static let stroke = Color.white.opacity(0.12)
}

private struct OnboardingDarkBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.03, blue: 0.04),
                    Color(red: 0.00, green: 0.01, blue: 0.015),
                    Color(red: 0.02, green: 0.04, blue: 0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(OnboardingStepPalette.lime.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 100)
                .offset(x: -120, y: 40)

            Circle()
                .fill(Color(red: 0.15, green: 0.66, blue: 0.95).opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .offset(x: 150, y: -180)

            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 230, height: 230)
                .blur(radius: 120)
                .offset(x: 120, y: 330)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingStepProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1 ... total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? OnboardingStepPalette.lime : Color.white.opacity(0.15))
                    .frame(height: 7)
            }
        }
    }
}

private struct OnboardingSportSelectionGrid: View {
    @Binding var sports: [Sport]
    @Binding var levels: [String: Int]
    let cardHeight: CGFloat
    let onSelectLevel: (Sport) -> Void

    @State private var showsAllSports = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let primarySports: [Sport] = [.tennis, .padel, .football, .fitness, .badminton]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(primarySports) { sport in
                OnboardingSportTile(
                    sport: sport,
                    isSelected: sports.contains(sport),
                    level: levels[sport.rawValue] ?? 5,
                    height: cardHeight,
                    onToggle: {
                        toggle(sport)
                    },
                    onLevelTap: {
                        onSelectLevel(sport)
                    }
                )
            }

            MoreSportsTile(isExpanded: showsAllSports, height: cardHeight) {
                AppHaptics.selection()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    showsAllSports.toggle()
                }
            }

            if showsAllSports {
                ForEach(extraSports) { sport in
                    OnboardingSportTile(
                        sport: sport,
                        isSelected: sports.contains(sport),
                        level: levels[sport.rawValue] ?? 5,
                        height: cardHeight,
                        onToggle: {
                            toggle(sport)
                        },
                        onLevelTap: {
                            onSelectLevel(sport)
                        }
                    )
                }
            }
        }
    }

    private var extraSports: [Sport] {
        Sport.allCases.filter { !primarySports.contains($0) }
    }

    private func toggle(_ sport: Sport) {
        AppHaptics.selection()
        if sports.contains(sport) {
            sports.removeAll { $0 == sport }
            levels.removeValue(forKey: sport.rawValue)
        } else {
            sports.append(sport)
            levels[sport.rawValue] = levels[sport.rawValue] ?? 5
        }
    }
}

private struct OnboardingSportTile: View {
    let sport: Sport
    let isSelected: Bool
    let level: Int
    let height: CGFloat
    let onToggle: () -> Void
    let onLevelTap: () -> Void

    var body: some View {
        VStack(spacing: height < 90 ? 5 : 6) {
            ZStack(alignment: .topTrailing) {
                SportPickIcon(
                    sport: sport,
                    isSelected: isSelected,
                    color: isSelected ? OnboardingStepPalette.lime : .white.opacity(0.88),
                    accent: OnboardingStepPalette.lime,
                    size: height < 90 ? 30 : 34
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: height < 90 ? 30 : 34)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(width: 24, height: 24)
                        .background(OnboardingStepPalette.lime, in: Circle())
                        .offset(x: 7, y: -4)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)

            Text(LocalizedStringKey(title))
                .font(.system(size: height < 90 ? 12 : 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Button(action: onLevelTap) {
                HStack(spacing: 3) {
                    Text(isSelected ? levelTone : L10n.string("Choose level", "Выбери уровень"))
                        .font(.system(size: height < 90 ? 10 : 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .black))
                }
                .foregroundStyle(isSelected ? OnboardingStepPalette.lime : .white.opacity(0.82))
                .padding(.horizontal, 6)
                .padding(.vertical, height < 90 ? 6 : 7)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected
                        ? OnboardingStepPalette.lime.opacity(0.14)
                        : Color.white.opacity(0.10),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .frame(height: height)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(isSelected ? 0.12 : 0.08),
                    OnboardingStepPalette.panelRaised.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? OnboardingStepPalette.lime : OnboardingStepPalette.stroke, lineWidth: isSelected ? 1.6 : 1)
        )
        .shadow(color: isSelected ? OnboardingStepPalette.lime.opacity(0.16) : .black.opacity(0.26), radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onToggle)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isSelected)
    }

    private var title: String {
        localizedOnboardingSportTitle(sport)
    }

    private var levelTone: String {
        switch level {
        case 1 ... 2:
            return L10n.string("Beginner", "Новичок")
        case 3 ... 4:
            return L10n.string("Basic", "База")
        case 5 ... 6:
            return L10n.string("Confident", "Уверенный")
        case 7 ... 8:
            return L10n.string("Advanced", "Сильный")
        default:
            return L10n.string("Competitive", "Турнирный")
        }
    }
}

private struct MoreSportsTile: View {
    let isExpanded: Bool
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        VStack(spacing: height < 90 ? 5 : 6) {
            Image(systemName: isExpanded ? "chevron.up" : "ellipsis")
                .font(.system(size: height < 90 ? 17 : 19, weight: .black))
                .foregroundStyle(.white)
                .frame(width: height < 90 ? 36 : 40, height: height < 90 ? 36 : 40)
                .background(.white.opacity(0.08), in: Circle())

            Text(isExpanded ? L10n.string("Hide", "Скрыть") : L10n.string("More", "Ещё виды"))
                .font(.system(size: height < 90 ? 12 : 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 5) {
                Text(isExpanded ? L10n.string("Collapse", "Свернуть") : L10n.string("Open", "Открыть"))
                    .font(.system(size: height < 90 ? 8 : 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 5)
            .padding(.vertical, height < 90 ? 5 : 6)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .frame(height: height)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), OnboardingStepPalette.panelRaised.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(OnboardingStepPalette.stroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: action)
    }
}

private struct OnboardingProfileBasicsFields: View {
    @Binding var name: String
    @Binding var age: Int
    let isCompact: Bool
    let focusedField: FocusState<OnboardingProfileField?>.Binding
    let showsAgeValidation: Bool
    let onAgeEdited: () -> Void
    let onAgeSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            OnboardingNameField(name: $name, isCompact: isCompact, focusedField: focusedField)
            OnboardingAgeField(
                age: $age,
                isCompact: isCompact,
                focusedField: focusedField,
                showsValidation: showsAgeValidation,
                onEdited: onAgeEdited,
                onSubmit: onAgeSubmit
            )
        }
    }
}

private struct OnboardingNameField: View {
    @Binding var name: String
    let isCompact: Bool
    let focusedField: FocusState<OnboardingProfileField?>.Binding

    var body: some View {
        HStack(spacing: isCompact ? 10 : 14) {
            Image(systemName: "person")
                .font(.system(size: isCompact ? 18 : 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))

            ZStack(alignment: .leading) {
                if name.isEmpty {
                    Text(L10n.string("Name — this is how other players will see you", "Имя — так тебя увидят другие игроки"))
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.36))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                TextField("", text: $name)
                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .tint(OnboardingStepPalette.lime)
                    .focused(focusedField, equals: .name)
                    .onSubmit {
                        focusedField.wrappedValue = .age
                    }
            }
        }
        .padding(.horizontal, isCompact ? 14 : 18)
        .frame(height: isCompact ? 52 : 58)
        .background(OnboardingStepPalette.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct OnboardingAgeField: View {
    @Binding var age: Int
    let isCompact: Bool
    let focusedField: FocusState<OnboardingProfileField?>.Binding
    let showsValidation: Bool
    let onEdited: () -> Void
    let onSubmit: () -> Void

    private var isValidAge: Bool {
        (18 ... 100).contains(age)
    }

    private var showsInvalidState: Bool {
        showsValidation && !isValidAge
    }

    private var ageText: Binding<String> {
        Binding(
            get: {
                age > 0 ? "\(age)" : ""
            },
            set: { nextValue in
                let digits = String(nextValue.filter(\.isNumber).prefix(3))
                age = Int(digits) ?? 0
                onEdited()
            }
        )
    }

    var body: some View {
        HStack(spacing: isCompact ? 10 : 14) {
            Image(systemName: "birthday.cake")
                .font(.system(size: isCompact ? 18 : 22, weight: .medium))
                .foregroundStyle(showsInvalidState ? Color.red.opacity(0.82) : .white.opacity(0.32))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("Age", "Возраст"))
                    .font(.system(size: isCompact ? 10 : 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))

                TextField("18–100", text: ageText)
                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tint(OnboardingStepPalette.lime)
                    .focused(focusedField, equals: .age)
                    .onSubmit {
                        onSubmit()
                    }
            }

            Text("18–100")
                .font(.system(size: isCompact ? 12 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(showsInvalidState ? Color.red.opacity(0.9) : .white.opacity(0.44))
                .lineLimit(1)
        }
        .padding(.horizontal, isCompact ? 14 : 18)
        .frame(height: isCompact ? 52 : 58)
        .background(OnboardingStepPalette.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(showsInvalidState ? Color.red.opacity(0.68) : Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct OnboardingVisibilityToggle: View {
    @Binding var isOn: Bool
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 10 : 14) {
            Image(systemName: "person.2.fill")
                .font(.system(size: isCompact ? 18 : 22, weight: .bold))
                .foregroundStyle(OnboardingStepPalette.lime)
                .frame(width: isCompact ? 38 : 44, height: isCompact ? 38 : 44)
                .background(OnboardingStepPalette.lime.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: isCompact ? 2 : 5) {
                Text(L10n.string("Show me in search", "Показывать меня в поиске"))
                    .font(.system(size: isCompact ? 14 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(L10n.string("Other players can find you and invite you to play", "Другие игроки смогут найти тебя и предложить игру"))
                    .font(.system(size: isCompact ? 11 : 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(OnboardingStepPalette.lime)
        }
        .padding(isCompact ? 12 : 16)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), OnboardingStepPalette.panelRaised.opacity(0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OnboardingLevelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var level: Int

    var body: some View {
        ZStack {
            OnboardingDarkBackground()

            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(1 ... 10, id: \.self) { value in
                        Button {
                            AppHaptics.selection()
                            level = value
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(value)")
                                    .font(.system(size: 19, weight: .black, design: .rounded))
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(value == level ? Color.black.opacity(0.86) : .white)
                                    .background(value == level ? OnboardingStepPalette.lime : Color.white.opacity(0.10), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(levelTone(value)))
                                        .font(.subheadline.weight(.black))
                                        .foregroundStyle(.white)
                                    Text(LocalizedStringKey(levelHint(value)))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.54))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Color.white.opacity(value == level ? 0.12 : 0.07),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(value == level ? OnboardingStepPalette.lime.opacity(0.85) : Color.white.opacity(0.10), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
    }

    private func levelTone(_ value: Int) -> String {
        switch value {
        case 1 ... 2:
            return L10n.string("Beginner", "Новичок")
        case 3 ... 4:
            return L10n.string("Basic", "База")
        case 5 ... 6:
            return L10n.string("Confident", "Уверенный")
        case 7 ... 8:
            return L10n.string("Advanced", "Сильный")
        default:
            return L10n.string("Competitive", "Турнирный")
        }
    }

    private func levelHint(_ value: Int) -> String {
        switch value {
        case 1 ... 2:
            return L10n.string("just starting", "только начинаю")
        case 3 ... 4:
            return L10n.string("play occasionally", "играю иногда")
        case 5 ... 6:
            return L10n.string("solid fundamentals", "стабильная база")
        case 7 ... 8:
            return L10n.string("strong pace", "хороший темп")
        default:
            return L10n.string("competitive", "соревновательный")
        }
    }
}

private struct OnboardingAvailabilityEditorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

private enum OnboardingLocationChoice: Equatable {
    case nearby
    case districts
}

private struct OnboardingSearchLocationSection: View {
    let selectedChoice: OnboardingLocationChoice?
    let selectedCity: String
    let selectedDistricts: [String]
    let isDetectingLocation: Bool
    let locationDetectionFailed: Bool
    let isDetectedDistrictConfirmed: Bool
    let onNearby: () -> Void
    let onDistricts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(L10n.string("Where is it convenient to exercise?", "Где удобно заниматься спортом?"))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: "mappin")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(.top, 4)

            selectedCityPill

            HStack(spacing: 10) {
                OnboardingLocationChoiceCard(
                    title: L10n.string("Near me", "Рядом со мной"),
                    subtitle: nearbySubtitle,
                    accessibilityValue: nearbyAccessibilityValue,
                    systemImage: "location.fill",
                    tint: OnboardingStepPalette.lime,
                    isSelected: selectedChoice == .nearby,
                    action: onNearby
                )

                OnboardingLocationChoiceCard(
                    title: L10n.string("Choose city and districts", "Выбрать город и районы"),
                    subtitle: cityAndDistrictsSummary,
                    accessibilityValue: cityAndDistrictsAccessibilityValue,
                    systemImage: "map",
                    tint: Color(red: 0.62, green: 0.34, blue: 1.0),
                    isSelected: selectedChoice == .districts,
                    action: onDistricts
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            if selectedChoice == .nearby {
                locationDetectionStatus
            }
        }
    }

    @ViewBuilder
    private var selectedCityPill: some View {
        if selectedCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label(L10n.string("City not selected", "Город не выбран"), systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.34))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.22), lineWidth: 1)
                )
        } else if !isOnboardingCityAvailable(selectedCity) {
            Label(L10n.string("\(selectedCity): clubs coming soon", "\(selectedCity) скоро: добавляем клубы"), systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.34))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.22), lineWidth: 1)
                )
        } else {
            Label(selectedCity, systemImage: "building.2.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingStepPalette.lime)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OnboardingStepPalette.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(OnboardingStepPalette.lime.opacity(0.24), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var locationDetectionStatus: some View {
        if !selectedDistrictsSummary.isEmpty {
            let cityDistrictTitle = [selectedCity, selectedDistrictsSummary]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(L10n.string("Searching near \(cityDistrictTitle). You can change or add districts.", "Ищем рядом с \(cityDistrictTitle). Можно изменить или добавить районы."))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                }

                Button(action: onDistricts) {
                    Text(L10n.string("Change city and districts", "Изменить город и районы"))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .foregroundStyle(.white)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .buttonStyle(.plain)
            }
            .foregroundStyle(OnboardingStepPalette.lime)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingStepPalette.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(OnboardingStepPalette.lime.opacity(0.26), lineWidth: 1)
            )
        } else if selectedChoice == .nearby,
                  isDetectedDistrictConfirmed,
                  !selectedCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label(L10n.string("City detected: \(selectedCity)", "Город определён: \(selectedCity)"), systemImage: "location.circle.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingStepPalette.lime)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OnboardingStepPalette.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(OnboardingStepPalette.lime.opacity(0.26), lineWidth: 1)
                )
        } else if isDetectingLocation {
            Label {
                Text(L10n.string("Detecting your city and district from your location", "Определяем город и район по геолокации"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } icon: {
                ProgressView()
                    .tint(.white.opacity(0.72))
                    .controlSize(.mini)
            }
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if locationDetectionFailed {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(L10n.string("We couldn't detect your city and district. Choose them manually.", "Не удалось определить город и район по гео. Выбери вручную."))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                }

                Button(action: onDistricts) {
                    Text(L10n.string("Choose city and districts", "Выбрать город и районы"))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .foregroundStyle(Color.black.opacity(0.88))
                .background(Color(red: 1.0, green: 0.78, blue: 0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .buttonStyle(.plain)
            }
            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.34))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.22), lineWidth: 1)
            )
        }
    }

    private var selectedDistrictsSummary: String {
        validSelectedDistricts
            .prefix(2)
            .map { localizedDistrictName($0) ?? $0 }
            .joined(separator: ", ")
            .appending(validSelectedDistricts.count > 2 ? " +\(validSelectedDistricts.count - 2)" : "")
    }

    private var validSelectedDistricts: [String] {
        filteredOnboardingDistricts(selectedDistricts, cityName: selectedCity)
    }

    private var fullSelectedDistrictsSummary: String {
        validSelectedDistricts
            .map { localizedDistrictName($0) ?? $0 }
            .joined(separator: ", ")
    }

    private var cityAndDistrictsSummary: String {
        let city = selectedCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if city.isEmpty {
            return L10n.string("Choose a city", "Открыть выбор города")
        }

        if !isOnboardingCityAvailable(city) {
            return L10n.string("\(city) · clubs coming soon", "\(city) · добавляем клубы")
        }

        guard !validSelectedDistricts.isEmpty else {
            return city
        }

        return "\(city) · \(selectedDistrictsSummary)"
    }

    private var nearbySubtitle: String {
        guard selectedChoice == .nearby else {
            return L10n.string("Detect city and district", "Определить город и район")
        }

        if !selectedDistrictsSummary.isEmpty {
            return "\(selectedCity.isEmpty ? onboardingDefaultCity : selectedCity) · \(selectedDistrictsSummary)"
        }

        if locationDetectionFailed {
            return selectedCity.isEmpty ? L10n.string("Could not detect", "Не удалось определить") : selectedCity
        }

        if isDetectedDistrictConfirmed, !selectedCity.isEmpty {
            return selectedCity
        }

        return selectedCity.isEmpty
            ? L10n.string("Detecting city", "Определяем город")
            : L10n.string("\(selectedCity) · detecting district", "\(selectedCity) · определяем район")
    }

    private var nearbyAccessibilityValue: String {
        let city = selectedCity.isEmpty ? onboardingDefaultCity : selectedCity
        if selectedChoice == .nearby, !fullSelectedDistrictsSummary.isEmpty {
            return L10n.string(
                "Selected: \(city). Districts: \(fullSelectedDistrictsSummary)",
                "Выбрано: \(city). Районы: \(fullSelectedDistrictsSummary)"
            )
        }

        return nearbySubtitle
    }

    private var cityAndDistrictsAccessibilityValue: String {
        let city = selectedCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty, !fullSelectedDistrictsSummary.isEmpty else {
            return cityAndDistrictsSummary
        }

        return L10n.string(
            "Selected: \(city). Districts: \(fullSelectedDistrictsSummary)",
            "Выбрано: \(city). Районы: \(fullSelectedDistrictsSummary)"
        )
    }
}

private struct OnboardingLocationChoiceCard: View {
    let title: String
    let subtitle: String
    let accessibilityValue: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(isSelected ? 0.10 : 0.07), OnboardingStepPalette.panelRaised.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? tint : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: isSelected ? tint.opacity(0.14) : .black.opacity(0.18), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(LocalizedStringKey(accessibilityValue)))
    }
}

private final class OnboardingLocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var detectionGeneration = 0
    @Published var detectedCity: String?
    @Published var detectedDistrict: String?
    @Published var detectedCoordinate: CLLocationCoordinate2D?
    @Published var isResolvingDistrict = false
    @Published var didFailToDetectDistrict = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocationAccess() {
        detectionGeneration += 1
        geocoder.cancelGeocode()
        detectedCity = nil
        detectedDistrict = nil
        detectedCoordinate = nil
        didFailToDetectDistrict = false
        isResolvingDistrict = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            markDetectionFailed()
        @unknown default:
            markDetectionFailed()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            markDetectionFailed()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            markDetectionFailed()
            return
        }
        let generation = detectionGeneration

        DispatchQueue.main.async {
            self.detectedCoordinate = location.coordinate
        }

        let nearestCity = Self.nearestSupportedCity(to: location.coordinate)

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, generation == self.detectionGeneration else {
                return
            }

            if let placemark = placemarks?.first {
                let resolvedCity = Self.city(from: placemark) ?? nearestCity
                let district = Self.districtSlug(from: placemark, city: resolvedCity)
                    ?? Self.districtSlug(from: location.coordinate, city: resolvedCity)

                if let resolvedCity {
                    self.applyDetectedLocation(city: resolvedCity.rawValue, district: district)
                    return
                }
            }

            if let nearestCity {
                let district = Self.districtSlug(from: location.coordinate, city: nearestCity)
                self.applyDetectedLocation(city: nearestCity.rawValue, district: district)
                return
            }

            self.markDetectionFailed()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        markDetectionFailed()
    }

    private func applyDetectedLocation(city: String, district: String?) {
        DispatchQueue.main.async {
            self.isResolvingDistrict = false
            self.didFailToDetectDistrict = false
            self.detectedCity = city
            self.detectedDistrict = district
        }
    }

    private func markDetectionFailed() {
        DispatchQueue.main.async {
            self.isResolvingDistrict = false
            self.didFailToDetectDistrict = true
        }
    }

    private static func districtSlug(from coordinate: CLLocationCoordinate2D, city: SupportedCity?) -> String? {
        districtAreasByID.values
            .filter { area in
                city.map { area.city == $0 } ?? true
            }
            .filter { contains(coordinate, in: $0.rawPolygon) }
            .min { left, right in
                haversineDistanceKm(from: coordinate, to: center(of: left))
                    < haversineDistanceKm(from: coordinate, to: center(of: right))
            }?
            .id
    }

    private static func center(of area: DistrictMapArea) -> CLLocationCoordinate2D {
        let count = Double(max(area.rawPolygon.count, 1))
        let longitude = area.rawPolygon.reduce(0) { $0 + $1.0 } / count
        let latitude = area.rawPolygon.reduce(0) { $0 + $1.1 } / count
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func contains(_ coordinate: CLLocationCoordinate2D, in polygon: [(Double, Double)]) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }

        let longitude = coordinate.longitude
        let latitude = coordinate.latitude
        var isInside = false
        var previousIndex = polygon.count - 1

        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let currentLatitude = current.1
            let previousLatitude = previous.1
            let intersectsLatitude = (currentLatitude > latitude) != (previousLatitude > latitude)

            if intersectsLatitude {
                let currentLongitude = current.0
                let previousLongitude = previous.0
                let projectedLongitude = (previousLongitude - currentLongitude) * (latitude - currentLatitude) / (previousLatitude - currentLatitude) + currentLongitude

                if longitude < projectedLongitude {
                    isInside.toggle()
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }

    private static func districtSlug(from placemark: CLPlacemark, city: SupportedCity?) -> String? {
        let candidates = [
            placemark.subLocality,
            placemark.subAdministrativeArea,
            placemark.locality,
            placemark.name
        ] + (placemark.areasOfInterest ?? [])

        return candidates
            .compactMap { resolvedDistrictID(forDisplayName: $0, city: city) }
            .first
    }

    private static func city(from placemark: CLPlacemark) -> SupportedCity? {
        let candidates = [
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
            placemark.name
        ]

        for candidate in candidates {
            if let city = SupportedCity.resolve(candidate), onboardingAvailableCities.contains(city) {
                return city
            }
        }

        return nil
    }

    private static func nearestSupportedCity(to coordinate: CLLocationCoordinate2D) -> SupportedCity? {
        onboardingSupportedCities
            .map { city in
                (city, haversineDistanceKm(from: coordinate, to: city.mapCenter))
            }
            .filter { city, distanceKm in
                distanceKm <= city.mapDiameterMeters / 1_000
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}

private struct OnboardingDistrictPickerSheet: View {
    private enum Screen: Equatable {
        case city
        case districts
    }

    @Binding var selectedCity: String
    @Binding var selectedDistricts: [String]
    let automaticallyDetectedDistrict: String?
    let onDetectAutomatically: () -> Void
    let onDone: () -> Void

    @State private var screen: Screen
    @State private var draftCity: String
    @State private var draftDistricts: [String]

    init(
        selectedCity: Binding<String>,
        selectedDistricts: Binding<[String]>,
        automaticallyDetectedDistrict: String? = nil,
        startsWithDistricts: Bool = false,
        onDetectAutomatically: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        _selectedCity = selectedCity
        _selectedDistricts = selectedDistricts
        self.automaticallyDetectedDistrict = automaticallyDetectedDistrict
        self.onDetectAutomatically = onDetectAutomatically
        self.onDone = onDone

        let initialCity = isOnboardingCityAvailable(selectedCity.wrappedValue)
            ? selectedCity.wrappedValue
            : (onboardingCityOptions.first ?? "")
        _screen = State(initialValue: startsWithDistricts && isOnboardingCityAvailable(initialCity) ? .districts : .city)
        _draftCity = State(initialValue: initialCity)
        _draftDistricts = State(
            initialValue: filteredOnboardingDistricts(
                selectedDistricts.wrappedValue,
                cityName: initialCity
            )
        )
    }

    var body: some View {
        ZStack {
            OnboardingDarkBackground()

            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                header

                ScrollView(showsIndicators: false) {
                    Group {
                        switch screen {
                        case .city:
                            cityScreen
                        case .districts:
                            districtScreen
                        }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                }

                primaryButton
                    .padding(.top, 10)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
        }
    }

    private var canSubmit: Bool {
        isOnboardingCityAvailable(draftCity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if screen == .districts {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            screen = .city
                        }
                        AppHaptics.selection()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("Back to city selection", "Назад к выбору города"))
                }

                Spacer()

                HStack(spacing: 6) {
                    progressSegment(isActive: true)
                    progressSegment(isActive: screen == .districts)
                }

                Spacer()

                if screen == .districts {
                    Color.clear
                        .frame(width: 38, height: 38)
                }
            }

            Text(screen == .city ? L10n.string("Where will you play?", "Где вы будете играть?") : L10n.string("Where is it convenient for you to play?", "Где вам удобно играть?"))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(screen == .city
                 ? L10n.string("Choose a city so we can show nearby games and clubs.", "Выберите город, чтобы мы показывали игры и клубы рядом.")
                 : L10n.string("Choose one or more districts. You can skip this step.", "Выберите один или несколько районов. Этот шаг можно пропустить."))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            Text(screen == .city ? L10n.string("1 of 2", "1 из 2") : L10n.string("2 of 2", "2 из 2"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func progressSegment(isActive: Bool) -> some View {
        Capsule()
            .fill(isActive ? OnboardingStepPalette.lime : Color.white.opacity(0.16))
            .frame(width: 38, height: 5)
    }

    private var cityScreen: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button(action: onDetectAutomatically) {
                HStack(spacing: 14) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(OnboardingStepPalette.lime)
                        .frame(width: 42, height: 42)
                        .background(OnboardingStepPalette.lime.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("Detect automatically", "Определить автоматически"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(L10n.string("Use your current location", "Используем ваше текущее местоположение"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.56))
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.66))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 76)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.string("Request location access", "Запросить доступ к геопозиции"))

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("Available cities", "Доступные города"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))

                ForEach(onboardingCityOptions, id: \.self) { city in
                    cityButton(city)
                }
            }
        }
    }

    @ViewBuilder
    private var districtScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(OnboardingStepPalette.lime)

                Text(draftCity)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if districtOptions.isEmpty {
                Label(L10n.string("Districts haven't been added for this city yet. You can continue without them.", "Для этого города районы пока не добавлены. Можно продолжить без них."), systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("Districts", "Районы"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))

                    LazyVStack(spacing: 10) {
                        ForEach(districtOptions, id: \.self) { district in
                            districtButton(district)
                        }
                    }
                }
            }

            if !draftDistricts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("Selected places", "Выбранные места"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))

                    ForEach(draftDistricts, id: \.self) { district in
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(OnboardingStepPalette.lime)

                            Text(localizedDistrictName(district) ?? district)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)

                            Spacer()

                            Button {
                                draftDistricts.removeAll { $0 == district }
                                AppHaptics.selection()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.string("Remove \(localizedDistrictName(district) ?? district)", "Удалить \(localizedDistrictName(district) ?? district)"))
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var primaryButton: some View {
        Button {
            switch screen {
            case .city:
                withAnimation(.easeInOut(duration: 0.2)) {
                    screen = .districts
                }
                AppHaptics.selection()
            case .districts:
                selectedCity = draftCity
                selectedDistricts = filteredOnboardingDistricts(draftDistricts, cityName: draftCity)
                onDone()
                AppHaptics.notification(.success)
            }
        } label: {
            Text(screen == .city ? L10n.string("Continue", "Продолжить") : L10n.string("Done", "Готово"))
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canSubmit ? OnboardingStepPalette.lime : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(canSubmit ? Color.black.opacity(0.88) : .white.opacity(0.38))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private func cityButton(_ city: String) -> some View {
        let isSelected = draftCity == city

        return Button {
            if draftCity != city {
                draftDistricts.removeAll()
            }
            draftCity = city
            AppHaptics.selection()
        } label: {
            HStack(spacing: 14) {
                if let imageName = onboardingCityImageName(for: city) {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .overlay(isSelected ? Color.white.opacity(0.06) : Color.black.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                }

                Text(city)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.82) : .white.opacity(0.48))
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 68)
            .background(isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(city)
        .accessibilityValue(Text(isSelected ? L10n.string("Selected", "Выбрано") : L10n.string("Not selected", "Не выбрано")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func districtButton(_ district: String) -> some View {
        let isSelected = draftDistricts.contains(district)
        let isAutomaticallyDetected = district == automaticallyDetectedDistrict
        let title = localizedDistrictName(district) ?? district

        return Button {
            if isSelected {
                draftDistricts.removeAll { $0 == district }
            } else {
                draftDistricts.append(district)
            }
            AppHaptics.selection()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if isAutomaticallyDetected {
                        Text(L10n.string("Detected from your location", "Определено по геопозиции"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isSelected ? Color.black.opacity(0.62) : OnboardingStepPalette.lime)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(Text(isSelected ? L10n.string("Selected", "Выбрано") : L10n.string("Not selected", "Не выбрано")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var districtOptions: [String] {
        onboardingDistrictOptions(for: draftCity)
    }
}

private struct OTPCodeField: View {
    enum Verdict: Equatable {
        case none
        case accepted
        /// Carries the attempt number, so every rejection shakes again.
        case rejected(Int)

        var attempt: Int {
            if case .rejected(let attempt) = self { return attempt }
            return 0
        }
    }

    @Binding var code: String
    var verdict: Verdict = .none
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var digits: [String] {
        let values = Array(code.prefix(6)).map(String.init)
        return values + Array(repeating: "", count: max(0, 6 - values.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Verification code", "Код подтверждения"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .textCase(.uppercase)
                .tracking(1.4)

            ZStack {
                HStack(spacing: 10) {
                    ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(boxFill)
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(boxStroke(at: index), lineWidth: isHighlighted(index) ? 2 : 1)

                            // Each digit pops in as it is typed.
                            Text(digit.isEmpty ? "•" : digit)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(digit.isEmpty ? AppTheme.mutedInk.opacity(0.34) : AppTheme.ink)
                                .id(digit.isEmpty ? "empty-\(index)" : "digit-\(index)-\(digit)")
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                    }
                }
                .modifier(OTPShake(shakes: CGFloat(reduceMotion ? 0 : verdict.attempt)))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: code)

                TextField("", text: Binding(
                    get: { code },
                    set: { newValue in
                        code = String(newValue.filter { $0.isNumber }.prefix(6))
                    }
                ))
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .foregroundColor(.clear)
                .accentColor(.clear)
                .opacity(0.01)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
        }
    }

    private var boxFill: Color {
        switch verdict {
        case .accepted: return AppTheme.mint
        case .rejected: return Color(red: 1, green: 0.9, blue: 0.88)
        case .none: return AppTheme.creamLight
        }
    }

    private func isHighlighted(_ index: Int) -> Bool {
        verdict != .none || (index == min(code.count, 5) && isFocused)
    }

    private func boxStroke(at index: Int) -> Color {
        switch verdict {
        case .accepted: return AppTheme.court
        case .rejected: return Color(red: 0.86, green: 0.24, blue: 0.2)
        case .none: return isHighlighted(index) ? AppTheme.court : AppTheme.court.opacity(0.16)
        }
    }
}

/// Side-to-side shake, one full shake per whole step of `shakes`.
private struct OTPShake: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(shakes * .pi * 4), y: 0))
    }
}

private struct SportCard: View {
    let sport: Sport
    let isSelected: Bool
    @Binding var level: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    SportIconView(
                        sport: sport,
                        color: isSelected ? .white : AppTheme.court,
                        size: 17
                    )
                        .frame(width: 30, height: 30)
                        .background(isSelected ? .white.opacity(0.16) : .white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text(LocalizedStringKey(sport.title))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? .white : AppTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }

                if isSelected {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.string("Level", "Уровень"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Text(LocalizedStringKey(levelTone))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.14), in: Capsule())
                        }

                        HStack(spacing: 8) {
                            levelButton("-", action: { level = max(1, level - 1) })
                            HStack(spacing: 3) {
                                ForEach(1 ... 10, id: \.self) { index in
                                    Capsule()
                                        .fill(index <= level ? Color.white.opacity(0.9) : Color.white.opacity(0.16))
                                        .frame(height: 8)
                                }
                            }
                            levelButton("+", action: { level = min(10, level + 1) })
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [AppTheme.court, AppTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.white.opacity(0.92), AppTheme.creamLight.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.16 : 0.74), lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(isSelected ? 0.14 : 0.05), radius: isSelected ? 18 : 10, x: 0, y: isSelected ? 14 : 8)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isSelected)
    }

    private var levelTone: String {
        switch level {
        case 1 ... 2:
            return L10n.string("Beginner", "Новичок")
        case 3 ... 4:
            return L10n.string("Basic", "База")
        case 5 ... 6:
            return L10n.string("Confident", "Уверенный")
        case 7 ... 8:
            return L10n.string("Advanced", "Сильный")
        default:
            return L10n.string("Competitive", "Турнирный")
        }
    }

    private var iconName: String {
        sport.appSystemIconName
    }

    private func levelButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.headline.weight(.bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.14), in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

private struct DetailedAvailabilityEditor: View {
    @Binding var availabilityByDay: [String: [String]]
    @State private var activeDay: DayOfWeek = .monday

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(DayOfWeek.allCases) { day in
                    let ranges = availabilityByDay[day.rawValue] ?? []
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            activeDay = day
                        }
                        AppHaptics.selection()
                    } label: {
                        VStack(spacing: 6) {
                            Text(LocalizedStringKey(day.shortTitle))
                                .font(.subheadline.weight(.bold))
                            HStack(spacing: 3) {
                                ForEach(TimeRange.allCases) { range in
                                    Circle()
                                        .fill(ranges.contains(range.rawValue) ? (activeDay == day ? .white : AppTheme.court) : (activeDay == day ? .white.opacity(0.24) : AppTheme.ink.opacity(0.12)))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .foregroundStyle(activeDay == day ? .white : AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(activeDay == day ? AppTheme.ink : AppTheme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey(activeDay.title))
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    if !(availabilityByDay[activeDay.rawValue] ?? []).isEmpty {
                        Button(L10n.string("Clear", "Очистить")) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                                availabilityByDay[activeDay.rawValue] = []
                            }
                            AppHaptics.selection()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.clay)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(TimeRange.allCases) { range in
                        AvailabilityWindowCard(
                            range: range,
                            isSelected: (availabilityByDay[activeDay.rawValue] ?? []).contains(range.rawValue)
                        ) {
                            toggle(range)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                presetButton(L10n.string("Weekday mornings", "Будни утром")) {
                    applyPreset(days: [.monday, .tuesday, .wednesday, .thursday, .friday], ranges: [.morning])
                }
                presetButton(L10n.string("Weekday evenings", "Будни вечером")) {
                    applyPreset(days: [.monday, .tuesday, .wednesday, .thursday, .friday], ranges: [.evening])
                }
                presetButton(L10n.string("Weekends", "Выходные")) {
                    applyPreset(days: [.saturday, .sunday], ranges: TimeRange.allCases)
                }
            }
        }
    }

    private func toggle(_ range: TimeRange) {
        var current = availabilityByDay[activeDay.rawValue] ?? []
        if current.contains(range.rawValue) {
            current.removeAll { $0 == range.rawValue }
        } else {
            current.append(range.rawValue)
        }
        availabilityByDay[activeDay.rawValue] = current.uniqued()
        AppHaptics.selection()
    }

    private func applyPreset(days: [DayOfWeek], ranges: [TimeRange]) {
        let rawRanges = ranges.map(\.rawValue)
        for day in days {
            availabilityByDay[day.rawValue] = rawRanges
        }
        AppHaptics.selection()
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(AppTheme.cream, in: Capsule())
        }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
    }
}

private struct AvailabilityWindowCard: View {
    let range: TimeRange
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(iconBackground, in: Circle())
                Text(LocalizedStringKey(range.title))
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            // A corner check instead of a "Selected" row keeps the card height fixed.
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .padding(7)
                }
            }
            .foregroundStyle(isSelected ? activeTextColor : inactiveTextColor)
            .shadow(color: shadowColor, radius: isSelected ? 16 : 8, x: 0, y: isSelected ? 12 : 6)
            .scaleEffect(isSelected ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconName: String {
        switch range {
        case .morning:
            return "sunrise.fill"
        case .day:
            return "sun.max.fill"
        case .evening:
            return "moon.stars.fill"
        }
    }

    private var background: LinearGradient {
        switch range {
        case .morning:
            return LinearGradient(colors: isSelected ? [Color(red: 1, green: 0.95, blue: 0.84), Color(red: 1, green: 0.86, blue: 0.7)] : [Color(red: 1, green: 0.98, blue: 0.92), Color(red: 1, green: 0.93, blue: 0.84)], startPoint: .top, endPoint: .bottom)
        case .day:
            return LinearGradient(colors: isSelected ? [Color(red: 1, green: 0.97, blue: 0.8), Color(red: 1, green: 0.91, blue: 0.57)] : [Color(red: 1, green: 0.98, blue: 0.89), Color(red: 1, green: 0.95, blue: 0.78)], startPoint: .top, endPoint: .bottom)
        case .evening:
            return LinearGradient(colors: isSelected ? [Color(red: 0.89, green: 0.92, blue: 1), Color(red: 0.79, green: 0.84, blue: 1)] : [Color(red: 0.96, green: 0.97, blue: 1), Color(red: 0.91, green: 0.93, blue: 1)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var activeTextColor: Color {
        switch range {
        case .morning:
            return Color(red: 0.54, green: 0.29, blue: 0.13)
        case .day:
            return Color(red: 0.54, green: 0.35, blue: 0)
        case .evening:
            return Color(red: 0.2, green: 0.3, blue: 0.48)
        }
    }

    private var inactiveTextColor: Color {
        activeTextColor.opacity(0.8)
    }

    private var iconBackground: Color {
        isSelected ? .white.opacity(0.98) : .white.opacity(0.76)
    }

    private var borderColor: Color {
        isSelected ? activeTextColor.opacity(0.42) : Color.white.opacity(0.82)
    }

    private var shadowColor: Color {
        activeTextColor.opacity(isSelected ? 0.15 : 0.06)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
