local ADDON_NAME, ns = ...
local L = ns.L

-- Init, AceDB mit Migration aus DotRangeCharDB, Events, Debug-Status, Slash-Befehle

local STATUS_INTERVAL = 1.0      -- Debug-Statuseintrag im Kampf (SPEC 3.8)

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "?"

ns.defaults = {
  profile = {
    colors = {
      melee  = { r = 0.0,  g = 0.87, b = 0.0  },  -- Grün  (Nahkampf, alle 3)
      near   = { r = 1.0,  g = 0.85, b = 0.0  },  -- Gelb  (knapp außerhalb, 2)
      medium = { r = 1.0,  g = 1.0,  b = 1.0  },  -- Weiß  (mittlere Distanz, 1)
      off    = { r = 0.15, g = 0.15, b = 0.15 },  -- Dunkel (inaktiv)
      border = { r = 0.0,  g = 0.0,  b = 0.0  },  -- Rahmen
    },
    boxSize = 24,
    borderSize = 1,
    alpha = 1.0,
    locked = false,
    hideNoTarget = false,
    hostileOnly = false,     -- nur bei feindlichen Zielen (SPEC 3.6)
    visibility = "always",   -- "always" | "combat" | "instance" | "group" (SPEC 3.5)
    hideInVehicle = false,
    scale = 1,
    position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 },   -- bis 3.0.0-alpha.2; Startwert für Layouts
    layouts = {},            -- Position pro Bearbeitungsmodus-Layout (EditMode.lua)
    stats = {                -- M+-Statistik (Stats.lua)
      enabled = true,        -- Statistik erfassen
      showWindow = true,     -- Fenster am Ende des Laufs zeigen
      windowPos = nil,       -- { point, relPoint, x, y }
    },
  },
  -- Pro Charakter, nicht im Profil: Profilkopien übertragen keine Statistik
  char = {
    mplus = {},              -- [mapID] = { name, runs, best, sum, count, last }
  },
  global = {
    debug = false,
  },
}

local function Print(msg)
  print("|cff33ff99DotRange|r: " .. msg)
end
ns.Print = Print

---------------------------------------------------------------------------
-- Migration aus 2.x (SPEC 3.2): DotRangeCharDB → Profil des Charakters.
-- Die alte Tabelle wird nur als migriert markiert, nicht gelöscht.
---------------------------------------------------------------------------

local function isColor(c)
  return type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number"
end

local function migrateCharDB()
  local old = DotRangeCharDB
  if type(old) ~= "table" or old.migrated then return false end

  local p = ns.db.profile
  local moved = {}

  if type(old.colors) == "table" then
    for key in pairs(ns.defaults.profile.colors) do
      local c = old.colors[key]
      if isColor(c) then
        p.colors[key] = { r = c.r, g = c.g, b = c.b }
        moved["colors." .. key] = true
      end
    end
  end
  for _, key in ipairs({ "boxSize", "borderSize", "alpha" }) do
    if type(old[key]) == "number" then
      p[key] = old[key]
      moved[key] = old[key]
    end
  end
  for _, key in ipairs({ "locked", "hideNoTarget" }) do
    if type(old[key]) == "boolean" then
      p[key] = old[key]
      moved[key] = old[key]
    end
  end
  -- 2.0 speicherte nur posPoint (Punkt = Relativpunkt), 2.1 zusätzlich posRelPoint
  if type(old.posPoint) == "string" and type(old.posX) == "number" and type(old.posY) == "number" then
    local relPoint = type(old.posRelPoint) == "string" and old.posRelPoint or old.posPoint
    p.position = { point = old.posPoint, relPoint = relPoint, x = old.posX, y = old.posY }
    moved.position = old.posPoint .. " " .. relPoint .. " " .. old.posX .. " " .. old.posY
  end

  old.migrated = true
  old.migratedTo = ns.VERSION
  old.migratedProfile = ns.db:GetCurrentProfile()
  ns.migration = moved
  return true
end

---------------------------------------------------------------------------
-- Aktualisierung
---------------------------------------------------------------------------

ns.inCombat = false
local lastStatus = 0

-- Im Kampf einmal pro Sekunde bei vorhandenem Ziel (SPEC 3.8)
local function logStatus(state)
  if not ns.inCombat then return end
  local now = GetTime()
  if now - lastStatus < STATUS_INTERVAL then return end

  local safeBool = ns.Display.SafeBool
  local exists, existsSecret = safeBool("UnitExists", UnitExists, "target")
  if exists ~= true and not existsSecret then return end
  lastStatus = now

  local hostile, hostileSecret = safeBool("UnitCanAttack", UnitCanAttack, "player", "target")
  local visible, visibleSecret = safeBool("UnitIsVisible", UnitIsVisible, "target")
  local out = {
    targetExists = existsSecret and "<SECRET>" or exists,
    hostile = hostileSecret and "<SECRET>" or hostile,
    visible = visibleSecret and "<SECRET>" or visible,
    state = state,
    hidden = ns.Display.last.hidden,          -- Grund, warum die Boxen ausgeblendet sind
    visibilityMacro = ns.Display.visibilityMacro,
    layout = ns.EditMode:GetLayoutName(),
    specID = ns.Spells.specID,
  }
  local Spells = ns.Spells
  for _, group in ipairs(Spells.GROUPS) do
    for _, spellID in ipairs(Spells[group]) do
      local inRange, secret, err = Spells:CheckRange(spellID, "target")
      local value = inRange
      if secret then value = "<SECRET>" elseif err then value = "error" end
      out[group .. " " .. spellID] = value
    end
  end
  ns.Debug:Add("status", out)
end

-- Specs mit eigener Stufentabelle (Verschlinger): Ergebnis von IsSpellInRange pro Zauber
-- (true/false/nil bzw. "<SECRET>"), auch außerhalb des Kampfes. Geloggt wird nur, wenn
-- sich ein Ergebnis oder der Zustand ändert.
local lastSpecRange

local function logSpecRange(state)
  local Spells = ns.Spells
  if not Spells.specTable then return end
  local exists = ns.Display.SafeBool("UnitExists", UnitExists, "target")
  if exists ~= true then
    lastSpecRange = nil
    return
  end
  local out = { specID = Spells.specID, state = state }
  local parts = { tostring(state) }
  for _, group in ipairs(Spells.GROUPS) do
    for _, spellID in ipairs(Spells[group]) do
      local inRange, secret, err = Spells:CheckRange(spellID, "target")
      local value
      if secret then
        value = "<SECRET>"
      elseif err then
        value = "error"
      else
        value = tostring(inRange)   -- "true" / "false" / "nil"
      end
      out[group .. " " .. spellID] = value
      parts[#parts + 1] = value
    end
  end
  local signature = table.concat(parts, ",")
  if signature == lastSpecRange then return end
  lastSpecRange = signature
  ns.Debug:Add("specRange", out)
end

function ns:Update()
  local state = ns.Display:Update()
  if ns.Debug:IsEnabled() then
    logStatus(state)
    if not ns.Display.editMode then logSpecRange(state) end
  end
end

local function safeUpdate()
  local ok, err = pcall(ns.Update, ns)
  if not ok then ns.Debug:Error("Update", err) end
end
ns.SafeUpdate = safeUpdate

-- Einstellungen sofort anwenden, ohne /reload
function ns:Refresh()
  ns.Display:ApplySettings()
  ns.Display:UpdateVisibility()
  safeUpdate()
end

function ns:OnProfileChanged()
  ns:Refresh()
  ns.EditMode:Refresh()
  ns.Options:Notify()
end
ns.OnProfileCopied = ns.OnProfileChanged
ns.OnProfileReset = ns.OnProfileChanged

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}
local lastKnownSignature

-- Spezialisierung und Stufen fürs Debug-Log: aktuelle Spec-ID, Devourer-ID der
-- Stufentabelle, alle Specs der Klasse (zur Laufzeit ermittelt) und die Reichweite
-- der Zauber laut C_Spell.GetSpellInfo.
local function logSpec(reason)
  if not ns.Debug:IsEnabled() then return end
  local Spells = ns.Spells
  local specID, specName = Spells:GetSpec()
  local out = Spells:ClassSpecs()
  out.reason = reason
  out.specID = specID
  out.specName = specName
  out.devourerSpecID = Spells.DEVOURER_SPEC_ID
  out.isDevourer = specID == Spells.DEVOURER_SPEC_ID
  out.specTable = Spells.specTable
  out.visibleFallback = Spells.visibleFallback
  for _, group in ipairs(Spells.GROUPS) do
    for _, spellID in ipairs(Spells[group]) do
      local minRange, maxRange = Spells:GetRangeInfo(spellID)
      out["range " .. group .. " " .. spellID] = ns.Debug.S(minRange) .. "-" .. ns.Debug.S(maxRange)
    end
  end
  ns.Debug:Add("spec", out)
end

-- Spezialisierung und bekannte Zauber neu prüfen (SPEC 3.7). Loggen nur, wenn sich
-- etwas geändert hat, denn SPELLS_CHANGED kommt oft.
local function spellsChanged(reason)
  if not ns.loggedIn then return end
  local specChanged = ns.Spells:ApplySpec()
  if specChanged then logSpec(reason) end
  local availabilityChanged = ns.Spells:UpdateAvailability()
  if availabilityChanged then
    ns.Debug:Add("availability", { reason = reason, available = ns.Spells.available })
  end
  if specChanged or availabilityChanged then
    ns.Options:Notify()
    safeUpdate()
  end
  if not ns.Debug:IsEnabled() then return end
  local _, signature = ns.Spells:KnownInfo()
  if signature == lastKnownSignature then return end
  lastKnownSignature = signature
  ns.Debug:LogSpells(reason)
end

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  events:UnregisterEvent("ADDON_LOADED")

  -- Ohne dritten Parameter legt AceDB ein Profil pro Charakter an ("Name - Realm")
  ns.db = LibStub("AceDB-3.0"):New("DotRangeDB", ns.defaults)
  ns.db.RegisterCallback(ns, "OnProfileChanged", "OnProfileChanged")
  ns.db.RegisterCallback(ns, "OnProfileCopied", "OnProfileCopied")
  ns.db.RegisterCallback(ns, "OnProfileReset", "OnProfileReset")
  ns.Debug:Init()
  ns.migrated = migrateCharDB()
  ns.Options:Init()
end

function handlers.PLAYER_LOGIN()
  ns.Spells:Init()
  ns.Spells:UpdateAvailability()
  ns.inCombat = InCombatLockdown() and true or false
  ns.Display:Create()
  ns.EditMode:Init()

  ns.Debug:LogMeta()
  logSpec("login")
  if ns.migrated then
    ns.Debug:Add("migration", ns.migration)
    Print(L["MIGRATED"])
  end
  lastKnownSignature = select(2, ns.Spells:KnownInfo())
  ns.loggedIn = true
  ns.Debug:Add("availability", {
    reason = "login", available = ns.Spells.available, unclear = ns.Spells.availabilityUnclear,
  })
  Print(L["LOADED"]:format(ns.VERSION))
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
  ns.Debug:LogInstance({ initial = isInitialLogin, reload = isReloadingUi })
  ns.Display:UpdateVisibility()   -- "Nur in Instanzen" hängt an IsInInstance()
  -- M+-Lauf nach Login/Reload fortsetzen bzw. Verlassen der Instanz erkennen
  local reload = (isInitialLogin == true or isReloadingUi == true) and "reload" or "enterWorld"
  ns.Stats:CheckActive(reload)
end

function handlers.ZONE_CHANGED_NEW_AREA()
  ns.Display:UpdateVisibility()
  ns.Stats:CheckActive("zoneChanged")
end

-- M+-Statistik (Stats.lua). Events und APIs im Spiel noch nicht getestet.
function handlers.CHALLENGE_MODE_START(mapID)
  ns.Stats:OnChallengeStart(mapID)
end

function handlers.CHALLENGE_MODE_COMPLETED()
  ns.Stats:OnChallengeCompleted()
end

function handlers.CHALLENGE_MODE_RESET(mapID)
  ns.Stats:OnChallengeReset(mapID)
end

-- Bossliste aus den Szenario-Zielen (Stats.lua, nach WarpDeplete)
function handlers.SCENARIO_CRITERIA_UPDATE()
  ns.Stats:OnScenarioUpdate("SCENARIO_CRITERIA_UPDATE")
end

function handlers.SCENARIO_POI_UPDATE()
  ns.Stats:OnScenarioUpdate("SCENARIO_POI_UPDATE")
end

function handlers.ENCOUNTER_START(...)
  ns.Stats:OnEncounterStart(...)
end

function handlers.ENCOUNTER_END(...)
  ns.Stats:OnEncounterEnd(...)
end

-- Zielregeln sofort anwenden, nicht erst beim nächsten Takt
function handlers.PLAYER_TARGET_CHANGED()
  safeUpdate()
end

function handlers.PLAYER_REGEN_DISABLED()
  ns.inCombat = true
  lastStatus = 0
  ns.Debug:Add("combatStart", { groupSize = GetNumGroupMembers() })
end

function handlers.PLAYER_REGEN_ENABLED()
  ns.inCombat = false
  ns.Debug:Add("combatEnd")
  ns.Display:UpdateVisibility()   -- im Kampf zurückgestellte Änderung nachholen
  ns.Stats:OnCombatEnd()          -- im Kampf zurückgestelltes Statistikfenster zeigen
end

function handlers.PLAYER_SPECIALIZATION_CHANGED(unit)
  if unit ~= nil and unit ~= "player" then return end
  spellsChanged("specChanged")
end

function handlers.SPELLS_CHANGED()
  spellsChanged("spellsChanged")
end

events:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if not handler then return end
  -- Vor ADDON_LOADED gibt es noch keine Datenbank
  if not ns.db and event ~= "ADDON_LOADED" then return end
  local ok, err = pcall(handler, ...)
  if not ok then
    if ns.db then ns.Debug:Error(event, err) end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
      geterrorhandler()(err)
    end
  end
end)

for event in pairs(handlers) do
  local ok = pcall(events.RegisterEvent, events, event)
  if not ok then Print("Event unknown: " .. event) end
end

---------------------------------------------------------------------------
-- Slash-Befehle. /dotrange ohne Argument öffnet die Einstellungen.
---------------------------------------------------------------------------

local function printHelp()
  Print(L["HELP_HEADER"])
  for _, key in ipairs({ "HELP_OPEN", "HELP_HELP", "HELP_CHECK", "HELP_STATS", "HELP_DEBUG" }) do
    print("  " .. L[key])
  end
end

local function debugValue(v, secret)
  if secret then return "<SECRET>" end
  return tostring(v)
end

-- Chat-Ausgabe der Reichweitenprüfung (bisher /dotrange debug)
local function spellLine(label, spellList)
  if #spellList == 0 then return label .. ": -" end
  local parts = {}
  for _, spellID in ipairs(spellList) do
    local inRange, secret = ns.Spells:CheckRange(spellID, "target")
    parts[#parts + 1] = L["CHECK_SPELL"]:format(ns.Spells:GetName(spellID), spellID,
      tostring(ns.Spells:IsKnown(spellID)), debugValue(inRange, secret))
  end
  return label .. ": " .. table.concat(parts, ", ")
end

local commands = {}

function commands.help()
  printHelp()
end

function commands.check()
  local safeBool = ns.Display.SafeBool
  local exists, existsSecret = safeBool("UnitExists", UnitExists, "target")
  if exists ~= true and not existsSecret then
    Print(L["CHECK_NO_TARGET"])
    return
  end
  local visible, visibleSecret = safeBool("UnitIsVisible", UnitIsVisible, "target")
  local Spells = ns.Spells
  Print(L["CHECK_HEADER"] .. " " .. L["CHECK_TARGET"]:format(tostring(Spells.class), debugValue(visible, visibleSecret)))
  local specID, specName = Spells:GetSpec()
  print("  " .. L["CHECK_SPEC"]:format(tostring(specName), tostring(specID),
    Spells.specTable and L["CHECK_SPEC_OWN"] or L["CHECK_SPEC_CLASS"]))
  print("  " .. spellLine(L["CHECK_MELEE"], Spells.melee))
  print("  " .. spellLine(L["CHECK_NEAR"], Spells.near))
  if #Spells.far > 0 then
    print("  " .. spellLine(L["CHECK_FAR"], Spells.far))
  end
end

-- /dotrange stats: Fenster mit dem letzten Lauf; /dotrange stats reset [confirm]
function commands.stats(arg)
  local sub, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  if sub == "reset" then
    ns.Stats:ResetCommand(rest)
  else
    ns.Stats:ShowWindow(ns.db.char.mplusLast)
  end
end

function commands.debug(arg)
  if arg == "on" then
    ns.Debug:SetEnabled(true)
    ns.Debug:LogInstance({ reason = "debugOn" })
    logSpec("debugOn")
    ns.Options:Notify()
    Print(L["DEBUG_ON"])
  elseif arg == "off" then
    ns.Debug:Add("debugOff")
    ns.Debug:SetEnabled(false)
    ns.Options:Notify()
    Print(L["DEBUG_OFF"])
  elseif arg == "clear" then
    ns.Debug:Clear()
    Print(L["DEBUG_CLEARED"])
  else
    Print(L["DEBUG_STATUS"]:format(ns.Debug:IsEnabled() and L["ON"] or L["OFF"], ns.Debug:Count()))
  end
end

SLASH_DOTRANGE1 = "/dotrange"
SlashCmdList.DOTRANGE = function(msg)
  if not ns.db then return end
  local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "" then
    -- Menü öffnen; ohne Menü (Bibliothek fehlt) die Hilfe zeigen
    if not ns.Options:Open() then printHelp() end
  elseif commands[cmd] then
    commands[cmd](arg)
  else
    Print(L["UNKNOWN_COMMAND"])
  end
end
