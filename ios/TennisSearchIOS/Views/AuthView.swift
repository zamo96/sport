import AuthenticationServices
import CoreLocation
import MapKit
import SwiftUI

private enum OnboardingProfileField: Hashable {
    case name
    case age
}

private let onboardingGeoDetectedCity = "Санкт-Петербург"
private let onboardingCityOptions = ["Санкт-Петербург", "Москва", "Казань"]
private let onboardingAvailableCities = ["Санкт-Петербург"]

private func isOnboardingCityAvailable(_ city: String) -> Bool {
    onboardingAvailableCities.contains(city.trimmingCharacters(in: .whitespacesAndNewlines))
}

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    @State private var code = ""
    @State private var draft: GuestOnboardingDraft
    @State private var step: AuthStep
    @State private var userAgreementAccepted = false
    @State private var appStats: AppStats?
    @State private var selectedLevelSport: Sport?
    @State private var selectedLocationChoice: OnboardingLocationChoice?
    @State private var showsDistrictPicker = false
    @State private var detectedDistrictForConfirmation: String?
    @State private var showsDetectedDistrictConfirmation = false
    @State private var isDetectedDistrictConfirmed = false
    @State private var didAutoRequestAvailabilityLocation = false
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
                        Button("Закрыть") {
                            appModel.dismissPresentedAuth()
                            dismiss()
                        }
                    }
                }

                if step == .profile && profileFocusedField != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("Скрыть") {
                            profileFocusedField = nil
                        }

                        Spacer()

                        Button("Дальше") {
                            advanceFromProfile()
                        }
                        .font(.headline.weight(.bold))
                        .disabled(!draft.hasProfileBasics)
                    }
                }
            }
            .task {
                draft = appModel.guestDraft
                selectedLocationChoice = draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.preferredDistricts.isEmpty ? nil : .districts
                if appModel.presentedAuthStep == .code {
                    step = .code
                }
                await loadAppStats()
            }
            .onChange(of: appModel.presentedAuthStep) { newValue in
                guard let newValue else {
                    return
                }
                step = newValue
            }
            .onChange(of: appModel.currentUser?.id) { newValue in
                if newValue != nil && !embedded {
                    dismiss()
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
            .sheet(isPresented: $showsDistrictPicker, onDismiss: {
                selectedLocationChoice = draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.preferredDistricts.isEmpty ? nil : .districts
            }) {
                OnboardingDistrictPickerSheet(
                    selectedCity: $draft.city,
                    selectedDistricts: $draft.preferredDistricts,
                    onDone: {
                        draft.city = draft.city.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !isOnboardingCityAvailable(draft.city) {
                            draft.city = ""
                        }
                        if draft.city != onboardingGeoDetectedCity {
                            draft.preferredDistricts.removeAll()
                        }
                        draft.district = draft.preferredDistricts.first
                        selectedLocationChoice = draft.city.isEmpty && draft.preferredDistricts.isEmpty ? nil : .districts
                        showsDistrictPicker = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsDetectedDistrictConfirmation) {
                if let district = detectedDistrictForConfirmation {
                    OnboardingDetectedDistrictSheet(
                        districtID: district,
                        userCoordinate: locationPermission.detectedCoordinate,
                        onConfirm: confirmDetectedDistrict,
                        onChooseDistrict: {
                            isDetectedDistrictConfirmed = false
                            selectedLocationChoice = .districts
                            draft.city = onboardingGeoDetectedCity
                            draft.preferredDistricts.removeAll()
                            draft.district = nil
                            showsDetectedDistrictConfirmation = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showsDistrictPicker = true
                            }
                            AppHaptics.selection()
                        }
                    )
                    .presentationDetents([.height(520), .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: locationPermission.detectedDistrict) { district in
                guard let district else {
                    return
                }
                guard step == .availability else {
                    return
                }
                selectedLocationChoice = .nearby
                draft.city = onboardingGeoDetectedCity
                detectedDistrictForConfirmation = district
                isDetectedDistrictConfirmed = false
                showsDetectedDistrictConfirmation = true
                AppHaptics.notification(.success)
            }
            .onChange(of: step) { newValue in
                if newValue != .availability {
                    showsDetectedDistrictConfirmation = false
                } else {
                    requestAvailabilityLocationIfNeeded()
                }
            }
        }
    }

    @ViewBuilder
    private var contentForStep: some View {
        switch step {
        case .intro:
            introScreen
        case .email:
            emailStep
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

    private var introScreen: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let isCompact = geometry.size.height < 760
            let heroHeight = isCompact
                ? min(max(geometry.size.height * 0.34, 230), 300)
                : min(max(geometry.size.height * 0.44, 340), 470)
            let titleTopOffset = isCompact ? max(24, safeTop + 4) : max(38, safeTop + 8)
            let verticalSpacing: CGFloat = isCompact ? 14 : 20

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Найди напарника")
                            .font(.system(size: isCompact ? 34 : 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        OnboardingTypewriterLine()

                        Text(seekingPlayersLine)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    OnboardingMotionHero(height: heroHeight)

                    Spacer(minLength: 8)

                    LiquidStartButton(title: "Начать", subtitle: "Шаг 1 из 2") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
                            step = .profile
                        }
                    }
                    .frame(height: 72)

                    existingAccountButton

                    Spacer()
                        .frame(height: max(isCompact ? 8 : 14, safeBottom))
                }
                .padding(.horizontal, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .onAppear {
            requestAvailabilityLocationIfNeeded()
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
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 17, weight: .semibold))
                Text("Уже есть аккаунт? Войти")
                    .font(.system(size: 16, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(.white.opacity(0.10), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Войти в существующий аккаунт")
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
                Text("Найди напарника")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                OnboardingTypewriterLine()

                Text("Соберём быстрый профиль и откроем подбор игроков. Доступность можно оставить пустой и заполнить позже, а email понадобится только для защищённых действий: мэтчей, чатов, уведомлений и сохранения.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(3)
            }

            LiquidStartButton(title: "Начать", subtitle: "Шаг 1 из 2") {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    step = .profile
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
                            Text("Шаг 1 из 2")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .overlay(alignment: .leading) {
                                    Text("Шаг 1")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(OnboardingStepPalette.lime)
                                }

                            Text("Во что хочешь\nсыграть?")
                                .font(.system(size: titleSize, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineSpacing(-5)
                                .minimumScaleFactor(0.78)

                            Text("Выбери виды спорта и укажи уровень — покажем подходящих игроков рядом.")
                                .font(.system(size: subtitleSize, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: isCompact ? 7 : 8) {
                            Text("Виды спорта")
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
                            Text("Имя и возраст")
                                .font(.headline.weight(.black))
                                .foregroundStyle(.white)

                            OnboardingProfileBasicsFields(
                                name: $draft.name,
                                age: $draft.age,
                                isCompact: isCompact,
                                focusedField: $profileFocusedField,
                                onAgeSubmit: advanceFromProfile
                            )

                            Text("Возраст обязателен: от 18 до 100 лет.")
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
                                    Text("Назад")
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
                                    Text("Дальше")
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
            let horizontalPadding: CGFloat = isCompact ? 18 : 24
            let topPadding: CGFloat = max(isCompact ? 58 : 64, geometry.safeAreaInsets.top + (isCompact ? 24 : 30))
            let bottomPadding: CGFloat = max(14, geometry.safeAreaInsets.bottom + 10)
            let verticalSpacing: CGFloat = isCompact ? 9 : 12
            let actionHeight: CGFloat = isCompact ? 52 : 58

            ZStack {
                OnboardingDarkBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: verticalSpacing) {
                        OnboardingStepProgress(current: 2, total: 2)
                            .padding(.top, topPadding)

                        VStack(alignment: .leading, spacing: isCompact ? 5 : 7) {
                            Text("Шаг 2 из 2")
                                .font(.system(size: isCompact ? 22 : 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .overlay(alignment: .leading) {
                                    Text("Шаг 2")
                                        .font(.system(size: isCompact ? 22 : 24, weight: .black, design: .rounded))
                                        .foregroundStyle(OnboardingStepPalette.lime)
                                }

                            Text("Когда тебе удобно играть. Можно оставить пустым и настроить позже.")
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
                                detectedDistrictForConfirmation = nil
                                draft.city = onboardingGeoDetectedCity
                                draft.preferredDistricts.removeAll()
                                draft.district = nil
                                locationPermission.requestLocationAccess()
                                AppHaptics.selection()
                            },
                            onConfirmDetectedDistrict: {
                                confirmDetectedDistrict()
                            },
                            onDistricts: {
                                selectedLocationChoice = .districts
                                isDetectedDistrictConfirmed = false
                                showsDistrictPicker = true
                                AppHaptics.selection()
                            }
                        )

                        HStack(spacing: 12) {
                            Button {
                                persistDraft()
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                                    step = .profile
                                }
                            } label: {
                                Text("Назад")
                                    .font(.system(size: isCompact ? 18 : 20, weight: .black, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: actionHeight)
                            }
                            .foregroundStyle(.white)
                            .background(OnboardingStepPalette.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .buttonStyle(.plain)

                            Button {
                                finishGuestOnboarding()
                            } label: {
                                Text(embedded ? "Смотреть игроков" : "Продолжить")
                                    .font(.system(size: isCompact ? 18 : 20, weight: .black, design: .rounded))
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
            userAgreementAccepted: $userAgreementAccepted,
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
                guard userAgreementAccepted else {
                    appModel.errorMessage = LegalDocuments.acceptanceError
                    return
                }
                persistDraft()
                Task {
                    await appModel.requestCode(userAgreementAccepted: userAgreementAccepted)
                }
            },
            onHaveCode: {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    step = .code
                }
            },
            onBack: {
                persistDraft()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    step = draft.hasProfileBasics ? .availability : .intro
                }
            }
        )
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(title: "Подтверждение", subtitle: "Введи 6 цифр из письма или логов. После проверки профиль будет сохранён в аккаунт.") {
                VStack(alignment: .leading, spacing: 12) {
                    OTPCodeField(code: $code)

                    Button("Войти") {
                        guard userAgreementAccepted else {
                            appModel.errorMessage = LegalDocuments.acceptanceError
                            return
                        }
                        persistDraft()
                        Task {
                            await appModel.verify(code: code, userAgreementAccepted: userAgreementAccepted)
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).count != 6 || !userAgreementAccepted)
                }
            }

            HStack {
                Button("Изменить email") {
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
        guard draft.hasProfileBasics else { return }
        persistDraft()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            step = .availability
        }
    }

    private var canFinishAvailability: Bool {
        isOnboardingCityAvailable(draft.city)
    }

    private var seekingPlayersLine: String {
        let count = appStats?.registeredPlayersCount ?? 315
        return "Ищут игру: \(count.formatted(.number.grouping(.automatic))) игроков"
    }

    private func loadAppStats() async {
        guard appStats == nil else {
            return
        }

        do {
            appStats = try await appModel.repository.fetchAppStats()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appStats = AppStats(registeredPlayersCount: 315, seekingPlayersCount: 315)
        }
    }

    private func finishGuestOnboarding() {
        var completedDraft = normalizedDraft()
        guard completedDraft.hasProfileBasics else {
            draft = completedDraft
            appModel.errorMessage = "Укажи имя, возраст от 18 до 100 и хотя бы один вид спорта."
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                step = .profile
            }
            return
        }
        guard isOnboardingCityAvailable(completedDraft.city) else {
            draft = completedDraft
            appModel.errorMessage = "Сейчас доступен Санкт-Петербург. Москва и Казань появятся после добавления клубов."
            return
        }
        completedDraft.onboardingCompleted = true
        appModel.updateGuestDraft(completedDraft)
        appModel.queueDiscoverSimilarPlayersHint()
        guard !embedded else {
            return
        }
        appModel.dismissPresentedAuth()
        dismiss()
    }

    private func confirmDetectedDistrict() {
        let district = detectedDistrictForConfirmation ?? draft.district ?? locationPermission.detectedDistrict

        if let district {
            draft.city = onboardingGeoDetectedCity
            draft.district = district
            draft.preferredDistricts = [district]
            detectedDistrictForConfirmation = district
        }

        selectedLocationChoice = .nearby
        isDetectedDistrictConfirmed = true
        showsDetectedDistrictConfirmation = false
        persistDraft()
        AppHaptics.notification(.success)
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
        detectedDistrictForConfirmation = nil
        draft.city = onboardingGeoDetectedCity
        draft.preferredDistricts.removeAll()
        draft.district = nil
        locationPermission.requestLocationAccess()
    }

    private var currentStepLabel: String {
        switch step {
        case .intro:
            return "Быстрый старт"
        case .profile:
            return "Шаг 1 из 2"
        case .availability:
            return "Шаг 2 из 2"
        case .email:
            return "Email"
        case .code:
            return "Код"
        }
    }

    private var currentStepSubtitle: String {
        switch step {
        case .intro:
            return "Собери черновик профиля, посмотри подбор и подтверди email только когда нужно."
        case .profile:
            return "Базовая карточка игрока: имя, возраст, спорт и уровень."
        case .availability:
            return "Дни недели и окна времени. Можно оставить пустым и заполнить позже."
        case .email:
            return "Email нужен только для защищённых действий: мэтчей, переписки, уведомлений и сохранения откликов."
        case .code:
            return "Подтверждение кода и перенос черновика в полноценный аккаунт."
        }
    }

    private func normalizedDraft() -> GuestOnboardingDraft {
        var next = draft
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.city = next.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isOnboardingCityAvailable(next.city) {
            next.city = ""
        }
        if next.city != onboardingGeoDetectedCity {
            next.district = nil
            next.preferredDistricts.removeAll()
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
                appModel.errorMessage = "Не удалось получить данные Apple ID. Попробуй ещё раз или используй email."
                return
            }

            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                appModel.errorMessage = "Apple не передал identity token. Попробуй ещё раз."
                return
            }
            guard userAgreementAccepted else {
                appModel.errorMessage = LegalDocuments.acceptanceError
                return
            }

            persistDraft()

            Task {
                await appModel.signInWithApple(
                    identityToken: identityToken,
                    email: credential.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName,
                    userAgreementAccepted: userAgreementAccepted
                )
            }

        case let .failure(error):
            if let authorizationError = error as? ASAuthorizationError {
                switch authorizationError.code {
                case .canceled:
                    appModel.errorMessage = nil
                case .unknown:
                    appModel.errorMessage = "Вход через Apple не завершён. Проверь, что для App ID shop.sportsearch.app включен Sign in with Apple, затем обнови профиль подписи в Xcode."
                default:
                    appModel.errorMessage = "Вход через Apple не завершён: \(authorizationError.localizedDescription)"
                }
            } else {
                appModel.errorMessage = "Вход через Apple не завершён: \(error.localizedDescription)"
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
            Text(text)
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
            Text(title)
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
                        Text(item[keyPath: titleForItem])
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
    @Binding var email: String
    @Binding var userAgreementAccepted: Bool
    let authMessage: String?
    let errorMessage: String?
    let debugCode: String?
    let embedded: Bool
    let onClose: () -> Void
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void
    let onRequestCode: () -> Void
    let onHaveCode: () -> Void
    let onBack: () -> Void

    @FocusState private var isEmailFocused: Bool
    @State private var isEmailLoginExpanded = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AuthReferenceBackground()

                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        if !embedded {
                            Button("Закрыть", action: onClose)
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
                                Label("Назад", systemImage: "arrow.left")
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

    private var legalAcceptanceControl: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                userAgreementAccepted.toggle()
                AppHaptics.selection()
            } label: {
                Image(systemName: userAgreementAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(userAgreementAccepted ? AppTheme.court : AppTheme.ink.opacity(0.45))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(userAgreementAccepted ? "Согласие принято" : "Принять пользовательское соглашение")

            VStack(alignment: .leading, spacing: 6) {
                Text("Принимаю пользовательское соглашение и даю согласие на обработку персональных данных.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                if let url = LegalDocuments.userAgreementURL {
                    Link("Открыть пользовательское соглашение", destination: url)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.court)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(userAgreementAccepted ? AppTheme.court.opacity(0.35) : Color(.systemGray4), lineWidth: 1)
        )
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Вход в профиль")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("Войди через Apple, чтобы сохранить профиль, матчи, переписки и уведомления.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SignInWithAppleButton(.continue, onRequest: onAppleRequest, onCompletion: onAppleCompletion)
                .signInWithAppleButtonStyle(.black)
                .frame(height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(!userAgreementAccepted)
                .opacity(userAgreementAccepted ? 1 : 0.45)

            legalAcceptanceControl

            if isEmailLoginExpanded {
                AuthDividerLabel(text: "или войти по Email")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Email")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    TextField("email@example.com", text: $email)
                        .font(.title3)
                        .foregroundStyle(AppTheme.ink)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEmailFocused)
                        .padding(.horizontal, 18)
                        .frame(height: 68)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isEmailFocused ? AppTheme.court.opacity(0.72) : Color(.systemGray4), lineWidth: isEmailFocused ? 1.5 : 1)
                        )
                }

                Button(action: onRequestCode) {
                    Text("Получить код по email")
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
                .disabled(!userAgreementAccepted)
                .opacity(userAgreementAccepted ? 1 : 0.52)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Email-вход нужен, если ты уже регистрировался без Apple ID.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Button("У меня уже есть код", action: onHaveCode)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.court)
                        .disabled(!userAgreementAccepted)
                        .opacity(userAgreementAccepted ? 1 : 0.52)
                }
            } else {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        isEmailLoginExpanded = true
                    }
                } label: {
                    Label("Войти по email", systemImage: "envelope")
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
            Text(text)
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
        Label(text, systemImage: icon)
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
    private let phrases = [
        "для игры в футбол",
        "для игры в теннис",
        "для похода в зал",
        "для похода на йогу"
    ]

    @State private var displayedPhrase = ""
    @State private var typingTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.48)) { timeline in
            let cursorVisible = Int(timeline.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)

            HStack(spacing: 2) {
                Text(displayedPhrase)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: 30)
                    .opacity(cursorVisible ? 1 : 0.22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 42, alignment: .leading)
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.03, green: 0.04, blue: 0.06),
                                Color(red: 0.06, green: 0.07, blue: 0.09),
                                Color(red: 0.03, green: 0.04, blue: 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .black.opacity(0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .fill(AppTheme.court.opacity(0.16))
                    .frame(width: 250, height: 250)
                    .blur(radius: 72)
                    .offset(x: -126 + CGFloat(sin(time * 0.34)) * 16, y: 38)

                Circle()
                    .fill(AppTheme.clay.opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 78)
                    .offset(x: 152 + CGFloat(cos(time * 0.31)) * 18, y: -28)

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 210, height: 210)
                    .blur(radius: 88)
                    .offset(x: 16, y: -140)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.black.opacity(0.32))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)

                VStack(spacing: 18) {
                    OnboardingLoopingCards(time: time)
                        .frame(height: height * 0.7)
                        .padding(.top, 2)

                    HStack(spacing: 8) {
                        ForEach(0 ..< 4, id: \.self) { index in
                            Circle()
                                .fill(index == 1 ? .white : .white.opacity(0.34))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                .padding(18)
            }
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 28, x: 0, y: 18)
        }
    }
}

private struct OnboardingLoopingCards: View {
    private let cards: [OnboardingPreviewCardData] = [
        .init(name: "Дмитрий, 29", sport: "Теннис", level: "Средний", metaLeft: "До 3 км", metaRight: "Сегодня, 8:30", imageName: "hero-tennis"),
        .init(name: "Максим, 27", sport: "Футбол", level: "Любитель", metaLeft: "До 5 км", metaRight: "Сегодня, 19:00", imageName: "hero-football"),
        .init(name: "Антон, 31", sport: "Зал", level: "Уверенный", metaLeft: "До 4 км", metaRight: "Завтра, 7:10", imageName: "hero-fitness")
    ]

    let time: TimeInterval

    private let cardWidth: CGFloat = 228
    private let cardSpacing: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let unit = cardWidth + cardSpacing
            let cycleWidth = unit * CGFloat(cards.count)
            let progress = CGFloat(time * 15).truncatingRemainder(dividingBy: cycleWidth)

            ZStack {
                ForEach(Array((cards + cards).enumerated()), id: \.offset) { index, card in
                    let baseX = CGFloat(index) * unit - progress
                    let wrappedX = baseX < -unit ? baseX + cycleWidth * 2 : baseX
                    let relative = wrappedX - geometry.size.width * 0.18
                    let centerDistance = abs(relative - geometry.size.width * 0.28)
                    let focus = max(0, 1 - centerDistance / 190)
                    let direction = ((geometry.size.width * 0.28) - relative) / max(geometry.size.width, 1)
                    let scale = 0.8 + focus * 0.28
                    let opacity = 0.22 + focus * 0.78
                    let phase = (wrappedX / max(cycleWidth, 1)) * .pi * 2
                    let orbitY = sin(phase - time * 0.72) * 12 - focus * 16
                    let tilt = sin(phase - time * 0.54) * 1.8
                    let perspectiveAngle = direction * 34
                    let depthX = direction * 18

                    OnboardingPreviewCard(card: card)
                        .frame(width: cardWidth)
                        .scaleEffect(scale)
                        .opacity(opacity)
                        .rotationEffect(.degrees(tilt))
                        .rotation3DEffect(
                            .degrees(perspectiveAngle),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.72
                        )
                        .shadow(
                            color: .black.opacity(0.18 + focus * 0.22),
                            radius: 14 + focus * 14,
                            x: depthX,
                            y: 18 + focus * 10
                        )
                        .offset(x: wrappedX, y: orbitY)
                        .zIndex(Double(focus))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .mask(
                Rectangle()
                    .frame(width: geometry.size.width, height: geometry.size.height + 76)
                    .offset(y: -24)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .frame(height: 168)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(card.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    chip(text: card.sport, tint: Color(red: 0.35, green: 0.55, blue: 0.23))
                    chip(text: card.level, tint: .white.opacity(0.12))
                }

                HStack(spacing: 6) {
                    metaChip(icon: "location.fill", text: card.metaLeft)
                    metaChip(icon: "plus.circle.fill", text: card.metaRight)
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.12, blue: 0.13), Color.black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 16)
    }

    private func chip(text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(tint, in: Capsule())
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.08), in: Capsule())
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

    @State private var isPressed = false
    @State private var hasExpanded = false
    @State private var pulse = false
    @State private var splashTrigger = 0
    @State private var isTransitioning = false

    var body: some View {
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

                TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate

                    ZStack {
                        Capsule(style: .continuous)
                            .fill(AppTheme.ink)

                        Circle()
                            .fill(AppTheme.court.opacity(0.78))
                            .frame(width: 110, height: 110)
                            .blur(radius: 12)
                            .offset(x: -92 + CGFloat(sin(time * 0.9)) * 12, y: CGFloat(cos(time * 0.74)) * 5)

                        Circle()
                            .fill(AppTheme.clay.opacity(0.78))
                            .frame(width: 126, height: 126)
                            .blur(radius: 16)
                            .offset(x: 116 + CGFloat(cos(time * 0.82)) * 12, y: CGFloat(sin(time * 0.66)) * 6)

                        LiquidSplashLayer(trigger: splashTrigger)

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.16), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                Text(subtitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.12), in: Circle())
                        }
                        .padding(.horizontal, 20)
                        .opacity(hasExpanded ? 1 : 0)
                        .blur(radius: hasExpanded ? 0 : 8)
                    }
                    .frame(width: width, height: 68)
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.ink.opacity(0.26), radius: pulse && !isTransitioning ? 30 : 20, x: 0, y: pulse && !isTransitioning ? 18 : 14)
                    .scaleEffect(isPressed ? 0.985 : (pulse && !isTransitioning && hasExpanded ? 1.02 : 1))
                    .animation(.spring(response: 0.6, dampingFraction: 0.84), value: hasExpanded)
                    .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 68)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !hasExpanded else {
                return
            }

            withAnimation(.spring(response: 0.62, dampingFraction: 0.82).delay(0.16)) {
                hasExpanded = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
                pulse = true
            }
        }
    }
}

private struct LiquidSplashLayer: View {
    let trigger: Int
    @State private var animate = false

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
            Text("Виды спорта")
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
                SportIconView(
                    sport: sport,
                    color: isSelected ? OnboardingStepPalette.lime : .white.opacity(0.88),
                    size: height < 90 ? 30 : 34
                )
                    .frame(height: height < 90 ? 30 : 34)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(width: 24, height: 24)
                        .background(OnboardingStepPalette.lime, in: Circle())
                        .offset(x: 7, y: -4)
                }
            }
            .frame(maxWidth: .infinity)

            Text(title)
                .font(.system(size: height < 90 ? 12 : 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Button(action: onLevelTap) {
                HStack(spacing: 3) {
                    Text(isSelected ? levelTone : "Выбери уровень")
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
        sport == .tableTennis ? "Наст. теннис" : sport.title
    }

    private var levelTone: String {
        switch level {
        case 1 ... 2:
            return "Новичок"
        case 3 ... 4:
            return "База"
        case 5 ... 6:
            return "Уверенный"
        case 7 ... 8:
            return "Сильный"
        default:
            return "Турнирный"
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

            Text(isExpanded ? "Скрыть" : "Ещё виды")
                .font(.system(size: height < 90 ? 12 : 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 5) {
                Text(isExpanded ? "Свернуть" : "Открыть")
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
    let onAgeSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            OnboardingNameField(name: $name, isCompact: isCompact, focusedField: focusedField)
            OnboardingAgeField(age: $age, isCompact: isCompact, focusedField: focusedField, onSubmit: onAgeSubmit)
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
                    Text("Имя — так тебя увидят другие игроки")
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
    let onSubmit: () -> Void

    private var isValidAge: Bool {
        (18 ... 100).contains(age)
    }

    private var ageText: Binding<String> {
        Binding(
            get: {
                age > 0 ? "\(age)" : ""
            },
            set: { nextValue in
                let digits = String(nextValue.filter(\.isNumber).prefix(3))
                age = Int(digits) ?? 0
            }
        )
    }

    var body: some View {
        HStack(spacing: isCompact ? 10 : 14) {
            Image(systemName: "birthday.cake")
                .font(.system(size: isCompact ? 18 : 22, weight: .medium))
                .foregroundStyle(isValidAge ? .white.opacity(0.32) : Color.red.opacity(0.82))

            VStack(alignment: .leading, spacing: 2) {
                Text("Возраст")
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
                .foregroundStyle(isValidAge ? .white.opacity(0.44) : Color.red.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, isCompact ? 14 : 18)
        .frame(height: isCompact ? 52 : 58)
        .background(OnboardingStepPalette.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isValidAge ? Color.white.opacity(0.14) : Color.red.opacity(0.68), lineWidth: 1)
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
                Text("Показывать меня в поиске")
                    .font(.system(size: isCompact ? 14 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("Другие игроки смогут найти тебя и предложить игру")
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
                                    Text(levelTone(value))
                                        .font(.subheadline.weight(.black))
                                        .foregroundStyle(.white)
                                    Text(levelHint(value))
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
            return "Новичок"
        case 3 ... 4:
            return "База"
        case 5 ... 6:
            return "Уверенный"
        case 7 ... 8:
            return "Сильный"
        default:
            return "Турнирный"
        }
    }

    private func levelHint(_ value: Int) -> String {
        switch value {
        case 1 ... 2:
            return "только начинаю"
        case 3 ... 4:
            return "играю иногда"
        case 5 ... 6:
            return "стабильная база"
        case 7 ... 8:
            return "хороший темп"
        default:
            return "соревновательный"
        }
    }
}

private struct OnboardingAvailabilityEditorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
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
    let onConfirmDetectedDistrict: () -> Void
    let onDistricts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text("Где искать игроков?")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                } icon: {
                    Image(systemName: "mappin")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)

                Text("Сначала выбери город. Районы можно добавить сразу или позже.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }

            selectedCityPill

            HStack(spacing: 10) {
                OnboardingLocationChoiceCard(
                    title: "Рядом со мной",
                    subtitle: nearbySubtitle,
                    systemImage: "location.fill",
                    tint: OnboardingStepPalette.lime,
                    isSelected: selectedChoice == .nearby,
                    action: onNearby
                )

                OnboardingLocationChoiceCard(
                    title: "Выбрать город и районы",
                    subtitle: cityAndDistrictsSummary,
                    systemImage: "map",
                    tint: Color(red: 0.62, green: 0.34, blue: 1.0),
                    isSelected: selectedChoice == .districts,
                    action: onDistricts
                )
            }

            if selectedChoice == .nearby {
                locationDetectionStatus
            }
        }
    }

    @ViewBuilder
    private var selectedCityPill: some View {
        if selectedCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("Город не выбран", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.34))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.22), lineWidth: 1)
                )
        } else if !isOnboardingCityAvailable(selectedCity) {
            Label("\(selectedCity) скоро: добавляем клубы", systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.34))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
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
                .padding(.vertical, 9)
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
        if let districtTitle = selectedDistrictTitle {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(isDetectedDistrictConfirmed ? "Район подтвержден: \(districtTitle)" : "Ваш район — \(districtTitle)?")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: isDetectedDistrictConfirmed ? "checkmark.circle.fill" : "mappin.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                }

                HStack(spacing: 8) {
                    if !isDetectedDistrictConfirmed {
                        Button(action: onConfirmDetectedDistrict) {
                            Text("Да")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        }
                        .foregroundStyle(Color.black.opacity(0.88))
                        .background(OnboardingStepPalette.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .buttonStyle(.plain)
                    }

                    Button(action: onDistricts) {
                        Text(isDetectedDistrictConfirmed ? "Изменить город и районы" : "Выбрать город и районы")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(OnboardingStepPalette.lime)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingStepPalette.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(OnboardingStepPalette.lime.opacity(0.26), lineWidth: 1)
            )
        } else if isDetectingLocation {
            Label {
                Text("Определяем район по геолокации")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } icon: {
                ProgressView()
                    .tint(.white.opacity(0.72))
                    .controlSize(.mini)
            }
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if locationDetectionFailed {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Не удалось определить район по гео. Выбери районы вручную.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                }

                Button(action: onDistricts) {
                    Text("Выбрать город и районы")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .foregroundStyle(Color.black.opacity(0.88))
                .background(Color(red: 1.0, green: 0.78, blue: 0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .buttonStyle(.plain)
            }
            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.34))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 1.0, green: 0.78, blue: 0.34).opacity(0.22), lineWidth: 1)
            )
        }
    }

    private var selectedDistrictsSummary: String {
        selectedDistricts
            .prefix(2)
            .compactMap { localizedDistrictName($0) }
            .joined(separator: ", ")
            .appending(selectedDistricts.count > 2 ? " +\(selectedDistricts.count - 2)" : "")
    }

    private var cityAndDistrictsSummary: String {
        let city = selectedCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if city.isEmpty {
            return "Открыть выбор города"
        }

        if !isOnboardingCityAvailable(city) {
            return "\(city) · добавляем клубы"
        }

        guard !selectedDistricts.isEmpty else {
            return city
        }

        return "\(city) · \(selectedDistrictsSummary)"
    }

    private var selectedDistrictTitle: String? {
        guard let district = selectedDistricts.first else {
            return nil
        }

        return localizedDistrictName(district)
    }

    private var nearbySubtitle: String {
        guard selectedChoice == .nearby else {
            return "Определить город и район"
        }

        if let selectedDistrictTitle {
            return "\(selectedCity.isEmpty ? onboardingGeoDetectedCity : selectedCity) · \(selectedDistrictTitle)"
        }

        if locationDetectionFailed {
            return selectedCity.isEmpty ? "Не удалось определить" : selectedCity
        }

        return selectedCity.isEmpty ? "Определяем город" : "\(selectedCity) · определяем район"
    }
}

private struct OnboardingLocationChoiceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(tint)
                    }

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
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
    }
}

private struct OnboardingDetectedDistrictSheet: View {
    let districtID: String
    let userCoordinate: CLLocationCoordinate2D?
    let onConfirm: () -> Void
    let onChooseDistrict: () -> Void

    private var districtTitle: String {
        localizedDistrictName(districtID) ?? districtID
    }

    var body: some View {
        ZStack {
            OnboardingDarkBackground()

            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ваш район — \(districtTitle)?")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Мы выделили район и точку на карте. Если всё верно, будем ранжировать игроков и клубы рядом с ним выше.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OnboardingDetectedDistrictMap(districtID: districtID, userCoordinate: userCoordinate)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(OnboardingStepPalette.lime.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: OnboardingStepPalette.lime.opacity(0.12), radius: 18, x: 0, y: 12)

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Да")
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .foregroundStyle(Color.black.opacity(0.9))
                    .background(OnboardingStepPalette.lime, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .buttonStyle(.plain)

                    Button(action: onChooseDistrict) {
                        Text("Выбрать город и районы")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

private struct OnboardingDetectedDistrictMap: UIViewRepresentable {
    let districtID: String
    let userCoordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .excludingAll

        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(mapView: mapView, districtID: districtID, userCoordinate: userCoordinate)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var renderedDistrictID: String?
        private var renderedCoordinate: CLLocationCoordinate2D?

        func update(mapView: MKMapView, districtID: String, userCoordinate: CLLocationCoordinate2D?) {
            guard renderedDistrictID != districtID || renderedCoordinate?.latitude != userCoordinate?.latitude || renderedCoordinate?.longitude != userCoordinate?.longitude else {
                return
            }

            renderedDistrictID = districtID
            renderedCoordinate = userCoordinate
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

            guard let area = districtAreasByID[districtID] else {
                let fallbackCenter = userCoordinate ?? CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351)
                if let userCoordinate {
                    mapView.addAnnotation(OnboardingDetectedLocationAnnotation(coordinate: userCoordinate))
                }
                mapView.setRegion(MKCoordinateRegion(center: fallbackCenter, latitudinalMeters: 18_000, longitudinalMeters: 18_000), animated: false)
                return
            }

            let polygon = MKPolygon(coordinates: area.coordinates, count: area.coordinates.count)
            mapView.addOverlay(polygon)
            var targetRect = polygon.boundingMapRect

            if let userCoordinate {
                mapView.addAnnotation(OnboardingDetectedLocationAnnotation(coordinate: userCoordinate))
                let pointRect = MKMapRect(origin: MKMapPoint(userCoordinate), size: MKMapSize(width: 0, height: 0))
                targetRect = targetRect.union(pointRect)
            }

            mapView.setVisibleMapRect(targetRect, edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28), animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.fillColor = UIColor(red: 0.55, green: 0.95, blue: 0.30, alpha: 0.26)
            renderer.strokeColor = UIColor(red: 0.55, green: 0.95, blue: 0.30, alpha: 0.92)
            renderer.lineWidth = 3
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is OnboardingDetectedLocationAnnotation else {
                return nil
            }

            let reuseID = "OnboardingDetectedLocationAnnotation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            view.image = onboardingLocationMarkerImage()
            view.centerOffset = CGPoint(x: 0, y: -14)
            return view
        }
    }
}

private final class OnboardingDetectedLocationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

private func onboardingLocationMarkerImage() -> UIImage? {
    let size = CGSize(width: 34, height: 34)
    return UIGraphicsImageRenderer(size: size).image { _ in
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        UIColor.black.withAlphaComponent(0.58).setFill()
        UIBezierPath(ovalIn: outer).fill()
        UIColor(red: 0.55, green: 0.95, blue: 0.30, alpha: 1).setFill()
        UIBezierPath(ovalIn: outer.insetBy(dx: 5, dy: 5)).fill()
        UIColor.white.withAlphaComponent(0.92).setStroke()
        let stroke = UIBezierPath(ovalIn: outer.insetBy(dx: 1, dy: 1))
        stroke.lineWidth = 2
        stroke.stroke()
    }
}

private final class OnboardingLocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
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

        DispatchQueue.main.async {
            self.detectedCoordinate = location.coordinate
        }

        if let district = Self.districtSlug(from: location.coordinate) {
            applyDetectedDistrict(district)
            return
        }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else {
                return
            }

            guard let placemark = placemarks?.first,
                  let district = Self.districtSlug(from: placemark) else {
                DispatchQueue.main.async {
                    self.markDetectionFailed()
                }
                return
            }

            self.applyDetectedDistrict(district)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        markDetectionFailed()
    }

    private func applyDetectedDistrict(_ district: String) {
        DispatchQueue.main.async {
            self.isResolvingDistrict = false
            self.didFailToDetectDistrict = false
            self.detectedDistrict = district
        }
    }

    private func markDetectionFailed() {
        DispatchQueue.main.async {
            self.isResolvingDistrict = false
            self.didFailToDetectDistrict = true
        }
    }

    private static func districtSlug(from coordinate: CLLocationCoordinate2D) -> String? {
        for districtID in districtDetectionOrder {
            guard let area = districtAreasByID[districtID],
                  contains(coordinate, in: area.rawPolygon) else {
                continue
            }

            return area.id
        }

        return nil
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

    private static func districtSlug(from placemark: CLPlacemark) -> String? {
        let candidates = [
            placemark.subLocality,
            placemark.subAdministrativeArea,
            placemark.locality,
            placemark.name
        ] + (placemark.areasOfInterest ?? [])

        let normalizedCandidates = candidates
            .compactMap { $0?.lowercased() }
            .map { value in
                value
                    .replacingOccurrences(of: "ё", with: "е")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
            }

        for (slug, aliases) in districtAliases {
            if normalizedCandidates.contains(where: { candidate in
                aliases.contains(where: { candidate.contains($0) })
            }) {
                return slug
            }
        }

        return nil
    }

    private static let districtDetectionOrder = [
        "admiralteysky",
        "vasileostrovsky",
        "vyborgsky",
        "kalininsky",
        "kirovsky",
        "kolpinsky",
        "krasnogvardeysky",
        "krasnoselsky",
        "kronshtadtsky",
        "kurortny",
        "moskovsky",
        "nevsky",
        "petrogradsky",
        "petrodvortsovy",
        "primorsky",
        "pushkinsky",
        "frunzensky",
        "central"
    ]

    private static let districtAliases: [String: [String]] = [
        "admiralteysky": ["адмиралтей", "admiralte"],
        "vasileostrovsky": ["василеостров", "vasileostrov"],
        "vyborgsky": ["выборг", "vyborg"],
        "kalininsky": ["калинин", "kalinin"],
        "kirovsky": ["киров", "kirov"],
        "kolpinsky": ["колпин", "kolpin"],
        "krasnogvardeysky": ["красногвардей", "krasnogvard"],
        "krasnoselsky": ["красносель", "krasnosel"],
        "kronshtadtsky": ["кронштадт", "kronshtadt"],
        "kurortny": ["курорт", "kurort"],
        "moskovsky": ["москов", "moskov", "moscow"],
        "nevsky": ["невск", "nevsk"],
        "petrogradsky": ["петроград", "petrograd"],
        "petrodvortsovy": ["петродвор", "petrodvor"],
        "primorsky": ["примор", "primorsk"],
        "pushkinsky": ["пушкин", "pushkin"],
        "frunzensky": ["фрунз", "frunz"],
        "central": ["централь", "central", "tsentral"]
    ]
}

private struct OnboardingDistrictPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCity: String
    @Binding var selectedDistricts: [String]
    let onDone: () -> Void

    var body: some View {
        ZStack {
            OnboardingDarkBackground()

            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Город и районы")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Сейчас доступен Санкт-Петербург. Москву и Казань откроем после добавления клубов.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Город")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .textCase(.uppercase)
                        .tracking(1.4)

                    HStack(spacing: 8) {
                        ForEach(onboardingCityOptions, id: \.self) { city in
                            cityButton(city)
                        }
                    }
                }

                if selectedCity == onboardingGeoDetectedCity {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Районы")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                            .textCase(.uppercase)
                            .tracking(1.4)

                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(onboardingDistrictOptions, id: \.self) { district in
                                    districtButton(district)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else if !selectedCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Этот город пока закрыт: добавляем клубы и районы.", systemImage: "info.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(spacing: 12) {
                    Button {
                        selectedCity = ""
                        selectedDistricts.removeAll()
                        onDone()
                    } label: {
                        Text("Сбросить")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .buttonStyle(.plain)

                    Button(action: onDone) {
                        Text("Готово")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(canSubmit ? OnboardingStepPalette.lime : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .foregroundStyle(canSubmit ? Color.black.opacity(0.88) : .white.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var canSubmit: Bool {
        isOnboardingCityAvailable(selectedCity)
    }

    private func cityButton(_ city: String) -> some View {
        let isSelected = selectedCity == city
        let isAvailable = isOnboardingCityAvailable(city)

        return Button {
            guard isAvailable else {
                AppHaptics.impact(.light)
                return
            }
            selectedCity = city
            if city != onboardingGeoDetectedCity {
                selectedDistricts.removeAll()
            }
            AppHaptics.selection()
        } label: {
            VStack(spacing: 2) {
                Text(city)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !isAvailable {
                    Text("Добавляем клубы")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
            }
            .foregroundStyle(cityForegroundColor(isSelected: isSelected, isAvailable: isAvailable))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(cityBackgroundColor(isSelected: isSelected, isAvailable: isAvailable), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cityBorderColor(isSelected: isSelected, isAvailable: isAvailable), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func cityForegroundColor(isSelected: Bool, isAvailable: Bool) -> Color {
        if !isAvailable {
            return .white.opacity(0.38)
        }
        return isSelected ? Color.black.opacity(0.86) : .white
    }

    private func cityBackgroundColor(isSelected: Bool, isAvailable: Bool) -> Color {
        if !isAvailable {
            return Color.white.opacity(0.045)
        }
        return isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.08)
    }

    private func cityBorderColor(isSelected: Bool, isAvailable: Bool) -> Color {
        if !isAvailable {
            return Color.white.opacity(0.08)
        }
        return isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.10)
    }

    private func districtButton(_ district: String) -> some View {
        let isSelected = selectedDistricts.contains(district)

        return Button {
            if isSelected {
                selectedDistricts.removeAll { $0 == district }
            } else {
                selectedDistricts.append(district)
            }
            AppHaptics.selection()
        } label: {
            HStack(spacing: 8) {
                Text(localizedDistrictName(district) ?? district)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                }
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.86) : .white)
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? OnboardingStepPalette.lime : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var onboardingDistrictOptions: [String] {
        [
            "central",
            "admiralteysky",
            "petrogradsky",
            "vasileostrovsky",
            "primorsky",
            "vyborgsky",
            "kalininsky",
            "moskovsky",
            "nevsky",
            "frunzensky",
            "kirovsky",
            "krasnogvardeysky",
            "krasnoselsky",
            "pushkinsky",
            "kurortny",
            "kolpinsky",
            "kronshtadtsky",
            "petrodvortsovy"
        ]
    }
}

private struct OTPCodeField: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    private var digits: [String] {
        let values = Array(code.prefix(6)).map(String.init)
        return values + Array(repeating: "", count: max(0, 6 - values.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Код подтверждения")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .textCase(.uppercase)
                .tracking(1.4)

            ZStack {
                HStack(spacing: 10) {
                    ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.creamLight)
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(index == min(code.count, 5) && isFocused ? AppTheme.court : AppTheme.court.opacity(0.16), lineWidth: index == min(code.count, 5) && isFocused ? 2 : 1)

                            Text(digit.isEmpty ? "•" : digit)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(digit.isEmpty ? AppTheme.mutedInk.opacity(0.34) : AppTheme.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                    }
                }

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

                    Text(sport.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? .white : AppTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }

                if isSelected {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Уровень")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Text(levelTone)
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
            return "Новичок"
        case 3 ... 4:
            return "База"
        case 5 ... 6:
            return "Уверенный"
        case 7 ... 8:
            return "Сильный"
        default:
            return "Турнирный"
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Одна шкала недели. Выбери день и затем отметь удобные окна времени.")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)

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
                            Text(day.shortTitle)
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
                        .padding(.vertical, 10)
                        .background(activeDay == day ? AppTheme.ink : AppTheme.cream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(activeDay.title)
                        .font(.headline)
                    Spacer()
                    if !(availabilityByDay[activeDay.rawValue] ?? []).isEmpty {
                        Button("Очистить") {
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

            HStack(spacing: 8) {
                presetButton("Будни утром") {
                    applyPreset(days: [.monday, .tuesday, .wednesday, .thursday, .friday], ranges: [.morning])
                }
                presetButton("Будни вечером") {
                    applyPreset(days: [.monday, .tuesday, .wednesday, .thursday, .friday], ranges: [.evening])
                }
                presetButton("Выходные") {
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
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.cream, in: Capsule())
            .foregroundStyle(AppTheme.ink)
    }
}

private struct AvailabilityWindowCard: View {
    let range: TimeRange
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(iconBackground, in: Circle())
                Text(range.title)
                    .font(.caption.weight(.bold))
                if isSelected {
                    Text("Выбрано")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(isSelected ? activeTextColor : inactiveTextColor)
            .shadow(color: shadowColor, radius: isSelected ? 16 : 8, x: 0, y: isSelected ? 12 : 6)
            .scaleEffect(isSelected ? 1.02 : 1)
        }
        .buttonStyle(.plain)
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
