import SwiftUI

@main
struct TennisSearchIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(appModel.notificationManager)
                .task {
                    await appModel.bootstrap()
                }
        }
    }
}
