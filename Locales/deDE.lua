if GetLocale() ~= "deDE" then return end

local _, ns = ...
local L = ns.L

L["LOADED"] = "Version %s geladen. Befehle mit /dotrange help."
L["UNKNOWN_COMMAND"] = "Unbekannter Befehl. Befehle mit /dotrange help."
L["MIGRATED"] = "Einstellungen aus Version 2.x wurden übernommen."
L["NOT_IN_COMBAT"] = "Im Kampf nicht möglich."

L["HELP_HEADER"] = "Befehle:"
L["HELP_OPEN"] = "/dotrange - Einstellungen öffnen"
L["HELP_HELP"] = "/dotrange help - Befehle auflisten"
L["HELP_CHECK"] = "/dotrange check - Reichweitenprüfung für das aktuelle Ziel im Chat"
L["HELP_DEBUG"] = "/dotrange debug on|off|clear|status - Debug-Log"

L["DEBUG_ON"] = "Debugmodus an. Das Log wird bei /reload oder Logout gespeichert."
L["DEBUG_OFF"] = "Debugmodus aus."
L["DEBUG_CLEARED"] = "Debug-Log geleert."
L["DEBUG_STATUS"] = "Debugmodus: %s, %d Einträge im Log."
L["ON"] = "an"
L["OFF"] = "aus"

L["CHECK_HEADER"] = "Prüfung:"
L["CHECK_NO_TARGET"] = "Kein Ziel ausgewählt."
L["CHECK_TARGET"] = "Klasse=%s Sichtbar=%s"
L["CHECK_MELEE"] = "Nahkampf"
L["CHECK_NEAR"] = "Mittel"
L["CHECK_SPELL"] = "%s(%d) bekannt=%s Reichweite=%s"

L["TAB_GENERAL"] = "Allgemein"
L["TAB_APPEARANCE"] = "Darstellung"
L["NOT_AVAILABLE"] = "Für diese Klasse/Spezialisierung nicht verfügbar. Dein Charakter kennt keinen der Zauber, die DotRange für die Reichweitenprüfung nutzt, deshalb ist die Anzeige ausgeblendet."

L["OPT_TARGET"] = "Ziel"
L["OPT_HIDE_NO_TARGET"] = "Ohne Ziel ausblenden"
L["OPT_HOSTILE_ONLY"] = "Nur bei feindlichen Zielen"
L["OPT_HOSTILE_ONLY_DESC"] = "Blendet die Anzeige aus, solange das Ziel freundlich ist oder nicht angegriffen werden kann."

L["OPT_VISIBILITY"] = "Anzeigen"
L["OPT_VISIBILITY_DESC"] = "Wann die Anzeige sichtbar ist. Im Haustierkampf ist sie immer ausgeblendet."
L["VISIBILITY_ALWAYS"] = "Immer"
L["VISIBILITY_COMBAT"] = "Nur im Kampf"
L["VISIBILITY_INSTANCE"] = "Nur in Instanzen"
L["VISIBILITY_GROUP"] = "Nur in Gruppe"
L["OPT_HIDE_VEHICLE"] = "Im Fahrzeug ausblenden"

L["OPT_POSITION"] = "Position"
L["OPT_POSITION_NOTE"] = "Die Anzeige im WoW-Bearbeitungsmodus verschieben (Esc > Bearbeitungsmodus). Die Position wird pro Layout gespeichert."
L["OPT_LOCKED"] = "Sperren"
L["OPT_LOCKED_DESC"] = "Die Anzeige lässt sich nicht mehr verschieben, auch nicht im Bearbeitungsmodus."

L["OPT_DEBUG"] = "Debugmodus"
L["OPT_DEBUG_DESC"] = "Schreibt ein Log in die SavedVariables (DotRangeDebugLog). Es wird bei /reload oder Logout gespeichert."

L["OPT_COLORS"] = "Farben"
L["COLOR_MELEE"] = "Nahkampf"
L["COLOR_MELEE_DESC"] = "3 Boxen: ein Nahkampf-Zauber ist in Reichweite."
L["COLOR_NEAR"] = "Knapp außerhalb"
L["COLOR_NEAR_DESC"] = "2 Boxen: ein Zauber mittlerer Reichweite ist in Reichweite."
L["COLOR_MEDIUM"] = "Mittlere Distanz"
L["COLOR_MEDIUM_DESC"] = "1 Box: Das Ziel ist sichtbar, aber weiter entfernt."
L["COLOR_OFF"] = "Inaktiv"
L["COLOR_OFF_DESC"] = "Boxen, die nicht leuchten."
L["COLOR_BORDER"] = "Rahmen"

L["OPT_SIZE"] = "Größe"
L["OPT_BOX_SIZE"] = "Boxgröße"
L["OPT_BORDER_SIZE"] = "Rahmenbreite"
L["OPT_ALPHA"] = "Deckkraft"
L["OPT_RESET_POSITION"] = "Position zurücksetzen"
L["OPT_RESET_POSITION_DESC"] = "Setzt die Anzeige im aktiven Bearbeitungsmodus-Layout auf die Standardposition zurück."
L["OPT_SCALE"] = "Skalierung"
L["EDITMODE_MORE_SETTINGS"] = "Weitere Einstellungen"
