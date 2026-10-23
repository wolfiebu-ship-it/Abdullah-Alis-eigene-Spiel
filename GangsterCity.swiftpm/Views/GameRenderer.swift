import SwiftUI

enum Palette {
    static let water = Color(red: 0.13, green: 0.32, blue: 0.48)
    static let sidewalk = Color(red: 0.60, green: 0.59, blue: 0.56)
    static let curb = Color(red: 0.48, green: 0.47, blue: 0.45)
    static let road = Color(red: 0.21, green: 0.21, blue: 0.23)
    static let grass = Color(red: 0.29, green: 0.54, blue: 0.26)
    static let path = Color(red: 0.70, green: 0.62, blue: 0.47)
    static let lane = Color(red: 0.95, green: 0.83, blue: 0.30)

    static let buildings: [Color] = [
        Color(red: 0.55, green: 0.36, blue: 0.30), Color(red: 0.42, green: 0.45, blue: 0.52),
        Color(red: 0.62, green: 0.55, blue: 0.42), Color(red: 0.36, green: 0.40, blue: 0.36),
        Color(red: 0.50, green: 0.30, blue: 0.40), Color(red: 0.32, green: 0.36, blue: 0.48),
        Color(red: 0.58, green: 0.50, blue: 0.52)
    ]
    static let cars: [Color] = [
        Color(red: 0.80, green: 0.15, blue: 0.15), Color(red: 0.15, green: 0.35, blue: 0.80),
        Color(red: 0.12, green: 0.55, blue: 0.30), Color(red: 0.90, green: 0.55, blue: 0.10),
        Color(red: 0.55, green: 0.20, blue: 0.65), Color(red: 0.85, green: 0.85, blue: 0.88),
        Color(red: 0.15, green: 0.15, blue: 0.17), Color(red: 0.20, green: 0.65, blue: 0.75)
    ]
    static let shirts: [Color] = [
        Color(red: 0.85, green: 0.30, blue: 0.30), Color(red: 0.30, green: 0.55, blue: 0.85),
        Color(red: 0.95, green: 0.80, blue: 0.30), Color(red: 0.55, green: 0.80, blue: 0.40),
        Color(red: 0.75, green: 0.45, blue: 0.85), Color(red: 0.95, green: 0.95, blue: 0.95),
        Color(red: 0.95, green: 0.55, blue: 0.25), Color(red: 0.40, green: 0.40, blue: 0.45)
    ]
    static let skins: [Color] = [
        Color(red: 0.98, green: 0.84, blue: 0.70), Color(red: 0.87, green: 0.67, blue: 0.50),
        Color(red: 0.70, green: 0.50, blue: 0.35), Color(red: 0.50, green: 0.34, blue: 0.24),
        Color(red: 0.36, green: 0.24, blue: 0.17)
    ]
    static let hair: [Color] = [
        Color(red: 0.10, green: 0.08, blue: 0.06), Color(red: 0.35, green: 0.22, blue: 0.12),
        Color(red: 0.80, green: 0.65, blue: 0.35), Color(red: 0.55, green: 0.55, blue: 0.55),
        Color(red: 0.60, green: 0.25, blue: 0.12)
    ]

    static func roof(_ kind: LocationKind) -> Color {
        switch kind {
        case .safehouse: Color(red: 0.25, green: 0.55, blue: 0.35)
        case .gunShop: Color(red: 0.35, green: 0.32, blue: 0.28)
        case .kiosk: Color(red: 0.85, green: 0.50, blue: 0.20)
        case .supermarket: Color(red: 0.20, green: 0.50, blue: 0.70)
        case .gasStation: Color(red: 0.80, green: 0.75, blue: 0.20)
        case .jeweler: Color(red: 0.55, green: 0.35, blue: 0.70)
        case .bank: Color(red: 0.75, green: 0.70, blue: 0.55)
        case .hospital: Color(red: 0.92, green: 0.92, blue: 0.94)
        case .police: Color(red: 0.18, green: 0.25, blue: 0.50)
        case .villa: Color(red: 0.60, green: 0.15, blue: 0.15)
        }
    }

    static func pick(_ list: [Color], _ index: Int) -> Color { list[abs(index) % list.count] }
}

/// Zeichnet die ganze Spielwelt in einen SwiftUI-Canvas.
struct GameRenderer {
    let engine: GameEngine

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let e = engine
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.water))

        var g = context
        g.translateBy(x: size.width / 2, y: size.height / 2)
        g.scaleBy(x: e.zoom, y: e.zoom)
        g.translateBy(x: -e.camera.x, y: -e.camera.y)

        let vw = size.width / e.zoom, vh = size.height / e.zoom
        let view = CGRect(x: e.camera.x - vw / 2, y: e.camera.y - vh / 2, width: vw, height: vh)
            .insetBy(dx: -120, dy: -120)

        drawGround(&g, view)
        drawDoors(&g, view)
        drawMissionMarker(&g)
        drawPickups(&g, view)
        for p in e.people where p.isDead && view.contains(p.pos) { drawCorpse(&g, p) }
        for car in e.cars where view.contains(car.pos) { drawCar(&g, car) }
        for p in e.people where !p.isDead && view.contains(p.pos) { drawPerson(&g, p) }
        if e.player.car == nil && e.outcome != .wasted { drawPlayer(&g) }
        if e.player.car == nil && e.outcome == .wasted { drawPlayerDown(&g) }
        drawBullets(&g)
        drawBuildings(&g, view)
        drawTrees(&g, view)
        drawEffects(&g)
        drawProgressRings(&g)
        drawTexts(&g, view)

        drawObjectiveArrow(&context, size: size)
        if e.player.hitFlash > 0 {
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.red.opacity(e.player.hitFlash * 1.2)))
        }
        if e.player.health < 30 && e.outcome == nil {
            let pulse = 0.12 + 0.08 * sin(e.time * 6)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.red.opacity(pulse)))
        }
    }

    // MARK: - Boden

    private func drawGround(_ g: inout GraphicsContext, _ view: CGRect) {
        let w = engine.world
        let t = World.tileSize
        let mapRect = CGRect(origin: .zero, size: w.size)
        g.fill(Path(mapRect.intersection(view)), with: .color(Palette.sidewalk))

        // Straßen
        var roads = Path()
        var curbs = Path()
        for k in 0..<World.nodeCount {
            let start = CGFloat(k * World.period) * t
            let h = CGRect(x: 0, y: start, width: w.size.width, height: 2 * t)
            let v = CGRect(x: start, y: 0, width: 2 * t, height: w.size.height)
            if h.intersects(view) {
                roads.addRect(h)
                curbs.addRect(h.insetBy(dx: 0, dy: -3))
            }
            if v.intersects(view) {
                roads.addRect(v)
                curbs.addRect(v.insetBy(dx: -3, dy: 0))
            }
        }
        g.fill(curbs, with: .color(Palette.curb))
        g.fill(roads, with: .color(Palette.road))

        // Mittellinien (gestrichelt), nicht auf Kreuzungen
        var dashes = Path()
        for k in 0..<World.nodeCount {
            let mid = CGFloat(k * World.period + 1) * t
            if mid > view.minY - 10 && mid < view.maxY + 10 {
                var x = max(0, floor(view.minX / 48) * 48)
                while x < min(view.maxX, w.size.width) {
                    let local = x.truncatingRemainder(dividingBy: CGFloat(World.period) * t)
                    if local > 2 * t + 8 && local < CGFloat(World.period) * t - 30 {
                        dashes.addRect(CGRect(x: x, y: mid - 2, width: 24, height: 4))
                    }
                    x += 48
                }
            }
            if mid > view.minX - 10 && mid < view.maxX + 10 {
                var y = max(0, floor(view.minY / 48) * 48)
                while y < min(view.maxY, w.size.height) {
                    let local = y.truncatingRemainder(dividingBy: CGFloat(World.period) * t)
                    if local > 2 * t + 8 && local < CGFloat(World.period) * t - 30 {
                        dashes.addRect(CGRect(x: mid - 2, y: y, width: 4, height: 24))
                    }
                    y += 48
                }
            }
        }
        g.fill(dashes, with: .color(Palette.lane))

        // Zebrastreifen an den Kreuzungen
        var zebra = Path()
        for m in 0..<World.nodeCount {
            for k in 0..<World.nodeCount {
                let c = w.nodePos(m, k)
                guard view.insetBy(dx: -t * 2, dy: -t * 2).contains(c) else { continue }
                let x0 = c.x - t, y0 = c.y - t
                for i in 0..<6 {
                    let o = CGFloat(i) * 21 + 4
                    zebra.addRect(CGRect(x: x0 + o, y: y0 - 20, width: 11, height: 16))       // oben
                    zebra.addRect(CGRect(x: x0 + o, y: y0 + 2 * t + 4, width: 11, height: 16)) // unten
                    zebra.addRect(CGRect(x: x0 - 20, y: y0 + o, width: 16, height: 11))       // links
                    zebra.addRect(CGRect(x: x0 + 2 * t + 4, y: y0 + o, width: 16, height: 11)) // rechts
                }
            }
        }
        g.fill(zebra, with: .color(.white.opacity(0.75)))

        // Parks
        for (bx, by) in World.parks {
            let rect = w.buildingRect(bx, by)
            guard rect.intersects(view) else { continue }
            g.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(Palette.grass))
            var paths = Path()
            paths.addRect(CGRect(x: rect.midX - 10, y: rect.minY, width: 20, height: rect.height))
            paths.addRect(CGRect(x: rect.minX, y: rect.midY - 10, width: rect.width, height: 20))
            g.fill(paths, with: .color(Palette.path))
            g.fill(Path(ellipseIn: CGRect(x: rect.midX - 34, y: rect.midY - 34, width: 68, height: 68)),
                   with: .color(Palette.path))
            if bx == World.gangPark.x && by == World.gangPark.y {
                // Graffiti der Roten Kobras
                g.draw(Text("KOBRAS").font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.red.opacity(0.75)),
                       at: CGPoint(x: rect.midX, y: rect.minY + 40))
            } else {
                g.fill(Path(ellipseIn: CGRect(x: rect.midX - 20, y: rect.midY - 20, width: 40, height: 40)),
                       with: .color(Color(red: 0.35, green: 0.6, blue: 0.85)))
            }
        }
    }

    private func drawDoors(_ g: inout GraphicsContext, _ view: CGRect) {
        let e = engine
        for kind in LocationKind.allCases {
            let door = e.world.door(kind)
            guard view.contains(door) else { continue }
            let active = !kind.isRobbable || e.cooldown(of: kind) <= 0
            let color: Color = kind.isRobbable ? (active ? .green : .gray) : Palette.roof(kind)
            let pulse = CGFloat(1 + 0.12 * sin(e.time * 4))
            let r = 20 * pulse
            g.fill(Path(ellipseIn: CGRect(x: door.x - r, y: door.y - r * 0.6, width: 2 * r, height: 1.2 * r)),
                   with: .color(color.opacity(0.45)))
            g.stroke(Path(ellipseIn: CGRect(x: door.x - r, y: door.y - r * 0.6, width: 2 * r, height: 1.2 * r)),
                     with: .color(color), lineWidth: 2)
            if kind.isRobbable && active {
                g.draw(Text("$").font(.system(size: 16, weight: .black)).foregroundColor(.white), at: door)
            }
        }
    }

    // MARK: - Gebäude & Bäume

    private func drawBuildings(_ g: inout GraphicsContext, _ view: CGRect) {
        let w = engine.world
        for by in 0..<World.blockCount {
            for bx in 0..<World.blockCount {
                let rect = w.buildingRect(bx, by)
                guard rect.intersects(view) else { continue }
                switch w.blockKind(bx, by) {
                case .park:
                    continue
                case .building(let style):
                    drawPlainBuilding(&g, rect, style: style)
                case .location(let kind):
                    drawLocation(&g, rect, kind: kind)
                }
            }
        }
    }

    private func drawPlainBuilding(_ g: inout GraphicsContext, _ rect: CGRect, style: Int) {
        g.fill(Path(rect.offsetBy(dx: 10, dy: 12)), with: .color(.black.opacity(0.28)))
        // Zwei oder drei Häuser nebeneinander
        let parts = 2 + style % 2
        let partW = rect.width / CGFloat(parts)
        for i in 0..<parts {
            let r = CGRect(x: rect.minX + CGFloat(i) * partW, y: rect.minY, width: partW, height: rect.height)
            let color = Palette.pick(Palette.buildings, style / 7 + i * 3)
            g.fill(Path(r), with: .color(color))
            g.stroke(Path(r.insetBy(dx: 5, dy: 5)), with: .color(.black.opacity(0.25)), lineWidth: 3)
            g.fill(Path(r.insetBy(dx: 9, dy: 9)), with: .color(.white.opacity(0.06)))
            // Klimaanlagen und Dachluken
            let seed = style + i * 31
            for j in 0..<2 {
                let ox = CGFloat((seed * (j + 3) * 17) % Int(max(1, r.width - 50))) + 18
                let oy = CGFloat((seed * (j + 5) * 13) % Int(max(1, r.height - 50))) + 18
                let box = CGRect(x: r.minX + ox, y: r.minY + oy, width: 20, height: 16)
                g.fill(Path(box), with: .color(.black.opacity(0.25)))
                g.fill(Path(box.insetBy(dx: 3, dy: 3)), with: .color(.white.opacity(0.18)))
            }
        }
    }

    private func drawLocation(_ g: inout GraphicsContext, _ rect: CGRect, kind: LocationKind) {
        g.fill(Path(rect.offsetBy(dx: 10, dy: 12)), with: .color(.black.opacity(0.3)))
        let roof = Palette.roof(kind)
        g.fill(Path(rect), with: .color(roof))
        g.stroke(Path(rect.insetBy(dx: 6, dy: 6)), with: .color(.black.opacity(0.3)), lineWidth: 4)

        // Markise über dem Eingang
        let awning = CGRect(x: rect.midX - 70, y: rect.maxY - 22, width: 140, height: 22)
        for i in 0..<7 {
            let stripe = CGRect(x: awning.minX + CGFloat(i) * 20, y: awning.minY, width: 20, height: awning.height)
            g.fill(Path(stripe), with: .color(i % 2 == 0 ? .white : roof.opacity(0.9)))
        }
        g.stroke(Path(awning), with: .color(.black.opacity(0.4)), lineWidth: 2)

        if kind == .hospital {
            var cross = Path()
            cross.addRect(CGRect(x: rect.midX - 14, y: rect.midY - 70, width: 28, height: 80))
            cross.addRect(CGRect(x: rect.midX - 40, y: rect.midY - 44, width: 80, height: 28))
            g.fill(cross, with: .color(.red))
        } else {
            g.draw(Text(kind.emoji).font(.system(size: 64)), at: CGPoint(x: rect.midX, y: rect.midY - 30))
        }
        let label = Text(kind.name.uppercased())
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundColor(kind == .hospital ? .black : .white)
        g.draw(label, at: CGPoint(x: rect.midX, y: rect.midY + 40))
    }

    private func drawTrees(_ g: inout GraphicsContext, _ view: CGRect) {
        for tree in engine.world.trees where view.contains(tree) {
            let r: CGFloat = 26
            g.fill(Path(ellipseIn: CGRect(x: tree.x - r + 8, y: tree.y - r + 10, width: 2 * r, height: 2 * r)),
                   with: .color(.black.opacity(0.22)))
            g.fill(Path(ellipseIn: CGRect(x: tree.x - r, y: tree.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(Color(red: 0.16, green: 0.42, blue: 0.18).opacity(0.92)))
            g.fill(Path(ellipseIn: CGRect(x: tree.x - r * 0.55 - 5, y: tree.y - r * 0.55 - 5, width: r * 1.1, height: r * 1.1)),
                   with: .color(Color(red: 0.28, green: 0.58, blue: 0.25).opacity(0.9)))
        }
    }

    // MARK: - Figuren

    private func drawPerson(_ g: inout GraphicsContext, _ p: Person) {
        let shirt: Color
        switch p.faction {
        case .civilian: shirt = Palette.pick(Palette.shirts, p.look.shirt)
        case .police: shirt = Color(red: 0.20, green: 0.32, blue: 0.70)
        case .gang: shirt = p.isBoss ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.75, green: 0.10, blue: 0.12)
        }
        drawFigure(&g, pos: p.pos, facing: p.facing, walkPhase: p.walkPhase, moving: p.speed > 5,
                   shirt: shirt, skin: Palette.pick(Palette.skins, p.look.skin),
                   hair: Palette.pick(Palette.hair, p.look.hair),
                   armed: p.faction != .civilian, faction: p.faction,
                   boss: p.isBoss, flash: p.hitFlash, scale: p.radius / 11)

        // Lebensbalken für verletzte Gegner
        if p.faction != .civilian && p.health < p.maxHealth {
            let w: CGFloat = p.isBoss ? 44 : 26
            let bar = CGRect(x: p.pos.x - w / 2, y: p.pos.y - p.radius - 14, width: w, height: 4)
            g.fill(Path(bar), with: .color(.black.opacity(0.6)))
            g.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: w * max(0, p.health / p.maxHealth), height: 4)),
                   with: .color(p.faction == .police ? .blue : .red))
        }
        if p.faction == .gang && p.isBoss {
            g.draw(Text("👑").font(.system(size: 16)), at: p.pos + CGPoint(x: 0, y: -30))
        }
    }

    private func drawPlayer(_ g: inout GraphicsContext) {
        let pl = engine.player
        let ring = CGRect(x: pl.pos.x - 18, y: pl.pos.y - 18, width: 36, height: 36)
        g.stroke(Path(ellipseIn: ring), with: .color(.yellow.opacity(0.7)), lineWidth: 2)
        drawFigure(&g, pos: pl.pos, facing: pl.facing, walkPhase: pl.walkPhase, moving: pl.moving,
                   shirt: Color(red: 0.10, green: 0.55, blue: 0.35), skin: Palette.skins[2], hair: Palette.hair[0],
                   armed: pl.weapon != .fist, faction: nil, boss: false, flash: pl.hitFlash, scale: 1.1)
    }

    private func drawPlayerDown(_ g: inout GraphicsContext) {
        let pl = engine.player
        var c = g
        c.translateBy(x: pl.pos.x, y: pl.pos.y)
        c.rotate(by: .radians(Double(pl.facing)))
        c.fill(Path(ellipseIn: CGRect(x: -16, y: -12, width: 30, height: 24)), with: .color(Color(red: 0.45, green: 0.05, blue: 0.05).opacity(0.6)))
        c.fill(Path(roundedRect: CGRect(x: -14, y: -8, width: 26, height: 16), cornerRadius: 7),
               with: .color(Color(red: 0.10, green: 0.55, blue: 0.35)))
        c.fill(Path(ellipseIn: CGRect(x: 9, y: -6, width: 12, height: 12)), with: .color(Palette.skins[2]))
    }

    private func drawFigure(_ g: inout GraphicsContext, pos: CGPoint, facing: CGFloat, walkPhase: CGFloat, moving: Bool,
                            shirt: Color, skin: Color, hair: Color, armed: Bool, faction: Faction?,
                            boss: Bool, flash: Double, scale: CGFloat) {
        var c = g
        c.translateBy(x: pos.x, y: pos.y)
        c.scaleBy(x: scale, y: scale)
        c.rotate(by: .radians(Double(facing)))

        c.fill(Path(ellipseIn: CGRect(x: -11, y: -9, width: 26, height: 22)), with: .color(.black.opacity(0.25)))

        // Füße
        let swing = moving ? sin(walkPhase) * 7 : 0
        c.fill(Path(ellipseIn: CGRect(x: swing - 4, y: -8, width: 8, height: 6)), with: .color(.black.opacity(0.8)))
        c.fill(Path(ellipseIn: CGRect(x: -swing - 4, y: 2, width: 8, height: 6)), with: .color(.black.opacity(0.8)))

        // Arme / Waffe
        if armed {
            c.fill(Path(roundedRect: CGRect(x: 6, y: 1, width: 16, height: 5), cornerRadius: 1.5), with: .color(.black))
            c.fill(Path(ellipseIn: CGRect(x: 4, y: -1, width: 8, height: 8)), with: .color(skin))
        } else {
            let arm = moving ? sin(walkPhase) * 5 : 0
            c.fill(Path(ellipseIn: CGRect(x: -arm - 3, y: -14, width: 7, height: 7)), with: .color(skin))
            c.fill(Path(ellipseIn: CGRect(x: arm - 3, y: 7, width: 7, height: 7)), with: .color(skin))
        }

        // Körper
        c.fill(Path(ellipseIn: CGRect(x: -8, y: -11, width: 16, height: 22)), with: .color(shirt))
        if boss {
            c.stroke(Path(ellipseIn: CGRect(x: -4, y: -7, width: 10, height: 14)), with: .color(.yellow), lineWidth: 2)
        }

        // Kopf
        c.fill(Path(ellipseIn: CGRect(x: -6, y: -7, width: 14, height: 14)), with: .color(skin))
        switch faction {
        case .police?:
            c.fill(Path(ellipseIn: CGRect(x: -7, y: -7, width: 13, height: 14)), with: .color(Color(red: 0.1, green: 0.13, blue: 0.3)))
            c.fill(Path(roundedRect: CGRect(x: 4, y: -5, width: 5, height: 10), cornerRadius: 2), with: .color(.black))
        case .gang?:
            c.fill(Path(ellipseIn: CGRect(x: -7, y: -6.5, width: 12, height: 13)), with: .color(hair))
            c.stroke(Path(ellipseIn: CGRect(x: -6, y: -7, width: 14, height: 14)), with: .color(.red), lineWidth: 2.5)
        default:
            c.fill(Path(ellipseIn: CGRect(x: -7, y: -6.5, width: 12, height: 13)), with: .color(hair))
        }

        if flash > 0 {
            c.fill(Path(ellipseIn: CGRect(x: -12, y: -12, width: 24, height: 24)), with: .color(.white.opacity(flash * 4)))
        }
    }

    private func drawCorpse(_ g: inout GraphicsContext, _ p: Person) {
        var c = g
        c.translateBy(x: p.pos.x, y: p.pos.y)
        c.rotate(by: .radians(Double(p.facing)))
        let spread = min(1, p.deadTime * 2)
        c.fill(Path(ellipseIn: CGRect(x: -14 * spread - 4, y: -12 * spread, width: 28 * spread + 8, height: 24 * spread)),
               with: .color(Color(red: 0.45, green: 0.05, blue: 0.05).opacity(0.55)))
        let shirt: Color = p.faction == .police ? Color(red: 0.20, green: 0.32, blue: 0.70)
            : p.faction == .gang ? Color(red: 0.75, green: 0.10, blue: 0.12)
            : Palette.pick(Palette.shirts, p.look.shirt)
        c.fill(Path(roundedRect: CGRect(x: -14, y: -8, width: 24, height: 16), cornerRadius: 7), with: .color(shirt.opacity(0.85)))
        c.fill(Path(ellipseIn: CGRect(x: 8, y: -6, width: 12, height: 12)), with: .color(Palette.pick(Palette.skins, p.look.skin)))
    }

    // MARK: - Autos

    private func drawCar(_ g: inout GraphicsContext, _ car: Car) {
        var c = g
        c.translateBy(x: car.pos.x, y: car.pos.y)
        c.rotate(by: .radians(Double(car.angle)))

        let body = CGRect(x: -24, y: -13, width: 48, height: 26)
        c.fill(Path(roundedRect: body.offsetBy(dx: 3, dy: 5), cornerRadius: 7), with: .color(.black.opacity(0.3)))

        var color: Color
        switch car.model {
        case .police: color = Color(red: 0.95, green: 0.95, blue: 0.97)
        case .taxi: color = Color(red: 0.98, green: 0.80, blue: 0.10)
        default: color = Palette.pick(Palette.cars, car.colorIndex)
        }
        if car.wrecked { color = Color(red: 0.18, green: 0.16, blue: 0.15) }

        c.fill(Path(roundedRect: body, cornerRadius: 7), with: .color(color))
        if car.model == .police && !car.wrecked {
            c.fill(Path(CGRect(x: -24, y: -13, width: 14, height: 26)), with: .color(Color(red: 0.12, green: 0.18, blue: 0.45)))
            c.fill(Path(CGRect(x: 12, y: -13, width: 10, height: 26)), with: .color(Color(red: 0.12, green: 0.18, blue: 0.45)))
        }
        if car.model == .sports && !car.wrecked {
            c.fill(Path(CGRect(x: -24, y: -3, width: 48, height: 6)), with: .color(.white.opacity(0.7)))
        }

        let glass = Color(red: 0.15, green: 0.22, blue: 0.30)
        let roofRect = car.model == .van ? CGRect(x: -20, y: -11, width: 30, height: 22) : CGRect(x: -11, y: -10, width: 18, height: 20)
        c.fill(Path(roundedRect: CGRect(x: 7, y: -10, width: 8, height: 20), cornerRadius: 3), with: .color(glass))
        if car.model != .van {
            c.fill(Path(roundedRect: CGRect(x: -17, y: -9, width: 6, height: 18), cornerRadius: 2), with: .color(glass))
        }
        c.fill(Path(roundedRect: roofRect, cornerRadius: 3), with: .color(car.wrecked ? color : color.opacity(0.85)))
        c.stroke(Path(roundedRect: roofRect, cornerRadius: 3), with: .color(.black.opacity(0.2)), lineWidth: 1)

        if !car.wrecked {
            c.fill(Path(CGRect(x: 21, y: -11, width: 3, height: 5)), with: .color(.yellow))
            c.fill(Path(CGRect(x: 21, y: 6, width: 3, height: 5)), with: .color(.yellow))
            c.fill(Path(CGRect(x: -24, y: -11, width: 2, height: 5)), with: .color(.red))
            c.fill(Path(CGRect(x: -24, y: 6, width: 2, height: 5)), with: .color(.red))
        }

        switch car.model {
        case .taxi where !car.wrecked:
            c.fill(Path(CGRect(x: -6, y: -5, width: 7, height: 10)), with: .color(.black))
        case .police where !car.wrecked:
            let blink = Int(engine.time * 8) % 2 == 0
            let sirenOn = car.driver == .police || (engine.stars > 0 && !car.deployed)
            c.fill(Path(CGRect(x: -4, y: -10, width: 6, height: 10)),
                   with: .color(sirenOn && blink ? .red : Color(red: 0.5, green: 0.1, blue: 0.1)))
            c.fill(Path(CGRect(x: -4, y: 0, width: 6, height: 10)),
                   with: .color(sirenOn && !blink ? .blue : Color(red: 0.1, green: 0.1, blue: 0.5)))
            if sirenOn {
                let glow = blink ? Color.red : Color.blue
                c.fill(Path(ellipseIn: CGRect(x: -30, y: -30, width: 56, height: 60)), with: .color(glow.opacity(0.15)))
            }
        default:
            break
        }

        if car.hitFlash > 0 {
            c.fill(Path(roundedRect: body, cornerRadius: 7), with: .color(.white.opacity(car.hitFlash * 5)))
        }
        if car === engine.player.car {
            c.stroke(Path(roundedRect: body.insetBy(dx: -3, dy: -3), cornerRadius: 9), with: .color(.yellow.opacity(0.6)), lineWidth: 2)
        }
    }

    // MARK: - Gegenstände, Kugeln, Effekte

    private func drawPickups(_ g: inout GraphicsContext, _ view: CGRect) {
        let e = engine
        for item in e.pickups where item.hiddenUntil <= e.time && view.contains(item.pos) {
            let bob = CGFloat(sin(e.time * 4 + Double(item.pos.x)) * 3)
            let p = item.pos + CGPoint(x: 0, y: bob)
            g.fill(Path(ellipseIn: CGRect(x: item.pos.x - 12, y: item.pos.y + 6, width: 24, height: 8)), with: .color(.black.opacity(0.25)))
            let glow: Color
            let icon: String
            switch item.kind {
            case .cash: glow = .green; icon = "💵"
            case .health: glow = .red; icon = "❤️"
            case .armor: glow = .blue; icon = "🛡️"
            case .weapon: glow = .orange; icon = "📦"
            }
            g.fill(Path(ellipseIn: CGRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32)), with: .color(glow.opacity(0.3)))
            g.draw(Text(icon).font(.system(size: 20)), at: p)
        }
    }

    private func drawBullets(_ g: inout GraphicsContext) {
        var path = Path()
        for b in engine.bullets {
            path.move(to: b.pos - b.vel.normalized * 12)
            path.addLine(to: b.pos)
        }
        g.stroke(path, with: .color(Color(red: 1, green: 0.9, blue: 0.4)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    private func drawEffects(_ g: inout GraphicsContext) {
        for fx in engine.effects {
            let t = CGFloat(fx.age / fx.duration)
            let p = fx.pos
            switch fx.kind {
            case .muzzle:
                let r = 9 * (1 - t) + 2
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(Color(red: 1, green: 0.95, blue: 0.6).opacity(Double(1 - t))))
            case .spark:
                let r: CGFloat = 3
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.yellow.opacity(Double(1 - t))))
            case .blood:
                for i in 0..<3 {
                    let o = CGPoint(angle: CGFloat(i) * 2.1 + CGFloat(p.x), length: 8 * t + 2)
                    let r: CGFloat = 4 * (1 - t) + 1
                    g.fill(Path(ellipseIn: CGRect(x: p.x + o.x - r, y: p.y + o.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(Color(red: 0.7, green: 0.05, blue: 0.05).opacity(Double(1 - t))))
                }
            case .punch:
                let r = 6 + 10 * t
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white.opacity(Double(1 - t))), lineWidth: 2)
            case .explosion:
                let r = 20 + 110 * t
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(Color(red: 1, green: 0.5, blue: 0.1).opacity(Double(1 - t) * 0.8)))
                let r2 = r * 0.6
                g.fill(Path(ellipseIn: CGRect(x: p.x - r2, y: p.y - r2, width: 2 * r2, height: 2 * r2)),
                       with: .color(Color(red: 1, green: 0.9, blue: 0.4).opacity(Double(1 - t))))
            case .smoke:
                let r = 10 + 24 * t
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.gray.opacity(Double(1 - t) * 0.5)))
            case .fire:
                let r = 9 * (1 - t) + 3
                g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                       with: .color((t < 0.4 ? Color.yellow : Color.orange).opacity(Double(1 - t))))
            }
        }
    }

    private func drawProgressRings(_ g: inout GraphicsContext) {
        let e = engine
        let p = e.playerPos
        if let r = e.robbery {
            drawRing(&g, at: p, progress: r.progress / r.duration, color: .green)
        }
        if e.bustProgress > 0.02 {
            drawRing(&g, at: p, progress: e.bustProgress, color: .blue)
        }
    }

    private func drawRing(_ g: inout GraphicsContext, at p: CGPoint, progress: Double, color: Color) {
        g.stroke(Path(ellipseIn: CGRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52)),
                 with: .color(.black.opacity(0.4)), lineWidth: 6)
        var arc = Path()
        arc.addArc(center: p, radius: 26, startAngle: .degrees(-90),
                   endAngle: .degrees(-90 + 360 * min(1, progress)), clockwise: false)
        g.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 6, lineCap: .round))
    }

    private func drawTexts(_ g: inout GraphicsContext, _ view: CGRect) {
        for t in engine.texts where view.contains(t.pos) {
            let color: Color
            switch t.style {
            case .money: color = Color(red: 0.4, green: 1, blue: 0.4)
            case .info: color = .white
            case .danger: color = Color(red: 1, green: 0.35, blue: 0.3)
            }
            let alpha = Double(max(0, 1 - max(0, t.age - 1) / 0.6))
            let text = Text(t.text).font(.system(size: 17, weight: .heavy, design: .rounded))
            g.draw(text.foregroundColor(.black.opacity(alpha * 0.7)), at: t.pos + CGPoint(x: 1.5, y: 1.5))
            g.draw(text.foregroundColor(color.opacity(alpha)), at: t.pos)
        }
    }

    // MARK: - Missionsziel

    private func drawMissionMarker(_ g: inout GraphicsContext) {
        guard let target = engine.missionTarget else { return }
        let pulse = CGFloat(1 + 0.2 * sin(engine.time * 5))
        let r = 30 * pulse
        g.fill(Path(ellipseIn: CGRect(x: target.x - r, y: target.y - r, width: 2 * r, height: 2 * r)),
               with: .color(.yellow.opacity(0.25)))
        g.stroke(Path(ellipseIn: CGRect(x: target.x - r, y: target.y - r, width: 2 * r, height: 2 * r)),
                 with: .color(.yellow), lineWidth: 3)
        var arrow = Path()
        let top = target.y - 46 - CGFloat(6 * sin(engine.time * 5))
        arrow.move(to: CGPoint(x: target.x - 12, y: top))
        arrow.addLine(to: CGPoint(x: target.x + 12, y: top))
        arrow.addLine(to: CGPoint(x: target.x, y: top + 18))
        arrow.closeSubpath()
        g.fill(arrow, with: .color(.yellow))
    }

    private func drawObjectiveArrow(_ context: inout GraphicsContext, size: CGSize) {
        let e = engine
        guard let target = e.missionTarget else { return }
        let screen = (target - e.camera) * e.zoom + CGPoint(x: size.width / 2, y: size.height / 2)
        let inset: CGFloat = 70
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        guard !bounds.contains(screen) else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dir = (screen - center).normalized
        // Punkt am Rand finden
        let sx = dir.x != 0 ? (bounds.width / 2) / abs(dir.x) : .infinity
        let sy = dir.y != 0 ? (bounds.height / 2) / abs(dir.y) : .infinity
        let edge = center + dir * min(sx, sy)

        var c = context
        c.translateBy(x: edge.x, y: edge.y)
        c.rotate(by: .radians(Double(dir.angle)))
        var tri = Path()
        tri.move(to: CGPoint(x: 18, y: 0))
        tri.addLine(to: CGPoint(x: -10, y: -13))
        tri.addLine(to: CGPoint(x: -10, y: 13))
        tri.closeSubpath()
        c.fill(tri, with: .color(.yellow))
        c.stroke(tri, with: .color(.black.opacity(0.6)), lineWidth: 2)
    }
}
