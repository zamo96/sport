import SwiftUI

/// The optional analytics consent, asked once in a while, on a calm screen and never as a gate:
/// two buttons of the same size, and the app works the same whatever is chosen. The rules for when
/// it shows are in `AnalyticsAskPolicy`; a switch stays in Profile → Privacy for good.
struct AnalyticsAskCard: View {
    private enum Phase: Equatable {
        case hidden, ask, thanks(String)
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.hidden
    @State private var isDetailsPresented = false
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        Group {
            switch phase {
            case .hidden:
                // Not EmptyView: modifiers on it never run, so `.task` below would not start.
                Color.clear.frame(width: 0, height: 0)
            case .ask:
                askCard.padding(.bottom, 12)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            case .thanks(let text):
                thanksRow(text).padding(.bottom, 12).transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85), value: phase)
        .task(id: appModel.currentUser?.id) { refresh() }
        .sheet(isPresented: $isDetailsPresented) {
            AnalyticsDetailsSheet(
                onAllow: { isDetailsPresented = false; answer(allow: true) },
                onLater: { isDetailsPresented = false; answer(allow: false) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground(VisitStyle.sheet)
        }
    }

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(VisitStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(VisitStyle.accent.opacity(0.12), in: Circle())
                Text(L10n.string("Help us make the app better", "Помогите сделать НаТреню лучше"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(L10n.string("If you allow it, we will see which features you use and where you get stuck, and fix what gets in the way.", "Разрешите — и мы увидим, какими функциями вы пользуетесь и где вам неудобно. Так мы исправим то, что мешает."))
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.string("Only screens and actions in your account, kept for 90 days. No chats, photos or exact location.", "Только экраны и действия в вашем аккаунте, 90 дней. Без чатов, фото и точного места."))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(VisitStyle.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    answer(allow: true)
                } label: {
                    ZStack {
                        if isSaving { ProgressView().tint(VisitStyle.onAccent) }
                        else { Text(L10n.string("Allow", "Разрешить")) }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(VisitStyle.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(VisitStyle.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityIdentifier("analytics-ask-allow")

                Button {
                    answer(allow: false)
                } label: {
                    Text(L10n.string("Not now", "Не сейчас"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(VisitStyle.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityIdentifier("analytics-ask-later")
            }

            HStack(alignment: .center, spacing: 8) {
                Button {
                    AppHaptics.selection()
                    isDetailsPresented = true
                } label: {
                    Text(L10n.string("What exactly we collect ›", "Что именно собираем ›"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VisitStyle.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Text(L10n.string("The app works the same either way", "Приложение работает так же, что бы вы ни выбрали"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(VisitStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private func thanksRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(VisitStyle.onAccent)
                .frame(width: 26, height: 26)
                .background(VisitStyle.accent, in: Circle())
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(VisitStyle.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Logic

    private func refresh() {
        guard let user = appModel.currentUser, appModel.isAuthenticated,
              user.isOnboardingComplete, user.consents?.reviewRequired != true else {
            phase = .hidden
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-analytics-ask-preview"), user.consents?.analytics != true {
            phase = .ask
            return
        }
        #endif
        let now = Date()
        let state = AnalyticsAskStore.load(userID: user.id)
        if AnalyticsAskPolicy.shouldShow(state, analyticsGranted: user.consents?.analytics == true, now: now) {
            AnalyticsAskStore.update(userID: user.id) { AnalyticsAskPolicy.recordShown(&$0, now: now) }
            phase = .ask
        } else {
            phase = .hidden
        }
    }

    private func answer(allow: Bool) {
        guard let userID = appModel.currentUser?.id, !isSaving else { return }
        errorText = nil
        guard allow else {
            AppHaptics.selection()
            AnalyticsAskStore.update(userID: userID) { AnalyticsAskPolicy.recordDeclined(&$0, now: Date()) }
            showThanks(L10n.string("OK. You can change your mind in Profile → Privacy", "Хорошо. Передумаете — Профиль → Приватность"))
            return
        }
        isSaving = true
        Task {
            let failure = await appModel.submitConsents(ConsentUpdate(analytics: true))
            isSaving = false
            if let failure {
                errorText = failure
                AppHaptics.notification(.error)
                return
            }
            AppHaptics.notification(.success)
            AnalyticsAskStore.update(userID: userID) { AnalyticsAskPolicy.recordGranted(&$0) }
            showThanks(L10n.string("Thank you. You can switch it off in Profile → Privacy", "Спасибо. Выключить можно в Профиле → Приватность"))
        }
    }

    private func showThanks(_ text: String) {
        phase = .thanks(text)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if phase == .thanks(text) { phase = .hidden }
        }
    }
}

extension View {
    /// Puts the analytics question above this content. The card adds its own gap only while it is shown.
    func analyticsAskCardAbove() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AnalyticsAskCard()
            self
        }
    }
}

/// «Что именно собираем»: the same list as the consent text, in plain words.
private struct AnalyticsDetailsSheet: View {
    let onAllow: () -> Void
    let onLater: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("What we collect", "Что мы собираем"))
                            .font(.system(size: 26, weight: .heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n.string("Only if you allow it. Saying no limits nothing.", "Только если вы разрешите. Отказ ничего не ограничивает."))
                            .font(.system(size: 15))
                            .foregroundStyle(VisitStyle.secondaryText)
                    }

                    list(
                        title: L10n.string("WE COLLECT", "СОБИРАЕМ"),
                        tint: VisitStyle.accent,
                        symbol: "checkmark",
                        items: [
                            L10n.string("Your account identifier", "Идентификатор аккаунта"),
                            L10n.string("Which screens and steps you open", "Какие экраны и шаги вы открываете"),
                            L10n.string("Actions: an invitation, a response, creating a search, a played game, opening a notification", "Действия: приглашение, отклик, создание поиска, сыгранная игра, открытие уведомления"),
                            L10n.string("Date and time of the event", "Дату и время события"),
                            L10n.string("Type of app: iOS, Android or web", "Тип приложения: iOS, Android или веб")
                        ]
                    )

                    list(
                        title: L10n.string("NEVER COLLECTED", "НИКОГДА НЕ СОБИРАЕМ"),
                        tint: VisitStyle.destructive,
                        symbol: "xmark",
                        items: [
                            L10n.string("Messages from your chats", "Переписку из чатов"),
                            L10n.string("Photos and videos", "Фото и видео"),
                            L10n.string("Exact coordinates", "Точные координаты"),
                            L10n.string("Advertising profiles and screen recording", "Рекламный профиль и запись экрана")
                        ]
                    )

                    VStack(spacing: 0) {
                        fact(L10n.string("Why", "Зачем"), L10n.string("To understand which features people use and where they struggle", "Понимать, какими функциями пользуются, и находить, где людям неудобно"))
                        fact(L10n.string("Where", "Где"), L10n.string("Only with us. No outside analytics platforms are used", "Только у НаТреню. Внешние аналитические платформы не используются"))
                        fact(L10n.string("How long", "Сколько храним"), L10n.string("90 days, then the events are deleted", "90 дней, потом события удаляются"))
                        fact(L10n.string("How to withdraw", "Как отозвать"), L10n.string("Profile → Privacy. What is saved is deleted within 30 days", "Профиль → Приватность. Сохранённое удаляем в течение 30 дней"), isLast: true)
                    }
                    .padding(.horizontal, 16)
                    .background(VisitStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let url = LegalDocuments.analyticsConsentURL {
                        Button {
                            openURL(url)
                        } label: {
                            Text(L10n.string("Full text of the consent ↗", "Полный текст согласия ↗"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(VisitStyle.accent)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                Button(action: onAllow) {
                    Text(L10n.string("Allow", "Разрешить"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(VisitStyle.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(VisitStyle.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: onLater) {
                    Text(L10n.string("Not now", "Не сейчас"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(VisitStyle.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(VisitStyle.sheet)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private func list(title: String, tint: Color, symbol: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(tint)
                        .frame(width: 18, height: 22)
                    Text(item)
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fact(_ title: String, _ text: String, isLast: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VisitStyle.secondaryText)
            Text(text)
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        }
    }
}
