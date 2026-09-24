import Foundation

@MainActor
final class NotificationGate<Value> {
    var continuation: CheckedContinuation<Value, Never>?
    func wait() async -> Value { await withCheckedContinuation { continuation = $0 } }
    func waitUntilSuspended() async { while continuation == nil { await Task.yield() } }
    func release(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}

@main
@MainActor
struct NotificationLifecycleTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func main() async {
        let manager = NotificationLifecycleHarness()
        defer { manager.defaults.removePersistentDomain(forName: manager.suite) }
        manager.defaults.set("apns", forKey: manager.storedAPNSTokenKey)
        for key in [manager.storedIDsKey, manager.realtimeLastEventIDKey, manager.seenHotEventIDsKey, manager.scheduledGameReminderIDsKey] {
            manager.defaults.set("old-account", forKey: key)
        }
        let old = TennisRepository()
        let gate = NotificationGate<[AppNotification]>()
        old.fetch = { await gate.wait() }
        manager.start(old)
        let oldSync = Task { await manager.manualRefresh(repository: old) }
        await gate.waitUntilSuspended()
        manager.clearAccountState()
        expect(manager.notifications.isEmpty && manager.summary.discoverBadgeCount == 0, "Logout immediately clears visible notification state")
        expect(manager.pushDeviceToken == "apns", "Logout retains only the install-wide APNs token")
        expect(manager.defaults.object(forKey: manager.realtimeLastEventIDKey) == nil && manager.defaults.object(forKey: manager.scheduledGameReminderIDsKey) == nil, "Logout drops old account delivery metadata")
        expect(UIApplication.shared.applicationIconBadgeNumber == 0 && UIApplication.shared.unregisterCount == 1, "Logout clears badge and unregisters remote notifications")
        let fresh = TennisRepository()
        fresh.fetch = { [AppNotification(id: "B")] }
        manager.start(fresh)
        await manager.manualRefresh(repository: fresh)
        gate.release([AppNotification(id: "A")])
        await oldSync.value
        expect(manager.notifications.map(\.id) == ["B"], "Late old-account sync cannot replace the next account notifications")

        let addGate = NotificationGate<Void>()
        manager.center.beforeAdd = { await addGate.wait() }
        let game = MatchGameRequest(id: "same-account-game")
        let oldReminder = Task { await manager.scheduleGameReminders(for: [game], playSound: true) }
        await addGate.waitUntilSuspended()
        manager.clearAccountState()
        manager.start(fresh)
        manager.center.beforeAdd = nil
        await manager.scheduleGameReminders(for: [game], playSound: true)
        let newIDs = Set(manager.center.pending.keys)
        expect(newIDs.count == 1, "A new session can schedule its game reminder")
        addGate.release(())
        await oldReminder.value
        expect(Set(manager.center.pending.keys) == newIDs, "Late old-session reminder is removed without deleting the same game's new reminder")
        await manager.scheduleGameReminders(for: [game], playSound: true)
        expect(Set(manager.center.pending.keys) == newIDs, "Repeated sync does not duplicate generation-scoped reminders")
        manager.clearAccountState()
        await manager.scheduleGameReminders(for: [game], playSound: true)
        expect(manager.center.pending.isEmpty, "A logged-out view cannot recreate reminders")
        print("Notification lifecycle tests: \(checks) checks passed")
    }
}
