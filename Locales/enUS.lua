local _, ns = ...

-- Basistabelle (enUS). Fehlende Schlüssel liefern den Schlüssel selbst,
-- damit nie ein Lua-Fehler durch einen fehlenden Text entsteht.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

L["LOADED"] = "Version %s loaded. Type /dotrange help for commands."
L["UNKNOWN_COMMAND"] = "Unknown command. Type /dotrange help for commands."
L["NO_SPELLS"] = "No spells are defined for the class '%s'."
L["MIGRATED"] = "Settings from version 2.x have been taken over."

L["HELP_HEADER"] = "Commands:"
L["HELP_OPEN"] = "/dotrange - open the settings"
L["HELP_HELP"] = "/dotrange help - list the commands"
L["HELP_CHECK"] = "/dotrange check - range check for the current target in the chat"
L["HELP_DEBUG"] = "/dotrange debug on|off|clear|status - debug log"

L["DEBUG_ON"] = "Debug mode on. The log is saved on /reload or logout."
L["DEBUG_OFF"] = "Debug mode off."
L["DEBUG_CLEARED"] = "Debug log cleared."
L["DEBUG_STATUS"] = "Debug mode: %s, %d entries in the log."
L["ON"] = "on"
L["OFF"] = "off"

L["CHECK_HEADER"] = "Check:"
L["CHECK_NO_TARGET"] = "No target selected."
L["CHECK_TARGET"] = "Class=%s Visible=%s"
L["CHECK_MELEE"] = "Melee"
L["CHECK_NEAR"] = "Near"
L["CHECK_SPELL"] = "%s(%d) known=%s range=%s"

-- Einstellungsfenster (bis zum AceConfig-Menü in Meilenstein 2)
L["PANEL_TITLE"] = "DotRange - Settings"
L["VERSION"] = "Version %s"
L["HEADER_COLORS"] = "Colors"
L["COLOR_MELEE"] = "Melee:"
L["COLOR_NEAR"] = "Just outside:"
L["COLOR_MEDIUM"] = "Medium distance:"
L["COLOR_OFF"] = "Inactive:"
L["COLOR_BORDER"] = "Border color:"
L["HEADER_APPEARANCE"] = "Size & appearance"
L["OPT_BOX_SIZE"] = "Box size"
L["OPT_BORDER_SIZE"] = "Border width"
L["OPT_ALPHA"] = "Opacity"
L["HEADER_BEHAVIOR"] = "Behavior"
L["OPT_LOCKED"] = "Lock position (not movable, click-through)"
L["OPT_HIDE_NO_TARGET"] = "Hide without target"
L["RESET"] = "Reset"
L["SETTINGS_RESET"] = "Settings reset."
L["OPEN_SETTINGS"] = "Open settings"
L["ALT_COMMAND"] = "Alternatively: /dotrange"
