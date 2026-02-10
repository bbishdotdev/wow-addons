local ADDON_NAME, GUnit = ...

GUnit.VERSION = "0.1.0"
GUnit.PRINT_PREFIX = "|cffff5555[G-Unit]|r "

local DB_DEFAULTS = {
    version = 1,
    targets = {},
}

local eventFrame = CreateFrame("Frame")
local handlersByEvent = {}

local function CopyDefaults(dst, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            CopyDefaults(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

function GUnit:Print(message)
    print(self.PRINT_PREFIX .. tostring(message))
end

function GUnit:NotifyDataChanged()
    if self.UI and self.UI.Refresh then
        self.UI:Refresh()
    end
end

function GUnit:RegisterEvent(eventName, callback)
    if not handlersByEvent[eventName] then
        handlersByEvent[eventName] = {}
        eventFrame:RegisterEvent(eventName)
    end
    table.insert(handlersByEvent[eventName], callback)
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
    local handlers = handlersByEvent[eventName]
    if not handlers then return end
    for i = 1, #handlers do
        handlers[i](eventName, ...)
    end
end)

local function OnPlayerLogin()
    if not GUnitDB then
        GUnitDB = {}
    end

    CopyDefaults(GUnitDB, DB_DEFAULTS)
    GUnit.db = GUnitDB

    if GUnit.Comm and GUnit.Comm.Init then
        GUnit.Comm:Init()
    end
    if GUnit.Tracking and GUnit.Tracking.Init then
        GUnit.Tracking:Init()
    end
    if GUnit.UI and GUnit.UI.Init then
        GUnit.UI:Init()
    end

    GUnit:Print("v" .. GUnit.VERSION .. " loaded. Use /ghit and /g-unit.")
end

GUnit:RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)
