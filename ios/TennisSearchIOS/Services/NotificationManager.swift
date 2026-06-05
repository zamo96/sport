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
    private var hasCompletedInitialSync = false
    private var repository: (any TennisRepository)?

    private let storedIDsKey = "ios.notification.delivered.ids"
    private let seenHotEventIDsKey = "ios.notification.hot.seen.ids"
    private let storedAPNSTokenKey = "ios.apns.token"
    private let gameReminderPrefix = "ios.game.reminder.2h."

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
            await registerCurrentDeviceIfPossible()
            await sync(repository: repository)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await sync(repository: repository)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
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

            let reminderDate = startDate.addingTimeInterval(-2 * 60 * 60)
            let effectiveReminderDate = reminderDate > now
                ? reminderDate
                : now.addingTimeInterval(10)

            return ("\(gameReminderPrefix)\(request.id)", request, effectiveReminderDate)
        }

        let desiredIDs = Set(reminders.map(\.id))
        let pendingReminderIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(gameReminderPrefix) }
        center.removePendingNotificationRequests(
            withIdentifiers: pendingReminderIDs.filter { !desiredIDs.contains($0) }
        )

        for reminder in reminders {
            await scheduleGameReminder(
                identifier: reminder.id,
                request: reminder.request,
                reminderDate: reminder.reminderDate,
                playSound: playSound
            )
        }
    }

    func markNotificationsOpened() {
        summary = ActivitySummary(
            inboxBadgeCount: summary.inboxBadgeCount,
            incomingLikesCount: summary.incomingLikesCount,
            hotBadgeCount: summary.hotBadgeCount,
            discoverBadgeCount: 0,
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
    ) async {
        guard let startDate = request.proposedDate else {
            return
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
            [.year, .month, .day, .hour, .minute],
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
        } catch {
            print("game reminder schedule error:", error.localizedDescription)
        }
    }

    private func applyBadge(summary: ActivitySummary) {
        UIApplication.shared.applicationIconBadgeNumber = summary.inboxBadgeCount + summary.discoverBadgeCount
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
        switch item.type {
        case .new_match, .new_message:
            return false
        default:
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
}
