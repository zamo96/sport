import SwiftUI
import PhotosUI
import CoreImage.CIFilterBuiltins
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import AVKit

private enum ProfileScreenMode: CaseIterable, Identifiable {
    case editing
    case preview

    var id: Self { self }

    var title: String {
        switch self {
        case .editing: return L10n.string("Editing", "Редактирование")
        case .preview: return L10n.string("Public preview", "Как видят другие")
        }
    }

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

enum ProfileGameFeedItem: Identifiable {
    case game(MatchGameRequest)
    case visit(PersonalActivity)

    var id: String {
        switch self {
        case .game(let request): return "game-\(request.id)"
        case .visit(let activity): return "visit-\(activity.id)"
        }
    }

    var date: Date {
        switch self {
        case .game(let request): return request.proposedDate ?? .distantPast
        case .visit(let activity): return activity.scheduledDate ?? .distantPast
        }
    }

    static func make(games: [MatchGameRequest], visits: [PersonalActivity], ownerID: String, referenceDate: Date = Date()) -> [ProfileGameFeedItem] {
        let gameItems = games.filter { request in
            guard request.hasEnded(referenceDate: referenceDate) else { return false }
            if let report = request.report { return report.visibility == "profile" }
            return request.outcome == "played"
        }.map(ProfileGameFeedItem.game)
        let visitItems = visits.filter { activity in
            guard activity.userId == ownerID, activity.status.lowercased() == "completed",
                  !activity.photoUrls.isEmpty, let date = activity.scheduledDate else { return false }
            let duration = TimeInterval((activity.durationMinutes ?? activity.sport.defaultDurationMinutes) * 60)
            return referenceDate.timeIntervalSince(date) >= duration
        }.map(ProfileGameFeedItem.visit)
        return Array((gameItems + visitItems).sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date > rhs.date
        }.prefix(6))
    }
}

private enum ProfileGameFeedSource {
    case games
    case visits
}

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var gameFeedVisits: [PersonalActivity] = []
    @State private var isGameFeedLoading = false
    @State private var isVisitFeedLoading = false
    @State private var gameFeedError: String?
    @State private var visitFeedError: String?
    @State private var gameFeedAccountID: String?
    @State private var gameFeedRequestToken: UUID?
    @State private var visitFeedRequestToken: UUID?
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
                .refreshable { await loadProfileGameFeed() }
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
                    title: L10n.string("Uploading video", "Видео загружается"),
                    subtitle: L10n.string("Opening the video and preparing the trim editor.", "Открываем ролик и готовим редактор обрезки.")
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
            await loadProfileGameFeed()
        }
        .onChange(of: appModel.currentUser?.id) { _ in
            resetProfileGameFeed()
            draft = appModel.currentUser
            Task { await loadProfileGameFeed() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await loadProfileGameFeed() }
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
            L10n.string("Delete profile?", "Удалить профиль?"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Delete profile", "Удалить профиль"), role: .destructive) {
                Task { await deleteProfile() }
            }
            Button(L10n.string("Cancel", "Отмена"), role: .cancel) {}
        } message: {
            Text(L10n.string("This action cannot be undone. Your account, searches, matches, and history will be deleted.", "Это действие необратимо. Аккаунт, поиски, мэтчи и история будут удалены."))
        }
        .confirmationDialog(
            L10n.string("Remove video from your profile?", "Удалить видео из карточки?"),
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
            Button(L10n.string("Remove video", "Удалить видео"), role: .destructive) {
                if let item = pendingProfileVideoRemoval {
                    removeProfileMediaPersistently(item)
                }
                pendingProfileVideoRemoval = nil
            }
            Button(L10n.string("Cancel", "Отмена"), role: .cancel) {
                pendingProfileVideoRemoval = nil
            }
        } message: {
            Text(L10n.string("The video will be removed from your profile. Your other photos and profile data will remain.", "Видео исчезнет из карточки профиля. Остальные фото и данные профиля останутся."))
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
                    items: profileGameFeedItems,
                    currentUserId: appModel.currentUser?.id,
                    isLoading: isGameFeedLoading || isVisitFeedLoading,
                    gameError: gameFeedError,
                    visitError: visitFeedError,
                    onRetryGames: { Task { await loadProfileGameFeed(source: .games) } },
                    onRetryVisits: { Task { await loadProfileGameFeed(source: .visits) } }
                )
                .id(appModel.currentUser?.id)

                ProfileMenuGroup {
                    NavigationLink {
                        sportsProfileEditor(for: draftBinding)
                    } label: {
                        ProfileMenuRow(
                            icon: "tennis.racket",
                            tint: AppTheme.court,
                            title: L10n.string("Sports profile", "Спортивный профиль"),
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
                            title: L10n.string("Availability", "Доступность"),
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
                            title: L10n.string("Preferred locations", "Где удобно играть"),
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
                            title: L10n.string("Preview profile", "Посмотреть карточку"),
                            subtitle: activitySummary(for: profile)
                        )
                    }
                    .buttonStyle(.plain)
                }

                ProfileMenuGroup {
                    NavigationLink {
                        ProfileLanguageSettingsScreen()
                    } label: {
                        ProfileMenuRow(
                            icon: "globe",
                            tint: .white.opacity(0.82),
                            title: "Language / Язык",
                            subtitle: appModel.localeStore.effectiveLocale.displayName
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        notificationProfileEditor(for: draftBinding)
                    } label: {
                        ProfileMenuRow(
                            icon: "bell",
                            tint: .white.opacity(0.82),
                            title: L10n.string("Notifications", "Уведомления"),
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
                            title: L10n.string("Privacy", "Приватность"),
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
                            title: L10n.string("Account", "Аккаунт"),
                            subtitle: profile.email ?? L10n.string("Email, phone, security", "Почта, телефон, безопасность")
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProfileSwipeCardPreview(profile: profile)
            }
        } else {
            ProfileDarkPanel {
                ProgressView(L10n.string("Loading profile", "Загружаем профиль"))
                    .tint(.white)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .center) {
            Text(L10n.string("Profile", "Профиль"))
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
                Text(L10n.string("Profile", "Профиль"))
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
                        Text(L10n.string("Guest mode", "Гостевой режим"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                        ProfileCapsule(text: L10n.string("Profile draft", "Черновик профиля"), tint: AppTheme.court)
                    }
                    Spacer()
                }
            }

            SectionCard(title: L10n.string("Profile draft", "Черновик профиля"), subtitle: L10n.string("Prepare your profile before verifying your email.", "Можно подготовить карточку до подтверждения email.")) {
                guestBasicsSection
                guestPreferencesSection
            }

            SectionCard(title: L10n.string("Sports", "Виды спорта"), subtitle: L10n.string("Choose a sport and level.", "Выбери спорт и уровень.")) {
                AppSportSelectionGrid(
                    title: L10n.string("Sports profile", "Спортивный профиль"),
                    sports: Sport.allCases,
                    selectedSports: $guestDraft.preferredSports,
                    levels: $guestDraft.sportLevels
                )
            }

            SectionCard(title: L10n.string("Availability", "Доступность"), subtitle: L10n.string("These time slots will be saved in your draft.", "Эти слоты сохранятся в черновике.")) {
                AppAvailabilityWeekEditor(availabilityByDay: $guestDraft.availabilityByDay)
                availabilitySummary(for: guestDraft.availabilityByDay)
            }

            HStack(spacing: 12) {
                Button(L10n.string("Save", "Сохранить")) {
                    persistGuestDraft()
                    showSaveToast(L10n.string("Draft saved", "Черновик сохранён"))
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .white))

                Button(L10n.string("Continue to email", "К email")) {
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
            title: L10n.string("Sports profile", "Спортивный профиль"),
            subtitle: L10n.string("Choose your sports and level.", "Настрой виды спорта и уровень."),
            systemImage: "tennis.racket",
            tint: AppTheme.court,
            onSave: { await save() }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: L10n.string("Sports", "Спортов"), value: "\(profile.wrappedValue.preferredSports.count)", icon: "figure.tennis"),
                        .init(title: L10n.string("Search", "Поиск"), value: profile.wrappedValue.isLookingForGame ? L10n.string("Active", "Активен") : L10n.string("Hidden", "Скрыт"), icon: "eye")
                    ])

                    ProfileEmbeddedLightCard(title: L10n.string("Sports", "Виды спорта"), subtitle: L10n.string("Choose everything you're ready to play and set your level.", "Выбери всё, во что готов играть, и выставь уровень.")) {
                        AppSportSelectionGrid(
                            title: L10n.string("Sports profile", "Спортивный профиль"),
                            sports: Sport.allCases,
                            selectedSports: profile.preferredSports,
                            levels: profile.sportLevels
                        )
                    }

                    ProfileEmbeddedLightCard(title: L10n.string("Visibility", "Видимость"), subtitle: L10n.string("You can temporarily hide from active player recommendations.", "Можно временно скрыться из активной подборки игроков.")) {
                        profileVisibilitySection(for: profile)
                    }
                }
            }
        }
    }

    private func availabilityProfileEditor(for profile: Binding<UserProfile>) -> some View {
        ProfileEditorScreen(
            title: L10n.string("Availability", "Доступность"),
            subtitle: L10n.string("Select the days and times when you can actually play.", "Отметь дни и окна времени, когда реально удобно играть."),
            systemImage: "clock.badge.checkmark",
            tint: Color.green,
            onSave: { await save() }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: availabilityMetricItems(for: profile.wrappedValue.availabilityByDay))

                    ProfileEmbeddedLightCard(title: L10n.string("Week", "Неделя"), subtitle: L10n.string("Use a preset or build your schedule manually.", "Можно быстро выбрать пресеты или собрать расписание вручную.")) {
                        AppAvailabilityWeekEditor(availabilityByDay: profile.availabilityByDay)
                    }

                    ProfileAvailabilityDarkSummary(availabilityByDay: profile.wrappedValue.availabilityByDay)
                }
            }
        }
    }

    private func locationProfileEditor(for profile: Binding<UserProfile>) -> some View {
        ProfileEditorScreen(
            title: L10n.string("Preferred locations", "Где удобно играть"),
            subtitle: L10n.string("Districts are used to recommend players and venues.", "Районы используются в подборе игроков и центров."),
            systemImage: "mappin.and.ellipse",
            tint: Color.green,
            onSave: { await save() }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: L10n.string("Districts", "Районов"), value: "\(activeProfileDistricts(for: profile.wrappedValue).count)", icon: "map"),
                        .init(title: L10n.string("Radius", "Радиус"), value: L10n.string("\(profile.wrappedValue.searchRadiusKm) km", "\(profile.wrappedValue.searchRadiusKm) км"), icon: "scope"),
                        .init(title: L10n.string("City", "Город"), value: profile.wrappedValue.city ?? L10n.string("Not selected", "Не выбран"), icon: "building.2")
                    ])

                    ProfileEmbeddedLightCard(title: L10n.string("City", "Город"), subtitle: L10n.string("Clubs and players are selected within the chosen city.", "Клубы и игроки подбираются внутри выбранного города.")) {
                        profileLocationButton(profile.wrappedValue)
                    }

                    if profileDistrictsEnabled(profile.wrappedValue),
                       let coveredCity = SupportedCity.resolve(profile.wrappedValue.city) {
                        ProfileDistrictPickerCard(
                            selectedDistricts: profile.preferredDistricts,
                            primaryDistrict: profile.district,
                            districts: profileDistrictOptions(for: coveredCity)
                        )
                    } else {
                        ProfileEmbeddedLightCard(
                            title: L10n.string("Districts", "Районы"),
                            subtitle: L10n.string("For \(profile.wrappedValue.city ?? "this city"), we'll use the selected radius and distance for now.", "Для \(profile.wrappedValue.city ?? "этого города") пока используем выбранный радиус и расстояние до места.")
                        ) {
                            Label(L10n.string("City districts will be added gradually", "Районы города добавим постепенно"), systemImage: "map")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink.opacity(0.62))
                        }
                    }

                    ProfileEmbeddedLightCard(title: L10n.string("Search radius", "Радиус поиска"), subtitle: L10n.string("If districts are unavailable, distance becomes the main signal.", "Если районов нет, расстояние станет главным сигналом.")) {
                        FieldShell(title: L10n.string("\(profile.wrappedValue.searchRadiusKm) km", "\(profile.wrappedValue.searchRadiusKm) км")) {
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
            title: L10n.string("Notifications", "Уведомления"),
            subtitle: L10n.string("Only events that require your attention or response.", "Оставляем только события, где тебе нужно увидеть действие или ответ."),
            systemImage: "bell.badge",
            tint: Color.yellow,
            onSave: { await save(successMessage: L10n.string("Notification settings saved", "Настройки уведомлений сохранены")) }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: "Push", value: notificationManager.authorizationStatus.title, icon: "bell.badge"),
                        .init(title: L10n.string("Events", "Событий"), value: "\(enabledNotificationCount(for: profile.wrappedValue))/3", icon: "checklist")
                    ])

                    ProfileEmbeddedLightCard(title: L10n.string("System access", "Системный доступ"), subtitle: L10n.string("Without iOS permission, notifications won't appear on the Lock Screen.", "Без разрешения iOS уведомления не появятся на заблокированном экране.")) {
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

                    ProfileEmbeddedLightCard(title: L10n.string("Events", "События"), subtitle: L10n.string("Actual notifications only, not profile settings.", "Здесь только реальные уведомления, а не настройки профиля.")) {
                        ToggleCard(title: L10n.string("New matches", "Новые мэтчи"), subtitle: L10n.string("Notify me when there is mutual interest.", "Сообщать, когда появляется взаимный интерес."), isOn: profile.notificationMatches)
                        ToggleCard(title: L10n.string("Messages", "Сообщения"), subtitle: L10n.string("Show new chat messages and replies.", "Показывать новые сообщения и ответы в чате."), isOn: profile.notificationMessages)
                        ToggleCard(title: L10n.string("Games and invitations", "Игры и предложения"), subtitle: L10n.string("Responses, confirmations, cancellations, and game updates.", "Отклики, подтверждения, отмены и изменения игр."), isOn: profile.notificationGames)
                    }

                    ProfileEmbeddedLightCard(title: L10n.string("Sound", "Звук"), subtitle: L10n.string("Controls notification sounds separately.", "Отдельно регулирует звуковой сигнал внутри приложения.")) {
                        ToggleCard(title: L10n.string("Notification sounds", "Звуковые сигналы"), subtitle: L10n.string("Play the system notification sound.", "Воспроизводить звук системного уведомления."), isOn: profile.notificationSound)
                    }
                }
            }
        }
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
    }

    private func profileEditor(for profile: Binding<UserProfile>, initialTitle: String = L10n.string("Edit profile", "Редактировать профиль")) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(initialTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 12)

                    SectionCard(title: L10n.string("Player profile", "Карточка игрока"), subtitle: L10n.string("Basic information visible to other players.", "Основные данные, которые видят другие игроки.")) {
                        basicsSection(for: profile)
                        profileVisibilitySection(for: profile)
                    }

                    SectionCard(title: L10n.string("Sports", "Виды спорта"), subtitle: L10n.string("Choose a sport and set your level.", "Выбери спорт и сразу настрой уровень.")) {
                        AppSportSelectionGrid(
                            title: L10n.string("Sports profile", "Спортивный профиль"),
                            sports: Sport.allCases,
                            selectedSports: profile.preferredSports,
                            levels: profile.sportLevels
                        )
                    }

                    SectionCard(title: L10n.string("Availability", "Доступность"), subtitle: L10n.string("Days and times when you can play.", "Дни и окна времени, когда удобно играть.")) {
                        AppAvailabilityWeekEditor(availabilityByDay: profile.availabilityByDay)
                        availabilitySummary(for: profile.wrappedValue.availabilityByDay)
                    }

                    HStack(spacing: 12) {
                        Button(L10n.string("Save profile", "Сохранить профиль")) {
                            Task {
                                if await save() {
                                    isEditorPresented = false
                                }
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.court))

                        Button(L10n.string("Sign out", "Выйти")) {
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
        FieldShell(title: L10n.string("Name", "Имя")) {
            TextField(L10n.string("Anna", "Анна"), text: profile.name.orEmpty)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }

        FieldShell(title: L10n.string("Age", "Возраст")) {
            Stepper(value: Binding(
                get: { profile.age.wrappedValue ?? 25 },
                set: { profile.age.wrappedValue = $0 }
            ), in: 18 ... 100) {
                Text("\(profile.age.wrappedValue ?? 25)")
                    .font(.headline)
            }
        }

        FieldShell(title: L10n.string("Gender", "Пол")) {
            Picker(L10n.string("Gender", "Пол"), selection: profile.gender) {
                Text(L10n.string("Prefer not to say", "Не указывать")).tag(Optional<Gender>.none)
                ForEach(Gender.allCases) { gender in
                    Text(gender.title).tag(Optional(gender))
                }
            }
            .pickerStyle(.menu)
        }

        FieldShell(title: L10n.string("City", "Город")) {
            profileLocationButton(profile.wrappedValue)
        }

        if profileDistrictsEnabled(profile.wrappedValue) {
            FieldShell(title: L10n.string("District", "Район")) {
                TextField(L10n.string("For example: Central", "Например: Приморский"), text: profile.district.orEmpty)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
        }

        FieldShell(title: L10n.string("About me", "О себе"), caption: L10n.string("Briefly describe yourself or who you'd like to play with.", "Коротко опиши себя или с кем хочешь играть.")) {
            TextField(
                L10n.string("I enjoy intense rallies and evening practice.", "Люблю интенсивные розыгрыши и вечерние тренировки."),
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
        ProfileMapVisibilityControl(isOn: profile.showOnMap)
        ToggleCard(title: L10n.string("Looking for a game now", "Ищу игру сейчас"), subtitle: L10n.string("Show you in active player recommendations.", "Показывать тебя в активной подборке игроков."), isOn: profile.isLookingForGame)
    }

    @ViewBuilder
    private var notificationAuthorizationButton: some View {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            Button(L10n.string("Allow", "Разрешить")) {
                Task { await notificationManager.requestAuthorization() }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
        case .denied:
            Button(L10n.string("Settings", "Настройки")) {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(settingsURL)
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
        default:
            Button(L10n.string("Check", "Проверить")) {
                Task { await notificationManager.refreshAuthorizationStatus() }
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
        }
    }

    private var notificationAuthorizationHint: String {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            return L10n.string("Allow push notifications to receive messages and game updates outside the app.", "Разреши push-уведомления, чтобы получать сообщения и действия по играм вне приложения.")
        case .denied:
            return L10n.string("Notifications are disabled in iOS Settings. Enable them manually.", "Уведомления отключены в настройках iOS. Их нужно включить вручную.")
        case .authorized, .provisional, .ephemeral:
            return L10n.string("System access is enabled. Configure event types below.", "Системный доступ включён. Типы событий можно настроить ниже.")
        @unknown default:
            return L10n.string("We couldn't determine the permission status. Check iOS Settings.", "Не удалось точно определить статус доступа. Проверь настройки iOS.")
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
            FieldShell(title: L10n.string("Name", "Имя")) {
                TextField(L10n.string("Anna", "Анна"), text: $guestDraft.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            FieldShell(title: L10n.string("Age", "Возраст")) {
                Stepper(value: $guestDraft.age, in: 18 ... 100) {
                    Text("\(guestDraft.age)")
                        .font(.headline)
                }
            }

            FieldShell(title: L10n.string("Gender", "Пол")) {
                Picker(L10n.string("Gender", "Пол"), selection: $guestDraft.gender) {
                    Text(L10n.string("Prefer not to say", "Не указывать")).tag(Optional<Gender>.none)
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
            FieldShell(title: L10n.string("Search radius", "Радиус поиска"), caption: L10n.string("\(guestDraft.searchRadiusKm) km", "\(guestDraft.searchRadiusKm) км")) {
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

            ToggleCard(title: L10n.string("Looking for a game now", "Ищу игру сейчас"), subtitle: L10n.string("Show this draft in guest recommendations.", "Показывать черновик в гостевой подборке."), isOn: $guestDraft.isLookingForGame)
        }
    }

    @ViewBuilder
    private func availabilitySummary(for availabilityByDay: [String: [String]]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Summary", "Итог"))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.8)
                .foregroundStyle(AppTheme.court)

            if availabilityByDay.isEmpty {
                AppInlineChip(text: L10n.string("Not set yet", "Пока не указано"), tint: AppTheme.cream, foreground: AppTheme.ink)
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

    private var profileGameFeedItems: [ProfileGameFeedItem] {
        guard let ownerID = appModel.currentUser?.id, gameFeedAccountID == ownerID else { return [] }
        return ProfileGameFeedItem.make(games: gameFeedRequests, visits: gameFeedVisits, ownerID: ownerID)
    }

    @MainActor
    private func resetProfileGameFeed() {
        gameFeedRequestToken = nil
        visitFeedRequestToken = nil
        gameFeedAccountID = appModel.currentUser?.id
        gameFeedRequests = []
        gameFeedVisits = []
        gameFeedError = nil
        visitFeedError = nil
        isGameFeedLoading = false
        isVisitFeedLoading = false
    }

    @MainActor
    private func loadProfileGameFeed(source: ProfileGameFeedSource? = nil) async {
        guard appModel.isAuthenticated, let accountID = appModel.currentUser?.id else {
            resetProfileGameFeed()
            return
        }
        if gameFeedAccountID != accountID { resetProfileGameFeed() }
        if let source {
            switch source {
            case .games: await loadProfileGames(accountID: accountID)
            case .visits: await loadProfileVisits(accountID: accountID)
            }
        } else {
            async let games: Void = loadProfileGames(accountID: accountID)
            async let visits: Void = loadProfileVisits(accountID: accountID)
            _ = await (games, visits)
        }
    }

    @MainActor
    private func loadProfileGames(accountID: String) async {
        guard !Task.isCancelled, !isGameFeedLoading,
              gameFeedAccountID == accountID, appModel.currentUser?.id == accountID,
              appModel.isAuthenticated else { return }
        let token = UUID()
        gameFeedRequestToken = token
        isGameFeedLoading = true
        gameFeedError = nil
        defer {
            if gameFeedRequestToken == token { isGameFeedLoading = false }
        }
        do {
            let requests = try await appModel.repository.fetchMyGameRequests()
            guard !Task.isCancelled, gameFeedRequestToken == token,
                  gameFeedAccountID == accountID, appModel.currentUser?.id == accountID,
                  appModel.isAuthenticated else { return }
            gameFeedRequests = requests
        } catch {
            guard !error.isCancellationLike, gameFeedRequestToken == token,
                  gameFeedAccountID == accountID, appModel.currentUser?.id == accountID,
                  appModel.isAuthenticated else { return }
            gameFeedError = L10n.string("Could not refresh games. Try again.", "Не удалось обновить игры. Попробуй ещё раз.")
        }
    }

    @MainActor
    private func loadProfileVisits(accountID: String) async {
        guard !Task.isCancelled, !isVisitFeedLoading,
              gameFeedAccountID == accountID, appModel.currentUser?.id == accountID,
              appModel.isAuthenticated else { return }
        let token = UUID()
        visitFeedRequestToken = token
        isVisitFeedLoading = true
        visitFeedError = nil
        defer {
            if visitFeedRequestToken == token { isVisitFeedLoading = false }
        }
        do {
            let visits = try await appModel.repository.fetchPersonalActivities()
            guard !Task.isCancelled, visitFeedRequestToken == token,
                  gameFeedAccountID == accountID, appModel.currentUser?.id == accountID,
                  appModel.isAuthenticated else { return }
            gameFeedVisits = visits
        } catch {
            guard !error.isCancellationLike, visitFeedRequestToken == token,
                  gameFeedAccountID == accountID, appModel.currentUser?.id == accountID,
                  appModel.isAuthenticated else { return }
            visitFeedError = L10n.string("Could not refresh personal visits. Try again.", "Не удалось обновить личные визиты. Попробуй ещё раз.")
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
    private func save(successMessage: String = L10n.string("Profile saved", "Профиль сохранён")) async -> Bool {
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
            appModel.errorMessage = L10n.string("Could not read the selected photo", "Не удалось прочитать выбранное фото")
            selectedAvatarItem = nil
            return
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.88) else {
            appModel.errorMessage = L10n.string("Could not prepare the photo for upload", "Не удалось подготовить фото к загрузке")
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
            showSaveToast(L10n.string("Photo updated", "Фото обновлено"))
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
            showSaveToast(preferredKind == .video ? L10n.string("Video added", "Видео добавлено") : L10n.string("Photo added", "Фото добавлено"))
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
            guard let pickedVideo = try await item.loadTransferable(type: ProfilePickedVideo.self) else {
                throw APIError.invalidPayload(L10n.string("Could not read the selected video", "Не удалось прочитать выбранное видео"))
            }

            let sourceURL = pickedVideo.url
            let asset = AVURLAsset(url: sourceURL)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))

            guard duration.isFinite, duration > 0 else {
                throw APIError.invalidPayload(L10n.string("Could not determine the video duration", "Не удалось определить длительность видео"))
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
            showSaveToast(L10n.string("Video added", "Видео добавлено"))
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
            throw APIError.invalidPayload(L10n.string("Could not prepare the video for trimming", "Не удалось подготовить видео к обрезке"))
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
                    continuation.resume(throwing: exportSession.error ?? APIError.invalidPayload(L10n.string("Could not trim the video", "Не удалось обрезать видео")))
                default:
                    continuation.resume(throwing: APIError.invalidPayload(L10n.string("Could not trim the video", "Не удалось обрезать видео")))
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
            throw APIError.invalidPayload(L10n.string("Could not read the selected file", "Не удалось прочитать выбранный файл"))
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
                showSaveToast(item.kind == .video ? L10n.string("Video removed", "Видео удалено") : L10n.string("Photo removed", "Фото удалено"))
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
        let coveredCity = SupportedCity.resolve(profile.city)
        let hasConfirmedCity = profile.location != nil
            || coveredCity.map(SupportedCity.selectableCases.contains) == true
        let hasDistrict = profile.district?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || !profile.preferredDistricts.isEmpty
        let hasLevels = !profile.preferredSports.isEmpty && profile.preferredSports.allSatisfy { sport in
            profile.sportLevels[sport.rawValue] != nil || (sport == .tennis && profile.tennisLevel != nil)
        }
        let hasAvailability = profile.availabilityByDay.values.contains { !$0.isEmpty }
        let hasPhoto = profile.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || !profile.profilePhotoUrls.isEmpty

        var requirements: [(isComplete: Bool, step: String)] = [
            (profile.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, L10n.string("Add your name", "Добавьте имя")),
            (profile.age != nil, L10n.string("Add your age", "Укажите возраст")),
            (hasConfirmedCity, L10n.string("Choose a city", "Выберите город")),
            (hasPhoto, L10n.string("Add a main photo", "Добавьте основное фото")),
            (!profile.preferredSports.isEmpty, L10n.string("Choose at least one sport", "Выберите хотя бы один вид спорта")),
            (hasLevels, L10n.string("Set a level for your selected sports", "Укажите уровень для выбранных видов спорта")),
            (hasAvailability, L10n.string("Add convenient days and times", "Отметьте удобные дни и время")),
            (profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, L10n.string("Tell others about yourself", "Расскажите о себе"))
        ]

        if profileDistrictsEnabled(profile), coveredCity == .saintPetersburg {
            requirements.append((hasDistrict, L10n.string("Choose a district", "Выберите район Санкт-Петербурга")))
        }

        let completedCount = requirements.filter(\.isComplete).count
        let percent = Int((Double(completedCount) / Double(requirements.count) * 100).rounded())
        return ProfileCompletionStatus(
            percent: percent,
            missingSteps: requirements.filter { !$0.isComplete }.map(\.step)
        )
    }

    private func sportsSummary(for profile: UserProfile) -> String {
        guard !profile.preferredSports.isEmpty else { return L10n.string("No sports selected yet", "Виды спорта ещё не выбраны") }
        return L10n.string("\(profile.preferredSports.count) sports and levels", "\(profile.preferredSports.count) вида спорта и уровни")
    }

    private func playLocationSummary(for profile: UserProfile) -> String {
        let districts = profile.preferredDistricts.isEmpty ? [profile.district].compactMap { $0 } : profile.preferredDistricts
        guard !districts.isEmpty else { return L10n.string("Districts and favorite clubs are not set", "Районы и любимые клубы не указаны") }
        return L10n.string("\(districts.count) districts, favorite clubs", "\(districts.count) района, любимые клубы")
    }

    private func activitySummary(for profile: UserProfile) -> String {
        profile.isLookingForGame ? L10n.string("Looking for a game now", "Ищешь игру сейчас") : L10n.string("No active searches", "Активных поисков нет")
    }

    private func notificationsSummary(for profile: UserProfile) -> String {
        let enabled = enabledNotificationCount(for: profile)
        guard enabled > 0 else { return L10n.string("All events are disabled", "Все события выключены") }
        return L10n.string("\(enabled) of 3 events, sound \(profile.notificationSound ? "on" : "off")", "\(enabled) из 3 событий, звук \(profile.notificationSound ? "включён" : "выключен")")
    }

    private func enabledNotificationCount(for profile: UserProfile) -> Int {
        [profile.notificationMatches, profile.notificationMessages, profile.notificationGames].filter { $0 }.count
    }

    private func availabilityHeadline(for availabilityByDay: [String: [String]]) -> String {
        guard !availabilityByDay.isEmpty else { return L10n.string("Play time is not set", "Время игры не указано") }
        let ranges = Set(availabilityByDay.values.flatMap { $0 }).compactMap { TimeRange(rawValue: $0)?.title.lowercased() }
        let daysCount = availabilityByDay.filter { !$0.value.isEmpty }.count
        return L10n.string("\(daysCount) days, \(ranges.sorted().joined(separator: ", "))", "\(daysCount) дней, \(ranges.sorted().joined(separator: ", "))")
    }

    private func profileDistrictOptions(for city: SupportedCity) -> [String] {
        districtAreasByID.values
            .filter { $0.city == city }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            .map(\.id)
    }

    private func profileDistrictsEnabled(_ profile: UserProfile) -> Bool {
        if profile.location != nil {
            return profile.coverage.districtsEnabled
        }
        guard let city = SupportedCity.resolve(profile.city) else { return false }
        return SupportedCity.selectableCases.contains(city)
    }

    private func applyProfileLocation(_ place: GeoPlace, source: LocationSource) {
        guard var current = draft else { return }
        let didChangePlace = current.location?.id != place.id
            || (current.location == nil && current.city?.localizedCaseInsensitiveCompare(place.city) != .orderedSame)
        current.location = place
        current.coverage = place.coverage
        current.locationSource = source
        current.city = place.coverage.legacyCity ?? place.city
        if didChangePlace {
            current.district = nil
            current.preferredDistricts.removeAll()
        }
        draft = current
        appModel.considerLocaleRecommendation(for: place)
    }

    private func profileLocationButton(_ profile: UserProfile) -> some View {
        NavigationLink {
            GlobalLocationPickerSheet(
                repository: appModel.repository,
                initialLocation: profile.location,
                automaticallyRequestsLocation: false,
                onSelect: applyProfileLocation
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe.europe.africa.fill")
                    .foregroundStyle(AppTheme.court)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.location?.city ?? profile.city ?? L10n.string("Choose country and city", "Выбрать страну и город"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    if let country = profile.location?.localizedCountryName {
                        Text(country)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.56))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.42))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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
            .init(title: L10n.string("Days", "Дней"), value: "\(selectedDays)", icon: "calendar"),
            .init(title: L10n.string("Windows", "Окна"), value: windows.isEmpty ? L10n.string("Empty", "Пусто") : windows, icon: "clock"),
            .init(title: L10n.string("Slots", "Слотов"), value: "\(availabilityByDay.values.reduce(0) { $0 + $1.count })", icon: "checklist")
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
                            Text(L10n.string("Save", "Сохранить"))
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

private struct ProfileLanguageSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var localeStore: LocaleStore

    private var isRussian: Bool { localeStore.effectiveLocale == .ru }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                ProfileSubscreenHeader(title: "Language / Язык", onBack: { dismiss() })

                Text(isRussian
                     ? "Язык интерфейса можно выбрать независимо от страны и города."
                     : "You can choose the interface language independently of your country and city.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))

                ProfileDarkPanel {
                    VStack(spacing: 10) {
                        ForEach(AppLocale.allCases) { locale in
                            Button {
                                appModel.setManualLocale(locale)
                                AppHaptics.selection()
                            } label: {
                                HStack {
                                    Text(locale.displayName)
                                        .font(.headline.weight(.bold))
                                    Spacer()
                                    if localeStore.effectiveLocale == locale {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.court)
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 52)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                ProfileSubscreenHeader(title: L10n.string("Account", "Аккаунт"), onBack: { dismiss() })

                ProfileDarkPanel {
                    VStack(spacing: 0) {
                        ProfileInfoLine(title: L10n.string("Email", "Почта"), value: email ?? L10n.string("Not provided", "Не указана"))
                        ProfileInfoLine(title: L10n.string("Status", "Статус"), value: isVerified ? L10n.string("Verified", "Подтверждён") : L10n.string("Not verified", "Не подтверждён"))
                    }
                }

                Button(L10n.string("Sign out", "Выйти")) {
                    onLogout()
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .white))

                Button(L10n.string("Delete profile", "Удалить профиль")) {
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
            Label(L10n.string("Schedule summary", "Итог расписания"), systemImage: "calendar.badge.checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            if availabilityByDay.isEmpty {
                Text(L10n.string("Availability is not set yet. Recommendations will rely less on your schedule.", "Доступность пока не указана. Подбор будет меньше учитывать расписание."))
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
        ProfileEmbeddedLightCard(title: L10n.string("Preferred districts", "Предпочтительные районы"), subtitle: L10n.string("The first selected district becomes your primary district.", "Первый выбранный район станет основным для профиля.")) {
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
                    Label(L10n.string("Clear districts", "Сбросить районы"), systemImage: "xmark.circle")
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

/// Выбранное видео приходит файлом, а не `Data`: пятиминутный ролик весит
/// сотни мегабайт, и читать его в память целиком ради 10-секундного фрагмента
/// незачем — редактор и экспорт работают с файлом напрямую.
private struct ProfilePickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("profile-video-source-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            // Файл пикера живёт только до конца замыкания. Копия в пределах
            // одного тома APFS — клон, она не зависит от длины ролика.
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ProfilePickedVideo(url: destination)
        }
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
                        Text(L10n.string("Trim video", "Обрезать видео"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text(L10n.string("Choose a clip up to 10 seconds", "Выберите фрагмент до 10 секунд"))
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
                        Text(L10n.string("\(Int(ceil(selectedDuration))) sec", "\(Int(ceil(selectedDuration))) сек"))
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

                    Text(maxStartTime <= 0 ? L10n.string("The video is under 10 seconds and can be uploaded in full.", "Видео короче 10 секунд, можно загрузить целиком.") : L10n.string("Move the slider to choose the start of the 10-second clip.", "Передвиньте шкалу, чтобы выбрать начало 10-секундного фрагмента."))
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
                        Text(isProcessing ? L10n.string("Preparing video...", "Готовим видео...") : L10n.string("Use clip", "Использовать фрагмент"))
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
                    title: L10n.string("Uploading video", "Видео загружается"),
                    subtitle: L10n.string("Saving the selected clip to your profile.", "Сохраняем выбранный фрагмент в карточку.")
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
                        Text(mode.title)
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
                Text(L10n.string("Profile in Similar players", "Карточка в «Похожих игроках»"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(L10n.string("Only information from your profile is shown", "Показаны только данные из вашего профиля"))
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

            Label(L10n.string("Preview: swipes and actions are disabled", "Предпросмотр: свайпы и действия отключены"), systemImage: "eye.fill")
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
                                ProfileCapsule(text: L10n.string("Looking for a game", "Ищу игру"), tint: AppTheme.court)
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

                        Text(profile.bio ?? L10n.string("Add a few lines about yourself and short practice videos.", "Добавь пару строк о себе и короткие видео с тренировок."))
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
                    Label(L10n.string("QR profile", "QR-профиль"), systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProfileSoftButtonStyle())
            }
        }
    }

    private func profileAgeCityLine(_ profile: UserProfile) -> String {
        var parts: [String] = []
        if let age = profile.age {
            parts.append(L10n.string("\(age) years old", "\(age) лет"))
        }
        parts.append(profile.city ?? L10n.string("City not selected", "Город не выбран"))
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
                        Text(L10n.string("Your profile", "Ваш профиль"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(L10n.string("Basic information and media", "Основные данные и медиа"))
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
                    .accessibilityLabel(L10n.string("Edit profile", "Редактировать профиль"))
                }

                PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileHeroImage(
                            name: profile.displayName,
                            path: profile.profileHeroImagePath,
                            height: 264
                        )

                        Label(L10n.string("Main photo", "Основное фото"), systemImage: "camera.fill")
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
                        Text(L10n.string("No sports selected yet", "Виды спорта пока не выбраны"))
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
                    mediaHeader

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
                                    ProfileAddMediaTile(title: L10n.string("Photo", "Фото"), systemImage: "camera.fill")
                                }
                                .buttonStyle(.plain)
                                .disabled(isUploading || isUploadingAvatar)
                            }

                            if remainingVideoSlots > 0 {
                                // `.current` отдаёт ролик как есть: без него система сперва
                                // перекодирует весь HEVC-файл в совместимый формат, и пятиминутное
                                // видео готовится минутами ради 10-секундного фрагмента.
                                PhotosPicker(
                                    selection: $selectedVideoItems,
                                    maxSelectionCount: remainingVideoSlots,
                                    matching: .videos,
                                    preferredItemEncoding: .current,
                                    photoLibrary: .shared()
                                ) {
                                    ProfileAddMediaTile(title: L10n.string("Video up to 10 sec", "Видео до 10 сек"), systemImage: "play.rectangle.fill")
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
            ProfileCapsule(text: L10n.string("Looking for a game", "Ищу игру"), tint: AppTheme.court)
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
        return parts.isEmpty ? L10n.string("City and district are not set", "Город и район не указаны") : parts.joined(separator: " · ")
    }

    private var profileBioText: String {
        guard let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty else {
            return L10n.string("Description is not filled in yet", "Описание пока не заполнено")
        }
        return bio
    }

    private var mediaTitle: some View {
        Text(L10n.string("Photos and videos", "Фото и видео"))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var mediaHeader: some View {
        if profile.profileVideoUrls.isEmpty {
            mediaTitle
        } else {
            ViewThatFits(in: .horizontal) {
                HStack {
                    mediaTitle
                    Spacer()
                    videoAddedLabel
                }

                VStack(alignment: .leading, spacing: 4) {
                    mediaTitle
                    videoAddedLabel
                }
            }
        }
    }

    private var videoAddedLabel: some View {
        Label(L10n.string("Video added", "Видео добавлено"), systemImage: "checkmark.circle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.mint)
    }
}

private struct ProfileHeroImage: View {
    let name: String
    let path: String?
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            RemoteImage(url: resolveAppRemoteURL(path)) { _ in
                fallback
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
                .accessibilityLabel(item.kind == .video ? L10n.string("Remove video", "Удалить видео") : L10n.string("Remove photo", "Удалить фото"))
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
            RemoteLoopingVideo(url: url, indicator: .shimmer) {
                tileFallback(showsIcon: false)
            }
        } else if item.kind == .photo, let url = resolveAppRemoteURL(item.path) {
            RemoteImage(url: url) { phase in
                tileFallback(showsIcon: phase != .loading)
            }
        } else {
            tileFallback(showsIcon: true)
        }
    }

    private func tileFallback(showsIcon: Bool) -> some View {
        LinearGradient(
            colors: [AppTheme.court.opacity(0.28), Color.white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            if showsIcon {
                Image(systemName: item.kind == .video ? "play.rectangle.fill" : "photo.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
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
            Text(L10n.string("Add well-lit photos and short videos from games or practice.", "Добавьте фото в хорошем освещении и короткие видео с игры или тренировки."))
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
                        Text(L10n.string("Profile completion", "Заполненность профиля"))
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
                    Label(L10n.string("All required steps are complete", "Все обязательные шаги выполнены"), systemImage: "checkmark.circle.fill")
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
                    hasVideoBonus ? L10n.string("Video added as a profile bonus", "Видео добавлено как бонус к карточке") : L10n.string("Video is a bonus and does not affect completion", "Видео: бонус, который не влияет на заполненность"),
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
            return L10n.string("Profile is ready to be shown", "Профиль готов к показу")
        }
        return L10n.string("Steps remaining: \(missingSteps.count)", "Осталось шагов: \(missingSteps.count)")
    }
}

private struct ProfileGameFeedSection: View {
    let items: [ProfileGameFeedItem]
    let currentUserId: String?
    let isLoading: Bool
    let gameError: String?
    let visitError: String?
    let onRetryGames: () -> Void
    let onRetryVisits: () -> Void
    @State private var selectedGallery: ReportPhotoGalleryItem?

    var body: some View {
        ProfileDarkPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("Game feed", "Лента игр"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(L10n.string("Games and your personal visit reports", "Игры и фотоотчёты твоих личных визитов"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().tint(.white)
                    } else if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.court)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppTheme.court.opacity(0.14), in: Capsule())
                    }
                }

                if let gameError { sourceError(gameError, onRetry: onRetryGames, identifier: "profile-feed-retry-games") }
                if let visitError { sourceError(visitError, onRetry: onRetryVisits, identifier: "profile-feed-retry-visits") }

                if items.isEmpty && !isLoading && gameError == nil && visitError == nil {
                    Text(L10n.string("Completed games and photo reports from your personal visits will appear here.", "Здесь появятся завершённые игры и фотоотчёты твоих личных визитов."))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        ProfileGameFeedRow(item: item, currentUserId: currentUserId) { selectedGallery = $0 }
                    }
                }
            }
        }
        .accessibilityIdentifier("profile-game-feed")
        .sheet(item: $selectedGallery) { ReportPhotoGallerySheet(item: $0) }
    }

    private func sourceError(_ message: String, onRetry: @escaping () -> Void, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.caption).foregroundStyle(.white.opacity(0.75))
            Button(L10n.string("Try again", "Повторить"), action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.court)
                .frame(minHeight: 44)
                .disabled(isLoading)
                .accessibilityIdentifier(identifier)
        }
    }
}

private struct ProfileGameFeedRow: View {
    let item: ProfileGameFeedItem
    let currentUserId: String?
    let onOpenGallery: (ReportPhotoGalleryItem) -> Void

    private var sport: Sport {
        switch item {
        case .game(let request): return request.sport
        case .visit(let activity): return activity.sport
        }
    }

    private var photoPaths: [String] {
        switch item {
        case .game(let request): return request.report?.photoUrls ?? []
        case .visit(let activity): return activity.photoUrls
        }
    }

    private var dateTitle: String {
        switch item {
        case .game(let request): return request.proposedDatetime.formattedDateTime()
        case .visit(let activity): return activity.scheduledAt.formattedDateTime()
        }
    }

    private var details: String {
        switch item {
        case .game(let request):
            return [request.proposedCourt?.name, request.participantNamesLine(currentUserId: currentUserId)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .visit(let activity):
            return [L10n.string("Personal visit", "Личный визит"), activity.court?.name]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var statusTitle: String {
        switch item {
        case .game(let request): return request.report?.statusTitle ?? request.outcomeLabel ?? ""
        case .visit: return L10n.string("Visit photo report", "Фотоотчёт визита")
        }
    }

    private var statusColor: Color {
        switch item {
        case .game(let request):
            if let report = request.report, report.status.lowercased() != "confirmed" { return .orange }
            return AppTheme.court
        case .visit: return AppTheme.court
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProfileGameFeedPreview(allPhotoPaths: photoPaths, sport: sport, onOpenPhoto: openPhoto)
            Button { openPhoto(0) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        SportIconView(sport: sport, color: AppTheme.court, size: 16)
                        Text("\(sport.title) · \(dateTitle)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                    Text(details)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                    Text(statusTitle).font(.caption.weight(.bold)).foregroundStyle(statusColor)
                    if !photoPaths.isEmpty {
                        Label(L10n.string("\(photoPaths.count) photos", "\(photoPaths.count) фото"), systemImage: "photo.stack")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(photoPaths.isEmpty)
            .accessibilityHint(photoPaths.isEmpty ? "" : L10n.string("Opens the photo report", "Открывает фотоотчёт"))
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
        .accessibilityIdentifier("profile-feed-\(item.id)")
    }

    private func openPhoto(_ index: Int) {
        guard !photoPaths.isEmpty else { return }
        let comment: String?
        switch item {
        case .game(let request): comment = request.report?.comment
        case .visit(let activity): comment = activity.reportComment
        }
        onOpenGallery(ReportPhotoGalleryItem(
            photoPaths: photoPaths,
            initialIndex: index,
            title: L10n.string("Photo report", "Фотоотчёт"),
            subtitle: "\(sport.title) · \(dateTitle) · \(statusTitle)",
            comment: comment
        ))
    }
}

private struct ProfileGameFeedPreview: View {
    let allPhotoPaths: [String]
    let sport: Sport
    let onOpenPhoto: (Int) -> Void

    private var photoPaths: [String] { Array(allPhotoPaths.prefix(4)) }
    private var extraPhotoCount: Int { max(allPhotoPaths.count - 4, 0) }

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
                photoTile(path: photoPaths[0], index: 0, showsMoreOverlay: false)
            case 2:
                HStack(spacing: gap) {
                    photoTile(path: photoPaths[0], index: 0, showsMoreOverlay: false)
                        .frame(width: halfWidth, height: geometry.size.height)
                    photoTile(path: photoPaths[1], index: 1, showsMoreOverlay: extraPhotoCount > 0)
                        .frame(width: halfWidth, height: geometry.size.height)
                }
            case 3:
                HStack(spacing: gap) {
                    photoTile(path: photoPaths[0], index: 0, showsMoreOverlay: false)
                        .frame(width: halfWidth, height: geometry.size.height)
                    VStack(spacing: gap) {
                        photoTile(path: photoPaths[1], index: 1, showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                        photoTile(path: photoPaths[2], index: 2, showsMoreOverlay: extraPhotoCount > 0)
                            .frame(width: halfWidth, height: halfHeight)
                    }
                }
            default:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        photoTile(path: photoPaths[0], index: 0, showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                        photoTile(path: photoPaths[1], index: 1, showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                    }
                    HStack(spacing: gap) {
                        photoTile(path: photoPaths[2], index: 2, showsMoreOverlay: false)
                            .frame(width: halfWidth, height: halfHeight)
                        photoTile(path: photoPaths[3], index: 3, showsMoreOverlay: extraPhotoCount > 0)
                            .frame(width: halfWidth, height: halfHeight)
                    }
                }
            }
        }
    }

    private func photoTile(path: String, index: Int, showsMoreOverlay: Bool) -> some View {
        Button { onOpenPhoto(index) } label: {
        ZStack {
            RemoteImage(url: resolveAppRemoteURL(path), indicator: .shimmer(AppTheme.court.opacity(0.4))) { phase in
                if phase != .loading {
                    fallbackIcon
                }
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
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("Open photo \(index + 1) of \(allPhotoPaths.count)", "Открыть фото \(index + 1) из \(allPhotoPaths.count)"))
    }
}

private struct QRProfileView: View {
    let profile: UserProfile
    let visibilityMode: ProfileVisibilityMode
    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?

    private var profileURL: String {
        AppConfig.profileURL(userID: profile.id).absoluteString
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    ProfileSubscreenHeader(title: L10n.string("QR profile", "QR-профиль"), onBack: { dismiss() })

                    ProfileDarkPanel {
                        VStack(spacing: 20) {
                            Text(L10n.string("Show this code to share your profile", "Покажи этот код, чтобы поделиться своим профилем"))
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

                            Label(L10n.string("The QR code opens only your public profile. Personal data is not shown.", "По QR откроется только публичная карточка. Личные данные не показываются."), systemImage: "checkmark.shield")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ProfileMenuGroup {
                        ProfileActionRow(icon: "link", title: L10n.string("Share link", "Поделиться ссылкой")) {
                            UIPasteboard.general.string = profileURL
                            AppHaptics.notification(.success)
                            showToast(L10n.string("Link copied", "Ссылка скопирована"))
                        }

                        ProfileActionRow(icon: "square.and.arrow.down", title: L10n.string("Save QR", "Сохранить QR")) {
                            AppHaptics.selection()
                            showToast(L10n.string("QR is ready to save", "QR готов к сохранению"))
                        }

                        ShareLink(item: profileURL) {
                            ProfileMenuRow(icon: "square.and.arrow.up", tint: .white.opacity(0.72), title: L10n.string("Share", "Поделиться"), subtitle: nil)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            VisibilitySettingsView(selectionRaw: .constant(visibilityMode.rawValue))
                        } label: {
                            ProfileMenuRow(icon: "eye", tint: .white.opacity(0.72), title: L10n.string("Visibility settings", "Настроить видимость"), subtitle: visibilityMode.title)
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
                ProfileSubscreenHeader(title: L10n.string("Visibility settings", "Настройки видимости"), onBack: { dismiss() })

                Text(L10n.string("Choose what is visible in your public profile", "Выбери, что будет видно в твоём публичном профиле"))
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
                    Label(L10n.string("You can change visibility settings at any time.", "В любой момент можно изменить настройки видимости."), systemImage: "info.circle")
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
                Text(profile.age.map { L10n.string("\($0) years old · \(profile.city ?? "City not selected")", "\($0) лет · \(profile.city ?? "Город не выбран")") } ?? (profile.city ?? L10n.string("City not selected", "Город не выбран")))
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
            return L10n.string("Public profile", "Публичный профиль")
        case .limitedProfile:
            return L10n.string("Limited profile", "Ограниченный профиль")
        }
    }

    var description: String {
        switch self {
        case .publicProfile:
            return L10n.string("Show photos, sport, level, district, and bio. Best for finding new players.", "Показывать фото, спорт, уровень, район и описание. Подходит для поиска новых игроков.")
        case .limitedProfile:
            return L10n.string("Show only name, sport, and city. More privacy with fewer details.", "Показывать только имя, спорт и город. Больше приватности — меньше деталей.")
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
            return L10n.string("Table tennis", "Наст. теннис")
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
                Text(L10n.string("Saved successfully", "Успешно сохранено"))
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
