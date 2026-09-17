import SwiftUI
import PhotosUI

private extension String {
    var localizedMatchesText: String {
        guard LocaleStore.currentEffectiveLocale == .en else { return self }

        let exact: [String: String] = [
            "Новый мэтч": "New match",
            "Нужно действие": "Action needed",
            "Игра закончилась": "Game ended",
            "Игра подтверждена": "Game confirmed",
            "Ждёт подтверждения": "Awaiting confirmation",
            "Ждем подтверждения": "Awaiting confirmation",
            "Отменена": "Canceled",
            "Поиск": "Search",
            "Подбор игроков": "Finding players",
            "Скоро начнется": "Starting soon",
            "Игра началась": "Game started",
            "Игра идет": "Game in progress",
            "Игра прошла": "Game played",
            "Не сыграли": "Not played",
            "Одиночная": "Singles",
            "Парная": "Doubles",
            "Любой": "Any",
            "Игрок уже отметил, что хочет с вами сыграть.": "This player has already said they would like to play with you."
        ]
        if let translated = exact[self] { return translated }

        var value = self
        let fragments: [(String, String)] = [
            ("Совпадает вид спорта", "Same sport"),
            ("Подходит уровень", "Compatible level"),
            ("Совпадает район", "Same preferred area"),
            ("Совпадает время", "Compatible availability"),
            ("Недалеко от вас", "Near you")
        ]
        for (russian, english) in fragments {
            value = value.replacingOccurrences(of: russian, with: english)
        }
        return value
    }
}

private struct AvatarPreviewItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String?
}

struct MatchesView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var matches: [MatchSummary] = []
    @State private var incomingLikes: [DiscoverUser] = []
    @State private var isLoading = false
    @State private var selectedProfileMatch: MatchSummary?
    @State private var selectedProposalMatch: MatchSummary?
    @State private var navigationMatch: MatchSummary?
    @State private var isChatPresented = false
    @State private var updatingRequestIDs: Set<String> = []
    @State private var updatingIncomingLikeIDs: Set<String> = []
    @State private var selectedFilter: MatchListFilter = .all
    @State private var selectedAvatarPreview: AvatarPreviewItem?

    private var filteredMatches: [MatchSummary] {
        matches.filter { match in
            switch selectedFilter {
            case .all:
                return true
            case .new:
                return match.latestGameRequest == nil
            case .action:
                return match.latestGameRequest?.isPendingForRecipient(currentUserId: appModel.currentUser?.id) == true
            case .withGame:
                guard let request = match.latestGameRequest else { return false }
                return ["accepted", "approved"].contains(request.status.lowercased())
            case .archive:
                guard let request = match.latestGameRequest else { return false }
                return ["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased()) || request.statusLabel == "Игра закончилась"
            }
        }
    }

    private var visibleIncomingLikes: [DiscoverUser] {
        switch selectedFilter {
        case .all, .new, .action:
            return incomingLikes
        case .withGame, .archive:
            return []
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                matchesHeader
                matchesFilterRail

                if !visibleIncomingLikes.isEmpty {
                    incomingLikesDecisionSection
                }

                if filteredMatches.isEmpty, visibleIncomingLikes.isEmpty, !isLoading {
                    SectionCard(title: L10n.string("No matches yet", "Пока нет мэтчей"), subtitle: nil) {
                        EmptyStateView(
                            title: L10n.string("No matches yet", "Пока нет мэтчей"),
                            subtitle: L10n.string("Like a few players in Discover. Mutual interest will automatically appear here.", "Поставь несколько лайков в поиске. Взаимные интересы автоматически появятся здесь."),
                            systemImage: "message.badge"
                        )
                    }
                }

                if !filteredMatches.isEmpty {
                    matchesInboxList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(Color.black.ignoresSafeArea())
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await markSeen()
            if matches.isEmpty {
                await loadMatches()
            }
            await openPendingChatIfPossible()
        }
        .refreshable {
            await markSeen()
            await loadMatches()
            await openPendingChatIfPossible()
        }
        .onChange(of: appModel.pendingChatMatchID) { _ in
            Task {
                await openPendingChatIfPossible()
            }
        }
        .navigationDestination(isPresented: $isChatPresented) {
            if let navigationMatch {
                ChatView(match: navigationMatch) {
                    handleBlockedUser(navigationMatch.otherUser.id)
                    self.navigationMatch = nil
                    isChatPresented = false
                }
            }
        }
        .sheet(item: $selectedProfileMatch) { match in
            MatchPlayerSheet(
                match: match,
                onOpenChat: {
                    presentChat(for: match)
                },
                onProposeGame: {
                    presentProposal(for: match)
                },
                onBlocked: {
                    handleBlockedUser(match.otherUser.id)
                }
            )
            .presentationDetents([.fraction(0.62), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedProposalMatch) { match in
            GameProposalSheet(match: match) {
                await loadMatches()
                navigationMatch = match
                isChatPresented = true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedAvatarPreview) { item in
            AvatarPreviewSheet(name: item.name, path: item.path)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
    }

    private func handleBlockedUser(_ userId: String) {
        selectedProfileMatch = nil
        matches.removeAll { $0.otherUser.id == userId }
        incomingLikes.removeAll { $0.id == userId }
        appModel.errorMessage = nil
        Task { await loadMatches() }
    }

    private var matchesHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Matches", "Мэтчи"))
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                Text(L10n.string("Chats and game arrangements", "Чаты и договоренности по играм"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()
        }
    }

    private var matchesFilterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MatchListFilter.allCases) { filter in
                    let selected = selectedFilter == filter
                    let count = filter.count(
                        in: matches,
                        incomingLikesCount: incomingLikes.count,
                        currentUserId: appModel.currentUser?.id
                    )

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text(filter.localizedTitle)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(selected ? .white : filter.badgeTint)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(selected ? .white.opacity(0.18) : filter.badgeTint.opacity(0.24), in: Capsule())
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? .white : .white.opacity(0.72))
                        .padding(.horizontal, 15)
                        .frame(height: 42)
                        .background(selected ? AppTheme.court : Color.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var matchesInboxList: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredMatches.enumerated()), id: \.element.id) { index, match in
                MatchInboxCard(
                    match: match,
                    currentUserId: appModel.currentUser?.id,
                    isUpdating: match.latestGameRequest.map { updatingRequestIDs.contains($0.id) } ?? false,
                    onOpenAvatar: {
                        AppHaptics.selection()
                        selectedAvatarPreview = AvatarPreviewItem(name: match.otherUser.displayName, path: match.otherUser.avatarUrl)
                    },
                    onOpenChat: {
                        presentChat(for: match)
                    },
                    onProposeGame: {
                        presentProposal(for: match)
                    },
                    onCancelRequest: {
                        await updateGameRequest(match: match, status: "canceled")
                    }
                )

                if index < filteredMatches.count - 1 {
                    Divider()
                        .overlay(.white.opacity(0.08))
                        .padding(.leading, 92)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.075), Color.white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var incomingLikesDecisionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("Waiting for your response", "Ждут решения"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(visibleIncomingLikes.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.court)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.court.opacity(0.18), in: Capsule())
                Spacer()
            }

            ForEach(visibleIncomingLikes) { user in
                IncomingLikeDecisionCard(
                    user: user,
                    isUpdating: updatingIncomingLikeIDs.contains(user.id),
                    onOpenAvatar: {
                        AppHaptics.selection()
                        selectedAvatarPreview = AvatarPreviewItem(name: user.displayName, path: user.avatarUrl)
                    },
                    onDecline: {
                        await respondToIncomingLike(user: user, action: .dislike)
                    },
                    onAccept: {
                        await respondToIncomingLike(user: user, action: .like)
                    }
                )
            }
        }
    }

    private func presentChat(for match: MatchSummary) {
        selectedProfileMatch = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            navigationMatch = match
            isChatPresented = true
        }
    }

    private func presentProposal(for match: MatchSummary) {
        selectedProfileMatch = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            selectedProposalMatch = match
        }
    }

    private func markSeen() async {
        do {
            try await appModel.repository.markInboxSeen()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func loadMatches() async {
        let shouldReportMenuLoading = matches.isEmpty
        if shouldReportMenuLoading {
            appModel.setTabContentLoading("matches", isLoading: true)
        }
        isLoading = true
        defer {
            isLoading = false
            if shouldReportMenuLoading {
                appModel.setTabContentLoading("matches", isLoading: false)
            }
        }

        do {
            async let fetchedMatches = appModel.repository.fetchMatches()

            if appModel.isAuthenticated {
                async let fetchedIncomingLikes = appModel.repository.fetchDiscoverUsers(view: .likes)
                matches = try await fetchedMatches
                incomingLikes = try await fetchedIncomingLikes
            } else {
                matches = try await fetchedMatches
                incomingLikes = []
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func respondToIncomingLike(user: DiscoverUser, action: SwipeAction) async {
        guard !updatingIncomingLikeIDs.contains(user.id) else {
            return
        }

        updatingIncomingLikeIDs.insert(user.id)
        defer { updatingIncomingLikeIDs.remove(user.id) }

        do {
            let createdMatchId = try await appModel.repository.swipe(userId: user.id, action: action)
            incomingLikes.removeAll { $0.id == user.id }

            switch action {
            case .like, .superlike:
                AppHaptics.notification(.success)
            case .dislike:
                AppHaptics.notification(.warning)
            }

            await loadMatches()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)

            if let createdMatchId,
               let createdMatch = matches.first(where: { $0.id == createdMatchId || $0.otherUser.id == user.id }) {
                navigationMatch = createdMatch
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func updateGameRequest(match: MatchSummary, status: String) async {
        guard let request = match.latestGameRequest else {
            return
        }

        updatingRequestIDs.insert(request.id)
        defer { updatingRequestIDs.remove(request.id) }

        do {
            _ = try await appModel.repository.updateGameRequestStatus(gameRequestId: request.id, status: status)
            switch status {
            case "accepted":
                AppHaptics.notification(.success)
            case "declined", "canceled":
                AppHaptics.notification(.warning)
            default:
                AppHaptics.selection()
            }
            await loadMatches()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func openPendingChatIfPossible() async {
        guard let pendingChatMatchID = appModel.pendingChatMatchID else {
            return
        }

        if let match = matches.first(where: { $0.id == pendingChatMatchID }) {
            navigationMatch = match
            isChatPresented = true
            appModel.pendingChatMatchID = nil
            return
        }

        do {
            let freshMatches = try await appModel.repository.fetchMatches()
            matches = freshMatches

            guard let match = freshMatches.first(where: { $0.id == pendingChatMatchID }) else {
                return
            }

            navigationMatch = match
            isChatPresented = true
            appModel.pendingChatMatchID = nil
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }
}

private enum MatchListFilter: String, CaseIterable, Identifiable {
    case all
    case new
    case action
    case withGame
    case archive

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:
            return L10n.string("All", "Все")
        case .new:
            return L10n.string("New", "Новые")
        case .action:
            return L10n.string("Action needed", "Нужно действие")
        case .withGame:
            return L10n.string("Confirmed", "Подтверждены")
        case .archive:
            return L10n.string("Archive", "Архив")
        }
    }

    var badgeTint: Color {
        switch self {
        case .all:
            return AppTheme.court
        case .new:
            return Color(red: 0.29, green: 0.48, blue: 0.95)
        case .action:
            return Color(red: 0.94, green: 0.58, blue: 0.18)
        case .withGame:
            return AppTheme.court
        case .archive:
            return .white.opacity(0.62)
        }
    }

    func count(in matches: [MatchSummary], incomingLikesCount: Int, currentUserId: String?) -> Int {
        matches.filter { match in
            switch self {
            case .all:
                return true
            case .new:
                return match.latestGameRequest == nil
            case .action:
                return match.latestGameRequest?.isPendingForRecipient(currentUserId: currentUserId) == true
            case .withGame:
                guard let request = match.latestGameRequest else { return false }
                return ["accepted", "approved"].contains(request.status.lowercased())
            case .archive:
                guard let request = match.latestGameRequest else { return false }
                return ["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased()) || request.statusLabel == "Игра закончилась"
            }
        }
        .count + extraCountForIncomingLikes(incomingLikesCount)
    }

    private func extraCountForIncomingLikes(_ incomingLikesCount: Int) -> Int {
        switch self {
        case .all, .new, .action:
            return incomingLikesCount
        case .withGame, .archive:
            return 0
        }
    }
}

private struct IncomingLikeDecisionCard: View {
    let user: DiscoverUser
    let isUpdating: Bool
    let onOpenAvatar: () -> Void
    let onDecline: () async -> Void
    let onAccept: () async -> Void

    private var primarySport: Sport {
        user.preferredSports.first ?? .tennis
    }

    private var sportDistrictLine: String {
        let district = user.districtDisplayNames.first ?? user.districtDisplaySummary
        return "\(primarySport.title) · \(district)"
    }

    private var reasonLine: String {
        user.explainabilityReasons.first?.localizedMatchesText ?? L10n.string("This player has already said they would like to play with you.", "Игрок уже отметил, что хочет с вами сыграть.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 13) {
                Button(action: onOpenAvatar) {
                    RemoteAvatarView(name: user.displayName, path: user.avatarUrl, size: 58)
                        .overlay(alignment: .bottomTrailing) {
                            if user.isOnline {
                                Circle()
                                    .fill(Color(red: 0.22, green: 0.82, blue: 0.45))
                                    .frame(width: 13, height: 13)
                                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                            }
                        }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(user.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        AppInlineChip(
                            text: L10n.string("Wants to play", "Хочет сыграть"),
                            tint: AppTheme.court.opacity(0.18),
                            foreground: AppTheme.mint
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    }

                    Text(sportDistrictLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.41, green: 0.86, blue: 0.56))
                        .lineLimit(1)

                    Text(reasonLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                }
                .layoutPriority(1)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await onDecline() }
                } label: {
                    Label(L10n.string("Skip", "Пропустить"), systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IncomingLikeDecisionButtonStyle(tint: .white.opacity(0.12), foreground: .white.opacity(0.82)))
                .disabled(isUpdating)

                Button {
                    Task { await onAccept() }
                } label: {
                    HStack(spacing: 7) {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        SportIconView(sport: primarySport, color: .white, size: 16)
                        Text(L10n.string("Let's play", "Можно сыграть"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(IncomingLikeDecisionButtonStyle(tint: AppTheme.court, foreground: .white))
                .disabled(isUpdating)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.09), Color.white.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.court.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct IncomingLikeDecisionButtonStyle: ButtonStyle {
    let tint: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(tint.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private struct MatchInboxCard: View {
    let match: MatchSummary
    let currentUserId: String?
    let isUpdating: Bool
    let onOpenAvatar: () -> Void
    let onOpenChat: () -> Void
    let onProposeGame: () -> Void
    let onCancelRequest: () async -> Void

    private var latestRequest: MatchGameRequest? {
        match.latestGameRequest
    }

    private var canCancelPending: Bool {
        guard let latestRequest else {
            return false
        }
        return latestRequest.status.lowercased() == "pending" && latestRequest.createdByUserId == currentUserId
    }

    private var primarySport: Sport {
        match.otherUser.preferredSports.first ?? .tennis
    }

    private var primaryLevelLine: String {
        if let min = match.otherUser.sportLevels[primarySport.rawValue] ?? match.otherUser.tennisLevel {
            return "\(max(min - 1, 1))–\(min + 1)"
        }
        return L10n.string("level not specified", "уровень не указан")
    }

    private var timestampText: String {
        let source = match.lastMessage?.createdAt ?? latestRequest?.proposedDatetime ?? match.createdAt
        guard let date = source.parsedISODateValue() else {
            return source.formattedDateTime()
        }

        if Calendar.current.isDateInToday(date) {
            return date.formattedHourMinute()
        }

        if Calendar.current.isDateInYesterday(date) {
            return L10n.string("Yesterday", "Вчера")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.string("en_US", "ru_RU"))
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private var statusBadgeText: String {
        latestRequest?.statusLabel.localizedMatchesText ?? L10n.string("New match", "Новый мэтч")
    }

    private var statusBadgeTint: Color {
        latestRequest?.statusTintColor ?? Color(red: 0.36, green: 0.41, blue: 0.83)
    }

    private var statusBadgeSurface: Color {
        latestRequest?.statusSurfaceColor ?? Color(red: 0.16, green: 0.18, blue: 0.33)
    }

    private var statusLineText: String {
        if let latestRequest {
            if latestRequest.isPendingForRecipient(currentUserId: currentUserId) {
                return L10n.string("Action needed", "Нужно действие")
            }
            return latestRequest.statusLabel.localizedMatchesText
        }

        return L10n.string("New match", "Новый мэтч")
    }

    private var statusLineTint: Color {
        if latestRequest?.isPendingForRecipient(currentUserId: currentUserId) == true {
            return Color(red: 1.0, green: 0.62, blue: 0.18)
        }

        return statusBadgeTint
    }

    private var matchReasonItems: [String] {
        let sportLine = "\(primarySport.title) · \(primarySport.formatTitle(format: match.otherUser.preferredPlayFormat))"
        let districtLine = match.otherUser.districtDisplayNames.first ?? match.otherUser.districtDisplaySummary
        let timeLine = match.otherUser.availableTimeRanges.compactMap { timeRangeTitle(for: $0) }.first ?? L10n.string("Time to be confirmed", "Время уточняется")
        return [sportLine, districtLine, timeLine]
    }

    private var sportDistrictLine: String {
        let district = match.otherUser.districtDisplayNames.first ?? match.otherUser.districtDisplaySummary
        return "\(primarySport.title) · \(district)"
    }

    private var upcomingGameLine: String? {
        guard let request = latestRequest else {
            return nil
        }

        let courtName = request.proposedCourt?.name ?? request.sport.venueUnspecifiedTitle
        return "\(request.sport.title) · \(request.proposedDatetime.formattedDateTime()) · \(courtName)"
    }

    private var lastMessagePreview: String? {
        guard let message = match.lastMessage else {
            return nil
        }

        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let content: String
        if !text.isEmpty {
            content = text
        } else if message.attachments.count > 1 {
            content = L10n.string("\(message.attachments.count) photos", "\(message.attachments.count) фото")
        } else if !message.attachments.isEmpty {
            content = L10n.string("Photo", "Фото")
        } else {
            return nil
        }

        if message.senderUserId == currentUserId {
            return L10n.string("You: \(content)", "Вы: \(content)")
        }

        let senderName = message.senderUser?.name ?? match.otherUser.displayName
        return "\(senderName): \(content)"
    }

    private var conversationPreview: String {
        lastMessagePreview ?? latestRequest?.comment ?? L10n.string("No messages yet. Be the first to say hi.", "Сообщений пока нет. Напиши первым.")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Button(action: onOpenAvatar) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteAvatarView(name: match.otherUser.displayName, path: match.otherUser.avatarUrl, size: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Circle()
                        .fill(match.otherUser.isOnline ? Color(red: 0.22, green: 0.82, blue: 0.45) : Color.white.opacity(0.28))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(match.otherUser.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(match.otherUser.presenceLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(match.otherUser.isOnline ? Color(red: 0.38, green: 0.93, blue: 0.62) : .white.opacity(0.44))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 4)

                    Text(timestampText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }

                if let upcomingGameLine {
                    Text(upcomingGameLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                } else {
                    Text(sportDistrictLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Text(conversationPreview)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 8) {
                    Text(statusLineText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(statusLineTint)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if latestRequest?.isPendingForRecipient(currentUserId: currentUserId) == true {
                        Circle()
                            .fill(Color(red: 0.29, green: 0.48, blue: 0.95))
                            .frame(width: 26, height: 26)
                            .overlay {
                                Text("!")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                    }
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenChat()
        }
    }

    private func matchReasonPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.72))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func matchActionButton(title: String, systemImage: String, tint: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func asyncMatchActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        foreground: Color,
        isUpdating: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if isUpdating {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(isUpdating)
    }

    private func timeRangeTitle(for rawValue: String) -> String? {
        guard let range = TimeRange(rawValue: rawValue) else {
            return nil
        }

        switch range {
        case .morning:
            return L10n.string("Morning", "Утро")
        case .day:
            return L10n.string("Afternoon", "День")
        case .evening:
            return L10n.string("Evening", "Вечер")
        }
    }
}

struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var notificationManager: NotificationManager
    let match: MatchSummary
    let onBlocked: () -> Void

    @State private var currentMatch: MatchSummary
    @State private var messages: [ChatMessage] = []
    @State private var messagesLoadRevision = 0
    @State private var gameRequests: [MatchGameRequest] = []
    @State private var selectedGameRequestID: String?
    @State private var text = ""
    @State private var selectedProposalMatch: MatchSummary?
    @State private var proposalContext: ProposalSheetContext = .new
    @State private var isProfilePresented = false
    @State private var isUpdatingRequest = false
    @State private var lastActiveChatPresenceRefresh = Date.distantPast
    @State private var selectedAvatarPreview: AvatarPreviewItem?
    @State private var selectedGameReport: GameReport?
    @State private var isChatPhotoPickerPresented = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var pendingPhotos: [PendingMatchChatPhoto] = []
    @State private var selectedMediaAttachment: ChatMediaAttachment?
    @State private var isSendingMessage = false
    @FocusState private var isComposerFocused: Bool
    private let bottomAnchorID = "chat-bottom-anchor"

    init(match: MatchSummary, onBlocked: @escaping () -> Void = {}) {
        self.match = match
        self.onBlocked = onBlocked
        _currentMatch = State(initialValue: match)
    }

    var body: some View {
        VStack(spacing: 0) {
            chatTopHeader
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)

            Divider()
                .overlay(.white.opacity(0.08))

            chatAgreementHeaderSection
                .padding(.horizontal, 16)
                .padding(.top, isComposerFocused ? 8 : 12)
                .padding(.bottom, isComposerFocused ? 8 : 10)
                .animation(.spring(response: 0.3, dampingFraction: 0.84), value: isComposerFocused)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(messages) { message in
                            let isMine = message.senderUserId == appModel.currentUser?.id
                            let presentation = chatMessagePresentation(for: message)
                            Group {
                                if message.isGameReportSystemEvent {
                                    let report = gameReport(for: message)
                                    ChatSystemEventRow(
                                        title: message.gameReportSystemTitle,
                                        timestamp: message.createdAt.formattedDateTime(),
                                        onTap: report.map { report in
                                            {
                                                selectedGameReport = report
                                            }
                                        }
                                    )
                                    .id(message.id)
                                } else {
                                    ChatBubble(
                                        text: presentation.text,
                                        attachments: message.attachments,
                                        timestamp: message.createdAt.formattedDateTime(),
                                        sender: message.senderUser?.name ?? currentMatch.otherUser.displayName,
                                        avatarPath: isMine ? nil : (message.senderUser?.avatarUrl ?? currentMatch.otherUser.avatarUrl),
                                        isMine: isMine,
                                        receipt: message.receipt,
                                        actionTitle: presentation.action?.title,
                                        actionSystemImage: presentation.action?.systemImage,
                                        onAction: presentation.action.map { action in
                                            {
                                                appModel.navigate(to: action.target)
                                            }
                                        },
                                        onAvatarTap: isMine
                                            ? nil
                                            : {
                                                selectedAvatarPreview = AvatarPreviewItem(
                                                    name: message.senderUser?.name ?? currentMatch.otherUser.displayName,
                                                    path: message.senderUser?.avatarUrl ?? currentMatch.otherUser.avatarUrl
                                                )
                                            },
                                        onAttachmentTap: { selectedMediaAttachment = $0 }
                                    )
                                    .id(message.id)
                                }
                            }
                            .chatReceiptRow(id: message.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .chatReceiptViewport(
                    incomingIDs: messages.filter { $0.senderUserId != appModel.currentUser?.id }.map(\.id),
                    isUncovered: !isChatPhotoPickerPresented && !isProfilePresented && selectedProposalMatch == nil && selectedAvatarPreview == nil && selectedGameReport == nil && selectedMediaAttachment == nil,
                    scope: .match(currentMatch.id), repository: appModel.repository
                )
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    isComposerFocused = false
                }
                .onAppear {
                    scrollChatToBottom(proxy, animated: false)
                }
                .onChange(of: messages.count) { _ in
                    scrollChatToBottom(proxy)
                }
                .onChange(of: latestRequestScrollSignature) { _ in
                    scrollChatToBottom(proxy)
                }
                .onChange(of: isComposerFocused) { focused in
                    if focused {
                        scrollChatToBottom(proxy)
                    }
                }
            }

            if let selectedRequest = selectedChatGameRequest, !isComposerFocused {
                Divider()
                    .overlay(.white.opacity(0.08))
                    .padding(.horizontal, 16)

                chatActionsBar(for: selectedRequest, showsSelectionSummary: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                Divider()
                    .overlay(.white.opacity(0.08))
                    .padding(.horizontal, 16)
            }

            if !pendingPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pendingPhotos) { photo in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 74, height: 74)
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
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    isChatPhotoPickerPresented = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 46, height: 58)
                        .foregroundStyle(AppTheme.court)
                }
                .photosPicker(isPresented: $isChatPhotoPickerPresented, selection: $photoPickerItems, maxSelectionCount: 4, matching: .images)
                .disabled(isSendingMessage)

                FieldShell {
                    TextField(L10n.string("Write a message...", "Написать сообщение..."), text: $text, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .focused($isComposerFocused)
                }

                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    Group {
                        if isSendingMessage {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .frame(width: 58, height: 58)
                    .background(AppTheme.court, in: Circle())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSendingMessage || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingPhotos.isEmpty))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black)

            if let selectedRequest = selectedChatGameRequest, isComposerFocused {
                chatActionsBar(for: selectedRequest, showsSelectionSummary: false)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .contentShape(Rectangle())
        .simultaneousGesture(chatBackSwipe)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: photoPickerItems) { items in
            Task { await loadPendingPhotos(from: items) }
        }
        .task {
            await markSeen()
            await refreshChatState()
            await runRealtimeChatUpdates()
        }
        .onAppear {
            notificationManager.setNotificationMuted(href: "/inbox/\(currentMatch.id)", isMuted: true)
            Task {
                await updateActiveChatPresence(isActive: true)
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = .hidden
            }
        }
        .onChange(of: isComposerFocused) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = .hidden
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tennisRealtimeEventReceived)) { notification in
            guard let event = notification.object as? RealtimeEvent,
                  shouldRefreshChat(for: event) else {
                return
            }

            Task {
                await refreshChatState(showErrors: false)
            }
        }
        .onDisappear {
            notificationManager.setNotificationMuted(href: "/inbox/\(currentMatch.id)", isMuted: false)
            Task {
                await updateActiveChatPresence(isActive: false)
            }
            appModel.bottomBarDisplayMode = .expanded
        }
        .sheet(isPresented: $isProfilePresented) {
            MatchPlayerSheet(
                match: currentMatch,
                onOpenChat: {
                    isProfilePresented = false
                },
                onProposeGame: {
                    isProfilePresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        proposalContext = .new
                        selectedProposalMatch = currentMatch
                    }
                },
                onBlocked: {
                    isProfilePresented = false
                    dismiss()
                }
            )
            .presentationDetents([.fraction(0.62), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedProposalMatch) { proposalMatch in
            GameProposalSheet(
                match: proposalMatch,
                context: proposalContext,
                seedRequest: selectedChatGameRequest
            ) {
                await refreshChatState()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
        .sheet(item: $selectedAvatarPreview) { item in
            AvatarPreviewSheet(name: item.name, path: item.path)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(item: $selectedGameReport) { report in
            GameReportViewerSheet(report: report)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground(Color.black)
        }
        .fullScreenCover(item: $selectedMediaAttachment) { attachment in
            MatchChatMediaViewer(attachment: attachment)
        }
    }

    private var chatPrimarySport: Sport {
        currentMatch.otherUser.preferredSports.first ?? .tennis
    }

    private var chatBackSwipe: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                guard value.startLocation.x <= 32 else {
                    return
                }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard horizontal > max(90, vertical * 1.8) else {
                    return
                }

                isComposerFocused = false
                dismiss()
            }
    }

    private var chatSubtitle: String {
        L10n.string("Looking for a \(chatPrimarySport.localizedPurposeTitle) partner", "Ищет партнера для \(chatPrimarySport.purposeTitle)")
    }

    private func gameReport(for message: ChatMessage) -> GameReport? {
        if let gameRequestId = message.gameRequestId,
           let report = gameRequests.first(where: { $0.id == gameRequestId })?.report {
            return report
        }

        return gameRequests
            .compactMap(\.report)
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private var chatTopHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)

            Button {
                AppHaptics.selection()
                selectedAvatarPreview = AvatarPreviewItem(name: currentMatch.otherUser.displayName, path: currentMatch.otherUser.avatarUrl)
            } label: {
                RemoteAvatarView(name: currentMatch.otherUser.displayName, path: currentMatch.otherUser.avatarUrl, size: 48)
                    .overlay(alignment: .bottomTrailing) {
                        if currentMatch.otherUser.isOnline {
                            Circle()
                                .fill(Color(red: 0.22, green: 0.82, blue: 0.45))
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(Color.black, lineWidth: 2))
                        }
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        chatNameText(lineLimit: 1)
                        presenceBadge
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        chatNameText(lineLimit: 2)
                        presenceBadge
                    }
                }

                Text(chatSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer()

            Button {
                AppHaptics.selection()
                isProfilePresented = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "person")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                    Text(L10n.string("Profile", "Профиль"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.82))
            }
            .buttonStyle(.plain)

            UserSafetyMenuButton(
                userId: currentMatch.otherUser.id,
                displayName: currentMatch.otherUser.displayName,
                context: .chat(messageId: messages.last(where: { $0.senderUserId == currentMatch.otherUser.id })?.id),
                onBlocked: {
                    onBlocked()
                    dismiss()
                }
            )
        }
    }

    private func chatNameText(lineLimit: Int) -> some View {
        Text(currentMatch.otherUser.displayName)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.62)
    }

    private var presenceBadge: some View {
        let isOnline = currentMatch.otherUser.isOnline

        return Text(currentMatch.otherUser.presenceLabel)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isOnline ? Color(red: 0.38, green: 0.93, blue: 0.62) : .white.opacity(0.62))
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                isOnline ? Color(red: 0.05, green: 0.25, blue: 0.16) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }

    private var chatGameRequests: [MatchGameRequest] {
        var byId: [String: MatchGameRequest] = [:]
        for request in gameRequests {
            byId[request.id] = request
        }
        if let latest = currentMatch.latestGameRequest {
            byId[latest.id] = latest
        }

        return byId.values.sorted { left, right in
            let leftInactive = isInactive(left)
            let rightInactive = isInactive(right)
            if leftInactive != rightInactive {
                return !leftInactive
            }

            return (left.proposedDate ?? .distantPast) > (right.proposedDate ?? .distantPast)
        }
    }

    private var selectedChatGameRequest: MatchGameRequest? {
        if let selectedGameRequestID,
           let selected = chatGameRequests.first(where: { $0.id == selectedGameRequestID }) {
            return selected
        }

        return chatGameRequests.first
    }

    private func ensureSelectedGameRequest() {
        let availableIDs = Set(chatGameRequests.map(\.id))
        if let selectedGameRequestID, availableIDs.contains(selectedGameRequestID) {
            return
        }

        selectedGameRequestID = chatGameRequests.first?.id
    }

    @ViewBuilder
    private var chatAgreementHeaderSection: some View {
        if !chatGameRequests.isEmpty {
            gameRequestsCarousel
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if !isComposerFocused {
            proposalPromptCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var gameRequestsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chatGameRequests) { request in
                    let isSelected = selectedChatGameRequest?.id == request.id

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedGameRequestID = request.id
                        }
                        AppHaptics.selection()
                    } label: {
                        compactGameRequestCard(request, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func compactGameRequestCard(_ request: MatchGameRequest, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            SportIconView(sport: request.sport, color: .white, size: 18)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(
                        colors: [AppTheme.court.opacity(0.74), AppTheme.court.opacity(0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(compactGameRequestSummary(request))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(request.statusLabel.localizedMatchesText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(request.statusTintColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.court)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: min(UIScreen.main.bounds.width - 48, 360), height: 62)
        .background(
            LinearGradient(
                colors: [
                    isSelected ? Color(red: 0.06, green: 0.21, blue: 0.14) : Color.white.opacity(0.07),
                    isSelected ? Color(red: 0.04, green: 0.12, blue: 0.09) : Color.white.opacity(0.035)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? AppTheme.court.opacity(0.72) : Color.white.opacity(0.10), lineWidth: isSelected ? 1.4 : 1)
        )
        .shadow(color: isSelected ? AppTheme.court.opacity(0.16) : .clear, radius: 14, x: 0, y: 8)
        .scaleEffect(isSelected ? 1.01 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    private func compactGameRequestSummary(_ request: MatchGameRequest) -> String {
        [
            request.sport.title,
            gameRequestCompactDayText(request),
            gameRequestTimeText(request),
            request.proposedCourt?.name ?? request.sport.venueUnspecifiedTitle
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func gameRequestCompactDayText(_ request: MatchGameRequest) -> String {
        guard let date = request.proposedDate else {
            return request.proposedDatetime
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.string("en_US", "ru_RU"))
        formatter.setLocalizedDateFormatFromTemplate("EEE, d MMMM")
        let value = formatter.string(from: date)
        return value.prefix(1).uppercased() + String(value.dropFirst())
    }

    private func gameRequestInfoLine(systemImage: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 18)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private func gameRequestDayText(_ request: MatchGameRequest) -> String {
        guard let date = request.proposedDate else {
            return request.proposedDatetime.formattedDateTime()
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.string("en_US", "ru_RU"))
        formatter.setLocalizedDateFormatFromTemplate("EEEE, d MMMM")
        let value = formatter.string(from: date)
        return value.prefix(1).uppercased() + String(value.dropFirst())
    }

    private func gameRequestTimeText(_ request: MatchGameRequest) -> String {
        guard let date = request.proposedDate else {
            return request.proposedDatetime
        }

        return date.formattedHourMinute()
    }

    private func gameRequestLocationLine(_ request: MatchGameRequest) -> String {
        let name = request.proposedCourt?.name ?? request.sport.venueUnspecifiedTitle
        if let address = request.proposedCourt?.address, !address.isEmpty {
            return "\(name) · \(address)"
        }
        return name
    }

    private func proposalStatusCard(_ request: MatchGameRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("GAME PROPOSAL", "ПРЕДЛОЖЕНИЕ ИГРЫ"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                    Text(nextStepLabel(for: request))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                statusPill(for: request)
            }

            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.court)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(request.sport.title) · \(request.effectiveFormatTitle.localizedMatchesText)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(request.proposedCourt?.name ?? request.sport.venueUnspecifiedTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)
            }

            proposalSlotRow(
                title: request.proposedDatetime.formattedDateTime(),
                subtitle: request.proposedCourt?.address ?? request.nextStepLabel,
                isEmphasized: !isInactive(request)
            )

            proposalActions(for: request)
        }
        .padding(16)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var proposalPromptCard: some View {
        Button {
            openProposalSheet(context: .new)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.50, green: 0.95, blue: 0.72))
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(
                            colors: [
                                AppTheme.court.opacity(0.42),
                                AppTheme.court.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Propose a game", "Предложить игру"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)

                    Text(L10n.string("Choose a date, time, and venue, then send your proposal.", "Выберите дату, время, корт и отправьте предложение"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.92, blue: 0.62))
            }
            .padding(14)
            .frame(width: min(UIScreen.main.bounds.width - 48, 280), alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        AppTheme.court.opacity(0.82),
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proposalShortcutButton(hasActiveProposal: Bool) -> some View {
        Button {
            openProposalSheet(context: hasActiveProposal ? .edit : .new)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: hasActiveProposal ? "square.and.pencil" : "calendar.badge.plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(red: 0.46, green: 0.96, blue: 0.70))

                Text(hasActiveProposal ? L10n.string("Edit game", "Изменить игру") : L10n.string("Propose a game", "Предложить игру"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.36, green: 0.92, blue: 0.62))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(AppTheme.court.opacity(0.74), lineWidth: 1.1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openProposalSheet(context: ProposalSheetContext) {
        AppHaptics.selection()
        proposalContext = context
        selectedProposalMatch = currentMatch
    }

    private var latestRequestScrollSignature: String {
        guard let request = currentMatch.latestGameRequest else {
            return "none"
        }

        return "\(request.id):\(request.status):\(request.proposedDatetime)"
    }

    private func scrollChatToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    private func proposalSlotRow(title: String, subtitle: String, isEmphasized: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isEmphasized ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isEmphasized ? Color(red: 0.42, green: 0.86, blue: 0.55) : Color(red: 0.93, green: 0.65, blue: 0.29))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .background((isEmphasized ? AppTheme.court.opacity(0.28) : Color.white.opacity(0.05)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isEmphasized ? AppTheme.court.opacity(0.62) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusPill(for request: MatchGameRequest) -> some View {
        Text(request.statusLabel.localizedMatchesText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(request.statusTintColor)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(request.statusSurfaceColor.opacity(0.95), in: Capsule())
    }

    @ViewBuilder
    private func proposalActions(for request: MatchGameRequest) -> some View {
        if request.isPendingForRecipient(currentUserId: appModel.currentUser?.id) {
            HStack(spacing: 10) {
                chatQuickAsyncActionButton(
                    title: L10n.string("Confirm", "Подтвердить"),
                    systemImage: "checkmark.circle.fill",
                    tint: AppTheme.court,
                    foreground: .white,
                    isUpdating: isUpdatingRequest
                ) {
                    await updateCurrentRequest(request, status: "accepted")
                }

                chatQuickAsyncActionButton(
                    title: L10n.string("Decline", "Отклонить"),
                    systemImage: "xmark.circle",
                    tint: Color(red: 0.25, green: 0.10, blue: 0.10),
                    foreground: Color(red: 1.0, green: 0.47, blue: 0.43),
                    isUpdating: isUpdatingRequest
                ) {
                    await updateCurrentRequest(request, status: "declined")
                }
            }
        } else {
            HStack(spacing: 10) {
                chatQuickActionButton(
                    title: isInactive(request) ? L10n.string("Propose again", "Предложить заново") : L10n.string("Edit", "Изменить"),
                    systemImage: isInactive(request) ? "calendar.badge.plus" : "square.and.pencil",
                    tint: isInactive(request) ? AppTheme.court : Color.white.opacity(0.06),
                    foreground: .white
                ) {
                    proposalContext = isInactive(request) ? .new : .edit
                    selectedProposalMatch = currentMatch
                }

                chatQuickAsyncActionButton(
                    title: L10n.string("Cancel", "Отменить"),
                    systemImage: "xmark.circle",
                    tint: Color(red: 0.25, green: 0.10, blue: 0.10),
                    foreground: Color(red: 1.0, green: 0.47, blue: 0.43),
                    isUpdating: isUpdatingRequest
                ) {
                    await cancelCurrentRequest(request)
                }
                .opacity(isInactive(request) ? 0.5 : 1)
                .disabled(isUpdatingRequest || isInactive(request))
            }
        }
    }

    private func chatActionsBar(for request: MatchGameRequest, showsSelectionSummary: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsSelectionSummary {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.court)

                    Text(L10n.string("Selected: \(gameRequestDayText(request)), \(gameRequestTimeText(request))", "Выбрана: \(gameRequestDayText(request)), \(gameRequestTimeText(request))"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    chatQuickActionButton(
                        title: L10n.string("New game", "Новая игра"),
                        systemImage: "calendar.badge.plus",
                        tint: AppTheme.court,
                        foreground: .white
                    ) {
                        proposalContext = .new
                        selectedProposalMatch = currentMatch
                    }

                    if request.isPendingForRecipient(currentUserId: appModel.currentUser?.id) {
                        chatQuickAsyncActionButton(
                            title: L10n.string("Confirm", "Подтвердить"),
                            systemImage: "checkmark.circle.fill",
                            tint: AppTheme.court,
                            foreground: .white,
                            isUpdating: isUpdatingRequest
                        ) {
                            await updateCurrentRequest(request, status: "accepted")
                        }

                        chatQuickAsyncActionButton(
                            title: L10n.string("Decline", "Отклонить"),
                            systemImage: "xmark.circle",
                            tint: Color(red: 0.25, green: 0.10, blue: 0.10),
                            foreground: Color(red: 1.0, green: 0.47, blue: 0.43),
                            isUpdating: isUpdatingRequest
                        ) {
                            await updateCurrentRequest(request, status: "declined")
                        }
                    } else if !isInactive(request) {
                        chatQuickActionButton(
                            title: L10n.string("Suggest a time", "Предложить время"),
                            systemImage: "clock",
                            tint: Color.white.opacity(0.06),
                            foreground: .white
                        ) {
                            proposalContext = .reschedule
                            selectedProposalMatch = currentMatch
                        }

                        chatQuickActionButton(
                            title: L10n.string("Edit game", "Изменить игру"),
                            systemImage: "slider.horizontal.3",
                            tint: Color.white.opacity(0.06),
                            foreground: .white
                        ) {
                            proposalContext = .edit
                            selectedProposalMatch = currentMatch
                        }

                        chatQuickAsyncActionButton(
                            title: L10n.string("Cancel game", "Отмена игры"),
                            systemImage: "xmark",
                            tint: Color(red: 0.25, green: 0.10, blue: 0.10),
                            foreground: Color(red: 1.0, green: 0.47, blue: 0.43),
                            isUpdating: isUpdatingRequest
                        ) {
                            await cancelCurrentRequest(request)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func chatQuickActionButton(title: String, systemImage: String, tint: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func chatQuickAsyncActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        foreground: Color,
        isUpdating: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 9) {
                if isUpdating {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .disabled(isUpdating)
    }

    private func isInactive(_ request: MatchGameRequest) -> Bool {
        ["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased())
            || request.statusLabel == "Игра закончилась"
    }

    private func nextStepLabel(for request: MatchGameRequest) -> String {
        guard request.status.lowercased() == "pending" else {
            return request.nextStepLabel.localizedMatchesText
        }

        if request.isPendingForRecipient(currentUserId: appModel.currentUser?.id) {
            return L10n.string("Confirm or decline the proposal so both players know the plan.", "Подтверди или отклони предложение, чтобы игра стала понятна обоим.")
        }

        return L10n.string("Proposal sent. Waiting for the other player's confirmation.", "Предложение отправлено. Ждём подтверждение второго игрока.")
    }

    private func updateCurrentRequest(_ request: MatchGameRequest, status: String) async {
        isUpdatingRequest = true
        defer { isUpdatingRequest = false }

        do {
            _ = try await appModel.repository.updateGameRequestStatus(gameRequestId: request.id, status: status)
            AppHaptics.notification(status == "accepted" ? .success : .warning)
            await refreshChatState()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func cancelCurrentRequest(_ request: MatchGameRequest) async {
        isUpdatingRequest = true
        defer { isUpdatingRequest = false }

        do {
            _ = try await appModel.repository.updateGameRequestStatus(gameRequestId: request.id, status: "canceled")
            AppHaptics.notification(.warning)
            await refreshChatState()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func markSeen() async {
        do {
            try await appModel.repository.markInboxSeen()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func loadMessages(showErrors: Bool = true) async {
        messagesLoadRevision += 1
        let revision = messagesLoadRevision
        do {
            let fetchedMessages = try await appModel.repository.fetchMessages(matchId: currentMatch.id)
            guard revision == messagesLoadRevision else { return }
            // IDs may stay the same while receipts advance; stale responses cannot regress them.
            messages = mergeChatReceipts(current: messages, fetched: fetchedMessages)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            if showErrors {
                appModel.present(error: error)
            }
        }
    }

    private func refreshMatch(showErrors: Bool = true) async {
        do {
            let freshMatches = try await appModel.repository.fetchMatches()
            if let refreshed = freshMatches.first(where: { $0.id == currentMatch.id }) {
                currentMatch = refreshed
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            if showErrors {
                appModel.present(error: error)
            }
        }
    }

    private func loadGameRequests(showErrors: Bool = true) async {
        do {
            let requests = try await appModel.repository.fetchMyGameRequests()
            gameRequests = requests.filter { $0.matchId == currentMatch.id }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            if showErrors {
                appModel.present(error: error)
            }
        }
    }

    private func refreshChatState(showErrors: Bool = true) async {
        await loadMessages(showErrors: showErrors)
        await refreshMatch(showErrors: showErrors)
        await loadGameRequests(showErrors: showErrors)
        ensureSelectedGameRequest()
        await appModel.notificationManager.manualRefresh(repository: appModel.repository)
    }

    private func runRealtimeChatUpdates() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else {
                return
            }
            await refreshActiveChatPresenceIfNeeded()
            await refreshChatState(showErrors: false)
        }
    }

    private func refreshActiveChatPresenceIfNeeded() async {
        guard Date().timeIntervalSince(lastActiveChatPresenceRefresh) > 30 else {
            return
        }

        await updateActiveChatPresence(isActive: true)
    }

    private func updateActiveChatPresence(isActive: Bool) async {
        do {
            try await appModel.repository.setActiveChat(matchId: currentMatch.id, gameRequestId: nil, isActive: isActive)
            if isActive {
                lastActiveChatPresenceRefresh = Date()
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
        }
    }

    private func shouldRefreshChat(for event: RealtimeEvent) -> Bool {
        if event.matchId == currentMatch.id {
            return true
        }

        if let href = event.href, href == "/inbox/\(currentMatch.id)" {
            return true
        }

        return false
    }

    private func chatMessagePresentation(for message: ChatMessage) -> ChatMessagePresentation {
        if let gameRequestId = message.gameRequestId {
            return ChatMessagePresentation(
                text: cleanActionLinkText(message.text),
                action: ChatMessageAction(
                    title: L10n.string("Open game", "Открыть игру"),
                    systemImage: "calendar.badge.clock",
                    target: .discover(.upcoming, highlightedGameRequestID: gameRequestId)
                )
            )
        }

        if let gameRequestId = extractPathID(from: message.text, marker: "/play/games/") {
            return ChatMessagePresentation(
                text: cleanActionLinkText(message.text),
                action: ChatMessageAction(
                    title: L10n.string("Open game", "Открыть игру"),
                    systemImage: "calendar.badge.clock",
                    target: .discover(.upcoming, highlightedGameRequestID: gameRequestId)
                )
            )
        }

        if let searchId = extractPathID(from: message.text, marker: "/play/searches/") {
            return ChatMessagePresentation(
                text: cleanActionLinkText(message.text),
                action: ChatMessageAction(
                    title: L10n.string("Open search", "Открыть поиск"),
                    systemImage: "magnifyingglass",
                    target: .discover(.hot, highlightedSearchID: searchId)
                )
            )
        }

        return ChatMessagePresentation(text: message.text, action: nil)
    }

    private func extractPathID(from text: String, marker: String) -> String? {
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        let suffix = text[markerRange.upperBound...]
        let rawID = suffix.prefix { character in
            !character.isWhitespace && character != "." && character != "," && character != ")" && character != "]"
        }
        let id = String(rawID).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private func cleanActionLinkText(_ text: String) -> String {
        var result = text
        for label in ["Открыть игру:", "Открыть поиск:"] {
            if let labelRange = result.range(of: label) {
                result = String(result[..<labelRange.lowerBound])
                break
            }
        }
        return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    }

    private func sendMessage() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingPhotos.isEmpty, !isSendingMessage else {
            return
        }

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
            let message = try await appModel.repository.sendMessage(
                matchId: currentMatch.id,
                text: trimmed,
                attachmentIds: attachmentIds
            )
            messagesLoadRevision += 1 // Invalidate history requests that began before this send completed.
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
            }
            text = ""
            pendingPhotos = []
            photoPickerItems = []
            AppHaptics.selection()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func loadPendingPhotos(from items: [PhotosPickerItem]) async {
        var loaded: [PendingMatchChatPhoto] = []
        for (index, item) in items.prefix(4).enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                continue
            }
            let uploadData = image.jpegData(compressionQuality: 0.88) ?? data
            loaded.append(
                PendingMatchChatPhoto(
                    data: uploadData,
                    image: image,
                    fileName: "chat-photo-\(index + 1).jpg",
                    mimeType: "image/jpeg"
                )
            )
        }
        pendingPhotos = loaded
    }

    private func removePendingPhoto(_ photo: PendingMatchChatPhoto) {
        guard let index = pendingPhotos.firstIndex(where: { $0.id == photo.id }) else {
            return
        }
        pendingPhotos.remove(at: index)
        if photoPickerItems.indices.contains(index) {
            photoPickerItems.remove(at: index)
        }
    }
}

private struct ChatMessagePresentation {
    let text: String
    let action: ChatMessageAction?
}

private struct PendingMatchChatPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
    let fileName: String
    let mimeType: String
}

private struct MatchChatMediaViewer: View {
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

private struct ChatMessageAction {
    let title: String
    let systemImage: String
    let target: AppNavigationTarget
}

private struct ChatBubble: View {
    let text: String
    let attachments: [ChatMediaAttachment]
    let timestamp: String
    let sender: String
    let avatarPath: String?
    let isMine: Bool
    let receipt: ChatReceipt?
    let actionTitle: String?
    let actionSystemImage: String?
    let onAction: (() -> Void)?
    let onAvatarTap: (() -> Void)?
    let onAttachmentTap: (ChatMediaAttachment) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isMine {
                Spacer(minLength: 48)
            } else {
                if let onAvatarTap {
                    Button(action: onAvatarTap) {
                        RemoteAvatarView(name: sender, path: avatarPath, size: 42)
                            .overlay(Circle().stroke(AppTheme.court.opacity(0.72), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                } else {
                    RemoteAvatarView(name: sender, path: avatarPath, size: 42)
                        .overlay(Circle().stroke(AppTheme.court.opacity(0.72), lineWidth: 1.5))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if !attachments.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: attachments.count == 1 ? 1 : 2),
                        spacing: 6
                    ) {
                        ForEach(attachments.sorted(by: { $0.position < $1.position })) { attachment in
                            Button {
                                onAttachmentTap(attachment)
                            } label: {
                                RemoteChatMediaImage(path: attachment.url)
                                .frame(width: attachments.count == 1 ? 210 : 100, height: attachments.count == 1 ? 180 : 100)
                                .background(.black.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(isMine ? .white : AppTheme.ink)
                }

                if let actionTitle, let onAction {
                    Button(action: onAction) {
                        Label(actionTitle, systemImage: actionSystemImage ?? "arrow.up.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isMine ? Color.black.opacity(0.88) : .white)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(isMine ? Color.white.opacity(0.92) : AppTheme.court, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    Text(timestamp)
                        .font(.caption2)
                        .foregroundStyle(isMine ? .white.opacity(0.72) : AppTheme.ink.opacity(0.42))
                    if isMine { ChatReceiptLabel(receipt: receipt) }
                }
            }
            .padding(14)
            .background(
                isMine
                    ? LinearGradient(colors: [AppTheme.court, AppTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.white.opacity(0.94), AppTheme.creamLight.opacity(0.96)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(isMine ? 0.12 : 0.82), lineWidth: 1)
            )

            if !isMine {
                Spacer(minLength: 48)
            }
        }
    }
}

private struct ChatSystemEventRow: View {
    let title: String
    let timestamp: String
    let onTap: (() -> Void)?

    var body: some View {
        HStack {
            Spacer(minLength: 24)

            Button {
                onTap?()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "photo.stack.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.court)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text(timestamp)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.52))
                    }

                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(AppTheme.court.opacity(0.8))
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(AppTheme.mint, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.court.opacity(onTap == nil ? 0.28 : 0.46), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            Spacer(minLength: 24)
        }
    }
}

private extension ChatMessage {
    var isGameReportSystemEvent: Bool {
        let normalized = text.lowercased()
        return normalized.contains("фотоотчёт") || normalized.contains("фотоотчет")
    }

    var gameReportSystemTitle: String {
        let normalized = text.lowercased()

        if normalized.contains("добав") || normalized.contains("загруж") {
            return L10n.string("Photo report uploaded", "Фотоотчёт загружен")
        }

        return text
    }
}

private extension Sport {
    var purposeTitle: String {
        switch self {
        case .tableTennis:
            return "настольного тенниса"
        case .tennis:
            return "тенниса"
        case .padel:
            return "падела"
        case .squash:
            return "сквоша"
        case .badminton:
            return "бадминтона"
        case .volleyball:
            return "волейбола"
        case .fitness:
            return "фитнеса"
        case .boxing:
            return "бокса"
        case .yoga:
            return "йоги"
        case .football:
            return "футбола"
        case .running:
            return "бега"
        case .supboard:
            return "сапборда"
        }
    }

    var localizedPurposeTitle: String {
        switch self {
        case .tableTennis: return L10n.string("table tennis", purposeTitle)
        case .tennis: return L10n.string("tennis", purposeTitle)
        case .padel: return L10n.string("padel", purposeTitle)
        case .squash: return L10n.string("squash", purposeTitle)
        case .badminton: return L10n.string("badminton", purposeTitle)
        case .volleyball: return L10n.string("volleyball", purposeTitle)
        case .fitness: return L10n.string("fitness", purposeTitle)
        case .boxing: return L10n.string("boxing", purposeTitle)
        case .yoga: return L10n.string("yoga", purposeTitle)
        case .football: return L10n.string("football", purposeTitle)
        case .running: return L10n.string("running", purposeTitle)
        case .supboard: return L10n.string("SUP", purposeTitle)
        }
    }
}

private struct MatchPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let match: MatchSummary
    let onOpenChat: () -> Void
    let onProposeGame: () -> Void
    let onBlocked: () -> Void

    init(match: MatchSummary, onOpenChat: @escaping () -> Void, onProposeGame: @escaping () -> Void, onBlocked: @escaping () -> Void = {}) {
        self.match = match
        self.onOpenChat = onOpenChat
        self.onProposeGame = onProposeGame
        self.onBlocked = onBlocked
    }

    @State private var gameHistory: [MatchGameRequest] = []
    @State private var isLoadingHistory = false

    private var commonSports: [Sport] {
        let mySports = appModel.currentUser?.preferredSports ?? []
        let common = Set(mySports).intersection(match.otherUser.preferredSports)
        if !common.isEmpty {
            return match.otherUser.preferredSports.filter { common.contains($0) }
        }
        return match.otherUser.preferredSports
    }

    private var primarySport: Sport {
        commonSports.first ?? match.otherUser.preferredSports.first ?? .tennis
    }

    private var sportsSummary: String {
        let titles = commonSports.prefix(3).map(\.title)
        return titles.isEmpty ? L10n.string("Sport to be confirmed", "Спорт уточняется") : titles.joined(separator: " · ")
    }

    private var levelSummary: String {
        let level = match.otherUser.sportLevels[primarySport.rawValue] ?? match.otherUser.tennisLevel
        guard let level else {
            return L10n.string("level not specified", "уровень не указан")
        }
        return "\(level)/10"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: match.otherUser.displayName, subtitle: match.otherUser.bio ?? L10n.string("A player from your matches.", "Игрок из твоего мэтча.")) {
                    HStack(alignment: .top, spacing: 14) {
                        RemoteAvatarView(name: match.otherUser.displayName, path: match.otherUser.avatarUrl, size: 92)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(Array(match.otherUser.districtDisplayNames.prefix(3)), id: \.self) { district in
                                    AppInlineChip(
                                        text: district,
                                        tint: AppTheme.mint,
                                        foreground: AppTheme.court
                                    )
                                }
                            }

                            if let age = match.otherUser.age, let city = match.otherUser.city {
                                Text(L10n.string("\(age) years old, \(city)", "\(age) лет, \(city)"))
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                            }

                            sportChips
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                }

                SectionCard(
                    title: L10n.string("Why you should play", "Почему вам стоит сыграть"),
                    subtitle: L10n.string("Based on your match, preferred areas, sport, and level.", "Пока это базовые причины: мэтч, районы для игры, спорт и уровень.")
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        MatchReasonRow(
                            systemImage: "checkmark.seal.fill",
                            text: L10n.string("You already matched, so you can start planning right away.", "У вас уже есть мэтч — можно сразу переходить к делу.")
                        )
                        MatchReasonRow(
                            systemImage: "location.fill",
                            text: L10n.string("Preferred areas: \(match.otherUser.districtDisplaySummary)", "Удобные районы: \(match.otherUser.districtDisplaySummary)")
                        )
                        MatchReasonRow(
                            systemImage: "sportscourt",
                            text: L10n.string("Sport in common: \(sportsSummary)", "Общий спорт: \(sportsSummary)")
                        )
                        MatchReasonRow(
                            systemImage: "chart.bar.fill",
                            text: L10n.string("\(primarySport.title) level: \(levelSummary)", "Уровень в \(primarySport.title): \(levelSummary)")
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionCard(
                    title: L10n.string("What's next", "Что дальше"),
                    subtitle: L10n.string("Starting with a chat is usually fastest. Create a game proposal when you want to set a time.", "Обычно быстрее всего начать с чата. Если хочешь зафиксировать время — создай предложение игры.")
                ) {
                    VStack(spacing: 12) {
                        Button(action: onOpenChat) {
                            Label(L10n.string("Open chat", "Открыть чат"), systemImage: "message.fill")
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))

                        Button(action: onProposeGame) {
                            Label(L10n.string("Propose a game", "Предложить игру"), systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.court))

                        Text(L10n.string("Tip: suggest 2–3 times and one convenient venue to make planning faster.", "Совет: предложи 2–3 времени и один короткий вариант места — так быстрее договориться."))
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SectionCard(title: L10n.string("Safety", "Безопасность"), subtitle: L10n.string("You can report this player to moderators or hide them completely.", "Можно пожаловаться модератору или полностью скрыть пользователя.")) {
                    UserSafetyActions(
                        userId: match.otherUser.id,
                        displayName: match.otherUser.displayName,
                        context: .profile(userId: match.otherUser.id),
                        onBlocked: {
                            dismiss()
                            onBlocked()
                        }
                    )
                }

                if let request = match.latestGameRequest {
                    SectionCard(title: L10n.string("Latest game proposal", "Последнее предложение игры"), subtitle: request.comment ?? L10n.string("This game is already linked to your match.", "Договоренность уже заведена в мэтче.")) {
                        VStack(alignment: .leading, spacing: 10) {
                            AppInlineChip(text: request.statusLabel.localizedMatchesText, tint: request.statusTintColor, foreground: .white)
                            HStack(spacing: 8) {
                                AppInlineChip(text: request.sport.title, tint: AppTheme.cream, foreground: AppTheme.ink)
                                AppInlineChip(text: request.effectiveFormatTitle, tint: AppTheme.cream, foreground: AppTheme.ink)
                            }
                            AppInlineChip(text: request.proposedDatetime.formattedDateTime(), tint: AppTheme.ink, foreground: .white)
                            if let court = request.proposedCourt {
                                Text("\(court.name), \(court.address)")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                            }
                            Text(request.nextStepLabel.localizedMatchesText)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    }
                }

                if isLoadingHistory {
                    SectionCard(title: L10n.string("Games", "Договоренности"), subtitle: L10n.string("Loading game history for this match.", "Загружаю историю игр в этом мэтче.")) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(L10n.string("Loading games", "Загружаю договоренности"))
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if !gameHistory.isEmpty {
                    SectionCard(title: L10n.string("Games", "Договоренности"), subtitle: L10n.string("Current and past games. Tap one to open it in Upcoming Games.", "Текущие и прошлые игры. Нажми, чтобы открыть их в ближайших играх.")) {
                        VStack(spacing: 10) {
                            ForEach(gameHistory) { request in
                                Button {
                                    dismiss()
                                    appModel.navigate(to: .discover(.upcoming, highlightedGameRequestID: request.id))
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(request.proposedDatetime.formattedNumericDateTime())
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(AppTheme.ink)
                                                .lineLimit(1)
                                            Text(request.proposedCourt?.name ?? request.sport.venueUnspecifiedTitle)
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.ink.opacity(0.62))
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 0)

                                        AppInlineChip(text: request.statusLabel.localizedMatchesText, tint: request.statusTintColor, foreground: .white)
                                    }
                                    .padding(12)
                                    .background(request.statusSurfaceColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await loadHistory()
        }
    }

    private var sportChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(match.otherUser.preferredSports.prefix(4)) { sport in
                    let level = match.otherUser.sportLevels[sport.rawValue]
                    SportLevelMiniChip(sport: sport, level: level)
                }
            }
        }
    }

    private func loadHistory() async {
        if appModel.isUsingMockData {
            gameHistory = match.latestGameRequest.map { [$0] } ?? []
            return
        }

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let requests = try await appModel.repository.fetchMyGameRequests()
            gameHistory = requests
                .filter { $0.matchId == match.id }
                .sorted { $0.proposedDatetime > $1.proposedDatetime }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            gameHistory = match.latestGameRequest.map { [$0] } ?? []
        }
    }
}

private struct MatchReasonRow: View {
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

enum ProposalSheetContext {
    case new
    case edit
    case reschedule
    case relocate

    var title: String {
        switch self {
        case .new:
            return L10n.string("Propose a game", "Предложить игру")
        case .edit:
            return L10n.string("Edit proposal", "Изменить предложение")
        case .reschedule:
            return L10n.string("Suggest another time", "Предложить другое время")
        case .relocate:
            return L10n.string("Suggest another venue", "Предложить другое место")
        }
    }

    var subtitlePrefix: String {
        switch self {
        case .new:
            return L10n.string("Create a new game", "Создай новую договоренность")
        case .edit:
            return L10n.string("Update the current game", "Обнови текущую договоренность")
        case .reschedule:
            return L10n.string("Update the game time", "Обнови время договоренности")
        case .relocate:
            return L10n.string("Update the game venue", "Обнови место договоренности")
        }
    }

    var submitTitle: String {
        switch self {
        case .new:
            return L10n.string("Send proposal", "Отправить предложение")
        case .edit:
            return L10n.string("Save changes", "Сохранить изменения")
        case .reschedule:
            return L10n.string("Send new time", "Отправить новое время")
        case .relocate:
            return L10n.string("Send new venue", "Отправить новое место")
        }
    }
}

struct GameProposalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appModel: AppModel

    let match: MatchSummary
    let context: ProposalSheetContext
    let seedRequest: MatchGameRequest?
    let initialCourt: Court?
    let onCreated: () async -> Void

    @State private var courts: [Court] = []
    @State private var isLoadingCourts = false
    @State private var isSubmitting = false
    @State private var isClubPickerPresented = false
    @State private var localError: String?
    @State private var draft: GameProposalDraft
    @State private var isExactDateTimeSelected = false
    @State private var isGameUpdateCelebrationPresented = false
    @State private var requiresBookingDateTimeChange = false
    @State private var bookingDateTimeBaseline: Date?
    @StateObject private var bookingCallFlow = BookingCallFlow()

    init(
        match: MatchSummary,
        context: ProposalSheetContext = .new,
        seedRequest: MatchGameRequest? = nil,
        initialCourt: Court? = nil,
        onCreated: @escaping () async -> Void
    ) {
        self.match = match
        self.context = context
        self.seedRequest = seedRequest
        self.initialCourt = initialCourt
        self.onCreated = onCreated

        let sourceRequest = context == .new ? seedRequest : (seedRequest ?? match.latestGameRequest)
        let sourceCourt = sourceRequest?.proposedCourt ?? initialCourt
        let courtSports = sourceCourt?.supportedSports ?? []
        let preferredCourtSport = match.otherUser.preferredSports.first { courtSports.contains($0) }
            ?? courtSports.first
            ?? sourceCourt?.primarySport
        let preferredSport = sourceRequest?.sport ?? preferredCourtSport ?? match.otherUser.preferredSports.first ?? .tennis
        let preferredFormat = sourceRequest?.format ?? preferredSport.defaultFormat
        let defaultLevel = match.otherUser.sportLevels[preferredSport.rawValue] ?? match.otherUser.tennisLevel ?? 5
        let proposalDate = Self.initialProposalDate(from: sourceRequest?.proposedDate)

        _draft = State(initialValue: GameProposalDraft(
            proposedCourtId: initialCourt?.id ?? (context == .new ? nil : sourceCourt?.id),
            proposedDatetime: proposalDate,
            durationMinutes: sourceRequest?.durationMinutes ?? 90,
            levelRangeMin: max(defaultLevel - 1, 1),
            levelRangeMax: min(defaultLevel + 1, 10),
            sport: preferredSport,
            format: preferredFormat,
            comment: sourceRequest?.comment ?? ""
        ))
        _isExactDateTimeSelected = State(initialValue: sourceRequest != nil)
    }

    private var availableSports: [Sport] {
        if let courtSports = initialCourt?.supportedSports, !courtSports.isEmpty {
            return courtSports
        }

        let mySports = appModel.currentUser?.preferredSports ?? []
        let candidateSports = mySports + match.otherUser.preferredSports + Sport.allCases
        var seen = Set<String>()
        return candidateSports.filter { sport in
            seen.insert(sport.rawValue).inserted
        }
    }

    private static func initialProposalDate(from sourceDate: Date?) -> Date {
        let calendar = Calendar.current
        let now = Date()

        guard let sourceDate else {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
            return calendar.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }

        guard sourceDate <= now else {
            return sourceDate
        }

        let components = calendar.dateComponents([.hour, .minute], from: sourceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
        return calendar.date(
            bySettingHour: components.hour ?? 19,
            minute: components.minute ?? 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    private var selectedCourt: Court? {
        guard let proposedCourtId = draft.proposedCourtId else {
            return nil
        }

        return filteredCourts.first(where: { $0.id == proposedCourtId })
            ?? courts.first(where: { $0.id == proposedCourtId })
    }

    private var proposalSummaryTitle: String {
        proposalDateTimeText(for: draft.proposedDatetime)
    }

    private var proposalSummarySubtitle: String {
        [
            draft.sport.title,
            draft.sport.formatTitle(format: draft.format).localizedMatchesText,
            selectedCourt?.name ?? draft.sport.venuePendingTitle.localizedMatchesText
        ].joined(separator: " · ")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        proposalHeader
                        proposalHero
                        sportSelector
                        dateTimeSection
                            .id("dateTimeSection")
                        courtSection
                        levelSection
                        commentSection
                        submitSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }

                if isGameUpdateCelebrationPresented {
                    SuccessCelebrationOverlay(
                        title: L10n.string("Game updated", "Игра изменена"),
                        subtitle: L10n.string("Waiting for your partner's confirmation", "Ждем подтверждения партнера"),
                        icon: "✅"
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadCourtsIfNeeded()
            }
            .sheet(isPresented: $isClubPickerPresented) {
                SearchClubPickerSheet(
                    sport: draft.sport,
                    courts: filteredCourts,
                    selectedCourtId: draft.proposedCourtId,
                    selectsImmediately: false,
                    allowsNoCourt: true,
                    onSelect: { court in
                        bookingCallFlow.reset()
                        guard let court else {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                draft.proposedCourtId = nil
                            }
                            return
                        }
                        selectCourt(court)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .confirmationDialog(
                L10n.string("Were you able to book?", "Удалось забронировать?"),
                isPresented: $bookingCallFlow.isResultPresented,
                titleVisibility: .visible
            ) {
                Button(L10n.string("Yes, the time matches", "Да, время совпало")) {
                    clearBookingDateTimeRequirement()
                }
                Button(L10n.string("Booked a different time", "Забронировал на другое время")) {
                    bookingDateTimeBaseline = draft.proposedDatetime
                    requiresBookingDateTimeChange = true
                    localError = L10n.string("Update the date or time to match the actual booking", "Измените дату или время на фактически забронированные")
                    Task { @MainActor in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("dateTimeSection", anchor: .top)
                        }
                    }
                }
                Button(L10n.string("I didn't book", "Не забронировал")) {
                    clearBookingDateTimeRequirement()
                }
                Button(L10n.string("Cancel", "Отмена"), role: .cancel) {}
            } message: {
                Text(L10n.string("Confirm the booking or update the proposal's date and time.", "Подтвердите бронь или измените дату и время предложения."))
            }
            .onChange(of: scenePhase) { phase in
                bookingCallFlow.handle(scenePhase: phase)
            }
            .onDisappear {
                bookingCallFlow.reset()
            }
        }
    }

    private var filteredCourts: [Court] {
        let sportCourts = courts.filter { court in
            guard let sports = court.supportedSports, !sports.isEmpty else {
                return true
            }
            return sports.contains(draft.sport)
        }
        return sportCourts.isEmpty ? courts : sportCourts
    }

    private var proposalHeader: some View {
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

            Text(context.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer()

            RemoteAvatarView(name: match.otherUser.displayName, path: match.otherUser.avatarUrl, size: 44)
        }
    }

    private var proposalHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.court.opacity(0.13))
                        .frame(width: 54, height: 54)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.court)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.string("\(context.subtitlePrefix) with \(match.otherUser.displayName)", "\(context.subtitlePrefix) с \(match.otherUser.displayName)"))
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.string("Choose a sport, time, and venue. The other player will see the proposal in Matches and can confirm it.", "Выбери спорт, время и клуб. Второй игрок увидит предложение в мэтче и сможет подтвердить игру."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.56))
                        .lineSpacing(3)
                }
            }

            HStack(spacing: 10) {
                proposalSummaryPill(systemImage: "clock", title: proposalSummaryTitle)
                proposalSummaryPill(systemImage: "sportscourt", title: draft.sport.title)
            }

            Text(proposalSummarySubtitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.court)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(18)
        .background(AppTheme.mint.opacity(0.72), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.court.opacity(0.12), lineWidth: 1)
        )
    }

    private func proposalSummaryPill(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.ink.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white.opacity(0.74), in: Capsule())
    }

    private var sportSelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("What are you playing?", "Что играем?"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(L10n.string("Sport", "Вид спорта"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.court)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableSports) { sport in
                        let isSelected = draft.sport == sport
                        let level = appModel.currentUser?.sportLevels[sport.rawValue] ?? appModel.currentUser?.tennisLevel
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

                                if let level {
                                    Text(L10n.string("lvl \(level)", "ур. \(level)"))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(isSelected ? AppTheme.court : AppTheme.ink.opacity(0.54))
                                }
                            }
                            .frame(width: 98, height: 126)
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
                ForEach(draft.sport.allowedFormats, id: \.rawValue) { format in
                    let isSelected = draft.format == format
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            draft.format = format
                        }
                    } label: {
                        Text(draft.sport.formatTitle(format: format).localizedMatchesText)
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

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("When are you playing?", "Когда играем?"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            if requiresBookingDateTimeChange {
                Label(L10n.string("Enter the actual booking date or time", "Укажите дату или время фактической брони"), systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                proposalDayButton(title: L10n.string("Today", "Сегодня"), offset: 0)
                proposalDayButton(title: L10n.string("Tomorrow", "Завтра"), offset: 1)
                proposalDayButton(title: L10n.string("Day after tomorrow", "Послезавтра"), offset: 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(proposalQuickTimes, id: \.self) { time in
                        proposalTimeButton(time)
                    }
                }
            }

            DatePicker(
                L10n.string("Exact date and time", "Точная дата и время"),
                selection: Binding(
                    get: { draft.proposedDatetime },
                    set: { nextDate in
                        draft.proposedDatetime = clampedFutureDate(nextDate)
                        isExactDateTimeSelected = true
                        markBookingDateTimeChanged()
                    }
                ),
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isExactDateTimeSelected ? AppTheme.court : AppTheme.ink)
            .datePickerStyle(.compact)
            .tint(AppTheme.court)
            .padding(16)
            .background(isExactDateTimeSelected ? AppTheme.mint.opacity(0.86) : Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isExactDateTimeSelected ? AppTheme.court.opacity(0.58) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func proposalDayButton(title: String, offset: Int) -> some View {
        let targetDate = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let selected = !isExactDateTimeSelected && Calendar.current.isDate(draft.proposedDatetime, inSameDayAs: targetDate)

        return Button {
            setProposalDay(offset: offset)
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Text(proposalDateSubtitle(for: targetDate))
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.72)
            }
            .foregroundStyle(selected ? .white : AppTheme.ink.opacity(0.82))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(selected ? AppTheme.court : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func proposalTimeButton(_ time: String) -> some View {
        let selected = !isExactDateTimeSelected && draft.proposedDatetime.formattedHourMinute() == time

        return Button {
            setProposalTime(time)
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

    private var courtSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(draft.sport.venueFieldTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if !filteredCourts.isEmpty {
                    Button {
                        AppHaptics.selection()
                        isClubPickerPresented = true
                    } label: {
                        Label(L10n.string("Choose on map", "Выбрать на карте"), systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.court)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isLoadingCourts {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.string("Loading venues", "Загружаем места"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if filteredCourts.isEmpty {
                Text(L10n.string("No venues available for this sport", "Нет доступных мест для этого спорта"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.58))
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                selectedCourtCard
            }
        }
    }

    private var selectedCourtCard: some View {
        let court = selectedCourt

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                AppHaptics.selection()
                isClubPickerPresented = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.mint)
                            .frame(width: 46, height: 46)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(AppTheme.court)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(court?.name ?? L10n.string("Choose a venue", "Выбери клуб"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                        Text(courtSubtitle(court))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.ink.opacity(0.55))
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 5) {
                        Image(systemName: court == nil ? "chevron.right.circle" : "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(court == nil ? AppTheme.ink.opacity(0.24) : AppTheme.court)
                        Text(court == nil ? L10n.string("Choose", "Выбрать") : L10n.string("Change", "Изменить"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.court)
                    }
                }
            }
            .buttonStyle(.plain)

            if let phoneURL = court?.phoneURL {
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
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var levelSection: some View {
        HStack(alignment: .top, spacing: 14) {
            proposalLevelCard(
                title: L10n.string("Min. level", "Мин. уровень"),
                value: Binding(
                    get: { draft.levelRangeMin ?? 1 },
                    set: { newValue in
                        draft.levelRangeMin = min(newValue, draft.levelRangeMax ?? 10)
                    }
                )
            )

            proposalLevelCard(
                title: L10n.string("Max. level", "Макс. уровень"),
                value: Binding(
                    get: { draft.levelRangeMax ?? 10 },
                    set: { newValue in
                        draft.levelRangeMax = max(newValue, draft.levelRangeMin ?? 1)
                    }
                )
            )
        }
    }

    private func proposalLevelCard(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 8) {
                levelAdjustButton(systemImage: "minus", isDisabled: value.wrappedValue <= 1) {
                    value.wrappedValue -= 1
                }

                Text("\(value.wrappedValue)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                levelAdjustButton(systemImage: "plus", isDisabled: value.wrappedValue >= 10) {
                    value.wrappedValue += 1
                }
            }
            .frame(height: 48)
            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 6) {
                ForEach(1 ... 5, id: \.self) { index in
                    Capsule()
                        .fill(index <= Int(ceil(Double(value.wrappedValue) / 2.0)) ? AppTheme.court : Color.black.opacity(0.08))
                        .frame(height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func levelAdjustButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(isDisabled ? AppTheme.ink.opacity(0.25) : AppTheme.ink)
                .frame(width: 38, height: 38)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
                TextField(L10n.string("For example: anytime after 7 PM", "Например: удобно после 19:00"), text: $draft.comment, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var submitSection: some View {
        VStack(spacing: 10) {
            if let localError, !localError.isEmpty {
                Text(localError)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    await submitProposal()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(context.submitTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(isSubmitting || requiresBookingDateTimeChange)

            Button(L10n.string("Cancel", "Отмена")) {
                dismiss()
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
        }
    }

    private var proposalQuickTimes: [String] {
        Array(stride(from: 8 * 60, through: 22 * 60 + 30, by: 30)).map { minutes in
            String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
    }

    private func loadCourtsIfNeeded() async {
        guard courts.isEmpty else {
            return
        }

        isLoadingCourts = true
        defer { isLoadingCourts = false }

        do {
            courts = try await appModel.repository.fetchCourts()
            if let proposedCourtId = draft.proposedCourtId,
               courts.contains(where: { $0.id == proposedCourtId }) {
                return
            }
            draft.proposedCourtId = initialCourt?.id
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            localError = error.localizedDescription
        }
    }

    private func applySportSelection(_ sport: Sport) {
        AppHaptics.selection()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            draft.sport = sport
            draft.format = sport.resolveFormat(draft.format)
            if let proposedCourtId = draft.proposedCourtId,
               !filteredCourts.contains(where: { $0.id == proposedCourtId }) {
                bookingCallFlow.reset()
                draft.proposedCourtId = nil
            }
        }
    }

    private func selectCourt(_ court: Court) {
        AppHaptics.selection()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            draft.proposedCourtId = court.id
        }
    }

    private func setProposalDay(offset: Int) {
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let currentComponents = calendar.dateComponents([.hour, .minute], from: draft.proposedDatetime)
        let nextDate = calendar.date(
            bySettingHour: currentComponents.hour ?? 19,
            minute: currentComponents.minute ?? 0,
            second: 0,
            of: targetDay
        ) ?? targetDay
        draft.proposedDatetime = clampedFutureDate(nextDate)
        isExactDateTimeSelected = false
        markBookingDateTimeChanged()
        AppHaptics.selection()
    }

    private func setProposalTime(_ time: String) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else {
            return
        }

        let calendar = Calendar.current
        let nextDate = calendar.date(
            bySettingHour: parts[0],
            minute: parts[1],
            second: 0,
            of: draft.proposedDatetime
        ) ?? draft.proposedDatetime
        draft.proposedDatetime = clampedFutureDate(nextDate)
        isExactDateTimeSelected = false
        markBookingDateTimeChanged()
        AppHaptics.selection()
    }

    private func clampedFutureDate(_ date: Date) -> Date {
        let now = Date()
        guard date <= now else {
            return date
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
        return calendar.date(
            bySettingHour: components.hour ?? 19,
            minute: components.minute ?? 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    private func proposalDateSubtitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.string("en_US", "ru_RU"))
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    private func courtSubtitle(_ court: Court?) -> String {
        guard let court else {
            return L10n.string("You can confirm the venue later", "Место можно уточнить позже")
        }

        let subtitle = [
            court.metroDisplayName,
            localizedDistrictName(court.district),
            court.distanceLabel
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return subtitle.isEmpty ? court.address : subtitle
    }

    private func proposalDateTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.string("en_US", "ru_RU"))
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    private func proposalSportIconName(for sport: Sport) -> String {
        sport.appSystemIconName
    }

    private func submitProposal() async {
        guard !requiresBookingDateTimeChange else {
            localError = L10n.string("Update the date or time to match the actual booking", "Измените дату или время на фактически забронированные")
            return
        }

        guard draft.proposedDatetime > Date() else {
            localError = L10n.string("Choose a future date and time", "Выбери будущую дату и время")
            draft.proposedDatetime = clampedFutureDate(draft.proposedDatetime)
            return
        }

        isSubmitting = true
        localError = nil
        defer { isSubmitting = false }

        do {
            if context != .new, let requestId = seedRequest?.id {
                _ = try await appModel.repository.updateGameRequest(gameRequestId: requestId, draft: draft)
                AppHaptics.successCelebration()
                withAnimation(.easeInOut(duration: 0.18)) {
                    isGameUpdateCelebrationPresented = true
                }
                try? await Task.sleep(for: .milliseconds(1700))
            } else {
                _ = try await appModel.repository.createGameRequest(matchId: match.id, draft: draft)
                AppHaptics.notification(.success)
            }
            await onCreated()
            dismiss()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            localError = error.localizedDescription
        }
    }

    private func markBookingDateTimeChanged() {
        guard requiresBookingDateTimeChange,
              let bookingDateTimeBaseline,
              Calendar.current.compare(
                  draft.proposedDatetime,
                  to: bookingDateTimeBaseline,
                  toGranularity: .minute
              ) != .orderedSame else {
            return
        }
        clearBookingDateTimeRequirement()
    }

    private func clearBookingDateTimeRequirement() {
        requiresBookingDateTimeChange = false
        bookingDateTimeBaseline = nil
        clearBookingDateTimeError()
    }

    private func clearBookingDateTimeError() {
        if localError == L10n.string("Update the date or time to match the actual booking", "Измените дату или время на фактически забронированные") {
            localError = nil
        }
    }
}
