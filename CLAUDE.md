# CLAUDE.md – Arbeitsanweisung für DotRange

Du überarbeitest das WoW-Addon **DotRange** (Retail 12.1.0, Interface `120100`) zu Version 3.0. Die fachliche Beschreibung steht in `SPEC.md`. Lies sie vollständig, bevor du Code schreibst.

## Rollen

- **Dominique** testet im Spiel, mergt Pull Requests und erstellt die Releases (Tags).
- **Koordinator** (Claude in Cowork) prüft Code, Logs und Screenshots und schreibt Folgeaufgaben.
- **Du** setzt um und öffnest pro Meilenstein einen Pull Request. **Keine Tags pushen.**

## Referenzprojekt OwnDPS

https://github.com/Okoith/wow-ownDPS ist vom selben Autor, fertig und im Spiel getestet. Übernimm von dort die bewährten Lösungen und passe sie an:

- `.pkgmeta`, `.github/workflows/release.yml`, `embeds.xml`, TOC mit `@project-version@`
- `Debug.lua` (Ringpuffer, Secret Values nur als `"<SECRET>"`)
- `Options.lua` (AceConfig, AceDBOptions, `AddToBlizOptions`, `AceConfigDialog:Open`)
- `EditMode.lua` (LibEditMode, Position pro Layout, Migration, Sperren, Slider mit `formatter`)
- Sichtbarkeitslogik aus `Display.lua`/`Core.lua`
- Locale-Aufbau aus `Locales/`

Die getesteten Fakten zu Midnight stehen in OwnDPS `SPEC.md`, Abschnitt 10. Sie gelten hier auch.

## Harte Regeln

1. Werte, die geheim sein können, niemals vergleichen, verrechnen, verketten oder als Tabellenschlüssel nutzen. Vorher mit `issecretvalue` prüfen.
2. Jeder Aufruf von `C_Spell.IsSpellInRange` und anderen Kampf-APIs steht in `pcall`.
3. Keine geheimen Werte in SavedVariables.
4. Kein Taint: keine geschützten Frames im Kampf ein- oder ausblenden, Sichtbarkeit über State Driver bzw. nicht geschützte Frames.
5. Die Anzeige-Logik und die Zauberliste aus 2.1 nicht ändern, außer die SPEC verlangt es.
6. Nichts raten: Unklare APIs defensiv absichern und im Debugmodus loggen.

## Meilensteine

1. **Grundgerüst:** Aufteilung in Dateien, Locales enUS/deDE, AceDB mit Migration aus `DotRangeCharDB`, Debugmodus, `.pkgmeta`, Release-Workflow, LICENSE (MIT, Copyright Dominique), CHANGELOG, README. Die Anzeige funktioniert wie in 2.1. Version `3.0.0-alpha.1`.
2. **Menü und Regeln:** AceConfig-Menü mit allen Optionen, Sichtbarkeit, „Nur bei feindlichen Zielen“, automatisches Ausblenden ohne passende Zauber. Version `3.0.0-alpha.2`.
3. **Bearbeitungsmodus:** LibEditMode wie bei OwnDPS inkl. Muster-Anzeige. Version `3.0.0-alpha.3`.

Nach jedem Meilenstein: Pull Request mit kurzer Testanleitung für Dominique.
