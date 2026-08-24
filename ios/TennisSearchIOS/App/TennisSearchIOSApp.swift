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
                .onOpenURL { url in
                    guard url.scheme?.lowercased() == "sportsearch" else { return }
                    switch url.host?.lowercased() {
                    case "upcoming":
                        appModel.navigate(to: .discover(.upcoming))
                    case "matches":
                        appModel.navigate(to: .matches)
                    default:
                        break
                    }
                }
        }
    }
}
