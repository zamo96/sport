import SwiftUI
import PhotosUI
import CoreImage.CIFilterBuiltins
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import AVKit

private enum ProfileScreenMode: String, CaseIterable, Identifiable {
    case editing = "Редактирование"
    case preview = "Как видят другие"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .editing: return "pencil"
        case .preview: return "eye"
        }
    }
}

private struct ProfileCompletionStatus {
    let percent: Int
    let missingSteps: [String]
}

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager

    private let profileTopAnchor = "profile-top"

    @State private var draft: UserProfile?
    @State private var guestDraft: GuestOnboardingDraft = .default
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedProfilePhotoItems: [PhotosPickerItem] = []
    @State private var selectedProfileVideoItems: [PhotosPickerItem] = []
    @State private var isUploadingAvatar = false
    @State private var isUploadingProfileMedia = false
    @State private var profileMediaMutationCount = 0
    @State private var profileMediaMutationTail: Task<Void, Never>?
    @State private var isPreparingProfileVideo = false
    @State private var selectedProfileMediaPreview: PlayerMediaItem?
    @State private var pendingProfileVideoRemoval: PlayerMediaItem?
    @State private var pendingVideoTrimQueue: [PhotosPickerItem] = []
    @State private var pendingVideoTrimDraft: ProfileVideoTrimDraft?
    @State private var saveToastMessage: String?
    @State private var gameFeedRequests: [MatchGameRequest] = []
    @State private var isGameFeedLoading = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isEditorPresented = false
    @State private var profileScreenMode: ProfileScreenMode = .editing
    @AppStorage("profile.visibilityMode") private var visibilityModeRaw = ProfileVisibilityMode.publicProfile.rawValue

    private var visibilityMode: ProfileVisibilityMode {
        ProfileVisibilityMode(rawValue: visibilityModeRaw) ?? .publicProfile
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if appModel.isAuthenticated {
                            authenticatedContent
                        } else {
                            guestContent
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 116)
                    .id(profileTopAnchor)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: profileScreenMode) { _ in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        scrollProxy.scrollTo(profileTopAnchor, anchor: .top)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let saveToastMessage {
                ProfileSaveSuccessToast(message: saveToastMessage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if isPreparingProfileVideo {
                ProfileMediaProgressOverlay(
                    title: "Видео загружается",
                    subtitle: "Открываем ролик и готовим редактор обрезки."
                )
                .transition(.opacity)
            }
        }
        .task {
            if draft == nil {
                draft = appModel.currentUser
            }
            guestDraft = appModel.guestDraft
            await notificationManager.refreshAuthorizationStatus()
            if appModel.isAuthenticated {
                await loadProfileGameFeed()
            }
        }
        .onChange(of: selectedAvatarItem) { newValue in
            guard let newValue else { return }
            Task { await uploadAvatar(from: newValue) }
        }
        .onChange(of: selectedProfilePhotoItems) { newValue in
            guard !newValue.isEmpty else { return }
            let capturedItems = newValue
            selectedProfilePhotoItems = []
            enqueueProfileMediaMutation {
                await uploadProfileMedia(from: capturedItems, preferredKind: .photo)
            }
        }
        .onChange(of: selectedProfileVideoItems) { newValue in
            guard !newValue.isEmpty else { return }
            pendingVideoTrimQueue.append(contentsOf: newValue)
            selectedProfileVideoItems = []
            Task { await prepareNextVideoTrimDraft() }
        }
        .sheet(item: $selectedProfileMediaPreview) { item in
            PlayerMediaPreviewSheet(item: item)
        }
        .sheet(item: $pendingVideoTrimDraft) { trimDraft in
            ProfileVideoTrimEditorSheet(
                draft: trimDraft,
                isUploading: isUploadingProfileMedia,
                onCancel: {
                    if let pendingVideoTrimDraft {
                        try? FileManager.default.removeItem(at: pendingVideoTrimDraft.sourceURL)
                    }
                    pendingVideoTrimDraft = nil
                    pendingVideoTrimQueue.removeAll()
                },
                onConfirm: { startTime in
                    Task { await uploadTrimmedProfileVideo(trimDraft, startTime: startTime) }
                }
            )
        }
        .sheet(isPresented: $isEditorPresented) {
            if let draftBinding {
                NavigationStack {
                    profileEditor(for: draftBinding)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog(
            "Удалить профиль?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Удалить профиль", role: .destructive) {
                Task { await deleteProfile() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие необратимо. Аккаунт, поиски, мэтчи и история будут удалены.")
        }
        .confirmationDialog(
            "Удалить видео из карточки?",
            isPresented: Binding(
                get: { pendingProfileVideoRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingProfileVideoRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить видео", role: .destructive) {
                if let item = pendingProfileVideoRemoval {
                    removeProfileMediaPersistently(item)
                }
                pendingProfileVideoRemoval = nil
            }
            Button("Отмена", role: .cancel) {
                pendingProfileVideoRemoval = nil
            }
        } message: {
            Text("Видео исчезнет из карточки профиля. Остальные фото и данные профиля останутся.")
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if let draftBinding {
            let profile = draftBinding.wrappedValue
            let completion = profileCompletionStatus(for: profile)

            profileHeader
            ProfileScreenModePicker(selection: $profileScreenMode)

            if profileScreenMode == .editing {
                ProfileSelectionMediaCard(
                    profile: profile,
                    isUploadingAvatar: isUploadingAvatar,
                    isUploading: profileMediaMutationCount > 0 || isUploadingProfileMedia,
                    selectedAvatarItem: $selectedAvatarItem,
                    selectedPhotoItems: $selectedProfilePhotoItems,
                    selectedVideoItems: $selectedProfileVideoItems,
                    onEdit: { isEditorPresented = true },
                    onPreview: { selectedProfileMediaPreview = $0 },
                    onRemove: requestProfileMediaRemoval
                )

                ProfileCompletenessCard(
                    percent: completion.percent,
                    missingSteps: completion.missingSteps,
                    hasVideoBonus: !profile.profileVideoUrls.isEmpty
                )

                ProfileGameFeedSection(
                    requests: profileGameFeedRequests,
                    currentUserId: appModel.currentUser?.id,
                    isLoading: isGameFeedLoading
                )

                ProfileMenuGroup {
                    NavigationLink {
                        sportsProfileEditor(for: draftBinding)
                    } label: {
                        ProfileMenuRow(
                            icon: "tennis.racket",
                            tint: AppTheme.court,
                            title: "Спортивный профиль",
                            subtitle: sportsSummary(for: profile)
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        availabilityProfileEditor(for: draftBinding)
                    } label: {
                        ProfileMenuRow(
                            icon: "clock",
                            tint: .green,
                            title: "Доступность",
                            subtitle: availabilityHeadline(for: profile.availabilityByDay)
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        locationProfileEditor(for: draftBinding)
                    } label: {
                        ProfileMenuRow(
                            icon: "mappin.and.ellipse",
                            tint: .green,
                            title: "Где удобно играть",
                            subtitle: playLocationSummary(for: profile)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            profileScreenMode = .preview
                        }
                    } label: {
                        ProfileMenuRow(
                            icon: "eye.fill",
                            tint: .yellow,
                            title: "Посмотреть карточку",
                            subtitle: activitySummary(for: profile)
                        )
                    }
                    .buttonStyle(.plain)
                }

                ProfileMenuGroup {
                    NavigationLink {
                        notificationProfileEditor(for: draftBinding)
                    } label: {
                        ProfileMenuRow(
                            icon: "bell",
                            tint: .white.opacity(0.82),
                            title: "Уведомления",
                            subtitle: notificationsSummary(for: profile)
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        VisibilitySettingsView(selectionRaw: $visibilityModeRaw)
                    } label: {
                        ProfileMenuRow(
                            icon: "lock",
                            tint: .white.opacity(0.82),
                            title: "Приватность",
                            subtitle: visibilityMode.title
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ProfileAccountScreen(
                            email: appModel.currentUser?.email,
                            isVerified: appModel.currentUser?.isVerified == true,
                            onLogout: { appModel.logout() },
                            onDelete: { isDeleteConfirmationPresented = true }
                        )
                    } label: {
                        ProfileMenuRow(
                            icon: "person",
                            tint: .white.opacity(0.82),
                            title: "Аккаунт",
                            subtitle: profile.email ?? "Почта, телефон, безопасность"
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProfileSwipeCardPreview(profile: profile)
            }
        } else {
            ProfileDarkPanel {
                ProgressView("Загружаем профиль")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .center) {
            Text("Профиль")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            if let profile = draft ?? appModel.currentUser {
                NavigationLink {
                    QRProfileView(profile: profile, visibilityMode: visibilityMode)
                } label: {
                    ProfileHeaderButton(systemImage: "qrcode.viewfinder", tint: AppTheme.court)
                }
                .buttonStyle(.plain)
            }

        }
    }

    private var guestContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Профиль")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }

            ProfileDarkPanel {
                HStack(spacing: 14) {
                    RemoteAvatarView(name: guestDraft.displayName, path: nil, size: 74)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(guestDraft.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Гостевой режим")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                        ProfileCapsule(text: "Черновик профиля", tint: AppTheme.court)
                    }
                    Spacer()
                }
            }

            SectionCard(title: "Черновик профиля", subtitle: "Можно подготовить карточку до подтверждения email.") {
                guestBasicsSection
                guestPreferencesSection
            }

            SectionCard(title: "Виды спорта", subtitle: "Выбери спорт и уровень.") {
                AppSportSelectionGrid(
                    title: "Спортивный профиль",
                    sports: Sport.allCases,
                    selectedSports: $guestDraft.preferredSports,
                    levels: $guestDraft.sportLevels
                )
            }

            SectionCard(title: "Доступность", subtitle: "Эти слоты сохранятся в черновике.") {
                AppAvailabilityWeekEditor(availabilityByDay: $guestDraft.availabilityByDay)
                availabilitySummary(for: guestDraft.availabilityByDay)
            }

            HStack(spacing: 12) {
                Button("Сохранить") {
                    persistGuestDraft()
                    showSaveToast("Черновик сохранён")
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .white))

                Button("К email") {
                    persistGuestDraft()
                    appModel.presentAuth(step: .email)
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.court))
                .disabled(!guestDraft.hasProfileBasics)
            }
        }
        .onChange(of: guestDraft) { newValue in
            appModel.updateGuestDraft(normalizedGuestDraft(newValue))
        }
    }

    private func sportsProfileEditor(for profile: Binding<UserProfile>) -> some View {
        ProfileEditorScreen(
            title: "Спортивный профиль",
            subtitle: "Настрой виды спорта и уровень.",
            systemImage: "tennis.racket",
            tint: AppTheme.court,
            onSave: { await save() }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: "Спортов", value: "\(profile.wrappedValue.preferredSports.count)", icon: "figure.tennis"),
                        .init(title: "Поиск", value: profile.wrappedValue.isLookingForGame ? "Активен" : "Скрыт", icon: "eye")
                    ])

                    ProfileEmbeddedLightCard(title: "Виды спорта", subtitle: "Выбери всё, во что готов играть, и выставь уровень.") {
                        AppSportSelectionGrid(
                            title: "Спортивный профиль",
                            sports: Sport.allCases,
                            selectedSports: profile.preferredSports,
                            levels: profile.sportLevels
                        )
                    }

                    ProfileEmbeddedLightCard(title: "Видимость", subtitle: "Можно временно скрыться из активной подборки игроков.") {
                        ToggleCard(title: "Ищу игру сейчас", subtitle: "Показывать тебя в активной подборке игроков.", isOn: profile.isLookingForGame)
                    }
                }
            }
        }
    }

    private func availabilityProfileEditor(for profile: Binding<UserProfile>) -> some View {
        ProfileEditorScreen(
            title: "Доступность",
            subtitle: "Отметь дни и окна времени, когда реально удобно играть.",
            systemImage: "clock.badge.checkmark",
            tint: Color.green,
            onSave: { await save() }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: availabilityMetricItems(for: profile.wrappedValue.availabilityByDay))

                    ProfileEmbeddedLightCard(title: "Неделя", subtitle: "Можно быстро выбрать пресеты или собрать расписание вручную.") {
                        AppAvailabilityWeekEditor(availabilityByDay: profile.availabilityByDay)
                    }

                    ProfileAvailabilityDarkSummary(availabilityByDay: profile.wrappedValue.availabilityByDay)
                }
            }
        }
    }

    private func locationProfileEditor(for profile: Binding<UserProfile>) -> some View {
        ProfileEditorScreen(
            title: "Где удобно играть",
            subtitle: "Районы используются в подборе игроков и центров.",
            systemImage: "mappin.and.ellipse",
            tint: Color.green,
            onSave: { await save() }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: "Районов", value: "\(activeProfileDistricts(for: profile.wrappedValue).count)", icon: "map"),
                        .init(title: "Радиус", value: "\(profile.wrappedValue.searchRadiusKm) км", icon: "scope"),
                        .init(title: "Город", value: profile.wrappedValue.city ?? "СПб", icon: "building.2")
                    ])

                    ProfileEmbeddedLightCard(title: "Город", subtitle: "Клубы и игроки подбираются внутри выбранного города.") {
                        Picker("Город", selection: supportedCityBinding(for: profile)) {
                            ForEach(SupportedCity.selectableCases) { city in
                                Text(city.rawValue).tag(city)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppTheme.court)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if supportedCityBinding(for: profile).wrappedValue.supportsDistrictSelection {
                        ProfileDistrictPickerCard(
                            selectedDistricts: profile.preferredDistricts,
                            primaryDistrict: profile.district,
                            districts: profileDistrictOptions(
                                for: supportedCityBinding(for: profile).wrappedValue
                            )
                        )
                    } else {
                        ProfileEmbeddedLightCard(
                            title: "Районы",
                            subtitle: "Для \(supportedCityBinding(for: profile).wrappedValue.rawValue) пока используем выбранный радиус и расстояние до места."
                        ) {
                            Label("Районы города добавим постепенно", systemImage: "map")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink.opacity(0.62))
                        }
                    }

                    ProfileEmbeddedLightCard(title: "Радиус поиска", subtitle: "Если районов нет, расстояние станет главным сигналом.") {
                        FieldShell(title: "\(profile.wrappedValue.searchRadiusKm) км") {
                            Slider(
                                value: Binding(
                                    get: { Double(profile.wrappedValue.searchRadiusKm) },
                                    set: { profile.wrappedValue.searchRadiusKm = Int($0.rounded()) }
                                ),
                                in: 1 ... 100,
                                step: 1
                            )
                            .tint(AppTheme.court)
                        }
                    }
                }
            }
        }
    }

    private func notificationProfileEditor(for profile: Binding<UserProfile>) -> some View {
        ProfileEditorScreen(
            title: "Уведомления",
            subtitle: "Оставляем только события, где тебе нужно увидеть действие или ответ.",
            systemImage: "bell.badge",
            tint: Color.yellow,
            onSave: { await save(successMessage: "Настройки уведомлений сохранены") }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: "Push", value: notificationManager.authorizationStatus.title, icon: "bell.badge"),
                        .init(title: "Событий", value: "\(enabledNotificationCount(for: profile.wrappedValue))/3", icon: "checklist")
                    ])

                    ProfileEmbeddedLightCard(title: "Системный доступ", subtitle: "Без разрешения iOS уведомления не появятся на заблокированном экране.") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                AppInlineChip(
                                    text: notificationManager.authorizationStatus.title,
                                    tint: notificationStatusTint,
                                    foreground: notificationStatusForeground
                                )

                                Text(notificationAuthorizationHint)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            notificationAuthorizationButton
                                .frame(maxWidth: .infinity)
                        }
                    }

                    ProfileEmbeddedLightCard(title: "События", subtitle: "Здесь только реальные уведомления, а не настройки профиля.") {
                        ToggleCard(title: "Новые мэтчи", subtitle: "Сообщать, когда появляется взаимный интерес.", isOn: profile.notificationMatches)
                        ToggleCard(title: "Сообщения", subtitle: "Показывать новые сообщения и ответы в чате.", isOn: profile.notificationMessages)
                        ToggleCard(title: "Игры и предложения", subtitle: "Отклики, подтверждения, отмены и изменения игр.", isOn: profile.notificationGames)
                    }

                    ProfileEmbeddedLightCard(title: "Звук", subtitle: "Отдельно регулирует звуковой сигнал внутри приложения.") {
                        ToggleCard(title: "Звуковые сигналы", subtitle: "Воспроизводить звук системного уведомления.", isOn: profile.notificationSound)
                    }
                }
            }
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
    }

    private func profileEditor(for profile: Binding<UserProfile>, initialTitle: String = "Редактировать профиль") -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(initialTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 12)

                    SectionCard(title: "Карточка игрока", subtitle: "Основные данные, которые видят другие игроки.") {
                        basicsSection(for: profile)
                        profileVisibilitySection(for: profile)
                    }

                    SectionCard(title: "Виды спорта", subtitle: "Выбери спорт и сразу настрой уровень.") {
                        AppSportSelectionGrid(
                            title: "Спортивный профиль",
                            sports: Sport.allCases,
                            selectedSports: profile.preferredSports,
                            levels: profile.sportLevels
                        )
                    }

                    SectionCard(title: "Доступность", subtitle: "Дни и окна времени, когда удобно играть.") {
                        AppAvailabilityWeekEditor(availabilityByDay: profile.availabilityByDay)
                        availabilitySummary(for: profile.wrappedValue.availabilityByDay)
                    }

                    HStack(spacing: 12) {
                        Button("Сохранить профиль") {
                            Task {
                                if await save() {
                                    isEditorPresented = false
                                }
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.court))

                        Button("Выйти") {
                            appModel.logout()
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: .red))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = .hidden
            }
        }
        .onDisappear {
            appModel.bottomBarDisplayMode = .expanded
        }
        .profileBackSwipe { isEditorPresented = false }
    }

    @ViewBuilder
    private func basicsSection(for profile: Binding<UserProfile>) -> some View {
        FieldShell(title: "Имя") {
            TextField("Анна", text: profile.name.orEmpty)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }

        FieldShell(title: "Возраст") {
            Stepper(value: Binding(
                get: { profile.age.wrappedValue ?? 25 },
                set: { profile.age.wrappedValue = $0 }
            ), in: 18 ... 100) {
                Text("\(profile.age.wrappedValue ?? 25)")
                    .font(.headline)
            }
        }

        FieldShell(title: "Пол") {
            Picker("Пол", selection: profile.gender) {
                Text("Не указывать").tag(Optional<Gender>.none)
                ForEach(Gender.allCases) { gender in
                    Text(gender.title).tag(Optional(gender))
                }
            }
            .pickerStyle(.menu)
        }

        FieldShell(title: "Город") {
            Picker("Город", selection: supportedCityBinding(for: profile)) {
                ForEach(SupportedCity.selectableCases) { city in
                    Text(city.rawValue).tag(city)
                }
            }
            .pickerStyle(.menu)
        }

        if supportedCityBinding(for: profile).wrappedValue.supportsDistrictSelection {
            FieldShell(title: "Район") {
                TextField("Например: Приморский", text: profile.district.orEmpty)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }

        FieldShell(title: "О себе", caption: "Коротко опиши себя или с кем хочешь играть.") {
            TextField(
                "Люблю интенсивные розыгрыши и вечерние тренировки.",
                text: profile.bio.orEmpty,
                axis: .vertical
            )
            .lineLimit(3 ... 6)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private func profileVisibilitySection(for profile: Binding<UserProfile>) -> some View {
        ToggleCard(title: "Ищу игру сейчас", subtitle: "Показывать тебя в активной подборке игроков.", isOn: profile.isLookingForGame)
    }

    @ViewBuilder
    private var notificationAuthorizationButton: some View {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            Button("Разрешить") {
                Task { await notificationManager.requestAuthorization() }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
        case .denied:
            Button("Настройки") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(settingsURL)
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
        default:
            Button("Проверить") {
                Task { await notificationManager.refreshAuthorizationStatus() }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
        }
    }

    private var notificationAuthorizationHint: String {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            return "Разреши push-уведомления, чтобы получать сообщения и действия по играм вне приложения."
        case .denied:
            return "Уведомления отключены в настройках iOS. Их нужно включить вручную."
        case .authorized, .provisional, .ephemeral:
            return "Системный доступ включён. Типы событий можно настроить ниже."
        @unknown default:
            return "Не удалось точно определить статус доступа. Проверь настройки iOS."
        }
    }

    private var notificationStatusTint: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return AppTheme.mint
        case .denied:
            return Color.red.opacity(0.14)
        default:
            return AppTheme.cream
        }
    }

    private var notificationStatusForeground: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return AppTheme.court
        case .denied:
            return .red
        default:
            return AppTheme.ink
        }
    }

    private var guestBasicsSection: some View {
        Group {
            FieldShell(title: "Имя") {
                TextField("Анна", text: $guestDraft.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            FieldShell(title: "Возраст") {
                Stepper(value: $guestDraft.age, in: 18 ... 100) {
                    Text("\(guestDraft.age)")
                        .font(.headline)
                }
            }

            FieldShell(title: "Пол") {
                Picker("Пол", selection: $guestDraft.gender) {
                    Text("Не указывать").tag(Optional<Gender>.none)
                    ForEach(Gender.allCases) { gender in
                        Text(gender.title).tag(Optional(gender))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var guestPreferencesSection: some View {
        Group {
            FieldShell(title: "Радиус поиска", caption: "\(guestDraft.searchRadiusKm) км") {
                Slider(
                    value: Binding(
                        get: { Double(guestDraft.searchRadiusKm) },
                        set: { guestDraft.searchRadiusKm = Int($0.rounded()) }
                    ),
                    in: 1 ... 100,
                    step: 1
                )
                .tint(AppTheme.court)
            }

            ToggleCard(title: "Ищу игру сейчас", subtitle: "Показывать черновик в гостевой подборке.", isOn: $guestDraft.isLookingForGame)
        }
    }

    @ViewBuilder
    private func availabilitySummary(for availabilityByDay: [String: [String]]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Итог")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.8)
                .foregroundStyle(AppTheme.court)

            if availabilityByDay.isEmpty {
                AppInlineChip(text: "Пока не указано", tint: AppTheme.cream, foreground: AppTheme.ink)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(DayOfWeek.allCases) { day in
                        if let ranges = availabilityByDay[day.rawValue], !ranges.isEmpty {
                            AppInlineChip(
                                text: "\(day.title) · \(ranges.compactMap { TimeRange(rawValue: $0)?.title }.joined(separator: ", "))",
                                tint: .white,
                                foreground: AppTheme.ink
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.mint.opacity(0.58), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var draftBinding: Binding<UserProfile>? {
        guard draft != nil || appModel.currentUser != nil else { return nil }

        return Binding(
            get: { draft ?? appModel.currentUser ?? UserProfile(id: "temp") },
            set: { draft = $0 }
        )
    }

    private var profileGameFeedRequests: [MatchGameRequest] {
        Array(
            gameFeedRequests
                .filter { request in
                    guard request.hasEnded() else { return false }
                    if let report = request.report {
                        return report.visibility == "profile"
                    }
                    return request.outcome == "played"
                }
                .sorted { ($0.proposedDate ?? .distantPast) > ($1.proposedDate ?? .distantPast) }
                .prefix(6)
        )
    }

    private func loadProfileGameFeed() async {
        guard !isGameFeedLoading else { return }
        isGameFeedLoading = true
        defer { isGameFeedLoading = false }

        do {
            gameFeedRequests = try await appModel.repository.fetchMyGameRequests()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            gameFeedRequests = []
        }
    }

    private func persistGuestDraft() {
        let normalized = normalizedGuestDraft(guestDraft)
        guestDraft = normalized
        appModel.updateGuestDraft(normalized)
    }

    private func normalizedGuestDraft(_ value: GuestOnboardingDraft) -> GuestOnboardingDraft {
        var next = value
        next.availableDays = DayOfWeek.allCases.map(\.rawValue).filter { !(next.availabilityByDay[$0] ?? []).isEmpty }
        next.availableTimeRanges = Array(Set(next.availabilityByDay.values.flatMap { $0 })).sorted { lhs, rhs in
            (TimeRange.allCases.firstIndex { $0.rawValue == lhs } ?? 0) < (TimeRange.allCases.firstIndex { $0.rawValue == rhs } ?? 0)
        }
        return next
    }

    @discardableResult
    private func save(successMessage: String = "Профиль сохранён") async -> Bool {
        guard let draft else { return false }

        let didSave = await appModel.saveProfile(draft)
        guard didSave else { return false }

        self.draft = appModel.currentUser
        AppHaptics.notification(.success)
        showSaveToast(successMessage)
        return true
    }

    private func deleteProfile() async {
        do {
            try await appModel.repository.deleteAccount()
            appModel.logout()
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func uploadAvatar(from item: PhotosPickerItem) async {
        guard !isUploadingAvatar else { return }

        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            appModel.errorMessage = "Не удалось прочитать выбранное фото"
            selectedAvatarItem = nil
            return
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.88) else {
            appModel.errorMessage = "Не удалось подготовить фото к загрузке"
            selectedAvatarItem = nil
            return
        }

        isUploadingAvatar = true
        defer {
            isUploadingAvatar = false
            selectedAvatarItem = nil
        }

        do {
            let avatarUrl = try await appModel.repository.uploadAvatar(data: jpegData, fileName: "avatar.jpg", mimeType: "image/jpeg")

            if var updatedDraft = draft {
                updatedDraft.avatarUrl = avatarUrl
                draft = updatedDraft
                appModel.currentUser = updatedDraft
            } else if var currentUser = appModel.currentUser {
                currentUser.avatarUrl = avatarUrl
                draft = currentUser
                appModel.currentUser = currentUser
            }

            AppHaptics.notification(.success)
            showSaveToast("Фото обновлено")
        } catch {
            appModel.present(error: error)
        }
    }

    private func uploadProfileMedia(from items: [PhotosPickerItem], preferredKind: PlayerMediaKind) async {
        isUploadingProfileMedia = true
        defer {
            isUploadingProfileMedia = false
        }

        do {
            for (index, item) in items.enumerated() {
                let payload = try await profileMediaPayload(from: item, preferredKind: preferredKind, index: index)
                let result = try await appModel.repository.uploadProfileMedia(
                    data: payload.data,
                    fileName: payload.fileName,
                    mimeType: payload.mimeType
                )

                applyProfileMediaUpload(result)
            }

            AppHaptics.notification(.success)
            showSaveToast(preferredKind == .video ? "Видео добавлено" : "Фото добавлено")
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func prepareNextVideoTrimDraft() async {
        guard pendingVideoTrimDraft == nil, !pendingVideoTrimQueue.isEmpty else { return }

        let item = pendingVideoTrimQueue.removeFirst()
        isPreparingProfileVideo = true
        defer {
            isPreparingProfileVideo = false
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw APIError.invalidPayload("Не удалось прочитать выбранное видео")
            }

            let contentType = item.supportedContentTypes.first
            let fileExtension = preferredProfileMediaExtension(for: contentType, preferredKind: .video)
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("profile-video-source-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)

            try data.write(to: sourceURL, options: [.atomic])

            let asset = AVURLAsset(url: sourceURL)
            let duration = CMTimeGetSeconds(asset.duration)

            guard duration.isFinite, duration > 0 else {
                throw APIError.invalidPayload("Не удалось определить длительность видео")
            }

            pendingVideoTrimDraft = ProfileVideoTrimDraft(
                sourceURL: sourceURL,
                duration: duration,
                fileName: "profile-video-\(UUID().uuidString)"
            )
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
            await prepareNextVideoTrimDraft()
        }
    }

    private func uploadTrimmedProfileVideo(_ trimDraft: ProfileVideoTrimDraft, startTime: TimeInterval) async {
        enqueueProfileMediaMutation {
            await performTrimmedProfileVideoUpload(trimDraft, startTime: startTime)
        }
    }

    private func performTrimmedProfileVideoUpload(_ trimDraft: ProfileVideoTrimDraft, startTime: TimeInterval) async {
        isUploadingProfileMedia = true
        defer {
            isUploadingProfileMedia = false
        }

        do {
            let payload = try await trimmedVideoPayload(from: trimDraft, startTime: startTime)
            let result = try await appModel.repository.uploadProfileMedia(
                data: payload.data,
                fileName: "\(trimDraft.fileName).\(payload.fileExtension)",
                mimeType: payload.mimeType
            )

            applyProfileMediaUpload(result)
            try? FileManager.default.removeItem(at: trimDraft.sourceURL)
            pendingVideoTrimDraft = nil

            AppHaptics.notification(.success)
            showSaveToast("Видео добавлено")
            await prepareNextVideoTrimDraft()
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func trimmedVideoPayload(
        from trimDraft: ProfileVideoTrimDraft,
        startTime: TimeInterval
    ) async throws -> ProfileTrimmedVideoPayload {
        let asset = AVURLAsset(url: trimDraft.sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw APIError.invalidPayload("Не удалось подготовить видео к обрезке")
        }

        let outputType: AVFileType = exportSession.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let outputExtension = outputType == .mp4 ? "mp4" : "mov"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-video-trimmed-\(UUID().uuidString)")
            .appendingPathExtension(outputExtension)

        let safeStart = min(max(startTime, 0), max(trimDraft.duration - 0.2, 0))
        let clipDuration = min(10, max(trimDraft.duration - safeStart, 0.2))
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputType
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: safeStart, preferredTimescale: 600),
            duration: CMTime(seconds: clipDuration, preferredTimescale: 600)
        )

        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    do {
                        let data = try Data(contentsOf: outputURL)
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(returning: ProfileTrimmedVideoPayload(
                            data: data,
                            fileExtension: outputExtension,
                            mimeType: outputType == .mp4 ? "video/mp4" : "video/quicktime"
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? APIError.invalidPayload("Не удалось обрезать видео"))
                default:
                    continuation.resume(throwing: APIError.invalidPayload("Не удалось обрезать видео"))
                }
            }
        }
    }

    private func profileMediaPayload(
        from item: PhotosPickerItem,
        preferredKind: PlayerMediaKind,
        index: Int
    ) async throws -> (data: Data, fileName: String, mimeType: String) {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw APIError.invalidPayload("Не удалось прочитать выбранный файл")
        }

        let contentType = item.supportedContentTypes.first

        if preferredKind == .photo, let image = UIImage(data: data), let jpegData = image.jpegData(compressionQuality: 0.88) {
            return (jpegData, "profile-photo-\(index + 1).jpg", "image/jpeg")
        }

        let mimeType = contentType?.preferredMIMEType ?? (preferredKind == .video ? "video/quicktime" : "image/jpeg")
        let fileExtension = preferredProfileMediaExtension(for: contentType, preferredKind: preferredKind)
        return (data, "profile-\(preferredKind.rawValue)-\(index + 1).\(fileExtension)", mimeType)
    }

    private func preferredProfileMediaExtension(for contentType: UTType?, preferredKind: PlayerMediaKind) -> String {
        if let preferredFilenameExtension = contentType?.preferredFilenameExtension {
            return preferredFilenameExtension
        }

        return preferredKind == .video ? "mov" : "jpg"
    }

    private func applyProfileMediaUpload(_ result: ProfileMediaUploadResult) {
        if var updatedDraft = draft {
            updatedDraft.profilePhotoUrls = result.profilePhotoUrls
            updatedDraft.profileVideoUrls = result.profileVideoUrls
            updatedDraft.avatarUrl = result.avatarUrl ?? result.profilePhotoUrls.first
            draft = updatedDraft
            appModel.currentUser = updatedDraft
        } else if var currentUser = appModel.currentUser {
            currentUser.profilePhotoUrls = result.profilePhotoUrls
            currentUser.profileVideoUrls = result.profileVideoUrls
            currentUser.avatarUrl = result.avatarUrl ?? result.profilePhotoUrls.first
            draft = currentUser
            appModel.currentUser = currentUser
        }
    }

    private func requestProfileMediaRemoval(_ item: PlayerMediaItem) {
        guard item.kind == .video else {
            removeProfileMediaPersistently(item)
            return
        }

        pendingProfileVideoRemoval = item
    }

    private func removeProfileMediaPersistently(_ item: PlayerMediaItem) {
        guard profileMediaMutationCount == 0,
              let snapshot = draft ?? appModel.currentUser else { return }

        applyOptimisticProfileMediaRemoval(item)
        enqueueProfileMediaMutation {
            do {
                let result = try await appModel.repository.removeProfileMedia(mediaUrl: item.path)
                applyProfileMediaUpload(result)
                AppHaptics.notification(.success)
                showSaveToast(item.kind == .video ? "Видео удалено" : "Фото удалено")
            } catch {
                draft = snapshot
                appModel.currentUser = snapshot
                guard !error.isCancellationLike else { return }
                appModel.present(error: error)
            }
        }
    }

    private func applyOptimisticProfileMediaRemoval(_ item: PlayerMediaItem) {
        guard var updatedDraft = draft ?? appModel.currentUser else { return }

        switch item.kind {
        case .photo:
            updatedDraft.profilePhotoUrls.removeAll { $0 == item.path }
            if updatedDraft.avatarUrl == item.path {
                updatedDraft.avatarUrl = updatedDraft.profilePhotoUrls.first
            }
        case .video:
            updatedDraft.profileVideoUrls.removeAll { $0 == item.path }
        }

        draft = updatedDraft
        appModel.currentUser = updatedDraft
    }

    private func enqueueProfileMediaMutation(_ operation: @escaping @MainActor () async -> Void) {
        let precedingMutation = profileMediaMutationTail
        profileMediaMutationCount += 1
        profileMediaMutationTail = Task { @MainActor in
            await precedingMutation?.value
            await operation()
            profileMediaMutationCount = max(profileMediaMutationCount - 1, 0)
        }
    }

    private func showSaveToast(_ message: String) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            saveToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.22)) {
                if saveToastMessage == message {
                    saveToastMessage = nil
                }
            }
        }
    }

    private func profileCompletionStatus(for profile: UserProfile) -> ProfileCompletionStatus {
        let city = SupportedCity.resolve(profile.city)
        let hasDistrict = profile.district?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || !profile.preferredDistricts.isEmpty
        let hasLevels = !profile.preferredSports.isEmpty && profile.preferredSports.allSatisfy { sport in
            profile.sportLevels[sport.rawValue] != nil || (sport == .tennis && profile.tennisLevel != nil)
        }
        let hasAvailability = profile.availabilityByDay.values.contains { !$0.isEmpty }
        let hasPhoto = profile.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || !profile.profilePhotoUrls.isEmpty

        var requirements: [(isComplete: Bool, step: String)] = [
            (profile.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "Добавьте имя"),
            (profile.age != nil, "Укажите возраст"),
            (city != nil, "Выберите город"),
            (hasPhoto, "Добавьте основное фото"),
            (!profile.preferredSports.isEmpty, "Выберите хотя бы один вид спорта"),
            (hasLevels, "Укажите уровень для выбранных видов спорта"),
            (hasAvailability, "Отметьте удобные дни и время"),
            (profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "Расскажите о себе")
        ]

        if city == .saintPetersburg {
            requirements.append((hasDistrict, "Выберите район Санкт-Петербурга"))
        }

        let completedCount = requirements.filter(\.isComplete).count
        let percent = Int((Double(completedCount) / Double(requirements.count) * 100).rounded())
        return ProfileCompletionStatus(
            percent: percent,
            missingSteps: requirements.filter { !$0.isComplete }.map(\.step)
        )
    }

    private func sportsSummary(for profile: UserProfile) -> String {
        guard !profile.preferredSports.isEmpty else { return "Виды спорта ещё не выбраны" }
        return "\(profile.preferredSports.count) вида спорта и уровни"
    }

    private func playLocationSummary(for profile: UserProfile) -> String {
        let districts = profile.preferredDistricts.isEmpty ? [profile.district].compactMap { $0 } : profile.preferredDistricts
        guard !districts.isEmpty else { return "Районы и любимые клубы не указаны" }
        return "\(districts.count) района, любимые клубы"
    }

    private func activitySummary(for profile: UserProfile) -> String {
        profile.isLookingForGame ? "Ищешь игру сейчас" : "Активных поисков нет"
    }

    private func notificationsSummary(for profile: UserProfile) -> String {
        let enabled = enabledNotificationCount(for: profile)
        guard enabled > 0 else { return "Все события выключены" }
        return "\(enabled) из 3 событий, звук \(profile.notificationSound ? "включён" : "выключен")"
    }

    private func enabledNotificationCount(for profile: UserProfile) -> Int {
        [profile.notificationMatches, profile.notificationMessages, profile.notificationGames].filter { $0 }.count
    }

    private func availabilityHeadline(for availabilityByDay: [String: [String]]) -> String {
        guard !availabilityByDay.isEmpty else { return "Время игры не указано" }
        let ranges = Set(availabilityByDay.values.flatMap { $0 }).compactMap { TimeRange(rawValue: $0)?.title.lowercased() }
        let daysCount = availabilityByDay.filter { !$0.value.isEmpty }.count
        return "\(daysCount) дней, \(ranges.sorted().joined(separator: ", "))"
    }

    private func profileDistrictOptions(for city: SupportedCity) -> [String] {
        districtAreasByID.values
            .filter { $0.city == city }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            .map(\.id)
    }

    private func supportedCityBinding(for profile: Binding<UserProfile>) -> Binding<SupportedCity> {
        Binding(
            get: {
                SupportedCity.resolve(profile.wrappedValue.city) ?? .saintPetersburg
            },
            set: { city in
                let previousCity = SupportedCity.resolve(profile.wrappedValue.city)
                profile.wrappedValue.city = city.rawValue
                guard previousCity != city else {
                    return
                }

                profile.wrappedValue.district = nil
                profile.wrappedValue.preferredDistricts.removeAll()
            }
        )
    }

    private func activeProfileDistricts(for profile: UserProfile) -> [String] {
        if !profile.preferredDistricts.isEmpty {
            return profile.preferredDistricts
        }

        return [profile.district].compactMap { $0 }.filter { !$0.isEmpty }
    }

    private func availabilityMetricItems(for availabilityByDay: [String: [String]]) -> [ProfileMetricItem] {
        let selectedDays = availabilityByDay.filter { !$0.value.isEmpty }.count
        let ranges = Set(availabilityByDay.values.flatMap { $0 })
        let windows = ranges
            .compactMap { TimeRange(rawValue: $0)?.title }
            .sorted()
            .joined(separator: ", ")

        return [
            .init(title: "Дней", value: "\(selectedDays)", icon: "calendar"),
            .init(title: "Окна", value: windows.isEmpty ? "Пусто" : windows, icon: "clock"),
            .init(title: "Слотов", value: "\(availabilityByDay.values.reduce(0) { $0 + $1.count })", icon: "checklist")
        ]
    }
}

private struct ProfileEditorScreen<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var isSaving = false

    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let onSave: () async -> Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        onSave: @escaping () async -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ProfileSubscreenHeader(title: title, onBack: { dismiss() })

                    ProfileEditorHero(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)

                    content

                    Button {
                        performSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Сохранить")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(ProfileFilledButtonStyle(tint: AppTheme.court))
                    .disabled(isSaving)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = .hidden
            }
        }
        .onDisappear {
            appModel.bottomBarDisplayMode = .expanded
        }
        .profileBackSwipe { dismiss() }
    }

    private func performSave() {
        guard !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            let shouldDismiss = await onSave()
            isSaving = false
            if shouldDismiss {
                dismiss()
            }
        }
    }
}

private struct ProfileAccountScreen: View {
    @Environment(\.dismiss) private var dismiss

    let email: String?
    let isVerified: Bool
    let onLogout: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                ProfileSubscreenHeader(title: "Аккаунт", onBack: { dismiss() })

                ProfileDarkPanel {
                    VStack(spacing: 0) {
                        ProfileInfoLine(title: "Почта", value: email ?? "Не указана")
                        ProfileInfoLine(title: "Статус", value: isVerified ? "Подтверждён" : "Не подтверждён")
                    }
                }

                Button("Выйти") {
                    onLogout()
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .white))

                Button("Удалить профиль") {
                    onDelete()
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .red))

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .profileBackSwipe { dismiss() }
    }
}

private struct ProfileBackSwipeModifier: ViewModifier {
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 28, coordinateSpace: .local)
                .onEnded { value in
                    let startsNearLeftEdge = value.startLocation.x <= 34
                    let movesRight = value.translation.width >= 82
                    let mostlyHorizontal = abs(value.translation.height) <= 72
                    guard startsNearLeftEdge && movesRight && mostlyHorizontal else { return }
                    AppHaptics.selection()
                    onBack()
                }
        )
    }
}

private extension View {
    func profileBackSwipe(onBack: @escaping () -> Void) -> some View {
        modifier(ProfileBackSwipeModifier(onBack: onBack))
    }
}

private struct ProfileEditorHero: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 58, height: 58)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.18), Color.white.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct ProfileMetricItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
}

private struct ProfileEditorMetricStrip: View {
    let items: [ProfileMetricItem]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.green)
                    Text(item.value)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                    Text(item.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
}

private struct ProfileEmbeddedLightCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(16)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct ProfileAvailabilityDarkSummary: View {
    let availabilityByDay: [String: [String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Итог расписания", systemImage: "calendar.badge.checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            if availabilityByDay.isEmpty {
                Text("Доступность пока не указана. Подбор будет меньше учитывать расписание.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(DayOfWeek.allCases) { day in
                        if let ranges = availabilityByDay[day.rawValue], !ranges.isEmpty {
                            ProfileCapsule(
                                text: "\(day.shortTitle) · \(ranges.compactMap { TimeRange(rawValue: $0)?.title }.joined(separator: ", "))",
                                tint: AppTheme.court
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ProfileDistrictPickerCard: View {
    @Binding var selectedDistricts: [String]
    @Binding var primaryDistrict: String?
    let districts: [String]

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]

    var body: some View {
        ProfileEmbeddedLightCard(title: "Предпочтительные районы", subtitle: "Первый выбранный район станет основным для профиля.") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(districts, id: \.self) { district in
                    districtChip(district)
                }
            }

            if !selectedDistricts.isEmpty {
                Button {
                    AppHaptics.selection()
                    selectedDistricts.removeAll()
                    primaryDistrict = nil
                } label: {
                    Label("Сбросить районы", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProfileSoftButtonStyle())
                .foregroundStyle(AppTheme.ink)
                .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func districtChip(_ district: String) -> some View {
        let isSelected = selectedDistricts.contains(district)
        let title = localizedDistrictName(district) ?? district

        return Button {
            AppHaptics.selection()
            if isSelected {
                selectedDistricts.removeAll { $0 == district }
            } else {
                selectedDistricts.append(district)
            }
            primaryDistrict = selectedDistricts.first
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : AppTheme.ink)
            .background(isSelected ? AppTheme.court : AppTheme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppTheme.court.opacity(0.42) : Color.white.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileVideoTrimDraft: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let duration: TimeInterval
    let fileName: String
}

private struct ProfileTrimmedVideoPayload {
    let data: Data
    let fileExtension: String
    let mimeType: String
}

private struct ProfileMediaProgressOverlay: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)

                VStack(spacing: 5) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 280)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.36), radius: 24, x: 0, y: 14)
        }
    }
}

private struct ProfileVideoTrimEditorSheet: View {
    let draft: ProfileVideoTrimDraft
    let isUploading: Bool
    let onCancel: () -> Void
    let onConfirm: (TimeInterval) -> Void

    @State private var startTime: TimeInterval = 0
    @State private var player: AVPlayer?
    @State private var didSubmit = false

    private var maxStartTime: TimeInterval {
        max(draft.duration - 10, 0)
    }

    private var isProcessing: Bool {
        isUploading || didSubmit
    }

    private var selectedDuration: TimeInterval {
        min(10, max(draft.duration - startTime, 0))
    }

    private var endTime: TimeInterval {
        min(startTime + selectedDuration, draft.duration)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Обрезать видео")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Выберите фрагмент до 10 секунд")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(formatTime(startTime)) - \(formatTime(endTime))")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(ceil(selectedDuration))) сек")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.mint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.court.opacity(0.28), in: Capsule())
                    }

                    trimTimeline

                    Slider(value: $startTime, in: 0 ... maxStartTime)
                        .tint(AppTheme.mint)
                        .disabled(maxStartTime <= 0)
                        .onChange(of: startTime) { newValue in
                            seekPlayer(to: newValue)
                        }

                    Text(maxStartTime <= 0 ? "Видео короче 10 секунд, можно загрузить целиком." : "Передвиньте шкалу, чтобы выбрать начало 10-секундного фрагмента.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
                .padding(16)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    guard !isProcessing else { return }
                    didSubmit = true
                    player?.pause()
                    onConfirm(startTime)
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isProcessing ? "Готовим видео..." : "Использовать фрагмент")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProfileFilledButtonStyle(tint: AppTheme.court))
                .disabled(isProcessing)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 28)

            if isProcessing {
                ProfileMediaProgressOverlay(
                    title: "Видео загружается",
                    subtitle: "Сохраняем выбранный фрагмент в карточку."
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            let nextPlayer = AVPlayer(url: draft.sourceURL)
            nextPlayer.isMuted = true
            player = nextPlayer
            seekPlayer(to: startTime)
            nextPlayer.play()
        }
        .onDisappear {
            player?.pause()
        }
        .onChange(of: isUploading) { uploading in
            if !uploading {
                didSubmit = false
            }
        }
    }

    private var trimTimeline: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let selectedWidth = width * CGFloat(selectedDuration / max(draft.duration, 0.1))
            let selectedOffset = width * CGFloat(startTime / max(draft.duration, 0.1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 16)

                Capsule()
                    .fill(AppTheme.mint)
                    .frame(width: max(selectedWidth, 22), height: 16)
                    .offset(x: min(selectedOffset, max(width - selectedWidth, 0)))
                    .shadow(color: AppTheme.mint.opacity(0.32), radius: 10, x: 0, y: 0)
            }
        }
        .frame(height: 20)
    }

    private func seekPlayer(to seconds: TimeInterval) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct ProfileScreenModePicker: View {
    @Binding var selection: ProfileScreenMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProfileScreenMode.allCases) { mode in
                Button {
                    AppHaptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.caption.weight(.bold))
                        Text(mode.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                        .foregroundStyle(selection == mode ? .black : .white.opacity(0.68))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .padding(.horizontal, 6)
                        .background(selection == mode ? AppTheme.mint : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct ProfileSwipeCardPreview: View {
    let profile: UserProfile

    private var previewUser: DiscoverUser {
        DiscoverUser(profile: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Карточка в «Похожих игроках»")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Показаны только данные из вашего профиля")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
            }

            SwipeCard(
                user: previewUser,
                index: 0,
                dragOffset: .zero,
                decision: nil,
                mode: .profilePreview,
                onOpen: {},
                onDislike: {},
                onLike: {}
            )
            .frame(height: 520)

            Label("Предпросмотр: свайпы и действия отключены", systemImage: "eye.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.56))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct ProfileOverviewCard: View {
    let profile: UserProfile
    let isUploadingAvatar: Bool
    @Binding var selectedAvatarItem: PhotosPickerItem?
    let onEdit: () -> Void

    var body: some View {
        ProfileDarkPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                        ZStack(alignment: .bottomTrailing) {
                            ProfileHeroImage(name: profile.displayName, path: profile.profileHeroImagePath, height: 118)
                                .frame(width: 112)

                            Circle()
                                .fill(isUploadingAvatar ? AppTheme.court : Color.green)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.black, lineWidth: 3))

                            if isUploadingAvatar {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                                    .offset(x: 2, y: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(profile.displayName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                            if profile.isLookingForGame {
                                ProfileCapsule(text: "Ищу игру", tint: AppTheme.court)
                            }
                        }

                        Text(profileAgeCityLine(profile))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        if let district = profile.district, !district.isEmpty {
                            Label(district, systemImage: "mappin.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Text(profile.bio ?? "Добавь пару строк о себе и короткие видео с тренировок.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(profile.preferredSports.prefix(4)) { sport in
                        ProfileSportChip(sport: sport, level: profile.sportLevels[sport.rawValue] ?? profile.tennisLevel)
                    }
                }

                NavigationLink {
                    QRProfileView(profile: profile, visibilityMode: .publicProfile)
                } label: {
                    Label("QR-профиль", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProfileSoftButtonStyle())
            }
        }
    }

    private func profileAgeCityLine(_ profile: UserProfile) -> String {
        var parts: [String] = []
        if let age = profile.age {
            parts.append("\(age) лет")
        }
        parts.append(profile.city ?? "Санкт-Петербург")
        return parts.joined(separator: " · ")
    }
}

private struct ProfileSelectionMediaCard: View {
    let profile: UserProfile
    let isUploadingAvatar: Bool
    let isUploading: Bool
    @Binding var selectedAvatarItem: PhotosPickerItem?
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var selectedVideoItems: [PhotosPickerItem]
    let onEdit: () -> Void
    let onPreview: (PlayerMediaItem) -> Void
    let onRemove: (PlayerMediaItem) -> Void

    private var mediaItems: [PlayerMediaItem] {
        profile.playerCardMediaItems
    }

    private var remainingPhotoSlots: Int {
        max(6 - profile.profilePhotoUrls.count, 0)
    }

    private var remainingVideoSlots: Int {
        max(4 - profile.profileVideoUrls.count, 0)
    }

    var body: some View {
        ProfileDarkPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ваш профиль")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Основные данные и медиа")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer(minLength: 4)

                    if isUploading || isUploadingAvatar {
                        ProgressView()
                            .tint(.white)
                    }

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.09), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Редактировать профиль")
                }

                PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileHeroImage(
                            name: profile.displayName,
                            path: profile.profileHeroImagePath,
                            height: 264
                        )

                        Label("Основное фото", systemImage: "camera.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(.black.opacity(0.64), in: Capsule())
                            .padding(12)

                        if isUploadingAvatar {
                            Color.black.opacity(0.36)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            ProgressView()
                                .tint(.white)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploading || isUploadingAvatar)

                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            profileName
                            lookingForGameBadge
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            profileName
                            lookingForGameBadge
                        }
                    }

                    Label(profileLocationLine, systemImage: "mappin.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)

                    if profile.preferredSports.isEmpty {
                        Text("Виды спорта пока не выбраны")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.52))
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(profile.preferredSports.prefix(4)) { sport in
                                ProfileSportChip(
                                    sport: sport,
                                    level: profile.sportLevels[sport.rawValue] ?? profile.tennisLevel
                                )
                            }
                        }
                    }

                    Text(profileBioText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            mediaTitle
                            Spacer()
                            videoBonusLabel
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            mediaTitle
                            videoBonusLabel
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(mediaItems) { item in
                                ProfileMediaTile(
                                    item: item,
                                    canRemove: item.kind == .video || profile.profilePhotoUrls.contains(item.path),
                                    isEnabled: !isUploading && !isUploadingAvatar,
                                    onPreview: onPreview,
                                    onRemove: onRemove
                                )
                            }

                            if remainingPhotoSlots > 0 {
                                PhotosPicker(
                                    selection: $selectedPhotoItems,
                                    maxSelectionCount: remainingPhotoSlots,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    ProfileAddMediaTile(title: "Фото", systemImage: "camera.fill")
                                }
                                .buttonStyle(.plain)
                                .disabled(isUploading || isUploadingAvatar)
                            }

                            if remainingVideoSlots > 0 {
                                PhotosPicker(
                                    selection: $selectedVideoItems,
                                    maxSelectionCount: remainingVideoSlots,
                                    matching: .videos,
                                    photoLibrary: .shared()
                                ) {
                                    ProfileAddMediaTile(title: "Видео до 10 сек", systemImage: "play.rectangle.fill")
                                }
                                .buttonStyle(.plain)
                                .disabled(isUploading || isUploadingAvatar)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                ProfileMediaAdviceRow()
            }
        }
    }

    private var profileName: some View {
        Text(profile.age.map { "\(profile.displayName), \($0)" } ?? profile.displayName)
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
    }

    @ViewBuilder
    private var lookingForGameBadge: some View {
        if profile.isLookingForGame {
            ProfileCapsule(text: "Ищу игру", tint: AppTheme.court)
        }
    }

    private var profileLocationLine: String {
        var parts: [String] = []
        if let city = profile.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            parts.append(city)
        }
        let districts = profile.preferredDistricts.isEmpty
            ? [profile.district].compactMap { $0 }
            : profile.preferredDistricts
        if let district = districts.compactMap(localizedDistrictName).first {
            parts.append(district)
        }
        return parts.isEmpty ? "Город и район не указаны" : parts.joined(separator: " · ")
    }

    private var profileBioText: String {
        guard let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty else {
            return "Описание пока не заполнено"
        }
        return bio
    }

    private var mediaTitle: some View {
        Text("Фото и видео")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
    }

    private var videoBonusLabel: some View {
        Label(
            profile.profileVideoUrls.isEmpty ? "Видео: необязательный бонус" : "Видео добавлено",
            systemImage: profile.profileVideoUrls.isEmpty ? "sparkles" : "checkmark.circle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(profile.profileVideoUrls.isEmpty ? .white.opacity(0.58) : AppTheme.mint)
    }
}

private struct ProfileHeroImage: View {
    let name: String
    let path: String?
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let url = resolveAppRemoteURL(path) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: height)
                                .clipped()
                        default:
                            fallback
                        }
                    }
                } else {
                    fallback
                }
            }
            .frame(width: geometry.size.width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.court.opacity(0.85), AppTheme.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(initials)
                .font(.system(size: min(height * 0.28, 46), weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        return parts.isEmpty ? "TS" : parts.joined()
    }
}

private struct ProfileMediaTile: View {
    let item: PlayerMediaItem
    let canRemove: Bool
    let isEnabled: Bool
    let onPreview: (PlayerMediaItem) -> Void
    let onRemove: (PlayerMediaItem) -> Void

    var body: some View {
        ZStack {
            Button {
                onPreview(item)
            } label: {
                thumbnail
                    .frame(width: 92, height: 120)
                    .clipped()
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)

            if canRemove {
                Button {
                    onRemove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.58), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(item.kind == .video ? "Удалить видео" : "Удалить фото")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(6)
            }
        }
        .frame(width: 92, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.court.opacity(0.55), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.kind == .video, let url = resolveAppRemoteURL(item.path) {
            MutedLoopingVideoView(url: url)
        } else if item.kind == .photo, let url = resolveAppRemoteURL(item.path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    tileFallback
                }
            }
        } else {
            tileFallback
        }
    }

    private var tileFallback: some View {
        LinearGradient(
            colors: [AppTheme.court.opacity(0.28), Color.white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: item.kind == .video ? "play.rectangle.fill" : "photo.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        )
    }
}

private struct ProfileAddMediaTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.86))
        .frame(width: 92, height: 120)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        )
    }
}

private struct ProfileMediaAdviceRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.court)
                .padding(.top, 1)
            Text("Добавьте фото в хорошем освещении и короткие видео с игры или тренировки.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProfileCompletenessCard: View {
    let percent: Int
    let missingSteps: [String]
    let hasVideoBonus: Bool

    var body: some View {
        ProfileDarkPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Заполненность профиля")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(completionSubtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer(minLength: 4)

                    Text("\(percent)%")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.mint)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule()
                            .fill(LinearGradient(colors: [AppTheme.court, .green], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 7)

                if missingSteps.isEmpty {
                    Label("Все обязательные шаги выполнены", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.mint)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(missingSteps, id: \.self) { step in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "circle")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.mint)
                                    .padding(.top, 3)
                                Text(step)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Label(
                    hasVideoBonus ? "Видео добавлено как бонус к карточке" : "Видео: бонус, который не влияет на заполненность",
                    systemImage: hasVideoBonus ? "play.circle.fill" : "sparkles"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(hasVideoBonus ? AppTheme.mint : .white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var completionSubtitle: String {
        if missingSteps.isEmpty {
            return "Профиль готов к показу"
        }
        return "Осталось шагов: \(missingSteps.count)"
    }
}

private struct ProfileGameFeedSection: View {
    let requests: [MatchGameRequest]
    let currentUserId: String?
    let isLoading: Bool
    @State private var selectedReport: GameReport?

    var body: some View {
        ProfileDarkPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Лента игр")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(feedSubtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else if !requests.isEmpty {
                        Text("\(requests.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.court)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppTheme.court.opacity(0.14), in: Capsule())
                    }
                }

                if requests.isEmpty && !isLoading {
                    Text("После завершённой игры добавь фотоотчёт — она появится здесь.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        ForEach(requests) { request in
                            ProfileGameFeedRow(
                                request: request,
                                currentUserId: currentUserId,
                                onOpenReport: { selectedReport = $0 }
                            )
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedReport) { report in
            GameReportPhotoGallerySheet(report: report)
        }
    }

    private var feedSubtitle: String {
        if requests.isEmpty {
            return "Фотоотчёты и подтверждённые тренировки"
        }
        let reportCount = requests.filter { $0.report != nil }.count
        return "\(requests.count) игр · \(reportCount) фотоотчётов"
    }
}

private struct ProfileGameFeedRow: View {
    let request: MatchGameRequest
    let currentUserId: String?
    let onOpenReport: (GameReport) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProfileGameFeedPreview(report: request.report, sport: request.sport)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SportIconView(sport: request.sport, color: AppTheme.court, size: 16)
                    Text("\(request.sport.title) · \(request.proposedDatetime.formattedDateTime())")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Text(feedDetails)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)

                if let report = request.report {
                    HStack(spacing: 8) {
                        Text(report.statusTitle)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(report.status.lowercased() == "confirmed" ? AppTheme.court : Color.orange)

                        if !report.photoUrls.isEmpty {
                            Label("\(report.photoUrls.count) фото", systemImage: "photo.stack")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                } else if let outcome = request.outcomeLabel {
                    Text(outcome)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.court)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            guard let report = request.report, !report.photoUrls.isEmpty else { return }
            onOpenReport(report)
        }
    }

    private var feedDetails: String {
        let people = request.participantNamesLine(currentUserId: currentUserId)
        let court = request.proposedCourt?.name
        return [court, people].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }
}

private struct ProfileGameFeedPreview: View {
    let report: GameReport?
    let sport: Sport

    private var photoPaths: [String] {
        Array((report?.photoUrls ?? []).prefix(4))
    }

    private var extraPhotoCount: Int {
        max((report?.photoUrls.count ?? 0) - 4, 0)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.court.opacity(0.16))

            if photoPaths.isEmpty {
                fallbackIcon
            } else {
                collage
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fallbackIcon: some View {
        SportIconView(sport: sport, color: AppTheme.court, size: 24)
    }

    @ViewBuilder
    private var collage: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let halfWidth = (geometry.size.width - gap) / 2
            let halfHeight = (geometry.size.height - gap) / 2

            switch photoPaths.count {
            case 1:
                photoTile(path: photoPaths[0], showsMoreOverlay: false)
            case 2:
                HStack(spacing: gap) {
                    photoTile(path: photoPaths[0], showsMoreOverlay: false)
                        .frame(width: halfWidth, height: geometry.size.height)
                    photoTile(path: photoPaths[1], showsMoreOverlay: extraPhotoCount > 0)
                        .frame(width: halfWidth, height: geometry.size.height)
                }
            case 3:
                HStack(spacing: gap) {
                    photoTile(path: photoPaths[0], showsMoreOverlay: false)
                        .frame(width: halfWidth, height: geometry.size.height)
                    VStack(spacing: gap) {
                        photoTile(path: photoPaths[1], showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                        photoTile(path: photoPaths[2], showsMoreOverlay: extraPhotoCount > 0)
                            .frame(width: halfWidth, height: halfHeight)
                    }
                }
            default:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        photoTile(path: photoPaths[0], showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                        photoTile(path: photoPaths[1], showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                    }
                    HStack(spacing: gap) {
                        photoTile(path: photoPaths[2], showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                        photoTile(path: photoPaths[3], showsMoreOverlay: extraPhotoCount > 0)
                            .frame(width: halfWidth, height: halfHeight)
                    }
                }
            }
        }
    }

    private func photoTile(path: String, showsMoreOverlay: Bool) -> some View {
        ZStack {
            if let url = resolveAppRemoteURL(path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }

            if showsMoreOverlay {
                Color.black.opacity(0.45)
                Text("+\(extraPhotoCount)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
            }
        }
        .clipped()
    }
}

private struct GameReportPhotoGallerySheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: GameReport
    @State private var selectedIndex = 0

    private var photoUrls: [String] {
        report.photoUrls
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if photoUrls.isEmpty {
                    emptyState
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(photoUrls.enumerated()), id: \.offset) { index, path in
                            GameReportGalleryPhoto(path: path)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }

                footer
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Фотоотчёт")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(report.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mint)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !photoUrls.isEmpty {
                HStack {
                    Text("\(selectedIndex + 1) / \(photoUrls.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer()
                    Image(systemName: "photo.stack")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.mint)
                }
            }

            if let comment = report.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.black.opacity(0.82))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 44, weight: .semibold))
            Text("Фото недоступны")
                .font(.headline.weight(.bold))
        }
        .foregroundStyle(.white.opacity(0.74))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GameReportGalleryPhoto: View {
    let path: String

    var body: some View {
        ZStack {
            if let url = resolveAppRemoteURL(path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }
}

private struct QRProfileView: View {
    let profile: UserProfile
    let visibilityMode: ProfileVisibilityMode
    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?

    private var profileURL: String {
        if let baseURL = AppConfig.apiBaseURL {
            return baseURL.appendingPathComponent("users").appendingPathComponent(profile.id).absoluteString
        }
        return "tennissearch://profile/\(profile.id)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ProfileSubscreenHeader(title: "QR-профиль", onBack: { dismiss() })

                    ProfileDarkPanel {
                        VStack(spacing: 20) {
                            Text("Покажи этот код, чтобы поделиться своим профилем")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            QRCodeImage(text: profileURL)
                                .frame(width: 246, height: 246)
                                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay {
                                    Image(systemName: "map")
                                        .font(.system(size: 34, weight: .semibold))
                                        .foregroundStyle(AppTheme.court)
                                        .padding(16)
                                        .background(Color(red: 0.09, green: 0.1, blue: 0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }

                            ProfileSmallPublicCard(profile: profile)

                            Label("По QR откроется только публичная карточка. Личные данные не показываются.", systemImage: "checkmark.shield")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ProfileMenuGroup {
                        ProfileActionRow(icon: "link", title: "Поделиться ссылкой") {
                            UIPasteboard.general.string = profileURL
                            AppHaptics.notification(.success)
                            showToast("Ссылка скопирована")
                        }

                        ProfileActionRow(icon: "square.and.arrow.down", title: "Сохранить QR") {
                            AppHaptics.selection()
                            showToast("QR готов к сохранению")
                        }

                        ShareLink(item: profileURL) {
                            ProfileMenuRow(icon: "square.and.arrow.up", tint: .white.opacity(0.72), title: "Поделиться", subtitle: nil)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            VisibilitySettingsView(selectionRaw: .constant(visibilityMode.rawValue))
                        } label: {
                            ProfileMenuRow(icon: "eye", tint: .white.opacity(0.72), title: "Настроить видимость", subtitle: visibilityMode.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .profileBackSwipe { dismiss() }
        .overlay(alignment: .top) {
            if let toast {
                InlineStatusToast(message: toast)
                    .padding(.top, 12)
            }
        }
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if toast == message {
                    toast = nil
                }
            }
        }
    }
}

private struct VisibilitySettingsView: View {
    @Binding var selectionRaw: String
    @Environment(\.dismiss) private var dismiss

    private var selection: ProfileVisibilityMode {
        ProfileVisibilityMode(rawValue: selectionRaw) ?? .publicProfile
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                ProfileSubscreenHeader(title: "Настройки видимости", onBack: { dismiss() })

                Text("Выбери, что будет видно в твоём публичном профиле")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.72))

                VisibilityOptionCard(
                    mode: .publicProfile,
                    isSelected: selection == .publicProfile,
                    onSelect: { selectionRaw = ProfileVisibilityMode.publicProfile.rawValue }
                )

                VisibilityOptionCard(
                    mode: .limitedProfile,
                    isSelected: selection == .limitedProfile,
                    onSelect: { selectionRaw = ProfileVisibilityMode.limitedProfile.rawValue }
                )

                ProfileDarkPanel {
                    Label("В любой момент можно изменить настройки видимости.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .profileBackSwipe { dismiss() }
    }
}

private struct VisibilityOptionCard: View {
    let mode: ProfileVisibilityMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            AppHaptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                onSelect()
            }
        } label: {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(mode.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isSelected ? .green : .white)
                        Spacer()
                        Circle()
                            .stroke(isSelected ? .green : .white.opacity(0.38), lineWidth: 2)
                            .frame(width: 22, height: 22)
                            .overlay {
                                if isSelected {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 12, height: 12)
                                }
                            }
                    }

                    Text(mode.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 12) {
                        ForEach(mode.icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.76))
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileMenuGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ProfileDarkPanel {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct ProfileMenuRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct ProfileActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileMenuRow(icon: icon, tint: .white.opacity(0.72), title: title, subtitle: nil)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileDarkPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
    }
}

private struct ProfileHeaderButton: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct ProfileCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint == AppTheme.court ? .green : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.18), in: Capsule())
    }
}

private struct ProfileSportChip: View {
    let sport: Sport
    let level: Int?

    var body: some View {
        HStack(spacing: 7) {
            SportIconView(sport: sport, color: sport == .tennis ? .yellow : AppTheme.court, size: 15)
            Text("\(sport.shortTitle) \(levelText)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private var levelText: String {
        guard let level else { return "" }
        let next = min(10, max(1, level + 1))
        return "\(level)-\(next)"
    }
}

private struct ProfileSubscreenHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Spacer()
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
    }
}

private struct QRCodeImage: View {
    let text: String

    var body: some View {
        Image(uiImage: makeQRCode(from: text))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .padding(18)
    }

    private func makeQRCode(from text: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return UIImage()
        }

        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledImage = outputImage.transformed(by: transform)
        let context = CIContext()

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return UIImage()
        }

        return UIImage(cgImage: cgImage)
    }
}

private struct ProfileSmallPublicCard: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 14) {
            RemoteAvatarView(name: profile.displayName, path: profile.avatarUrl, size: 70)
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(profile.age.map { "\($0) лет · \(profile.city ?? "Санкт-Петербург")" } ?? (profile.city ?? "Санкт-Петербург"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                Text(profile.preferredSports.prefix(2).map(\.title).joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct ProfileFact: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.045))
    }
}

private struct ProfileInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.56))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}

private struct ProfileFilledButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(tint.opacity(configuration.isPressed ? 0.72 : 0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct ProfileSoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct ToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
            }
            Spacer()
            Button {
                AppHaptics.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isOn.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isOn ? AppTheme.court : AppTheme.cream)
                    .frame(width: 54, height: 32)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                            .padding(4)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }
}

private enum ProfileVisibilityMode: String {
    case publicProfile
    case limitedProfile

    var title: String {
        switch self {
        case .publicProfile:
            return "Публичный профиль"
        case .limitedProfile:
            return "Ограниченный профиль"
        }
    }

    var description: String {
        switch self {
        case .publicProfile:
            return "Показывать фото, спорт, уровень, район и описание. Подходит для поиска новых игроков."
        case .limitedProfile:
            return "Показывать только имя, спорт и город. Больше приватности — меньше деталей."
        }
    }

    var icons: [String] {
        switch self {
        case .publicProfile:
            return ["person.2", "tennis.racket", "chart.bar", "mappin", "message"]
        case .limitedProfile:
            return ["person.2", "tennis.racket", "location"]
        }
    }
}

private extension Sport {
    var shortTitle: String {
        switch self {
        case .tableTennis:
            return "Наст. теннис"
        default:
            return title
        }
    }

    var profileIcon: String {
        switch self {
        case .tennis:
            return "tennisball.fill"
        case .padel, .badminton, .squash, .tableTennis:
            return appSystemIconName
        case .volleyball:
            return "volleyball.fill"
        case .fitness:
            return "dumbbell.fill"
        case .boxing:
            return "figure.boxing"
        case .yoga:
            return "figure.yoga"
        case .football:
            return "soccerball"
        case .running:
            return "figure.run"
        case .supboard:
            return "water.waves"
        }
    }
}

private extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct ProfileSaveSuccessToast: View {
    let message: String

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .scaleEffect(isAnimating ? 1 : 0.62)
                    .rotationEffect(.degrees(isAnimating ? 0 : -18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Успешно сохранено")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(Color(red: 0.76, green: 0.97, blue: 0.80))

                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.17, blue: 0.12), Color(red: 0.10, green: 0.30, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.37, green: 0.78, blue: 0.56).opacity(0.8), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 12)
        .padding(.horizontal, 16)
        .scaleEffect(isAnimating ? 1 : 0.96)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                isAnimating = true
            }
        }
    }
}

private struct InlineStatusToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 12)
        .padding(.horizontal, 16)
    }
}
