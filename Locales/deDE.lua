if GetLocale() ~= "deDE" then return end

local _, ns = ...
local L = ns.L

L["LOADED"] = "Version %s geladen. Befehle mit /dotrange help."
L["UNKNOWN_COMMAND"] = "Unbekannter Befehl. Befehle mit /dotrange help."
L["NO_SPELLS"] = "Für die Klasse '%s' sind keine Zauber hinterlegt."
L["MIGRATED"] = "Einstellungen aus Version 2.x wurden übernommen."

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

L["PANEL_TITLE"] = "DotRange - Einstellungen"
L["VERSION"] = "Version %s"
L["HEADER_COLORS"] = "Farben"
L["COLOR_MELEE"] = "Nahkampf:"
L["COLOR_NEAR"] = "Knapp außerhalb:"
L["COLOR_MEDIUM"] = "Mittlere Distanz:"
L["COLOR_OFF"] = "Inaktiv:"
L["COLOR_BORDER"] = "Rahmenfarbe:"
L["HEADER_APPEARANCE"] = "Größe & Aussehen"
L["OPT_BOX_SIZE"] = "Boxgröße"
L["OPT_BORDER_SIZE"] = "Rahmenbreite"
L["OPT_ALPHA"] = "Transparenz"
L["HEADER_BEHAVIOR"] = "Verhalten"
L["OPT_LOCKED"] = "Position fixieren (nicht verschiebbar, klickbar durch)"
L["OPT_HIDE_NO_TARGET"] = "Ohne Ziel ausblenden"
L["RESET"] = "Zurücksetzen"
L["SETTINGS_RESET"] = "Einstellungen zurückgesetzt."
L["OPEN_SETTINGS"] = "Einstellungen öffnen"
L["ALT_COMMAND"] = "Alternativ: /dotrange"
