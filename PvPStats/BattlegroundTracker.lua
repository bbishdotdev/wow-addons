-- PvPStats: Battleground lifecycle tracking and data collection
local _, PvPStats = ...

local Utils = PvPStats.Utils
local Tracker = {}
PvPStats.BattlegroundTracker = Tracker

-- ============================================================
-- State tracking
-- ============================================================
local pendingMatch = nil   -- match being built (queued but not finished)
local isCapturing = false  -- prevents double-capture on repeated score events
local lastCaptureTime = 0  -- timestamp of last successful capture (ghost match prevention)

-- No real BG ends in under this many seconds
local MIN_MATCH_DURATION = 60
-- Ignore "active" status events for this many seconds after a capture
local CAPTURE_COOLDOWN = 30

-- Known BG locations we track
local TRACKED_BGS = {
    ["Warsong Gulch"]  = true,
    ["Arathi Basin"]   = true,
    ["Alterac Valley"] = true,
}

-- ============================================================
-- Init (called after SavedVariables are ready)
-- ============================================================
function Tracker:Init()
    PvPStats:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", self.OnBattlefieldStatus)
    PvPStats:RegisterEvent("UPDATE_BATTLEFIELD_SCORE", self.OnBattlefieldScore)
    PvPStats:RegisterEvent("ZONE_CHANGED_NEW_AREA", self.OnZoneChanged)

    PvPStats:Print("BG tracker active.")
end

-- ============================================================
-- Detect solo vs group at queue time
-- Uses HOME category to check pre-made group (not the BG raid)
-- ============================================================
local function IsInPreMadeGroup()
    -- LE_PARTY_CATEGORY_HOME = 1 in modern clients
    local categoryHome = LE_PARTY_CATEGORY_HOME or 1

    if IsInGroup and IsInGroup(categoryHome) then
        return true
    end

    -- Fallback for older API
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        return true
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return true
    end

    return false
end

-- ============================================================
-- Find the active battlefield index for a tracked BG
-- ============================================================
local function FindActiveBattlefield()
    local maxId = GetMaxBattlefieldID and GetMaxBattlefieldID() or 3

    for i = 1, maxId do
        local status, mapName = GetBattlefieldStatus(i)
        if status and status ~= "none" and mapName and TRACKED_BGS[mapName] then
            return i, status, mapName
        end
    end
    return nil, nil, nil
end

-- ============================================================
-- UPDATE_BATTLEFIELD_STATUS handler
-- Fires on: queue, confirm popup, enter BG, leave BG
-- ============================================================
function Tracker.OnBattlefieldStatus()
    local idx, status, mapName = FindActiveBattlefield()
    if not idx then
        -- No active tracked BG — check if we had a pending match that got abandoned
        -- But skip during post-capture cooldown (leaving a completed BG triggers this)
        local timeSinceCapture = GetServerTime() - lastCaptureTime
        if pendingMatch and pendingMatch.startTime and not pendingMatch.endTime
           and timeSinceCapture >= CAPTURE_COOLDOWN then
            Tracker:FinalizeAbandonedMatch()
        end
        return
    end

    if status == "queued" then
        Tracker:OnQueued(mapName)
    elseif status == "active" then
        Tracker:OnActive(mapName)
    end
    -- "confirm" status = popup to enter, no action needed yet
end

-- ============================================================
-- Player queued for a BG
-- ============================================================
function Tracker:OnQueued(mapName)
    -- Don't overwrite if we already have a pending match for this BG
    if pendingMatch and pendingMatch.location == mapName then return end

    local grouped = IsInPreMadeGroup()

    pendingMatch = {
        location  = mapName,
        queueType = grouped and "group" or "solo",
        queueTime = GetServerTime(),
        result    = nil,
        startTime = nil,
        endTime   = nil,
    }

    PvPStats:Print("Queued for " .. mapName .. " (" .. pendingMatch.queueType .. ")")
end

-- ============================================================
-- Player entered an active BG
-- ============================================================
function Tracker:OnActive(mapName)
    -- Ignore stale "active" status that fires when leaving a completed BG
    local now = GetServerTime()
    if (now - lastCaptureTime) < CAPTURE_COOLDOWN then
        return
    end

    if not pendingMatch then
        -- Edge case: addon loaded mid-BG or missed queue event
        pendingMatch = {
            location  = mapName,
            queueType = "unknown",
            queueTime = nil,
        }
    end

    -- Only set startTime once
    if not pendingMatch.startTime then
        pendingMatch.startTime = now
        isCapturing = false
        PvPStats:Print(mapName .. " started.")

        -- Request initial scoreboard data
        RequestBattlefieldScoreData()
    end
end

-- ============================================================
-- UPDATE_BATTLEFIELD_SCORE handler
-- Fires when scoreboard data is refreshed. Check if BG ended.
-- ============================================================
function Tracker.OnBattlefieldScore()
    if not pendingMatch or not pendingMatch.startTime then return end
    if isCapturing then return end

    -- No real BG ends this fast — reject stale winner data
    local elapsed = GetServerTime() - pendingMatch.startTime
    if elapsed < MIN_MATCH_DURATION then return end

    local winner = GetBattlefieldWinner()
    if winner == nil then return end -- match still in progress

    -- BG is over — capture everything
    isCapturing = true
    Tracker:CaptureMatchResult(winner)
end

-- ============================================================
-- Capture the full match result and scoreboard
-- ============================================================
function Tracker:CaptureMatchResult(winner)
    local now = GetServerTime()
    local playerFactionId = Utils.GetPlayerFactionId()

    -- Determine result
    local result
    if winner == 255 then
        result = "draw"
    elseif playerFactionId ~= nil and winner == playerFactionId then
        result = "win"
    else
        result = "loss"
    end

    pendingMatch.endTime  = now
    pendingMatch.result   = result
    pendingMatch.duration = pendingMatch.startTime and (now - pendingMatch.startTime) or 0
    pendingMatch.date     = Utils.FormatDate(now)

    -- Capture BG-specific stat column names
    pendingMatch.bgStatColumns = self:CaptureBGStatColumns()

    -- Capture full scoreboard
    local scoreboard, playerStats = self:CaptureScoreboard(pendingMatch.bgStatColumns)
    pendingMatch.scoreboard  = scoreboard
    pendingMatch.playerStats = playerStats

    -- Assign ID and save
    pendingMatch.id = PvPStats:NextMatchId()
    table.insert(PvPStats.db.matches, pendingMatch)

    local location = Utils.ShortBGName(pendingMatch.location)
    PvPStats:Print(location .. " " .. Utils.ColorResult(result)
        .. " | " .. Utils.FormatDuration(pendingMatch.duration)
        .. " | " .. (playerStats and (playerStats.killingBlows .. " KB") or ""))

    -- Reset state and set cooldown to reject stale events on BG leave
    pendingMatch = nil
    isCapturing = false
    lastCaptureTime = GetServerTime()
end

-- ============================================================
-- Capture BG-specific stat column metadata
-- Returns: { "Flags Returned", "Flags Captured" } etc.
-- ============================================================
function Tracker:CaptureBGStatColumns()
    local columns = {}
    local idx = 1

    while true do
        local name = GetBattlefieldStatInfo(idx)
        if not name then break end
        table.insert(columns, name)
        idx = idx + 1
    end

    return columns
end

-- ============================================================
-- Capture full scoreboard data for all players
-- Returns: scoreboard table, player's own stats
-- ============================================================
function Tracker:CaptureScoreboard(bgStatColumns)
    local numScores = GetNumBattlefieldScores()
    if not numScores or numScores == 0 then return {}, nil end

    local scoreboard = {}
    local playerStats = nil
    local playerName = UnitName("player")
    local numBGStats = bgStatColumns and #bgStatColumns or 0

    for i = 1, numScores do
        local entry = self:CapturePlayerScore(i, numBGStats)
        if entry then
            table.insert(scoreboard, entry)

            -- Identify our own stats (plain match, handles server suffixes like "Name-Server")
            if entry.name and (entry.name == playerName or
               entry.name:find(playerName, 1, true) == 1) then
                playerStats = self:ExtractPlayerStats(entry, bgStatColumns)
            end
        end
    end

    return scoreboard, playerStats
end

-- ============================================================
-- Capture a single player's scoreboard entry
-- ============================================================
function Tracker:CapturePlayerScore(index, numBGStats)
    local name, killingBlows, honorableKills, deaths, honorGained,
          faction, _, race, class, classToken, damageDone, healingDone =
          GetBattlefieldScore(index)

    if not name then return nil end

    local entry = {
        name           = name,
        killingBlows   = killingBlows or 0,
        honorableKills = honorableKills or 0,
        deaths         = deaths or 0,
        honorGained    = honorGained or 0,
        faction        = faction,
        race           = race,
        class          = class,
        classToken     = classToken,
        damageDone     = damageDone or 0,
        healingDone    = healingDone or 0,
        bgStats        = {},
    }

    -- Capture BG-specific stats (flag caps, bases, etc.)
    for j = 1, numBGStats do
        entry.bgStats[j] = GetBattlefieldStatData(index, j) or 0
    end

    return entry
end

-- ============================================================
-- Extract the player's own stats into a flat structure
-- ============================================================
function Tracker:ExtractPlayerStats(entry, bgStatColumns)
    local stats = {
        killingBlows   = entry.killingBlows,
        honorableKills = entry.honorableKills,
        deaths         = entry.deaths,
        honorGained    = entry.honorGained,
        damageDone     = entry.damageDone,
        healingDone    = entry.healingDone,
    }

    -- Map BG-specific stats to named fields
    if bgStatColumns then
        for j, colName in ipairs(bgStatColumns) do
            local value = entry.bgStats[j] or 0
            -- Normalize column names to camelCase keys
            -- API returns varying names: "Flag Captures"/"Flags Captured", etc.
            local col = colName:lower()
            if col:find("flag") and col:find("capture") then
                stats.flagsCaptured = value
            elseif col:find("flag") and col:find("return") then
                stats.flagsReturned = value
            elseif col:find("bases") and col:find("assault") then
                stats.basesAssaulted = value
            elseif col:find("bases") and col:find("defend") then
                stats.basesDefended = value
            end
        end
    end

    return stats
end

-- ============================================================
-- Handle abandoned match (left BG before it ended)
-- ============================================================
function Tracker:FinalizeAbandonedMatch()
    if not pendingMatch then return end

    pendingMatch.endTime  = GetServerTime()
    pendingMatch.result   = "abandoned"
    pendingMatch.duration = pendingMatch.startTime and
        (pendingMatch.endTime - pendingMatch.startTime) or 0
    pendingMatch.date     = Utils.FormatDate(pendingMatch.endTime)

    pendingMatch.id = PvPStats:NextMatchId()
    table.insert(PvPStats.db.matches, pendingMatch)

    local location = Utils.ShortBGName(pendingMatch.location or "Unknown")
    PvPStats:Print(location .. " " .. Utils.ColorResult("abandoned"))

    pendingMatch = nil
    isCapturing = false
end

-- ============================================================
-- ZONE_CHANGED_NEW_AREA handler (backup BG detection)
-- ============================================================
function Tracker.OnZoneChanged()
    -- If we're in a tracked BG zone but missed the status event, pick it up
    local zone = GetZoneText()
    if zone and TRACKED_BGS[zone] and pendingMatch and not pendingMatch.startTime then
        pendingMatch.startTime = GetServerTime()
        pendingMatch.location = zone
        PvPStats:Print(zone .. " started (detected via zone change).")
        RequestBattlefieldScoreData()
    end
end
