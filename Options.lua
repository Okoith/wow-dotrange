local ADDON_NAME, ns = ...
local L = ns.L

-- Einstellungsmenü (SPEC 3.3) mit AceConfig-3.0 / AceConfigDialog-3.0,
-- eingetragen unter Einstellungen > AddOns. Profile über AceDBOptions-3.0 (SPEC 3.2).
-- Jede Änderung wird sofort angewendet (ns:Refresh), ohne /reload. Übernommen aus OwnDPS.

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
local AceDBOptions = LibStub("AceDBOptions-3.0", true)

---------------------------------------------------------------------------
-- Zugriff auf Profilwerte über info.arg = { "pfad", "zum", "schlüssel" }
---------------------------------------------------------------------------

local function resolve(path)
  local t = ns.db.profile
  for i = 1, #path - 1 do t = t[path[i]] end
  return t, path[#path]
end

local function get(info)
  local t, k = resolve(info.arg)
  return t[k]
end

local function set(info, value)
  local t, k = resolve(info.arg)
  t[k] = value
  ns.Debug:Add("setting", { [table.concat(info.arg, ".")] = value })
  ns:Refresh()
  ns.EditMode:Refresh()   -- Sperre und Skalierung im Bearbeitungsmodus-Dialog nachziehen
end

local function getColor(info)
  local t, k = resolve(info.arg)
  local c = t[k]
  return c.r, c.g, c.b
end

local function setColor(info, r, g, b)
  local t, k = resolve(info.arg)
  t[k] = { r = r, g = g, b = b }
  ns:Refresh()
end

---------------------------------------------------------------------------
-- Optionstabelle
---------------------------------------------------------------------------

local function buildOptions()
  local o = {
    type = "group",
    name = "DotRange",
    childGroups = "tab",
    args = {},
  }

  -- Allgemein ---------------------------------------------------------------
  o.args.general = {
    type = "group", order = 1, name = L["TAB_GENERAL"],
    args = {
      -- Hinweis, wenn der Charakter keinen passenden Zauber kennt (SPEC 3.7)
      unavailable = {
        type = "description", order = 0, fontSize = "medium", width = "full",
        name = function() return "|cffff8020" .. L["NOT_AVAILABLE"] .. "|r\n" end,
        hidden = function() return ns.Spells.available end,
      },
      targetHeader = { type = "header", order = 10, name = L["OPT_TARGET"] },
      hideNoTarget = {
        type = "toggle", order = 11, name = L["OPT_HIDE_NO_TARGET"], width = "full",
        arg = { "hideNoTarget" }, get = get, set = set,
      },
      hostileOnly = {
        type = "toggle", order = 12, name = L["OPT_HOSTILE_ONLY"], desc = L["OPT_HOSTILE_ONLY_DESC"], width = "full",
        arg = { "hostileOnly" }, get = get, set = set,
      },
      visibilityHeader = { type = "header", order = 20, name = L["OPT_VISIBILITY"] },
      visibility = {
        type = "select", order = 21, name = L["OPT_VISIBILITY"], desc = L["OPT_VISIBILITY_DESC"],
        values = {
          always = L["VISIBILITY_ALWAYS"], combat = L["VISIBILITY_COMBAT"],
          instance = L["VISIBILITY_INSTANCE"], group = L["VISIBILITY_GROUP"],
        },
        sorting = { "always", "combat", "instance", "group" },
        arg = { "visibility" }, get = get, set = set,
      },
      hideInVehicle = {
        type = "toggle", order = 22, name = L["OPT_HIDE_VEHICLE"],
        arg = { "hideInVehicle" }, get = get, set = set,
      },
      positionHeader = { type = "header", order = 30, name = L["OPT_POSITION"] },
      positionNote = { type = "description", order = 31, name = L["OPT_POSITION_NOTE"] },
      locked = {
        type = "toggle", order = 32, name = L["OPT_LOCKED"], desc = L["OPT_LOCKED_DESC"],
        arg = { "locked" }, get = get, set = set,
      },
      resetPosition = {
        type = "execute", order = 33, name = L["OPT_RESET_POSITION"], desc = L["OPT_RESET_POSITION_DESC"],
        func = function() ns.EditMode:ResetPosition() end,
      },
      debugHeader = { type = "header", order = 90, name = L["OPT_DEBUG"] },
      debug = {
        type = "toggle", order = 91, name = L["OPT_DEBUG"], desc = L["OPT_DEBUG_DESC"], width = "full",
        get = function() return ns.Debug:IsEnabled() end,
        set = function(_, value)
          if not value then ns.Debug:Add("debugOff") end
          ns.Debug:SetEnabled(value)
        end,
      },
    },
  }

  -- Darstellung -------------------------------------------------------------
  o.args.appearance = {
    type = "group", order = 2, name = L["TAB_APPEARANCE"],
    args = {
      colorsHeader = { type = "header", order = 10, name = L["OPT_COLORS"] },
      colorMelee = {
        type = "color", order = 11, name = L["COLOR_MELEE"], desc = L["COLOR_MELEE_DESC"],
        arg = { "colors", "melee" }, get = getColor, set = setColor,
      },
      colorNear = {
        type = "color", order = 12, name = L["COLOR_NEAR"], desc = L["COLOR_NEAR_DESC"],
        arg = { "colors", "near" }, get = getColor, set = setColor,
      },
      colorMedium = {
        type = "color", order = 13, name = L["COLOR_MEDIUM"], desc = L["COLOR_MEDIUM_DESC"],
        arg = { "colors", "medium" }, get = getColor, set = setColor,
      },
      colorOff = {
        type = "color", order = 14, name = L["COLOR_OFF"], desc = L["COLOR_OFF_DESC"],
        arg = { "colors", "off" }, get = getColor, set = setColor,
      },
      colorBorder = {
        type = "color", order = 15, name = L["COLOR_BORDER"],
        arg = { "colors", "border" }, get = getColor, set = setColor,
      },
      sizeHeader = { type = "header", order = 20, name = L["OPT_SIZE"] },
      boxSize = {
        type = "range", order = 21, name = L["OPT_BOX_SIZE"], min = 12, max = 48, step = 1,
        arg = { "boxSize" }, get = get, set = set,
      },
      borderSize = {
        type = "range", order = 22, name = L["OPT_BORDER_SIZE"], min = 0, max = 4, step = 1,
        arg = { "borderSize" }, get = get, set = set,
      },
      scale = {
        type = "range", order = 23, name = L["OPT_SCALE"], min = 0.5, max = 3, step = 0.05, isPercent = true,
        arg = { "scale" }, get = get,
        set = function(info, value) set(info, ns.RoundScale(value)) end,
      },
      alpha = {
        type = "range", order = 24, name = L["OPT_ALPHA"], min = 0.2, max = 1, step = 0.05, isPercent = true,
        arg = { "alpha" }, get = get, set = set,
      },
    },
  }

  -- Profile: "Kopieren von", Zurücksetzen usw. (AceDBOptions-3.0) ------------
  if AceDBOptions then
    o.args.profiles = AceDBOptions:GetOptionsTable(ns.db)
    o.args.profiles.order = 100
  end

  return o
end

---------------------------------------------------------------------------
-- Registrieren und Öffnen
---------------------------------------------------------------------------

function Options:Init()
  if not (AceConfig and AceConfigDialog) then
    ns.Debug:Error("Options", "AceConfig-3.0 missing")
    return
  end
  local ok, err = pcall(function()
    AceConfig:RegisterOptionsTable(ADDON_NAME, buildOptions())
    -- Seit Ace3 r1390 (WoW 12.0) muss die zweite Rückgabe an Settings.OpenToCategory
    -- weitergegeben werden (Ace3 changelog.txt, bei OwnDPS getestet).
    local _, categoryID = AceConfigDialog:AddToBlizOptions(ADDON_NAME, "DotRange")
    self.categoryID = categoryID
  end)
  if not ok then ns.Debug:Error("Options:Init", err) end
end

-- Rückgabe true, wenn das Menü verfügbar ist (auch wenn es im Kampf gesperrt ist)
function Options:Open()
  if not self.categoryID then return false end
  -- C_SettingsUtil.OpenSettingsPanel ist als HasRestrictions markiert: im Kampf nicht aufrufen
  if InCombatLockdown() then
    ns.Print(L["NOT_IN_COMBAT"])
    return true
  end
  local ok, err = pcall(Settings.OpenToCategory, self.categoryID)
  if not ok then
    ns.Debug:Error("OpenToCategory", err)
    return false
  end
  return true
end

-- Offenes Menü aktualisieren, wenn sich etwas außerhalb davon ändert
function Options:Notify()
  local registry = LibStub("AceConfigRegistry-3.0", true)
  if registry then pcall(registry.NotifyChange, registry, ADDON_NAME) end
end

local function editModeShown()
  if not EditModeManagerFrame then return "missing" end
  local ok, shown = pcall(EditModeManagerFrame.IsShown, EditModeManagerFrame)
  return ok and shown or "error"
end

-- Eigenständiges AceConfigDialog-Fenster, für den Button im Bearbeitungsmodus.
-- Settings.OpenToCategory lief dort bei OwnDPS ohne Fehler, zeigte aber kein Fenster.
-- Das AceGUI-Fenster liegt in der Ebene FULLSCREEN_DIALOG, der Bearbeitungsmodus in DIALOG.
function Options:OpenStandalone()
  if not AceConfigDialog then return false end
  local ok, err = pcall(AceConfigDialog.Open, AceConfigDialog, ADDON_NAME)
  local openFrame = AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames[ADDON_NAME]
  local okShown, frameShown = false, nil
  if openFrame and openFrame.frame then
    okShown, frameShown = pcall(openFrame.frame.IsShown, openFrame.frame)
  end
  ns.Debug:Add("optionsStandalone", {
    ok = ok,
    err = err,
    editModeShown = editModeShown(),
    frameShown = okShown and frameShown or false,
  })
  if not ok then ns.Debug:Error("AceConfigDialog:Open", err) end
  return ok
end
