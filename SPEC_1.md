# DotRange – Spezifikation v3.0

Stand: 23.09.2026 · WoW Retail 12.1.0 (Interface `120100`)

## 1. Ziel

DotRange zeigt die Entfernung zum aktuellen Ziel als **drei farbige Boxen**. Die Logik aus Version 2.1 bleibt unverändert. Version 3.0 macht das Addon veröffentlichungsfertig und bringt es technisch auf den Stand von OwnDPS (https://github.com/Okoith/wow-ownDPS).

## 2. Anzeige (unverändert aus 2.1)

| Zustand | Boxen | Farbe (Standard) |
|---|---|---|
| Ein `melee`-Zauber in Reichweite | 3 | Grün |
| Ein `near`-Zauber in Reichweite | 2 | Gelb |
| Ziel sichtbar (`UnitIsVisible`), aber weiter weg | 1 | Weiß |
| Kein Ziel / nicht sichtbar | 0 | alle Boxen „inaktiv“ |

- Reichweite über `C_Spell.IsSpellInRange` mit der Zauberliste pro Klasse aus 2.1 (`CLASS_SPELLS`, mehrere Kandidaten, einer genügt)
- Aktualisierung alle 0,1 s
- Bestehende Optionen bleiben: Farben (Nahkampf, knapp außerhalb, mittlere Distanz, inaktiv, Rahmen), Boxgröße, Rahmenbreite, Transparenz, Sperren, „Ohne Ziel ausblenden“

## 3. Neu in 3.0

### 3.1 Sprache
- Englisch (enUS) als Standard, Deutsch (deDE) als Übersetzung
- Alle Texte über eine Locale-Tabelle, Fallback enUS

### 3.2 Profile (AceDB-3.0)
- Einstellungen pro Charakter (Standardprofil = Charakter), wie bei OwnDPS
- „Kopieren von …“, Zurücksetzen und Profilverwaltung über AceDBOptions-3.0
- **Migration:** Beim ersten Start von 3.0 die Werte aus der alten `DotRangeCharDB` (SavedVariablesPerCharacter) in das Profil des Charakters übernehmen. Danach die alte Tabelle als migriert markieren, nicht löschen.

### 3.3 Einstellungsmenü (AceConfig-3.0)
- Eintrag unter *Einstellungen → AddOns → DotRange*
- `/dotrange` ohne Argument öffnet das Menü, `/dotrange help` listet die Befehle
- Das bisherige eigene Einstellungsfenster entfällt
- Änderungen wirken sofort

### 3.4 Bearbeitungsmodus (LibEditMode)
- Verschieben im WoW-Bearbeitungsmodus, Position pro Layout, Übernahme der bisherigen Position
- Im LibEditMode-Dialog: Skalierungsregler (Anzeige mit 2 Nachkommastellen, Wert auf 0,01 gerundet) und Button „Weitere Einstellungen“
- Der Button öffnet das Menü als eigenständiges Fenster über `AceConfigDialog:Open` (bei OwnDPS getestet: `Settings.OpenToCategory` zeigt im Bearbeitungsmodus kein Fenster)
- Option „Sperren“: auch im Bearbeitungsmodus nicht verschiebbar (Technik aus OwnDPS `EditMode.lua`)
- Im Bearbeitungsmodus immer sichtbar, als Muster mit drei grünen Boxen

### 3.5 Sichtbarkeit
- Immer (Standard) / nur im Kampf / nur in Instanzen / nur in Gruppe
- Optional im Fahrzeug ausblenden, im Haustierkampf immer ausgeblendet
- Umsetzung ohne Taint (State Driver bzw. Events, wie OwnDPS)

### 3.6 Zieloptionen
- „Ohne Ziel ausblenden“ (bleibt)
- **Neu:** „Nur bei feindlichen Zielen“ (Standard: aus). Prüfung über `UnitCanAttack("player", "target")`. Bei freundlichen Zielen dann ausblenden.

### 3.7 Klassen und Spezialisierungen ohne passende Zauber
- Prüfen, ob der Charakter mindestens einen Zauber aus `melee` oder `near` kennt (`C_SpellBook.IsSpellKnown` o. ä., vorher in der aktuellen API-Doku prüfen)
- Wenn nicht: Anzeige automatisch ausblenden, im Menü ein Hinweis „Für diese Klasse/Spezialisierung nicht verfügbar“
- Neu prüfen bei `PLAYER_SPECIALIZATION_CHANGED` und `SPELLS_CHANGED`
- Kennt der Charakter nur `near`-Zauber, funktioniert die Anzeige mit maximal 2 Boxen

### 3.8 Debugmodus
- Schalter im Menü und `/dotrange debug on|off|clear`, Standard aus
- Log in SavedVariables `DotRangeDebugLog`, Ringpuffer max. 5000 Einträge
- Secret Values werden **nie** gespeichert, nur `"<SECRET>"` (Prüfung mit `issecretvalue`)
- Inhalt: Version, Build, Klasse, Spezialisierung, bekannte Zauber aus der Liste, Kampfbeginn/-ende, Instanzwechsel, Fehler
- Im Kampf einmal pro Sekunde (bei vorhandenem Ziel): Ziel vorhanden, feindlich, sichtbar, **pro Zauber das Ergebnis von `IsSpellInRange` bzw. ob es geheim ist**, angezeigter Zustand (0–3)
- Das bisherige `/dotrange debug` mit Chat-Ausgabe bleibt als `/dotrange check`

## 4. Offener Prüfpunkt: Secret Values

Es ist nicht getestet, ob `C_Spell.IsSpellInRange` im Kampf in Instanzen geheime Werte liefert. Der Debugmodus muss genau das beantworten. Ist das Ergebnis geheim, zählt es aktuell als „nicht in Reichweite“. Eine Lösung dafür wird erst nach dem Test entworfen.

## 5. Technik

- Bibliotheken über `.pkgmeta` externals: LibStub, CallbackHandler-1.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0, AceConfig-3.0, LibEditMode (Quellen wie bei OwnDPS)
- Alle API-Aufrufe in `pcall`, keine Rechnung oder Vergleiche mit Werten, die geheim sein können
- TOC: `## Interface: 120100`, `## Version: @project-version@`, `## SavedVariables: DotRangeDB, DotRangeDebugLog`, `## SavedVariablesPerCharacter: DotRangeCharDB` (nur noch für die Migration)

## 6. Veröffentlichung

- Lizenz MIT, `LICENSE`, `CHANGELOG.md` (Nutzertexte auf Englisch), `README.md` (Englisch)
- Release-Workflow mit BigWigs Packager bei Tag `v*`, wie bei OwnDPS
- Versionen: `v3.0.0-alpha.N` für Tests, dann `v3.0.0`
- CurseForge-Projekt-ID später in der TOC (`## X-Curse-Project-ID`)
