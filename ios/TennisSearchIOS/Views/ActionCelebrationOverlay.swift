import SwiftUI

/// Smaller moments than a match, each with its own short illustration in the same card:
/// a search going out, a photo report, a game marked played or not, a game edited, a
/// visit saved. Driven by elapsed time like `MatchMomentOverlay`, so it settles before the
/// caller's ~2 s auto-dismiss and shows only its last frame under Reduce Motion.
enum ActionCelebrationKind {
    case searchPublished(Sport)
    case photoReport
    case gamePlayed(Sport)
    case gameNotPlayed
    case gameUpdated(AppModel.GameConfirmation)
    case visitSaved(Sport, date: Date, withPhoto: Bool)

    /// When everything has come to rest and the timeline can pause.
    fileprivate var settle: Double {
        switch self {
        case .searchPublished: return 2.2
        case .photoReport: return 1.9
        case .gamePlayed: return 2.2
        case .gameNotPlayed: return 1.2
        case .gameUpdated: return 1.6
        case .visitSaved: return 1.6
        }
    }

    /// What the hand feels, on the beats the eye sees.
    fileprivate var cues: [(time: Double, play: () -> Void)] {
        switch self {
        case .searchPublished:
            let lit = ActionRadarStage.dots.map { ActionRadarStage.lightTime(radius: $0.radius) }.sorted()
            return [lit[0], lit[3], lit[6]].map { time in (time, { AppHaptics.impact(.soft) }) }
                + [(1.25, { AppHaptics.notification(.success) })]
        case .photoReport:
            return [
                (0.35, { AppHaptics.impact(.rigid) }),
                (0.45, { AppHaptics.impact(.light) }),
                (1.3, { AppHaptics.notification(.success) })
            ]
        case .gamePlayed(let sport):
            let style = MatchMomentStyle(sport: sport)
            let feel = style.beats.contacts.last(where: { $0.hitter != nil })?.feel ?? .medium
            let landing: () -> Void = style.beats.landingFeel == .gentle
                ? { AppHaptics.notification(.success) }
                : { AppHaptics.successCelebration() }
            return [
                (ActionPlayedStage.contacts[0], { AppHaptics.impact(feel) }),
                (ActionPlayedStage.contacts[1], { AppHaptics.impact(.light) }),
                (ActionPlayedStage.landing, landing)
            ]
        case .gameNotPlayed:
            return [(0.5, { AppHaptics.impact(.soft) })]
        case .gameUpdated:
            return [
                (0.45, { AppHaptics.impact(.light) }),
                (0.95, { AppHaptics.impact(.rigid) }),
                (1.0, { AppHaptics.notification(.success) })
            ]
        case .visitSaved(_, _, let withPhoto):
            return (withPhoto ? [(0.45, { AppHaptics.impact(.light) })] : [])
                + [(0.55, { AppHaptics.impact(.rigid) }), (0.95, { AppHaptics.notification(.success) })]
        }
    }
}

struct ActionCelebrationOverlay: View {
    let kind: ActionCelebrationKind
    let title: String
    let subtitle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var isSettled = false
    @State private var isRevealed = false
    @State private var cuesTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isSettled)) { context in
            card(at: isSettled ? 10 : context.date.timeIntervalSince(startDate))
        }
        .opacity(reduceMotion && !isRevealed ? 0 : 1)
        .allowsHitTesting(false)
        .onAppear(perform: start)
        .onDisappear { cuesTask?.cancel() }
    }

    private func card(at time: Double) -> some View {
        let appear = MatchMomentCurve.spring(time, response: 0.34, damping: 0.62)

        return ZStack {
            Color.black.opacity(0.24 * MatchMomentCurve.easeOut(time / 0.2))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                stage(at: time)
                    .frame(width: 240, height: 150)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .modifier(MatchMomentReveal(time: time, start: 0.22))

                    Text(subtitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .modifier(MatchMomentReveal(time: time, start: 0.3))
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.13, blue: 0.10).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(0.86 + 0.14 * appear)
            .opacity(MatchMomentCurve.easeOut(time / 0.18))
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func stage(at time: Double) -> some View {
        switch kind {
        case .searchPublished(let sport):
            ActionRadarStage(sport: sport, time: time)
        case .photoReport:
            ActionPhotoStage(time: time)
        case .gamePlayed(let sport):
            ActionPlayedStage(sport: sport, time: time)
        case .gameNotPlayed:
            ActionNotPlayedStage(time: time)
        case .gameUpdated(let game):
            ActionUpdatedStage(game: game, time: time)
        case .visitSaved(let sport, let date, let withPhoto):
            ActionVisitStage(sport: sport, date: date, withPhoto: withPhoto, time: time)
        }
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

        let cues = kind.cues.sorted { $0.time < $1.time } + [(time: kind.settle, play: { isSettled = true })]
        let startDate = startDate
        cuesTask = Task { @MainActor in
            for cue in cues {
                let delay = cue.time - Date().timeIntervalSince(startDate)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                cue.play()
            }
        }
    }
}

// MARK: - Search published: a radar pulse finds nearby players

private struct ActionRadarStage: View {
    static let dots: [(angle: Double, radius: CGFloat)] = [
        (-2.4, 38), (-1.25, 62), (-0.35, 44), (0.5, 72), (1.35, 52), (2.2, 66), (3.0, 34)
    ]
    static let pulses = [0.3, 0.72, 1.14]
    static let pulseDuration = 0.9

    /// When the first pulse, easing out from 20 to 90 pt, reaches a dot.
    static func lightTime(radius: CGFloat) -> Double {
        let reached = Double((radius - 20) / 70)
        return pulses[0] + pulseDuration * (1 - pow(1 - reached, 1.0 / 3.0))
    }

    let sport: Sport
    let time: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.court.opacity(0.2 * MatchMomentCurve.easeOut(time / 0.3)))
                .frame(width: 180, height: 180)
            ForEach([45.0, 90.0], id: \.self) { radius in
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
            }

            ForEach(Self.pulses, id: \.self) { start in
                let progress = (time - start) / Self.pulseDuration
                if progress >= 0, progress < 1 {
                    Circle()
                        .stroke(MatchMomentPalette.ball.opacity(0.55 * (1 - progress)), lineWidth: 2)
                        .frame(width: 2 * (20 + 70 * CGFloat(MatchMomentCurve.easeOut(progress))))
                }
            }

            ForEach(0 ..< Self.dots.count, id: \.self) { index in
                let dot = Self.dots[index]
                let since = time - Self.lightTime(radius: dot.radius)
                let lit = MatchMomentCurve.spring(since, response: 0.35, damping: 0.5)
                Circle()
                    .fill(since >= 0 ? MatchMomentPalette.ball : Color.white.opacity(0.25 * MatchMomentCurve.easeOut(time / 0.3)))
                    .frame(width: 9, height: 9)
                    .shadow(color: MatchMomentPalette.ball.opacity(since >= 0 ? 0.7 : 0), radius: 6)
                    .scaleEffect(0.6 + 0.5 * lit)
                    .offset(x: cos(dot.angle) * dot.radius, y: sin(dot.angle) * dot.radius)
            }

            ZStack {
                Circle().fill(MatchMomentPalette.ball)
                SportIconView(sport: sport, color: AppTheme.ink, size: 20)
            }
            .frame(width: 40, height: 40)
            .scaleEffect(max(MatchMomentCurve.spring(time - 0.05, response: 0.42, damping: 0.55), 0.001))
        }
    }
}

// MARK: - Photo report: a print drops onto the stack, flashes and develops

private struct ActionPhotoStage: View {
    let time: Double

    var body: some View {
        let drop = MatchMomentCurve.spring(time, response: 0.5, damping: 0.62)
        let settle = MatchMomentCurve.spring(time - 1.35, response: 0.4, damping: 0.6)
        let develop = MatchMomentCurve.easeInOut((time - 0.5) / 0.8)
        let flashSince = time - 0.45
        let stackIn = MatchMomentCurve.easeOut((time - 0.1) / 0.25)

        return ZStack {
            ForEach([(-9.0, CGFloat(-26)), (7.0, CGFloat(24))], id: \.0) { tilt, x in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.35 * stackIn))
                    .frame(width: 92, height: 110)
                    .rotationEffect(.degrees(tilt))
                    .offset(x: x, y: 6)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 104, height: 124)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                ActionDevelopingPhoto(develop: develop)
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(.top, 7)
            }
            .rotationEffect(.degrees(-14 + 11 * drop + 5 * settle))
            .offset(y: -130 * CGFloat(1 - drop) + 4 * CGFloat(settle))

            if flashSince >= 0 {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.85 * exp(-10 * flashSince)))
                    .frame(width: 240, height: 150)
            }
        }
    }
}

/// A sunny court coming up out of the dark, like a print developing.
private struct ActionDevelopingPhoto: View {
    let develop: Double

    var body: some View {
        ZStack {
            Color(white: 0.08)
            ZStack {
                LinearGradient(colors: [Color(red: 0.55, green: 0.8, blue: 0.95), AppTheme.mint], startPoint: .top, endPoint: .center)
                Rectangle()
                    .fill(AppTheme.court)
                    .frame(height: 38)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 70))
                    path.addLine(to: CGPoint(x: 80, y: 70))
                    path.move(to: CGPoint(x: 45, y: 54))
                    path.addLine(to: CGPoint(x: 45, y: 90))
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                Circle()
                    .fill(MatchMomentPalette.ball)
                    .frame(width: 18, height: 18)
                    .offset(x: 24, y: -24)
            }
            .opacity(develop)
            .saturation(develop)
        }
        .blur(radius: 8 * (1 - develop))
    }
}

// MARK: - Game played: the ball drops into the ring and becomes its seal

private struct ActionPlayedStage: View {
    static let fall = 0.4
    static let contacts = [0.62, 0.86]
    static let landing = 1.0

    let sport: Sport
    let time: Double

    var body: some View {
        let style = MatchMomentStyle(sport: sport)
        let drawn = MatchMomentCurve.easeInOut((time - 0.05) / 0.5)
        let filled = MatchMomentCurve.easeOut((time - Self.landing) / 0.3)
        let check = MatchMomentCurve.spring(time - Self.landing - 0.05, response: 0.38, damping: 0.5)

        return ZStack {
            Circle()
                .fill(style.accent.opacity(0.14 * filled))
                .frame(width: 110, height: 110)
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(style.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 110, height: 110)

            ForEach(style.particles) { particle in
                let age = time - Self.landing - particle.delay
                if age >= 0, age < particle.lifetime {
                    RoundedRectangle(cornerRadius: particle.isRound ? particle.size.width / 2 : 2, style: .continuous)
                        .fill(particle.color)
                        .frame(width: particle.size.width, height: particle.size.height)
                        .rotationEffect(.degrees(particle.spin * age))
                        .opacity(particle.opacity(at: age))
                        .offset(x: particle.offset(at: age, from: .zero).x * 0.7, y: particle.offset(at: age, from: .zero).y * 0.7)
                }
            }

            if let flight = flight(style: style) {
                projectile(style: style, size: flight.size)
                    .rotationEffect(.degrees(flight.rotation))
                    .scaleEffect(x: flight.squash.width, y: flight.squash.height)
                    .shadow(color: style.accent.opacity(0.5), radius: 10)
                    .offset(y: flight.y)
            }

            ZStack {
                Circle().fill(MatchMomentPalette.ball)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 28, height: 28)
            .scaleEffect(max(check, 0.001))
            .offset(x: 40, y: 40)
        }
    }

    private struct Flight {
        let y: CGFloat
        let size: CGFloat
        let rotation: Double
        let squash: CGSize
    }

    /// Falls in, bounces twice on the ring's floor, then rises to the centre as the seal.
    private func flight(style: MatchMomentStyle) -> Flight? {
        guard time >= Self.fall else { return nil }
        let floor: CGFloat = 20
        let kind = style.rally?.projectile
        let small = kind?.flightSize ?? 34
        let seal = kind?.sealSize ?? 46
        let impact = Self.contacts.reduce(0.0) { $0 + max(0, MatchMomentCurve.bump(time - $1)) }
        let squash = CGSize(width: 1 + 0.2 * impact, height: 1 - 0.18 * impact)
        let spin = kind?.isShuttle == true ? 0 : min(time, Self.landing) * 600

        if time < Self.contacts[0] {
            let u = (time - Self.fall) / (Self.contacts[0] - Self.fall)
            return Flight(y: -110 + (floor + 110) * CGFloat(u * u), size: small, rotation: spin, squash: squash)
        }
        if time < Self.contacts[1] {
            let u = (time - Self.contacts[0]) / (Self.contacts[1] - Self.contacts[0])
            return Flight(y: floor - 36 * CGFloat(4 * u * (1 - u)), size: small, rotation: spin, squash: squash)
        }
        if time < Self.landing {
            let u = (time - Self.contacts[1]) / (Self.landing - Self.contacts[1])
            return Flight(y: floor - 12 * CGFloat(4 * u * (1 - u)), size: small, rotation: spin, squash: squash)
        }
        let grow = CGFloat(MatchMomentCurve.spring(time - Self.landing, response: 0.4, damping: 0.6))
        return Flight(y: floor * (1 - grow), size: small + (seal - small) * grow, rotation: spin, squash: squash)
    }

    @ViewBuilder
    private func projectile(style: MatchMomentStyle, size: CGFloat) -> some View {
        if let kind = style.rally?.projectile {
            MatchMomentProjectileView(kind: kind, size: size)
        } else {
            ZStack {
                Circle().fill(MatchMomentPalette.ball)
                SportIconView(sport: sport, color: AppTheme.ink, size: size * 0.52)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Game not played: the day is quietly crossed out

private struct ActionNotPlayedStage: View {
    let time: Double

    var body: some View {
        let drop = MatchMomentCurve.easeOut(time / 0.45)
        let strike = MatchMomentCurve.easeInOut((time - 0.5) / 0.4)
        let dim = MatchMomentCurve.easeOut((time - 0.9) / 0.3)

        return ZStack {
            VStack(spacing: 0) {
                ZStack {
                    AppTheme.clay
                    HStack(spacing: 34) {
                        ForEach(0 ..< 2, id: \.self) { _ in
                            Capsule().fill(Color.white.opacity(0.85)).frame(width: 5, height: 14)
                        }
                    }
                }
                .frame(height: 28)
                Text(String(Calendar.current.component(.day, from: Date())))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 100, height: 110)
            .background(AppTheme.creamLight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Path { path in
                path.move(to: CGPoint(x: 18, y: 44))
                path.addLine(to: CGPoint(x: 82, y: 100))
            }
            .trim(from: 0, to: strike)
            .stroke(AppTheme.mutedInk.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 100, height: 110)
        }
        .saturation(1 - 0.5 * dim)
        .opacity((0.3 + 0.7 * drop) * (1 - 0.2 * dim))
        .offset(y: -24 * CGFloat(1 - drop))
    }
}

// MARK: - Game updated: the ticket flips over to the new plan and gets stamped

private struct ActionUpdatedStage: View {
    static let ticket = CGSize(width: 330, height: 214)

    let game: AppModel.GameConfirmation
    let time: Double

    var body: some View {
        let angle = 180 * MatchMomentCurve.easeInOut((time - 0.15) / 0.6)
        let slamSince = time - 0.95
        let stampScale: Double = slamSince < 0
            ? 1.9 - 0.9 * pow(MatchMomentCurve.clamp((time - 0.79) / 0.16), 2)
            : 1 - 0.06 * MatchMomentCurve.bump(slamSince)

        return ZStack(alignment: .topTrailing) {
            Group {
                if angle < 90 {
                    GameConfirmedTicketShape(notchY: GameConfirmedTicket.perforation)
                        .fill(AppTheme.creamLight.opacity(0.85))
                        .overlay(
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach([0.5, 0.8, 0.35], id: \.self) { width in
                                    Capsule().fill(AppTheme.ink.opacity(0.12)).frame(width: Self.ticket.width * width, height: 14)
                                }
                            }
                            .padding(22),
                            alignment: .topLeading
                        )
                        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                } else {
                    GameConfirmedTicket(confirmation: game, time: 10, size: Self.ticket)
                        .rotation3DEffect(.degrees(angle - 180), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                }
            }
            .frame(width: Self.ticket.width, height: Self.ticket.height)

            GameConfirmedStamp(label: L10n.string("Sent", "Отправлено"))
                .scaleEffect(stampScale)
                .opacity(MatchMomentCurve.clamp((time - 0.79) / 0.05))
                .offset(x: -10, y: -18)
        }
        .scaleEffect(0.66)
    }
}

// MARK: - Visit saved: the day fills in on the week, with its photo if there is one

private struct ActionVisitStage: View {
    let sport: Sport
    let date: Date
    let withPhoto: Bool
    let time: Double

    private var dayIndex: Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7
    }

    private var letters: [String] {
        L10n.string("M T W T F S S", "П В С Ч П С В").split(separator: " ").map(String.init)
    }

    var body: some View {
        let fill = MatchMomentCurve.spring(time - 0.55, response: 0.38, damping: 0.5)
        let tick = MatchMomentCurve.easeInOut((time - 0.6) / 0.3)
        let badge = MatchMomentCurve.spring(time - 0.95, response: 0.4, damping: 0.55)
        let ringProgress = (time - 0.55) / 0.7
        let dayX = CGFloat(dayIndex - 3) * 32

        return ZStack {
            HStack(spacing: 6) {
                ForEach(0 ..< 7, id: \.self) { index in
                    let appear = MatchMomentCurve.spring(time - 0.04 * Double(index), response: 0.4, damping: 0.7)
                    let isDay = index == dayIndex
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(isDay ? 0.5 : 0.18), lineWidth: 1.5)
                            if isDay {
                                Circle()
                                    .fill(MatchMomentPalette.ball)
                                    .scaleEffect(max(fill, 0.001))
                                Path { path in
                                    path.move(to: CGPoint(x: 8, y: 13.5))
                                    path.addLine(to: CGPoint(x: 11.5, y: 17))
                                    path.addLine(to: CGPoint(x: 18.5, y: 9))
                                }
                                .trim(from: 0, to: tick)
                                .stroke(AppTheme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(letters[index])
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(isDay ? 0.9 : 0.45))
                    }
                    .scaleEffect(max(appear, 0.001))
                }
            }
            .offset(y: 16)

            if ringProgress >= 0, ringProgress < 1 {
                Circle()
                    .stroke(MatchMomentPalette.ball.opacity(0.6 * (1 - ringProgress)), lineWidth: 2)
                    .frame(width: 26 + 60 * CGFloat(MatchMomentCurve.easeOut(ringProgress)))
                    .offset(x: dayX, y: 3)
            }

            if withPhoto {
                let drop = MatchMomentCurve.spring(time - 0.2, response: 0.45, damping: 0.62)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 24, height: 28)
                    .overlay(
                        ActionDevelopingPhoto(develop: 1)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .padding(.top, 2),
                        alignment: .top
                    )
                    .rotationEffect(.degrees(12))
                    .opacity(MatchMomentCurve.clamp((time - 0.2) / 0.1))
                    .offset(x: dayX + 14, y: -14 - 80 * CGFloat(1 - drop))
            }

            ZStack {
                Circle().stroke(MatchMomentPalette.ball, lineWidth: 2)
                SportIconView(sport: sport, color: MatchMomentPalette.ball, size: 18)
            }
            .frame(width: 36, height: 36)
            .scaleEffect(max(badge, 0.001))
            .offset(x: dayX, y: -40)
        }
    }
}
