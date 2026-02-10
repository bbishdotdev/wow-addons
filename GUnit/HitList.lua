local _, GUnit = ...
local Utils = GUnit.Utils

GUnit.HitList = {}
local HitList = GUnit.HitList

local HIT_MODE_ONE_TIME = "one_time"
local HIT_MODE_KOS = "kos"
local HIT_STATUS_ACTIVE = "active"
local HIT_STATUS_COMPLETED = "completed"
local BOUNTY_MODE_NONE = "none"
local BOUNTY_MODE_FIRST = "first_kill"
local BOUNTY_MODE_INFINITE = "infinite"
local BOUNTY_STATUS_OPEN = "open"
local BOUNTY_STATUS_CLAIMED = "claimed"

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
    if status ~= HIT_STATUS_ACTIVE and status ~= HIT_STATUS_COMPLETED then
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
    local myFaction = UnitFactionGroup("player")

    if faction and myFaction and faction == myFaction then
        return nil, "Same faction."
    end

    target.validated = true
    target.classToken = englishClass
    target.race = raceName
    target.faction = faction
    target.updatedAt = Utils.Now()
    return target
end

function HitList:ApplyKill(targetName, killerName, zone, ts)
    local target = self:Get(targetName)
    if not target then return nil end

    local now = ts or Utils.Now()
    local killer = Utils.NormalizeName(killerName) or killerName or "Unknown"

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
    target.killCount = (target.killCount or 0) + 1

    if target.hitMode == HIT_MODE_ONE_TIME and target.hitStatus == HIT_STATUS_ACTIVE then
        target.hitStatus = HIT_STATUS_COMPLETED
    end

    if target.bountyAmount and target.bountyAmount > 0 then
        target.bountyClaims = target.bountyClaims or {}
        local existing = target.bountyClaims[killer] or { totalCopper = 0, claimCount = 0, lastClaimAt = 0 }
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

