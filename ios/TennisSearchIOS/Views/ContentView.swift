import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        AppScreen {
            Group {
                if appModel.sessionRestoreState == .restoring {
                    ProgressView(L10n.string("Restoring your session…", "Восстанавливаем вход…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appModel.sessionRestoreState == .failed {
                    VStack(spacing: 18) {
                        Text(L10n.string("Could not restore your session", "Не удалось восстановить вход"))
                            .font(.headline)
                        Text(L10n.string("Check your connection and try again.", "Проверь подключение и попробуй ещё раз."))
                            .foregroundStyle(.secondary)
                        Button(L10n.string("Try again", "Повторить")) {
                            Task { await appModel.bootstrap() }
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.court))
                        Button(L10n.string("Continue as guest", "Продолжить как гость")) {
                            appModel.logout()
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.court))
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appModel.isOnboardingComplete || appModel.isGuestModeAvailable {
                    MainTabView()
                        .id(appModel.sessionGeneration)
                } else {
                    AuthView(initialStep: appModel.isAuthenticated ? (appModel.guestDraft.hasProfileBasics ? .availability : .profile) : .intro, embedded: true)
                }
            }
        }
        .sheet(item: $appModel.presentedAuthStep, onDismiss: {
            appModel.authenticationSheetDidDismiss()
        }) { step in
            NavigationStack {
                AppScreen {
                    AuthView(initialStep: step, embedded: false)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if appModel.isBusy {
                LoadingOverlay()
            }
        }
        .overlay {
            if let notice = appModel.serverRecoveryNotice {
                ServerRecoveryOverlay(
                    title: notice.title,
                    message: notice.message,
                    onDismiss: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            appModel.dismissServerRecoveryNotice()
                        }
                    }
                )
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(10)
            }
        }
        .overlay {
            KeyboardWarmupView()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .alert(L10n.string("Error", "Ошибка"), isPresented: Binding(
            get: { appModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    appModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                appModel.errorMessage = nil
            }
        } message: {
            Text(LocalizedStringKey(appModel.errorMessage ?? ""))
        }
        .onChange(of: appModel.serverRecoveryNotice?.id) { value in
            guard value != nil else {
                return
            }

            AppHaptics.notification(.warning)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.2))
                guard appModel.serverRecoveryNotice?.id == value else {
                    return
                }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    appModel.dismissServerRecoveryNotice()
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: appModel.serverRecoveryNotice?.id)
    }
}

private enum MainTab: String, CaseIterable, Identifiable {
    case discover
    case matches
    case searches
    case courts
    case profile

    var id: String { rawValue }

    func title(locale: AppLocale) -> String {
        switch self {
        case .discover:
            return L10n.string("Home", "Главная", locale: locale)
        case .matches:
            return L10n.string("Matches", "Мэтчи", locale: locale)
        case .searches:
            return L10n.string("Searches", "Мои поиски", locale: locale)
        case .courts:
            return L10n.string("Courts", "Центры", locale: locale)
        case .profile:
            return L10n.string("Profile", "Профиль", locale: locale)
        }
    }

    var systemImage: String {
        switch self {
        case .discover:
            return "safari"
        case .matches:
            return "message"
        case .searches:
            return "magnifyingglass.circle"
        case .courts:
            return "map"
        case .profile:
            return "person"
        }
    }

    func loadingTitle(locale: AppLocale) -> String {
        switch self {
        case .discover:
            return L10n.string("Refreshing players", "Обновляем игроков", locale: locale)
        case .matches:
            return L10n.string("Loading matches", "Загружаем мэтчи", locale: locale)
        case .searches:
            return L10n.string("Loading searches", "Загружаем поиски", locale: locale)
        case .courts:
            return L10n.string("Loading courts", "Загружаем центры", locale: locale)
        case .profile:
            return L10n.string("Loading profile", "Загружаем профиль", locale: locale)
        }
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var localeStore: LocaleStore
    @State private var selectedTab: MainTab = {
        #if DEBUG
        if AppConfig.useMockData,
           ProcessInfo.processInfo.arguments.contains("-centers-map-preview")
            || ProcessInfo.processInfo.arguments.contains("-centers-list-preview") {
            return .courts
        }
        #endif
        return .discover
    }()
    @State private var discoverStackID = UUID()
    @State private var matchesStackID = UUID()
    @State private var searchesStackID = UUID()
    @State private var courtsStackID = UUID()
    @State private var profileStackID = UUID()
    @State private var discoverHighlightedUserID: String?
    @State private var discoverHighlightedSearchID: String?
    @State private var discoverHighlightedGameRequestID: String?
    @State private var courtsInitialSport: Sport?
    @State private var courtsVisitPlanningMode = false
    @State private var courtsInitialPersonalVisit: Court?
    @State private var isSportHomePresented = false
    @State private var hasNavigatedBeyondEntry = false
    @State private var discoverViewIdentity = UUID()
    @State private var isSlidingTabs = false
    @State private var tabDragLocationX: CGFloat?
    @State private var pendingTab: MainTab?

    private var usesBoundedTabViewport: Bool {
        selectedTab == .courts || selectedTab == .discover
    }

    var body: some View {
        Group {
            if usesBoundedTabViewport {
                // Keep maps and Discover's viewed-player dock physically above the menu.
                // Nested navigation stacks do not consistently inherit a custom inset.
                VStack(spacing: 0) {
                    currentTabScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay {
                            if shouldShowTabLoading {
                                MenuTabLoadingOverlay(title: selectedTab.loadingTitle(locale: localeStore.effectiveLocale))
                                    .transition(.opacity)
                            }
                        }
                        .clipped()

                    bottomBar
                        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: appModel.bottomBarDisplayMode)
                }
            } else {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    currentTabScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if shouldShowTabLoading {
                        MenuTabLoadingOverlay(title: selectedTab.loadingTitle(locale: localeStore.effectiveLocale))
                            .transition(.opacity)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            handlePendingNavigation(appModel.pendingNavigationTarget)
            resumePendingPersonalVisitIfNeeded()
        }
        .onChange(of: appModel.pendingNavigationTarget) { target in
            handlePendingNavigation(target)
        }
        .onChange(of: appModel.canResumePendingPersonalVisit) { canResume in
            if canResume { resumePendingPersonalVisitIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tennisNotificationRouteRequested)) { notification in
            guard let href = notification.object as? String,
                  let target = AppNavigationTarget(notificationHref: href) else {
                return
            }
            appModel.navigate(to: target)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !usesBoundedTabViewport {
                bottomBar
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: appModel.bottomBarDisplayMode)
            }
        }
    }

    private var bottomBar: some View {
        let mode = appModel.bottomBarDisplayMode

        return GeometryReader { proxy in
            telegramTabBar(width: proxy.size.width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: bottomBarHeight(for: mode))
        .background(Color.clear)
        .opacity(mode == .hidden ? 0 : 1)
        .allowsHitTesting(mode != .hidden)
    }

    @ViewBuilder
    private var currentTabScreen: some View {
        switch selectedTab {
        case .discover:
            tabNavigation(id: discoverStackID) {
                DiscoverView(
                    isForeground: !isSportHomePresented,
                    initialTab: appModel.lastSelectedDiscoverTab,
                    highlightedUserID: discoverHighlightedUserID,
                    highlightedSearchID: discoverHighlightedSearchID,
                    highlightedGameRequestID: discoverHighlightedGameRequestID,
                    onTabChanged: {
                        hasNavigatedBeyondEntry = true
                        appModel.lastSelectedDiscoverTab = $0
                    },
                    onOpenSportHome: {
                        hasNavigatedBeyondEntry = true
                        isSportHomePresented = true
                    },
                    featureGuide: featureGuideConfiguration
                )
                .id(discoverViewIdentity)
                .navigationDestination(isPresented: $isSportHomePresented) {
                    SportHomeView(
                        onOpenIntent: openHomeIntent,
                        onOpenUpcoming: { gameID in
                            openHomeDiscover(.upcoming, gameID: gameID)
                        }
                    )
                    .toolbar(.visible, for: .navigationBar)
                }
            }
        case .matches:
            tabNavigation(id: matchesStackID) {
                if appModel.isAuthenticated {
                    MatchesView()
                } else {
                    AuthGateView(
                        title: L10n.string("Matches are available after email verification", "Мэтчи откроются после email"),
                        subtitle: L10n.string("Verify your email first to create matches, chat, and receive notifications.", "Сначала подтверди почту, чтобы создавать мэтчи, переписываться и получать уведомления."),
                        buttonTitle: L10n.string("Continue", "Продолжить"),
                        startStep: .email
                    )
                }
            }
        case .searches:
            tabNavigation(id: searchesStackID) {
                if appModel.isAuthenticated {
                    SearchesView()
                } else {
                    AuthGateView(
                        title: L10n.string("Searches are saved to your account", "Поиски сохраняются в аккаунте"),
                        subtitle: L10n.string("You can browse players as a guest. Verify your email to publish searches.", "Сейчас можно смотреть игроков в гостевом режиме. Чтобы публиковать свои поиски, нужен email."),
                        buttonTitle: L10n.string("Verify email", "Подтвердить email"),
                        startStep: .email
                    )
                }
            }
        case .courts:
            tabNavigation(id: courtsStackID) {
                CourtsView(
                    initialSport: courtsInitialSport,
                    visitPlanningMode: courtsVisitPlanningMode,
                    initialPersonalVisitCourt: courtsInitialPersonalVisit
                )
            }
        case .profile:
            tabNavigation(id: profileStackID) {
                ProfileView()
            }
        }
    }

    private func tabNavigation<Content: View>(id: UUID, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
        }
        .id(id)
    }

    private func telegramTabBar(width: CGFloat) -> some View {
        let safeWidth = max(width, 320)
        let horizontalInset: CGFloat = 14
        let barWidth = safeWidth - (horizontalInset * 2)
        let tabWidth = barWidth / CGFloat(MainTab.allCases.count)
        let indicatorCenter = currentIndicatorCenterX(tabWidth: tabWidth, barWidth: barWidth)
        let indicatorWidth = currentIndicatorWidth(tabWidth: tabWidth, barWidth: barWidth)
        let mode = appModel.bottomBarDisplayMode
        let isCompact = mode == .compact

        return ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(isCompact ? .black.opacity(0.72) : .black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 999 : 32, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(isCompact ? 0.1 : 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 999 : 32, style: .continuous)
                        .stroke(.white.opacity(isCompact ? 0.14 : 0.08), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.16))
                .frame(width: indicatorWidth, height: 58)
                .offset(x: indicatorCenter - (barWidth / 2), y: -1)
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
                .opacity(isCompact ? 0 : 1)
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: selectedTab)
                .animation(.spring(response: 0.28, dampingFraction: 0.84), value: tabDragLocationX)

            HStack(spacing: 0) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        pendingTab = nil
                        tabDragLocationX = nil
                        isSlidingTabs = false
                        activateTab(tab, source: .tap)
                    } label: {
                        VStack(spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 21, weight: displayedTab == tab ? .semibold : .regular))

                                if let badge = badgeText(for: tab) {
                                    Text(badge)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(badgeBackground(for: tab), in: Capsule())
                                        .offset(x: 14, y: -10)
                                }
                            }
                            .frame(height: 24)

                            Text(tab.title(locale: localeStore.effectiveLocale))
                                .font(.system(size: 11, weight: displayedTab == tab ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(displayedTab == tab ? Color(red: 0.28, green: 0.55, blue: 0.98) : .white.opacity(0.92))
                        .frame(width: tabWidth, height: 72)
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(isCompact ? 0 : 1)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.82))
                .frame(width: 44, height: 5)
                .opacity(isCompact ? 1 : 0)
        }
        .frame(width: isCompact ? 58 : barWidth, height: isCompact ? 8 : 76)
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard !isCompact else {
                        return
                    }
                    isSlidingTabs = true
                    let clampedX = min(max(value.location.x, tabWidth / 2), barWidth - (tabWidth / 2))
                    tabDragLocationX = clampedX
                    pendingTab = tab(at: value.location.x, tabWidth: tabWidth)
                }
                .onEnded { _ in
                    guard !isCompact else {
                        return
                    }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        if let pendingTab {
                            activateTab(pendingTab, source: .tap)
                        }
                        self.pendingTab = nil
                        isSlidingTabs = false
                        tabDragLocationX = nil
                    }
                }
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, isCompact ? 4 : 8)
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
    }

    private func bottomBarHeight(for mode: BottomBarDisplayMode) -> CGFloat {
        switch mode {
        case .expanded:
            return 98
        case .compact:
            return 20
        case .hidden:
            return 0
        }
    }

    private func badgeText(for tab: MainTab) -> String? {
        switch tab {
        case .discover:
            let count = notificationManager.summary.discoverBadgeCount
            return count > 0 ? String(min(count, 99)) : nil
        case .matches:
            let count = appModel.isAuthenticated ? notificationManager.summary.inboxBadgeCount : 0
            return count > 0 ? String(min(count, 99)) : nil
        case .searches:
            let count = appModel.isAuthenticated ? notificationManager.summary.activeSearchesCount : 0
            return count > 0 ? String(min(count, 99)) : nil
        default:
            return nil
        }
    }

    private func badgeBackground(for tab: MainTab) -> Color {
        tab == .searches ? AppTheme.court : .red
    }

    private var displayedTab: MainTab {
        if isSlidingTabs, let pendingTab {
            return pendingTab
        }
        return selectedTab
    }

    private var shouldShowTabLoading: Bool {
        guard selectedTab != .discover || !isSportHomePresented else { return false }
        return appModel.isTabContentLoading(selectedTab.rawValue)
    }

    private var isFeatureGuideAvailable: Bool {
        !isSportHomePresented
            && (appModel.isOnboardingComplete || appModel.isGuestModeAvailable)
            && appModel.pendingNavigationTarget == nil
            && appModel.pendingPersonalVisit == nil
            && appModel.presentedAuthStep == nil
            && discoverHighlightedUserID == nil
            && discoverHighlightedSearchID == nil
            && discoverHighlightedGameRequestID == nil
    }

    private var shouldShowFeatureGuide: Bool {
        isFeatureGuideAvailable
            && !hasNavigatedBeyondEntry
            && appModel.shouldShowFeatureGuide
            && appModel.featureGuideProgress.openedIntents.count < UserIntent.allCases.count
    }

    private var featureGuideConfiguration: DiscoverFeatureGuide? {
        guard isFeatureGuideAvailable else { return nil }
        let generation = appModel.sessionGeneration
        return DiscoverFeatureGuide(
            selectedIntents: appModel.selectedUserIntents,
            progress: appModel.featureGuideProgress,
            allowsAutomaticPresentation: shouldShowFeatureGuide,
            onAcknowledgeSwipe: {
                guard appModel.sessionGeneration == generation else { return }
                appModel.completeFeatureGuideSwipeTutorial()
            },
            onOpen: { intent in
                guard appModel.sessionGeneration == generation else { return }
                openFeatureGuideIntent(intent)
            },
            onDismiss: {
                guard appModel.sessionGeneration == generation else { return }
                appModel.dismissFeatureGuide()
            }
        )
    }

    private func openFeatureGuideIntent(_ intent: UserIntent) {
        appModel.markFeatureGuideOpened(intent)
        // A chosen section closes the guide for good, like the cross does:
        // otherwise it reopened on every launch until all four were checked.
        appModel.dismissFeatureGuide()
        hasNavigatedBeyondEntry = true
        openHomeIntent(intent)
    }

    private func tab(at x: CGFloat, tabWidth: CGFloat) -> MainTab {
        let index = min(max(Int(x / tabWidth), 0), MainTab.allCases.count - 1)
        return MainTab.allCases[index]
    }

    private func centerX(for tab: MainTab, tabWidth: CGFloat) -> CGFloat {
        let index = CGFloat(MainTab.allCases.firstIndex(of: tab) ?? 0)
        return (index * tabWidth) + (tabWidth / 2)
    }

    private func currentIndicatorCenterX(tabWidth: CGFloat, barWidth: CGFloat) -> CGFloat {
        if isSlidingTabs, let tabDragLocationX {
            return min(max(tabDragLocationX, tabWidth / 2), barWidth - (tabWidth / 2))
        }
        return centerX(for: selectedTab, tabWidth: tabWidth)
    }

    private func currentIndicatorWidth(tabWidth: CGFloat, barWidth: CGFloat) -> CGFloat {
        let baseWidth: CGFloat = max(56, tabWidth * 0.82)
        guard isSlidingTabs, let tabDragLocationX else {
            return baseWidth
        }

        let activeCenter = centerX(for: selectedTab, tabWidth: tabWidth)
        let clampedX = min(max(tabDragLocationX, tabWidth / 2), barWidth - (tabWidth / 2))
        let drift = abs(clampedX - activeCenter)
        return min(baseWidth + drift * 0.18, tabWidth * 0.96)
    }

    private func handlePendingNavigation(_ target: AppNavigationTarget?) {
        guard let target else {
            return
        }

        hasNavigatedBeyondEntry = true
        isSportHomePresented = false
        switch target {
        case .discover(let tab, let highlightedUserID, let highlightedSearchID, let highlightedGameRequestID):
            let resolvedTab: DiscoverTab = tab == .seeking ? .hot : tab
            appModel.lastSelectedDiscoverTab = resolvedTab
            discoverHighlightedUserID = highlightedUserID
            discoverHighlightedSearchID = highlightedSearchID
            discoverHighlightedGameRequestID = highlightedGameRequestID
            discoverViewIdentity = UUID()
            discoverStackID = UUID()
            selectedTab = .discover
        case .matches:
            matchesStackID = UUID()
            selectedTab = .matches
        case .searches:
            searchesStackID = UUID()
            selectedTab = .searches
        case .searchLobby(let searchId):
            appModel.pendingSearchLobbyID = searchId
            searchesStackID = UUID()
            selectedTab = .searches
        case .createSearch(let prefill):
            appModel.pendingCreateSearchPrefill = prefill
            searchesStackID = UUID()
            selectedTab = .searches
        case .profile:
            selectedTab = .profile
        case .courts(let sport):
            courtsInitialSport = sport
            courtsVisitPlanningMode = false
            courtsInitialPersonalVisit = nil
            courtsStackID = UUID()
            selectedTab = .courts
        case .chat(let matchId):
            appModel.pendingChatMatchID = matchId
            matchesStackID = UUID()
            selectedTab = .matches
        }

        appModel.clearPendingNavigation()
    }

    private enum TabActivationSource {
        case tap
    }

    private func activateTab(_ tab: MainTab, source _: TabActivationSource) {
        hasNavigatedBeyondEntry = true
        isSportHomePresented = false
        switch tab {
        case .discover:
            discoverHighlightedUserID = nil
            discoverHighlightedSearchID = nil
            discoverHighlightedGameRequestID = nil
            discoverViewIdentity = UUID()
            discoverStackID = UUID()
        case .matches:
            matchesStackID = UUID()
        case .searches:
            searchesStackID = UUID()
        case .courts:
            courtsInitialSport = nil
            courtsVisitPlanningMode = false
            courtsInitialPersonalVisit = nil
            courtsStackID = UUID()
        case .profile:
            profileStackID = UUID()
        }
        selectedTab = tab
    }

    private func openHomeIntent(_ intent: UserIntent) {
        isSportHomePresented = false
        switch intent {
        case .partner:
            openHomeDiscover(.swipe)
        case .group:
            openHomeDiscover(.hot)
        case .activity, .centers:
            courtsInitialSport = nil
            courtsVisitPlanningMode = intent == .activity
            courtsInitialPersonalVisit = nil
            courtsStackID = UUID()
            selectedTab = .courts
        }
    }

    private func openHomeDiscover(_ tab: DiscoverTab, gameID: String? = nil) {
        appModel.lastSelectedDiscoverTab = tab
        discoverHighlightedUserID = nil
        discoverHighlightedSearchID = nil
        discoverHighlightedGameRequestID = gameID
        isSportHomePresented = false
        discoverViewIdentity = UUID()
        selectedTab = .discover
    }

    private func resumePendingPersonalVisitIfNeeded() {
        guard let continuation = appModel.consumePendingPersonalVisit() else { return }
        hasNavigatedBeyondEntry = true
        courtsInitialSport = continuation.sport
        courtsInitialPersonalVisit = continuation.court
        courtsVisitPlanningMode = true
        courtsStackID = UUID()
        selectedTab = .courts
    }
}

private struct MenuTabLoadingOverlay: View {
    let title: String
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        loadingBall(index: index)
                    }
                }

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .opacity(isAnimating ? 0.9 : 0.62)
            }
            .padding(.bottom, 54)
        }
        .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }

    private func loadingBall(index: Int) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 212 / 255, green: 245 / 255, blue: 65 / 255),
                        Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 22, height: 22)
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.72), lineWidth: 1.4)
                    .frame(width: 4, height: 24)
                    .rotationEffect(.degrees(28))
            )
            .scaleEffect(isAnimating ? 1.04 : 0.76)
            .offset(y: isAnimating ? -10 : 10)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .shadow(
                color: Color(red: 48 / 255, green: 214 / 255, blue: 147 / 255).opacity(isAnimating ? 0.44 : 0.2),
                radius: isAnimating ? 14 : 6,
                x: 0,
                y: 6
            )
            .animation(
                .easeInOut(duration: 0.58)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.16),
                value: isAnimating
            )
    }
}

private struct AuthGateView: View {
    @EnvironmentObject private var appModel: AppModel

    let title: String
    let subtitle: String
    let buttonTitle: String
    let startStep: AuthStep

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle) {
                appModel.presentAuth(step: startStep)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            Spacer()
        }
        .padding(24)
        .navigationTitle(L10n.string("Sign-in required", "Требуется вход"))
    }
}
