import SwiftUI

@main
struct TennisSearchIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var localeStore: LocaleStore
    @StateObject private var appModel: AppModel

    init() {
        let localeStore = LocaleStore()
        _localeStore = StateObject(wrappedValue: localeStore)
        _appModel = StateObject(wrappedValue: AppModel(localeStore: localeStore))
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                if appModel.updateStatus == .hardUpdateRequired {
                    AppUpdateRequiredView()
                } else {
                    ContentView()

                    VStack(spacing: 10) {
                        if let recommendation = appModel.pendingLocaleRecommendation {
                            LocaleRecommendationBanner(
                                recommendation: recommendation,
                                onAccept: appModel.acceptLocaleRecommendation,
                                onDismiss: appModel.dismissLocaleRecommendation
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if let latestVersion = appModel.pendingUpdateBanner {
                            AppUpdateBanner(
                                latestVersion: latestVersion,
                                onDismiss: appModel.dismissUpdateBanner
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .zIndex(100)
                }
            }
                .environmentObject(appModel)
                .environmentObject(appModel.notificationManager)
                .environmentObject(localeStore)
                .environment(\.locale, localeStore.locale)
                .animation(AppMotion.standard, value: appModel.pendingLocaleRecommendation)
                .animation(AppMotion.standard, value: appModel.pendingUpdateBanner)
                .task {
                    if !SportsActivityFeedPreview.isEnabled {
                        await appModel.bootstrap()
                    }
                }
                .onOpenURL { url in
                    appModel.handleIncomingURL(url)
                }
        }
    }
}

private struct LocaleRecommendationBanner: View {
    @EnvironmentObject private var localeStore: LocaleStore

    let recommendation: AppModel.LocaleRecommendation
    let onAccept: () -> Void
    let onDismiss: () -> Void

    private var languageName: String {
        recommendation.locale.displayName
    }

    private var isRussian: Bool { localeStore.effectiveLocale == .ru }
    private var title: String { isRussian ? "Язык для вашей локации" : "Language for your location" }
    private var message: String {
        if isRussian {
            return recommendation.locale == .ru
                ? "Для выбранной страны рекомендуем русский язык. Переключить?"
                : "Для выбранной страны рекомендуем English. Переключить?"
        }
        return recommendation.locale == .ru
            ? "Russian is recommended for the selected country. Switch?"
            : "English is recommended for the selected country. Switch?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isRussian ? "Закрыть" : "Close"))
            }

            HStack(spacing: 10) {
                Button(isRussian ? "Оставить текущий" : "Keep current", action: onDismiss)
                    .buttonStyle(.bordered)
                Button(isRussian ? "Переключить на \(languageName)" : "Switch to \(languageName)", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .padding(14)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}
