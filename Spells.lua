local ADDON_NAME, ns = ...

-- Zauberliste pro Klasse (unverändert aus 2.1) und geschützte Reichweitenprüfung.
-- melee = Nahkampf (~5 yd) → alle 3 Boxen
-- near  = Mittlere Distanz (~13-30 yd) → 2 Boxen
-- Pro Stufe mehrere Kandidaten: Es reicht, wenn EINER davon in Reichweite ist.
-- Unbekannte Spells (andere Spezialisierung/Talent/Form) liefern laut
-- C_Spell.IsSpellInRange nil und werden dadurch automatisch ignoriert.

local Spells = {}
ns.Spells = Spells

local issecret = issecretvalue or function() return false end

Spells.CLASS_SPELLS = {
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

-- Eigene Stufen pro Spezialisierung. Schlüssel: Spec-ID, wie GetSpecializationInfo sie
-- zur Laufzeit liefert. Eine Tabelle ersetzt die Klassenliste nur für diese Spec.
--   melee → 3 Boxen, near → 2 Boxen, far → 1 Box
--   visibleFallback = false: ohne far-Treffer bleiben alle Boxen inaktiv
--   (kein Rückfall auf UnitIsVisible)
Spells.DEVOURER_SPEC_ID = 1480   -- Dämonenjäger Verschlinger (warcraft.wiki.gg, SpecializationID)

Spells.SPEC_SPELLS = {
  [Spells.DEVOURER_SPEC_ID] = {
    melee = { 473662 },             -- Consume (25 yd)
    near  = { 183752 },             -- Disrupt (30 yd beim Verschlinger)
    far   = { 1245412 },            -- Voidblade (35 yd)
    visibleFallback = false,
  },
}

Spells.GROUPS = { "melee", "near", "far" }

Spells.melee = {}
Spells.near = {}
Spells.far = {}
Spells.visibleFallback = true
Spells.available = true   -- kennt der Charakter mindestens einen Zauber? (SPEC 3.7)

-- Bei PLAYER_LOGIN, dann ist die Klasse sicher bekannt
function Spells:Init()
  local _, class, classID = UnitClass("player")
  self.class = class
  self.classID = classID
  self:ApplySpec()
end

-- Wählt die Stufen für die aktuelle Spezialisierung: eigene Tabelle, sonst Klassenliste.
-- Rückgabe: true, wenn sich die Spec-ID geändert hat.
function Spells:ApplySpec()
  local specID = self:GetSpec()
  local changed = specID ~= self.specID
  self.specID = specID
  local list = (specID and self.SPEC_SPELLS[specID]) or self.CLASS_SPELLS[self.class] or {}
  self.specTable = (specID and self.SPEC_SPELLS[specID]) ~= nil
  self.melee = list.melee or {}
  self.near = list.near or {}
  self.far = list.far or {}
  self.visibleFallback = list.visibleFallback ~= false
  return changed
end

function Spells:HasAny()
  return #self.melee > 0 or #self.near > 0 or #self.far > 0
end

-- Reichweite eines Zaubers. Rückgabe: inRange (true/false/nil), secret, err.
-- Ein Secret Value wird nie verglichen und zählt als nil (SPEC Abschnitt 4).
function Spells:CheckRange(spellID, unit)
  local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
  if not ok then return nil, false, inRange end
  if issecret(inRange) then return nil, true end
  return inRange, false
end

-- true, wenn mindestens ein Zauber der Liste in Reichweite ist
function Spells:AnyInRange(spellList, unit)
  for _, spellID in ipairs(spellList) do
    local inRange, _, err = self:CheckRange(spellID, unit)
    if err then ns.Debug:Error("IsSpellInRange", err) end
    if inRange == true then return true end
  end
  return false
end

-- Kennt der Charakter den Zauber? true/false, nil wenn die API fehlt oder fehlschlägt
function Spells:IsKnown(spellID)
  if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return nil end
  local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
  if not ok then
    ns.Debug:Error("IsSpellKnown", known)
    return nil
  end
  if issecret(known) then return nil end
  return known
end

function Spells:GetName(spellID)
  local ok, name = pcall(C_Spell.GetSpellName, spellID)
  if ok and type(name) == "string" and not issecret(name) then return name end
  return "?"
end

-- Aktuelle Spezialisierung: specID, specName (nil, wenn nicht ermittelbar)
function Spells:GetSpec()
  local ok, index = pcall(GetSpecialization)
  if not ok or type(index) ~= "number" then return nil, nil end
  local okInfo, specID, specName = pcall(GetSpecializationInfo, index)
  if not okInfo or issecret(specID) or type(specID) ~= "number" then return nil, nil end
  if issecret(specName) then specName = nil end
  return specID, specName
end

-- Bekannte Zauber fürs Debug-Log: flache Tabelle "melee 6552" = true/false/nil
-- und eine Signatur, um Änderungen zu erkennen.
function Spells:KnownInfo()
  local out, parts = {}, {}
  for _, group in ipairs(self.GROUPS) do
    for _, spellID in ipairs(self[group]) do
      local known = self:IsKnown(spellID)
      out[group .. " " .. spellID] = known
      if known then parts[#parts + 1] = spellID end
    end
  end
  return out, table.concat(parts, ",")
end

-- Prüft, ob der Charakter mindestens einen Zauber aus melee, near oder far kennt (SPEC 3.7).
-- Liefert C_SpellBook.IsSpellKnown für einen Zauber kein klares Ergebnis (API fehlt,
-- Fehler, Secret Value), wird nichts geraten: Die Anzeige bleibt dann verfügbar.
-- Rückgabe: true, wenn sich die Verfügbarkeit geändert hat.
function Spells:UpdateAvailability()
  local known, unclear = false, false
  for _, group in ipairs(self.GROUPS) do
    for _, spellID in ipairs(self[group]) do
      local k = self:IsKnown(spellID)
      if k == true then
        known = true
      elseif k == nil then
        unclear = true
      end
    end
  end
  local available = self:HasAny() and (known or unclear)
  local changed = available ~= self.available
  self.available = available
  self.availabilityUnclear = unclear and not known
  return changed
end

-- Reichweite laut C_Spell.GetSpellInfo (minRange, maxRange), fürs Debug-Log
function Spells:GetRangeInfo(spellID)
  local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
  if not ok or type(info) ~= "table" then return nil, nil end
  return info.minRange, info.maxRange
end

-- Alle Spezialisierungen der eigenen Klasse (ID und Name), zur Laufzeit ermittelt.
-- Damit lässt sich im Debug-Log prüfen, ob die Devourer-ID stimmt.
function Spells:ClassSpecs()
  local out = {}
  if type(self.classID) ~= "number" then return out end
  local okNum, num = pcall(GetNumSpecializationsForClassID, self.classID)
  if not okNum or type(num) ~= "number" then return out end
  for i = 1, num do
    local ok, id, name = pcall(GetSpecializationInfoForClassID, self.classID, i)
    if ok and type(id) == "number" and not issecret(id) and not issecret(name) then
      out["spec" .. i] = tostring(id) .. " " .. tostring(name)
    end
  end
  return out
end
