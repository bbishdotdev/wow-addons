local _, Addon = ...

-- TODO(shared-ui): This file intentionally mirrors PvPStats/UITheme.lua.
-- Keep APIs in sync across addons until we promote these modules into one shared package.

local Theme = {}
Addon.UITheme = Theme

Theme.FRAME_WIDTH = 882
Theme.FRAME_HEIGHT = 540
Theme.PADDING = 10
Theme.ROW_HEIGHT = 34
Theme.ROWS_PER_PAGE = 11
Theme.DRAWER_WIDTH = 330
Theme.DRAWER_GAP = 8

Theme.COLOR = {
    borderBg = { 0.03, 0.03, 0.03, 0.9 },
    panelBg = { 0.08, 0.08, 0.08, 0.75 },
    headerBg = { 0.12, 0.12, 0.12, 0.85 },
    rowOdd = { 0.2, 0.2, 0.2, 0.12 },
    rowEven = { 0.2, 0.2, 0.2, 0.06 },
    rowHover = { 1, 1, 1, 0.08 },
    textMuted = { 0.6, 0.6, 0.6, 1 },
    textAccent = { 1, 0.82, 0.0, 1 },
    statusActive = { 0.85, 0.2, 0.2, 1 }, -- Open
    statusDone = { 0.2, 0.8, 0.2, 1 }, -- Closed (completed)
    statusClosed = { 0.2, 0.8, 0.2, 1 }, -- Closed
}

Theme.ICON = {
    fallback = "Interface\\Icons\\INV_Misc_QuestionMark",
    bounty = "Interface\\Icons\\INV_Misc_Coin_01",
    kill = "Interface\\Icons\\Ability_FiegnDead",
    submitter = "Interface\\Icons\\INV_Misc_Note_01",
    statusActive = "Interface\\Icons\\Ability_DualWield",
    statusDone = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    statusClosed = "Interface\\Icons\\Spell_Shadow_DeathScream",
    faction = {
        Horde = "Interface\\PVPFrame\\PVP-Currency-Horde",
        Alliance = "Interface\\PVPFrame\\PVP-Currency-Alliance",
    },
    race = {
        Human = "Interface\\Icons\\Spell_Holy_BlessingOfStrength",
        Dwarf = "Interface\\Icons\\Spell_Holy_DivineSpirit",
        NightElf = "Interface\\Icons\\Ability_Ambush",
        Gnome = "Interface\\Icons\\INV_Misc_Head_Gnome_01",
        Orc = "Interface\\Icons\\INV_Misc_Head_Orc_01",
        Undead = "Interface\\Icons\\Spell_Shadow_RaiseDead",
        Tauren = "Interface\\Icons\\Ability_BullRush",
        Troll = "Interface\\Icons\\Ability_Whirlwind",
        BloodElf = "Interface\\Icons\\Spell_Arcane_Blink",
        Draenei = "Interface\\Icons\\Spell_Holy_HolyBolt",
    },
}

Theme.CLASS_ICON_ATLAS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"
Theme.CLASS_ICON_COORDS = {
    WARRIOR = { 0.00, 0.25, 0.00, 0.25 },
    MAGE = { 0.25, 0.50, 0.00, 0.25 },
    ROGUE = { 0.50, 0.75, 0.00, 0.25 },
    DRUID = { 0.75, 1.00, 0.00, 0.25 },
    HUNTER = { 0.00, 0.25, 0.25, 0.50 },
    SHAMAN = { 0.25, 0.50, 0.25, 0.50 },
    PRIEST = { 0.50, 0.75, 0.25, 0.50 },
    WARLOCK = { 0.75, 1.00, 0.25, 0.50 },
    PALADIN = { 0.00, 0.25, 0.50, 0.75 },
}

function Theme.SetClassIcon(texture, classToken)
    texture:SetTexture(Theme.CLASS_ICON_ATLAS)
    local coords = Theme.CLASS_ICON_COORDS[classToken]
    if coords then
        texture:SetTexCoord(unpack(coords))
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

function Theme.GetRaceIcon(raceName)
    return Theme.ICON.race[raceName] or Theme.ICON.fallback
end

function Theme.GetFactionIcon(factionName)
    return Theme.ICON.faction[factionName] or Theme.ICON.fallback
end

function Theme.GetStatusIcon(status)
    if status == "completed" then
        return Theme.ICON.statusDone
    elseif status == "closed" then
        return Theme.ICON.statusClosed
    end
    return Theme.ICON.statusActive
end

function Theme.GetStatusColor(status)
    if status == "completed" then
        return Theme.COLOR.statusDone
    elseif status == "closed" then
        return Theme.COLOR.statusClosed
    end
    return Theme.COLOR.statusActive
end
