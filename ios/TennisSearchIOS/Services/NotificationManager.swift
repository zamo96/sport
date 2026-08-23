import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var summary: ActivitySummary = .empty

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var monitorTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var hasCompletedInitialSync = false
    private var repository: (any TennisRepository)?
    private var mutedNotificationHrefs: Set<String> = []

    private let storedIDsKey = "ios.notification.delivered.ids"
    private let realtimeLastEventIDKey = "ios.realtime.last_event.id"
    private let seenHotEventIDsKey = "ios.notification.hot.seen.ids"
    private let storedAPNSTokenKey = "ios.apns.token"
    private let gameReminderPrefix = "ios.game.reminder.1h."
    private let legacyGameReminderPrefixes = ["ios.game.reminder.2h."]
    private let scheduledGameReminderIDsKey = "ios.game.reminder.scheduled.ids.v1"
    private let gameReminderLeadTime: TimeInterval = 60 * 60
    private let monitorIntervalNanoseconds: UInt64 = 5_000_000_000

    override init() {
        super.init()
        center.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPNSRegistration(_:)),
            name: .didRegisterForRemoteNotifications,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPNSRegistrationFailure(_:)),
            name: .didFailToRegisterForRemoteNotifications,
            object: nil
        )
    }

    var unreadNotificationCount: Int {
        summary.discoverBadgeCount
    }

    func configure() async {
        await refreshAuthorizationStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("notification auth error:", error.localizedDescription)
        }

        await refreshAuthorizationStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func startMonitoring(repository: TennisRepository) {
        stopMonitoring()
        self.repository = repository
        monitorTask = Task { [weak self] in
            guard let self else { return }
            if authorizationStatus == .notDetermined {
                await requestAuthorization()
            }
            await registerCurrentDeviceIfPossible()
            await sync(repository: repository)
            startRealtimeMonitoring(repository: repository)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: monitorIntervalNanoseconds)
                await sync(repository: repository)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        realtimeTask?.cancel()
        monitorTask = nil
        realtimeTask = nil
        hasCompletedInitialSync = false
        repository = nil
    }

    func manualRefresh(repository: TennisRepository) async {
        await sync(repository: repository)
    }

    func scheduleGameReminders(for gameRequests: [MatchGameRequest], playSound: Bool) async {
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }

        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            return
        }

        let now = Date()
        let reminders = gameRequests.compactMap { request -> (id: String, request: MatchGameRequest, reminderDate: Date)? in
            let status = request.status.lowercased()
            guard status == "accepted" || status == "approved",
                  request.outcome == nil,
                  let startDate = request.proposedDate,
                  startDate > now else {
                return nil
            }

            let reminderDate = startDate.addingTimeInterval(-gameReminderLeadTime)
            let effectiveReminderDate = reminderDate > now
                ? reminderDate
                : now.addingTimeInterval(10)

            return (gameReminderIdentifier(for: request, startDate: startDate), request, effectiveReminderDate)
        }

        let desiredIDs = Set(reminders.map(\.id))
        let pendingReminderIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(isGameReminderIdentifier)
        let pendingReminderIDSet = Set(pendingReminderIDs)
        center.removePendingNotificationRequests(
            withIdentifiers: pendingReminderIDs.filter { !desiredIDs.contains($0) }
        )

        for reminder in reminders {
            if scheduledGameReminderIDs.contains(reminder.id) {
                continue
            }

            if pendingReminderIDSet.contains(reminder.id) {
                rememberScheduledGameReminder(id: reminder.id)
                continue
            }

            let didSchedule = await scheduleGameReminder(
                identifier: reminder.id,
                request: reminder.request,
                reminderDate: reminder.reminderDate,
                playSound: playSound
            )
            if didSchedule {
                rememberScheduledGameReminder(id: reminder.id)
            }
        }
    }

    func markNotificationsOpened() {
        summary = ActivitySummary(
            inboxBadgeCount: summary.inboxBadgeCount,
            incomingLikesCount: summary.incomingLikesCount,
            hotBadgeCount: summary.hotBadgeCount,
            discoverBadgeCount: 0,
            activeSearchesCount: summary.activeSearchesCount,
            searchesBadgeCount: summary.searchesBadgeCount,
            notificationSound: summary.notificationSound
        )
        applyBadge(summary: summary)
    }

    func markHotEventsOpened() {
        let hotEventIDs = notifications
            .filter { $0.type == .hot_event }
            .map(\.id)
        rememberSeenHotEventIDs(hotEventIDs)

        summary = summary.removingHotEvents()
        applyBadge(summary: summary)
    }

    func setNotificationMuted(href: String, isMuted: Bool) {
        if isMuted {
            mutedNotificationHrefs.insert(href)
        } else {
            mutedNotificationHrefs.remove(href)
        }
    }

    private func sync(repository: TennisRepository) async {
        do {
            async let notificationsRequest = repository.fetchNotifications()
            async let summaryRequest = repository.fetchActivitySummary()

            let fetchedNotifications = try await notificationsRequest
            let fetchedSummary = try await summaryRequest

            let newNotifications = fetchedNotifications.filter { item in
                !deliveredIDs.contains(item.id)
            }

            let effectiveSummary = effectiveSummary(from: fetchedSummary, notifications: fetchedNotifications)

            notifications = fetchedNotifications
            summary = effectiveSummary
            applyBadge(summary: effectiveSummary)

            if hasCompletedInitialSync && (authorizationStatus == .authorized || authorizationStatus == .provisional) {
                for item in newNotifications {
                    if shouldScheduleLocalNotification(for: item) {
                        await scheduleLocalNotification(for: item, playSound: fetchedSummary.notificationSound)
                    }
                    rememberDelivered(id: item.id)
                }
            } else {
                fetchedNotifications.forEach { rememberDelivered(id: $0.id) }
            }

            hasCompletedInitialSync = true
        } catch {
            print("notification sync error:", error.localizedDescription)
        }
    }

    private func startRealtimeMonitoring(repository: TennisRepository) {
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            var reconnectDelay: UInt64 = 1_000_000_000

            while !Task.isCancelled {
                do {
                    let lastEventId = defaults.string(forKey: realtimeLastEventIDKey)
                    for try await event in repository.realtimeEvents(lastEventId: lastEventId) {
                        guard !Task.isCancelled else {
                            return
                        }

                        if let eventId = event.id, !eventId.isEmpty {
                            defaults.set(eventId, forKey: realtimeLastEventIDKey)
                        }

                        NotificationCenter.default.post(name: .tennisRealtimeEventReceived, object: event)
                        await sync(repository: repository)
                        reconnectDelay = 1_000_000_000
                    }
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    print("realtime stream error:", error.localizedDescription)
                }

                try? await Task.sleep(nanoseconds: reconnectDelay)
                reconnectDelay = min(reconnectDelay * 2, 30_000_000_000)
            }
        }
    }

    private func scheduleLocalNotification(for item: AppNotification, playSound: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.description
        content.sound = playSound ? .default : nil
        content.userInfo = ["href": item.href, "notificationId": item.id]

        let request = UNNotificationRequest(
            identifier: item.id,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            print("notification schedule error:", error.localizedDescription)
        }
    }

    private func scheduleGameReminder(
        identifier: String,
        request: MatchGameRequest,
        reminderDate: Date,
        playSound: Bool
    ) async -> Bool {
        guard let startDate = request.proposedDate else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Игра скоро начнется"
        content.body = [
            request.sport.title,
            startDate.formattedHourMinute(),
            request.proposedCourt?.name
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        content.sound = playSound ? .default : nil
        content.userInfo = [
            "href": "/play/games/\(request.id)",
            "gameRequestId": request.id
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(notificationRequest)
            return true
        } catch {
            print("game reminder schedule error:", error.localizedDescription)
            return false
        }
    }

    private func gameReminderIdentifier(for request: MatchGameRequest, startDate: Date) -> String {
        "\(gameReminderPrefix)\(request.id).\(Int(startDate.timeIntervalSince1970))"
    }

    private func isGameReminderIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(gameReminderPrefix) || legacyGameReminderPrefixes.contains { identifier.hasPrefix($0) }
    }

    private func applyBadge(summary: ActivitySummary) {
        UIApplication.shared.applicationIconBadgeNumber = summary.inboxBadgeCount + summary.discoverBadgeCount + summary.searchesBadgeCount
    }

    private func effectiveSummary(from fetchedSummary: ActivitySummary, notifications: [AppNotification]) -> ActivitySummary {
        let hotEventIDs = Set(notifications.filter { $0.type == .hot_event }.map(\.id))
        guard fetchedSummary.hotBadgeCount > 0,
              !hotEventIDs.isEmpty,
              hotEventIDs.isSubset(of: seenHotEventIDs) else {
            return fetchedSummary
        }

        return fetchedSummary.removingHotEvents()
    }

    private var seenHotEventIDs: Set<String> {
        Set(defaults.stringArray(forKey: seenHotEventIDsKey) ?? [])
    }

    private func rememberSeenHotEventIDs(_ ids: [String]) {
        guard !ids.isEmpty else {
            return
        }

        var stored = seenHotEventIDs
        stored.formUnion(ids)
        defaults.set(Array(stored).sorted(), forKey: seenHotEventIDsKey)
    }

    private var deliveredIDs: Set<String> {
        Set(defaults.stringArray(forKey: storedIDsKey) ?? [])
    }

    private var scheduledGameReminderIDs: Set<String> {
        Set(defaults.stringArray(forKey: scheduledGameReminderIDsKey) ?? [])
    }

    private func rememberScheduledGameReminder(id: String) {
        var ids = scheduledGameReminderIDs
        guard !ids.contains(id) else {
            return
        }

        ids.insert(id)
        defaults.set(Array(ids.sorted().suffix(200)), forKey: scheduledGameReminderIDsKey)
    }

    private func rememberDelivered(id: String) {
        var ids = deliveredIDs
        guard !ids.contains(id) else {
            return
        }

        ids.insert(id)
        let trimmed = Array(ids.suffix(200))
        defaults.set(trimmed, forKey: storedIDsKey)
    }

    private func shouldScheduleLocalNotification(for item: AppNotification) -> Bool {
        if mutedNotificationHrefs.contains(item.href) {
            return false
        }

        switch item.type {
        case .new_match, .new_message, .incoming_like, .search_response, .application_result, .hot_event:
            return true
        }
    }

    @objc private func handleAPNSRegistration(_ notification: Notification) {
        guard let token = notification.userInfo?["token"] as? String else {
            return
        }

        defaults.set(token, forKey: storedAPNSTokenKey)
        Task {
            await registerCurrentDeviceIfPossible()
        }
    }

    @objc private func handleAPNSRegistrationFailure(_ notification: Notification) {
        let error = notification.userInfo?["error"] as? Error
        print("apns registration failure:", error?.localizedDescription ?? "unknown")
    }

    private func registerCurrentDeviceIfPossible() async {
        guard let repository else {
            return
        }

        guard let token = defaults.string(forKey: storedAPNSTokenKey), !token.isEmpty else {
            return
        }

        guard let environment = AppConfig.apnsEnvironment else {
            return
        }

        guard let bundleId = Bundle.main.bundleIdentifier else {
            return
        }

        do {
            try await repository.registerPushDevice(
                token: token,
                environment: environment,
                bundleId: bundleId,
                deviceName: UIDevice.current.name
            )
        } catch {
            print("apns device register error:", error.localizedDescription)
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let href = response.notification.request.content.userInfo["href"] as? String

        DispatchQueue.main.async {
            if let href {
                NotificationCenter.default.post(name: .tennisNotificationRouteRequested, object: href)
            }
            completionHandler()
        }
    }
}
