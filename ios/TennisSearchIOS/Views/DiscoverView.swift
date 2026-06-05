import SwiftUI
import UIKit

struct DiscoverView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var users: [DiscoverUser] = []
    @State private var upcomingMatches: [MatchSummary] = []
    @State private var upcomingGameRequests: [MatchGameRequest] = []
    @State private var selectedUpcomingMatch: MatchSummary?
    @State private var selectedUpcomingParticipant: DiscoverUser?
    @State private var selectedUpcomingDetailsRequest: MatchGameRequest?
    @State private var selectedEditGameRequest: MatchGameRequest?
    @State private var selectedShareRequest: MatchGameRequest?
    @State private var selectedNextProposalMatch: MatchSummary?
    @State private var isUpcomingChatPresented = false
    @State private var mySearches: [GameSearch] = []
    @State private var mySearchesCount = 0
    @State private var selectedTab: DiscoverTab = .swipe
    @State private var isLoading = false
    @State private var matchMessage: String?
    @State private var matchMessageTask: Task<Void, Never>?
    @State private var responseMessage: String?
    @State private var responseMessageTask: Task<Void, Never>?
    @State private var localResponseStatuses: [String: String] = [:]
    @State private var localResponseIDs: [String: String] = [:]
    @State private var dragOffset: CGSize = .zero
    @State private var dragDecision: SwipeAction?
    @State private var tabSwipeOffset: CGFloat = 0
    @State private var isSystemRefreshing = false
    @State private var pullRefreshProgress: CGFloat = 0
    @State private var refreshSymbols: [String] = [Sport.tennis.ambientSymbol, Sport.football.ambientSymbol]
    @State private var didPrimeRefreshPull = false
    @State private var islandPulse = false
    @State private var lastAnnouncedSummarySignature: String?
    @AppStorage("announcedDiscoverSummarySignatures") private var announcedSummarySignaturesRaw = ""
    @State private var discoverScrollOffset: CGFloat = 0
    @State private var regularSportFilter: Sport?
    @State private var regularDayFilter: DayOfWeek?
    @State private var updatingUpcomingRequestIDs: Set<String> = []
    @State private var presentedRegularPairID: String?
    @State private var presentedSearchLobbyID: String?
    @State private var isWidgetHelpPresented = false
    @AppStorage("ios.discover.upcomingWidgetPrompt.dismissed.v1") private var isUpcomingWidgetPromptDismissed = false
    @State private var isSimilarPlayersHintPresented = false
    @State private var isSimilarPlayersHintScheduled = false
    @State private var similarPlayersHintDemoPhase = 0
    @State private var isFirstInterestHintPresented = false
    @State private var isFirstInterestHintScheduled = false
    @State private var firstInterestHintPlayerName: String?
    private let highlightedUserID: String?
    private let highlightedSearchID: String?
    private let highlightedGameRequestID: String?
    private let onTabChanged: ((DiscoverTab) -> Void)?

    init(
        initialTab: DiscoverTab = .swipe,
        highlightedUserID: String? = nil,
        highlightedSearchID: String? = nil,
        highlightedGameRequestID: String? = nil,
        onTabChanged: ((DiscoverTab) -> Void)? = nil
    ) {
        _selectedTab = State(initialValue: initialTab)
        self.highlightedUserID = highlightedUserID
        self.highlightedSearchID = highlightedSearchID
        self.highlightedGameRequestID = highlightedGameRequestID
        self.onTabChanged = onTabChanged
    }

    private var activeUser: DiscoverUser? {
        users.first
    }

    private var similarPlayersHintDemoOffset: CGSize {
        guard !reduceMotion else {
            return .zero
        }
        return CGSize(
            width: CGFloat(similarPlayersHintDemoPhase) * 56,
            height: abs(CGFloat(similarPlayersHintDemoPhase)) * 5
        )
    }

    private var similarPlayersHintDemoDecision: SwipeAction? {
        guard !reduceMotion else {
            return nil
        }
        switch similarPlayersHintDemoPhase {
        case -1:
            return .dislike
        case 1:
            return .like
        default:
            return nil
        }
    }

    private var swipeDeckMinHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.54, 440), 500)
    }

    private var activeUpcomingGameRequests: [MatchGameRequest] {
        upcomingGameRequests
            .filter { !$0.isArchivedForTimeline }
            .sorted { $0.proposedDatetime < $1.proposedDatetime }
    }

    private var archivedUpcomingGameRequests: [MatchGameRequest] {
        upcomingGameRequests
            .filter(\.isArchivedForTimeline)
            .sorted { $0.proposedDatetime > $1.proposedDatetime }
    }

    private var currentSelectionTitle: String {
        switch selectedTab {
        case .swipe:
            return "Сейчас выбрано: можно поиграть"
        case .likes:
            return "Сейчас выбрано: хотят с тобой поиграть"
        case .seeking:
            return "Сейчас выбрано: регулярно"
        case .hot:
            return "Сейчас выбрано: срочно"
        case .upcoming:
            return "Сейчас выбрано: ближайшие игры"
        }
    }

    private var summaryMaxWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.82, 336)
    }

    private var islandCollapseProgress: CGFloat {
        min(max(discoverScrollOffset / 110, 0), 1)
    }

    private var confirmedSoonRequests: [MatchGameRequest] {
        let now = Date()
        let cutoff = now.addingTimeInterval(7 * 24 * 60 * 60)

        return activeUpcomingGameRequests.filter { request in
            let status = request.status.lowercased()
            guard (status == "accepted" || status == "approved"),
                  let proposedDate = request.proposedDate else {
                return false
            }

            return proposedDate >= now && proposedDate <= cutoff
        }
    }

    private var pendingConfirmationCount: Int {
        activeUpcomingGameRequests.filter { request in
            request.isPendingForRecipient(currentUserId: appModel.currentUser?.id)
        }.count
    }

    private var pendingSearchResponsesCount: Int {
        mySearches.reduce(into: 0) { count, search in
            guard isSearchCountedInMyEvents(search) else {
                return
            }
            count += search.responses.filter { $0.status == "pending" }.count
        }
    }

    private var searchesNeedingSlotsCount: Int {
        mySearches.filter { search in
            guard isSearchCountedInMyEvents(search) else {
                return false
            }

            let approvedResponses = search.responses.filter { $0.status == "approved" }
            return !approvedResponses.isEmpty && search.activeSlotProposal == nil
        }.count
    }

    private var searchAttentionCount: Int {
        pendingSearchResponsesCount + searchesNeedingSlotsCount
    }

    private func isSearchCountedInMyEvents(_ search: GameSearch) -> Bool {
        let status = search.status.lowercased()
        guard (search.isActive ?? true),
              !["matched", "closed", "canceled", "cancelled", "expired"].contains(status) else {
            return false
        }
        return true
    }

    private var typedAttentionItems: [DiscoverSummaryAttentionItem] {
        var items: [DiscoverSummaryAttentionItem] = []

        if notificationManager.summary.incomingLikesCount > 0 {
            items.append(.init(
                count: notificationManager.summary.incomingLikesCount,
                title: notificationManager.summary.incomingLikesCount == 1 ? "хочет сыграть" : "хотят сыграть",
                subtitle: "Хотят с тобой поиграть",
                target: .discover(.likes)
            ))
        }

        if pendingConfirmationCount > 0 {
            items.append(.init(
                count: pendingConfirmationCount,
                title: pendingConfirmationCount == 1 ? "игра ждёт ответа" : "игры ждут ответа",
                subtitle: "Подтвердить игру",
                target: .discover(.upcoming)
            ))
        }

        if searchesNeedingSlotsCount > 0 {
            items.append(.init(
                count: searchesNeedingSlotsCount,
                title: searchesNeedingSlotsCount == 1 ? "нужно предложить слоты" : "нужно предложить слоты",
                subtitle: "Предложить слоты",
                target: .searches
            ))
        }

        if pendingSearchResponsesCount > 0 {
            items.append(.init(
                count: pendingSearchResponsesCount,
                title: pendingSearchResponsesCount == 1 ? "отклик на поиск" : "отклика на поиски",
                subtitle: "Ответить на отклики",
                target: .searches
            ))
        }

        if notificationManager.summary.hotBadgeCount > 0 {
            items.append(.init(
                count: notificationManager.summary.hotBadgeCount,
                title: notificationManager.summary.hotBadgeCount == 1 ? "срочное событие" : "срочных события",
                subtitle: "Срочный поиск",
                target: .discover(.hot)
            ))
        }

        if notificationManager.summary.inboxBadgeCount > 0 {
            items.append(.init(
                count: notificationManager.summary.inboxBadgeCount,
                title: notificationManager.summary.inboxBadgeCount == 1 ? "сообщение" : "сообщения",
                subtitle: "Открыть мэтчи",
                target: .matches
            ))
        }

        return items
    }

    private var summaryAttentionItems: [DiscoverSummaryAttentionItem] {
        let typedItems = typedAttentionItems
        guard typedItems.isEmpty, notificationManager.summary.discoverBadgeCount > 0 else {
            return typedItems
        }

        return [
            .init(
                count: notificationManager.summary.discoverBadgeCount,
                title: notificationManager.summary.discoverBadgeCount == 1 ? "уведомление" : "уведомления",
                subtitle: "Открыть уведомления",
                target: .discover(.swipe)
            )
        ]
    }

    private var hasSearchAttention: Bool {
        searchAttentionCount > 0
    }

    private var hasMatchAttention: Bool {
        pendingConfirmationCount > 0 || notificationManager.summary.inboxBadgeCount > 0
    }

    private func upcomingMatch(for request: MatchGameRequest) -> MatchSummary? {
        guard let matchId = request.matchId else {
            return nil
        }
        return upcomingMatches.first { $0.id == matchId }
    }

    private func upcomingDisplayName(for request: MatchGameRequest, match: MatchSummary?) -> String {
        let requestName = request.upcomingDisplayName(currentUserId: appModel.currentUser?.id)
        if requestName != "Игрок" {
            return requestName
        }
        return match?.otherUser.displayName ?? requestName
    }

    private func upcomingAvatarURL(for request: MatchGameRequest, match: MatchSummary?) -> String? {
        request.upcomingAvatarURL(currentUserId: appModel.currentUser?.id) ?? match?.otherUser.avatarUrl
    }

    private var attentionCount: Int {
        summaryAttentionItems.reduce(0) { $0 + $1.count }
    }

    private var summaryCardState: DiscoverSummaryCardState {
        if attentionCount > 0 {
            let items = summaryAttentionItems
            let firstItem = items.first
            let title = attentionTitle(for: items)
            let subtitle = attentionSubtitle(for: items)
            let routeHint = firstItem?.subtitle ?? "Открыть важное"
            let upcomingContext = confirmedSoonRequests.first.map(summaryUpcomingContext)
            return .attention(
                count: attentionCount,
                title: title,
                subtitle: [routeHint, subtitle, upcomingContext]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            )
        }

        if let nextConfirmedRequest = confirmedSoonRequests.first {
            return .upcoming(nextConfirmedRequest)
        }

        return .idle
    }

    private var summaryNavigationTarget: AppNavigationTarget? {
        switch summaryCardState {
        case .upcoming(let request):
            return .discover(.upcoming, highlightedGameRequestID: request.id)
        case .attention:
            return summaryAttentionItems.first?.target
        case .idle:
            return nil
        }
    }

    private var summaryStateSignature: String {
        switch summaryCardState {
        case .upcoming(let request):
            return "upcoming:\(request.id)"
        case .attention(let count, let title, _):
            let itemSignature = summaryAttentionItems.map { "\($0.subtitle):\($0.count)" }.joined(separator: ",")
            let upcomingSignature = confirmedSoonRequests.first?.id ?? "none"
            return "attention:\(count):\(title):\(itemSignature):upcoming:\(upcomingSignature)"
        case .idle:
            return "idle"
        }
    }

    private var announcedSummarySignatures: Set<String> {
        Set(announcedSummarySignaturesRaw.split(separator: "|").map(String.init))
    }

    private var hasVisibleSummaryCard: Bool {
        switch summaryCardState {
        case .idle:
            return false
        case .upcoming, .attention:
            return true
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                DiscoverScrollOffsetReader()
                topIslandCard
                tabBar
                tabContentContainer
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 120)
        }
        .coordinateSpace(name: "discover-scroll")
        .refreshable {
            await performRefresh()
        }
        .background(
            RefreshProgressObserver(
                progress: $pullRefreshProgress,
                isRefreshing: $isSystemRefreshing
            )
        )
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { presentedRegularPairID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedRegularPairID = nil
                }
            }
        )) {
            if let presentedRegularPairID {
                RegularPairDetailSheet(regularPairId: presentedRegularPairID)
            }
        }
        .sheet(isPresented: Binding(
            get: { presentedSearchLobbyID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedSearchLobbyID = nil
                    Task {
                        await loadDiscover()
                    }
                }
            }
        )) {
            if let presentedSearchLobbyID {
                SearchLobbySheet(searchId: presentedSearchLobbyID)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if appModel.isAuthenticated {
                        NavigationLink {
                            SearchesView(openedFromDiscover: true)
                        } label: {
                            MyEventsToolbarButton(count: mySearchesCount)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            NotificationsView()
                        } label: {
                            Image(systemName: "bell")
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .overlay(alignment: .topTrailing) {
                            if notificationManager.unreadNotificationCount > 0 {
                                Text("\(min(notificationManager.unreadNotificationCount, 99))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.red, in: Capsule())
                                    .offset(x: 10, y: -8)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            appModel.presentAuth(step: .email)
                        } label: {
                            MyEventsToolbarButton(count: 0)
                        }
                        .buttonStyle(.plain)

                        Button("Войти") {
                            appModel.presentAuth(step: .email)
                        }
                    }
                }
            }
        }
        .task {
            await loadDiscover()
            markHotEventsSeenIfNeeded()
            scheduleSimilarPlayersHintIfNeeded()
            scheduleFirstInterestHintIfNeeded()
        }
        .navigationDestination(isPresented: $isUpcomingChatPresented) {
            if let selectedUpcomingMatch {
                ChatView(match: selectedUpcomingMatch)
            }
        }
        .sheet(item: $selectedUpcomingParticipant) { user in
            DiscoverParticipantSheet(
                user: user,
                onOpenChat: selectedUpcomingMatch == nil
                    ? nil
                    : {
                        selectedUpcomingParticipant = nil
                        isUpcomingChatPresented = true
                    }
            )
                .presentationDetents([.fraction(0.58), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(item: $selectedUpcomingDetailsRequest) { request in
            let match = upcomingMatch(for: request)
            UpcomingGameDetailsSheet(
                request: request,
                displayName: upcomingDisplayName(for: request, match: match),
                avatarURL: upcomingAvatarURL(for: request, match: match),
                isUpdating: updatingUpcomingRequestIDs.contains(request.id),
                canEdit: canEditUpcomingRequest(request) && match != nil,
                canCancel: canManageUpcomingRequest(request),
                cancelTitle: request.createdByUserId == appModel.currentUser?.id ? "Отменить игру" : "Не смогу",
                onEdit: {
                    selectedUpcomingDetailsRequest = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        selectedEditGameRequest = request
                    }
                },
                onCancel: {
                    await cancelUpcomingRequest(request)
                    selectedUpcomingDetailsRequest = nil
                },
                onParticipantsChanged: {
                    await loadDiscover()
                    if let updated = upcomingGameRequests.first(where: { $0.id == request.id }) {
                        selectedUpcomingDetailsRequest = updated
                    }
                }
            )
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground(Color.black)
        }
        .sheet(item: $selectedEditGameRequest) { request in
            if let match = upcomingMatch(for: request) {
                GameProposalSheet(match: match, context: .edit, seedRequest: request) {
                    await loadDiscover()
                    await appModel.notificationManager.manualRefresh(repository: appModel.repository)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
        }
        .sheet(item: $selectedShareRequest) { request in
            ShareExistingGameSheet(
                request: request,
                matches: shareableMatches(for: request),
                onShare: { matchIds in
                    await shareUpcomingRequest(request, to: matchIds)
                }
            )
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedNextProposalMatch) { match in
            GameProposalSheet(match: match) {
                await loadDiscover()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(isPresented: $isWidgetHelpPresented) {
            UpcomingWidgetHelpSheet {
                isUpcomingWidgetPromptDismissed = true
            }
                .presentationDetents([.fraction(0.58), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground(Color.black)
        }
        .onChange(of: selectedTab) { _ in
            appModel.lastSelectedDiscoverTab = selectedTab
            onTabChanged?(selectedTab)
            markHotEventsSeenIfNeeded()
            Task {
                await loadDiscover()
                scheduleSimilarPlayersHintIfNeeded()
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if pullRefreshProgress > 0.01 || isSystemRefreshing {
                    SportRefreshIndicator(
                        progress: isSystemRefreshing ? 1 : pullRefreshProgress,
                        isRefreshing: isSystemRefreshing,
                        symbols: refreshSymbols
                    )
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let matchMessage {
                    MatchSuccessToast(message: matchMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let responseMessage {
                    InlineToast(message: responseMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: matchMessage)
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: responseMessage)
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: islandCollapseProgress)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: hasVisibleSummaryCard)
        .onChange(of: pullRefreshProgress) { value in
            if value > 0.02, !didPrimeRefreshPull {
                didPrimeRefreshPull = true
                refreshSymbols = randomRefreshSymbols()
            } else if value <= 0.001 {
                didPrimeRefreshPull = false
            }
        }
        .onPreferenceChange(DiscoverScrollOffsetPreferenceKey.self) { value in
            discoverScrollOffset = value
        }
        .overlay {
            if isSimilarPlayersHintPresented {
                DiscoverSimilarPlayersHintOverlay(
                    onDismiss: dismissSimilarPlayersHint
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(3)
            } else if isFirstInterestHintPresented {
                DiscoverFirstInterestHintOverlay(
                    playerName: firstInterestHintPlayerName,
                    onDismiss: dismissFirstInterestHint
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(3)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isSimilarPlayersHintPresented)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isFirstInterestHintPresented)
        .task(id: isSimilarPlayersHintPresented) {
            await runSimilarPlayersHintDemoLoop()
        }
        .onChange(of: isSimilarPlayersHintPresented) { isPresented in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = (isPresented || isFirstInterestHintPresented) ? .hidden : .expanded
            }
            if !isPresented {
                similarPlayersHintDemoPhase = 0
                scheduleFirstInterestHintIfNeeded()
            }
        }
        .onChange(of: isFirstInterestHintPresented) { isPresented in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = (isPresented || isSimilarPlayersHintPresented) ? .hidden : .expanded
            }
        }
        .onDisappear {
            if isSimilarPlayersHintPresented || isFirstInterestHintPresented {
                appModel.bottomBarDisplayMode = .expanded
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: summaryStateSignature) { _ in
            guard hasVisibleSummaryCard else {
                lastAnnouncedSummarySignature = nil
                return
            }

            guard lastAnnouncedSummarySignature != summaryStateSignature else {
                return
            }
            lastAnnouncedSummarySignature = summaryStateSignature

            guard !announcedSummarySignatures.contains(summaryStateSignature) else {
                return
            }
            rememberAnnouncedSummarySignature(summaryStateSignature)

            switch summaryCardState {
            case .attention:
                AppHaptics.notification(.warning)
            case .upcoming:
                AppHaptics.impact(.medium)
            case .idle:
                break
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                islandPulse = true
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(480))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    islandPulse = false
                }
            }
        }
    }

    private var topIslandCard: some View {
        let visibility = max(0, 1 - islandCollapseProgress)
        let compactWidth = summaryMaxWidth - (78 * islandCollapseProgress)

        return Group {
            if hasVisibleSummaryCard {
                HStack {
                    DiscoverSummaryCard(
                        state: summaryCardState,
                        maxWidth: max(176, compactWidth),
                        compact: true,
                        islandStyle: true,
                        pulse: islandPulse,
                        onTap: handleSummaryTap
                    )
                    .scaleEffect(
                        x: (0.72 + (0.28 * visibility)) * (1 - (0.1 * islandCollapseProgress)),
                        y: (0.84 + (0.16 * visibility)) * (1 - (0.16 * islandCollapseProgress)),
                        anchor: .topLeading
                    )
                    .opacity(visibility)
                    .offset(y: -(22 * islandCollapseProgress))
                    Spacer(minLength: 0)
                }
                .padding(.top, 4 * visibility)
                .padding(.bottom, 4 * visibility)
                .frame(height: 78 * visibility, alignment: .top)
                .clipped()
                .allowsHitTesting(visibility > 0.2)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.18, anchor: .topLeading)
                            .combined(with: .opacity)
                            .combined(with: .offset(x: -10, y: -18)),
                        removal: .scale(scale: 0.45, anchor: .topLeading)
                            .combined(with: .opacity)
                            .combined(with: .offset(x: -6, y: -16))
                    )
                )
            }
        }
    }

    private func scheduleSimilarPlayersHintIfNeeded() {
        guard appModel.shouldPresentDiscoverSimilarPlayersHint(),
              selectedTab == .swipe,
              !users.isEmpty,
              !isSimilarPlayersHintPresented,
              !isFirstInterestHintPresented,
              !isSimilarPlayersHintScheduled else {
            return
        }

        isSimilarPlayersHintScheduled = true
        Task { @MainActor in
            defer {
                isSimilarPlayersHintScheduled = false
            }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled,
                  appModel.shouldPresentDiscoverSimilarPlayersHint(),
                  selectedTab == .swipe,
                  !users.isEmpty,
                  !isFirstInterestHintPresented,
                  !isSimilarPlayersHintPresented else {
                return
            }
            appModel.consumeDiscoverSimilarPlayersHint()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isSimilarPlayersHintPresented = true
            }
        }
    }

    private func dismissSimilarPlayersHint() {
        AppHaptics.selection()
        appModel.completeDiscoverSimilarPlayersHint()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isSimilarPlayersHintPresented = false
        }
    }

    private func scheduleFirstInterestHintIfNeeded(playerName: String? = nil) {
        guard appModel.shouldPresentDiscoverFirstInterestHint(),
              !isSimilarPlayersHintPresented,
              !isFirstInterestHintPresented,
              !isFirstInterestHintScheduled else {
            return
        }

        if let playerName {
            firstInterestHintPlayerName = playerName
        }

        isFirstInterestHintScheduled = true
        Task { @MainActor in
            defer {
                isFirstInterestHintScheduled = false
            }
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled,
                  appModel.shouldPresentDiscoverFirstInterestHint(),
                  !isSimilarPlayersHintPresented,
                  !isFirstInterestHintPresented else {
                return
            }
            appModel.consumeDiscoverFirstInterestHint()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isFirstInterestHintPresented = true
            }
        }
    }

    private func dismissFirstInterestHint() {
        AppHaptics.selection()
        appModel.completeDiscoverFirstInterestHint()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isFirstInterestHintPresented = false
        }
    }

    private func runSimilarPlayersHintDemoLoop() async {
        guard isSimilarPlayersHintPresented, !reduceMotion else {
            return
        }

        while !Task.isCancelled, isSimilarPlayersHintPresented {
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled, isSimilarPlayersHintPresented else {
                return
            }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.56)) {
                    similarPlayersHintDemoPhase = -1
                }
            }

            try? await Task.sleep(for: .milliseconds(780))
            guard !Task.isCancelled, isSimilarPlayersHintPresented else {
                return
            }
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    similarPlayersHintDemoPhase = 0
                }
            }

            try? await Task.sleep(for: .milliseconds(390))
            guard !Task.isCancelled, isSimilarPlayersHintPresented else {
                return
            }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.56)) {
                    similarPlayersHintDemoPhase = 1
                }
            }

            try? await Task.sleep(for: .milliseconds(780))
            guard !Task.isCancelled, isSimilarPlayersHintPresented else {
                return
            }
            await MainActor.run {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    similarPlayersHintDemoPhase = 0
                }
            }

            try? await Task.sleep(for: .milliseconds(780))
        }
    }

    private func attentionTitle(for items: [DiscoverSummaryAttentionItem]) -> String {
        guard let first = items.first else {
            return "Требует внимания"
        }

        if items.count == 1 {
            return "\(first.count) \(first.title)"
        }

        return attentionCount == 1 ? "1 требует действия" : "\(attentionCount) требуют действия"
    }

    private func attentionSubtitle(for items: [DiscoverSummaryAttentionItem]) -> String {
        guard !items.isEmpty else {
            return ""
        }

        return items
            .prefix(3)
            .map { "\($0.count) \($0.title)" }
            .joined(separator: ", ")
    }

    private func summaryUpcomingContext(for request: MatchGameRequest) -> String {
        guard let date = request.proposedDate else {
            return "есть ближайшая игра"
        }

        let calendar = Calendar.current
        let prefix: String
        if calendar.isDateInToday(date) {
            prefix = "игра сегодня"
        } else if calendar.isDateInTomorrow(date) {
            prefix = "игра завтра"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMM"
            prefix = "игра \(formatter.string(from: date))"
        }

        return "\(prefix), \(date.formattedHourMinute())"
    }

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DiscoverTab.allCases) { tab in
                        Button {
                            selectTab(tab)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.systemImage)
                                Text(tab.title)
                                if tab == .upcoming, appModel.isAuthenticated, !activeUpcomingGameRequests.isEmpty {
                                    Text("\(min(activeUpcomingGameRequests.count, 99))")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.white.opacity(0.25), in: Capsule())
                                }
                                if tab == .swipe, !users.isEmpty {
                                    Text("\(min(users.count, 99))")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.white.opacity(0.25), in: Capsule())
                                }
                                if tab == .likes, appModel.isAuthenticated, notificationManager.summary.incomingLikesCount > 0 {
                                    Text("\(min(notificationManager.summary.incomingLikesCount, 99))")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.white.opacity(0.25), in: Capsule())
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(backgroundColor(for: tab))
                            .foregroundStyle(foregroundColor(for: tab))
                            .scaleEffect(selectedTab == tab ? 1 : 0.985)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(selectedTab == tab ? AppTheme.line : Color.white.opacity(0.8), lineWidth: selectedTab == tab ? 1.2 : 1)
                            )
                            .shadow(color: AppTheme.ink.opacity(selectedTab == tab ? 0.12 : 0.04), radius: 14, x: 0, y: 8)
                        }
                        .buttonStyle(.plain)
                        .id(tab.id)
                    }
                }
            }
            .onAppear {
                proxy.scrollTo(selectedTab.id, anchor: .center)
            }
            .onChange(of: selectedTab) { value in
                withAnimation(.easeInOut(duration: 0.34)) {
                    proxy.scrollTo(value.id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .upcoming:
            upcomingContent
        case .swipe:
            swipeContent
        case .likes:
            likesContent
        case .seeking, .hot:
            searchContent
        }
    }

    @ViewBuilder
    private var tabContentContainer: some View {
        let content = selectedTabContent
            .frame(maxWidth: .infinity, alignment: .leading)

        if selectedTab == .swipe || selectedTab == .likes {
            content
        } else {
            content
                .contentShape(Rectangle())
                .gesture(tabSwitchGesture)
        }
    }

    @ViewBuilder
    private var upcomingContent: some View {
        if !appModel.isAuthenticated {
            SectionCard(title: "Ближайшие игры", subtitle: "Этот раздел доступен после входа по email.") {
                AuthInlinePrompt(
                    title: "Сохрани аккаунт, чтобы видеть ближайшие игры",
                    subtitle: "После подтверждения email здесь появятся подтверждённые договорённости и предстоящие матчи."
                ) {
                    appModel.presentAuth(step: .email)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if activeUpcomingGameRequests.isEmpty, archivedUpcomingGameRequests.isEmpty, !isLoading {
                    EmptyStateView(
                        title: "Ближайших игр пока нет",
                        subtitle: "Как только договорённость будет подтверждена, она появится здесь.",
                        systemImage: "calendar.badge.clock"
                    )
                }

                if !isUpcomingWidgetPromptDismissed {
                    UpcomingWidgetPromptCard(hasUpcomingGames: !activeUpcomingGameRequests.isEmpty) {
                        isWidgetHelpPresented = true
                    }
                }

                ForEach(activeUpcomingGameRequests, id: \.id) { request in
                    if let match = upcomingMatches.first(where: { $0.id == request.matchId }) {
                        UpcomingGameCard(
                            request: request,
                            displayName: upcomingDisplayName(for: request, match: match),
                            avatarURL: upcomingAvatarURL(for: request, match: match),
                            currentUserId: appModel.currentUser?.id,
                            isUpdating: updatingUpcomingRequestIDs.contains(request.id),
                            onSelectParticipant: { participant in
                                selectedUpcomingMatch = match
                                selectedUpcomingParticipant = participant
                            },
                            onOpenChat: {
                                if let searchLobbyId = request.searchLobbyId {
                                    presentedSearchLobbyID = searchLobbyId
                                } else {
                                    selectedUpcomingMatch = match
                                    isUpcomingChatPresented = true
                                }
                            },
                            onOpenDetails: {
                                selectedUpcomingDetailsRequest = request
                            },
                            onShare: canShareUpcomingRequest(request)
                                ? {
                                    selectedShareRequest = request
                                }
                                : nil,
                            onAccept: canAcceptUpcomingRequest(request)
                                ? {
                                    await acceptUpcomingRequest(request)
                                }
                                : nil,
                            onCancel: canManageUpcomingRequest(request)
                                ? {
                                    await cancelUpcomingRequest(request)
                                }
                                : nil,
                            onMarkOutcome: request.needsOutcomeReview
                                ? { outcome in
                                    await markUpcomingOutcome(request, outcome: outcome)
                                }
                                : nil,
                            onProposeNext: {
                                selectedNextProposalMatch = match
                            }
                        )
                    } else {
                        UpcomingGameCard(
                            request: request,
                            displayName: upcomingDisplayName(for: request, match: nil),
                            avatarURL: upcomingAvatarURL(for: request, match: nil),
                            currentUserId: appModel.currentUser?.id,
                            isUpdating: updatingUpcomingRequestIDs.contains(request.id),
                            onSelectParticipant: { participant in
                                selectedUpcomingMatch = nil
                                selectedUpcomingParticipant = participant
                            },
                            onOpenChat: request.searchLobbyId == nil ? nil : {
                                presentedSearchLobbyID = request.searchLobbyId
                            },
                            onOpenDetails: {
                                selectedUpcomingDetailsRequest = request
                            },
                            onShare: canShareUpcomingRequest(request)
                                ? {
                                    selectedShareRequest = request
                                }
                                : nil,
                            onAccept: canAcceptUpcomingRequest(request)
                                ? {
                                    await acceptUpcomingRequest(request)
                                }
                                : nil,
                            onCancel: canManageUpcomingRequest(request)
                                ? {
                                    await cancelUpcomingRequest(request)
                                }
                                : nil,
                            onMarkOutcome: request.needsOutcomeReview
                                ? { outcome in
                                    await markUpcomingOutcome(request, outcome: outcome)
                                }
                                : nil,
                            onProposeNext: nil
                        )
                    }
                }

                if !archivedUpcomingGameRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("История игр")
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.68))
                            Spacer()
                            Text("\(archivedUpcomingGameRequests.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.08), in: Capsule())
                        }

                        ForEach(archivedUpcomingGameRequests, id: \.id) { request in
                            CompactUpcomingHistoryRow(
                                request: request,
                                displayName: request.upcomingDisplayName(currentUserId: appModel.currentUser?.id),
                                avatarURL: request.upcomingAvatarURL(currentUserId: appModel.currentUser?.id)
                                    ?? upcomingMatches.first(where: { $0.id == request.matchId })?.otherUser.avatarUrl,
                                onOpenChat: {
                                    if let searchLobbyId = request.searchLobbyId {
                                        presentedSearchLobbyID = searchLobbyId
                                    } else if let match = upcomingMatches.first(where: { $0.id == request.matchId }) {
                                        selectedUpcomingMatch = match
                                        isUpcomingChatPresented = true
                                    }
                                }
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var swipeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SwipeHintBar(isHighlighted: isSimilarPlayersHintPresented)
            if topStack.isEmpty, !isLoading {
                EmptyStateView(
                    title: "Карточки закончились",
                    subtitle: "Обнови подбор позже или переключись на активные поиски.",
                    systemImage: "sparkles"
                )
            } else {
                ZStack {
                    if isSimilarPlayersHintPresented {
                        TutorialSwipeDecisionZones()
                            .zIndex(Double(topStack.count) - 0.25)
                    }

                    ForEach(Array(topStack.enumerated()), id: \.element.id) { index, user in
                        if index == 0 {
                            SwipeCard(
                                user: user,
                                index: index,
                                dragOffset: isSimilarPlayersHintPresented ? similarPlayersHintDemoOffset : dragOffset,
                                decision: isSimilarPlayersHintPresented ? similarPlayersHintDemoDecision : dragDecision
                            )
                            .scaleEffect(isSimilarPlayersHintPresented ? 0.92 : 1.0)
                            .offset(y: isSimilarPlayersHintPresented ? 10 : 0)
                            .zIndex(Double(topStack.count))
                            .simultaneousGesture(dragGesture(for: user))
                            .onTapGesture {
                                openDiscoverParticipant(user)
                            }
                        } else {
                            SwipeCard(
                                user: user,
                                index: index,
                                dragOffset: .zero,
                                decision: nil
                            )
                            .scaleEffect(0.965 - CGFloat(index) * 0.02)
                            .offset(y: CGFloat(index) * 14)
                            .zIndex(Double(topStack.count - index))
                        }
                    }
                }
                .frame(minHeight: swipeDeckMinHeight)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var likesContent: some View {
        if !appModel.isAuthenticated {
            SectionCard(title: "Хотят с тобой поиграть", subtitle: "Этот раздел доступен после входа по email.") {
                AuthInlinePrompt(
                    title: "Войди, чтобы видеть входящие симпатии",
                    subtitle: "После подтверждения email здесь появятся игроки, которые уже отметили интерес к тебе."
                ) {
                    appModel.presentAuth(step: .email)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SwipeHintBar(leftTitle: "Влево — отказать", rightTitle: "Вправо — можно сыграть")

                if topStack.isEmpty, !isLoading {
                    EmptyStateView(
                        title: "Пока никто не отметил интерес",
                        subtitle: "Когда кто-то захочет сыграть с тобой, карточки появятся здесь.",
                        systemImage: "heart.text.square"
                    )
                } else {
                    ZStack {
                        ForEach(Array(topStack.enumerated()), id: \.element.id) { index, user in
                            if index == 0 {
                                SwipeCard(
                                    user: user,
                                    index: index,
                                    dragOffset: dragOffset,
                                    decision: dragDecision
                                )
                                .scaleEffect(1.0)
                                .offset(y: 0)
                                .zIndex(Double(topStack.count))
                                .simultaneousGesture(dragGesture(for: user))
                                .onTapGesture {
                                    openDiscoverParticipant(user)
                                }
                            } else {
                                SwipeCard(
                                    user: user,
                                    index: index,
                                    dragOffset: .zero,
                                    decision: nil
                                )
                                .scaleEffect(0.965 - CGFloat(index) * 0.02)
                                .offset(y: CGFloat(index) * 14)
                                .zIndex(Double(topStack.count - index))
                            }
                        }
                    }
                    .frame(minHeight: swipeDeckMinHeight)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        let title = selectedTab == .hot ? "Срочные поиски" : "Регулярные поиски"
        let visibleUsers = filteredSearchUsers

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.bold))

            if selectedTab == .seeking {
                regularFilters
            }

            if visibleUsers.isEmpty, !isLoading {
                EmptyStateView(
                    title: "Подходящих поисков пока нет",
                    subtitle: selectedTab == .hot
                        ? "Срочные события появятся здесь, как только кто-то начнёт искать игрока на сегодня или завтра."
                        : "Регулярные поиски появятся здесь, когда найдутся совпадения по спорту и времени.",
                    systemImage: selectedTab == .hot ? "flame" : "calendar"
                )
            }

            ForEach(visibleUsers) { user in
                if let search = user.gameSearches.first {
                    let ownResponse = currentUserResponse(in: search)
                    SeekingSearchCard(
                        user: user,
                        search: search,
                        variant: selectedTab,
                        responseStatus: normalizedResponseStatus(
                            localResponseStatuses[search.id] ?? ownResponse?.status
                        ),
                        responseId: normalizedResponseId(
                            status: localResponseStatuses[search.id] ?? ownResponse?.status,
                            id: localResponseIDs[search.id] ?? ownResponse?.id
                        ),
                        onOpenApprovedChat: {
                            if search.playersNeeded > 1 {
                                presentedSearchLobbyID = search.id
                            } else {
                                openApprovedRegularPair(for: search)
                            }
                        }
                    ) {
                        Task {
                            await handleResponseAction(for: search)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filteredSearchUsers: [DiscoverUser] {
        let baseUsers: [DiscoverUser]
        if let highlightedSearchID {
            baseUsers = prioritizingSearch(highlightedSearchID, in: users)
        } else {
            baseUsers = users
        }

        guard selectedTab == .seeking else {
            return baseUsers
        }

        return baseUsers.filter { user in
            guard let search = user.gameSearches.first else {
                return false
            }

             let responseStatus = normalizedResponseStatus(
                localResponseStatuses[search.id] ?? currentUserResponse(in: search)?.status
             )
             if responseStatus == "rejected" {
                return false
             }

            let matchesSport = regularSportFilter == nil || search.sport == regularSportFilter
            let matchesDay = regularDayFilter == nil || search.preferredDays.contains(regularDayFilter?.rawValue ?? "")
            return matchesSport && matchesDay
        }
    }

    private var regularFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        title: "Все виды",
                        isSelected: regularSportFilter == nil
                    ) {
                        regularSportFilter = nil
                    }

                    ForEach(availableRegularSports, id: \.self) { sport in
                        filterChip(
                            title: sport.title,
                            isSelected: regularSportFilter == sport
                        ) {
                            regularSportFilter = regularSportFilter == sport ? nil : sport
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        title: "Любой день",
                        isSelected: regularDayFilter == nil
                    ) {
                        regularDayFilter = nil
                    }

                    ForEach(availableRegularDays, id: \.self) { day in
                        filterChip(
                            title: day.shortTitle,
                            isSelected: regularDayFilter == day
                        ) {
                            regularDayFilter = regularDayFilter == day ? nil : day
                        }
                    }
                }
            }
        }
    }

    private var availableRegularSports: [Sport] {
        Array(Set(users.compactMap { $0.gameSearches.first?.sport })).sorted { $0.title < $1.title }
    }

    private var availableRegularDays: [DayOfWeek] {
        Array(
            Set(
                users
                    .compactMap { $0.gameSearches.first }
                    .flatMap(\.preferredDays)
                    .compactMap(DayOfWeek.init(rawValue:))
            )
        )
        .sorted { DayOfWeek.allCases.firstIndex(of: $0) ?? 0 < DayOfWeek.allCases.firstIndex(of: $1) ?? 0 }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isSelected ? AppTheme.court : .white.opacity(0.12),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(isSelected ? 0.16 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var topStack: [DiscoverUser] {
        Array(users.prefix(2))
    }

    private func loadDiscover() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if appModel.isAuthenticated {
                async let matchesRequest = appModel.repository.fetchMatches()
                async let gameRequestsRequest = appModel.repository.fetchMyGameRequests()
                async let searchesRequest = appModel.repository.fetchSearches()
                let matches = try await matchesRequest
                let gameRequests = try await gameRequestsRequest
                let searches = try await searchesRequest

                upcomingMatches = matches
                upcomingGameRequests = reorderedGameRequests(gameRequests)
                mySearches = searches
                mySearchesCount = searches.filter(isSearchCountedInMyEvents).count
                appModel.hasActiveUpcomingGameRequests = !activeUpcomingGameRequests.isEmpty
                UpcomingGamesWidgetStore.save(
                    gameRequests: activeUpcomingGameRequests,
                    currentUserId: appModel.currentUser?.id
                )
                await notificationManager.scheduleGameReminders(
                    for: activeUpcomingGameRequests,
                    playSound: appModel.currentUser?.notificationSound ?? true
                )

                if selectedTab == .upcoming {
                    await appModel.notificationManager.manualRefresh(repository: appModel.repository)
                    return
                }

                async let discoverRequest = appModel.repository.fetchDiscoverUsers(view: selectedTab)
                let fetchedUsers = try await discoverRequest
                users = reorderedUsers(fetchedUsers)
                await appModel.notificationManager.manualRefresh(repository: appModel.repository)
            } else {
                upcomingMatches = []
                upcomingGameRequests = []
                appModel.hasActiveUpcomingGameRequests = false
                UpcomingGamesWidgetStore.clear()
                mySearches = []
                let fetchedUsers = try await appModel.repository.fetchGuestDiscoverUsers(draft: appModel.guestDraft, view: selectedTab)
                users = reorderedUsers(fetchedUsers)
                mySearchesCount = 0
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func reorderedUsers(_ source: [DiscoverUser]) -> [DiscoverUser] {
        if let highlightedUserID, (selectedTab == .likes || selectedTab == .swipe) {
            return prioritizingUser(highlightedUserID, in: source)
        }

        if let highlightedSearchID, selectedTab == .hot || selectedTab == .seeking || selectedTab == .upcoming {
            return prioritizingSearch(highlightedSearchID, in: source)
        }

        return source
    }

    private func reorderedGameRequests(_ source: [MatchGameRequest]) -> [MatchGameRequest] {
        guard let highlightedGameRequestID else {
            return source
        }

        guard let index = source.firstIndex(where: { $0.id == highlightedGameRequestID }) else {
            return source
        }

        var reordered = source
        let highlighted = reordered.remove(at: index)
        reordered.insert(highlighted, at: 0)
        return reordered
    }

    private func prioritizingUser(_ userID: String, in source: [DiscoverUser]) -> [DiscoverUser] {
        guard let index = source.firstIndex(where: { $0.id == userID }) else {
            return source
        }

        var reordered = source
        let highlighted = reordered.remove(at: index)
        reordered.insert(highlighted, at: 0)
        return reordered
    }

    private func prioritizingSearch(_ searchID: String, in source: [DiscoverUser]) -> [DiscoverUser] {
        guard let index = source.firstIndex(where: { $0.gameSearches.contains(where: { $0.id == searchID }) }) else {
            return source
        }

        var reordered = source
        let highlighted = reordered.remove(at: index)
        reordered.insert(highlighted, at: 0)
        return reordered
    }

    private func handleSummaryTap() {
        AppHaptics.selection()
        guard let target = summaryNavigationTarget else {
            return
        }
        if case .discover(.hot, _, _, _) = target {
            notificationManager.markHotEventsOpened()
        }
        appModel.navigate(to: target)
    }

    private func openDiscoverParticipant(_ user: DiscoverUser) {
        guard !isSimilarPlayersHintPresented, !isFirstInterestHintPresented else {
            return
        }
        AppHaptics.selection()
        selectedUpcomingMatch = nil
        selectedUpcomingParticipant = user
    }

    private func markHotEventsSeenIfNeeded() {
        guard selectedTab == .hot, notificationManager.summary.hotBadgeCount > 0 else {
            return
        }

        notificationManager.markHotEventsOpened()
    }

    private func rememberAnnouncedSummarySignature(_ signature: String) {
        var signatures = announcedSummarySignatures
        signatures.insert(signature)

        if signatures.count > 24 {
            signatures = Set(signatures.sorted().suffix(24))
        }

        announcedSummarySignaturesRaw = signatures.sorted().joined(separator: "|")
    }

    private func submitSwipe(_ action: SwipeAction) async {
        guard let activeUser else {
            return
        }
        let swipedUserName = activeUser.displayName

        if !appModel.isAuthenticated && action != .dislike {
            appModel.presentAuth(step: .email)
            return
        }

        dragDecision = action
        switch action {
        case .dislike:
            AppHaptics.notification(.warning)
        case .like:
            AppHaptics.notification(.success)
        case .superlike:
            AppHaptics.impact(.heavy)
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            switch action {
            case .dislike:
                dragOffset = CGSize(width: -340, height: 12)
            case .like:
                dragOffset = CGSize(width: 340, height: 12)
            case .superlike:
                dragOffset = CGSize(width: 0, height: -240)
            }
        }

        try? await Task.sleep(nanoseconds: 180_000_000)

        do {
            let createdMatchId = try await appModel.repository.swipe(userId: activeUser.id, action: action)
            users.removeFirst()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
            if createdMatchId != nil, action == .like {
                showMatchToast("С \(activeUser.displayName) случился новый мэтч.")
            }
            if action == .like || action == .superlike {
                firstInterestHintPlayerName = swipedUserName
                if appModel.queueDiscoverFirstInterestHintIfNeeded() {
                    scheduleFirstInterestHintIfNeeded(playerName: swipedUserName)
                }
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
            dragOffset = .zero
            dragDecision = nil
        }
    }

    private func respond(to search: GameSearch) async {
        guard appModel.isAuthenticated else {
            appModel.presentAuth(step: .email)
            return
        }

        do {
            let response = try await appModel.repository.respondToSearch(searchId: search.id, message: "")
            localResponseStatuses[search.id] = response.status
            localResponseIDs[search.id] = response.id
            AppHaptics.notification(.success)
            showResponseToast("Отклик отправлен. Дальше организатор увидит тебя в своих поисках.")
            await loadDiscover()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func withdrawResponse(searchId: String, responseId: String) async {
        do {
            _ = try await appModel.repository.withdrawSearchResponse(responseId: responseId)
            localResponseStatuses[searchId] = nil
            localResponseIDs[searchId] = nil
            AppHaptics.notification(.warning)
            showResponseToast("Отклик отменён.")
            await loadDiscover()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func handleResponseAction(for search: GameSearch) async {
        let rawStatus = localResponseStatuses[search.id] ?? currentUserResponse(in: search)?.status
        let status = normalizedResponseStatus(rawStatus)
        let responseId = normalizedResponseId(
            status: rawStatus,
            id: localResponseIDs[search.id] ?? currentUserResponse(in: search)?.id
        )

        if status == "pending", let responseId {
            await withdrawResponse(searchId: search.id, responseId: responseId)
            return
        }

        await respond(to: search)
    }

    private func openApprovedRegularPair(for search: GameSearch) {
        guard let regularPairId = search.regularPair?.id else {
            return
        }
        AppHaptics.selection()
        presentedRegularPairID = regularPairId
    }

    private func currentUserResponse(in search: GameSearch) -> SearchResponse? {
        guard let currentUserId = appModel.currentUser?.id else {
            return nil
        }

        return search.responses.first(where: { $0.responderUser.id == currentUserId })
    }

    private func normalizedResponseStatus(_ status: String?) -> String? {
        guard let status else {
            return nil
        }
        return status == "withdrawn" ? nil : status
    }

    private func normalizedResponseId(status: String?, id: String?) -> String? {
        guard status != "withdrawn" else {
            return nil
        }
        return id
    }

    private func showResponseToast(_ message: String) {
        responseMessageTask?.cancel()
        responseMessage = message
        responseMessageTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            if responseMessage == message {
                responseMessage = nil
            }
        }
    }

    private func showMatchToast(_ message: String) {
        matchMessageTask?.cancel()
        matchMessage = message
        matchMessageTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            if matchMessage == message {
                matchMessage = nil
            }
        }
    }

    private func performRefresh() async {
        AppHaptics.impact(.medium)
        refreshSymbols = randomRefreshSymbols()
        isSystemRefreshing = true
        await loadDiscover()
        isSystemRefreshing = false
        scheduleSimilarPlayersHintIfNeeded()
    }

    private func randomRefreshSymbols() -> [String] {
        let pool = Sport.allCases.map(\.ambientSymbol)
        return Array(pool.shuffled().prefix(3))
    }

    private func canManageUpcomingRequest(_ request: MatchGameRequest) -> Bool {
        guard !request.isRegularOccurrence else {
            return false
        }
        let rawStatus = request.status.lowercased()
        guard rawStatus == "pending" || rawStatus == "accepted" || rawStatus == "approved" || rawStatus == "proposed" else {
            return false
        }
        return request.canCancel(currentUserId: appModel.currentUser?.id)
    }

    private func canEditUpcomingRequest(_ request: MatchGameRequest) -> Bool {
        guard canManageUpcomingRequest(request) else {
            return false
        }

        let rawStatus = request.status.lowercased()
        return rawStatus != "canceled" && rawStatus != "cancelled" && rawStatus != "declined" && rawStatus != "rejected"
    }

    private func canShareUpcomingRequest(_ request: MatchGameRequest) -> Bool {
        guard !request.isRegularOccurrence else {
            return false
        }
        guard request.createdByUserId == appModel.currentUser?.id else {
            return false
        }
        return !shareableMatches(for: request).isEmpty
    }

    private func canAcceptUpcomingRequest(_ request: MatchGameRequest) -> Bool {
        guard !request.isRegularOccurrence else {
            return false
        }
        return request.isPendingForRecipient(currentUserId: appModel.currentUser?.id)
    }

    private func shareableMatches(for request: MatchGameRequest) -> [MatchSummary] {
        upcomingMatches.filter { match in
            guard match.id != request.matchId else {
                return false
            }

            let latestStatus = match.latestGameRequest?.status.lowercased()
            return latestStatus != "pending" && latestStatus != "accepted"
        }
    }

    private func cancelUpcomingRequest(_ request: MatchGameRequest) async {
        updatingUpcomingRequestIDs.insert(request.id)
        defer { updatingUpcomingRequestIDs.remove(request.id) }

        do {
            _ = try await appModel.repository.updateGameRequestStatus(gameRequestId: request.id, status: "canceled")
            AppHaptics.notification(.warning)
            if request.createdByUserId == appModel.currentUser?.id {
                showResponseToast("Игра отменена.")
            } else {
                showResponseToast("Отправили, что не сможешь сыграть.")
            }
            await loadDiscover()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func acceptUpcomingRequest(_ request: MatchGameRequest) async {
        updatingUpcomingRequestIDs.insert(request.id)
        defer { updatingUpcomingRequestIDs.remove(request.id) }

        do {
            _ = try await appModel.repository.updateGameRequestStatus(gameRequestId: request.id, status: "accepted")
            AppHaptics.notification(.success)
            showResponseToast("Игра подтверждена.")
            await loadDiscover()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func markUpcomingOutcome(_ request: MatchGameRequest, outcome: String) async {
        updatingUpcomingRequestIDs.insert(request.id)
        defer { updatingUpcomingRequestIDs.remove(request.id) }

        do {
            _ = try await appModel.repository.updateGameRequestOutcome(gameRequestId: request.id, outcome: outcome)
            AppHaptics.notification(outcome == "played" ? .success : .warning)
            showResponseToast(outcome == "played" ? "Отметили, что игра прошла." : "Отметили, что сыграть не удалось.")
            await loadDiscover()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func shareUpcomingRequest(_ request: MatchGameRequest, to matchIds: [String]) async {
        guard !matchIds.isEmpty else {
            return
        }

        updatingUpcomingRequestIDs.insert(request.id)
        defer { updatingUpcomingRequestIDs.remove(request.id) }

        do {
            let created = try await appModel.repository.shareGameRequest(
                gameRequestId: request.rootRequestId ?? request.id,
                matchIds: matchIds
            )
            AppHaptics.notification(.success)
            selectedShareRequest = nil
            showResponseToast(created.count == 1 ? "Приглашение отправлено" : "Приглашения отправлены")
            await loadDiscover()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func dragGesture(for user: DiscoverUser) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isSimilarPlayersHintPresented, !isFirstInterestHintPresented else {
                    return
                }
                guard isHorizontalSwipe(value.translation) else {
                    return
                }
                dragOffset = CGSize(width: value.translation.width, height: 0)
                dragDecision = currentDecision(for: value.translation)
            }
            .onEnded { value in
                guard !isSimilarPlayersHintPresented, !isFirstInterestHintPresented else {
                    return
                }
                guard isHorizontalSwipe(value.translation) else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        dragOffset = .zero
                        dragDecision = nil
                    }
                    return
                }
                let decision = currentDecision(for: value.translation)
                guard let decision else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        dragOffset = .zero
                        dragDecision = nil
                    }
                    return
                }

                Task {
                    _ = user
                    await submitSwipe(decision)
                }
            }
    }

    private func isHorizontalSwipe(_ offset: CGSize) -> Bool {
        abs(offset.width) > 18 && abs(offset.width) > abs(offset.height) * 1.2
    }

    private func currentDecision(for offset: CGSize) -> SwipeAction? {
        if offset.width > 110 {
            return .like
        }
        if offset.width < -110 {
            return .dislike
        }
        return nil
    }

    private func backgroundColor(for tab: DiscoverTab) -> Color {
        guard selectedTab == tab else {
            return .white.opacity(0.8)
        }

        switch tab {
        case .upcoming:
            return AppTheme.court
        case .swipe:
            return AppTheme.ink
        case .likes:
            return Color(red: 0.16, green: 0.50, blue: 0.34)
        case .seeking:
            return AppTheme.clay
        case .hot:
            return .red.opacity(0.9)
        }
    }

    private func foregroundColor(for tab: DiscoverTab) -> Color {
        selectedTab == tab ? .white : AppTheme.ink.opacity(0.65)
    }

    private var tabSwitchGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard selectedTab != .swipe else {
                    return
                }
                guard selectedTab != .likes else {
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else {
                    tabSwipeOffset = 0
                    return
                }
                tabSwipeOffset = min(max(value.translation.width, -180), 180)
            }
            .onEnded { value in
                defer {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                        tabSwipeOffset = 0
                    }
                }
                guard selectedTab != .swipe else {
                    return
                }
                guard selectedTab != .likes else {
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else {
                    return
                }
                if value.translation.width < -90 {
                    switchToNeighborTab(offset: 1)
                } else if value.translation.width > 90 {
                    switchToNeighborTab(offset: -1)
                }
            }
    }

    private func switchToNeighborTab(offset: Int) {
        guard let currentIndex = DiscoverTab.allCases.firstIndex(of: selectedTab) else {
            return
        }
        let nextIndex = min(max(currentIndex + offset, 0), DiscoverTab.allCases.count - 1)
        guard nextIndex != currentIndex else {
            return
        }
        selectTab(DiscoverTab.allCases[nextIndex])
    }

    private func selectTab(_ tab: DiscoverTab) {
        guard tab != selectedTab else {
            return
        }
        withAnimation(.interactiveSpring(response: 0.46, dampingFraction: 0.88, blendDuration: 0.12)) {
            selectedTab = tab
            tabSwipeOffset = 0
        }
    }
}

private struct DiscoverSimilarPlayersHintOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 760
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let maxPanelWidth = min(geometry.size.width - 28, 370)
            let instructionY = max(
                safeTop + (isCompact ? 118 : 132),
                geometry.size.height * (isCompact ? 0.18 : 0.17)
            )
            let actionY = min(
                max(geometry.size.height * (isCompact ? 0.54 : 0.56), isCompact ? 380 : 440),
                geometry.size.height - 230
            )

            ZStack {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        AppTheme.court.opacity(0.08),
                        Color.black.opacity(0.56)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 10) {
                    Text("Смахивай карточки, чтобы выбирать игроков")
                        .font(.system(size: isCompact ? 17 : 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: maxPanelWidth)
                .position(x: geometry.size.width / 2, y: instructionY)

                HStack(alignment: .top) {
                    TutorialSwipeActionCue(
                        title: "не\nподходит",
                        systemImage: "xmark",
                        tint: Color(red: 1.0, green: 0.34, blue: 0.38),
                        textAlignment: .leading
                    )

                    Spacer(minLength: 0)

                    TutorialSwipeActionCue(
                        title: "интересно\nсыграть",
                        systemImage: "heart.fill",
                        tint: Color(red: 0.52, green: 0.92, blue: 0.38),
                        textAlignment: .trailing
                    )
                }
                .padding(.horizontal, isCompact ? 18 : 24)
                .frame(width: geometry.size.width)
                .position(x: geometry.size.width / 2, y: actionY)

                VStack {
                    Spacer()

                    Button("Понятно") {
                        onDismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.68, green: 0.96, blue: 0.42),
                                Color(red: 0.48, green: 0.84, blue: 0.3)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(18, safeBottom + 18))
                }
            }
            .contentShape(Rectangle())
        }
    }
}

private struct DiscoverFirstInterestHintOverlay: View {
    let playerName: String?
    let onDismiss: () -> Void

    private var recipientText: String {
        if let playerName {
            let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "игроку"
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 760
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let panelWidth = min(geometry.size.width - 28, 386)
            let contentWidth = panelWidth - 48

            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.3),
                        AppTheme.court.opacity(0.2),
                        Color.black.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    Spacer(minLength: safeTop + (isCompact ? 54 : 74))

                    VStack(spacing: isCompact ? 15 : 19) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.court.opacity(0.18))
                                .frame(width: isCompact ? 78 : 86, height: isCompact ? 78 : 86)
                                .overlay(
                                    Circle()
                                        .stroke(Color(red: 0.52, green: 0.92, blue: 0.38).opacity(0.82), lineWidth: 1.5)
                                )
                                .shadow(color: Color(red: 0.52, green: 0.92, blue: 0.38).opacity(0.34), radius: 18, x: 0, y: 0)

                            Image(systemName: "paperplane.fill")
                                .font(.system(size: isCompact ? 29 : 32, weight: .bold))
                                .foregroundStyle(Color(red: 0.58, green: 0.96, blue: 0.36))
                                .rotationEffect(.degrees(-10))
                        }

                        VStack(spacing: 8) {
                            Text("Спортивный интерес\nотправлен")
                                .font(.system(size: isCompact ? 23 : 26, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Мы покажем \(recipientText), что ты готов сыграть. Если интерес будет взаимным, вы сможете общаться в «Мэтчи».")
                                .font(.system(size: isCompact ? 15 : 16, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.86))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: contentWidth)

                        HStack(alignment: .top, spacing: 8) {
                            InterestStepView(
                                systemImage: "checkmark.circle.fill",
                                title: "Отметил",
                                tint: Color(red: 0.58, green: 0.96, blue: 0.36)
                            )

                            InterestArrow()

                            InterestStepView(
                                systemImage: "paperplane.fill",
                                title: "Ждем",
                                tint: Color(red: 0.58, green: 0.96, blue: 0.36)
                            )

                            InterestArrow()

                            InterestStepView(
                                systemImage: "bell.fill",
                                title: "Увидит",
                                tint: Color(red: 0.58, green: 0.96, blue: 0.36)
                            )
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 10) {
                            Label {
                                Text("Что дальше?")
                                    .font(.headline.weight(.bold))
                            } icon: {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(red: 0.58, green: 0.96, blue: 0.36))
                            }
                            .foregroundStyle(.white)

                            Text("Когда интерес станет взаимным, игрок появится в разделе «Мэтчи». Там можно обсудить спорт, удобное время и место.")
                                .font(.system(size: isCompact ? 14 : 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(AppTheme.court.opacity(0.22), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color(red: 0.58, green: 0.96, blue: 0.36).opacity(0.34), lineWidth: 1)
                        )

                        Button("Понятно") {
                            onDismiss()
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.68, green: 0.96, blue: 0.42),
                                    Color(red: 0.48, green: 0.84, blue: 0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, isCompact ? 20 : 24)
                    .frame(width: panelWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .fill(AppTheme.court.opacity(0.1))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color(red: 0.52, green: 0.92, blue: 0.38).opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.44), radius: 24, x: 0, y: 20)

                    Spacer(minLength: max(18, safeBottom + 18))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}

private struct InterestStepView: View {
    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct InterestArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color(red: 0.58, green: 0.96, blue: 0.36))
            .frame(width: 18, height: 54)
    }
}

private struct TutorialSwipeDecisionZones: View {
    var body: some View {
        GeometryReader { geometry in
            let zoneWidth = min(max(geometry.size.width * 0.5, 170), 212)
            let zoneHeight = min(max(geometry.size.height * 0.9, 420), 520)

            ZStack {
                zoneCard(
                    tint: Color(red: 1.0, green: 0.34, blue: 0.38),
                    rotation: -3.5
                )
                .frame(width: zoneWidth, height: zoneHeight)
                .position(x: zoneWidth * 0.5, y: geometry.size.height / 2 + 2)

                zoneCard(
                    tint: Color(red: 0.52, green: 0.92, blue: 0.38),
                    rotation: 3.5
                )
                .frame(width: zoneWidth, height: zoneHeight)
                .position(x: geometry.size.width - zoneWidth * 0.5, y: geometry.size.height / 2 + 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func zoneCard(tint: Color, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(tint.opacity(0.24))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(tint.opacity(0.86), lineWidth: 1.6)
            )
            .shadow(color: tint.opacity(0.35), radius: 16, x: 0, y: 8)
            .rotationEffect(.degrees(rotation))
    }
}

private struct TutorialSwipeActionCue: View {
    let title: String
    let systemImage: String
    let tint: Color
    let textAlignment: TextAlignment

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(
                    RadialGradient(
                        colors: [tint.opacity(0.9), tint.opacity(0.54)],
                        center: .center,
                        startRadius: 4,
                        endRadius: 42
                    ),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.45), radius: 14, x: 0, y: 6)

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .multilineTextAlignment(textAlignment)
        }
        .frame(width: 94)
    }
}

private struct SportRefreshIndicator: View {
    let progress: CGFloat
    let isRefreshing: Bool
    let symbols: [String]

    @State private var animateBounce = false

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.72))
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

            HStack(spacing: 7) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: index == 1 ? 24 : 20))
                        .foregroundStyle(AppTheme.softWhite)
                        .scaleEffect(0.9 + progress * 0.16)
                        .rotationEffect(.degrees(isRefreshing ? (animateBounce ? 10 : -10) : Double((progress - 0.5) * 10)))
                        .offset(
                            x: index == 1 ? 0 : CGFloat(index == 0 ? -2 : 2),
                            y: isRefreshing
                                ? (animateBounce ? CGFloat(-4 - index) : CGFloat(4 - index))
                                : (1 - progress) * -8
                        )
                        .animation(
                            isRefreshing
                                ? .easeInOut(duration: 0.54).repeatForever(autoreverses: true).delay(Double(index) * 0.05)
                                : .interactiveSpring(response: 0.28, dampingFraction: 0.84),
                            value: animateBounce
                        )
                }
            }
        }
        .frame(width: 86, height: 44)
        .onAppear {
            if isRefreshing {
                animateBounce = true
            }
        }
        .onChange(of: isRefreshing) { value in
            animateBounce = value
        }
    }
}

private struct TennisBallIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.84, green: 0.98, blue: 0.34))

            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: 1.4)

            ballStripe(offset: -6)
            ballStripe(offset: 6)
        }
    }

    private func ballStripe(offset: CGFloat) -> some View {
        Ellipse()
            .trim(from: 0.2, to: 0.8)
            .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            .frame(width: 18, height: 28)
            .offset(x: offset)
    }
}

private struct RefreshProgressObserver: UIViewRepresentable {
    @Binding var progress: CGFloat
    @Binding var isRefreshing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(progress: $progress, isRefreshing: $isRefreshing)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attachIfNeeded(from: uiView)
    }

    final class Coordinator {
        private let progress: Binding<CGFloat>
        private let isRefreshing: Binding<Bool>
        private weak var scrollView: UIScrollView?
        private weak var refreshControl: UIRefreshControl?
        private var observation: NSKeyValueObservation?

        init(progress: Binding<CGFloat>, isRefreshing: Binding<Bool>) {
            self.progress = progress
            self.isRefreshing = isRefreshing
        }

        func attachIfNeeded(from view: UIView) {
            guard scrollView == nil else {
                syncRefreshState()
                return
            }

            DispatchQueue.main.async {
                guard self.scrollView == nil else {
                    self.syncRefreshState()
                    return
                }
                guard let scrollView = self.enclosingScrollView(from: view) else {
                    return
                }

                self.scrollView = scrollView
                self.refreshControl = scrollView.refreshControl
                self.refreshControl?.tintColor = .clear
                self.refreshControl?.attributedTitle = NSAttributedString(string: " ")

                self.observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    self?.handleContentOffsetChange(scrollView)
                }
                self.handleContentOffsetChange(scrollView)
            }
        }

        private func handleContentOffsetChange(_ scrollView: UIScrollView) {
            let overscroll = max(-(scrollView.contentOffset.y + scrollView.adjustedContentInset.top), 0)
            let normalized = min(overscroll / 42, 1)

            DispatchQueue.main.async {
                self.progress.wrappedValue = self.isRefreshing.wrappedValue ? 1 : normalized
                self.syncRefreshState()
            }
        }

        private func syncRefreshState() {
            let controlRefreshing = refreshControl?.isRefreshing ?? false
            if isRefreshing.wrappedValue != controlRefreshing {
                isRefreshing.wrappedValue = controlRefreshing
            }
            if !controlRefreshing, progress.wrappedValue < 0.01 {
                progress.wrappedValue = 0
            }
        }

        private func enclosingScrollView(from view: UIView) -> UIScrollView? {
            var current = view.superview
            while let currentView = current {
                if let scrollView = currentView as? UIScrollView {
                    return scrollView
                }
                current = currentView.superview
            }
            return nil
        }
    }
}


private struct MyEventsToolbarButton: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.court)

            Text("Мои")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(count > 0 ? AppTheme.court : .white.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
    }
}

private struct DiscoverScrollOffsetReader: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: DiscoverScrollOffsetPreferenceKey.self,
                    value: max(-geometry.frame(in: .named("discover-scroll")).minY, 0)
                )
        }
        .frame(height: 0)
    }
}

private struct DiscoverScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DiscoverSummaryAttentionItem {
    let count: Int
    let title: String
    let subtitle: String
    let target: AppNavigationTarget
}

private enum DiscoverSummaryCardState {
    case upcoming(MatchGameRequest)
    case attention(count: Int, title: String, subtitle: String)
    case idle
}

private struct DiscoverSummaryCard: View {
    let state: DiscoverSummaryCardState
    let maxWidth: CGFloat
    var compact = false
    var islandStyle = false
    var pulse = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: compact ? 10 : 14) {
                ZStack {
                    Circle()
                        .fill(iconSurfaceColor)
                        .frame(width: compact ? 32 : 46, height: compact ? 32 : 46)

                    Image(systemName: iconName)
                        .font(.system(size: compact ? 14 : 20, weight: .semibold))
                        .foregroundStyle(iconColor)

                    if let attentionCount, attentionCount > 1 {
                        Text("\(min(attentionCount, 99))")
                            .font(.system(size: compact ? 9 : 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .offset(x: compact ? 15 : 18, y: compact ? -15 : -18)
                    }
                }

                VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                    Text(eyebrow)
                        .font((compact ? Font.system(size: 10, weight: .bold) : .caption.weight(.bold)))
                        .foregroundStyle(accentColor)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(title)
                        .font(.system(size: compact ? 14 : 19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.78)

                    Text(subtitle)
                        .font(.system(size: compact ? 10 : 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.76)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: compact ? 13 : 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 8 : 15)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(backgroundGradient, in: RoundedRectangle(cornerRadius: islandStyle ? 26 : (compact ? 20 : 24), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: islandStyle ? 26 : (compact ? 20 : 24), style: .continuous)
                    .stroke(borderColor, lineWidth: pulse ? 1.4 : 1)
            )
            .shadow(color: shadowColor, radius: compact ? 12 : 18, x: 0, y: compact ? 6 : 10)
            .scaleEffect(pulse ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .buttonStyle(ElasticIslandButtonStyle())
        .disabled(!showsChevron)
    }

    private var eyebrow: String {
        switch state {
        case .upcoming:
            return "Ближайшая игра"
        case .attention:
            return "Требует внимания"
        case .idle:
            return "Всё спокойно"
        }
    }

    private var attentionCount: Int? {
        switch state {
        case .attention(let count, _, _):
            return count
        case .upcoming, .idle:
            return nil
        }
    }

    private var title: String {
        switch state {
        case .upcoming(let request):
            guard let date = request.proposedDate else {
                return "Игра подтверждена"
            }
            return relativeSummaryDate(for: date)
        case .attention(_, let title, _):
            return title
        case .idle:
            return "Новых событий нет"
        }
    }

    private var subtitle: String {
        switch state {
        case .upcoming(let request):
            return request.proposedCourt?.name ?? request.otherUser(currentUserId: nil)?.name ?? "Открой ближайшие игры"
        case .attention(_, _, let subtitle):
            return subtitle
        case .idle:
            return "Можно продолжить поиск"
        }
    }

    private var iconName: String {
        switch state {
        case .upcoming:
            return "calendar"
        case .attention:
            return "clock.badge.exclamationmark"
        case .idle:
            return "cup.and.saucer.fill"
        }
    }

    private var accentColor: Color {
        switch state {
        case .upcoming:
            return Color(red: 0.51, green: 0.92, blue: 0.54)
        case .attention:
            return Color(red: 1.0, green: 0.63, blue: 0.23)
        case .idle:
            return Color(red: 0.62, green: 0.69, blue: 0.79)
        }
    }

    private var iconColor: Color {
        accentColor
    }

    private var iconSurfaceColor: Color {
        accentColor.opacity(0.18)
    }

    private var backgroundGradient: LinearGradient {
        switch state {
        case .upcoming:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.18, blue: 0.10), Color(red: 0.07, green: 0.23, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .attention:
            return LinearGradient(
                colors: [Color(red: 0.19, green: 0.11, blue: 0.04), Color(red: 0.22, green: 0.13, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .idle:
            return LinearGradient(
                colors: [Color.white.opacity(0.05), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        switch state {
        case .attention:
            return pulse ? accentColor.opacity(0.9) : Color.white.opacity(0.08)
        case .upcoming, .idle:
            return Color.white.opacity(0.08)
        }
    }

    private var shadowColor: Color {
        switch state {
        case .attention:
            return pulse ? accentColor.opacity(0.32) : .black.opacity(0.22)
        case .upcoming, .idle:
            return .black.opacity(0.22)
        }
    }

    private var showsChevron: Bool {
        switch state {
        case .idle:
            return false
        case .upcoming, .attention:
            return true
        }
    }

    private func relativeSummaryDate(for date: Date) -> String {
        let calendar = Calendar.current
        let prefix: String

        if calendar.isDateInToday(date) {
            prefix = "Сегодня"
        } else if calendar.isDateInTomorrow(date) {
            prefix = "Завтра"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ru_RU")
            dateFormatter.dateFormat = "d MMM"
            prefix = dateFormatter.string(from: date)
        }

        return "\(prefix), \(date.formattedHourMinute())"
    }
}

private struct ElasticIslandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: configuration.isPressed ? 0.95 : 1,
                y: configuration.isPressed ? 1.03 : 1,
                anchor: .center
            )
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

private struct SwipeHintBar: View {
    var leftTitle = "Влево — пропустить"
    var rightTitle = "Вправо — можно сыграть"
    var isHighlighted = false

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "arrow.left")
                Text(leftTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(isHighlighted ? Color(red: 1.0, green: 0.34, blue: 0.38) : .white.opacity(0.38))

            Spacer()

            HStack(spacing: 5) {
                Text(rightTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(isHighlighted ? Color(red: 0.55, green: 0.92, blue: 0.38) : .white.opacity(0.38))
        }
        .font(.caption.weight(isHighlighted ? .bold : .semibold))
        .lineLimit(1)
        .padding(.horizontal, 8)
    }
}

private struct CompactUpcomingHistoryRow: View {
    let request: MatchGameRequest
    let displayName: String
    let avatarURL: String?
    let onOpenChat: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            RemoteAvatarView(name: displayName, path: avatarURL, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    AppInlineChip(text: request.statusLabel, tint: request.statusTintColor, foreground: .white)
                }

                Text(request.proposedDatetime.formattedNumericDateTime())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let onOpenChat {
                Button(action: onOpenChat) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct GameParticipantStatusRow: Identifiable {
    let user: DiscoverUser
    let status: GameParticipantStatus

    var id: String { user.id }
}

private struct GameParticipantStatus {
    let label: String
    let tint: Color
}

private struct GameParticipantStatusPill: View {
    let status: GameParticipantStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(status.tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(status.tint.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(status.tint.opacity(0.32), lineWidth: 1)
            )
    }
}

private struct UpcomingWidgetPromptCard: View {
    let hasUpcomingGames: Bool
    let onOpenHelp: () -> Void

    var body: some View {
        Button(action: onOpenHelp) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.28), AppTheme.court.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)

                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Виджет ближайших игр")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(hasUpcomingGames ? "Покажем следующую игру прямо на главном экране iPhone." : "Добавь виджет сейчас, он заполнится после первой подтвержденной игры.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.green.opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct UpcomingWidgetHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Color.green)
                        .frame(width: 64, height: 64)
                        .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Добавь виджет")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Ближайшая игра будет видна без открытия приложения.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.1), in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Закрыть")
                }

                VStack(alignment: .leading, spacing: 12) {
                    WidgetInstructionRow(index: 1, text: "Зажми пустое место на главном экране iPhone.")
                    WidgetInstructionRow(index: 2, text: "Нажми «+» и найди SportSearch.")
                    WidgetInstructionRow(index: 3, text: "Выбери «Ближайшие игры» и добавь на экран.")
                }
                .padding(16)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )

                Text("Данные обновляются после открытия раздела «Ближайшие игры» и после изменений в играх.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Понятно")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .foregroundStyle(Color.black.opacity(0.9))
                .background(
                    LinearGradient(colors: [Color.green, Color(red: 0.49, green: 0.86, blue: 0.22)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct WidgetInstructionRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.88))
                .frame(width: 26, height: 26)
                .background(Color.green, in: Circle())

            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UpcomingGameDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let request: MatchGameRequest
    let displayName: String
    let avatarURL: String?
    let isUpdating: Bool
    let canEdit: Bool
    let canCancel: Bool
    let cancelTitle: String
    let onEdit: (() -> Void)?
    let onCancel: (() async -> Void)?
    let onParticipantsChanged: () async -> Void

    @State private var lobby: SearchLobbyGameSearch?
    @State private var isLoadingLobby = false
    @State private var updatingResponseID: String?

    private var statusTint: Color {
        request.statusTintColor
    }

    private var participantRows: [GameParticipantStatusRow] {
        var rows: [GameParticipantStatusRow] = []
        var seen = Set<String>()

        func append(_ user: DiscoverUser, status: GameParticipantStatus) {
            guard seen.insert(user.id).inserted else {
                return
            }
            rows.append(GameParticipantStatusRow(user: user, status: status))
        }

        for participant in request.participants {
            append(participant, status: status(for: participant))
        }

        for invitee in request.invitees {
            append(invitee.user, status: .init(label: invitee.statusLabel, tint: invitee.statusTint))
        }

        return rows
    }

    var body: some View {
        ZStack {
            sheetBackground

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(width: 46, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    header
                    actionButtons

                    VStack(spacing: 12) {
                        detailRow(
                            icon: "calendar",
                            title: request.proposedDatetime.formattedDateTime(),
                            subtitle: countdownText
                        )
                        detailRow(
                            icon: "sportscourt.fill",
                            title: request.proposedCourt?.name ?? request.sport.venuePendingTitle,
                            subtitle: request.proposedCourt?.address
                        )
                        detailRow(
                            icon: "checkmark.circle",
                            title: request.statusLabel,
                            subtitle: request.nextStepLabel
                        )
                        detailRow(
                            icon: "questionmark.circle.fill",
                            title: request.sport.formatTitle(format: request.format),
                            subtitle: request.sport.title
                        )
                    }

                    if !participantRows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Участники")
                                .font(.caption.weight(.bold))
                                .textCase(.uppercase)
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.58))

                            ForEach(participantRows.prefix(8)) { row in
                                HStack(spacing: 12) {
                                    RemoteAvatarView(name: row.user.displayName, path: row.user.avatarUrl, size: 42)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.user.displayName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)

                                        Text(row.status.label)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(row.status.tint)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    GameParticipantStatusPill(status: row.status)
                                }
                                .padding(12)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }

                    searchResponseApprovalSection

                    if let comment = request.comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Комментарий")
                                .font(.caption.weight(.bold))
                                .textCase(.uppercase)
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.58))
                            Text(comment)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: request.searchLobbyId) {
            await loadSearchLobbyIfNeeded()
        }
    }

    private var sheetBackground: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            RadialGradient(
                colors: [statusTint.opacity(0.26), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 360
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color(red: 0.03, green: 0.04, blue: 0.04), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if canEdit || canCancel {
            HStack(spacing: 10) {
                if canEdit, let onEdit {
                    Button(action: onEdit) {
                        Label("Изменить игру", systemImage: "calendar.badge.clock")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .foregroundStyle(.white)
                    .background(AppTheme.court, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .buttonStyle(.plain)
                }

                if canCancel, let onCancel {
                    Button {
                        Task {
                            await onCancel()
                        }
                    } label: {
                        Group {
                            if isUpdating {
                                ProgressView()
                                    .tint(Color(red: 1.0, green: 0.47, blue: 0.43))
                            } else {
                                Label(cancelTitle, systemImage: "xmark.circle")
                            }
                        }
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.47, blue: 0.43))
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(red: 1.0, green: 0.47, blue: 0.43).opacity(0.34), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                    .disabled(isUpdating)
                }
            }
        }
    }

    private func status(for participant: DiscoverUser) -> GameParticipantStatus {
        if let invitee = request.invitees.first(where: { $0.user.id == participant.id }) {
            return GameParticipantStatus(label: invitee.statusLabel, tint: invitee.statusTint)
        }

        if participant.id == request.createdByUserId {
            return GameParticipantStatus(label: "Организатор", tint: Color(red: 0.63, green: 0.93, blue: 0.75))
        }

        if participant.id == request.matchedUserId {
            return primaryRecipientStatus
        }

        return GameParticipantStatus(label: "Участник", tint: .white.opacity(0.64))
    }

    private var primaryRecipientStatus: GameParticipantStatus {
        switch request.status.lowercased() {
        case "accepted", "approved":
            return GameParticipantStatus(label: "Принял", tint: AppTheme.court)
        case "declined", "rejected":
            return GameParticipantStatus(label: "Отклонил", tint: .red.opacity(0.88))
        case "canceled", "cancelled", "withdrawn":
            return GameParticipantStatus(label: "Отменено", tint: .gray.opacity(0.82))
        default:
            return GameParticipantStatus(label: "Ожидаем ответ", tint: Color(red: 1.0, green: 0.70, blue: 0.30))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                RemoteAvatarView(name: displayName, path: avatarURL, size: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text("\(request.sport.title) · \(request.sport.formatTitle(format: request.format))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.74))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                AppInlineChip(text: request.statusLabel, tint: statusTint, foreground: .white)
                AppInlineChip(text: request.sport.title, tint: .white.opacity(0.10), foreground: .white)
                AppInlineChip(text: request.sport.formatTitle(format: request.format), tint: .white.opacity(0.10), foreground: .white)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.14, green: 0.15, blue: 0.15), Color(red: 0.06, green: 0.07, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(statusTint.opacity(0.65), lineWidth: 1)
        )
    }

    private var countdownText: String? {
        request.startsInMinutesText()
    }

    @ViewBuilder
    private var searchResponseApprovalSection: some View {
        if isLoadingLobby {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppTheme.court)
                Text("Загружаем отклики")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if let lobby, !lobby.responses.isEmpty {
            let pending = lobby.responses.filter { $0.status == "pending" }
            let approved = lobby.responses.filter { $0.status == "approved" }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Отклики на поиск")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Text("\(approved.count) в составе")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.court)
                }

                ForEach((pending.isEmpty ? approved : pending).prefix(6)) { response in
                    pendingResponseRow(response)
                }
            }
            .padding(14)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.court.opacity(pending.isEmpty ? 0.12 : 0.28), lineWidth: 1)
            )
        }
    }

    private func pendingResponseRow(_ response: SearchResponse) -> some View {
        HStack(spacing: 12) {
            RemoteAvatarView(name: response.responderUser.displayName, path: response.responderUser.avatarUrl, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(response.responderUser.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(response.status == "approved" ? "Уже в составе" : "Ждёт решения")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(response.status == "approved" ? AppTheme.court : Color(red: 1.0, green: 0.70, blue: 0.30))
            }

            Spacer()

            if response.status == "pending" {
                HStack(spacing: 8) {
                    responseActionButton(response: response, status: "approved", systemImage: "checkmark", tint: AppTheme.court, foreground: .white)
                    responseActionButton(response: response, status: "rejected", systemImage: "xmark", tint: Color(red: 0.25, green: 0.10, blue: 0.10), foreground: Color(red: 1.0, green: 0.47, blue: 0.43))
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.court)
            }
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func responseActionButton(response: SearchResponse, status: String, systemImage: String, tint: Color, foreground: Color) -> some View {
        Button {
            Task {
                await updateSearchResponse(response, status: status)
            }
        } label: {
            ZStack {
                if updatingResponseID == response.id {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .black))
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(tint, in: Circle())
        .disabled(updatingResponseID != nil)
    }

    private func loadSearchLobbyIfNeeded() async {
        guard let searchLobbyId = request.searchLobbyId else {
            return
        }

        isLoadingLobby = true
        defer { isLoadingLobby = false }

        do {
            lobby = try await appModel.repository.fetchSearchLobby(searchId: searchLobbyId).gameSearch
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func updateSearchResponse(_ response: SearchResponse, status: String) async {
        updatingResponseID = response.id
        defer { updatingResponseID = nil }

        do {
            _ = try await appModel.repository.updateSearchResponseStatus(responseId: response.id, status: status)
            AppHaptics.notification(status == "approved" ? .success : .warning)
            await loadSearchLobbyIfNeeded()
            await onParticipantsChanged()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func detailRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(red: 0.63, green: 0.93, blue: 0.75))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SwipeCard: View {
    let user: DiscoverUser
    let index: Int
    let dragOffset: CGSize
    let decision: SwipeAction?

    private var swipeStrength: CGFloat {
        min(abs(dragOffset.width) / 170, 1)
    }

    private var leftSwipeProgress: CGFloat {
        min(max(-dragOffset.width, 0) / 170, 1)
    }

    private var rightSwipeProgress: CGFloat {
        min(max(dragOffset.width, 0) / 170, 1)
    }

    private var centerSwipeText: String? {
        if leftSwipeProgress > 0.05 {
            return "Пропустить"
        }
        if rightSwipeProgress > 0.05 {
            return "Можно сыграть"
        }
        return nil
    }

    private var centerSwipeTextOpacity: CGFloat {
        max(leftSwipeProgress, rightSwipeProgress)
    }

    private var contentParallaxX: CGFloat {
        dragOffset.width * 0.045
    }

    private var contentParallaxY: CGFloat {
        -min(abs(dragOffset.width) * 0.02, 8)
    }

    private var accentColor: Color {
        guard let firstSport = user.preferredSports.first else {
            return AppTheme.court
        }

        switch firstSport {
        case .tennis, .padel:
            return AppTheme.court
        case .squash, .boxing:
            return AppTheme.clay
        case .badminton, .fitness:
            return Color(red: 0.24, green: 0.52, blue: 0.88)
        case .volleyball, .football:
            return Color(red: 0.78, green: 0.61, blue: 0.18)
        case .tableTennis:
            return Color(red: 0.16, green: 0.63, blue: 0.72)
        case .yoga:
            return Color(red: 0.56, green: 0.36, blue: 0.74)
        }
    }

    var body: some View {
        VStack {
            cardSurface
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.white.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.74), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .rotationEffect(.degrees(index == 0 ? Double(dragOffset.width / 22) : 0))
        .offset(dragOffset)
        .shadow(color: AppTheme.ink.opacity(index == 0 ? 0.18 : 0.08), radius: 24, x: 0, y: 14)
    }

    private var cardSurface: some View {
        cardContent
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .offset(x: contentParallaxX, y: contentParallaxY)
            .background {
                cardBackground
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(decisionOverlay)
            }
            .overlay(alignment: .topLeading) {
                if index == 0 {
                    decisionBadge
                        .padding(16)
                }
            }
            .overlay(alignment: .bottom) {
                if let centerSwipeText {
                    bottomDecisionText(text: centerSwipeText)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBlock
            metaTags
            sportsBlock
            if !user.explainabilityReasons.isEmpty {
                reasonsBlock
            }
            bioBlock
            Spacer()
        }
    }

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            RemoteAvatarView(name: user.displayName, path: user.avatarUrl, size: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                if let score = user.score {
                    Text("Скор \(Int(score.rounded()))")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white.opacity(0.94))
                }

                Text(user.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let age = user.age {
                        Text("\(age) лет")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(user.city ?? "Город не указан")
                        .font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var metaTags: some View {
        HStack(spacing: 8) {
            ForEach(Array(user.districtDisplayNames.prefix(2)), id: \.self) { district in
                GlassTag(text: district)
            }
            Spacer(minLength: 0)
        }
    }

    private var sportsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            AutoScrollingSportChips(
                sports: Array(user.preferredSports.prefix(3)),
                levelProvider: { sport in
                    user.sportLevels[sport.rawValue] ?? user.tennisLevel
                }
            )
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in }
                .onEnded { _ in }
        )
    }

    private var bioBlock: some View {
        Text(user.bio ?? "Готов быстро договориться и выйти на игру без лишних шагов.")
            .font(.body)
            .foregroundStyle(.white.opacity(0.84))
            .lineSpacing(2)
            .lineLimit(3)
    }

    private var reasonsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Почему в подборе")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.72))

            ForEach(user.explainabilityReasons.prefix(2), id: \.self) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(.white.opacity(0.7))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(reason)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor, AppTheme.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            SwipeCardAmbientLayer(accent: accentColor, dragOffset: dragOffset, sports: user.preferredSports)
        }
    }

    private func bottomDecisionText(text: String) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .opacity(centerSwipeTextOpacity)
            .scaleEffect(0.92 + centerSwipeTextOpacity * 0.08)
            .padding(.bottom, 18)
    }

    @ViewBuilder
    private var decisionBadge: some View {
        switch decision {
        case .dislike:
            GlassDecision(text: "Пропустить", tint: .white)
        case .like:
            GlassDecision(text: "Можно сыграть", tint: Color(red: 0.83, green: 1, blue: 0.88))
        case .superlike:
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    private var decisionOverlay: LinearGradient {
        let tint: Color
        switch decision {
        case .dislike:
            tint = .red
        case .like:
            tint = .green
        default:
            tint = .clear
        }

        return LinearGradient(
            colors: [tint.opacity(0.28 * swipeStrength), .clear, tint.opacity(0.12 * swipeStrength)],
            startPoint: dragOffset.width >= 0 ? .topLeading : .topTrailing,
            endPoint: dragOffset.width >= 0 ? .bottomTrailing : .bottomLeading
        )
    }
}

private struct AutoScrollingSportChips: View {
    let sports: [Sport]
    let levelProvider: (Sport) -> Int?

    @State private var trackWidth: CGFloat = 0
    @State private var shouldAnimate = false

    private let spacing: CGFloat = 8
    private let pointsPerSecond: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let needsAnimation = sports.count > 1 && trackWidth > availableWidth && availableWidth > 0

            Group {
                if needsAnimation {
                    marqueeRow(availableWidth: availableWidth)
                        .mask(fadeMask)
                } else {
                    chipRow
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: availableWidth, height: 38, alignment: .leading)
            .clipped()
            .onAppear {
                restartAnimationIfNeeded(availableWidth: availableWidth)
            }
            .onChange(of: trackWidth) { _ in
                restartAnimationIfNeeded(availableWidth: availableWidth)
            }
            .onChange(of: availableWidth) { _ in
                restartAnimationIfNeeded(availableWidth: availableWidth)
            }
        }
        .frame(height: 38)
    }

    private var chipRow: some View {
        HStack(spacing: spacing) {
            ForEach(sports) { sport in
                SportLevelMiniChip(sport: sport, level: levelProvider(sport))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SportChipTrackWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(SportChipTrackWidthPreferenceKey.self) { value in
            trackWidth = value
        }
    }

    private func marqueeRow(availableWidth: CGFloat) -> some View {
        HStack(spacing: spacing) {
            chipRow
            chipRow
        }
        .offset(x: shouldAnimate ? -(trackWidth + spacing) : 0)
        .frame(width: availableWidth, alignment: .leading)
        .animation(
            .linear(duration: max(Double((trackWidth + spacing) / pointsPerSecond), 14))
                .repeatForever(autoreverses: false),
            value: shouldAnimate
        )
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func restartAnimationIfNeeded(availableWidth: CGFloat) {
        let needsAnimation = sports.count > 1 && trackWidth > availableWidth && availableWidth > 0
        guard needsAnimation else {
            shouldAnimate = false
            return
        }

        shouldAnimate = false
        DispatchQueue.main.async {
            shouldAnimate = true
        }
    }
}

private struct SportChipTrackWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SwipeCardAmbientLayer: View {
    let accent: Color
    let dragOffset: CGSize
    let sports: [Sport]

    private var floatingSymbols: [String] {
        let tokens = sports.prefix(3).map(\.ambientSymbol)
        return tokens.isEmpty ? [Sport.tennis.ambientSymbol] : Array(tokens)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let horizontalBias = dragOffset.width * 0.04

            ZStack {
                Circle()
                    .fill(accent.opacity(0.28))
                    .frame(width: 220, height: 220)
                    .blur(radius: 26)
                    .offset(
                        x: -124 + CGFloat(sin(time * 0.7)) * 18 + horizontalBias,
                        y: -112 + CGFloat(cos(time * 0.9)) * 12
                    )

                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 170, height: 170)
                    .blur(radius: 22)
                    .offset(
                        x: 132 + CGFloat(cos(time * 0.56)) * 14 - horizontalBias * 0.4,
                        y: 118 + CGFloat(sin(time * 0.82)) * 10
                    )

                if let first = floatingSymbols.first {
                    Text(first)
                        .font(.system(size: 46))
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                        .rotationEffect(.degrees(-8 + sin(time * 0.84) * 6))
                        .offset(x: 118 + CGFloat(cos(time * 0.66)) * 12, y: -78 + CGFloat(sin(time * 0.9)) * 8)
                }

                if floatingSymbols.count > 1 {
                    Text(floatingSymbols[1])
                        .font(.system(size: 30))
                        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
                        .rotationEffect(.degrees(12 + cos(time * 0.92) * 7))
                        .offset(x: -112 + CGFloat(sin(time * 0.74)) * 10, y: 96 + CGFloat(cos(time * 0.8)) * 8)
                }

                if floatingSymbols.count > 2 {
                    Text(floatingSymbols[2])
                        .font(.system(size: 24))
                        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 3)
                        .rotationEffect(.degrees(-14 + sin(time * 0.88) * 8))
                        .offset(x: -18 + CGFloat(cos(time * 0.69)) * 8, y: -132 + CGFloat(sin(time * 0.78)) * 8)
                }

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.14), .clear, .black.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .allowsHitTesting(false)
        }
    }
}

private extension Sport {
    var ambientSymbol: String {
        switch self {
        case .tennis:
            return "🎾"
        case .football:
            return "⚽"
        case .boxing:
            return "🥊"
        case .badminton:
            return "🏸"
        case .volleyball:
            return "🏐"
        case .tableTennis:
            return "🏓"
        case .padel:
            return "🎾"
        case .squash:
            return "🎾"
        case .fitness:
            return "🏋️"
        case .yoga:
            return "🧘"
        }
    }
}

private struct SeekingSearchCard: View {
    let user: DiscoverUser
    let search: GameSearch
    let variant: DiscoverTab
    let responseStatus: String?
    let responseId: String?
    let onOpenApprovedChat: () -> Void
    let action: () -> Void

    private var hotCountdownLabel: String? {
        guard search.searchType == .hot, let startsAt = search.hotStartsAt else {
            return nil
        }
        return startsAt.formattedDateTime()
    }

    private var rosterLabel: String {
        let approvedResponses = search.responses.filter { $0.status == "approved" }.count
        if search.playersNeeded > 1 {
            return "Собрано \(approvedResponses) из \(search.playersNeeded)"
        }
        return approvedResponses > 0 ? "Игрок уже подтверждён" : "Нужен 1 игрок"
    }

    private var approvedResponsesCount: Int {
        search.responses.filter { $0.status == "approved" }.count
    }

    private var detailsTitle: String {
        if search.searchType == .hot {
            return search.hasCourtBooked ? "Нужен игрок на ближайшее время" : "Быстрая игра на ближайшее время"
        }
        return "Ищет партнёра по расписанию"
    }

    private var detailText: String {
        if let comment = search.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            return comment
        }
        if let bio = user.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
            return bio
        }
        return "Хочет быстро договориться и выйти на игру без долгой переписки."
    }

    private var searchStatusLabel: String {
        search.statusLabel
    }

    private var myResponseStatusLabel: String? {
        switch responseStatus {
        case "pending":
            return "Мой отклик отправлен"
        case "approved":
            return "Меня подтвердили"
        case "rejected":
            return "Отклик отклонён"
        default:
            return nil
        }
    }

    private var myResponseStatusCaption: String? {
        switch responseStatus {
        case "pending":
            return "Ожидает решения организатора"
        case "approved":
            return "Можно договариваться об игре"
        case "rejected":
            return "Не получится сыграть"
        default:
            return nil
        }
    }

    private var gradientColors: [Color] {
        switch responseStatus {
        case "approved":
            return [Color(red: 0.10, green: 0.45, blue: 0.24), AppTheme.ink]
        case "rejected":
            return [Color(red: 0.42, green: 0.14, blue: 0.14), AppTheme.ink]
        case "pending":
            return [Color(red: 0.56, green: 0.37, blue: 0.11), AppTheme.ink]
        default:
            switch searchStatusLabel {
            case "Игрок найден", "Игроки найдены":
                return [Color(red: 0.10, green: 0.45, blue: 0.24), AppTheme.ink]
            case "Ожидает решения", "В процессе набора", "В процессе набора людей":
                return [Color(red: 0.56, green: 0.37, blue: 0.11), AppTheme.ink]
            default:
                return search.searchType == .hot
                    ? [Color(red: 0.68, green: 0.18, blue: 0.14), AppTheme.ink]
                    : [AppTheme.court, AppTheme.ink]
            }
        }
    }

    private var statusTint: Color {
        switch responseStatus {
        case "approved":
            return .green.opacity(0.82)
        case "pending":
            return .orange.opacity(0.82)
        case "rejected":
            return .red.opacity(0.82)
        default:
            switch searchStatusLabel {
            case "Игрок найден", "Игроки найдены":
                return .green.opacity(0.82)
            case "Ожидает решения", "В процессе набора", "В процессе набора людей":
                return .orange.opacity(0.82)
            case "Идет набор", "Поиск":
                return .white.opacity(0.16)
            default:
                return search.searchType == .hot ? .red.opacity(0.92) : .white.opacity(0.16)
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.white.opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.76), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        RemoteAvatarView(name: user.displayName, path: user.avatarUrl, size: 64)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(user.displayName + (user.age.map { ", \($0)" } ?? ""))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                SearchGlassPill(systemImage: "mappin.and.ellipse", text: [user.city, user.districtLabel].compactMap { $0 }.joined(separator: " · "))
                                SearchStatusPill(
                                    systemImage: search.searchType == .hot ? "flame.fill" : "calendar",
                                    text: searchStatusLabel,
                                    accent: statusTint
                                )
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Сейчас ищет")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.62))
                        Text(detailsTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text(detailText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        SearchInfoTile(systemImage: "clock", label: "Когда", value: search.scheduleLine)
                        SearchInfoTile(
                            systemImage: "building.2",
                            label: search.sport.venueFieldTitle,
                            value: search.preferredCourt?.name ?? (search.hasCourtBooked ? "Уже забронировано" : "Без привязки")
                        )
                        SearchInfoTile(systemImage: "person.2", label: "Состав", value: rosterLabel)
                        SearchInfoTile(
                            systemImage: "target",
                            label: "Ищет",
                            value: "Уровень \((search.desiredLevelMin ?? 1))-\((search.desiredLevelMax ?? 10))"
                        )
                    }

                    FlowLayout(items: searchPills) { pill in
                        SearchGlassPill(systemImage: pill.systemImage, text: pill.text, tint: pill.tint)
                    }

                    if let myResponseStatusLabel {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "paperplane.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(statusTint)
                                Text(myResponseStatusLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }

                            if let myResponseStatusCaption {
                                Text(myResponseStatusCaption)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.76))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(statusTint)
                                .frame(width: 4, height: 34)
                                .padding(.leading, 8)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(0.96)

                        RadialGradient(
                            colors: [
                                .white.opacity(0.08),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 220
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .padding(6)
            }

            Button(appModelButtonTitle) {
                if responseStatus == "approved", search.playersNeeded > 1 || canOpenApprovedPair {
                    onOpenApprovedChat()
                } else {
                    action()
                }
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: buttonTint))
            .disabled(isButtonDisabled)
            .opacity(isButtonDisabled ? 0.84 : 1)
        }
    }

    private var appModelButtonTitle: String {
        switch responseStatus {
        case "pending":
            return "Отменить отклик"
        case "approved":
            if search.playersNeeded > 1 {
                return "Открыть чат состава"
            }
            return canOpenApprovedPair ? "Открыть пару" : "Отклик принят"
        case "rejected":
            return "Отклик отклонён"
        default:
            return "Откликнуться"
        }
    }

    private var isButtonDisabled: Bool {
        responseStatus == "rejected" ||
            (responseStatus == "pending" && responseId == nil) ||
            (responseStatus == "approved" && search.playersNeeded == 1 && !canOpenApprovedPair)
    }

    private var buttonTint: Color {
        switch responseStatus {
        case "pending":
            return Color.white.opacity(0.22)
        case "approved":
            return search.playersNeeded > 1 || canOpenApprovedPair ? AppTheme.ink : .white.opacity(0.22)
        case "rejected":
            return .red
        default:
            return search.searchType == .hot ? .red : AppTheme.ink
        }
    }

    private var canOpenApprovedPair: Bool {
        responseStatus == "approved" && search.regularPair?.id != nil
    }

    private var searchPills: [SearchPillModel] {
        var pills: [SearchPillModel] = [
            .init(
                systemImage: nil,
                text: search.sport.formatTitle(format: search.format, playersNeeded: search.playersNeeded),
                tint: .white.opacity(0.12)
            ),
            .init(systemImage: nil, text: search.sport.title, tint: .white.opacity(0.12))
        ]

        if search.playersNeeded > 1 {
            pills.append(.init(systemImage: "person.3.fill", text: "Нужно игроков: \(search.playersNeeded)", tint: .white.opacity(0.12)))
        }

        if let date = hotCountdownLabel, search.searchType == .hot {
            pills.append(.init(systemImage: "flame.fill", text: date, tint: .red.opacity(0.92)))
        }

        return pills
    }
}

private struct InlineToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.ink.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.18), radius: 18, x: 0, y: 12)
        .padding(.horizontal, 16)
    }
}

private struct ShareExistingGameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: MatchGameRequest
    let matches: [MatchSummary]
    let onShare: ([String]) async -> Void

    @State private var selectedMatchIDs: Set<String> = []
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionCard(
                            title: "Пригласить в игру",
                            subtitle: "Выбери мэтчи, которым нужно отправить уже созданную договорённость."
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                AppInlineChip(text: request.sport.title, tint: AppTheme.cream, foreground: AppTheme.ink)
                                AppInlineChip(text: request.proposedDatetime.formattedNumericDateTime(), tint: AppTheme.ink, foreground: .white)
                            }
                        }

                        if matches.isEmpty {
                            SectionCard(title: "Нет доступных мэтчей", subtitle: "Сначала нужен ещё хотя бы один мэтч без активного приглашения.") {
                                EmptyStateView(
                                    title: "Некого приглашать",
                                    subtitle: "Как только появятся другие мэтчи, здесь можно будет быстро разослать эту игру нескольким людям.",
                                    systemImage: "person.3"
                                )
                            }
                        } else {
                            SectionCard(title: "Кому отправить", subtitle: "Можно отметить сразу нескольких игроков.") {
                                VStack(spacing: 10) {
                                    ForEach(matches) { match in
                                        Button {
                                            toggle(match.id)
                                        } label: {
                                            HStack(spacing: 12) {
                                                RemoteAvatarView(name: match.otherUser.displayName, path: match.otherUser.avatarUrl, size: 52)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(match.otherUser.displayName)
                                                        .font(.headline)
                                                        .foregroundStyle(AppTheme.ink)
                                                        .lineLimit(1)
                                                    if let district = match.otherUser.districtLabel ?? match.otherUser.district {
                                                        Text(localizedDistrictName(district) ?? district)
                                                            .font(.subheadline)
                                                            .foregroundStyle(AppTheme.ink.opacity(0.62))
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                                Image(systemName: selectedMatchIDs.contains(match.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 22, weight: .semibold))
                                                    .foregroundStyle(selectedMatchIDs.contains(match.id) ? AppTheme.court : AppTheme.ink.opacity(0.24))
                                            }
                                            .padding(14)
                                            .background(
                                                selectedMatchIDs.contains(match.id) ? AppTheme.mint : .white.opacity(0.7),
                                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Приглашения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSubmitting = true
                            await onShare(Array(selectedMatchIDs))
                            isSubmitting = false
                            dismiss()
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(AppTheme.court)
                        } else {
                            Text("Отправить")
                        }
                    }
                    .disabled(selectedMatchIDs.isEmpty || isSubmitting)
                }
            }
        }
    }

    private func toggle(_ matchId: String) {
        if selectedMatchIDs.contains(matchId) {
            selectedMatchIDs.remove(matchId)
        } else {
            selectedMatchIDs.insert(matchId)
        }
    }
}

private struct MatchSuccessToast: View {
    let message: String

    @State private var animateBounce = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 42, height: 42)

                TennisBallIcon()
                    .frame(width: 26, height: 26)
                    .offset(y: animateBounce ? -4 : 4)
                    .rotationEffect(.degrees(animateBounce ? 12 : -12))
                    .animation(.easeInOut(duration: 0.46).repeatForever(autoreverses: true), value: animateBounce)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Новый мэтч")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(Color(red: 0.76, green: 0.97, blue: 0.80))

                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
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
        .onAppear {
            animateBounce = true
            AppHaptics.notification(.success)
        }
    }
}

private struct SearchPillModel: Hashable {
    let systemImage: String?
    let text: String
    let tint: Color
}

private struct SearchInfoTile: View {
    let systemImage: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(label)
            }
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.62))

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SearchGlassPill: View {
    let systemImage: String?
    let text: String
    var tint: Color = .white.opacity(0.12)

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint, in: Capsule())
    }
}

private struct SearchStatusPill: View {
    let systemImage: String?
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Text(text)
                .lineLimit(1)
                .foregroundStyle(.white)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.28), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct UpcomingGameCard: View {
    let request: MatchGameRequest
    let displayName: String
    let avatarURL: String?
    let currentUserId: String?
    let isUpdating: Bool
    let onSelectParticipant: (DiscoverUser) -> Void
    let onOpenChat: (() -> Void)?
    let onOpenDetails: (() -> Void)?
    let onShare: (() -> Void)?
    let onAccept: (() async -> Void)?
    let onCancel: (() async -> Void)?
    let onMarkOutcome: ((String) async -> Void)?
    let onProposeNext: (() -> Void)?

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var isCompactScreen: Bool {
        screenWidth <= 430
    }

    private var heroHeight: CGFloat {
        isCompactScreen ? 104 : 118
    }

    private var avatarSize: CGFloat {
        isCompactScreen ? 44 : 52
    }

    private var titleSize: CGFloat {
        isCompactScreen ? 18 : 22
    }

    private var outerPadding: CGFloat {
        isCompactScreen ? 8 : 10
    }

    private var innerPadding: CGFloat {
        isCompactScreen ? 10 : 12
    }

    private var statusLabel: String {
        request.statusLabel
    }

    private var statusTint: Color {
        request.statusTintColor
    }

    private var sportLabel: String {
        request.sport.title
    }

    private var formatLabel: String {
        request.sport.formatTitle(format: request.format)
    }

    private var compactDateLabel: String {
        request.proposedDatetime.formattedDateTime()
    }

    private var courtLabel: String {
        request.proposedCourt?.name ?? request.sport.venuePendingTitle
    }

    private var cancelTitle: String {
        request.createdByUserId == currentUserId ? "Отменить" : "Не смогу"
    }

    private var visibleParticipants: [DiscoverUser] {
        request.visibleParticipants(currentUserId: currentUserId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader
            heroSection

            VStack(alignment: .leading, spacing: 12) {
                infoRow

                Divider()
                    .overlay(.white.opacity(0.08))

                footerRow

                if request.needsOutcomeReview, let onMarkOutcome {
                    GameOutcomePrompt(
                        isUpdating: isUpdating,
                        onPlayed: { await onMarkOutcome("played") },
                        onMissed: { await onMarkOutcome("not_played") },
                        onProposeNext: onProposeNext
                    )
                } else if request.outcome != nil {
                    GameOutcomeSummary(
                        label: request.outcomeLabel ?? "Итог сохранён",
                        onProposeNext: onProposeNext
                    )
                }
            }
            .padding(innerPadding)
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.10, blue: 0.11), Color(red: 0.05, green: 0.05, blue: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(statusTint.opacity(0.9), lineWidth: 1.6)
                )
        )
        .shadow(color: statusTint.opacity(0.14), radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            onOpenDetails?()
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            RemoteAvatarView(name: displayName, path: avatarURL, size: avatarSize)
                .overlay(
                    RoundedRectangle(cornerRadius: avatarSize * 0.34, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("\(sportLabel) · \(formatLabel)")
                    .font(.system(size: isCompactScreen ? 13 : 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            AppInlineChip(text: statusLabel, tint: statusTint, foreground: .white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, innerPadding)
        .padding(.top, innerPadding)
    }

    private var heroSection: some View {
        Button {
            onOpenDetails?()
        } label: {
            ZStack(alignment: .bottomLeading) {
                UpcomingHeroImage(
                    sport: request.sport,
                    isCompactScreen: isCompactScreen
                )

                LinearGradient(
                    colors: [.black.opacity(0.08), .black.opacity(0.54), .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .center, spacing: 12) {
                    RemoteAvatarView(name: displayName, path: avatarURL, size: avatarSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: avatarSize * 0.34, style: .continuous)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.system(size: titleSize, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text("\(sportLabel) · \(formatLabel)")
                            .font(.system(size: isCompactScreen ? 13 : 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)

                        if !isCompactScreen, let comment = request.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    AppInlineChip(text: statusLabel, tint: statusTint, foreground: .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(innerPadding)
            }
            .frame(height: heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onOpenDetails == nil)
    }

    private var infoRow: some View {
        HStack(spacing: 12) {
            compactInfoBlock(
                systemImage: "calendar",
                title: compactDateLabel,
                subtitle: nil
            ) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let countdownText = request.startsInMinutesText(referenceDate: context.date) {
                        Text(countdownText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.70, blue: 0.30))
                            .lineLimit(1)
                    }
                }
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 4)

            compactInfoBlock(
                systemImage: "sportscourt.fill",
                title: request.sport.venueFieldTitle,
                subtitle: courtLabel
            )
        }
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            participantsPreview

            Spacer(minLength: 8)

            if let onOpenChat {
                Button(action: onOpenChat) {
                    Text(onAccept == nil ? "Открыть чат" : "Чат")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .background(AppTheme.court, in: Capsule())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }

            if let onAccept {
                Button {
                    Task {
                        await onAccept()
                    }
                } label: {
                    Group {
                        if isUpdating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .background(AppTheme.court, in: Circle())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .disabled(isUpdating)
            }

            if let onShare, !request.isRegularOccurrence {
                Button(action: onShare) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                }
                .background(.white.opacity(0.08), in: Circle())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }

            if let onOpenDetails {
                Button(action: onOpenDetails) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 40, height: 40)
                }
                .background(.white.opacity(0.08), in: Circle())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .accessibilityLabel("Детали игры")
            }
        }
    }

    private var participantsPreview: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) {
                if visibleParticipants.isEmpty {
                    RemoteAvatarView(name: displayName, path: avatarURL, size: 36)
                } else {
                    ForEach(Array(visibleParticipants.prefix(2))) { participant in
                        Button {
                            onSelectParticipant(participant)
                        } label: {
                            RemoteAvatarView(name: participant.displayName, path: participant.avatarUrl, size: 36)
                                .overlay(Circle().stroke(Color(red: 0.10, green: 0.10, blue: 0.11), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }

                    if max(request.participantCount - 2, 0) > 0 {
                        Text("+\(request.participantCount - 2)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.12), in: Circle())
                            .overlay(Circle().stroke(Color(red: 0.10, green: 0.10, blue: 0.11), lineWidth: 1.5))
                    }
                }
            }

            Text("\(request.participantCount) \(participantsCountWord(request.participantCount))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
    }

    private func compactInfoBlock<Accessory: View>(
        systemImage: String,
        title: String,
        subtitle: String?,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.63, green: 0.93, blue: 0.75))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: isCompactScreen ? 14 : 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                accessory()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactInfoBlock(
        systemImage: String,
        title: String,
        subtitle: String?
    ) -> some View {
        compactInfoBlock(systemImage: systemImage, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }

    private func participantsCountWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 {
            return "участник"
        }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return "участника"
        }
        return "участников"
    }
}

private struct UpcomingHeroImage: View {
    let sport: Sport
    let isCompactScreen: Bool

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .offset(y: isCompactScreen ? -26 : -10)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.19, blue: 0.16),
                        Color(red: 0.10, green: 0.11, blue: 0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func loadImage() -> UIImage? {
        for resourceName in candidateResourceNames {
            if let uiImage = UIImage(named: resourceName) {
                return uiImage
            }

            for ext in ["jpg", "jpeg", "png", "webp"] {
                if let url = Bundle.main.url(forResource: resourceName, withExtension: ext),
                   let image = UIImage(contentsOfFile: url.path) {
                    return image
                }
            }
        }

        return nil
    }

    private var candidateResourceNames: [String] {
        switch sport {
        case .tennis:
            return ["hero-tennis", "upcoming-game-hero"]
        case .padel:
            return ["hero-padel", "upcoming-game-hero"]
        case .squash:
            return ["hero-squash", "upcoming-game-hero"]
        case .badminton:
            return ["hero-badminton", "upcoming-game-hero"]
        case .tableTennis:
            return ["hero-table-tennis", "hero-table_tennis", "upcoming-game-hero"]
        case .volleyball:
            return ["hero-volleyball", "upcoming-game-hero"]
        case .fitness:
            return ["hero-fitness", "upcoming-game-hero"]
        case .boxing:
            return ["hero-boxing", "upcoming-game-hero"]
        case .yoga:
            return ["hero-yoga", "upcoming-game-hero"]
        case .football:
            return ["hero-football", "upcoming-game-hero"]
        }
    }
}

private struct UpcomingMetaTile: View {
    let systemImage: String
    let label: String
    let value: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.63, green: 0.93, blue: 0.75))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 8)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct GameOutcomePrompt: View {
    let isUpdating: Bool
    let onPlayed: () async -> Void
    let onMissed: () async -> Void
    let onProposeNext: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Игра закончилась")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.63, green: 0.93, blue: 0.75))
                    .textCase(.uppercase)
                    .tracking(1.4)
                Text("Удалось сыграть?")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                outcomeButton(title: "Да, сыграли", systemImage: "checkmark.circle.fill", tint: AppTheme.court) {
                    await onPlayed()
                }
                outcomeButton(title: "Нет", systemImage: "xmark.circle.fill", tint: Color(red: 0.63, green: 0.22, blue: 0.20)) {
                    await onMissed()
                }
            }

            if let onProposeNext {
                Button(action: onProposeNext) {
                    Label("Назначить следующую", systemImage: "calendar.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
                .disabled(isUpdating)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func outcomeButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack(spacing: 8) {
                if isUpdating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(isUpdating)
    }
}

private struct GameOutcomeSummary: View {
    let label: String
    let onProposeNext: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppTheme.court)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let onProposeNext {
                Button("Следующая") {
                    onProposeNext()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.court)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DiscoverParticipantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let user: DiscoverUser
    let onOpenChat: (() -> Void)?

    private var primarySport: Sport {
        user.preferredSports.first ?? .tennis
    }

    private var sportsSummary: String {
        let titles = user.preferredSports.prefix(3).map(\.title)
        return titles.isEmpty ? "Спорт уточняется" : titles.joined(separator: " · ")
    }

    private var levelSummary: String {
        let level = user.sportLevels[primarySport.rawValue] ?? user.tennisLevel
        guard let level else {
            return "Уровень не указан"
        }
        return "\(level)/10"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: user.displayName, subtitle: user.bio ?? "Профиль участника игры.") {
                    HStack(alignment: .top, spacing: 14) {
                        RemoteAvatarView(name: user.displayName, path: user.avatarUrl, size: 92)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(Array(user.districtDisplayNames.prefix(3)), id: \.self) { district in
                                    AppInlineChip(
                                        text: district,
                                        tint: AppTheme.mint,
                                        foreground: AppTheme.court
                                    )
                                }
                            }

                            if let age = user.age, let city = user.city {
                                Text("\(age) лет, \(city)")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(user.preferredSports.prefix(4)) { sport in
                                        let level = user.sportLevels[sport.rawValue] ?? user.tennisLevel
                                        SportLevelMiniChip(sport: sport, level: level)
                                    }
                                }
                            }
                        }
                    }
                }

                SectionCard(
                    title: "Почему вам стоит сыграть",
                    subtitle: user.explainabilityReasons.isEmpty
                        ? "Пока это базовые причины: районы для игры, спорт и уровень."
                        : "2–4 причины релевантности из подбора."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if user.explainabilityReasons.isEmpty {
                            DiscoverReasonRow(
                                systemImage: "location.fill",
                                text: "Удобные районы: \(user.districtDisplaySummary)"
                            )
                            DiscoverReasonRow(
                                systemImage: "sportscourt",
                                text: "Спорт: \(sportsSummary)"
                            )
                            DiscoverReasonRow(
                                systemImage: "chart.bar.fill",
                                text: "Уровень в \(primarySport.title): \(levelSummary)"
                            )
                        } else {
                            ForEach(user.explainabilityReasons.prefix(4), id: \.self) { reason in
                                DiscoverReasonRow(
                                    systemImage: "sparkles",
                                    text: reason
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !appModel.isAuthenticated {
                    SectionCard(title: "Что дальше", subtitle: "Вход нужен, чтобы переписываться, сохранять и получать уведомления.") {
                        AuthInlinePrompt(
                            title: "Войти, чтобы продолжить",
                            subtitle: "Подтверди email — и сможешь писать, предлагать игры и видеть историю."
                        ) {
                            appModel.presentAuth(step: .email)
                        }
                    }
                } else {
                    SectionCard(
                        title: "Что дальше",
                        subtitle: "Самый быстрый шаг — написать. В чате удобно предложить 2–3 времени или уточнить \(primarySport.venueFieldTitle.lowercased())."
                    ) {
                        VStack(spacing: 12) {
                            if let onOpenChat {
                                Button {
                                    dismiss()
                                    onOpenChat()
                                } label: {
                                    Label("Открыть чат", systemImage: "message.fill")
                                }
                                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                            } else {
                                Text("Открой чат из карточки игры — там проще договориться о времени и формате.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                            }

                            Button("Закрыть карточку") {
                                dismiss()
                            }
                            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.court))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct DiscoverReasonRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.court)
                .frame(width: 22, alignment: .leading)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


private struct AuthInlinePrompt: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.68))
            Button("Продолжить с email", action: action)
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
        }
    }
}

private struct GlassTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

private struct GlassDecision: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunked(items, size: 3), id: \.self) { row in
                HStack {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ array: [Item], size: Int) -> [[Item]] {
        stride(from: 0, to: array.count, by: size).map {
            Array(array[$0 ..< min($0 + size, array.count)])
        }
    }
}
