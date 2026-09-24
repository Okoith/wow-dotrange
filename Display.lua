local ADDON_NAME, ns = ...

-- Anzeige: drei Boxen, Logik unverändert aus 2.1 (SPEC Abschnitt 2).
-- Werte, die geheim sein könnten, werden nie verglichen: Unit-Abfragen laufen über
-- safeCall, das bei Fehler oder Secret Value nil liefert.
--
-- Aufbau wie OwnDPS: Der Hauptframe gehört dem State Driver (Sichtbarkeitsregeln,
-- SPEC 3.5). Die Boxen liegen im inneren Frame "content", der nach den Zielregeln
-- (SPEC 3.6, 3.7) ein- und ausgeblendet wird. Beide Frames sind nicht geschützt,
-- Show/Hide von content ist daher auch im Kampf erlaubt.
--
-- Verschoben wird nur im WoW-Bearbeitungsmodus (EditMode.lua). Dort ist die Anzeige
-- immer sichtbar und zeigt als Muster drei grüne Boxen (SPEC 3.4).

local Display = {}
ns.Display = Display

local issecret = issecretvalue or function() return false end

local BOX_COUNT = 3
local GAP = 4
local UPDATE_INTERVAL = 0.1

local frame, content
local boxes = {}
local lastCount, lastColorKey  -- zuletzt gezeichneter Zustand

-- Ergebnis der letzten Aktualisierung, für das Debug-Log
Display.last = { state = 0 }

-- Ruft eine API geschützt auf. Rückgabe: Wert (nil bei Fehler/Secret), secret, failed
local function safeCall(where, fn, ...)
  local ok, v = pcall(fn, ...)
  if not ok then
    ns.Debug:Error(where, v)
    return nil, false, true
  end
  if issecret(v) then return nil, true, false end
  return v, false, false
end
Display.SafeBool = safeCall

function Display:GetFrame()
  return frame
end

---------------------------------------------------------------------------
-- Boxen
---------------------------------------------------------------------------

local function setBoxes(activeCount, colorKey)
  if not boxes[1] then return end
  if activeCount == lastCount and colorKey == lastColorKey then return end
  lastCount, lastColorKey = activeCount, colorKey

  local colors = ns.db.profile.colors
  local c   = colorKey and colors[colorKey] or colors.off
  local off = colors.off
  for i = 1, BOX_COUNT do
    local col = (i <= activeCount) and c or off
    boxes[i].bg:SetColorTexture(col.r, col.g, col.b, 1.0)
  end
end

local function rebuildBoxes()
  local p    = ns.db.profile
  local size = p.boxSize
  local bs   = p.borderSize
  local bc   = p.colors.border

  frame:SetSize((size * BOX_COUNT) + (GAP * (BOX_COUNT - 1)), size)
  frame:SetScale(p.scale)
  frame:SetAlpha(p.alpha)

  for i = 1, BOX_COUNT do
    if not boxes[i] then
      boxes[i] = CreateFrame("Frame", "DotRangeBox" .. i, content)
    end
    local box = boxes[i]
    box:SetSize(size, size)
    box:ClearAllPoints()
    box:SetPoint("LEFT", content, "LEFT", (i - 1) * (size + GAP), 0)
    box:Show()

    if not box.border then
      box.border = box:CreateTexture(nil, "BACKGROUND")
      box.border:SetAllPoints()
    end
    box.border:SetColorTexture(bc.r, bc.g, bc.b, 1.0)

    if not box.bg then
      box.bg = box:CreateTexture(nil, "ARTWORK")
    end
    box.bg:ClearAllPoints()
    box.bg:SetPoint("TOPLEFT",     box, "TOPLEFT",      bs, -bs)
    box.bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -bs,  bs)
  end

  -- Farben neu zeichnen erzwingen
  local count, key = lastCount or 0, lastColorKey
  lastCount, lastColorKey = nil, nil
  setBoxes(count, key)
end

---------------------------------------------------------------------------
-- Position des aktiven Bearbeitungsmodus-Layouts (EditMode.lua), sonst Profil-Position
---------------------------------------------------------------------------

function Display:ApplyPosition()
  if not frame then return end
  local pos = ns.EditMode:GetPosition()
  frame:ClearAllPoints()
  frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or pos.point or "CENTER", pos.x or 0, pos.y or 0)
end

---------------------------------------------------------------------------
-- Zielregeln (SPEC 3.6, 3.7): Rückgabe des Grundes, content auszublenden, sonst nil.
-- Ist ein Ergebnis unklar (Fehler, Secret Value), wird nicht ausgeblendet.
---------------------------------------------------------------------------

local function hiddenReason(p, exists)
  if not ns.Spells.available then return "noSpells" end
  if p.hideNoTarget and exists ~= true then return "noTarget" end
  if p.hostileOnly and exists == true then
    local canAttack, secret, failed = safeCall("UnitCanAttack", UnitCanAttack, "player", "target")
    if not secret and not failed and canAttack ~= true then return "notHostile" end
  end
  return nil
end

---------------------------------------------------------------------------
-- Aktualisierung
---------------------------------------------------------------------------

-- Berechnet den Zustand (0-3) und zeichnet ihn. Rückgabe: Zustand
function Display:Update()
  if not frame then return 0 end
  local p = ns.db.profile
  local last = self.last

  -- Bearbeitungsmodus: Muster mit drei grünen Boxen, unabhängig von Ziel und Regeln
  if self.editMode then
    last.hidden = false
    content:Show()
    setBoxes(3, "melee")
    last.state = 3
    return 3
  end

  local exists = safeCall("UnitExists", UnitExists, "target")

  local reason = hiddenReason(p, exists)
  last.hidden = reason or false
  if reason then
    content:Hide()
    last.state = 0
    return 0
  end
  content:Show()

  local isPlayer = exists and safeCall("UnitIsUnit", UnitIsUnit, "target", "player")
  local Spells = ns.Spells
  local state, colorKey

  if exists ~= true or isPlayer == true then
    state, colorKey = 0, nil
  elseif Spells:AnyInRange(Spells.melee, "target") then
    -- Nahkampf: alle 3 Boxen
    state, colorKey = 3, "melee"
  elseif Spells:AnyInRange(Spells.near, "target") then
    -- Mittlere Distanz: 2 Boxen
    state, colorKey = 2, "near"
  elseif safeCall("UnitIsVisible", UnitIsVisible, "target") == true then
    -- Sichtbar aber weit weg: 1 Box
    state, colorKey = 1, "medium"
  else
    -- Nicht sichtbar / kein Ziel
    state, colorKey = 0, nil
  end

  setBoxes(state, colorKey)
  last.state = state
  return state
end

---------------------------------------------------------------------------
-- Sichtbarkeit (SPEC 3.5) über den State Driver "visibility", wie OwnDPS (getestet).
-- Haustierkampf immer aus, Fahrzeug optional. Für Instanzen gibt es keine
-- Macro-Bedingung, daher wird IsInInstance() bei Zonenwechseln ausgewertet und der
-- Treiber neu gesetzt. RegisterStateDriver wird nie im Kampf aufgerufen, sondern
-- bis Kampfende zurückgestellt.
---------------------------------------------------------------------------

local function inInstance()
  local ok, isIn = pcall(IsInInstance)
  return ok and isIn == true
end

function Display:BuildVisibilityMacro()
  if self.editMode then return "show" end   -- im Bearbeitungsmodus immer sichtbar
  local p = ns.db.profile
  local parts = { "[petbattle] hide" }
  if p.hideInVehicle then parts[#parts + 1] = "[vehicleui] hide" end
  local mode = p.visibility
  if mode == "combat" then
    parts[#parts + 1] = "[combat] show"
    parts[#parts + 1] = "hide"
  elseif mode == "group" then
    parts[#parts + 1] = "[group] show"
    parts[#parts + 1] = "hide"
  elseif mode == "instance" then
    parts[#parts + 1] = inInstance() and "show" or "hide"
  else
    parts[#parts + 1] = "show"
  end
  return table.concat(parts, "; ")
end

-- Rückgabe true, wenn der Treiber aktuell ist; false, wenn bis Kampfende verschoben
function Display:UpdateVisibility()
  if not frame then return false end
  local macro = self:BuildVisibilityMacro()
  if macro == self.visibilityMacro then
    self.visibilityPending = false
    return true
  end
  if InCombatLockdown() then
    self.visibilityPending = true
    return false
  end
  local ok, err = pcall(RegisterStateDriver, frame, "visibility", macro)
  if ok then
    self.visibilityMacro = macro
    self.visibilityPending = false
    ns.Debug:Add("visibility", { macro = macro })
  else
    ns.Debug:Error("RegisterStateDriver", err)
  end
  return ok
end

function Display:SetEditMode(on)
  self.editMode = on and true or false
  self:UpdateVisibility()
  if ns.SafeUpdate then ns.SafeUpdate() end   -- Muster sofort zeigen bzw. entfernen
end

-- Einstellungen sofort anwenden
function Display:ApplySettings()
  if not frame then return end
  rebuildBoxes()
  self:ApplyPosition()
end

---------------------------------------------------------------------------
-- Erzeugen (bei PLAYER_LOGIN)
---------------------------------------------------------------------------

function Display:Create()
  if frame then return end
  -- Keine Maus: Klicks gehen immer durch die Anzeige hindurch. Verschoben wird im
  -- Bearbeitungsmodus über den Auswahl-Frame von LibEditMode.
  frame = CreateFrame("Frame", "DotRangeAnchor", UIParent)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(false)

  content = CreateFrame("Frame", nil, frame)
  content:SetAllPoints(frame)
  content:EnableMouse(false)

  local elapsed = 0
  frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0
    ns.SafeUpdate()
  end)

  self:ApplySettings()
  self:UpdateVisibility()
end
