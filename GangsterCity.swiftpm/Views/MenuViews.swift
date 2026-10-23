import SwiftUI

/// Gemeinsamer Rahmen für Menüs im Spiel.
struct GamePanel<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").font(.title)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding()
                ScrollView {
                    content.padding([.horizontal, .bottom])
                }
            }
            .frame(maxWidth: 560, maxHeight: 360)
            .background(Color(red: 0.12, green: 0.12, blue: 0.16), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.2), lineWidth: 1.5))
            .padding()
        }
    }
}

// MARK: - Waffenladen

struct ShopView: View {
    let engine: GameEngine
    let onClose: () -> Void
    /// Zwingt die Ansicht nach einem Kauf zum Neuzeichnen.
    @State private var refresh = 0
    @State private var message = "Was darf's sein?"

    var body: some View {
        GamePanel(title: "🎯 Waffenladen", onClose: onClose) {
            VStack(spacing: 10) {
                HStack {
                    Text(message).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("$\(engine.player.money)")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
                .id(refresh)

                ForEach(Weapon.allCases.filter { !$0.isMelee }) { weapon in
                    weaponRow(weapon)
                }

                HStack {
                    Image(systemName: "shield.fill").font(.title2).foregroundStyle(.blue).frame(width: 36)
                    VStack(alignment: .leading) {
                        Text("Schutzweste").font(.headline)
                        Text("Fängt Treffer ab").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    shopButton("$\(GameEngine.armorCost)", enabled: engine.player.armor < 100) {
                        if engine.buyArmor() { message = "Gut geschützt!" } else { message = "Zu wenig Geld!" }
                    }
                }
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            .foregroundStyle(.white)
        }
    }

    private func weaponRow(_ weapon: Weapon) -> some View {
        let owned = engine.player.owns(weapon)
        return HStack {
            Image(systemName: weapon.symbol).font(.title2).foregroundStyle(.orange).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(weapon.name).font(.headline)
                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(i < weapon.power ? Color.red : Color.white.opacity(0.2))
                    }
                    if owned {
                        Text("  Munition: \(engine.player.ammo[weapon] ?? 0)")
                            .font(.caption).foregroundStyle(.yellow)
                    }
                }
            }
            Spacer()
            if owned {
                shopButton("+\(weapon.ammoPack) Schuss $\(weapon.ammoPrice)", enabled: true) {
                    message = engine.buyAmmo(weapon) ? "Munition gekauft!" : "Zu wenig Geld!"
                }
            } else {
                shopButton("Kaufen $\(weapon.price)", enabled: true) {
                    message = engine.buyWeapon(weapon) ? "\(weapon.name) gehört jetzt dir!" : "Zu wenig Geld!"
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .id("\(weapon.rawValue)-\(refresh)")
    }

    private func shopButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            refresh += 1
        } label: {
            Text(title)
                .font(.subheadline.weight(.heavy))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((enabled ? Color.orange : Color.gray).gradient, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Handy (Missionen)

struct PhoneView: View {
    let engine: GameEngine
    let onClose: () -> Void

    var body: some View {
        GamePanel(title: "📱 Missionen", onClose: onClose) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(engine.missions.enumerated()), id: \.offset) { index, mission in
                    missionRow(index: index, mission: mission)
                }
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func missionRow(index: Int, mission: MissionDef) -> some View {
        let done = index < engine.completedMissions
        let current = index == engine.completedMissions
        let running = engine.mission?.index == index

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: done ? "checkmark.circle.fill" : current ? "star.circle.fill" : "lock.fill")
                    .foregroundStyle(done ? Color.green : current ? Color.yellow : Color.gray)
                Text("\(index + 1). \(mission.title)").font(.headline)
                Spacer()
                Text("$\(mission.reward)").font(.subheadline.weight(.bold)).foregroundStyle(.green)
            }
            if current {
                Text(mission.briefing)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if running {
                    Button {
                        engine.abortMission()
                        onClose()
                    } label: {
                        Label("Mission abbrechen", systemImage: "xmark")
                            .font(.subheadline.weight(.heavy))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.red.gradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        engine.startMission()
                        onClose()
                    } label: {
                        Label("Mission starten", systemImage: "play.fill")
                            .font(.subheadline.weight(.heavy))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.green.gradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(current ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12))
        .opacity(done || current ? 1 : 0.6)

        if engine.completedMissions >= engine.missions.count && index == engine.missions.count - 1 {
            Text("👑 Du hast alle Missionen geschafft! Die Stadt gehört dir – mach, was du willst.")
                .font(.headline)
                .foregroundStyle(.yellow)
                .padding(.top, 4)
        }
    }
}

// MARK: - Pause

struct PauseView: View {
    let engine: GameEngine
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        GamePanel(title: "⏸ Pause", onClose: onResume) {
            VStack(spacing: 12) {
                MenuButton(title: "Weiter", subtitle: "Zurück ins Spiel", color: .green, action: onResume)
                MenuButton(title: "Hauptmenü", subtitle: "Nicht gespeicherter Fortschritt geht verloren",
                           color: .red, action: onQuit)
                Text("Tipp: Im Versteck 🏠 kannst du speichern. Nach jeder Mission wird automatisch gespeichert.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
