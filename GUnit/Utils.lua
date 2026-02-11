local _, GUnit = ...

GUnit.Utils = {}
local Utils = GUnit.Utils

local SERIAL_SEP = "\031"

function Utils.NormalizeName(name)
    if not name then return nil end
    name = strtrim(name)
    if name == "" then return nil end

    local simpleName = name:match("^[^%-]+") or name
    simpleName = simpleName:lower()
    return simpleName:gsub("^%l", string.upper)
end

function Utils.PlayerName()
    return UnitName("player") or "Unknown"
end

function Utils.InGuild()
    return IsInGuild and IsInGuild() or (GetGuildInfo("player") ~= nil)
end

function Utils.GuildName()
    if GetGuildInfo then
        return GetGuildInfo("player")
    end
    return nil
end

function Utils.CopperFromGoldString(value)
    local amount = tonumber(value)
    if not amount then return nil end
    if amount < 0 then return nil end
    return math.floor(amount * 10000 + 0.5)
end

function Utils.GoldStringFromCopper(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return "0g" end
    return string.format("%dg", math.floor(copper / 10000))
end

function Utils.IsSubmitter(target, playerName)
    if not target or not target.submitter then return false end
    return target.submitter == (playerName or Utils.PlayerName())
end

function Utils.Escape(value)
    value = tostring(value or "")
    value = value:gsub("%%", "%%25")
    value = value:gsub("\029", "%%1D")
    value = value:gsub(SERIAL_SEP, "%%1F")
    return value
end

function Utils.Unescape(value)
    value = tostring(value or "")
    value = value:gsub("%%1F", SERIAL_SEP)
    value = value:gsub("%%1D", "\029")
    value = value:gsub("%%25", "%%")
    return value
end

function Utils.SerializeParts(parts)
    local encoded = {}
    for i = 1, #parts do
        encoded[i] = Utils.Escape(parts[i])
    end
    return table.concat(encoded, SERIAL_SEP)
end

function Utils.DeserializeParts(payload)
    local out = {}
    if not payload or payload == "" then return out end
    for value in string.gmatch(payload, "([^" .. SERIAL_SEP .. "]*)") do
        if value == "" and #out > 0 and #out >= string.len(payload) then
            break
        end
        table.insert(out, Utils.Unescape(value))
    end
    return out
end

function Utils.SendGuildChat(message)
    if Utils.InGuild() and SendChatMessage then
        SendChatMessage(message, "GUILD")
    end
end

function Utils.ZoneName()
    return GetRealZoneText() or "Unknown Zone"
end

function Utils.Now()
    return time()
end

function Utils.ClassColorName(name, classToken)
    if not classToken then return name end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if not color then return name end
    return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name)
end
