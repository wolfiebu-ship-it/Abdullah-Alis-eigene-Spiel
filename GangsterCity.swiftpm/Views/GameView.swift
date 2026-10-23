import SwiftUI

/// Der Spielbildschirm: Welt, Anzeigen und Steuerung.
struct GameView: View {
    let engine: GameEngine
    let onQuit: () -> Void

    @State private var paused = false
    @State private var showShop = false
    @State private var showPhone = false
    @FocusState private var focused: Bool

    private var isPaused: Bool { paused || showShop || showPhone }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { timeline in
                ZStack {
                    Canvas { context, size in
                        engine.tick(to: timeline.date, size: size)
                        GameRenderer(engine: engine).draw(in: &context, size: size)
                    }
                    .ignoresSafeArea()

                    HUDView(engine: engine, now: timeline.date,
                            onPhone: { openPhone() },
                            onPause: { pause() })

                    ControlsView(engine: engine, now: timeline.date,
                                 onInteract: { interact() })

                    OverlayView(engine: engine, now: timeline.date)
                }
            }

            if paused {
                PauseView(engine: engine,
                          onResume: { resume() },
                          onQuit: onQuit)
            }
            if showShop {
                ShopView(engine: engine) {
                    showShop = false
                    resume()
                }
            }
            if showPhone {
                PhoneView(engine: engine) {
                    showPhone = false
                    resume()
                }
            }
        }
        .background(Color.black)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .up]) { press in
            handleKey(press)
        }
        .onAppear { focused = true }
    }

    // MARK: - Aktionen

    private func pause() {
        engine.input = InputState()
        paused = true
    }

    private func resume() {
        paused = false
        engine.resetClock()
        focused = true
    }

    private func openPhone() {
        engine.input = InputState()
        showPhone = true
    }

    private func interact() {
        guard let action = engine.interaction else { return }
        if action == .gunShop {
            engine.input = InputState()
            showShop = true
        } else {
            engine.perform(action)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let down = press.phase == .down
        var direction: String?
        switch press.key {
        case .upArrow: direction = "up"
        case .downArrow: direction = "down"
        case .leftArrow: direction = "left"
        case .rightArrow: direction = "right"
        default: break
        }
        let char = press.characters.lowercased()
        switch char {
        case "w": direction = "up"
        case "s": direction = "down"
        case "a": direction = "left"
        case "d": direction = "right"
        default: break
        }
        if let direction {
            if down { engine.input.keys.insert(direction) } else { engine.input.keys.remove(direction) }
            return .handled
        }
        if char == " " {
            engine.input.keyFiring = down
            return .handled
        }
        guard down, !isPaused || char == "p" else { return .ignored }
        switch char {
        case "e", "f": engine.toggleCar()
        case "q": engine.cycleWeapon()
        case "r": interact()
        case "m": openPhone()
        case "p": paused ? resume() : pause()
        default: return .ignored
        }
        return .handled
    }
}

// MARK: - Steuerung

struct ControlsView: View {
    let engine: GameEngine
    let now: Date
    let onInteract: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                Joystick { engine.input.stick = $0 }
                    .padding(.leading, 8)

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    if let action = engine.interaction {
                        Button(action: onInteract) {
                            Label(action.label, systemImage: action.symbol)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(actionColor(action).gradient, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(spacing: 12) {
                            if engine.isInCar || engine.canEnterCar {
                                RoundButton(symbol: engine.isInCar ? "figure.walk" : "car.fill",
                                            label: engine.isInCar ? "Raus" : "Einsteigen",
                                            color: .blue, size: 58) {
                                    engine.toggleCar()
                                }
                            }
                            RoundButton(symbol: "arrow.triangle.2.circlepath",
                                        label: "Waffe", color: .gray, size: 58) {
                                engine.cycleWeapon()
                            }
                        }
                        FireButton(engine: engine)
                    }
                }
                .padding(.trailing, 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func actionColor(_ action: Interaction) -> Color {
        switch action {
        case .rob, .mug: .green
        case .gunShop: .orange
        case .heal: .red
        case .save: .teal
        }
    }
}

struct Joystick: View {
    let onChange: (CGPoint) -> Void

    @State private var knob: CGSize = .zero
    private let radius: CGFloat = 62

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.10))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 2))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(.white.opacity(0.55))
                .frame(width: 54, height: 54)
                .offset(knob)
        }
        .frame(width: radius * 2 + 50, height: radius * 2 + 50)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var d = CGPoint(x: value.location.x - (radius + 25), y: value.location.y - (radius + 25))
                    if d.length > radius { d = d.normalized * radius }
                    knob = CGSize(width: d.x, height: d.y)
                    onChange(d / radius)
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(.zero)
                }
        )
    }
}

struct FireButton: View {
    let engine: GameEngine
    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill((pressed ? Color.red : Color.red.opacity(0.75)).gradient)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 3))
            VStack(spacing: 2) {
                Image(systemName: engine.player.weapon == .fist ? "hand.raised.fill" : "scope")
                    .font(.system(size: 30, weight: .bold))
                Text(engine.player.weapon == .fist ? "Schlagen" : "Feuer")
                    .font(.caption.weight(.heavy))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 92, height: 92)
        .scaleEffect(pressed ? 0.92 : 1)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    pressed = true
                    engine.input.touchFiring = true
                }
                .onEnded { _ in
                    pressed = false
                    engine.input.touchFiring = false
                }
        )
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    let color: Color
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: size * 0.33, weight: .bold))
                Text(label).font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.opacity(0.8).gradient, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
