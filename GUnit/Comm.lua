local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList

GUnit.Comm = {}
local Comm = GUnit.Comm

local PREFIX = "GUNIT"
local PAIR_SEP = "\031"
local KV_SEP = "\029"

local function RegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
end

local function SendAddon(channel, payload)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, channel)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, payload, channel)
    end
end

local function EncodeMap(map)
    local parts = {}
    for key, value in pairs(map) do
        table.insert(parts, Utils.Escape(key) .. KV_SEP .. Utils.Escape(value))
    end
    return table.concat(parts, PAIR_SEP)
end

local function DecodeMap(payload)
    local out = {}
    for part in string.gmatch(payload or "", "([^" .. PAIR_SEP .. "]+)") do
        local key, value = string.match(part, "^(.-)" .. KV_SEP .. "(.*)$")
        if key then
            out[Utils.Unescape(key)] = Utils.Unescape(value or "")
        end
    end
    return out
end

local function ActionPayload(action, map)
    map = map or {}
    map.action = action
    return EncodeMap(map)
end

function Comm:BroadcastUpsert(target)
    if not target or not Utils.InGuild() then return end
    local payload = ActionPayload("UPSERT", {
        name = target.name,
        submitter = target.submitter,
        reason = target.reason or "",
        bountyAmount = target.bountyAmount or 0,
        hitMode = target.hitMode or "one_time",
        hitStatus = target.hitStatus or "active",
        bountyMode = target.bountyMode or "none",
        bountyStatus = target.bountyStatus or "open",
        validated = target.validated and "1" or "0",
        classToken = target.classToken or "",
        race = target.race or "",
        faction = target.faction or "",
        createdAt = target.createdAt or Utils.Now(),
        updatedAt = target.updatedAt or Utils.Now(),
        killCount = target.killCount or 0,
    })
    SendAddon("GUILD", payload)
end

function Comm:BroadcastDelete(targetName)
    if not Utils.InGuild() then return end
    local payload = ActionPayload("DELETE", {
        name = targetName,
        updatedAt = Utils.Now(),
    })
    SendAddon("GUILD", payload)
end

function Comm:BroadcastKill(targetName, killerName, zoneName, ts)
    if not Utils.InGuild() then return end
    local payload = ActionPayload("KILL", {
        name = targetName,
        killer = killerName,
        zone = zoneName or Utils.ZoneName(),
        ts = ts or Utils.Now(),
    })
    SendAddon("GUILD", payload)
end

local function HandleUpsert(data)
    if not data.name then return end
    HitList:UpsertFromComm(data)
    GUnit:NotifyDataChanged()
end

local function HandleDelete(data)
    if not data.name then return end
    HitList:Delete(data.name)
    GUnit:NotifyDataChanged()
end

local function HandleKill(data)
    if not data.name then return end
    local target = HitList:ApplyKill(data.name, data.killer, data.zone, tonumber(data.ts))
    if target then
        GUnit:NotifyDataChanged()
    end
end

local function OnAddonMessage(_, prefix, payload, _, sender)
    if prefix ~= PREFIX then return end
    if Utils.NormalizeName(sender) == Utils.NormalizeName(Utils.PlayerName()) then return end
    local data = DecodeMap(payload)
    local action = data.action
    if action == "UPSERT" then
        HandleUpsert(data)
    elseif action == "DELETE" then
        HandleDelete(data)
    elseif action == "KILL" then
        HandleKill(data)
    end
end

function Comm:Init()
    RegisterPrefix()
    GUnit:RegisterEvent("CHAT_MSG_ADDON", OnAddonMessage)
end
