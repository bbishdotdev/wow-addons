-- PvPStats: Core initialization, event dispatch, slash command
local ADDON_NAME, PvPStats = ...

local Utils = PvPStats.Utils

PvPStats.VERSION = "0.1.0"
PvPStats.PRINT_PREFIX = "|cff00ccff[PvPStats]|r "

-- Default database structure
local DB_DEFAULTS = {
    matches = {},
    nextId = 1,
}

-- ============================================================
-- Addon print helper
-- ============================================================
function PvPStats:Print(msg)
    print(self.PRINT_PREFIX .. msg)
end

-- ============================================================
-- Event system
-- ============================================================
local eventFrame = CreateFrame("Frame")
local registeredHandlers = {} -- event -> list of handler functions

function PvPStats:RegisterEvent(event, handler)
    if not registeredHandlers[event] then
        registeredHandlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(registeredHandlers[event], handler)
end

function PvPStats:UnregisterEvent(event, handler)
    local handlers = registeredHandlers[event]
    if not handlers then return end

    for i = #handlers, 1, -1 do
        if handlers[i] == handler then
            table.remove(handlers, i)
        end
    end

    if #handlers == 0 then
        eventFrame:UnregisterEvent(event)
        registeredHandlers[event] = nil
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = registeredHandlers[event]
    if not handlers then return end

    for _, handler in ipairs(handlers) do
        local ok, err = pcall(handler, event, ...)
        if not ok then
            print("|cffff0000[PvPStats ERROR]|r " .. event .. ": " .. tostring(err))
        end
    end
end)

-- ============================================================
-- SavedVariables initialization on login
-- ============================================================
local function OnPlayerLogin()
    if not PvPStatsDB then
        PvPStatsDB = {}
    end

    for key, default in pairs(DB_DEFAULTS) do
        if PvPStatsDB[key] == nil then
            PvPStatsDB[key] = default
        end
    end

    PvPStats.db = PvPStatsDB

    PvPStats:Print("v" .. PvPStats.VERSION .. " loaded. Type /pvpstats to open.")

    if PvPStats.BattlegroundTracker then
        PvPStats.BattlegroundTracker:Init()
    end
end

PvPStats:RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)

-- ============================================================
-- Generate a unique match ID
-- ============================================================
function PvPStats:NextMatchId()
    local id = self.db.nextId
    self.db.nextId = id + 1
    return id
end

-- ============================================================
-- Confirmation dialogs for destructive actions
-- ============================================================
StaticPopupDialogs["PVPSTATS_CONFIRM_RESET"] = {
    text = "Delete ALL PvPStats match data?\n\nThis cannot be undone.",
    button1 = "Delete All",
    button2 = "Cancel",
    OnAccept = function()
        PvPStatsDB.matches = {}
        PvPStatsDB.nextId = 1
        PvPStats:Print("All data cleared.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Stash the pending delete info so the popup callback can use it
local pendingDelete = nil

StaticPopupDialogs["PVPSTATS_CONFIRM_DELETE"] = {
    text = "Delete this match?\n\n%s\n\nThis cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function()
        if not pendingDelete then return end
        local removed = table.remove(PvPStats.db.matches, pendingDelete.realIdx)
        if removed then
            PvPStats:Print("Deleted: " .. (removed.location or "Unknown"))
        end
        pendingDelete = nil
    end,
    OnCancel = function()
        pendingDelete = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================
-- Helpers for sorted match list (newest first)
-- ============================================================
local function GetSortedMatchIndices()
    local sorted = {}
    for i, m in ipairs(PvPStats.db.matches) do
        table.insert(sorted, { idx = i, match = m, time = m.endTime or m.startTime or 0 })
    end
    table.sort(sorted, function(a, b) return a.time > b.time end)
    return sorted
end

local function FormatMatchSummary(m)
    local dur = m.duration and Utils.FormatDuration(m.duration) or "?"
    return Utils.ShortBGName(m.location)
        .. " " .. Utils.ColorResult(m.result)
        .. " " .. dur
        .. " " .. Utils.FormatDateTime(m.endTime or m.startTime)
end

-- ============================================================
-- Slash command
-- ============================================================
SLASH_PVPSTATS1 = "/pvpstats"
SlashCmdList["PVPSTATS"] = function(msg)
    local ok, err = pcall(function()
        msg = strtrim(msg or "")

        if msg == "reset" then
            local count = PvPStats.db and #PvPStats.db.matches or 0
            if count == 0 then
                PvPStats:Print("Nothing to reset.")
                return
            end
            StaticPopup_Show("PVPSTATS_CONFIRM_RESET")
            return
        end

        if msg == "count" then
            local count = #PvPStats.db.matches
            PvPStats:Print(count .. " match(es) recorded.")
            return
        end

        -- Delete a specific match by list position (newest first)
        local deleteIdx = msg:match("^delete%s+(%d+)$")
        if deleteIdx then
            deleteIdx = tonumber(deleteIdx)
            local sorted = GetSortedMatchIndices()

            if deleteIdx < 1 or deleteIdx > #sorted then
                PvPStats:Print("Invalid index. Use 1-" .. #sorted)
                return
            end

            local entry = sorted[deleteIdx]
            local summary = FormatMatchSummary(entry.match)

            pendingDelete = { realIdx = entry.idx }
            StaticPopup_Show("PVPSTATS_CONFIRM_DELETE", summary)
            return
        end

        -- List recent matches for easy delete targeting
        if msg == "list" then
            local matches = PvPStats.db.matches
            if #matches == 0 then
                PvPStats:Print("No matches recorded.")
                return
            end

            local sorted = GetSortedMatchIndices()

            PvPStats:Print("Recent matches (use /pvpstats delete #):")
            for i, entry in ipairs(sorted) do
                if i > 10 then break end
                PvPStats:Print("  " .. i .. ") " .. FormatMatchSummary(entry.match))
            end
            return
        end

        -- Default: toggle UI
        if PvPStats.UI then
            PvPStats.UI:Toggle()
        else
            PvPStats:Print("UI not loaded.")
        end
    end)

    if not ok then
        print("|cffff0000[PvPStats ERROR]|r /pvpstats: " .. tostring(err))
    end
end
