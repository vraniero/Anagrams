import SwiftUI

/// The icon's night sky, alive: blue glows drift slowly and cream letter tiles float up,
/// turning gently, changing letter each time they come round again. Holds still when
/// Reduce Motion is on.
///
/// Cheap to draw, since it sits behind every screen: 30 frames a second (it drifts slowly),
/// and each letter tile is rendered once and reused.
struct IconBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tiles = 16
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || Motion.isStill)) { timeline in
            let t = reduceMotion || Motion.isStill ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawGlows(&context, size, t)
                for i in 0..<Self.tiles { drawTile(i, &context, size, t) }
            } symbols: {
                ForEach(Self.alphabet.indices, id: \.self) { n in
                    TileSymbol(letter: Self.alphabet[n]).tag(n)
                }
            }
        }
        .background(Theme.night)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A repeatable random number in 0..<1 for tile `i`, property `k`.
    private static func random(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    private func drawGlows(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let glows: [(x: Double, y: Double, r: Double, speed: Double, color: Color)] = [
            (0.30, 0.25, 0.55, 0.11, Theme.glow.opacity(0.35)),
            (0.75, 0.55, 0.50, 0.08, Theme.glow.opacity(0.25)),
            (0.40, 0.85, 0.60, 0.06, Theme.glowLight.opacity(0.18)),
        ]
        for (n, g) in glows.enumerated() {
            let center = CGPoint(x: size.width * (g.x + 0.12 * sin(t * g.speed + Double(n))),
                                 y: size.height * (g.y + 0.08 * cos(t * g.speed * 1.3 + Double(n))))
            let radius = size.width * g.r
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .radialGradient(Gradient(colors: [g.color, .clear]),
                                               center: center, startRadius: 0, endRadius: radius))
        }
    }

    private func drawTile(_ i: Int, _ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let r = { (k: Int) in Self.random(i, k) }
        let side = 22 + r(3) * 34                     // near tiles are bigger…
        let near = (side - 22) / 34
        let speed = 10 + near * 22                     // …faster…
        let travel = size.height + side * 3
        let progress = t * speed + r(2) * travel
        let lap = Int(progress / travel)
        let y = size.height + side * 1.5 - progress.truncatingRemainder(dividingBy: travel)
        let x = size.width * r(0) + sin(t * 0.35 + Double(i)) * 18
        let angle = sin(t * (0.25 + r(4) * 0.4) + Double(i)) * 0.45
        let letter = Int(Self.random(i, 100 + lap) * 26) % 26
        guard let symbol = context.resolveSymbol(id: letter) else { return }

        var tile = context
        tile.opacity = 0.05 + near * 0.25             // …and brighter
        tile.translateBy(x: x, y: y)
        tile.rotate(by: .radians(angle))
        tile.scaleBy(x: side / TileSymbol.side, y: side / TileSymbol.side)
        tile.draw(symbol, at: .zero)
    }
}

/// One cream letter tile, drawn once at a fixed size and scaled for each floating tile.
private struct TileSymbol: View {
    static let side: CGFloat = 56
    let letter: Character

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.side * 0.18, style: .continuous)
        ZStack {
            shape.fill(Theme.creamShade).offset(y: Self.side * 0.08)
            shape.fill(Theme.cream)
            Text(String(letter))
                .font(.system(size: Self.side * 0.58, weight: .bold))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: Self.side, height: Self.side)
    }
}

/// The icon's two glowing arrows, chasing each other round the title.
struct CirclingArrows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || Motion.isStill)) { timeline in
            let t = reduceMotion || Motion.isStill ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = CGSize(width: size.width / 2 - 8, height: size.height / 2 - 8)
                let turn = t * 0.35
                for half in 0..<2 {
                    let start = turn + Double(half) * .pi + 0.35
                    drawArrow(&context, center: center, radius: radius, from: start, to: start + 1.7)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func point(_ a: Double, _ c: CGPoint, _ r: CGSize) -> CGPoint {
        CGPoint(x: c.x + r.width * cos(a), y: c.y + r.height * sin(a))
    }

    private func drawArrow(_ context: inout GraphicsContext, center: CGPoint, radius: CGSize, from: Double, to: Double) {
        var arc = Path()
        let steps = 40
        for s in 0...steps {
            let p = point(from + (to - from) * Double(s) / Double(steps), center, radius)
            s == 0 ? arc.move(to: p) : arc.addLine(to: p)
        }
        let end = point(to, center, radius)
        let before = point(to - 0.05, center, radius)
        let direction = atan2(end.y - before.y, end.x - before.x)
        var head = Path()
        head.move(to: CGPoint(x: end.x + 16 * cos(direction), y: end.y + 16 * sin(direction)))
        head.addLine(to: CGPoint(x: end.x + 11 * cos(direction + 2.2), y: end.y + 11 * sin(direction + 2.2)))
        head.addLine(to: CGPoint(x: end.x + 11 * cos(direction - 2.2), y: end.y + 11 * sin(direction - 2.2)))
        head.closeSubpath()

        var glow = context
        glow.addFilter(.blur(radius: 6))
        glow.stroke(arc, with: .color(Theme.glow), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        let tail = point(from, center, radius)
        context.stroke(arc, with: .linearGradient(Gradient(colors: [Theme.glow.opacity(0), Theme.glowLight]),
                                                  startPoint: tail, endPoint: end),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        context.fill(head, with: .color(Theme.glowLight))
    }
}
