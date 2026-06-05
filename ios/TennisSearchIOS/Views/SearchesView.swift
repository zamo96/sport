import SwiftUI
import UIKit
import MapKit

struct SearchesView: View {
    @Environment(\.dismiss) private var dismiss
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
    let openedFromDiscover: Bool

    init(openedFromDiscover: Bool = false) {
        self.openedFromDiscover = openedFromDiscover
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    searchesHeader
                    summaryStrip
                    filterRail

                    if filteredSearches.isEmpty {
                        SectionCard(title: "Пока пусто", subtitle: "Создай первый поиск, чтобы получать отклики игроков.") {
                            EmptyStateView(
                                title: "Нет поисков в этом разделе",
                                subtitle: "Попробуй другой фильтр или создай новый поиск.",
                                systemImage: "sportscourt"
                            )
                        }
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
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(backToDiscoverSwipe)
        .task {
            await loadSearches()
        }
        .refreshable {
            await loadSearches()
        }
        .sheet(isPresented: $isPresentingComposer) {
            SearchComposerView { created in
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
        searches.filter { ($0.isActive ?? true) && $0.status != "matched" && $0.status != "closed" }.count
    }

    private var pendingResponsesCount: Int {
        searches.reduce(into: 0) { count, search in
            guard isSearchCountedInSummary(search) else {
                return
            }
            count += search.responses.filter { $0.status == "pending" }.count
        }
    }

    private var nextUpcomingLine: String {
        let candidates = searches.compactMap(nextEventDate(for:))
        guard let next = candidates.sorted().first else {
            return "Пока нет"
        }
        return next.formattedShortRelative()
    }

    private var filteredSearches: [GameSearch] {
        switch selectedFilter {
        case .all:
            return searches
        case .active:
            return searches.filter { ($0.isActive ?? true) && $0.status != "matched" && $0.status != "closed" }
        case .withResponses:
            return searches.filter { !$0.responses.isEmpty }
        case .paused:
            return searches.filter { !($0.isActive ?? true) && $0.status != "closed" }
        case .completed:
            return searches.filter { $0.status == "matched" || $0.status == "closed" }
        }
    }

    private var allSearchSections: [SearchSectionModel] {
        let active = searches.filter { ($0.isActive ?? true) && $0.status != "matched" && $0.status != "closed" }
        let paused = searches.filter { !($0.isActive ?? true) && $0.status != "closed" }
        let completed = searches.filter { $0.status == "matched" || $0.status == "closed" }

        return [
            SearchSectionModel(id: "active", title: "Активные", subtitle: "Поиски, которые сейчас видят игроки.", searches: active),
            SearchSectionModel(id: "paused", title: "Остановлены", subtitle: "Эти поиски сняты с показа и ждут перезапуска.", searches: paused),
            SearchSectionModel(id: "completed", title: "Завершены", subtitle: "Игроки найдены или поиск уже закрыт.", searches: completed)
        ]
        .filter { !$0.searches.isEmpty }
    }

    private func isSearchCountedInSummary(_ search: GameSearch) -> Bool {
        let status = search.status.lowercased()
        guard (search.isActive ?? true),
              !["matched", "closed", "canceled", "cancelled", "expired"].contains(status) else {
            return false
        }
        return true
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
        SearchOverviewCard(
            search: search,
            updatingResponseID: updatingResponseID,
            updatingSearchID: updatingSearchID,
            onUpdateResponseStatus: updateResponseStatus,
            onUpdateRegularOccurrence: updateRegularOccurrence,
            onOpenLobby: {
                presentedSearchLobbyID = search.id
            },
            onOpenDetails: {
                presentedSearch = search
            },
            onEdit: {
                isPresentingComposer = false
                editingSearch = search
            },
            onToggleActive: { isActive in
                await setSearchActive(searchId: search.id, isActive: isActive)
            },
            onReload: {
                await loadSearches()
            }
        )
    }

    private var searchesHeader: some View {
        HStack(alignment: .center) {
            Text("Мои поиски")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Button {
                triggerCreateComposerFeedback()
                editingSearch = nil
                isPresentingComposer = true
            } label: {
                HStack(spacing: 10) {
                    Text("Создать поиск")
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .scaleEffect(createButtonPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: createButtonPressed)
            .buttonStyle(.plain)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(title: "Активные поиски", value: "\(activeSearchCount)", accent: AppTheme.court, systemImage: "waveform.path.ecg")
            Divider()
                .frame(height: 44)
            summaryCell(title: "Новые отклики", value: "\(pendingResponsesCount)", accent: .red.opacity(0.9), systemImage: "person.2")
            Divider()
                .frame(height: 44)
            summaryCell(title: "Ближайшая игра", value: nextUpcomingLine, accent: AppTheme.court, systemImage: "clock")
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
        do {
            searches = try await appModel.repository.fetchSearches()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
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
        case .all: return "Все"
        case .active: return "Активные"
        case .withResponses: return "С откликами"
        case .paused: return "На паузе"
        case .completed: return "Завершённые"
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
        case .all: return "Все"
        case .pending: return "Новые"
        case .approved: return "Одобрены"
        case .rejected: return "Отклонены"
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
    let updatingResponseID: String?
    let updatingSearchID: String?
    let onUpdateResponseStatus: (String, String) async -> Void
    let onUpdateRegularOccurrence: (String, String, String?, Date?, String?) async -> Void
    let onOpenLobby: () -> Void
    let onOpenDetails: () -> Void
    let onEdit: () -> Void
    let onToggleActive: (Bool) async -> Void
    let onReload: () async -> Void

    private var pendingResponses: [SearchResponse] {
        search.responses.filter { $0.status == "pending" }
    }

    private var approvedResponses: [SearchResponse] {
        search.responses.filter { $0.status == "approved" }
    }

    private var remainingSeats: Int {
        max(search.playersNeeded - approvedResponses.count, 0)
    }

    private var rejectedResponses: [SearchResponse] {
        search.responses.filter { $0.status == "rejected" }
    }

    private var withdrawnResponses: [SearchResponse] {
        search.responses.filter { $0.status == "withdrawn" }
    }

    private var visibleResponses: [SearchResponse] {
        Array((approvedResponses + pendingResponses + rejectedResponses + withdrawnResponses).prefix(4))
    }

    private var totalVisiblePlayerCount: Int {
        max(search.playersNeeded, approvedResponses.count)
    }

    private var headlineText: String {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return "Игра собрана"
        }

        if let min = search.desiredLevelMin, let max = search.desiredLevelMax {
            return "Ищу \(playerNoun(count: search.playersNeeded)) уровня \(min)–\(max)"
        }

        return "Ищу \(playerNoun(count: search.playersNeeded))"
    }

    private var scheduleText: String {
        if search.searchType == .hot {
            return [search.hotWindow?.title, search.hotStartsAt?.formattedDateTime()]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        let parts = [
            search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.prefix(2).joined(separator: ", "),
            search.preferredTimeRanges.compactMap { TimeRange(rawValue: $0)?.title }.prefix(2).joined(separator: ", ")
        ]
        .filter { !$0.isEmpty }

        return parts.joined(separator: " · ")
    }

    private var areaText: String {
        if let district = search.preferredDistricts.first {
            return localizedDistrictName(district) ?? district
        }
        return "Любой район"
    }

    private var courtText: String {
        search.preferredCourt?.name ?? "Без клуба"
    }

    private var responseSummaryTitle: String {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            let count = max(totalVisiblePlayerCount, approvedResponses.count)
            return "\(count) \(peopleWord(count))"
        }

        return remainingSeats == 0 ? "Состав собран" : "Осталось \(remainingSeats)"
    }

    private var responseSummarySubtitle: String {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return "Все подтвердили"
        }

        return pendingResponses.isEmpty
            ? "\(search.responses.count) \(responseWord(search.responses.count))"
            : "\(pendingResponses.count) новых"
    }

    private var cardStatusTitle: String {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return "Собрано"
        }
        if !(search.isActive ?? true) {
            return "Остановлен"
        }
        if !pendingResponses.isEmpty {
            return "Есть отклики"
        }
        return "Активен"
    }

    private var cardStatusTint: Color {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
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
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return Color.blue.opacity(0.9)
        }
        if !(search.isActive ?? true) {
            return AppTheme.ink.opacity(0.72)
        }
        return AppTheme.court
    }

    private var primaryActionTitle: String {
        if !search.responses.isEmpty {
            return "Отклики"
        }
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return "Открыть"
        }
        return "Детали"
    }

    private var primaryActionTint: Color {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return Color.blue.opacity(0.85)
        }
        return AppTheme.court
    }

    private var cardAccentColor: Color {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Circle()
                    .fill(sportTint.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: sportIconName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(sportTint)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(search.sport.title) · \(search.sport.formatTitle(format: search.format, playersNeeded: search.playersNeeded))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.88))
                        .lineLimit(1)
                }

                Spacer()

                AppInlineChip(text: cardStatusTitle, tint: cardStatusTint, foreground: cardStatusForeground)

                Button(action: onOpenDetails) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink.opacity(0.74))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            Text(headlineText)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 8) {
                if search.searchType == .hot {
                    HStack(spacing: 12) {
                        hotSearchMetaPill(systemImage: "flame.fill", text: "Срочно")
                        hotSearchMetaPill(systemImage: "clock.fill", text: hotCardTimeText)
                    }
                } else {
                    HStack(spacing: 12) {
                        cardMeta(systemImage: "calendar", text: search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.prefix(2).joined(separator: ", "))
                        cardMeta(systemImage: "clock", text: search.preferredTimeRanges.compactMap { TimeRange(rawValue: $0)?.title }.prefix(1).joined(separator: ", "))
                    }
                }
                HStack(spacing: 12) {
                    cardMeta(systemImage: "location", text: areaText)
                    cardMeta(systemImage: "building.2", text: courtText)
                }
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

                Button(action: onOpenDetails) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(responseSummaryTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(responseSummarySubtitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(responseSummarySubtitle.contains("нов") ? .red.opacity(0.9) : AppTheme.ink.opacity(0.48))
                    }
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(0.3))
            }

            HStack(spacing: 10) {
                Button(action: onOpenDetails) {
                    Label(primaryActionTitle, systemImage: primaryActionTitle == "Отклики" ? "person.crop.circle.badge.checkmark" : "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(primaryActionTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(action: onEdit) {
                    Label("Изм.", systemImage: "pencil")
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
                        Label((search.isActive ?? true) ? "Остановить" : "Возобновить", systemImage: (search.isActive ?? true) ? "pause.fill" : "play.fill")
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
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardAccentColor.opacity(0.28), lineWidth: 1.2)
        )
        .shadow(color: AppTheme.ink.opacity(0.04), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpenDetails)
    }

    private var sportIconName: String {
        switch search.sport {
        case .tableTennis: return "circle.grid.cross"
        case .tennis: return "tennis.racket"
        case .padel: return "sportscourt"
        case .squash: return "figure.racquetball"
        case .badminton: return "bird"
        case .volleyball: return "volleyball"
        case .fitness: return "dumbbell"
        case .boxing: return "figure.boxing"
        case .yoga: return "figure.mind.and.body"
        case .football: return "soccerball"
        }
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
        return search.hotStartsAt?.formattedDateTime() ?? "Время не указано"
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

    private var parameterRows: [(icon: String, title: String, value: String)] {
        var rows: [(String, String, String)] = []

        rows.append(("sportscourt", "Формат игры", search.sport.formatTitle(format: search.format, playersNeeded: search.playersNeeded)))
        rows.append(("person.2", "Нужно игроков", remainingSeats == 0 ? "\(search.playersNeeded) · состав собран" : "\(search.playersNeeded) · осталось \(remainingSeats)"))

        if let min = search.desiredLevelMin, let max = search.desiredLevelMax {
            rows.append(("chart.bar.xaxis", "Уровень", "\(min)–\(max)"))
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
                search.preferredTimeRanges.compactMap { TimeRange(rawValue: $0)?.title }.joined(separator: ", ")
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        }
        if !schedule.isEmpty {
            rows.append(("clock", "Время", schedule))
        }

        let districts = search.preferredDistricts.compactMap(localizedDistrictName).joined(separator: ", ")
        if !districts.isEmpty {
            rows.append(("map", "Районы", districts))
        }

        rows.append(("building.2", "Корт / клуб", search.preferredCourt?.name ?? "Не указан"))
        rows.append(("bubble.left", "Комментарий", (search.comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? search.comment! : "Не указан")))
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
                            title: "Регулярные слоты",
                            subtitle: "Подтверждай ближайшие слоты и открывай чат пары."
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

                    Button {
                        Task { await toggleSearchActive() }
                    } label: {
                        if updatingSearchID == search.id {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        } else {
                            Label((search.isActive ?? true) ? "Остановить поиск" : "Запустить поиск", systemImage: (search.isActive ?? true) ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(SecondaryActionButtonStyle(tint: .red.opacity(0.88)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Поиск игры")
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
                    onShareInviteLink: shareInviteLink
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
                        Image(systemName: detailSportIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
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
                    text: (search.isActive ?? true) ? "Активен" : "На паузе",
                    tint: .white.opacity(0.18),
                    foreground: .white
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    detailMetaRow(icon: "calendar", text: search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.joined(separator: ", "))
                    detailMetaRow(icon: "clock", text: search.preferredTimeRanges.compactMap { TimeRange(rawValue: $0)?.detailTitle }.joined(separator: " · "))
                }
                HStack(spacing: 12) {
                    detailMetaRow(icon: "map", text: search.preferredDistricts.compactMap(localizedDistrictName).joined(separator: ", "))
                    detailMetaRow(icon: "building.2", text: search.preferredCourt?.name ?? "Без клуба")
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
                        Text("\(search.responses.count) откликов")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        if !pendingResponses.isEmpty {
                            Text("· \(pendingResponses.count) новых")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.red.opacity(0.9))
                        }
                    }
                    Text("Откликнувшиеся игроки по этому поиску")
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
                Label("Отклики", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(AppTheme.court, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                onEdit(search)
            } label: {
                Label("Изменить", systemImage: "pencil")
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
                Label((search.isActive ?? true) ? "Пауза" : "Запуск", systemImage: (search.isActive ?? true) ? "pause.fill" : "play.fill")
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

    private var parameterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Параметры")
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
            Text("Ссылка-приглашение")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Text("Делитесь ссылкой, чтобы игроки могли откликнуться")
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.58))

            HStack(spacing: 10) {
                Text(AppConfig.searchInviteURL(searchId: search.inviteSlug ?? search.id)?.absoluteString ?? "Ссылка недоступна")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.court)
                    .lineLimit(1)

                Spacer()

                Button {
                    copyInviteLink()
                } label: {
                    HStack(spacing: 6) {
                        if didCopyInviteLink {
                            Text("Скопировано")
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
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Предложите время для игры")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Открой общий состав, чтобы отправить слоты на подтверждение и обсудить детали игры.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.62))
                }
            }

            Button {
                onOpenLobby(search.id)
            } label: {
                Text("Предложить слоты")
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
        switch search.sport {
        case .tableTennis: return "circle.grid.cross"
        case .tennis: return "tennis.racket"
        case .padel: return "sportscourt"
        case .squash: return "figure.racquetball"
        case .badminton: return "bird"
        case .volleyball: return "volleyball"
        case .fitness: return "dumbbell"
        case .boxing: return "figure.boxing"
        case .yoga: return "figure.mind.and.body"
        case .football: return "soccerball"
        }
    }

    private var detailHeadline: String {
        if search.status == "matched" || approvedResponses.count >= max(search.playersNeeded, 1) {
            return "Состав собран"
        }
        if let min = search.desiredLevelMin, let max = search.desiredLevelMax {
            return "Ищу \(search.playersNeeded) игроков уровня \(min)–\(max)"
        }
        return "Ищу \(search.playersNeeded) игроков"
    }

    private func detailMetaRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(text.isEmpty ? "Не указано" : text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareInviteLink() {
        guard let inviteURL = AppConfig.searchInviteURL(searchId: search.inviteSlug ?? search.id) else {
            appModel.errorMessage = "Не удалось подготовить ссылку приглашения"
            return
        }
        AppHaptics.selection()
        shareItems = ["Присоединяйся к моему поиску игры в TennisSearch", inviteURL]
    }

    private func copyInviteLink() {
        guard let inviteURL = AppConfig.searchInviteURL(searchId: search.inviteSlug ?? search.id) else {
            appModel.errorMessage = "Не удалось подготовить ссылку приглашения"
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

    @State private var selectedFilter: SearchResponsesFilter = .all

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

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    searchSummaryCard
                    responsesFilterRail

                    ForEach(filteredResponses) { response in
                        SearchResponseActionRow(
                            response: response,
                            updatingResponseID: updatingResponseID,
                            onUpdateResponseStatus: onUpdateResponseStatus
                        )
                    }

                    Button {
                        onShareInviteLink()
                    } label: {
                        Label("Пригласить ещё игроков", systemImage: "person.badge.plus")
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
            .navigationTitle("Отклики")
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
                        text: "\(search.responses.count) откликов · \(search.responses.filter { $0.status == "pending" }.count) новых",
                        tint: AppTheme.mint,
                        foreground: AppTheme.court
                    )
                }
            }
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
                    Text(search.desiredLevelMin != nil && search.desiredLevelMax != nil ? "Ищу \(search.playersNeeded) игроков уровня \(search.desiredLevelMin!)–\(search.desiredLevelMax!)" : "Ищу \(search.playersNeeded) игроков")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 16) {
                compactMetaRow(icon: "calendar", text: search.preferredDays.compactMap { DayOfWeek(rawValue: $0)?.shortTitle }.joined(separator: ", "))
                compactMetaRow(icon: "clock", text: search.preferredTimeRanges.compactMap { TimeRange(rawValue: $0)?.detailTitle }.joined(separator: " · "))
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
            Text(text.isEmpty ? "Не указано" : text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.ink.opacity(0.82))
                .lineLimit(2)
        }
    }
}

private struct SearchResponseActionRow: View {
    let response: SearchResponse
    let updatingResponseID: String?
    let onUpdateResponseStatus: (String, String) async -> Void

    private var levelLine: String? {
        if let level = response.responderUser.sportLevels["tennis"] ?? response.responderUser.tennisLevel {
            return String(format: "%.1f", Double(level))
        }
        return nil
    }

    var body: some View {
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

            if response.status == "pending" {
                HStack(spacing: 10) {
                    circleAction(systemImage: "checkmark", tint: AppTheme.court, foreground: .white, status: "approved")
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
            return "Игрок уже в составе"
        case "rejected":
            return "Отклик был отклонён"
        default:
            return "Хочет присоединиться к игре"
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch response.status {
        case "approved":
            AppInlineChip(text: "ОДОБРЕН", tint: AppTheme.mint, foreground: AppTheme.court)
        case "rejected":
            AppInlineChip(text: "ОТКЛОНЁН", tint: Color.red.opacity(0.12), foreground: .red.opacity(0.9))
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
            return "Утро"
        case .day:
            return "День"
        case .evening:
            return "Вечер (после 18:00)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == GameSearch {
    func applying(responseUpdate result: SearchResponseUpdateResult) -> [GameSearch] {
        map { $0.applying(responseUpdate: result) }
    }
}

private extension GameSearch {
    func applying(responseUpdate result: SearchResponseUpdateResult) -> GameSearch {
        guard responses.contains(where: { $0.id == result.response.id }) || result.gameSearch?.id == id else {
            return self
        }

        let patchedResponse = SearchResponse(
            id: result.response.id,
            status: result.response.status,
            responderUser: result.response.responderUser,
            matchId: result.response.matchId ?? result.matchId
        )
        let nextResponses = responses.map { response in
            response.id == patchedResponse.id ? patchedResponse : response
        }
        let nextStatus: String
        let nextIsActive: Bool?
        if let searchUpdate = result.gameSearch, searchUpdate.id == id {
            nextStatus = searchUpdate.status
            nextIsActive = searchUpdate.isActive == nil ? isActive : searchUpdate.isActive
        } else {
            nextStatus = status
            nextIsActive = isActive
        }

        return GameSearch(
            id: id,
            inviteSlug: inviteSlug,
            status: nextStatus,
            searchType: searchType,
            hotWindow: hotWindow,
            hotStartsAt: hotStartsAt,
            durationMinutes: durationMinutes,
            hasCourtBooked: hasCourtBooked,
            sport: sport,
            selfLevel: selfLevel,
            selfLevelUnknown: selfLevelUnknown,
            desiredLevelMin: desiredLevelMin,
            desiredLevelMax: desiredLevelMax,
            format: format,
            playersNeeded: playersNeeded,
            preferredDays: preferredDays,
            preferredTimeRanges: preferredTimeRanges,
            comment: comment,
            isActive: nextIsActive,
            isExpired: isExpired,
            preferredCourt: preferredCourt,
            preferredDistricts: preferredDistricts,
            activeSlotProposal: activeSlotProposal,
            regularPair: regularPair,
            responses: nextResponses
        )
    }
}

private extension Date {
    func formattedShortRelative() -> String {
        if Calendar.current.isDateInToday(self) {
            return "Сегодня, \(formattedHourMinute())"
        }
        if Calendar.current.isDateInTomorrow(self) {
            return "Завтра, \(formattedHourMinute())"
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

struct SearchLobbySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let searchId: String

    @State private var lobby: SearchLobbyGameSearch?
    @State private var lobbyLoadError: String?
    @State private var courts: [Court] = []
    @State private var messageText = ""
    @State private var proposedCourtId = ""
    @State private var courtQuery = ""
    @State private var proposedAt = Date().addingTimeInterval(24 * 60 * 60)
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

    private var approvedResponses: [SearchResponse] {
        lobby?.responses.filter { $0.status == "approved" } ?? []
    }

    private var pendingResponses: [SearchResponse] {
        lobby?.responses.filter { $0.status == "pending" } ?? []
    }

    private var isCreator: Bool {
        lobby?.createdByUserId == appModel.currentUser?.id
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

    private var dateOptions: [Date] {
        let calendar = Calendar.current
        let preferred = (lobby?.preferredDays ?? []).compactMap(DayOfWeek.init(rawValue:))
        var dates: [Date] = []
        for offset in 0 ..< 10 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            if preferred.isEmpty || preferred.contains(dayOfWeek(for: date)) {
                dates.append(calendar.startOfDay(for: date))
            }
            if dates.count == 5 {
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
        selectedSlotTimes.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let lobby {
                            SectionCard(
                                title: "Состав и общий чат",
                                subtitle: "Это общее пространство по этому поиску. Здесь видно состав и обсуждение до финальной игры."
                            ) {
                                HStack(spacing: 10) {
                                    AppInlineChip(
                                        text: "\(approvedResponses.count) из \(max(lobby.playersNeeded, 1)) подтверждено",
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
                            }

                            SectionCard(
                                title: "Участники",
                                subtitle: "Подтвержденные игроки уже в составе, ожидающие пока не приняты."
                            ) {
                                VStack(spacing: 10) {
                                    ForEach(approvedResponses) { response in
                                        lobbyParticipantRow(response: response, title: "В составе", tint: AppTheme.court)
                                    }

                                    ForEach(pendingResponses) { response in
                                        lobbyParticipantRow(response: response, title: "Ожидаем ответ", tint: Color(red: 1.0, green: 0.70, blue: 0.30))
                                    }
                                }
                            }

                            if isCreator, !approvedResponses.isEmpty {
                                slotProposalSection(lobby: lobby)
                            } else if let activeSlotProposal = lobby.activeSlotProposal {
                                slotVotingSection(activeSlotProposal)
                            }

                            SectionCard(
                                title: "Общий чат",
                                subtitle: "Здесь удобно договориться по составу, району и ожиданиям до финальной игры."
                            ) {
                                VStack(spacing: 10) {
                                    ForEach(lobby.messages) { message in
                                        searchLobbyBubble(message: message)
                                    }
                                }

                                HStack(alignment: .bottom, spacing: 10) {
                                    FieldShell {
                                        TextField("Сообщение для состава...", text: $messageText, axis: .vertical)
                                            .lineLimit(1 ... 4)
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
                                    .disabled(isSendingMessage || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        } else if let lobbyLoadError {
                            SectionCard(title: "Состав и общий чат", subtitle: "Не удалось загрузить детали поиска.") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(lobbyLoadError)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.ink.opacity(0.68))

                                    Button {
                                        Task {
                                            await loadLobby()
                                        }
                                    } label: {
                                        Label("Повторить", systemImage: "arrow.clockwise")
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
                            SectionCard(title: "Состав и общий чат", subtitle: "Загружаем детали поиска.") {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 24)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Лобби поиска")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadLobby()
                await loadLobbyCourts()
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
                            "Дата игры",
                            selection: Binding(
                                get: { proposedAt },
                                set: { proposedAt = $0 }
                            ),
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()

                        Button("Готово") {
                            isDatePickerPresented = false
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                    }
                    .padding(20)
                    .background(Color.white.ignoresSafeArea())
                    .navigationTitle("Выбрать дату")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Закрыть") {
                                isDatePickerPresented = false
                            }
                            .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
            }
        }
    }

    private func loadLobby() async {
        lobbyLoadError = nil

        do {
            let summary = try await appModel.repository.fetchSearchLobby(searchId: searchId)
            applyLobbySummary(summary)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            lobbyLoadError = error.detailedMessage
            appModel.present(error: error)
            return
        }
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

    private func applyLobbySummary(_ summary: SearchLobbySummary) {
        lobby = summary.gameSearch
        proposedCourtId = summary.gameSearch.scheduledCourt?.id ?? summary.gameSearch.preferredCourt?.id ?? ""
        proposedAt = summary.gameSearch.scheduledAt?.parsedISODateValue() ?? summary.gameSearch.hotStartsAt?.parsedISODateValue() ?? proposedAt
        durationMinutes = summary.gameSearch.scheduledDurationMinutes ?? summary.gameSearch.durationMinutes ?? 90
        if let preferredRange = summary.gameSearch.preferredTimeRanges.compactMap(TimeRange.init(rawValue:)).first {
            selectedSlotTimeRange = preferredRange
        }
        let proposedTime = proposedAt.formattedHourMinute()
        selectedSlotTimes = [
            Self.timeOptions(for: selectedSlotTimeRange).contains(proposedTime)
                ? proposedTime
                : (Self.timeOptions(for: selectedSlotTimeRange).first ?? "19:00")
        ]
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
            court.nearestMetroName,
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
                        courtMetaPill(systemImage: "tram.fill", text: court.nearestMetroName)
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
        guard !trimmed.isEmpty else {
            return
        }

        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            let message = try await appModel.repository.sendSearchLobbyMessage(searchId: searchId, text: trimmed)
            lobby = SearchLobbyGameSearch(
                id: lobby?.id ?? searchId,
                createdByUserId: lobby?.createdByUserId ?? appModel.currentUser?.id ?? "",
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
                messages: (lobby?.messages ?? []) + [message]
            )
            messageText = ""
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func scheduleSlot() async {
        let options = selectedSlotDraftOptions()
        guard !proposedCourtId.isEmpty, !options.isEmpty else {
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
        selectedSlotTimes
            .sorted()
            .compactMap { scheduledDate(for: $0) }
            .map {
                SearchSlotProposalDraftOption(
                    scheduledAt: $0,
                    proposedCourtId: proposedCourtId.isEmpty ? nil : proposedCourtId,
                    durationMinutes: durationMinutes
                )
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

    private func scheduledDate(for label: String) -> Date? {
        let components = label.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(
            bySettingHour: components.first ?? 19,
            minute: components.last ?? 0,
            second: 0,
            of: selectedDay
        )
    }

    private func lobbyParticipantRow(response: SearchResponse, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            RemoteAvatarView(name: response.responderUser.displayName, path: response.responderUser.avatarUrl, size: 40)
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

        return HStack {
            if isMine {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 6) {
                if !isMine {
                    Text(message.senderUser?.name ?? "Игрок")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isMine ? .white : AppTheme.ink)

                Text(message.createdAt.formattedDateTime())
                    .font(.caption2)
                    .foregroundStyle(isMine ? .white.opacity(0.72) : AppTheme.ink.opacity(0.42))
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

    @ViewBuilder
    private func slotProposalSection(lobby: SearchLobbyGameSearch) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .center, spacing: 4) {
                Text("Предложить слоты")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Выберите удобный вариант для подтвержденного состава")
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
                        Image(systemName: lobby.sport == .tennis ? "tennis.racket" : "sportscourt")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.court)
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
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDay)

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

            Text("Можно выбрать несколько вариантов")
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
                Text("Текущее голосование")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                AppInlineChip(text: "\(proposal.options.count) слота", tint: AppTheme.mint, foreground: AppTheme.court)
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
                                .lineLimit(1)
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
                Text("Выберите слоты")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Можно отметить несколько вариантов")
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
                    Text("Отправить выбор")
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
                    Text("Клуб")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.52))
                    Text(selectedCourtName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                }

                Spacer()

                Text("Выбрать")
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
            Text("Комментарий (необязательно)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            ZStack(alignment: .leading) {
                if slotComment.isEmpty {
                    Text("Например: корт с крышей желателен")
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
                    Text("Предложить \(selectedSlotCount) \(slotWord(selectedSlotCount))")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(isScheduling || proposedCourtId.isEmpty || selectedSlotTimes.isEmpty)

            Text("Игроки смогут проголосовать")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var selectedCourtName: String {
        availableCourts.first(where: { $0.id == proposedCourtId })?.name ?? (lobby?.preferredCourt?.name ?? "Выбрать клуб")
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
            return "Ищу \(lobby.playersNeeded) игроков уровня \(min)–\(max)"
        }
        return "Ищу \(lobby.playersNeeded) игроков"
    }

    private func updateSelectedDate(_ date: Date) {
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
                    Text("Регулярная пара активна")
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
                .accessibilityLabel("Открыть чат")
            }

            if visibleOccurrences.isEmpty {
                Text("Пара создана, но ближайшие слоты пока не появились. Проверь дни и время в параметрах поиска.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Ближайшие слоты")
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
                        Text("Ещё \(upcomingOccurrences.count - visibleOccurrences.count) слота доступны в регулярной паре.")
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
            return ("Подтверждено", AppTheme.court, AppTheme.mint)
        case "declined":
            if let currentUserId, declinedUserId == currentUserId {
                return ("Ты отказался", .red.opacity(0.9), Color.red.opacity(0.12))
            }
            return ("Партнер не может", .red.opacity(0.9), Color.red.opacity(0.12))
        case "canceled", "cancelled":
            return ("Отменено", AppTheme.ink.opacity(0.72), Color.gray.opacity(0.18))
        case "expired":
            return ("Уже прошло", AppTheme.ink.opacity(0.72), Color.gray.opacity(0.18))
        default:
            return ("Ждет подтверждения", AppTheme.ink, AppTheme.cream)
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
                .accessibilityLabel("Изменить дату, время или клуб")
            }

            HStack(spacing: 8) {
                confirmationPill(title: "Ты", value: myConfirmationLabel, valueColor: confirmationColor(for: currentUserId))
                confirmationPill(title: "Партнер", value: partnerConfirmationLabel, valueColor: confirmationColor(for: partnerUserId))
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
            return "Ждет подтверждения"
        }

        let status = occurrence.confirmations.first(where: { $0.user.id == userId })?.status.lowercased()
        switch status {
        case "confirmed":
            return "Подтверждено"
        case "declined":
            return "Не смогу"
        default:
            return "Ждет подтверждения"
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
        _isExpanded = State(initialValue: !responses.isEmpty && (title == "Хочет присоединиться" || title == "В составе"))
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
                    actionButton(title: "Принять", tint: AppTheme.court, status: "approved")
                    actionButton(title: "Отклонить", tint: .red, status: "rejected", secondary: true)
                }
            } else if response.status == "approved" {
                actionButton(title: "Убрать из состава", tint: .red, status: "rejected", secondary: true)
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
            return "Подтвержден"
        case "rejected":
            return "Отклонен"
        case "withdrawn":
            return "Отменил сам"
        default:
            return "Ожидаем ответ"
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
                        text: isOpen ? "Открыт" : statusTitle,
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
        }
    }
}

private struct SearchComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    @State private var courts: [Court] = []
    @State private var courtQuery = ""
    @State private var draft = SearchDraft(
        inviteSlug: nil,
        preferredCourtId: nil,
        preferredDistricts: [],
        preferredDays: ["wednesday", "saturday"],
        preferredTimeRanges: ["evening"],
        searchType: .regular,
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
    @State private var isSavingSearch = false
    @State private var isRocketLaunchPresented = false
    @State private var submitButtonPressed = false
    @State private var hotStep: HotSearchStep = .when
    @State private var didInitializeComposer = false
    @State private var selectedSport: Sport = .tennis
    @State private var selectedCourtId: String?
    @State private var selectedCourtSnapshot: Court?

    let initialSearch: GameSearch?
    let onCreate: (GameSearch) -> Void

    init(initialSearch: GameSearch? = nil, onCreate: @escaping (GameSearch) -> Void) {
        self.initialSearch = initialSearch
        self.onCreate = onCreate
    }

    private var availableSports: [Sport] {
        let preferred = appModel.currentUser?.preferredSports ?? []
        let fallback = Sport.defaultAuthSports + Sport.allCases
        var ordered = preferred + fallback
        var seen = Set<String>()
        ordered.removeAll { sport in
            let inserted = seen.insert(sport.rawValue).inserted
            return !inserted
        }
        return ordered
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
            return ("Начальный", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)")
        case 3 ... 4:
            return ("Базовый", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)")
        case 5 ... 6:
            return ("Средний", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)")
        case 7 ... 8:
            return ("Продвинутый", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)")
        default:
            return ("Сильный", "Ищем игроков \(draft.desiredLevelMin)-\(draft.desiredLevelMax)")
        }
    }

    private var locationTitle: String {
        selectedCourt?.name ?? (draft.preferredDistricts.isEmpty ? "Без привязки" : districtsSummary)
    }

    private var locationSubtitle: String {
        if let selectedCourt {
            return [selectedCourt.nearestMetroName, localizedDistrictName(selectedCourt.district), selectedCourt.address]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        return draft.preferredDistricts.isEmpty ? "Покажем клубы рядом" : "Будем искать в выбранных районах"
    }

    private var districtsSummary: String {
        let names = draft.preferredDistricts.compactMap(localizedDistrictName)
        return names.isEmpty ? "Будем показывать клубы поблизости" : names.prefix(3).joined(separator: ", ")
    }

    private var shouldApplyPreferredSportOnFirstLoad: Bool {
        selectedSport == .tennis
            && selectedCourtId == nil
            && draft.preferredDistricts.isEmpty
            && draft.searchType == .regular
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
                        inviteBanner
                        searchTypeModeSwitch
                        if draft.searchType == .hot {
                            urgentSearchProgressHeader
                            hotStepContent
                            hotStepActions
                        } else {
                            sportRailSection
                            formatSection
                            compactStatsSection
                            scheduleSection
                            mapPreviewSection
                            commentSection
                            submitSection
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }

                if isRocketLaunchPresented {
                    RocketLaunchOverlay()
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
                            clearDistrictsWhenNil: true,
                            markBooked: draft.searchType == .hot
                        )
                    }
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
            .task {
                guard !didInitializeComposer else {
                    return
                }
                didInitializeComposer = true

                do {
                    if initialSearch == nil, draft.inviteSlug == nil {
                        draft.inviteSlug = UUID().uuidString.lowercased()
                    }
                    courts = try await appModel.repository.fetchCourts()
                    if let initialSearch {
                        apply(initialSearch)
                    }
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
        .onChange(of: draft.searchType) { nextType in
            if nextType == .hot {
                hotStep = .when
                if (draft.hotStartTime ?? "").isEmpty {
                    draft.hotStartTime = hotQuickTimes.first ?? "00:00"
                }
            }
        }
        .onChange(of: draft.hotWindow) { _ in
            let availableTimes = hotQuickTimes
            guard !availableTimes.isEmpty else {
                draft.hotStartTime = nil
                return
            }

            if let selectedTime = draft.hotStartTime, availableTimes.contains(selectedTime) {
                return
            }
            draft.hotStartTime = availableTimes.first
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

            Text(initialSearch == nil ? "Найти партнёров" : "Изменить поиск")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Button {
                isAdvancedPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.04), in: Circle())
            }
            .buttonStyle(.plain)
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
                Text("Быстрее с друзьями")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Пригласите друзей и собирайте игры чаще")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.64))
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            if let inviteURL = resolvedInviteURL {
                ShareLink(item: inviteURL) {
                    Text("Пригласить")
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
                Text("Пригласить")
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
            searchTypeButton(type: .regular, systemImage: "calendar", title: "Обычный")
            searchTypeButton(type: .hot, systemImage: "rocket", title: "Срочный")
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
                Text("Срочный поиск")
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
                formatSection
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
                Button("Назад") {
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
                    Text(hotStep == .confirm ? "Опубликовать срочно" : "Продолжить")
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
                Text("Что ищем?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("Выбрать вид спорта")
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
                                Image(systemName: sportIconName(for: sport))
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(isSelected ? AppTheme.court : AppTheme.ink.opacity(0.92))
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
            Text("Формат игры")
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
                Text("Нужно игроков")
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
                    ForEach(0 ..< min(max(draft.playersNeeded, 1), 3), id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? AppTheme.clay.opacity(0.9) : AppTheme.ink.opacity(0.18 + Double(index) * 0.08))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    Text(draft.playersNeeded == 1 ? "1 место открыто" : "\(draft.playersNeeded) места открыто")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.court)
                        .padding(.leading, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))

            VStack(alignment: .leading, spacing: 14) {
                Text("Уровень")
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

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Когда играть?")
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
                Text("Когда хотите сыграть?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Выберите день и удобное время")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }

            VStack(spacing: 10) {
                ForEach(HotWindow.allCases) { window in
                    hotWindowButton(window)
                }
            }

            Text("Во сколько?")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(hotQuickTimes, id: \.self) { time in
                        hotQuickTimeButton(time)
                    }
                }
            }

            FieldShell(title: "Длительность") {
                Stepper(value: Binding(
                    get: { draft.durationMinutes ?? selectedSport.defaultDurationMinutes },
                    set: { draft.durationMinutes = $0 }
                ), in: 30 ... 180, step: 30) {
                    Text("\(draft.durationMinutes ?? selectedSport.defaultDurationMinutes) мин")
                        .font(.headline)
                }
            }
        }
    }

    private var hotLocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Где играем?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Выберите район или клуб, если он уже забронирован")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }

            courtToggle
            mapPreviewSection
            hotDistrictRail
        }
    }

    @ViewBuilder
    private var hotDistrictRail: some View {
        if !availableDistricts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Районы")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        districtChip(title: "Любой", district: nil)
                        ForEach(availableDistricts.prefix(10), id: \.self) { district in
                            districtChip(title: prettifyDistrict(district), district: district)
                        }
                    }
                }
            }
        }
    }

    private var hotQuickTimes: [String] {
        let window = draft.hotWindow ?? .today
        let startMinutes: Int

        switch window {
        case .today:
            startMinutes = roundedUpMinutesFromNow()
        case .tomorrow, .dayAfterTomorrow:
            startMinutes = 0
        }

        let clampedStart = min(max(startMinutes, 0), 23 * 60 + 30)
        let allMinutes = stride(from: clampedStart, through: 23 * 60 + 30, by: 30)

        let times = allMinutes.map(Self.timeLabel(minutes:))
        return times.isEmpty ? [Self.timeLabel(minutes: clampedStart)] : times
    }

    private func hotWindowButton(_ window: HotWindow) -> some View {
        let selected = (draft.hotWindow ?? .today) == window

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                draft.hotWindow = window
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
                    selectPreferredCourt(
                        court,
                        markBooked: draft.searchType == .hot
                    )
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
                    Text(selectedCourt?.name ?? "Клубы и районы")
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
                Text("Комментарий (необязательно)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
                TextField("Например: хочу сыграть после 19:00", text: $draft.comment, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var urgentConfirmationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Проверьте и опубликуйте")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            VStack(spacing: 0) {
                urgentConfirmationRow(icon: "calendar", title: "Когда", value: "\(draft.hotWindow?.title ?? HotWindow.today.title), \(draft.hotStartTime ?? "19:00")")
                Divider()
                urgentConfirmationRow(icon: "tennis.racket", title: "Вид спорта", value: selectedSport.title)
                Divider()
                urgentConfirmationRow(icon: "person.2", title: "Формат", value: selectedSport.formatTitle(format: draft.format))
                Divider()
                urgentConfirmationRow(icon: "person.badge.plus", title: "Нужно игроков", value: "\(draft.playersNeeded)")
                Divider()
                urgentConfirmationRow(icon: "chart.bar", title: "Уровень", value: "\(draft.desiredLevelMin)-\(draft.desiredLevelMax)")
                Divider()
                urgentConfirmationRow(icon: "mappin.and.ellipse", title: "Место", value: locationTitle)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                Label("Больше шансов найти игрока", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.56, green: 0.32, blue: 0.05))

                HStack {
                    Label("Отправить push подходящим игрокам", systemImage: "clock.badge.checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .tint(AppTheme.court)
                        .disabled(true)
                }

                HStack {
                    Label("Показать выше в ленте", systemImage: "arrow.up.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .tint(AppTheme.court)
                        .disabled(true)
                }
            }
            .padding(14)
            .background(Color(red: 1.0, green: 0.97, blue: 0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.74, green: 0.54, blue: 0.22).opacity(0.18), lineWidth: 1)
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

            Text(draft.searchType == .hot ? "Поиск будет активен до начала игры" : "Партнёрам придёт уведомление о вашем запросе")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.38))
                .frame(maxWidth: .infinity)
        }
    }

    private var submitButtonTitle: String {
        if initialSearch != nil {
            return "Сохранить поиск"
        }
        return draft.searchType == .hot ? "Опубликовать срочно" : "Создать поиск"
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

    private func applySportSelection(_ sport: Sport) {
        guard selectedSport != sport else {
            return
        }

        AppHaptics.selection()
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
            }

            draft.preferredDistricts = draft.preferredDistricts.filter { validDistricts.contains($0) }
        }

        setSportLevel(appModel.currentUser?.sportLevels[sport.rawValue] ?? appModel.currentUser?.tennisLevel ?? 5, haptic: false)
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
        clearDistrictsWhenNil: Bool = false,
        markBooked: Bool = false
    ) {
        let currentSport = selectedSport

        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            selectedCourtSnapshot = court
            selectedCourtId = court?.id
            draft.preferredCourtId = court?.id
            if let court {
                if let district = court.district {
                    draft.preferredDistricts = [district] + draft.preferredDistricts.filter { $0 != district }
                }

                if markBooked {
                    draft.hasCourtBooked = true
                }
            } else if clearDistrictsWhenNil {
                draft.preferredDistricts.removeAll()
            }
            draft.sport = currentSport
        }
    }

    private func formatTitle(for format: PlayFormat) -> String {
        switch format {
        case .singles:
            return "Одиночная"
        case .doubles:
            return "Парная"
        case .both:
            return "Любой"
        }
    }

    private func sportIconName(for sport: Sport) -> String {
        switch sport {
        case .tableTennis: return "circle.grid.cross"
        case .tennis: return "tennis.racket"
        case .padel: return "sportscourt"
        case .squash: return "figure.racquetball"
        case .badminton: return "bird"
        case .volleyball: return "volleyball"
        case .fitness: return "dumbbell"
        case .boxing: return "figure.boxing"
        case .yoga: return "figure.mind.and.body"
        case .football: return "soccerball"
        }
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
                Text("Отметь, если осталось только согласовать состав и время.")
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
            payload.sport = selectedSport
            payload.preferredCourtId = selectedCourtId
            payload.inviteSlug = payload.inviteSlug ?? resolvedInviteIdentifier
            if let selectedCourt = courts.first(where: { $0.id == payload.preferredCourtId }), let district = selectedCourt.district {
                payload.preferredDistricts = [district] + payload.preferredDistricts.filter { $0 != district }
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

            if draft.searchType == .regular {
                payload.preferredDays = orderedDays(from: availabilityByDay)
                payload.preferredTimeRanges = Array(Set(availabilityByDay.values.flatMap { $0 })).sorted { lhs, rhs in
                    timeRangeIndex(lhs) < timeRangeIndex(rhs)
                }
                payload.hotWindow = nil
                payload.hotStartTime = nil
                payload.durationMinutes = nil
            } else {
                payload.preferredDays = []
                payload.preferredTimeRanges = [timeRangeFromHotStartTime(payload.hotStartTime ?? "19:00")]
            }

            let created: GameSearch
            if let initialSearch {
                created = try await appModel.repository.updateSearch(searchId: initialSearch.id, draft: payload)
            } else {
                created = try await appModel.repository.createSearch(payload)
            }
            onCreate(created)
            if initialSearch == nil, payload.searchType == .hot {
                AppHaptics.notification(.success)
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRocketLaunchPresented = true
                }
                try? await Task.sleep(for: .milliseconds(1250))
            }
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
        selectedCourtSnapshot = search.preferredCourt
        availabilityByDay = Dictionary(uniqueKeysWithValues: search.preferredDays.map { ($0, search.preferredTimeRanges) })
    }

    private func searchableCourtText(for court: Court) -> String {
        [
            court.name,
            court.address,
            court.nearestMetroName,
            localizedDistrictName(court.district)
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func courtSubtitle(for court: Court) -> String {
        [
            court.nearestMetroName,
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

private enum HotSearchStep: Int, CaseIterable {
    case when = 0
    case who
    case location
    case confirm

    var badgeTitle: String {
        switch self {
        case .when:
            return "1. Когда"
        case .who:
            return "2. Кого"
        case .location:
            return "3. Где"
        case .confirm:
            return "4. Подтверждение"
        }
    }
}

private struct RocketLaunchOverlay: View {
    @State private var launched = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            Text("🚀")
                .font(.system(size: launched ? 46 : 78))
                .rotationEffect(.degrees(launched ? -24 : 0))
                .scaleEffect(launched ? 0.72 : 1)
                .offset(y: launched ? -360 : 0)
                .opacity(launched ? 0 : 1)
                .shadow(color: AppTheme.court.opacity(0.32), radius: 26, x: 0, y: 18)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.05)) {
                launched = true
            }
        }
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
                        SectionCard(title: "Дополнительно", subtitle: "Скрытые настройки поиска: тип, срочное окно, районы и бронирование клуба.") {
                            AppSegmentedChoice(
                                title: "Тип поиска",
                                items: SearchType.allCases,
                                selection: $draft.searchType,
                                titleForItem: \.title
                            )

                            if draft.searchType == .hot {
                                AppSegmentedChoice(
                                    title: "Окно",
                                    items: HotWindow.allCases,
                                    selection: Binding(
                                        get: { draft.hotWindow ?? .today },
                                        set: { draft.hotWindow = $0 }
                                    ),
                                    titleForItem: \.title
                                )

                                HStack(spacing: 12) {
                                    FieldShell(title: "Время старта") {
                                        TextField("19:00", text: Binding(
                                            get: { draft.hotStartTime ?? "19:00" },
                                            set: { draft.hotStartTime = $0 }
                                        ))
                                        .keyboardType(.numbersAndPunctuation)
                                    }

                                    FieldShell(title: "Длительность") {
                                        Stepper(value: Binding(
                                            get: { draft.durationMinutes ?? sport.defaultDurationMinutes },
                                            set: { draft.durationMinutes = $0 }
                                        ), in: 30 ... 180, step: 30) {
                                            Text("\(draft.durationMinutes ?? sport.defaultDurationMinutes) мин")
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
                                    Text("Отметь, если место уже есть и нужно только собрать состав.")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink.opacity(0.6))
                                }
                                Spacer()
                                Toggle("", isOn: $draft.hasCourtBooked)
                                    .labelsHidden()
                                    .tint(AppTheme.court)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Удобные районы")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                                    .textCase(.uppercase)
                                    .tracking(1.4)

                                if availableDistricts.isEmpty {
                                    Text("Районы появятся, когда загрузятся клубы для выбранного спорта.")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            advancedDistrictChip(title: "Любой район", district: nil)
                                            ForEach(availableDistricts, id: \.self) { district in
                                                advancedDistrictChip(title: localizedDistrictName(district) ?? district, district: district)
                                            }
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Текущая доступность")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                                    .textCase(.uppercase)
                                    .tracking(1.4)
                                AppAvailabilityWeekEditor(availabilityByDay: $availabilityByDay)
                            }
                        }

                        Button("Готово") {
                            dismiss()
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Параметры")
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

private struct SearchClubPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sport: Sport
    let courts: [Court]
    let selectedCourtId: String?
    let selectsImmediately: Bool
    let onSelect: (Court?) -> Void

    @State private var query = ""
    @State private var pendingSelectionId: String?
    @State private var pendingCourtSnapshot: Court?
    @FocusState private var isSearchFocused: Bool

    private var filteredCourts: [Court] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sortedCourts = courts.sorted { left, right in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        guard !normalizedQuery.isEmpty else {
            return sortedCourts
        }

        return sortedCourts.filter { court in
            [
                court.name,
                court.address,
                court.nearestMetroName,
                localizedDistrictName(court.district)
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
            .contains(normalizedQuery)
        }
    }

    private var suggestedCourts: [Court] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let prefixMatches = filteredCourts.filter { court in
            court.name.lowercased().hasPrefix(normalizedQuery)
        }
        let metroMatches = filteredCourts.filter { court in
            guard let metro = court.nearestMetroName?.lowercased() else {
                return false
            }
            return metro.contains(normalizedQuery) && !prefixMatches.contains(where: { $0.id == court.id })
        }
        let districtMatches = filteredCourts.filter { court in
            guard let district = localizedDistrictName(court.district)?.lowercased() else {
                return false
            }
            return district.contains(normalizedQuery)
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

    var body: some View {
        AppScreen {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 48, height: 6)
                    .padding(.top, 10)

                HStack {
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
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                VStack(spacing: 8) {
                    Text("Выбор клуба")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Найдите клуб по названию, метро или району")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                }
                .padding(.top, 6)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.ink.opacity(0.36))
                    ZStack(alignment: .leading) {
                        if query.isEmpty {
                            Text("Название клуба, метро или район")
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
                                        Text(court.nearestMetroName ?? localizedDistrictName(court.district) ?? court.address)
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
                        chip(title: "Все", selected: true)
                        chip(title: sport.title, selected: false)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "location")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("Рядом с вами")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                        }

                        Text(
                            focusedCourt.map { court in
                                [court.name, localizedDistrictName(court.district)]
                                    .compactMap { $0 }
                                    .joined(separator: " · ")
                            } ?? "Санкт-Петербург"
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink.opacity(0.56))
                        .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    SearchClubPickerMapView(
                        courts: mapPreviewCourts,
                        focusedCourt: focusedCourt,
                        onSelectCourt: { courtId in
                            commitSelection(courts.first(where: { $0.id == courtId }))
                        }
                    )
                    .frame(width: 126, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
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
                    Text("Рекомендуемые")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 18)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            CourtBrowseCard(
                                sport: sport,
                                title: "Без привязки",
                                subtitleLines: ["Покажем ближайшие подходящие клубы"],
                                distance: nil,
                                isSelected: pendingSelectionId == nil
                            ) {
                                commitSelection(nil as Court?)
                            }

                            ForEach(filteredCourts) { court in
                                CourtBrowseCard(
                                    sport: sport,
                                    title: court.name,
                                    subtitleLines: [
                                        sport.title,
                                        court.nearestMetroName ?? "Метро не указано",
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
                    .scrollDismissesKeyboard(.interactively)
                }
                .padding(.top, 20)

                VStack(spacing: 10) {
                    Button(pendingSelectionId == nil ? "Оставить без привязки" : "Выбрать этот клуб") {
                        onSelect(pendingCourtSnapshot ?? pendingSelectionId.flatMap { id in courts.first(where: { $0.id == id }) })
                        dismiss()
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))

                    Text("Клуб можно будет изменить позже")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink.opacity(0.38))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.white.opacity(0.96))
            }
        }
        .onAppear {
            pendingSelectionId = selectedCourtId
            pendingCourtSnapshot = selectedCourtId.flatMap { id in courts.first(where: { $0.id == id }) }
            isSearchFocused = false
        }
    }

    private func commitSelection(_ court: Court?) {
        pendingSelectionId = court?.id
        pendingCourtSnapshot = court
        AppHaptics.selection()

        guard selectsImmediately else {
            return
        }

        onSelect(court)
        dismiss()
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
                        Image(systemName: sportSymbolName(for: sport))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
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
                            Image(systemName: index == 0 ? sportSymbolName(for: sport) : (index == 1 ? "tram.fill" : "mappin.and.ellipse"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(index == 0 ? AppTheme.court : AppTheme.ink.opacity(0.72))
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

struct SearchClubPickerMapView: UIViewRepresentable {
    let courts: [Court]
    let focusedCourt: Court?
    let onSelectCourt: (String) -> Void

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
        context.coordinator.update(mapView: mapView, courts: courts, focusedCourt: focusedCourt)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let onSelectCourt: (String) -> Void
        private var lastCourtIDs: [String] = []
        private var lastFocusedCourtID: String?
        private var hasSetVisibleRegion = false

        init(onSelectCourt: @escaping (String) -> Void) {
            self.onSelectCourt = onSelectCourt
        }

        func update(mapView: MKMapView, courts: [Court], focusedCourt: Court?) {
            let visibleCourts = Array(courts.prefix(18))
            let courtIDs = visibleCourts.map(\.id)
            if courtIDs != lastCourtIDs {
                lastCourtIDs = courtIDs
                mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
                mapView.addAnnotations(visibleCourts.map(SearchPreviewCourtAnnotation.init))
            }

            let annotations = mapView.annotations.compactMap { $0 as? SearchPreviewCourtAnnotation }
            let focusedCourtID = focusedCourt?.id

            if let focusedCourt, focusedCourtID != lastFocusedCourtID {
                lastFocusedCourtID = focusedCourtID
                hasSetVisibleRegion = true
                let region = MKCoordinateRegion(
                    center: focusedCourt.coordinate,
                    latitudinalMeters: 3_000,
                    longitudinalMeters: 3_000
                )
                mapView.setRegion(region, animated: true)
                return
            }

            lastFocusedCourtID = focusedCourtID

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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? SearchPreviewCourtAnnotation else {
                return nil
            }

            let reuseID = "SearchClubPickerAnnotationView"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            view.canShowCallout = false
            view.centerOffset = CGPoint(x: 0, y: -18)
            view.image = sportMarkerImage(for: annotation.court.supportedSports?.first)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let annotation = annotation as? SearchPreviewCourtAnnotation else {
                return
            }
            onSelectCourt(annotation.court.id)
        }
    }
}
