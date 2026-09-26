import SwiftUI

private let appStoreURL = URL(string: "https://apps.apple.com/app/id6768862885")!

struct AppUpdateBanner: View {
    let latestVersion: String
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateBounce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppTheme.court.opacity(0.14))
                        .frame(width: 34, height: 34)

                    TennisBallIcon()
                        .frame(width: 22, height: 22)
                        .offset(y: animateBounce ? -3 : 3)
                        .rotationEffect(.degrees(animateBounce ? 8 : -8))
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animateBounce)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("Update available", "Доступно обновление"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text(L10n.string(
                        "Version \(latestVersion) brings new filters and fixes",
                        "Версия \(latestVersion) — новые фильтры и исправления"
                    ))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(L10n.string("Not now", "Не сейчас"), action: onDismiss)
                    .buttonStyle(.bordered)
                Button(L10n.string("Update", "Обновить")) {
                    openURL(appStoreURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.court)
            }
        }
        .padding(14)
        .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.ink.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: AppTheme.ink.opacity(0.1), radius: 16, x: 0, y: 8)
        .onAppear {
            // Decorative loop: Reduce Motion keeps the ball still.
            animateBounce = !reduceMotion
        }
    }
}

struct AppUpdateRequiredView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateBounce = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(AppTheme.court.opacity(0.16))
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)

                    Circle()
                        .fill(AppTheme.court.opacity(0.14))
                        .frame(width: 96, height: 96)

                    TennisBallIcon()
                        .frame(width: 56, height: 56)
                        .offset(y: animateBounce ? -5 : 5)
                        .rotationEffect(.degrees(animateBounce ? 8 : -8))
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animateBounce)
                }

                VStack(spacing: 8) {
                    Text(L10n.string("Update required", "Нужно обновить"))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text(L10n.string(
                        "This version is no longer supported. Update the app to continue.",
                        "Эта версия больше не поддерживается. Обновите приложение, чтобы продолжить."
                    ))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
                    .multilineTextAlignment(.center)
                }

                Button(L10n.string("Update", "Обновить")) {
                    openURL(appStoreURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.court)
                .controlSize(.large)
            }
            .padding(.horizontal, 36)
        }
        .onAppear {
            // Decorative loops: Reduce Motion keeps the screen still.
            animateBounce = !reduceMotion
            pulse = !reduceMotion
        }
    }
}
