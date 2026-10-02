local ADDON_NAME, ns = ...
local L = ns.L

-- M+-Statistik "Zeit in Reichweite" (SPEC Abschnitt 7).
--
-- Gemessen wird nur während eines Mythisch+-Laufs, mit eigenem Ticker (0,2 s), unabhängig
-- davon, ob die Anzeige sichtbar ist. Gezählt wird nur, wenn der Spieler im Kampf ist, lebt
-- und ein angreifbares Ziel hat. "In Reichweite" ist dieselbe Bedingung wie für 3 Boxen.
--
-- Ab 3.2.0 zusätzlich nach Abschnitten wie WarpDeplete: Trash, Boss 1, Trash, Boss 2 ...
-- Trash gehört zum nächsten gepullten Boss; Trash nach dem letzten Boss ist ein eigener
-- Abschnitt. Ein Wipe zählt zum selben Boss-Abschnitt.
--
-- Der laufende Messstand liegt in db.char.mplusCurrent (nur Zahlen und lesbare Texte, nie
-- geheime Werte), damit die Messung nach /reload weiterläuft. Abgeschlossene Läufe landen in
-- db.char.mplus[mapID].
--
-- Jeder API-Aufruf steht in pcall, jedes Ergebnis wird auf Secret Values geprüft,
-- Unbekanntes wird geloggt statt geraten.
--
-- Teile der Bosslisten- und Namenslogik sind nach WarpDeplete (https://github.com/happenslol/
-- WarpDeplete, MIT-Lizenz, Copyright (c) 2021 Hilmar Wiegand) übernommen und angepasst:
-- State.lua UpdateObjectives/LoadKeyDetails, Util.lua getEJInstanceID/formatObjectiveName.

local Stats = {}
ns.Stats = Stats

local issecret = issecretvalue or function() return false end

local TICK_INTERVAL = 0.2
local MAX_TICK_GAP = 1.0          -- größere Lücken (Ladebildschirm, Reload) nicht zählen
local MIN_TOTAL = 30              -- Sekunden, darunter wird ein Lauf nicht gewertet
local MIN_CATEGORY = 10           -- Sekunden, Mindestzeit für Boss-/Trash-Wert und Abschnitte
local TICK_LOG_INTERVAL = 30      -- Zwischenstand im Debug-Log
local RESUME_MAX_AGE = 2 * 3600   -- gespeicherten Lauf höchstens so lange fortsetzen
local ENDED_GUARD = 90 * 60       -- nach Abschluss im selben Dungeon nicht neu starten
local RESET_CONFIRM_SECONDS = 15
local MAX_CRITERIA = 20
local EPSILON = 0.05              -- Toleranz für Gleitkomma-Summen (50 x 0,2 s = 9,9999...)
local CRITERIA_TYPE_DUNGEON_ENCOUNTER = 165   -- assetID = DungeonEncounterID (WarpDeplete)

Stats.CATEGORIES = { "total", "boss", "trash" }

local ticker
local lastTickTime
local lastTickLog = 0
local pendingWindow = false
local resetRequestedAt
local ejNames                    -- [DungeonEncounterID] = Name aus dem Dungeonkompendium
local ejSelected = false         -- EJ_SelectInstance in dieser Sitzung schon aufgerufen
local lastBossesSignature

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

local function nonEmpty(s)
  if type(s) == "string" and s ~= "" then return s end
  return nil
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
-- Challenge-Mode-Infos (defensiv)
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

-- Name über GetMapUIInfo (1. Rückgabe)
local function mapUIName(mapID)
  if not (CM and mapID) then return nil end
  local ok, name = try("GetMapUIInfo", CM.GetMapUIInfo, mapID)
  return ok and nonEmpty(plain(name, "string")) or nil
end

-- Fallback: Name der aktuellen Instanz (nur in einer Dungeon-Instanz sinnvoll)
local function instanceName()
  local ok, name, instanceType = pcall(GetInstanceInfo)
  if not ok then return nil end
  if plain(instanceType, "string") ~= "party" then return nil end
  return nonEmpty(plain(name, "string"))
end

function Stats:GetMapName(mapID)
  return mapUIName(mapID)
end

-- Fehlende mapID bzw. fehlenden Namen nachtragen; ein bekannter Name bleibt erhalten
local function resolveRunInfo(run, reason)
  if not run.mapID then
    local mapID = activeKey()
    if mapID then run.mapID = mapID end
  end
  if not run.name then
    local uiName = mapUIName(run.mapID)
    local instName = (not uiName) and instanceName() or nil
    run.name = uiName or instName
    if run.name then
      run.nameSource = uiName and "GetMapUIInfo" or "GetInstanceInfo"
      ns.Debug:Add("mplusName", { reason = reason, mapID = run.mapID, name = run.name, source = run.nameSource })
    end
  end
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
-- Bossliste aus den Szenario-Zielen (nach WarpDeplete UpdateObjectives)
---------------------------------------------------------------------------

-- Anzahl Kriterien: C_Scenario.GetStepInfo (3. Rückgabe, wie WarpDeplete), sonst
-- C_ScenarioInfo.GetScenarioStepInfo().numCriteria. Rückgabe: Anzahl, Quelle
local function criteriaCount()
  if C_Scenario and C_Scenario.GetStepInfo then
    local ok, _, _, num = try("C_Scenario.GetStepInfo", C_Scenario.GetStepInfo)
    num = ok and plain(num, "number") or nil
    if num then return num, "GetStepInfo" end
  end
  if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
    local ok, info = try("GetScenarioStepInfo", C_ScenarioInfo.GetScenarioStepInfo)
    if ok and type(info) == "table" and not issecret(info) then
      local num = plain(info.numCriteria, "number")
      if num then return num, "GetScenarioStepInfo" end
    end
  end
  return nil, "none"
end

-- Endungen wie "besiegt"/"defeated" entfernen (WarpDeplete formatObjectiveName;
-- deDE-Filter von DotRange ergänzt)
local OBJECTIVE_FILTERS = { " [Bb]esiegt", "[Bb]esiegt", " [Dd]efeated", "[Dd]efeated" }

local function formatObjectiveName(description)
  if type(description) ~= "string" then return nil end
  local result = description
  for _, filter in ipairs(OBJECTIVE_FILTERS) do
    result = result:gsub(filter, "")
  end
  result = result:gsub("^%s+", ""):gsub("%s+$", "")
  return nonEmpty(result)
end
Stats.FormatObjectiveName = formatObjectiveName

-- Liest die Kriterien. Rückgabe: Bossliste { {encounterID, description, completed, index} },
-- flache Tabelle fürs Debug-Log, Signatur
local function readBosses()
  local bosses, log, parts = {}, {}, {}
  if not (C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then
    return bosses, { missing = "C_ScenarioInfo.GetCriteriaInfo" }, "missing"
  end
  local num, source = criteriaCount()
  log.count = num
  log.countSource = source
  if not num or num <= 0 then return bosses, log, "none" end
  for i = 1, math.min(num, MAX_CRITERIA) do
    local ok, info = try("GetCriteriaInfo", C_ScenarioInfo.GetCriteriaInfo, i)
    if ok and type(info) == "table" and not issecret(info) then
      local ctype = plain(info.criteriaType, "number")
      local asset = plain(info.assetID, "number")
      local desc = plain(info.description, "string")
      local completed = plain(info.completed, "boolean")
      local weighted = plain(info.isWeightedProgress, "boolean")
      log["c" .. i] = table.concat({
        tostring(ctype), tostring(asset), tostring(desc), tostring(completed), tostring(weighted),
      }, "|")
      parts[#parts + 1] = log["c" .. i]
      if weighted ~= true and ctype == CRITERIA_TYPE_DUNGEON_ENCOUNTER and asset and asset ~= 0 then
        bosses[#bosses + 1] = { encounterID = asset, description = desc, completed = completed, index = i }
      end
    else
      log["c" .. i] = "unreadable"
      parts[#parts + 1] = "?"
    end
  end
  return bosses, log, table.concat(parts, ";")
end

function Stats:UpdateBosses(reason)
  local run = charDB().mplusCurrent
  if not run then return end
  local bosses, log, signature = readBosses()
  if #bosses > 0 then run.bosses = bosses end
  if signature ~= lastBossesSignature then
    lastBossesSignature = signature
    log.reason = reason
    log.bosses = #bosses
    ns.Debug:Add("mplusBosses", log)
  end
end

---------------------------------------------------------------------------
-- Bossnamen aus dem Dungeonkompendium (ohne das Fenster zu öffnen)
---------------------------------------------------------------------------

-- Journal-Instanz wie WarpDeplete Util.getEJInstanceID (ohne dessen feste Tabelle alter
-- Dungeons): C_Map.GetBestMapForUnit("player") → EJ_GetInstanceForMap
local function ejInstanceID()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local okMap, uiMapID = try("GetBestMapForUnit", C_Map.GetBestMapForUnit, "player")
  uiMapID = okMap and plain(uiMapID, "number") or nil
  if not uiMapID then return nil end
  local ok, id = try("EJ_GetInstanceForMap", EJ_GetInstanceForMap, uiMapID)
  id = ok and plain(id, "number") or nil
  if id and id ~= 0 then return id end
  return nil
end

local function readEJ(instanceID)
  local names, count = {}, 0
  for i = 1, MAX_CRITERIA do
    local ok, name, _, _, _, _, _, dungeonEncounterID = try("EJ_GetEncounterInfoByIndex",
      EJ_GetEncounterInfoByIndex, i, instanceID)
    if not ok then break end
    name = nonEmpty(plain(name, "string"))
    dungeonEncounterID = plain(dungeonEncounterID, "number")
    if not name then break end
    if dungeonEncounterID then
      names[dungeonEncounterID] = name
      count = count + 1
    end
  end
  return names, count
end

-- Laut warcraft.wiki.gg (EJ_GetEncounterInfo) liefert die Funktion mit journalInstanceID nur
-- Werte, wenn EJ_SelectInstance in der Sitzung einmal aufgerufen wurde. Wir rufen es nur
-- dann auf, und nur mit der Instanz des aktuellen Dungeons.
local function loadEJNames(reason)
  local instanceID = ejInstanceID()
  if not instanceID then
    ns.Debug:Add("mplusEJ", { reason = reason, instanceID = "none" })
    return
  end
  local names, count = readEJ(instanceID)
  local selected = false
  if count == 0 and not ejSelected and type(EJ_SelectInstance) == "function" then
    ejSelected = true
    selected = try("EJ_SelectInstance", EJ_SelectInstance, instanceID)
    names, count = readEJ(instanceID)
  end
  ejNames = names
  ns.Debug:Add("mplusEJ", { reason = reason, instanceID = instanceID, count = count, selectInstance = selected })
end

-- Bossname in der Reihenfolge der SPEC: Event, Kompendium, Kriterium, "Boss N".
-- Rückgabe: name, Quelle
local function bossName(run, encounterID, eventName, number)
  local name = nonEmpty(plain(eventName, "string"))
  if name then return name, "event" end
  if encounterID then
    if not ejNames then loadEJNames("bossName") end
    if ejNames and ejNames[encounterID] then return ejNames[encounterID], "journal" end
    for _, b in ipairs(run.bosses or {}) do
      if b.encounterID == encounterID then
        local formatted = formatObjectiveName(b.description)
        if formatted then return formatted, "criteria" end
      end
    end
  end
  return L["STATS_BOSS_N"]:format(number), "number"
end

---------------------------------------------------------------------------
-- Abschnitte
---------------------------------------------------------------------------

local function newCounters()
  return { total = 0, boss = 0, trash = 0 }
end

local function newSegment(key, kind, encounterID, name, nameSource)
  return { key = key, kind = kind, encounterID = encounterID, name = name, nameSource = nameSource,
    time = 0, inRange = 0 }
end

-- Lauf aus 3.1.0 (ohne Abschnitte) bzw. neuer Lauf: offenen Trash-Topf anlegen
local function ensureSegments(run)
  if not run.segments then
    run.segments = { newSegment("trash:open", "trash") }
    run.current = 1
    run.bossNumber = 0
  end
end

local function findSegment(run, key)
  for i, seg in ipairs(run.segments) do
    if seg.key == key then return i, seg end
  end
  return nil
end

local function logSegment(run, seg)
  ns.Debug:Add("mplusSegment", {
    kind = seg.kind, key = seg.key, encounterID = seg.encounterID, name = seg.name,
    nameSource = seg.nameSource, index = run.current,
  })
end

-- ENCOUNTER_START: offenen Trash-Topf diesem Boss zuordnen, Boss-Abschnitt beginnen
local function startBossSegment(run, encounterID, eventName)
  ensureSegments(run)
  local bossKey
  if encounterID then
    bossKey = "boss:" .. encounterID
  end
  local existingIndex = bossKey and findSegment(run, bossKey)
  local number
  if existingIndex then
    number = nil
  else
    run.bossNumber = (run.bossNumber or 0) + 1
    number = run.bossNumber
    if not bossKey then bossKey = "boss:#" .. number end
  end

  local name, nameSource
  if existingIndex then
    local seg = run.segments[existingIndex]
    name, nameSource = seg.name, seg.nameSource
  else
    name, nameSource = bossName(run, encounterID, eventName, number)
  end

  -- offenen Trash-Topf diesem Boss zuordnen (bei einem Wipe in den vorhandenen Trash-Abschnitt)
  local cur = run.segments[run.current]
  if cur and cur.key == "trash:open" then
    local trashKey = "trash:" .. (encounterID or ("#" .. (number or 0)))
    local _, existingTrash = findSegment(run, trashKey)
    if existingTrash then
      existingTrash.time = existingTrash.time + cur.time
      existingTrash.inRange = existingTrash.inRange + cur.inRange
      table.remove(run.segments, run.current)
    else
      cur.key = trashKey
      cur.encounterID = encounterID
      cur.name = L["STATS_TRASH_BEFORE"]:format(name)
    end
  end

  local index = findSegment(run, bossKey)
  if not index then
    run.segments[#run.segments + 1] = newSegment(bossKey, "boss", encounterID, name, nameSource)
    index = #run.segments
  end
  run.current = index
  run.boss = true
  if not encounterID then
    ns.Debug:Add("mplusEncounterUnknown", { bossNumber = number, key = bossKey })
  end
  logSegment(run, run.segments[index])
end

-- ENCOUNTER_END: neuer offener Trash-Topf
local function endBossSegment(run)
  ensureSegments(run)
  run.boss = false
  local _, open = findSegment(run, "trash:open")
  if not open then
    run.segments[#run.segments + 1] = newSegment("trash:open", "trash")
  end
  run.current = (findSegment(run, "trash:open"))
  logSegment(run, run.segments[run.current])
end

---------------------------------------------------------------------------
-- Messung
---------------------------------------------------------------------------

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

  ensureSegments(run)
  local seg = run.segments[run.current]
  if seg then
    seg.time = seg.time + dt
    if inRange then seg.inRange = seg.inRange + dt end
  end
  return "counted"
end

local function percent(run, category)
  local t = run.time[category]
  if t <= 0 then return nil end
  return round1(run.inRange[category] / t * 100)
end

local function segmentPercent(seg)
  if seg.time <= 0 then return nil end
  return round1(seg.inRange / seg.time * 100)
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
    local seg = run.segments and run.segments[run.current]
    ns.Debug:Add("mplusTick", {
      mapID = run.mapID,
      boss = run.boss,
      segment = seg and seg.key,
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

-- eventMapID: Argument von CHALLENGE_MODE_START, nur fürs Debug-Log.
-- Die mapID kommt immer aus GetActiveChallengeMapID (wie WarpDeplete LoadKeyDetails).
function Stats:StartRun(source, eventMapID)
  if not self:IsEnabled() then return end
  local db = charDB()
  if db.mplusCurrent then
    -- Ein noch offener Lauf wird ersetzt (z. B. neuer Schlüssel ohne Reset-Event)
    self:EndRun("replaced", true)
  end
  local mapID, level = activeKey()
  local uiName = mapUIName(mapID)
  local instName = instanceName()
  local run = {
    mapID = mapID,
    name = uiName or instName,
    nameSource = (uiName and "GetMapUIInfo") or (instName and "GetInstanceInfo") or nil,
    level = level,
    started = clock(),
    updated = clock(),
    boss = false,
    time = newCounters(),
    inRange = newCounters(),
    skippedUnknown = 0,
    skippedGap = 0,
  }
  ensureSegments(run)
  db.mplusCurrent = run
  db.mplusEnded = nil
  ejNames = nil
  lastBossesSignature = nil
  self:StartTicker()
  ns.Debug:Add("mplusStart", {
    source = source, resumed = false,
    eventMapID = plain(eventMapID, "number"), eventMapIDSecret = issecret(eventMapID) or nil,
    activeMapID = mapID, level = level,
    nameMapUI = uiName, nameInstance = instName, name = run.name,
  })
  self:UpdateBosses("start")
  loadEJNames("start")
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
    if keyRunning and run.mapID == nil then run.mapID = mapID end
    if keyRunning and mapID == run.mapID and clock() - (run.updated or 0) <= RESUME_MAX_AGE then
      if not ticker then
        ensureSegments(run)
        resolveRunInfo(run, "resume")
        self:StartTicker()
        ns.Debug:Add("mplusStart", {
          source = source, resumed = true, activeMapID = mapID, level = run.level,
          name = run.name, nameMapUI = mapUIName(mapID), nameInstance = instanceName(),
          timeTotal = round1(run.time.total), segments = #run.segments,
        })
        self:UpdateBosses("resume")
        if not ejNames then loadEJNames("resume") end
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
    self:StartRun(source)
  end
end

local function categoryValid(run, category)
  if category == "total" then return run.time.total >= MIN_TOTAL - EPSILON end
  return run.time[category] >= MIN_CATEGORY - EPSILON
end

-- Abschnitte für Ergebnis und Speicherung vorbereiten: offener Trash wird zu "trash:end",
-- leere Trash-Abschnitte entfallen.
local function finalizeSegments(run)
  ensureSegments(run)
  local out = {}
  for _, seg in ipairs(run.segments) do
    if seg.key == "trash:open" then
      seg.key = "trash:end"
      seg.name = L["STATS_TRASH_AFTER_LAST"]
    end
    if not (seg.kind == "trash" and seg.time <= 0) then
      out[#out + 1] = {
        key = seg.key, kind = seg.kind, name = seg.name, nameSource = seg.nameSource,
        time = round1(seg.time), pct = segmentPercent(seg), valid = seg.time >= MIN_CATEGORY - EPSILON,
      }
    end
  end
  return out
end

-- Beendet den Lauf. reason: "completed", "reset", "leftInstance", "replaced", "disabled"
function Stats:EndRun(reason, silent)
  local db = charDB()
  local run = db.mplusCurrent
  self:StopTicker()
  if not run then return end
  db.mplusCurrent = nil

  resolveRunInfo(run, "end")
  local info = reason == "completed" and completionInfo() or nil
  if info then
    run.level = run.level or info.level
    ns.Debug:Add("mplusCompletion", info)
  end

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
    segments = finalizeSegments(run),
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
      m = { runs = 0, best = {}, sum = newCounters(), count = newCounters(), last = {} }
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

    -- Abschnitte (ab 3.2.0; ältere Einträge bekommen die Tabelle hier)
    m.segments = m.segments or {}
    for _, seg in ipairs(result.segments) do
      local s = m.segments[seg.key]
      if not s then
        s = { sum = 0, count = 0 }
        m.segments[seg.key] = s
      end
      if seg.name then s.name = seg.name end
      local v = seg.valid and seg.pct or nil
      if v then
        if s.best == nil or v > s.best then
          seg.newBest = s.best ~= nil
          s.best = v
        end
        s.sum = s.sum + v
        s.count = s.count + 1
      end
      s.last = v
    end
  end

  -- Vergleichswerte fürs Fenster (auch bei nicht gewerteten Läufen)
  local m = run.mapID and db.mplus[run.mapID]
  if m then
    result.runs = m.runs
    for _, cat in ipairs(self.CATEGORIES) do
      result.best[cat] = m.best[cat]
      if m.count[cat] > 0 then result.avg[cat] = round1(m.sum[cat] / m.count[cat]) end
    end
    for _, seg in ipairs(result.segments) do
      local s = m.segments and m.segments[seg.key]
      if s then seg.best = s.best end
    end
  end

  if completed then db.mplusEnded = { mapID = run.mapID, at = clock() } end
  -- Ersetzte bzw. durch Ausschalten beendete Läufe nicht als "letzten Lauf" anbieten
  if reason ~= "replaced" and reason ~= "disabled" then db.mplusLast = result end

  local log = {
    reason = reason,
    mapID = run.mapID,
    name = run.name,
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
  }
  for i, seg in ipairs(result.segments) do
    log["seg" .. i] = table.concat({ seg.key, tostring(seg.name), tostring(seg.time), tostring(seg.pct) }, "|")
  end
  ns.Debug:Add("mplusEnd", log)

  if not silent and reason ~= "replaced" and reason ~= "disabled" then
    self:RequestWindow()
  end
  ns.Options:Notify()
end

---------------------------------------------------------------------------
-- Events (aus Core.lua weitergereicht)
---------------------------------------------------------------------------

function Stats:OnChallengeStart(eventMapID)
  ns.Debug:Add("challengeEvent", {
    event = "CHALLENGE_MODE_START", eventMapID = plain(eventMapID, "number"),
    activeMapID = (activeKey()),
  })
  self:StartRun("event", eventMapID)
end

function Stats:OnChallengeCompleted()
  ns.Debug:Add("challengeEvent", { event = "CHALLENGE_MODE_COMPLETED" })
  if charDB().mplusCurrent then self:EndRun("completed") end
end

function Stats:OnChallengeReset(mapID)
  ns.Debug:Add("challengeEvent", { event = "CHALLENGE_MODE_RESET", mapID = plain(mapID, "number") })
  if charDB().mplusCurrent then self:EndRun("reset") end
end

function Stats:OnScenarioUpdate(event)
  if charDB().mplusCurrent then self:UpdateBosses(event) end
end

function Stats:OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
  local id = plain(encounterID, "number")
  ns.Debug:Add("encounter", {
    phase = "start",
    encounterID = id,
    encounterName = plain(encounterName, "string"),
    difficultyID = plain(difficultyID, "number"),
    groupSize = plain(groupSize, "number"),
    secretArgs = issecret(encounterID) or issecret(encounterName) or nil,
    running = charDB().mplusCurrent ~= nil,
  })
  local run = charDB().mplusCurrent
  if run then startBossSegment(run, id, encounterName) end
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
  if run then endBossSegment(run) end
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

-- Spalten: Name | Prozent (rechtsbündig) | Vergleich
local WIDTH = 600
local ROW = 18
local PAD = 16
local NAME_W = 220
local PCT_RIGHT = PAD + NAME_W + 80     -- rechte Kante der Prozentspalte
local EXTRA_X = PCT_RIGHT + 16
local TOP = 44

local function createWindow()
  local f = CreateFrame("Frame", "DotRangeStatsWindow", UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, 200)
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
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -14)
  f.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
  f.title:SetJustifyH("LEFT")

  f.separator = f:CreateTexture(nil, "ARTWORK")
  f.separator:SetColorTexture(0.4, 0.4, 0.4, 0.8)
  f.separator:SetHeight(1)

  f.rows = {}
  return f
end

-- Zeile holen bzw. anlegen (Name, Prozent, Vergleich, Hervorhebung)
local function getRow(f, i)
  local row = f.rows[i]
  if row then return row end
  row = {}
  row.highlight = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.highlight:SetColorTexture(1, 0.82, 0, 0.15)
  row.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetWidth(NAME_W)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.pct = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.pct:SetJustifyH("RIGHT")
  row.extra = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.extra:SetJustifyH("LEFT")
  row.extra:SetWordWrap(false)
  f.rows[i] = row
  return row
end

local function placeRow(f, row, y)
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
  row.pct:ClearAllPoints()
  row.pct:SetPoint("TOPRIGHT", f, "TOPLEFT", PCT_RIGHT, y)
  row.extra:ClearAllPoints()
  row.extra:SetPoint("TOPLEFT", f, "TOPLEFT", EXTRA_X, y - 1)
  row.extra:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  row.highlight:ClearAllPoints()
  row.highlight:SetPoint("TOPLEFT", f, "TOPLEFT", 6, y + 2)
  row.highlight:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  row.highlight:SetHeight(ROW)
end

local function setRowShown(row, shown)
  row.name:SetShown(shown)
  row.pct:SetShown(shown)
  row.extra:SetShown(shown)
  if not shown then row.highlight:Hide() end
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

-- Vergleichstext für eine Zeile: "Neuer Bestwert!" oder "Bestwert x"
local function compareText(best, newBest)
  if newBest then return "|cffffd100" .. L["STATS_NEW_BEST"] .. "|r" end
  if best then return "|cffaaaaaa" .. L["STATS_BEST"]:format(formatPct(best)) .. "|r" end
  return ""
end

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

    local y = -TOP
    local used = 0

    -- Abschnitte in Laufreihenfolge (Läufe vor 3.2.0 haben keine)
    for _, seg in ipairs(result.segments or {}) do
      used = used + 1
      local row = getRow(f, used)
      placeRow(f, row, y)
      setRowShown(row, true)
      -- Boss weiß hervorgehoben, Trash schlicht grau
      row.name:SetFontObject("GameFontHighlight")
      if seg.kind == "boss" then
        row.name:SetText("|cffffffff" .. (seg.name or "?") .. "|r")
      else
        row.name:SetText("|cff9d9d9d" .. L["STATS_TRASH_LINE"] .. "|r")
      end
      local v = seg.valid and seg.pct or nil
      row.pct:SetText(coloredPct(v))
      local extra = compareText(seg.best, seg.newBest)
      if not seg.valid and seg.pct ~= nil then
        extra = "|cffaaaaaa" .. L["STATS_TOO_SHORT_CATEGORY"] .. "|r"
      end
      row.extra:SetText(extra)
      row.highlight:SetShown(seg.newBest == true)
      y = y - ROW
    end

    -- Trennlinie
    if used > 0 then
      y = y - 4
      f.separator:ClearAllPoints()
      f.separator:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
      f.separator:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
      f.separator:Show()
      y = y - 6
    else
      f.separator:Hide()
    end

    -- Gesamt
    used = used + 1
    local total = getRow(f, used)
    placeRow(f, total, y)
    setRowShown(total, true)
    total.name:SetFontObject("GameFontNormal")
    total.name:SetText(L["STATS_TOTAL"])
    local tv = result.valid.total and result.pct.total or nil
    total.pct:SetText(coloredPct(tv))
    -- jeder Teil einzeln gefärbt, damit ein |r die Farbe der übrigen Teile nicht aufhebt
    local gray = "|cffaaaaaa"
    local extra = {}
    if result.newBest.total then
      extra[#extra + 1] = "|cffffd100" .. L["STATS_NEW_BEST"] .. "|r"
    elseif result.best.total then
      extra[#extra + 1] = gray .. L["STATS_BEST"]:format(formatPct(result.best.total)) .. "|r"
    end
    if result.avg.total then extra[#extra + 1] = gray .. L["STATS_AVG"]:format(formatPct(result.avg.total)) .. "|r" end
    if result.runs == 1 then
      extra[#extra + 1] = gray .. L["STATS_RUN_ONE"] .. "|r"
    elseif result.runs > 1 then
      extra[#extra + 1] = gray .. L["STATS_RUNS"]:format(result.runs) .. "|r"
    end
    total.extra:SetText(table.concat(extra, gray .. " · |r"))
    total.highlight:SetShown(result.newBest.total == true)
    y = y - ROW

    -- übrige Zeilen ausblenden
    for i = used + 1, #f.rows do setRowShown(f.rows[i], false) end

    -- Bosse · Trash · Kampfzeit
    if not f.summary then
      f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      f.summary:SetJustifyH("LEFT")
    end
    f.summary:ClearAllPoints()
    f.summary:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 2)
    f.summary:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    local bv = result.valid.boss and result.pct.boss or nil
    local trv = result.valid.trash and result.pct.trash or nil
    f.summary:SetText(L["STATS_SUMMARY"]:format(coloredPct(bv), coloredPct(trv), formatDuration(result.countedTime)))
    y = y - ROW - 4

    local note
    if not result.completed then
      note = "|cffff8020" .. L["STATS_ABORTED"] .. "|r"
    elseif not result.rated then
      note = "|cffff8020" .. L["STATS_NOT_RATED_SHORT"] .. "|r"
    elseif result.firstRun then
      note = "|cff33ff99" .. L["STATS_FIRST_RUN"] .. "|r"
    end
    if not f.note then
      f.note = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      f.note:SetJustifyH("LEFT")
    end
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 2)
    f.note:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.note:SetText(note or "")
    if note then y = y - ROW - 4 end

    f:SetHeight(-y + 14)
    f:Show()
  end)
  if not ok then
    ns.Debug:Error("Stats:ShowWindow", err)
    return false
  end
  return true
end
