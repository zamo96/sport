import SwiftUI

/// Что показать вместо колоды, когда игроков рядом нет. Клубы дают повод выйти
/// на корт сегодня, приглашение приводит нового игрока — далёких игроков здесь
/// намеренно нет: сыграть с ними нельзя, а свайп потрачен.
struct EmptyDeckView: View {
    @EnvironmentObject private var appModel: AppModel

    let city: String?
    let seenCount: Int
    let sections: [EmptyDeckSection]
    let invite: InviteSummary?

    private var isFirstInCity: Bool { seenCount == 0 }

    private var title: String {
        isFirstInCity
            ? L10n.string("You are the first one here", "Здесь вы первый")
            : L10n.string("You have seen everyone", "Вы посмотрели всех")
    }

    private var subtitle: String {
        let place = city ?? L10n.string("your city", "вашем городе")

        if isFirstInCity {
            return L10n.string(
                "No other players in \(place) yet. Invite the people you already play with.",
                "В городе \(place) пока нет других игроков. Позовите тех, с кем уже играете."
            )
        }

        return L10n.string(
            "There are \(seenCount) profiles in \(place) right now, and you went through all of them.",
            "В городе \(place) сейчас \(seenCount) анкет, и вы пролистали все. Появятся новые — напишем."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            leadCard

            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                ClubRow(section: section, driftDuration: 22 + Double(index) * 4)
            }
        }
    }

    /// Приговор и действие в одной карточке: так приглашение остаётся выше
    /// сгиба даже на маленьком экране, где два блока подряд не помещаются.
    private var leadCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

            if let invite {
                InviteStrip(invite: invite, city: city)
            }
        }
        .background(.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct InviteStrip: View {
    let invite: InviteSummary
    let city: String?

    @State private var showsLink = true

    private var shareMessage: String {
        let place = city ?? L10n.string("my city", "своём городе")
        let intro = L10n.string(
            "I play in \(place) and I am looking for partners. Join me:",
            "Играю в городе \(place), ищу партнёров. Присоединяйся:"
        )
        return "\(intro) \(invite.url)"
    }

    private var shortLink: String {
        invite.url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string("Invite whoever you already play with", "Позовите, с кем уже играете"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Ссылку никто не перепечатывает — она нужна на один взгляд,
                // чтобы стало понятно, чем делятся. Дальше место занимает зря.
                if showsLink {
                    Text(shortLink)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 6)

            ShareLink(item: shareMessage) {
                Text(L10n.string("Share", "Отправить"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.clay)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(AppTheme.clay)
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeInOut(duration: 0.45)) {
                showsLink = false
            }
        }
    }
}

/// Ряд клубов одного вида спорта. Медленно едет сам, пока его не тронули.
private struct ClubRow: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let section: EmptyDeckSection
    let driftDuration: Double

    @State private var driftOffset: CGFloat = 0
    /// Палец главнее: как только человек листает сам, движение больше не
    /// возвращаем — иначе оно спорит с ним.
    @State private var userTookOver = false

    private var driftDistance: CGFloat { -60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовки лежат прямо на чёрном фоне экрана, а не на карточке:
            // тёмно-зелёный из палитры здесь нечитаем.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: section.sport.appSystemIconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mint)
                Text(section.sport.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(L10n.string("All · \(section.total)", "Все · \(section.total)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mint)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(section.courts) { court in
                        Button {
                            appModel.pendingCourtID = court.id
                            appModel.navigate(to: .courts(sport: section.sport))
                        } label: {
                            ClubTile(court: court, sport: section.sport)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        appModel.navigate(to: .courts(sport: section.sport))
                    } label: {
                        AllCourtsTile()
                    }
                    .buttonStyle(.plain)
                }
                .offset(x: driftOffset)
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
                    stopDrift()
                })
            }
            .scrollDisabled(false)
        }
        .task {
            guard !reduceMotion, !userTookOver, section.courts.count > 2 else {
                return
            }

            withAnimation(.linear(duration: driftDuration).repeatForever(autoreverses: true)) {
                driftOffset = driftDistance
            }
        }
    }

    private func stopDrift() {
        guard !userTookOver else {
            return
        }

        userTookOver = true
        withAnimation(.easeOut(duration: 0.25)) {
            driftOffset = 0
        }
    }
}

private struct ClubTile: View {
    let court: EmptyDeckCourt
    let sport: Sport

    private var reason: String? {
        if court.activeSearchesCount > 0 {
            return L10n.string(
                "\(court.activeSearchesCount) looking for a game",
                "ищут игру · \(court.activeSearchesCount)"
            )
        }

        if court.memberCount > 0 {
            return L10n.string("\(court.memberCount) players from here", "\(court.memberCount) игроков отсюда")
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.mint)
                    Image(systemName: sport.appSystemIconName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.court)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(court.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    if let distance = court.distanceLabel {
                        Text(distance)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.ink.opacity(0.6))
                    }
                }
            }

            HStack(spacing: 6) {
                if court.searchers.isEmpty == false {
                    SearcherFaces(searchers: court.searchers)
                }
                if court.activeSearchesCount > 0 {
                    Circle()
                        .fill(Color(red: 63 / 255, green: 163 / 255, blue: 127 / 255))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 22, alignment: .leading)

            Text(reason ?? L10n.string("courts to rent", "корты в аренду"))
                .font(.caption2.weight(reason == nil ? .regular : .semibold))
                .foregroundStyle(reason == nil ? AppTheme.ink.opacity(0.55) : AppTheme.court)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: 168, alignment: .leading)
        .background(.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SearcherFaces: View {
    let searchers: [EmptyDeckSearcher]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(searchers) { searcher in
                ZStack {
                    Circle().fill(AppTheme.court)
                    Text(initials(for: searcher.name))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 21, height: 21)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }

    private func initials(for name: String?) -> String {
        guard let name, name.isEmpty == false else {
            return "?"
        }

        return name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

private struct AllCourtsTile: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
            Text(L10n.string("All courts", "Все корты"))
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(AppTheme.court)
        .frame(width: 92, height: 96)
        .background(.white.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
