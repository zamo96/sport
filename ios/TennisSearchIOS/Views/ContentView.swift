import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        AppScreen {
            Group {
                if appModel.isAuthenticated || appModel.isGuestModeAvailable {
                    MainTabView()
                } else {
                    AuthView(initialStep: .intro, embedded: true)
                }
            }
        }
        .sheet(item: $appModel.presentedAuthStep) { step in
            NavigationStack {
                AppScreen {
                    AuthView(initialStep: step, embedded: false)
                }
            }
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
        .alert("Ошибка", isPresented: Binding(
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
            Text(appModel.errorMessage ?? "")
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

    var title: String {
        switch self {
        case .discover:
            return "Главная"
        case .matches:
            return "Мэтчи"
        case .searches:
            return "Поиски"
        case .courts:
            return "Центры"
        case .profile:
            return "Профиль"
        }
    }

    var systemImage: String {
        switch self {
        case .discover:
            return "safari"
        case .matches:
            return "message"
        case .searches:
            return "flame"
        case .courts:
            return "map"
        case .profile:
            return "person"
        }
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager
    @State private var selectedTab: MainTab = .discover
    @State private var discoverStackID = UUID()
    @State private var matchesStackID = UUID()
    @State private var searchesStackID = UUID()
    @State private var courtsStackID = UUID()
    @State private var profileStackID = UUID()
    @State private var discoverHighlightedUserID: String?
    @State private var discoverHighlightedSearchID: String?
    @State private var discoverHighlightedGameRequestID: String?
    @State private var discoverViewIdentity = UUID()
    @State private var isSlidingTabs = false
    @State private var tabDragLocationX: CGFloat?
    @State private var pendingTab: MainTab?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            currentTabScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.black.ignoresSafeArea())
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            handlePendingNavigation(appModel.pendingNavigationTarget)
        }
        .onChange(of: appModel.pendingNavigationTarget) { target in
            handlePendingNavigation(target)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: appModel.bottomBarDisplayMode)
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
                    initialTab: appModel.lastSelectedDiscoverTab,
                    highlightedUserID: discoverHighlightedUserID,
                    highlightedSearchID: discoverHighlightedSearchID,
                    highlightedGameRequestID: discoverHighlightedGameRequestID,
                    onTabChanged: { appModel.lastSelectedDiscoverTab = $0 }
                )
                .id(discoverViewIdentity)
            }
        case .matches:
            tabNavigation(id: matchesStackID) {
                if appModel.isAuthenticated {
                    MatchesView()
                } else {
                    AuthGateView(
                        title: "Мэтчи откроются после email",
                        subtitle: "Сначала подтверди почту, чтобы создавать мэтчи, переписываться и получать уведомления.",
                        buttonTitle: "Продолжить",
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
                        title: "Поиски сохраняются в аккаунте",
                        subtitle: "Сейчас можно смотреть игроков в гостевом режиме. Чтобы публиковать свои поиски, нужен email.",
                        buttonTitle: "Подтвердить email",
                        startStep: .email
                    )
                }
            }
        case .courts:
            tabNavigation(id: courtsStackID) {
                CourtsView()
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
                                        .background(.red, in: Capsule())
                                        .offset(x: 14, y: -10)
                                }
                            }
                            .frame(height: 24)

                            Text(tab.title)
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
                            selectedTab = pendingTab
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
        default:
            return nil
        }
    }

    private var displayedTab: MainTab {
        if isSlidingTabs, let pendingTab {
            return pendingTab
        }
        return selectedTab
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

        switch target {
        case .discover(let tab, let highlightedUserID, let highlightedSearchID, let highlightedGameRequestID):
            appModel.lastSelectedDiscoverTab = tab
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
        switch tab {
        case .discover:
            appModel.lastSelectedDiscoverTab = appModel.hasActiveUpcomingGameRequests ? .upcoming : .swipe
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
            courtsStackID = UUID()
        case .profile:
            profileStackID = UUID()
        }
        selectedTab = tab
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
        .navigationTitle("Требуется вход")
    }
}
