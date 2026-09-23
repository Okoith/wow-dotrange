# DotRange

World-of-Warcraft-Addon, das die Entfernung zum aktuellen Ziel als drei farbige Boxen anzeigt.

| Boxen | Farbe (Standard) | Bedeutung |
|-------|------------------|-----------|
| 3 | Grün | Nahkampfreichweite (~5 yd) |
| 2 | Gelb | Mittlere Distanz (je nach Klasse ~13–30 yd) |
| 1 | Weiß | Ziel sichtbar, aber weiter entfernt |
| 0 | Dunkel | Kein Ziel / Ziel nicht sichtbar |

## Befehle

- `/dotrange` – Anzeige ein-/ausblenden
- `/dotrange config` – Einstellungsfenster öffnen (auch über *Optionen → AddOns → DotRange*)
- `/dotrange debug` – zeigt für das aktuelle Ziel jeden geprüften Spell mit „bekannt“ und Reichweitenergebnis

## Einstellungen

Farben, Boxgröße, Rahmenbreite, Transparenz, Position fixieren (die Anzeige lässt dann Mausklicks durch) und „Ohne Ziel ausblenden“. Alle Einstellungen werden pro Charakter gespeichert.

## Funktionsweise

Die Entfernung wird über `C_Spell.IsSpellInRange` mit klassenspezifischen Spells ermittelt. Pro Stufe sind mehrere Kandidaten hinterlegt; es genügt, wenn einer davon in Reichweite ist. Spells, die der Charakter nicht kennt (andere Spezialisierung, Talent, Gestalt), liefern `nil` und werden ignoriert.

| Klasse | Nahkampf | Mittlere Distanz |
|--------|----------|------------------|
| Krieger | Pummel | Taunt (30 yd), Charge (8–25 yd) |
| Schurke | Kick | Shadowstep (25 yd), Pistol Shot (20 yd) |
| Paladin | Rebuke, Crusader Strike | Hand of Reckoning (30 yd) |
| Mönch | Spear Hand Strike | Provoke (30 yd) |
| Todesritter | Death Strike | Death Grip (30 yd) |
| Dämonenjäger | Chaos Strike, Shear, Disrupt | Throw Glaive (30 yd), Torment (30 yd) |
| Jäger (Survival) | Muzzle, Raptor Strike | Harpoon (8–30 yd) |
| Druide (Katze/Bär) | Shred, Mangle | Growl (30 yd), Skull Bash (13 yd) |
| Schamane | Stormstrike, Lava Lash | Wind Shear (30 yd) |

## Bekannte Einschränkungen

- **Freundliche Ziele:** Die hinterlegten Spells wirken nur auf feindliche Ziele. Bei freundlichen Zielen zeigt die Anzeige daher höchstens 1 Box.
- **Reine Fernkampf-/Heiler-Spezialisierungen** (z. B. Beast Mastery/Marksmanship-Jäger, Magier, Priester) haben keine passenden Nahkampf-Spells und sehen höchstens 1 Box.
- **Midnight (12.0) / Secret Values:** Falls `IsSpellInRange` im Kampf oder in Instanzen einen Secret Value liefert, wird dieser nicht ausgewertet (die Stufe entfällt), statt einen Lua-Fehler zu erzeugen. `/dotrange debug` zeigt das als `range=SECRET` an.
