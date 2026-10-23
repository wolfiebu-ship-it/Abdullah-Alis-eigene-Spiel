import Foundation
import CoreGraphics

/// Eine Kachel der Stadtkarte.
enum Tile: UInt8 {
    case road, sidewalk, building, grass
}

/// Besondere Orte in der Stadt.
enum LocationKind: String, CaseIterable, Codable {
    case safehouse, gunShop, kiosk, supermarket, gasStation, jeweler, bank, hospital, police, villa

    var name: String {
        switch self {
        case .safehouse: "Versteck"
        case .gunShop: "Waffenladen"
        case .kiosk: "Kiosk"
        case .supermarket: "Supermarkt"
        case .gasStation: "Tankstelle"
        case .jeweler: "Juwelier"
        case .bank: "Bank"
        case .hospital: "Krankenhaus"
        case .police: "Polizeiwache"
        case .villa: "Kobra-Villa"
        }
    }

    var emoji: String {
        switch self {
        case .safehouse: "🏠"
        case .gunShop: "🎯"
        case .kiosk: "🏪"
        case .supermarket: "🛒"
        case .gasStation: "⛽️"
        case .jeweler: "💎"
        case .bank: "🏦"
        case .hospital: "🏥"
        case .police: "🚓"
        case .villa: "🐍"
        }
    }

    /// Häuserblock (x, y) auf dem 6×6-Raster.
    var block: (x: Int, y: Int) {
        switch self {
        case .safehouse: (1, 1)
        case .gunShop: (2, 1)
        case .kiosk: (1, 2)
        case .supermarket: (3, 2)
        case .gasStation: (4, 4)
        case .jeweler: (2, 4)
        case .bank: (3, 3)
        case .hospital: (0, 3)
        case .police: (5, 0)
        case .villa: (5, 5)
        }
    }

    var isRobbable: Bool {
        switch self {
        case .kiosk, .supermarket, .gasStation, .jeweler, .bank: true
        default: false
        }
    }

    var loot: ClosedRange<Int> {
        switch self {
        case .kiosk: 150...300
        case .supermarket: 300...600
        case .gasStation: 250...500
        case .jeweler: 1500...2500
        case .bank: 5000...8000
        default: 0...0
        }
    }

    /// Wie lange der Überfall dauert (Sekunden).
    var robDuration: Double {
        switch self {
        case .kiosk: 3
        case .supermarket, .gasStation: 4
        case .jeweler: 6
        case .bank: 9
        default: 0
        }
    }

    /// Zusätzliche Fahndung nach einem erfolgreichen Überfall.
    var robHeat: Double {
        switch self {
        case .kiosk: 3
        case .supermarket, .gasStation: 4
        case .jeweler: 8
        case .bank: 15
        default: 0
        }
    }
}

enum BlockKind: Equatable {
    case building(style: Int)
    case park
    case location(LocationKind)
}

/// Die Stadt: ein Raster aus Straßen, Gehwegen, Häusern und Parks.
///
/// Alle 8 Kacheln verläuft eine zweispurige Straße. Dazwischen liegt ein
/// Häuserblock mit Gehweg-Ring (6×6 Kacheln) und einem Gebäude oder Park (4×4).
final class World {
    static let tileSize: CGFloat = 64
    static let cols = 50
    static let rows = 50
    static let period = 8
    static let blockCount = 6
    static let nodeCount = 7
    static let parks: [(Int, Int)] = [(2, 2), (4, 1), (0, 5), (5, 3), (1, 4)]
    static let gangPark = (x: 4, y: 1)

    let size = CGSize(width: CGFloat(World.cols) * World.tileSize,
                      height: CGFloat(World.rows) * World.tileSize)

    private(set) var tiles: [Tile]
    private(set) var blocks: [BlockKind]
    private(set) var trees: [CGPoint] = []

    init() {
        var rng = SeededRandom(seed: 2024)

        var blocks: [BlockKind] = []
        for by in 0..<World.blockCount {
            for bx in 0..<World.blockCount {
                if let loc = LocationKind.allCases.first(where: { $0.block.x == bx && $0.block.y == by }) {
                    blocks.append(.location(loc))
                } else if World.parks.contains(where: { $0.0 == bx && $0.1 == by }) {
                    blocks.append(.park)
                } else {
                    blocks.append(.building(style: Int.random(in: 0..<1000, using: &rng)))
                }
            }
        }
        self.blocks = blocks

        var tiles = [Tile](repeating: .sidewalk, count: World.cols * World.rows)
        for r in 0..<World.rows {
            for c in 0..<World.cols {
                let lc = c % World.period
                let lr = r % World.period
                let tile: Tile
                if lc <= 1 || lr <= 1 {
                    tile = .road
                } else if (3...6).contains(lc) && (3...6).contains(lr) {
                    let kind = blocks[(r / World.period) * World.blockCount + c / World.period]
                    tile = kind == .park ? .grass : .building
                } else {
                    tile = .sidewalk
                }
                tiles[r * World.cols + c] = tile
            }
        }
        self.tiles = tiles

        var trees: [CGPoint] = []
        for (bx, by) in World.parks {
            let rect = World.buildingRect(bx, by).insetBy(dx: 26, dy: 26)
            for _ in 0..<7 {
                trees.append(CGPoint(x: CGFloat.random(in: rect.minX...rect.maxX, using: &rng),
                                     y: CGFloat.random(in: rect.minY...rect.maxY, using: &rng)))
            }
        }
        self.trees = trees
    }

    // MARK: - Abfragen

    func blockKind(_ bx: Int, _ by: Int) -> BlockKind {
        blocks[by * World.blockCount + bx]
    }

    func tile(_ c: Int, _ r: Int) -> Tile {
        guard c >= 0, r >= 0, c < World.cols, r < World.rows else { return .building }
        return tiles[r * World.cols + c]
    }

    func tileCoord(_ p: CGPoint) -> (Int, Int) {
        (Int(floor(p.x / World.tileSize)), Int(floor(p.y / World.tileSize)))
    }

    func tileAt(_ p: CGPoint) -> Tile {
        let (c, r) = tileCoord(p)
        return tile(c, r)
    }

    func isSolid(_ p: CGPoint) -> Bool { tileAt(p) == .building }

    func center(_ c: Int, _ r: Int) -> CGPoint {
        CGPoint(x: (CGFloat(c) + 0.5) * World.tileSize, y: (CGFloat(r) + 0.5) * World.tileSize)
    }

    /// Rechteck des Gebäudes (bzw. der Wiese) in einem Block.
    static func buildingRect(_ bx: Int, _ by: Int) -> CGRect {
        CGRect(x: CGFloat(bx * period + 3) * tileSize,
               y: CGFloat(by * period + 3) * tileSize,
               width: 4 * tileSize, height: 4 * tileSize)
    }

    func buildingRect(_ bx: Int, _ by: Int) -> CGRect { World.buildingRect(bx, by) }

    /// Eingang eines Ortes (auf dem Gehweg vor der Südseite).
    func door(_ kind: LocationKind) -> CGPoint {
        let rect = buildingRect(kind.block.x, kind.block.y)
        return CGPoint(x: rect.midX, y: rect.maxY + 22)
    }

    func blockCenter(_ bx: Int, _ by: Int) -> CGPoint {
        let rect = buildingRect(bx, by)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// Mitte einer Kreuzung.
    func nodePos(_ m: Int, _ k: Int) -> CGPoint {
        CGPoint(x: CGFloat(m * World.period + 1) * World.tileSize,
                y: CGFloat(k * World.period + 1) * World.tileSize)
    }

    // MARK: - Kollision

    /// Schiebt einen Kreis aus allen Gebäuden heraus. Gibt die Verschiebung zurück.
    @discardableResult
    func resolve(_ p: inout CGPoint, radius r: CGFloat) -> CGPoint {
        let start = p
        let t = World.tileSize
        let minC = Int(floor((p.x - r) / t)), maxC = Int(floor((p.x + r) / t))
        let minR = Int(floor((p.y - r) / t)), maxR = Int(floor((p.y + r) / t))
        for row in minR...maxR {
            for col in minC...maxC where tile(col, row) == .building {
                let rect = CGRect(x: CGFloat(col) * t, y: CGFloat(row) * t, width: t, height: t)
                let cx = clamp(p.x, rect.minX, rect.maxX)
                let cy = clamp(p.y, rect.minY, rect.maxY)
                let dx = p.x - cx, dy = p.y - cy
                let d2 = dx * dx + dy * dy
                guard d2 < r * r else { continue }
                if d2 > 0.0001 {
                    let d = d2.squareRoot()
                    p.x += dx / d * (r - d)
                    p.y += dy / d * (r - d)
                } else {
                    // Mittelpunkt steckt im Gebäude: kürzester Weg hinaus.
                    let left = p.x - rect.minX, right = rect.maxX - p.x
                    let top = p.y - rect.minY, bottom = rect.maxY - p.y
                    let m = min(left, right, top, bottom)
                    if m == left { p.x = rect.minX - r }
                    else if m == right { p.x = rect.maxX + r }
                    else if m == top { p.y = rect.minY - r }
                    else { p.y = rect.maxY + r }
                }
            }
        }
        p.x = clamp(p.x, r, size.width - r)
        p.y = clamp(p.y, r, size.height - r)
        return p - start
    }

    /// Kann man von a nach b sehen (ohne Gebäude dazwischen)?
    func lineOfSight(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let d = b - a
        let steps = Int(d.length / 24) + 1
        guard steps > 1 else { return true }
        for i in 1..<steps {
            let p = a + d * (CGFloat(i) / CGFloat(steps))
            if isSolid(p) { return false }
        }
        return true
    }

    /// Zufälliger Punkt in einem Ring um `around`, der auf einer erlaubten Kachel liegt.
    func randomSpot(around: CGPoint, minDist: CGFloat, maxDist: CGFloat, allowed: Set<Tile>) -> CGPoint? {
        for _ in 0..<30 {
            let a = CGFloat.random(in: 0..<(2 * .pi))
            let d = CGFloat.random(in: minDist...max(minDist + 1, maxDist))
            let p = around + CGPoint(angle: a, length: d)
            guard p.x > 20, p.y > 20, p.x < size.width - 20, p.y < size.height - 20 else { continue }
            if allowed.contains(tileAt(p)) { return p }
        }
        return nil
    }

    // MARK: - Wegfindung

    /// Breitensuche vom Ziel aus: jede begehbare Kachel bekommt ihre Entfernung zum Ziel.
    func flowField(to target: CGPoint) -> [Int32] {
        var field = [Int32](repeating: -1, count: World.cols * World.rows)
        let (tc, tr) = tileCoord(target)
        guard tile(tc, tr) != .building else { return field }
        var queue: [(Int, Int)] = [(tc, tr)]
        field[tr * World.cols + tc] = 0
        var head = 0
        while head < queue.count {
            let (c, r) = queue[head]
            head += 1
            let d = field[r * World.cols + c]
            for (dx, dy) in fourDirections {
                let nc = c + dx, nr = r + dy
                guard tile(nc, nr) != .building else { continue }
                let i = nr * World.cols + nc
                if field[i] == -1 {
                    field[i] = d + 1
                    queue.append((nc, nr))
                }
            }
        }
        return field
    }

    func flowValue(_ field: [Int32], _ c: Int, _ r: Int) -> Int32? {
        guard c >= 0, r >= 0, c < World.cols, r < World.rows, !field.isEmpty else { return nil }
        let v = field[r * World.cols + c]
        return v >= 0 ? v : nil
    }
}
