import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(
            name: .didRegisterForRemoteNotifications,
            object: nil,
            userInfo: ["token": token]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: .didFailToRegisterForRemoteNotifications,
            object: nil,
            userInfo: ["error": error]
        )
        print("apns registration error:", error.localizedDescription)
    }
}

extension Notification.Name {
    static let didRegisterForRemoteNotifications = Notification.Name("TennisSearchIOS.didRegisterForRemoteNotifications")
    static let didFailToRegisterForRemoteNotifications = Notification.Name("TennisSearchIOS.didFailToRegisterForRemoteNotifications")
}
