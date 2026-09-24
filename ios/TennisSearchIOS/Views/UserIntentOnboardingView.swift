import SwiftUI

struct UserIntentOnboardingView: View {
    @State private var selection: Set<UserIntent>
    let onContinue: (Set<UserIntent>) -> Void
    let onBack: () -> Void

    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)

    init(initialSelection: Set<UserIntent>, onContinue: @escaping (Set<UserIntent>) -> Void, onBack: @escaping () -> Void) {
        _selection = State(initialValue: initialSelection)
        self.onContinue = onContinue
        self.onBack = onBack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Back", "Назад"))
                .accessibilityIdentifier("onboarding-intents-back")

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("YOUR SPORT, YOUR WAY", "СПОРТ В ТВОЁМ РИТМЕ"))
                        .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(lime)
                    Text(L10n.string("What brings you here?", "Что тебе интересно?"))
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string("Choose a few things you'd like to try. We'll show you where to start.", "Выбери, что хочется попробовать. После входа покажем, с чего начать."))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    ForEach(UserIntent.allCases) { intent in
                        intentChoice(intent)
                    }
                }

                VStack(spacing: 10) {
                    Text(L10n.string("Choose several, or skip. Every feature stays available.", "Можно выбрать несколько или пропустить. Все возможности останутся доступны."))
                        .font(.footnote).foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { onContinue(selection) } label: {
                        HStack {
                            Text(L10n.string("Continue", "Продолжить"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline).foregroundStyle(.black)
                        .padding(18).frame(maxWidth: .infinity, minHeight: 56)
                        .background(lime, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding-intents-continue")
                    Button(L10n.string("Skip for now", "Пока пропустить")) { onContinue([]) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("onboarding-intents-skip")
                }
            }
            .padding(22)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func intentChoice(_ intent: UserIntent) -> some View {
        let isSelected = selection.contains(intent)
        return Button {
            if isSelected { selection.remove(intent) } else { selection.insert(intent) }
            AppHaptics.selection()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: intent.systemImage)
                    .font(.title3).foregroundStyle(lime)
                    .frame(width: 34).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(intent.title).font(.headline)
                    Text(intent.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(isSelected ? lime : .white.opacity(0.3))
                    .accessibilityHidden(true)
            }
            .padding(17)
            .background(isSelected ? lime.opacity(0.09) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(isSelected ? lime.opacity(0.7) : .white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(intent.title + ". " + intent.subtitle)
        .accessibilityValue(isSelected ? L10n.string("Selected", "Выбрано") : L10n.string("Not selected", "Не выбрано"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding-intent-\(intent.rawValue)")
    }
}

/// Presentation-only callbacks keep the guide independent of discovery eligibility and ranking.
struct DiscoverFeatureGuide {
    let selectedIntents: Set<UserIntent>
    let progress: FeatureGuideProgress
    let allowsAutomaticPresentation: Bool
    let onAcknowledgeSwipe: () -> Void
    let onOpen: (UserIntent) -> Void
    let onDismiss: () -> Void
}

struct FeatureGuideCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @State private var visibleActionCount = 0
    @State private var revealTask: Task<Void, Never>?
    let selectedIntents: Set<UserIntent>
    let openedIntents: Set<UserIntent>
    let onOpen: (UserIntent) -> Void
    let onDismiss: () -> Void
    private let lime = Color(red: 0.77, green: 0.94, blue: 0.38)

    private var orderedIntents: [UserIntent] {
        UserIntent.allCases.filter { selectedIntents.contains($0) }
            + UserIntent.allCases.filter { !selectedIntents.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("YOUR NEXT STEP", "ЧТО ПОПРОБУЕМ?"))
                        .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(lime)
                    Text(L10n.string("More ways to play", "Возможности приложения"))
                        .font(.title2.weight(.bold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string("Open a section — we'll mark it as explored.", "Открой раздел — отметим его галочкой."))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Close app features", "Закрыть возможности приложения"))
                .accessibilityIdentifier("feature-guide-dismiss")
            }
            HStack(spacing: 8) {
                Image(systemName: openedIntents.count == UserIntent.allCases.count ? "checkmark.circle.fill" : "square.grid.2x2")
                    .accessibilityHidden(true)
                Text(L10n.string("Explored \(openedIntents.count) of 4", "Посмотрел \(openedIntents.count) из 4"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(lime)
            .accessibilityIdentifier("feature-guide-progress")

            VStack(spacing: 10) {
                ForEach(Array(orderedIntents.enumerated()), id: \.element.id) { index, intent in
                    action(intent, isVisible: reduceMotion || isVoiceOverEnabled || index < visibleActionCount)
                }
            }
        }
        .padding(22)
        .background(Color(red: 0.065, green: 0.085, blue: 0.065), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.09), lineWidth: 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: openedIntents)
        .onAppear { startReveal() }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private func startReveal() {
        revealTask?.cancel()
        guard !reduceMotion, !isVoiceOverEnabled else {
            visibleActionCount = orderedIntents.count
            return
        }
        visibleActionCount = 0
        let count = orderedIntents.count
        revealTask = Task { @MainActor in
            for index in 0..<count {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 80 : 140))
                guard !Task.isCancelled else { return }
                visibleActionCount = index + 1
                AppHaptics.impact(.light)
            }
        }
    }

    private func action(_ intent: UserIntent, isVisible: Bool) -> some View {
        let hasOpened = openedIntents.contains(intent)
        return Button {
            AppHaptics.selection()
            onOpen(intent)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: intent.systemImage)
                    .font(.title3).foregroundStyle(lime).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(intent.primaryActionTitle)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(intent.subtitle)
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: hasOpened ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(hasOpened ? lime : .white.opacity(0.25))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(hasOpened ? lime.opacity(0.065) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(hasOpened ? lime.opacity(0.25) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(intent.primaryActionTitle)
        .accessibilityValue(hasOpened ? L10n.string("Explored", "Посмотрел") : L10n.string("Not explored yet", "Ещё не открывал"))
        .accessibilityHint(intent.subtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("feature-guide-\(intent.rawValue)")
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible || reduceMotion || isVoiceOverEnabled ? 0 : 8)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isVisible)
    }
}
