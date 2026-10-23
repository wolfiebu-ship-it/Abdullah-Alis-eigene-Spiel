# Gangster City 🚗💥

Abdullah Alis eigenes Spiel: ein GTA-ähnliches Action-Spiel von oben gesehen, gebaut mit **SwiftUI**.

Du kommst neu nach *Gangster City*. Klau Autos, raub Läden aus, kauf dir Waffen,
leg dich mit der Gang „Rote Kobras“ an und häng die Polizei ab, bis dir die ganze Stadt gehört.

## Was es im Spiel gibt

- **Offene Stadt** mit Straßen, Kreuzungen, Parks, Verkehr und Passanten
- **Autos fahren und klauen**: Steig in geparkte Autos oder wirf Fahrer aus ihrem Auto.
  Autos können kaputtgehen, brennen und explodieren.
- **Waffen**: Fäuste, Pistole, Maschinenpistole, Schrotflinte und Sturmgewehr. Zielen geht automatisch.
- **Waffenladen** 🎯: Waffen, Munition und Schutzweste kaufen
- **Überfälle** 💰: Kiosk, Supermarkt, Tankstelle, Juwelier und Bank ausrauben (grüne `$`-Kreise)
- **Polizei mit Fahndungssternen** ⭐️ (1–5):
  - 1 Stern: Polizisten versuchen dich zu verhaften
  - ab 2 Sternen wird geschossen
  - ab 3 Sternen kommen Streifenwagen mit Blaulicht
  - Bleib außer Sicht, bis die Sterne verschwinden
- **8 Missionen** übers Handy 📱, vom ersten Kiosk-Überfall bis zum großen Bankraub
- **Krankenhaus** 🏥 (heilen), **Versteck** 🏠 (speichern), Minikarte und Missionspfeil
- „ERLEDIGT“ wenn du stirbst, „VERHAFTET“ wenn die Polizei dich schnappt

## So startest du das Spiel

Das Projekt ist ein **App-Playground** (`GangsterCity.swiftpm`).

**Auf dem iPad oder Mac mit Swift Playgrounds:**
1. Den Ordner `GangsterCity.swiftpm` aufs Gerät kopieren (z. B. über iCloud Drive).
2. In der App *Swift Playgrounds* öffnen.
3. Auf ▶︎ „Ausführen“ tippen.

**Auf dem Mac mit Xcode (15 oder neuer):**
1. In Xcode `Datei → Öffnen…` wählen und den Ordner `GangsterCity.swiftpm` auswählen.
2. Oben einen iPhone- oder iPad-Simulator auswählen.
3. Mit ▶︎ (⌘R) starten.

Benötigt iOS / iPadOS 17 oder neuer. Das Spiel läuft im Querformat.

## Steuerung

| Touch | Tastatur | Aktion |
|---|---|---|
| Joystick links | WASD / Pfeiltasten | Laufen / Fahren |
| Roter Knopf | Leertaste | Schießen / Schlagen |
| „Waffe“ | Q | Waffe wechseln |
| „Einsteigen“ / „Raus“ | E | Auto ein- / aussteigen |
| Aktionsknopf (erscheint vor Läden) | R | Ausrauben, Waffenladen, Heilen, Speichern |
| 📱 | M | Missionen |
| ⏸ | P | Pause |

## Aufbau des Codes

```
GangsterCity.swiftpm/
├── Package.swift            App-Einstellungen
├── GangsterCityApp.swift    Startpunkt der App
├── Engine/                  Spiellogik (ohne Grafik)
│   ├── GameEngine.swift     Spieler, Polizei-KI, Gang, Autos, Kugeln, Überfälle, Missionen
│   ├── World.swift          Stadtkarte, Kollisionen, Wegfindung
│   ├── Entities.swift       Waffen, Personen, Autos, Gegenstände
│   ├── Missions.swift       Alle Missionen + Speichern
│   └── Geometry.swift       Vektor-Mathe
└── Views/                   Alles, was man sieht
    ├── GameView.swift       Spielbildschirm, Joystick, Knöpfe, Tastatur
    ├── GameRenderer.swift   Zeichnet Stadt, Figuren, Autos und Effekte
    ├── HUDView.swift        Geld, Leben, Sterne, Minikarte
    ├── MenuViews.swift      Waffenladen, Handy, Pause
    └── TitleView.swift      Hauptmenü und Hilfe
```

### Ideen zum Selbst-Erweitern

- Neue Mission: in `Engine/Missions.swift` einfach eine weitere `MissionDef` hinzufügen.
- Neue Waffe: in `Engine/Entities.swift` einen neuen `case` bei `Weapon` mit Schaden, Preis usw. einfügen.
- Mehr Polizei oder schwerere Fahndung: Zahlen in `updateSpawning` und `starHeat` in `GameEngine.swift` ändern.
