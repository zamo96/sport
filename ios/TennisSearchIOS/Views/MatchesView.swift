import SwiftUI

struct MatchesView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var matches: [MatchSummary] = []
    @State private var isLoading = false
    @State private var selectedProfileMatch: MatchSummary?
    @State private var selectedProposalMatch: MatchSummary?
    @State private var navigationMatch: MatchSummary?
    @State private var isChatPresented = false
    @State private var updatingRequestIDs: Set<String> = []
    @State private var selectedFilter: MatchListFilter = .all

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
                return !["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased())
            case .archive:
                guard let request = match.latestGameRequest else { return false }
                return ["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased()) || request.statusLabel == "Игра закончилась"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                matchesHeader
                matchesFilterRail

                if filteredMatches.isEmpty, !isLoading {
                    SectionCard(title: "Пока нет мэтчей", subtitle: nil) {
                        EmptyStateView(
                            title: "Пока нет мэтчей",
                            subtitle: "Поставь несколько лайков в поиске. Взаимные интересы автоматически появятся здесь.",
                            systemImage: "message.badge"
                        )
                    }
                }

                ForEach(filteredMatches, id: \.id) { match in
                    MatchInboxCard(
                        match: match,
                        currentUserId: appModel.currentUser?.id,
                        isUpdating: match.latestGameRequest.map { updatingRequestIDs.contains($0.id) } ?? false,
                        onOpenProfile: {
                            AppHaptics.selection()
                            selectedProfileMatch = match
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
                ChatView(match: navigationMatch)
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
    }

    private var matchesHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Мэтчи")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Text("Переписка, предложения игры и статусы договоренностей.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.08), in: Circle())
        }
    }

    private var matchesFilterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MatchListFilter.allCases) { filter in
                    let selected = selectedFilter == filter
                    let count = filter.count(in: matches, currentUserId: appModel.currentUser?.id)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text(filter.title)
                            if count > 0, filter != .all {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(selected ? AppTheme.ink : .white.opacity(0.9))
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(selected ? .white.opacity(0.88) : .white.opacity(0.12), in: Capsule())
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
        isLoading = true
        defer { isLoading = false }

        do {
            matches = try await appModel.repository.fetchMatches()
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

    var title: String {
        switch self {
        case .all:
            return "Все"
        case .new:
            return "Новые"
        case .action:
            return "Нужно действие"
        case .withGame:
            return "Есть игра"
        case .archive:
            return "Архив"
        }
    }

    func count(in matches: [MatchSummary], currentUserId: String?) -> Int {
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
                return !["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased())
            case .archive:
                guard let request = match.latestGameRequest else { return false }
                return ["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased()) || request.statusLabel == "Игра закончилась"
            }
        }
        .count
    }
}

private struct MatchInboxCard: View {
    let match: MatchSummary
    let currentUserId: String?
    let isUpdating: Bool
    let onOpenProfile: () -> Void
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
        return "уровень не указан"
    }

    private var timestampText: String {
        latestRequest?.proposedDatetime.formattedDateTime() ?? match.createdAt.formattedDateTime()
    }

    private var statusBadgeText: String {
        latestRequest?.statusLabel ?? "Новый мэтч"
    }

    private var statusBadgeTint: Color {
        latestRequest?.statusTintColor ?? Color(red: 0.36, green: 0.41, blue: 0.83)
    }

    private var statusBadgeSurface: Color {
        latestRequest?.statusSurfaceColor ?? Color(red: 0.16, green: 0.18, blue: 0.33)
    }

    private var matchReasonItems: [String] {
        let sportLine = "\(primarySport.title) · \(primarySport.formatTitle(format: match.otherUser.preferredPlayFormat))"
        let districtLine = match.otherUser.districtDisplayNames.first ?? match.otherUser.districtDisplaySummary
        let timeLine = match.otherUser.availableTimeRanges.compactMap { timeRangeTitle(for: $0) }.first ?? "Время уточняется"
        return [sportLine, districtLine, timeLine]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpenProfile) {
                    HStack(alignment: .top, spacing: 14) {
                        RemoteAvatarView(name: match.otherUser.displayName, path: match.otherUser.avatarUrl, size: 68)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color(red: 0.22, green: 0.82, blue: 0.45))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                            }

                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(match.otherUser.displayName)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)

                                    Text("\(primarySport.title) · \(primarySport.formatTitle(format: match.otherUser.preferredPlayFormat)) · \(primaryLevelLine)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color(red: 0.41, green: 0.86, blue: 0.56))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(timestampText)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.52))

                                    AppInlineChip(text: statusBadgeText, tint: statusBadgeSurface, foreground: statusBadgeTint)
                                }
                            }

                            Text(latestRequest?.comment ?? "Совпадение по ключевым параметрам")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), alignment: .leading, spacing: 8) {
                                matchReasonPill(systemImage: "tennis.racket", text: matchReasonItems[0])
                                matchReasonPill(systemImage: "location", text: matchReasonItems[1])
                                matchReasonPill(systemImage: "clock", text: matchReasonItems[2])
                                if let request = latestRequest {
                                    matchReasonPill(systemImage: "calendar", text: request.proposedDatetime.formattedDateTime())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 30, height: 30)
            }

            if let request = latestRequest {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(request.proposedCourt?.name ?? request.sport.venueUnspecifiedTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(request.nextStepLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    AppInlineChip(
                        text: request.proposedDatetime.formattedDateTime(),
                        tint: Color.white.opacity(0.08),
                        foreground: .white
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if canCancelPending {
                HStack(spacing: 10) {
                    matchActionButton(title: "Чат", systemImage: "message", tint: Color.white.opacity(0.08), foreground: .white.opacity(0.92), action: onOpenChat)
                    asyncMatchActionButton(title: "Отменить", systemImage: "xmark.circle", tint: Color(red: 0.32, green: 0.12, blue: 0.12), foreground: Color(red: 1.0, green: 0.47, blue: 0.43), isUpdating: isUpdating, action: onCancelRequest)
                }
            } else {
                HStack(spacing: 10) {
                    matchActionButton(title: latestRequest?.statusLabel == "Отменена" ? "Чат" : "Написать", systemImage: "message", tint: Color.white.opacity(0.08), foreground: .white.opacity(0.92), action: onOpenChat)
                    matchActionButton(title: latestRequest?.statusLabel == "Отменена" ? "Предложить заново" : "Предложить игру", systemImage: "calendar.badge.plus", tint: AppTheme.court, foreground: .white, action: onProposeGame)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
            return "Утро"
        case .day:
            return "День"
        case .evening:
            return "Вечер"
        }
    }
}

struct ChatView: View {
    @EnvironmentObject private var appModel: AppModel
    let match: MatchSummary

    @State private var currentMatch: MatchSummary
    @State private var messages: [ChatMessage] = []
    @State private var text = ""
    @State private var selectedProposalMatch: MatchSummary?
    @State private var proposalContext: ProposalSheetContext = .new
    @State private var isProfilePresented = false
    @State private var isUpdatingRequest = false
    @FocusState private var isComposerFocused: Bool
    private let bottomAnchorID = "chat-bottom-anchor"

    init(match: MatchSummary) {
        self.match = match
        _currentMatch = State(initialValue: match)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Button {
                            AppHaptics.selection()
                            isProfilePresented = true
                        } label: {
                            matchHeader
                        }
                        .buttonStyle(.plain)

                        ForEach(messages) { message in
                            let isMine = message.senderUserId == appModel.currentUser?.id
                            ChatBubble(
                                text: message.text,
                                timestamp: message.createdAt.formattedDateTime(),
                                sender: message.senderUser?.name ?? currentMatch.otherUser.displayName,
                                isMine: isMine
                            )
                            .id(message.id)
                        }

                        if let latestRequest = currentMatch.latestGameRequest {
                            proposalStatusCard(latestRequest)
                        } else {
                            proposalPromptCard
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
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
            }

            let hasActiveProposal = currentMatch.latestGameRequest.map { !isInactive($0) } ?? false
            Divider()
                .overlay(.white.opacity(0.08))
                .padding(.horizontal, 16)

            proposalShortcutButton(hasActiveProposal: hasActiveProposal)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()
                .overlay(.white.opacity(0.08))
                .padding(.horizontal, 16)

            HStack(alignment: .bottom, spacing: 10) {
                FieldShell {
                    TextField("Написать сообщение...", text: $text, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .focused($isComposerFocused)
                }

                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(AppTheme.court, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(currentMatch.otherUser.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    isComposerFocused = false
                }
            }
        }
        .task {
            await markSeen()
            await refreshChatState()
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = .hidden
            }
        }
        .onChange(of: isComposerFocused) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                appModel.bottomBarDisplayMode = .hidden
            }
        }
        .onDisappear {
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
                seedRequest: currentMatch.latestGameRequest
            ) {
                await refreshChatState()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
    }

    private var matchHeader: some View {
        HStack(spacing: 12) {
            RemoteAvatarView(name: currentMatch.otherUser.displayName, path: currentMatch.otherUser.avatarUrl, size: 58)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.82, blue: 0.45))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(currentMatch.otherUser.displayName)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)

                Text("Онлайн")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.32, green: 0.85, blue: 0.50))

                Text(currentMatch.otherUser.bio ?? currentMatch.otherUser.districtDisplaySummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func proposalStatusCard(_ request: MatchGameRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ПРЕДЛОЖЕНИЕ ИГРЫ")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                    Text(request.nextStepLabel)
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
                    Text("\(request.sport.title) · \(request.sport.formatTitle(format: request.format))")
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

            HStack(spacing: 10) {
                chatQuickActionButton(
                    title: isInactive(request) ? "Предложить заново" : "Изменить",
                    systemImage: isInactive(request) ? "calendar.badge.plus" : "square.and.pencil",
                    tint: isInactive(request) ? AppTheme.court : Color.white.opacity(0.06),
                    foreground: .white
                ) {
                    proposalContext = isInactive(request) ? .new : .edit
                    selectedProposalMatch = currentMatch
                }

                chatQuickAsyncActionButton(
                    title: "Отменить",
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
                    Text("Предложить игру")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Выберите дату, время, корт и отправьте предложение")
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

                Text(hasActiveProposal ? "Изменить игру" : "Предложить игру")
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
        Text(request.statusLabel)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(request.statusTintColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(request.statusSurfaceColor.opacity(0.95), in: Capsule())
    }

    private func chatActionsBar(for request: MatchGameRequest) -> some View {
        HStack(spacing: 10) {
            chatQuickActionButton(
                title: "Другое время",
                systemImage: "calendar.badge.clock",
                tint: Color.white.opacity(0.06),
                foreground: .white
            ) {
                proposalContext = .reschedule
                selectedProposalMatch = currentMatch
            }

            chatQuickActionButton(
                title: "Другое место",
                systemImage: "location",
                tint: Color.white.opacity(0.06),
                foreground: .white
            ) {
                proposalContext = .relocate
                selectedProposalMatch = currentMatch
            }

            chatQuickAsyncActionButton(
                title: isInactive(request) ? "Новая игра" : "Отменить",
                systemImage: isInactive(request) ? "calendar.badge.plus" : "xmark.circle",
                tint: isInactive(request) ? AppTheme.court : Color(red: 0.25, green: 0.10, blue: 0.10),
                foreground: isInactive(request) ? .white : Color(red: 1.0, green: 0.47, blue: 0.43),
                isUpdating: isUpdatingRequest
            ) {
                if isInactive(request) {
                    proposalContext = .new
                    selectedProposalMatch = currentMatch
                } else {
                    await cancelCurrentRequest(request)
                }
            }
        }
    }

    private func chatQuickActionButton(title: String, systemImage: String, tint: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            VStack(spacing: 10) {
                if isUpdating {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .disabled(isUpdating)
    }

    private func isInactive(_ request: MatchGameRequest) -> Bool {
        ["declined", "rejected", "withdrawn", "canceled", "cancelled"].contains(request.status.lowercased())
            || request.statusLabel == "Игра закончилась"
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

    private func loadMessages() async {
        do {
            messages = try await appModel.repository.fetchMessages(matchId: currentMatch.id)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func refreshMatch() async {
        do {
            let freshMatches = try await appModel.repository.fetchMatches()
            if let refreshed = freshMatches.first(where: { $0.id == currentMatch.id }) {
                currentMatch = refreshed
            }
        } catch {
            guard !error.isCancellationLike else {
                return
            }
        }
    }

    private func refreshChatState() async {
        await loadMessages()
        await refreshMatch()
        await appModel.notificationManager.manualRefresh(repository: appModel.repository)
    }

    private func sendMessage() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        do {
            let message = try await appModel.repository.sendMessage(matchId: currentMatch.id, text: trimmed)
            messages.append(message)
            text = ""
            isComposerFocused = false
            AppHaptics.selection()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }
}

private struct ChatBubble: View {
    let text: String
    let timestamp: String
    let sender: String
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !isMine {
                    Text(sender)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                }

                Text(text)
                    .font(.body)
                    .foregroundStyle(isMine ? .white : AppTheme.ink)

                Text(timestamp)
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

private struct MatchPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let match: MatchSummary
    let onOpenChat: () -> Void
    let onProposeGame: () -> Void

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
        return titles.isEmpty ? "Спорт уточняется" : titles.joined(separator: " · ")
    }

    private var levelSummary: String {
        let level = match.otherUser.sportLevels[primarySport.rawValue] ?? match.otherUser.tennisLevel
        guard let level else {
            return "уровень не указан"
        }
        return "\(level)/10"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SectionCard(title: match.otherUser.displayName, subtitle: match.otherUser.bio ?? "Игрок из твоего мэтча.") {
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
                                Text("\(age) лет, \(city)")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                            }

                            sportChips
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                }

                SectionCard(
                    title: "Почему вам стоит сыграть",
                    subtitle: "Пока это базовые причины: мэтч, районы для игры, спорт и уровень."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        MatchReasonRow(
                            systemImage: "checkmark.seal.fill",
                            text: "У вас уже есть мэтч — можно сразу переходить к делу."
                        )
                        MatchReasonRow(
                            systemImage: "location.fill",
                            text: "Удобные районы: \(match.otherUser.districtDisplaySummary)"
                        )
                        MatchReasonRow(
                            systemImage: "sportscourt",
                            text: "Общий спорт: \(sportsSummary)"
                        )
                        MatchReasonRow(
                            systemImage: "chart.bar.fill",
                            text: "Уровень в \(primarySport.title): \(levelSummary)"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionCard(
                    title: "Что дальше",
                    subtitle: "Обычно быстрее всего начать с чата. Если хочешь зафиксировать время — создай предложение игры."
                ) {
                    VStack(spacing: 12) {
                        Button(action: onOpenChat) {
                            Label("Открыть чат", systemImage: "message.fill")
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))

                        Button(action: onProposeGame) {
                            Label("Предложить игру", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.court))

                        Text("Совет: предложи 2–3 времени и один короткий вариант места — так быстрее договориться.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let request = match.latestGameRequest {
                    SectionCard(title: "Последнее предложение игры", subtitle: request.comment ?? "Договоренность уже заведена в мэтче.") {
                        VStack(alignment: .leading, spacing: 10) {
                            AppInlineChip(text: request.statusLabel, tint: request.statusTintColor, foreground: .white)
                            HStack(spacing: 8) {
                                AppInlineChip(text: request.sport.title, tint: AppTheme.cream, foreground: AppTheme.ink)
                                AppInlineChip(text: request.sport.formatTitle(format: request.format), tint: AppTheme.cream, foreground: AppTheme.ink)
                            }
                            AppInlineChip(text: request.proposedDatetime.formattedDateTime(), tint: AppTheme.ink, foreground: .white)
                            if let court = request.proposedCourt {
                                Text("\(court.name), \(court.address)")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                            }
                            Text(request.nextStepLabel)
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    }
                }

                if isLoadingHistory {
                    SectionCard(title: "Договоренности", subtitle: "Загружаю историю игр в этом мэтче.") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Загружаю договоренности")
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if !gameHistory.isEmpty {
                    SectionCard(title: "Договоренности", subtitle: "Текущие и прошлые игры. Нажми, чтобы открыть их в ближайших играх.") {
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

                                        AppInlineChip(text: request.statusLabel, tint: request.statusTintColor, foreground: .white)
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
            return "Предложить игру"
        case .edit:
            return "Изменить предложение"
        case .reschedule:
            return "Предложить другое время"
        case .relocate:
            return "Предложить другое место"
        }
    }

    var subtitlePrefix: String {
        switch self {
        case .new:
            return "Создай новую договоренность"
        case .edit:
            return "Обнови текущую договоренность"
        case .reschedule:
            return "Обнови время договоренности"
        case .relocate:
            return "Обнови место договоренности"
        }
    }

    var submitTitle: String {
        switch self {
        case .new:
            return "Отправить предложение"
        case .edit:
            return "Сохранить изменения"
        case .reschedule:
            return "Отправить новое время"
        case .relocate:
            return "Отправить новое место"
        }
    }
}

struct GameProposalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel

    let match: MatchSummary
    let context: ProposalSheetContext
    let seedRequest: MatchGameRequest?
    let onCreated: () async -> Void

    @State private var courts: [Court] = []
    @State private var isLoadingCourts = false
    @State private var isSubmitting = false
    @State private var isClubPickerPresented = false
    @State private var localError: String?
    @State private var draft: GameProposalDraft

    init(
        match: MatchSummary,
        context: ProposalSheetContext = .new,
        seedRequest: MatchGameRequest? = nil,
        onCreated: @escaping () async -> Void
    ) {
        self.match = match
        self.context = context
        self.seedRequest = seedRequest
        self.onCreated = onCreated

        let sourceRequest = seedRequest ?? match.latestGameRequest
        let preferredSport = sourceRequest?.sport ?? match.otherUser.preferredSports.first ?? .tennis
        let preferredFormat = sourceRequest?.format ?? match.otherUser.preferredPlayFormat
        let defaultLevel = match.otherUser.sportLevels[preferredSport.rawValue] ?? match.otherUser.tennisLevel ?? 5
        let proposalDate = Self.initialProposalDate(from: sourceRequest?.proposedDate)

        _draft = State(initialValue: GameProposalDraft(
            proposedCourtId: sourceRequest?.proposedCourt?.id ?? "",
            proposedDatetime: proposalDate,
            durationMinutes: sourceRequest?.durationMinutes ?? 90,
            levelRangeMin: max(defaultLevel - 1, 1),
            levelRangeMax: min(defaultLevel + 1, 10),
            sport: preferredSport,
            format: preferredFormat,
            comment: sourceRequest?.comment ?? ""
        ))
    }

    private var availableSports: [Sport] {
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
        filteredCourts.first(where: { $0.id == draft.proposedCourtId })
            ?? courts.first(where: { $0.id == draft.proposedCourtId })
    }

    private var proposalSummaryTitle: String {
        proposalDateTimeText(for: draft.proposedDatetime)
    }

    private var proposalSummarySubtitle: String {
        [
            draft.sport.title,
            draft.sport.formatTitle(format: draft.format),
            selectedCourt?.name ?? draft.sport.venuePendingTitle
        ].joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    proposalHeader
                    proposalHero
                    sportSelector
                    formatSection
                    dateTimeSection
                    courtSection
                    levelSection
                    commentSection
                    submitSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 40)
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
                selectedCourtId: draft.proposedCourtId.isEmpty ? nil : draft.proposedCourtId,
                selectsImmediately: false,
                allowsNoCourt: false,
                onSelect: { court in
                    guard let court else {
                        return
                    }
                    selectCourt(court)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
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
                    Text("\(context.subtitlePrefix) с \(match.otherUser.displayName)")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Выбери спорт, время и клуб. Второй игрок увидит предложение в мэтче и сможет подтвердить игру.")
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
                Text("Что играем?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("Вид спорта")
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
                                Image(systemName: proposalSportIconName(for: sport))
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

                                if let level {
                                    Text("ур. \(level)")
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
            Text("Формат игры")
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
                        Text(draft.sport.formatTitle(format: format))
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
            Text("Когда играем?")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 10) {
                proposalDayButton(title: "Сегодня", offset: 0)
                proposalDayButton(title: "Завтра", offset: 1)
                proposalDayButton(title: "Послезавтра", offset: 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(proposalQuickTimes, id: \.self) { time in
                        proposalTimeButton(time)
                    }
                }
            }

            DatePicker(
                "Точная дата и время",
                selection: $draft.proposedDatetime,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
            .datePickerStyle(.compact)
            .tint(AppTheme.court)
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func proposalDayButton(title: String, offset: Int) -> some View {
        let targetDate = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let selected = Calendar.current.isDate(draft.proposedDatetime, inSameDayAs: targetDate)

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
        let selected = draft.proposedDatetime.formattedHourMinute() == time

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
                        Label("Все места", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.court)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isLoadingCourts {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Загружаем места")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.58))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if filteredCourts.isEmpty {
                Text("Нет доступных мест для этого спорта")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.58))
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                selectedCourtCard

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredCourts.prefix(8), id: \.id) { court in
                            compactCourtButton(court)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var selectedCourtCard: some View {
        let court = selectedCourt

        return VStack(alignment: .leading, spacing: 12) {
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
                    Text(court?.name ?? "Выбери клуб")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    Text(courtSubtitle(court))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.ink.opacity(0.55))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(court == nil ? AppTheme.ink.opacity(0.18) : AppTheme.court)
            }

            if let phoneURL = bookingPhoneURL(for: court) {
                Button {
                    openURL(phoneURL)
                } label: {
                    Label("Позвонить забронировать", systemImage: "phone.fill")
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

    private func compactCourtButton(_ court: Court) -> some View {
        let selected = draft.proposedCourtId == court.id

        return Button {
            selectCourt(court)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(court.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(selected ? .white : AppTheme.ink)
                    .lineLimit(2)

                Text(courtSubtitle(court))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? .white.opacity(0.72) : AppTheme.ink.opacity(0.52))
                    .lineLimit(2)
            }
            .frame(width: 172, height: 76, alignment: .topLeading)
            .padding(12)
            .background(selected ? AppTheme.court : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var levelSection: some View {
        HStack(alignment: .top, spacing: 14) {
            proposalLevelCard(
                title: "Мин. уровень",
                value: Binding(
                    get: { draft.levelRangeMin ?? 1 },
                    set: { newValue in
                        draft.levelRangeMin = min(newValue, draft.levelRangeMax ?? 10)
                    }
                )
            )

            proposalLevelCard(
                title: "Макс. уровень",
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
                Text("Комментарий (необязательно)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
                TextField("Например: удобно после 19:00", text: $draft.comment, axis: .vertical)
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
            .disabled(isSubmitting || draft.proposedCourtId.isEmpty)

            Button("Отмена") {
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
            if draft.proposedCourtId.isEmpty {
                draft.proposedCourtId = filteredCourts.first?.id ?? ""
            }
            return
        }

        isLoadingCourts = true
        defer { isLoadingCourts = false }

        do {
            courts = try await appModel.repository.fetchCourts()
            draft.proposedCourtId = filteredCourts.first?.id ?? courts.first?.id ?? ""
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
            if !filteredCourts.contains(where: { $0.id == draft.proposedCourtId }) {
                draft.proposedCourtId = filteredCourts.first?.id ?? courts.first?.id ?? ""
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
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    private func courtSubtitle(_ court: Court?) -> String {
        guard let court else {
            return "Выбери место, где удобно встретиться"
        }

        let subtitle = [
            court.nearestMetroName,
            localizedDistrictName(court.district),
            court.distanceLabel
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return subtitle.isEmpty ? court.address : subtitle
    }

    private func bookingPhoneURL(for court: Court?) -> URL? {
        guard let phone = court?.phone else {
            return nil
        }

        let normalized = phone.filter { $0.isNumber || $0 == "+" }
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(string: "tel://\(normalized)")
    }

    private func proposalDateTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    private func proposalSportIconName(for sport: Sport) -> String {
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

    private func submitProposal() async {
        guard !draft.proposedCourtId.isEmpty else {
            localError = "Выбери место"
            return
        }

        guard draft.proposedDatetime > Date() else {
            localError = "Выбери будущую дату и время"
            draft.proposedDatetime = clampedFutureDate(draft.proposedDatetime)
            return
        }

        isSubmitting = true
        localError = nil
        defer { isSubmitting = false }

        do {
            if context == .edit, let requestId = seedRequest?.id {
                _ = try await appModel.repository.updateGameRequest(gameRequestId: requestId, draft: draft)
            } else {
                _ = try await appModel.repository.createGameRequest(matchId: match.id, draft: draft)
            }
            AppHaptics.notification(.success)
            await onCreated()
            dismiss()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            localError = error.localizedDescription
        }
    }
}
