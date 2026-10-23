import Foundation
import CoreGraphics

// MARK: - Waffen

enum Weapon: Int, CaseIterable, Identifiable {
    case fist, pistol, smg, shotgun, rifle

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .fist: "Fäuste"
        case .pistol: "Pistole"
        case .smg: "Maschinenpistole"
        case .shotgun: "Schrotflinte"
        case .rifle: "Sturmgewehr"
        }
    }

    var shortName: String {
        switch self {
        case .fist: "FAUST"
        case .pistol: "PISTOLE"
        case .smg: "MP"
        case .shotgun: "SCHROT"
        case .rifle: "GEWEHR"
        }
    }

    var symbol: String {
        switch self {
        case .fist: "hand.raised.fill"
        case .pistol: "scope"
        case .smg: "bolt.fill"
        case .shotgun: "burst.fill"
        case .rifle: "flame.fill"
        }
    }

    var isMelee: Bool { self == .fist }

    var damage: CGFloat {
        switch self {
        case .fist: 14
        case .pistol: 26
        case .smg: 15
        case .shotgun: 16
        case .rifle: 32
        }
    }

    /// Sekunden zwischen zwei Schüssen.
    var cooldown: Double {
        switch self {
        case .fist: 0.35
        case .pistol: 0.32
        case .smg: 0.085
        case .shotgun: 0.8
        case .rifle: 0.12
        }
    }

    var range: CGFloat {
        switch self {
        case .fist: 36
        case .pistol: 520
        case .smg: 450
        case .shotgun: 300
        case .rifle: 650
        }
    }

    var bulletSpeed: CGFloat {
        switch self {
        case .fist: 0
        case .pistol: 950
        case .smg: 1000
        case .shotgun: 850
        case .rifle: 1200
        }
    }

    var pellets: Int { self == .shotgun ? 6 : 1 }

    var spread: CGFloat {
        switch self {
        case .fist: 0
        case .pistol: 0.03
        case .smg: 0.09
        case .shotgun: 0.28
        case .rifle: 0.04
        }
    }

    var price: Int {
        switch self {
        case .fist: 0
        case .pistol: 250
        case .smg: 800
        case .shotgun: 1200
        case .rifle: 2500
        }
    }

    var ammoPrice: Int {
        switch self {
        case .fist: 0
        case .pistol: 40
        case .smg: 80
        case .shotgun: 100
        case .rifle: 150
        }
    }

    var ammoPack: Int {
        switch self {
        case .fist: 0
        case .pistol: 24
        case .smg: 60
        case .shotgun: 12
        case .rifle: 60
        }
    }

    /// Wie stark die Waffe ist (1–5), für den Laden.
    var power: Int {
        switch self {
        case .fist: 1
        case .pistol: 2
        case .smg: 3
        case .shotgun: 4
        case .rifle: 5
        }
    }
}

// MARK: - Spieler

final class Player {
    var pos: CGPoint
    var facing: CGFloat = 0
    var health: CGFloat = 100
    var armor: CGFloat = 0
    var money = 300
    /// Besessene Waffen und ihre Munition (Fäuste haben unendlich).
    var ammo: [Weapon: Int] = [.fist: 0]
    var weapon: Weapon = .fist
    var car: Car?
    var fireCooldown: Double = 0
    var walkPhase: CGFloat = 0
    var moving = false
    var hitFlash: Double = 0
    let radius: CGFloat = 12

    init(pos: CGPoint) { self.pos = pos }

    func owns(_ w: Weapon) -> Bool { ammo[w] != nil }

    var ownedWeapons: [Weapon] { Weapon.allCases.filter { owns($0) } }

    var currentAmmo: Int { ammo[weapon] ?? 0 }
}

// MARK: - Personen (Passanten, Polizei, Gang)

enum Faction {
    case civilian, police, gang
}

struct Look {
    var shirt: Int
    var skin: Int
    var hair: Int

    static func random() -> Look {
        Look(shirt: Int.random(in: 0..<100), skin: Int.random(in: 0..<100), hair: Int.random(in: 0..<100))
    }
}

final class Person {
    let id: Int
    let faction: Faction
    var pos: CGPoint
    var facing: CGFloat = 0
    var health: CGFloat
    var maxHealth: CGFloat
    var radius: CGFloat = 11
    var speed: CGFloat = 0
    var walkPhase: CGFloat = 0
    var look = Look.random()

    var waypoint: CGPoint?
    var dir: (Int, Int) = fourDirections.randomElement()!
    var laneJitter = CGPoint(x: CGFloat.random(in: -14...14), y: CGFloat.random(in: -14...14))
    var panic: Double = 0
    var panicFrom: CGPoint = .zero
    var fireCooldown = Double.random(in: 0.5...1.5)
    var hitFlash: Double = 0
    var deadTime: Double = 0
    var knock: CGPoint = .zero

    var home: CGPoint
    var gangGroup: Int?
    var isBoss = false
    var aggro = false
    var chasing = false

    var isDead: Bool { health <= 0 }

    init(id: Int, faction: Faction, pos: CGPoint) {
        self.id = id
        self.faction = faction
        self.pos = pos
        self.home = pos
        switch faction {
        case .civilian: health = 40
        case .police: health = 70
        case .gang: health = 60
        }
        maxHealth = health
    }
}

// MARK: - Autos

enum CarModel: Int, CaseIterable {
    case sedan, sports, taxi, van, police

    var maxSpeed: CGFloat {
        switch self {
        case .sedan: 380
        case .sports: 480
        case .taxi: 360
        case .van: 320
        case .police: 430
        }
    }

    static let trafficModels: [CarModel] = [.sedan, .sedan, .sedan, .sports, .taxi, .van]
}

enum Driver {
    case none, player, traffic, police
}

final class Car {
    let id: Int
    let model: CarModel
    var pos: CGPoint
    var angle: CGFloat
    var speed: CGFloat = 0
    var colorIndex = Int.random(in: 0..<100)
    var hp: CGFloat = 100
    var driver: Driver
    var burnTime: Double = 0
    var wrecked = false
    var hitFlash: Double = 0

    // Verkehr
    var node: (Int, Int) = (0, 0)
    var dir: (Int, Int) = (1, 0)
    var target: CGPoint = .zero
    var waitTime: Double = 0

    // Polizei
    var deployed = false
    var stuckTime: Double = 0
    var reverseTime: Double = 0

    var forward: CGPoint { CGPoint(angle: angle) }
    var isBurning: Bool { hp <= 0 && !wrecked }
    var isUsable: Bool { hp > 0 && !wrecked }

    init(id: Int, model: CarModel, pos: CGPoint, angle: CGFloat, driver: Driver) {
        self.id = id
        self.model = model
        self.pos = pos
        self.angle = angle
        self.driver = driver
    }
}

// MARK: - Kugeln, Gegenstände, Effekte

enum BulletOwner {
    case player, police, gang
}

struct Bullet {
    var pos: CGPoint
    var vel: CGPoint
    var life: Double
    var damage: CGFloat
    var owner: BulletOwner
}

enum PickupKind {
    case cash(Int)
    case health
    case armor
    case weapon(Weapon, Int)
}

struct Pickup {
    var pos: CGPoint
    var kind: PickupKind
    /// Feste Gegenstände tauchen nach einer Weile wieder auf.
    var isStatic = false
    var hiddenUntil: Double = 0
    var expires: Double?
}

enum EffectKind {
    case muzzle, spark, blood, explosion, smoke, fire, punch
}

struct Effect {
    var pos: CGPoint
    var kind: EffectKind
    var duration: Double
    var age: Double = 0
    var vel: CGPoint = .zero
}

enum TextStyle {
    case money, info, danger
}

struct FloatText {
    var text: String
    var pos: CGPoint
    var style: TextStyle
    var age: Double = 0
}
