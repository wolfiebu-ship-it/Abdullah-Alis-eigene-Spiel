import Foundation
import CoreGraphics

// Kleine Vektor-Mathematik für Positionen und Richtungen.

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x / s, y: a.y / s) }
    static prefix func - (a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }
    static func -= (a: inout CGPoint, b: CGPoint) { a = a - b }

    init(angle: CGFloat, length: CGFloat = 1) {
        self.init(x: cos(angle) * length, y: sin(angle) * length)
    }

    var length: CGFloat { (x * x + y * y).squareRoot() }

    var normalized: CGPoint {
        let l = length
        return l > 0.0001 ? CGPoint(x: x / l, y: y / l) : .zero
    }

    /// Richtung als Winkel (0 = nach rechts, positiv = im Uhrzeigersinn, da y nach unten zeigt).
    var angle: CGFloat { atan2(y, x) }

    /// 90° gedreht (zeigt bei Blickrichtung nach rechts nach unten = rechte Seite).
    var perpendicular: CGPoint { CGPoint(x: -y, y: x) }

    func distance(to p: CGPoint) -> CGFloat { (self - p).length }

    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }
}

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

/// Kleinster Winkelunterschied a - b im Bereich -π...π.
func angleDiff(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}

func normalizeAngle(_ a: CGFloat) -> CGFloat {
    angleDiff(a, 0)
}

/// Zufallsgenerator mit festem Startwert, damit die Stadt immer gleich aussieht.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

let fourDirections: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
