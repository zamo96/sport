import SwiftUI

/// Что показать вместо колоды, когда игроков рядом нет. Клубы дают повод выйти
/// на корт сегодня, приглашение приводит нового игрока — далёких игроков здесь
/// намеренно нет: сыграть с ними нельзя, а свайп потрачен.
struct EmptyDeckView: View {
    @EnvironmentObject private var appModel: AppModel

    let city: String?
    let seenCount: Int
    let courts: [Court]
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
            "There are \(seenCount) profiles in \(place) right now, and you went through all of them. We will write when new ones show up.",
            "В городе \(place) сейчас \(seenCount) анкет, и вы пролистали все. Появятся новые — напишем."
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            // Когда играть не с кем совсем, приглашение — единственное, что
            // вообще меняет дело, поэтому оно идёт первым.
            if isFirstInCity {
                inviteCard
                courtsSection
            } else {
                courtsSection
                inviteCard
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.clay)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
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

    @ViewBuilder
    private var courtsSection: some View {
        if courts.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("Courts nearby", "Корты рядом"))
                    .font(.caption.weight(.semibold))
                    .kerning(1.1)
                    .foregroundStyle(AppTheme.ink.opacity(0.55))
                    .padding(.horizontal, 4)

                ForEach(courts.prefix(3)) { court in
                    Button {
                        appModel.pendingCourtID = court.id
                        appModel.navigate(to: .courts(sport: nil))
                    } label: {
                        CourtRow(court: court)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var inviteCard: some View {
        if let invite {
            InviteCard(invite: invite, city: city)
        }
    }
}

private struct CourtRow: View {
    let court: Court

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.mint)
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(AppTheme.court)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(court.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                if let metro = court.nearestMetroName ?? court.metroNames.first {
                    Text(metro)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let distance = court.distanceLabel {
                Text(distance)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.court)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct InviteCard: View {
    let invite: InviteSummary
    let city: String?

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
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Invite whoever you already play with", "Позовите, с кем уже играете"))
                .font(.headline)
                .foregroundStyle(.white)
            Text(L10n.string(
                "It is faster to find a partner when your own people are around.",
                "Быстрее найти партнёра, если рядом есть свои."
            ))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 10) {
                Text(shortLink)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                ShareLink(item: shareMessage) {
                    Text(L10n.string("Share", "Отправить"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.clay)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Пока по ссылке никто не переходил, счётчик показывать незачем —
            // нули только расхолаживают.
            if invite.visits > 0 {
                Text(L10n.string(
                    "Opened \(invite.visits) · joined \(invite.joined)",
                    "Переходов \(invite.visits) · дошли до анкеты \(invite.joined)"
                ))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.clay)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
