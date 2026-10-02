local ADDON_NAME, ns = ...
local L = ns.L

-- M+-Statistik "Zeit in Reichweite" (SPEC Abschnitt 7).
--
-- Gemessen wird nur während eines Mythisch+-Laufs, mit eigenem Ticker (0,2 s), unabhängig
-- davon, ob die Anzeige sichtbar ist. Gezählt wird nur, wenn der Spieler im Kampf ist, lebt
-- und ein angreifbares Ziel hat. "In Reichweite" ist dieselbe Bedingung wie für 3 Boxen.
--
-- Der laufende Messstand liegt in db.char.mplusCurrent (nur Zahlen, nie geheime Werte), damit
-- die Messung nach /reload weiterläuft. Abgeschlossene Läufe landen in db.char.mplus[mapID].
--
-- Alle Challenge-Mode-APIs und -Events sind im Spiel noch nicht getestet: jeder Aufruf in
-- pcall, jedes Ergebnis auf Secret Values geprüft, Unbekanntes wird geloggt statt geraten.

local Stats = {}
ns.Stats = Stats

local issecret = issecretvalue or function() return false end

local TICK_INTERVAL = 0.2
local MAX_TICK_GAP = 1.0          -- größere Lücken (Ladebildschirm, Reload) nicht zählen
local MIN_TOTAL = 30              -- Sekunden, darunter wird ein Lauf nicht gewertet
local MIN_CATEGORY = 10           -- Sekunden, Mindestzeit für Boss- bzw. Trash-Wert
local TICK_LOG_INTERVAL = 30      -- Zwischenstand im Debug-Log
local RESUME_MAX_AGE = 2 * 3600   -- gespeicherten Lauf höchstens so lange fortsetzen
local ENDED_GUARD = 90 * 60       -- nach Abschluss im selben Dungeon nicht neu starten
local RESET_CONFIRM_SECONDS = 15

Stats.CATEGORIES = { "total", "boss", "trash" }

local ticker
local lastTickTime
local lastTickLog = 0
local pendingWindow = false
local resetRequestedAt

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------

local function pack(...)
  return { n = select("#", ...), ... }
end

-- API geschützt aufrufen. Rückgabe: ok, Ergebnisse ... (bei fehlender API ok = false)
local function try(where, fn, ...)
  if type(fn) ~= "function" then
    return false, "missing"
  end
  local res = pack(pcall(fn, ...))
  if not res[1] then
    ns.Debug:Error(where, res[2])
    return false, res[2]
  end
  return unpack(res, 1, res.n)
end

-- Wert nur zurückgeben, wenn er nicht geheim ist und den erwarteten Typ hat
local function plain(v, wantType)
  if issecret(v) then return nil end
  if wantType and type(v) ~= wantType then return nil end
  return v
end

local function round1(v)
  return math.floor(v * 10 + 0.5) / 10
end

local function now()
  return GetTime()
end

local function clock()
  local ok, t = pcall(time)
  return ok and plain(t, "number") or 0
end

local function charDB()
  return ns.db.char
end

function Stats:IsEnabled()
  return ns.db.profile.stats.enabled
end

---------------------------------------------------------------------------
-- Challenge-Mode-Infos (nicht getestet, daher defensiv)
---------------------------------------------------------------------------

local CM = C_ChallengeMode

-- Laufender Schlüssel: mapID, level, known.
-- known = false, wenn eine der APIs fehlt, fehlschlägt oder Geheimes liefert; dann ist
-- "kein Schlüssel" nicht sicher und es wird nichts daraus geschlossen.
local function activeKey()
  if not CM then return nil, nil, false end
  local okMap, mapID = try("GetActiveChallengeMapID", CM.GetActiveChallengeMapID)
  local okKey, level = try("GetActiveKeystoneInfo", CM.GetActiveKeystoneInfo)
  local known = okMap and okKey and not issecret(mapID) and not issecret(level)
  mapID = okMap and plain(mapID, "number") or nil
  level = okKey and plain(level, "number") or nil
  return mapID, level, known and true or false
end

-- true / false, nil = unbekannt
local function challengeModeActive()
  if not CM then return nil end
  local ok, active = try("IsChallengeModeActive", CM.IsChallengeModeActive)
  if not ok then return nil end
  return plain(active, "boolean")
end

function Stats:GetMapName(mapID)
  if not (CM and mapID) then return nil end
  local ok, name = try("GetMapUIInfo", CM.GetMapUIInfo, mapID)
  return ok and plain(name, "string") or nil
end

-- Abschlussinfo (Nachfolger von GetCompletionInfo seit 11.0.5, warcraft.wiki.gg)
local function completionInfo()
  if not CM then return nil end
  local ok, info = try("GetChallengeCompletionInfo", CM.GetChallengeCompletionInfo)
  if not ok or issecret(info) or type(info) ~= "table" then return nil end
  return {
    mapID = plain(info.mapChallengeModeID, "number"),
    level = plain(info.level, "number"),
    time = plain(info.time, "number"),
    onTime = plain(info.onTime, "boolean"),
    practiceRun = plain(info.practiceRun, "boolean"),
  }
end

local function inInstance()
  local ok, isIn = pcall(IsInInstance)
  if not ok or issecret(isIn) then return nil end
  return isIn == true
end

---------------------------------------------------------------------------
-- Messung
---------------------------------------------------------------------------

local function newCounters()
  return { total = 0, boss = 0, trash = 0 }
end

-- Wahrheitswert einer Unit-API. Rückgabe: Wert, unknown (Fehler oder Secret Value)
local function unitBool(where, fn, ...)
  local value, secret, failed = ns.Display.SafeBool(where, fn, ...)
  if secret or failed then return nil, true end
  return value, false
end

-- Wie Spells:AnyInRange für die Nahkampfstufe, aber dreiwertig:
-- true, false oder nil (unbekannt, wenn kein Treffer und ein Ergebnis geheim/fehlerhaft war)
local function meleeInRange()
  local Spells = ns.Spells
  local unknown = false
  for _, spellID in ipairs(Spells.melee) do
    local inRange, secret, err = Spells:CheckRange(spellID, "target")
    if err then ns.Debug:Error("IsSpellInRange", err) end
    if inRange == true then return true end
    if secret or err then unknown = true end
  end
  if unknown then return nil end
  return false
end

-- Ein Messschritt. Rückgabe: "counted", "skipped" oder nil (nicht zählbar, z. B. außer Kampf)
local function measure(run, dt)
  local okCombat, combat = pcall(InCombatLockdown)
  if not okCombat or issecret(combat) then return "skipped" end
  if combat ~= true then return nil end

  local dead, deadUnknown = unitBool("UnitIsDeadOrGhost", UnitIsDeadOrGhost, "player")
  if deadUnknown then return "skipped" end
  if dead == true then return nil end

  local exists, existsUnknown = unitBool("UnitExists", UnitExists, "target")
  if existsUnknown then return "skipped" end
  if exists ~= true then return nil end

  local isPlayer, isPlayerUnknown = unitBool("UnitIsUnit", UnitIsUnit, "target", "player")
  if isPlayerUnknown then return "skipped" end
  if isPlayer == true then return nil end

  local canAttack, canAttackUnknown = unitBool("UnitCanAttack", UnitCanAttack, "player", "target")
  if canAttackUnknown then return "skipped" end
  if canAttack ~= true then return nil end

  if #ns.Spells.melee == 0 then return nil end
  local inRange = meleeInRange()
  if inRange == nil then return "skipped" end

  local category = run.boss and "boss" or "trash"
  run.time.total = run.time.total + dt
  run.time[category] = run.time[category] + dt
  if inRange then
    run.inRange.total = run.inRange.total + dt
    run.inRange[category] = run.inRange[category] + dt
  end
  return "counted"
end

local function percent(run, category)
  local t = run.time[category]
  if t <= 0 then return nil end
  return round1(run.inRange[category] / t * 100)
end

local function onTick()
  local run = charDB().mplusCurrent
  if not run then
    Stats:StopTicker()
    return
  end
  local t = now()
  local dt = t - (lastTickTime or t)
  lastTickTime = t
  if dt <= 0 then return end
  if dt > MAX_TICK_GAP then
    run.skippedGap = (run.skippedGap or 0) + dt
    return
  end

  local ok, result = pcall(measure, run, dt)
  if not ok then
    ns.Debug:Error("Stats:measure", result)
    run.skippedUnknown = run.skippedUnknown + dt
  elseif result == "skipped" then
    run.skippedUnknown = run.skippedUnknown + dt
  end
  run.updated = clock()

  if ns.Debug:IsEnabled() and t - lastTickLog >= TICK_LOG_INTERVAL then
    lastTickLog = t
    ns.Debug:Add("mplusTick", {
      mapID = run.mapID,
      boss = run.boss,
      timeTotal = round1(run.time.total),
      timeBoss = round1(run.time.boss),
      timeTrash = round1(run.time.trash),
      pctTotal = percent(run, "total"),
      skippedUnknown = round1(run.skippedUnknown),
    })
  end
end

function Stats:StartTicker()
  if ticker then return end
  lastTickTime = now()
  lastTickLog = now()
  local ok, t = pcall(C_Timer.NewTicker, TICK_INTERVAL, onTick)
  if ok then
    ticker = t
  else
    ns.Debug:Error("Stats:NewTicker", t)
  end
end

function Stats:StopTicker()
  if ticker then
    pcall(ticker.Cancel, ticker)
    ticker = nil
  end
end

---------------------------------------------------------------------------
-- Lauf starten, fortsetzen, beenden
---------------------------------------------------------------------------

function Stats:StartRun(mapID, source)
  if not self:IsEnabled() then return end
  local db = charDB()
  if db.mplusCurrent then
    -- Ein noch offener Lauf wird ersetzt (z. B. neuer Schlüssel ohne Reset-Event)
    self:EndRun("replaced", true)
  end
  local _, level = activeKey()
  db.mplusCurrent = {
    mapID = mapID,
    name = self:GetMapName(mapID),
    level = level,
    started = clock(),
    updated = clock(),
    boss = false,
    time = newCounters(),
    inRange = newCounters(),
    skippedUnknown = 0,
    skippedGap = 0,
  }
  db.mplusEnded = nil
  self:StartTicker()
  ns.Debug:Add("mplusStart", {
    mapID = mapID, name = db.mplusCurrent.name, level = level, source = source, resumed = false,
  })
end

-- Beim Betreten der Welt / nach /reload: laufenden Schlüssel erkennen und fortsetzen,
-- Verlassen der Instanz ohne Abschluss als Abbruch werten.
function Stats:CheckActive(source)
  if not self:IsEnabled() then return end
  local db = charDB()
  local run = db.mplusCurrent
  local mapID, level, known = activeKey()
  local keyRunning = mapID ~= nil and level ~= nil and level > 0
  local inside = inInstance()

  if run then
    if keyRunning and mapID == run.mapID and clock() - (run.updated or 0) <= RESUME_MAX_AGE then
      if not ticker then
        self:StartTicker()
        ns.Debug:Add("mplusStart", {
          mapID = mapID, name = run.name, level = run.level, source = source, resumed = true,
          timeTotal = round1(run.time.total),
        })
      end
      return
    end
    if clock() - (run.updated or 0) > RESUME_MAX_AGE then
      -- alter Lauf (z. B. Logout mitten im Lauf vor langer Zeit): still verwerfen
      ns.Debug:Add("mplusDiscarded", { mapID = run.mapID, reason = "stale" })
      db.mplusCurrent = nil
      self:StopTicker()
      return
    end
    -- Instanz verlassen bzw. anderer Schlüssel aktiv. Ist der Schlüssel-Status unbekannt
    -- und wir sind noch in einer Instanz, wird nichts beendet, nur weitergemessen.
    if inside == false or (known and (not keyRunning or mapID ~= run.mapID)) then
      self:EndRun("leftInstance")
    else
      ns.Debug:Add("mplusKeyUnknown", { mapID = run.mapID, inside = inside, known = known })
      if not ticker then self:StartTicker() end
    end
    return
  end

  if keyRunning then
    -- Nach Abschluss meldet die API den Schlüssel womöglich noch: nicht neu starten
    local ended = db.mplusEnded
    if ended and ended.mapID == mapID and clock() - (ended.at or 0) <= ENDED_GUARD then
      ns.Debug:Add("mplusNoRestart", { mapID = mapID, reason = "recentlyEnded" })
      return
    end
    if challengeModeActive() == false then
      ns.Debug:Add("mplusNoRestart", { mapID = mapID, reason = "notActive" })
      return
    end
    self:StartRun(mapID, source)
  end
end

local function categoryValid(run, category)
  if category == "total" then return run.time.total >= MIN_TOTAL end
  return run.time[category] >= MIN_CATEGORY
end

-- Beendet den Lauf. reason: "completed", "reset", "leftInstance", "replaced", "disabled"
function Stats:EndRun(reason, silent)
  local db = charDB()
  local run = db.mplusCurrent
  self:StopTicker()
  if not run then return end
  db.mplusCurrent = nil

  local info = reason == "completed" and completionInfo() or nil
  if info then
    run.level = run.level or info.level
    ns.Debug:Add("mplusCompletion", info)
  end
  run.name = run.name or self:GetMapName(run.mapID)

  local completed = reason == "completed"
  local rated = completed and run.mapID ~= nil and categoryValid(run, "total")

  local result = {
    mapID = run.mapID,
    name = run.name,
    level = run.level,
    reason = reason,
    completed = completed,
    rated = rated,
    countedTime = round1(run.time.total),
    pct = {}, valid = {}, best = {}, avg = {}, newBest = {},
    runs = 0,
    firstRun = false,
    at = clock(),
  }
  for _, cat in ipairs(self.CATEGORIES) do
    result.pct[cat] = percent(run, cat)
    result.valid[cat] = categoryValid(run, cat) and result.pct[cat] ~= nil
  end

  if rated then
    local m = db.mplus[run.mapID]
    if not m then
      m = {
        runs = 0,
        best = {},
        sum = newCounters(),
        count = newCounters(),
        last = {},
      }
      db.mplus[run.mapID] = m
    end
    if run.name then m.name = run.name end
    result.firstRun = m.runs == 0
    m.runs = m.runs + 1
    for _, cat in ipairs(self.CATEGORIES) do
      local v = result.valid[cat] and result.pct[cat] or nil
      if v then
        local old = m.best[cat]
        if old == nil or v > old then
          m.best[cat] = v
          result.newBest[cat] = old ~= nil   -- beim ersten Wert kein "Neuer Bestwert"
        end
        m.sum[cat] = m.sum[cat] + v
        m.count[cat] = m.count[cat] + 1
      end
      m.last[cat] = v
    end
    m.last.level = run.level
    m.last.time = clock()
  end

  -- Vergleichswerte fürs Fenster (auch bei nicht gewerteten Läufen)
  local m = run.mapID and db.mplus[run.mapID]
  if m then
    result.runs = m.runs
    for _, cat in ipairs(self.CATEGORIES) do
      result.best[cat] = m.best[cat]
      if m.count[cat] > 0 then result.avg[cat] = round1(m.sum[cat] / m.count[cat]) end
    end
  end

  if completed then db.mplusEnded = { mapID = run.mapID, at = clock() } end
  -- Ersetzte bzw. durch Ausschalten beendete Läufe nicht als "letzten Lauf" anbieten
  if reason ~= "replaced" and reason ~= "disabled" then db.mplusLast = result end

  ns.Debug:Add("mplusEnd", {
    reason = reason,
    mapID = run.mapID,
    level = run.level,
    timeTotal = round1(run.time.total),
    timeBoss = round1(run.time.boss),
    timeTrash = round1(run.time.trash),
    pctTotal = result.pct.total,
    pctBoss = result.pct.boss,
    pctTrash = result.pct.trash,
    skippedUnknown = round1(run.skippedUnknown),
    skippedGap = round1(run.skippedGap or 0),
    rated = rated,
    newBestTotal = result.newBest.total == true,
    newBestBoss = result.newBest.boss == true,
    newBestTrash = result.newBest.trash == true,
  })

  if not silent and reason ~= "replaced" and reason ~= "disabled" then
    self:RequestWindow()
  end
  ns.Options:Notify()
end

---------------------------------------------------------------------------
-- Events (aus Core.lua weitergereicht)
---------------------------------------------------------------------------

function Stats:OnChallengeStart(mapID)
  mapID = plain(mapID, "number") or select(1, activeKey())
  ns.Debug:Add("challengeEvent", { event = "CHALLENGE_MODE_START", mapID = mapID })
  if mapID then self:StartRun(mapID, "event") end
end

function Stats:OnChallengeCompleted()
  ns.Debug:Add("challengeEvent", { event = "CHALLENGE_MODE_COMPLETED" })
  if charDB().mplusCurrent then self:EndRun("completed") end
end

function Stats:OnChallengeReset(mapID)
  ns.Debug:Add("challengeEvent", { event = "CHALLENGE_MODE_RESET", mapID = plain(mapID, "number") })
  if charDB().mplusCurrent then self:EndRun("reset") end
end

function Stats:OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
  ns.Debug:Add("encounter", {
    phase = "start",
    encounterID = plain(encounterID, "number"),
    encounterName = plain(encounterName, "string"),
    difficultyID = plain(difficultyID, "number"),
    groupSize = plain(groupSize, "number"),
    secretArgs = issecret(encounterID) or issecret(encounterName) or nil,
    running = charDB().mplusCurrent ~= nil,
  })
  local run = charDB().mplusCurrent
  if run then run.boss = true end
end

function Stats:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  ns.Debug:Add("encounter", {
    phase = "end",
    encounterID = plain(encounterID, "number"),
    encounterName = plain(encounterName, "string"),
    difficultyID = plain(difficultyID, "number"),
    success = plain(success, "number"),
    running = charDB().mplusCurrent ~= nil,
  })
  local run = charDB().mplusCurrent
  if run then run.boss = false end
end

function Stats:OnCombatEnd()
  if pendingWindow then
    pendingWindow = false
    self:ShowWindow(charDB().mplusLast)
  end
end

function Stats:SetEnabled(enabled)
  ns.db.profile.stats.enabled = enabled and true or false
  if enabled then
    self:CheckActive("enabled")
  elseif charDB().mplusCurrent then
    self:EndRun("disabled", true)
  end
end

---------------------------------------------------------------------------
-- Statistik abfragen und zurücksetzen
---------------------------------------------------------------------------

-- Liste für die Übersicht im Menü, sortiert nach Name
function Stats:Overview()
  local list = {}
  for mapID, m in pairs(charDB().mplus) do
    local avg = (m.count.total or 0) > 0 and round1(m.sum.total / m.count.total) or nil
    list[#list + 1] = { mapID = mapID, name = m.name or tostring(mapID), runs = m.runs, best = m.best.total, avg = avg }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

function Stats:Reset()
  local db = charDB()
  wipe(db.mplus)
  db.mplusLast = nil
  db.mplusEnded = nil
  ns.Debug:Add("mplusStatsReset")
  ns.Options:Notify()
  if self.window then self.window:Hide() end
end

-- /dotrange stats reset: zweimal eingeben (innerhalb kurzer Zeit) oder "confirm"
function Stats:ResetCommand(arg)
  local t = now()
  if arg == "confirm" or (resetRequestedAt and t - resetRequestedAt <= RESET_CONFIRM_SECONDS) then
    resetRequestedAt = nil
    self:Reset()
    ns.Print(L["STATS_RESET_DONE"])
  else
    resetRequestedAt = t
    ns.Print(L["STATS_RESET_CONFIRM"])
  end
end

---------------------------------------------------------------------------
-- Fenster am Ende des Laufs
---------------------------------------------------------------------------

local function formatPct(v)
  if v == nil then return "–" end
  local s = string.format("%.1f", v):gsub("%.", L["DECIMAL_SEP"])
  return s .. " %"
end
Stats.FormatPct = formatPct

local function pctColor(v)
  if v == nil then return "|cffaaaaaa" end
  if v >= 90 then return "|cff33ff33" end
  if v >= 75 then return "|cffffd100" end
  return "|cffff4040"
end

local function coloredPct(v)
  return pctColor(v) .. formatPct(v) .. "|r"
end

local function formatDuration(seconds)
  seconds = math.floor((seconds or 0) + 0.5)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end
Stats.FormatDuration = formatDuration

function Stats:RequestWindow()
  if not ns.db.profile.stats.showWindow then return end
  local okCombat, combat = pcall(InCombatLockdown)
  if okCombat and combat == true then
    pendingWindow = true
    return
  end
  self:ShowWindow(charDB().mplusLast)
end

local WIDTH, ROW = 470, 20
local LABEL_X, VALUE_X = 16, 150

local function createWindow()
  local f = CreateFrame("Frame", "DotRangeStatsWindow", UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, 168)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)   -- Position speichert das Addon selbst
    local point, _, relPoint, x, y = self:GetPoint()
    ns.db.profile.stats.windowPos = {
      point = point, relPoint = relPoint, x = math.floor(x + 0.5), y = math.floor(y + 0.5),
    }
  end)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
  f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() f:Hide() end)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_X, -14)
  f.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
  f.title:SetJustifyH("LEFT")

  f.rows = {}
  for i, cat in ipairs(Stats.CATEGORIES) do
    local y = -44 - (i - 1) * ROW
    local row = {}
    row.highlight = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight:SetPoint("TOPLEFT", f, "TOPLEFT", 6, y + 2)
    row.highlight:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    row.highlight:SetHeight(ROW)
    row.highlight:SetColorTexture(1, 0.82, 0, 0.15)
    row.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_X, y)
    row.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.value:SetPoint("TOPLEFT", f, "TOPLEFT", VALUE_X, y)
    row.value:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    row.value:SetJustifyH("LEFT")
    f.rows[cat] = row
  end

  f.timeLine = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.timeLine:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_X, -44 - 3 * ROW - 8)
  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.note:SetPoint("TOPLEFT", f.timeLine, "BOTTOMLEFT", 0, -8)
  f.note:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  f.note:SetJustifyH("LEFT")
  return f
end

local function applyWindowPosition(f)
  local pos = ns.db.profile.stats.windowPos
  f:ClearAllPoints()
  if pos and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
end

local LABELS = { total = "STATS_IN_RANGE", boss = "STATS_BOSSES", trash = "STATS_TRASH" }

-- result: Tabelle aus EndRun (db.char.mplusLast). Rückgabe: true, wenn angezeigt.
function Stats:ShowWindow(result)
  if not result then
    ns.Print(L["STATS_NO_RUN"])
    return false
  end
  local ok, err = pcall(function()
    if not self.window then self.window = createWindow() end
    local f = self.window
    applyWindowPosition(f)

    local title = "DotRange · " .. (result.name or L["STATS_UNKNOWN_DUNGEON"])
    if result.level then title = title .. " +" .. result.level end
    f.title:SetText(title)

    for _, cat in ipairs(self.CATEGORIES) do
      local row = f.rows[cat]
      row.label:SetText(L[LABELS[cat]])
      local v = result.valid[cat] and result.pct[cat] or nil
      local text = coloredPct(v)
      if result.valid[cat] == false and result.pct[cat] ~= nil then
        text = text .. "  |cffaaaaaa" .. L["STATS_TOO_SHORT_CATEGORY"] .. "|r"
      end
      local extra = {}
      if result.best[cat] then extra[#extra + 1] = L["STATS_BEST"]:format(formatPct(result.best[cat])) end
      if cat == "total" then
        if result.avg.total then extra[#extra + 1] = L["STATS_AVG"]:format(formatPct(result.avg.total)) end
        if result.runs == 1 then
          extra[#extra + 1] = L["STATS_RUN_ONE"]
        elseif result.runs > 1 then
          extra[#extra + 1] = L["STATS_RUNS"]:format(result.runs)
        end
      end
      if #extra > 0 then text = text .. "   |cffaaaaaa(" .. table.concat(extra, " · ") .. ")|r" end
      if result.newBest[cat] then text = text .. "  |cffffd100" .. L["STATS_NEW_BEST"] .. "|r" end
      row.value:SetText(text)
      row.highlight:SetShown(result.newBest[cat] == true)
    end

    f.timeLine:SetText(L["STATS_COUNTED_TIME"]:format(formatDuration(result.countedTime)))

    local note
    if not result.completed then
      note = "|cffff8020" .. L["STATS_ABORTED"] .. "|r"
    elseif not result.rated then
      note = "|cffff8020" .. L["STATS_NOT_RATED_SHORT"] .. "|r"
    elseif result.firstRun then
      note = "|cff33ff99" .. L["STATS_FIRST_RUN"] .. "|r"
    end
    f.note:SetText(note or "")
    f:SetHeight(note and 176 or 154)
    f:Show()
  end)
  if not ok then
    ns.Debug:Error("Stats:ShowWindow", err)
    return false
  end
  return true
end
