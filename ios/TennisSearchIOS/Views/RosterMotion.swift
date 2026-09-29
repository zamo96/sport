import SwiftUI

/// Someone on a group game's roster, as the roster views draw them.
struct RosterPerson: Identifiable, Equatable {
    let id: String
    let name: String
    let imagePath: String?

    init(id: String, name: String, imagePath: String?) {
        self.id = id
        self.name = name
        self.imagePath = imagePath
    }

    init(_ user: DiscoverUser) {
        self.init(id: user.id, name: user.displayName, imagePath: user.profileHeroImagePath)
    }

    init(_ profile: UserProfile) {
        self.init(id: profile.id, name: profile.displayName, imagePath: profile.profileHeroImagePath)
    }
}

/// A group game's roster that has just filled, ready for its moment.
struct RosterCompletion: Identifiable {
    let id = UUID()
    let searchId: String
    let sport: Sport
    /// The organiser first, then the approved players in the order they joined.
    let people: [RosterPerson]

    /// Present only when an approval is what filled a group roster: one-player searches
    /// become a game straight away and have their own moment.
    static func afterApproval(of search: GameSearch, approvedBefore: Int, host: UserProfile?) -> RosterCompletion? {
        let needed = search.playersNeeded
        let approved = search.responses.filter { $0.status == "approved" }
        guard needed > 1, approvedBefore < needed, approved.count >= needed, let host else { return nil }
        return RosterCompletion(
            searchId: search.id,
            sport: search.sport,
            people: [RosterPerson(host)] + approved.map { RosterPerson($0.responderUser) }
        )
    }
}

// MARK: - Roster strip

/// Who is in so far: the organiser, then one slot per player needed. A slot fills with a
/// pop and a ring as that player is approved, and the bar underneath tracks the count.
struct RosterSlotsStrip: View {
    let host: RosterPerson
    let players: [RosterPerson]
    let capacity: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filled: Int { min(players.count, capacity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("Roster", "Состав"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(L10n.string("\(filled) of \(capacity)", "\(filled) из \(capacity)"))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(filled >= capacity ? AppTheme.court : AppTheme.mutedInk)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    RosterAvatar(person: host, isHost: true, size: 48)
                    ForEach(0 ..< capacity, id: \.self) { index in
                        ZStack {
                            RosterEmptySlot(size: 48)
                            if index < players.count {
                                RosterAvatar(person: players[index], isHost: false, size: 48)
                                    .id(players[index].id)
                                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.mint)
                    Capsule()
                        .fill(AppTheme.court)
                        .frame(width: proxy.size.width * CGFloat(filled) / CGFloat(max(capacity, 1)))
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .animation(AppMotion.animation(.spring(response: 0.42, dampingFraction: 0.58), reduceMotion: reduceMotion), value: players.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("Roster: \(filled) of \(capacity)", "Состав: \(filled) из \(capacity)"))
    }
}

/// A roster member's photo; the organiser wears a star. It rings once as it arrives.
private struct RosterAvatar: View {
    let person: RosterPerson
    let isHost: Bool
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasArrived = false

    var body: some View {
        RemoteAvatarView(name: person.name, path: person.imagePath, size: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                    .stroke(AppTheme.court, lineWidth: 2)
                    .scaleEffect(hasArrived ? 1.35 : 1)
                    .opacity(hasArrived || reduceMotion ? 0 : 0.8)
            )
            .overlay(alignment: .topTrailing) {
                if isHost {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 18, height: 18)
                        .background(MatchMomentPalette.ball, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.6)) {
                    hasArrived = true
                }
            }
    }
}

private struct RosterEmptySlot: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
            .stroke(AppTheme.mutedInk.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.mutedInk.opacity(0.45))
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Roster complete moment

/// The last slot just filled: everyone flies in from the edges and takes a place around
/// the sport's badge, a ring closes through them, and they all lean in for the burst.
/// Time-driven like `MatchMomentOverlay`; a tap skips to the last frame.
struct RosterCompleteOverlay: View {
    let completion: RosterCompletion
    let onOpenRoster: (() -> Void)?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var isSettled = false
    @State private var isRevealed = false
    @State private var cuesTask: Task<Void, Never>?

    private var beats: RosterBeats { RosterBeats(count: completion.people.count) }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isSettled)) { context in
            scene(at: isSettled ? 10 : context.date.timeIntervalSince(startDate))
        }
        .opacity(reduceMotion && !isRevealed ? 0 : 1)
        .accessibilityAddTraits(.isModal)
        .onAppear(perform: start)
        .onDisappear { cuesTask?.cancel() }
    }

    private func scene(at time: Double) -> some View {
        let beats = beats
        let style = MatchMomentStyle(sport: completion.sport)

        return GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: max(proxy.size.height * 0.36, 220))
            let radius = min(118, proxy.size.width * 0.3)
            let avatarSize: CGFloat = completion.people.count > 6 ? 48 : 58

            ZStack {
                RadialGradient(
                    colors: [style.accent.opacity(time < beats.burst ? 0 : 0.1 + 0.24 * exp(-4 * (time - beats.burst))), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 230
                )
                .frame(width: 460, height: 460)
                .position(center)

                Circle()
                    .trim(from: 0, to: MatchMomentCurve.easeInOut((time - beats.ring) / 0.4))
                    .stroke(MatchMomentPalette.ball.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                ForEach(0 ..< 2, id: \.self) { index in
                    let progress = (time - beats.burst - 0.1 * Double(index)) / 0.75
                    if progress >= 0, progress < 1 {
                        Circle()
                            .stroke(style.accent.opacity(0.55 * (1 - progress)), lineWidth: 0.5 + 3 * (1 - progress))
                            .frame(width: 2 * (40 + 170 * CGFloat(MatchMomentCurve.easeOut(progress))))
                            .position(center)
                    }
                }

                ForEach(style.particles) { particle in
                    let age = time - beats.burst - particle.delay
                    if age >= 0, age < particle.lifetime {
                        RoundedRectangle(cornerRadius: particle.isRound ? particle.size.width / 2 : 2, style: .continuous)
                            .fill(particle.color)
                            .frame(width: particle.size.width, height: particle.size.height)
                            .rotationEffect(.degrees(particle.spin * age))
                            .opacity(particle.opacity(at: age))
                            .position(particle.offset(at: age, from: center))
                    }
                }

                ZStack {
                    Circle().fill(MatchMomentPalette.ball)
                    SportIconView(sport: completion.sport, color: AppTheme.ink, size: 30)
                }
                .frame(width: 66, height: 66)
                .scaleEffect(max(MatchMomentCurve.spring(time - 0.1, response: 0.42, damping: 0.55), 0.001) * (1 + 0.15 * MatchMomentCurve.bump(time - beats.burst)))
                .shadow(color: MatchMomentPalette.ball.opacity(0.5), radius: 14)
                .position(center)

                ForEach(Array(completion.people.enumerated()), id: \.element.id) { index, person in
                    let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(completion.people.count)
                    let arrived = MatchMomentCurve.spring(time - beats.arrival(index), response: 0.5, damping: 0.7)
                    let lean = 12 * MatchMomentCurve.bump(time - beats.burst)
                    let distance = 460 + (Double(radius) - 460) * arrived - lean
                    RosterAvatar(person: person, isHost: index == 0, size: avatarSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: avatarSize * 0.34, style: .continuous)
                                .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                        .scaleEffect(1 - 0.08 * MatchMomentCurve.bump(time - beats.landing(index)))
                        .position(x: center.x + CGFloat(cos(angle) * distance), y: center.y + CGFloat(sin(angle) * distance))
                }

                VStack(spacing: 0) {
                    copy(at: time, beats: beats)
                        .padding(.top, center.y + radius + avatarSize / 2 + 34)
                    Spacer(minLength: 16)
                    actions(at: time, beats: beats)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.09, blue: 0.07), Color(red: 0.06, green: 0.19, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(MatchMomentCurve.easeOut(time / 0.28))
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: skipToEnd)
    }

    private func copy(at time: Double, beats: RosterBeats) -> some View {
        VStack(spacing: 10) {
            Text(L10n.string("Roster complete", "Состав собран"))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(MatchMomentPalette.eyebrow)
                .modifier(MatchMomentReveal(time: time, start: beats.copy))

            Text(L10n.string("Everyone's in", "Все на месте"))
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)
                .modifier(MatchMomentReveal(time: time, start: beats.copy + 0.08))

            Text(L10n.string("Now agree on the time in the lobby.", "Осталось договориться о времени в лобби."))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .modifier(MatchMomentReveal(time: time, start: beats.copy + 0.16))
        }
        .accessibilityElement(children: .combine)
    }

    private func actions(at time: Double, beats: RosterBeats) -> some View {
        VStack(spacing: 6) {
            if let onOpenRoster {
                Button(action: onOpenRoster) {
                    Text(L10n.string("Open roster", "Перейти к составу"))
                }
                .buttonStyle(MatchMomentPrimaryButtonStyle())
                .modifier(MatchMomentReveal(time: time, start: beats.actions))
            }

            Button(action: onDismiss) {
                Text(onOpenRoster == nil ? L10n.string("Great", "Отлично") : L10n.string("Later", "Позже"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(MatchMomentReveal(time: time, start: beats.actions + 0.08))
        }
        .allowsHitTesting(time >= beats.actions)
    }

    private func start() {
        startDate = Date()
        guard !reduceMotion else {
            isSettled = true
            AppHaptics.notification(.success)
            withAnimation(.easeOut(duration: 0.25)) {
                isRevealed = true
            }
            return
        }

        let beats = beats
        let count = completion.people.count
        let landingFeel = MatchMomentStyle(sport: completion.sport).beats.landingFeel
        let felt = Set([0, count / 2, count - 1])
        var cues: [(time: Double, play: () -> Void)] = felt.sorted().map { index in
            (beats.landing(index), { AppHaptics.impact(.light) })
        }
        cues.append((beats.burst, landingFeel == .gentle ? { AppHaptics.notification(.success) } : { AppHaptics.successCelebration() }))
        cues.append((beats.settle, { isSettled = true }))

        let startDate = startDate
        cuesTask = Task { @MainActor in
            for cue in cues.sorted(by: { $0.time < $1.time }) {
                let delay = cue.time - Date().timeIntervalSince(startDate)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                cue.play()
            }
        }
    }

    private func skipToEnd() {
        guard !isSettled else { return }
        cuesTask?.cancel()
        if Date().timeIntervalSince(startDate) < beats.burst {
            AppHaptics.notification(.success)
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isSettled = true
        }
    }
}

/// Everyone arrives one after another, then the ring closes and they burst together.
private struct RosterBeats {
    let count: Int

    func arrival(_ index: Int) -> Double { 0.25 + 0.09 * Double(index) }
    /// The arrival spring has closed ~95% of the way by now.
    func landing(_ index: Int) -> Double { arrival(index) + 0.34 }
    var ring: Double { landing(max(count - 1, 0)) }
    var burst: Double { ring + 0.4 }
    var copy: Double { burst - 0.1 }
    var actions: Double { burst + 0.18 }
    var settle: Double { burst + 1.3 }
}
