import SwiftUI
import UIKit
import MapKit
import PhotosUI

struct SearchesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appModel: AppModel
    @State private var searches: [GameSearch] = []
    @State private var isPresentingComposer = false
    @State private var editingSearch: GameSearch?
    @State private var selectedFilter: SearchListFilter = .all
    @State private var presentedSearch: GameSearch?
    @State private var updatingResponseID: String?
    @State private var updatingSearchID: String?
    @State private var presentedSearchLobbyID: String?
    @State private var createButtonPressed = false
    @State private var isCreateFABExpanded = true
    @State private var hasInteractedWithCreateFAB = false
    @State private var isOpeningCreateComposer = false
    @State private var isLoadingSearches = false
    let openedFromDiscover: Bool

    init(openedFromDiscover: Bool = false) {
        self.openedFromDiscover = openedFromDiscover
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    searchesHeader
                    summaryStrip
                    filterRail

                    if filteredSearches.isEmpty, !isLoadingSearches {
                        emptySearchesState
                    } else {
                        if selectedFilter == .all {
                            ForEach(allSearchSections) { section in
                                searchSection(section.title, subtitle: section.subtitle, searches: section.searches)
                            }
                        } else {
                            searchSection(nil, subtitle: nil, searches: filteredSearches)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 172)
            }
            .simultaneousGesture(createFABScrollGesture)

            createSearchFAB
        }
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(backToDiscoverSwipe)
        .task {
            openPendingSearchLobbyIfNeeded()
            if appModel.pendingCreateSearchPrefill != nil {
                presentCreateSearchComposer()
            }
            await loadSearches()
        }
        .task(id: createFABAutoCollapseKey) {
            guard !filteredSearches.isEmpty, !hasInteractedWithCreateFAB else {
                return
            }

            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else {
                return
            }
            collapseCreateFAB()
        }
        .onChange(of: appModel.pendingCreateSearchPrefill) { prefill in
            guard prefill != nil else {
                return
            }
            presentCreateSearchComposer()
        }
        .onChange(of: appModel.pendingSearchLobbyID) { _ in
            openPendingSearchLobbyIfNeeded()
        }
        .refreshable {
            await loadSearches()
        }
        .sheet(isPresented: $isPresentingComposer, onDismiss: {
            isOpeningCreateComposer = false
            appModel.pendingCreateSearchPrefill = nil
        }) {
            SearchComposerView(
                initialSport: appModel.pendingCreateSearchPrefill?.sport,
                initialHotWindow: appModel.pendingCreateSearchPrefill?.hotWindow,
                initialHotStartTime: appModel.pendingCreateSearchPrefill?.hotStartTime
            ) { created in
                searches.insert(created, at: 0)
            }
            .id("create-search-composer")
            .environmentObject(appModel)
        }
        .sheet(item: $editingSearch) { search in
            SearchComposerView(initialSearch: search) { updated in
                if let index = searches.firstIndex(where: { $0.id == updated.id }) {
                    searches[index] = updated
                }
            }
            .id(search.id)
            .environmentObject(appModel)
        }
        .sheet(item: $presentedSearch) { search in
            SearchDetailSheet(
                initialSearch: search,
                onEdit: { selected in
                    presentedSearch = nil
                    editingSearch = selected
                },
                onOpenLobby: { searchId in
                    presentedSearch = nil
                    presentedSearchLobbyID = searchId
                },
                onReloadParent: {
                    await loadSearches()
                }
            )
            .environmentObject(appModel)
        }
        .sheet(isPresented: Binding(
            get: { presentedSearchLobbyID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedSearchLobbyID = nil
                }
            }
        )) {
            if let presentedSearchLobbyID {
                SearchLobbySheet(searchId: presentedSearchLobbyID)
                    .environmentObject(appModel)
            }
        }
    }

    private var backToDiscoverSwipe: some Gesture {
        DragGesture(minimumDistance: 34)
            .onEnded { value in
                guard openedFromDiscover else {
                    return
                }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > max(80, vertical * 1.3) else {
                    return
                }

                dismiss()
            }
    }

    private var activeSearchCount: Int {
        visibleSearches.filter { isOwnedSearch($0) && isEditableSearch($0) && ($0.isActive ?? true) }.count
    }

    private var pendingResponsesCount: Int {
        let currentUserId = appModel.currentUser?.id
        return visibleSearches.reduce(into: 0) { count, search in
            guard isOwnedActiveHotSearchForAttention(search, currentUserId: currentUserId) else {
                return
            }
            count += search.responses.filter { $0.status == "pending" }.count
        }
    }

    private var nextUpcomingLine: String {
        let candidates = visibleSearches.compactMap(nextEventDate(for:))
        guard let next = candidates.sorted().first else {
            return L10n.string("None yet", "Пока нет")
        }
        return next.formattedShortRelative()
    }

    private var filteredSearches: [GameSearch] {
        switch selectedFilter {
        case .all:
            return visibleSearches
        case .active:
            return visibleSearches.filter { isOwnedSearch($0) && isEditableSearch($0) && ($0.isActive ?? true) }
        case .withResponses:
            return visibleSearches.filter { (isOwnedSearch($0) && !$0.responses.isEmpty) || hasMyResponse($0) }
        case .paused:
            return visibleSearches.filter { isOwnedSearch($0) && isEditableSearch($0) && !($0.isActive ?? true) }
        case .completed:
            return visibleSearches.filter { isCompletedSearch($0) }
        }
    }

    private var visibleSearches: [GameSearch] {
        searches.filter { $0.searchType == .hot }
    }

    private var allSearchSections: [SearchSectionModel] {
        let active = visibleSearches.filter { isOwnedSearch($0) && isEditableSearch($0) && ($0.isActive ?? true) }
        let applications = visibleSearches.filter { !isOwnedSearch($0) && hasMyResponse($0) }
        let paused = visibleSearches.filter { isOwnedSearch($0) && isEditableSearch($0) && !($0.isActive ?? true) }
        let completed = visibleSearches.filter { isOwnedSearch($0) && isCompletedSearch($0) }

        return [
            SearchSectionModel(id: "active", title: L10n.string("Active", "Активные"), subtitle: L10n.string("Searches currently visible to players.", "Поиски, которые сейчас видят игроки."), searches: active),
            SearchSectionModel(id: "applications", title: L10n.string("My responses", "Мои отклики"), subtitle: L10n.string("Other players’ searches you have responded to.", "Поиски других игроков, куда ты уже откликнулся."), searches: applications),
            SearchSectionModel(id: "paused", title: L10n.string("Paused", "Остановлены"), subtitle: L10n.string("These searches are hidden and waiting to be resumed.", "Эти поиски сняты с показа и ждут перезапуска."), searches: paused),
            SearchSectionModel(id: "completed", title: L10n.string("Completed", "Завершены"), subtitle: L10n.string("Players have been found or the search is closed.", "Игроки найдены или поиск уже закрыт."), searches: completed)
        ]
        .filter { !$0.searches.isEmpty }
    }

    private func isCompletedSearch(_ search: GameSearch) -> Bool {
        let status = search.status.lowercased()
        if ["matched", "completed", "finished"].contains(status) {
            return true
        }
        let approvedCount = search.responses.filter { $0.status == "approved" }.count
        return approvedCount >= max(search.playersNeeded, 1)
    }

    private func isEditableSearch(_ search: GameSearch) -> Bool {
        !isCompletedSearch(search)
    }

    private func isOwnedSearch(_ search: GameSearch) -> Bool {
        guard let createdByUserId = search.createdByUserId,
              let currentUserId = appModel.currentUser?.id else {
            return true
        }
        return createdByUserId == currentUserId
    }

    private func hasMyResponse(_ search: GameSearch) -> Bool {
        guard let currentUserId = appModel.currentUser?.id else {
            return false
        }
        return search.responses.contains { $0.responderUser.id == currentUserId }
    }

    @ViewBuilder
    private func searchSection(_ title: String?, subtitle: String?, searches: [GameSearch]) -> some View {
        if let title, let subtitle {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.52))
                }

                ForEach(searches) { search in
                    searchCard(for: search)
                }
            }
        } else {
            ForEach(searches) { search in
                searchCard(for: search)
            }
        }
    }

    private func searchCard(for search: GameSearch) -> some View {
        let isOwned = isOwnedSearch(search)
        return SearchOverviewCard(
            search: search,
            currentUserId: appModel.currentUser?.id,
            updatingResponseID: updatingResponseID,
            updatingSearchID: updatingSearchID,
            onUpdateResponseStatus: updateResponseStatus,
            onUpdateRegularOccurrence: updateRegularOccurrence,
            onOpenLobby: {
                presentedSearchLobbyID = search.id
            },
            onOpenDetails: {
                if isOwned {
                    presentedSearch = search
                } else {
                    presentedSearchLobbyID = search.id
                }
            },
            onEdit: {
                guard isOwned else {
                    presentedSearchLobbyID = search.id
                    return
                }
                isPresentingComposer = false
                editingSearch = search
            },
            onToggleActive: { isActive in
                guard isOwned else {
                    return
                }
                await setSearchActive(searchId: search.id, isActive: isActive)
            },
            onReload: {
                await loadSearches()
            }
        )
    }

    private func openPendingSearchLobbyIfNeeded() {
        guard let searchId = appModel.pendingSearchLobbyID else {
            return
        }

        guard !searches.isEmpty else {
            return
        }

        if let search = searches.first(where: { $0.id == searchId }), isOwnedSearch(search) {
            presentedSearch = search
        } else {
            presentedSearchLobbyID = searchId
        }
        appModel.pendingSearchLobbyID = nil
    }

    private var searchesHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("My searches", "Мои поиски"))
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var createSearchFABBottomPadding: CGFloat {
        switch appModel.bottomBarDisplayMode {
        case .expanded:
            return 108
        case .compact:
            return 30
        case .hidden:
            return 16
        }
    }

    private var createSearchFAB: some View {
        Button {
            presentCreateSearchComposer()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .bold))
                    .frame(width: 24, height: 24)

                if isCreateFABExpanded {
                    Text(L10n.string("Create search", "Создать поиск"))
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(AppTheme.ink)
            .frame(width: isCreateFABExpanded ? 190 : 60, height: 60)
            .background(createSearchFABBackground)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .shadow(color: AppTheme.ink.opacity(0.18), radius: 18, x: 0, y: 9)
        }
        .scaleEffect(createButtonPressed ? 0.96 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: createButtonPressed)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: isCreateFABExpanded)
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("Create search", "Создать поиск"))
        .padding(.trailing, 18)
        .padding(.bottom, createSearchFABBottomPadding)
    }

    @ViewBuilder
    private var createSearchFABBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.clear)
                .glassEffect(.regular.tint(AppTheme.court.opacity(0.78)).interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(AppTheme.court.opacity(0.74)))
                .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
        }
    }

    private var createFABAutoCollapseKey: String {
        "\(filteredSearches.isEmpty)|\(hasInteractedWithCreateFAB)"
    }

    private var createFABScrollGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { _ in
                registerCreateFABInteraction()
            }
    }

    private func registerCreateFABInteraction() {
        hasInteractedWithCreateFAB = true
        collapseCreateFAB()
    }

    private func collapseCreateFAB() {
        guard isCreateFABExpanded else {
            return
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            isCreateFABExpanded = false
        }
    }

    private var emptySearchesState: some View {
        SectionCard(
            title: activeSearchCount == 0 ? L10n.string("No active searches", "Активных поисков нет") : L10n.string("Nothing here yet", "Пока пусто"),
            subtitle: activeSearchCount == 0
                ? L10n.string("Create a search so nearby players can respond.", "Создай поиск, чтобы игроки рядом могли откликнуться.")
                : L10n.string("There are no searches in this section right now.", "В этом разделе сейчас нет поисков.")
        ) {
            VStack(spacing: 14) {
                EmptyStateView(
                    title: activeSearchCount == 0 ? L10n.string("Create your search", "Создай свой поиск") : L10n.string("No searches in this section", "Нет поисков в этом разделе"),
                    subtitle: activeSearchCount == 0
                        ? L10n.string("Choose a sport, time, and place. Responses will appear here.", "Укажи вид спорта, время и место. Отклики появятся здесь.")
                        : L10n.string("Change the filter or come back later.", "Смени фильтр или вернись позже."),
                    systemImage: "magnifyingglass.circle"
                )
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(title: L10n.string("Active urgent", "Активные срочные"), value: "\(activeSearchCount)", accent: AppTheme.court, systemImage: "flame")
            Divider()
                .frame(height: 44)
            summaryCell(title: L10n.string("New responses", "Новые отклики"), value: "\(pendingResponsesCount)", accent: .red.opacity(0.9), systemImage: "person.2")
            Divider()
                .frame(height: 44)
            summaryCell(title: L10n.string("Next game", "Ближайшая игра"), value: nextUpcomingLine, accent: AppTheme.court, systemImage: "clock")
        }
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchListFilter.allCases) { filter in
                    let selected = selectedFilter == filter
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selected ? .white : AppTheme.ink.opacity(0.86))
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(selected ? AppTheme.court : Color.white, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selected ? AppTheme.court : Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func summaryCell(title: String, value: String, accent: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.ink.opacity(0.58))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.12), in: Circle())
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }


    private func loadSearches() async {
        let shouldReportMenuLoading = searches.isEmpty
        if shouldReportMenuLoading {
            appModel.setTabContentLoading("searches", isLoading: true)
        }
        isLoadingSearches = true
        defer {
            isLoadingSearches = false
            if shouldReportMenuLoading {
                appModel.setTabContentLoading("searches", isLoading: false)
            }
        }

        do {
            searches = try await appModel.repository.fetchSearches()
            openPendingSearchLobbyIfNeeded()
            await markSearchNotificationsSeenIfNeeded()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func markSearchNotificationsSeenIfNeeded() async {
        guard appModel.isAuthenticated,
              appModel.notificationManager.summary.searchesBadgeCount > pendingResponsesCount else {
            return
        }

        do {
            try await appModel.repository.markNotificationsSeen()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            print("search notifications seen error:", error.localizedDescription)
        }
    }

    private func updateResponseStatus(responseId: String, status: String) async {
        updatingResponseID = responseId
        defer { updatingResponseID = nil }

        do {
            let result = try await appModel.repository.updateSearchResponseStatus(responseId: responseId, status: status)
            searches = searches.applying(responseUpdate: result)
            let fetchedSearches = try await appModel.repository.fetchSearches()
            searches = fetchedSearches.applying(responseUpdate: result)
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)

            guard status == "approved" else {
                return
            }

            if let gameRequestId = result.gameRequestId {
                appModel.navigate(to: .discover(.upcoming, highlightedGameRequestID: gameRequestId))
                return
            }

            if result.regularPairId != nil {
                appModel.navigate(to: .searches)
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func setSearchActive(searchId: String, isActive: Bool) async {
        updatingSearchID = searchId
        defer { updatingSearchID = nil }

        do {
            let updated = try await appModel.repository.setSearchActive(searchId: searchId, isActive: isActive)
            if let index = searches.firstIndex(where: { $0.id == searchId }) {
                searches[index] = updated
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func updateRegularOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: Date?,
        proposedCourtId: String?
    ) async {
        do {
            _ = try await appModel.repository.updateRegularPairOccurrence(
                regularPairId: regularPairId,
                occurrenceId: occurrenceId,
                status: status,
                scheduledAt: scheduledAt,
                proposedCourtId: proposedCourtId
            )
            searches = try await appModel.repository.fetchSearches()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func nextEventDate(for search: GameSearch) -> Date? {
        let regularDate = search.regularPair?.occurrences
            .compactMap { $0.scheduledAt.parsedISODateValue() }
            .filter { $0 > Date() }
            .sorted()
            .first

        let hotDate = search.hotStartsAt?.parsedISODateValue()
        return [regularDate, hotDate].compactMap { $0 }.sorted().first
    }
}

private enum SearchListFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case withResponses
    case paused
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.string("All", "Все")
        case .active: return L10n.string("Active", "Активные")
        case .withResponses: return L10n.string("With responses", "С откликами")
        case .paused: return L10n.string("Paused", "На паузе")
        case .completed: return L10n.string("Completed", "Завершённые")
        }
    }
}

private struct SearchSectionModel: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let searches: [GameSearch]
}

private extension SearchesView {
    func presentCreateSearchComposer() {
        guard !isPresentingComposer, !isOpeningCreateComposer else {
            return
        }

        isOpeningCreateComposer = true
        registerCreateFABInteraction()
        triggerCreateComposerFeedback()
        editingSearch = nil
        isPresentingComposer = true
    }

    func triggerCreateComposerFeedback() {
        AppHaptics.impact(.medium)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.65)) {
            createButtonPressed = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                createButtonPressed = false
            }
        }
    }
}

private enum SearchResponsesFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case approved
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.string("All", "Все")
        case .pending: return L10n.string("New", "Новые")
        case .approved: return L10n.string("Approved", "Одобрены")
        case .rejected: return L10n.string("Rejected", "Отклонены")
        }
    }

    func count(in responses: [SearchResponse]) -> Int {
        switch self {
        case .all:
            return responses.count
        case .pending:
            return responses.filter { $0.status == "pending" }.count
        case .approved:
            return responses.filter { $0.status == "approved" }.count
        case .rejected:
            return responses.filter { $0.status == "rejected" }.count
        }
    }
}

private struct SearchOverviewCard: View {
    let search: GameSearch
    let currentUserId: String?
    let updatingResponseID: String?
    let updatingSearchID: String?
    let onUpdateResponseStatus: (String, String) async -> Void
    let onUpdateRegularOccurrence: (String, String, String?, Date?, String?) async -> Void
    let onOpenLobby: () -> Void
    let onOpenDetails: () -> Void
    let onEdit: () -> Void
    let onToggleActive: (Bool) async -> Void
    let onReload: () async -> Void

    @State private var isRouteDetailPresented = false

    private var pendingResponses: [SearchResponse] {
        scopedResponses.filter { $0.status == "pending" }
    }

    private var approvedResponses: [SearchResponse] {
        scopedResponses.filter { $0.status == "approved" }
    }

    private var remainingSeats: Int {
        max(search.playersNeeded - approvedResponses.count, 0)
    }

    private var rejectedResponses: [SearchResponse] {
        scopedResponses.filter { $0.status == "rejected" }
    }

    private var withdrawnResponses: [SearchResponse] {
        scopedResponses.filter { $0.status == "withdrawn" }
    }

    private var visibleResponses: [SearchResponse] {
        Array((approvedResponses + pendingResponses + rejectedResponses + withdrawnResponses).prefix(4))
    }

    private var totalVisiblePlayerCount: Int {
        max(search.playersNeeded, approvedResponses.count)
    }

    private var isCompleted: Bool {
        let status = search.status.lowercased()
        return ["matched", "completed", "finished"].contains(status) ||
            search.responses.filter { $0.status == "approved" }.count >= max(search.playersNeeded, 1)
    }

    private var canManageSearch: Bool {
        isOwnedByCurrentUser && !isCompleted
    }

    private var isOwnedByCurrentUser: Bool {
        guard let createdByUserId = search.createdByUserId,
              let currentUserId else {
            return true
        }
        return createdByUserId == currentUserId
    }

    private var myResponse: SearchResponse? {
        guard let currentUserId else {
            return nil
        }
        return search.responses.first { $0.responderUser.id == currentUserId }
    }

    private var canOpenDetailsForCurrentUser: Bool {
        isOwnedByCurrentUser || myResponse?.status == "approved"
    }

    private var scopedResponses: [SearchResponse] {
        if isOwnedByCurrentUser {
            return search.responses
        }
        return myResponse.map { [$0] } ?? []
    }

    private var headlineText: String {
        if !isOwnedByCurrentUser {
            if let min = search.desiredLevelMin, let max = search.desiredLevelMax {
                return L10n.string("You responded to a level \(min)–\(max) search", "Вы откликнулись на поиск уровня \(min)–\(max)")
            }
            return L10n.string("You responded to this search", "Вы откликнулись на этот поиск")
        }

        if isCompleted {
            return L10n.string("Game is full", "Игра собрана")
        }

        if let min = search.desiredLevelMin, let max = search.desiredLevelMax {
            return L10n.string("Looking for \(search.playersNeeded) player(s), level \(min)–\(max)", "Ищу \(playerNoun(count: search.playersNeeded)) уровня \(min)–\(max)")
        }

        return L10n.string("Looking for \(search.playersNeeded) player(s)", "Ищу \(playerNoun(count: search.playersNeeded))")
    }

    private var scheduleText: String {
        if search.searchType == .hot {
            return [search.hotWindow?.title, search.hotStartsAt?.formattedDateTime()]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        let parts = [
            search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.prefix(2).joined(separator: ", "),
            search.preferredTimeRanges.map(localizedTimePreferenceTitle).prefix(2).joined(separator: ", ")
        ]
        .filter { !$0.isEmpty }

        return parts.joined(separator: " · ")
    }

    private var areaText: String {
        if let district = search.preferredDistricts.first {
            return localizedDistrictName(district) ?? district
        }
        return L10n.string("Any district", "Любой район")
    }

    private var courtText: String {
        search.preferredCourt?.name
            ?? search.customVenueAddress
            ?? search.customVenueTitle
            ?? (search.sport.isRouteSport ? L10n.string("Route to be confirmed", "Маршрут уточняется") : L10n.string("No club", "Без клуба"))
    }

    private var responseSummaryTitle: String {
        if !isOwnedByCurrentUser {
            return myResponseStatusTitle
        }

        if isCompleted {
            let count = max(totalVisiblePlayerCount, approvedResponses.count)
            return "\(count) \(peopleWord(count))"
        }

        return remainingSeats == 0 ? L10n.string("Roster complete", "Состав собран") : L10n.string("\(remainingSeats) left", "Осталось \(remainingSeats)")
    }

    private var responseSummarySubtitle: String {
        if !isOwnedByCurrentUser {
            return L10n.string("Your response", "Ваш отклик")
        }

        if isCompleted {
            return L10n.string("Everyone confirmed", "Все подтвердили")
        }

        return pendingResponses.isEmpty
            ? "\(search.responses.count) \(responseWord(search.responses.count))"
            : L10n.string("\(pendingResponses.count) new", "\(pendingResponses.count) новых")
    }

    private var cardStatusTitle: String {
        if !isOwnedByCurrentUser {
            return myResponseStatusTitle
        }

        if isCompleted {
            return L10n.string("Full", "Собрано")
        }
        if !(search.isActive ?? true) {
            return L10n.string("Paused", "Остановлен")
        }
        if !pendingResponses.isEmpty {
            return L10n.string("Has responses", "Есть отклики")
        }
        return L10n.string("Active", "Активен")
    }

    private var cardStatusTint: Color {
        if !isOwnedByCurrentUser {
            switch myResponse?.status {
            case "approved":
                return AppTheme.mint
            case "rejected", "withdrawn":
                return Color.gray.opacity(0.16)
            default:
                return AppTheme.cream
            }
        }

        if isCompleted {
            return Color.blue.opacity(0.16)
        }
        if !(search.isActive ?? true) {
            return Color.gray.opacity(0.16)
        }
        if !pendingResponses.isEmpty {
            return AppTheme.mint
        }
        return AppTheme.mint
    }

    private var cardStatusForeground: Color {
        if !isOwnedByCurrentUser {
            switch myResponse?.status {
            case "approved":
                return AppTheme.court
            case "rejected", "withdrawn":
                return AppTheme.ink.opacity(0.72)
            default:
                return Color(red: 0.70, green: 0.46, blue: 0.04)
            }
        }

        if isCompleted {
            return Color.blue.opacity(0.9)
        }
        if !(search.isActive ?? true) {
            return AppTheme.ink.opacity(0.72)
        }
        return AppTheme.court
    }

    private var primaryActionTitle: String {
        if !isOwnedByCurrentUser {
            return myResponse?.status == "approved" ? L10n.string("Lobby", "Лобби") : myResponseStatusTitle
        }

        if !search.responses.isEmpty {
            return L10n.string("Responses", "Отклики")
        }
        if isCompleted {
            return L10n.string("Open", "Открыть")
        }
        return L10n.string("Details", "Детали")
    }

    private var primaryActionTint: Color {
        if !isOwnedByCurrentUser {
            return AppTheme.ink
        }

        if isCompleted {
            return Color.blue.opacity(0.85)
        }
        return AppTheme.court
    }

    private var cardAccentColor: Color {
        if !isOwnedByCurrentUser {
            return AppTheme.ink.opacity(0.42)
        }

        if isCompleted {
            return Color.blue.opacity(0.78)
        }
        if !(search.isActive ?? true) {
            return AppTheme.ink.opacity(0.42)
        }
        if !pendingResponses.isEmpty {
            return AppTheme.court
        }
        if search.sport == .padel {
            return Color(red: 0.80, green: 0.60, blue: 0.16)
        }
        return AppTheme.court.opacity(0.78)
    }

    private var cardSurfaceColor: Color {
        if !isOwnedByCurrentUser {
            return Color.black.opacity(0.04)
        }

        if isCompleted {
            return Color.blue.opacity(0.10)
        }
        if !(search.isActive ?? true) {
            return Color.gray.opacity(0.14)
        }
        if !pendingResponses.isEmpty {
            return Color(red: 1.0, green: 0.96, blue: 0.86).opacity(0.82)
        }
        return AppTheme.mint.opacity(0.42)
    }

    private var myResponseStatusTitle: String {
        switch myResponse?.status {
        case "approved":
            return L10n.string("Approved", "Одобрено")
        case "rejected":
            return L10n.string("Rejected", "Отклонено")
        case "withdrawn":
            return L10n.string("Withdrawn", "Отозвано")
        default:
            return L10n.string("Pending", "На рассмотрении")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Circle()
                    .fill(sportTint.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay(
                        SportIconView(sport: search.sport, color: sportTint, size: 20)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(search.sport.title) · \(search.sport.formatTitle(format: search.format, playersNeeded: search.playersNeeded))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.88))
                        .lineLimit(1)
                }

                Spacer()

                AppInlineChip(text: cardStatusTitle, tint: cardStatusTint, foreground: cardStatusForeground)

                Button(action: openDetailsIfAllowed) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink.opacity(0.74))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(!canOpenDetailsForCurrentUser)
            }

            Text(headlineText)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 8) {
                if search.searchType == .hot {
                    HStack(spacing: 12) {
                        hotSearchMetaPill(systemImage: "flame.fill", text: L10n.string("Urgent", "Срочно"))
                        hotSearchMetaPill(systemImage: "clock.fill", text: hotCardTimeText)
                    }
                } else {
                    HStack(spacing: 12) {
                        cardMeta(systemImage: "calendar", text: search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.prefix(2).joined(separator: ", "))
                        cardMeta(systemImage: "clock", text: search.preferredTimeRanges.map(localizedTimePreferenceTitle).prefix(1).joined(separator: ", "))
                    }
                }
                HStack(spacing: 12) {
                    cardMeta(systemImage: "location", text: areaText)
                    cardMeta(systemImage: "building.2", text: courtText)
                }
            }

            if search.sport.isRouteSport, search.runningRoutePoints.count >= 2 {
                Button {
                    isRouteDetailPresented = true
                } label: {
                    RunningRoutePreviewMapView(points: search.runningRoutePoints, followsRoads: search.sport.routeFollowsRoads)
                        .frame(height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(cardAccentColor.opacity(0.24), lineWidth: 1)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Label(L10n.string("Open route", "Открыть маршрут"), systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.48), in: Capsule())
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(Array(visibleResponses.enumerated()), id: \.offset) { index, response in
                        RemoteAvatarView(name: response.responderUser.displayName, path: response.responderUser.avatarUrl, size: 38)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .zIndex(Double(visibleResponses.count - index))
                    }

                    if max(search.responses.count - visibleResponses.count, 0) > 0 {
                        Text("+\(search.responses.count - visibleResponses.count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.76))
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.05), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                Spacer()

                Button(action: openDetailsIfAllowed) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(responseSummaryTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(responseSummarySubtitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(pendingResponses.isEmpty ? AppTheme.ink.opacity(0.48) : .red.opacity(0.9))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canOpenDetailsForCurrentUser)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.3))
            }

            HStack(spacing: 10) {
                Button(action: openDetailsIfAllowed) {
                    Label(primaryActionTitle, systemImage: primaryActionTitle == L10n.string("Responses", "Отклики") ? "person.crop.circle.badge.checkmark" : "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(primaryActionTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!canOpenDetailsForCurrentUser)

                if canManageSearch {
                    Button(action: onEdit) {
                        Label(L10n.string("Edit", "Изм."), systemImage: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.ink)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .disabled(updatingSearchID == search.id)

                    Button {
                        Task {
                            await onToggleActive(!(search.isActive ?? true))
                            await onReload()
                        }
                    } label: {
                        if updatingSearchID == search.id {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        } else {
                            Label((search.isActive ?? true) ? L10n.string("Pause", "Остановить") : L10n.string("Resume", "Возобновить"), systemImage: (search.isActive ?? true) ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.ink)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .disabled(updatingSearchID == search.id)
                }
            }
        }
        .padding(16)
        .background(cardSurfaceColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardAccentColor.opacity(0.28), lineWidth: 1.2)
        )
        .shadow(color: AppTheme.ink.opacity(0.04), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: openDetailsIfAllowed)
        .sheet(isPresented: $isRouteDetailPresented) {
            RunningRouteDetailSheet(title: search.runningRoute ?? search.sport.routeDefaultTitle, sport: search.sport, points: search.runningRoutePoints)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    private var sportIconName: String {
        search.sport.appSystemIconName
    }

    private func openDetailsIfAllowed() {
        guard canOpenDetailsForCurrentUser else {
            return
        }
        onOpenDetails()
    }

    private var sportTint: Color {
        switch search.sport {
        case .padel:
            return Color(red: 0.82, green: 0.60, blue: 0.05)
        case .badminton:
            return Color.blue.opacity(0.82)
        default:
            return AppTheme.court
        }
    }

    private func cardMeta(systemImage: String, text: String) -> some View {
        if text.isEmpty {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.72))
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.84))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    private var hotCardTimeText: String {
        if let startsAt = search.hotStartsAt?.parsedISODateValue() {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMM, HH:mm"
            return formatter.string(from: startsAt)
        }
        return search.hotStartsAt?.formattedDateTime() ?? L10n.string("Time not specified", "Время не указано")
    }

    private func hotSearchMetaPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(systemImage == "flame.fill" ? .red.opacity(0.92) : AppTheme.ink)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(systemImage == "flame.fill" ? Color.red.opacity(0.10) : Color.black.opacity(0.04), in: Capsule())
    }

    private func playerNoun(count: Int) -> String {
        if LocaleStore.currentEffectiveLocale == .en { return "\(count) \(count == 1 ? "player" : "players")" }
        switch count {
        case 1:
            return "1 игрока"
        case 2 ... 4:
            return "\(count) игроков"
        default:
            return "\(count) игроков"
        }
    }

    private func responseWord(_ count: Int) -> String {
        if LocaleStore.currentEffectiveLocale == .en { return count == 1 ? "response" : "responses" }
        switch count {
        case 1:
            return "отклик"
        case 2 ... 4:
            return "отклика"
        default:
            return "откликов"
        }
    }

    private func peopleWord(_ count: Int) -> String {
        if LocaleStore.currentEffectiveLocale == .en { return count == 1 ? "player" : "players" }
        switch count {
        case 1:
            return "игрок"
        case 2 ... 4:
            return "игрока"
        default:
            return "игроков"
        }
    }
}

private struct SearchDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let initialSearch: GameSearch
    let onEdit: (GameSearch) -> Void
    let onOpenLobby: (String) -> Void
    let onReloadParent: () async -> Void

    @State private var search: GameSearch
    @State private var courts: [Court] = []
    @State private var editingOccurrence: RegularPairOccurrence?
    @State private var updatingSearchID: String?
    @State private var updatingResponseID: String?
    @State private var updatingOccurrenceID: String?
    @State private var shareItems: [Any] = []
    @State private var didCopyInviteLink = false
    @State private var isPresentingResponses = false

    init(
        initialSearch: GameSearch,
        onEdit: @escaping (GameSearch) -> Void,
        onOpenLobby: @escaping (String) -> Void,
        onReloadParent: @escaping () async -> Void
    ) {
        self.initialSearch = initialSearch
        self.onEdit = onEdit
        self.onOpenLobby = onOpenLobby
        self.onReloadParent = onReloadParent
        _search = State(initialValue: initialSearch)
    }

    private var pendingResponses: [SearchResponse] {
        search.responses.filter { $0.status == "pending" }
    }

    private var approvedResponses: [SearchResponse] {
        search.responses.filter { $0.status == "approved" }
    }

    private var remainingSeats: Int {
        max(search.playersNeeded - approvedResponses.count, 0)
    }

    private var shouldShowLobbyButton: Bool {
        search.playersNeeded > 1 && !approvedResponses.isEmpty
    }

    private var usesRegularSlotLobby: Bool {
        search.searchType == .regular && search.playersNeeded <= 1
    }

    private var isCompleted: Bool {
        search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1)
    }

    private var canManageSearch: Bool {
        !isCompleted
    }

    private var lobbyActionTitle: String {
        usesRegularSlotLobby ? L10n.string("Suggest a time to play", "Предложите время для игры") : L10n.string("Roster and game chat", "Состав и чат игры")
    }

    private var lobbyActionSubtitle: String {
        usesRegularSlotLobby
            ? L10n.string("Open the shared roster to suggest time slots and discuss the game.", "Открой общий состав, чтобы предложить слоты и обсудить детали игры.")
            : L10n.string("Open the roster chat to discuss details without a time-slot poll.", "Открой общий чат состава, чтобы уточнить детали без опроса по слотам.")
    }

    private var lobbyActionButtonTitle: String {
        usesRegularSlotLobby ? L10n.string("Suggest time slots", "Предложить слоты") : L10n.string("Open roster", "Открыть состав")
    }

    private var parameterRows: [(icon: String, title: String, value: String)] {
        var rows: [(String, String, String)] = []

        rows.append(("sportscourt", L10n.string("Game format", "Формат игры"), search.sport.formatTitle(format: search.format, playersNeeded: search.playersNeeded)))
        rows.append(("person.2", L10n.string("Players needed", "Нужно игроков"), remainingSeats == 0 ? L10n.string("\(search.playersNeeded) · roster complete", "\(search.playersNeeded) · состав собран") : L10n.string("\(search.playersNeeded) · \(remainingSeats) left", "\(search.playersNeeded) · осталось \(remainingSeats)")))

        if let min = search.desiredLevelMin, let max = search.desiredLevelMax {
            rows.append(("chart.bar.xaxis", L10n.string("Level", "Уровень"), "\(min)–\(max)"))
        }

        let schedule: String
        if search.searchType == .hot {
            schedule = [
                search.hotWindow?.title,
                search.hotStartsAt?.formattedDateTime()
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        } else {
            schedule = [
                search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.joined(separator: ", "),
                search.preferredTimeRanges.map(localizedTimePreferenceTitle).joined(separator: ", ")
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        }
        if !schedule.isEmpty {
            rows.append(("clock", L10n.string("Time", "Время"), schedule))
        }

        let districts = search.preferredDistricts.compactMap(localizedDistrictName).joined(separator: ", ")
        if !districts.isEmpty {
            rows.append(("map", L10n.string("Districts", "Районы"), districts))
        }

        let venue = search.preferredCourt?.name
            ?? search.customVenueAddress
            ?? search.customVenueTitle
            ?? (search.sport.isRouteSport ? L10n.string("Route not specified", "Маршрут не указан") : L10n.string("Not specified", "Не указан"))
        rows.append(("building.2", search.sport.isRouteSport ? L10n.string("Route", "Маршрут") : L10n.string("Court / club", "Корт / клуб"), venue))
        if search.sport.isRouteSport,
           let route = search.runningRoute?.trimmingCharacters(in: .whitespacesAndNewlines),
           !route.isEmpty {
            rows.append(("point.topleft.down.curvedto.point.bottomright.up", L10n.string("Route details", "Детали маршрута"), route))
        }
        rows.append(("bubble.left", L10n.string("Comment", "Комментарий"), (search.comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? search.comment! : L10n.string("Not specified", "Не указан"))))
        return rows
    }

    private var upcomingRegularOccurrences: [RegularPairOccurrence] {
        guard let occurrences = search.regularPair?.occurrences else {
            return []
        }

        return occurrences
            .filter { $0.scheduledAt.parsedISODateValue().map { $0 > Date() } ?? false }
            .sorted { ($0.scheduledAt.parsedISODateValue() ?? .distantFuture) < ($1.scheduledAt.parsedISODateValue() ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    detailHero
                    responseSummaryCard
                    detailActions
                    parameterCard

                    if shouldShowLobbyButton {
                        lobbyActionCard
                    }

                    if let regularPair = search.regularPair {
                        SearchEmbeddedSection(
                            title: L10n.string("Recurring time slots", "Регулярные слоты"),
                            subtitle: L10n.string("Confirm upcoming slots and open the pair chat.", "Подтверждай ближайшие слоты и открывай чат пары.")
                        ) {
                            RegularPairCard(
                                regularPair: regularPair,
                                currentUserId: appModel.currentUser?.id,
                                upcomingOccurrences: upcomingRegularOccurrences,
                                updatingOccurrenceID: updatingOccurrenceID,
                                onOpenChat: {
                                    appModel.pendingChatMatchID = regularPair.matchId
                                    dismiss()
                                    appModel.navigate(to: .matches)
                                },
                                onConfirmOccurrence: { occurrence in
                                    await updateOccurrence(regularPairId: regularPair.id, occurrenceId: occurrence.id, status: "confirmed", scheduledAt: nil, proposedCourtId: nil)
                                },
                                onDeclineOccurrence: { occurrence in
                                    await updateOccurrence(regularPairId: regularPair.id, occurrenceId: occurrence.id, status: "declined", scheduledAt: nil, proposedCourtId: nil)
                                },
                                onEditOccurrence: { occurrence in
                                    await loadCourtsIfNeeded()
                                    editingOccurrence = occurrence
                                }
                            )
                        }
                    }

                    inviteCard

                    if canManageSearch {
                        Button {
                            Task { await toggleSearchActive() }
                        } label: {
                            if updatingSearchID == search.id {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                            } else {
                                Label((search.isActive ?? true) ? L10n.string("Pause search", "Остановить поиск") : L10n.string("Start search", "Запустить поиск"), systemImage: (search.isActive ?? true) ? "pause.fill" : "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: .red.opacity(0.88)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(L10n.string("Game search", "Поиск игры"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: shareInviteLink) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    Button(action: shareInviteLink) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            }
            .sheet(item: $editingOccurrence) { occurrence in
                RegularPairOccurrenceEditorSheet(
                    occurrence: occurrence,
                    courts: courts,
                    onSave: { date, courtId in
                        guard let regularPair = search.regularPair else { return }
                        await updateOccurrence(regularPairId: regularPair.id, occurrenceId: occurrence.id, status: nil, scheduledAt: date, proposedCourtId: courtId)
                    }
                )
            }
            .sheet(isPresented: $isPresentingResponses) {
                SearchResponsesSheet(
                    search: $search,
                    updatingResponseID: updatingResponseID,
                    onUpdateResponseStatus: { responseId, status in
                        await updateResponseStatus(responseId: responseId, status: status)
                    },
                    onShareInviteLink: shareInviteLink,
                    onFinalizeRoster: {
                        await finalizeApprovedRoster()
                    },
                    onOpenLobby: {
                        isPresentingResponses = false
                        onOpenLobby(search.id)
                    }
                )
                .environmentObject(appModel)
            }
            .sheet(isPresented: Binding(
                get: { !shareItems.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        shareItems = []
                    }
                }
            )) {
                ActivityShareSheet(items: shareItems)
            }
        }
    }

    private var detailHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay(
                        SportIconView(sport: search.sport, color: .white, size: 20)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(search.sport.title) · \(search.sport.formatTitle(format: search.format, playersNeeded: search.playersNeeded))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(detailHeadline)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                AppInlineChip(
                    text: (search.isActive ?? true) ? L10n.string("Active", "Активен") : L10n.string("Paused", "На паузе"),
                    tint: .white.opacity(0.18),
                    foreground: .white
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    detailMetaRow(icon: "calendar", text: search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.joined(separator: ", "))
                    detailMetaRow(icon: "clock", text: search.preferredTimeRanges.map(localizedTimePreferenceDetailTitle).joined(separator: " · "))
                }
                HStack(spacing: 12) {
                    detailMetaRow(icon: "map", text: search.preferredDistricts.compactMap(localizedDistrictName).joined(separator: ", "))
                    detailMetaRow(icon: "building.2", text: search.preferredCourt?.name ?? L10n.string("No club", "Без клуба"))
                }
            }
        }
        .padding(15)
        .background(
            LinearGradient(colors: [AppTheme.court, AppTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var responseSummaryCard: some View {
        Button {
            isPresentingResponses = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(L10n.string("\(search.responses.count) responses", "\(search.responses.count) откликов"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        if !pendingResponses.isEmpty {
                            Text(L10n.string("· \(pendingResponses.count) new", "· \(pendingResponses.count) новых"))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.red.opacity(0.9))
                        }
                    }
                    Text(L10n.string("Players who responded to this search", "Откликнувшиеся игроки по этому поиску"))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.56))
                }

                Spacer()

                HStack(spacing: -10) {
                    ForEach(Array(search.responses.prefix(4).enumerated()), id: \.offset) { index, response in
                        RemoteAvatarView(name: response.responderUser.displayName, path: response.responderUser.avatarUrl, size: 34)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .zIndex(Double(4 - index))
                    }
                    if max(search.responses.count - 4, 0) > 0 {
                        Text("+\(search.responses.count - 4)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.ink.opacity(0.72))
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.05), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.28))
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var detailActions: some View {
        HStack(spacing: 10) {
            Button {
                isPresentingResponses = true
            } label: {
                Label(L10n.string("Responses", "Отклики"), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(AppTheme.court, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if canManageSearch {
                Button {
                    onEdit(search)
                } label: {
                    Label(L10n.string("Edit", "Изменить"), systemImage: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ink)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

                Button {
                    Task { await toggleSearchActive() }
                } label: {
                    Label((search.isActive ?? true) ? L10n.string("Pause", "Пауза") : L10n.string("Start", "Запуск"), systemImage: (search.isActive ?? true) ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ink)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var parameterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("Details", "Параметры"))
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ForEach(Array(parameterRows.enumerated()), id: \.offset) { index, row in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.64))
                            .frame(width: 22)
                        Text(row.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.72))
                        Spacer()
                        Text(row.value)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.ink.opacity(0.24))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    if index < parameterRows.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Invitation link", "Ссылка-приглашение"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Text(L10n.string("Share the link so players can respond", "Делитесь ссылкой, чтобы игроки могли откликнуться"))
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.58))

            HStack(spacing: 10) {
                Text(AppConfig.searchInviteURL(searchId: search.inviteSlug ?? search.id)?.absoluteString ?? L10n.string("Link unavailable", "Ссылка недоступна"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.court)
                    .lineLimit(1)

                Spacer()

                Button {
                    copyInviteLink()
                } label: {
                    HStack(spacing: 6) {
                        if didCopyInviteLink {
                            Text(L10n.string("Copied", "Скопировано"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.court)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }

                        Image(systemName: didCopyInviteLink ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(didCopyInviteLink ? AppTheme.court : AppTheme.ink)
                    }
                    .animation(.easeInOut(duration: 0.18), value: didCopyInviteLink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var lobbyActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: search.searchType == .regular ? "calendar.badge.plus" : "person.3.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lobbyActionTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(lobbyActionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.62))
                }
            }

            Button {
                onOpenLobby(search.id)
            } label: {
                Text(lobbyActionButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
        }
        .padding(18)
        .background(AppTheme.mint.opacity(0.46), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.court.opacity(0.14), lineWidth: 1)
        )
    }

    private var detailSportIcon: String {
        search.sport.appSystemIconName
    }

    private var detailHeadline: String {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return L10n.string("Roster complete", "Состав собран")
        }
        if let min = search.desiredLevelMin, let max = search.desiredLevelMax {
            return L10n.string("Looking for \(search.playersNeeded) player(s), level \(min)–\(max)", "Ищу \(search.playersNeeded) игроков уровня \(min)–\(max)")
        }
        return L10n.string("Looking for \(search.playersNeeded) player(s)", "Ищу \(search.playersNeeded) игроков")
    }

    private func detailMetaRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(text.isEmpty ? L10n.string("Not specified", "Не указано") : text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareInviteLink() {
        guard let inviteURL = AppConfig.searchInviteURL(searchId: search.inviteSlug ?? search.id) else {
            appModel.errorMessage = L10n.string("Could not prepare the invitation link", "Не удалось подготовить ссылку приглашения")
            return
        }
        AppHaptics.selection()
        shareItems = [L10n.string("Join my game search on TennisSearch", "Присоединяйся к моему поиску игры в TennisSearch"), inviteURL]
    }

    private func copyInviteLink() {
        guard let inviteURL = AppConfig.searchInviteURL(searchId: search.inviteSlug ?? search.id) else {
            appModel.errorMessage = L10n.string("Could not prepare the invitation link", "Не удалось подготовить ссылку приглашения")
            return
        }

        UIPasteboard.general.string = inviteURL.absoluteString
        AppHaptics.selection()
        didCopyInviteLink = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            didCopyInviteLink = false
        }
    }

    private func reloadSearch() async {
        do {
            let searches = try await appModel.repository.fetchSearches()
            if let updated = searches.first(where: { $0.id == search.id }) {
                search = updated
            }
            await onReloadParent()
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func updateResponseStatus(responseId: String, status: String) async {
        updatingResponseID = responseId
        defer { updatingResponseID = nil }

        do {
            let result = try await appModel.repository.updateSearchResponseStatus(responseId: responseId, status: status)
            search = search.applying(responseUpdate: result)
            let searches = try await appModel.repository.fetchSearches()
            if let updated = searches.first(where: { $0.id == search.id }) {
                search = updated.applying(responseUpdate: result)
            }
            await onReloadParent()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func toggleSearchActive() async {
        updatingSearchID = search.id
        defer { updatingSearchID = nil }

        do {
            search = try await appModel.repository.setSearchActive(searchId: search.id, isActive: !(search.isActive ?? true))
            await onReloadParent()
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func finalizeApprovedRoster() async {
        guard let scheduledAt = search.hotStartsAt?.parsedISODateValue() else {
            appModel.errorMessage = L10n.string("Could not determine the game time", "Не удалось определить время игры")
            return
        }

        updatingSearchID = search.id
        defer { updatingSearchID = nil }

        do {
            let result = try await appModel.repository.scheduleSearchGame(
                searchId: search.id,
                courtId: search.preferredCourt?.id,
                scheduledAt: scheduledAt,
                durationMinutes: search.durationMinutes ?? 90
            )
            search = result.gameSearch
            await onReloadParent()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
            isPresentingResponses = false

            if let gameRequestId = result.gameRequestId {
                dismiss()
                appModel.navigate(to: .discover(.upcoming, highlightedGameRequestID: gameRequestId))
            }
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func loadCourtsIfNeeded() async {
        guard courts.isEmpty else { return }
        do {
            courts = try await appModel.repository.fetchCourts()
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }

    private func updateOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: Date?,
        proposedCourtId: String?
    ) async {
        updatingOccurrenceID = occurrenceId
        defer { updatingOccurrenceID = nil }

        do {
            _ = try await appModel.repository.updateRegularPairOccurrence(
                regularPairId: regularPairId,
                occurrenceId: occurrenceId,
                status: status,
                scheduledAt: scheduledAt,
                proposedCourtId: proposedCourtId
            )
            await reloadSearch()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else { return }
            appModel.present(error: error)
        }
    }
}

private struct SearchResponsesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    @Binding var search: GameSearch
    let updatingResponseID: String?
    let onUpdateResponseStatus: (String, String) async -> Void
    let onShareInviteLink: () -> Void
    let onFinalizeRoster: (() async -> Void)?
    let onOpenLobby: (() -> Void)?

    @State private var selectedFilter: SearchResponsesFilter = .all
    @State private var selectedPlayer: DiscoverUser?
    @State private var isFinalizingRoster = false

    private var filteredResponses: [SearchResponse] {
        switch selectedFilter {
        case .all:
            return search.responses
        case .pending:
            return search.responses.filter { $0.status == "pending" }
        case .approved:
            return search.responses.filter { $0.status == "approved" }
        case .rejected:
            return search.responses.filter { $0.status == "rejected" }
        }
    }

    private var canApproveMoreResponses: Bool {
        search.status != "matched" && search.responses.filter { $0.status == "approved" }.count < max(search.playersNeeded, 1)
    }

    private var approvedResponsesCount: Int {
        search.responses.filter { $0.status == "approved" }.count
    }

    private var shouldShowLobbyShortcut: Bool {
        search.playersNeeded > 1 && approvedResponsesCount > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    searchSummaryCard
                    responsesFilterRail

                    ForEach(filteredResponses) { response in
                        SearchResponseActionRow(
                            response: response,
                            canApprove: canApproveMoreResponses,
                            updatingResponseID: updatingResponseID,
                            onUpdateResponseStatus: onUpdateResponseStatus,
                            onOpenPlayer: { player in
                                selectedPlayer = player
                            }
                        )
                    }

                    if shouldShowLobbyShortcut, let onOpenLobby {
                        Button {
                            if approvedResponsesCount >= max(search.playersNeeded, 1) {
                                onOpenLobby()
                            } else if let onFinalizeRoster {
                                Task {
                                    isFinalizingRoster = true
                                    await onFinalizeRoster()
                                    isFinalizingRoster = false
                                }
                            } else {
                                onOpenLobby()
                            }
                        } label: {
                            if isFinalizingRoster {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label(
                                    approvedResponsesCount >= max(search.playersNeeded, 1)
                                        ? L10n.string("Open roster", "Перейти к составу")
                                        : L10n.string("Finish without a full roster", "Завершить без полного добора"),
                                    systemImage: "person.3.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                        .disabled(isFinalizingRoster)
                    }

                    Button {
                        onShareInviteLink()
                    } label: {
                        Label(L10n.string("Invite more players", "Пригласить ещё игроков"), systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.court))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(L10n.string("Responses", "Отклики"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                ToolbarItem(placement: .principal) {
                    AppInlineChip(
                        text: L10n.string("\(search.responses.count) responses · \(search.responses.filter { $0.status == "pending" }.count) new", "\(search.responses.count) откликов · \(search.responses.filter { $0.status == "pending" }.count) новых"),
                        tint: AppTheme.mint,
                        foreground: AppTheme.court
                    )
                }
            }
        }
        .sheet(item: $selectedPlayer) { player in
            DiscoverParticipantSheet(user: player, onOpenChat: nil)
                .environmentObject(appModel)
        }
    }

    private var searchSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.mint)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "tennis.racket")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.court)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(search.sport.title) · \(search.sport.formatTitle(format: search.format, playersNeeded: search.playersNeeded))")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Text(search.desiredLevelMin != nil && search.desiredLevelMax != nil ? L10n.string("Looking for \(search.playersNeeded) player(s), level \(search.desiredLevelMin!)–\(search.desiredLevelMax!)", "Ищу \(search.playersNeeded) игроков уровня \(search.desiredLevelMin!)–\(search.desiredLevelMax!)") : L10n.string("Looking for \(search.playersNeeded) player(s)", "Ищу \(search.playersNeeded) игроков"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 16) {
                compactMetaRow(icon: "calendar", text: search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.joined(separator: ", "))
                compactMetaRow(icon: "clock", text: search.preferredTimeRanges.map(localizedTimePreferenceDetailTitle).joined(separator: " · "))
            }

            compactMetaRow(icon: "building.2", text: [search.preferredDistricts.compactMap(localizedDistrictName).joined(separator: ", "), search.preferredCourt?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var responsesFilterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchResponsesFilter.allCases) { filter in
                    let count = filter.count(in: search.responses)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(filter.title)
                            Text("\(count)")
                                .foregroundStyle(selectedFilter == filter ? .white.opacity(0.92) : AppTheme.ink.opacity(0.58))
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedFilter == filter ? .white : AppTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(selectedFilter == filter ? AppTheme.court : Color.white, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedFilter == filter ? AppTheme.court : Color.black.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func compactMetaRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.72))
            Text(text.isEmpty ? L10n.string("Not specified", "Не указано") : text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.ink.opacity(0.82))
                .lineLimit(2)
        }
    }
}

private struct SearchResponseActionRow: View {
    let response: SearchResponse
    let canApprove: Bool
    let updatingResponseID: String?
    let onUpdateResponseStatus: (String, String) async -> Void
    let onOpenPlayer: (DiscoverUser) -> Void

    private var levelLine: String? {
        if let level = response.responderUser.sportLevels["tennis"] ?? response.responderUser.tennisLevel {
            return String(format: "%.1f", Double(level))
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onOpenPlayer(response.responderUser)
            } label: {
                HStack(spacing: 12) {
                    RemoteAvatarView(name: response.responderUser.displayName, path: response.responderUser.avatarUrl, size: 56)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(response.responderUser.displayName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                            if let levelLine {
                                Text(levelLine)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AppTheme.ink.opacity(0.58))
                            }
                            Spacer()
                            statusPill
                        }

                        Text(response.responderUser.bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? defaultSubtitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.68))
                            .lineLimit(2)

                        if let district = response.responderUser.districtLabel ?? response.responderUser.district {
                            Text(localizedDistrictName(district) ?? district)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.ink.opacity(0.5))
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if response.status == "pending" {
                HStack(spacing: 10) {
                    if canApprove {
                        circleAction(systemImage: "checkmark", tint: AppTheme.court, foreground: .white, status: "approved")
                    } else {
                        Text(L10n.string("Roster complete", "Состав собран"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.ink.opacity(0.54))
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.05), in: Capsule())
                    }
                    circleAction(systemImage: "xmark", tint: Color.black.opacity(0.06), foreground: AppTheme.ink, status: "rejected")
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.24))
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var defaultSubtitle: String {
        switch response.status {
        case "approved":
            return L10n.string("Player is already on the roster", "Игрок уже в составе")
        case "rejected":
            return L10n.string("The response was rejected", "Отклик был отклонён")
        default:
            return L10n.string("Wants to join the game", "Хочет присоединиться к игре")
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch response.status {
        case "approved":
            AppInlineChip(text: L10n.string("APPROVED", "ОДОБРЕН"), tint: AppTheme.mint, foreground: AppTheme.court)
        case "rejected":
            AppInlineChip(text: L10n.string("REJECTED", "ОТКЛОНЁН"), tint: Color.red.opacity(0.12), foreground: .red.opacity(0.9))
        default:
            EmptyView()
        }
    }

    private func circleAction(systemImage: String, tint: Color, foreground: Color, status: String) -> some View {
        Button {
            Task { await onUpdateResponseStatus(response.id, status) }
        } label: {
            if updatingResponseID == response.id {
                ProgressView()
                    .tint(foreground)
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .background(tint, in: Circle())
        .disabled(updatingResponseID == response.id)
    }
}

private extension TimeRange {
    var detailTitle: String {
        switch self {
        case .morning:
            return L10n.string("Morning", "Утро")
        case .day:
            return L10n.string("Afternoon", "День")
        case .evening:
            return L10n.string("Evening (after 6 PM)", "Вечер (после 18:00)")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Date {
    func formattedShortRelative() -> String {
        if Calendar.current.isDateInToday(self) {
            return L10n.string("Today, \(formattedHourMinute())", "Сегодня, \(formattedHourMinute())")
        }
        if Calendar.current.isDateInTomorrow(self) {
            return L10n.string("Tomorrow, \(formattedHourMinute())", "Завтра, \(formattedHourMinute())")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM, HH:mm")
        return formatter.string(from: self)
    }
}

private struct SearchEmbeddedSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }

            content
        }
    }
}

private struct PendingSearchChatPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
    let fileName: String
    let mimeType: String
}

private struct SearchChatMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: ChatMediaAttachment

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemoteChatMediaImage(path: attachment.url, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding(20)
        }
    }
}

struct SearchLobbySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let searchId: String

    @State private var lobby: SearchLobbyGameSearch?
    @State private var lobbyLoadRevision = 0
    @State private var lobbyLoadError: String?
    @State private var courts: [Court] = []
    @State private var messageText = ""
    @State private var proposedCourtId = ""
    @State private var courtQuery = ""
    @State private var proposedAt = Date().addingTimeInterval(24 * 60 * 60)
    @State private var selectedSlotDateKeys: Set<String> = []
    @State private var durationMinutes = 90
    @State private var slotComment = ""
    @State private var selectedSlotTimeRange: TimeRange = .evening
    @State private var selectedSlotTimes: Set<String> = ["19:00"]
    @State private var selectedVoteOptionIDs: Set<String> = []
    @State private var isCourtPickerPresented = false
    @State private var isDatePickerPresented = false
    @State private var isSendingMessage = false
    @State private var isScheduling = false
    @State private var isVotingOnSlots = false
    @State private var isSimulatingRegularFlow = false
    @State private var simulationMessage: String?
    @State private var lastLobbyPresenceRefresh = Date.distantPast
    @State private var selectedLobbyPlayer: DiscoverUser?
    @State private var isChatPhotoPickerPresented = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var pendingPhotos: [PendingSearchChatPhoto] = []
    @State private var selectedMediaAttachment: ChatMediaAttachment?
    @FocusState private var isMessageComposerFocused: Bool
    private let bottomAnchorID = "search-lobby-bottom-anchor"

    private var approvedResponses: [SearchResponse] {
        lobby?.responses.filter { $0.status == "approved" } ?? []
    }

    private var pendingResponses: [SearchResponse] {
        lobby?.responses.filter { $0.status == "pending" } ?? []
    }

    private var isCreator: Bool {
        lobby?.createdByUserId == appModel.currentUser?.id
    }

    private var canProposeSlotsInLobby: Bool {
        guard let lobby else {
            return false
        }
        return isCreator && lobby.searchType == .regular && lobby.playersNeeded <= 1 && !approvedResponses.isEmpty
    }

    private var canVoteForSlotsInLobby: Bool {
        guard let lobby else {
            return false
        }
        return lobby.searchType == .regular && lobby.playersNeeded <= 1 && lobby.activeSlotProposal != nil
    }

    private var canSimulateRegularFlow: Bool {
        guard let lobby else {
            return false
        }
        return isCreator && lobby.searchType == .regular && lobby.playersNeeded <= 1
    }

    private var availableCourts: [Court] {
        guard let lobby else {
            return courts
        }

        return courts.filter { court in
            guard let supportedSports = court.supportedSports, !supportedSports.isEmpty else {
                return true
            }
            return supportedSports.contains(lobby.sport)
        }
    }

    private var filteredCourts: [Court] {
        let trimmedQuery = courtQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sortedCourts = availableCourts.sorted { left, right in
            if left.id == proposedCourtId { return true }
            if right.id == proposedCourtId { return false }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        guard !trimmedQuery.isEmpty else {
            return Array(sortedCourts.prefix(18))
        }

        return sortedCourts.filter { court in
            searchableText(for: court).contains(trimmedQuery)
        }
    }

    private var selectedDay: Date {
        Calendar.current.startOfDay(for: proposedAt)
    }

    private var selectedSlotDates: [Date] {
        var selected = dateOptions.filter { selectedSlotDateKeys.contains(dateKey(for: $0)) }
        let currentKey = dateKey(for: selectedDay)
        if selectedSlotDateKeys.contains(currentKey),
           !selected.contains(where: { Calendar.current.isDate($0, inSameDayAs: selectedDay) }) {
            selected.append(selectedDay)
        }
        return selected.isEmpty ? [selectedDay] : selected
    }

    private var dateOptions: [Date] {
        let calendar = Calendar.current
        let preferred = (lobby?.preferredDays ?? []).compactMap(DayOfWeek.init(rawValue:))
        var dates: [Date] = []
        var seenWeekdays = Set<DayOfWeek>()
        for offset in 0 ..< 14 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let weekday = dayOfWeek(for: date)
            if (preferred.isEmpty || preferred.contains(weekday)), !seenWeekdays.contains(weekday) {
                dates.append(calendar.startOfDay(for: date))
                seenWeekdays.insert(weekday)
            }
            if dates.count == max(preferred.count, preferred.isEmpty ? 5 : preferred.count) {
                break
            }
        }
        return dates.isEmpty ? [calendar.startOfDay(for: Date())] : dates
    }

    private var timeOptions: [String] {
        Self.timeOptions(for: selectedSlotTimeRange)
    }

    private var selectedTimeLabel: String {
        proposedAt.formattedHourMinute()
    }

    private var selectedSlotCount: Int {
        selectedSlotDates.count * selectedSlotTimes.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            searchLobbyContent

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                    .chatReceiptViewport(
                        incomingIDs: (lobby?.messages ?? []).filter { $0.senderUserId != appModel.currentUser?.id }.map(\.id),
                        isUncovered: !isChatPhotoPickerPresented && !isCourtPickerPresented && !isDatePickerPresented && selectedLobbyPlayer == nil && selectedMediaAttachment == nil,
                        scope: .search(searchId), repository: appModel.repository
                    )
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isMessageComposerFocused = false
                    }
                    .onAppear {
                        scrollLobbyToBottom(proxy, animated: false)
                    }
                    .onChange(of: lobbyMessageSignature) { _ in
                        scrollLobbyToBottom(proxy)
                    }
                    .onChange(of: isMessageComposerFocused) { isFocused in
                        if isFocused {
                            scrollLobbyToBottom(proxy)
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("Search lobby", "Лобби поиска"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                appModel.notificationManager.setNotificationMuted(href: "/play/searches/\(searchId)", isMuted: true)
                await loadLobby()
                await loadLobbyCourts()
                await updateSearchLobbyPresence(isActive: true)
                await runRealtimeLobbyUpdates()
            }
            .onDisappear {
                appModel.notificationManager.setNotificationMuted(href: "/play/searches/\(searchId)", isMuted: false)
                Task {
                    await updateSearchLobbyPresence(isActive: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tennisRealtimeEventReceived)) { notification in
                guard let event = notification.object as? RealtimeEvent,
                      shouldRefreshLobby(for: event) else {
                    return
                }

                Task {
                    await loadLobby()
                }
            }
            .onChange(of: photoPickerItems) { items in
                Task { await loadPendingPhotos(from: items) }
            }
            .sheet(isPresented: $isCourtPickerPresented) {
                SearchClubPickerSheet(
                    sport: lobby?.sport ?? .tennis,
                    courts: availableCourts,
                    selectedCourtId: proposedCourtId.isEmpty ? nil : proposedCourtId,
                    selectsImmediately: false,
                    onSelect: { court in
                        proposedCourtId = court?.id ?? ""
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $isDatePickerPresented) {
                NavigationStack {
                    VStack(spacing: 20) {
                        DatePicker(
                            L10n.string("Game date", "Дата игры"),
                            selection: Binding(
                                get: { proposedAt },
                                set: { date in
                                    proposedAt = date
                                    selectedSlotDateKeys.insert(dateKey(for: date))
                                }
                            ),
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()

                        Button(L10n.string("Done", "Готово")) {
                            isDatePickerPresented = false
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                    }
                    .padding(20)
                    .background(Color.white.ignoresSafeArea())
                    .navigationTitle(L10n.string("Choose date", "Выбрать дату"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L10n.string("Close", "Закрыть")) {
                                isDatePickerPresented = false
                            }
                            .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
            }
            .sheet(item: $selectedLobbyPlayer) { player in
                DiscoverParticipantSheet(user: player, onOpenChat: nil)
                    .environmentObject(appModel)
            }
            .fullScreenCover(item: $selectedMediaAttachment) { attachment in
                SearchChatMediaViewer(attachment: attachment)
            }
        }
    }

    @ViewBuilder
    private var searchLobbyContent: some View {
        if let lobby {
            SectionCard(
                title: L10n.string("Roster and group chat", "Состав и общий чат"),
                subtitle: L10n.string("This is the shared space for this search. The roster and discussion are visible here before the final game.", "Это общее пространство по этому поиску. Здесь видно состав и обсуждение до финальной игры.")
            ) {
                HStack(spacing: 10) {
                    AppInlineChip(
                        text: L10n.string("\(approvedResponses.count) of \(max(lobby.playersNeeded, 1)) confirmed", "\(approvedResponses.count) из \(max(lobby.playersNeeded, 1)) подтверждено"),
                        tint: AppTheme.mint,
                        foreground: AppTheme.court
                    )
                    AppInlineChip(
                        text: lobby.sport.formatTitle(format: lobby.format, playersNeeded: lobby.playersNeeded),
                        tint: AppTheme.cream,
                        foreground: AppTheme.ink
                    )
                }

                if let comment = lobby.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
                    Text(comment)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink.opacity(0.72))
                }

                if canSimulateRegularFlow {
                    Button {
                        Task { await simulateRegularFlow() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSimulatingRegularFlow {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppTheme.court)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(L10n.string("Simulate responses and slots", "Симулировать отклики и слоты"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .opacity(0.55)
                        }
                        .foregroundStyle(AppTheme.court)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(AppTheme.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSimulatingRegularFlow)
                }

                if let simulationMessage {
                    Text(simulationMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.court)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(AppTheme.mint.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            SectionCard(
                title: L10n.string("Participants", "Участники"),
                subtitle: L10n.string("Confirmed players are on the roster; pending players haven’t been accepted yet.", "Подтвержденные игроки уже в составе, ожидающие пока не приняты.")
            ) {
                VStack(spacing: 10) {
                    ForEach(approvedResponses) { response in
                        lobbyParticipantRow(response: response, title: L10n.string("On roster", "В составе"), tint: AppTheme.court)
                    }

                    ForEach(pendingResponses) { response in
                        lobbyParticipantRow(response: response, title: L10n.string("Awaiting response", "Ожидаем ответ"), tint: Color(red: 1.0, green: 0.70, blue: 0.30))
                    }
                }
            }

            if canProposeSlotsInLobby {
                slotProposalSection(lobby: lobby)
            } else if canVoteForSlotsInLobby, let activeSlotProposal = lobby.activeSlotProposal {
                slotVotingSection(activeSlotProposal)
            }

            SectionCard(
                title: L10n.string("Group chat", "Общий чат"),
                subtitle: L10n.string("Use this chat to agree on the roster, district, and expectations before the final game.", "Здесь удобно договориться по составу, району и ожиданиям до финальной игры.")
            ) {
                VStack(spacing: 10) {
                    ForEach(lobby.messages) { message in
                        searchLobbyBubble(message: message)
                            .id(message.id)
                            .chatReceiptRow(id: message.id)
                    }
                }

                if !pendingPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(pendingPhotos) { photo in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: photo.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 70, height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Button {
                                        removePendingPhoto(photo)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    Button {
                        isChatPhotoPickerPresented = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 40, height: 50)
                            .foregroundStyle(AppTheme.court)
                    }
                    .photosPicker(isPresented: $isChatPhotoPickerPresented, selection: $photoPickerItems, maxSelectionCount: 4, matching: .images)
                    .disabled(isSendingMessage)

                    FieldShell {
                        TextField(L10n.string("Message the roster…", "Сообщение для состава..."), text: $messageText, axis: .vertical)
                            .lineLimit(1 ... 4)
                            .focused($isMessageComposerFocused)
                    }

                    Button {
                        Task { await sendMessage() }
                    } label: {
                        if isSendingMessage {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 50, height: 50)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 50, height: 50)
                        }
                    }
                    .buttonStyle(.plain)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                    .disabled(isSendingMessage || (messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingPhotos.isEmpty))
                }
            }
        } else if let lobbyLoadError {
            SectionCard(title: L10n.string("Roster and group chat", "Состав и общий чат"), subtitle: L10n.string("Could not load search details.", "Не удалось загрузить детали поиска.")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lobbyLoadError)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink.opacity(0.68))

                    Button {
                        Task {
                            await loadLobby()
                        }
                    } label: {
                        Label(L10n.string("Try again", "Повторить"), systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        } else {
            SectionCard(title: L10n.string("Roster and group chat", "Состав и общий чат"), subtitle: L10n.string("Loading search details.", "Загружаем детали поиска.")) {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
        }
    }

    private var lobbyMessageSignature: String {
        lobby?.messages.map(\.id).joined(separator: "|") ?? ""
    }

    private func scrollLobbyToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func loadLobby(showErrors: Bool = true) async {
        lobbyLoadRevision += 1
        let revision = lobbyLoadRevision
        if showErrors {
            lobbyLoadError = nil
        }

        do {
            let summary = try await appModel.repository.fetchSearchLobby(searchId: searchId)
            guard revision == lobbyLoadRevision else { return }
            applyLobbySummary(summary)
            lobbyLoadError = nil
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            if showErrors {
                lobbyLoadError = error.detailedMessage
                appModel.present(error: error)
            }
            return
        }
    }

    private func runRealtimeLobbyUpdates() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else {
                return
            }
            await refreshSearchLobbyPresenceIfNeeded()
            await loadLobby(showErrors: false)
        }
    }

    private func refreshSearchLobbyPresenceIfNeeded() async {
        guard Date().timeIntervalSince(lastLobbyPresenceRefresh) > 30 else {
            return
        }

        await updateSearchLobbyPresence(isActive: true)
    }

    private func loadLobbyCourts() async {
        do {
            courts = try await appModel.repository.fetchCourts()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            courts = []
        }
    }

    private func updateSearchLobbyPresence(isActive: Bool) async {
        do {
            try await appModel.repository.setActiveSearchLobby(searchId: searchId, isActive: isActive)
            if isActive {
                lastLobbyPresenceRefresh = Date()
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
        }
    }

    private func shouldRefreshLobby(for event: RealtimeEvent) -> Bool {
        if event.searchId == searchId {
            return true
        }

        if let href = event.href, href == "/play/searches/\(searchId)" {
            return true
        }

        return false
    }

    private func applyLobbySummary(_ summary: SearchLobbySummary) {
        var updated = summary.gameSearch
        updated.messages = mergeChatReceipts(current: lobby?.messages ?? [], fetched: updated.messages)
        lobby = updated
        proposedCourtId = summary.gameSearch.scheduledCourt?.id ?? summary.gameSearch.preferredCourt?.id ?? ""
        proposedAt = summary.gameSearch.scheduledAt?.parsedISODateValue() ?? summary.gameSearch.hotStartsAt?.parsedISODateValue() ?? proposedAt
        durationMinutes = summary.gameSearch.scheduledDurationMinutes ?? summary.gameSearch.durationMinutes ?? 90
        if let preferredRange = summary.gameSearch.preferredTimeRanges.compactMap(TimeRange.init(rawValue:)).first {
            selectedSlotTimeRange = preferredRange
        }
        let exactTimes = summary.gameSearch.preferredTimeRanges.compactMap(Self.timeValue(from:))
        if !exactTimes.isEmpty {
            selectedSlotTimes = Set(exactTimes)
            if let firstExactTime = exactTimes.first,
               let inferredRange = Self.inferredTimeRange(for: firstExactTime) {
                selectedSlotTimeRange = inferredRange
            }
        } else {
            let proposedTime = proposedAt.formattedHourMinute()
            selectedSlotTimes = [
                Self.timeOptions(for: selectedSlotTimeRange).contains(proposedTime)
                    ? proposedTime
                : (Self.timeOptions(for: selectedSlotTimeRange).first ?? "19:00")
            ]
        }
        let pairedDays = Set(summary.gameSearch.preferredTimeRanges.compactMap(Self.dayValue(from:)))
        let selectedKeys = Set(dateOptions.filter { date in
            pairedDays.isEmpty || pairedDays.contains(dayOfWeek(for: date).rawValue)
        }.map(dateKey(for:)))
        selectedSlotDateKeys = selectedKeys.isEmpty ? [dateKey(for: selectedDay)] : selectedKeys
        if let activeSlotProposal = summary.gameSearch.activeSlotProposal {
            selectedVoteOptionIDs = activeSlotProposal.selectedOptionIDs(for: appModel.currentUser?.id)
        } else {
            selectedVoteOptionIDs = []
        }
    }

    private func searchableText(for court: Court) -> String {
        [
            court.name,
            court.address,
            court.metroDisplayName,
            localizedDistrictName(court.district)
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func prettifyDistrict(_ value: String?) -> String? {
        localizedDistrictName(value)
    }

    @ViewBuilder
    private func courtMetaPill(systemImage: String, text: String?) -> some View {
        if let text, !text.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(text)
                    .lineLimit(1)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.ink.opacity(0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.creamLight, in: Capsule())
        }
    }

    private func lobbyCourtOptionRow(court: Court, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "building.2.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.court : AppTheme.ink.opacity(0.58))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text(court.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        courtMetaPill(systemImage: "tram.fill", text: court.metroDisplayName)
                        courtMetaPill(systemImage: "map.fill", text: prettifyDistrict(court.district))
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.52))
                        Text(court.address)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink.opacity(0.64))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                isSelected ? AppTheme.mint : AppTheme.creamLight,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppTheme.court.opacity(0.2) : Color.white.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sendMessage() async {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingPhotos.isEmpty else {
            return
        }

        isMessageComposerFocused = false
        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            var attachmentIds: [String] = []
            for photo in pendingPhotos {
                let asset = try await appModel.repository.uploadChatMedia(
                    data: photo.data,
                    fileName: photo.fileName,
                    mimeType: photo.mimeType
                )
                attachmentIds.append(asset.id)
            }
            let message = try await appModel.repository.sendSearchLobbyMessage(
                searchId: searchId,
                text: trimmed,
                attachmentIds: attachmentIds
            )
            lobbyLoadRevision += 1 // Do not let an earlier history request remove this sent message.
            lobby = SearchLobbyGameSearch(
                id: lobby?.id ?? searchId,
                createdByUserId: lobby?.createdByUserId ?? appModel.currentUser?.id ?? "",
                createdByUser: lobby?.createdByUser,
                searchType: lobby?.searchType ?? .regular,
                status: lobby?.status ?? "active",
                isActive: lobby?.isActive ?? true,
                sport: lobby?.sport ?? .tennis,
                format: lobby?.format ?? .singles,
                preferredDistricts: lobby?.preferredDistricts ?? [],
                preferredDays: lobby?.preferredDays ?? [],
                preferredTimeRanges: lobby?.preferredTimeRanges ?? [],
                hotStartsAt: lobby?.hotStartsAt,
                durationMinutes: lobby?.durationMinutes,
                playersNeeded: lobby?.playersNeeded ?? 1,
                desiredLevelMin: lobby?.desiredLevelMin,
                desiredLevelMax: lobby?.desiredLevelMax,
                comment: lobby?.comment,
                scheduledAt: lobby?.scheduledAt,
                scheduledDurationMinutes: lobby?.scheduledDurationMinutes,
                preferredCourt: lobby?.preferredCourt,
                scheduledCourt: lobby?.scheduledCourt,
                activeSlotProposal: lobby?.activeSlotProposal,
                responses: lobby?.responses ?? [],
                messages: (lobby?.messages ?? []).filter { $0.id != message.id } + [message]
            )
            messageText = ""
            pendingPhotos = []
            photoPickerItems = []
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func loadPendingPhotos(from items: [PhotosPickerItem]) async {
        var loaded: [PendingSearchChatPhoto] = []
        for (index, item) in items.prefix(4).enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                continue
            }
            let uploadData = image.jpegData(compressionQuality: 0.88) ?? data
            loaded.append(
                PendingSearchChatPhoto(
                    data: uploadData,
                    image: image,
                    fileName: "chat-photo-\(index + 1).jpg",
                    mimeType: "image/jpeg"
                )
            )
        }
        pendingPhotos = loaded
    }

    private func removePendingPhoto(_ photo: PendingSearchChatPhoto) {
        guard let index = pendingPhotos.firstIndex(where: { $0.id == photo.id }) else {
            return
        }
        pendingPhotos.remove(at: index)
        if photoPickerItems.indices.contains(index) {
            photoPickerItems.remove(at: index)
        }
    }

    private func scheduleSlot() async {
        let options = selectedSlotDraftOptions()
        guard !options.isEmpty else {
            return
        }

        isScheduling = true
        defer { isScheduling = false }

        do {
            _ = try await appModel.repository.createSearchSlotProposal(
                searchId: searchId,
                options: options,
                comment: slotComment.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
            slotComment = ""
            await loadLobby()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func selectedSlotDraftOptions() -> [SearchSlotProposalDraftOption] {
        selectedSlotDates.flatMap { date in
            selectedSlotTimes
                .sorted()
                .compactMap { scheduledDate(for: $0, on: date) }
                .map {
                    SearchSlotProposalDraftOption(
                        scheduledAt: $0,
                        proposedCourtId: proposedCourtId.isEmpty ? nil : proposedCourtId,
                        durationMinutes: durationMinutes
                    )
                }
            }
    }

    private func voteForSlots(_ proposal: SearchSlotProposalSummary) async {
        guard !selectedVoteOptionIDs.isEmpty else {
            return
        }

        isVotingOnSlots = true
        defer { isVotingOnSlots = false }

        do {
            _ = try await appModel.repository.voteSearchSlotProposal(
                searchId: searchId,
                proposalId: proposal.id,
                optionIds: Array(selectedVoteOptionIDs)
            )
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
            await loadLobby()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func simulateRegularFlow() async {
        guard !isSimulatingRegularFlow else {
            return
        }

        isSimulatingRegularFlow = true
        defer { isSimulatingRegularFlow = false }

        do {
            let result = try await appModel.repository.simulateRegularSearchActivity(searchId: searchId)
            simulationMessage = result.message
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
            await loadLobby()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func scheduledDate(for label: String, on date: Date) -> Date? {
        let components = label.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(
            bySettingHour: components.first ?? 19,
            minute: components.last ?? 0,
            second: 0,
            of: date
        )
    }

    private func lobbyParticipantRow(response: SearchResponse, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedLobbyPlayer = response.responderUser
            } label: {
                RemoteAvatarView(name: response.responderUser.displayName, path: response.responderUser.avatarUrl, size: 40)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(response.responderUser.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink.opacity(0.58))
            }
            Spacer()
            AppInlineChip(text: title, tint: tint.opacity(0.14), foreground: tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func searchLobbyBubble(message: SearchLobbyMessage) -> some View {
        let isMine = message.senderUserId == appModel.currentUser?.id
        let sender = lobbyUser(for: message.senderUserId)

        return HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 48)
            } else if let sender {
                Button {
                    selectedLobbyPlayer = sender
                } label: {
                    RemoteAvatarView(name: sender.displayName, path: sender.avatarUrl, size: 34)
                }
                .buttonStyle(.plain)
            } else {
                RemoteAvatarView(name: message.senderUser?.name ?? L10n.string("Player", "Игрок"), path: message.senderUser?.avatarUrl, size: 34)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !isMine {
                    Text(message.senderUser?.name ?? L10n.string("Player", "Игрок"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                }

                if !message.attachments.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: message.attachments.count == 1 ? 1 : 2),
                        spacing: 6
                    ) {
                        ForEach(message.attachments.sorted(by: { $0.position < $1.position })) { attachment in
                            Button {
                                selectedMediaAttachment = attachment
                            } label: {
                                RemoteChatMediaImage(path: attachment.url)
                                .frame(width: message.attachments.count == 1 ? 210 : 98, height: message.attachments.count == 1 ? 180 : 98)
                                .background(.black.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(isMine ? .white : AppTheme.ink)
                }

                HStack(spacing: 6) {
                    Text(message.createdAt.formattedDateTime())
                        .font(.caption2)
                        .foregroundStyle(isMine ? .white.opacity(0.72) : AppTheme.ink.opacity(0.42))
                    if isMine { ChatReceiptLabel(receipt: message.receipt, isGroup: true) }
                }
            }
            .padding(14)
            .background(
                isMine
                    ? LinearGradient(colors: [AppTheme.court, AppTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.white.opacity(0.94), AppTheme.creamLight.opacity(0.96)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )

            if !isMine {
                Spacer(minLength: 48)
            }
        }
    }

    private func lobbyUser(for userId: String) -> DiscoverUser? {
        if let responseUser = lobby?.responses.first(where: { $0.responderUser.id == userId })?.responderUser {
            return responseUser
        }

        if lobby?.createdByUser?.id == userId {
            return lobby?.createdByUser
        }

        return nil
    }

    @ViewBuilder
    private func slotProposalSection(lobby: SearchLobbyGameSearch) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .center, spacing: 4) {
                Text(L10n.string("Recurring schedule", "Регулярное расписание"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("Choose days and times that repeat every week", "Выберите дни и время, которые будут повторяться каждую неделю"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }
            .frame(maxWidth: .infinity)

            slotSummaryCard(lobby: lobby)
            if let activeSlotProposal = lobby.activeSlotProposal {
                activeSlotProposalCard(activeSlotProposal)
            }
            dateOptionsRail
            timeOptionsCard
            clubSelectionCard
            slotCommentCard
            slotPrimaryAction
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func slotSummaryCard(lobby: SearchLobbyGameSearch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.mint)
                    .frame(width: 36, height: 36)
                    .overlay(
                        SportIconView(sport: lobby.sport, color: AppTheme.court, size: 18)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(lobby.sport.title) · \(lobby.sport.formatTitle(format: lobby.format, playersNeeded: lobby.playersNeeded))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.78))
                    Text(slotHeadline(for: lobby))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 12) {
                detailPill(icon: "person.2", text: lobby.preferredDistrictsLabel)
                detailPill(icon: "building.2", text: selectedCourtName)
            }
        }
        .padding(15)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var dateOptionsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(dateOptions, id: \.self) { date in
                    dateOptionButton(for: date)
                }

                datePickerAccessoryButton
            }
        }
    }

    private func dateOptionButton(for date: Date) -> some View {
        let key = dateKey(for: date)
        let selected = selectedSlotDateKeys.contains(key)

        return Button {
            updateSelectedDate(date)
        } label: {
            VStack(spacing: 6) {
                Text(dayShortTitle(for: date))
                    .font(.system(size: 15, weight: .medium))
                Text(dayNumberTitle(for: date))
                    .font(.system(size: 26, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : AppTheme.ink)
            .frame(width: 72, height: 82)
            .background(selected ? AppTheme.court : Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? AppTheme.court : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var timeOptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(primaryTimeRangeTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                Spacer()

                Text("\(selectedSlotCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.court, in: Circle())
            }

            HStack(spacing: 8) {
                ForEach(TimeRange.allCases) { range in
                    slotTimeRangeButton(range)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(timeOptions, id: \.self) { time in
                    timeOptionButton(for: time)
                }
            }

            Text(L10n.string("You can choose multiple days and times", "Можно выбрать несколько дней и несколько времен"))
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func timeOptionButton(for time: String) -> some View {
        let selected = selectedSlotTimes.contains(time)

        return Button {
            toggleSlotTime(time)
        } label: {
            Text(time)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(selected ? AppTheme.court : AppTheme.ink.opacity(0.74))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(selected ? AppTheme.mint.opacity(0.55) : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? AppTheme.court : Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func slotTimeRangeButton(_ range: TimeRange) -> some View {
        let selected = selectedSlotTimeRange == range

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                selectedSlotTimeRange = range
            }
        } label: {
            Text(range.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : AppTheme.ink.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(selected ? AppTheme.court : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func activeSlotProposalCard(_ proposal: SearchSlotProposalSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("Current poll", "Текущее голосование"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                AppInlineChip(text: L10n.string("\(proposal.options.count) recurring", "\(proposal.options.count) регулярных"), tint: AppTheme.mint, foreground: AppTheme.court)
            }

            if let comment = proposal.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
                Text(comment)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
            }

            VStack(spacing: 8) {
                ForEach(proposal.options) { option in
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.court)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.mint, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.scheduledAt.formattedDateTime())
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text(option.proposedCourt?.name ?? selectedCourtName)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink.opacity(0.56))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Label("\(option.voteCount)", systemImage: "person.2.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.court)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(AppTheme.mint.opacity(0.75), in: Capsule())
                    }
                    .padding(10)
                    .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func slotVotingSection(_ proposal: SearchSlotProposalSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Choose recurring time slots", "Выберите регулярные слоты"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("Select the days and times that really work every week", "Отметь дни и время, которые реально подходят каждую неделю"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }

            if let comment = proposal.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
                Text(comment)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(proposal.options) { option in
                    slotVoteOptionButton(option)
                }
            }

            Button {
                Task { await voteForSlots(proposal) }
            } label: {
                if isVotingOnSlots {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(L10n.string("Submit selection", "Отправить выбор"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(isVotingOnSlots || selectedVoteOptionIDs.isEmpty)
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func slotVoteOptionButton(_ option: SearchSlotProposalOption) -> some View {
        let selected = selectedVoteOptionIDs.contains(option.id)

        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                if selected {
                    selectedVoteOptionIDs.remove(option.id)
                } else {
                    selectedVoteOptionIDs.insert(option.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(option.scheduledAt.formattedDateTime())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? AppTheme.court : AppTheme.ink)
                    .lineLimit(2)
                Text(option.proposedCourt?.name ?? selectedCourtName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink.opacity(0.54))
                    .lineLimit(1)
                Label("\(option.voteCount)", systemImage: "person.2.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.court)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? AppTheme.mint.opacity(0.6) : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? AppTheme.court : Color.black.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var clubSelectionCard: some View {
        Button {
            isCourtPickerPresented = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Club", "Клуб"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.52))
                    Text(selectedCourtName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                }

                Spacer()

                Text(L10n.string("Choose", "Выбрать"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.88))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Color.black.opacity(0.04), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var slotCommentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Comment (optional)", "Комментарий (необязательно)"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            ZStack(alignment: .leading) {
                if slotComment.isEmpty {
                    Text(L10n.string("For example: an indoor court is preferred", "Например: корт с крышей желателен"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.28))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                }

                TextField("", text: $slotComment, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2 ... 3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
            }
            .frame(minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var slotPrimaryAction: some View {
        VStack(spacing: 8) {
            Button {
                Task { await scheduleSlot() }
            } label: {
                if isScheduling {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                } else {
                    Text(L10n.string("Suggest \(selectedSlotCount) \(selectedSlotCount == 1 ? "slot" : "slots")", "Предложить \(selectedSlotCount) \(slotWord(selectedSlotCount))"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(isScheduling || selectedSlotTimes.isEmpty || selectedSlotDates.isEmpty)

            Text(L10n.string("Selected days and times will repeat every week", "Выбранные дни и время будут повторяться каждую неделю"))
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var selectedCourtName: String {
        availableCourts.first(where: { $0.id == proposedCourtId })?.name ?? (lobby?.preferredCourt?.name ?? L10n.string("No club", "Без клуба"))
    }

    private var primaryTimeRangeTitle: String {
        selectedSlotTimeRange.detailTitle
    }

    private var datePickerAccessoryButton: some View {
        Button {
            isDatePickerPresented = true
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 56, height: 82)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func slotHeadline(for lobby: SearchLobbyGameSearch) -> String {
        if let min = lobby.desiredLevelMin, let max = lobby.desiredLevelMax {
            return L10n.string("Looking for \(lobby.playersNeeded) player(s), level \(min)–\(max)", "Ищу \(lobby.playersNeeded) игроков уровня \(min)–\(max)")
        }
        return L10n.string("Looking for \(lobby.playersNeeded) player(s)", "Ищу \(lobby.playersNeeded) игроков")
    }

    private func updateSelectedDate(_ date: Date) {
        let key = dateKey(for: date)
        if selectedSlotDateKeys.contains(key), selectedSlotDateKeys.count > 1 {
            selectedSlotDateKeys.remove(key)
        } else {
            selectedSlotDateKeys.insert(key)
        }

        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: proposedAt)
        proposedAt = calendar.date(bySettingHour: time.hour ?? 19, minute: time.minute ?? 0, second: 0, of: date) ?? date
    }

    private func updateSelectedTime(_ label: String) {
        let components = label.split(separator: ":").compactMap { Int($0) }
        let calendar = Calendar.current
        proposedAt = calendar.date(bySettingHour: components.first ?? 19, minute: components.last ?? 0, second: 0, of: selectedDay) ?? proposedAt
    }

    private func toggleSlotTime(_ label: String) {
        if selectedSlotTimes.contains(label) {
            selectedSlotTimes.remove(label)
        } else {
            selectedSlotTimes.insert(label)
            updateSelectedTime(label)
        }
    }

    private static func timeOptions(for range: TimeRange) -> [String] {
        switch range {
        case .morning:
            return ["08:00", "08:30", "09:00", "09:30", "10:00", "10:30"]
        case .day:
            return ["12:00", "12:30", "13:00", "13:30", "14:00", "14:30", "15:00", "15:30", "16:00", "16:30", "17:00"]
        case .evening:
            return ["18:00", "18:30", "19:00", "19:30", "20:00", "20:30", "21:00", "21:30", "22:00"]
        }
    }

    private func slotWord(_ count: Int) -> String {
        if count % 10 == 1, count % 100 != 11 {
            return "слот"
        }
        if (2 ... 4).contains(count % 10), !(12 ... 14).contains(count % 100) {
            return "слота"
        }
        return "слотов"
    }

    private func dayOfWeek(for date: Date) -> DayOfWeek {
        switch Calendar.current.component(.weekday, from: date) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .sunday
        }
    }

    private func dayShortTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date).capitalized
    }

    private func dayNumberTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter.string(from: date)
    }

    private func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        ]
        .map(String.init)
        .joined(separator: "-")
    }

    private static func timeValue(from preference: String) -> String? {
        let parts = preference.split(separator: "@", maxSplits: 1).map(String.init)
        let value = parts.count == 2 ? parts[1] : preference
        return value.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) == nil ? nil : value
    }

    private static func dayValue(from preference: String) -> String? {
        let parts = preference.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              DayOfWeek(rawValue: parts[0]) != nil else {
            return nil
        }
        return parts[0]
    }

    private static func inferredTimeRange(for value: String) -> TimeRange? {
        guard timeValue(from: value) != nil,
              let hour = Int(value.prefix(2)) else {
            return nil
        }

        if hour < 12 {
            return .morning
        }
        if hour < 18 {
            return .day
        }
        return .evening
    }

    private func detailPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.ink.opacity(0.82))
    }
}

private struct RegularPairCard: View {
    let regularPair: RegularPairSummary
    let currentUserId: String?
    let upcomingOccurrences: [RegularPairOccurrence]
    let updatingOccurrenceID: String?
    let onOpenChat: () -> Void
    let onConfirmOccurrence: (RegularPairOccurrence) async -> Void
    let onDeclineOccurrence: (RegularPairOccurrence) async -> Void
    let onEditOccurrence: (RegularPairOccurrence) async -> Void

    private var visibleOccurrences: [RegularPairOccurrence] {
        Array(upcomingOccurrences.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RemoteAvatarView(
                    name: regularPair.partnerUser.displayName,
                    path: regularPair.partnerUser.avatarUrl,
                    size: 52
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Recurring pair is active", "Регулярная пара активна"))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.6)
                        .foregroundStyle(AppTheme.court)
                    Text(regularPair.partnerUser.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    if let courtName = regularPair.preferredCourt?.name {
                        Text(courtName)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink.opacity(0.62))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: onOpenChat) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Open chat", "Открыть чат"))
            }

            if visibleOccurrences.isEmpty {
                Text(L10n.string("The pair is created, but upcoming slots haven’t appeared yet. Check the days and times in search settings.", "Пара создана, но ближайшие слоты пока не появились. Проверь дни и время в параметрах поиска."))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.string("Upcoming time slots", "Ближайшие слоты"))
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(1.6)
                            .foregroundStyle(AppTheme.court)
                        Spacer()
                        Text("\(upcomingOccurrences.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppTheme.court, in: Capsule())
                    }

                    ForEach(visibleOccurrences) { occurrence in
                        RegularOccurrenceRow(
                            occurrence: occurrence,
                            currentUserId: currentUserId,
                            partnerUserId: regularPair.partnerUser.id,
                            isUpdating: updatingOccurrenceID == occurrence.id,
                            onConfirm: {
                                await onConfirmOccurrence(occurrence)
                            },
                            onDecline: {
                                await onDeclineOccurrence(occurrence)
                            },
                            onEdit: {
                                await onEditOccurrence(occurrence)
                            }
                        )
                    }

                    if upcomingOccurrences.count > visibleOccurrences.count {
                        Text(L10n.string("\(upcomingOccurrences.count - visibleOccurrences.count) more slots are available in the recurring pair.", "Ещё \(upcomingOccurrences.count - visibleOccurrences.count) слота доступны в регулярной паре."))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink.opacity(0.6))
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.mint.opacity(0.9), lineWidth: 1)
        )
    }
}

private struct RegularOccurrenceRow: View {
    let occurrence: RegularPairOccurrence
    let currentUserId: String?
    let partnerUserId: String
    let isUpdating: Bool
    let onConfirm: () async -> Void
    let onDecline: () async -> Void
    let onEdit: () async -> Void

    private var myConfirmationLabel: String {
        confirmationLabel(for: currentUserId)
    }

    private var partnerConfirmationLabel: String {
        confirmationLabel(for: partnerUserId)
    }

    private var myConfirmationStatus: String? {
        guard let currentUserId else {
            return nil
        }

        return occurrence.confirmations.first(where: { $0.user.id == currentUserId })?.status.lowercased()
    }

    private var shouldShowDecisionBar: Bool {
        guard let myConfirmationStatus else {
            return true
        }

        return !["confirmed", "declined"].contains(myConfirmationStatus)
    }

    private var statusPresentation: (text: String, tint: Color, surface: Color) {
        let declinedUserId = occurrence.confirmations.first(where: { $0.status.lowercased() == "declined" })?.user.id

        switch occurrence.status.lowercased() {
        case "confirmed":
            return (L10n.string("Confirmed", "Подтверждено"), AppTheme.court, AppTheme.mint)
        case "declined":
            if let currentUserId, declinedUserId == currentUserId {
                return (L10n.string("You declined", "Ты отказался"), .red.opacity(0.9), Color.red.opacity(0.12))
            }
            return (L10n.string("Partner can’t make it", "Партнер не может"), .red.opacity(0.9), Color.red.opacity(0.12))
        case "canceled", "cancelled":
            return (L10n.string("Cancelled", "Отменено"), AppTheme.ink.opacity(0.72), Color.gray.opacity(0.18))
        case "expired":
            return (L10n.string("Past", "Уже прошло"), AppTheme.ink.opacity(0.72), Color.gray.opacity(0.18))
        default:
            return (L10n.string("Awaiting confirmation", "Ждет подтверждения"), AppTheme.ink, AppTheme.cream)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(occurrence.scheduledAt.formattedNumericDateTime())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    if let courtName = occurrence.proposedCourt?.name {
                        Text(courtName)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink.opacity(0.62))
                            .lineLimit(1)
                    }
                }

                Spacer()

                AppInlineChip(
                    text: statusPresentation.text,
                    tint: statusPresentation.surface,
                    foreground: statusPresentation.tint
                )
            }

            HStack(spacing: 8) {
                if shouldShowDecisionBar || isUpdating {
                    RegularOccurrenceDecisionBar(
                        isUpdating: isUpdating,
                        hasResolvedDecision: !shouldShowDecisionBar,
                        onConfirm: onConfirm,
                        onDecline: onDecline
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                Button {
                    Task { await onEdit() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 44, height: 38)
                        .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .accessibilityLabel(L10n.string("Change date, time, or club", "Изменить дату, время или клуб"))
            }

            HStack(spacing: 8) {
                confirmationPill(title: L10n.string("You", "Ты"), value: myConfirmationLabel, valueColor: confirmationColor(for: currentUserId))
                confirmationPill(title: L10n.string("Partner", "Партнер"), value: partnerConfirmationLabel, valueColor: confirmationColor(for: partnerUserId))
            }
        }
        .padding(12)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func confirmationPill(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.52))
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func confirmationLabel(for userId: String?) -> String {
        guard let userId else {
            return L10n.string("Awaiting confirmation", "Ждет подтверждения")
        }

        let status = occurrence.confirmations.first(where: { $0.user.id == userId })?.status.lowercased()
        switch status {
        case "confirmed":
            return L10n.string("Confirmed", "Подтверждено")
        case "declined":
            return L10n.string("Can’t make it", "Не смогу")
        default:
            return L10n.string("Awaiting confirmation", "Ждет подтверждения")
        }
    }

    private func confirmationColor(for userId: String?) -> Color {
        guard let userId else {
            return AppTheme.ink.opacity(0.72)
        }

        let status = occurrence.confirmations.first(where: { $0.user.id == userId })?.status.lowercased()
        switch status {
        case "confirmed":
            return AppTheme.court
        case "declined":
            return .red.opacity(0.9)
        default:
            return AppTheme.ink.opacity(0.72)
        }
    }
}

private struct SearchResponseGroupSection: View {
    let title: String
    let tint: Color
    let responses: [SearchResponse]
    let updatingResponseID: String?
    let onUpdateResponseStatus: (String, String) async -> Void

    @State private var isExpanded: Bool

    init(
        title: String,
        tint: Color,
        responses: [SearchResponse],
        updatingResponseID: String?,
        onUpdateResponseStatus: @escaping (String, String) async -> Void
    ) {
        self.title = title
        self.tint = tint
        self.responses = responses
        self.updatingResponseID = updatingResponseID
        self.onUpdateResponseStatus = onUpdateResponseStatus
        _isExpanded = State(initialValue: !responses.isEmpty && (title == L10n.string("Wants to join the game", "Хочет присоединиться к игре") || title == L10n.string("On roster", "В составе")))
    }

    var body: some View {
        if !responses.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 10) {
                    ForEach(responses) { response in
                        SearchResponseRow(
                            response: response,
                            updatingResponseID: updatingResponseID,
                            onUpdateResponseStatus: onUpdateResponseStatus
                        )
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(tint)
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("\(responses.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tint, in: Capsule())
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct SearchResponseRow: View {
    let response: SearchResponse
    let updatingResponseID: String?
    let onUpdateResponseStatus: (String, String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RemoteAvatarView(name: response.responderUser.displayName, path: response.responderUser.avatarUrl, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(response.responderUser.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let district = response.responderUser.districtLabel ?? response.responderUser.district {
                            AppInlineChip(text: districtPrettified(district), tint: AppTheme.mint, foreground: AppTheme.court)
                        }
                        AppInlineChip(text: responseStatusText(response.status), tint: responseStatusTint(response.status), foreground: .white)
                    }
                }
                Spacer()
            }

            if response.status == "pending" {
                HStack(spacing: 8) {
                    actionButton(title: L10n.string("Accept", "Принять"), tint: AppTheme.court, status: "approved")
                    actionButton(title: L10n.string("Reject", "Отклонить"), tint: .red, status: "rejected", secondary: true)
                }
            } else if response.status == "approved" {
                actionButton(title: L10n.string("Remove from roster", "Убрать из состава"), tint: .red, status: "rejected", secondary: true)
            }
        }
        .padding(12)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func actionButton(title: String, tint: Color, status: String, secondary: Bool = false) -> some View {
        let button = Button {
            Task {
                await onUpdateResponseStatus(response.id, status)
            }
        } label: {
            if updatingResponseID == response.id {
                ProgressView()
                    .tint(secondary ? tint : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
        }

        if secondary {
            button
                .buttonStyle(SecondaryActionButtonStyle(tint: tint))
                .disabled(updatingResponseID == response.id)
        } else {
            button
                .buttonStyle(PrimaryActionButtonStyle(tint: tint))
                .disabled(updatingResponseID == response.id)
        }
    }

    private static func districtPrettified(_ value: String) -> String {
        localizedDistrictName(value) ?? value
    }

    private func districtPrettified(_ value: String) -> String {
        Self.districtPrettified(value)
    }

    private func responseStatusText(_ status: String) -> String {
        switch status {
        case "approved":
            return L10n.string("Confirmed", "Подтвержден")
        case "rejected":
            return L10n.string("Rejected", "Отклонен")
        case "withdrawn":
            return L10n.string("Withdrawn", "Отменил сам")
        default:
            return L10n.string("Awaiting response", "Ожидаем ответ")
        }
    }

    private func responseStatusTint(_ status: String) -> Color {
        switch status {
        case "approved":
            return AppTheme.court
        case "rejected":
            return .red.opacity(0.9)
        case "withdrawn":
            return .gray.opacity(0.8)
        default:
            return Color(red: 1.0, green: 0.70, blue: 0.30)
        }
    }
}

private struct SearchOverviewHero: View {
    let sport: Sport
    let isOpen: Bool
    let statusTitle: String
    let hotWindowTitle: String?

    var body: some View {
        ZStack {
            SearchHeroImage(sport: sport)

            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.42), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack {
                    heroChip(text: sport.title, systemImage: "tennis.racket")

                    Spacer()

                    heroStatusChip(
                        text: isOpen ? L10n.string("Open", "Открыт") : statusTitle,
                        tint: isOpen ? Color.black.opacity(0.4) : Color.black.opacity(0.5)
                    )
                }
                .padding(.top, 30)
                .padding(.horizontal, 14)

                Spacer()

                if let hotWindowTitle {
                    HStack {
                        heroChip(text: hotWindowTitle, systemImage: "flame.fill")
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func heroChip(text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.34), in: Capsule())
    }

    private func heroStatusChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
    }
}

private struct SearchHeroImage: View {
    let sport: Sport

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .offset(y: 12)
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
        case .running:
            return ["hero-run", "upcoming-game-hero"]
        case .supboard:
            return ["hero-run", "upcoming-game-hero"]
        }
    }
}

struct SearchComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appModel: AppModel

    @State private var courts: [Court] = []
    @State private var courtQuery = ""
    @State private var draft = SearchDraft(
        inviteSlug: nil,
        preferredCourtId: nil,
        preferredDistricts: [],
        preferredDays: ["wednesday", "saturday"],
        preferredTimeRanges: ["evening"],
        searchType: .hot,
        hotWindow: .today,
        hotStartTime: "19:00",
        durationMinutes: Sport.tennis.defaultDurationMinutes,
        hasCourtBooked: false,
        sport: .tennis,
        selfLevel: nil,
        selfLevelUnknown: true,
        desiredLevelMin: 4,
        desiredLevelMax: 6,
        format: Sport.tennis.defaultFormat,
        playersNeeded: Sport.tennis.defaultPlayersNeeded(format: Sport.tennis.defaultFormat),
        comment: ""
    )
    @State private var availabilityByDay: [String: [String]] = [
        "wednesday": ["evening"],
        "saturday": ["evening"]
    ]
    @State private var isClubPickerPresented = false
    @State private var isAdvancedPresented = false
    @State private var isRunningRoutePickerPresented = false
    @State private var isSavingSearch = false
    @State private var isRocketLaunchPresented = false
    @State private var submitButtonPressed = false
    @State private var hotStep: HotSearchStep = .when
    @State private var didInitializeComposer = false
    @State private var selectedSport: Sport = .tennis
    @State private var selectedCourtId: String?
    @State private var selectedCourtSnapshot: Court?
    @State private var customHotDate: Date?
    @State private var isCustomHotCalendarExpanded = false
    @StateObject private var bookingCallFlow = BookingCallFlow()
    @FocusState private var isSearchCommentFocused: Bool

    let initialSearch: GameSearch?
    let initialCourt: Court?
    let initialSport: Sport?
    let onCreate: (GameSearch) -> Void

    init(
        initialSearch: GameSearch? = nil,
        initialCourt: Court? = nil,
        initialSport: Sport? = nil,
        initialHotWindow: HotWindow? = nil,
        initialHotStartTime: String? = nil,
        onCreate: @escaping (GameSearch) -> Void
    ) {
        self.initialSearch = initialSearch
        self.initialCourt = initialCourt
        self.initialSport = initialSport
        self.onCreate = onCreate

        let requestedSport = initialSearch?.sport ?? initialSport ?? initialCourt?.primarySport ?? .tennis
        let initialCourtSports = initialCourt?.supportedSports?.isEmpty == false ? initialCourt?.supportedSports ?? [] : []
        let resolvedSport = initialCourtSports.isEmpty || initialCourtSports.contains(requestedSport)
            ? requestedSport
            : initialCourtSports[0]
        let resolvedFormat = resolvedSport.defaultFormat
        var initialDraft = SearchDraft(
            inviteSlug: nil,
            preferredCourtId: initialCourt?.id,
            preferredDistricts: initialCourt?.district.map { [$0] } ?? [],
            preferredDays: ["wednesday", "saturday"],
            preferredTimeRanges: ["evening"],
            searchType: .hot,
            hotWindow: .today,
            hotStartTime: "19:00",
            durationMinutes: resolvedSport.defaultDurationMinutes,
            hasCourtBooked: false,
            sport: resolvedSport,
            selfLevel: nil,
            selfLevelUnknown: true,
            desiredLevelMin: 4,
            desiredLevelMax: 6,
            format: resolvedFormat,
            playersNeeded: resolvedSport.defaultPlayersNeeded(format: resolvedFormat),
            comment: ""
        )

        if let initialHotWindow {
            initialDraft.hotWindow = initialHotWindow
        }

        if let initialHotStartTime {
            initialDraft.hotStartTime = initialHotStartTime
        }

        if let initialSearch {
            initialDraft.preferredCourtId = initialSearch.preferredCourt?.id
            initialDraft.preferredDistricts = initialSearch.preferredDistricts
            initialDraft.preferredDays = initialSearch.preferredDays
            initialDraft.preferredTimeRanges = initialSearch.preferredTimeRanges
            initialDraft.searchType = .hot
            initialDraft.hotWindow = initialSearch.hotWindow
            initialDraft.hotStartTime = initialSearch.hotStartsAt?.parsedISODateValue()?.formattedHourMinute()
            initialDraft.hotStartsAt = initialSearch.hotStartsAt
            initialDraft.durationMinutes = initialSearch.durationMinutes
            initialDraft.hasCourtBooked = initialSearch.hasCourtBooked
            initialDraft.selfLevel = initialSearch.selfLevel
            initialDraft.selfLevelUnknown = initialSearch.selfLevelUnknown ?? false
            initialDraft.desiredLevelMin = initialSearch.desiredLevelMin ?? 1
            initialDraft.desiredLevelMax = initialSearch.desiredLevelMax ?? 10
            initialDraft.format = initialSearch.format
            initialDraft.playersNeeded = initialSearch.playersNeeded
            initialDraft.comment = initialSearch.comment ?? ""
        }

        _draft = State(initialValue: initialDraft)
        _selectedSport = State(initialValue: resolvedSport)
        _selectedCourtId = State(initialValue: initialSearch?.preferredCourt?.id ?? initialCourt?.id)
        _selectedCourtSnapshot = State(initialValue: initialSearch?.preferredCourt ?? initialCourt)
        _customHotDate = State(initialValue: initialDraft.hotWindow == nil ? initialSearch?.hotStartsAt?.parsedISODateValue() : nil)
        _isCustomHotCalendarExpanded = State(initialValue: initialDraft.hotWindow == nil && initialSearch?.hotStartsAt != nil)
    }

    private var availableSports: [Sport] {
        let preferred = appModel.currentUser?.preferredSports ?? []
        let fallback = Sport.defaultAuthSports + Sport.allCases
        var ordered = preferred + fallback
        if let selectedCourtSports {
            ordered = ordered.filter { selectedCourtSports.contains($0) } + selectedCourtSports
        }
        var seen = Set<String>()
        ordered.removeAll { sport in
            let inserted = seen.insert(sport.rawValue).inserted
            return !inserted
        }
        return ordered
    }

    private var selectedCourtSports: [Sport]? {
        guard let sports = selectedCourt?.supportedSports, !sports.isEmpty else {
            return nil
        }
        return sports
    }

    private var profileSportLevel: Int? {
        appModel.currentUser?.sportLevels[selectedSport.rawValue] ?? appModel.currentUser?.tennisLevel
    }

    private var currentSportLevel: Int? {
        draft.selfLevel ?? profileSportLevel
    }

    private var editableSportLevel: Int {
        currentSportLevel ?? 5
    }

    private var sportCourts: [Court] {
        courts.filter { court in
            guard let supportedSports = court.supportedSports, !supportedSports.isEmpty else {
                return true
            }
            return supportedSports.contains(selectedSport)
        }
    }

    private var availableDistricts: [String] {
        sportCourts
            .compactMap(\.district)
            .reduce(into: [String]()) { result, district in
                if !result.contains(district) {
                    result.append(district)
                }
            }
            .sorted { prettifyDistrict($0) < prettifyDistrict($1) }
    }

    private var filteredCourts: [Court] {
        let trimmedQuery = courtQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let districtFiltered = sportCourts.filter { court in
            draft.preferredDistricts.isEmpty || (court.district != nil && draft.preferredDistricts.contains(court.district!))
        }

        let sorted = districtFiltered.sorted { left, right in
            if left.id == selectedCourtId { return true }
            if right.id == selectedCourtId { return false }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        guard !trimmedQuery.isEmpty else {
            return sorted
        }

        return sorted.filter { searchableCourtText(for: $0).contains(trimmedQuery) }
    }

    private var selectedDayValues: [String] {
        orderedDays(from: availabilityByDay)
    }

    private var selectedTimeRangeValues: [String] {
        Array(Set(availabilityByDay.values.flatMap { $0 })).sorted { lhs, rhs in
            timeRangeIndex(lhs) < timeRangeIndex(rhs)
        }
    }

    private var selectedCourt: Court? {
        if let selectedCourtSnapshot,
           selectedCourtSnapshot.id == selectedCourtId {
            return selectedCourtSnapshot
        }
        return courts.first(where: { $0.id == selectedCourtId })
    }

    private var previewDistrictAreas: [DistrictMapArea] {
        let ids = draft.preferredDistricts.isEmpty
            ? selectedCourt?.district.map { [$0] } ?? []
            : draft.preferredDistricts

        return ids
            .reduce(into: [DistrictMapArea]()) { result, district in
                guard let area = districtAreasByID[district.lowercased()],
                      !result.contains(where: { $0.id == area.id }) else {
                    return
                }
                result.append(area)
            }
            .prefix(3)
            .map { $0 }
    }

    private var previewCourts: [Court] {
        var result: [Court] = []

        if let selectedCourt {
            result.append(selectedCourt)
        }

        let candidateCourts = sportCourts
            .filter { court in
                if let selectedCourt, court.id == selectedCourt.id {
                    return false
                }

                if draft.preferredDistricts.isEmpty {
                    return true
                }

                guard let district = court.district else {
                    return false
                }
                return draft.preferredDistricts.contains(district)
            }
            .sorted { left, right in
                left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }

        for court in candidateCourts {
            guard result.count < 18 else {
                break
            }
            result.append(court)
        }

        if result.isEmpty {
            result = Array(
                sportCourts
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    .prefix(18)
            )
        }

        return result
    }

    private var canSubmit: Bool {
        if draft.searchType == .hot {
            return !(draft.hotStartTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return !selectedDayValues.isEmpty && !selectedTimeRangeValues.isEmpty
    }

    private var isCustomHotDateSelected: Bool {
        draft.hotWindow == nil
    }

    private var resolvedHotDate: Date {
        if isCustomHotDateSelected, let customHotDate {
            return customHotDate
        }

        let offset: Int
        switch draft.hotWindow ?? .today {
        case .today:
            offset = 0
        case .tomorrow:
            offset = 1
        case .dayAfterTomorrow:
            offset = 2
        }

        return Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private var defaultCustomHotDate: Date {
        let fallbackDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date().addingTimeInterval(3 * 24 * 60 * 60)
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: fallbackDate) ?? fallbackDate
    }

    private var customHotDateBinding: Binding<Date> {
        Binding(
            get: { customHotDate ?? defaultCustomHotDate },
            set: { date in
                selectCustomHotDate(date)
            }
        )
    }

    private var hotDateTitle: String {
        if Calendar.current.isDateInToday(resolvedHotDate) {
            return L10n.string("Today", "Сегодня")
        }
        if Calendar.current.isDateInTomorrow(resolvedHotDate) {
            return L10n.string("Tomorrow", "Завтра")
        }
        if let dayAfterTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Date()),
           Calendar.current.isDate(resolvedHotDate, inSameDayAs: dayAfterTomorrow) {
            return L10n.string("Day after tomorrow", "Послезавтра")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: resolvedHotDate)
    }

    private var hotStepIndex: Int {
        HotSearchStep.allCases.firstIndex(of: hotStep) ?? 0
    }

    private var canAdvanceHotStep: Bool {
        switch hotStep {
        case .when:
            return canSubmit
        case .location, .who, .confirm:
            return true
        }
    }

    private var sportLevelSummary: (title: String, subtitle: String) {
        let level = editableSportLevel
        switch level {
        case 1 ... 2:
            return (L10n.string("Beginner", "Начальный"), L10n.string("Looking for level \(draft.desiredLevelMin)-\(draft.desiredLevelMax) players", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)"))
        case 3 ... 4:
            return (L10n.string("Basic", "Базовый"), L10n.string("Looking for level \(draft.desiredLevelMin)-\(draft.desiredLevelMax) players", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)"))
        case 5 ... 6:
            return (L10n.string("Intermediate", "Средний"), L10n.string("Looking for level \(draft.desiredLevelMin)-\(draft.desiredLevelMax) players", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)"))
        case 7 ... 8:
            return (L10n.string("Advanced", "Продвинутый"), L10n.string("Looking for level \(draft.desiredLevelMin)-\(draft.desiredLevelMax) players", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)"))
        default:
            return (L10n.string("Expert", "Сильный"), L10n.string("Looking for level \(draft.desiredLevelMin)-\(draft.desiredLevelMax) players", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)"))
        }
    }

    private var locationTitle: String {
        if selectedSport.isRouteSport {
            if let route = draft.runningRoute?.trimmingCharacters(in: .whitespacesAndNewlines),
               !route.isEmpty {
                return route
            }
            if draft.runningRoutePoints?.isEmpty == false {
                return selectedSport.routeDefaultTitle
            }
            return L10n.string("No route", "Без маршрута")
        }

        return selectedCourt?.name
            ?? draft.customVenueAddress
            ?? draft.customVenueTitle
            ?? (draft.preferredDistricts.isEmpty ? L10n.string("No preference", "Без привязки") : districtsSummary)
    }

    private var locationSubtitle: String {
        if let selectedCourt {
            return [selectedCourt.metroDisplayName, localizedDistrictName(selectedCourt.district), selectedCourt.address]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        if selectedSport.isRouteSport {
            if let points = draft.runningRoutePoints, points.count >= 2 {
                return L10n.string("Route on map · \(points.count) points", "Маршрут на карте · \(points.count) точек")
            }
            return L10n.string("Mark the start, finish, and key points", "Нарисуйте старт, финиш и ключевые точки")
        }

        if let address = draft.customVenueAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty {
            return address
        }

        return draft.preferredDistricts.isEmpty ? L10n.string("We’ll show nearby clubs", "Покажем клубы рядом") : L10n.string("We’ll search in selected districts", "Будем искать в выбранных районах")
    }

    private var districtsSummary: String {
        let names = draft.preferredDistricts.compactMap(localizedDistrictName)
        return names.isEmpty ? L10n.string("We’ll show nearby clubs", "Будем показывать клубы поблизости") : names.prefix(3).joined(separator: ", ")
    }

    private var shouldApplyPreferredSportOnFirstLoad: Bool {
        selectedSport == .tennis
            && selectedCourtId == nil
            && draft.preferredDistricts.isEmpty
            && draft.searchType == .hot
            && draft.format == Sport.tennis.defaultFormat
            && draft.playersNeeded == Sport.tennis.defaultPlayersNeeded(format: Sport.tennis.defaultFormat)
            && (draft.durationMinutes ?? Sport.tennis.defaultDurationMinutes) == Sport.tennis.defaultDurationMinutes
            && draft.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        composerHeader
                        urgentSearchProgressHeader
                        hotStepContent
                        hotStepActions
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }

                if isRocketLaunchPresented {
                    SuccessCelebrationOverlay(
                        title: L10n.string("Urgent search published", "Срочный поиск опубликован"),
                        subtitle: L10n.string("Players will see it in the feed", "Игроки увидят его в ленте"),
                        icon: "🚀"
                    )
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isClubPickerPresented) {
                SearchClubPickerSheet(
                    sport: selectedSport,
                    courts: sportCourts,
                    selectedCourtId: selectedCourtId,
                    selectsImmediately: false,
                    onSelect: { court in
                        selectPreferredCourt(
                            court,
                            clearDistrictsWhenNil: true
                        )
                    },
                    onSelectCustomAddress: { address in
                        selectCustomVenueAddress(address)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $isRunningRoutePickerPresented) {
                RunningRoutePickerSheet(
                    sport: selectedSport,
                    points: Binding(
                        get: { draft.runningRoutePoints ?? [] },
                        set: { draft.runningRoutePoints = $0 }
                    ),
                    routeTitle: Binding(
                        get: { draft.runningRoute ?? "" },
                        set: { draft.runningRoute = $0 }
                    )
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $isAdvancedPresented) {
                SearchComposerAdvancedSheet(
                    draft: $draft,
                    sport: selectedSport,
                    availableDistricts: availableDistricts,
                    availabilityByDay: $availabilityByDay
                )
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                L10n.string("Were you able to book?", "Удалось забронировать?"),
                isPresented: $bookingCallFlow.isResultPresented,
                titleVisibility: .visible
            ) {
                Button(L10n.string("Yes, at the selected time", "Да, время совпало")) {
                    draft.hasCourtBooked = true
                }
                Button(L10n.string("Booked for another time", "Забронировал на другое время")) {
                    draft.hasCourtBooked = true
                    hotStep = .when
                }
                Button(L10n.string("Didn’t book", "Не забронировал")) {
                    draft.hasCourtBooked = false
                }
                Button(L10n.string("Cancel", "Отмена"), role: .cancel) {}
            } message: {
                Text(L10n.string("Confirm the booking or change the search date and time.", "Подтвердите бронь или измените дату и время поиска."))
            }
            .task {
                guard !didInitializeComposer else {
                    return
                }
                didInitializeComposer = true

                do {
                    if initialSearch == nil, draft.inviteSlug == nil {
                        draft.inviteSlug = UUID().uuidString.lowercased()
                    }
                    draft.searchType = .hot
                    courts = try await appModel.repository.fetchCourts()
                    if let initialSearch {
                        apply(initialSearch)
                    } else if let initialCourt {
                        selectedCourtSnapshot = courts.first(where: { $0.id == initialCourt.id }) ?? initialCourt
                        selectedCourtId = initialCourt.id
                        draft.preferredCourtId = initialCourt.id
                        if let district = initialCourt.district {
                            draft.preferredDistricts = [district] + draft.preferredDistricts.filter { $0 != district }
                        }
                    }
                    reconcileSelectedSportWithAvailableSports()
                } catch {
                    appModel.present(error: error)
                }
            }
        }
        .onChange(of: draft.format) { nextFormat in
            let resolvedFormat = selectedSport.resolveFormat(nextFormat)
            if resolvedFormat != draft.format {
                draft.format = resolvedFormat
                return
            }
            draft.playersNeeded = selectedSport.defaultPlayersNeeded(format: resolvedFormat)
        }
        .onChange(of: draft.searchType) { _ in
            draft.searchType = .hot
            hotStep = .when
            if (draft.hotStartTime ?? "").isEmpty {
                draft.hotStartTime = hotQuickTimes.first ?? "09:00"
            }
        }
        .onChange(of: draft.hotWindow) { _ in
            syncHotStartTimeWithAvailableTimes()
        }
        .onChange(of: scenePhase) { phase in
            bookingCallFlow.handle(scenePhase: phase)
        }
        .onDisappear {
            bookingCallFlow.reset()
        }
    }

    private var composerHeader: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.04), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(initialSearch == nil ? L10n.string("Find partners", "Найти партнёров") : L10n.string("Edit search", "Изменить поиск"))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    private var inviteBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.88))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.2")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Faster with friends", "Быстрее с друзьями"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("Invite friends and play more often", "Пригласите друзей и собирайте игры чаще"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.64))
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            if let inviteURL = resolvedInviteURL {
                ShareLink(item: inviteURL) {
                    Text(L10n.string("Invite", "Пригласить"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(AppTheme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        AppHaptics.selection()
                    }
                )
            } else {
                Text(L10n.string("Invite", "Пригласить"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(AppTheme.ink.opacity(0.55), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.76),
                    Color(red: 0.89, green: 0.97, blue: 0.93),
                    Color(red: 0.98, green: 0.97, blue: 0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var searchTypeModeSwitch: some View {
        HStack(spacing: 8) {
            searchTypeButton(type: .regular, systemImage: "calendar", title: L10n.string("Recurring", "Регулярный"))
            searchTypeButton(type: .hot, systemImage: "rocket", title: L10n.string("Urgent", "Срочный"))
        }
        .padding(5)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func searchTypeButton(type: SearchType, systemImage: String, title: String) -> some View {
        let selected = draft.searchType == type

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                draft.searchType = type
            }
        } label: {
            Group {
                if systemImage == "rocket" {
                    HStack(spacing: 8) {
                        Text("🚀")
                        Text(title)
                    }
                } else {
                    Label(title, systemImage: systemImage)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(selected ? .white : AppTheme.ink.opacity(0.74))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(selected ? AppTheme.court : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var urgentSearchProgressHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("🚀")
                    .font(.system(size: 22))
                Text(L10n.string("Urgent search", "Срочный поиск"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(hotStep.badgeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(AppTheme.mint, in: Capsule())
            }

            HStack(spacing: 8) {
                ForEach(0 ..< 4, id: \.self) { index in
                    Capsule()
                        .fill(index <= hotStepIndex ? AppTheme.court : Color.black.opacity(0.08))
                        .frame(height: 4)
                }
            }
        }
        .padding(16)
        .background(AppTheme.mint.opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var hotStepContent: some View {
        switch hotStep {
        case .when:
            hotSettingsSection
        case .who:
            VStack(spacing: 24) {
                sportRailSection
                compactStatsSection
                commentSection
            }
        case .location:
            hotLocationSection
        case .confirm:
            urgentConfirmationSection
        }
    }

    private var hotStepActions: some View {
        HStack(spacing: 12) {
            if hotStep != .when {
                Button(L10n.string("Back", "Назад")) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        hotStep = HotSearchStep(rawValue: hotStep.rawValue - 1) ?? .when
                    }
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
            }

            Button {
                triggerSubmitFeedback()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    if hotStep == .confirm {
                        Task { await saveSearch() }
                    } else {
                        hotStep = HotSearchStep(rawValue: hotStep.rawValue + 1) ?? .confirm
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if hotStep == .confirm {
                        Text("🚀")
                    }
                    Text(hotStep == .confirm ? L10n.string("Publish urgent search", "Опубликовать срочно") : L10n.string("Continue", "Продолжить"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .scaleEffect(submitButtonPressed ? 0.97 : 1)
            .disabled(!canAdvanceHotStep || isSavingSearch)
        }
    }

    private var sportRailSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("What are you looking for?", "Что ищем?"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(L10n.string("Choose a sport", "Выбрать вид спорта"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.court)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableSports, id: \.rawValue) { sport in
                        let isSelected = selectedSport == sport
                        Button {
                            applySportSelection(sport)
                        } label: {
                            VStack(spacing: 10) {
                                SportIconView(
                                    sport: sport,
                                    color: isSelected ? AppTheme.court : AppTheme.ink.opacity(0.92),
                                    size: 30
                                )
                                    .frame(width: 52, height: 52)
                                    .background(isSelected ? AppTheme.mint : Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                                Text(sport.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 86)
                            }
                            .frame(width: 98, height: 118)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(isSelected ? AppTheme.court : Color.black.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                            )
                            .shadow(color: AppTheme.ink.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 16 : 10, x: 0, y: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Game format", "Формат игры"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 8) {
                ForEach(selectedSport.allowedFormats, id: \.rawValue) { format in
                    let isSelected = draft.format == format
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            draft.format = format
                        }
                    } label: {
                        Text(formatTitle(for: format))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : AppTheme.ink.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(isSelected ? AppTheme.court : Color.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var compactStatsSection: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("Players needed", "Нужно игроков"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                HStack(spacing: 4) {
                    counterButton(systemImage: "minus", isDisabled: draft.playersNeeded <= 1) {
                        decrementPlayersNeeded()
                    }

                    Text("\(draft.playersNeeded)")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 38, maxWidth: .infinity)

                    counterButton(systemImage: "plus", isDisabled: draft.playersNeeded >= selectedSport.maxPlayersNeeded) {
                        incrementPlayersNeeded()
                    }
                }
                .frame(height: 54)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: -8) {
                    if let currentUser = appModel.currentUser {
                        RemoteAvatarView(name: currentUser.displayName, path: currentUser.avatarUrl, size: 28)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    } else {
                        Circle()
                            .fill(AppTheme.clay.opacity(0.9))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }

                    ForEach(0 ..< min(draft.playersNeeded, 2), id: \.self) { index in
                        Circle()
                            .fill(AppTheme.ink.opacity(0.18 + Double(index) * 0.08))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    Text(L10n.string("You + \(openSeatsLabel)", "Вы + \(openSeatsLabel)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.court)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.leading, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))

            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("Level", "Уровень"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                Text(sportLevelSummary.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)

                HStack(spacing: 8) {
                    levelButton(systemImage: "minus", isDisabled: editableSportLevel <= 1) {
                        adjustSportLevel(by: -1)
                    }

                    Text("\(editableSportLevel)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)

                    levelButton(systemImage: "plus", isDisabled: editableSportLevel >= 10) {
                        adjustSportLevel(by: 1)
                    }
                }
                .frame(height: 42)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 6) {
                    ForEach(1 ... 5, id: \.self) { index in
                        Capsule()
                            .fill(index <= Int(ceil(Double(editableSportLevel) / 2.0)) ? AppTheme.court : Color.black.opacity(0.08))
                            .frame(height: 8)
                    }
                }

                Text(sportLevelSummary.subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
        }
    }

    private var openSeatsLabel: String {
        L10n.string("\(draft.playersNeeded) open \(draft.playersNeeded == 1 ? "spot" : "spots")", "\(draft.playersNeeded) \(openSeatsWord(for: draft.playersNeeded)) открыто")
    }

    private func openSeatsWord(for count: Int) -> String {
        let lastTwoDigits = count % 100
        if (11 ... 14).contains(lastTwoDigits) {
            return "мест"
        }

        switch count % 10 {
        case 1:
            return "место"
        case 2 ... 4:
            return "места"
        default:
            return "мест"
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("When do you want to play?", "Когда играть?"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 10) {
                ForEach(TimeRange.allCases) { range in
                    let selected = selectedTimeRangeValues.contains(range.rawValue)
                    Button {
                        toggleTimeRange(range)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: timeRangeIcon(for: range))
                                .font(.system(size: 16, weight: .semibold))
                            Text(range.title)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(selected ? timeRangeColor(for: range) : AppTheme.ink.opacity(0.72))
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .background(selected ? timeRangeBackground(for: range) : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(selected ? timeRangeColor(for: range).opacity(0.24) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                ForEach(DayOfWeek.allCases) { day in
                    let selected = selectedDayValues.contains(day.rawValue)
                    Button {
                        toggleDay(day)
                    } label: {
                        Text(day.shortTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selected ? .white : AppTheme.ink.opacity(0.78))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(selected ? AppTheme.court : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hotSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("When would you like to play?", "Когда хотите сыграть?"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("Choose a day and a convenient time", "Выберите день и удобное время"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }

            VStack(spacing: 10) {
                ForEach(HotWindow.allCases) { window in
                    hotWindowButton(window)
                }
                customHotDateButton

                if isCustomHotDateSelected && isCustomHotCalendarExpanded {
                    HotDateCalendarCard(
                        selection: customHotDateBinding,
                        minimumDate: Date(),
                        tint: AppTheme.court
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Text(L10n.string("What time?", "Во сколько?"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(hotQuickTimes, id: \.self) { time in
                            hotQuickTimeButton(time)
                                .id(time)
                        }
                    }
                }
                .onAppear {
                    scrollToSelectedHotTime(proxy)
                }
                .onChange(of: draft.hotStartTime ?? "") { _ in
                    scrollToSelectedHotTime(proxy)
                }
                .onChange(of: hotQuickTimes) { _ in
                    scrollToSelectedHotTime(proxy)
                }
            }

            FieldShell(title: L10n.string("Duration", "Длительность")) {
                Stepper(value: Binding(
                    get: { draft.durationMinutes ?? selectedSport.defaultDurationMinutes },
                    set: { draft.durationMinutes = $0 }
                ), in: 30 ... 180, step: 30) {
                    Text(L10n.string("\(draft.durationMinutes ?? selectedSport.defaultDurationMinutes) min", "\(draft.durationMinutes ?? selectedSport.defaultDurationMinutes) мин"))
                        .font(.headline)
                }
            }
        }
    }

    private var hotLocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedSport.isRouteSport ? L10n.string("Where is the route?", "Где маршрут?") : L10n.string("Where are we playing?", "Где играем?"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(selectedSport.isRouteSport ? L10n.string("Mark the route on the map. Clubs and districts aren’t needed here.", "Отметьте маршрут на карте. Клубы и районы здесь не нужны.") : L10n.string("Choose a district or a club if it’s already booked", "Выберите район или клуб, если он уже забронирован"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }

            if selectedSport.isRouteSport {
                runningRouteSection
            } else {
                courtToggle
                mapPreviewSection
                if let phoneURL = selectedCourt?.phoneURL {
                    Button {
                        bookingCallFlow.start(url: phoneURL, openURL: openURL)
                    } label: {
                        Label(L10n.string("Call and book", "Позвонить и забронировать"), systemImage: "phone.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(AppTheme.court, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                hotDistrictRail
            }
        }
    }

    private var runningRouteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedSport.routeDefaultTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(runningRouteSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.56))
                }

                Spacer()

                Button {
                    isRunningRoutePickerPresented = true
                    AppHaptics.selection()
                } label: {
                    Label(draft.runningRoutePoints?.isEmpty == false ? L10n.string("Edit", "Изменить") : L10n.string("Draw", "Нарисовать"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(AppTheme.court, in: Capsule())
            }

            if let points = draft.runningRoutePoints, points.count >= 2 {
                RunningRoutePreviewMapView(points: points, followsRoads: selectedSport.routeFollowsRoads)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            } else {
                Button {
                    isRunningRoutePickerPresented = true
                    AppHaptics.selection()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "map")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.court)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.mint, in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string("Mark route points on the map", "Отметьте точки маршрута на карте"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                            Text(L10n.string("Players will see the route on the search card.", "Маршрут будет виден игрокам в карточке поиска."))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.ink.opacity(0.56))
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.ink.opacity(0.32))
                    }
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.07), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var runningRouteSummary: String {
        let pointsCount = draft.runningRoutePoints?.count ?? 0
        if pointsCount >= 2 {
            return L10n.string("\(pointsCount) points · \(draft.runningRoute?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? draft.runningRoute! : "Route on map")", "\(pointsCount) точек · \(draft.runningRoute?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? draft.runningRoute! : "Маршрут на карте")")
        }
        return L10n.string("Mark the start, finish, and key points", "Нарисуйте старт, финиш и ключевые точки")
    }

    @ViewBuilder
    private var hotDistrictRail: some View {
        if !availableDistricts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("Districts", "Районы"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        districtChip(title: L10n.string("Any", "Любой"), district: nil)
                        ForEach(availableDistricts.prefix(10), id: \.self) { district in
                            districtChip(title: prettifyDistrict(district), district: district)
                        }
                    }
                }
            }
        }
    }

    private var hotQuickTimes: [String] {
        let startMinutes: Int

        if Calendar.current.isDateInToday(resolvedHotDate) {
            startMinutes = roundedUpMinutesFromNow()
        } else {
            startMinutes = 0
        }

        let clampedStart = min(max(startMinutes, 0), 23 * 60 + 30)
        let allMinutes = stride(from: clampedStart, through: 23 * 60 + 30, by: 30)

        let times = allMinutes.map(Self.timeLabel(minutes:))
        return times.isEmpty ? [Self.timeLabel(minutes: clampedStart)] : times
    }

    private func hotWindowButton(_ window: HotWindow) -> some View {
        let selected = draft.hotWindow == window

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                draft.hotWindow = window
                draft.hotStartsAt = nil
                draft.hotStartTime = preferredHotStartTime(for: hotDate(for: window))
                isCustomHotCalendarExpanded = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: hotWindowIcon(for: window))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? AppTheme.court : AppTheme.ink.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(selected ? AppTheme.mint : Color.black.opacity(0.04), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(window.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? AppTheme.court : AppTheme.ink)
                    Text(hotWindowSubtitle(for: window))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.48))
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.court)
                }
            }
            .padding(14)
            .background(selected ? AppTheme.mint.opacity(0.55) : Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? AppTheme.court.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var customHotDateButton: some View {
        let selected = isCustomHotDateSelected

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                selectCustomHotDate(customHotDate ?? defaultCustomHotDate)
                isCustomHotCalendarExpanded.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? AppTheme.court : AppTheme.ink.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(selected ? AppTheme.mint : Color.black.opacity(0.04), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("Another date", "Другая дата"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? AppTheme.court : AppTheme.ink)
                    Text(selected ? hotDateTitle : L10n.string("Choose in calendar", "Выбрать в календаре"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.48))
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.court)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.42))
                }
            }
            .padding(14)
            .background(selected ? AppTheme.mint.opacity(0.55) : Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? AppTheme.court.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func hotQuickTimeButton(_ time: String) -> some View {
        let selected = (draft.hotStartTime ?? "19:00") == time

        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                draft.hotStartTime = time
            }
        } label: {
            Text(time)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? .white : AppTheme.ink.opacity(0.82))
                .frame(width: 84, height: 50)
                .background(selected ? AppTheme.court : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? AppTheme.court : Color.black.opacity(0.07), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func selectCustomHotDate(_ date: Date) {
        customHotDate = date
        draft.hotWindow = nil
        draft.hotStartsAt = nil
        draft.hotStartTime = preferredHotStartTime(for: date)
        syncHotStartTimeWithAvailableTimes()
    }

    private func syncHotStartTimeWithAvailableTimes() {
        let availableTimes = hotQuickTimes
        guard !availableTimes.isEmpty else {
            draft.hotStartTime = nil
            return
        }

        if let selectedTime = draft.hotStartTime, availableTimes.contains(selectedTime) {
            return
        }
        let preferredTime = preferredHotStartTime(for: resolvedHotDate)
        draft.hotStartTime = availableTimes.contains(preferredTime) ? preferredTime : availableTimes.first
    }

    private func hotDate(for window: HotWindow) -> Date {
        let offset: Int
        switch window {
        case .today:
            offset = 0
        case .tomorrow:
            offset = 1
        case .dayAfterTomorrow:
            offset = 2
        }

        return Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func preferredHotStartTime(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeLabel(minutes: roundedUpMinutesFromNow())
        }

        return "09:00"
    }

    private func scrollToSelectedHotTime(_ proxy: ScrollViewProxy) {
        let selectedTime = draft.hotStartTime ?? preferredHotStartTime(for: resolvedHotDate)
        guard hotQuickTimes.contains(selectedTime) else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(selectedTime, anchor: .center)
            }
        }
    }

    private func combinedHotStartsAt() -> Date? {
        let time = draft.hotStartTime ?? "19:00"
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard let hour = parts.first else {
            return nil
        }

        return Calendar.current.date(
            bySettingHour: hour,
            minute: parts.dropFirst().first ?? 0,
            second: 0,
            of: resolvedHotDate
        )
    }

    private func hotStartsAtPayloadValue() -> String? {
        guard isCustomHotDateSelected, let startsAt = combinedHotStartsAt() else {
            return nil
        }

        return ISO8601DateFormatter().string(from: startsAt)
    }

    private func hotWindowIcon(for window: HotWindow) -> String {
        switch window {
        case .today:
            return "calendar.badge.clock"
        case .tomorrow:
            return "sun.max"
        case .dayAfterTomorrow:
            return "calendar"
        }
    }

    private func hotWindowSubtitle(for window: HotWindow) -> String {
        let offset: Int
        switch window {
        case .today:
            offset = 0
        case .tomorrow:
            offset = 1
        case .dayAfterTomorrow:
            offset = 2
        }

        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    private func roundedUpMinutesFromNow(referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: referenceDate)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let totalMinutes = hour * 60 + minute
        let rounded = Int(ceil(Double(totalMinutes) / 30.0)) * 30
        return min(rounded, 23 * 60 + 30)
    }

    private static func timeLabel(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private var mapPreviewSection: some View {
        ZStack(alignment: .bottom) {
            SearchLocationPreviewMapView(
                courts: previewCourts,
                highlightedDistricts: previewDistrictAreas,
                selectedCourtId: selectedCourtId,
                onSelectCourt: { court in
                    AppHaptics.selection()
                    selectPreferredCourt(court)
                }
            )
            .frame(height: 232)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.90, green: 0.98, blue: 0.75))
                        .frame(width: 42, height: 42)
                    Image(systemName: "tennisball.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.court)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCourt?.name ?? L10n.string("Clubs and districts", "Клубы и районы"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(districtsSummary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    AppHaptics.selection()
                    isClubPickerPresented = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var commentSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.78))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Comment (optional)", "Комментарий (необязательно)"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
                TextField(L10n.string("For example: I’d like to play after 7 PM", "Например: хочу сыграть после 19:00"), text: $draft.comment, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
                    .focused($isSearchCommentFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isSearchCommentFocused = false
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(L10n.string("Done", "Готово")) {
                                isSearchCommentFocused = false
                            }
                        }
                    }
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var urgentConfirmationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("Review and publish", "Проверьте и опубликуйте"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            inviteBanner

            VStack(spacing: 0) {
                urgentConfirmationRow(icon: "calendar", title: L10n.string("When", "Когда"), value: "\(hotDateTitle), \(draft.hotStartTime ?? "19:00")")
                Divider()
                urgentConfirmationRow(icon: "tennis.racket", title: L10n.string("Sport", "Вид спорта"), value: selectedSport.title)
                Divider()
                urgentConfirmationRow(icon: "person.badge.plus", title: L10n.string("Players needed", "Нужно игроков"), value: L10n.string("You + \(openSeatsLabel)", "Вы + \(openSeatsLabel)"))
                Divider()
                urgentConfirmationRow(icon: "chart.bar", title: L10n.string("Level", "Уровень"), value: "\(draft.desiredLevelMin)-\(draft.desiredLevelMax)")
                Divider()
                urgentConfirmationRow(icon: "mappin.and.ellipse", title: L10n.string("Location", "Место"), value: locationTitle)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func urgentConfirmationRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.ink.opacity(0.58))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    private var submitSection: some View {
        VStack(spacing: 10) {
            Button {
                triggerSubmitFeedback()
                Task {
                    await saveSearch()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSavingSearch {
                        ProgressView()
                            .tint(.white)
                    } else if draft.searchType == .hot {
                        Image(systemName: "bolt.fill")
                    }
                    Text(submitButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .scaleEffect(submitButtonPressed ? 0.97 : 1)
            .disabled(!canSubmit || isSavingSearch)

            Text(draft.searchType == .hot ? L10n.string("The search will stay active until the game starts", "Поиск будет активен до начала игры") : L10n.string("Partners will be notified about your request", "Партнёрам придёт уведомление о вашем запросе"))
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.38))
                .frame(maxWidth: .infinity)
        }
    }

    private var submitButtonTitle: String {
        if initialSearch != nil {
            return L10n.string("Save search", "Сохранить поиск")
        }
        return draft.searchType == .hot ? L10n.string("Publish urgent search", "Опубликовать срочно") : L10n.string("Create search", "Создать поиск")
    }

    private func decrementPlayersNeeded() {
        guard draft.playersNeeded > 1 else {
            return
        }
        AppHaptics.selection()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            draft.playersNeeded -= 1
        }
    }

    private func incrementPlayersNeeded() {
        guard draft.playersNeeded < selectedSport.maxPlayersNeeded else {
            return
        }
        AppHaptics.selection()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            draft.playersNeeded += 1
        }
    }

    private func applySportSelection(_ sport: Sport, haptic: Bool = true) {
        guard selectedSport != sport else {
            return
        }

        if haptic {
            AppHaptics.selection()
        }
        let nextFormat = sport.resolveFormat(draft.format)
        let validDistricts = Set(
            courts
                .filter { courtSupports($0, sport: sport) }
                .compactMap(\.district)
        )

        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            selectedSport = sport
            draft.sport = sport
            draft.format = nextFormat
            draft.playersNeeded = sport.defaultPlayersNeeded(format: nextFormat)
            draft.durationMinutes = sport.defaultDurationMinutes

            if let selectedCourt = selectedCourt, !courtSupports(selectedCourt, sport: sport) {
                selectedCourtId = nil
                draft.preferredCourtId = nil
                selectedCourtSnapshot = nil
                draft.hasCourtBooked = false
            }

            if !sport.isRouteSport {
                draft.runningRoute = nil
                draft.runningRoutePoints = nil
            } else {
                selectedCourtId = nil
                draft.preferredCourtId = nil
                selectedCourtSnapshot = nil
                draft.customVenueTitle = nil
                draft.customVenueAddress = nil
                draft.hasCourtBooked = false
            }

            draft.preferredDistricts = sport.isRouteSport
                ? []
                : draft.preferredDistricts.filter { validDistricts.contains($0) }
        }

        setSportLevel(appModel.currentUser?.sportLevels[sport.rawValue] ?? appModel.currentUser?.tennisLevel ?? 5, haptic: false)
    }

    private func reconcileSelectedSportWithAvailableSports() {
        guard !availableSports.contains(selectedSport), let firstSport = availableSports.first else {
            return
        }
        applySportSelection(firstSport, haptic: false)
    }

    private func courtSupports(_ court: Court, sport: Sport) -> Bool {
        guard let supportedSports = court.supportedSports, !supportedSports.isEmpty else {
            return true
        }
        return supportedSports.contains(sport)
    }

    private func adjustSportLevel(by delta: Int) {
        setSportLevel(editableSportLevel + delta)
    }

    private func setSportLevel(_ level: Int, haptic: Bool = true) {
        let clampedLevel = min(max(level, 1), 10)
        if haptic {
            AppHaptics.selection()
        }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
            draft.selfLevel = clampedLevel
            draft.selfLevelUnknown = false
            draft.desiredLevelMin = max(clampedLevel - 1, 1)
            draft.desiredLevelMax = min(clampedLevel + 1, 10)
        }
    }

    private func counterButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isDisabled ? AppTheme.ink.opacity(0.24) : AppTheme.ink)
                .frame(width: 44, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func levelButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isDisabled ? AppTheme.ink.opacity(0.22) : AppTheme.ink)
                .frame(width: 34, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func selectPreferredCourt(
        _ court: Court?,
        clearDistrictsWhenNil: Bool = false
    ) {
        bookingCallFlow.reset()
        let currentSport = selectedSport
        let isChangingVenue = selectedCourtId != court?.id
            || (court == nil && (draft.customVenueTitle != nil || draft.customVenueAddress != nil))

        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            selectedCourtSnapshot = court
            selectedCourtId = court?.id
            draft.preferredCourtId = court?.id
            if let court {
                draft.customVenueTitle = nil
                draft.customVenueAddress = nil
                if let district = court.district {
                    draft.preferredDistricts = [district] + draft.preferredDistricts.filter { $0 != district }
                }
            } else if clearDistrictsWhenNil {
                draft.preferredDistricts.removeAll()
            }
            if isChangingVenue {
                draft.hasCourtBooked = false
            }
            draft.sport = currentSport
        }
    }

    private func selectCustomVenueAddress(_ address: String) {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        bookingCallFlow.reset()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            selectedCourtSnapshot = nil
            selectedCourtId = nil
            draft.preferredCourtId = nil
            draft.customVenueTitle = nil
            draft.customVenueAddress = normalized
            draft.hasCourtBooked = false
        }
    }

    private func formatTitle(for format: PlayFormat) -> String {
        switch format {
        case .singles:
            return L10n.string("Singles", "Одиночная")
        case .doubles:
            return L10n.string("Doubles", "Парная")
        case .both:
            return L10n.string("Any", "Любой")
        }
    }

    private func sportIconName(for sport: Sport) -> String {
        sport.appSystemIconName
    }

    private func timeRangeIcon(for range: TimeRange) -> String {
        switch range {
        case .morning:
            return "sunrise.fill"
        case .day:
            return "sun.max.fill"
        case .evening:
            return "moon.stars.fill"
        }
    }

    private func timeRangeColor(for range: TimeRange) -> Color {
        switch range {
        case .morning:
            return Color(red: 0.78, green: 0.42, blue: 0.09)
        case .day:
            return Color(red: 0.92, green: 0.68, blue: 0.04)
        case .evening:
            return Color(red: 0.27, green: 0.37, blue: 0.76)
        }
    }

    private func timeRangeBackground(for range: TimeRange) -> Color {
        switch range {
        case .morning:
            return Color(red: 0.99, green: 0.94, blue: 0.87)
        case .day:
            return Color(red: 1.0, green: 0.96, blue: 0.86)
        case .evening:
            return Color(red: 0.93, green: 0.94, blue: 1.0)
        }
    }

    private func toggleDay(_ day: DayOfWeek) {
        let currentRanges = selectedTimeRangeValues.isEmpty ? [TimeRange.evening.rawValue] : selectedTimeRangeValues
        if selectedDayValues.contains(day.rawValue) {
            availabilityByDay.removeValue(forKey: day.rawValue)
        } else {
            availabilityByDay[day.rawValue] = currentRanges
        }
    }

    private func toggleTimeRange(_ range: TimeRange) {
        var nextRanges = selectedTimeRangeValues
        if nextRanges.contains(range.rawValue) {
            nextRanges.removeAll { $0 == range.rawValue }
        } else {
            nextRanges.append(range.rawValue)
        }
        nextRanges.sort { lhs, rhs in
            timeRangeIndex(lhs) < timeRangeIndex(rhs)
        }

        let targetDays = selectedDayValues.isEmpty ? [DayOfWeek.monday.rawValue] : selectedDayValues
        for day in targetDays {
            availabilityByDay[day] = nextRanges
        }
    }

    private var courtToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSport.venueBookedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("Select this if you only need to agree on the roster and time.", "Отметь, если осталось только согласовать состав и время."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    draft.hasCourtBooked.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(draft.hasCourtBooked ? AppTheme.court : AppTheme.cream)
                    .frame(width: 54, height: 32)
                    .overlay(alignment: draft.hasCourtBooked ? .trailing : .leading) {
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

    private var resolvedInviteIdentifier: String {
        if let existing = initialSearch?.inviteSlug ?? initialSearch?.id {
            return existing
        }
        return draft.inviteSlug ?? UUID().uuidString.lowercased()
    }

    private var resolvedInviteURL: URL? {
        AppConfig.searchInviteURL(searchId: resolvedInviteIdentifier)
    }

    private func saveSearch() async {
        guard !isSavingSearch else {
            return
        }
        isSavingSearch = true
        defer { isSavingSearch = false }

        do {
            var payload = draft
            payload.searchType = .hot
            payload.sport = selectedSport
            payload.preferredCourtId = selectedCourtId
            payload.inviteSlug = payload.inviteSlug ?? resolvedInviteIdentifier
            if let selectedCourt = courts.first(where: { $0.id == payload.preferredCourtId }), let district = selectedCourt.district {
                payload.preferredDistricts = [district] + payload.preferredDistricts.filter { $0 != district }
            }
            if payload.preferredCourtId != nil {
                payload.customVenueTitle = nil
                payload.customVenueAddress = nil
            }
            if !payload.sport.isRouteSport {
                payload.runningRoute = nil
                payload.runningRoutePoints = nil
            } else {
                payload.preferredCourtId = nil
                payload.customVenueTitle = nil
                payload.customVenueAddress = nil
                payload.hasCourtBooked = false
                payload.preferredDistricts = []
                if payload.runningRoutePoints?.isEmpty == true {
                    payload.runningRoutePoints = nil
                }
            }
            payload.preferredDistricts = payload.preferredDistricts.reduce(into: [String]()) { result, district in
                if !result.contains(district) {
                    result.append(district)
                }
            }
            let sportLevel = currentSportLevel
            payload.selfLevel = sportLevel
            payload.selfLevelUnknown = sportLevel == nil
            payload.desiredLevelMin = max((sportLevel ?? 5) - 1, 1)
            payload.desiredLevelMax = min((sportLevel ?? 5) + 1, 10)

            if payload.searchType == .regular {
                payload.preferredDays = orderedDays(from: availabilityByDay)
                payload.preferredTimeRanges = Array(Set(availabilityByDay.values.flatMap { $0 })).sorted { lhs, rhs in
                    timeRangeIndex(lhs) < timeRangeIndex(rhs)
                }
                payload.hotWindow = nil
                payload.hotStartTime = nil
                payload.hotStartsAt = nil
                payload.durationMinutes = nil
            } else {
                payload.preferredDays = []
                payload.preferredTimeRanges = [timeRangeFromHotStartTime(payload.hotStartTime ?? "19:00")]
                payload.hotStartsAt = hotStartsAtPayloadValue()
                if payload.hotStartsAt != nil {
                    payload.hotWindow = nil
                }
            }

            let created: GameSearch
            if let initialSearch {
                created = try await appModel.repository.updateSearch(searchId: initialSearch.id, draft: payload)
            } else {
                created = try await appModel.repository.createSearch(payload)
            }
            let shouldCelebratePublish = initialSearch == nil && payload.searchType == .hot
            if shouldCelebratePublish {
                AppHaptics.successCelebration()
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRocketLaunchPresented = true
                }
                try? await Task.sleep(for: .milliseconds(1700))
            }
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
            onCreate(created)
            dismiss()
        } catch {
            appModel.present(error: error)
        }
    }

    private func triggerSubmitFeedback() {
        AppHaptics.selection()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.78)) {
            submitButtonPressed = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                submitButtonPressed = false
            }
        }
    }

    private func orderedDays(from availability: [String: [String]]) -> [String] {
        DayOfWeek.allCases.map(\.rawValue).filter { !(availability[$0] ?? []).isEmpty }
    }

    private func timeRangeIndex(_ value: String) -> Int {
        TimeRange.allCases.firstIndex(where: { $0.rawValue == value }) ?? 999
    }

    private func timeRangeFromHotStartTime(_ value: String) -> String {
        let parts = value.split(separator: ":")
        let hour = Int(parts.first ?? "19") ?? 19
        if hour < 12 {
            return TimeRange.morning.rawValue
        }
        if hour < 18 {
            return TimeRange.day.rawValue
        }
        return TimeRange.evening.rawValue
    }

    private func apply(_ search: GameSearch) {
        selectedSport = search.sport
        selectedCourtId = search.preferredCourt?.id
        draft = SearchDraft(
            inviteSlug: search.inviteSlug,
            preferredCourtId: search.preferredCourt?.id,
            preferredDistricts: search.preferredDistricts,
            preferredDays: search.preferredDays,
            preferredTimeRanges: search.preferredTimeRanges,
            searchType: search.searchType,
            hotWindow: search.hotWindow,
            hotStartTime: search.hotStartsAt?.parsedISODateValue()?.formattedHourMinute(),
            hotStartsAt: search.hotStartsAt,
            durationMinutes: search.durationMinutes,
            hasCourtBooked: search.hasCourtBooked,
            sport: search.sport,
            selfLevel: search.selfLevel,
            selfLevelUnknown: search.selfLevelUnknown ?? false,
            desiredLevelMin: search.desiredLevelMin ?? 1,
            desiredLevelMax: search.desiredLevelMax ?? 10,
            format: search.format,
            playersNeeded: search.playersNeeded,
            comment: search.comment ?? ""
        )
        draft.customVenueTitle = search.customVenueTitle
        draft.customVenueAddress = search.customVenueAddress
        draft.runningRoute = search.runningRoute
        draft.runningRoutePoints = search.runningRoutePoints
        selectedCourtSnapshot = search.preferredCourt
        customHotDate = search.hotWindow == nil ? search.hotStartsAt?.parsedISODateValue() : nil
        isCustomHotCalendarExpanded = customHotDate != nil
        availabilityByDay = Dictionary(uniqueKeysWithValues: search.preferredDays.map { ($0, search.preferredTimeRanges) })
    }

    private func searchableCourtText(for court: Court) -> String {
        [
            court.name,
            court.address,
            court.metroDisplayName,
            localizedDistrictName(court.district)
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func courtSubtitle(for court: Court) -> String {
        [
            court.metroDisplayName,
            localizedDistrictName(court.district),
            court.address
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " • ")
    }

    private func selectableCourtRow(
        title: String,
        subtitle: String,
        metaItems: [(icon: String, text: String)] = [],
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    if !metaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(metaItems.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 6) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppTheme.court)
                                    Text(item.text)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink.opacity(0.64))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink.opacity(0.64))
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.court)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                isSelected ? AppTheme.mint : AppTheme.creamLight,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppTheme.court.opacity(0.2) : Color.white.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func districtChip(title: String, district: String?) -> some View {
        let isSelected = district == nil ? draft.preferredDistricts.isEmpty : draft.preferredDistricts.contains(district!)

        return Button {
            if let district {
                if isSelected {
                    draft.preferredDistricts.removeAll { $0 == district }
                } else {
                    draft.preferredDistricts.append(district)
                }
            } else {
                draft.preferredDistricts.removeAll()
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                if isSelected && district != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isSelected ? .white : AppTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                isSelected ? AppTheme.court : AppTheme.creamLight,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func prettifyDistrict(_ value: String) -> String {
        localizedDistrictName(value) ?? value
    }
}

private struct SearchLocationPreviewMapView: UIViewRepresentable {
    let courts: [Court]
    let highlightedDistricts: [DistrictMapArea]
    let selectedCourtId: String?
    let onSelectCourt: (Court) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectCourt: onSelectCourt)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsTraffic = false
        mapView.showsScale = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            courts: courts,
            highlightedDistricts: highlightedDistricts,
            selectedCourtId: selectedCourtId
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var hasSetInitialVisibleRect = false
        private var lastCourtIDs: [String] = []
        private var lastSelectedCourtId: String?
        private var lastOverlayIDs: [String] = []
        private let onSelectCourt: (Court) -> Void

        init(onSelectCourt: @escaping (Court) -> Void) {
            self.onSelectCourt = onSelectCourt
        }

        func update(mapView: MKMapView, courts: [Court], highlightedDistricts: [DistrictMapArea], selectedCourtId: String?) {
            let courtIDs = courts.map(\.id)
            if courtIDs != lastCourtIDs {
                lastCourtIDs = courtIDs
                mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
                mapView.addAnnotations(courts.map(SearchPreviewCourtAnnotation.init))
            }

            let overlayIDs = highlightedDistricts.map(\.id)
            if overlayIDs != lastOverlayIDs {
                lastOverlayIDs = overlayIDs
                mapView.removeOverlays(mapView.overlays)

                for area in highlightedDistricts {
                    var coordinates = area.coordinates
                    let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                    polygon.title = area.id
                    mapView.addOverlay(polygon)
                }
            }

            let annotations = mapView.annotations.compactMap { $0 as? SearchPreviewCourtAnnotation }
            let targetRect = targetVisibleRect(annotations: annotations, districtAreas: highlightedDistricts)
            guard !targetRect.isNull, !targetRect.isEmpty else {
                return
            }

            if let selectedCourtId,
               let selectedAnnotation = annotations.first(where: { $0.court.id == selectedCourtId }) {
                if selectedCourtId != lastSelectedCourtId {
                    lastSelectedCourtId = selectedCourtId
                    let region = MKCoordinateRegion(
                        center: selectedAnnotation.coordinate,
                        latitudinalMeters: 3_000,
                        longitudinalMeters: 3_000
                    )
                    mapView.setRegion(region, animated: true)
                }
                mapView.selectAnnotation(selectedAnnotation, animated: true)
            } else {
                lastSelectedCourtId = nil
                for annotation in annotations {
                    mapView.deselectAnnotation(annotation, animated: false)
                }

                guard !hasSetInitialVisibleRect else {
                    return
                }
                hasSetInitialVisibleRect = true
                let edgePadding = UIEdgeInsets(top: 28, left: 18, bottom: 28, right: 18)
                mapView.setVisibleMapRect(targetRect, edgePadding: edgePadding, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon,
                  let overlayID = polygon.title ?? nil,
                  let area = districtAreasByID[overlayID] else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.fillColor = area.color.withAlphaComponent(0.16)
            renderer.strokeColor = area.color.withAlphaComponent(0.74)
            renderer.lineWidth = 1.5
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? SearchPreviewCourtAnnotation else {
                return nil
            }

            let reuseID = SearchPreviewAnnotationView.reuseID
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? SearchPreviewAnnotationView)
                ?? SearchPreviewAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? SearchPreviewCourtAnnotation else {
                return
            }
            onSelectCourt(annotation.court)
        }

        private func targetVisibleRect(annotations: [SearchPreviewCourtAnnotation], districtAreas: [DistrictMapArea]) -> MKMapRect {
            let annotationRects = annotations.map {
                MKMapRect(origin: MKMapPoint($0.coordinate), size: MKMapSize(width: 0, height: 0))
            }

            let overlayRects = districtAreas.map { area -> MKMapRect in
                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                return polygon.boundingMapRect
            }

            return (annotationRects + overlayRects).reduce(MKMapRect.null) { partial, next in
                partial.isNull ? next : partial.union(next)
            }
        }
    }
}

private final class SearchPreviewCourtAnnotation: NSObject, MKAnnotation {
    let court: Court
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(court: Court) {
        self.court = court
        coordinate = court.coordinate
        title = court.name
        subtitle = [localizedDistrictName(court.district), court.address]
            .compactMap { $0 }
            .joined(separator: " · ")
        super.init()
    }
}

private final class SearchClubAggregateAnnotation: NSObject, MKAnnotation {
    let members: [SearchPreviewCourtAnnotation]
    let coordinate: CLLocationCoordinate2D

    init(members: [SearchPreviewCourtAnnotation]) {
        self.members = members
        let coordinateTotal = members.reduce((latitude: 0.0, longitude: 0.0)) { partial, annotation in
            (
                latitude: partial.latitude + annotation.coordinate.latitude,
                longitude: partial.longitude + annotation.coordinate.longitude
            )
        }
        let memberCount = Double(members.count)
        coordinate = CLLocationCoordinate2D(
            latitude: coordinateTotal.latitude / memberCount,
            longitude: coordinateTotal.longitude / memberCount
        )
        super.init()
    }
}

private final class SearchPreviewUserAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String? = L10n.string("You are here", "Вы здесь")
    let subtitle: String?

    init(coordinate: CLLocationCoordinate2D, districtLabel: String?) {
        self.coordinate = coordinate
        subtitle = districtLabel
        super.init()
    }
}

private final class DistrictReferenceAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(area: DistrictMapArea) {
        var coordinates = area.coordinates
        let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
        let bounds = polygon.boundingMapRect
        coordinate = MKMapPoint(x: bounds.midX, y: bounds.midY).coordinate
        title = area.label
        super.init()
    }
}

private final class DistrictReferenceAnnotationView: MKAnnotationView {
    static let reuseID = "DistrictReferenceAnnotationView"

    private let titleLabel = UILabel()

    override var annotation: MKAnnotation? {
        didSet {
            titleLabel.text = annotation?.title ?? nil
            let fittingSize = titleLabel.sizeThatFits(CGSize(width: 190, height: 34))
            frame.size = CGSize(width: min(fittingSize.width + 20, 210), height: 34)
            titleLabel.frame = bounds.insetBy(dx: 10, dy: 5)
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(red: 0.02, green: 0.22, blue: 0.12, alpha: 0.82)
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 0.19, green: 0.84, blue: 0.58, alpha: 0.9).cgColor
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        addSubview(titleLabel)
        displayPriority = .required
        zPriority = .min
        clusteringIdentifier = nil
        canShowCallout = false
        self.annotation = annotation
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class SearchPreviewAnnotationView: MKAnnotationView {
    static let reuseID = "SearchPreviewAnnotationView"

    override var annotation: MKAnnotation? {
        didSet {
            configure()
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -18)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func configure() {
        guard let annotation = annotation as? SearchPreviewCourtAnnotation else {
            image = nil
            return
        }

        image = sportMarkerImage(for: annotation.court.supportedSports?.first)
    }
}

private struct HotDateCalendarCard: View {
    @Binding private var selection: Date
    let minimumDate: Date
    let tint: Color

    @State private var visibleMonthStart: Date

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        return calendar
    }

    init(selection: Binding<Date>, minimumDate: Date, tint: Color) {
        self._selection = selection
        self.minimumDate = minimumDate
        self.tint = tint

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selection.wrappedValue))
            ?? calendar.startOfDay(for: selection.wrappedValue)
        self._visibleMonthStart = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canMoveToPreviousMonth ? AppTheme.ink : AppTheme.ink.opacity(0.18))
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.035), in: Circle())
                }
                .disabled(!canMoveToPreviousMonth)
                .buttonStyle(.plain)

                Text(monthTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.035), in: Circle())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.ink.opacity(0.46))
                        .frame(height: 24)
                }

                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayButton(day)
                    } else {
                        Color.clear
                            .frame(height: 42)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    private var weekdayTitles: [String] {
        LocaleStore.currentEffectiveLocale == .ru ? ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"] : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    private var minimumDay: Date {
        calendar.startOfDay(for: minimumDate)
    }

    private var minimumMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: minimumDate)) ?? minimumDay
    }

    private var canMoveToPreviousMonth: Bool {
        visibleMonthStart > minimumMonthStart
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let value = formatter.string(from: visibleMonthStart)
        return value.prefix(1).uppercased() + String(value.dropFirst())
    }

    private var calendarDays: [Int?] {
        guard let daysRange = calendar.range(of: .day, in: .month, for: visibleMonthStart) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: visibleMonthStart)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        var days: [Int?] = Array(repeating: nil, count: leadingEmptyDays)
        days.append(contentsOf: daysRange.map { Optional($0) })

        let trailingEmptyDays = (7 - (days.count % 7)) % 7
        days.append(contentsOf: Array(repeating: nil, count: trailingEmptyDays))
        return days
    }

    private func dayButton(_ day: Int) -> some View {
        let date = date(for: day)
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let isDisabled = date < minimumDay

        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                selection = date
            }
        } label: {
            Text("\(day)")
                .font(.system(size: 16, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(dayTextColor(isSelected: isSelected, isDisabled: isDisabled))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Group {
                        if isSelected {
                            Circle().fill(tint)
                        } else if isToday {
                            Circle().fill(AppTheme.mint)
                        } else {
                            Circle().fill(Color.clear)
                        }
                    }
                )
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
    }

    private func dayTextColor(isSelected: Bool, isDisabled: Bool) -> Color {
        if isSelected {
            return .white
        }
        if isDisabled {
            return AppTheme.ink.opacity(0.2)
        }
        return AppTheme.ink
    }

    private func date(for day: Int) -> Date {
        var components = calendar.dateComponents([.year, .month], from: visibleMonthStart)
        components.day = day
        return calendar.date(from: components) ?? visibleMonthStart
    }

    private func moveMonth(by offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonthStart) else {
            return
        }
        visibleMonthStart = max(newMonth, minimumMonthStart)
    }
}

private enum HotSearchStep: Int, CaseIterable {
    case when = 0
    case who
    case location
    case confirm

    var badgeTitle: String {
        switch self {
        case .when:
            return L10n.string("1. When", "1. Когда")
        case .who:
            return L10n.string("2. Who", "2. Кого")
        case .location:
            return L10n.string("3. Where", "3. Где")
        case .confirm:
            return L10n.string("4. Review", "4. Подтверждение")
        }
    }
}

struct RunningRoutePreviewMapView: UIViewRepresentable {
    let points: [RunningRoutePoint]
    var isInteractive = false
    var showsAnnotations = false
    var mapType: MKMapType = .standard
    var followsRoads = true

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        mapView.isUserInteractionEnabled = isInteractive
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = false
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType
        mapView.isUserInteractionEnabled = isInteractive
        context.coordinator.update(mapView: mapView, points: points, showsAnnotations: showsAnnotations, followsRoads: followsRoads)
    }

    func makeCoordinator() -> RunningRouteMapCoordinator {
        RunningRouteMapCoordinator()
    }
}

struct RunningRouteDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var sport: Sport = .running
    let points: [RunningRoutePoint]
    @State private var usesSatelliteMap = false

    var body: some View {
        AppScreen {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.isEmpty ? sport.routeDefaultTitle : title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text(L10n.string("\(points.count) points · \(sport.routeFollowsRoads ? "street route" : "water route")", "\(points.count) точек · \(sport.routeFollowsRoads ? "маршрут по улицам" : "маршрут по воде")"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.56))
                    }

                    Spacer()

                    Button {
                        usesSatelliteMap.toggle()
                        AppHaptics.selection()
                    } label: {
                        Text(usesSatelliteMap ? L10n.string("Map", "Карта") : L10n.string("Satellite", "Спутник"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Color.black.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.04), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .background(Color.white)

                RunningRoutePreviewMapView(
                    points: points,
                    isInteractive: true,
                    showsAnnotations: true,
                    mapType: usesSatelliteMap ? .satellite : .standard,
                    followsRoads: sport.routeFollowsRoads
                )
                    .ignoresSafeArea(edges: .horizontal)
            }
        }
    }
}

private struct RunningRoutePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sport: Sport
    @Binding var points: [RunningRoutePoint]
    @Binding var routeTitle: String
    @State private var draftPoints: [RunningRoutePoint]
    @State private var draftTitle: String
    @State private var usesSatelliteMap = false
    @FocusState private var isRouteTitleFocused: Bool

    init(sport: Sport, points: Binding<[RunningRoutePoint]>, routeTitle: Binding<String>) {
        self.sport = sport
        _points = points
        _routeTitle = routeTitle
        _draftPoints = State(initialValue: points.wrappedValue)
        _draftTitle = State(initialValue: routeTitle.wrappedValue)
    }

    var body: some View {
        AppScreen {
            VStack(spacing: 0) {
                header

                ZStack(alignment: .topLeading) {
                    RunningRouteEditorMapView(
                        points: $draftPoints,
                        mapType: usesSatelliteMap ? .satellite : .standard,
                        followsRoads: sport.routeFollowsRoads
                    )
                        .ignoresSafeArea(edges: .horizontal)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Tap along the route on the map", "Нажимайте на карту по маршруту"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text(sport.routeFollowsRoads ? L10n.string("Add at least a start and finish. The line will follow streets.", "Поставьте минимум старт и финиш. Линия будет строиться по улицам.") : L10n.string("Add at least a start and finish. The line will follow the water between points.", "Поставьте минимум старт и финиш. Линия пойдёт по воде между точками."))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(16)
                }
                .frame(maxHeight: .infinity)

                controls
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sport.routeDefaultTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("\(draftPoints.count) points on map", "\(draftPoints.count) точек на карте"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }

            Spacer()

            Button {
                usesSatelliteMap.toggle()
                AppHaptics.selection()
            } label: {
                Text(usesSatelliteMap ? L10n.string("Map", "Карта") : L10n.string("Satellite", "Спутник"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.black.opacity(0.04), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                isRouteTitleFocused = false
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.04), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(sport == .supboard ? L10n.string("Route name, for example: island loop on the water", "Название маршрута, например: Крестовский, круг по воде") : L10n.string("Route name, for example: park loop, 5 km", "Название маршрута, например: Парк 300-летия, круг 5 км"), text: $draftTitle, axis: .vertical)
                .lineLimit(1 ... 3)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .focused($isRouteTitleFocused)
                .submitLabel(.done)
                .onSubmit {
                    isRouteTitleFocused = false
                }
                .padding(14)
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(L10n.string("Done", "Готово")) {
                            isRouteTitleFocused = false
                        }
                    }
                }

            HStack(spacing: 10) {
                Button {
                    isRouteTitleFocused = false
                    _ = draftPoints.popLast()
                    AppHaptics.selection()
                } label: {
                    Label(L10n.string("Undo", "Назад"), systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
                .disabled(draftPoints.isEmpty)

                Button {
                    isRouteTitleFocused = false
                    draftPoints.removeAll()
                    AppHaptics.selection()
                } label: {
                    Label(L10n.string("Clear", "Очистить"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle(tint: .red.opacity(0.88)))
                .disabled(draftPoints.isEmpty)
            }

            Button {
                isRouteTitleFocused = false
                points = draftPoints
                let normalizedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                routeTitle = normalizedTitle.isEmpty && draftPoints.count >= 2 ? L10n.string("Route on map", "Маршрут на карте") : normalizedTitle
                AppHaptics.notification(.success)
                dismiss()
            } label: {
                Text(L10n.string("Done", "Готово"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(draftPoints.count < 2)
        }
        .padding(18)
        .background(Color.white)
    }
}

private struct RunningRouteEditorMapView: UIViewRepresentable {
    @Binding var points: [RunningRoutePoint]
    var mapType: MKMapType = .standard
    var followsRoads = true

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.setRegion(MKCoordinateRegion(
            center: runningRouteDefaultCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.16)
        ), animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(RunningRouteMapCoordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)
        context.coordinator.pointsBinding = $points
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType
        context.coordinator.pointsBinding = $points
        context.coordinator.update(mapView: mapView, points: points, showsAnnotations: true, followsRoads: followsRoads)
    }

    func makeCoordinator() -> RunningRouteMapCoordinator {
        RunningRouteMapCoordinator()
    }
}

private let runningRouteDefaultCenter = CLLocationCoordinate2D(latitude: 59.9386, longitude: 30.3141)

final class RunningRouteMapCoordinator: NSObject, MKMapViewDelegate {
    var pointsBinding: Binding<[RunningRoutePoint]>?
    private var lastSignature = ""
    private var activeDirections: [MKDirections] = []

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let mapView = recognizer.view as? MKMapView else {
            return
        }
        let location = recognizer.location(in: mapView)
        let coordinate = mapView.convert(location, toCoordinateFrom: mapView)
        pointsBinding?.wrappedValue.append(RunningRoutePoint(coordinate: coordinate))
    }

    func update(mapView: MKMapView, points: [RunningRoutePoint], showsAnnotations: Bool, followsRoads: Bool) {
        let signature = "\(followsRoads ? "roads" : "direct")|" + points.map { "\($0.lat.rounded(toPlaces: 5)),\($0.lng.rounded(toPlaces: 5))" }.joined(separator: "|")
        guard signature != lastSignature else {
            return
        }
        lastSignature = signature
        activeDirections.forEach { $0.cancel() }
        activeDirections.removeAll()

        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        if showsAnnotations {
            mapView.addAnnotations(points.enumerated().map { index, point in
                RunningRoutePointAnnotation(index: index + 1, coordinate: point.coordinate)
            })
        }

        if points.count >= 2 {
            let coordinates = points.map(\.coordinate)
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
            setVisibleRoute(mapView: mapView, overlays: [polyline], animated: true)
            if followsRoads {
                buildStreetRoute(mapView: mapView, points: points, signature: signature)
            }
        } else if let first = points.first {
            mapView.setRegion(MKCoordinateRegion(
                center: first.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.05)
            ), animated: true)
        }
    }

    private func buildStreetRoute(mapView: MKMapView, points: [RunningRoutePoint], signature: String) {
        activeDirections.forEach { $0.cancel() }
        activeDirections.removeAll()

        let coordinatePairs = zip(points.dropLast(), points.dropFirst()).map { ($0.coordinate, $1.coordinate) }
        guard !coordinatePairs.isEmpty else {
            return
        }

        var routedOverlays = Array<MKPolyline?>(repeating: nil, count: coordinatePairs.count)
        var completedSegments = 0
        var hasFailedSegment = false

        for (index, pair) in coordinatePairs.enumerated() {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: pair.0))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: pair.1))
            request.transportType = .walking
            request.requestsAlternateRoutes = false

            let directions = MKDirections(request: request)
            activeDirections.append(directions)
            directions.calculate { [weak self, weak mapView] response, _ in
                DispatchQueue.main.async {
                    guard let self, let mapView, self.lastSignature == signature else {
                        return
                    }

                    if let route = response?.routes.first {
                        routedOverlays[index] = route.polyline
                    } else {
                        hasFailedSegment = true
                    }

                    completedSegments += 1
                    guard completedSegments == coordinatePairs.count else {
                        return
                    }

                    self.activeDirections.removeAll()
                    let resolvedOverlays = routedOverlays.compactMap { $0 }
                    guard !hasFailedSegment, resolvedOverlays.count == coordinatePairs.count else {
                        return
                    }

                    mapView.removeOverlays(mapView.overlays)
                    mapView.addOverlays(resolvedOverlays)
                    self.setVisibleRoute(mapView: mapView, overlays: resolvedOverlays, animated: true)
                }
            }
        }
    }

    private func setVisibleRoute(mapView: MKMapView, overlays: [MKPolyline], animated: Bool) {
        let routeRect = overlays.reduce(MKMapRect.null) { partial, overlay in
            partial.isNull ? overlay.boundingMapRect : partial.union(overlay.boundingMapRect)
        }

        guard !routeRect.isNull, !routeRect.isEmpty else {
            return
        }

        mapView.setVisibleMapRect(
            routeRect,
            edgePadding: UIEdgeInsets(top: 44, left: 34, bottom: 44, right: 34),
            animated: animated
        )
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor(red: 0.05, green: 0.55, blue: 0.36, alpha: 1)
        renderer.lineWidth = 5
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let annotation = annotation as? RunningRoutePointAnnotation else {
            return nil
        }
        let reuseID = "RunningRoutePointAnnotation"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        view.annotation = annotation
        view.markerTintColor = UIColor(red: 0.05, green: 0.55, blue: 0.36, alpha: 1)
        view.glyphText = "\(annotation.index)"
        view.canShowCallout = false
        return view
    }
}

private final class RunningRoutePointAnnotation: NSObject, MKAnnotation {
    let index: Int
    let coordinate: CLLocationCoordinate2D

    init(index: Int, coordinate: CLLocationCoordinate2D) {
        self.index = index
        self.coordinate = coordinate
    }
}

private struct SearchComposerAdvancedSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var draft: SearchDraft
    let sport: Sport
    let availableDistricts: [String]
    @Binding var availabilityByDay: [String: [String]]

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionCard(title: L10n.string("Advanced", "Дополнительно"), subtitle: L10n.string("Additional search settings: type, urgent window, districts, and club booking.", "Скрытые настройки поиска: тип, срочное окно, районы и бронирование клуба.")) {
                            AppSegmentedChoice(
                                title: L10n.string("Search type", "Тип поиска"),
                                items: SearchType.userVisibleCases,
                                selection: $draft.searchType,
                                titleForItem: \.title
                            )

                            if draft.searchType == .hot {
                                AppSegmentedChoice(
                                    title: L10n.string("Window", "Окно"),
                                    items: HotWindow.allCases,
                                    selection: Binding(
                                        get: { draft.hotWindow ?? .today },
                                        set: { draft.hotWindow = $0 }
                                    ),
                                    titleForItem: \.title
                                )

                                HStack(spacing: 12) {
                                    FieldShell(title: L10n.string("Start time", "Время старта")) {
                                        TextField("19:00", text: Binding(
                                            get: { draft.hotStartTime ?? "19:00" },
                                            set: { draft.hotStartTime = $0 }
                                        ))
                                        .keyboardType(.numbersAndPunctuation)
                                    }

                                    FieldShell(title: L10n.string("Duration", "Длительность")) {
                                        Stepper(value: Binding(
                                            get: { draft.durationMinutes ?? sport.defaultDurationMinutes },
                                            set: { draft.durationMinutes = $0 }
                                        ), in: 30 ... 180, step: 30) {
                                            Text(L10n.string("\(draft.durationMinutes ?? sport.defaultDurationMinutes) min", "\(draft.durationMinutes ?? sport.defaultDurationMinutes) мин"))
                                                .font(.headline)
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sport.venueBookedTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(L10n.string("Select this if the venue is ready and you only need to fill the roster.", "Отметь, если место уже есть и нужно только собрать состав."))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink.opacity(0.6))
                                }
                                Spacer()
                                Toggle("", isOn: $draft.hasCourtBooked)
                                    .labelsHidden()
                                    .tint(AppTheme.court)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.string("Preferred districts", "Удобные районы"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                                    .textCase(.uppercase)
                                    .tracking(1.4)

                                if availableDistricts.isEmpty {
                                    Text(L10n.string("Districts will appear after clubs for the selected sport load.", "Районы появятся, когда загрузятся клубы для выбранного спорта."))
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            advancedDistrictChip(title: L10n.string("Any district", "Любой район"), district: nil)
                                            ForEach(availableDistricts, id: \.self) { district in
                                                advancedDistrictChip(title: localizedDistrictName(district) ?? district, district: district)
                                            }
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.string("Current availability", "Текущая доступность"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                                    .textCase(.uppercase)
                                    .tracking(1.4)
                                AppAvailabilityWeekEditor(availabilityByDay: $availabilityByDay)
                            }
                        }

                        Button(L10n.string("Done", "Готово")) {
                            dismiss()
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(L10n.string("Settings", "Параметры"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func advancedDistrictChip(title: String, district: String?) -> some View {
        let isSelected = district == nil ? draft.preferredDistricts.isEmpty : draft.preferredDistricts.contains(district!)

        return Button {
            if let district {
                if isSelected {
                    draft.preferredDistricts.removeAll { $0 == district }
                } else {
                    draft.preferredDistricts.append(district)
                }
            } else {
                draft.preferredDistricts.removeAll()
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if isSelected && district != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isSelected ? .white : AppTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.court : AppTheme.creamLight, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SearchClubPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let sport: Sport
    let courts: [Court]
    let selectedCourtId: String?
    let selectsImmediately: Bool
    let allowsNoCourt: Bool
    let onSelect: (Court?) -> Void
    let onSelectCustomAddress: ((String) -> Void)?

    init(
        sport: Sport,
        courts: [Court],
        selectedCourtId: String?,
        selectsImmediately: Bool,
        allowsNoCourt: Bool = true,
        onSelect: @escaping (Court?) -> Void,
        onSelectCustomAddress: ((String) -> Void)? = nil
    ) {
        self.sport = sport
        self.courts = courts
        self.selectedCourtId = selectedCourtId
        self.selectsImmediately = selectsImmediately
        self.allowsNoCourt = allowsNoCourt
        self.onSelect = onSelect
        self.onSelectCustomAddress = onSelectCustomAddress
    }

    @State private var query = ""
    @State private var pendingSelectionId: String?
    @State private var pendingCourtSnapshot: Court?
    @State private var isMapExpanded = false
    @State private var addressSuggestions: [AddressSuggestion] = []
    @State private var isLoadingAddressSuggestions = false
    @State private var addressSuggestionTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSuggestAddresses: Bool {
        onSelectCustomAddress != nil && normalizedQuery.count >= 3
    }

    private var suggestionCity: String? {
        courts.first(where: { $0.city?.isEmpty == false })?.city ?? L10n.string("Saint Petersburg", "Санкт-Петербург")
    }

    private var filteredCourts: [Court] {
        let searchText = normalizedQuery.lowercased()
        let sortedCourts = courts.sorted { left, right in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        guard !searchText.isEmpty else {
            return sortedCourts
        }

        return sortedCourts.filter { court in
            [
                court.name,
                court.address,
                court.metroDisplayName,
                localizedDistrictName(court.district)
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
            .contains(searchText)
        }
    }

    private var suggestedCourts: [Court] {
        let searchText = normalizedQuery.lowercased()
        guard !searchText.isEmpty else {
            return []
        }

        let prefixMatches = filteredCourts.filter { court in
            court.name.lowercased().hasPrefix(searchText)
        }
        let metroMatches = filteredCourts.filter { court in
            guard let metro = court.metroDisplayName?.lowercased() else {
                return false
            }
            return metro.contains(searchText) && !prefixMatches.contains(where: { $0.id == court.id })
        }
        let districtMatches = filteredCourts.filter { court in
            guard let district = localizedDistrictName(court.district)?.lowercased() else {
                return false
            }
            return district.contains(searchText)
                && !prefixMatches.contains(where: { $0.id == court.id })
                && !metroMatches.contains(where: { $0.id == court.id })
        }

        return Array((prefixMatches + metroMatches + districtMatches).prefix(4))
    }

    private var focusedCourt: Court? {
        if let pendingSelectionId {
            return courts.first(where: { $0.id == pendingSelectionId })
        }
        if let selectedCourtId {
            return courts.first(where: { $0.id == selectedCourtId })
        }
        return suggestedCourts.first ?? filteredCourts.first
    }

    private var mapPreviewCourts: [Court] {
        var items: [Court] = []

        if let focusedCourt {
            items.append(focusedCourt)
        }

        for court in filteredCourts {
            guard items.count < 18 else {
                break
            }
            if !items.contains(where: { $0.id == court.id }) {
                items.append(court)
            }
        }

        return items
    }

    private var pendingCourt: Court? {
        pendingCourtSnapshot ?? pendingSelectionId.flatMap { id in courts.first(where: { $0.id == id }) }
    }

    private func recommendedListHeight(for availableHeight: CGFloat) -> CGFloat {
        let baseHeight = isSearchFocused ? availableHeight * 0.3 : availableHeight * 0.38
        let minimumHeight: CGFloat = isSearchFocused ? 260 : 340
        let maximumHeight: CGFloat = isSearchFocused ? 300 : 420
        return min(max(baseHeight, minimumHeight), maximumHeight)
    }

    var body: some View {
        AppScreen {
            GeometryReader { sheetGeometry in
                VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 48, height: 6)
                    .padding(.top, 10)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("Choose a club", "Выбор клуба"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                        Text(L10n.string("Name, transit station, district, or address", "Название, метро, район или адрес"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Spacer(minLength: 8)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.04), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.ink.opacity(0.36))
                    ZStack(alignment: .leading) {
                        if query.isEmpty {
                            Text(L10n.string("Club name, transit station, district, or address", "Название клуба, метро, район или адрес"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppTheme.ink.opacity(0.28))
                        }

                        TextField("", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(AppTheme.ink)
                            .tint(AppTheme.court)
                            .focused($isSearchFocused)
                    }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            clearAddressSuggestions()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.ink.opacity(0.2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 18)

                if !normalizedQuery.isEmpty,
                   let onSelectCustomAddress {
                    addressSuggestionsSection(onSelectAddress: onSelectCustomAddress)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    if normalizedQuery.count >= 3 && !isLoadingAddressSuggestions && addressSuggestions.isEmpty {
                        MissingClubAddressHint(address: query) { address in
                            onSelectCustomAddress(address)
                            dismiss()
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                    }
                }

                if !suggestedCourts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(suggestedCourts) { court in
                                Button {
                                    commitSelection(court)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(court.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppTheme.ink)
                                            .lineLimit(1)
                                        Text(court.metroDisplayName ?? localizedDistrictName(court.district) ?? court.address)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.ink.opacity(0.56))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(
                                                pendingSelectionId == court.id ? AppTheme.court.opacity(0.32) : Color.black.opacity(0.06),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        chip(title: L10n.string("All", "Все"), selected: true)
                        chip(title: sport.title, selected: false)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "location")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(L10n.string("Near you", "Рядом с вами"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                            }

                            Text(
                                focusedCourt.map { court in
                                    [court.name, localizedDistrictName(court.district)]
                                        .compactMap { $0 }
                                        .joined(separator: " · ")
                                } ?? L10n.string("Saint Petersburg", "Санкт-Петербург")
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink.opacity(0.56))
                            .lineLimit(2)

                            Button {
                                isMapExpanded = true
                                AppHaptics.selection()
                            } label: {
                                Label(L10n.string("Expand map", "Развернуть карту"), systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.court)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 8)

                        SearchClubPickerMapView(
                            courts: mapPreviewCourts,
                            focusedCourt: pendingCourt ?? focusedCourt,
                            onSelectCourt: { courtId in
                                previewSelection(courts.first(where: { $0.id == courtId }))
                            }
                        )
                        .frame(width: 132, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                    }

                    if let pendingCourt {
                        MapSelectedCourtMiniCard(court: pendingCourt, sport: sport) {
                            confirmSelection(pendingCourt)
                        }
                    }
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("Recommended", "Рекомендуемые"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 18)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            if allowsNoCourt {
                                CourtBrowseCard(
                                    sport: sport,
                                    title: L10n.string("No preference", "Без привязки"),
                                    subtitleLines: [L10n.string("We’ll show the nearest suitable clubs", "Покажем ближайшие подходящие клубы")],
                                    distance: nil,
                                    isSelected: pendingSelectionId == nil
                                ) {
                                    commitSelection(nil as Court?)
                                }
                            }

                            ForEach(filteredCourts) { court in
                                CourtBrowseCard(
                                    sport: sport,
                                    title: court.name,
                                    subtitleLines: [
                                        sport.title,
                                        court.metroDisplayName ?? L10n.string("Transit station not specified", "Метро не указано"),
                                        court.address
                                    ],
                                    distance: court.distanceLabel,
                                    isSelected: pendingSelectionId == court.id
                                ) {
                                    commitSelection(court)
                                }
                            }

                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
                    .frame(height: recommendedListHeight(for: sheetGeometry.size.height))
                    .scrollDismissesKeyboard(.interactively)
                }
                .padding(.top, 20)

                VStack(spacing: 10) {
                    Button(pendingSelectionId == nil && allowsNoCourt ? L10n.string("Keep no preference", "Оставить без привязки") : L10n.string("Choose this club", "Выбрать этот клуб")) {
                        onSelect(pendingCourtSnapshot ?? pendingSelectionId.flatMap { id in courts.first(where: { $0.id == id }) })
                        dismiss()
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                    .disabled(!allowsNoCourt && pendingSelectionId == nil)

                    Text(L10n.string("You can change the club later", "Клуб можно будет изменить позже"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink.opacity(0.38))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.white.opacity(0.96))
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            pendingSelectionId = selectedCourtId
            pendingCourtSnapshot = selectedCourtId.flatMap { id in courts.first(where: { $0.id == id }) }
            isSearchFocused = false
        }
        .onChange(of: query) { value in
            scheduleAddressSuggestions(for: value)
        }
        .onDisappear {
            addressSuggestionTask?.cancel()
        }
        .sheet(isPresented: $isMapExpanded) {
            SearchClubExpandedMapSheet(
                sport: sport,
                courts: mapPreviewCourts,
                focusedCourt: pendingCourt ?? focusedCourt,
                selectedCourt: pendingCourt,
                onPreview: { court in
                    previewSelection(court)
                },
                onChoose: { court in
                    confirmSelection(court)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    @ViewBuilder
    private func addressSuggestionsSection(onSelectAddress: @escaping (String) -> Void) -> some View {
        if canSuggestAddresses {
            if isLoadingAddressSuggestions {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(AppTheme.court)
                    Text(L10n.string("Searching for address", "Ищем адрес"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.62))
                    Spacer()
                }
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            } else if !addressSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("Addresses", "Адреса"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.ink.opacity(0.48))
                            .textCase(.uppercase)
                        Text(L10n.string("If the club isn’t listed, choose the exact address from suggestions.", "Если клуба нет в списке, выберите точный адрес из подсказок."))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.54))
                    }

                    ForEach(addressSuggestions) { suggestion in
                        AddressSuggestionRow(suggestion: suggestion) {
                            onSelectAddress(suggestion.address)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func clearAddressSuggestions() {
        addressSuggestionTask?.cancel()
        addressSuggestions = []
        isLoadingAddressSuggestions = false
    }

    @MainActor
    private func scheduleAddressSuggestions(for value: String) {
        addressSuggestionTask?.cancel()
        addressSuggestions = []

        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard onSelectCustomAddress != nil, query.count >= 3 else {
            isLoadingAddressSuggestions = false
            return
        }

        let city = suggestionCity
        addressSuggestionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else {
                return
            }

            isLoadingAddressSuggestions = true

            do {
                let serverSuggestions = try await appModel.repository.fetchAddressSuggestions(query: query, city: city)
                let suggestions = serverSuggestions.isEmpty
                    ? await fetchLocalAddressSuggestions(query: query, city: city)
                    : serverSuggestions
                guard !Task.isCancelled else {
                    return
                }

                addressSuggestions = suggestions
                isLoadingAddressSuggestions = false
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                addressSuggestions = []
                isLoadingAddressSuggestions = false
            }
        }
    }

    private func fetchLocalAddressSuggestions(query: String, city: String?) async -> [AddressSuggestion] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [city, query]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351),
            latitudinalMeters: 45_000,
            longitudinalMeters: 45_000
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            return Array(response.mapItems.prefix(6).enumerated()).compactMap { index, item in
                let address = formattedAddress(for: item.placemark)
                let title = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTitle = (title?.isEmpty == false ? title : address) ?? query
                let resolvedAddress = address ?? resolvedTitle
                guard !resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                return AddressSuggestion(
                    id: "mapkit-\(index)-\(resolvedAddress)",
                    title: resolvedTitle,
                    address: resolvedAddress,
                    subtitle: item.placemark.locality,
                    lat: item.placemark.coordinate.latitude,
                    lng: item.placemark.coordinate.longitude
                )
            }
        } catch {
            return []
        }
    }

    private func formattedAddress(for placemark: MKPlacemark) -> String? {
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let parts = [
            placemark.locality,
            street.isEmpty ? nil : street,
            placemark.name
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        let uniqueParts = parts.reduce(into: [String]()) { result, part in
            if !result.contains(part) {
                result.append(part)
            }
        }

        return uniqueParts.isEmpty ? nil : uniqueParts.joined(separator: ", ")
    }

    private func previewSelection(_ court: Court?) {
        guard allowsNoCourt || court != nil else {
            return
        }

        pendingSelectionId = court?.id
        pendingCourtSnapshot = court
        AppHaptics.selection()
    }

    private func confirmSelection(_ court: Court? = nil) {
        let resolvedCourt = court ?? pendingCourt
        onSelect(resolvedCourt)
        dismiss()
    }

    private func commitSelection(_ court: Court?) {
        guard allowsNoCourt || court != nil else {
            return
        }

        previewSelection(court)

        guard selectsImmediately else {
            return
        }

        confirmSelection(court)
    }

    private func chip(title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? .white : AppTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(selected ? AppTheme.court : Color.white, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? AppTheme.court : Color.black.opacity(0.08), lineWidth: 1)
            )
    }

}

private struct AddressSuggestionRow: View {
    let suggestion: AddressSuggestion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.mint, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(suggestion.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(suggestion.address)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.court)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.32))
                    .padding(.top, 12)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MissingClubAddressHint: View {
    let address: String
    let onUseAddress: (String) -> Void

    private var normalizedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button {
            onUseAddress(normalizedAddress)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.mint, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("Use entered address", "Использовать введённый адрес"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(normalizedAddress)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.court)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.string("If the address isn’t in suggestions, we’ll save the entered text as the search location.", "Если адреса нет в подсказках, сохраним введённый текст как место поиска."))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.32))
                    .padding(.top, 12)
            }
        }
        .buttonStyle(.plain)
        .disabled(normalizedAddress.isEmpty)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.mint.opacity(0.74), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.court.opacity(0.18), lineWidth: 1)
        )
    }
}

struct CourtBrowseCard: View {
    let sport: Sport
    let title: String
    let subtitleLines: [String]
    let distance: String?
    let isSelected: Bool
    var showsSelectionIndicator: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.court.opacity(0.85), AppTheme.ink.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)
                    .overlay(
                        SportIconView(sport: sport, color: .white.opacity(0.92), size: 34)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if let distance {
                            Text(distance)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink.opacity(0.62))
                        }
                    }

                    ForEach(Array(subtitleLines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 8) {
                            if index == 0 {
                                SportIconView(sport: sport, color: AppTheme.court, size: 13)
                                    .frame(width: 14)
                            } else {
                                Image(systemName: index == 1 ? "tram.fill" : "mappin.and.ellipse")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink.opacity(0.72))
                                    .frame(width: 14)
                            }
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(index == 0 ? AppTheme.court : AppTheme.ink.opacity(0.72))
                                .lineLimit(index == 2 ? 2 : 1)
                        }
                    }
                }
                .padding(.top, 3)

                if showsSelectionIndicator {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(isSelected ? AppTheme.court : AppTheme.ink.opacity(0.18))
                        .padding(.top, 3)
                }
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(isSelected ? AppTheme.court.opacity(0.24) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MapSelectedCourtMiniCard: View {
    let court: Court
    let sport: Sport
    let onChoose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MapCourtThumbnail(court: court, sport: sport, size: 66)

            VStack(alignment: .leading, spacing: 4) {
                Text(court.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)

                Text([sport.title, court.metroDisplayName ?? localizedDistrictName(court.district)]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink.opacity(0.58))
                    .lineLimit(1)

                Text(court.address)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.5))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(L10n.string("Choose", "Выбрать")) {
                onChoose()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(AppTheme.ink, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.mint.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.court.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct MapCourtThumbnail: View {
    let court: Court
    let sport: Sport
    let size: CGFloat

    var body: some View {
        RemoteImage(url: resolveAppRemoteURL(court.primaryPhotoUrl)) { _ in
            fallback
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.court.opacity(0.82), AppTheme.ink.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            SportIconView(
                sport: court.supportedSports?.first ?? sport,
                color: .white.opacity(0.9),
                size: size * 0.38
            )
        }
    }
}

private struct SearchClubExpandedMapSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sport: Sport
    let courts: [Court]
    let focusedCourt: Court?
    let selectedCourt: Court?
    let onPreview: (Court) -> Void
    let onChoose: (Court) -> Void

    @State private var previewCourt: Court?
    @State private var focusRevision = 0

    private var activeCourt: Court? {
        previewCourt ?? selectedCourt ?? focusedCourt
    }

    var body: some View {
        AppScreen {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 48, height: 6)
                    .padding(.top, 10)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("Club map", "Карта клубов"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text(L10n.string("Tap a marker to view and choose a club", "Нажмите на значок, чтобы увидеть клуб и выбрать его"))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.58))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.04), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ZStack(alignment: .bottom) {
                    SearchClubPickerMapView(
                        courts: courts,
                        focusedCourt: activeCourt,
                        focusRevision: focusRevision,
                        onSelectCourt: { courtId in
                            guard let court = courts.first(where: { $0.id == courtId }) else {
                                return
                            }
                            previewCourt = court
                            focusRevision += 1
                            onPreview(court)
                        },
                        onChooseCourt: { courtId in
                            guard let court = courts.first(where: { $0.id == courtId }) else {
                                return
                            }
                            onChoose(court)
                            dismiss()
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                    if let activeCourt {
                        MapSelectedCourtMiniCard(court: activeCourt, sport: sport) {
                            onChoose(activeCourt)
                            dismiss()
                        }
                        .padding(14)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .onAppear {
            previewCourt = selectedCourt ?? focusedCourt
        }
    }
}

private final class SearchClubPickerAnnotationView: MKAnnotationView {
    static let reuseID = "SearchClubPickerAnnotationView"

    private let markerIconView = UIImageView()
    private let titleLabel = UILabel()
    private var representedCourtID: String?
    private var configuredCalloutCourtID: String?
    private var configuredShowsCallout: Bool?
    private var photoTask: URLSessionDataTask?

    override var annotation: MKAnnotation? {
        didSet {
            if let annotation = annotation as? SearchPreviewCourtAnnotation {
                representedCourtID = annotation.court.id
                configureMarker(for: annotation.court)
            } else {
                representedCourtID = nil
                configureMarker(for: nil)
            }
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        markerIconView.contentMode = .scaleAspectFit
        markerIconView.isUserInteractionEnabled = false

        titleLabel.backgroundColor = UIColor.white.withAlphaComponent(0.96)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor(red: 0.09, green: 0.17, blue: 0.16, alpha: 1)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.layer.cornerRadius = 14
        titleLabel.layer.borderWidth = 1
        titleLabel.layer.borderColor = UIColor.black.withAlphaComponent(0.08).cgColor
        titleLabel.clipsToBounds = true
        titleLabel.isUserInteractionEnabled = false

        addSubview(titleLabel)
        addSubview(markerIconView)

        image = nil
        clipsToBounds = false
        clusteringIdentifier = nil
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        photoTask?.cancel()
        photoTask = nil
        representedCourtID = nil
        configuredCalloutCourtID = nil
        configuredShowsCallout = nil
        leftCalloutAccessoryView = nil
        detailCalloutAccessoryView = nil
        rightCalloutAccessoryView = nil
        configureMarker(for: nil)
    }

    func configure(court: Court, showsCallout: Bool) {
        representedCourtID = court.id
        configureMarker(for: court)
        canShowCallout = showsCallout
        clusteringIdentifier = nil
        displayPriority = .required

        guard configuredCalloutCourtID != court.id || configuredShowsCallout != showsCallout else {
            return
        }
        configuredCalloutCourtID = court.id
        configuredShowsCallout = showsCallout
        photoTask?.cancel()
        photoTask = nil

        guard showsCallout else {
            leftCalloutAccessoryView = nil
            detailCalloutAccessoryView = nil
            rightCalloutAccessoryView = nil
            return
        }

        leftCalloutAccessoryView = makePhotoView(for: court)
        detailCalloutAccessoryView = SearchClubCalloutContentView(court: court)

        let chooseButton = UIButton(type: .system)
        chooseButton.setTitle(L10n.string("Choose", "Выбрать"), for: .normal)
        chooseButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        chooseButton.tintColor = UIColor(red: 0.09, green: 0.17, blue: 0.16, alpha: 1)
        chooseButton.frame = CGRect(x: 0, y: 0, width: 74, height: 34)
        rightCalloutAccessoryView = chooseButton
    }

    private func configureMarker(for court: Court?) {
        let iconSize = CGSize(width: 42, height: 52)
        let iconAnchor = CGPoint(x: 21, y: 48)
        let labelOriginX: CGFloat = 35
        let labelHeight: CGFloat = 28
        let maximumLabelWidth: CGFloat = 160

        if let court {
            markerIconView.image = sportMarkerImage(for: court.supportedSports?.first)
        } else {
            markerIconView.image = nil
        }
        markerIconView.frame = CGRect(origin: .zero, size: iconSize)

        let title = court?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        titleLabel.text = title
        titleLabel.isHidden = title.isEmpty

        let labelWidth: CGFloat
        if title.isEmpty {
            labelWidth = 0
        } else {
            let measuredWidth = ceil(
                (title as NSString).boundingRect(
                    with: CGSize(width: maximumLabelWidth - 24, height: labelHeight),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: titleLabel.font as Any],
                    context: nil
                ).width
            )
            labelWidth = min(maximumLabelWidth, max(52, measuredWidth + 24))
        }

        if title.isEmpty {
            titleLabel.frame = .zero
        } else {
            titleLabel.frame = CGRect(
                x: labelOriginX,
                y: 5,
                width: labelWidth,
                height: labelHeight
            )
        }

        let markerWidth = title.isEmpty ? iconSize.width : labelOriginX + labelWidth
        bounds = CGRect(x: 0, y: 0, width: markerWidth, height: iconSize.height)
        centerOffset = CGPoint(
            x: markerWidth / 2 - iconAnchor.x,
            y: iconSize.height / 2 - iconAnchor.y
        )
        calloutOffset = CGPoint(x: iconAnchor.x - markerWidth / 2, y: 0)
        accessibilityLabel = title.isEmpty ? L10n.string("Sports club", "Спортивный клуб") : title
    }

    private func makePhotoView(for court: Court) -> UIImageView {
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 58, height: 58))
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = UIColor(red: 0.9, green: 0.97, blue: 0.93, alpha: 1)
        imageView.tintColor = UIColor(red: 0.08, green: 0.54, blue: 0.36, alpha: 1)
        imageView.image = UIImage(systemName: sportSymbolName(for: court.supportedSports?.first ?? .tennis))

        guard let url = resolveAppRemoteURL(court.primaryPhotoUrl) else {
            return imageView
        }

        let courtID = court.id
        let task = URLSession.shared.dataTask(with: url) { [weak self, weak imageView] data, _, _ in
            guard let data,
                  let image = UIImage(data: data) else {
                return
            }

            DispatchQueue.main.async {
                guard self?.representedCourtID == courtID else {
                    return
                }
                imageView?.image = image
                imageView?.contentMode = .scaleAspectFill
            }
        }
        photoTask = task
        task.resume()

        return imageView
    }
}

private final class SearchClubCalloutContentView: UIStackView {
    init(court: Court) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = 3
        widthAnchor.constraint(equalToConstant: 226).isActive = true

        let sportsLine = (court.supportedSports?.isEmpty == false ? court.supportedSports : nil)?
            .map(\.title)
            .joined(separator: " · ")
            ?? L10n.string("Club", "Клуб")
        addArrangedSubview(makeLabel(sportsLine, font: .systemFont(ofSize: 12, weight: .semibold), color: UIColor(red: 0.08, green: 0.54, blue: 0.36, alpha: 1), lines: 1))

        let placeLine = [court.metroDisplayName, localizedDistrictName(court.district), court.distanceLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !placeLine.isEmpty {
            addArrangedSubview(makeLabel(placeLine, font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabel, lines: 1))
        }

        addArrangedSubview(makeLabel(court.address, font: .systemFont(ofSize: 12, weight: .medium), color: .label, lines: 2))

        let extraLine = [court.workingHours, court.priceRange, court.rating.map { L10n.string(String(format: "Rating %.1f", $0), String(format: "Рейтинг %.1f", $0)) }]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !extraLine.isEmpty {
            addArrangedSubview(makeLabel(extraLine, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabel, lines: 1))
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor, lines: Int) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

private struct SearchMapItem: Identifiable {
    let user: DiscoverUser
    let search: GameSearch

    var id: String { search.id }

    var districtID: String? {
        if let courtDistrict = search.preferredCourt?.district?.lowercased(), !courtDistrict.isEmpty {
            return courtDistrict
        }

        if let district = search.preferredDistricts.first?.lowercased(), !district.isEmpty {
            return district
        }

        if let userDistrict = user.district?.lowercased(), !userDistrict.isEmpty {
            return userDistrict
        }

        return nil
    }

    var coordinate: CLLocationCoordinate2D {
        if let court = search.preferredCourt {
            return court.coordinate
        }

        if let districtID, let area = districtAreasByID[districtID] {
            return area.centerCoordinate
        }

        return CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351)
    }

    var venueTitle: String {
        if let court = search.preferredCourt {
            return court.name
        }

        if let customVenueTitle = search.customVenueTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customVenueTitle.isEmpty {
            return customVenueTitle
        }

        if let customVenueAddress = search.customVenueAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customVenueAddress.isEmpty {
            return customVenueAddress
        }

        if let districtID, let districtName = localizedDistrictName(districtID) {
            return districtName
        }

        return L10n.string("Location to be confirmed", "Место уточняется")
    }

    var timeTitle: String {
        guard let hotStartsAt = search.hotStartsAt else {
            return L10n.string("Time to be confirmed", "Время уточняется")
        }

        return hotStartsAt.formattedDateTime()
    }

    var playersTitle: String {
        let approved = search.responses.filter { $0.status == "approved" }.count
        return L10n.string("\(approved) / \(max(search.playersNeeded, 1)) confirmed", "\(approved) / \(max(search.playersNeeded, 1)) собрано")
    }
}

private extension DistrictMapArea {
    var centerCoordinate: CLLocationCoordinate2D {
        let polygonCoordinates = self.coordinates
        guard !polygonCoordinates.isEmpty else {
            return CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351)
        }

        let lat = polygonCoordinates.map(\.latitude).reduce(0, +) / Double(polygonCoordinates.count)
        let lon = polygonCoordinates.map(\.longitude).reduce(0, +) / Double(polygonCoordinates.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

private struct SearchMapPreviewCard: View {
    let item: SearchMapItem
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteAvatarView(name: item.user.displayName, path: item.user.avatarUrl, size: 46)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(item.user.isOnline ? Color(red: 0.22, green: 0.82, blue: 0.45) : Color.white.opacity(0.5))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.black.opacity(0.72), lineWidth: 2))
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.user.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(item.search.sport.title) · \(item.search.sport.formatTitle(format: item.search.format, playersNeeded: item.search.playersNeeded))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.36, green: 0.94, blue: 0.63))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(item.timeTitle, systemImage: "calendar")
                    Label(item.venueTitle, systemImage: "mappin.and.ellipse")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
            }
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 8) {
                Text(item.playersTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)

                Button(action: onOpen) {
                    Text(L10n.string("Open", "Открыть"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Color(red: 0.36, green: 0.94, blue: 0.63), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 8)
    }
}

private struct SearchesMapView: UIViewRepresentable {
    let items: [SearchMapItem]
    let selectedItemID: String?
    let highlightedDistrictIDs: [String]
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            items: items,
            selectedItemID: selectedItemID,
            highlightedDistrictIDs: highlightedDistrictIDs
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let onSelect: (String) -> Void
        private var lastItemIDs: [String] = []
        private var lastOverlayIDs: [String] = []
        private var lastSelectedItemID: String?
        private var hasSetVisibleRegion = false

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        func update(
            mapView: MKMapView,
            items: [SearchMapItem],
            selectedItemID: String?,
            highlightedDistrictIDs: [String]
        ) {
            let itemIDs = items.map(\.id)
            if itemIDs != lastItemIDs {
                lastItemIDs = itemIDs
                mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
                mapView.addAnnotations(items.map(SearchMapAnnotation.init))
                hasSetVisibleRegion = false
            }

            let overlayIDs = Array(Set(highlightedDistrictIDs.map { $0.lowercased() })).sorted()
            updateDistrictOverlays(mapView: mapView, districtIDs: overlayIDs)
            updateSelection(mapView: mapView, selectedItemID: selectedItemID)

            guard !hasSetVisibleRegion else {
                return
            }

            let targetRect = targetVisibleRect(items: items, districtIDs: overlayIDs)
            if targetRect.isNull || targetRect.isEmpty {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351),
                        latitudinalMeters: 18_000,
                        longitudinalMeters: 18_000
                    ),
                    animated: false
                )
                hasSetVisibleRegion = true
                return
            }

            mapView.setVisibleMapRect(
                targetRect,
                edgePadding: UIEdgeInsets(top: 34, left: 34, bottom: 118, right: 34),
                animated: false
            )
            hasSetVisibleRegion = true
        }

        private func updateDistrictOverlays(mapView: MKMapView, districtIDs: [String]) {
            guard districtIDs != lastOverlayIDs else {
                return
            }

            lastOverlayIDs = districtIDs
            mapView.removeOverlays(mapView.overlays)

            for districtID in districtIDs {
                guard let area = districtAreasByID[districtID] else {
                    continue
                }

                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                polygon.title = area.id
                mapView.addOverlay(polygon)
            }
        }

        private func updateSelection(mapView: MKMapView, selectedItemID: String?) {
            guard selectedItemID != lastSelectedItemID else {
                return
            }

            lastSelectedItemID = selectedItemID
            for annotation in mapView.annotations.compactMap({ $0 as? SearchMapAnnotation }) {
                guard let view = mapView.view(for: annotation) as? SearchMapAnnotationView else {
                    continue
                }
                view.configure(item: annotation.item, isSelected: annotation.item.id == selectedItemID)
            }
        }

        private func targetVisibleRect(items: [SearchMapItem], districtIDs: [String]) -> MKMapRect {
            let annotationRects = items.map {
                MKMapRect(origin: MKMapPoint($0.coordinate), size: MKMapSize(width: 0, height: 0))
            }

            let districtRects = districtIDs.compactMap { districtID -> MKMapRect? in
                guard let area = districtAreasByID[districtID] else {
                    return nil
                }

                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                return polygon.boundingMapRect
            }

            return (annotationRects + districtRects).reduce(MKMapRect.null) { partial, next in
                partial.isNull ? next : partial.union(next)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon,
                  let overlayID = polygon.title ?? nil,
                  let area = districtAreasByID[overlayID] else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.fillColor = area.color.withAlphaComponent(0.22)
            renderer.strokeColor = area.color.withAlphaComponent(0.92)
            renderer.lineWidth = 2.4
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? SearchMapAnnotation else {
                return nil
            }

            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: SearchMapAnnotationView.reuseID) as? SearchMapAnnotationView)
                ?? SearchMapAnnotationView(annotation: annotation, reuseIdentifier: SearchMapAnnotationView.reuseID)
            view.annotation = annotation
            view.configure(item: annotation.item, isSelected: annotation.item.id == lastSelectedItemID)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? SearchMapAnnotation else {
                return
            }

            onSelect(annotation.item.id)
        }
    }
}

private final class SearchMapAnnotation: NSObject, MKAnnotation {
    let item: SearchMapItem

    var coordinate: CLLocationCoordinate2D {
        item.coordinate
    }

    var title: String? {
        item.user.displayName
    }

    var subtitle: String? {
        item.venueTitle
    }

    init(item: SearchMapItem) {
        self.item = item
        super.init()
    }
}

private final class SearchMapAnnotationView: MKAnnotationView {
    static let reuseID = "SearchMapAnnotationView"

    func configure(item: SearchMapItem, isSelected: Bool) {
        image = searchMapMarkerImage(for: item.search.sport, isSelected: isSelected)
        centerOffset = CGPoint(x: 0, y: -20)
        canShowCallout = false
        displayPriority = isSelected ? .required : .defaultHigh
        zPriority = isSelected ? .max : .defaultSelected
    }
}

private func searchMapMarkerImage(for sport: Sport, isSelected: Bool) -> UIImage? {
    let size = CGSize(width: isSelected ? 54 : 46, height: isSelected ? 54 : 46)
    let renderer = UIGraphicsImageRenderer(size: size)
    let tint = searchMapSportUIColor(for: sport)
    let symbolConfig = UIImage.SymbolConfiguration(pointSize: isSelected ? 19 : 17, weight: .bold)
    let symbol = UIImage(systemName: sportSymbolName(for: sport), withConfiguration: symbolConfig)?
        .withTintColor(.white, renderingMode: .alwaysOriginal)

    return renderer.image { _ in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        UIColor.black.withAlphaComponent(0.68).setFill()
        UIBezierPath(ovalIn: rect).fill()

        tint.setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: isSelected ? 4 : 5, dy: isSelected ? 4 : 5)).fill()

        UIColor.white.withAlphaComponent(isSelected ? 0.95 : 0.72).setStroke()
        let stroke = UIBezierPath(ovalIn: rect.insetBy(dx: 1.2, dy: 1.2))
        stroke.lineWidth = isSelected ? 3 : 2
        stroke.stroke()

        if let symbol {
            let side = isSelected ? 24 : 21
            let symbolRect = CGRect(
                x: (size.width - CGFloat(side)) / 2,
                y: (size.height - CGFloat(side)) / 2,
                width: CGFloat(side),
                height: CGFloat(side)
            )
            symbol.draw(in: symbolRect)
        }
    }
}

private func searchMapSportUIColor(for sport: Sport) -> UIColor {
    switch sport {
    case .tennis:
        return UIColor(red: 0.94, green: 0.78, blue: 0.18, alpha: 1)
    case .padel:
        return UIColor(red: 0.11, green: 0.72, blue: 0.43, alpha: 1)
    case .football:
        return UIColor(red: 0.14, green: 0.55, blue: 0.96, alpha: 1)
    case .badminton:
        return UIColor(red: 0.48, green: 0.38, blue: 0.96, alpha: 1)
    case .tableTennis:
        return UIColor(red: 0.95, green: 0.35, blue: 0.30, alpha: 1)
    case .running:
        return UIColor(red: 0.98, green: 0.45, blue: 0.18, alpha: 1)
    case .supboard:
        return UIColor(red: 0.16, green: 0.72, blue: 0.86, alpha: 1)
    default:
        return UIColor(red: 0.22, green: 0.86, blue: 0.55, alpha: 1)
    }
}

struct SearchClubPickerMapView: UIViewRepresentable {
    let courts: [Court]
    let focusedCourt: Court?
    let focusedDistrictID: String?
    let highlightedDistrictIDs: [String]
    let focusRevision: Int
    let annotationLimit: Int?
    let cityCenter: CLLocationCoordinate2D?
    let cityDiameterMeters: CLLocationDistance
    let userCoordinate: CLLocationCoordinate2D?
    let userDistrictLabel: String?
    let focusesUserLocation: Bool
    let showsDistrictReference: Bool
    let onSelectCourt: (String) -> Void
    let onChooseCourt: ((String) -> Void)?

    init(
        courts: [Court],
        focusedCourt: Court?,
        focusedDistrictID: String? = nil,
        highlightedDistrictIDs: [String] = [],
        focusRevision: Int = 0,
        annotationLimit: Int? = 18,
        cityCenter: CLLocationCoordinate2D? = nil,
        cityDiameterMeters: CLLocationDistance = 70_000,
        userCoordinate: CLLocationCoordinate2D? = nil,
        userDistrictLabel: String? = nil,
        focusesUserLocation: Bool = false,
        showsDistrictReference: Bool = false,
        onSelectCourt: @escaping (String) -> Void,
        onChooseCourt: ((String) -> Void)? = nil
    ) {
        self.courts = courts
        self.focusedCourt = focusedCourt
        self.focusedDistrictID = focusedDistrictID
        self.highlightedDistrictIDs = highlightedDistrictIDs
        self.focusRevision = focusRevision
        self.annotationLimit = annotationLimit
        self.cityCenter = cityCenter
        self.cityDiameterMeters = cityDiameterMeters
        self.userCoordinate = userCoordinate
        self.userDistrictLabel = userDistrictLabel
        self.focusesUserLocation = focusesUserLocation
        self.showsDistrictReference = showsDistrictReference
        self.onSelectCourt = onSelectCourt
        self.onChooseCourt = onChooseCourt
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectCourt: onSelectCourt, onChooseCourt: onChooseCourt)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsTraffic = false
        mapView.showsScale = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(
            mapView: mapView,
            courts: courts,
            focusedCourt: focusedCourt,
            focusedDistrictID: focusedDistrictID,
            highlightedDistrictIDs: highlightedDistrictIDs,
            focusRevision: focusRevision,
            annotationLimit: annotationLimit,
            cityCenter: cityCenter,
            cityDiameterMeters: cityDiameterMeters,
            userCoordinate: userCoordinate,
            userDistrictLabel: userDistrictLabel,
            focusesUserLocation: focusesUserLocation,
            showsDistrictReference: showsDistrictReference
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let onSelectCourt: (String) -> Void
        private let onChooseCourt: ((String) -> Void)?
        private var lastCourtIDs: [String] = []
        private var lastOverlayIDs: [String] = []
        private var lastFocusSignature: String?
        private var lastCitySignature: String?
        private var hasSetVisibleRegion = false
        private var userAnnotation: SearchPreviewUserAnnotation?
        private var districtReferenceAnnotations: [DistrictReferenceAnnotation] = []
        private var lastUserSignature: String?
        private var usesDistrictReferenceStyle = false
        private var sourceCourtAnnotations: [String: SearchPreviewCourtAnnotation] = [:]
        private var displayedCourtAnnotations: [String: SearchPreviewCourtAnnotation] = [:]
        private var displayedAggregateAnnotations: [String: SearchClubAggregateAnnotation] = [:]

        init(onSelectCourt: @escaping (String) -> Void, onChooseCourt: ((String) -> Void)?) {
            self.onSelectCourt = onSelectCourt
            self.onChooseCourt = onChooseCourt
        }

        func update(
            mapView: MKMapView,
            courts: [Court],
            focusedCourt: Court?,
            focusedDistrictID: String?,
            highlightedDistrictIDs: [String],
            focusRevision: Int,
            annotationLimit: Int?,
            cityCenter: CLLocationCoordinate2D?,
            cityDiameterMeters: CLLocationDistance,
            userCoordinate: CLLocationCoordinate2D?,
            userDistrictLabel: String?,
            focusesUserLocation: Bool,
            showsDistrictReference: Bool
        ) {
            let normalizedHighlightIDs = Array(
                Set(highlightedDistrictIDs.map { $0.lowercased() })
            )
            .sorted()
            let visibleCourts: [Court]
            if let annotationLimit {
                let effectiveLimit = normalizedHighlightIDs.isEmpty ? annotationLimit : max(annotationLimit, 80)
                visibleCourts = Array(courts.prefix(effectiveLimit))
            } else {
                visibleCourts = courts
            }
            let courtIDs = visibleCourts.map(\.id)
            if courtIDs != lastCourtIDs {
                lastCourtIDs = courtIDs
                sourceCourtAnnotations = Dictionary(
                    uniqueKeysWithValues: visibleCourts.map { court in
                        (court.id, SearchPreviewCourtAnnotation(court: court))
                    }
                )
            }
            refreshDisplayedCourtAnnotations(on: mapView)

            updateUserAnnotation(
                mapView: mapView,
                coordinate: userCoordinate,
                districtLabel: userDistrictLabel
            )

            updateDistrictOverlays(
                mapView: mapView,
                districtIDs: normalizedHighlightIDs,
                showsDistrictReference: showsDistrictReference
            )

            let annotations = visibleCourts.compactMap { sourceCourtAnnotations[$0.id] }
            let focusedCourtID = focusedCourt?.id
            let normalizedDistrictID = focusedDistrictID?.lowercased()
            let citySignature = cityCenter.map { "\($0.latitude),\($0.longitude)" } ?? ""
            if citySignature != lastCitySignature {
                lastCitySignature = citySignature
                hasSetVisibleRegion = false
            }
            let focusSignature = [
                focusedCourtID ?? "",
                normalizedDistrictID ?? "",
                normalizedHighlightIDs.joined(separator: ","),
                focusesUserLocation ? "user" : "",
                showsDistrictReference ? "district-reference" : "",
                userCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "",
                citySignature,
                String(focusRevision)
            ].joined(separator: "|")

            if focusesUserLocation,
               showsDistrictReference,
               normalizedHighlightIDs.count == 1,
               let districtID = normalizedHighlightIDs.first,
               let area = districtAreasByID[districtID],
               focusSignature != lastFocusSignature {
                lastFocusSignature = focusSignature
                hasSetVisibleRegion = true
                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                mapView.setVisibleMapRect(
                    polygon.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 48, right: 20),
                    animated: true
                )
                return
            }

            if focusesUserLocation,
               let userCoordinate,
               focusSignature != lastFocusSignature {
                lastFocusSignature = focusSignature
                hasSetVisibleRegion = true
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: userCoordinate,
                        latitudinalMeters: 9_000,
                        longitudinalMeters: 9_000
                    ),
                    animated: true
                )
                return
            }

            if let focusedCourt, focusSignature != lastFocusSignature {
                lastFocusSignature = focusSignature
                hasSetVisibleRegion = true
                let region = MKCoordinateRegion(
                    center: focusedCourt.coordinate,
                    latitudinalMeters: 3_000,
                    longitudinalMeters: 3_000
                )
                mapView.setRegion(region, animated: true)
                return
            }

            if focusedCourt == nil,
               let normalizedDistrictID,
               let area = districtAreasByID[normalizedDistrictID],
               focusSignature != lastFocusSignature {
                lastFocusSignature = focusSignature
                hasSetVisibleRegion = true
                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                mapView.setVisibleMapRect(
                    polygon.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                    animated: true
                )
                return
            }

            if focusedCourt == nil,
               !normalizedHighlightIDs.isEmpty,
               focusSignature != lastFocusSignature {
                lastFocusSignature = focusSignature
                hasSetVisibleRegion = true
                let targetRect = targetVisibleRect(annotations: annotations, districtIDs: normalizedHighlightIDs)
                guard !targetRect.isNull, !targetRect.isEmpty else {
                    return
                }
                mapView.setVisibleMapRect(
                    targetRect,
                    edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                    animated: true
                )
                return
            }

            if focusedCourt == nil,
               annotations.isEmpty,
               let cityCenter,
               focusSignature != lastFocusSignature {
                lastFocusSignature = focusSignature
                hasSetVisibleRegion = true
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: cityCenter,
                        latitudinalMeters: cityDiameterMeters,
                        longitudinalMeters: cityDiameterMeters
                    ),
                    animated: true
                )
                return
            }

            if focusedCourt == nil,
               annotations.count == 1,
               let annotation = annotations.first,
               focusSignature != lastFocusSignature {
                lastFocusSignature = focusSignature
                hasSetVisibleRegion = true
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: annotation.coordinate,
                        latitudinalMeters: 12_000,
                        longitudinalMeters: 12_000
                    ),
                    animated: true
                )
                return
            }

            lastFocusSignature = focusSignature

            let targetRect = annotations
                .map { MKMapRect(origin: MKMapPoint($0.coordinate), size: MKMapSize(width: 0, height: 0)) }
                .reduce(MKMapRect.null) { partial, next in
                    partial.isNull ? next : partial.union(next)
                }

            guard !targetRect.isNull, !targetRect.isEmpty else {
                return
            }

            guard !hasSetVisibleRegion else {
                return
            }
            hasSetVisibleRegion = true
            mapView.setVisibleMapRect(targetRect, edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: false)
        }

        private func updateUserAnnotation(
            mapView: MKMapView,
            coordinate: CLLocationCoordinate2D?,
            districtLabel: String?
        ) {
            let signature = coordinate.map {
                "\($0.latitude),\($0.longitude)|\(districtLabel ?? "")"
            }
            guard signature != lastUserSignature else {
                return
            }
            lastUserSignature = signature

            if let userAnnotation {
                mapView.removeAnnotation(userAnnotation)
                self.userAnnotation = nil
            }

            guard let coordinate else {
                return
            }

            let annotation = SearchPreviewUserAnnotation(
                coordinate: coordinate,
                districtLabel: districtLabel
            )
            userAnnotation = annotation
            mapView.addAnnotation(annotation)
        }

        private func updateDistrictOverlays(
            mapView: MKMapView,
            districtIDs: [String],
            showsDistrictReference: Bool
        ) {
            guard districtIDs != lastOverlayIDs || showsDistrictReference != usesDistrictReferenceStyle else {
                return
            }

            lastOverlayIDs = districtIDs
            usesDistrictReferenceStyle = showsDistrictReference
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(districtReferenceAnnotations)
            districtReferenceAnnotations = []

            for districtID in districtIDs {
                guard let area = districtAreasByID[districtID] else {
                    continue
                }
                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                polygon.title = area.id
                mapView.addOverlay(polygon)

                if showsDistrictReference {
                    districtReferenceAnnotations.append(DistrictReferenceAnnotation(area: area))
                }
            }

            if !districtReferenceAnnotations.isEmpty {
                mapView.addAnnotations(districtReferenceAnnotations)
            }
        }

        private func targetVisibleRect(annotations: [SearchPreviewCourtAnnotation], districtIDs: [String]) -> MKMapRect {
            let annotationRects = annotations.map {
                MKMapRect(
                    origin: MKMapPoint($0.coordinate),
                    size: MKMapSize(width: 0, height: 0)
                )
            }

            let districtRects = districtIDs.compactMap { districtID -> MKMapRect? in
                guard let area = districtAreasByID[districtID] else {
                    return nil
                }
                var coordinates = area.coordinates
                let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                return polygon.boundingMapRect
            }

            return (annotationRects + districtRects).reduce(MKMapRect.null) { partial, next in
                partial.isNull ? next : partial.union(next)
            }
        }

        private func refreshDisplayedCourtAnnotations(on mapView: MKMapView) {
            guard !sourceCourtAnnotations.isEmpty else {
                let annotationsToRemove: [MKAnnotation] =
                    Array(displayedCourtAnnotations.values) + Array(displayedAggregateAnnotations.values)
                if !annotationsToRemove.isEmpty {
                    mapView.removeAnnotations(annotationsToRemove)
                }
                displayedCourtAnnotations = [:]
                displayedAggregateAnnotations = [:]
                return
            }

            let clusteringRadius: CGFloat = 52
            let visibleBounds = mapView.bounds.insetBy(dx: -clusteringRadius, dy: -clusteringRadius)
            let visibleAnnotations = sourceCourtAnnotations.values.filter { annotation in
                guard mapView.bounds.width > 0, mapView.bounds.height > 0 else {
                    return true
                }
                return visibleBounds.contains(mapView.convert(annotation.coordinate, toPointTo: mapView))
            }
            let components = screenSpaceComponents(
                annotations: visibleAnnotations,
                mapView: mapView,
                radius: clusteringRadius
            )

            var desiredCourts: [String: SearchPreviewCourtAnnotation] = [:]
            var desiredAggregates: [String: SearchClubAggregateAnnotation] = [:]

            for component in components {
                if component.count >= 6 {
                    let key = component.map(\.court.id).sorted().joined(separator: "|")
                    desiredAggregates[key] = displayedAggregateAnnotations[key]
                        ?? SearchClubAggregateAnnotation(members: component)
                } else {
                    for annotation in component {
                        desiredCourts[annotation.court.id] = annotation
                    }
                }
            }

            let annotationsToRemove: [MKAnnotation] =
                displayedCourtAnnotations
                    .filter { desiredCourts[$0.key] !== $0.value }
                    .map(\.value)
                + displayedAggregateAnnotations
                    .filter { desiredAggregates[$0.key] !== $0.value }
                    .map(\.value)

            let annotationsToAdd: [MKAnnotation] =
                desiredCourts
                    .filter { displayedCourtAnnotations[$0.key] !== $0.value }
                    .map(\.value)
                + desiredAggregates
                    .filter { displayedAggregateAnnotations[$0.key] !== $0.value }
                    .map(\.value)

            if !annotationsToRemove.isEmpty {
                mapView.removeAnnotations(annotationsToRemove)
            }
            if !annotationsToAdd.isEmpty {
                mapView.addAnnotations(annotationsToAdd)
            }

            displayedCourtAnnotations = desiredCourts
            displayedAggregateAnnotations = desiredAggregates
        }

        private func screenSpaceComponents(
            annotations: [SearchPreviewCourtAnnotation],
            mapView: MKMapView,
            radius: CGFloat
        ) -> [[SearchPreviewCourtAnnotation]] {
            let annotations = Array(annotations)
            let points = annotations.map { mapView.convert($0.coordinate, toPointTo: mapView) }
            let squaredRadius = radius * radius
            var visited = Array(repeating: false, count: annotations.count)
            var components: [[SearchPreviewCourtAnnotation]] = []

            for startIndex in annotations.indices where !visited[startIndex] {
                visited[startIndex] = true
                var pending = [startIndex]
                var component: [SearchPreviewCourtAnnotation] = []

                while let currentIndex = pending.popLast() {
                    component.append(annotations[currentIndex])
                    for candidateIndex in annotations.indices where !visited[candidateIndex] {
                        let deltaX = points[currentIndex].x - points[candidateIndex].x
                        let deltaY = points[currentIndex].y - points[candidateIndex].y
                        if deltaX * deltaX + deltaY * deltaY <= squaredRadius {
                            visited[candidateIndex] = true
                            pending.append(candidateIndex)
                        }
                    }
                }

                components.append(component)
            }

            return components
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon,
                  let overlayID = polygon.title ?? nil,
                  let area = districtAreasByID[overlayID] else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolygonRenderer(polygon: polygon)
            if usesDistrictReferenceStyle, lastOverlayIDs.contains(overlayID) {
                renderer.fillColor = UIColor(red: 0.01, green: 0.30, blue: 0.16, alpha: 0.44)
                renderer.strokeColor = UIColor(red: 0.19, green: 0.84, blue: 0.58, alpha: 1)
                renderer.lineWidth = 4.5
            } else {
                renderer.fillColor = area.color.withAlphaComponent(0.18)
                renderer.strokeColor = area.color.withAlphaComponent(0.78)
                renderer.lineWidth = 1.7
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is DistrictReferenceAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: DistrictReferenceAnnotationView.reuseID) as? DistrictReferenceAnnotationView)
                    ?? DistrictReferenceAnnotationView(annotation: annotation, reuseIdentifier: DistrictReferenceAnnotationView.reuseID)
                view.annotation = annotation
                return view
            }

            if annotation is SearchPreviewUserAnnotation {
                let reuseID = "SearchPreviewUserAnnotation"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                view.annotation = annotation
                view.markerTintColor = UIColor(red: 0.18, green: 0.84, blue: 0.58, alpha: 1)
                view.glyphImage = UIImage(systemName: "person.fill")
                view.glyphTintColor = .black
                view.canShowCallout = true
                view.displayPriority = .required
                view.zPriority = .max
                view.clusteringIdentifier = nil
                return view
            }

            if let cluster = annotation as? SearchClubAggregateAnnotation {
                let reuseID = "SearchClubClusterAnnotation"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: reuseID)
                view.annotation = cluster
                view.markerTintColor = UIColor(red: 0.10, green: 0.58, blue: 0.40, alpha: 1)
                view.glyphText = "\(cluster.members.count)"
                view.glyphTintColor = .white
                view.canShowCallout = false
                view.displayPriority = .required
                view.zPriority = .max
                view.clusteringIdentifier = nil
                return view
            }

            guard let annotation = annotation as? SearchPreviewCourtAnnotation else {
                return nil
            }

            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: SearchClubPickerAnnotationView.reuseID) as? SearchClubPickerAnnotationView)
                ?? SearchClubPickerAnnotationView(annotation: annotation, reuseIdentifier: SearchClubPickerAnnotationView.reuseID)
            view.annotation = annotation
            view.configure(court: annotation.court, showsCallout: onChooseCourt != nil)
            view.zPriority = .defaultSelected
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? SearchClubAggregateAnnotation {
                let targetRect = cluster.members
                    .map {
                        MKMapRect(
                            origin: MKMapPoint($0.coordinate),
                            size: MKMapSize(width: 0, height: 0)
                        )
                    }
                    .reduce(MKMapRect.null) { partial, next in
                        partial.isNull ? next : partial.union(next)
                    }
                guard !targetRect.isNull else {
                    return
                }
                let minimumMapPoints = 1_500 / MKMetersPerMapPointAtLatitude(cluster.coordinate.latitude)
                let zoomRect = MKMapRect(
                    x: targetRect.midX - max(targetRect.width, minimumMapPoints) / 2,
                    y: targetRect.midY - max(targetRect.height, minimumMapPoints) / 2,
                    width: max(targetRect.width, minimumMapPoints),
                    height: max(targetRect.height, minimumMapPoints)
                )
                mapView.setVisibleMapRect(
                    zoomRect,
                    edgePadding: UIEdgeInsets(top: 64, left: 64, bottom: 64, right: 64),
                    animated: true
                )
                return
            }

            guard let annotation = annotation as? SearchPreviewCourtAnnotation else {
                return
            }
            onSelectCourt(annotation.court.id)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let annotation = view.annotation as? SearchPreviewCourtAnnotation else {
                return
            }
            onChooseCourt?(annotation.court.id)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            refreshDisplayedCourtAnnotations(on: mapView)
        }
    }
}
