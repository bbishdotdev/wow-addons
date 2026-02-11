local _, GUnit = ...
local Utils = GUnit.Utils

GUnit.HitList = {}
local HitList = GUnit.HitList

local HIT_MODE_ONE_TIME = "one_time"
local HIT_MODE_KOS = "kos"
local HIT_STATUS_ACTIVE = "active"
local HIT_STATUS_COMPLETED = "completed"
local HIT_STATUS_CLOSED = "closed"
local BOUNTY_MODE_NONE = "none"
local BOUNTY_MODE_FIRST = "first_kill"
local BOUNTY_MODE_INFINITE = "infinite"
local BOUNTY_STATUS_OPEN = "open"
local BOUNTY_STATUS_CLAIMED = "claimed"

local function SafePlayerLocationForUnit(unit)
    if not PlayerLocation or not PlayerLocation.CreateFromUnit then
        return nil
    end
    local ok, location = pcall(PlayerLocation.CreateFromUnit, PlayerLocation, unit)
    if ok then
        return location
    end
    return nil
end

local function CaptureUnitRaceMetadata(unit)
    local location = SafePlayerLocationForUnit(unit)
    local raceId = nil
    local sex = nil

    if location and C_PlayerInfo then
        if C_PlayerInfo.GetRace then
            local okRace, value = pcall(C_PlayerInfo.GetRace, location)
            if okRace then
                raceId = tonumber(value)
            end
        end
        if C_PlayerInfo.GetSex then
            local okSex, value = pcall(C_PlayerInfo.GetSex, location)
            if okSex then
                sex = tonumber(value)
            end
        end
    end

    return raceId, sex
end

local function CloneEntry(entry)
    local out = {}
    for k, v in pairs(entry) do
        out[k] = v
    end
    return out
end

local function EnsureTarget(name, actorName, ts)
    if not GUnit.db.targets[name] then
        GUnit.db.targets[name] = {
            name = name,
            submitter = actorName,
            guildName = Utils.GuildName(),
            reason = "",
            bountyAmount = 0,
            hitMode = HIT_MODE_ONE_TIME,
            hitStatus = HIT_STATUS_ACTIVE,
            bountyMode = BOUNTY_MODE_NONE,
            bountyStatus = BOUNTY_STATUS_OPEN,
            createdAt = ts,
            updatedAt = ts,
            validated = false,
            classToken = nil,
            race = nil,
            raceId = nil,
            sex = nil,
            faction = nil,
            killCount = 0,
            kills = {},
            bountyClaims = {},
        }
    end
    return GUnit.db.targets[name]
end

function HitList:Constants()
    return {
        HIT_MODE_ONE_TIME = HIT_MODE_ONE_TIME,
        HIT_MODE_KOS = HIT_MODE_KOS,
        HIT_STATUS_ACTIVE = HIT_STATUS_ACTIVE,
        HIT_STATUS_COMPLETED = HIT_STATUS_COMPLETED,
        HIT_STATUS_CLOSED = HIT_STATUS_CLOSED,
        BOUNTY_MODE_NONE = BOUNTY_MODE_NONE,
        BOUNTY_MODE_FIRST = BOUNTY_MODE_FIRST,
        BOUNTY_MODE_INFINITE = BOUNTY_MODE_INFINITE,
        BOUNTY_STATUS_OPEN = BOUNTY_STATUS_OPEN,
        BOUNTY_STATUS_CLAIMED = BOUNTY_STATUS_CLAIMED,
    }
end

function HitList:Get(name)
    local normalized = Utils.NormalizeName(name)
    if not normalized then return nil end
    return GUnit.db.targets[normalized]
end

function HitList:GetAll()
    return GUnit.db.targets
end

function HitList:SortedNames()
    local names = {}
    for name in pairs(GUnit.db.targets) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function HitList:SortedNamesForCurrentGuild()
    local guildName = Utils.GuildName()
    local names = {}
    for name, target in pairs(GUnit.db.targets) do
        if target.guildName == guildName then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function HitList:GetAllForCurrentGuild()
    local guildName = Utils.GuildName()
    local out = {}
    for name, target in pairs(GUnit.db.targets) do
        if target.guildName == guildName then
            out[name] = target
        end
    end
    return out
end

function HitList:CanMutate(target, actorName)
    return target and Utils.IsSubmitter(target, actorName)
end

function HitList:CreateOrTouch(name, actorName, reason, ts)
    local normalized = Utils.NormalizeName(name)
    if not normalized then
        return nil, "Invalid target name."
    end

    local now = ts or Utils.Now()
    local target = EnsureTarget(normalized, actorName, now)
    target.updatedAt = now

    if reason and reason ~= "" and Utils.IsSubmitter(target, actorName) then
        target.reason = reason
    end

    return target
end

function HitList:Delete(name)
    local normalized = Utils.NormalizeName(name)
    if not normalized then return false end
    if not GUnit.db.targets[normalized] then return false end
    GUnit.db.targets[normalized] = nil
    return true
end

function HitList:SetReason(name, reason, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit this hit." end
    target.reason = reason or ""
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetBountyAmount(name, bountyAmount, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit this hit." end
    target.bountyAmount = math.max(0, tonumber(bountyAmount) or 0)
    if target.bountyAmount <= 0 then
        target.bountyMode = BOUNTY_MODE_NONE
        target.bountyStatus = BOUNTY_STATUS_OPEN
    end
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetHitMode(name, mode, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit hit mode." end
    if mode ~= HIT_MODE_ONE_TIME and mode ~= HIT_MODE_KOS then
        return nil, "Invalid hit mode."
    end

    target.hitMode = mode
    if mode == HIT_MODE_KOS and target.hitStatus == HIT_STATUS_COMPLETED then
        target.hitStatus = HIT_STATUS_ACTIVE
    end
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetBountyMode(name, mode, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can edit bounty mode." end
    if mode ~= BOUNTY_MODE_NONE and mode ~= BOUNTY_MODE_FIRST and mode ~= BOUNTY_MODE_INFINITE then
        return nil, "Invalid bounty mode."
    end

    target.bountyMode = mode
    if mode == BOUNTY_MODE_FIRST then
        target.bountyStatus = BOUNTY_STATUS_OPEN
    else
        target.bountyStatus = BOUNTY_STATUS_OPEN
    end
    if mode == BOUNTY_MODE_NONE then
        target.bountyAmount = 0
    end
    target.updatedAt = Utils.Now()
    return target
end

function HitList:SetHitStatus(name, status, actorName)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not self:CanMutate(target, actorName) then return nil, "Only submitter can change status." end
    if status ~= HIT_STATUS_ACTIVE and status ~= HIT_STATUS_COMPLETED and status ~= HIT_STATUS_CLOSED then
        return nil, "Invalid hit status."
    end
    target.hitStatus = status
    target.updatedAt = Utils.Now()
    return target
end

function HitList:ShouldAnnounceSighting(target)
    if not target then return false end
    return target.hitStatus == HIT_STATUS_ACTIVE
end

function HitList:UpsertFromComm(payload)
    local normalized = Utils.NormalizeName(payload.name)
    if not normalized then return nil end
    local ts = tonumber(payload.updatedAt) or Utils.Now()
    local submitter = Utils.NormalizeName(payload.submitter) or payload.submitter or "Unknown"

    local target = EnsureTarget(normalized, submitter, ts)

    -- Guild channel is authoritative — always update guildName
    if payload.guildName and payload.guildName ~= "" then
        target.guildName = payload.guildName
    end

    if target.updatedAt and target.updatedAt > ts then
        return target
    end

    target.submitter = submitter
    target.reason = payload.reason or target.reason or ""
    target.bountyAmount = tonumber(payload.bountyAmount) or target.bountyAmount or 0
    target.hitMode = payload.hitMode or target.hitMode or HIT_MODE_ONE_TIME
    target.hitStatus = payload.hitStatus or target.hitStatus or HIT_STATUS_ACTIVE
    target.bountyMode = payload.bountyMode or target.bountyMode or BOUNTY_MODE_NONE
    target.bountyStatus = payload.bountyStatus or target.bountyStatus or BOUNTY_STATUS_OPEN
    target.validated = payload.validated == "1" or payload.validated == true or target.validated
    target.classToken = payload.classToken or target.classToken
    target.race = payload.race or target.race
    target.faction = payload.faction or target.faction
    target.raceId = tonumber(payload.raceId) or target.raceId
    target.sex = tonumber(payload.sex) or target.sex
    target.createdAt = tonumber(payload.createdAt) or target.createdAt
    target.updatedAt = ts
    target.killCount = tonumber(payload.killCount) or target.killCount or 0
    target.kills = target.kills or {}
    target.bountyClaims = target.bountyClaims or {}
    return target
end

function HitList:UpdateValidationFromUnit(name, unit)
    local target = self:Get(name)
    if not target then return nil, "Target not found." end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil, "Unit invalid." end

    local unitName = Utils.NormalizeName(UnitName(unit))
    if unitName ~= target.name then return nil, "Unit name mismatch." end

    local _, englishClass = UnitClass(unit)
    local raceName = UnitRace(unit)
    local faction = UnitFactionGroup(unit)
    local raceId, sex = CaptureUnitRaceMetadata(unit)
    local myFaction = UnitFactionGroup("player")

    if faction and myFaction and faction == myFaction then
        return nil, "Same faction."
    end

    target.validated = true
    target.classToken = englishClass
    target.race = raceName
    target.raceId = raceId or target.raceId
    target.sex = sex or target.sex
    target.faction = faction
    target.updatedAt = Utils.Now()
    return target
end

function HitList:ApplyKill(targetName, killerName, zone, ts)
    local target = self:Get(targetName)
    if not target then
        GUnit:Print("[DEBUG] ApplyKill: target not found for '" .. tostring(targetName) .. "'")
        return nil
    end

    local now = ts or Utils.Now()
    local killer = Utils.NormalizeName(killerName) or killerName or "Unknown"

    local prevCount = target.killCount or 0
    target.kills = target.kills or {}
    table.insert(target.kills, {
        killer = killer,
        ts = now,
        zone = zone or Utils.ZoneName(),
        submitterAtTime = target.submitter,
        proof = {
            auto = true,
            ts = now,
            zone = zone or Utils.ZoneName(),
        },
    })
    target.killCount = prevCount + 1
    GUnit:Print("[DEBUG] ApplyKill: " .. targetName .. " killCount " .. prevCount .. " -> " .. target.killCount)

    if target.hitMode == HIT_MODE_ONE_TIME and target.hitStatus == HIT_STATUS_ACTIVE then
        target.hitStatus = HIT_STATUS_COMPLETED
    end

    if target.bountyAmount and target.bountyAmount > 0 then
        target.bountyClaims = target.bountyClaims or {}
        local existing = target.bountyClaims[killer] or { totalCopper = 0, paidCopper = 0, claimCount = 0, lastClaimAt = 0 }
        existing.paidCopper = existing.paidCopper or 0
        if target.bountyMode == BOUNTY_MODE_FIRST and target.bountyStatus ~= BOUNTY_STATUS_CLAIMED then
            existing.totalCopper = existing.totalCopper + target.bountyAmount
            existing.claimCount = existing.claimCount + 1
            existing.lastClaimAt = now
            target.bountyClaims[killer] = existing
            target.bountyStatus = BOUNTY_STATUS_CLAIMED
        elseif target.bountyMode == BOUNTY_MODE_INFINITE then
            existing.totalCopper = existing.totalCopper + target.bountyAmount
            existing.claimCount = existing.claimCount + 1
            existing.lastClaimAt = now
            target.bountyClaims[killer] = existing
        end
    end

    target.updatedAt = now
    return CloneEntry(target)
end

function HitList:RecordBountyPayment(targetName, killerName, copperPaid)
    local target = self:Get(targetName)
    if not target then return nil, "Target not found." end

    local killer = Utils.NormalizeName(killerName)
    if not killer then return nil, "Invalid killer name." end

    target.bountyClaims = target.bountyClaims or {}
    local claim = target.bountyClaims[killer]
    if not claim then return nil, "No bounty claim found for " .. killer end

    claim.paidCopper = claim.paidCopper or 0
    claim.paidCopper = math.min(claim.totalCopper, claim.paidCopper + copperPaid)
    target.updatedAt = Utils.Now()
    return target
end

function HitList:GetBountyOwed(targetName, killerName)
    local target = self:Get(targetName)
    if not target then return 0 end

    local killer = Utils.NormalizeName(killerName)
    if not killer then return 0 end

    local claim = target.bountyClaims and target.bountyClaims[killer]
    if not claim then return 0 end

    return math.max(0, (claim.totalCopper or 0) - (claim.paidCopper or 0))
end

local FIELD_SEP = ";"
local EXPORT_FIELDS = {
    "name", "submitter", "guildName", "reason", "bountyAmount",
    "hitMode", "hitStatus", "bountyMode", "bountyStatus",
    "validated", "classToken", "race", "faction",
    "raceId", "sex", "createdAt", "updatedAt", "killCount",
}

local LEGACY_EXPORT_FIELDS = {
    "name", "submitter", "guildName", "reason", "bountyAmount",
    "hitMode", "hitStatus", "bountyMode", "bountyStatus",
    "validated", "classToken", "race", "faction",
    "createdAt", "updatedAt", "killCount",
}

function HitList:ExportCurrentGuild()
    local targets = self:GetAllForCurrentGuild()
    local lines = {}
    for _, target in pairs(targets) do
        local fields = {}
        for _, key in ipairs(EXPORT_FIELDS) do
            local val = target[key]
            if key == "validated" then
                val = val and "1" or "0"
            end
            table.insert(fields, tostring(val or ""))
        end
        table.insert(lines, table.concat(fields, FIELD_SEP))
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

local function SplitFields(line)
    local fields = {}
    local padded = line .. FIELD_SEP
    for field in padded:gmatch("([^" .. FIELD_SEP .. "]*)" .. FIELD_SEP) do
        table.insert(fields, field)
    end
    return fields
end

function HitList:ImportFromString(data)
    if not data or data == "" then return 0 end
    local count = 0
    for line in data:gmatch("[^\n]+") do
        local trimmed = strtrim(line)
        if trimmed ~= "" then
            local fields = SplitFields(trimmed)
            local schema = nil
            if #fields >= #EXPORT_FIELDS then
                schema = EXPORT_FIELDS
            elseif #fields >= #LEGACY_EXPORT_FIELDS then
                schema = LEGACY_EXPORT_FIELDS
            end
            if schema then
                local payload = {}
                for i, key in ipairs(schema) do
                    payload[key] = fields[i]
                end
                if payload.name and payload.name ~= "" then
                    self:UpsertFromComm(payload)
                    count = count + 1
                end
            end
        end
    end
    return count
end

