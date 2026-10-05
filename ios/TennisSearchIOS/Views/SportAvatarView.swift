import SwiftUI

/// A small person doing the sport, drawn in a 120 × 120 box. It stands in for a photo until
/// the player adds one, chosen by the first sport they picked.
struct SportAvatarView: View {
    let sport: Sport

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 120
            var drawing = context
            drawing.translateBy(x: (size.width - 120 * scale) / 2, y: (size.height - 120 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            SportAvatarFigure.draw(sport, in: &drawing)
        }
        .accessibilityHidden(true)
    }
}

enum SportAvatarFigure {
    private static let skin = Color(red: 0.94, green: 0.78, blue: 0.63)
    private static let hair = Color(red: 0.23, green: 0.16, blue: 0.125)
    private static let shirt = Color(red: 0.84, green: 0.98, blue: 0.34)
    private static let legs = Color(red: 0.81, green: 0.91, blue: 0.86)
    private static let white = Color.white
    private static let red = Color(red: 0.88, green: 0.28, blue: 0.25)
    private static let orange = Color(red: 0.94, green: 0.63, blue: 0.24)

    static func draw(_ sport: Sport, in ctx: inout GraphicsContext) {
        switch sport {
        case .tennis:
            body(&ctx, headAt: (58, 26), torsoFrom: (58, 40), to: (56, 68), backArm: [(58, 44), (46, 56), (40, 66)],
                 legsA: [(56, 68), (44, 90), (40, 108)], legsB: [(56, 68), (70, 88), (78, 108)])
            arm(&ctx, [(60, 44), (76, 46), (86, 36)])
            line(&ctx, (86, 36), (94, 28), white, 3)
            ring(&ctx, center: (101, 19), rx: 9, ry: 12, degrees: 40, width: 3)
            dot(&ctx, (106, 56), 4.5, shirt)
        case .padel:
            rect(&ctx, x: 112, y: 10, w: 4, h: 98, fill: white.opacity(0.22))
            body(&ctx, headAt: (58, 26), torsoFrom: (58, 40), to: (56, 68), backArm: [(58, 44), (46, 56), (40, 66)],
                 legsA: [(56, 68), (44, 90), (40, 108)], legsB: [(56, 68), (70, 88), (78, 108)])
            arm(&ctx, [(60, 44), (76, 46), (86, 36)])
            line(&ctx, (86, 36), (92, 30), white, 4)
            rect(&ctx, x: 88, y: 8, w: 20, h: 26, radius: 10, degrees: 35, about: (98, 21), fill: orange)
            dot(&ctx, (102, 60), 4.5, shirt)
        case .tableTennis:
            body(&ctx, headAt: (60, 26), torsoFrom: (60, 40), to: (58, 68), backArm: [(60, 44), (48, 58), (46, 68)],
                 legsA: [(58, 68), (50, 90), (48, 108)], legsB: [(58, 68), (66, 90), (70, 108)])
            let blue = Color(red: 0.18, green: 0.435, blue: 0.745)
            rect(&ctx, x: 14, y: 82, w: 92, h: 6, radius: 2, fill: blue)
            line(&ctx, (22, 88), (22, 108), blue, 4)
            line(&ctx, (98, 88), (98, 108), blue, 4)
            line(&ctx, (60, 76), (60, 82), white, 2)
            arm(&ctx, [(62, 44), (78, 54), (86, 62)])
            dot(&ctx, (93, 58), 7.5, red)
            line(&ctx, (88, 63), (84, 68), white, 3)
            dot(&ctx, (104, 44), 3.5, white)
        case .badminton:
            body(&ctx, headAt: (58, 26), torsoFrom: (58, 40), to: (56, 68), backArm: [(58, 44), (46, 56), (40, 66)],
                 legsA: [(56, 68), (44, 90), (40, 108)], legsB: [(56, 68), (70, 88), (78, 108)])
            arm(&ctx, [(60, 44), (74, 38), (82, 28)])
            line(&ctx, (82, 28), (88, 20), white, 2.5)
            ring(&ctx, center: (94, 11), rx: 6.5, ry: 10, degrees: 40, width: 2.5)
            dot(&ctx, (106, 52), 3.5, white)
            var feathers = Path()
            feathers.addLines([CGPoint(x: 106, y: 52), CGPoint(x: 116, y: 46), CGPoint(x: 114, y: 58)])
            feathers.closeSubpath()
            ctx.fill(feathers, with: .color(white.opacity(0.85)))
        case .squash:
            rect(&ctx, x: 112, y: 8, w: 4, h: 100, fill: white.opacity(0.22))
            body(&ctx, headAt: (60, 26), torsoFrom: (58, 40), to: (50, 66), backArm: [(58, 48), (46, 56), (40, 52)],
                 legsA: [(50, 66), (34, 88), (20, 106)], legsB: [(50, 66), (74, 78), (76, 106)])
            arm(&ctx, [(58, 48), (78, 60), (92, 72)])
            line(&ctx, (92, 72), (98, 80), white, 3)
            ring(&ctx, center: (103, 90), rx: 7, ry: 10, degrees: -35, width: 3)
            dot(&ctx, (100, 56), 4, shirt)
        case .volleyball:
            arm(&ctx, [(58, 46), (47, 30), (50, 16)])
            arm(&ctx, [(58, 46), (69, 30), (66, 16)])
            leg(&ctx, [(58, 70), (47, 90), (45, 108)])
            leg(&ctx, [(58, 70), (69, 90), (71, 108)])
            line(&ctx, (58, 44), (58, 70), shirt, 18)
            head(&ctx, (58, 32))
            dot(&ctx, (58, 9), 9, Color(red: 0.96, green: 0.85, blue: 0.35))
            var seams = Path()
            seams.move(to: CGPoint(x: 50, y: 5)); seams.addQuadCurve(to: CGPoint(x: 66, y: 5), control: CGPoint(x: 58, y: 11))
            seams.move(to: CGPoint(x: 50, y: 13)); seams.addQuadCurve(to: CGPoint(x: 66, y: 13), control: CGPoint(x: 58, y: 7))
            ctx.stroke(seams, with: .color(Color(red: 0.18, green: 0.435, blue: 0.75)), lineWidth: 2)
        case .fitness:
            arm(&ctx, [(56, 46), (46, 32), (42, 20)])
            arm(&ctx, [(60, 46), (70, 32), (74, 20)])
            leg(&ctx, [(58, 70), (44, 90), (40, 108)])
            leg(&ctx, [(58, 70), (72, 90), (76, 108)])
            line(&ctx, (58, 44), (58, 70), shirt, 18)
            head(&ctx, (58, 32))
            line(&ctx, (20, 18), (98, 18), white, 4)
            rect(&ctx, x: 16, y: 6, w: 7, h: 24, radius: 2, fill: red)
            rect(&ctx, x: 95, y: 6, w: 7, h: 24, radius: 2, fill: red)
            rect(&ctx, x: 24, y: 10, w: 5, h: 16, radius: 2, fill: red.opacity(0.75))
            rect(&ctx, x: 89, y: 10, w: 5, h: 16, radius: 2, fill: red.opacity(0.75))
        case .boxing:
            leg(&ctx, [(56, 68), (44, 90), (34, 106)])
            leg(&ctx, [(56, 68), (68, 88), (74, 108)])
            line(&ctx, (56, 40), (56, 68), shirt, 18)
            head(&ctx, (56, 26))
            arm(&ctx, [(58, 46), (64, 60), (74, 54)])
            dot(&ctx, (79, 52), 8.5, red)
            arm(&ctx, [(60, 44), (72, 52), (82, 40)])
            dot(&ctx, (87, 37), 9, red)
        case .yoga:
            rect(&ctx, x: 24, y: 104, w: 72, h: 7, radius: 3.5, fill: Color(red: 0.56, green: 0.44, blue: 0.82))
            leg(&ctx, [(58, 70), (58, 90), (58, 104)])
            leg(&ctx, [(58, 72), (78, 82), (62, 90)])
            line(&ctx, (58, 44), (58, 70), shirt, 18)
            arm(&ctx, [(56, 48), (46, 32), (56, 14)])
            arm(&ctx, [(60, 48), (70, 32), (60, 14)])
            head(&ctx, (58, 32))
        case .football:
            line(&ctx, (8, 110), (112, 110), Color(red: 0.18, green: 0.48, blue: 0.396), 5)
            arm(&ctx, [(56, 46), (40, 54), (32, 50)])
            leg(&ctx, [(54, 68), (52, 90), (50, 108)])
            leg(&ctx, [(54, 68), (74, 76), (90, 68)])
            line(&ctx, (58, 40), (54, 68), shirt, 18)
            head(&ctx, (58, 26))
            arm(&ctx, [(58, 46), (76, 42), (86, 48)])
            dot(&ctx, (102, 66), 8, white)
            dot(&ctx, (102, 66), 3, Color(red: 0.055, green: 0.165, blue: 0.13))
        case .running:
            line(&ctx, (6, 46), (26, 46), white.opacity(0.35), 3)
            line(&ctx, (10, 58), (28, 58), white.opacity(0.35), 3)
            line(&ctx, (4, 70), (22, 70), white.opacity(0.35), 3)
            arm(&ctx, [(62, 46), (48, 54), (42, 66)])
            leg(&ctx, [(54, 68), (38, 84), (24, 96)])
            leg(&ctx, [(54, 68), (72, 80), (72, 104)])
            line(&ctx, (64, 40), (54, 68), shirt, 18)
            head(&ctx, (68, 26))
            arm(&ctx, [(64, 46), (78, 56), (88, 46)])
            line(&ctx, (20, 110), (104, 110), white.opacity(0.3), 3)
        case .supboard:
            ctx.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: CGRect(x: 3, y: 3, width: 114, height: 114)))
                var water = Path()
                water.move(to: CGPoint(x: 0, y: 104))
                for index in 0 ..< 6 {
                    let x = CGFloat(index) * 20
                    water.addQuadCurve(to: CGPoint(x: x + 20, y: 104), control: CGPoint(x: x + 10, y: index.isMultiple(of: 2) ? 98 : 110))
                }
                water.addLine(to: CGPoint(x: 120, y: 120))
                water.addLine(to: CGPoint(x: 0, y: 120))
                water.closeSubpath()
                layer.fill(water, with: .color(Color(red: 0.17, green: 0.5, blue: 0.72)))
            }
            rect(&ctx, x: 14, y: 98, w: 92, h: 9, radius: 4.5, fill: orange)
            leg(&ctx, [(56, 70), (52, 88), (52, 98)])
            leg(&ctx, [(60, 70), (62, 88), (66, 98)])
            line(&ctx, (58, 40), (58, 70), shirt, 18)
            head(&ctx, (58, 26))
            line(&ctx, (84, 30), (76, 100), white, 3)
            rect(&ctx, x: 70, y: 88, w: 10, h: 17, radius: 4, degrees: 8, about: (75, 96), fill: white)
            arm(&ctx, [(58, 46), (70, 42), (82, 44)])
            arm(&ctx, [(58, 48), (68, 60), (78, 62)])
        }
    }

    // MARK: Parts

    private static func body(
        _ ctx: inout GraphicsContext, headAt: (CGFloat, CGFloat), torsoFrom: (CGFloat, CGFloat), to torsoTo: (CGFloat, CGFloat),
        backArm: [(CGFloat, CGFloat)], legsA: [(CGFloat, CGFloat)], legsB: [(CGFloat, CGFloat)]
    ) {
        arm(&ctx, backArm)
        leg(&ctx, legsA)
        leg(&ctx, legsB)
        line(&ctx, torsoFrom, torsoTo, shirt, 18)
        head(&ctx, headAt)
    }

    private static func head(_ ctx: inout GraphicsContext, _ center: (CGFloat, CGFloat)) {
        dot(&ctx, center, 9.5, skin)
        var cap = Path()
        for step in 0 ... 16 {
            let angle = CGFloat.pi + CGFloat.pi * CGFloat(step) / 16
            let point = CGPoint(x: center.0 + 9.5 * cos(angle), y: center.1 + 9.5 * sin(angle))
            // An empty Path has no current point: addLine would run from the origin.
            if step == 0 { cap.move(to: point) } else { cap.addLine(to: point) }
        }
        cap.closeSubpath()
        ctx.fill(cap, with: .color(hair))
    }

    private static func arm(_ ctx: inout GraphicsContext, _ points: [(CGFloat, CGFloat)]) { stroke(&ctx, points, skin, 7) }
    private static func leg(_ ctx: inout GraphicsContext, _ points: [(CGFloat, CGFloat)]) { stroke(&ctx, points, legs, 9) }

    private static func stroke(_ ctx: inout GraphicsContext, _ points: [(CGFloat, CGFloat)], _ color: Color, _ width: CGFloat) {
        var path = Path()
        path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private static func line(_ ctx: inout GraphicsContext, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ color: Color, _ width: CGFloat) {
        stroke(&ctx, [a, b], color, width)
    }

    private static func dot(_ ctx: inout GraphicsContext, _ center: (CGFloat, CGFloat), _ radius: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: center.0 - radius, y: center.1 - radius, width: radius * 2, height: radius * 2)), with: .color(color))
    }

    private static func ring(_ ctx: inout GraphicsContext, center: (CGFloat, CGFloat), rx: CGFloat, ry: CGFloat, degrees: CGFloat, width: CGFloat) {
        let oval = Path(ellipseIn: CGRect(x: center.0 - rx, y: center.1 - ry, width: rx * 2, height: ry * 2))
        ctx.stroke(oval.applying(rotation(degrees, about: center)), with: .color(white), lineWidth: width)
    }

    private static func rect(
        _ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat = 0,
        degrees: CGFloat = 0, about: (CGFloat, CGFloat)? = nil, fill: Color
    ) {
        var path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius)
        if degrees != 0, let about {
            path = path.applying(rotation(degrees, about: about))
        }
        ctx.fill(path, with: .color(fill))
    }

    private static func rotation(_ degrees: CGFloat, about center: (CGFloat, CGFloat)) -> CGAffineTransform {
        CGAffineTransform(translationX: center.0, y: center.1)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -center.0, y: -center.1)
    }
}
