import SwiftUI

struct TitleView: View {
    let onStart: (SaveData?) -> Void

    @State private var save = SaveStore.load()
    @State private var showHelp = false
    @State private var confirmNew = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.35, green: 0.05, blue: 0.25), Color(red: 0.05, green: 0.05, blue: 0.15)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // Skyline
            GeometryReader { geo in
                Canvas { ctx, size in
                    var x: CGFloat = 0
                    var i = 0
                    while x < size.width {
                        let w = CGFloat(40 + (i * 37) % 50)
                        let h = CGFloat(80 + (i * 53) % 160)
                        let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
                        ctx.fill(Path(rect), with: .color(.black.opacity(0.75)))
                        for wy in stride(from: rect.minY + 10, to: rect.maxY - 10, by: 18) {
                            for wx in stride(from: rect.minX + 8, to: rect.maxX - 8, by: 14) where (Int(wx + wy) + i) % 3 != 0 {
                                ctx.fill(Path(CGRect(x: wx, y: wy, width: 6, height: 8)),
                                         with: .color(.yellow.opacity(0.5)))
                            }
                        }
                        x += w + 4
                        i += 1
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 2) {
                    Text("GANGSTER")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                    Text("CITY")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .tracking(16)
                        .foregroundStyle(.white)
                }
                .shadow(color: .black, radius: 0, x: 4, y: 4)

                Text("Ein Spiel von Abdullah Ali")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 16) {
                    if let save {
                        MenuButton(title: "Weiterspielen", subtitle: "$\(save.money) · Mission \(min(save.missions + 1, 8))/8",
                                   color: .green) {
                            onStart(save)
                        }
                        MenuButton(title: "Neues Spiel", subtitle: "Von vorne", color: .orange) {
                            confirmNew = true
                        }
                    } else {
                        MenuButton(title: "Spielen", subtitle: "Neues Spiel", color: .green) {
                            onStart(nil)
                        }
                    }
                    MenuButton(title: "Steuerung", subtitle: "So geht's", color: .blue) {
                        showHelp = true
                    }
                }
            }
            .padding()
        }
        .alert("Neues Spiel starten?", isPresented: $confirmNew) {
            Button("Abbrechen", role: .cancel) {}
            Button("Ja, neu starten", role: .destructive) {
                SaveStore.clear()
                onStart(nil)
            }
        } message: {
            Text("Dein gespeicherter Fortschritt wird gelöscht.")
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }
}

struct MenuButton: View {
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.title3.weight(.heavy))
                Text(subtitle).font(.caption).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(minWidth: 150)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.4), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Bewegen & Kämpfen") {
                    HelpRow(icon: "circle.circle", text: "Joystick links: laufen oder fahren")
                    HelpRow(icon: "scope", text: "Roter Knopf: schießen / zuschlagen (zielt automatisch)")
                    HelpRow(icon: "arrow.triangle.2.circlepath", text: "Waffe wechseln")
                    HelpRow(icon: "car.fill", text: "In ein Auto einsteigen oder aussteigen – auch Autos klauen!")
                }
                Section("Polizei ⭐️") {
                    HelpRow(icon: "star.fill", text: "Verbrechen bringen Fahndungssterne. Je mehr Sterne, desto mehr Polizei.")
                    HelpRow(icon: "eye.slash.fill", text: "Bleib außer Sicht der Polizei, bis die Sterne verschwinden.")
                    HelpRow(icon: "hand.raised.fill", text: "Bei 1 Stern versucht die Polizei, dich zu verhaften – lauf weg!")
                }
                Section("Orte") {
                    HelpRow(icon: "dollarsign.circle.fill", text: "Grüne $-Kreise: Läden, die du ausrauben kannst")
                    HelpRow(icon: "cart.fill", text: "🎯 Waffenladen: Waffen, Munition und Schutzweste kaufen")
                    HelpRow(icon: "cross.case.fill", text: "🏥 Krankenhaus: heilen lassen")
                    HelpRow(icon: "house.fill", text: "🏠 Versteck: Spiel speichern")
                    HelpRow(icon: "iphone", text: "📱 Handy: Missionen starten")
                }
                Section("Tastatur (iPad / Mac)") {
                    HelpRow(icon: "keyboard", text: "WASD / Pfeile: bewegen · Leertaste: schießen")
                    HelpRow(icon: "keyboard", text: "E: Auto · Q: Waffe · R: Aktion · M: Handy · P: Pause")
                }
            }
            .navigationTitle("Steuerung")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

private struct HelpRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(.orange)
        }
    }
}
