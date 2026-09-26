import SwiftUI
import UIKit

// Per-sport choreography for `MatchMomentOverlay`: what is drawn under the cards, what
// flies between them and when, and what the moment says. Kept apart from the view so a
// new sport is a new case here, not new timeline code.

// MARK: - Style

enum MatchMomentScene {
    /// Something flies between the players and lands as the seal.
    case rally(MatchMomentRally)
    /// Both sprint in and break the finish tape between them.
    case sprint
    /// The cards square up in the ring and their gloves meet in the middle.
    case gloves
    /// Side by side under one barbell: catch it, sit into a squat, press it overhead.
    case lift
    /// A slow drift together on the mat, breathing; nothing strikes, nothing bursts.
    case breathe
    /// Two boards bob on the water, drift in and bump with a splash.
    case float
    /// The cards simply come together; the sport badge lands where they touch.
    case meet
}

struct MatchMomentStyle {
    let sport: Sport
    let scene: MatchMomentScene
    let beats: MatchMomentBeats
    let copy: MatchMomentCopy

    init(sport: Sport) {
        self.sport = sport
        copy = MatchMomentCopy(sport: sport)
        if let rally = MatchMomentRally(sport: sport) {
            scene = .rally(rally)
            beats = rally.beats
            return
        }
        switch sport {
        case .running:
            scene = .sprint
            beats = .sprint
        case .boxing:
            scene = .gloves
            beats = .gloves
        case .fitness:
            scene = .lift
            beats = .lift
        case .yoga:
            scene = .breathe
            beats = .breathe
        case .supboard:
            scene = .float
            beats = .float
        default:
            scene = .meet
            beats = .meet
        }
    }

    var rally: MatchMomentRally? {
        if case .rally(let rally) = scene { return rally }
        return nil
    }

    var isSprint: Bool {
        if case .sprint = scene { return true }
        return false
    }

    var isGloves: Bool {
        if case .gloves = scene { return true }
        return false
    }

    var isLift: Bool {
        if case .lift = scene { return true }
        return false
    }

    var isBreathe: Bool {
        if case .breathe = scene { return true }
        return false
    }

    /// Court, track, ring, gym floor, mat or water under the cards; the neutral scene
    /// draws none.
    var ground: MatchMomentGround? {
        switch scene {
        case .rally(let rally): return rally.ground
        case .sprint: return .track
        case .gloves: return .ring
        case .lift: return .gym
        case .breathe: return .mat
        case .float: return .water
        case .meet: return nil
        }
    }

    /// When the ground steps back to let the seal read. Where the players leave their
    /// places for the centre that is when they go; where the whole scene is the
    /// approach (the run, the drift, the water), only once they have arrived.
    var groundRecedes: Double {
        switch scene {
        case .sprint, .breathe, .float: return beats.landing
        default: return beats.converge
        }
    }

    var accent: Color {
        switch scene {
        case .rally(let rally): return rally.projectile.accent
        case .breathe: return AppTheme.mint
        case .float: return MatchMomentPalette.water
        default: return MatchMomentPalette.ball
        }
    }

    /// Boxers stop at arm's length so the gloves have room to meet between them;
    /// lifters stand shoulder to shoulder under one bar.
    var meetX: CGFloat {
        switch scene {
        case .gloves: return 84
        case .lift: return 60
        case .float: return 58
        default: return 54
        }
    }

    /// How far each card leans once settled. Under a barbell they stand upright.
    var settledTilt: Double {
        switch scene {
        case .gloves: return 3
        case .lift: return 2
        case .float: return 5
        case .breathe: return 6
        default: return 8
        }
    }

    /// Where the seal lands: the gap between the cards' top corners, the point where
    /// the gloves touch, the pressed bar, or the waterline where the boards bump.
    func landingPoint(on stage: MatchMomentStage) -> CGPoint {
        switch scene {
        case .gloves: return CGPoint(x: 0, y: -30)
        case .lift: return CGPoint(x: 0, y: MatchMomentLift.barY(squat: 0, press: 1))
        case .float: return CGPoint(x: 0, y: 50)
        default: return stage.landing
        }
    }

    /// Rings spreading from the landing point: a sharp double shock by default, slow
    /// breaths on the mat, flat ripples on the water.
    var rings: [MatchMomentRing] {
        let landing = beats.landing
        switch scene {
        case .breathe:
            return [0.2, 0.95].map { MatchMomentRing(start: $0, duration: 1.6, radius: 110, flatten: 1, strength: 0.28) }
                + [MatchMomentRing(start: landing, duration: 1.9, radius: 170, flatten: 1, strength: 0.4)]
        case .float:
            return [0, 0.18, 0.36].map { MatchMomentRing(start: landing + $0, duration: 1.1, radius: 170, flatten: 0.34, strength: 0.55) }
        default:
            return [0, 0.1].map { MatchMomentRing(start: landing + $0, duration: 0.75, radius: 150, flatten: 1, strength: 0.6) }
        }
    }

    var particles: [MatchMomentParticle] {
        switch scene {
        case .breathe: return MatchMomentParticle.motes
        case .float: return MatchMomentParticle.splash
        default: return MatchMomentParticle.confetti
        }
    }
}

struct MatchMomentRing {
    let start: Double
    let duration: Double
    let radius: CGFloat
    /// Height over width: 1 is a circle, less lays it flat on the water.
    let flatten: CGFloat
    let strength: Double
}

/// The barbell and the squat under it, as functions of time.
enum MatchMomentLift {
    static let pressHeight: CGFloat = 40

    /// Card height scale for a squat depth: 0 standing, 1 at the bottom, negative when
    /// the legs drive through at lockout.
    static func stature(squat: Double) -> CGFloat {
        CGFloat(1 - 0.1 * squat)
    }

    /// The bar's centre relative to the stage centre: resting on the card tops, which
    /// are anchored at their bottoms, lifted by the press.
    static func barY(squat: Double, press: Double) -> CGFloat {
        let card = MatchMomentStage.card.height
        return card / 2 - card * stature(squat: squat) - 4 - pressHeight * CGFloat(press)
    }

    /// Catch dips, recover, one full squat, drive up through lockout, settle.
    static func squat(at time: Double, beats: MatchMomentBeats) -> Double {
        let caught = beats.contacts[0].time
        let landing = beats.landing
        guard time >= caught else { return 0 }
        if time >= landing {
            return -0.25 * (1 - MatchMomentCurve.spring(time - landing, response: 0.4, damping: 0.6))
        }
        let keys: [(Double, Double)] = [(caught, 0), (caught + 0.07, 0.45), (caught + 0.2, 0.05), (landing - 0.3, 1), (landing, -0.25)]
        for index in 1 ..< keys.count where time < keys[index].0 {
            let (from, to) = (keys[index - 1], keys[index])
            let u = MatchMomentCurve.easeInOut((time - from.0) / (to.0 - from.0))
            return from.1 + (to.1 - from.1) * u
        }
        return -0.25
    }

    /// How far the bar has gone from the shoulders to overhead.
    static func press(at time: Double, beats: MatchMomentBeats) -> Double {
        MatchMomentCurve.easeOut((time - (beats.landing - 0.22)) / 0.22)
    }
}

struct MatchMomentContact {
    let time: Double
    /// Whose card strikes; nil for a wall bounce or a footstep.
    let hitter: MatchMomentSide?
    let feel: UIImpactFeedbackGenerator.FeedbackStyle
}

struct MatchMomentBeats {
    /// Every hit, bounce or step that the hand should feel, in order.
    let contacts: [MatchMomentContact]
    /// When the players leave their positions for the centre.
    let converge: Double
    /// When the last shot, the badge or the gloves land as the seal.
    let landing: Double
    /// Whether the cards themselves collide at `landing`, rather than a ball landing.
    let cardsTouch: Bool
    /// How long after `landing` the last ring or particle is gone.
    var rest: Double = 1.23
    /// A full celebration, or, where the scene is calm, a single soft success.
    var landingFeel: LandingFeel = .celebration

    enum LandingFeel { case celebration, gentle }

    var copy: Double { landing - 0.11 }
    var actions: Double { landing + 0.17 }
    /// Every spring, ring and particle has come to rest by now; the timeline pauses.
    var settle: Double { landing + rest }
    static let finalFrame = 10.0

    /// Both walk in under the bar, catch it as it drops, sit into one squat and press
    /// it overhead together.
    static let lift = MatchMomentBeats(
        contacts: [
            MatchMomentContact(time: 1.02, hitter: nil, feel: .heavy),
            MatchMomentContact(time: 1.42, hitter: nil, feel: .medium)
        ],
        converge: 0.25,
        landing: 1.72,
        cardsTouch: false
    )

    /// One soft pulse on the first inhale; they arrive on the exhale.
    static let breathe = MatchMomentBeats(
        contacts: [MatchMomentContact(time: 0.75, hitter: nil, feel: .soft)],
        converge: 0,
        landing: 1.55,
        cardsTouch: false,
        rest: 2.1,
        landingFeel: .gentle
    )

    /// The boards touch as the drift arrives (its spring is ~98% there by 0.85 s).
    static let float = MatchMomentBeats(contacts: [], converge: 0, landing: 0.9, cardsTouch: true, rest: 1.5, landingFeel: .gentle)

    /// The cards head for each other almost as soon as they enter and touch at `landing`.
    static let meet = MatchMomentBeats(contacts: [], converge: 0.3, landing: 0.6, cardsTouch: true)

    /// From off-screen straight to the tape, one light tick per stride.
    static let sprint: MatchMomentBeats = {
        let start = 0.12
        let finish = 1.0
        let steps = (1 ... 4).map { step in
            MatchMomentContact(time: start + (finish - start) * Double(step) / 5, hitter: nil, feel: .light)
        }
        return MatchMomentBeats(contacts: steps, converge: start, landing: finish, cardsTouch: true)
    }()

    static let gloves = MatchMomentBeats(contacts: [], converge: 0.7, landing: 1.05, cardsTouch: false)

    /// Serve, return, and the closing shot; the players leave for the net while it flies.
    static func exchange(returnHit: Double, closingHit: Double, landing: Double, feel: UIImpactFeedbackGenerator.FeedbackStyle) -> MatchMomentBeats {
        MatchMomentBeats(
            contacts: [
                MatchMomentContact(time: 0.55, hitter: .viewer, feel: .light),
                MatchMomentContact(time: returnHit, hitter: .player, feel: feel),
                MatchMomentContact(time: closingHit, hitter: .viewer, feel: feel)
            ],
            converge: closingHit + 0.05,
            landing: landing,
            cardsTouch: false
        )
    }
}

// MARK: - Rally

/// Everything that makes a rally feel like its sport: the ground, what flies, the path
/// it takes, how fast and how high it flies, and how hard each contact lands in the hand.
struct MatchMomentRally {
    enum Path {
        /// Back and forth over a net, then a lob onto the seal.
        case overNet
        /// Along the grass between the players' feet, then a chip onto the seal.
        case ground
        /// Every shot goes into the front wall and comes back to the other player.
        case offWall
    }

    let ground: MatchMomentGround
    let projectile: MatchMomentProjectile
    let path: Path
    let beats: MatchMomentBeats
    /// Arc height per leg of the path; the last one is the closing shot.
    let apex: [CGFloat]

    init?(sport: Sport) {
        switch sport {
        case .tennis:
            ground = .tennis
            projectile = .tennisBall
            path = .overNet
            beats = .exchange(returnHit: 0.83, closingHit: 1.09, landing: 1.47, feel: .rigid)
            apex = [92, 78, 150]
        case .padel:
            // Flatter and a touch quicker than tennis: the glass keeps rallies low.
            ground = .padel
            projectile = .padelBall
            path = .overNet
            beats = .exchange(returnHit: 0.8, closingHit: 1.05, landing: 1.42, feel: .rigid)
            apex = [64, 58, 150]
        case .badminton:
            // The shuttle floats high and brakes hard, so the rally is the slowest.
            ground = .badminton
            projectile = .shuttlecock
            path = .overNet
            beats = .exchange(returnHit: 0.95, closingHit: 1.33, landing: 1.76, feel: .soft)
            apex = [130, 118, 165]
        case .tableTennis:
            // Quick, low ticks across a small table.
            ground = .tableTennis
            projectile = .pingPong
            path = .overNet
            beats = .exchange(returnHit: 0.73, closingHit: 0.91, landing: 1.24, feel: .light)
            apex = [34, 30, 120]
        case .volleyball:
            ground = .volleyball
            projectile = .volleyball
            path = .overNet
            beats = .exchange(returnHit: 0.92, closingHit: 1.27, landing: 1.68, feel: .medium)
            apex = [120, 110, 165]
        case .football:
            // Two passes along the grass, barely leaving it, then a chip onto the seal.
            ground = .football
            projectile = .football
            path = .ground
            beats = .exchange(returnHit: 0.86, closingHit: 1.14, landing: 1.52, feel: .medium)
            apex = [5, 5, 145]
        case .squash:
            // Hit, wall, the other player: six contacts, the wall ones felt lighter.
            ground = .squash
            projectile = .squashBall
            path = .offWall
            beats = MatchMomentBeats(
                contacts: [
                    MatchMomentContact(time: 0.55, hitter: .viewer, feel: .rigid),
                    MatchMomentContact(time: 0.69, hitter: nil, feel: .light),
                    MatchMomentContact(time: 0.86, hitter: .player, feel: .rigid),
                    MatchMomentContact(time: 1.0, hitter: nil, feel: .light),
                    MatchMomentContact(time: 1.16, hitter: .viewer, feel: .rigid),
                    MatchMomentContact(time: 1.29, hitter: nil, feel: .light)
                ],
                converge: 1.21,
                landing: 1.54,
                cardsTouch: false
            )
            apex = [8, 36, 60]
        default:
            return nil
        }
    }

    /// The path in stage coordinates. Legs run back to back from the first contact to
    /// the landing, one per gap between contacts.
    func legs(on stage: MatchMomentStage) -> [MatchMomentLeg] {
        let times = beats.contacts.map(\.time) + [beats.landing]
        let landing = stage.landing
        let stops: [CGPoint]
        let heights: [CGFloat]
        switch path {
        case .overNet:
            stops = [stage.leftHit, stage.rightHit, stage.leftHit, landing]
            heights = apex
        case .ground:
            stops = [stage.leftFoot, stage.rightFoot, stage.leftFoot, landing]
            heights = apex
        case .offWall:
            let wall = stage.wallY
            stops = [
                stage.leftHit, CGPoint(x: -58, y: wall), stage.rightHit,
                CGPoint(x: 46, y: wall), stage.leftHit, CGPoint(x: -8, y: wall), landing
            ]
            // Flat into the wall, dropping on the way back, the last one onto the seal.
            heights = [apex[0], apex[1], apex[0], apex[1], apex[0], apex[2]]
        }
        return (0 ..< stops.count - 1).map { index in
            MatchMomentLeg(from: stops[index], to: stops[index + 1], start: times[index], end: times[index + 1], apex: heights[index])
        }
    }
}

struct MatchMomentLeg {
    let from: CGPoint
    let to: CGPoint
    let start: Double
    let end: Double
    let apex: CGFloat
}

struct MatchMomentFlight {
    let position: CGPoint
    let size: CGFloat
    /// Grows toward the apex, as if coming closer.
    let depth: CGFloat
    let rotation: Double
    let squash: CGSize
    let isInFlight: Bool

    static func state(at time: Double, stage: MatchMomentStage, rally: MatchMomentRally) -> MatchMomentFlight? {
        let kind = rally.projectile
        let legs = rally.legs(on: stage)
        let first = legs[0]
        let toss = 0.12
        guard time >= first.start - toss else { return nil }

        if time < first.start {
            // A ball at the feet is simply there; anything else is tossed up to be hit.
            let up = MatchMomentCurve.easeOut((time - first.start + toss) / toss)
            let lift: CGFloat = kind.rolls ? 0 : 18 * CGFloat(1 - up)
            return MatchMomentFlight(
                position: CGPoint(x: first.from.x, y: first.from.y + lift),
                size: kind.flightSize * CGFloat(up),
                depth: CGFloat(up),
                rotation: kind.isShuttle ? 90 : 0,
                squash: CGSize(width: 1, height: 1),
                isInFlight: false
            )
        }

        for leg in legs where time < leg.end {
            let u = (time - leg.start) / (leg.end - leg.start)
            let arc = CGFloat(4 * u * (1 - u))
            let depth = 1 + 0.22 * arc * min(leg.apex / 60, 1)
            let position = Self.position(on: leg, at: u, shuttle: kind.isShuttle)
            return MatchMomentFlight(
                position: position,
                size: kind.flightSize * depth,
                depth: depth,
                rotation: rotation(of: kind, at: time, position: position, leg: leg, u: u),
                squash: CGSize(width: 1, height: 1),
                isInFlight: true
            )
        }

        // Landed: a short hop, a squash that rings out, and it grows into the seal.
        // A shuttle doesn't squash; it swings round to stand cork down.
        let last = legs[legs.count - 1]
        let landed = time - last.end
        let ring = kind.isShuttle ? 0 : exp(-8 * landed) * cos(26 * landed)
        let hop = 10 * exp(-7 * landed) * abs(sin(11 * landed))
        let grow = MatchMomentCurve.spring(landed, response: 0.4, damping: 0.6)
        let settledRotation: Double
        if kind.isShuttle {
            let arrival = heading(on: last, at: 1)
            settledRotation = arrival + (90 - arrival) * MatchMomentCurve.spring(landed, response: 0.45, damping: 0.62)
        } else {
            let arrival = rotation(of: kind, at: last.end, position: last.to, leg: last, u: 1)
            settledRotation = arrival + 90 * (1 - exp(-5 * landed))
        }
        return MatchMomentFlight(
            position: CGPoint(x: last.to.x, y: last.to.y - hop),
            size: kind.flightSize + (kind.sealSize - kind.flightSize) * grow,
            depth: 1,
            rotation: settledRotation,
            squash: CGSize(width: 1 + 0.26 * ring, height: 1 - 0.22 * ring),
            isInFlight: false
        )
    }

    /// A shuttle points where it flies; a football turns as far as it rolls; balls spin.
    private static func rotation(of kind: MatchMomentProjectile, at time: Double, position: CGPoint, leg: MatchMomentLeg, u: Double) -> Double {
        if kind.isShuttle { return heading(on: leg, at: u) }
        if kind.rolls { return Double(position.x) * 360 / (Double.pi * Double(kind.flightSize)) }
        return time * 720
    }

    /// Balls cross at constant speed under a parabola, so they read as thrown, not
    /// tweened. A shuttle leaves fast and brakes, so its fall comes steeply at the end.
    private static func position(on leg: MatchMomentLeg, at u: Double, shuttle: Bool) -> CGPoint {
        let across = shuttle ? 1 - (1 - u) * (1 - u) : u
        let arc = CGFloat(4 * u * (1 - u))
        let x = leg.from.x + (leg.to.x - leg.from.x) * CGFloat(across)
        let y = leg.from.y + (leg.to.y - leg.from.y) * CGFloat(u) - leg.apex * arc
        return CGPoint(x: x, y: y)
    }

    /// Direction of travel in degrees, for a shuttle whose cork leads.
    private static func heading(on leg: MatchMomentLeg, at u: Double) -> Double {
        let dx = Double(leg.to.x - leg.from.x) * 2 * (1 - u)
        let dy = Double(leg.to.y - leg.from.y) - Double(leg.apex) * (4 - 8 * u)
        return atan2(dy, max(abs(dx), 0.001) * (dx < 0 ? -1 : 1)) * 180 / .pi
    }
}

// MARK: - Ground

enum MatchMomentGround {
    case tennis, padel, badminton, tableTennis, volleyball, squash, football, track, ring, gym, mat, water

    /// Length over width, laid sideways with the net (or halfway line) upright. Net
    /// sports use their real proportions; the rest are shaped to sit under the cards.
    var aspect: CGFloat {
        switch self {
        case .tennis: return 23.77 / 10.97
        case .padel: return 20 / 10
        case .badminton: return 13.4 / 6.1
        case .tableTennis: return 2.74 / 1.525
        case .volleyball: return 18 / 9
        case .squash: return 2.1
        case .football: return 105 / 68
        case .track: return 2.2
        case .ring: return 2
        case .gym: return 2.2
        case .mat: return 3
        case .water: return 2
        }
    }

    var surface: Color {
        switch self {
        case .tennis: return AppTheme.court
        case .padel: return Color(red: 0.16, green: 0.38, blue: 0.66)
        case .badminton: return Color(red: 0.12, green: 0.46, blue: 0.4)
        case .tableTennis: return Color(red: 0.12, green: 0.3, blue: 0.56)
        case .volleyball: return AppTheme.clay
        case .squash: return Color(red: 0.78, green: 0.62, blue: 0.4)
        case .football: return Color(red: 0.16, green: 0.5, blue: 0.24)
        case .track: return Color(red: 0.74, green: 0.3, blue: 0.22)
        case .ring: return Color(red: 0.86, green: 0.83, blue: 0.76)
        case .gym: return Color(white: 0.34)
        case .mat: return Color(red: 0.5, green: 0.4, blue: 0.68)
        case .water: return Color(red: 0.12, green: 0.45, blue: 0.68)
        }
    }

    /// A table's white edges and a ring's ropes are part of what makes them read.
    var lineOpacity: Double {
        switch self {
        case .tableTennis, .ring: return 0.5
        case .gym: return 0.12
        case .mat: return 0.3
        default: return 0.2
        }
    }

    var lineWidth: CGFloat { self == .tableTennis ? 2.5 : 1.5 }

    /// Only net sports have a net; football's halfway line is part of its markings.
    var netWidth: CGFloat? {
        switch self {
        case .tennis, .padel, .badminton, .tableTennis: return 2.5
        case .volleyball: return 3.5
        case .squash, .football, .track, .ring, .gym, .mat, .water: return nil
        }
    }
}

/// Each ground turned sideways with its markings; net sports in real proportions.
struct MatchMomentGroundLines: Shape {
    let ground: MatchMomentGround

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch ground {
        case .water:
            // Its lines are the waves, which move; see `MatchMomentWaves`.
            return path
        case .mat:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height * 0.18, height: rect.height * 0.18))
        default:
            path.addRect(rect)
        }
        switch ground {
        case .tennis:
            let singlesInset = rect.height * (10.97 - 8.23) / 2 / 10.97
            let serviceOffset = rect.width / 2 * 6.40 / 11.885
            Self.horizontal(&path, rect, y: rect.minY + singlesInset)
            Self.horizontal(&path, rect, y: rect.maxY - singlesInset)
            Self.vertical(&path, x: rect.midX - serviceOffset, from: rect.minY + singlesInset, to: rect.maxY - singlesInset)
            Self.vertical(&path, x: rect.midX + serviceOffset, from: rect.minY + singlesInset, to: rect.maxY - singlesInset)
            Self.centre(&path, rect, from: rect.midX - serviceOffset, to: rect.midX + serviceOffset)
            for (x, direction) in [(rect.minX, 1.0), (rect.maxX, -1.0)] {
                path.move(to: CGPoint(x: x, y: rect.midY))
                path.addLine(to: CGPoint(x: x + 6 * direction, y: rect.midY))
            }
        case .padel:
            let serviceOffset = rect.width / 2 * 6.95 / 10
            Self.vertical(&path, x: rect.midX - serviceOffset, from: rect.minY, to: rect.maxY)
            Self.vertical(&path, x: rect.midX + serviceOffset, from: rect.minY, to: rect.maxY)
            Self.centre(&path, rect, from: rect.midX - serviceOffset, to: rect.midX + serviceOffset)
        case .badminton:
            let singlesInset = rect.height * 0.46 / 6.1
            let shortService = rect.width / 2 * 1.98 / 6.7
            let longService = rect.width * 0.76 / 13.4
            Self.horizontal(&path, rect, y: rect.minY + singlesInset)
            Self.horizontal(&path, rect, y: rect.maxY - singlesInset)
            for x in [rect.midX - shortService, rect.midX + shortService, rect.minX + longService, rect.maxX - longService] {
                Self.vertical(&path, x: x, from: rect.minY, to: rect.maxY)
            }
            Self.centre(&path, rect, from: rect.minX, to: rect.midX - shortService)
            Self.centre(&path, rect, from: rect.midX + shortService, to: rect.maxX)
        case .tableTennis:
            Self.centre(&path, rect, from: rect.minX, to: rect.maxX)
        case .volleyball:
            let attack = rect.width / 2 * 3 / 9
            Self.vertical(&path, x: rect.midX - attack, from: rect.minY, to: rect.maxY)
            Self.vertical(&path, x: rect.midX + attack, from: rect.minY, to: rect.maxY)
        case .squash:
            // Front wall is above the floor; here the short line, the half-court line
            // behind it and the two service boxes.
            let shortLine = rect.minY + rect.height * 0.42
            let box = rect.height * 0.3
            Self.horizontal(&path, rect, y: shortLine)
            Self.vertical(&path, x: rect.midX, from: shortLine, to: rect.maxY)
            path.addRect(CGRect(x: rect.minX, y: shortLine, width: box, height: box))
            path.addRect(CGRect(x: rect.maxX - box, y: shortLine, width: box, height: box))
        case .football:
            let penaltyDepth = rect.width * 16.5 / 105
            let penaltyWidth = rect.height * 40.32 / 68
            let goalAreaDepth = rect.width * 5.5 / 105
            let goalAreaWidth = rect.height * 18.32 / 68
            let goalWidth = rect.height * 7.32 / 68
            let circle = rect.height * 9.15 / 68
            Self.vertical(&path, x: rect.midX, from: rect.minY, to: rect.maxY)
            path.addEllipse(in: CGRect(x: rect.midX - circle, y: rect.midY - circle, width: circle * 2, height: circle * 2))
            for (edge, inward) in [(rect.minX, 1.0), (rect.maxX, -1.0)] {
                let penaltyX = inward > 0 ? edge : edge - penaltyDepth
                let goalAreaX = inward > 0 ? edge : edge - goalAreaDepth
                let goalX = inward > 0 ? edge - 6 : edge
                path.addRect(CGRect(x: penaltyX, y: rect.midY - penaltyWidth / 2, width: penaltyDepth, height: penaltyWidth))
                path.addRect(CGRect(x: goalAreaX, y: rect.midY - goalAreaWidth / 2, width: goalAreaDepth, height: goalAreaWidth))
                path.addRect(CGRect(x: goalX, y: rect.midY - goalWidth / 2, width: 6, height: goalWidth))
            }
        case .track:
            // Lanes, and the finish line where the tape is stretched.
            for lane in 1 ... 3 {
                Self.horizontal(&path, rect, y: rect.minY + rect.height * CGFloat(lane) / 4)
            }
            Self.vertical(&path, x: rect.midX, from: rect.minY, to: rect.maxY)
        case .ring:
            // Three ropes inside the apron.
            for inset in [CGFloat(9), 18] {
                path.addRoundedRect(in: rect.insetBy(dx: inset, dy: inset), cornerSize: CGSize(width: 4, height: 4))
            }
        case .gym:
            // Rubber floor tiles.
            for column in 1 ..< 6 {
                Self.vertical(&path, x: rect.minX + rect.width * CGFloat(column) / 6, from: rect.minY, to: rect.maxY)
            }
            for row in 1 ..< 3 {
                Self.horizontal(&path, rect, y: rect.minY + rect.height * CGFloat(row) / 3)
            }
        case .mat:
            // The mat's end stripes.
            for x in [rect.minX + rect.width * 0.09, rect.maxX - rect.width * 0.09] {
                Self.vertical(&path, x: x, from: rect.minY + 10, to: rect.maxY - 10)
            }
        case .water:
            break
        }
        return path
    }

    private static func horizontal(_ path: inout Path, _ rect: CGRect, y: CGFloat) {
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
    }

    private static func vertical(_ path: inout Path, x: CGFloat, from top: CGFloat, to bottom: CGFloat) {
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
    }

    private static func centre(_ path: inout Path, _ rect: CGRect, from left: CGFloat, to right: CGFloat) {
        path.move(to: CGPoint(x: left, y: rect.midY))
        path.addLine(to: CGPoint(x: right, y: rect.midY))
    }
}

/// Rows of waves drifting across the water, alternate rows the other way.
struct MatchMomentWaves: Shape {
    let phase: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = 4
        let wavelength = 72.0
        for row in 0 ..< rows {
            let y = rect.minY + rect.height * (CGFloat(row) + 0.5) / CGFloat(rows)
            let drift = phase * 38 * (row.isMultiple(of: 2) ? 1 : -0.7) + Double(row) * 23
            var x = rect.minX
            func crest(_ x: CGFloat) -> CGFloat {
                y + 4 * CGFloat(sin((Double(x) + drift) / wavelength * 2 * .pi))
            }
            path.move(to: CGPoint(x: x, y: crest(x)))
            while x < rect.maxX {
                x = min(x + 6, rect.maxX)
                path.addLine(to: CGPoint(x: x, y: crest(x)))
            }
        }
        return path
    }
}

// MARK: - Projectiles

enum MatchMomentProjectile {
    case tennisBall, padelBall, shuttlecock, pingPong, volleyball, football, squashBall

    var flightSize: CGFloat {
        switch self {
        case .tennisBall: return 32
        case .padelBall, .shuttlecock: return 30
        case .pingPong, .squashBall: return 18
        case .volleyball, .football: return 34
        }
    }

    /// The size it grows to once it lands as the seal between the cards.
    var sealSize: CGFloat {
        switch self {
        case .tennisBall: return 46
        case .padelBall, .shuttlecock: return 44
        case .pingPong, .squashBall: return 34
        case .volleyball, .football: return 48
        }
    }

    /// Glow, trail and landing rings take the colour of what flew; a black squash ball
    /// would vanish, so it borrows the brand yellow.
    var accent: Color {
        switch self {
        case .tennisBall, .padelBall, .squashBall: return MatchMomentPalette.ball
        case .shuttlecock, .pingPong, .football: return .white
        case .volleyball: return MatchMomentPalette.volleyballYellow
        }
    }

    /// A shuttle points where it flies and lands cork down; balls spin and squash.
    var isShuttle: Bool { self == .shuttlecock }
    /// A football rests at the feet and turns as it rolls instead of spinning in the air.
    var rolls: Bool { self == .football }
}

struct MatchMomentProjectileView: View {
    let kind: MatchMomentProjectile
    let size: CGFloat

    var body: some View {
        switch kind {
        case .tennisBall, .padelBall:
            TennisBallIcon()
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .scaleEffect(size / 26)
        case .pingPong:
            Circle()
                .fill(RadialGradient(colors: [.white, Color(white: 0.8)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                .frame(width: size, height: size)
        case .volleyball:
            MatchMomentVolleyball()
                .frame(width: size, height: size)
        case .shuttlecock:
            MatchMomentShuttlecock()
                .frame(width: size * 1.25, height: size * 0.8)
        case .football:
            ZStack {
                Circle().fill(Color.white)
                Image(systemName: "soccerball")
                    .resizable()
                    .foregroundStyle(Color(white: 0.12))
            }
            .frame(width: size, height: size)
        case .squashBall:
            ZStack {
                Circle().fill(Color(white: 0.1))
                ForEach([CGPoint(x: -0.18, y: -0.16), CGPoint(x: 0.2, y: 0.14)], id: \.x) { dot in
                    Circle()
                        .fill(MatchMomentPalette.volleyballYellow)
                        .frame(width: size * 0.18, height: size * 0.18)
                        .offset(x: dot.x * size, y: dot.y * size)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

/// White ball with a yellow and a blue panel band, spun by its rotation.
struct MatchMomentVolleyball: View {
    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                Circle().fill(Color(white: 0.97))
                Ellipse()
                    .stroke(MatchMomentPalette.volleyballYellow, lineWidth: side * 0.18)
                    .frame(width: side * 1.3, height: side * 0.7)
                    .offset(y: -side * 0.42)
                Ellipse()
                    .stroke(MatchMomentPalette.volleyballBlue, lineWidth: side * 0.18)
                    .frame(width: side * 1.3, height: side * 0.7)
                    .offset(y: side * 0.42)
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
        }
    }
}

/// Feathered skirt trailing a cork, drawn pointing right; rotation aims it along the flight.
struct MatchMomentShuttlecock: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.66, y: height * 0.34))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width * 0.66, y: height * 0.66))
                    path.closeSubpath()
                }
                .fill(Color.white)

                Path { path in
                    for fraction in [0.2, 0.5, 0.8] {
                        path.move(to: CGPoint(x: width * 0.66, y: height * (0.34 + 0.32 * fraction)))
                        path.addLine(to: CGPoint(x: 0, y: height * fraction))
                    }
                }
                .stroke(Color.black.opacity(0.14), lineWidth: 1)

                Circle()
                    .fill(Color(red: 0.96, green: 0.93, blue: 0.86))
                    .overlay(Circle().stroke(AppTheme.clay, lineWidth: 2))
                    .frame(width: height * 0.46, height: height * 0.46)
                    .position(x: width * 0.78, y: height / 2)
            }
        }
    }
}

/// A boxing glove drawn punching right: cuff, fist, thumb, a highlight.
struct MatchMomentGlove: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 13, height: 24)
                .offset(x: -17)
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.black.opacity(0.2), lineWidth: 1))
                .frame(width: 38, height: 32)
                .offset(x: 3)
            Capsule()
                .fill(color)
                .overlay(Capsule().stroke(Color.black.opacity(0.22), lineWidth: 1))
                .frame(width: 17, height: 10)
                .offset(x: 1, y: -12)
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 11, height: 4)
                .offset(x: 12, y: -6)
        }
        .frame(width: 50, height: 36)
    }
}

/// Bar with a bumper, a smaller plate and a collar on each side; the plates droop by
/// `bend` so the catch and the lockout ring through the bar.
struct MatchMomentBarbell: View {
    let bend: CGFloat

    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.88), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 292, height: 6)
            ForEach([-1.0, 1.0], id: \.self) { side in
                let s = CGFloat(side)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MatchMomentPalette.ball)
                    .frame(width: 14, height: 58)
                    .offset(x: s * 133, y: bend)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(AppTheme.clay)
                    .frame(width: 10, height: 42)
                    .offset(x: s * 121, y: bend * 0.8)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(white: 0.8))
                    .frame(width: 6, height: 16)
                    .offset(x: s * 112, y: bend * 0.6)
            }
        }
        .frame(width: 300, height: 70)
    }
}

// MARK: - Copy

/// Copy says what the two will actually do together, and where.
struct MatchMomentCopy {
    let title: String
    let subtitle: String
    let action: String
    /// Headline once a game in this sport is agreed.
    let confirmed: String

    init(sport: Sport) {
        let venue: (en: String, ru: String)
        switch sport {
        case .tennis, .padel, .squash, .badminton: venue = ("court", "корте")
        case .volleyball: venue = ("court", "площадке")
        case .football: venue = ("pitch", "поле")
        case .running: venue = ("route", "маршруте")
        case .fitness, .boxing: venue = ("gym", "зале")
        case .tableTennis, .yoga, .supboard: venue = ("place", "месте")
        }
        subtitle = L10n.string("Now agree on a time and a \(venue.en).", "Осталось договориться о времени и \(venue.ru).")

        switch sport {
        case .running:
            title = L10n.string("You both want to run", "Вы оба хотите побегать")
            action = L10n.string("Plan the run", "Договориться о пробежке")
            confirmed = L10n.string("Run confirmed", "Пробежка подтверждена")
        case .fitness, .boxing:
            title = L10n.string("You both want to train", "Вы оба хотите потренироваться")
            action = L10n.string("Plan the session", "Договориться о тренировке")
            confirmed = L10n.string("Session confirmed", "Тренировка подтверждена")
        case .yoga:
            title = L10n.string("You both want to practice", "Вы оба хотите позаниматься")
            action = L10n.string("Plan the class", "Договориться о занятии")
            confirmed = L10n.string("Class confirmed", "Занятие подтверждено")
        case .supboard:
            title = L10n.string("You both want to paddle", "Вы оба хотите покататься на сапе")
            action = L10n.string("Plan the trip", "Договориться о прогулке")
            confirmed = L10n.string("Trip confirmed", "Прогулка подтверждена")
        case .tennis, .padel, .squash, .badminton, .tableTennis, .volleyball, .football:
            title = L10n.string("You both want to play", "Вы оба хотите сыграть")
            action = L10n.string("Plan the game", "Договориться об игре")
            confirmed = L10n.string("Game confirmed", "Игра подтверждена")
        }
    }
}

// MARK: - Stage

enum MatchMomentSide {
    case viewer
    case player

    var sign: Double { self == .viewer ? -1 : 1 }
    var entrance: Double { self == .viewer ? 0.05 : 0.12 }

    /// When this card strikes, plus the moment the two cards collide when they do.
    func hits(in beats: MatchMomentBeats) -> [Double] {
        let strikes = beats.contacts.filter { $0.hitter == self }.map(\.time)
        return beats.cardsTouch ? strikes + [beats.landing] : strikes
    }
}

struct MatchMomentStage {
    static let card = CGSize(width: 116, height: 148)

    let center: CGPoint
    let court: CGSize
    let baselineX: CGFloat
    let offstageX: CGFloat
    let copyTop: CGFloat

    init(size: CGSize, groundAspect: CGFloat) {
        let courtWidth = min(size.width - 24, 380)
        court = CGSize(width: courtWidth, height: courtWidth / groundAspect)
        // Centre the settled picture (seal, court, copy ≈ 330 pt) in the space above the
        // actions; the highest lob still needs ~210 pt of headroom on short screens.
        let settledAboveCenter: CGFloat = 96
        let settledHeight = settledAboveCenter + court.height / 2 + 40 + 110
        let centerY = max(230, (size.height - 120 - settledHeight) / 2 + settledAboveCenter)
        center = CGPoint(x: size.width / 2, y: centerY)
        copyTop = centerY + court.height / 2 + 40
        baselineX = courtWidth / 2 - Self.card.width / 2 - 4
        offstageX = size.width / 2 + Self.card.width
    }

    /// Struck off the card's inner top corner, so the card reads as the racket.
    var leftHit: CGPoint { CGPoint(x: -baselineX + Self.card.width / 2 - 2, y: -44) }
    var rightHit: CGPoint { CGPoint(x: baselineX - Self.card.width / 2 + 2, y: -44) }
    /// Kicked off the card's inner bottom corner, along the grass.
    var leftFoot: CGPoint { CGPoint(x: -baselineX + Self.card.width / 2 + 4, y: 58) }
    var rightFoot: CGPoint { CGPoint(x: baselineX - Self.card.width / 2 - 4, y: 58) }
    /// The squash front wall's face, well above the cards.
    var wallY: CGFloat { -court.height / 2 - 58 }
    /// The gap between the two cards' top corners once they meet.
    var landing: CGPoint { CGPoint(x: 0, y: -Self.card.height / 2 + 4) }

    func point(_ offset: CGPoint) -> CGPoint {
        CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }
}

// MARK: - Shared pieces

struct MatchMomentParticle: Identifiable {
    enum Kind {
        /// Thrown up from the seal and pulled down by gravity.
        case confetti
        /// Heavier water drops, all round.
        case splash
        /// Light motes that rise slowly, sway and fade in and out.
        case mote
    }

    let id: Int
    let kind: Kind
    let angle: Double
    let speed: Double
    let spin: Double
    let delay: Double
    let size: CGSize
    let color: Color
    let isRound: Bool

    var lifetime: Double {
        switch kind {
        case .confetti: return 1
        case .splash: return 0.9
        case .mote: return 1.8
        }
    }

    func offset(at age: Double, from origin: CGPoint) -> CGPoint {
        switch kind {
        case .confetti, .splash:
            let travel = speed * age
            let fall = 0.5 * (kind == .splash ? 900 : 640) * age * age
            return CGPoint(x: origin.x + cos(angle) * travel, y: origin.y + sin(angle) * travel + fall)
        case .mote:
            // Spread along the cards, then up with a slow sway.
            let sway = 8 * sin(age * 3 + Double(id))
            return CGPoint(x: origin.x + cos(angle) * 90 + sway, y: origin.y - speed * age)
        }
    }

    func opacity(at age: Double) -> Double {
        let fadeStart = 0.55 * lifetime
        let fadeOut = 1 - max(0, age - fadeStart) / (lifetime - fadeStart)
        return kind == .mote ? min(age / 0.3, 1) * fadeOut : fadeOut
    }

    /// Seeded, so every match bursts the same way and screenshots stay comparable.
    private static func seeded(_ start: UInt64) -> () -> Double {
        var seed = start
        return {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(UInt64(1) << 31)
        }
    }

    static let confetti: [MatchMomentParticle] = {
        let next = seeded(0x5EED_BA11)
        let palette = [MatchMomentPalette.ball, AppTheme.clay, AppTheme.mint, AppTheme.creamLight, MatchMomentPalette.ball]
        return (0 ..< 18).map { index in
            let isRound = index % 3 == 0
            let length = 8 + 8 * next()
            return MatchMomentParticle(
                id: index,
                kind: .confetti,
                angle: -Double.pi * (0.06 + 0.88 * next()),
                speed: 190 + 170 * next(),
                spin: (next() - 0.5) * 900,
                delay: 0.12 * next(),
                size: isRound ? CGSize(width: 7, height: 7) : CGSize(width: length * 0.55, height: length),
                color: palette[index % palette.count],
                isRound: isRound
            )
        }
    }()

    static let splash: [MatchMomentParticle] = {
        let next = seeded(0x5A1_5A5)
        let palette = [Color.white, MatchMomentPalette.water, Color(red: 0.7, green: 0.93, blue: 1)]
        return (0 ..< 16).map { index in
            let drop = 5 + 4 * next()
            return MatchMomentParticle(
                id: index,
                kind: .splash,
                angle: -Double.pi * (0.18 + 0.64 * next()),
                speed: 170 + 170 * next(),
                spin: 0,
                delay: 0.06 * next(),
                size: CGSize(width: drop, height: drop),
                color: palette[index % palette.count],
                isRound: true
            )
        }
    }()

    static let motes: [MatchMomentParticle] = {
        let next = seeded(0xB4EA_7E)
        let palette = [AppTheme.mint, AppTheme.creamLight, MatchMomentPalette.ball.opacity(0.8)]
        return (0 ..< 14).map { index in
            let mote = 4 + 4 * next()
            return MatchMomentParticle(
                id: index,
                kind: .mote,
                angle: Double.pi * next(),
                speed: 45 + 40 * next(),
                spin: 0,
                delay: 0.25 * next(),
                size: CGSize(width: mote, height: mote),
                color: palette[index % palette.count],
                isRound: true
            )
        }
    }()
}

enum MatchMomentCurve {
    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func easeOut(_ value: Double) -> Double {
        let t = clamp(value)
        return 1 - pow(1 - t, 3)
    }

    static func easeInOut(_ value: Double) -> Double {
        let t = clamp(value)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Pulls back a little before it goes: a wind-up.
    static func anticipate(_ value: Double) -> Double {
        let t = clamp(value)
        let overshoot = 1.7
        return t * t * ((overshoot + 1) * t - overshoot)
    }

    /// Closed-form underdamped spring from 0 to 1, parameterised like SwiftUI's
    /// `.spring(response:dampingFraction:)` so the numbers mean the same thing.
    static func spring(_ elapsed: Double, response: Double, damping: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let decay = damping * omega
        let damped = omega * sqrt(1 - damping * damping)
        return 1 - exp(-decay * elapsed) * (cos(damped * elapsed) + decay / damped * sin(damped * elapsed))
    }

    /// A struck-and-released impulse: rises within ~60 ms, overshoots once, dies out.
    static func bump(_ elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed < 0.8 else { return 0 }
        return exp(-9 * elapsed) * sin(24 * elapsed)
    }
}

enum MatchMomentPalette {
    static let ball = Color(red: 0.84, green: 0.98, blue: 0.34)
    static let eyebrow = Color(red: 0.76, green: 0.97, blue: 0.80)
    static let volleyballYellow = Color(red: 0.98, green: 0.8, blue: 0.22)
    static let volleyballBlue = Color(red: 0.16, green: 0.36, blue: 0.74)
    static let redCorner = Color(red: 0.86, green: 0.24, blue: 0.2)
    static let blueCorner = Color(red: 0.2, green: 0.42, blue: 0.86)
    static let water = Color(red: 0.45, green: 0.8, blue: 1)
    static let viewerCard = [AppTheme.court, Color(red: 0.1, green: 0.3, blue: 0.23)]
    static let playerCard = [AppTheme.clay, Color(red: 0.52, green: 0.25, blue: 0.15)]
}

struct MatchMomentCard: View {
    static let cornerRadius: CGFloat = 26

    let name: String
    let caption: String
    let imagePath: String?
    let tint: [Color]

    var body: some View {
        RemoteImage(url: resolveAppRemoteURL(imagePath), indicator: .shimmer(.white.opacity(0.6))) { _ in
            ZStack {
                LinearGradient(colors: tint, startPoint: .topLeading, endPoint: .bottomTrailing)
                Group {
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40, weight: .semibold))
                    } else {
                        Text(initials)
                            .font(.system(size: 42, weight: .black, design: .rounded))
                    }
                }
                .foregroundStyle(.white.opacity(0.92))
                .offset(y: -10)
            }
        }
        .frame(width: MatchMomentStage.card.width, height: MatchMomentStage.card.height)
        .overlay(alignment: .bottom) {
            Text(caption)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.top, 22)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 12)
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

struct MatchMomentReveal: ViewModifier {
    let time: Double
    let start: Double

    func body(content: Content) -> some View {
        let progress = MatchMomentCurve.easeOut((time - start) / 0.42)
        content
            .opacity(progress)
            .offset(y: 16 * (1 - progress))
    }
}

struct MatchMomentPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(MatchMomentPalette.ball, in: Capsule())
            .shadow(color: MatchMomentPalette.ball.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 18, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
