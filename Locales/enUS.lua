local _, ns = ...

-- Basistabelle (enUS). Fehlende Schlüssel liefern den Schlüssel selbst,
-- damit nie ein Lua-Fehler durch einen fehlenden Text entsteht.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

L["LOADED"] = "Version %s loaded. Type /dotrange help for commands."
L["UNKNOWN_COMMAND"] = "Unknown command. Type /dotrange help for commands."
L["MIGRATED"] = "Settings from version 2.x have been taken over."
L["NOT_IN_COMBAT"] = "Not possible during combat."

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

-- Einstellungsmenü
L["TAB_GENERAL"] = "General"
L["TAB_APPEARANCE"] = "Appearance"
L["NOT_AVAILABLE"] = "Not available for this class/specialization. Your character knows none of the spells DotRange uses for the range check, so the display is hidden."

L["OPT_TARGET"] = "Target"
L["OPT_HIDE_NO_TARGET"] = "Hide without target"
L["OPT_HOSTILE_ONLY"] = "Only for hostile targets"
L["OPT_HOSTILE_ONLY_DESC"] = "Hides the display while your target is friendly or cannot be attacked."

L["OPT_VISIBILITY"] = "Show"
L["OPT_VISIBILITY_DESC"] = "When the display is visible. It is always hidden during pet battles."
L["VISIBILITY_ALWAYS"] = "Always"
L["VISIBILITY_COMBAT"] = "Only in combat"
L["VISIBILITY_INSTANCE"] = "Only in instances"
L["VISIBILITY_GROUP"] = "Only in a group"
L["OPT_HIDE_VEHICLE"] = "Hide in vehicles"

L["OPT_POSITION"] = "Position"
L["OPT_POSITION_NOTE"] = "Move the display in WoW's Edit Mode (Esc > Edit Mode). The position is saved per Edit Mode layout."
L["OPT_LOCKED"] = "Lock"
L["OPT_LOCKED_DESC"] = "The display can no longer be moved, not even in Edit Mode."

L["OPT_DEBUG"] = "Debug mode"
L["OPT_DEBUG_DESC"] = "Writes a log to the SavedVariables (DotRangeDebugLog). It is saved on /reload or logout."

L["OPT_COLORS"] = "Colors"
L["COLOR_MELEE"] = "Melee"
L["COLOR_MELEE_DESC"] = "3 boxes: a melee spell is in range."
L["COLOR_NEAR"] = "Just outside"
L["COLOR_NEAR_DESC"] = "2 boxes: a medium-range spell is in range."
L["COLOR_MEDIUM"] = "Medium distance"
L["COLOR_MEDIUM_DESC"] = "1 box: the target is visible, but further away."
L["COLOR_OFF"] = "Inactive"
L["COLOR_OFF_DESC"] = "Boxes that are not lit."
L["COLOR_BORDER"] = "Border"

L["OPT_SIZE"] = "Size"
L["OPT_BOX_SIZE"] = "Box size"
L["OPT_BORDER_SIZE"] = "Border width"
L["OPT_ALPHA"] = "Opacity"
L["OPT_RESET_POSITION"] = "Reset position"
L["OPT_RESET_POSITION_DESC"] = "Moves the display back to its default position in the active Edit Mode layout."
L["OPT_SCALE"] = "Scale"
L["EDITMODE_MORE_SETTINGS"] = "More settings"
