import SwiftUI

/// Anzeigen am Bildschirmrand: Geld, Leben, Waffe, Sterne, Mission, Minikarte.
struct HUDView: View {
    let engine: GameEngine
    let now: Date
    let onPhone: () -> Void
    let onPause: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                StatusPanel(engine: engine)
                Spacer(minLength: 8)
                ObjectivePanel(engine: engine)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 8) {
                        WantedStars(engine: engine)
                        HUDIconButton(symbol: "iphone", badge: engine.isMissionAvailable, action: onPhone)
                        HUDIconButton(symbol: "pause.fill", badge: false, action: onPause)
                    }
                    MiniMap(engine: engine)
                        .frame(width: 112, height: 112)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

private struct StatusPanel: View {
    let engine: GameEngine

    var body: some View {
        let p = engine.player
        VStack(alignment: .leading, spacing: 4) {
            Text("$\(p.money)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 1, blue: 0.45))
                .shadow(color: .black, radius: 0, x: 2, y: 2)
                .monospacedDigit()
            Bar(value: p.health / 100, color: .red, symbol: "heart.fill")
            if p.armor > 0 {
                Bar(value: p.armor / 100, color: .blue, symbol: "shield.fill")
            }
            HStack(spacing: 6) {
                Image(systemName: p.weapon.symbol)
                Text(p.weapon.shortName)
                if p.weapon != .fist {
                    Text("\(p.currentAmmo)").monospacedDigit()
                        .foregroundStyle(p.currentAmmo == 0 ? Color.red : Color.yellow)
                }
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
        }
    }
}

private struct Bar: View {
    let value: CGFloat
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.5))
                Capsule().fill(color.gradient)
                    .frame(width: 110 * clamp(value, 0, 1))
            }
            .frame(width: 110, height: 9)
        }
    }
}

private struct WantedStars: View {
    let engine: GameEngine

    var body: some View {
        let stars = engine.stars
        let evading = stars > 0 && !engine.copsSeePlayer
        let blinkOn = Int(engine.time * 4) % 2 == 0
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "star.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(i < stars ? Color.yellow : Color.white.opacity(0.22))
                        .opacity(i < stars && evading && !blinkOn ? 0.35 : 1)
                }
            }
            .shadow(color: .black, radius: 0, x: 1, y: 1)
            if evading {
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.5))
                    Capsule().fill(Color.yellow)
                        .frame(width: 92 * clamp(engine.evadeTimer / engine.evadeDuration, 0, 1))
                }
                .frame(width: 92, height: 5)
            }
        }
    }
}

private struct ObjectivePanel: View {
    let engine: GameEngine

    var body: some View {
        if let objective = engine.currentObjective {
            VStack(spacing: 2) {
                Text(objective.text)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                if let t = engine.objectiveTimeLeft {
                    Text(String(format: "⏱ %d:%02d", Int(t) / 60, Int(t) % 60))
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(t < 10 ? Color.red : Color.yellow)
                        .monospacedDigit()
                }
                if case .survive(_, let seconds) = objective.kind, let m = engine.mission {
                    Text("Noch \(max(0, Int(seconds - m.stepTime))) s")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.yellow.opacity(0.6), lineWidth: 1.5))
            .frame(maxWidth: 320)
        }
    }
}

private struct HUDIconButton: View {
    let symbol: String
    let badge: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(.red).frame(width: 11, height: 11)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Kleine Karte der ganzen Stadt.
struct MiniMap: View {
    let engine: GameEngine

    var body: some View {
        Canvas { ctx, size in
            let w = engine.world
            let scale = size.width / w.size.width
            func map(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }
            func dot(_ p: CGPoint, _ r: CGFloat, _ color: Color) {
                let m = map(p)
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            }

            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.road))
            for by in 0..<World.blockCount {
                for bx in 0..<World.blockCount {
                    let block = CGRect(x: CGFloat(bx * World.period + 2) * World.tileSize * scale,
                                       y: CGFloat(by * World.period + 2) * World.tileSize * scale,
                                       width: 6 * World.tileSize * scale, height: 6 * World.tileSize * scale)
                    let color: Color
                    switch w.blockKind(bx, by) {
                    case .park: color = Palette.grass
                    case .building: color = Color(white: 0.45)
                    case .location(let kind): color = Palette.roof(kind)
                    }
                    ctx.fill(Path(block), with: .color(color))
                }
            }

            let blink = Int(engine.time * 6) % 2 == 0
            if engine.stars > 0 {
                for p in engine.people where p.faction == .police && !p.isDead {
                    dot(p.pos, 2, blink ? .red : .blue)
                }
                for c in engine.cars where c.driver == .police {
                    dot(c.pos, 3, blink ? .blue : .red)
                }
            }
            for p in engine.people where p.faction == .gang && p.gangGroup != nil && !p.isDead {
                dot(p.pos, 2.5, .red)
            }
            if let target = engine.missionTarget {
                dot(target, blink ? 5 : 4, .yellow)
            }

            // Spieler als Pfeil
            let pp = map(engine.playerPos)
            var c = ctx
            c.translateBy(x: pp.x, y: pp.y)
            c.rotate(by: .radians(Double(engine.player.facing)))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 6, y: 0))
            arrow.addLine(to: CGPoint(x: -4, y: -4))
            arrow.addLine(to: CGPoint(x: -4, y: 4))
            arrow.closeSubpath()
            c.fill(arrow, with: .color(.white))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.5), lineWidth: 1.5))
        .opacity(0.9)
    }
}

/// Große Meldungen: Missionen, ERLEDIGT, VERHAFTET.
struct OverlayView: View {
    let engine: GameEngine
    let now: Date

    var body: some View {
        ZStack {
            if let outcome = engine.outcome {
                Color.black.opacity(min(0.6, engine.outcomeTime * 0.3))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                Text(outcome == .wasted ? "ERLEDIGT" : "VERHAFTET")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(outcome == .wasted ? Color.red : Color.blue)
                    .shadow(color: .black, radius: 0, x: 4, y: 4)
                    .scaleEffect(CGFloat(1 + max(0, 0.3 - engine.outcomeTime * 0.3)))
            } else if let banner = engine.banner {
                VStack(spacing: 4) {
                    Text(banner.title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(color(for: banner.style))
                        .multilineTextAlignment(.center)
                    Text(banner.subtitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .shadow(color: .black, radius: 0, x: 2, y: 2)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 110)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }

    private func color(for style: BannerStyle) -> Color {
        switch style {
        case .success: .yellow
        case .failure: .red
        case .info: .orange
        }
    }
}
