import Foundation
import CoreGraphics

// MARK: - Hilfstypen

struct InputState {
    /// Joystick (-1...1 in beide Richtungen).
    var stick: CGPoint = .zero
    /// Gedrückte Richtungstasten ("up", "down", "left", "right").
    var keys: Set<String> = []
    var touchFiring = false
    var keyFiring = false

    var move: CGPoint {
        var k = CGPoint.zero
        if keys.contains("up") { k.y -= 1 }
        if keys.contains("down") { k.y += 1 }
        if keys.contains("left") { k.x -= 1 }
        if keys.contains("right") { k.x += 1 }
        let v = stick + k
        return v.length > 1 ? v.normalized : v
    }

    var wantsFire: Bool { touchFiring || keyFiring }
}

enum Interaction: Equatable {
    case rob(LocationKind), gunShop, heal, save, mug

    var label: String {
        switch self {
        case .rob: "Ausrauben"
        case .gunShop: "Waffenladen"
        case .heal: "Heilen $\(GameEngine.healCost)"
        case .save: "Speichern"
        case .mug: "Abziehen"
        }
    }

    var symbol: String {
        switch self {
        case .rob: "dollarsign.circle.fill"
        case .gunShop: "cart.fill"
        case .heal: "cross.case.fill"
        case .save: "square.and.arrow.down.fill"
        case .mug: "hand.raised.fill"
        }
    }
}

enum Outcome {
    case wasted, busted
}

enum BannerStyle {
    case success, failure, info
}

struct Banner {
    var title: String
    var subtitle: String
    var until: Double
    var style: BannerStyle
}

struct Robbery {
    let kind: LocationKind
    var progress: Double
    let duration: Double
}

// MARK: - Engine

/// Die komplette Spiellogik. Wird jedes Bild von der GameView mit `tick` angetrieben.
final class GameEngine {
    static let starHeat: [Double] = [1, 4, 9, 16, 26]
    static let healCost = 100
    static let armorCost = 250

    let world: World
    let player: Player
    let missions: [MissionDef]

    private(set) var people: [Person] = []
    private(set) var cars: [Car] = []
    private(set) var bullets: [Bullet] = []
    private(set) var pickups: [Pickup] = []
    private(set) var effects: [Effect] = []
    private(set) var texts: [FloatText] = []
    var input = InputState()

    private(set) var time: Double = 0
    private var lastDate: Date?
    private(set) var camera: CGPoint = .zero
    private(set) var zoom: CGFloat = 1
    private var viewSize = CGSize(width: 844, height: 390)
    private var firstFrame = true

    private(set) var heat: Double = 0
    private(set) var evadeTimer: Double = 0
    private(set) var copsSeePlayer = false
    private var bustTimer: Double = 0
    private var bustContact = false

    private(set) var robbery: Robbery?
    private var shopCooldown: [LocationKind: Double] = [:]
    private(set) var outcome: Outcome?
    private(set) var outcomeTime: Double = 0
    private(set) var banner: Banner?

    private(set) var completedMissions: Int
    private(set) var mission: ActiveMission?
    private var robbedEvents: [LocationKind] = []

    private var flow: [Int32] = []
    private var flowTimer: Double = 0
    private var spawnTimer: Double = 0
    private var nextID = 1

    init(save: SaveData?) {
        let w = World()
        let ms = Missions.make(in: w)
        world = w
        missions = ms
        player = Player(pos: w.door(.safehouse))
        completedMissions = min(save?.missions ?? 0, ms.count)

        if let save {
            player.money = save.money
            player.armor = CGFloat(save.armor)
            var ammo: [Weapon: Int] = [.fist: 0]
            for (raw, count) in save.ammo {
                if let weapon = Weapon(rawValue: raw) { ammo[weapon] = count }
            }
            player.ammo = ammo
            player.weapon = player.ownedWeapons.last ?? .fist
        }
        camera = player.pos
        populate()
        showBanner("GANGSTER CITY", completedMissions < missions.count
                   ? "Tippe auf das Handy 📱 für deine nächste Mission"
                   : "Die Stadt gehört dir!", style: .info, seconds: 4)
    }

    // MARK: - Öffentliche Werte für die Anzeige

    var playerPos: CGPoint { player.car?.pos ?? player.pos }

    var stars: Int {
        var s = 0
        for (i, h) in Self.starHeat.enumerated() where heat >= h { s = i + 1 }
        return s
    }

    var evadeDuration: Double { 5 + 2.5 * Double(stars) }
    var bustProgress: Double { bustTimer / 1.6 }
    var isInCar: Bool { player.car != nil }
    var isMissionAvailable: Bool { mission == nil && completedMissions < missions.count }

    var currentObjective: Objective? {
        guard let m = mission else { return nil }
        return missions[m.index].objectives[m.step]
    }

    var objectiveTimeLeft: Double? {
        guard let m = mission, let limit = currentObjective?.timeLimit else { return nil }
        return max(0, limit - m.stepTime)
    }

    func cooldown(of kind: LocationKind) -> Double {
        max(0, (shopCooldown[kind] ?? 0) - time)
    }

    /// Wohin der Missionspfeil zeigt.
    var missionTarget: CGPoint? {
        guard let obj = currentObjective else { return nil }
        switch obj.kind {
        case .reach(let p, _): return p
        case .rob(let kind): return world.door(kind)
        case .buy: return world.door(.gunShop)
        case .enterCar:
            return player.car == nil ? nearestCar(maxDistance: 2000, onlyEmpty: true)?.pos : nil
        case .eliminateGang:
            let group = missionGroup
            return people
                .filter { $0.gangGroup == group && !$0.isDead }
                .min { $0.pos.distance(to: playerPos) < $1.pos.distance(to: playerPos) }?.pos
        case .loseWanted, .survive:
            return nil
        }
    }

    /// Was der Spieler hier gerade tun kann (für den Aktionsknopf).
    var interaction: Interaction? {
        guard player.car == nil, outcome == nil, robbery == nil else { return nil }
        for kind in LocationKind.allCases where player.pos.distance(to: world.door(kind)) < 60 {
            switch kind {
            case .gunShop: return .gunShop
            case .hospital: return .heal
            case .safehouse: return .save
            default:
                if kind.isRobbable && cooldown(of: kind) <= 0 { return .rob(kind) }
            }
        }
        if nearestCivilian(within: 40) != nil { return .mug }
        return nil
    }

    var canEnterCar: Bool {
        player.car == nil && outcome == nil && nearestCar(maxDistance: 58, onlyEmpty: false) != nil
    }

    // MARK: - Zeit

    func tick(to date: Date, size: CGSize) {
        viewSize = size
        guard let last = lastDate else {
            lastDate = date
            return
        }
        lastDate = date
        let dt = min(date.timeIntervalSince(last), 1.0 / 20.0)
        guard dt > 0 else { return }
        update(dt)
    }

    /// Nach einer Pause aufrufen, damit kein riesiger Zeitsprung entsteht.
    func resetClock() { lastDate = nil }

    private func update(_ dt: Double) {
        time += dt
        if let b = banner, b.until < time { banner = nil }

        if outcome != nil {
            outcomeTime += dt
            updateEffects(dt)
            updateCamera(dt)
            if outcomeTime > 3.5 { respawn() }
            return
        }

        flowTimer -= dt
        if flowTimer <= 0 {
            flow = world.flowField(to: playerPos)
            flowTimer = 0.35
        }

        bustContact = false
        updatePlayer(dt)
        updatePeople(dt)
        updateCars(dt)
        updateBullets(dt)
        updatePickups()
        updateRobbery(dt)
        updateWanted(dt)
        updateMission(dt)
        robbedEvents.removeAll()
        updateSpawning(dt)
        updateEffects(dt)
        updateCamera(dt)

        if player.health <= 0 && outcome == nil {
            setOutcome(.wasted)
        }
    }

    // MARK: - Spieler

    private func updatePlayer(_ dt: Double) {
        let f = CGFloat(dt)
        player.fireCooldown -= dt
        player.hitFlash = max(0, player.hitFlash - dt)
        let move = input.move

        if let car = player.car {
            drive(car, toward: move.length > 0.15 ? move : nil,
                  throttle: min(1, move.length * 1.25), maxSpeed: car.model.maxSpeed, dt: dt)
            player.pos = car.pos
            player.facing = car.angle
            player.moving = false
        } else {
            let v = move * 175
            player.pos += v * f
            world.resolve(&player.pos, radius: player.radius)
            for car in cars {
                pushOut(&player.pos, radius: player.radius, from: car)
            }
            player.moving = v.length > 5
            if player.moving {
                player.walkPhase += v.length * f * 0.15
                player.facing = v.angle
            }
        }

        if input.wantsFire { playerFire() }
    }

    private func playerFire() {
        guard player.fireCooldown <= 0 else { return }
        var weapon = player.weapon
        if !weapon.isMelee && player.currentAmmo <= 0 {
            float("Keine Munition!", at: playerPos, style: .danger)
            player.weapon = .fist
            weapon = .fist
            player.fireCooldown = 0.4
            return
        }
        player.fireCooldown = weapon.cooldown

        let origin = playerPos
        let target = autoTarget(range: weapon.isMelee ? 60 : weapon.range)
        let aim = target.map { ($0.pos - origin).angle } ?? player.facing
        if player.car == nil { player.facing = aim }

        if weapon.isMelee {
            guard player.car == nil else { return }
            let reach = origin + CGPoint(angle: aim, length: 22)
            effects.append(Effect(pos: reach, kind: .punch, duration: 0.15))
            if let victim = people.first(where: { !$0.isDead && $0.pos.distance(to: reach) < $0.radius + 16 }) {
                damage(victim, amount: weapon.damage, from: origin, byPlayer: true)
            }
            return
        }

        player.ammo[weapon] = max(0, player.currentAmmo - 1)
        let muzzle = origin + CGPoint(angle: aim, length: player.car == nil ? 20 : 30)
        for _ in 0..<weapon.pellets {
            let a = aim + CGFloat.random(in: -weapon.spread...weapon.spread)
            bullets.append(Bullet(pos: muzzle, vel: CGPoint(angle: a, length: weapon.bulletSpeed),
                                  life: Double(weapon.range / weapon.bulletSpeed) + 0.05,
                                  damage: weapon.damage, owner: .player))
        }
        effects.append(Effect(pos: muzzle, kind: .muzzle, duration: 0.07))

        // Schüsse machen Passanten Angst – und Streifenpolizisten hellhörig.
        for p in people where !p.isDead && p.pos.distance(to: origin) < 450 {
            if p.faction == .civilian {
                p.panic = 5
                p.panicFrom = origin
            } else if p.faction == .police && stars == 0 && world.lineOfSight(p.pos, origin) {
                addHeat(1)
            }
        }
    }

    /// Automatisches Zielen: zuerst Gegner, sonst wer vor einem steht.
    private func autoTarget(range: CGFloat) -> Person? {
        let origin = playerPos
        var best: Person?
        var bestScore = CGFloat.infinity
        for p in people where !p.isDead {
            let d = p.pos.distance(to: origin)
            guard d < range else { continue }
            let hostile = (p.faction == .police && stars > 0) || (p.faction == .gang && (p.aggro || p.gangGroup != nil))
            let angleOff = abs(angleDiff((p.pos - origin).angle, player.facing))
            if !hostile && angleOff > 0.6 { continue }
            guard world.lineOfSight(origin, p.pos) else { continue }
            let score = hostile ? d * 0.5 : d + angleOff * 200
            if score < bestScore {
                bestScore = score
                best = p
            }
        }
        return best
    }

    func cycleWeapon() {
        let owned = player.ownedWeapons
        guard owned.count > 1, let i = owned.firstIndex(of: player.weapon) else { return }
        player.weapon = owned[(i + 1) % owned.count]
    }

    func toggleCar() {
        guard outcome == nil else { return }
        if let car = player.car {
            car.driver = .none
            var p = car.pos + car.forward.perpendicular * -34
            world.resolve(&p, radius: player.radius)
            player.pos = p
            player.car = nil
            return
        }
        guard robbery == nil, let car = nearestCar(maxDistance: 58, onlyEmpty: false) else { return }
        if car.driver == .traffic || car.driver == .police {
            // Fahrer rauswerfen!
            let ped = spawnPerson(car.driver == .police ? .police : .civilian,
                                  at: car.pos + car.forward.perpendicular * -30)
            if ped.faction == .civilian {
                ped.panic = 6
                ped.panicFrom = car.pos
            }
            addHeat(car.driver == .police ? 3 : (copNearby(400) ? 1 : 0))
            float("Auto geklaut!", at: car.pos, style: .info)
        }
        car.driver = .player
        player.car = car
        robbery = nil
    }

    // MARK: - Interaktionen

    func perform(_ action: Interaction) {
        switch action {
        case .rob(let kind):
            guard cooldown(of: kind) <= 0 else { return }
            robbery = Robbery(kind: kind, progress: 0, duration: kind.robDuration)
            addHeat(1)
            float("Hände hoch! Kasse auf!", at: player.pos, style: .danger)
        case .heal:
            guard player.money >= Self.healCost, player.health < 100 else {
                float(player.health >= 100 ? "Du bist gesund" : "Zu wenig Geld", at: player.pos, style: .info)
                return
            }
            player.money -= Self.healCost
            player.health = 100
            float("Geheilt!", at: player.pos, style: .info)
        case .save:
            saveGame()
            showBanner("GESPEICHERT", "Dein Fortschritt ist sicher.", style: .info, seconds: 2)
        case .mug:
            guard let victim = nearestCivilian(within: 40) else { return }
            let amount = Int.random(in: 10...60)
            player.money += amount
            victim.panic = 6
            victim.panicFrom = player.pos
            victim.knock = (victim.pos - player.pos).normalized * 200
            addHeat(copNearby(450) ? 2 : 0.6)
            float("+$\(amount)", at: victim.pos, style: .money)
        case .gunShop:
            break // Laden wird von der Oberfläche geöffnet.
        }
    }

    @discardableResult
    func buyWeapon(_ w: Weapon) -> Bool {
        guard !player.owns(w), player.money >= w.price else { return false }
        player.money -= w.price
        player.ammo[w] = w.ammoPack
        player.weapon = w
        return true
    }

    @discardableResult
    func buyAmmo(_ w: Weapon) -> Bool {
        guard player.owns(w), !w.isMelee, player.money >= w.ammoPrice else { return false }
        player.money -= w.ammoPrice
        player.ammo[w, default: 0] += w.ammoPack
        return true
    }

    @discardableResult
    func buyArmor() -> Bool {
        guard player.armor < 100, player.money >= Self.armorCost else { return false }
        player.money -= Self.armorCost
        player.armor = 100
        return true
    }

    func saveGame() {
        var ammo: [Int: Int] = [:]
        for (w, n) in player.ammo { ammo[w.rawValue] = n }
        SaveStore.save(SaveData(money: player.money, ammo: ammo,
                                missions: completedMissions, armor: Double(player.armor)))
    }

    // MARK: - Missionen

    private var missionGroup: Int { 1000 + (mission?.index ?? 0) }

    func startMission() {
        guard isMissionAvailable else { return }
        mission = ActiveMission(index: completedMissions)
        let def = missions[completedMissions]
        showBanner(def.title.uppercased(), def.objectives[0].text, style: .info, seconds: 3.5)
        beginStep()
    }

    func abortMission() {
        guard mission != nil else { return }
        failMission("Abgebrochen")
    }

    private func beginStep() {
        guard let obj = currentObjective else { return }
        switch obj.setup {
        case .none:
            break
        case .spawnGang(let at, let count, let boss):
            spawnGang(at: at, count: count, boss: boss, group: missionGroup)
        case .wanted(let s):
            heat = max(heat, Self.starHeat[s - 1])
            float("Die Polizei ist hinter dir her!", at: playerPos, style: .danger)
        }
    }

    private func updateMission(_ dt: Double) {
        guard var m = mission, let obj = currentObjective else { return }
        m.stepTime += dt
        mission = m

        if let limit = obj.timeLimit, m.stepTime > limit {
            failMission("Die Zeit ist abgelaufen!")
            return
        }

        let done: Bool
        switch obj.kind {
        case .reach(let p, let needsCar):
            done = playerPos.distance(to: p) < 70 && (!needsCar || player.car != nil)
        case .rob(let kind):
            done = robbedEvents.contains(kind)
        case .buy(let w):
            done = player.owns(w)
        case .enterCar:
            done = player.car != nil
        case .eliminateGang:
            let group = missionGroup
            done = !people.contains { $0.gangGroup == group && !$0.isDead }
        case .loseWanted:
            done = stars == 0
        case .survive(let s, let seconds):
            heat = max(heat, Self.starHeat[s - 1])
            done = m.stepTime >= seconds
        }
        guard done else { return }

        m.step += 1
        m.stepTime = 0
        let def = missions[m.index]
        if m.step >= def.objectives.count {
            completeMission()
        } else {
            mission = m
            showBanner("NEUES ZIEL", def.objectives[m.step].text, style: .info, seconds: 2.5)
            beginStep()
        }
    }

    private func completeMission() {
        guard let m = mission else { return }
        let def = missions[m.index]
        mission = nil
        completedMissions = m.index + 1
        player.money += def.reward
        float("+$\(def.reward)", at: playerPos, style: .money)
        if completedMissions >= missions.count {
            showBanner("DU BIST DER KÖNIG DER STADT!", "Alle Missionen geschafft! +$\(def.reward)", style: .success, seconds: 6)
        } else {
            showBanner("MISSION ERFÜLLT!", "\(def.title)  +$\(def.reward)", style: .success, seconds: 4)
        }
        saveGame()
    }

    private func failMission(_ reason: String) {
        guard mission != nil else { return }
        let group = missionGroup
        people.removeAll { $0.gangGroup == group }
        mission = nil
        showBanner("MISSION GESCHEITERT", reason, style: .failure, seconds: 4)
    }

    // MARK: - Fahndung

    func addHeat(_ amount: Double) {
        guard amount > 0 else { return }
        let before = stars
        heat = min(heat + amount, 40)
        evadeTimer = 0
        if stars > before && before == 0 {
            float("Die Polizei sucht dich!", at: playerPos, style: .danger)
        }
    }

    private func copNearby(_ distance: CGFloat) -> Bool {
        people.contains { $0.faction == .police && !$0.isDead && $0.pos.distance(to: playerPos) < distance }
    }

    private func updateWanted(_ dt: Double) {
        let s = stars
        if bustContact && s == 1 {
            bustTimer += dt
            if bustTimer > 1.6 { setOutcome(.busted) }
        } else {
            bustTimer = max(0, bustTimer - dt * 2)
        }

        guard s > 0 else {
            evadeTimer = 0
            copsSeePlayer = false
            return
        }
        let pos = playerPos
        copsSeePlayer = people.contains { p in
            p.faction == .police && !p.isDead && p.pos.distance(to: pos) < 520 && world.lineOfSight(p.pos, pos)
        } || cars.contains { c in
            c.driver == .police && c.pos.distance(to: pos) < 420 && world.lineOfSight(c.pos, pos)
        }

        if copsSeePlayer || robbery != nil {
            evadeTimer = 0
        } else {
            evadeTimer += dt
            if evadeTimer >= evadeDuration && !isSurviveMission {
                heat = 0
                evadeTimer = 0
                for p in people where p.faction == .police { p.chasing = false }
                showBanner("ENTKOMMEN!", "Die Polizei hat deine Spur verloren.", style: .success, seconds: 2.5)
            }
        }
    }

    private var isSurviveMission: Bool {
        if case .survive? = currentObjective?.kind { return true }
        return false
    }

    private func setOutcome(_ o: Outcome) {
        outcome = o
        outcomeTime = 0
        robbery = nil
        input.touchFiring = false
        if let car = player.car {
            car.driver = .none
            player.pos = car.pos + car.forward.perpendicular * -30
            world.resolve(&player.pos, radius: player.radius)
            player.car = nil
        }
        if mission != nil {
            failMission(o == .wasted ? "Du bist gestorben." : "Du wurdest verhaftet.")
        }
    }

    private func respawn() {
        guard let o = outcome else { return }
        outcome = nil
        heat = 0
        evadeTimer = 0
        bustTimer = 0
        let fee = min(player.money, 100)
        player.money -= fee
        player.health = 100
        switch o {
        case .wasted:
            player.pos = world.door(.hospital)
            player.armor = 0
            showBanner("KRANKENHAUS", "Die Rechnung: $\(fee)", style: .info, seconds: 3)
        case .busted:
            player.pos = world.door(.police)
            player.ammo = [.fist: 0]
            player.weapon = .fist
            showBanner("POLIZEIWACHE", "Waffen weg und $\(fee) Strafe bezahlt", style: .info, seconds: 3)
        }
        // Verfolger verschwinden lassen
        people.removeAll { $0.faction == .police && $0.chasing }
        cars.removeAll { $0.driver == .police }
        bullets.removeAll()
        camera = player.pos
        flow = world.flowField(to: player.pos)
    }

    // MARK: - Überfall

    private func updateRobbery(_ dt: Double) {
        guard var r = robbery else { return }
        guard player.car == nil, player.pos.distance(to: world.door(r.kind)) < 95 else {
            robbery = nil
            float("Überfall abgebrochen", at: player.pos, style: .danger)
            return
        }
        let before = Int(r.progress)
        r.progress += dt
        if Int(r.progress) > before {
            float("💰", at: world.door(r.kind) + CGPoint(x: CGFloat.random(in: -20...20), y: -20), style: .money)
        }
        if r.progress >= r.duration {
            let loot = Int.random(in: r.kind.loot)
            player.money += loot
            addHeat(r.kind.robHeat)
            shopCooldown[r.kind] = time + 150
            robbedEvents.append(r.kind)
            float("+$\(loot)", at: player.pos, style: .money)
            robbery = nil
        } else {
            robbery = r
        }
    }

    // MARK: - Personen

    @discardableResult
    private func spawnPerson(_ faction: Faction, at pos: CGPoint) -> Person {
        let p = Person(id: nextID, faction: faction, pos: pos)
        nextID += 1
        people.append(p)
        return p
    }

    private func spawnGang(at center: CGPoint, count: Int, boss: Bool, group: Int?) {
        for i in 0..<count {
            guard let pos = world.randomSpot(around: center, minDist: 0, maxDist: 150,
                                             allowed: [.sidewalk, .grass, .road]) else { continue }
            let g = spawnPerson(.gang, at: pos)
            g.gangGroup = group
            if boss && i == 0 {
                g.isBoss = true
                g.health = 350
                g.maxHealth = 350
                g.radius = 14
            }
        }
    }

    private func nearestCivilian(within distance: CGFloat) -> Person? {
        people
            .filter { $0.faction == .civilian && !$0.isDead && $0.pos.distance(to: player.pos) < distance }
            .min { $0.pos.distance(to: player.pos) < $1.pos.distance(to: player.pos) }
    }

    private func damage(_ p: Person, amount: CGFloat, from source: CGPoint, byPlayer: Bool) {
        guard !p.isDead else { return }
        p.health -= amount
        p.hitFlash = 0.15
        p.knock = (p.pos - source).normalized * 160
        effects.append(Effect(pos: p.pos, kind: .blood, duration: 0.35))

        if byPlayer {
            switch p.faction {
            case .civilian:
                p.panic = 6
                p.panicFrom = source
                addHeat(0.4)
            case .police:
                addHeat(1)
                p.chasing = true
            case .gang:
                p.aggro = true
                for other in people where other.faction == .gang && other.pos.distance(to: p.pos) < 400 {
                    other.aggro = true
                }
            }
        }
        if p.health <= 0 { kill(p, byPlayer: byPlayer) }
    }

    private func kill(_ p: Person, byPlayer: Bool) {
        p.health = 0
        p.deadTime = 0
        let drop = p.pos + CGPoint(x: 10, y: 6)
        switch p.faction {
        case .civilian:
            if byPlayer { addHeat(1) }
            pickups.append(Pickup(pos: drop, kind: .cash(Int.random(in: 5...40)), expires: time + 30))
        case .police:
            if byPlayer { addHeat(2.5) }
            pickups.append(Pickup(pos: drop, kind: .weapon(.pistol, 12), expires: time + 30))
            if Int.random(in: 0..<5) == 0 {
                pickups.append(Pickup(pos: p.pos - CGPoint(x: 12, y: 8), kind: .health, expires: time + 30))
            }
        case .gang:
            if p.isBoss {
                pickups.append(Pickup(pos: drop, kind: .cash(1000), expires: time + 60))
                pickups.append(Pickup(pos: p.pos - CGPoint(x: 14, y: 6), kind: .weapon(.rifle, 60), expires: time + 60))
            } else {
                pickups.append(Pickup(pos: drop, kind: .cash(Int.random(in: 20...80)), expires: time + 30))
                if Int.random(in: 0..<3) == 0 {
                    pickups.append(Pickup(pos: p.pos - CGPoint(x: 12, y: 8), kind: .weapon(.smg, 30), expires: time + 30))
                }
            }
        }
    }

    private func damagePlayer(_ amount: CGFloat) {
        guard outcome == nil else { return }
        var a = amount
        if player.armor > 0 {
            let absorbed = min(player.armor, a)
            player.armor -= absorbed
            a -= absorbed
        }
        player.health = max(0, player.health - a)
        player.hitFlash = 0.25
    }

    private func updatePeople(_ dt: Double) {
        let f = CGFloat(dt)
        for p in people {
            p.hitFlash = max(0, p.hitFlash - dt)
            if p.isDead {
                p.deadTime += dt
                continue
            }
            p.fireCooldown -= dt

            let move: CGPoint
            switch p.faction {
            case .civilian: move = civilianMove(p, dt)
            case .police: move = stars > 0 ? policeMove(p) : wander(p, speed: 50)
            case .gang: move = gangMove(p)
            }

            p.pos += (move + p.knock) * f
            p.knock = p.knock * CGFloat(pow(0.01, dt))
            world.resolve(&p.pos, radius: p.radius)
            p.speed = move.length
            if p.speed > 1 { p.walkPhase += p.speed * f * 0.15 }
        }

        // Personen schubsen sich gegenseitig zur Seite.
        let alive = people.filter { !$0.isDead }
        for i in alive.indices {
            let a = alive[i]
            for j in (i + 1)..<alive.count {
                let b = alive[j]
                let d = a.pos - b.pos
                let minD = a.radius + b.radius
                let l = d.length
                if l < minD && l > 0.01 {
                    let push = d / l * ((minD - l) / 2)
                    a.pos += push
                    b.pos -= push
                }
            }
            let d = a.pos - player.pos
            if player.car == nil && d.length < a.radius + player.radius && d.length > 0.01 {
                a.pos = player.pos + d.normalized * (a.radius + player.radius)
            }
        }
    }

    private func civilianMove(_ p: Person, _ dt: Double) -> CGPoint {
        if p.panic > 0 {
            p.panic -= dt
            var away = (p.pos - p.panicFrom).normalized
            if away == .zero { away = CGPoint(angle: CGFloat.random(in: 0..<(2 * .pi))) }
            let v = away * 150
            p.facing = v.angle
            if p.panic <= 0 { p.waypoint = nil }
            return v
        }
        return wander(p, speed: 55)
    }

    /// Spazieren auf Gehwegen und durch Parks, manchmal über die Straße.
    private func wander(_ p: Person, speed: CGFloat) -> CGPoint {
        if p.waypoint == nil || p.pos.distance(to: p.waypoint!) < 8 {
            p.waypoint = nextWaypoint(p)
        }
        let v = (p.waypoint! - p.pos).normalized * speed
        if v.length > 0.1 { p.facing = v.angle }
        return v
    }

    private func nextWaypoint(_ p: Person) -> CGPoint {
        let (c, r) = world.tileCoord(p.pos)
        let current = world.tile(c, r)
        func walkable(_ d: (Int, Int), road: Bool) -> Bool {
            let t = world.tile(c + d.0, r + d.1)
            return t == .sidewalk || t == .grass || (road && t == .road)
        }
        let reverse = (-p.dir.0, -p.dir.1)
        var choice: (Int, Int)?

        if current == .road {
            // Auf der Straße: zügig geradeaus weiter.
            if walkable(p.dir, road: true) { choice = p.dir }
        } else if walkable(p.dir, road: true) && world.tile(c + p.dir.0, r + p.dir.1) == .road
                    && Double.random(in: 0..<1) < 0.12 {
            choice = p.dir
        } else if walkable(p.dir, road: false) && Double.random(in: 0..<1) < 0.8 {
            choice = p.dir
        } else {
            let options = fourDirections.filter { !($0 == reverse) && walkable($0, road: false) }
            choice = options.randomElement()
        }
        if choice == nil && walkable(reverse, road: current == .road) { choice = reverse }

        guard let d = choice else { return world.center(c, r) }
        p.dir = d
        return world.center(c + d.0, r + d.1) + p.laneJitter
    }

    /// Nächster Schritt Richtung Spieler laut Wegfindung.
    private func chaseStep(from pos: CGPoint) -> CGPoint {
        let (c, r) = world.tileCoord(pos)
        guard let here = world.flowValue(flow, c, r) else { return playerPos }
        var best = here
        var bestTile = (c, r)
        for (dx, dy) in fourDirections {
            if let v = world.flowValue(flow, c + dx, r + dy), v < best {
                best = v
                bestTile = (c + dx, r + dy)
            }
        }
        if best == here { return playerPos }
        return world.center(bestTile.0, bestTile.1)
    }

    private func policeMove(_ p: Person) -> CGPoint {
        p.chasing = true
        let target = playerPos
        let toP = target - p.pos
        let d = toP.length
        let los = d < 600 && world.lineOfSight(p.pos, target)
        let s = stars

        var v: CGPoint
        if los && d < 260 {
            if s >= 2 && d < 180 {
                v = toP.normalized.perpendicular * (sin(CGFloat(time) * 1.3 + CGFloat(p.id)) * 50)
            } else {
                v = toP.normalized * 150
            }
        } else {
            v = (chaseStep(from: p.pos) - p.pos).normalized * 150
        }

        if s >= 2 && los && d < 450 {
            p.facing = toP.angle
            if p.fireCooldown <= 0 {
                npcFire(from: p, at: target, damage: 5, owner: .police, spread: 0.12)
                p.fireCooldown = Double.random(in: 0.8...1.5)
            }
        } else if v.length > 1 {
            p.facing = v.angle
        }

        if s == 1 && d < p.radius + player.radius + 10 {
            let carSlow = player.car.map { abs($0.speed) < 30 } ?? true
            if carSlow { bustContact = true }
        }
        return v
    }

    private func gangMove(_ p: Person) -> CGPoint {
        let target = playerPos
        let toP = target - p.pos
        let d = toP.length
        let sightRange: CGFloat = p.gangGroup != nil ? 330 : 170

        if !p.aggro && d < sightRange && world.lineOfSight(p.pos, target) {
            p.aggro = true
            for other in people where other.faction == .gang && other.pos.distance(to: p.pos) < 300 {
                other.aggro = true
            }
        }
        if p.aggro && p.gangGroup == nil && d > 900 { p.aggro = false }

        guard p.aggro else {
            // Rumhängen in der Nähe des Treffpunkts.
            if p.waypoint == nil || p.pos.distance(to: p.waypoint!) < 8 {
                p.waypoint = world.randomSpot(around: p.home, minDist: 0, maxDist: 90,
                                              allowed: [.sidewalk, .grass, .road]) ?? p.home
            }
            let v = (p.waypoint! - p.pos).normalized * 35
            if v.length > 0.1 { p.facing = v.angle }
            return v
        }

        let los = d < 600 && world.lineOfSight(p.pos, target)
        var v: CGPoint
        if los && d < 420 {
            if d > 170 {
                v = toP.normalized * 120
            } else if d < 100 {
                v = toP.normalized * -80
            } else {
                v = toP.normalized.perpendicular * (sin(CGFloat(time) + CGFloat(p.id)) * 60)
            }
            p.facing = toP.angle
            if p.fireCooldown <= 0 {
                npcFire(from: p, at: target, damage: p.isBoss ? 10 : 5, owner: .gang, spread: p.isBoss ? 0.08 : 0.14)
                p.fireCooldown = p.isBoss ? Double.random(in: 0.35...0.7) : Double.random(in: 0.8...1.4)
            }
        } else {
            v = (chaseStep(from: p.pos) - p.pos).normalized * 120
            if v.length > 1 { p.facing = v.angle }
        }
        return v
    }

    private func npcFire(from p: Person, at target: CGPoint, damage: CGFloat, owner: BulletOwner, spread: CGFloat) {
        let a = (target - p.pos).angle + CGFloat.random(in: -spread...spread)
        let dir = CGPoint(angle: a)
        let muzzle = p.pos + dir * 18
        bullets.append(Bullet(pos: muzzle, vel: dir * 700, life: 0.9, damage: damage, owner: owner))
        effects.append(Effect(pos: muzzle, kind: .muzzle, duration: 0.06))
    }

    // MARK: - Autos

    private func nearestCar(maxDistance: CGFloat, onlyEmpty: Bool) -> Car? {
        cars
            .filter { $0.isUsable && $0.driver != .player && (!onlyEmpty || $0.driver == .none)
                && $0.pos.distance(to: player.pos) < maxDistance }
            .min { $0.pos.distance(to: player.pos) < $1.pos.distance(to: player.pos) }
    }

    /// Drückt einen Kreis aus einem Auto heraus (Auto = drei Kreise hintereinander).
    @discardableResult
    private func pushOut(_ pos: inout CGPoint, radius r: CGFloat, from car: Car) -> Bool {
        var hit = false
        for offset: CGFloat in [-12, 0, 12] {
            let c = car.pos + car.forward * offset
            let d = pos - c
            let minD = 13 + r
            let l = d.length
            if l < minD {
                pos = c + (l > 0.01 ? d / l : car.forward.perpendicular) * minD
                hit = true
            }
        }
        return hit
    }

    /// Lenkt ein Auto in Richtung `dir` (oder bremst ohne Richtung).
    private func drive(_ car: Car, toward dir: CGPoint?, throttle: CGFloat, maxSpeed: CGFloat, dt: Double) {
        let f = CGFloat(dt)
        if let dir, throttle > 0.05, car.isUsable {
            let desired = dir.angle
            let diff = angleDiff(desired, car.angle)
            if abs(diff) > 2.3 && car.speed < 60 {
                // Rückwärts fahren und dabei das Heck in die Wunschrichtung drehen.
                let back = angleDiff(desired + .pi, car.angle)
                car.speed = max(car.speed - 320 * f, -150)
                car.angle += clamp(back, -2.4 * f, 2.4 * f) * min(1, abs(car.speed) / 60)
            } else {
                let steer = min(1, abs(car.speed) / 70)
                car.angle += clamp(diff, -2.8 * f, 2.8 * f) * steer
                let target = maxSpeed * throttle * (abs(diff) > 1.2 ? 0.5 : 1)
                if car.speed < target {
                    car.speed = min(target, car.speed + 280 * f)
                } else {
                    car.speed = max(target, car.speed - 420 * f)
                }
            }
        } else {
            car.speed *= CGFloat(pow(0.15, dt))
            if abs(car.speed) < 3 { car.speed = 0 }
        }
        car.angle = normalizeAngle(car.angle)
        moveCar(car, dt: dt)
    }

    private func moveCar(_ car: Car, dt: Double) {
        let f = CGFloat(dt)
        car.pos += car.forward * (car.speed * f)
        var totalPush = CGPoint.zero
        for offset: CGFloat in [-12, 12] {
            var c = car.pos + car.forward * offset
            let push = world.resolve(&c, radius: 13)
            totalPush += push
        }
        guard totalPush.length > 0.01 else { return }
        car.pos += totalPush * 0.5
        let impact = abs(car.forward.dot(totalPush.normalized))
        let before = abs(car.speed)
        car.speed *= 1 - impact * 0.8
        if before * impact > 130 {
            damageCar(car, amount: before * impact * 0.05)
            effects.append(Effect(pos: car.pos + car.forward * 24, kind: .spark, duration: 0.2))
        }
    }

    private func damageCar(_ car: Car, amount: CGFloat) {
        guard !car.wrecked else { return }
        car.hp -= amount
        car.hitFlash = 0.1
        if car.hp <= 0 && car.burnTime == 0 {
            car.burnTime = 0.0001
            if car === player.car { float("Das Auto brennt – raus da!", at: car.pos, style: .danger) }
            if car.driver == .traffic || car.driver == .police {
                let ped = spawnPerson(car.driver == .police ? .police : .civilian,
                                      at: car.pos + car.forward.perpendicular * -30)
                ped.panic = 6
                ped.panicFrom = car.pos
                car.driver = .none
            }
        }
    }

    private func explode(_ car: Car) {
        car.wrecked = true
        car.speed = 0
        effects.append(Effect(pos: car.pos, kind: .explosion, duration: 0.7))
        for _ in 0..<6 {
            effects.append(Effect(pos: car.pos + CGPoint(x: CGFloat.random(in: -20...20), y: CGFloat.random(in: -20...20)),
                                  kind: .smoke, duration: 1.4,
                                  vel: CGPoint(x: CGFloat.random(in: -30...30), y: CGFloat.random(in: -40...(-10)))))
        }
        for p in people where !p.isDead {
            let d = p.pos.distance(to: car.pos)
            if d < 120 { damage(p, amount: 90 * (1 - d / 160), from: car.pos, byPlayer: false) }
        }
        if player.car === car {
            damagePlayer(999)
        } else {
            let d = player.pos.distance(to: car.pos)
            if player.car == nil && d < 120 { damagePlayer(70 * (1 - d / 140)) }
        }
        for other in cars where other !== car && other.pos.distance(to: car.pos) < 110 {
            damageCar(other, amount: 50)
        }
    }

    private func updateCars(_ dt: Double) {
        for car in cars {
            car.hitFlash = max(0, car.hitFlash - dt)

            if car.isBurning {
                car.burnTime += dt
                if Int(car.burnTime * 12) != Int((car.burnTime - dt) * 12) {
                    effects.append(Effect(pos: car.pos + CGPoint(x: CGFloat.random(in: -14...14), y: CGFloat.random(in: -8...8)),
                                          kind: .fire, duration: 0.5, vel: CGPoint(x: 0, y: -40)))
                }
                if car.burnTime > 3.5 { explode(car) }
            }

            if car === player.car { continue }
            switch car.driver {
            case .traffic: trafficAI(car, dt: dt)
            case .police: policeCarAI(car, dt: dt)
            case .none, .player: drive(car, toward: nil, throttle: 0, maxSpeed: 0, dt: dt)
            }
        }

        // Autos gegen Autos
        for i in cars.indices {
            for j in (i + 1)..<cars.count {
                let a = cars[i], b = cars[j]
                let d = a.pos - b.pos
                let l = d.length
                guard l < 32 && l > 0.01 else { continue }
                let push = d / l * ((32 - l) / 2)
                a.pos += push
                b.pos -= push
                let rel = abs(a.speed - b.speed)
                if rel > 150 {
                    damageCar(a, amount: rel * 0.04)
                    damageCar(b, amount: rel * 0.04)
                    effects.append(Effect(pos: (a.pos + b.pos) / 2, kind: .spark, duration: 0.2))
                }
                a.speed *= 0.6
                b.speed *= 0.6
            }
        }

        // Autos gegen Personen
        for car in cars {
            let fast = abs(car.speed) > 70
            for p in people where !p.isDead {
                if pushOut(&p.pos, radius: p.radius, from: car) && fast {
                    damage(p, amount: abs(car.speed) * 0.25, from: car.pos, byPlayer: car === player.car)
                    p.knock = (p.pos - car.pos).normalized * abs(car.speed) * 0.8
                    car.speed *= 0.9
                }
            }
            if player.car == nil {
                let before = player.pos
                if pushOut(&player.pos, radius: player.radius, from: car) && abs(car.speed) > 80 {
                    damagePlayer(abs(car.speed) * 0.12)
                    player.pos = before + (before - car.pos).normalized * 20
                    world.resolve(&player.pos, radius: player.radius)
                    car.speed *= 0.6
                }
            }
        }
    }

    private func trafficPoint(node: (Int, Int), dir: (Int, Int)) -> CGPoint {
        let right = CGPoint(x: CGFloat(-dir.1), y: CGFloat(dir.0))
        return world.nodePos(node.0, node.1) + right * 26
    }

    private func trafficAI(_ car: Car, dt: Double) {
        if car.pos.distance(to: car.target) < 34 {
            let (m, k) = car.node
            let reverse = (-car.dir.0, -car.dir.1)
            let options = fourDirections.filter { d in
                !(d == reverse) && (0..<World.nodeCount).contains(m + d.0) && (0..<World.nodeCount).contains(k + d.1)
            }
            let straight = options.contains { $0 == car.dir }
            let d = (straight && Bool.random()) ? car.dir : (options.randomElement() ?? reverse)
            car.dir = d
            car.node = (m + d.0, k + d.1)
            car.target = trafficPoint(node: car.node, dir: d)
        }

        // Bremsen, wenn etwas im Weg ist.
        let fwd = car.forward
        func blocking(_ p: CGPoint) -> Bool {
            let d = p - car.pos
            let along = d.dot(fwd)
            return along > 0 && along < 75 && abs(d.dot(fwd.perpendicular)) < 20
        }
        var blocked = blocking(playerPos)
            || cars.contains { $0 !== car && blocking($0.pos) }
            || people.contains { !$0.isDead && blocking($0.pos) }
        if blocked {
            car.waitTime += dt
            if car.waitTime > 3 { blocked = false }
            if car.waitTime > 4 { car.waitTime = 0 }
        } else {
            car.waitTime = 0
        }
        drive(car, toward: (car.target - car.pos).normalized, throttle: blocked ? 0 : 1, maxSpeed: 150, dt: dt)
    }

    private func policeCarAI(_ car: Car, dt: Double) {
        guard stars > 0 else {
            drive(car, toward: nil, throttle: 0, maxSpeed: 0, dt: dt)
            return
        }
        if car.reverseTime > 0 {
            car.reverseTime -= dt
            car.speed = -110
            car.angle += 1.6 * CGFloat(dt)
            moveCar(car, dt: dt)
            return
        }

        let target = playerPos
        let d = car.pos.distance(to: target)
        let playerSlow = player.car.map { abs($0.speed) < 60 } ?? true
        if !car.deployed && d < 150 && playerSlow {
            drive(car, toward: nil, throttle: 0, maxSpeed: 0, dt: dt)
            if abs(car.speed) < 40 {
                car.deployed = true
                car.driver = .none
                for side: CGFloat in [-1, 1] {
                    var p = car.pos + car.forward.perpendicular * (30 * side)
                    world.resolve(&p, radius: 11)
                    let cop = spawnPerson(.police, at: p)
                    cop.chasing = true
                }
            }
            return
        }

        let los = d < 400 && world.lineOfSight(car.pos, target)
        let next = los ? target : chaseStep(from: car.pos)
        drive(car, toward: (next - car.pos).normalized, throttle: 1, maxSpeed: 330, dt: dt)

        if abs(car.speed) < 20 {
            car.stuckTime += dt
            if car.stuckTime > 1.2 {
                car.stuckTime = 0
                car.reverseTime = 0.8
            }
        } else {
            car.stuckTime = 0
        }
    }

    // MARK: - Kugeln

    private func updateBullets(_ dt: Double) {
        let f = CGFloat(dt)
        var remaining: [Bullet] = []
        remaining.reserveCapacity(bullets.count)
        for var b in bullets {
            b.life -= dt
            let step = b.vel * f
            var hit = false
            for s in 1...3 {
                let p = b.pos + step * (CGFloat(s) / 3)
                if world.isSolid(p) {
                    effects.append(Effect(pos: p, kind: .spark, duration: 0.15))
                    hit = true
                    break
                }
                if bulletHits(b, at: p) {
                    hit = true
                    break
                }
            }
            b.pos += step
            if !hit && b.life > 0 { remaining.append(b) }
        }
        bullets = remaining
    }

    private func bulletHits(_ b: Bullet, at p: CGPoint) -> Bool {
        switch b.owner {
        case .player:
            if let victim = people.first(where: { !$0.isDead && $0.pos.distance(to: p) < $0.radius + 3 }) {
                damage(victim, amount: b.damage, from: p - b.vel.normalized * 30, byPlayer: true)
                return true
            }
            if let car = cars.first(where: { $0 !== player.car && !$0.wrecked && $0.pos.distance(to: p) < 20 }) {
                damageCar(car, amount: b.damage * 0.5)
                effects.append(Effect(pos: p, kind: .spark, duration: 0.15))
                if car.driver == .police { addHeat(0.5) }
                return true
            }
        case .police, .gang:
            if let car = player.car {
                if car.pos.distance(to: p) < 20 {
                    damageCar(car, amount: b.damage * 0.8)
                    damagePlayer(b.damage * 0.25)
                    effects.append(Effect(pos: p, kind: .spark, duration: 0.15))
                    return true
                }
            } else if player.pos.distance(to: p) < player.radius + 3 {
                damagePlayer(b.damage)
                effects.append(Effect(pos: p, kind: .blood, duration: 0.3))
                return true
            }
        }
        return false
    }

    // MARK: - Gegenstände

    private func updatePickups() {
        let pos = playerPos
        var i = pickups.count - 1
        while i >= 0 {
            var item = pickups[i]
            if let e = item.expires, e < time {
                pickups.remove(at: i)
            } else if item.hiddenUntil <= time && item.pos.distance(to: pos) < 28 && collect(item) {
                if item.isStatic {
                    item.hiddenUntil = time + 45
                    pickups[i] = item
                } else {
                    pickups.remove(at: i)
                }
            }
            i -= 1
        }
    }

    private func collect(_ item: Pickup) -> Bool {
        switch item.kind {
        case .cash(let n):
            player.money += n
            float("+$\(n)", at: item.pos, style: .money)
        case .health:
            guard player.health < 100 else { return false }
            player.health = min(100, player.health + 40)
            float("+Gesundheit", at: item.pos, style: .info)
        case .armor:
            guard player.armor < 100 else { return false }
            player.armor = min(100, player.armor + 50)
            float("+Schutzweste", at: item.pos, style: .info)
        case .weapon(let w, let n):
            let isNew = !player.owns(w)
            player.ammo[w, default: 0] += n
            if isNew { player.weapon = w }
            float(isNew ? "\(w.name)!" : "+\(n) Munition", at: item.pos, style: .info)
        }
        return true
    }

    // MARK: - Spawnen

    private var offscreenRadius: CGFloat {
        (viewSize.width * viewSize.width + viewSize.height * viewSize.height).squareRoot() / 2 / zoom + 40
    }

    private func populate() {
        for _ in 0..<18 { spawnParkedCar() }
        for _ in 0..<10 { spawnTrafficCar(minDist: 200, maxDist: 1500) }
        for _ in 0..<18 {
            if let p = world.randomSpot(around: player.pos, minDist: 100, maxDist: 900, allowed: [.sidewalk, .grass]) {
                spawnPerson(.civilian, at: p)
            }
        }
        for _ in 0..<2 {
            if let p = world.randomSpot(around: player.pos, minDist: 400, maxDist: 1200, allowed: [.sidewalk]) {
                spawnPerson(.police, at: p)
            }
        }
        // Feste Gegenstände in den Parks
        for (bx, by) in World.parks {
            let c = world.blockCenter(bx, by)
            if bx == World.gangPark.x && by == World.gangPark.y {
                pickups.append(Pickup(pos: c, kind: .weapon(.smg, 60), isStatic: true))
            } else {
                pickups.append(Pickup(pos: c, kind: .health, isStatic: true))
            }
        }
        pickups.append(Pickup(pos: world.blockCenter(0, 5) + CGPoint(x: 70, y: 60), kind: .armor, isStatic: true))
        pickups.append(Pickup(pos: world.blockCenter(5, 3) + CGPoint(x: -70, y: -60), kind: .armor, isStatic: true))
        pickups.append(Pickup(pos: world.blockCenter(1, 4) + CGPoint(x: 60, y: -70), kind: .weapon(.shotgun, 12), isStatic: true))
    }

    private func spawnParkedCar() {
        let t = World.tileSize
        let horizontal = Bool.random()
        let k = Int.random(in: 0..<World.nodeCount)
        let b = Int.random(in: 0..<World.blockCount)
        let along = CGFloat(b * World.period + 2) * t + CGFloat.random(in: 40...(6 * t - 40))
        let firstSide = Bool.random()
        let roadStart = CGFloat(k * World.period) * t
        let across = firstSide ? roadStart + 13 : roadStart + 2 * t - 13
        let pos = horizontal ? CGPoint(x: along, y: across) : CGPoint(x: across, y: along)
        let angle: CGFloat = horizontal ? (firstSide ? .pi : 0) : (firstSide ? .pi / 2 : -.pi / 2)
        guard !cars.contains(where: { $0.pos.distance(to: pos) < 60 }) else { return }
        let car = Car(id: nextID, model: CarModel.trafficModels.randomElement()!, pos: pos, angle: angle, driver: .none)
        nextID += 1
        cars.append(car)
    }

    private func spawnTrafficCar(minDist: CGFloat, maxDist: CGFloat) {
        for _ in 0..<12 {
            let m = Int.random(in: 0..<World.nodeCount), k = Int.random(in: 0..<World.nodeCount)
            let d = world.nodePos(m, k).distance(to: playerPos)
            guard d >= minDist && d <= maxDist else { continue }
            let dirs = fourDirections.filter {
                (0..<World.nodeCount).contains(m + $0.0) && (0..<World.nodeCount).contains(k + $0.1)
            }
            guard let dir = dirs.randomElement() else { continue }
            let start = trafficPoint(node: (m, k), dir: dir)
            guard !cars.contains(where: { $0.pos.distance(to: start) < 70 }) else { continue }
            let car = Car(id: nextID, model: CarModel.trafficModels.randomElement()!, pos: start,
                          angle: atan2(CGFloat(dir.1), CGFloat(dir.0)), driver: .traffic)
            nextID += 1
            car.node = (m + dir.0, k + dir.1)
            car.dir = dir
            car.target = trafficPoint(node: car.node, dir: dir)
            car.speed = 100
            cars.append(car)
            return
        }
    }

    private func spawnPoliceCar() {
        let r = offscreenRadius
        for _ in 0..<12 {
            let m = Int.random(in: 0..<World.nodeCount), k = Int.random(in: 0..<World.nodeCount)
            let pos = world.nodePos(m, k)
            let d = pos.distance(to: playerPos)
            guard d >= r && d <= r + 700 else { continue }
            guard !cars.contains(where: { $0.pos.distance(to: pos) < 60 }) else { continue }
            let car = Car(id: nextID, model: .police, pos: pos, angle: (playerPos - pos).angle, driver: .police)
            nextID += 1
            car.speed = 150
            car.colorIndex = 0
            cars.append(car)
            return
        }
    }

    private func updateSpawning(_ dt: Double) {
        spawnTimer -= dt
        guard spawnTimer <= 0 else { return }
        spawnTimer = 0.5

        let center = playerPos
        let r = offscreenRadius
        let s = stars
        let group = missionGroup
        let activeGroup = mission != nil

        people.removeAll { p in
            let d = p.pos.distance(to: center)
            if p.isDead { return p.deadTime > 25 || d > r + 500 }
            if let g = p.gangGroup { return !(activeGroup && g == group) }
            switch p.faction {
            case .civilian: return d > r + 700
            case .police: return d > r + (s > 0 ? 1300 : 700)
            case .gang: return d > r + 900
            }
        }
        cars.removeAll { c in
            guard c !== player.car else { return false }
            let d = c.pos.distance(to: center)
            switch c.driver {
            case .traffic: return d > r + 900
            case .police: return d > r + 1500 || s == 0 && d > r + 200
            case .none: return d > r + (c.wrecked ? 600 : 2200)
            case .player: return false
            }
        }

        let civilians = people.filter { $0.faction == .civilian && !$0.isDead }.count
        if civilians < 18,
           let p = world.randomSpot(around: center, minDist: r, maxDist: r + 450, allowed: [.sidewalk, .grass]) {
            spawnPerson(.civilian, at: p)
        }

        let cops = people.filter { $0.faction == .police && !$0.isDead }.count
        let wantedCops = [2, 2, 4, 6, 8, 10][s]
        if cops < wantedCops,
           let p = world.randomSpot(around: center, minDist: r, maxDist: r + 300, allowed: [.sidewalk, .road, .grass]) {
            let cop = spawnPerson(.police, at: p)
            cop.chasing = s > 0
        }

        let policeCars = cars.filter { $0.driver == .police }.count
        if policeCars < [0, 0, 0, 1, 2, 3][s] { spawnPoliceCar() }

        let traffic = cars.filter { $0.driver == .traffic }.count
        if traffic < 10 { spawnTrafficCar(minDist: r, maxDist: r + 700) }

        // Die Roten Kobras hängen immer in ihrem Park ab.
        let gangHome = world.blockCenter(World.gangPark.x, World.gangPark.y)
        let ambientGang = people.filter { $0.faction == .gang && $0.gangGroup == nil && !$0.isDead }.count
        if ambientGang < 4 && gangHome.distance(to: center) < r + 600 && gangHome.distance(to: center) > r {
            spawnGang(at: gangHome, count: 1, boss: false, group: nil)
        }
    }

    // MARK: - Effekte & Kamera

    private func float(_ text: String, at pos: CGPoint, style: TextStyle) {
        texts.append(FloatText(text: text, pos: pos + CGPoint(x: 0, y: -24), style: style))
    }

    private func showBanner(_ title: String, _ subtitle: String, style: BannerStyle, seconds: Double) {
        banner = Banner(title: title, subtitle: subtitle, until: time + seconds, style: style)
    }

    private func updateEffects(_ dt: Double) {
        let f = CGFloat(dt)
        for i in effects.indices {
            effects[i].age += dt
            effects[i].pos += effects[i].vel * f
        }
        effects.removeAll { $0.age >= $0.duration }
        for i in texts.indices {
            texts[i].age += dt
            texts[i].pos.y -= 30 * f
        }
        texts.removeAll { $0.age > 1.6 }
    }

    private func updateCamera(_ dt: Double) {
        let f = CGFloat(dt)
        let base = clamp(viewSize.height / 430, 0.75, 1.7)
        let speedFactor = player.car.map { min(abs($0.speed) / 450, 1) } ?? 0
        let targetZoom = base * (1 - 0.25 * speedFactor)
        let look = player.car.map { $0.forward * ($0.speed * 0.35) } ?? .zero
        if firstFrame {
            zoom = targetZoom
            camera = playerPos
            firstFrame = false
        }
        zoom += (targetZoom - zoom) * min(1, f * 2)
        camera += (playerPos + look - camera) * min(1, f * 5)
    }
}
