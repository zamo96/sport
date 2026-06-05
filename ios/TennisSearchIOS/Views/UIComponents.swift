import SwiftUI
import UIKit

enum AppTheme {
    static let ink = Color(red: 17 / 255, green: 38 / 255, blue: 29 / 255)
    static let cream = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    static let creamLight = Color(red: 255 / 255, green: 249 / 255, blue: 241 / 255)
    static let mint = Color(red: 229 / 255, green: 243 / 255, blue: 236 / 255)
    static let clay = Color(red: 201 / 255, green: 109 / 255, blue: 66 / 255)
    static let court = Color(red: 47 / 255, green: 122 / 255, blue: 101 / 255)
    static let line = Color.white.opacity(0.62)
    static let mutedInk = ink.opacity(0.62)
    static let softWhite = Color.white.opacity(0.88)

    static let pageBackground = LinearGradient(
        colors: [creamLight, cream, mint],
        startPoint: .top,
        endPoint: .bottom
    )
}

enum AppHaptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

struct AppScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            Circle()
                .fill(AppTheme.clay.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: 110, y: -260)

            Circle()
                .fill(AppTheme.court.opacity(0.14))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: -120, y: 260)

            content
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.62))
                }
            }
            content
        }
        .padding(18)
        .background(.white.opacity(0.86))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

struct PillLabel: View {
    let text: String
    var tint: Color = AppTheme.clay

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct SportLevelMiniChip: View {
    let sport: Sport
    let level: Int?

    private var resolvedLevel: Int {
        min(max(level ?? 5, 1), 10)
    }

    private var tone: String {
        switch resolvedLevel {
        case 1 ... 2: return "Новичок"
        case 3 ... 4: return "База"
        case 5 ... 6: return "Уверенный"
        case 7 ... 8: return "Сильный"
        default: return "Турнирный"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(sport.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 2) {
                ForEach(1 ... 5, id: \.self) { index in
                    Capsule()
                        .fill(index <= Int(ceil(Double(resolvedLevel) / 2.0)) ? AppTheme.court : AppTheme.ink.opacity(0.14))
                        .frame(width: 8, height: 5)
                }
            }

            Text(tone)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.62))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.cream, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
    }
}

struct AppInlineChip: View {
    let text: String
    let tint: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tint, in: Capsule())
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.clay)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.white.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.08).ignoresSafeArea()
            ProgressView()
                .tint(AppTheme.clay)
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

struct ServerRecoveryOverlay: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    @State private var pulse = false
    @State private var drift = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(AppTheme.clay.opacity(0.22))
                        .frame(width: pulse ? 110 : 88, height: pulse ? 110 : 88)
                        .blur(radius: 16)

                    Circle()
                        .fill(AppTheme.court.opacity(0.2))
                        .frame(width: drift ? 84 : 72, height: drift ? 84 : 72)
                        .blur(radius: 10)
                        .offset(x: drift ? 14 : -10, y: drift ? -10 : 12)

                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(22)
                        .background(.white.opacity(0.92), in: Circle())
                        .shadow(color: AppTheme.ink.opacity(0.12), radius: 16, x: 0, y: 10)
                }
                .frame(height: 118)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Button("Понятно", action: onDismiss)
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.78), lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(0.16), radius: 28, x: 0, y: 18)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

private enum KeyboardWarmupController {
    static var hasWarmed = false

    @MainActor
    static func warmIfNeeded() {
        guard !hasWarmed else {
            return
        }

        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                Task { @MainActor in
                    warmIfNeeded()
                }
            }
            return
        }

        hasWarmed = true

        let textField = UITextField(frame: CGRect(x: -240, y: -240, width: 1, height: 1))
        textField.alpha = 0.01
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.inputView = UIView(frame: .zero)

        window.addSubview(textField)
        textField.becomeFirstResponder()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            textField.resignFirstResponder()
            textField.removeFromSuperview()
        }
    }
}

struct KeyboardWarmupView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Task { @MainActor in
                KeyboardWarmupController.warmIfNeeded()
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct FieldShell<Content: View>: View {
    let title: String?
    let caption: String?
    let content: Content

    init(title: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.68))
                    .textCase(.uppercase)
                    .tracking(1.4)
            }

            content
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .foregroundStyle(AppTheme.ink)
                .tint(AppTheme.court)
                .environment(\.colorScheme, .light)
                .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.court.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: AppTheme.ink.opacity(0.06), radius: 14, x: 0, y: 8)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: tint.opacity(configuration.isPressed ? 0.12 : 0.2), radius: configuration.isPressed ? 10 : 18, x: 0, y: configuration.isPressed ? 6 : 12)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(configuration.isPressed ? 0.04 : 0.08), radius: configuration.isPressed ? 10 : 16, x: 0, y: configuration.isPressed ? 6 : 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct RegularOccurrenceDecisionBar: View {
    private enum DecisionAction {
        case confirm
        case decline

        var symbol: String {
            switch self {
            case .confirm:
                return "checkmark"
            case .decline:
                return "xmark"
            }
        }

        var tint: Color {
            switch self {
            case .confirm:
                return AppTheme.court
            case .decline:
                return .red.opacity(0.9)
            }
        }

        var surface: Color {
            switch self {
            case .confirm:
                return AppTheme.mint
            case .decline:
                return Color.red.opacity(0.12)
            }
        }
    }

    let isUpdating: Bool
    let hasResolvedDecision: Bool
    let onConfirm: () async -> Void
    let onDecline: () async -> Void

    @State private var pendingAction: DecisionAction?

    var body: some View {
        ZStack {
            if let pendingAction {
                HStack(spacing: 8) {
                    Image(systemName: pendingAction.symbol)
                        .font(.system(size: 14, weight: .bold))
                    Text(pendingAction == .confirm ? "Подтверждено" : "Отказ")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(pendingAction.tint)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    pendingAction.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 4).combined(with: .opacity),
                        removal: .scale(scale: 0.94).combined(with: .opacity)
                    )
                )
            } else {
                HStack(spacing: 8) {
                    decisionButton(for: .confirm)
                    decisionButton(for: .decline)
                }
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 6).combined(with: .opacity),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: pendingAction)
        .onChange(of: isUpdating) { updating in
            guard !updating, pendingAction != nil, !hasResolvedDecision else {
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: 520_000_000)
                await MainActor.run {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        pendingAction = nil
                    }
                }
            }
        }
    }

    private func decisionButton(for action: DecisionAction) -> some View {
        Button {
            Task {
                await perform(action)
            }
        } label: {
            Image(systemName: action.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(action.tint)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    action.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(action.tint.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isUpdating || pendingAction != nil)
        .accessibilityLabel(action == .confirm ? "Подтвердить слот" : "Отказаться от слота")
    }

    private func perform(_ action: DecisionAction) async {
        guard !isUpdating, pendingAction == nil else {
            return
        }

        switch action {
        case .confirm:
            AppHaptics.notification(.success)
            AppHaptics.impact(.light)
        case .decline:
            AppHaptics.notification(.warning)
            AppHaptics.impact(.rigid)
        }

        await MainActor.run {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                pendingAction = action
            }
        }

        try? await Task.sleep(nanoseconds: 220_000_000)

        switch action {
        case .confirm:
            await onConfirm()
        case .decline:
            await onDecline()
        }
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct RemoteAvatarView: View {
    let name: String
    let path: String?
    var size: CGFloat = 76

    var body: some View {
        Group {
            if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
    }

    private var initialsView: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.mint, AppTheme.softWhite],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(initials)
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(AppTheme.court)
        }
    }

    private var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        return parts.isEmpty ? "TS" : parts.joined()
    }

    private var resolvedURL: URL? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if path.contains("://") {
            return URL(string: path)
        }

        guard let base = AppConfig.apiBaseURL else {
            return nil
        }

        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(trimmed)
    }
}

struct AppSegmentedChoice<Item: Identifiable & Hashable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    private let titleProvider: (Item) -> String

    init(
        title: String,
        items: [Item],
        selection: Binding<Item>,
        titleForItem: KeyPath<Item, String>
    ) {
        self.title = title
        self.items = items
        _selection = selection
        self.titleProvider = { $0[keyPath: titleForItem] }
    }

    init(
        title: String,
        items: [Item],
        selection: Binding<Item>,
        titleProvider: @escaping (Item) -> String
    ) {
        self.title = title
        self.items = items
        _selection = selection
        self.titleProvider = titleProvider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .textCase(.uppercase)
                .tracking(1.4)

            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            selection = item
                        }
                        AppHaptics.selection()
                    } label: {
                        Text(titleProvider(item))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == item ? .white : AppTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(selection == item ? AppTheme.ink : .white.opacity(0.78))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(selection == item ? 0.08 : 0.82), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AppSportSelectionGrid: View {
    let title: String
    let sports: [Sport]
    @Binding var selectedSports: [Sport]
    @Binding var levels: [String: Int]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .textCase(.uppercase)
                .tracking(1.4)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sports) { sport in
                    AppSportSelectionCard(
                        sport: sport,
                        isSelected: selectedSports.contains(sport),
                        level: Binding(
                            get: { levels[sport.rawValue] ?? 5 },
                            set: { levels[sport.rawValue] = $0 }
                        )
                    ) {
                        AppHaptics.selection()
                        if selectedSports.contains(sport) {
                            selectedSports.removeAll { $0 == sport }
                            levels.removeValue(forKey: sport.rawValue)
                        } else {
                            selectedSports.append(sport)
                            levels[sport.rawValue] = levels[sport.rawValue] ?? 5
                        }
                    }
                }
            }
        }
    }
}

struct AppSingleSportSelectionGrid: View {
    let title: String
    let sports: [Sport]
    @Binding var selectedSport: Sport
    let levelProvider: (Sport) -> Int?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.68))
                .textCase(.uppercase)
                .tracking(1.4)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sports) { sport in
                    Button {
                        guard selectedSport != sport else {
                            return
                        }
                        selectedSport = sport
                        AppHaptics.selection()
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: sport.selectionIconName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 34, height: 34)
                                    .background(selectedSport == sport ? .white.opacity(0.16) : .white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .foregroundStyle(selectedSport == sport ? .white : AppTheme.court)

                                Text(sport.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(selectedSport == sport ? .white : AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                if let level = levelProvider(sport) {
                                    CompactSportLevelReadout(level: level, isSelected: selectedSport == sport)
                                } else {
                                    Text("Выбрать спорт")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selectedSport == sport ? .white.opacity(0.82) : AppTheme.mutedInk)
                                }

                                if selectedSport == sport {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 15, weight: .bold))
                                        Text("Выбрано")
                                            .font(.caption.weight(.bold))
                                    }
                                    .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    selectedSport == sport
                                        ? LinearGradient(colors: [AppTheme.court, AppTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [.white.opacity(0.92), AppTheme.creamLight.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(selectedSport == sport ? 0.16 : 0.74), lineWidth: 1)
                        )
                        .shadow(color: AppTheme.ink.opacity(selectedSport == sport ? 0.14 : 0.05), radius: selectedSport == sport ? 18 : 10, x: 0, y: selectedSport == sport ? 14 : 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CompactSportLevelReadout: View {
    let level: Int
    let isSelected: Bool

    private var tone: String {
        switch level {
        case 1 ... 2: return "Новичок"
        case 3 ... 4: return "База"
        case 5 ... 6: return "Уверенный"
        case 7 ... 8: return "Сильный"
        default: return "Турнирный"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(1 ... 5, id: \.self) { index in
                    Capsule()
                        .fill(index <= Int(ceil(Double(level) / 2.0)) ? (isSelected ? .white : AppTheme.court) : (isSelected ? .white.opacity(0.18) : AppTheme.ink.opacity(0.12)))
                        .frame(height: 6)
                }
            }

            Text(tone)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? .white.opacity(0.82) : AppTheme.mutedInk)
                .lineLimit(1)
        }
    }
}

struct AppSportSelectionCard: View {
    let sport: Sport
    let isSelected: Bool
    @Binding var level: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(isSelected ? .white.opacity(0.16) : .white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(isSelected ? .white : AppTheme.court)

                    Text(sport.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? .white : AppTheme.ink)
                        .multilineTextAlignment(.leading)
                }

                Text("Добавь в свои виды спорта")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.76) : AppTheme.mutedInk)

                if isSelected {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Уровень")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            Text(levelTone)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.14), in: Capsule())
                        }

                        HStack(spacing: 8) {
                            levelButton("-", action: { level = max(1, level - 1) })
                            HStack(spacing: 3) {
                                ForEach(1 ... 10, id: \.self) { index in
                                    Capsule()
                                        .fill(index <= level ? Color.white.opacity(0.9) : Color.white.opacity(0.16))
                                        .frame(height: 8)
                                }
                            }
                            levelButton("+", action: { level = min(10, level + 1) })
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [AppTheme.court, AppTheme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.white.opacity(0.92), AppTheme.creamLight.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.16 : 0.74), lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(isSelected ? 0.14 : 0.05), radius: isSelected ? 18 : 10, x: 0, y: isSelected ? 14 : 8)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isSelected)
    }

    private var levelTone: String {
        switch level {
        case 1 ... 2: return "Новичок"
        case 3 ... 4: return "База"
        case 5 ... 6: return "Уверенный"
        case 7 ... 8: return "Сильный"
        default: return "Турнирный"
        }
    }

    private var iconName: String {
        sport.selectionIconName
    }

    private func levelButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.headline.weight(.bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.14), in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

private extension Sport {
    var selectionIconName: String {
        switch self {
        case .tableTennis: return "circle.grid.cross"
        case .tennis: return "tennis.racket"
        case .padel: return "sportscourt"
        case .squash: return "figure.racquetball"
        case .badminton: return "bird"
        case .volleyball: return "volleyball"
        case .fitness: return "dumbbell"
        case .boxing: return "figure.boxing"
        case .yoga: return "figure.mind.and.body"
        case .football: return "soccerball"
        }
    }
}

struct AppAvailabilityWeekEditor: View {
    @Binding var availabilityByDay: [String: [String]]
    @State private var activeDay: DayOfWeek = .monday

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(DayOfWeek.allCases) { day in
                    let ranges = availabilityByDay[day.rawValue] ?? []
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            activeDay = day
                        }
                        AppHaptics.selection()
                    } label: {
                        VStack(spacing: 6) {
                            Text(day.shortTitle)
                                .font(.subheadline.weight(.bold))
                            HStack(spacing: 3) {
                                ForEach(TimeRange.allCases) { range in
                                    Circle()
                                        .fill(ranges.contains(range.rawValue) ? (activeDay == day ? .white : AppTheme.court) : (activeDay == day ? .white.opacity(0.24) : AppTheme.ink.opacity(0.12)))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .foregroundStyle(activeDay == day ? .white : AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(activeDay == day ? AppTheme.ink : AppTheme.cream, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(activeDay.title)
                        .font(.headline)
                    Spacer()
                    if !(availabilityByDay[activeDay.rawValue] ?? []).isEmpty {
                        Button("Очистить") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                                availabilityByDay[activeDay.rawValue] = []
                            }
                            AppHaptics.selection()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.clay)
                    }
                }

                HStack(spacing: 10) {
                    ForEach(TimeRange.allCases) { range in
                        AppAvailabilityWindowCard(
                            range: range,
                            isSelected: (availabilityByDay[activeDay.rawValue] ?? []).contains(range.rawValue)
                        ) {
                            toggle(range)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                presetButton("Будни утром") {
                    applyPreset(days: [.monday, .tuesday, .wednesday, .thursday, .friday], ranges: [.morning])
                }
                presetButton("Будни вечером") {
                    applyPreset(days: [.monday, .tuesday, .wednesday, .thursday, .friday], ranges: [.evening])
                }
                presetButton("Выходные") {
                    applyPreset(days: [.saturday, .sunday], ranges: TimeRange.allCases)
                }
            }
        }
    }

    private func toggle(_ range: TimeRange) {
        var current = availabilityByDay[activeDay.rawValue] ?? []
        if current.contains(range.rawValue) {
            current.removeAll { $0 == range.rawValue }
        } else {
            current.append(range.rawValue)
        }
        availabilityByDay[activeDay.rawValue] = current.uniqued()
        AppHaptics.selection()
    }

    private func applyPreset(days: [DayOfWeek], ranges: [TimeRange]) {
        let rawRanges = ranges.map(\.rawValue)
        for day in days {
            availabilityByDay[day.rawValue] = rawRanges
        }
        AppHaptics.selection()
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.cream, in: Capsule())
            .foregroundStyle(AppTheme.ink)
    }
}

struct AppAvailabilityWindowCard: View {
    let range: TimeRange
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.76), in: Circle())
                Text(range.title)
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.2 : 0.82), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? activeTextColor : inactiveTextColor)
            .shadow(color: shadowColor, radius: isSelected ? 16 : 8, x: 0, y: isSelected ? 12 : 6)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch range {
        case .morning: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }

    private var background: LinearGradient {
        switch range {
        case .morning:
            return LinearGradient(colors: isSelected ? [Color(red: 1, green: 0.95, blue: 0.84), Color(red: 1, green: 0.86, blue: 0.7)] : [Color(red: 1, green: 0.98, blue: 0.92), Color(red: 1, green: 0.93, blue: 0.84)], startPoint: .top, endPoint: .bottom)
        case .day:
            return LinearGradient(colors: isSelected ? [Color(red: 1, green: 0.97, blue: 0.8), Color(red: 1, green: 0.91, blue: 0.57)] : [Color(red: 1, green: 0.98, blue: 0.89), Color(red: 1, green: 0.95, blue: 0.78)], startPoint: .top, endPoint: .bottom)
        case .evening:
            return LinearGradient(colors: isSelected ? [Color(red: 0.89, green: 0.92, blue: 1), Color(red: 0.79, green: 0.84, blue: 1)] : [Color(red: 0.96, green: 0.97, blue: 1), Color(red: 0.91, green: 0.93, blue: 1)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var activeTextColor: Color {
        switch range {
        case .morning: return Color(red: 0.54, green: 0.29, blue: 0.13)
        case .day: return Color(red: 0.54, green: 0.35, blue: 0)
        case .evening: return Color(red: 0.2, green: 0.3, blue: 0.48)
        }
    }

    private var inactiveTextColor: Color {
        activeTextColor.opacity(0.8)
    }

    private var shadowColor: Color {
        activeTextColor.opacity(isSelected ? 0.15 : 0.06)
    }
}

struct RegularPairDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    let regularPairId: String

    @State private var regularPair: RegularPairSummary?
    @State private var courts: [Court] = []
    @State private var isLoading = false
    @State private var editingOccurrence: RegularPairOccurrence?
    @State private var updatingOccurrenceID: String?

    private var upcomingOccurrences: [RegularPairOccurrence] {
        guard let regularPair else {
            return []
        }

        return regularPair.occurrences
            .filter { ($0.scheduledAt.parsedISODateValue() ?? .distantPast) > Date() }
            .sorted { ($0.scheduledAt.parsedISODateValue() ?? .distantFuture) < ($1.scheduledAt.parsedISODateValue() ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let regularPair {
                            SectionCard(
                                title: regularPair.partnerUser.displayName,
                                subtitle: "Подтверждай слоты, меняй время и клуб, а потом переходи в чат."
                            ) {
                                HStack(alignment: .center, spacing: 12) {
                                    RemoteAvatarView(
                                        name: regularPair.partnerUser.displayName,
                                        path: regularPair.partnerUser.avatarUrl,
                                        size: 60
                                    )

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Регулярная пара")
                                            .font(.caption.weight(.semibold))
                                            .textCase(.uppercase)
                                            .tracking(1.6)
                                            .foregroundStyle(AppTheme.court)

                                        if let comment = regularPair.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                                           !comment.isEmpty {
                                            Text(comment)
                                                .font(.footnote)
                                                .foregroundStyle(AppTheme.ink.opacity(0.68))
                                                .lineLimit(3)
                                        }
                                    }

                                    Spacer()
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                                    ForEach(regularPair.preferredDays, id: \.self) { day in
                                        AppInlineChip(
                                            text: DayOfWeek(rawValue: day)?.title ?? day,
                                            tint: AppTheme.cream,
                                            foreground: AppTheme.ink
                                        )
                                    }

                                    ForEach(regularPair.preferredTimeRanges, id: \.self) { range in
                                        AppInlineChip(
                                            text: TimeRange(rawValue: range)?.title ?? range,
                                            tint: AppTheme.cream,
                                            foreground: AppTheme.ink
                                        )
                                    }

                                    if let courtName = regularPair.preferredCourt?.name {
                                        AppInlineChip(
                                            text: courtName,
                                            tint: AppTheme.mint,
                                            foreground: AppTheme.court
                                        )
                                    }
                                }

                                HStack(spacing: 10) {
                                    Button("Открыть чат") {
                                        appModel.pendingChatMatchID = regularPair.matchId
                                        appModel.navigate(to: .matches)
                                        dismiss()
                                    }
                                    .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))

                                    Button("Обновить") {
                                        Task {
                                            await loadRegularPair()
                                        }
                                    }
                                    .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.court))
                                }
                            }

                            if upcomingOccurrences.isEmpty {
                                SectionCard(title: "Ближайшие слоты", subtitle: "Новых предложений пока нет.") {
                                    EmptyStateView(
                                        title: "Слоты пока не появились",
                                        subtitle: "Когда расписание синхронизируется, здесь появятся ближайшие игры на 2 недели.",
                                        systemImage: "calendar.badge.exclamationmark"
                                    )
                                }
                            } else {
                                SectionCard(title: "Ближайшие слоты", subtitle: "Можно быстро подтвердить или поправить дату, время и клуб.") {
                                    VStack(spacing: 12) {
                                        ForEach(upcomingOccurrences) { occurrence in
                                            RegularPairOccurrenceCard(
                                                occurrence: occurrence,
                                                partnerName: regularPair.partnerUser.displayName,
                                                courts: courts,
                                                currentUserId: appModel.currentUser?.id,
                                                isUpdating: updatingOccurrenceID == occurrence.id,
                                                onConfirm: {
                                                    await updateOccurrence(
                                                        occurrenceId: occurrence.id,
                                                        status: "confirmed",
                                                        scheduledAt: nil,
                                                        proposedCourtId: nil
                                                    )
                                                },
                                                onDecline: {
                                                    await updateOccurrence(
                                                        occurrenceId: occurrence.id,
                                                        status: "declined",
                                                        scheduledAt: nil,
                                                        proposedCourtId: nil
                                                    )
                                                },
                                                onShiftDay: { delta in
                                                    guard let currentDate = occurrence.scheduledAt.parsedISODateValue(),
                                                          let nextDate = Calendar.current.date(byAdding: .day, value: delta, to: currentDate) else {
                                                        appModel.errorMessage = "Не удалось изменить дату слота."
                                                        return
                                                    }

                                                    guard nextDate > Date() else {
                                                        appModel.errorMessage = "Слот нельзя перенести в прошлое."
                                                        return
                                                    }

                                                    await updateOccurrence(
                                                        occurrenceId: occurrence.id,
                                                        status: nil,
                                                        scheduledAt: nextDate,
                                                        proposedCourtId: nil
                                                    )
                                                },
                                                onApplyTimeRange: { timeRange in
                                                    guard let currentDate = occurrence.scheduledAt.parsedISODateValue(),
                                                          let nextDate = date(byApplying: timeRange, to: currentDate) else {
                                                        appModel.errorMessage = "Не удалось изменить время слота."
                                                        return
                                                    }

                                                    guard nextDate > Date() else {
                                                        appModel.errorMessage = "Выбранное время уже прошло."
                                                        return
                                                    }

                                                    await updateOccurrence(
                                                        occurrenceId: occurrence.id,
                                                        status: nil,
                                                        scheduledAt: nextDate,
                                                        proposedCourtId: nil
                                                    )
                                                },
                                                onApplyCourt: { courtId in
                                                    await updateOccurrence(
                                                        occurrenceId: occurrence.id,
                                                        status: nil,
                                                        scheduledAt: nil,
                                                        proposedCourtId: courtId
                                                    )
                                                },
                                                onEdit: {
                                                    await loadCourtsIfNeeded()
                                                    editingOccurrence = occurrence
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        } else if isLoading {
                            LoadingOverlay()
                                .frame(height: 180)
                        } else {
                            SectionCard(title: "Регулярная пара", subtitle: "Не удалось загрузить данные.") {
                                Button("Повторить") {
                                    Task {
                                        await loadRegularPair()
                                    }
                                }
                                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.ink))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Регулярная пара")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadRegularPair()
                await loadCourtsIfNeeded()
            }
            .sheet(item: $editingOccurrence) { occurrence in
                RegularPairOccurrenceEditorSheet(
                    occurrence: occurrence,
                    courts: courts,
                    onSave: { date, courtId in
                        await updateOccurrence(
                            occurrenceId: occurrence.id,
                            status: nil,
                            scheduledAt: date,
                            proposedCourtId: courtId
                        )
                    }
                )
            }
        }
    }

    private func loadRegularPair() async {
        isLoading = true
        defer { isLoading = false }

        do {
            regularPair = try await appModel.repository.fetchRegularPair(regularPairId: regularPairId)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func loadCourtsIfNeeded() async {
        guard courts.isEmpty else {
            return
        }

        do {
            courts = try await appModel.repository.fetchCourts()
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func updateOccurrence(
        occurrenceId: String,
        status: String?,
        scheduledAt: Date?,
        proposedCourtId: String?
    ) async {
        updatingOccurrenceID = occurrenceId
        defer { updatingOccurrenceID = nil }

        do {
            _ = try await appModel.repository.updateRegularPairOccurrence(
                regularPairId: regularPairId,
                occurrenceId: occurrenceId,
                status: status,
                scheduledAt: scheduledAt,
                proposedCourtId: proposedCourtId
            )
            editingOccurrence = nil
            await loadRegularPair()
            await appModel.notificationManager.manualRefresh(repository: appModel.repository)
        } catch {
            guard !error.isCancellationLike else {
                return
            }
            appModel.present(error: error)
        }
    }

    private func date(byApplying timeRange: TimeRange, to baseDate: Date) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)

        switch timeRange {
        case .morning:
            components.hour = 9
        case .day:
            components.hour = 14
        case .evening:
            components.hour = 19
        }

        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)
    }
}

private struct RegularPairOccurrenceCard: View {
    let occurrence: RegularPairOccurrence
    let partnerName: String
    let courts: [Court]
    let currentUserId: String?
    let isUpdating: Bool
    let onConfirm: () async -> Void
    let onDecline: () async -> Void
    let onShiftDay: (Int) async -> Void
    let onApplyTimeRange: (TimeRange) async -> Void
    let onApplyCourt: (String?) async -> Void
    let onEdit: () async -> Void

    private var selectedTimeRange: TimeRange? {
        guard let date = occurrence.scheduledAt.parsedISODateValue() else {
            return nil
        }

        switch Calendar.current.component(.hour, from: date) {
        case 0..<12:
            return .morning
        case 12..<17:
            return .day
        default:
            return .evening
        }
    }

    private var selectedCourtName: String {
        occurrence.proposedCourt?.name ?? "Без клуба"
    }

    private var myConfirmationStatus: String? {
        guard let currentUserId else {
            return nil
        }

        return occurrence.confirmations.first(where: { $0.user.id == currentUserId })?.status.lowercased()
    }

    private var shouldShowDecisionBar: Bool {
        guard let myConfirmationStatus else {
            return true
        }

        return !["confirmed", "declined"].contains(myConfirmationStatus)
    }

    private var statusPresentation: (text: String, tint: Color, surface: Color) {
        let declinedUserId = occurrence.confirmations.first(where: { $0.status.lowercased() == "declined" })?.user.id

        switch occurrence.status.lowercased() {
        case "confirmed":
            return ("Подтверждено", AppTheme.court, AppTheme.mint)
        case "declined":
            if let currentUserId, declinedUserId == currentUserId {
                return ("Ты отказался", .red.opacity(0.9), Color.red.opacity(0.12))
            }
            return ("Партнер не может", .red.opacity(0.9), Color.red.opacity(0.12))
        case "canceled", "cancelled":
            return ("Отменено", AppTheme.ink.opacity(0.72), Color.gray.opacity(0.18))
        case "expired":
            return ("Уже прошло", AppTheme.ink.opacity(0.72), Color.gray.opacity(0.18))
        default:
            return ("Ждет подтверждения", AppTheme.ink, AppTheme.cream)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(occurrence.scheduledAt.formattedNumericDateTime())
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    if let courtName = occurrence.proposedCourt?.name {
                        Text(courtName)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink.opacity(0.62))
                    }
                }

                Spacer()

                AppInlineChip(
                    text: statusPresentation.text,
                    tint: statusPresentation.surface,
                    foreground: statusPresentation.tint
                )
            }

            if shouldShowDecisionBar || isUpdating {
                HStack(spacing: 8) {
                    RegularOccurrenceDecisionBar(
                        isUpdating: isUpdating,
                        hasResolvedDecision: !shouldShowDecisionBar,
                        onConfirm: onConfirm,
                        onDecline: onDecline
                    )
                }
            }

            HStack(spacing: 8) {
                confirmationStatusCard(title: "Ты", userId: currentUserId)
                confirmationStatusCard(title: partnerName, userId: occurrence.confirmations.first(where: { $0.user.id != currentUserId })?.user.id)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Быстро изменить")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))

                HStack(spacing: 8) {
                    quickActionChip(title: "-1 день") {
                        await onShiftDay(-1)
                    }

                    quickActionChip(title: "+1 день") {
                        await onShiftDay(1)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(TimeRange.allCases) { timeRange in
                        quickTimeRangeChip(for: timeRange)
                    }
                }

                courtMenu
            }

            Button {
                Task { await onEdit() }
            } label: {
                Text("Точная настройка")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))
            .disabled(isUpdating)
        }
        .padding(14)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func confirmationStatusCard(title: String, userId: String?) -> some View {
        let value = confirmationText(for: userId)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.52))
                .lineLimit(1)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(confirmationColor(for: userId))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func confirmationText(for userId: String?) -> String {
        guard let userId,
              let status = occurrence.confirmations.first(where: { $0.user.id == userId })?.status.lowercased() else {
            return "Ждет подтверждения"
        }

        switch status {
        case "confirmed":
            return "Подтверждено"
        case "declined":
            return "Не смогу"
        default:
            return "Ждет подтверждения"
        }
    }

    private func confirmationColor(for userId: String?) -> Color {
        guard let userId,
              let status = occurrence.confirmations.first(where: { $0.user.id == userId })?.status.lowercased() else {
            return AppTheme.ink.opacity(0.72)
        }

        switch status {
        case "confirmed":
            return AppTheme.court
        case "declined":
            return .red.opacity(0.9)
        default:
            return AppTheme.ink.opacity(0.72)
        }
    }

    private func quickActionChip(title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppTheme.creamLight, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
    }

    private func quickTimeRangeChip(for timeRange: TimeRange) -> some View {
        let isSelected = selectedTimeRange == timeRange

        return Button {
            Task { await onApplyTimeRange(timeRange) }
        } label: {
            Text(timeRange.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? .white : AppTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    (isSelected ? AppTheme.court : AppTheme.creamLight),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
    }

    private var courtMenu: some View {
        Menu {
            Button("Без клуба") {
                Task { await onApplyCourt(nil) }
            }

            if !courts.isEmpty {
                Divider()

                ForEach(courts) { court in
                    Button(court.name) {
                        Task { await onApplyCourt(court.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Клуб: \(selectedCourtName)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.56))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(isUpdating)
    }
}

struct RegularPairOccurrenceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let occurrence: RegularPairOccurrence
    let courts: [Court]
    let onSave: (Date, String?) async -> Void

    @State private var scheduledAt: Date
    @State private var proposedCourtId: String?
    @State private var courtQuery: String
    @State private var isSaving = false

    init(
        occurrence: RegularPairOccurrence,
        courts: [Court],
        onSave: @escaping (Date, String?) async -> Void
    ) {
        self.occurrence = occurrence
        self.courts = courts
        self.onSave = onSave
        _scheduledAt = State(initialValue: occurrence.scheduledAt.parsedISODateValue() ?? Date().addingTimeInterval(3600))
        _proposedCourtId = State(initialValue: occurrence.proposedCourt?.id)
        _courtQuery = State(initialValue: "")
    }

    private var filteredCourts: [Court] {
        let trimmedQuery = courtQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sortedCourts = courts.sorted { left, right in
            if left.id == proposedCourtId { return true }
            if right.id == proposedCourtId { return false }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        guard !trimmedQuery.isEmpty else {
            return Array(sortedCourts.prefix(18))
        }

        return sortedCourts.filter { court in
            searchableText(for: court).contains(trimmedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            AppScreen {
                VStack(alignment: .leading, spacing: 16) {
                    SectionCard(title: "Изменить слот", subtitle: "Новая дата или клуб сбросят старые подтверждения и попросят ответить заново.") {
                        FieldShell(title: "Дата и время") {
                            DatePicker(
                                "",
                                selection: $scheduledAt,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                        }

                        FieldShell(title: "Клуб") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(AppTheme.ink.opacity(0.48))
                                    TextField("Найти клуб, метро или район", text: $courtQuery)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                                ScrollView(showsIndicators: false) {
                                    VStack(spacing: 8) {
                                        courtOptionRow(
                                            title: "Без клуба",
                                            subtitle: "Оставить слот без привязки к центру",
                                            isSelected: proposedCourtId == nil
                                        ) {
                                            proposedCourtId = nil
                                        }

                                        if courts.isEmpty {
                                            Text("Список клубов загружается.")
                                                .font(.footnote)
                                                .foregroundStyle(AppTheme.ink.opacity(0.62))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 8)
                                        } else if filteredCourts.isEmpty {
                                            Text("Ничего не найдено. Попробуй название клуба, метро или район.")
                                                .font(.footnote)
                                                .foregroundStyle(AppTheme.ink.opacity(0.62))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 8)
                                        } else {
                                            ForEach(filteredCourts) { court in
                                                courtOptionRow(
                                                    title: court.name,
                                                    subtitle: courtSubtitle(for: court),
                                                    metaItems: [
                                                        court.nearestMetroName.map { ("tram.fill", $0) },
                                                        localizedDistrictName(court.district).map { ("map.fill", $0) },
                                                        (!court.address.isEmpty ? ("mappin.and.ellipse", court.address) : nil)
                                                    ].compactMap { $0 },
                                                    isSelected: proposedCourtId == court.id
                                                ) {
                                                    proposedCourtId = court.id
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 280)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Отмена") {
                            dismiss()
                        }
                        .buttonStyle(SecondaryActionButtonStyle(tint: AppTheme.ink))

                        Button {
                            Task {
                                isSaving = true
                                await onSave(scheduledAt, proposedCourtId)
                                isSaving = false
                                dismiss()
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            } else {
                                Text("Сохранить")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.court))
                        .disabled(isSaving)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationTitle("Настроить слот")
        }
    }

    private func searchableText(for court: Court) -> String {
        [
            court.name,
            court.address,
            court.nearestMetroName,
            localizedDistrictName(court.district)
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func courtSubtitle(for court: Court) -> String {
        [
            court.nearestMetroName,
            localizedDistrictName(court.district),
            court.address
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " • ")
    }

    private func courtOptionRow(
        title: String,
        subtitle: String,
        metaItems: [(icon: String, text: String)] = [],
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    if !metaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(metaItems.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 6) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppTheme.court)
                                    Text(item.text)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.ink.opacity(0.64))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.ink.opacity(0.64))
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.court)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                isSelected ? AppTheme.mint : AppTheme.creamLight,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppTheme.court.opacity(0.2) : Color.white.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
