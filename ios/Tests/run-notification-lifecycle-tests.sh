#!/bin/sh
set -eu
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tennis-notification-lifecycle.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
python3 - "$test_dir" "$temp_dir" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]).parent / 'TennisSearchIOS/Services/NotificationManager.swift').read_text()
def declaration(name):
    start = source.index(name)
    index = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[index] == '{') - (source[index] == '}')
        index += 1
    return source[start:index]
text = '''import Foundation
struct AppNotification {
    enum Kind { case new_match, new_message, incoming_like, search_response, application_result, hot_event }
    let id: String
    var type = Kind.new_message
    var title = "Private title"
    var description = "Private body"
    var href = "/private"
}
struct ActivitySummary {
    var inboxBadgeCount = 0, incomingLikesCount = 0, hotBadgeCount = 0, discoverBadgeCount = 0, activeSearchesCount = 0, searchesBadgeCount = 0
    var notificationSound = true
    static let empty = Self()
    func removingHotEvents() -> Self { self }
}
struct MatchGameRequest {
    let id: String
    var status = "accepted"
    var outcome: String?
    var proposedDate: Date? = Date().addingTimeInterval(7200)
    struct Sport { let title = "Tennis" }
    let sport = Sport()
    struct Court { let name: String }
    var proposedCourt: Court?
}
extension Date { func formattedHourMinute() -> String { "12:00" } }
struct NotificationSound { static let `default` = Self() }
final class UNMutableNotificationContent {
    var title = "", body = ""
    var sound: NotificationSound?
    var userInfo: [String: String] = [:]
}
struct UNCalendarNotificationTrigger { let dateMatching: DateComponents; let repeats: Bool }
struct UNNotificationRequest {
    let identifier: String
    let content: UNMutableNotificationContent
    let trigger: UNCalendarNotificationTrigger?
}
@MainActor final class UIApplication {
    static let shared = UIApplication()
    var applicationIconBadgeNumber = 0
    var unregisterCount = 0
    func unregisterForRemoteNotifications() { unregisterCount += 1 }
}
@MainActor final class NotificationCenterStub {
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: [String: UNNotificationRequest] = [:]
    var beforeAdd: (() async -> Void)?
    var beforePending: (() async -> Void)?
    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await beforePending?()
        return Array(pending.values)
    }
    func add(_ request: UNNotificationRequest) async throws {
        await beforeAdd?()
        pending[request.identifier] = request
    }
    func removeAllPendingNotificationRequests() { pending = [:] }
    func removeAllDeliveredNotifications() { delivered = [:] }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) { for id in ids { pending[id] = nil } }
    func removeDeliveredNotifications(withIdentifiers ids: [String]) { for id in ids { delivered[id] = nil } }
}
@MainActor final class TennisRepository {
    var fetch: () async throws -> [AppNotification] = { [] }
    func fetchNotifications() async throws -> [AppNotification] { try await fetch() }
    func fetchActivitySummary() async throws -> ActivitySummary { ActivitySummary(discoverBadgeCount: 1) }
}
@MainActor final class NotificationLifecycleHarness {
    let center = NotificationCenterStub()
    let defaults: UserDefaults
    let suite = "notification.tests." + UUID().uuidString
    var monitoringGeneration = UUID()
    var repository: TennisRepository?
    var monitorTask: Task<Void, Never>?
    var realtimeTask: Task<Void, Never>?
    var hasCompletedInitialSync = true
    var notifications: [AppNotification] = []
    var summary = ActivitySummary.empty
    var mutedNotificationHrefs: Set<String> = []
    enum Authorization { case notDetermined, authorized, provisional }
    var authorizationStatus = Authorization.authorized
    let storedIDsKey = "delivered", realtimeLastEventIDKey = "realtime", seenHotEventIDsKey = "seen", storedAPNSTokenKey = "token"
    let gameReminderPrefix = "ios.game.reminder.1h."
    let legacyGameReminderPrefixes = ["ios.game.reminder.2h."]
    let scheduledGameReminderIDsKey = "scheduled"
    let gameReminderLeadTime: TimeInterval = 3600
    init() { defaults = UserDefaults(suiteName: suite)! }
    func start(_ repository: TennisRepository) { stopMonitoring(); self.repository = repository }
    func requestAuthorization() async {}
'''
for name in ['    func stopMonitoring()', '    var pushDeviceToken:', '    func clearAccountState()', '    private func isCurrent(', '    func manualRefresh(', '    func scheduleGameReminders(', '    private func sync(', '    private func scheduleLocalNotification(', '    private func scheduleGameReminder(', '    private func gameReminderIdentifier(', '    private func gameReminderBaseIdentifier(', '    private func isGameReminderIdentifier(', '    private func applyBadge(', '    private func effectiveSummary(', '    private var seenHotEventIDs:', '    private func rememberSeenHotEventIDs(', '    private var deliveredIDs:', '    private var scheduledGameReminderIDs:', '    private func rememberScheduledGameReminder(', '    private func rememberDelivered(', '    private func shouldScheduleLocalNotification(']:
    text += '\n' + declaration(name)
text += '\n}\n'
(Path(sys.argv[2]) / 'NotificationProduction.swift').write_text(text)
PY
swiftc "$temp_dir/NotificationProduction.swift" "$test_dir/NotificationLifecycleTests.swift" -o "$temp_dir/notification-lifecycle-tests"
"$temp_dir/notification-lifecycle-tests"
