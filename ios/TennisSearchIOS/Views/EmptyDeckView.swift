import SwiftUI
import UIKit

/// The next useful step after the final player card. Navigation stays with the host.
struct EmptyDeckView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAppeared = false
    @State private var isMounted = false
    @State private var isHeroVisible = false
    @State private var selectedPage = 0
    @State private var isRotationPaused = false

    let city: String?
    let preferredSports: [Sport]
    let sections: [EmptyDeckSection]
    let invite: InviteSummary?
    let hasActiveSearch: Bool
    let isLoading: Bool
    let hasLoaded: Bool
    let loadFailed: Bool
    let onCreateSearch: () -> Void
    let onManageSearches: () -> Void
    let onOpenCourt: (EmptyDeckCourt, Sport) -> Void
    let onOpenClubs: (Sport) -> Void
    let onRetry: () -> Void

    private var visibleSections: [EmptyDeckSection] {
        sections.filter { !$0.courts.isEmpty }
    }

    private var trainingSport: Sport? {
        emptyDeckTrainingSport(preferredSports: preferredSports, sections: sections)
    }

    private var canAutoRotate: Bool {
        emptyDeckShouldAutoRotate(
            hasTraining: trainingSport != nil,
            isVisible: isMounted && isHeroVisible,
            sceneIsActive: scenePhase == .active,
            isPaused: isRotationPaused,
            reduceMotion: reduceMotion,
            voiceOverEnabled: voiceOverEnabled
        )
    }

    private var pageAnimation: Animation? {
        reduceMotion || voiceOverEnabled ? nil : .easeInOut(duration: 0.4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero

            if !visibleSections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("Find your court", "Найдите свой корт"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n.string("Explore clubs and their players", "Посмотрите клубы и тех, кто там играет"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    ForEach(visibleSections) { section in
                        EmptyDeckClubRow(
                            section: section,
                            onOpenCourt: { court in
                                pauseRotation()
                                onOpenCourt(court, section.sport)
                            },
                            onOpenClubs: {
                                pauseRotation()
                                onOpenClubs(section.sport)
                            }
                        )
                    }
                }
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(AppTheme.mint)
                    Text(L10n.string("Loading clubs and invitation…", "Загружаем клубы и приглашение…"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if loadFailed {
                supplementaryError
            } else if hasLoaded && visibleSections.isEmpty {
                Label(
                    L10n.string("No clubs in this selection yet. You can create a search without a club.", "В этой подборке пока нет клубов. Поиск можно создать без клуба."),
                    systemImage: "mappin.and.ellipse"
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            }

            if let invite {
                EmptyDeckInviteCard(invite: invite, city: city, onInteraction: pauseRotation)
            }
        }
        .opacity(hasAppeared || reduceMotion ? 1 : 0)
        .onAppear {
            isMounted = true
            withAnimation(pageAnimation) { hasAppeared = true }
        }
        .onDisappear { isMounted = false }
        .onChange(of: trainingSport) { _ in selectedPage = 0 }
        .onChange(of: reduceMotion) { enabled in
            if enabled { pauseRotation() }
        }
        .onChange(of: voiceOverEnabled) { enabled in
            if enabled { pauseRotation() }
        }
        .task(id: canAutoRotate) {
            guard canAutoRotate else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard !Task.isCancelled, canAutoRotate else { return }
                withAnimation(pageAnimation) { selectedPage = selectedPage == 0 ? 1 : 0 }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            heroHeader

            // Both pages participate in sizing. Changing page cannot move the clubs.
            ZStack(alignment: .topLeading) {
                searchPage
                    .opacity(selectedPage == 0 ? 1 : 0)
                    .offset(x: selectedPage == 0 || pageAnimation == nil ? 0 : -12)
                    .allowsHitTesting(selectedPage == 0)
                    .accessibilityHidden(selectedPage != 0)
                if let sport = trainingSport {
                    trainingPage(sport: sport)
                        .opacity(selectedPage == 1 ? 1 : 0)
                        .offset(x: selectedPage == 1 || pageAnimation == nil ? 0 : 12)
                        .allowsHitTesting(selectedPage == 1)
                        .accessibilityHidden(selectedPage != 1)
                }
            }
            .clipped()
            .simultaneousGesture(TapGesture().onEnded { pauseRotation() })
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.27, blue: 0.21), Color(red: 0.045, green: 0.13, blue: 0.105)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateHeroVisibility(frame: proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { frame in
                        updateHeroVisibility(frame: frame)
                    }
            }
        }
        // Let the enclosing ScrollView own vertical drags. Any drag still pauses rotation.
        .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in pauseRotation() })
    }

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(spacing: 8) {
                EmptyDeckCourtIllustration()
                    .frame(width: 56, height: 40)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                ZStack(alignment: .leading) {
                    heroCaption(L10n.string("YOUR NEXT STEP", "СЛЕДУЮЩИЙ ШАГ"))
                        .opacity(selectedPage == 0 ? 1 : 0)
                        .accessibilityHidden(selectedPage != 0)
                    if let sport = trainingSport {
                        heroCaption(sport.title)
                            .opacity(selectedPage == 1 ? 1 : 0)
                            .accessibilityHidden(selectedPage != 1)
                    }
                }
            }
            .simultaneousGesture(TapGesture().onEnded { pauseRotation() })
            Spacer(minLength: 0)
            if trainingSport != nil {
                HStack(spacing: 0) {
                    pageButton(0)
                    pageButton(1)
                    Button {
                        isRotationPaused.toggle()
                    } label: {
                        Image(systemName: isRotationPaused || reduceMotion || voiceOverEnabled ? "play.fill" : "pause.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(EmptyDeckPressStyle())
                    .disabled(reduceMotion || voiceOverEnabled)
                    .accessibilityLabel(isRotationPaused
                                        ? L10n.string("Resume recommendations", "Включить смену рекомендаций")
                                        : L10n.string("Pause recommendations", "Остановить смену рекомендаций"))
                    .accessibilityHint(reduceMotion || voiceOverEnabled
                                       ? L10n.string("Automatic switching is off for accessibility", "Автосмена отключена для универсального доступа")
                                       : L10n.string("Changes every eight seconds", "Смена каждые восемь секунд"))
                }
            }
        }
        .frame(minHeight: trainingSport == nil ? 24 : 44)
    }

    private func heroCaption(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(EmptyDeckPalette.lime)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pageButton(_ page: Int) -> some View {
        Button {
            pauseRotation()
            withAnimation(pageAnimation) { selectedPage = page }
        } label: {
            Capsule()
                .fill(selectedPage == page ? EmptyDeckPalette.lime : .white.opacity(0.3))
                .frame(width: selectedPage == page ? 18 : 6, height: 6)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(EmptyDeckPressStyle(onPress: pauseRotation))
        .accessibilityLabel(page == 0
                            ? L10n.string("Recommendation 1 of 2: search", "Рекомендация 1 из 2: поиск")
                            : L10n.string("Recommendation 2 of 2: training", "Рекомендация 2 из 2: тренировка"))
        .accessibilityAddTraits(selectedPage == page ? [.isSelected] : [])
    }

    private var searchPage: some View {
        recommendationPage(
            title: hasActiveSearch
                ? L10n.string("Your search is active", "Ваш поиск активен")
                : L10n.string("Keep the game going", "Игра продолжается"),
            subtitle: hasActiveSearch
                ? L10n.string("Check responses or update your plans for a game.", "Посмотрите отклики или обновите планы на игру.")
                : L10n.string("Create a search so other players can find you and suggest a game.", "Оставьте поиск — другие игроки смогут найти вас и предложить игру."),
            buttonTitle: hasActiveSearch ? L10n.string("My searches", "Мои поиски") : L10n.string("Create a search", "Создать поиск"),
            buttonIcon: hasActiveSearch ? "text.bubble.fill" : "plus.circle.fill"
        ) {
            pauseRotation()
            if hasActiveSearch { onManageSearches() } else { onCreateSearch() }
        }
    }

    private func trainingPage(sport: Sport) -> some View {
        recommendationPage(
            title: L10n.string("Individual training", "Индивидуальная тренировка"),
            subtitle: L10n.string("Choose a club and ask about training options.", "Выберите клуб и уточните условия занятий."),
            buttonTitle: L10n.string("Choose a club", "Выбрать клуб"),
            buttonIcon: "mappin.and.ellipse"
        ) {
            pauseRotation()
            onOpenClubs(sport)
        }
    }

    private func recommendationPage(title: String, subtitle: String, buttonTitle: String, buttonIcon: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: buttonIcon)
                    Text(buttonTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(EmptyDeckPalette.lime, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(EmptyDeckPressStyle(onPress: pauseRotation))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updateHeroVisibility(frame: CGRect) {
        isHeroVisible = emptyDeckHeroIsVisible(frame: frame, viewport: UIScreen.main.bounds)
    }

    private func pauseRotation() {
        isRotationPaused = true
    }

    private var supplementaryError: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Clubs and invitation couldn't load", "Не удалось загрузить клубы и приглашение"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Button(action: onRetry) {
                Label(L10n.string("Try again", "Попробовать снова"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EmptyDeckPalette.lime)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EmptyDeckPressStyle())
        }
    }
}

private enum EmptyDeckPalette {
    static let lime = Color(red: 0.83, green: 0.95, blue: 0.49)
    static let panel = Color(red: 0.075, green: 0.085, blue: 0.078)
}

/// Compact decorative court and ball, sized to the existing carousel header.
private struct EmptyDeckCourtIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.court)
                .frame(width: 44, height: 31)
                .overlay {
                    Canvas { context, size in
                        let court = CGRect(x: 5, y: 4, width: size.width - 10, height: size.height - 8)
                        var lines = Path()
                        lines.addRect(court)
                        lines.move(to: CGPoint(x: court.midX, y: court.minY))
                        lines.addLine(to: CGPoint(x: court.midX, y: court.maxY))
                        for y in [court.minY + 5, court.maxY - 5] {
                            lines.move(to: CGPoint(x: court.minX, y: y))
                            lines.addLine(to: CGPoint(x: court.maxX, y: y))
                        }
                        context.stroke(lines, with: .color(.white.opacity(0.8)), lineWidth: 0.8)
                    }
                }
                .rotationEffect(.degrees(-12))
                .offset(x: -3, y: -2)
            Image(systemName: "tennisball.fill")
                .font(.system(size: 21))
                .foregroundStyle(EmptyDeckPalette.lime)
                .rotationEffect(.degrees(24))
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                .offset(x: 16, y: 9)
        }
    }
}

/// Selection follows the user's sport order; club payload order cannot change it.
func emptyDeckTrainingSport(preferredSports: [Sport], sections: [EmptyDeckSection]) -> Sport? {
    let supported: Set<Sport> = [.tennis, .tableTennis, .padel, .squash, .badminton, .fitness, .boxing, .yoga]
    return preferredSports.first { sport in
        supported.contains(sport) && sections.contains { $0.sport == sport && !$0.courts.isEmpty }
    }
}

func emptyDeckShouldAutoRotate(hasTraining: Bool, isVisible: Bool, sceneIsActive: Bool, isPaused: Bool, reduceMotion: Bool, voiceOverEnabled: Bool) -> Bool {
    hasTraining && isVisible && sceneIsActive && !isPaused && !reduceMotion && !voiceOverEnabled
}

func emptyDeckHeroIsVisible(frame: CGRect, viewport: CGRect) -> Bool {
    guard frame.width > 0, frame.height > 0 else { return false }
    let visible = frame.intersection(viewport)
    return !visible.isNull && visible.height >= frame.height * 0.75 && visible.width >= frame.width * 0.75
}

struct EmptyDeckClubRow: View {
    let section: EmptyDeckSection
    let onOpenCourt: (EmptyDeckCourt) -> Void
    let onOpenClubs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(section.sport.title, systemImage: section.sport.appSystemIconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onOpenClubs) {
                    HStack(spacing: 5) {
                        Text(L10n.string("All clubs", "Все клубы"))
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EmptyDeckPalette.lime)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(EmptyDeckPressStyle())
                .accessibilityLabel(L10n.string("All clubs: \(section.sport.title)", "Все клубы: \(section.sport.title)"))
            }

            if let nearby = section.courts.compactMap(\.nearby).first {
                NearbyResultsBanner(nearby: nearby, title: L10n.string("Clubs around your city", "Клубы рядом с вашим городом"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(section.courts) { court in
                        Button { onOpenCourt(court) } label: {
                            EmptyDeckClubTile(court: court, sport: section.sport)
                        }
                        .buttonStyle(EmptyDeckPressStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(L10n.string("Open club", "Открыть клуб"))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct EmptyDeckClubTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let court: EmptyDeckCourt
    let sport: Sport

    private var activity: String {
        if court.activeSearchesCount > 0 {
            return L10n.string("Active searches: \(court.activeSearchesCount)", "Активных поисков: \(court.activeSearchesCount)")
        }
        if court.memberCount > 0 {
            return L10n.string("Club players: \(court.memberCount)", "Игроков клуба: \(court.memberCount)")
        }
        return L10n.string("Explore the club", "Познакомиться с клубом")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                Image(systemName: sport.appSystemIconName)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(AppTheme.court)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.court.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(court.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 44, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
                if let city = court.city, court.nearby != nil {
                    Text(city).font(.caption).foregroundStyle(AppTheme.ink.opacity(0.7))
                }
                if let distance = court.nearby?.distanceLabel ?? court.distanceLabel, !distance.isEmpty {
                    Label(distance, systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink.opacity(0.65))
                }
            }
            Rectangle().fill(AppTheme.ink.opacity(0.09)).frame(height: 1)
            Label(activity, systemImage: court.activeSearchesCount > 0 ? "person.2.fill" : "sportscourt")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.court)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 280 : 238, alignment: .leading)
        .background(AppTheme.creamLight, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
    }
}

private struct EmptyDeckInviteCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let invite: InviteSummary
    let city: String?
    let onInteraction: () -> Void
    @State private var linkCopied = false

    private var shareMessage: String {
        let intro: String
        if let city, !city.isEmpty {
            intro = L10n.string("I play in \(city). Join me:", "Играю в городе \(city). Присоединяйся:")
        } else {
            intro = L10n.string("Let's find time for a game. Join me:", "Давайте найдём время для игры. Присоединяйся:")
        }
        return "\(intro) \(invite.url)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(EmptyDeckPalette.lime)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("Better together", "Со своими ещё лучше"))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(L10n.string("Invite someone you already play with. Your personal link is ready.", "Позовите тех, с кем уже играете. Ваша личная ссылка готова."))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { shareButton; copyButton }
            } else {
                HStack(spacing: 10) { shareButton; copyButton }
            }
        }
        .padding(20)
        .background(EmptyDeckPalette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
        .task(id: linkCopied) {
            guard linkCopied else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            linkCopied = false
        }
    }

    private var shareButton: some View {
        ShareLink(item: shareMessage) {
            Label(L10n.string("Invite a friend", "Позвать друга"), systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 14)
                .background(AppTheme.mint, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(EmptyDeckPressStyle())
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
    }

    private var copyButton: some View {
        Button {
            onInteraction()
            UIPasteboard.general.string = invite.url
            AppHaptics.selection()
            linkCopied = true
            UIAccessibility.post(notification: .announcement, argument: L10n.string("Link copied", "Ссылка скопирована"))
        } label: {
            Label(
                linkCopied ? L10n.string("Copied", "Скопировано") : L10n.string("Copy link", "Ссылка"),
                systemImage: linkCopied ? "checkmark" : "link"
            )
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(linkCopied ? EmptyDeckPalette.lime : .white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 14)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityLabel(linkCopied
                             ? L10n.string("Link copied", "Ссылка скопирована")
                             : L10n.string("Copy invitation link", "Скопировать ссылку-приглашение"))
        .buttonStyle(EmptyDeckPressStyle())
    }
}

private struct EmptyDeckPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onPress: (() -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed { onPress?() }
            }
    }
}

struct NearbyResultsBanner: View {
    let nearby: NearbyResult
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "location.magnifyingglass")
                .font(.subheadline.weight(.semibold))
            Text(nearby.areaLabel)
                .font(.caption)
            Text(L10n.string("Distances are measured in a straight line from the search location.", "Расстояния указаны по прямой от места поиска."))
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.85))
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.court.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
