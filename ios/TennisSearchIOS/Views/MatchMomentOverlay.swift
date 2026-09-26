import SwiftUI

/// Full-screen moment for a mutual like, played in the match's sport (see
/// `MatchMomentScenes.swift`): a rally over a net, off a wall or along the grass, a sprint
/// through the finish tape, gloves touching in the ring, a barbell pressed together, a
/// breath on the mat, or two boards bumping on the water.
///
/// Every frame is a pure function of the elapsed time. That keeps the choreography
/// deterministic, lets a tap or Reduce Motion jump straight to the final frame, and
/// keeps the per-frame work inside this view instead of the screen underneath.
struct MatchMomentOverlay: View {
    let moment: AppModel.MatchMoment
    let onPlanGame: () -> Void
    let onKeepBrowsing: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var isSettled = false
    @State private var isRevealed = false
    @State private var beatsTask: Task<Void, Never>?

    private var style: MatchMomentStyle { MatchMomentStyle(sport: moment.sport) }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isSettled)) { context in
            scene(at: isSettled ? MatchMomentBeats.finalFrame : context.date.timeIntervalSince(startDate))
        }
        // Reduce Motion skips the choreography and only fades the settled frame in.
        .opacity(reduceMotion && !isRevealed ? 0 : 1)
        .accessibilityAddTraits(.isModal)
        .onAppear(perform: start)
        .onDisappear { beatsTask?.cancel() }
    }

    private func scene(at time: Double) -> some View {
        let style = style

        return GeometryReader { proxy in
            let stage = MatchMomentStage(size: proxy.size, groundAspect: style.ground?.aspect ?? MatchMomentGround.tennis.aspect)

            ZStack {
                glow(at: time, stage: stage, style: style)
                if let ground = style.ground {
                    self.ground(ground, at: time, stage: stage, style: style)
                }
                if style.isSprint {
                    finishTape(at: time, stage: stage, beats: style.beats)
                    speedLines(of: .viewer, at: time, stage: stage, style: style)
                    speedLines(of: .player, at: time, stage: stage, style: style)
                }
                shockwaves(at: time, stage: stage, style: style)
                card(side: .viewer, at: time, stage: stage, style: style)
                card(side: .player, at: time, stage: stage, style: style)
                particles(at: time, stage: stage, style: style)
                seal(at: time, stage: stage, style: style)

                VStack(spacing: 0) {
                    copy(style.copy, at: time, beats: style.beats)
                        .padding(.top, stage.copyTop)
                    Spacer(minLength: 16)
                    actions(style.copy, at: time, beats: style.beats)
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

    // MARK: Ground

    private func glow(at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        let landed = time - style.beats.landing
        let strength = landed < 0 ? 0 : 0.1 + 0.26 * exp(-4 * landed)

        return RadialGradient(
            colors: [style.accent.opacity(strength), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 220
        )
        .frame(width: 440, height: 440)
        .position(stage.point(style.landingPoint(on: stage)))
        .accessibilityHidden(true)
    }

    private func ground(_ ground: MatchMomentGround, at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        let drawn = MatchMomentCurve.easeInOut((time - 0.1) / 0.7)
        let stretched = MatchMomentCurve.easeInOut((time - 0.25) / 0.35)
        // The players leave their places for the centre, so the ground steps back; a
        // sprint crosses the track the whole time, so it only fades after the finish.
        let recede = 1 - 0.5 * MatchMomentCurve.easeInOut((time - style.groundRecedes) / 0.4)
        let netHeight = stage.court.height + 28
        let rect = CGRect(
            x: stage.center.x - stage.court.width / 2,
            y: stage.center.y - stage.court.height / 2,
            width: stage.court.width,
            height: stage.court.height
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ground.surface.opacity(0.26 * drawn * recede))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            MatchMomentGroundLines(ground: ground)
                .trim(from: 0, to: drawn)
                .stroke(Color.white.opacity(ground.lineOpacity * recede), style: StrokeStyle(lineWidth: ground.lineWidth, lineCap: .round))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            if let netWidth = ground.netWidth {
                Capsule()
                    .fill(Color.white.opacity(0.45 * recede))
                    .frame(width: netWidth, height: netHeight * stretched)
                    .position(x: stage.center.x, y: stage.center.y - netHeight / 2 + netHeight * stretched / 2)
            }

            switch ground {
            case .squash:
                squashWall(stage: stage, width: rect.width * stretched, opacity: recede)
            case .ring:
                ringPosts(in: rect, opacity: drawn * recede)
            case .water:
                // The water keeps moving until the timeline rests, then holds still.
                MatchMomentWaves(phase: min(time, style.beats.settle))
                    .trim(from: 0, to: drawn)
                    .stroke(Color.white.opacity(0.3 * recede), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            default:
                EmptyView()
            }
        }
        .accessibilityHidden(true)
    }

    /// The front wall above the floor: its face, the red out line on top and the tin below.
    private func squashWall(stage: MatchMomentStage, width: CGFloat, opacity: Double) -> some View {
        let face = stage.point(CGPoint(x: 0, y: stage.wallY - 16))

        return ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.1 * opacity))
                .frame(width: width, height: 32)
            VStack(spacing: 0) {
                Rectangle().fill(AppTheme.clay.opacity(0.8 * opacity)).frame(height: 2)
                Spacer(minLength: 0)
                Rectangle().fill(AppTheme.clay.opacity(0.8 * opacity)).frame(height: 3)
            }
            .frame(width: width, height: 32)
        }
        .position(face)
    }

    /// Corner posts: red and blue for the two corners, neutral white for the others.
    private func ringPosts(in rect: CGRect, opacity: Double) -> some View {
        let corners: [(CGPoint, Color)] = [
            (CGPoint(x: rect.minX, y: rect.minY), MatchMomentPalette.redCorner),
            (CGPoint(x: rect.maxX, y: rect.minY), .white),
            (CGPoint(x: rect.minX, y: rect.maxY), .white),
            (CGPoint(x: rect.maxX, y: rect.maxY), MatchMomentPalette.blueCorner)
        ]

        return ZStack {
            ForEach(0 ..< corners.count, id: \.self) { index in
                Circle()
                    .fill(corners[index].1.opacity(0.9 * opacity))
                    .frame(width: 12, height: 12)
                    .position(corners[index].0)
            }
        }
    }

    // MARK: Players

    private struct Pose {
        let x: CGFloat
        let y: CGFloat
        let rotation: Double
    }

    /// Where a card is. Most scenes enter to their side and later come together; a sprint
    /// runs straight in from off-screen, accelerating, bobbing each stride, leaning in.
    private func pose(of side: MatchMomentSide, at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> Pose {
        let s = side.sign
        let beats = style.beats
        let offstage = stage.offstageX * CGFloat(s)
        let meet = style.meetX * CGFloat(s)
        let settledTilt = s * style.settledTilt

        switch style.scene {
        case .breathe:
            // Unhurried and without overshoot, straight to each other.
            let drift = MatchMomentCurve.spring(time - side.entrance * 2, response: 1.4, damping: 0.9)
            return Pose(x: offstage + (meet - offstage) * CGFloat(drift), y: 0, rotation: s * 12 + (settledTilt - s * 12) * drift)
        case .float:
            // Bobbing and rolling out of step with each other, calming once they touch;
            // the phase stops with the timeline so the final frame matches the last one.
            let drift = MatchMomentCurve.spring(time - side.entrance, response: 1.0, damping: 0.82)
            let calm = min(time, beats.settle)
            let swell = calm < beats.landing ? 1 : exp(-3 * (calm - beats.landing))
            let phase = 2 * Double.pi * calm / 1.7 + (side == .viewer ? 0 : 1.9)
            return Pose(
                x: offstage + (meet - offstage) * CGFloat(drift),
                y: CGFloat(5 * sin(phase) * swell),
                rotation: s * 10 + (settledTilt - s * 10) * drift + 3 * sin(phase + 0.8) * swell
            )
        default:
            break
        }

        if style.isSprint {
            let run = MatchMomentCurve.clamp((time - beats.converge) / (beats.landing - beats.converge))
            let finished = MatchMomentCurve.spring(time - beats.landing, response: 0.45, damping: 0.7)
            let stride = time < beats.landing ? -8 * abs(sin(run * .pi * 5)) : 0
            let lean = -s * 10
            return Pose(
                x: offstage + (meet - offstage) * CGFloat(run * run),
                y: CGFloat(stride),
                rotation: lean + (settledTilt - lean) * finished
            )
        }

        let entered = MatchMomentCurve.spring(time - side.entrance, response: 0.55, damping: 0.74)
        let met = MatchMomentCurve.spring(time - beats.converge, response: 0.5, damping: 0.66)
        let baseline = stage.baselineX * CGFloat(s)
        var x = offstage + (baseline - offstage) * CGFloat(entered)
        x += (meet - x) * CGFloat(met)
        var rotation = s * (14 + (4 - 14) * entered)
        rotation += (settledTilt - rotation) * met
        return Pose(x: x, y: 0, rotation: rotation)
    }

    private func card(side: MatchMomentSide, at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        let s = side.sign
        let pose = pose(of: side, at: time, stage: stage, style: style)

        // A hit (or the two cards colliding) lunges the card at the centre and squeezes
        // it, then springs back.
        let hits = side.hits(in: style.beats)
        let swing = hits.reduce(0) { $0 + MatchMomentCurve.bump(time - $1) }
        let flash = hits.reduce(0) { total, hit in
            let since = time - hit
            return since < 0 ? total : total + 0.35 * exp(-14 * since)
        }

        // Lifters sink and drive under the bar; on the mat the cards breathe.
        let stature: CGFloat
        let girth: CGFloat
        if style.isLift {
            let squat = MatchMomentLift.squat(at: time, beats: style.beats)
            stature = MatchMomentLift.stature(squat: squat)
            girth = 1 + 0.03 * CGFloat(squat)
        } else if style.isBreathe {
            let calm = min(time, style.beats.settle)
            let fade = calm < style.beats.landing ? 1 : exp(-2 * (calm - style.beats.landing))
            let breath = 1 + 0.025 * CGFloat(sin(2 * Double.pi * (calm - 0.35) / 1.6) * fade)
            stature = breath
            girth = breath
        } else {
            stature = 1
            girth = 1
        }

        let person = side == .viewer ? moment.viewer : moment.player
        return MatchMomentCard(
            name: person.name,
            caption: side == .viewer ? L10n.string("You", "Ты") : person.name,
            imagePath: person.imagePath,
            tint: side == .viewer ? MatchMomentPalette.viewerCard : MatchMomentPalette.playerCard
        )
        .overlay(
            RoundedRectangle(cornerRadius: MatchMomentCard.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(min(flash, 0.5)))
        )
        .scaleEffect(x: girth, y: stature, anchor: .bottom)
        .scaleEffect(1 - 0.07 * swing)
        .rotationEffect(.degrees(pose.rotation - s * 3 * swing))
        .position(stage.point(CGPoint(x: pose.x - CGFloat(s * 10 * swing), y: pose.y)))
        .accessibilityHidden(true)
    }

    // MARK: Sprint

    /// Stretched across the finish line like the net; the cards break it, and each half
    /// snaps back to its post with a wobble.
    private func finishTape(at time: Double, stage: MatchMomentStage, beats: MatchMomentBeats) -> some View {
        let half = stage.court.height / 2 + 18
        let stretched = CGFloat(MatchMomentCurve.easeInOut((time - 0.25) / 0.35))
        let broken = time - beats.landing
        let snap = broken < 0 ? 0 : MatchMomentCurve.spring(broken, response: 0.5, damping: 0.45)
        let wobble = broken < 0 ? 0 : 18 * exp(-5 * broken) * sin(20 * broken)
        let length = half * stretched
        let shrink = CGFloat(max(0.14, 1 - 0.86 * snap))

        return ZStack {
            ForEach([-1.0, 1.0], id: \.self) { end in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 9, height: 9)
                    .position(stage.point(CGPoint(x: 0, y: CGFloat(end) * half)))
            }

            Capsule()
                .fill(MatchMomentPalette.ball)
                .frame(width: 4, height: length)
                .scaleEffect(x: 1, y: shrink, anchor: .top)
                .rotationEffect(.degrees(-wobble), anchor: .top)
                .position(stage.point(CGPoint(x: 0, y: -half + length / 2)))

            Capsule()
                .fill(MatchMomentPalette.ball)
                .frame(width: 4, height: length)
                .scaleEffect(x: 1, y: shrink, anchor: .bottom)
                .rotationEffect(.degrees(wobble), anchor: .bottom)
                .position(stage.point(CGPoint(x: 0, y: half - length / 2)))
        }
        .accessibilityHidden(true)
    }

    /// Streaks trailing each runner, as strong as the run is fast.
    private func speedLines(of side: MatchMomentSide, at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        let beats = style.beats
        let run = MatchMomentCurve.clamp((time - beats.converge) / (beats.landing - beats.converge))
        let strength = time < beats.landing ? run : max(0, 1 - (time - beats.landing) / 0.25)
        let pose = pose(of: side, at: time, stage: stage, style: style)
        let behind = CGFloat(side.sign) * (MatchMomentStage.card.width / 2 + 22)
        let rows: [CGFloat] = [-38, 4, 42]

        return ZStack {
            ForEach(0 ..< rows.count, id: \.self) { index in
                let length = CGFloat(30 + 14 * index)
                Capsule()
                    .fill(Color.white.opacity(0.4 * strength))
                    .frame(width: length, height: 3)
                    .position(stage.point(CGPoint(x: pose.x + behind + CGFloat(side.sign) * length / 2, y: pose.y + rows[index])))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Seal

    @ViewBuilder
    private func seal(at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        switch style.scene {
        case .rally(let rally):
            projectile(rally, at: time, stage: stage)
        case .gloves:
            glove(of: .viewer, at: time, stage: stage, style: style)
            glove(of: .player, at: time, stage: stage, style: style)
        case .lift:
            barbell(at: time, stage: stage, beats: style.beats)
        case .breathe:
            sportBadge(at: time, stage: stage, beats: style.beats, gentle: true)
        case .sprint, .float, .meet:
            sportBadge(at: time, stage: stage, beats: style.beats, gentle: false)
        }
    }

    @ViewBuilder
    private func projectile(_ rally: MatchMomentRally, at time: Double, stage: MatchMomentStage) -> some View {
        if let state = MatchMomentFlight.state(at: time, stage: stage, rally: rally) {
            ZStack {
                ForEach(1 ..< 5, id: \.self) { index in
                    if state.isInFlight, let ghost = MatchMomentFlight.state(at: time - 0.022 * Double(index), stage: stage, rally: rally), ghost.isInFlight {
                        Circle()
                            .fill(rally.projectile.accent.opacity(0.26 * (1 - Double(index) / 5)))
                            .frame(width: rally.projectile.flightSize * ghost.depth * (1 - 0.1 * CGFloat(index)))
                            .position(stage.point(ghost.position))
                    }
                }

                MatchMomentProjectileView(kind: rally.projectile, size: state.size)
                    .rotationEffect(.degrees(state.rotation))
                    .scaleEffect(x: state.squash.width, y: state.squash.height)
                    .shadow(color: rally.projectile.accent.opacity(0.55), radius: 12)
                    .position(stage.point(state.position))
            }
            .accessibilityHidden(true)
        }
    }

    /// Each glove rides with its card, winds up as the boxers square off, punches in to
    /// touch the other one in the middle, then eases back a little.
    private func glove(of side: MatchMomentSide, at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        let s = CGFloat(side.sign)
        let landing = style.beats.landing
        let contact = style.landingPoint(on: stage)
        let pose = pose(of: side, at: time, stage: stage, style: style)
        let held = CGPoint(x: pose.x - s * 40, y: contact.y + 8)
        // Each glove stays on its own boxer's side of the centre: they touch, not cross.
        let strike = CGPoint(x: s * 17, y: contact.y)
        let rest = CGPoint(x: s * 23, y: contact.y)
        let appear = MatchMomentCurve.easeOut((time - (landing - 0.5)) / 0.2)

        let point: CGPoint
        if time >= landing {
            let recoil = CGFloat(MatchMomentCurve.spring(time - landing, response: 0.35, damping: 0.55))
            point = CGPoint(x: strike.x + (rest.x - strike.x) * recoil, y: strike.y)
        } else {
            let punch = CGFloat(MatchMomentCurve.anticipate((time - (landing - 0.24)) / 0.24))
            point = CGPoint(x: held.x + (strike.x - held.x) * punch, y: held.y + (strike.y - held.y) * punch)
        }
        let impact = 1 + 0.12 * MatchMomentCurve.bump(time - landing)

        return MatchMomentGlove(color: side == .viewer ? MatchMomentPalette.redCorner : MatchMomentPalette.blueCorner)
            .scaleEffect(x: side == .viewer ? 1 : -1, y: 1)
            .scaleEffect(max(appear, 0.001) * impact)
            .rotationEffect(.degrees(Double(s) * 8))
            .opacity(appear)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .position(stage.point(point))
            .accessibilityHidden(true)
    }

    /// Drops from above onto both pairs of shoulders, rides the squat, and goes
    /// overhead at lockout; the plates ring on the catch and on the lockout.
    private func barbell(at time: Double, stage: MatchMomentStage, beats: MatchMomentBeats) -> some View {
        let caught = beats.contacts[0].time
        let dropStart = caught - 0.3
        let squat = MatchMomentLift.squat(at: time, beats: beats)
        let press = MatchMomentLift.press(at: time, beats: beats)
        let y: CGFloat
        if time < caught {
            let fall = MatchMomentCurve.clamp((time - dropStart) / 0.3)
            let shoulders = MatchMomentLift.barY(squat: 0, press: 0)
            y = -300 + (shoulders + 300) * CGFloat(fall * fall)
        } else {
            y = MatchMomentLift.barY(squat: squat, press: press)
        }
        let bend = 7 * CGFloat(MatchMomentCurve.bump(time - caught) + 0.7 * MatchMomentCurve.bump(time - beats.landing))

        return MatchMomentBarbell(bend: bend)
            .opacity(MatchMomentCurve.clamp((time - dropStart) / 0.08))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .position(stage.point(CGPoint(x: 0, y: y)))
            .accessibilityHidden(true)
    }

    /// Without anything thrown the badge is what lands: it drops in where the two cards
    /// touch and settles with one overshoot; on the mat it just blooms in.
    private func sportBadge(at time: Double, stage: MatchMomentStage, beats: MatchMomentBeats, gentle: Bool) -> some View {
        let pop = gentle
            ? MatchMomentCurve.easeOut((time - beats.landing) / 0.6)
            : MatchMomentCurve.spring(time - beats.landing, response: 0.42, damping: 0.55)

        return ZStack {
            Circle()
                .fill(MatchMomentPalette.ball)
            SportIconView(sport: moment.sport, color: AppTheme.ink, size: 26)
        }
        .frame(width: 50, height: 50)
        .scaleEffect(max(pop, 0.001))
        .offset(y: -22 * (1 - min(pop, 1)))
        .shadow(color: MatchMomentPalette.ball.opacity(0.55), radius: 12)
        .position(stage.point(stage.landing))
        .accessibilityHidden(true)
    }

    // MARK: Landing

    private func shockwaves(at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        let origin = style.landingPoint(on: stage)
        let rings = style.rings

        return ZStack {
            ForEach(0 ..< rings.count, id: \.self) { index in
                let ring = rings[index]
                let progress = (time - ring.start) / ring.duration
                if progress >= 0, progress < 1 {
                    let radius = 24 + ring.radius * CGFloat(MatchMomentCurve.easeOut(progress))
                    Ellipse()
                        .stroke(style.accent.opacity(ring.strength * (1 - progress)), lineWidth: 0.5 + 3 * (1 - progress))
                        .frame(width: 2 * radius, height: 2 * radius * ring.flatten)
                        .position(stage.point(origin))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func particles(at time: Double, stage: MatchMomentStage, style: MatchMomentStyle) -> some View {
        let landed = time - style.beats.landing
        let origin = style.landingPoint(on: stage)

        return ZStack {
            ForEach(style.particles) { particle in
                let age = landed - particle.delay
                if age >= 0, age < particle.lifetime {
                    RoundedRectangle(cornerRadius: particle.isRound ? particle.size.width / 2 : 2, style: .continuous)
                        .fill(particle.color)
                        .frame(width: particle.size.width, height: particle.size.height)
                        .rotationEffect(.degrees(particle.spin * age))
                        .opacity(particle.opacity(at: age))
                        .position(stage.point(particle.offset(at: age, from: origin)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Copy

    private func copy(_ copy: MatchMomentCopy, at time: Double, beats: MatchMomentBeats) -> some View {
        VStack(spacing: 10) {
            Text(L10n.string("New match", "Новый мэтч"))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(MatchMomentPalette.eyebrow)
                .modifier(MatchMomentReveal(time: time, start: beats.copy))

            Text(copy.title)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .modifier(MatchMomentReveal(time: time, start: beats.copy + 0.08))

            Text(copy.subtitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .modifier(MatchMomentReveal(time: time, start: beats.copy + 0.16))
        }
        .accessibilityElement(children: .combine)
    }

    private func actions(_ copy: MatchMomentCopy, at time: Double, beats: MatchMomentBeats) -> some View {
        VStack(spacing: 6) {
            Button(action: onPlanGame) {
                Text(copy.action)
            }
            .buttonStyle(MatchMomentPrimaryButtonStyle())
            .modifier(MatchMomentReveal(time: time, start: beats.actions))

            Button(action: onKeepBrowsing) {
                Text(L10n.string("Keep browsing", "Смотреть дальше"))
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

        let beats = style.beats
        var cues: [(time: Double, play: () -> Void)] = beats.contacts.map { contact in
            (contact.time, { AppHaptics.impact(contact.feel) })
        }
        switch beats.landingFeel {
        case .celebration:
            cues.append((beats.landing, { AppHaptics.successCelebration() }))
        case .gentle:
            cues.append((beats.landing, { AppHaptics.notification(.success) }))
        }
        cues.append((beats.settle, { isSettled = true }))

        let startDate = startDate
        beatsTask = Task { @MainActor in
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
        beatsTask?.cancel()
        if Date().timeIntervalSince(startDate) < style.beats.landing {
            AppHaptics.notification(.success)
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isSettled = true
        }
    }
}
