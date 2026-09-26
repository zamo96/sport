import SwiftUI

/// Full-screen moment when a game is agreed: the game drops in as a ticket, and the
/// sport's ball, shuttle or ball flies in and slams the "confirmed" stamp onto it; sports
/// without one get the stamp slammed down on its own.
///
/// Driven by elapsed time like `MatchMomentOverlay`, and borrows its per-sport accents,
/// particles and landing feel, so a yoga booking lands as softly as a yoga match.
struct GameConfirmedOverlay: View {
    let confirmation: AppModel.GameConfirmation
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var isSettled = false
    @State private var isRevealed = false
    @State private var cuesTask: Task<Void, Never>?

    private var style: MatchMomentStyle { MatchMomentStyle(sport: confirmation.sport) }
    private var settle: Double { GameConfirmedBeat.impact + style.beats.rest }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isSettled)) { context in
            scene(at: isSettled ? GameConfirmedBeat.finalFrame : context.date.timeIntervalSince(startDate))
        }
        .opacity(reduceMotion && !isRevealed ? 0 : 1)
        .accessibilityAddTraits(.isModal)
        .onAppear(perform: start)
        .onDisappear { cuesTask?.cancel() }
    }

    private func scene(at time: Double) -> some View {
        let style = style

        return GeometryReader { proxy in
            let layout = GameConfirmedLayout(size: proxy.size)

            ZStack {
                glow(at: time, layout: layout, style: style)
                ticket(at: time, layout: layout)
                rings(at: time, layout: layout, style: style)
                particles(at: time, layout: layout, style: style)
                stamp(at: time, layout: layout, style: style)
                if let projectile = style.rally?.projectile {
                    flight(of: projectile, at: time, layout: layout)
                }

                VStack(spacing: 0) {
                    copy(style.copy, at: time)
                        .padding(.top, layout.copyTop)
                    Spacer(minLength: 16)
                    Button(action: onDone) {
                        Text(L10n.string("Great", "Отлично"))
                    }
                    .buttonStyle(MatchMomentPrimaryButtonStyle())
                    .modifier(MatchMomentReveal(time: time, start: GameConfirmedBeat.actions))
                    .allowsHitTesting(time >= GameConfirmedBeat.actions)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
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

    // MARK: Ticket

    /// Drops in from above with a little swing, then takes the stamp's hit.
    private func ticket(at time: Double, layout: GameConfirmedLayout) -> some View {
        let drop = MatchMomentCurve.spring(time - GameConfirmedBeat.drop, response: 0.6, damping: 0.7)
        let jolt = MatchMomentCurve.bump(time - GameConfirmedBeat.impact)
        let fallFrom = layout.center.y + layout.ticket.height

        return GameConfirmedTicket(confirmation: confirmation, time: time, size: layout.ticket)
            .scaleEffect(1 - 0.03 * jolt)
            .rotationEffect(.degrees(-9 + 7 * drop - 2 * jolt))
            .position(x: layout.center.x, y: layout.center.y - fallFrom * CGFloat(1 - drop) + CGFloat(8 * jolt))
            .accessibilityElement(children: .combine)
    }

    // MARK: Stamp

    /// Thrown sports: the stamp appears where the ball hits and springs down to size.
    /// Others: the stamp comes down from above the ticket and slams onto it.
    private func stamp(at time: Double, layout: GameConfirmedLayout, style: MatchMomentStyle) -> some View {
        let impact = GameConfirmedBeat.impact
        let since = time - impact
        let scale: Double
        let opacity: Double
        if style.rally != nil {
            scale = since < 0 ? 1.3 : 1.3 - 0.3 * MatchMomentCurve.spring(since, response: 0.3, damping: 0.6)
            opacity = MatchMomentCurve.clamp(since / 0.05)
        } else if since < 0 {
            let slam = MatchMomentCurve.clamp((time - (impact - 0.16)) / 0.16)
            scale = 1.9 - 0.9 * slam * slam
            opacity = MatchMomentCurve.clamp(slam * 3)
        } else {
            scale = 1 - 0.06 * MatchMomentCurve.bump(since)
            opacity = 1
        }

        return GameConfirmedStamp()
            .scaleEffect(scale)
            .opacity(opacity)
            .position(layout.stamp)
    }

    /// The sport's ball arcs in from below and hits the stamp spot.
    @ViewBuilder
    private func flight(of kind: MatchMomentProjectile, at time: Double, layout: GameConfirmedLayout) -> some View {
        let start = GameConfirmedBeat.launch
        let end = GameConfirmedBeat.impact
        if time >= start, time < end + 0.05 {
            let u = min((time - start) / (end - start), 1)
            let arc = CGFloat(4 * u * (1 - u))
            let from = layout.launch
            let to = layout.stamp
            let position = CGPoint(x: from.x + (to.x - from.x) * CGFloat(u), y: from.y + (to.y - from.y) * CGFloat(u) - 180 * arc)
            let dx = Double(to.x - from.x)
            let dy = Double(to.y - from.y) - 180 * (4 - 8 * u)
            let rotation = kind.isShuttle ? atan2(dy, dx) * 180 / .pi : time * 720

            MatchMomentProjectileView(kind: kind, size: kind.flightSize * (1 + 0.25 * arc))
                .rotationEffect(.degrees(rotation))
                .shadow(color: kind.accent.opacity(0.55), radius: 12)
                .opacity(1 - MatchMomentCurve.clamp((time - end) / 0.05))
                .position(position)
                .accessibilityHidden(true)
        }
    }

    // MARK: Burst

    private func glow(at time: Double, layout: GameConfirmedLayout, style: MatchMomentStyle) -> some View {
        let landed = time - GameConfirmedBeat.impact
        let strength = landed < 0 ? 0 : 0.1 + 0.26 * exp(-4 * landed)

        return RadialGradient(colors: [style.accent.opacity(strength), .clear], center: .center, startRadius: 0, endRadius: 220)
            .frame(width: 440, height: 440)
            .position(layout.stamp)
            .accessibilityHidden(true)
    }

    private func rings(at time: Double, layout: GameConfirmedLayout, style: MatchMomentStyle) -> some View {
        let landed = time - GameConfirmedBeat.impact

        return ZStack {
            ForEach(0 ..< 2, id: \.self) { index in
                let progress = (landed - 0.1 * Double(index)) / 0.75
                if progress >= 0, progress < 1 {
                    Circle()
                        .stroke(style.accent.opacity(0.55 * (1 - progress)), lineWidth: 0.5 + 3 * (1 - progress))
                        .frame(width: 2 * (30 + 130 * CGFloat(MatchMomentCurve.easeOut(progress))))
                        .position(layout.stamp)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func particles(at time: Double, layout: GameConfirmedLayout, style: MatchMomentStyle) -> some View {
        let landed = time - GameConfirmedBeat.impact
        let origin = layout.stamp

        return ZStack {
            ForEach(style.particles) { particle in
                let age = landed - particle.delay
                if age >= 0, age < particle.lifetime {
                    RoundedRectangle(cornerRadius: particle.isRound ? particle.size.width / 2 : 2, style: .continuous)
                        .fill(particle.color)
                        .frame(width: particle.size.width, height: particle.size.height)
                        .rotationEffect(.degrees(particle.spin * age))
                        .opacity(particle.opacity(at: age))
                        .position(particle.offset(at: age, from: origin))
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Copy

    private func copy(_ copy: MatchMomentCopy, at time: Double) -> some View {
        VStack(spacing: 10) {
            Text(copy.confirmed)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .modifier(MatchMomentReveal(time: time, start: GameConfirmedBeat.copy))

            Text(L10n.string("You'll find it under Upcoming games on Home.", "Всё будет в «Ближайших играх» на главной."))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .modifier(MatchMomentReveal(time: time, start: GameConfirmedBeat.copy + 0.08))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Timeline

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

        let style = style
        var cues: [(time: Double, play: () -> Void)] = [(GameConfirmedBeat.ticketLands, { AppHaptics.impact(.light) })]
        if style.rally != nil {
            cues.append((GameConfirmedBeat.launch, { AppHaptics.impact(.soft) }))
        }
        switch style.beats.landingFeel {
        case .celebration:
            cues.append((GameConfirmedBeat.impact, { AppHaptics.successCelebration() }))
        case .gentle:
            cues.append((GameConfirmedBeat.impact, { AppHaptics.notification(.success) }))
        }
        cues.append((settle, { isSettled = true }))

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

    private func skipToEnd() {
        guard !isSettled else { return }
        cuesTask?.cancel()
        if Date().timeIntervalSince(startDate) < GameConfirmedBeat.impact {
            AppHaptics.notification(.success)
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isSettled = true
        }
    }
}

private enum GameConfirmedBeat {
    static let drop = 0.08
    /// The drop spring is ~95% down by now.
    static let ticketLands = 0.43
    static let launch = 0.74
    static let impact = 1.12
    static let copy = impact + 0.06
    static let actions = impact + 0.26
    static let finalFrame = 10.0
}

private struct GameConfirmedLayout {
    let ticket: CGSize
    let center: CGPoint
    let copyTop: CGFloat
    let launch: CGPoint
    let stamp: CGPoint

    init(size: CGSize) {
        ticket = CGSize(width: min(size.width - 56, 330), height: 214)
        // Ticket, gap and copy (≈ 350 pt) centred in the space above the button.
        let settledHeight = ticket.height + 44 + 92
        let top = max(70, (size.height - 110 - settledHeight) / 2)
        center = CGPoint(x: size.width / 2, y: top + ticket.height / 2)
        copyTop = center.y + ticket.height / 2 + 44
        launch = CGPoint(x: -40, y: center.y + ticket.height / 2 + 240)
        // Straddling the ticket's top edge like a sticker, so it covers none of the
        // lines even for a long sport name.
        stamp = CGPoint(x: center.x + ticket.width / 2 - 70, y: center.y - ticket.height / 2 - 12)
    }
}

// MARK: - Pieces

/// The agreed game as a ticket: sport and length, the day, the time, then past the
/// perforation where and with whom.
private struct GameConfirmedTicket: View {
    static let perforation: CGFloat = 152

    let confirmation: AppModel.GameConfirmation
    let time: Double
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            GameConfirmedTicketShape(notchY: Self.perforation)
                .fill(AppTheme.creamLight)
                .shadow(color: .black.opacity(0.4), radius: 22, x: 0, y: 14)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(AppTheme.court)
                        SportIconView(sport: confirmation.sport, color: .white, size: 16)
                    }
                    .frame(width: 28, height: 28)

                    Text(header)
                        .font(.system(size: 13, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .modifier(MatchMomentReveal(time: time, start: 0.42))
                .padding(.bottom, 14)

                Text(dayLine)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .modifier(MatchMomentReveal(time: time, start: 0.48))

                if let timeLine {
                    Text(timeLine)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .modifier(MatchMomentReveal(time: time, start: 0.54))
                }
            }
            .padding(20)

            Path { path in
                path.move(to: CGPoint(x: 18, y: Self.perforation))
                path.addLine(to: CGPoint(x: size.width - 18, y: Self.perforation))
            }
            .stroke(AppTheme.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))

            HStack(spacing: 10) {
                Label(place, systemImage: confirmation.sport == .running ? "point.topleft.down.curvedto.point.bottomright.up" : "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    RemoteAvatarView(name: confirmation.partnerName, path: confirmation.partnerImagePath, size: 24)
                    Text(confirmation.partnerName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .frame(width: size.width, height: size.height - Self.perforation)
            .offset(y: Self.perforation)
            .modifier(MatchMomentReveal(time: time, start: 0.6))
        }
        .frame(width: size.width, height: size.height)
    }

    /// Sport and length on one line; the top-right corner is left for the stamp.
    private var header: String {
        guard let minutes = confirmation.durationMinutes else { return confirmation.sport.title }
        return confirmation.sport.title + " · " + L10n.string("\(minutes) min", "\(minutes) мин")
    }

    private var dayLine: String {
        guard let date = confirmation.date else {
            return L10n.string("Time to be agreed", "Время уточняется")
        }
        let text = CachedDateFormatters.display(template: "EEEEdMMMM").string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var timeLine: String? {
        guard let date = confirmation.date else { return nil }
        let formatter = CachedDateFormatters.display(template: "Hm")
        let end = date.addingTimeInterval(TimeInterval((confirmation.durationMinutes ?? 90) * 60))
        return "\(formatter.string(from: date)) – \(formatter.string(from: end))"
    }

    private var place: String {
        if let place = confirmation.place {
            return place
        }
        return confirmation.sport == .running
            ? L10n.string("Route to be agreed", "Маршрут уточняется")
            : L10n.string("Place to be agreed", "Место уточняется")
    }
}

/// A rounded ticket with a half-circle notch bitten out of each side at the perforation.
private struct GameConfirmedTicketShape: Shape {
    let notchY: CGFloat

    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = 22
        let notch: CGFloat = 11
        let y = rect.minY + notchY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - corner, y: rect.minY + corner), radius: corner, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: y - notch))
        path.addArc(center: CGPoint(x: rect.maxX, y: y), radius: notch, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addArc(center: CGPoint(x: rect.maxX - corner, y: rect.maxY - corner), radius: corner, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + corner, y: rect.maxY - corner), radius: corner, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: y + notch))
        path.addArc(center: CGPoint(x: rect.minX, y: y), radius: notch, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addArc(center: CGPoint(x: rect.minX + corner, y: rect.minY + corner), radius: corner, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// A rubber stamp, set at an angle as if pressed by hand.
private struct GameConfirmedStamp: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
            Text(L10n.string("Confirmed", "Подтверждено"))
                .textCase(.uppercase)
                .tracking(1)
        }
        .font(.system(size: 14, weight: .heavy))
        .foregroundStyle(AppTheme.court)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.mint.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.court, lineWidth: 3))
        .rotationEffect(.degrees(-12))
        .accessibilityLabel(L10n.string("Confirmed", "Подтверждено"))
    }
}
