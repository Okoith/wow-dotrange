local ADDON_NAME, ns = ...
local L = ns.L

-- Einstellungsfenster aus 2.1, lokalisiert und an das AceDB-Profil angebunden.
-- Übergangslösung: Meilenstein 2 ersetzt es durch das AceConfig-Menü (SPEC 3.3).

local Config = {}
ns.Config = Config

local panel
local widgets = {}  -- Refresh-Funktionen der Bedienelemente

local function profile()
  return ns.db.profile
end

function Config:Refresh()
  for _, refresh in ipairs(widgets) do refresh() end
end

local function createColorSwatch(parent, label, colorKey, yOffset)
  local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
  lbl:SetText(label)

  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(20, 20)
  btn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)

  local tex = btn:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints()
  btn.tex = tex

  local function refresh()
    local c = profile().colors[colorKey]
    tex:SetColorTexture(c.r, c.g, c.b, 1.0)
  end
  refresh()
  table.insert(widgets, refresh)

  local function setColor(r, g, b)
    profile().colors[colorKey] = { r = r, g = g, b = b }
    tex:SetColorTexture(r, g, b, 1.0)
    ns:Refresh()
  end

  btn:SetScript("OnClick", function()
    local c = profile().colors[colorKey]
    ColorPickerFrame:SetupColorPickerAndShow({
      swatchFunc = function()
        setColor(ColorPickerFrame:GetColorRGB())
      end,
      cancelFunc = function()
        local r, g, b = ColorPickerFrame:GetPreviousValues()
        setColor(r, g, b)
      end,
      r = c.r, g = c.g, b = c.b,
    })
  end)
end

local function createSlider(parent, label, minVal, maxVal, step, key, yOffset)
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

  local function refresh()
    s:SetValue(profile()[key])
    valText:SetText(string.format(fmt, profile()[key]))
  end
  refresh()
  table.insert(widgets, refresh)

  s:SetScript("OnValueChanged", function(_, val)
    val = math.floor(val / step + 0.5) * step
    if step >= 1 then val = math.floor(val) end
    valText:SetText(string.format(fmt, val))
    profile()[key] = val
    ns:Refresh()
  end)
end

local function createCheckbox(parent, label, key, yOffset)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
  cb:SetSize(24, 24)
  cb.text:SetText(label)

  local function refresh() cb:SetChecked(profile()[key]) end
  refresh()
  table.insert(widgets, refresh)

  cb:SetScript("OnClick", function(self)
    profile()[key] = self:GetChecked() == true
    ns.Debug:Add("setting", { [key] = profile()[key] })
    ns:Refresh()
  end)
end

local function createDivider(parent, yOffset)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetSize(348, 1)
  line:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
  line:SetColorTexture(0.4, 0.4, 0.4, 0.6)
end

local function createHeader(parent, label, yOffset)
  local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
  lbl:SetText("|cFFFFD700" .. label .. "|r")
end

local function buildPanel()
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
  title:SetText(L["PANEL_TITLE"])

  -- Version
  local ver = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ver:SetPoint("TOP", title, "BOTTOM", 0, -2)
  ver:SetText("|cFF888888" .. L["VERSION"]:format(ns.VERSION) .. "|r")

  -- Schließen
  local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)

  local y = -55

  -- Farben
  createHeader(panel, L["HEADER_COLORS"], y)                    y = y - 25
  createColorSwatch(panel, L["COLOR_MELEE"],  "melee",  y)      y = y - 28
  createColorSwatch(panel, L["COLOR_NEAR"],   "near",   y)      y = y - 28
  createColorSwatch(panel, L["COLOR_MEDIUM"], "medium", y)      y = y - 28
  createColorSwatch(panel, L["COLOR_OFF"],    "off",    y)      y = y - 28
  createColorSwatch(panel, L["COLOR_BORDER"], "border", y)      y = y - 20

  createDivider(panel, y)                                       y = y - 16

  -- Größe & Aussehen
  createHeader(panel, L["HEADER_APPEARANCE"], y)                y = y - 30
  createSlider(panel, L["OPT_BOX_SIZE"],    12,  48,  1,    "boxSize",    y) y = y - 65
  createSlider(panel, L["OPT_BORDER_SIZE"], 0,   4,   1,    "borderSize", y) y = y - 65
  createSlider(panel, L["OPT_ALPHA"],       0.2, 1.0, 0.05, "alpha",      y) y = y - 50

  createDivider(panel, y)                                       y = y - 16

  -- Verhalten
  createHeader(panel, L["HEADER_BEHAVIOR"], y)                  y = y - 28
  createCheckbox(panel, L["OPT_LOCKED"],         "locked",       y) y = y - 28
  createCheckbox(panel, L["OPT_HIDE_NO_TARGET"], "hideNoTarget", y)

  -- Zurücksetzen: setzt das aktive Profil zurück (AceDB), OnProfileReset wendet es an
  local resetBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
  resetBtn:SetSize(160, 26)
  resetBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12)
  resetBtn:SetText(L["RESET"])
  resetBtn:SetScript("OnClick", function()
    ns.db:ResetProfile()
    ns.Print(L["SETTINGS_RESET"])
  end)
end

function Config:Open()
  if not panel then buildPanel() end
  if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- Eintrag unter Einstellungen > AddOns mit Button zum Fenster (wie 2.1)
function Config:Init()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local ok, err = pcall(function()
    local f = CreateFrame("Frame", "DotRangeSettingsFrame")
    f:SetSize(600, 400)
    f:Hide()

    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    name:SetText("DotRange")

    local ver = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ver:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    ver:SetText("|cFF888888" .. L["VERSION"]:format(ns.VERSION) .. "|r")

    local btn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    btn:SetSize(160, 30)
    btn:SetPoint("TOPLEFT", ver, "BOTTOMLEFT", 0, -16)
    btn:SetText(L["OPEN_SETTINGS"])
    btn:SetScript("OnClick", function()
      pcall(HideUIPanel, SettingsPanel)
      Config:Open()
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -8)
    hint:SetText("|cFF888888" .. L["ALT_COMMAND"] .. "|r")

    local cat = Settings.RegisterCanvasLayoutCategory(f, "DotRange")
    Settings.RegisterAddOnCategory(cat)
  end)
  if not ok then ns.Debug:Error("Config:Init", err) end
end
