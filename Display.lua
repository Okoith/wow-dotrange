local ADDON_NAME, ns = ...

-- Anzeige: drei Boxen, Logik unverändert aus 2.1 (SPEC Abschnitt 2).
-- Werte, die geheim sein könnten, werden nie verglichen: Unit-Abfragen laufen über
-- safeBool, das bei Fehler oder Secret Value nil liefert.

local Display = {}
ns.Display = Display

local issecret = issecretvalue or function() return false end

local BOX_COUNT = 3
local GAP = 4
local UPDATE_INTERVAL = 0.1

local anchor
local boxes = {}
local lastCount, lastColorKey  -- zuletzt gezeichneter Zustand

-- Ergebnis der letzten Aktualisierung, für Debug-Log
Display.last = { state = 0 }

-- Ruft eine Unit-API geschützt auf. Rückgabe: Wert (nil bei Fehler/Secret), secret-Flag
local function safeBool(where, fn, ...)
  local ok, v = pcall(fn, ...)
  if not ok then
    ns.Debug:Error(where, v)
    return nil, false
  end
  if issecret(v) then return nil, true end
  return v, false
end
Display.SafeBool = safeBool

function Display:GetFrame()
  return anchor
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

  anchor:SetSize((size * BOX_COUNT) + (GAP * (BOX_COUNT - 1)), size)
  anchor:SetAlpha(p.alpha)

  for i = 1, BOX_COUNT do
    if not boxes[i] then
      boxes[i] = CreateFrame("Frame", "DotRangeBox" .. i, anchor)
    end
    local box = boxes[i]
    box:SetSize(size, size)
    box:ClearAllPoints()
    box:SetPoint("LEFT", anchor, "LEFT", (i - 1) * (size + GAP), 0)
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
-- Position und Sperre (Verschieben per Maus wie in 2.1; LibEditMode folgt in Meilenstein 3)
---------------------------------------------------------------------------

function Display:ApplyPosition()
  if not anchor then return end
  local pos = ns.db.profile.position
  anchor:ClearAllPoints()
  anchor:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or pos.point or "CENTER", pos.x or 0, pos.y or 0)
end

function Display:ApplyLock()
  if not anchor then return end
  local locked = ns.db.profile.locked
  anchor:SetMovable(not locked)
  -- Fixiert: Klicks gehen durch die Anzeige hindurch in die Spielwelt
  anchor:EnableMouse(not locked)
end

---------------------------------------------------------------------------
-- Aktualisierung
---------------------------------------------------------------------------

-- Berechnet den Zustand (0-3) und zeichnet ihn. Rückgabe: Zustand
function Display:Update()
  local exists = safeBool("UnitExists", UnitExists, "target")
  local isPlayer = exists and safeBool("UnitIsUnit", UnitIsUnit, "target", "player")
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
  elseif safeBool("UnitIsVisible", UnitIsVisible, "target") == true then
    -- Sichtbar aber weit weg: 1 Box
    state, colorKey = 1, "medium"
  else
    -- Nicht sichtbar / kein Ziel
    state, colorKey = 0, nil
  end

  setBoxes(state, colorKey)
  self.last.state = state
  return state
end

-- Ohne Ziel ausblenden (2.1). Der Anker ist kein geschützter Frame.
function Display:UpdateVisibility()
  if not anchor then return end
  local show = true
  if ns.db.profile.hideNoTarget then
    show = safeBool("UnitExists", UnitExists, "target") == true
  end
  if show then
    anchor:Show()
    ns.SafeUpdate()
  else
    anchor:Hide()
  end
end

-- Einstellungen sofort anwenden
function Display:ApplySettings()
  if not anchor then return end
  rebuildBoxes()
  self:ApplyLock()
  self:ApplyPosition()
end

---------------------------------------------------------------------------
-- Erzeugen (bei PLAYER_LOGIN)
---------------------------------------------------------------------------

function Display:Create()
  if anchor then return end
  anchor = CreateFrame("Frame", "DotRangeAnchor", UIParent)
  anchor:SetMovable(true)
  anchor:EnableMouse(true)
  anchor:RegisterForDrag("LeftButton")

  anchor:SetScript("OnDragStart", function(self)
    if not ns.db.profile.locked then self:StartMoving() end
  end)

  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Position speichert das Addon selbst, nicht zusätzlich der Layout-Cache
    self:SetUserPlaced(false)
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.profile.position = {
      point = point,
      relPoint = relPoint,
      x = math.floor(x + 0.5),
      y = math.floor(y + 0.5),
    }
    ns.Debug:Add("positionChanged", ns.db.profile.position)
  end)

  local elapsed = 0
  anchor:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0
    ns.SafeUpdate()
  end)

  self:ApplySettings()
  self:UpdateVisibility()
end
