local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm

GUnit.Tracking = {}
local Tracking = GUnit.Tracking

local SIGHTING_THROTTLE_SECONDS = 60
local sightingThrottleByName = {}

local function SendGuildMessage(message)
    Utils.SendGuildChat(message)
end

local function LocalAlert(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
    end
    GUnit:Print(message)
end

local function ShouldThrottleSighting(name, now)
    local lastSeen = sightingThrottleByName[name] or 0
    if now - lastSeen < SIGHTING_THROTTLE_SECONDS then
        return true
    end
    sightingThrottleByName[name] = now
    return false
end

local function ValidateTargetUnit(unit, targetName)
    local updated, err = HitList:UpdateValidationFromUnit(targetName, unit)
    if updated then
        Comm:BroadcastUpsert(updated)
        GUnit:NotifyDataChanged()
        return
    end

    if err == "Same faction." then
        HitList:Delete(targetName)
        Comm:BroadcastDelete(targetName)
        GUnit:NotifyDataChanged()
        GUnit:Print("Removed " .. targetName .. " from hit list: same faction.")
    end
end

local function ProcessSeenUnit(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if UnitIsUnit(unit, "player") then return end

    local unitName = Utils.NormalizeName(UnitName(unit))
    if not unitName then return end

    local target = HitList:Get(unitName)
    if not target then return end

    ValidateTargetUnit(unit, unitName)
    target = HitList:Get(unitName)
    if not target then return end

    if not HitList:ShouldAnnounceSighting(target) then return end

    local now = Utils.Now()
    if ShouldThrottleSighting(unitName, now) then return end
    LocalAlert("G-Unit target found in your area: " .. target.name .. ". Be on the lookout!")
end

local function AnnounceEngageIfNeeded()
    if not UnitExists("target") or not UnitIsPlayer("target") then return end
    local targetName = Utils.NormalizeName(UnitName("target"))
    if not targetName then return end

    local hitTarget = HitList:Get(targetName)
    if not hitTarget then return end
    if not HitList:ShouldAnnounceSighting(hitTarget) then return end

    SendGuildMessage("Attempting to kill " .. Utils.TargetLabel(hitTarget) .. "! Hit was placed by " .. hitTarget.submitter .. ".")
end

local function OnCombatLogEvent()
    local _, subevent, _, sourceGUID, sourceName, _, _, _, destName = CombatLogGetCurrentEventInfo()
    if subevent ~= "PARTY_KILL" then return end
    if not sourceName or not destName then return end

    local killer = Utils.NormalizeName(sourceName)
    local playerName = Utils.NormalizeName(Utils.PlayerName())
    if killer ~= playerName then return end

    local targetName = Utils.NormalizeName(destName)
    local target = HitList:Get(targetName)
    if not target then
        GUnit:Print("[DEBUG] PARTY_KILL: " .. tostring(destName) .. " not on hit list")
        return
    end
    if not HitList:ShouldAnnounceSighting(target) then
        GUnit:Print("[DEBUG] PARTY_KILL: " .. targetName .. " skipped (status=" .. tostring(target.hitStatus) .. ")")
        return
    end

    GUnit:Print("[DEBUG] PARTY_KILL: processing kill on " .. targetName .. " (pre-killCount=" .. tostring(target.killCount) .. ")")

    local zone = Utils.ZoneName()
    local now = Utils.Now()
    HitList:ApplyKill(targetName, playerName, zone, now)
    Comm:BroadcastKill(targetName, playerName, zone, now)

    local updatedTarget = HitList:Get(targetName)
    GUnit:Print("[DEBUG] PARTY_KILL: post-kill " .. targetName .. " killCount=" .. tostring(updatedTarget and updatedTarget.killCount or "NIL"))
    Comm:BroadcastUpsert(updatedTarget)
    GUnit:NotifyDataChanged()

    SendGuildMessage(Utils.TargetLabel(target) .. " has been killed! Hit placed by " .. target.submitter .. ".")
    SendChatMessage("[G-Unit] " .. target.name .. " has been killed for you.", "WHISPER", nil, target.submitter)
end

function Tracking:Init()
    GUnit:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        ProcessSeenUnit("target")
    end)
    GUnit:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
        ProcessSeenUnit("mouseover")
    end)
    GUnit:RegisterEvent("PLAYER_REGEN_DISABLED", AnnounceEngageIfNeeded)
    GUnit:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLogEvent)
end
