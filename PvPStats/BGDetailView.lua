-- PvPStats: Single-match detail view — back button, header, faction-split roster
local _, PvPStats = ...
local C = PvPStats.C
local Utils = PvPStats.Utils

local BGDetailView = {}
PvPStats.BGDetailView = BGDetailView

BGDetailView.frame = nil

-- ============================================================
-- Layout constants
-- ============================================================
local DETAIL_ROW_HEIGHT = 20
local CONTENT_WIDTH = C.FRAME_WIDTH - 30 -- approximate usable width
local PANEL_GAP = 8
local PANEL_WIDTH = math.floor((CONTENT_WIDTH - PANEL_GAP) / 2)

-- State
local currentMatch = nil
local rosterRows = {}

-- Cached frame refs (set during Create)
local headerBGIcon, headerInfoText, headerStatsText
local scrollFrame, scrollChild
local hordePanel, alliancePanel, noDataText

-- ============================================================
-- Creation
-- ============================================================
function BGDetailView:Create(parent)
    if self.frame then return end

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    self.frame = frame

    self:CreateHeader(frame)
    self:CreateRosterArea(frame)

    frame:Hide()
end

-- ============================================================
-- Header: back button, match info, player stats
-- ============================================================
function BGDetailView:CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(70)

    -- Back arrow
    local back = CreateFrame("Button", nil, header)
    back:SetSize(24, 24)
    back:SetPoint("TOPLEFT", 4, -4)
    back:SetNormalTexture("Interface\\BUTTONS\\UI-SpellbookIcon-PrevPage-Up")
    back:SetPushedTexture("Interface\\BUTTONS\\UI-SpellbookIcon-PrevPage-Down")
    back:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    back:SetScript("OnClick", function()
        PvPStats.UI:ShowView("list")
    end)

    -- BG icon (beside back arrow)
    headerBGIcon = header:CreateTexture(nil, "ARTWORK")
    headerBGIcon:SetSize(28, 28)
    headerBGIcon:SetPoint("LEFT", back, "RIGHT", 8, 0)

    -- Match info text (first line)
    headerInfoText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerInfoText:SetPoint("LEFT", headerBGIcon, "RIGHT", 8, 0)
    headerInfoText:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    headerInfoText:SetJustifyH("LEFT")

    -- Player stats text (second line)
    headerStatsText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerStatsText:SetPoint("TOPLEFT", header, "TOPLEFT", 4, -38)
    headerStatsText:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    headerStatsText:SetJustifyH("LEFT")

    -- Separator
    local sep = header:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", 4, 0)
    sep:SetPoint("BOTTOMRIGHT", -4, 0)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    self.header = header
end

-- ============================================================
-- Roster area: scroll frame with two side-by-side faction panels
-- ============================================================
function BGDetailView:CreateRosterArea(parent)
    scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    scrollFrame:EnableMouseWheel(true)

    scrollChild = CreateFrame("Frame")
    scrollChild:SetWidth(CONTENT_WIDTH)
    scrollChild:SetHeight(1) -- updated in BuildRoster
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = math.max(0, scrollChild:GetHeight() - self:GetHeight())
        local new = math.max(0, math.min(cur - delta * 60, maxScroll))
        self:SetVerticalScroll(new)
    end)

    -- Horde panel (left)
    hordePanel = CreateFrame("Frame", nil, scrollChild)
    hordePanel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT")
    hordePanel:SetWidth(PANEL_WIDTH)
    hordePanel:SetHeight(1)

    -- Alliance panel (right)
    alliancePanel = CreateFrame("Frame", nil, scrollChild)
    alliancePanel:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT")
    alliancePanel:SetWidth(PANEL_WIDTH)
    alliancePanel:SetHeight(1)

    -- No data fallback
    noDataText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noDataText:SetPoint("CENTER")
    noDataText:SetText("|cff888888No scoreboard data for this match.|r")
    noDataText:Hide()
end

-- ============================================================
-- Set and display a match
-- ============================================================
function BGDetailView:SetMatch(match)
    currentMatch = match
    if not match then return end

    self:UpdateHeader(match)
    self:BuildRoster(match)
    scrollFrame:SetVerticalScroll(0)
end

-- ============================================================
-- Update header
-- ============================================================
function BGDetailView:UpdateHeader(match)
    -- BG icon
    local bgInfo = C.BG_INFO[match.location]
    if bgInfo then
        headerBGIcon:SetTexture(bgInfo.icon)
        headerBGIcon:Show()
    else
        headerBGIcon:Hide()
    end

    -- Match info line
    local rc = C.RESULT_COLOR[match.result] or C.RESULT_COLOR.draw
    local resultStr = (match.result or "?"):sub(1, 1):upper() .. (match.result or "?"):sub(2)
    local resultColored = string.format("|cff%02x%02x%02x%s|r",
        rc.r * 255, rc.g * 255, rc.b * 255, resultStr)

    local queueStr = match.queueType == "group" and "Group" or "Solo"
    local dateStr = Utils.FormatDate(match.endTime or match.startTime)

    headerInfoText:SetText(string.format("%s  —  %s  —  %s  —  %s  —  %s",
        match.location or "Unknown",
        resultColored,
        Utils.FormatDuration(match.duration),
        queueStr,
        dateStr
    ))

    -- Player stats line
    local ps = match.playerStats
    if ps then
        local parts = {
            "|cffffffffYour Stats:|r",
            string.format("%d KB", ps.killingBlows or 0),
            string.format("%d HK", ps.honorableKills or 0),
            string.format("%d Deaths", ps.deaths or 0),
            string.format("%s Honor", Utils.FormatNumber(ps.honorGained or 0)),
            string.format("%s Dmg", Utils.FormatNumber(ps.damageDone or 0)),
            string.format("%s Heal", Utils.FormatNumber(ps.healingDone or 0)),
        }

        if match.location == "Warsong Gulch" then
            table.insert(parts, string.format("%dC/%dR Flags",
                ps.flagsCaptured or 0, ps.flagsReturned or 0))
        elseif match.location == "Arathi Basin" then
            table.insert(parts, string.format("%dA/%dD Bases",
                ps.basesAssaulted or 0, ps.basesDefended or 0))
        end

        headerStatsText:SetText(table.concat(parts, "  |  "))
    else
        headerStatsText:SetText("|cff888888No player stats available.|r")
    end
end

-- ============================================================
-- Build roster (two faction panels)
-- ============================================================
function BGDetailView:BuildRoster(match)
    -- Hide all existing rows
    for _, row in ipairs(rosterRows) do
        row:Hide()
    end

    local scoreboard = match.scoreboard
    if not scoreboard or #scoreboard == 0 then
        noDataText:Show()
        scrollChild:SetHeight(40)
        return
    end
    noDataText:Hide()

    -- Split by faction
    local hordePlayers, alliancePlayers = {}, {}
    for _, entry in ipairs(scoreboard) do
        if entry.faction == 0 then
            table.insert(hordePlayers, entry)
        else
            table.insert(alliancePlayers, entry)
        end
    end

    -- Sort each faction by killing blows (desc)
    local function sortByKB(a, b)
        return (a.killingBlows or 0) > (b.killingBlows or 0)
    end
    table.sort(hordePlayers, sortByKB)
    table.sort(alliancePlayers, sortByKB)

    -- Populate panels
    local hordeRowCount = self:PopulateFactionPanel(
        hordePanel, "Horde", 0, hordePlayers, match, 0)
    local allianceRowCount = self:PopulateFactionPanel(
        alliancePanel, "Alliance", 1, alliancePlayers, match, 500)

    -- Size scroll child to taller faction
    local maxRows = math.max(hordeRowCount, allianceRowCount)
    local totalHeight = (maxRows + 2) * DETAIL_ROW_HEIGHT
    hordePanel:SetHeight(totalHeight)
    alliancePanel:SetHeight(totalHeight)
    scrollChild:SetHeight(totalHeight)
end

-- ============================================================
-- Populate one faction panel
-- Returns: number of player rows
-- ============================================================
function BGDetailView:PopulateFactionPanel(panel, factionName, factionId, players, match, rowOffset)
    local playerName = UnitName("player")
    local y = 0

    -- Faction header row
    local hdrRow = self:GetOrCreateRow(rowOffset + 1, panel)
    hdrRow:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    hdrRow:SetPoint("RIGHT", panel, "RIGHT")
    hdrRow:SetHeight(DETAIL_ROW_HEIGHT)
    self:ClearRow(hdrRow)

    -- Faction icon + name
    if not hdrRow.factionIcon then
        hdrRow.factionIcon = hdrRow:CreateTexture(nil, "ARTWORK")
        hdrRow.factionIcon:SetSize(16, 16)
        hdrRow.factionIcon:SetPoint("LEFT", 2, 0)
    end
    hdrRow.factionIcon:SetTexture(C.FACTION_ICON[factionId])
    hdrRow.factionIcon:Show()

    if not hdrRow.factionText then
        hdrRow.factionText = hdrRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdrRow.factionText:SetPoint("LEFT", hdrRow.factionIcon, "RIGHT", 4, 0)
    end
    local fc = C.FACTION_COLOR[factionId]
    hdrRow.factionText:SetText(string.format("|cff%02x%02x%02x%s (%d)|r",
        fc.r * 255, fc.g * 255, fc.b * 255, factionName, #players))
    hdrRow.factionText:Show()

    hdrRow.bg:SetColorTexture(fc.r * 0.3, fc.g * 0.3, fc.b * 0.3, 0.4)
    hdrRow:Show()
    y = y + DETAIL_ROW_HEIGHT

    -- Column sub-headers
    local colRow = self:GetOrCreateRow(rowOffset + 2, panel)
    colRow:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
    colRow:SetPoint("RIGHT", panel, "RIGHT")
    colRow:SetHeight(DETAIL_ROW_HEIGHT)
    self:ClearRow(colRow)
    self:EnsureColumnHeaders(colRow)
    colRow.bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
    colRow:Show()
    y = y + DETAIL_ROW_HEIGHT

    -- Player rows
    for i, entry in ipairs(players) do
        local row = self:GetOrCreateRow(rowOffset + 2 + i, panel)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", panel, "RIGHT")
        row:SetHeight(DETAIL_ROW_HEIGHT)
        self:ClearRow(row)
        self:PopulatePlayerRow(row, entry, match, playerName, i)
        row:Show()
        y = y + DETAIL_ROW_HEIGHT
    end

    return #players
end

-- ============================================================
-- Row pool
-- ============================================================
function BGDetailView:GetOrCreateRow(index, parent)
    if rosterRows[index] then
        rosterRows[index]:SetParent(parent)
        return rosterRows[index]
    end

    local row = CreateFrame("Frame", nil, parent)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    rosterRows[index] = row
    return row
end

function BGDetailView:ClearRow(row)
    local optionals = {
        "classIcon", "nameText", "kbText", "deathsText",
        "damageText", "healingText", "bgStatText",
        "factionIcon", "factionText",
    }
    for _, key in ipairs(optionals) do
        if row[key] and row[key].Hide then row[key]:Hide() end
    end
    -- Hide column header texts if they exist
    if row.colHeaders then
        for _, fs in ipairs(row.colHeaders) do fs:Hide() end
    end
    row.bg:SetColorTexture(0, 0, 0, 0)
end

-- ============================================================
-- Column headers for roster panels
-- ============================================================
function BGDetailView:EnsureColumnHeaders(row)
    if not row.colHeaders then
        row.colHeaders = {}
        local defs = {
            { x = 22,  w = 90, text = "Name",  align = "LEFT" },
            { x = 115, w = 30, text = "KB",    align = "CENTER" },
            { x = 147, w = 30, text = "D",     align = "CENTER" },
            { x = 179, w = 48, text = "Dmg",   align = "RIGHT" },
            { x = 229, w = 48, text = "Heal",  align = "RIGHT" },
            { x = 279, w = 42, text = "BG",    align = "CENTER" },
        }
        for _, def in ipairs(defs) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("LEFT", row, "LEFT", def.x, 0)
            fs:SetWidth(def.w)
            fs:SetJustifyH(def.align)
            fs:SetText("|cffffd100" .. def.text .. "|r")
            table.insert(row.colHeaders, fs)
        end
    end

    for _, fs in ipairs(row.colHeaders) do fs:Show() end
end

-- ============================================================
-- Populate a single player row
-- ============================================================
function BGDetailView:PopulatePlayerRow(row, entry, match, playerName, index)
    local isPlayer = entry.name and
        (entry.name == playerName or entry.name:find(playerName, 1, true) == 1)

    -- Background tint
    if isPlayer then
        row.bg:SetColorTexture(1, 1, 1, 0.15)
    else
        row.bg:SetColorTexture(0.3, 0.3, 0.3, (index % 2 == 0) and 0.06 or 0)
    end

    -- Class icon
    if not row.classIcon then
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetSize(16, 16)
        row.classIcon:SetPoint("LEFT", 2, 0)
    end
    C.SetClassIcon(row.classIcon, entry.classToken)
    row.classIcon:Show()

    -- Name (class-colored, strip server suffix)
    if not row.nameText then
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", row, "LEFT", 22, 0)
        row.nameText:SetWidth(90)
        row.nameText:SetJustifyH("LEFT")
    end
    local displayName = entry.name or "?"
    local dash = displayName:find("-", 1, true)
    if dash then displayName = displayName:sub(1, dash - 1) end
    row.nameText:SetText(C.ColorName(displayName, entry.classToken))
    row.nameText:Show()

    -- KB
    if not row.kbText then
        row.kbText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.kbText:SetPoint("LEFT", row, "LEFT", 115, 0)
        row.kbText:SetWidth(30)
        row.kbText:SetJustifyH("CENTER")
    end
    row.kbText:SetText(tostring(entry.killingBlows or 0))
    row.kbText:Show()

    -- Deaths
    if not row.deathsText then
        row.deathsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.deathsText:SetPoint("LEFT", row, "LEFT", 147, 0)
        row.deathsText:SetWidth(30)
        row.deathsText:SetJustifyH("CENTER")
    end
    row.deathsText:SetText(tostring(entry.deaths or 0))
    row.deathsText:Show()

    -- Damage
    if not row.damageText then
        row.damageText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.damageText:SetPoint("LEFT", row, "LEFT", 179, 0)
        row.damageText:SetWidth(48)
        row.damageText:SetJustifyH("RIGHT")
    end
    row.damageText:SetText(Utils.FormatNumber(entry.damageDone))
    row.damageText:Show()

    -- Healing
    if not row.healingText then
        row.healingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.healingText:SetPoint("LEFT", row, "LEFT", 229, 0)
        row.healingText:SetWidth(48)
        row.healingText:SetJustifyH("RIGHT")
    end
    row.healingText:SetText(Utils.FormatNumber(entry.healingDone))
    row.healingText:Show()

    -- BG-specific stat
    if not row.bgStatText then
        row.bgStatText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.bgStatText:SetPoint("LEFT", row, "LEFT", 279, 0)
        row.bgStatText:SetWidth(42)
        row.bgStatText:SetJustifyH("CENTER")
    end
    row.bgStatText:SetText(self:FormatEntryBGStat(entry, match))
    row.bgStatText:Show()
end

-- ============================================================
-- Format BG stat for a single scoreboard entry
-- ============================================================
function BGDetailView:FormatEntryBGStat(entry, match)
    if not entry.bgStats or not match.bgStatColumns then return "-" end

    local parts = {}
    for j, colName in ipairs(match.bgStatColumns) do
        local val = entry.bgStats[j] or 0
        local col = colName:lower()
        local abbr
        if col:find("capture") then abbr = "C"
        elseif col:find("return") then abbr = "R"
        elseif col:find("assault") then abbr = "A"
        elseif col:find("defend") then abbr = "D"
        else abbr = "?" end
        table.insert(parts, val .. abbr)
    end

    return table.concat(parts, "/")
end
