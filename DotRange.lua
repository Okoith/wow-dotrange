-- DotRange.lua v2.0
-- v1.8: Sichtbarkeit-Feature entfernt, kompletter Neuaufbau als Stable Version
-- v1.9: Dämonenjäger von Disrupt auf Chaos Strike (162794) geändert
-- v2.0: CheckInteractDistance entfernt (protected seit 10.2), ersetzt durch
--       C_Spell.IsSpellInRange mit zwei klassenspezifischen Spells pro Klasse
--       Alle Einstellungen per Charakter gespeichert (SavedVariablesPerCharacter)
--       Blizzard Addon-Panel neu implementiert

-- ============================================================
-- VERSION
-- ============================================================
local ADDON_VERSION = "2.0"

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
    boxSize    = 24,
    borderSize = 1,
    alpha      = 1.0,
    locked     = false,
    posPoint   = "CENTER",
    posX       = 0,
    posY       = -150,
}

local cfg = {}

local function ApplyDefaults()
    DotRangeCharDB = DotRangeCharDB or {}
    local db = DotRangeCharDB

    db.colors = db.colors or {}
    for key, def in pairs(DEFAULTS.colors) do
        db.colors[key] = db.colors[key] or { r=def.r, g=def.g, b=def.b }
    end

    if db.boxSize    == nil then db.boxSize    = DEFAULTS.boxSize    end
    if db.borderSize == nil then db.borderSize = DEFAULTS.borderSize end
    if db.alpha      == nil then db.alpha      = DEFAULTS.alpha      end
    if db.locked     == nil then db.locked     = DEFAULTS.locked     end
    if db.posPoint   == nil then db.posPoint   = DEFAULTS.posPoint   end
    if db.posX       == nil then db.posX       = DEFAULTS.posX       end
    if db.posY       == nil then db.posY       = DEFAULTS.posY       end

    cfg = db
end

-- ============================================================
-- NAHKAMPF-SPELLS JE KLASSE
-- meleeSpell  = Nahkampf (~5 yd) → alle 3 Boxen
-- nearSpell   = Mittlere Distanz (~30 yd) → 2 Boxen
-- Ohne nearSpell → nur Nahkampf-Check möglich
-- ============================================================
local CLASS_SPELLS = {
    ["WARRIOR"]     = { melee=6552,   near=100    }, -- Pummel / Charge (20 yd)
    ["ROGUE"]       = { melee=1766,   near=36554  }, -- Kick / Shadowstep (25 yd)
    ["PALADIN"]     = { melee=96231,  near=62124  }, -- Rebuke / Hammer of Wrath (30 yd)
    ["MONK"]        = { melee=116705, near=115546 }, -- Spear Hand Strike / Flying Serpent Kick (50 yd)
    ["DEATHKNIGHT"] = { melee=49998,  near=49576  }, -- Death Strike / Death Grip (30 yd)
    ["DEMONHUNTER"] = { melee=162794, near=185123 }, -- Chaos Strike / Throw Glaive (30 yd)
    ["HUNTER"]      = { melee=187707, near=186270 }, -- Muzzle / Harpoon (30 yd, Survival)
}

local playerClass   = select(2, UnitClass("player"))
local classSpells   = CLASS_SPELLS[playerClass] or {}
local MELEE_SPELL_ID = classSpells.melee
local NEAR_SPELL_ID  = classSpells.near

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
    local point, _, _, x, y = self:GetPoint()
    cfg.posPoint = point
    cfg.posX     = math.floor(x)
    cfg.posY     = math.floor(y)
end)

local function LoadPosition()
    anchor:ClearAllPoints()
    anchor:SetPoint(cfg.posPoint or "CENTER", UIParent, cfg.posPoint or "CENTER", cfg.posX or 0, cfg.posY or -150)
end

local function ApplyLock()
    anchor:SetMovable(not cfg.locked)
end

-- ============================================================
-- BOXEN AUFBAUEN
-- ============================================================
local function RebuildBoxes()
    local size  = cfg.boxSize    or DEFAULTS.boxSize
    local bs    = cfg.borderSize or DEFAULTS.borderSize
    local gap   = 4
    local bc    = cfg.colors.border

    anchor:SetSize((size * BOX_COUNT) + (gap * (BOX_COUNT - 1)), size)

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
        local off = cfg.colors.off
        box.bg:SetColorTexture(off.r, off.g, off.b, cfg.alpha or 1.0)
    end
end

local function SetBoxes(activeCount, colorKey)
    local c   = colorKey and cfg.colors[colorKey] or cfg.colors.off
    local alp = cfg.alpha or 1.0
    local off = cfg.colors.off
    local bc  = cfg.colors.border
    local bs  = cfg.borderSize or DEFAULTS.borderSize

    for i = 1, BOX_COUNT do
        boxes[i].border:SetColorTexture(bc.r, bc.g, bc.b, 1.0)
        boxes[i].bg:ClearAllPoints()
        boxes[i].bg:SetPoint("TOPLEFT",     boxes[i], "TOPLEFT",      bs, -bs)
        boxes[i].bg:SetPoint("BOTTOMRIGHT", boxes[i], "BOTTOMRIGHT", -bs,  bs)
        if i <= activeCount then
            boxes[i].bg:SetColorTexture(c.r, c.g, c.b, alp)
        else
            boxes[i].bg:SetColorTexture(off.r, off.g, off.b, alp)
        end
    end
end

-- ============================================================
-- UPDATE-LOGIK
-- ============================================================
local function UpdateDotRange()
    if not UnitExists("target") or UnitIsUnit("target", "player") then
        SetBoxes(0, nil); return
    end

    local inMelee = MELEE_SPELL_ID and C_Spell.IsSpellInRange(MELEE_SPELL_ID, "target")
    local inNear  = NEAR_SPELL_ID  and C_Spell.IsSpellInRange(NEAR_SPELL_ID,  "target")

    if inMelee == true then
        -- Nahkampf: alle 3 Boxen
        SetBoxes(3, "melee")
    elseif inNear == true then
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
-- CONFIG PANEL
-- ============================================================
local panel = nil

local function CreateColorSwatch(parent, label, colorKey, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    lbl:SetText(label)

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(20, 20)
    btn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)

    local tex = btn:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    local c = cfg.colors[colorKey]
    tex:SetColorTexture(c.r, c.g, c.b, 1.0)
    btn.tex = tex

    btn:SetScript("OnClick", function()
        local c = cfg.colors[colorKey]
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                cfg.colors[colorKey] = { r=r, g=g, b=b }
                tex:SetColorTexture(r, g, b, 1.0)
                RebuildBoxes()
            end,
            cancelFunc = function(prev)
                cfg.colors[colorKey] = { r=prev.r, g=prev.g, b=prev.b }
                tex:SetColorTexture(prev.r, prev.g, prev.b, 1.0)
                RebuildBoxes()
            end,
            r = c.r, g = c.g, b = c.b, opacity = 0,
        })
    end)
end

local function CreateSlider(parent, label, minVal, maxVal, step, getFunc, setFunc, yOffset)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    s:SetWidth(220)
    s:SetMinMaxValues(minVal, maxVal)
    s:SetValueStep(step)
    s:SetValue(getFunc())
    s:SetObeyStepOnDrag(true)
    s.Text:SetText(label)
    s.Low:SetText(minVal)
    s.High:SetText(maxVal)

    local valText = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOP", s, "BOTTOM", 0, -2)
    valText:SetText(string.format("%.2f", getFunc()))

    s:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        valText:SetText(string.format("%.2f", val))
        setFunc(val)
        RebuildBoxes()
    end)
end

local function CreateCheckbox(parent, label, getFunc, setFunc, yOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    cb:SetSize(24, 24)
    cb:SetChecked(getFunc())
    cb.text:SetText(label)
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
    panel:SetSize(380, 560)
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
    CreateCheckbox(panel, "Position fixieren (nicht verschiebbar)",
        function() return cfg.locked end,
        function(v) cfg.locked = v; ApplyLock() end, y)

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
        anchor:Show()
        panel:Hide()
        panel = nil
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
    local f = CreateFrame("Frame", "DotRangeSettingsFrame", UIParent)
    f:SetSize(600, 400)

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
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event ~= "ADDON_LOADED" or arg1 ~= "DotRange" then return end

    ApplyDefaults()
    LoadPosition()
    RebuildBoxes()
    ApplyLock()
    anchor:Show()

    if not MELEE_SPELL_ID then
        print("|cFFFF2020DotRange:|r Kein Nahkampf-Spell für Klasse '" .. (playerClass or "?") .. "' gefunden.")
    end

    if Settings and Settings.RegisterCanvasLayoutCategory then
        RegisterBlizzardPanel()
    end

    self:UnregisterEvent("ADDON_LOADED")
end)

-- ============================================================
-- SLASH-BEFEHLE
-- ============================================================
SLASH_DOTRANGE1 = "/dotrange"
SlashCmdList["DOTRANGE"] = function(msg)
    msg = strtrim(msg or "")
    if msg == "config" then
        OpenConfig()
    elseif msg == "debug" then
        if UnitExists("target") then
            local melee = MELEE_SPELL_ID and C_Spell.IsSpellInRange(MELEE_SPELL_ID, "target")
            local near  = NEAR_SPELL_ID  and C_Spell.IsSpellInRange(NEAR_SPELL_ID,  "target")
            local vis   = UnitIsVisible("target")
            print(string.format("|cFF00FF00DotRange v%s Debug:|r Klasse=%s Melee(ID=%s)=%s Near(ID=%s)=%s Visible=%s",
                ADDON_VERSION, playerClass,
                tostring(MELEE_SPELL_ID), tostring(melee),
                tostring(NEAR_SPELL_ID),  tostring(near),
                tostring(vis)))
        else
            print("|cFF00FF00DotRange v" .. ADDON_VERSION .. " Debug:|r Kein Ziel ausgewählt")
        end
    elseif msg == "" then
        if anchor:IsShown() then anchor:Hide() else anchor:Show() end
    else
        print("|cFF00FF00DotRange v" .. ADDON_VERSION .. " Befehle:|r /dotrange | /dotrange config | /dotrange debug")
    end
end

print("|cFF00FF00DotRange|r v" .. ADDON_VERSION .. " geladen.")
