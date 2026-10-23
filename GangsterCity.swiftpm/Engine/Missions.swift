import Foundation
import CoreGraphics

enum ObjectiveKind {
    /// Gehe/fahre zu einem Punkt.
    case reach(CGPoint, needsCar: Bool)
    /// Raube einen Laden aus.
    case rob(LocationKind)
    /// Kaufe eine Waffe.
    case buy(Weapon)
    /// Steig in ein Auto.
    case enterCar
    /// Erledige alle Gangmitglieder dieser Mission.
    case eliminateGang
    /// Häng die Polizei ab (0 Sterne).
    case loseWanted
    /// Überlebe eine Zeit lang mit mindestens so vielen Sternen.
    case survive(stars: Int, seconds: Double)
}

enum ObjectiveSetup {
    case none
    case spawnGang(at: CGPoint, count: Int, boss: Bool)
    case wanted(stars: Int)
}

struct Objective {
    var text: String
    var kind: ObjectiveKind
    var timeLimit: Double? = nil
    var setup: ObjectiveSetup = .none
}

struct MissionDef {
    var title: String
    var briefing: String
    var reward: Int
    var objectives: [Objective]
}

struct ActiveMission {
    var index: Int
    var step = 0
    var stepTime: Double = 0
}

enum Missions {
    static func make(in w: World) -> [MissionDef] {
        let gangPark = w.blockCenter(World.gangPark.x, World.gangPark.y)
        let harbor = w.nodePos(0, 6) + CGPoint(x: 40, y: 20)
        return [
            MissionDef(
                title: "Willkommen in Gangster City",
                briefing: "Onkel Rico hat dich vom Bahnhof abgeholt. \"Wer hier überleben will, braucht eine Waffe\", sagt er. Geh zum Waffenladen und kauf dir eine Pistole.",
                reward: 300,
                objectives: [
                    Objective(text: "Geh zum Waffenladen 🎯", kind: .reach(w.door(.gunShop), needsCar: false)),
                    Objective(text: "Kaufe eine Pistole", kind: .buy(.pistol))
                ]
            ),
            MissionDef(
                title: "Der erste Coup",
                briefing: "Zeit für schnelles Geld. Der Kiosk um die Ecke hat volle Kassen. Raub ihn aus und häng danach die Bullen ab!",
                reward: 500,
                objectives: [
                    Objective(text: "Raube den Kiosk aus 🏪", kind: .rob(.kiosk)),
                    Objective(text: "Häng die Polizei ab!", kind: .loseWanted)
                ]
            ),
            MissionDef(
                title: "Kurierfahrt",
                briefing: "Rico braucht einen Fahrer. Besorg dir ein Auto, hol ein Paket an der Tankstelle ab und bring es zum Hafen – aber schnell!",
                reward: 800,
                objectives: [
                    Objective(text: "Besorg dir ein Auto 🚗", kind: .enterCar),
                    Objective(text: "Hol das Paket an der Tankstelle ab", kind: .reach(w.door(.gasStation), needsCar: true)),
                    Objective(text: "Bring das Paket zum Hafen!", kind: .reach(harbor, needsCar: true), timeLimit: 50)
                ]
            ),
            MissionDef(
                title: "Kobra-Krieg",
                briefing: "Die Roten Kobras machen sich im Park breit. Zeig ihnen, wer hier der Boss ist!",
                reward: 1500,
                objectives: [
                    Objective(text: "Geh zum Revier der Roten Kobras", kind: .reach(gangPark, needsCar: false),
                              setup: .spawnGang(at: gangPark, count: 6, boss: false)),
                    Objective(text: "Erledige alle Roten Kobras!", kind: .eliminateGang),
                    Objective(text: "Häng die Polizei ab!", kind: .loseWanted)
                ]
            ),
            MissionDef(
                title: "Heiße Jagd",
                briefing: "Lenk die Polizei ab, damit Rico in Ruhe arbeiten kann. Überlebe eine Minute mit 4 Sternen!",
                reward: 2000,
                objectives: [
                    Objective(text: "Überlebe 60 Sekunden!", kind: .survive(stars: 4, seconds: 60),
                              setup: .wanted(stars: 4)),
                    Objective(text: "Häng die Polizei ab!", kind: .loseWanted)
                ]
            ),
            MissionDef(
                title: "Juwelenraub",
                briefing: "Beim Juwelier liegen Diamanten. Raub den Laden aus – das gibt richtig Ärger mit der Polizei.",
                reward: 2500,
                objectives: [
                    Objective(text: "Raube den Juwelier aus 💎", kind: .rob(.jeweler)),
                    Objective(text: "Häng die Polizei ab!", kind: .loseWanted)
                ]
            ),
            MissionDef(
                title: "Der Kobra-Boss",
                briefing: "Der Boss der Roten Kobras versteckt sich in seiner Villa. Er ist zäh und hat Leibwächter. Mach ihn fertig!",
                reward: 4000,
                objectives: [
                    Objective(text: "Fahr zur Kobra-Villa 🐍", kind: .reach(w.door(.villa), needsCar: false),
                              setup: .spawnGang(at: w.door(.villa), count: 6, boss: true)),
                    Objective(text: "Erledige den Boss und seine Wachen!", kind: .eliminateGang),
                    Objective(text: "Häng die Polizei ab!", kind: .loseWanted)
                ]
            ),
            MissionDef(
                title: "Der große Bankraub",
                briefing: "Das ist der große Coup. Raub die Bank aus und bring die Beute sicher in dein Versteck!",
                reward: 10000,
                objectives: [
                    Objective(text: "Raube die Bank aus 🏦", kind: .rob(.bank)),
                    Objective(text: "Bring die Beute ins Versteck 🏠", kind: .reach(w.door(.safehouse), needsCar: false))
                ]
            )
        ]
    }
}

// MARK: - Speichern

struct SaveData: Codable {
    var money: Int
    var ammo: [Int: Int]
    var missions: Int
    var armor: Double
}

enum SaveStore {
    private static let key = "gangstercity.save.v1"

    static func load() -> SaveData? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SaveData.self, from: data)
    }

    static func save(_ save: SaveData) {
        if let data = try? JSONEncoder().encode(save) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
