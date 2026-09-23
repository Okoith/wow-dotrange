local ADDON_NAME, ns = ...

-- Debug-Log in der SavedVariable DotRangeDebugLog (Ringpuffer), übernommen aus OwnDPS.
-- Regel: Secret Values werden nie gespeichert, nur als "<SECRET>" markiert.

local Debug = {}
ns.Debug = Debug

local MAX_ENTRIES = 5000
local ERROR_REPEAT_SECONDS = 5

local issecret = issecretvalue or function() return false end

local loginNo = 0
local lastErrors = {}   -- Meldungstext -> Zeitpunkt, drosselt identische Fehler

-- Wandelt einen Wert in etwas Speicherbares um. Secret Values -> "<SECRET>".
local function S(v)
  if issecret(v) then return "<SECRET>" end
  if v == nil then return "nil" end
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  return "<" .. t .. ">"
end
Debug.S = S

function Debug:Init()
  if type(DotRangeDebugLog) ~= "table" then DotRangeDebugLog = {} end
  local log = DotRangeDebugLog
  if type(log.entries) ~= "table" then log.entries = {} end
  log.logins = (tonumber(log.logins) or 0) + 1
  loginNo = log.logins
end

function Debug:IsEnabled()
  return ns.db ~= nil and ns.db.global.debug == true
end

function Debug:SetEnabled(enabled)
  ns.db.global.debug = enabled and true or false
  if enabled then self:LogMeta() end
end

function Debug:Count()
  local log = DotRangeDebugLog
  return (log and log.entries) and #log.entries or 0
end

function Debug:Clear()
  local log = DotRangeDebugLog
  if log and log.entries then wipe(log.entries) end
end

-- data: flache Tabelle mit festen String-Schlüsseln; jeder Wert wird mit S() bereinigt.
function Debug:Add(kind, data)
  if not self:IsEnabled() then return end
  local log = DotRangeDebugLog
  if not log or not log.entries then return end

  local entry = {}
  if data then
    for k, v in pairs(data) do entry[k] = S(v) end
  end
  entry.kind = kind
  entry.t = math.floor(GetTime() * 100 + 0.5) / 100
  entry.time = date("%H:%M:%S")
  entry.login = loginNo
  entry.combat = InCombatLockdown() and true or false

  local e = log.entries
  e[#e + 1] = entry
  while #e > MAX_ENTRIES do table.remove(e, 1) end
end

-- Fehler aus pcall. Gleiche Meldungen höchstens alle paar Sekunden.
function Debug:Error(where, err)
  if not self:IsEnabled() then return end
  local msg = S(err)
  if type(msg) ~= "string" then msg = tostring(msg) end
  local key = where .. ":" .. msg
  local now = GetTime()
  if lastErrors[key] and now - lastErrors[key] < ERROR_REPEAT_SECONDS then return end
  lastErrors[key] = now
  self:Add("error", { where = where, err = msg })
end

-- Version, Build, Sprache, Klasse, Spezialisierung, bekannte Zauber
function Debug:LogMeta()
  if not self:IsEnabled() then return end
  local gameVersion, build, buildDate, toc = GetBuildInfo()
  local specID, specName = ns.Spells:GetSpec()
  local out = {
    addonVersion = ns.VERSION,
    gameVersion = gameVersion, build = build, buildDate = buildDate, toc = toc,
    locale = GetLocale(),
    class = ns.Spells.class,
    specID = specID,
    specName = specName,
    profile = ns.db:GetCurrentProfile(),
    hasIsSecretValue = issecretvalue ~= nil,
    hasIsSpellKnown = (C_SpellBook and C_SpellBook.IsSpellKnown) ~= nil,
  }
  self:Add("meta", out)
  self:LogSpells("meta")
end

-- Bekannte Zauber aus der Liste
function Debug:LogSpells(reason)
  if not self:IsEnabled() then return end
  local out, signature = ns.Spells:KnownInfo()
  local specID, specName = ns.Spells:GetSpec()
  out.reason = reason
  out.known = signature
  out.specID = specID
  out.specName = specName
  self:Add("spells", out)
end

function Debug:LogInstance(extra)
  if not self:IsEnabled() then return end
  local out = extra or {}
  local ok, name, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID = pcall(GetInstanceInfo)
  if ok then
    out.instName = name
    out.instType = instanceType
    out.diffID = difficultyID
    out.diffName = difficultyName
    out.maxPlayers = maxPlayers
    out.instID = instanceID
  end
  out.groupSize = GetNumGroupMembers()
  self:Add("instance", out)
end
