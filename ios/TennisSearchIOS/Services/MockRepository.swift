import Foundation

actor MockRepository: TennisRepository {
    private var slotProposalsBySearchId: [String: SearchSlotProposalSummary] = [:]

    private var currentUser = UserProfile(
        id: "u-anna",
        email: "anna@tennis.dev",
        name: "Анна",
        age: 29,
        gender: .female,
        city: "Санкт-Петербург",
        district: "petrogradsky",
        preferredDistricts: ["petrogradsky", "primorsky"],
        bio: "Ищу стабильного партнера на вечерние игры по будням. Люблю быстрый созвон и без долгих переписок.",
        tennisLevel: 5,
        preferredSports: [.tennis, .padel],
        sportLevels: ["tennis": 5, "padel": 4],
        preferredPlayFormat: .singles,
        preferredSurface: .hard,
        availableDays: ["wednesday", "friday", "saturday"],
        availableTimeRanges: ["evening"],
        availabilityByDay: ["wednesday": ["evening"], "friday": ["evening"], "saturday": ["evening"]],
        isLookingForGame: true,
        searchRadiusKm: 12,
        onboardingCompleted: true,
        isVerified: true
    )

    private var discoverUsers: [DiscoverUser] = [
        makeDiscoverUser(
            id: "u-elena",
            name: "Елена",
            age: 31,
            city: "Санкт-Петербург",
            district: "moskovsky",
            districtLabel: "Московский",
            bio: "Готова подстраиваться под центр, если можно закрепить корт заранее.",
            sports: [.tennis],
            levels: ["tennis": 5],
            format: .singles,
            surface: .hard,
            days: ["tuesday", "thursday"],
            ranges: ["evening"],
            distance: "4.2 км",
            score: 92,
            searches: [],
            reasons: ["Совпадает спорт: Теннис", "Уровень рядом: 5", "Недалеко: 4.2 км"]
        ),
        makeDiscoverUser(
            id: "u-maria",
            name: "Мария",
            age: 27,
            city: "Санкт-Петербург",
            district: "central",
            districtLabel: "Центральный",
            bio: "Могу сыграть и в теннис, и в падел. Часто свободна утром в выходные.",
            sports: [.tennis, .padel],
            levels: ["tennis": 4, "padel": 4],
            format: .both,
            surface: .clay,
            days: ["saturday", "sunday"],
            ranges: ["morning"],
            distance: "7.8 км",
            score: 88,
            searches: [
                GameSearch(
                    id: "search-maria",
                    status: "active",
                    searchType: .regular,
                    hotWindow: nil,
                    hotStartsAt: nil,
                    durationMinutes: nil,
                    hasCourtBooked: false,
                    sport: .tennis,
                    selfLevel: 4,
                    selfLevelUnknown: false,
                    desiredLevelMin: 3,
                    desiredLevelMax: 5,
                    format: .both,
                    playersNeeded: 1,
                    preferredDays: ["saturday"],
                    preferredTimeRanges: ["morning"],
                    comment: "Ищу регулярную игру по выходным.",
                    isActive: true,
                    isExpired: false,
                    preferredCourt: nil,
                    regularPair: nil,
                    responses: []
                )
            ],
            reasons: ["Совпадает спорт: Теннис", "Уровень рядом: 4", "Недалеко: 7.8 км", "Пересекается расписание"]
        ),
        makeDiscoverUser(
            id: "u-sofia",
            name: "София",
            age: 33,
            city: "Санкт-Петербург",
            district: "petrogradsky",
            districtLabel: "Петроградский",
            bio: "Ищу игрока на сегодня вечером, центр уже подобран.",
            sports: [.tennis],
            levels: ["tennis": 6],
            format: .singles,
            surface: .hard,
            days: ["today"],
            ranges: ["evening"],
            distance: "2.9 км",
            score: 95,
            searches: [
                GameSearch(
                    id: "search-sofia-hot",
                    status: "active",
                    searchType: .hot,
                    hotWindow: .today,
                    hotStartsAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200)),
                    durationMinutes: 90,
                    hasCourtBooked: true,
                    sport: .tennis,
                    selfLevel: 6,
                    selfLevelUnknown: false,
                    desiredLevelMin: 5,
                    desiredLevelMax: 7,
                    format: .singles,
                    playersNeeded: 1,
                    preferredDays: [],
                    preferredTimeRanges: [],
                    comment: "Корт уже взят, нужен игрок на сегодня.",
                    isActive: true,
                    isExpired: false,
                    preferredCourt: mockCourt,
                    regularPair: nil,
                    responses: []
                )
            ],
            reasons: ["Совпадает спорт: Теннис", "Уровень рядом: 5–6", "Недалеко: 2.9 км"]
        )
    ]

    private var incomingLikes: [DiscoverUser] = []
    private var matches: [MatchSummary] = []
    private var messagesByMatch: [String: [ChatMessage]] = [:]
    private var searches: [GameSearch] = [
        GameSearch(
            id: "search-1",
            status: "active",
            searchType: .regular,
            hotWindow: nil,
            hotStartsAt: nil,
            durationMinutes: nil,
            hasCourtBooked: false,
            sport: .tennis,
            selfLevel: 5,
            selfLevelUnknown: false,
            desiredLevelMin: 4,
            desiredLevelMax: 6,
            format: .singles,
            playersNeeded: 1,
            preferredDays: ["wednesday", "saturday"],
            preferredTimeRanges: ["evening"],
            comment: "Ищу стабильную игру 1-2 раза в неделю.",
            isActive: true,
            isExpired: false,
            preferredCourt: nil,
            regularPair: nil,
            responses: []
        ),
        GameSearch(
            id: "search-2",
            status: "active",
            searchType: .hot,
            hotWindow: .today,
            hotStartsAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200)),
            durationMinutes: 90,
            hasCourtBooked: true,
            sport: .tennis,
            selfLevel: 5,
            selfLevelUnknown: false,
            desiredLevelMin: 4,
            desiredLevelMax: 6,
            format: .singles,
            playersNeeded: 1,
            preferredDays: [],
            preferredTimeRanges: [],
            comment: "Корт уже взят, нужен игрок на сегодня.",
            isActive: true,
            isExpired: false,
            preferredCourt: mockCourt,
            regularPair: nil,
            responses: []
        )
    ]

    private var notifications: [AppNotification] = [
        AppNotification(
            id: "notif-message-1",
            type: .new_message,
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)),
            title: "Новое сообщение от Елены",
            description: "Привет. Можем сыграть завтра в 20:00?",
            href: "/inbox/match-u-elena",
            status: nil
        ),
        AppNotification(
            id: "notif-like-1",
            type: .incoming_like,
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1800)),
            title: "Елена хочет с тобой сыграть",
            description: "Открой вкладку «Хотят с тобой».",
            href: "/discover?view=likes&highlight=u-elena",
            status: nil
        ),
        AppNotification(
            id: "notif-hot-1",
            type: .hot_event,
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600)),
            title: "София ищет срочно теннис на сегодня",
            description: "Есть срочный поиск по одному из твоих видов спорта.",
            href: "/discover?view=hot&highlight=search-sofia-hot",
            status: nil
        )
    ]

    private let courts: [Court] = [
        mockCourt,
        Court(
            id: "court-2",
            name: "Padel Club North",
            address: "Пр. Медиков, 5",
            district: "petrogradsky",
            locationLat: 59.9739,
            locationLng: 30.3084,
            distanceLabel: "5.1 км",
            nearestMetroName: "Выборгская",
            supportedSports: [.padel],
            phone: "+7 (812) 555-20-20",
            workingHours: "08:00-23:00",
            yandexMapsUrl: nil,
            websiteUrl: "https://padelnorth.example.com",
            bookingUrl: "https://padelnorth.example.com/book",
            photoUrl: nil,
            priceRange: "$$$",
            rating: 4.8
        ),
        Court(
            id: "court-3",
            name: "Krestovsky Tennis Hall",
            address: "Южная дорога, 25",
            district: "petrogradsky",
            locationLat: 59.9702,
            locationLng: 30.2501,
            distanceLabel: "8.6 км",
            nearestMetroName: "Крестовский остров",
            supportedSports: [.tennis, .squash],
            phone: "+7 (812) 555-35-35",
            workingHours: "07:00-22:00",
            yandexMapsUrl: nil,
            websiteUrl: "https://krestovskyhall.example.com",
            bookingUrl: nil,
            photoUrl: nil,
            priceRange: "$$",
            rating: 4.7
        )
    ]

    init() {
        incomingLikes = Array(discoverUsers.prefix(1))
    }

    func requestCode(email: String) async throws -> AuthChallenge {
        currentUser = UserProfile(
            id: currentUser.id,
            email: email,
            name: currentUser.name,
            age: currentUser.age,
            gender: currentUser.gender,
            city: currentUser.city,
            district: currentUser.district,
            preferredDistricts: currentUser.preferredDistricts,
            bio: currentUser.bio,
            avatarUrl: currentUser.avatarUrl,
            tennisLevel: currentUser.tennisLevel,
            preferredSports: currentUser.preferredSports,
            sportLevels: currentUser.sportLevels,
            preferredPlayFormat: currentUser.preferredPlayFormat,
            preferredSurface: currentUser.preferredSurface,
            availableDays: currentUser.availableDays,
            availableTimeRanges: currentUser.availableTimeRanges,
            availabilityByDay: currentUser.availabilityByDay,
            isLookingForGame: currentUser.isLookingForGame,
            searchRadiusKm: currentUser.searchRadiusKm,
            onboardingCompleted: currentUser.onboardingCompleted,
            isVerified: currentUser.isVerified,
            notificationMatches: currentUser.notificationMatches,
            notificationMessages: currentUser.notificationMessages,
            notificationGames: currentUser.notificationGames,
            notificationSound: currentUser.notificationSound
        )
        return AuthChallenge(message: "Код подтверждения отправлен", debugCode: "111111")
    }

    func verifyCode(email: String, code: String) async throws -> SessionUser {
        guard code == "111111" else {
            throw APIError.server("В mock-режиме используй код 111111")
        }

        return SessionUser(id: currentUser.id, email: email, onboardingCompleted: currentUser.onboardingCompleted)
    }

    func signInWithApple(identityToken: String, email: String?, givenName: String?, familyName: String?) async throws -> SessionUser {
        let resolvedName = [givenName, familyName]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")

        if let email {
            currentUser = UserProfile(
                id: currentUser.id,
                email: email,
                name: currentUser.name ?? (resolvedName.isEmpty ? nil : resolvedName),
                age: currentUser.age,
                gender: currentUser.gender,
                city: currentUser.city,
                district: currentUser.district,
                preferredDistricts: currentUser.preferredDistricts,
                bio: currentUser.bio,
                avatarUrl: currentUser.avatarUrl,
                tennisLevel: currentUser.tennisLevel,
                preferredSports: currentUser.preferredSports,
                sportLevels: currentUser.sportLevels,
                preferredPlayFormat: currentUser.preferredPlayFormat,
                preferredSurface: currentUser.preferredSurface,
                availableDays: currentUser.availableDays,
                availableTimeRanges: currentUser.availableTimeRanges,
                availabilityByDay: currentUser.availabilityByDay,
                isLookingForGame: currentUser.isLookingForGame,
                searchRadiusKm: currentUser.searchRadiusKm,
                onboardingCompleted: currentUser.onboardingCompleted,
                isVerified: true,
                notificationMatches: currentUser.notificationMatches,
                notificationMessages: currentUser.notificationMessages,
                notificationGames: currentUser.notificationGames,
                notificationSound: currentUser.notificationSound
            )
        }

        return SessionUser(
            id: currentUser.id,
            email: currentUser.email ?? email ?? "apple-user@mock.local",
            onboardingCompleted: currentUser.onboardingCompleted
        )
    }

    nonisolated func clearAuthSession() {
    }

    func fetchCurrentUser() async throws -> UserProfile {
        currentUser
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        currentUser = profile
        return currentUser
    }

    func deleteAccount() async throws {
        matches = []
        searches = []
        notifications = []
        messagesByMatch = [:]
        discoverUsers = []
        incomingLikes = []
    }

    func uploadAvatar(data: Data, fileName: String, mimeType: String) async throws -> String {
        let path = "/uploads/mock/\(UUID().uuidString)-\(fileName)"
        currentUser.avatarUrl = path
        return path
    }

    func fetchDiscoverUsers(view: DiscoverTab) async throws -> [DiscoverUser] {
        switch view {
        case .upcoming:
            return discoverUsers.filter { !$0.gameSearches.isEmpty }
        case .swipe:
            return discoverUsers
        case .likes:
            return incomingLikes
        case .seeking:
            return discoverUsers.filter { !$0.gameSearches.filter { $0.searchType == .regular }.isEmpty }
        case .hot:
            return discoverUsers.filter { !$0.gameSearches.filter { $0.searchType == .hot }.isEmpty }
        }
    }

    func fetchGuestDiscoverUsers(draft: GuestOnboardingDraft, view: DiscoverTab) async throws -> [DiscoverUser] {
        let effectiveView: DiscoverTab
        switch view {
        case .upcoming, .likes:
            effectiveView = .swipe
        default:
            effectiveView = view
        }
        return try await fetchDiscoverUsers(view: effectiveView)
    }

    func swipe(userId: String, action: SwipeAction) async throws -> String? {
        defer {
            discoverUsers.removeAll { $0.id == userId }
            incomingLikes.removeAll { $0.id == userId }
        }

        guard action == .like || action == .superlike else {
            return nil
        }

        guard let user = discoverUsers.first(where: { $0.id == userId }) ?? incomingLikes.first(where: { $0.id == userId }) else {
            return nil
        }

        let matchId = "match-\(userId)"
        let introMessage = ChatMessage(
            id: "msg-\(UUID().uuidString)",
            senderUserId: user.id,
            text: "Привет. Можем сыграть в четверг вечером?",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            senderUser: ChatSender(id: user.id, name: user.name, avatarUrl: user.avatarUrl)
        )
        messagesByMatch[matchId] = [introMessage]
        let match = MatchSummary(
            id: matchId,
            status: "active",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            otherUser: user,
            lastMessage: introMessage,
            latestGameRequest: nil
        )
        matches.insert(match, at: 0)
        return matchId
    }

    func fetchMatches() async throws -> [MatchSummary] {
        matches.map { match in
            MatchSummary(
                id: match.id,
                status: match.status,
                createdAt: match.createdAt,
                otherUser: match.otherUser,
                lastMessage: messagesByMatch[match.id]?.last ?? match.lastMessage,
                latestGameRequest: match.latestGameRequest
            )
        }
    }

    func fetchMyGameRequests() async throws -> [MatchGameRequest] {
        matches.compactMap(\.latestGameRequest)
            .sorted { $0.proposedDatetime < $1.proposedDatetime }
    }

    func fetchMessages(matchId: String) async throws -> [ChatMessage] {
        messagesByMatch[matchId] ?? []
    }

    func sendMessage(matchId: String, text: String) async throws -> ChatMessage {
        let message = ChatMessage(
            id: "msg-\(UUID().uuidString)",
            senderUserId: currentUser.id,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            senderUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl)
        )
        messagesByMatch[matchId, default: []].append(message)
        return message
    }

    func createGameRequest(matchId: String, draft: GameProposalDraft) async throws -> MatchGameRequest {
        guard let court = courts.first(where: { $0.id == draft.proposedCourtId }) ?? courts.first else {
            throw APIError.server("Место не найдено")
        }

        let request = MatchGameRequest(
            id: "game-request-\(UUID().uuidString)",
            matchId: matchId,
            searchLobbyId: nil,
            status: "accepted",
            proposedDatetime: ISO8601DateFormatter().string(from: draft.proposedDatetime),
            createdByUserId: currentUser.id,
            matchedUserId: matches.first(where: { $0.id == matchId })?.otherUser.id,
            durationMinutes: draft.durationMinutes,
            comment: draft.comment.isEmpty ? nil : draft.comment,
            outcome: nil,
            sport: draft.sport,
            format: draft.format,
            proposedCourt: court,
            createdByUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl),
            matchedUser: matches.first(where: { $0.id == matchId }).map {
                ChatSender(id: $0.otherUser.id, name: $0.otherUser.name, avatarUrl: $0.otherUser.avatarUrl)
            },
            participants: participants(for: matchId)
        )

        if let matchIndex = matches.firstIndex(where: { $0.id == matchId }) {
            let proposalText = DateFormatter.localizedString(
                from: draft.proposedDatetime,
                dateStyle: .short,
                timeStyle: .short
            )
            let summary = draft.comment.isEmpty
                ? "Игра назначена: \(proposalText) · \(draft.sport.formatTitle(format: draft.format))"
                : "Игра назначена: \(proposalText) · \(draft.comment)"
            let systemMessage = ChatMessage(
                id: "msg-\(UUID().uuidString)",
                senderUserId: currentUser.id,
                text: summary,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                senderUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl)
            )
            messagesByMatch[matchId, default: []].append(systemMessage)
            let existing = matches[matchIndex]
            matches[matchIndex] = MatchSummary(
                id: existing.id,
                status: existing.status,
                createdAt: existing.createdAt,
                otherUser: existing.otherUser,
                lastMessage: systemMessage,
                latestGameRequest: request
            )
        }

        return request
    }

    func updateGameRequest(gameRequestId: String, draft: GameProposalDraft) async throws -> MatchGameRequest {
        guard let court = courts.first(where: { $0.id == draft.proposedCourtId }) ?? courts.first else {
            throw APIError.server("Место не найдено")
        }

        guard let matchIndex = matches.firstIndex(where: { $0.latestGameRequest?.id == gameRequestId }),
              let existing = matches[matchIndex].latestGameRequest else {
            throw APIError.server("Предложение игры не найдено")
        }

        let updated = MatchGameRequest(
            id: existing.id,
            matchId: existing.matchId,
            rootRequestId: existing.rootRequestId,
            searchLobbyId: existing.searchLobbyId,
            sourceType: existing.sourceType,
            regularPairId: existing.regularPairId,
            status: existing.status,
            proposedDatetime: ISO8601DateFormatter().string(from: draft.proposedDatetime),
            createdByUserId: existing.createdByUserId,
            matchedUserId: existing.matchedUserId,
            durationMinutes: draft.durationMinutes,
            comment: draft.comment.isEmpty ? nil : draft.comment,
            outcome: existing.outcome,
            sport: draft.sport,
            format: draft.format,
            proposedCourt: court,
            createdByUser: existing.createdByUser,
            matchedUser: existing.matchedUser,
            participants: existing.participants,
            invitees: existing.invitees
        )

        let summary = "Предложение игры обновлено: \(DateFormatter.localizedString(from: draft.proposedDatetime, dateStyle: .short, timeStyle: .short)) · \(court.name)"
        let systemMessage = ChatMessage(
            id: "msg-\(UUID().uuidString)",
            senderUserId: currentUser.id,
            text: summary,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            senderUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl)
        )

        messagesByMatch[existing.matchId ?? "", default: []].append(systemMessage)
        let match = matches[matchIndex]
        matches[matchIndex] = MatchSummary(
            id: match.id,
            status: match.status,
            createdAt: match.createdAt,
            otherUser: match.otherUser,
            lastMessage: systemMessage,
            latestGameRequest: updated
        )

        return updated
    }

    func shareGameRequest(gameRequestId: String, matchIds: [String]) async throws -> [MatchGameRequest] {
        guard let sourceMatch = matches.first(where: { $0.latestGameRequest?.id == gameRequestId }),
              let sourceRequest = sourceMatch.latestGameRequest else {
            throw APIError.server("Договоренность не найдена")
        }

        var created: [MatchGameRequest] = []

        for matchId in matchIds {
            guard let matchIndex = matches.firstIndex(where: { $0.id == matchId }) else {
                continue
            }

            let request = MatchGameRequest(
                id: "game-request-\(UUID().uuidString)",
                matchId: matchId,
                searchLobbyId: nil,
                status: "accepted",
                proposedDatetime: sourceRequest.proposedDatetime,
                createdByUserId: currentUser.id,
                matchedUserId: matches[matchIndex].otherUser.id,
                durationMinutes: sourceRequest.durationMinutes,
                comment: sourceRequest.comment,
                outcome: nil,
                sport: sourceRequest.sport,
                format: sourceRequest.format,
                proposedCourt: sourceRequest.proposedCourt,
                createdByUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl),
                matchedUser: ChatSender(
                    id: matches[matchIndex].otherUser.id,
                    name: matches[matchIndex].otherUser.name,
                    avatarUrl: matches[matchIndex].otherUser.avatarUrl
                ),
                participants: participants(for: matchId)
            )

            let systemMessage = ChatMessage(
                id: "msg-\(UUID().uuidString)",
                senderUserId: currentUser.id,
                text: "Добавил(а) тебя в уже созданную игру.",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                senderUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl)
            )

            messagesByMatch[matchId, default: []].append(systemMessage)
            let existing = matches[matchIndex]
            matches[matchIndex] = MatchSummary(
                id: existing.id,
                status: existing.status,
                createdAt: existing.createdAt,
                otherUser: existing.otherUser,
                lastMessage: systemMessage,
                latestGameRequest: request
            )
            created.append(request)
        }

        return created
    }

    func updateGameRequestStatus(gameRequestId: String, status: String) async throws -> MatchGameRequest {
        guard let matchIndex = matches.firstIndex(where: { $0.latestGameRequest?.id == gameRequestId }),
              let existing = matches[matchIndex].latestGameRequest else {
            throw APIError.server("Предложение игры не найдено")
        }

        let updated = MatchGameRequest(
            id: existing.id,
            matchId: existing.matchId,
            searchLobbyId: existing.searchLobbyId,
            status: status,
            proposedDatetime: existing.proposedDatetime,
            createdByUserId: existing.createdByUserId,
            matchedUserId: existing.matchedUserId,
            durationMinutes: existing.durationMinutes,
            comment: existing.comment,
            outcome: existing.outcome,
            sport: existing.sport,
            format: existing.format,
            proposedCourt: existing.proposedCourt,
            createdByUser: existing.createdByUser,
            matchedUser: existing.matchedUser,
            participants: existing.participants
        )

        let text: String
        switch status {
        case "accepted":
            text = "Игра подтверждена."
        case "declined":
            text = "Предложение игры отклонено."
        case "canceled":
            text = "Игра отменена."
        default:
            text = "Статус предложения обновлён."
        }

        let systemMessage = ChatMessage(
            id: "msg-\(UUID().uuidString)",
            senderUserId: currentUser.id,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            senderUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl)
        )

        let existingMatch = matches[matchIndex]
        matches[matchIndex] = MatchSummary(
            id: existingMatch.id,
            status: existingMatch.status,
            createdAt: existingMatch.createdAt,
            otherUser: existingMatch.otherUser,
            lastMessage: systemMessage,
            latestGameRequest: updated
        )
        messagesByMatch[existingMatch.id, default: []].append(systemMessage)

        return updated
    }

    func updateGameRequestOutcome(gameRequestId: String, outcome: String) async throws -> MatchGameRequest {
        guard let matchIndex = matches.firstIndex(where: { $0.latestGameRequest?.id == gameRequestId }),
              let existing = matches[matchIndex].latestGameRequest else {
            throw APIError.server("Предложение игры не найдено")
        }

        let updated = MatchGameRequest(
            id: existing.id,
            matchId: existing.matchId,
            rootRequestId: existing.rootRequestId,
            searchLobbyId: existing.searchLobbyId,
            sourceType: existing.sourceType,
            regularPairId: existing.regularPairId,
            status: existing.status,
            proposedDatetime: existing.proposedDatetime,
            createdByUserId: existing.createdByUserId,
            matchedUserId: existing.matchedUserId,
            durationMinutes: existing.durationMinutes,
            comment: existing.comment,
            outcome: outcome,
            sport: existing.sport,
            format: existing.format,
            proposedCourt: existing.proposedCourt,
            createdByUser: existing.createdByUser,
            matchedUser: existing.matchedUser,
            participants: existing.participants,
            invitees: existing.invitees
        )

        let text = outcome == "played"
            ? "Отметили, что игра состоялась."
            : "Отметили, что сыграть не удалось."
        let systemMessage = ChatMessage(
            id: "msg-\(UUID().uuidString)",
            senderUserId: currentUser.id,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            senderUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl)
        )

        let existingMatch = matches[matchIndex]
        matches[matchIndex] = MatchSummary(
            id: existingMatch.id,
            status: existingMatch.status,
            createdAt: existingMatch.createdAt,
            otherUser: existingMatch.otherUser,
            lastMessage: systemMessage,
            latestGameRequest: updated
        )
        messagesByMatch[existingMatch.id, default: []].append(systemMessage)

        return updated
    }

    func fetchSearches() async throws -> [GameSearch] {
        searches
    }

    func createSearch(_ draft: SearchDraft) async throws -> GameSearch {
        let created = GameSearch(
            id: "search-\(UUID().uuidString.prefix(6))",
            inviteSlug: draft.inviteSlug,
            status: "active",
            searchType: draft.searchType,
            hotWindow: draft.hotWindow,
            hotStartsAt: draft.hotStartTime.map { time in
                let today = Calendar.current.startOfDay(for: Date())
                let parts = time.split(separator: ":").compactMap { Int($0) }
                let date = Calendar.current.date(bySettingHour: parts.first ?? 19, minute: parts.last ?? 0, second: 0, of: today) ?? Date()
                return ISO8601DateFormatter().string(from: date)
            },
            durationMinutes: draft.durationMinutes,
            hasCourtBooked: draft.hasCourtBooked,
            sport: draft.sport,
            selfLevel: currentUser.tennisLevel,
            selfLevelUnknown: false,
            desiredLevelMin: max((currentUser.tennisLevel ?? 5) - 1, 1),
            desiredLevelMax: min((currentUser.tennisLevel ?? 5) + 1, 10),
            format: draft.format,
            playersNeeded: draft.playersNeeded,
            preferredDays: draft.preferredDays,
            preferredTimeRanges: draft.preferredTimeRanges,
            comment: draft.comment,
            isActive: true,
            isExpired: false,
            preferredCourt: courts.first(where: { $0.id == draft.preferredCourtId }),
            preferredDistricts: draft.preferredDistricts,
            regularPair: nil,
            responses: []
        )
        searches.insert(created, at: 0)
        return created
    }

    func updateSearch(searchId: String, draft: SearchDraft) async throws -> GameSearch {
        guard let index = searches.firstIndex(where: { $0.id == searchId }) else {
            throw URLError(.badServerResponse)
        }

        let updated = GameSearch(
            id: searches[index].id,
            inviteSlug: draft.inviteSlug ?? searches[index].inviteSlug,
            status: searches[index].isActive == false ? "closed" : "active",
            searchType: draft.searchType,
            hotWindow: draft.hotWindow,
            hotStartsAt: draft.hotStartTime.map { time in
                let today = Calendar.current.startOfDay(for: Date())
                let parts = time.split(separator: ":").compactMap { Int($0) }
                let date = Calendar.current.date(bySettingHour: parts.first ?? 19, minute: parts.last ?? 0, second: 0, of: today) ?? Date()
                return ISO8601DateFormatter().string(from: date)
            },
            durationMinutes: draft.durationMinutes,
            hasCourtBooked: draft.hasCourtBooked,
            sport: draft.sport,
            selfLevel: currentUser.sportLevels[draft.sport.rawValue] ?? currentUser.tennisLevel,
            selfLevelUnknown: draft.selfLevelUnknown,
            desiredLevelMin: draft.desiredLevelMin,
            desiredLevelMax: draft.desiredLevelMax,
            format: draft.format,
            playersNeeded: draft.playersNeeded,
            preferredDays: draft.preferredDays,
            preferredTimeRanges: draft.preferredTimeRanges,
            comment: draft.comment,
            isActive: searches[index].isActive,
            isExpired: false,
            preferredCourt: courts.first(where: { $0.id == draft.preferredCourtId }),
            preferredDistricts: draft.preferredDistricts,
            regularPair: searches[index].regularPair,
            responses: searches[index].responses
        )
        searches[index] = updated
        return updated
    }

    func setSearchActive(searchId: String, isActive: Bool) async throws -> GameSearch {
        guard let index = searches.firstIndex(where: { $0.id == searchId }) else {
            throw URLError(.badServerResponse)
        }

        let existing = searches[index]
        let updated = GameSearch(
            id: existing.id,
            status: isActive ? "active" : "closed",
            searchType: existing.searchType,
            hotWindow: existing.hotWindow,
            hotStartsAt: existing.hotStartsAt,
            durationMinutes: existing.durationMinutes,
            hasCourtBooked: existing.hasCourtBooked,
            sport: existing.sport,
            selfLevel: existing.selfLevel,
            selfLevelUnknown: existing.selfLevelUnknown,
            desiredLevelMin: existing.desiredLevelMin,
            desiredLevelMax: existing.desiredLevelMax,
            format: existing.format,
            playersNeeded: existing.playersNeeded,
            preferredDays: existing.preferredDays,
            preferredTimeRanges: existing.preferredTimeRanges,
            comment: existing.comment,
            isActive: isActive,
            isExpired: existing.isExpired,
            preferredCourt: existing.preferredCourt,
            regularPair: existing.regularPair,
            responses: existing.responses
        )
        searches[index] = updated
        return updated
    }

    func fetchSearchLobby(searchId: String) async throws -> SearchLobbySummary {
        guard let search = searches.first(where: { $0.id == searchId }) else {
            throw URLError(.badServerResponse)
        }

        return SearchLobbySummary(
            gameSearch: SearchLobbyGameSearch(
                id: search.id,
                createdByUserId: currentUser.id,
                searchType: search.searchType,
                status: search.status,
                isActive: search.isActive ?? true,
                sport: search.sport,
                format: search.format,
                preferredDistricts: search.preferredDistricts,
                preferredDays: search.preferredDays,
                preferredTimeRanges: search.preferredTimeRanges,
                hotStartsAt: search.hotStartsAt,
                durationMinutes: search.durationMinutes,
                playersNeeded: search.playersNeeded,
                desiredLevelMin: search.desiredLevelMin,
                desiredLevelMax: search.desiredLevelMax,
                comment: search.comment,
                scheduledAt: nil,
                scheduledDurationMinutes: nil,
                preferredCourt: search.preferredCourt,
                scheduledCourt: nil,
                activeSlotProposal: slotProposalsBySearchId[search.id],
                responses: search.responses,
                messages: []
            )
        )
    }

    func sendSearchLobbyMessage(searchId: String, text: String) async throws -> SearchLobbyMessage {
        SearchLobbyMessage(
            id: "search-message-\(UUID().uuidString.prefix(6))",
            senderUserId: currentUser.id,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            senderUser: ChatSender(id: currentUser.id, name: currentUser.name, avatarUrl: currentUser.avatarUrl)
        )
    }

    func createSearchSlotProposal(
        searchId: String,
        options: [SearchSlotProposalDraftOption],
        comment: String?
    ) async throws -> SearchSlotProposalSummary {
        let proposal = SearchSlotProposalSummary(
            id: "slot-proposal-\(UUID().uuidString.prefix(6))",
            comment: comment,
            status: "open",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            options: options.enumerated().map { index, option in
                SearchSlotProposalOption(
                    id: "slot-option-\(index)-\(UUID().uuidString.prefix(6))",
                    scheduledAt: ISO8601DateFormatter().string(from: option.scheduledAt),
                    durationMinutes: option.durationMinutes,
                    proposedCourt: option.proposedCourtId.flatMap { courtId in
                        courts.first(where: { $0.id == courtId })
                    },
                    votes: []
                )
            }
        )
        slotProposalsBySearchId[searchId] = proposal
        updateSearchSchedule(searchId: searchId, from: proposal.options, activeSlotProposal: proposal)
        return proposal
    }

    func voteSearchSlotProposal(
        searchId: String,
        proposalId: String,
        optionIds: [String]
    ) async throws -> SearchSlotProposalSummary {
        guard let proposal = slotProposalsBySearchId[searchId], proposal.id == proposalId else {
            throw URLError(.badServerResponse)
        }

        let selectedOptionIds = Set(optionIds)
        let votedOptions = proposal.options.map { option in
            let votesWithoutCurrentUser = option.votes.filter { $0.userId != currentUser.id }
            let votes = selectedOptionIds.contains(option.id)
                ? votesWithoutCurrentUser + [
                    SearchSlotProposalVote(
                        id: "slot-vote-\(UUID().uuidString.prefix(6))",
                        userId: currentUser.id,
                        createdAt: ISO8601DateFormatter().string(from: Date())
                    )
                ]
                : votesWithoutCurrentUser

            return SearchSlotProposalOption(
                id: option.id,
                scheduledAt: option.scheduledAt,
                durationMinutes: option.durationMinutes,
                proposedCourt: option.proposedCourt,
                votes: votes
            )
        }
        let approvedCount = searches
            .first(where: { $0.id == searchId })?
            .responses
            .filter { $0.status == "approved" }
            .count ?? 1
        let finalizedOptions = approvedCount > 0 ? votedOptions.filter { $0.votes.count >= approvedCount } : []
        let updatedStatus = finalizedOptions.isEmpty ? proposal.status : "closed"
        let updated = SearchSlotProposalSummary(
            id: proposal.id,
            comment: proposal.comment,
            status: updatedStatus,
            createdAt: proposal.createdAt,
            options: votedOptions
        )
        if finalizedOptions.isEmpty {
            slotProposalsBySearchId[searchId] = updated
        } else {
            slotProposalsBySearchId[searchId] = nil
        }
        updateSearchSchedule(
            searchId: searchId,
            from: finalizedOptions.isEmpty ? votedOptions : finalizedOptions,
            activeSlotProposal: finalizedOptions.isEmpty ? updated : nil,
            clearsActiveProposal: !finalizedOptions.isEmpty
        )
        return updated
    }

    func scheduleSearchGame(searchId: String, courtId: String, scheduledAt: Date, durationMinutes: Int) async throws -> SearchGameScheduleResult {
        let updated = try await updateSearch(
            searchId: searchId,
            draft: searches.first(where: { $0.id == searchId }).map {
                SearchDraft(
                    inviteSlug: $0.inviteSlug,
                    preferredCourtId: $0.preferredCourt?.id,
                    preferredDistricts: $0.preferredDistricts,
                    preferredDays: $0.preferredDays,
                    preferredTimeRanges: $0.preferredTimeRanges,
                    searchType: $0.searchType,
                    hotWindow: $0.hotWindow,
                    hotStartTime: $0.hotStartsAt?.parsedISODateValue()?.formattedHourMinute(),
                    durationMinutes: $0.durationMinutes,
                    hasCourtBooked: $0.hasCourtBooked,
                    sport: $0.sport,
                    selfLevel: $0.selfLevel,
                    selfLevelUnknown: $0.selfLevelUnknown ?? false,
                    desiredLevelMin: $0.desiredLevelMin ?? 1,
                    desiredLevelMax: $0.desiredLevelMax ?? 10,
                    format: $0.format,
                    playersNeeded: $0.playersNeeded,
                    comment: $0.comment ?? ""
                )
            } ?? SearchDraft(
                inviteSlug: nil,
                preferredCourtId: courtId,
                preferredDistricts: [],
                preferredDays: [],
                preferredTimeRanges: [],
                searchType: .regular,
                hotWindow: nil,
                hotStartTime: nil,
                durationMinutes: durationMinutes,
                hasCourtBooked: true,
                sport: .tennis,
                selfLevel: nil,
                selfLevelUnknown: true,
                desiredLevelMin: 1,
                desiredLevelMax: 10,
                format: .singles,
                playersNeeded: 1,
                comment: ""
            )
        )

        return SearchGameScheduleResult(gameSearch: updated, gameRequestId: nil)
    }

    func fetchRegularPair(regularPairId: String) async throws -> RegularPairSummary {
        if let pair = searches.compactMap(\.regularPair).first(where: { $0.id == regularPairId }) {
            return pair
        }

        if let pair = discoverUsers
            .flatMap(\.gameSearches)
            .compactMap(\.regularPair)
            .first(where: { $0.id == regularPairId }) {
            return pair
        }

        throw URLError(.badServerResponse)
    }

    func updateRegularPairOccurrence(
        regularPairId: String,
        occurrenceId: String,
        status: String?,
        scheduledAt: Date?,
        proposedCourtId: String?
    ) async throws -> RegularPairOccurrence {
        guard let pair = try? await fetchRegularPair(regularPairId: regularPairId),
              let existingOccurrence = pair.occurrences.first(where: { $0.id == occurrenceId }) else {
            throw URLError(.badServerResponse)
        }

        let nextStatus = status ?? "pending"
        let updated = RegularPairOccurrence(
            id: existingOccurrence.id,
            scheduledAt: scheduledAt.map { ISO8601DateFormatter().string(from: $0) } ?? existingOccurrence.scheduledAt,
            scheduleAnchor: existingOccurrence.scheduleAnchor ?? existingOccurrence.scheduledAt,
            durationMinutes: existingOccurrence.durationMinutes,
            status: nextStatus,
            proposedCourt: proposedCourtId.flatMap { id in courts.first(where: { $0.id == id }) } ?? existingOccurrence.proposedCourt,
            confirmations: existingOccurrence.confirmations
        )

        searches = searches.map { search in
            guard let regularPair = search.regularPair, regularPair.id == regularPairId else {
                return search
            }

            let occurrences = regularPair.occurrences.map { $0.id == occurrenceId ? updated : $0 }
            let updatedPair = RegularPairSummary(
                id: regularPair.id,
                matchId: regularPair.matchId,
                partnerUser: regularPair.partnerUser,
                preferredCourt: regularPair.preferredCourt,
                preferredDays: regularPair.preferredDays,
                preferredTimeRanges: regularPair.preferredTimeRanges,
                comment: regularPair.comment,
                occurrences: occurrences
            )

            return GameSearch(
                id: search.id,
                status: search.status,
                searchType: search.searchType,
                hotWindow: search.hotWindow,
                hotStartsAt: search.hotStartsAt,
                durationMinutes: search.durationMinutes,
                hasCourtBooked: search.hasCourtBooked,
                sport: search.sport,
                selfLevel: search.selfLevel,
                selfLevelUnknown: search.selfLevelUnknown,
                desiredLevelMin: search.desiredLevelMin,
                desiredLevelMax: search.desiredLevelMax,
                format: search.format,
                playersNeeded: search.playersNeeded,
                preferredDays: search.preferredDays,
                preferredTimeRanges: search.preferredTimeRanges,
                comment: search.comment,
                isActive: search.isActive,
                isExpired: search.isExpired,
                preferredCourt: search.preferredCourt,
                regularPair: updatedPair,
                responses: search.responses
            )
        }

        return updated
    }

    func respondToSearch(searchId: String, message: String) async throws -> SearchResponse {
        let response = SearchResponse(
            id: "response-\(UUID().uuidString)",
            status: "pending",
            responderUser: makeDiscoverUser(
                id: currentUser.id,
                name: currentUser.name ?? "Ты",
                age: currentUser.age ?? 28,
                city: currentUser.city ?? "Санкт-Петербург",
                district: currentUser.district ?? "petrogradsky",
                districtLabel: "Твой район",
                bio: currentUser.bio ?? "",
                sports: currentUser.preferredSports,
                levels: currentUser.sportLevels,
                format: currentUser.preferredPlayFormat,
                surface: currentUser.preferredSurface,
                days: currentUser.availableDays,
                ranges: currentUser.availableTimeRanges,
                distance: "0 км",
                score: 100,
                searches: []
            ),
            matchId: nil
        )

        if let index = discoverUsers.firstIndex(where: { user in
            user.gameSearches.contains(where: { $0.id == searchId })
        }) {
            var owner = discoverUsers[index]
            let responses = owner.gameSearches.first?.responses ?? []
            let updatedSearch = GameSearch(
                id: owner.gameSearches.first?.id ?? searchId,
                status: "in_review",
                searchType: owner.gameSearches.first?.searchType ?? .regular,
                hotWindow: owner.gameSearches.first?.hotWindow,
                hotStartsAt: owner.gameSearches.first?.hotStartsAt,
                durationMinutes: owner.gameSearches.first?.durationMinutes,
                hasCourtBooked: owner.gameSearches.first?.hasCourtBooked ?? false,
                sport: owner.gameSearches.first?.sport ?? .tennis,
                selfLevel: owner.gameSearches.first?.selfLevel,
                selfLevelUnknown: owner.gameSearches.first?.selfLevelUnknown,
                desiredLevelMin: owner.gameSearches.first?.desiredLevelMin,
                desiredLevelMax: owner.gameSearches.first?.desiredLevelMax,
                format: owner.gameSearches.first?.format ?? .singles,
                playersNeeded: owner.gameSearches.first?.playersNeeded ?? 1,
                preferredDays: owner.gameSearches.first?.preferredDays ?? [],
                preferredTimeRanges: owner.gameSearches.first?.preferredTimeRanges ?? [],
                comment: owner.gameSearches.first?.comment ?? message,
                isActive: owner.gameSearches.first?.isActive,
                isExpired: owner.gameSearches.first?.isExpired,
                preferredCourt: owner.gameSearches.first?.preferredCourt,
                regularPair: owner.gameSearches.first?.regularPair,
                responses: responses + [response]
            )
            owner = makeDiscoverUser(
                id: owner.id,
                name: owner.name ?? "Игрок",
                age: owner.age ?? 28,
                city: owner.city ?? "Санкт-Петербург",
                district: owner.district ?? "petrogradsky",
                districtLabel: owner.districtLabel ?? "Район",
                bio: owner.bio ?? "",
                sports: owner.preferredSports,
                levels: owner.sportLevels,
                format: owner.preferredPlayFormat,
                surface: owner.preferredSurface,
                days: owner.availableDays,
                ranges: owner.availableTimeRanges,
                distance: owner.distanceLabel,
                score: owner.score ?? 80,
                searches: [updatedSearch]
            )
            discoverUsers[index] = owner
        }

        return response
    }

    func withdrawSearchResponse(responseId: String) async throws -> SearchResponse {
        for index in discoverUsers.indices {
            guard let search = discoverUsers[index].gameSearches.first,
                  let responseIndex = search.responses.firstIndex(where: { $0.id == responseId }) else {
                continue
            }

            var responses = search.responses
            let existing = responses[responseIndex]
            let updated = SearchResponse(
                id: existing.id,
                status: "withdrawn",
                responderUser: existing.responderUser,
                matchId: existing.matchId
            )
            responses[responseIndex] = updated

            let updatedSearch = GameSearch(
                id: search.id,
                status: "active",
                searchType: search.searchType,
                hotWindow: search.hotWindow,
                hotStartsAt: search.hotStartsAt,
                durationMinutes: search.durationMinutes,
                hasCourtBooked: search.hasCourtBooked,
                sport: search.sport,
                selfLevel: search.selfLevel,
                selfLevelUnknown: search.selfLevelUnknown,
                desiredLevelMin: search.desiredLevelMin,
                desiredLevelMax: search.desiredLevelMax,
                format: search.format,
                playersNeeded: search.playersNeeded,
                preferredDays: search.preferredDays,
                preferredTimeRanges: search.preferredTimeRanges,
                comment: search.comment,
                isActive: search.isActive,
                isExpired: search.isExpired,
                preferredCourt: search.preferredCourt,
                regularPair: search.regularPair,
                responses: responses
            )

            let owner = discoverUsers[index]
            discoverUsers[index] = makeDiscoverUser(
                id: owner.id,
                name: owner.name ?? "Игрок",
                age: owner.age ?? 28,
                city: owner.city ?? "Санкт-Петербург",
                district: owner.district ?? "petrogradsky",
                districtLabel: owner.districtLabel ?? "Район",
                bio: owner.bio ?? "",
                sports: owner.preferredSports,
                levels: owner.sportLevels,
                format: owner.preferredPlayFormat,
                surface: owner.preferredSurface,
                days: owner.availableDays,
                ranges: owner.availableTimeRanges,
                distance: owner.distanceLabel,
                score: owner.score ?? 80,
                searches: [updatedSearch]
            )

            return updated
        }

        throw APIError.server("Отклик не найден")
    }

    func updateSearchResponseStatus(responseId: String, status: String) async throws -> SearchResponseUpdateResult {
        if let searchIndex = searches.firstIndex(where: { search in
            search.responses.contains(where: { $0.id == responseId })
        }) {
            var search = searches[searchIndex]
            guard let responseIndex = search.responses.firstIndex(where: { $0.id == responseId }) else {
                throw APIError.server("Отклик не найден")
            }

            var responses = search.responses
            let existing = responses[responseIndex]
            let updated = SearchResponse(
                id: existing.id,
                status: status,
                responderUser: existing.responderUser,
                matchId: existing.matchId
            )
            responses[responseIndex] = updated

            let approvedCount = responses.filter { $0.status == "approved" }.count
            let playersNeeded = max(search.playersNeeded, 1)
            let isFilled = approvedCount >= playersNeeded
            if isFilled {
                responses = responses.map { response in
                    guard response.id != updated.id, response.status == "pending" else {
                        return response
                    }
                    return SearchResponse(
                        id: response.id,
                        status: "rejected",
                        responderUser: response.responderUser,
                        matchId: response.matchId
                    )
                }
            }

            let nextSearchStatus: String
            if isFilled {
                nextSearchStatus = "matched"
            } else if approvedCount > 0 || responses.contains(where: { $0.status == "pending" }) {
                nextSearchStatus = "in_review"
            } else {
                nextSearchStatus = "active"
            }

            let generatedMatchId = updated.matchId ?? search.regularPair?.matchId ?? "match-\(responseId)"
            let generatedRegularPairId =
                status == "approved" && search.searchType == .regular && playersNeeded == 1
                ? (search.regularPair?.id ?? "pair-\(responseId)")
                : nil
            let generatedGameRequestId =
                status == "approved" && search.searchType == .hot && playersNeeded == 1
                ? "game-\(responseId)"
                : nil
            let nextRegularPair = generatedRegularPairId.map { regularPairId in
                RegularPairSummary(
                    id: regularPairId,
                    matchId: generatedMatchId,
                    partnerUser: updated.responderUser,
                    preferredCourt: search.preferredCourt,
                    preferredDays: search.preferredDays,
                    preferredTimeRanges: search.preferredTimeRanges,
                    comment: search.comment,
                    occurrences: makeRegularOccurrences(
                        preferredDays: search.preferredDays,
                        preferredTimeRanges: search.preferredTimeRanges,
                        proposedCourt: search.preferredCourt,
                        durationMinutes: search.durationMinutes
                    )
                )
            } ?? search.regularPair

            search = makeGameSearch(
                from: search,
                status: nextSearchStatus,
                isActive: !isFilled,
                regularPair: nextRegularPair,
                responses: responses
            )

            searches[searchIndex] = search

            return SearchResponseUpdateResult(
                response: updated,
                matchId: status == "approved" ? generatedMatchId : nil,
                gameRequestId: generatedGameRequestId,
                regularPairId: generatedRegularPairId,
                gameSearch: SearchStatusUpdate(
                    id: search.id,
                    status: nextSearchStatus,
                    isActive: !isFilled
                )
            )
        }

        throw APIError.server("Отклик не найден")
    }

    func simulateRegularSearchActivity(searchId: String) async throws -> SearchSimulationResult {
        guard let searchIndex = searches.firstIndex(where: { $0.id == searchId && $0.searchType == .regular }) else {
            throw APIError.server("Регулярный поиск не найден")
        }

        let search = searches[searchIndex]
        let approvedResponses = search.responses.filter { $0.status == "approved" }

        if let proposal = slotProposalsBySearchId[searchId], !approvedResponses.isEmpty {
            let selectedOptionIds = Set(proposal.options.prefix(2).map(\.id))
            let votedOptions = proposal.options.map { option in
                guard selectedOptionIds.contains(option.id) else {
                    return option
                }

                let existingUserIds = Set(option.votes.map(\.userId))
                let missingVotes = approvedResponses
                    .filter { !existingUserIds.contains($0.responderUser.id) }
                    .map { response in
                        SearchSlotProposalVote(
                            id: "slot-vote-\(UUID().uuidString.prefix(6))",
                            userId: response.responderUser.id,
                            createdAt: ISO8601DateFormatter().string(from: Date())
                        )
                    }

                return SearchSlotProposalOption(
                    id: option.id,
                    scheduledAt: option.scheduledAt,
                    durationMinutes: option.durationMinutes,
                    proposedCourt: option.proposedCourt,
                    votes: option.votes + missingVotes
                )
            }
            let finalizedOptions = votedOptions.filter { $0.votes.count >= approvedResponses.count }
            let updatedProposal = SearchSlotProposalSummary(
                id: proposal.id,
                comment: proposal.comment,
                status: finalizedOptions.isEmpty ? proposal.status : "closed",
                createdAt: proposal.createdAt,
                options: votedOptions
            )

            if finalizedOptions.isEmpty {
                slotProposalsBySearchId[searchId] = updatedProposal
            } else {
                slotProposalsBySearchId[searchId] = nil
            }

            updateSearchSchedule(
                searchId: searchId,
                from: finalizedOptions.isEmpty ? votedOptions : finalizedOptions,
                activeSlotProposal: finalizedOptions.isEmpty ? updatedProposal : nil,
                clearsActiveProposal: !finalizedOptions.isEmpty
            )

            return SearchSimulationResult(
                createdResponses: 0,
                createdVotes: selectedOptionIds.count * approvedResponses.count,
                finalizedOptions: finalizedOptions.count,
                message: finalizedOptions.isEmpty ? "Игроки проголосовали за слоты" : "Регулярное расписание согласовано"
            )
        }

        if search.responses.contains(where: { $0.status == "pending" }) {
            return SearchSimulationResult(
                createdResponses: 0,
                createdVotes: 0,
                finalizedOptions: 0,
                message: "Отклики уже есть. Одобри игроков, затем предложи слоты."
            )
        }

        if !approvedResponses.isEmpty {
            return SearchSimulationResult(
                createdResponses: 0,
                createdVotes: 0,
                finalizedOptions: 0,
                message: "Игроки уже одобрены. Предложи слоты и запусти симуляцию ещё раз."
            )
        }

        let responders = makeSimulationResponders(for: search, count: max(2, search.playersNeeded))
        let responses = responders.map { responder in
            SearchResponse(
                id: "response-\(UUID().uuidString.prefix(6))",
                status: "pending",
                responderUser: responder,
                matchId: nil
            )
        }

        searches[searchIndex] = makeGameSearch(
            from: search,
            status: "in_review",
            isActive: true,
            responses: search.responses + responses
        )

        return SearchSimulationResult(
            createdResponses: responses.count,
            createdVotes: 0,
            finalizedOptions: 0,
            message: "Добавлены отклики на регулярный поиск"
        )
    }

    private func participants(for matchId: String) -> [DiscoverUser] {
        guard let match = matches.first(where: { $0.id == matchId }) else {
            return []
        }

        return [
            makeDiscoverUser(
                id: currentUser.id,
                name: currentUser.name ?? "Ты",
                age: currentUser.age ?? 28,
                city: currentUser.city ?? "Санкт-Петербург",
                district: currentUser.district ?? "petrogradsky",
                districtLabel: "Твой район",
                bio: currentUser.bio ?? "",
                sports: currentUser.preferredSports,
                levels: currentUser.sportLevels,
                format: currentUser.preferredPlayFormat,
                surface: currentUser.preferredSurface,
                days: currentUser.availableDays,
                ranges: currentUser.availableTimeRanges,
                distance: "0 км",
                score: 100,
                searches: []
            ),
            match.otherUser
        ]
    }

    private func updateSearchSchedule(
        searchId: String,
        from options: [SearchSlotProposalOption],
        activeSlotProposal: SearchSlotProposalSummary?,
        clearsActiveProposal: Bool = false
    ) {
        guard let index = searches.firstIndex(where: { $0.id == searchId }) else {
            return
        }

        let existing = searches[index]
        let schedule = weeklySchedule(from: options)
        let nextDays = schedule.preferredDays.isEmpty ? existing.preferredDays : schedule.preferredDays
        let nextTimeRanges = schedule.preferredTimeRanges.isEmpty ? existing.preferredTimeRanges : schedule.preferredTimeRanges
        let nextCourt = schedule.preferredCourt ?? existing.preferredCourt
        let nextProposal = clearsActiveProposal ? nil : (activeSlotProposal ?? existing.activeSlotProposal)
        let nextRegularPair = existing.regularPair.map { pair in
            RegularPairSummary(
                id: pair.id,
                matchId: pair.matchId,
                partnerUser: pair.partnerUser,
                preferredCourt: nextCourt,
                preferredDays: nextDays,
                preferredTimeRanges: nextTimeRanges,
                comment: pair.comment,
                occurrences: makeRegularOccurrences(
                    preferredDays: nextDays,
                    preferredTimeRanges: nextTimeRanges,
                    proposedCourt: nextCourt,
                    durationMinutes: existing.durationMinutes
                )
            )
        }

        searches[index] = makeGameSearch(
            from: existing,
            preferredDays: nextDays,
            preferredTimeRanges: nextTimeRanges,
            preferredCourt: nextCourt,
            activeSlotProposal: nextProposal,
            clearsActiveProposal: clearsActiveProposal,
            regularPair: nextRegularPair
        )
    }

    private func weeklySchedule(from options: [SearchSlotProposalOption]) -> (
        preferredDays: [String],
        preferredTimeRanges: [String],
        preferredCourt: Court?
    ) {
        let formatter = ISO8601DateFormatter()
        var days = Set<String>()
        var timeRanges = Set<String>()
        let courtIds = Set(options.compactMap(\.proposedCourt?.id))

        for option in options {
            guard let date = formatter.date(from: option.scheduledAt) else {
                continue
            }

            let day = dayOfWeek(for: date)
            days.insert(day.rawValue)
            timeRanges.insert("\(day.rawValue)@\(hourMinuteString(from: date))")
        }

        let preferredDays = DayOfWeek.allCases.map(\.rawValue).filter { days.contains($0) }
        let preferredTimeRanges = Array(timeRanges).sorted(by: sortTimePreference)
        let preferredCourt = courtIds.count == 1
            ? courtIds.first.flatMap { courtId in courts.first(where: { $0.id == courtId }) }
            : nil

        return (preferredDays, preferredTimeRanges, preferredCourt)
    }

    private func makeRegularOccurrences(
        preferredDays: [String],
        preferredTimeRanges: [String],
        proposedCourt: Court?,
        durationMinutes: Int?
    ) -> [RegularPairOccurrence] {
        let days = preferredDays.compactMap(DayOfWeek.init(rawValue:))
        let timePreferences = preferredTimeRanges.isEmpty ? ["evening"] : preferredTimeRanges
        var occurrences: [RegularPairOccurrence] = []

        for weekOffset in 0 ..< 4 {
            for preference in timePreferences {
                let parsed = parsedTimePreference(preference)
                let targetDays = parsed.day.map { [$0] } ?? days
                for day in targetDays where !targetDays.isEmpty {
                    guard let scheduledAt = nextWeeklyDate(
                        day: day,
                        hour: parsed.hour,
                        minute: parsed.minute,
                        weekOffset: weekOffset
                    ) else {
                        continue
                    }
                    let scheduledAtString = ISO8601DateFormatter().string(from: scheduledAt)
                    occurrences.append(
                        RegularPairOccurrence(
                            id: "mock-occurrence-\(day.rawValue)-\(parsed.hour)-\(parsed.minute)-\(weekOffset)",
                            scheduledAt: scheduledAtString,
                            scheduleAnchor: scheduledAtString,
                            durationMinutes: durationMinutes ?? 90,
                            status: "pending",
                            proposedCourt: proposedCourt,
                            confirmations: []
                        )
                    )
                }
            }
        }

        return occurrences
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .prefix(8)
            .map { $0 }
    }

    private func parsedTimePreference(_ value: String) -> (day: DayOfWeek?, hour: Int, minute: Int) {
        let parts = value.split(separator: "@", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            let day = DayOfWeek(rawValue: parts[0])
            let time = parsedHourMinute(parts[1]) ?? (19, 0)
            return (day, time.0, time.1)
        }

        if let time = parsedHourMinute(value) {
            return (nil, time.0, time.1)
        }

        switch TimeRange(rawValue: value) {
        case .morning:
            return (nil, 9, 0)
        case .day:
            return (nil, 13, 0)
        case .evening, .none:
            return (nil, 19, 0)
        }
    }

    private func parsedHourMinute(_ value: String) -> (Int, Int)? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0 ... 23).contains(parts[0]),
              (0 ... 59).contains(parts[1]) else {
            return nil
        }
        return (parts[0], parts[1])
    }

    private func nextWeeklyDate(day: DayOfWeek, hour: Int, minute: Int, weekOffset: Int) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for dayOffset in 0 ..< 7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            if dayOfWeek(for: date) == day {
                let shifted = calendar.date(byAdding: .day, value: weekOffset * 7, to: date) ?? date
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted)
            }
        }
        return nil
    }

    private func dayOfWeek(for date: Date) -> DayOfWeek {
        switch Calendar.current.component(.weekday, from: date) {
        case 1:
            return .sunday
        case 2:
            return .monday
        case 3:
            return .tuesday
        case 4:
            return .wednesday
        case 5:
            return .thursday
        case 6:
            return .friday
        default:
            return .saturday
        }
    }

    private func hourMinuteString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func sortTimePreference(_ left: String, _ right: String) -> Bool {
        let leftParsed = parsedTimePreference(left)
        let rightParsed = parsedTimePreference(right)
        let leftDayIndex = leftParsed.day.flatMap { DayOfWeek.allCases.firstIndex(of: $0) } ?? 0
        let rightDayIndex = rightParsed.day.flatMap { DayOfWeek.allCases.firstIndex(of: $0) } ?? 0

        if leftDayIndex != rightDayIndex {
            return leftDayIndex < rightDayIndex
        }
        if leftParsed.hour != rightParsed.hour {
            return leftParsed.hour < rightParsed.hour
        }
        return leftParsed.minute < rightParsed.minute
    }

    private func makeGameSearch(
        from search: GameSearch,
        status: String? = nil,
        isActive: Bool? = nil,
        preferredDays: [String]? = nil,
        preferredTimeRanges: [String]? = nil,
        preferredCourt: Court? = nil,
        activeSlotProposal: SearchSlotProposalSummary? = nil,
        clearsActiveProposal: Bool = false,
        regularPair: RegularPairSummary? = nil,
        responses: [SearchResponse]? = nil
    ) -> GameSearch {
        GameSearch(
            id: search.id,
            inviteSlug: search.inviteSlug,
            status: status ?? search.status,
            searchType: search.searchType,
            hotWindow: search.hotWindow,
            hotStartsAt: search.hotStartsAt,
            durationMinutes: search.durationMinutes,
            hasCourtBooked: search.hasCourtBooked,
            sport: search.sport,
            selfLevel: search.selfLevel,
            selfLevelUnknown: search.selfLevelUnknown,
            desiredLevelMin: search.desiredLevelMin,
            desiredLevelMax: search.desiredLevelMax,
            format: search.format,
            playersNeeded: search.playersNeeded,
            preferredDays: preferredDays ?? search.preferredDays,
            preferredTimeRanges: preferredTimeRanges ?? search.preferredTimeRanges,
            comment: search.comment,
            isActive: isActive ?? search.isActive,
            isExpired: search.isExpired,
            preferredCourt: preferredCourt ?? search.preferredCourt,
            preferredDistricts: search.preferredDistricts,
            activeSlotProposal: clearsActiveProposal ? nil : (activeSlotProposal ?? search.activeSlotProposal),
            regularPair: regularPair ?? search.regularPair,
            responses: responses ?? search.responses
        )
    }

    func fetchCourts() async throws -> [Court] {
        courts
    }

    func fetchNotifications() async throws -> [AppNotification] {
        notifications
    }

    func fetchActivitySummary() async throws -> ActivitySummary {
        ActivitySummary(
            inboxBadgeCount: matches.count,
            incomingLikesCount: incomingLikes.count,
            hotBadgeCount: discoverUsers.filter { !$0.gameSearches.filter { $0.searchType == .hot }.isEmpty }.count,
            discoverBadgeCount: incomingLikes.count + discoverUsers.filter { !$0.gameSearches.filter { $0.searchType == .hot }.isEmpty }.count,
            notificationSound: currentUser.notificationSound
        )
    }

    func fetchAppStats() async throws -> AppStats {
        AppStats(
            registeredPlayersCount: max(315, discoverUsers.count + incomingLikes.count + 1),
            seekingPlayersCount: max(315, discoverUsers.count + incomingLikes.count + 1)
        )
    }

    func markInboxSeen() async throws {}

    func markNotificationsSeen() async throws {}

    func registerPushDevice(token: String, environment: APNSEnvironment, bundleId: String, deviceName: String?) async throws {}
}

private let mockCourt = Court(
    id: "court-1",
    name: "Tennis Prime",
    address: "Аптекарская наб., 7",
    district: "petrogradsky",
    locationLat: 59.9726,
    locationLng: 30.3162,
    distanceLabel: "3.4 км",
    nearestMetroName: "Петроградская",
    supportedSports: [.tennis],
    phone: "+7 (812) 555-10-10",
    workingHours: "07:00-23:00",
    yandexMapsUrl: nil,
    websiteUrl: "https://tennisprime.example.com",
    bookingUrl: "https://tennisprime.example.com/book",
    photoUrl: nil,
    priceRange: "$$",
    rating: 4.9
)

private func makeDiscoverUser(
    id: String,
    name: String,
    age: Int,
    city: String,
    district: String,
    districtLabel: String,
    bio: String,
    sports: [Sport],
    levels: [String: Int],
    format: PlayFormat,
    surface: Surface,
    days: [String],
    ranges: [String],
    distance: String,
    score: Double,
    searches: [GameSearch],
    reasons: [String] = []
) -> DiscoverUser {
    let payload: [String: Any] = [
        "id": id,
        "name": name,
        "age": age,
        "city": city,
        "district": district,
        "districtLabel": districtLabel,
        "bio": bio,
        "avatarUrl": NSNull(),
        "tennisLevel": levels["tennis"] ?? 5,
        "preferredSports": sports.map(\.rawValue),
        "sportLevels": levels,
        "preferredPlayFormat": format.rawValue,
        "preferredSurface": surface.rawValue,
        "availableDays": days,
        "availableTimeRanges": ranges,
        "distanceLabel": distance,
        "score": score,
        "explainabilityReasons": reasons,
        "gameSearches": searches.map(gameSearchDictionary)
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return try! JSONDecoder().decode(DiscoverUser.self, from: data)
}

private func makeSimulationResponders(for search: GameSearch, count: Int) -> [DiscoverUser] {
    let names = ["Елена", "Мария", "София", "Никита"]
    let districts = ["petrogradsky", "primorsky", "central", "moskovsky"]

    return (0 ..< count).map { index in
        let level = min(max((search.selfLevel ?? 5) + (index % 2 == 0 ? 0 : -1), 1), 10)
        return makeDiscoverUser(
            id: "sim-responder-\(search.id)-\(index + 1)",
            name: names[index % names.count],
            age: 27 + index * 3,
            city: "Санкт-Петербург",
            district: districts[index % districts.count],
            districtLabel: localizedDistrictName(districts[index % districts.count]) ?? "Район",
            bio: "Симуляция: готов(а) регулярно играть и голосовать за предложенные слоты.",
            sports: [search.sport],
            levels: [search.sport.rawValue: level],
            format: search.format,
            surface: .any,
            days: search.preferredDays.isEmpty ? ["wednesday"] : search.preferredDays,
            ranges: search.preferredTimeRanges.isEmpty ? ["evening"] : search.preferredTimeRanges,
            distance: "\(3 + index).\(index) км",
            score: 92 - Double(index * 3),
            searches: []
        )
    }
}

private func gameSearchDictionary(_ search: GameSearch) -> [String: Any] {
    [
        "id": search.id,
        "status": search.status,
        "searchType": search.searchType.rawValue,
        "hotWindow": search.hotWindow?.rawValue as Any,
        "hotStartsAt": search.hotStartsAt as Any,
        "durationMinutes": search.durationMinutes as Any,
        "hasCourtBooked": search.hasCourtBooked,
        "sport": search.sport.rawValue,
        "selfLevel": search.selfLevel as Any,
        "selfLevelUnknown": search.selfLevelUnknown as Any,
        "desiredLevelMin": search.desiredLevelMin as Any,
        "desiredLevelMax": search.desiredLevelMax as Any,
        "format": search.format.rawValue,
        "playersNeeded": search.playersNeeded,
        "preferredDays": search.preferredDays,
        "preferredTimeRanges": search.preferredTimeRanges,
        "comment": search.comment as Any,
        "isActive": search.isActive as Any,
        "isExpired": search.isExpired as Any,
        "preferredCourt": search.preferredCourt.map(courtDictionary) as Any,
        "responses": []
    ]
}

private func courtDictionary(_ court: Court) -> [String: Any] {
    [
        "id": court.id,
        "name": court.name,
        "address": court.address,
        "district": court.district as Any,
        "locationLat": court.locationLat,
        "locationLng": court.locationLng,
        "distanceLabel": court.distanceLabel as Any,
        "nearestMetroName": court.nearestMetroName as Any,
        "supportedSports": court.supportedSports?.map(\.rawValue) as Any,
        "phone": court.phone as Any,
        "workingHours": court.workingHours as Any,
        "yandexMapsUrl": court.yandexMapsUrl as Any,
        "websiteUrl": court.websiteUrl as Any,
        "bookingUrl": court.bookingUrl as Any,
        "photoUrl": court.photoUrl as Any,
        "priceRange": court.priceRange as Any,
        "rating": court.rating as Any
    ]
}
