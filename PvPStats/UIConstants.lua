-- PvPStats: Shared UI constants — icons, colors, layout values
local _, PvPStats = ...

local C = {}
PvPStats.C = C

-- ============================================================
-- Layout
-- ============================================================
C.FRAME_WIDTH = 750
C.FRAME_HEIGHT = 550
C.ROW_HEIGHT = 22
C.HEADER_HEIGHT = 22
C.TAB_HEIGHT = 32
C.CONTENT_INSET = 8

-- ============================================================
-- Class icon atlas: single texture, use tex coords per class
-- ============================================================
C.CLASS_ICON_ATLAS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"

-- Tex coords: { left, right, top, bottom } for each class in the atlas (4x4 grid)
C.CLASS_ICON_COORDS = {
    WARRIOR     = { 0.00, 0.25, 0.00, 0.25 },
    MAGE        = { 0.25, 0.50, 0.00, 0.25 },
    ROGUE       = { 0.50, 0.75, 0.00, 0.25 },
    DRUID       = { 0.75, 1.00, 0.00, 0.25 },
    HUNTER      = { 0.00, 0.25, 0.25, 0.50 },
    SHAMAN      = { 0.25, 0.50, 0.25, 0.50 },
    PRIEST      = { 0.50, 0.75, 0.25, 0.50 },
    WARLOCK     = { 0.75, 1.00, 0.25, 0.50 },
    PALADIN     = { 0.00, 0.25, 0.50, 0.75 },
}

-- ============================================================
-- Class colors (hex for WoW color escapes)
-- ============================================================
C.CLASS_COLORS = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43, hex = "ffc79c6e" },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73, hex = "fff58cba" },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45, hex = "ffabd473" },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41, hex = "fffff569" },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffffff" },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87, hex = "ff0070de" },
    MAGE        = { r = 0.41, g = 0.80, b = 0.94, hex = "ff69ccf0" },
    WARLOCK     = { r = 0.58, g = 0.51, b = 0.79, hex = "ff9482c9" },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04, hex = "ffff7d0a" },
}

-- ============================================================
-- Faction icons & colors
-- ============================================================
C.FACTION_ICON = {
    [0] = "Interface\\PVPFrame\\PVP-Currency-Horde",
    [1] = "Interface\\PVPFrame\\PVP-Currency-Alliance",
}

C.FACTION_COLOR = {
    [0] = { r = 0.8, g = 0.2, b = 0.2 },  -- Horde red
    [1] = { r = 0.2, g = 0.4, b = 0.8 },  -- Alliance blue
}

-- ============================================================
-- BG icons & metadata
-- ============================================================
C.BG_INFO = {
    ["Warsong Gulch"] = {
        short = "WSG",
        icon  = "Interface\\Icons\\INV_Misc_Rune_07",
    },
    ["Arathi Basin"] = {
        short = "AB",
        icon  = "Interface\\Icons\\INV_Jewelry_Amulet_07",
    },
    ["Alterac Valley"] = {
        short = "AV",
        icon  = "Interface\\Icons\\INV_Jewelry_StormPikeInsignia_01",
    },
}

-- ============================================================
-- Result colors (for row tinting)
-- ============================================================
C.RESULT_COLOR = {
    win       = { r = 0.0, g = 0.6, b = 0.0 },
    loss      = { r = 0.6, g = 0.0, b = 0.0 },
    draw      = { r = 0.6, g = 0.6, b = 0.0 },
    abandoned = { r = 0.4, g = 0.4, b = 0.4 },
}

-- ============================================================
-- Helpers
-- ============================================================
function C.ColorName(name, classToken)
    local cc = C.CLASS_COLORS[classToken]
    if cc then
        return "|c" .. cc.hex .. name .. "|r"
    end
    return name or "?"
end

function C.SetClassIcon(texture, classToken)
    texture:SetTexture(C.CLASS_ICON_ATLAS)
    local coords = C.CLASS_ICON_COORDS[classToken]
    if coords then
        texture:SetTexCoord(unpack(coords))
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
end
