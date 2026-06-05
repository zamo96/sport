import SwiftUI
import PhotosUI
import CoreImage.CIFilterBuiltins
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var draft: UserProfile?
    @State private var guestDraft: GuestOnboardingDraft = .default
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var saveToastMessage: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var isEditorPresented = false
    @AppStorage("profile.visibilityMode") private var visibilityModeRaw = ProfileVisibilityMode.publicProfile.rawValue

    private var visibilityMode: ProfileVisibilityMode {
        ProfileVisibilityMode(rawValue: visibilityModeRaw) ?? .publicProfile
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if let saveToastMessage {
                InlineStatusToast(message: saveToastMessage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            if draft == nil {
                draft = appModel.currentUser
            }
            guestDraft = appModel.guestDraft
            await notificationManager.refreshAuthorizationStatus()
        }
        .onChange(of: selectedAvatarItem) { newValue in
            guard let newValue else { return }
            Task { await uploadAvatar(from: newValue) }
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
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if let draftBinding {
            let profile = draftBinding.wrappedValue

            profileHeader
            ProfileOverviewCard(
                profile: profile,
                isUploadingAvatar: isUploadingAvatar,
                selectedAvatarItem: $selectedAvatarItem,
                onEdit: { isEditorPresented = true }
            )

            ProfileCompletenessCard(
                percent: profileCompleteness(for: profile),
                missingText: profileMissingHint(for: profile)
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

                NavigationLink {
                    PublicProfilePreviewView(profile: profile, visibilityMode: visibilityMode)
                } label: {
                    ProfileMenuRow(
                        icon: "star.fill",
                        tint: .yellow,
                        title: "Моя активность",
                        subtitle: activitySummary(for: profile)
                    )
                }
                .buttonStyle(.plain)
            }

            ProfileMenuGroup {
                NavigationLink {
                    profileEditor(for: draftBinding, initialTitle: "Уведомления")
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
                    accountScreen
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

            Button {
                AppHaptics.selection()
                isEditorPresented = true
            } label: {
                ProfileHeaderButton(systemImage: "gearshape", tint: .white.opacity(0.76))
            }
            .buttonStyle(.plain)
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
            subtitle: "Настрой виды спорта, уровень и стиль игры.",
            systemImage: "tennis.racket",
            tint: AppTheme.court,
            onSave: { Task { await save() } }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: "Спортов", value: "\(profile.wrappedValue.preferredSports.count)", icon: "figure.tennis"),
                        .init(title: "Формат", value: profile.wrappedValue.preferredPlayFormat.title, icon: "person.2"),
                        .init(title: "Покрытие", value: profile.wrappedValue.preferredSurface.title, icon: "square.grid.2x2")
                    ])

                    ProfileEmbeddedLightCard(title: "Виды спорта", subtitle: "Выбери всё, во что готов играть, и выставь уровень.") {
                        AppSportSelectionGrid(
                            title: "Спортивный профиль",
                            sports: Sport.allCases,
                            selectedSports: profile.preferredSports,
                            levels: profile.sportLevels
                        )
                    }

                    ProfileEmbeddedLightCard(title: "Стиль игры", subtitle: "Эти параметры влияют на подбор и предложения игр.") {
                        AppSegmentedChoice(title: "Формат", items: PlayFormat.allCases, selection: profile.preferredPlayFormat, titleForItem: \.title)
                        AppSegmentedChoice(title: "Покрытие", items: Surface.allCases, selection: profile.preferredSurface, titleForItem: \.title)
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
            onSave: { Task { await save() } }
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
            onSave: { Task { await save() } }
        ) {
            ProfileDarkPanel {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileEditorMetricStrip(items: [
                        .init(title: "Районов", value: "\(activeProfileDistricts(for: profile.wrappedValue).count)", icon: "map"),
                        .init(title: "Радиус", value: "\(profile.wrappedValue.searchRadiusKm) км", icon: "scope"),
                        .init(title: "Город", value: profile.wrappedValue.city ?? "СПб", icon: "building.2")
                    ])

                    ProfileDistrictPickerCard(
                        selectedDistricts: profile.preferredDistricts,
                        primaryDistrict: profile.district,
                        districts: profileDistrictOptions
                    )

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

                    SectionCard(title: "Уведомления", subtitle: "Какие события подсвечивать в аккаунте.") {
                        ToggleCard(title: "Новые мэтчи", subtitle: "Сообщать, когда появляется взаимный интерес.", isOn: profile.notificationMatches)
                        ToggleCard(title: "Сообщения", subtitle: "Показывать новые сообщения и ответы в чате.", isOn: profile.notificationMessages)
                        ToggleCard(title: "Игры и предложения", subtitle: "Уведомления по поискам, играм и предложениям.", isOn: profile.notificationGames)
                        ToggleCard(title: "Звук", subtitle: "Воспроизводить звук системного уведомления.", isOn: profile.notificationSound)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Системный доступ")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(notificationManager.authorizationStatus.title)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                            }
                            Spacer()
                            Button("Разрешить") {
                                Task { await notificationManager.requestAuthorization() }
                            }
                            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
                            .frame(width: 128)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Сохранить профиль") {
                            Task { await save() }
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
    }

    private var accountScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Аккаунт")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                ProfileDarkPanel {
                    VStack(spacing: 0) {
                        ProfileInfoLine(title: "Почта", value: appModel.currentUser?.email ?? "Не указана")
                        ProfileInfoLine(title: "Статус", value: appModel.currentUser?.isVerified == true ? "Подтверждён" : "Не подтверждён")
                    }
                }

                Button("Выйти") {
                    appModel.logout()
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .white))

                Button("Удалить профиль") {
                    isDeleteConfirmationPresented = true
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .red))

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
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
            ), in: 18 ... 70) {
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
            TextField("Санкт-Петербург", text: profile.city.orEmpty)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }

        FieldShell(title: "Район") {
            TextField("Например: Приморский", text: profile.district.orEmpty)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }

        FieldShell(title: "О себе", caption: "Коротко опиши стиль игры или с кем хочешь играть.") {
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

    private var guestBasicsSection: some View {
        Group {
            FieldShell(title: "Имя") {
                TextField("Анна", text: $guestDraft.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            FieldShell(title: "Возраст") {
                Stepper(value: $guestDraft.age, in: 18 ... 70) {
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
            AppSegmentedChoice(title: "Формат", items: PlayFormat.allCases, selection: $guestDraft.preferredPlayFormat, titleForItem: \.title)
            AppSegmentedChoice(title: "Покрытие", items: Surface.allCases, selection: $guestDraft.preferredSurface, titleForItem: \.title)

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

    private func save() async {
        guard let draft else { return }

        await appModel.saveProfile(draft)
        self.draft = appModel.currentUser
        guard appModel.errorMessage == nil else { return }
        AppHaptics.notification(.success)
        showSaveToast("Профиль сохранён")
        isEditorPresented = false
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

    private func showSaveToast(_ message: String) {
        saveToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.22)) {
                if saveToastMessage == message {
                    saveToastMessage = nil
                }
            }
        }
    }

    private func profileCompleteness(for profile: UserProfile) -> Int {
        let checks = [
            profile.name?.isEmpty == false,
            profile.age != nil,
            profile.city?.isEmpty == false,
            profile.district?.isEmpty == false || !profile.preferredDistricts.isEmpty,
            !profile.preferredSports.isEmpty,
            !profile.availabilityByDay.isEmpty,
            profile.bio?.isEmpty == false,
            profile.avatarUrl?.isEmpty == false
        ]
        let done = checks.filter { $0 }.count
        return Int((Double(done) / Double(checks.count) * 100).rounded())
    }

    private func profileMissingHint(for profile: UserProfile) -> String {
        if profile.avatarUrl?.isEmpty != false {
            return "Осталось добавить фото в деле."
        }
        if profile.bio?.isEmpty != false {
            return "Осталось заполнить описание."
        }
        if profile.availabilityByDay.isEmpty {
            return "Осталось указать удобное время."
        }
        return "Отлично! Карточка выглядит полной."
    }

    private func sportsSummary(for profile: UserProfile) -> String {
        guard !profile.preferredSports.isEmpty else { return "Виды спорта ещё не выбраны" }
        return "\(profile.preferredSports.count) вида спорта, уровни и стили игры"
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
        let enabled = [profile.notificationMatches, profile.notificationMessages, profile.notificationGames].filter { $0 }.count
        return enabled == 0 ? "Выключены" : "Мэтчи, сообщения и игры включены"
    }

    private func availabilityHeadline(for availabilityByDay: [String: [String]]) -> String {
        guard !availabilityByDay.isEmpty else { return "Время игры не указано" }
        let ranges = Set(availabilityByDay.values.flatMap { $0 }).compactMap { TimeRange(rawValue: $0)?.title.lowercased() }
        let daysCount = availabilityByDay.filter { !$0.value.isEmpty }.count
        return "\(daysCount) дней, \(ranges.sorted().joined(separator: ", "))"
    }

    private var profileDistrictOptions: [String] {
        districtAreasByID.values
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            .map(\.id)
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

    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let onSave: () -> Void
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        onSave: @escaping () -> Void,
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
                        onSave()
                    } label: {
                        Text("Сохранить")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProfileFilledButtonStyle(tint: AppTheme.court))
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

private struct ProfileOverviewCard: View {
    let profile: UserProfile
    let isUploadingAvatar: Bool
    @Binding var selectedAvatarItem: PhotosPickerItem?
    let onEdit: () -> Void

    var body: some View {
        ProfileDarkPanel {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                        ZStack(alignment: .bottomTrailing) {
                            RemoteAvatarView(name: profile.displayName, path: profile.avatarUrl, size: 86)

                            Circle()
                                .fill(isUploadingAvatar ? AppTheme.court : Color.green)
                                .frame(width: 18, height: 18)
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
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            if profile.isLookingForGame {
                                ProfileCapsule(text: "Ищу игру сейчас", tint: AppTheme.court)
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
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(profile.preferredSports.prefix(4)) { sport in
                        ProfileSportChip(sport: sport, level: profile.sportLevels[sport.rawValue] ?? profile.tennisLevel)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onEdit) {
                        Label("Редактировать", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProfileFilledButtonStyle(tint: AppTheme.court))

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

private struct ProfileCompletenessCard: View {
    let percent: Int
    let missingText: String

    var body: some View {
        ProfileDarkPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Заполненность профиля")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(percent)%")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.green)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule()
                            .fill(LinearGradient(colors: [AppTheme.court, .green], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * CGFloat(percent) / 100)
                    }
                }
                .frame(height: 5)

                Text(missingText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
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
    }
}

private struct PublicProfilePreviewView: View {
    let profile: UserProfile
    let visibilityMode: ProfileVisibilityMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    ProfileSubscreenHeader(title: "Публичный профиль", onBack: { dismiss() })
                    PublicProfileCard(profile: profile, visibilityMode: visibilityMode)

                    ProfileDarkPanel {
                        VStack(spacing: 6) {
                            Text("Нужен доступ к полному профилю?")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.56))
                            Text("Открыть в приложении")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct PublicProfileCard: View {
    let profile: UserProfile
    let visibilityMode: ProfileVisibilityMode

    var body: some View {
        ProfileDarkPanel {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [AppTheme.court.opacity(0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 168)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "tennisball.fill")
                                .font(.system(size: 88))
                                .foregroundStyle(.yellow.opacity(0.82))
                                .rotationEffect(.degrees(-18))
                                .padding(.trailing, 28)
                        }

                    RemoteAvatarView(name: profile.displayName, path: profile.avatarUrl, size: 92)
                        .padding(.leading, 18)
                        .offset(y: 32)
                }
                .padding(.bottom, 28)

                Text("\(profile.displayName), \(profile.age ?? 28)")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(profile.city ?? "Санкт-Петербург") · \(profile.district ?? "район не указан")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))

                HStack(spacing: 8) {
                    ForEach(profile.preferredSports.prefix(2)) { sport in
                        ProfileSportChip(sport: sport, level: profile.sportLevels[sport.rawValue] ?? profile.tennisLevel)
                    }
                }

                if visibilityMode == .publicProfile {
                    Text(profile.bio?.isEmpty == false ? profile.bio! : "Играю в удовольствие и на результат. Открыт к новым знакомствам и интересным играм!")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                        ProfileFact(icon: "clock", title: "Когда удобно", value: "Пн-Пт вечером")
                        ProfileFact(icon: "tennisball", title: "Предпочитаю", value: profile.preferredPlayFormat.title)
                        ProfileFact(icon: "arrow.triangle.2.circlepath", title: "Частота", value: "2-4 раза в неделю")
                        ProfileFact(icon: "building.2", title: "Любимые клубы", value: "Vaska Padel Yard")
                    }
                }

                Button {
                    AppHaptics.impact(.light)
                } label: {
                    Label("Предложить игру", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProfileFilledButtonStyle(tint: AppTheme.court))
            }
        }
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
            Image(systemName: sport.profileIcon)
                .foregroundStyle(sport == .tennis ? .yellow : AppTheme.court)
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
                Text("\(profile.age ?? 28) лет · \(profile.city ?? "Санкт-Петербург")")
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
            return "tennis.racket"
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
