-- PvPStats: Utility functions
local _, PvPStats = ...

PvPStats.Utils = {}
local Utils = PvPStats.Utils

-- Format seconds into "Xm Ys" or "Xh Ym" for longer durations
function Utils.FormatDuration(seconds)
    if not seconds or seconds < 0 then return "N/A" end

    seconds = math.floor(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm %ds", mins, secs)
end

-- Format a server timestamp into a readable date string
function Utils.FormatDate(timestamp)
    if not timestamp then return "N/A" end
    return date("%b %d, %Y", timestamp)
end

-- Format a server timestamp into a readable time string
function Utils.FormatTime(timestamp)
    if not timestamp then return "N/A" end
    return date("%H:%M", timestamp)
end

-- Format a server timestamp into date + time
function Utils.FormatDateTime(timestamp)
    if not timestamp then return "N/A" end
    return date("%b %d %H:%M", timestamp)
end

-- Format large numbers with comma separators (e.g. 45230 -> "45,230")
function Utils.FormatNumber(n)
    if not n then return "0" end

    n = tonumber(n)
    if not n then return "0" end
    n = math.floor(n)
    if n < 1000 then return tostring(n) end

    local formatted = tostring(n)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

-- Get the player's faction as an integer (0 = Horde, 1 = Alliance)
function Utils.GetPlayerFactionId()
    local _, faction = UnitFactionGroup("player")
    if faction == "Horde" then return 0 end
    if faction == "Alliance" then return 1 end
    return nil
end

-- Colorize text for win/loss/draw
function Utils.ColorResult(result)
    if result == "win" then
        return "|cff00ff00Win|r"
    elseif result == "loss" then
        return "|cffff0000Loss|r"
    elseif result == "draw" then
        return "|cffffff00Draw|r"
    elseif result == "abandoned" then
        return "|cff888888Left|r"
    end
    return result or "N/A"
end

-- Short BG name for display
Utils.BG_SHORT_NAMES = {
    ["Warsong Gulch"]  = "WSG",
    ["Arathi Basin"]   = "AB",
    ["Alterac Valley"] = "AV",
}

function Utils.ShortBGName(location)
    return Utils.BG_SHORT_NAMES[location] or location
end
