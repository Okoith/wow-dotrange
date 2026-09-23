-- DotRange.lua
-- v1.8: Sichtbarkeit-Feature entfernt, kompletter Neuaufbau als Stable Version
-- v1.9: Dämonenjäger von Disrupt auf Chaos Strike (162794) geändert
-- v2.0: CheckInteractDistance entfernt (protected seit 10.2), ersetzt durch
--       C_Spell.IsSpellInRange mit zwei klassenspezifischen Spells pro Klasse
--       Alle Einstellungen per Charakter gespeichert (SavedVariablesPerCharacter)
--       Blizzard Addon-Panel neu implementiert
-- v2.1: Mehrere Kandidaten-Spells pro Klasse/Spezialisierung (Jäger-ID korrigiert,
--       Krieger-Lücke 5-8 yd geschlossen, Druide + Schamane ergänzt)
--       Fixierte Anzeige lässt Mausklicks durch, Position nicht mehr doppelt gespeichert
--       Boxen werden nur noch bei Zustandsänderung neu eingefärbt
--       Option "Ohne Ziel ausblenden", Reset aktualisiert das offene Fenster
--       Schutz gegen Secret Values (Midnight 12.0)

local addonName = ...

-- ============================================================
-- VERSION
-- ============================================================
local ADDON_VERSION = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

-- ============================================================
-- STANDARD-EINSTELLUNGEN
-- ============================================================
local DEFAULTS = {
    colors = {
        melee  = { r=0.0,  g=0.87, b=0.0  },  -- Grün  (Nahkampf, alle 3)
        near   = { r=1.0,  g=0.85, b=0.0  },  -- Gelb  (knapp außerhalb, 2)
        medium = { r=1.0,  g=1.0,  b=1.0  },  -- Weiß  (mittlere Distanz, 1)
        off    = { r=0.15, g=0.15, b=0.15 },  -- Dunkel (inaktiv)
        border = { r=0.0,  g=0.0,  b=0.0  },  -- Rahmen
    },
    boxSize      = 24,
    borderSize   = 1,
    alpha        = 1.0,
    locked       = false,
    hideNoTarget = false,
    posPoint     = "CENTER",
    posRelPoint  = "CENTER",
    posX         = 0,
    posY         = -150,
}

local cfg = {}

local function ApplyDefaults()
    DotRangeCharDB = DotRangeCharDB or {}
    local db = DotRangeCharDB

    db.colors = db.colors or {}
    for key, def in pairs(DEFAULTS.colors) do
        db.colors[key] = db.colors[key] or { r=def.r, g=def.g, b=def.b }
    end

    -- Ältere Versionen haben nur posPoint gespeichert (Punkt = Relativpunkt)
    if db.posRelPoint == nil then db.posRelPoint = db.posPoint end
    for key, def in pairs(DEFAULTS) do
        if key ~= "colors" and db[key] == nil then db[key] = def end
    end

    cfg = db
end

-- ============================================================
-- SPELLS JE KLASSE
-- melee = Nahkampf (~5 yd) → alle 3 Boxen
-- near  = Mittlere Distanz (~13-30 yd) → 2 Boxen
-- Pro Stufe mehrere Kandidaten: Es reicht, wenn EINER davon in Reichweite
-- ist. Unbekannte Spells (andere Spezialisierung/Talent/Form) liefern laut
-- C_Spell.IsSpellInRange nil und werden dadurch automatisch ignoriert.
-- ============================================================
local CLASS_SPELLS = {
    ["WARRIOR"] = {
        melee = { 6552 },               -- Pummel
        near  = { 355, 100 },           -- Taunt (30 yd), Charge (8-25 yd)
    },
    ["ROGUE"] = {
        melee = { 1766 },               -- Kick
        near  = { 36554, 185763 },      -- Shadowstep (25 yd), Pistol Shot (20 yd, Outlaw)
    },
    ["PALADIN"] = {
        melee = { 96231, 35395 },       -- Rebuke, Crusader Strike
        near  = { 62124 },              -- Hand of Reckoning (30 yd)
    },
    ["MONK"] = {
        melee = { 116705 },             -- Spear Hand Strike
        near  = { 115546 },             -- Provoke (30 yd)
    },
    ["DEATHKNIGHT"] = {
        melee = { 49998 },              -- Death Strike
        near  = { 49576 },              -- Death Grip (30 yd)
    },
    ["DEMONHUNTER"] = {
        melee = { 162794, 203782, 183752 }, -- Chaos Strike (Havoc), Shear, Disrupt
        near  = { 185123, 185245 },         -- Throw Glaive (30 yd), Torment (30 yd)
    },
    ["HUNTER"] = {
        melee = { 187707, 186270 },     -- Muzzle, Raptor Strike (Survival)
        near  = { 190925 },             -- Harpoon (8-30 yd, Survival)
    },
    ["DRUID"] = {
        melee = { 5221, 33917 },        -- Shred (Katze), Mangle (Bär)
        near  = { 6795, 106839 },       -- Growl (30 yd, Bär), Skull Bash (13 yd)
    },
    ["SHAMAN"] = {
        melee = { 17364, 60103 },       -- Stormstrike, Lava Lash (Enhancement)
        near  = { 57994 },              -- Wind Shear (30 yd)
    },
}

local playerClass = select(2, UnitClass("player"))
local classSpells = CLASS_SPELLS[playerClass] or {}
local MELEE_SPELLS = classSpells.melee or {}
local NEAR_SPELLS  = classSpells.near  or {}

-- Liefert true/false/nil wie C_Spell.IsSpellInRange. Ein Secret Value
-- (Midnight 12.0) darf nicht verglichen werden und zählt deshalb als nil.
local function CheckRange(spellID, unit)
    local inRange = C_Spell.IsSpellInRange(spellID, unit)
    if issecretvalue and issecretvalue(inRange) then return nil, true end
    return inRange, false
end

local function AnyInRange(spellList, unit)
    for _, spellID in ipairs(spellList) do
        if CheckRange(spellID, unit) == true then return true end
    end
    return false
end

local function IsKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID)
    end
    return nil
end

-- ============================================================
-- ANCHOR FRAME
-- ============================================================
local BOX_COUNT = 3
local boxes     = {}

local anchor = CreateFrame("Frame", "DotRangeAnchor", UIParent)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")

anchor:SetScript("OnDragStart", function(self)
    if not cfg.locked then self:StartMoving() end
end)

anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Position speichert das Addon selbst, nicht zusätzlich der Layout-Cache
    self:SetUserPlaced(false)
    local point, _, relPoint, x, y = self:GetPoint()
    cfg.posPoint    = point
    cfg.posRelPoint = relPoint
    cfg.posX        = math.floor(x + 0.5)
    cfg.posY        = math.floor(y + 0.5)
end)

local function LoadPosition()
    anchor:ClearAllPoints()
    anchor:SetPoint(cfg.posPoint, UIParent, cfg.posRelPoint, cfg.posX, cfg.posY)
end

local function ApplyLock()
    anchor:SetMovable(not cfg.locked)
    -- Fixiert: Klicks gehen durch die Anzeige hindurch in die Spielwelt
    anchor:EnableMouse(not cfg.locked)
end

-- ============================================================
-- BOXEN AUFBAUEN
-- ============================================================
local lastCount, lastColorKey  -- zuletzt gezeichneter Zustand

local function SetBoxes(activeCount, colorKey)
    if not boxes[1] then return end
    if activeCount == lastCount and colorKey == lastColorKey then return end
    lastCount, lastColorKey = activeCount, colorKey

    local c   = colorKey and cfg.colors[colorKey] or cfg.colors.off
    local off = cfg.colors.off
    for i = 1, BOX_COUNT do
        local col = (i <= activeCount) and c or off
        boxes[i].bg:SetColorTexture(col.r, col.g, col.b, 1.0)
    end
end

local function RebuildBoxes()
    local size  = cfg.boxSize
    local bs    = cfg.borderSize
    local gap   = 4
    local bc    = cfg.colors.border

    anchor:SetSize((size * BOX_COUNT) + (gap * (BOX_COUNT - 1)), size)
    anchor:SetAlpha(cfg.alpha)

    for i = 1, BOX_COUNT do
        if not boxes[i] then
            boxes[i] = CreateFrame("Frame", "DotRangeBox"..i, anchor)
        end
        local box = boxes[i]
        box:SetSize(size, size)
        box:ClearAllPoints()
        box:SetPoint("LEFT", anchor, "LEFT", (i-1) * (size + gap), 0)
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
        box.bg:SetPoint("TOPLEFT",     box, "TOPLEFT",       bs, -bs)
        box.bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT",  -bs,  bs)
    end

    -- Farben neu zeichnen erzwingen
    local count, key = lastCount or 0, lastColorKey
    lastCount, lastColorKey = nil, nil
    SetBoxes(count, key)
end

-- ============================================================
-- UPDATE-LOGIK
-- ============================================================
local function UpdateDotRange()
    if not UnitExists("target") or UnitIsUnit("target", "player") then
        SetBoxes(0, nil); return
    end

    if AnyInRange(MELEE_SPELLS, "target") then
        -- Nahkampf: alle 3 Boxen
        SetBoxes(3, "melee")
    elseif AnyInRange(NEAR_SPELLS, "target") then
        -- Mittlere Distanz: 2 Boxen
        SetBoxes(2, "near")
    elseif UnitIsVisible("target") then
        -- Sichtbar aber weit weg: 1 Box
        SetBoxes(1, "medium")
    else
        -- Nicht sichtbar / kein Ziel
        SetBoxes(0, nil)
    end
end

local elapsed = 0
anchor:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed < 0.1 then return end
    elapsed = 0
    UpdateDotRange()
end)

-- ============================================================
-- SICHTBARKEIT
-- ============================================================
local userHidden = false  -- per /dotrange ausgeblendet

local function UpdateVisibility()
    local show = not userHidden
    if show and cfg.hideNoTarget and not UnitExists("target") then
        show = false
    end
    if show then
        anchor:Show()
        UpdateDotRange()
    else
        anchor:Hide()
    end
end

-- ============================================================
-- CONFIG PANEL
-- ============================================================
local panel = nil
local panelWidgets = {}  -- Refresh-Funktionen der Bedienelemente

local function RefreshPanel()
    for _, refresh in ipairs(panelWidgets) do refresh() end
end

local function CreateColorSwatch(parent, label, colorKey, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    lbl:SetText(label)

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    btn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)

    local tex = btn:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    btn.tex = tex

    local function Refresh()
        local c = cfg.colors[colorKey]
        tex:SetColorTexture(c.r, c.g, c.b, 1.0)
    end
    Refresh()
    table.insert(panelWidgets, Refresh)

    local function SetColor(r, g, b)
        cfg.colors[colorKey] = { r=r, g=g, b=b }
        tex:SetColorTexture(r, g, b, 1.0)
        RebuildBoxes()
    end

    btn:SetScript("OnClick", function()
        local c = cfg.colors[colorKey]
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function()
                SetColor(ColorPickerFrame:GetColorRGB())
            end,
            cancelFunc = function()
                local r, g, b = ColorPickerFrame:GetPreviousValues()
                SetColor(r, g, b)
            end,
            r = c.r, g = c.g, b = c.b,
        })
    end)
end

local function CreateSlider(parent, label, minVal, maxVal, step, getFunc, setFunc, yOffset)
    local fmt = (step >= 1) and "%d" or "%.2f"

    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    s:SetWidth(220)
    s:SetMinMaxValues(minVal, maxVal)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Text:SetText(label)
    s.Low:SetText(minVal)
    s.High:SetText(maxVal)

    local valText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOP", s, "BOTTOM", 0, -2)

    local function Refresh()
        s:SetValue(getFunc())
        valText:SetText(string.format(fmt, getFunc()))
    end
    Refresh()
    table.insert(panelWidgets, Refresh)

    s:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        valText:SetText(string.format(fmt, val))
        setFunc(val)
        RebuildBoxes()
    end)
end

local function CreateCheckbox(parent, label, getFunc, setFunc, yOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    cb:SetSize(24, 24)
    cb.text:SetText(label)

    local function Refresh() cb:SetChecked(getFunc()) end
    Refresh()
    table.insert(panelWidgets, Refresh)

    cb:SetScript("OnClick", function(self)
        setFunc(self:GetChecked() == true)
    end)
end

local function CreateDivider(parent, yOffset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetSize(348, 1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    line:SetColorTexture(0.4, 0.4, 0.4, 0.6)
end

local function CreateHeader(parent, label, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    lbl:SetText("|cFFFFD700" .. label .. "|r")
end

local function BuildPanel()
    panel = CreateFrame("Frame", "DotRangeConfigPanel", UIParent)
    panel:SetSize(380, 590)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    panel:Hide()

    -- Hintergrund
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.95)
    CreateFrame("Frame", nil, panel, "DialogBorderTemplate"):SetAllPoints()

    -- Titel
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -16)
    title:SetText("DotRange - Einstellungen")

    -- Version
    local ver = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ver:SetPoint("TOP", title, "BOTTOM", 0, -2)
    ver:SetText("|cFF888888Version " .. ADDON_VERSION .. "|r")

    -- Schließen
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    local y = -55

    -- Farben
    CreateHeader(panel, "Farben", y)                            y = y - 25
    CreateColorSwatch(panel, "Nahkampf:",         "melee",  y) y = y - 28
    CreateColorSwatch(panel, "Knapp außerhalb:",  "near",   y) y = y - 28
    CreateColorSwatch(panel, "Mittlere Distanz:", "medium", y) y = y - 28
    CreateColorSwatch(panel, "Inaktiv:",          "off",    y) y = y - 28
    CreateColorSwatch(panel, "Rahmenfarbe:",      "border", y) y = y - 20

    CreateDivider(panel, y)                                     y = y - 16

    -- Größe & Aussehen
    CreateHeader(panel, "Größe & Aussehen", y)                  y = y - 30
    CreateSlider(panel, "Boxgröße", 12, 48, 1,
        function() return cfg.boxSize end,
        function(v) cfg.boxSize = math.floor(v) end, y)        y = y - 65
    CreateSlider(panel, "Rahmenbreite", 0, 4, 1,
        function() return cfg.borderSize end,
        function(v) cfg.borderSize = math.floor(v) end, y)     y = y - 65
    CreateSlider(panel, "Transparenz", 0.2, 1.0, 0.05,
        function() return cfg.alpha end,
        function(v) cfg.alpha = v end, y)                       y = y - 50

    CreateDivider(panel, y)                                     y = y - 16

    -- Verhalten
    CreateHeader(panel, "Verhalten", y)                         y = y - 28
    CreateCheckbox(panel, "Position fixieren (nicht verschiebbar, klickbar durch)",
        function() return cfg.locked end,
        function(v) cfg.locked = v; ApplyLock() end, y)         y = y - 28
    CreateCheckbox(panel, "Ohne Ziel ausblenden",
        function() return cfg.hideNoTarget end,
        function(v) cfg.hideNoTarget = v; UpdateVisibility() end, y)

    -- Zurücksetzen
    local resetBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    resetBtn:SetSize(160, 26)
    resetBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12)
    resetBtn:SetText("Zurücksetzen")
    resetBtn:SetScript("OnClick", function()
        DotRangeCharDB = nil
        ApplyDefaults()
        RebuildBoxes()
        ApplyLock()
        LoadPosition()
        userHidden = false
        UpdateVisibility()
        RefreshPanel()
        print("|cFF00FF00DotRange:|r Einstellungen zurückgesetzt.")
    end)
end

local function OpenConfig()
    if not panel then BuildPanel() end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- ============================================================
-- BLIZZARD ADDON-PANEL
-- ============================================================
local function RegisterBlizzardPanel()
    local f = CreateFrame("Frame", "DotRangeSettingsFrame")
    f:SetSize(600, 400)
    f:Hide()

    -- Version
    local ver = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ver:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    ver:SetText("DotRange")

    local verSmall = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verSmall:SetPoint("TOPLEFT", ver, "BOTTOMLEFT", 0, -4)
    verSmall:SetText("|cFF888888Version " .. ADDON_VERSION .. "|r")

    -- Button
    local btn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    btn:SetSize(160, 30)
    btn:SetPoint("TOPLEFT", verSmall, "BOTTOMLEFT", 0, -16)
    btn:SetText("Einstellungen öffnen")
    btn:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        OpenConfig()
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -8)
    hint:SetText("|cFF888888Alternativ: /dotrange config|r")

    local cat = Settings.RegisterCanvasLayoutCategory(f, "DotRange")
    Settings.RegisterAddOnCategory(cat)
end

-- ============================================================
-- INITIALISIERUNG
-- ============================================================
local loaded = false

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_TARGET_CHANGED" then
        if loaded then UpdateVisibility() end
        return
    end

    if event ~= "ADDON_LOADED" or arg1 ~= addonName then return end

    ApplyDefaults()
    loaded = true
    LoadPosition()
    RebuildBoxes()
    ApplyLock()
    UpdateVisibility()

    if #MELEE_SPELLS == 0 then
        print("|cFFFF2020DotRange:|r Keine Nahkampf-Spells für Klasse '" .. (playerClass or "?") .. "' hinterlegt.")
    end

    if Settings and Settings.RegisterCanvasLayoutCategory then
        RegisterBlizzardPanel()
    end

    self:UnregisterEvent("ADDON_LOADED")
end)

-- ============================================================
-- SLASH-BEFEHLE
-- ============================================================
local function DebugSpellList(label, spellList)
    if #spellList == 0 then return label .. ": -" end
    local parts = {}
    for _, spellID in ipairs(spellList) do
        local inRange, secret = CheckRange(spellID, "target")
        local name = C_Spell.GetSpellName(spellID) or "?"
        table.insert(parts, string.format("%s(%d) bekannt=%s range=%s",
            name, spellID, tostring(IsKnown(spellID)),
            secret and "SECRET" or tostring(inRange)))
    end
    return label .. ": " .. table.concat(parts, ", ")
end

SLASH_DOTRANGE1 = "/dotrange"
SlashCmdList["DOTRANGE"] = function(msg)
    msg = strtrim(msg or "")
    if msg == "config" then
        OpenConfig()
    elseif msg == "debug" then
        local prefix = "|cFF00FF00DotRange v" .. ADDON_VERSION .. " Debug:|r "
        if UnitExists("target") then
            print(prefix .. "Klasse=" .. tostring(playerClass)
                .. " Visible=" .. tostring(UnitIsVisible("target")))
            print("  " .. DebugSpellList("Melee", MELEE_SPELLS))
            print("  " .. DebugSpellList("Near",  NEAR_SPELLS))
        else
            print(prefix .. "Kein Ziel ausgewählt")
        end
    elseif msg == "" then
        userHidden = not userHidden
        UpdateVisibility()
    else
        print("|cFF00FF00DotRange v" .. ADDON_VERSION .. " Befehle:|r /dotrange | /dotrange config | /dotrange debug")
    end
end

print("|cFF00FF00DotRange|r v" .. ADDON_VERSION .. " geladen.")
