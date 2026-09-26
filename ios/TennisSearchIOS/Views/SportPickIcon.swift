import SwiftUI

/// A sport icon that plays a one-shot flourish in its sport's character the moment the
/// sport is picked: rackets swing and send the ball off, balls bounce, the runner
/// dashes, the glove punches, the dumbbell goes up twice, yoga takes a breath, the board
/// sways. A ring spreads behind it for every sport. At rest it is exactly `SportIconView`.
struct SportPickIcon: View {
    let sport: Sport
    let isSelected: Bool
    let color: Color
    let accent: Color
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: pickedAt == nil)) { context in
            let elapsed = pickedAt.map { context.date.timeIntervalSince($0) } ?? SportPickMotion.duration
            content(at: min(elapsed, SportPickMotion.duration))
        }
        .frame(width: size, height: size)
        .onChange(of: isSelected) { selected in
            guard selected, !reduceMotion else { return }
            let start = Date()
            pickedAt = start
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(SportPickMotion.duration * 1_000_000_000))
                if pickedAt == start {
                    pickedAt = nil
                }
            }
        }
    }

    private func content(at time: Double) -> some View {
        let motion = SportPickMotion(sport: sport, time: time)
        let ring = MatchMomentCurve.clamp(time / 0.55)

        return ZStack {
            if ring < 1 {
                Circle()
                    .stroke(accent.opacity(0.6 * (1 - ring)), lineWidth: 2)
                    .frame(width: size * (1 + 1.1 * CGFloat(MatchMomentCurve.easeOut(ring))))
            }

            SportIconView(sport: sport, color: color, size: size)
                .scaleEffect(x: motion.scale.width, y: motion.scale.height, anchor: motion.scaleAnchor)
                .rotationEffect(.degrees(motion.rotation), anchor: motion.pivot)
                .offset(motion.offset)

            if let shot = motion.shot {
                MatchMomentProjectileView(kind: shot.kind, size: size * 0.4)
                    .rotationEffect(.degrees(shot.kind.isShuttle ? -40 : time * 900))
                    .offset(shot.offset)
                    .opacity(shot.opacity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The flourish as a pure function of time since the pick; identity at `duration`.
private struct SportPickMotion {
    static let duration = 0.9

    struct Shot {
        let kind: MatchMomentProjectile
        let offset: CGSize
        let opacity: Double
    }

    var offset: CGSize = .zero
    var rotation: Double = 0
    var scale = CGSize(width: 1, height: 1)
    /// Squash from the ground up, but a ball still rolls about its own centre.
    var scaleAnchor: UnitPoint = .center
    /// What it turns about: the grip of a racket, the feet of a runner.
    var pivot: UnitPoint = .center
    var shot: Shot?

    init(sport: Sport, time: Double) {
        guard time < Self.duration else { return }
        let t = time

        switch sport {
        case .tennis, .padel, .squash, .badminton, .tableTennis:
            // Back-swing, snap through, settle; the ball leaves on the snap.
            pivot = .bottomLeading
            if t < 0.12 {
                rotation = -28 * MatchMomentCurve.easeOut(t / 0.12)
            } else if t < 0.2 {
                rotation = -28 + 46 * MatchMomentCurve.easeOut((t - 0.12) / 0.08)
            } else {
                rotation = 18 * (1 - MatchMomentCurve.spring(t - 0.2, response: 0.35, damping: 0.55))
            }
            if let kind = MatchMomentRally(sport: sport)?.projectile, t >= 0.18 {
                let u = MatchMomentCurve.clamp((t - 0.18) / 0.45)
                shot = Shot(
                    kind: kind,
                    offset: CGSize(width: 44 * u, height: -26 * u - 22 * 4 * u * (1 - u)),
                    opacity: 1 - u
                )
            }
        case .football, .volleyball:
            // Two bounces, squashing on each landing; a football rolls as it goes.
            let decay = exp(-2.5 * t)
            let phase = t / 0.35
            let hop = abs(sin(Double.pi * phase)) * decay
            offset = CGSize(width: 0, height: -16 * hop)
            let contact = max(0, 1 - hop * 6) * decay
            scale = CGSize(width: 1 + 0.18 * contact, height: 1 - 0.16 * contact)
            scaleAnchor = .bottom
            rotation = sport == .football ? 300 * (1 - decay) : 0
        case .running:
            // A dash forward, leaning in, and back.
            let dash = sin(Double.pi * MatchMomentCurve.clamp(t / 0.55))
            offset = CGSize(width: 10 * dash, height: 0)
            rotation = 12 * dash
            pivot = .bottom
        case .boxing:
            // A punch at the viewer: a sharp swell that snaps back.
            let punch = exp(-6 * t) * sin(14 * t)
            scale = CGSize(width: 1 + 0.35 * punch, height: 1 + 0.35 * punch)
            offset = CGSize(width: 3 * punch, height: 0)
        case .fitness:
            // Two reps.
            let rep = abs(sin(2 * Double.pi * t / 0.9)) * (t < 0.9 ? 1 : 0)
            offset = CGSize(width: 0, height: -10 * rep)
        case .yoga:
            // One slow breath.
            let breath = 0.14 * sin(Double.pi * t / Self.duration)
            scale = CGSize(width: 1 + breath, height: 1 + breath)
        case .supboard:
            // Sways on a swell and settles.
            let sway = exp(-3 * t) * sin(12 * t)
            rotation = 10 * sway
            offset = CGSize(width: 0, height: -3 * sway)
            pivot = .bottom
        }
    }
}
