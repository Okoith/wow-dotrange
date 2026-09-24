local ADDON_NAME, ns = ...
local L = ns.L

-- Einbindung in den WoW-Bearbeitungsmodus über LibEditMode (SPEC 3.4), übernommen aus
-- OwnDPS (dort im Spiel getestet). API laut Wiki von p3lim-wow/LibEditMode: AddFrame,
-- AddFrameSettings, AddFrameSettingsButtons, RegisterCallback, GetActiveLayoutName.
--
-- Positionen liegen pro Layout im Profil: profile.layouts[layoutName] = { point, relPoint, x, y }.
-- profile.position ist die bisherige Position (bis 3.0.0-alpha.2, inkl. Migration aus 2.x)
-- und dient als Startwert für Layouts ohne eigenen Eintrag.

local EditMode = {}
ns.EditMode = EditMode

local LEM = LibStub("LibEditMode", true)

local DEFAULT_POSITION = { point = "CENTER", x = 0, y = -150 }

local function copyPosition(pos)
  return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
end

-- Skalierung auf 0,01 runden (Slider liefern Werte wie 1.7000000476837)
function ns.RoundScale(value)
  return math.floor(value * 100 + 0.5) / 100
end

function EditMode:GetLayoutName()
  if not LEM then return nil end
  local ok, name = pcall(LEM.GetActiveLayoutName, LEM)
  return ok and name or nil
end

-- Position für das aktive Layout; ohne Layout-Eintrag die Profil-Position
function EditMode:GetPosition()
  local p = ns.db.profile
  local name = self:GetLayoutName()
  if name and p.layouts[name] then return p.layouts[name] end
  return p.position
end

-- Setzt die Position im aktiven Layout auf den Standard (Menü).
-- Wirkt auch bei "Sperren", weil es eine ausdrückliche Aktion ist.
function EditMode:ResetPosition()
  local p = ns.db.profile
  local name = self:GetLayoutName()
  if name then
    p.layouts[name] = copyPosition(DEFAULT_POSITION)
  else
    p.position = copyPosition(DEFAULT_POSITION)
  end
  ns.Debug:Add("positionReset", { layout = name or "-" })
  ns.Display:ApplyPosition()
end

---------------------------------------------------------------------------
-- Sperren: im Bearbeitungsmodus nicht verschiebbar
---------------------------------------------------------------------------

-- LibEditMode hat dafür keine API. Das Ziehen startet im OnDragStart-Skript des
-- Auswahl-Frames (lib.frameSelections[frame], nicht dokumentiert, bei OwnDPS getestet).
-- Bei Sperre wird dieses Skript entfernt, sonst wiederhergestellt. Pfeiltasten und
-- "Position zurücksetzen" im Dialog fängt onPositionChanged ab.
function EditMode:ApplyLock()
  local frame = ns.Display:GetFrame()
  local selection = LEM and frame and LEM.frameSelections and LEM.frameSelections[frame]
  if not selection then return end
  local ok, err = pcall(function()
    if not self.originalDragStart then
      self.originalDragStart = selection:GetScript("OnDragStart")
    end
    if ns.db.profile.locked then
      selection:SetScript("OnDragStart", nil)
    else
      selection:SetScript("OnDragStart", self.originalDragStart)
    end
  end)
  if not ok then ns.Debug:Error("EditMode:ApplyLock", err) end
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------

-- LibEditMode ruft das nach Ziehen, Pfeiltasten und "Position zurücksetzen" auf.
local function onPositionChanged(frame, layoutName, point, x, y)
  local p = ns.db.profile
  if p.locked then
    -- gesperrt: nichts speichern, gespeicherte Position wiederherstellen
    ns.Display:ApplyPosition()
    ns.Debug:Add("positionLocked", { layout = layoutName })
    return
  end
  if not layoutName then return end
  p.layouts[layoutName] = { point = point, relPoint = point, x = x, y = y }
  ns.Debug:Add("positionChanged", { layout = layoutName, point = point, x = x, y = y })
end

local function onLayout(layoutName)
  local p = ns.db.profile
  if layoutName and not p.layouts[layoutName] then
    -- Migration: bisherige Position (Profil) für dieses Layout übernehmen
    p.layouts[layoutName] = copyPosition(p.position)
    ns.Debug:Add("positionMigrated", { layout = layoutName, point = p.position.point, x = p.position.x, y = p.position.y })
  end
  ns.Display:ApplyPosition()
end

local function onCreate(layoutName, _, sourceLayoutName)
  local p = ns.db.profile
  local source = sourceLayoutName and p.layouts[sourceLayoutName]
  p.layouts[layoutName] = copyPosition(source or p.position)
end

local function onRename(oldName, newName)
  local p = ns.db.profile
  if p.layouts[oldName] then
    p.layouts[newName] = p.layouts[oldName]
    p.layouts[oldName] = nil
  end
end

local function onDelete(layoutName)
  ns.db.profile.layouts[layoutName] = nil
end

---------------------------------------------------------------------------
-- Einrichten (nach Display:Create, also bei PLAYER_LOGIN)
---------------------------------------------------------------------------

function EditMode:Init()
  if not LEM then
    ns.Debug:Error("EditMode", "LibEditMode missing")
    return
  end
  local frame = ns.Display:GetFrame()
  local ok, err = pcall(function()
    LEM:AddFrame(frame, onPositionChanged, DEFAULT_POSITION, "DotRange")

    LEM:AddFrameSettings(frame, {
      {
        kind = LEM.SettingType.Slider,
        name = L["OPT_SCALE"],
        default = 1,
        get = function() return ns.db.profile.scale end,
        set = function(_, value)
          ns.db.profile.scale = ns.RoundScale(value)
          ns:Refresh()
          ns.Options:Notify()
        end,
        minValue = 0.5,
        maxValue = 3,
        valueStep = 0.05,
        -- Ohne formatter zeigt der Slider den Float-Rohwert (OwnDPS-Test)
        formatter = function(value) return string.format("%.2f", value) end,
      },
    })

    -- Settings.OpenToCategory zeigt im Bearbeitungsmodus kein Fenster (OwnDPS-Test),
    -- deshalb das eigenständige AceConfigDialog-Fenster.
    LEM:AddFrameSettingsButtons(frame, {
      {
        text = L["EDITMODE_MORE_SETTINGS"],
        click = function() ns.Options:OpenStandalone() end,
      },
    })

    LEM:RegisterCallback("enter", function()
      ns.Debug:Add("editMode", { on = true, layout = EditMode:GetLayoutName() })
      ns.Display:SetEditMode(true)
      EditMode:ApplyLock()
    end)
    LEM:RegisterCallback("exit", function()
      ns.Debug:Add("editMode", { on = false })
      ns.Display:SetEditMode(false)
    end)
    LEM:RegisterCallback("layout", onLayout)
    LEM:RegisterCallback("create", onCreate)
    LEM:RegisterCallback("rename", onRename)
    LEM:RegisterCallback("delete", onDelete)
  end)
  if not ok then ns.Debug:Error("EditMode:Init", err) end
  self:ApplyLock()
end

-- Nach Profilwechsel oder Änderung der Sperre/Skalierung
function EditMode:Refresh()
  self:ApplyLock()
  if LEM and ns.Display:GetFrame() then
    pcall(LEM.RefreshFrameSettings, LEM, ns.Display:GetFrame())
  end
end
