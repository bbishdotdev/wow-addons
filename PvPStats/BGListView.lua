-- PvPStats: BG match list — dropdown filters, styled rows, summary bar
local _, PvPStats = ...
local C = PvPStats.C
local Utils = PvPStats.Utils

local BGListView = {}
PvPStats.BGListView = BGListView

-- ============================================================
-- State
-- ============================================================
local selectedBG = "any"
local selectedQueue = "any"
local scrollOffset = 0
local filteredMatches = {}
local rows = {}

local MAX_VISIBLE_ROWS = 16
local ROW_HEIGHT = C.ROW_HEIGHT

-- Frame references
BGListView.frame = nil
local summaryText, emptyText, pageText

-- ============================================================
-- Filter dropdown options
-- ============================================================
local BG_OPTIONS = {
    { value = "any",            label = "Any Battleground" },
    { value = "Warsong Gulch",  label = "Warsong Gulch",  icon = C.BG_INFO["Warsong Gulch"].icon },
    { value = "Arathi Basin",   label = "Arathi Basin",    icon = C.BG_INFO["Arathi Basin"].icon },
    { value = "Alterac Valley", label = "Alterac Valley",  icon = C.BG_INFO["Alterac Valley"].icon },
}

local QUEUE_OPTIONS = {
    { value = "any",   label = "Any Queue" },
    { value = "solo",  label = "Solo" },
    { value = "group", label = "Group" },
}

-- ============================================================
-- Helpers
-- ============================================================
local function FormatPlayerBGStat(match)
    local ps = match.playerStats
    if not ps then return "-" end

    if match.location == "Warsong Gulch" then
        return (ps.flagsCaptured or 0) .. "C/" .. (ps.flagsReturned or 0) .. "R"
    elseif match.location == "Arathi Basin" then
        return (ps.basesAssaulted or 0) .. "A/" .. (ps.basesDefended or 0) .. "D"
    end
    return "-"
end

local function ComputeSummary(matches)
    local wins, losses, totalKB, totalDeaths, totalHonor = 0, 0, 0, 0, 0

    for _, m in ipairs(matches) do
        if m.result == "win" then wins = wins + 1
        elseif m.result == "loss" then losses = losses + 1 end

        local ps = m.playerStats
        if ps then
            totalKB     = totalKB     + (ps.killingBlows or 0)
            totalDeaths = totalDeaths + (ps.deaths or 0)
            totalHonor  = totalHonor  + (ps.honorGained or 0)
        end
    end

    local total = wins + losses
    local pct = total > 0 and math.floor(wins / total * 1000 + 0.5) / 10 or 0

    return string.format(
        "|cff00ff00%d|rW - |cffff0000%d|rL (%.1f%%)  |  %s KB  |  %d Deaths  |  %s Honor",
        wins, losses, pct,
        Utils.FormatNumber(totalKB), totalDeaths, Utils.FormatNumber(totalHonor)
    )
end

-- ============================================================
-- Creation
-- ============================================================
function BGListView:Create(parent)
    if self.frame then return end

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    self.frame = frame

    self:CreateFilterBar(frame)
    self:CreateSummaryBar(frame)
    self:CreateColumnHeaders(frame)
    self:CreateRowContainer(frame)

    frame:Hide()
end

-- ============================================================
-- Filter bar
-- ============================================================
function BGListView:CreateFilterBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(30)

    -- BG filter dropdown
    local bgDD = CreateFrame("Frame", "PvPStatsBGFilter", bar, "UIDropDownMenuTemplate")
    bgDD:SetPoint("TOPLEFT", -15, 0)
    UIDropDownMenu_SetWidth(bgDD, 140)
    UIDropDownMenu_SetText(bgDD, "Any Battleground")

    UIDropDownMenu_Initialize(bgDD, function(_, level)
        for _, opt in ipairs(BG_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = opt.label
            info.value    = opt.value
            info.icon     = opt.icon
            info.checked  = (selectedBG == opt.value)
            info.func = function(self)
                selectedBG = self.value
                UIDropDownMenu_SetText(bgDD, opt.label)
                CloseDropDownMenus()
                scrollOffset = 0
                BGListView:Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Queue filter dropdown
    local qDD = CreateFrame("Frame", "PvPStatsQueueFilter", bar, "UIDropDownMenuTemplate")
    qDD:SetPoint("LEFT", bgDD, "RIGHT", 0, 0)
    UIDropDownMenu_SetWidth(qDD, 100)
    UIDropDownMenu_SetText(qDD, "Any Queue")

    UIDropDownMenu_Initialize(qDD, function(_, level)
        for _, opt in ipairs(QUEUE_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = opt.label
            info.value    = opt.value
            info.checked  = (selectedQueue == opt.value)
            info.func = function(self)
                selectedQueue = self.value
                UIDropDownMenu_SetText(qDD, opt.label)
                CloseDropDownMenus()
                scrollOffset = 0
                BGListView:Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    self.filterBar = bar
end

-- ============================================================
-- Summary stats bar
-- ============================================================
function BGListView:CreateSummaryBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", self.filterBar, "BOTTOMLEFT", 0, -2)
    bar:SetPoint("TOPRIGHT", self.filterBar, "BOTTOMRIGHT", 0, -2)
    bar:SetHeight(20)

    summaryText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("LEFT", 8, 0)
    summaryText:SetJustifyH("LEFT")

    -- Thin separator below summary
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.4)

    self.summaryBar = bar
end

-- ============================================================
-- Column headers (gold, BG-scoreboard style)
-- ============================================================
function BGListView:CreateColumnHeaders(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", self.summaryBar, "BOTTOMLEFT", 0, -2)
    header:SetPoint("TOPRIGHT", self.summaryBar, "BOTTOMRIGHT", 0, -2)
    header:SetHeight(C.HEADER_HEIGHT)

    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local cols = {
        { x = 36,  w = 90,  text = "Date",     align = "LEFT" },
        { x = 130, w = 60,  text = "Duration",  align = "CENTER" },
        { x = 194, w = 40,  text = "Queue",     align = "CENTER" },
        { x = 240, w = 42,  text = "KB",        align = "CENTER" },
        { x = 286, w = 42,  text = "HK",        align = "CENTER" },
        { x = 332, w = 48,  text = "Deaths",    align = "CENTER" },
        { x = 385, w = 55,  text = "Honor",     align = "RIGHT" },
        { x = 445, w = 65,  text = "Damage",    align = "RIGHT" },
        { x = 515, w = 65,  text = "Healing",   align = "RIGHT" },
        { x = 585, w = 65,  text = "BG Stat",   align = "CENTER" },
    }

    for _, col in ipairs(cols) do
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", header, "LEFT", col.x, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.align)
        fs:SetText(col.text)
    end

    self.headerRow = header
end

-- ============================================================
-- Row container (mouse-wheel scrollable)
-- ============================================================
function BGListView:CreateRowContainer(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", self.headerRow, "BOTTOMLEFT", 0, -1)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 16)

    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #filteredMatches - MAX_VISIBLE_ROWS)
        scrollOffset = math.max(0, math.min(scrollOffset - delta * 3, maxOff))
        BGListView:RenderRows()
    end)

    for i = 1, MAX_VISIBLE_ROWS do
        rows[i] = self:CreateRow(container, i)
    end

    -- Empty state
    emptyText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER")
    emptyText:SetText("|cff888888No battleground data yet.|r")
    emptyText:Hide()

    -- Page indicator (bottom-right)
    pageText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageText:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 2)
    pageText:SetTextColor(0.5, 0.5, 0.5)

    self.rowContainer = container
end

-- ============================================================
-- Single match row
-- ============================================================
function BGListView:CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", parent, "RIGHT")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    -- Hover highlight
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    -- Result indicator (thin left bar)
    row.resultBar = row:CreateTexture(nil, "ARTWORK")
    row.resultBar:SetWidth(3)
    row.resultBar:SetPoint("TOPLEFT")
    row.resultBar:SetPoint("BOTTOMLEFT")

    -- BG icon
    row.bgIcon = row:CreateTexture(nil, "ARTWORK")
    row.bgIcon:SetSize(18, 18)
    row.bgIcon:SetPoint("LEFT", row.resultBar, "RIGHT", 8, 0)

    -- Date
    row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dateText:SetPoint("LEFT", row, "LEFT", 36, 0)
    row.dateText:SetWidth(90)
    row.dateText:SetJustifyH("LEFT")

    -- Duration
    row.durationText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.durationText:SetPoint("LEFT", row, "LEFT", 130, 0)
    row.durationText:SetWidth(60)
    row.durationText:SetJustifyH("CENTER")

    -- Queue type
    row.queueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.queueText:SetPoint("LEFT", row, "LEFT", 194, 0)
    row.queueText:SetWidth(40)
    row.queueText:SetJustifyH("CENTER")

    -- KB
    row.kbText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.kbText:SetPoint("LEFT", row, "LEFT", 240, 0)
    row.kbText:SetWidth(42)
    row.kbText:SetJustifyH("CENTER")

    -- HK
    row.hkText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.hkText:SetPoint("LEFT", row, "LEFT", 286, 0)
    row.hkText:SetWidth(42)
    row.hkText:SetJustifyH("CENTER")

    -- Deaths
    row.deathsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.deathsText:SetPoint("LEFT", row, "LEFT", 332, 0)
    row.deathsText:SetWidth(48)
    row.deathsText:SetJustifyH("CENTER")

    -- Honor
    row.honorText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.honorText:SetPoint("LEFT", row, "LEFT", 385, 0)
    row.honorText:SetWidth(55)
    row.honorText:SetJustifyH("RIGHT")

    -- Damage
    row.damageText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.damageText:SetPoint("LEFT", row, "LEFT", 445, 0)
    row.damageText:SetWidth(65)
    row.damageText:SetJustifyH("RIGHT")

    -- Healing
    row.healingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.healingText:SetPoint("LEFT", row, "LEFT", 515, 0)
    row.healingText:SetWidth(65)
    row.healingText:SetJustifyH("RIGHT")

    -- BG-specific stat
    row.bgStatText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bgStatText:SetPoint("LEFT", row, "LEFT", 585, 0)
    row.bgStatText:SetWidth(65)
    row.bgStatText:SetJustifyH("CENTER")

    -- Click → detail view
    row:SetScript("OnClick", function()
        if row.matchData then
            PvPStats.UI:ShowMatchDetail(row.matchData)
        end
    end)

    -- Hover tooltip
    row:SetScript("OnEnter", function(self)
        if not self.matchData then return end
        local m = self.matchData
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(m.location or "Unknown", 1, 0.82, 0)
        GameTooltip:AddLine(Utils.ColorResult(m.result) .. "  |  "
            .. Utils.FormatDuration(m.duration), 1, 1, 1)
        if m.playerStats then
            local ps = m.playerStats
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("KB:", tostring(ps.killingBlows or 0),
                0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Damage:", Utils.FormatNumber(ps.damageDone),
                0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Healing:", Utils.FormatNumber(ps.healingDone),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to view details", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

-- ============================================================
-- Refresh (filter + render)
-- ============================================================
function BGListView:Refresh()
    filteredMatches = self:FilterMatches()
    summaryText:SetText(ComputeSummary(filteredMatches))
    self:RenderRows()
end

function BGListView:FilterMatches()
    local matches = PvPStats.db and PvPStats.db.matches or {}
    local result = {}

    for _, m in ipairs(matches) do
        local passLoc   = (selectedBG    == "any") or (m.location  == selectedBG)
        local passQueue = (selectedQueue  == "any") or (m.queueType == selectedQueue)
        if passLoc and passQueue then
            table.insert(result, m)
        end
    end

    -- Newest first
    table.sort(result, function(a, b)
        return (a.endTime or a.startTime or 0) > (b.endTime or b.startTime or 0)
    end)

    return result
end

-- ============================================================
-- Render visible rows
-- ============================================================
function BGListView:RenderRows()
    local total = #filteredMatches

    if total == 0 then
        for i = 1, MAX_VISIBLE_ROWS do rows[i]:Hide() end
        emptyText:Show()
        pageText:SetText("")
        return
    end

    emptyText:Hide()

    for i = 1, MAX_VISIBLE_ROWS do
        local dataIdx = i + scrollOffset
        local match = filteredMatches[dataIdx]
        if match then
            self:PopulateRow(rows[i], match, dataIdx)
            rows[i]:Show()
        else
            rows[i]:Hide()
        end
    end

    local first = scrollOffset + 1
    local last  = math.min(scrollOffset + MAX_VISIBLE_ROWS, total)
    pageText:SetText(first .. "-" .. last .. " of " .. total)
end

-- ============================================================
-- Populate a single row
-- ============================================================
function BGListView:PopulateRow(row, match, index)
    row.matchData = match

    -- Result bar color
    local rc = C.RESULT_COLOR[match.result] or C.RESULT_COLOR.draw
    row.resultBar:SetColorTexture(rc.r, rc.g, rc.b, 1)

    -- Row background (alternating + result tint)
    local isEven = (index % 2 == 0)
    local alpha = isEven and 0.12 or 0.06
    if match.result == "win" then
        row.bg:SetColorTexture(0, 0.3, 0, alpha)
    elseif match.result == "loss" then
        row.bg:SetColorTexture(0.3, 0, 0, alpha)
    else
        row.bg:SetColorTexture(0.2, 0.2, 0.2, alpha)
    end

    -- BG icon
    local bgInfo = C.BG_INFO[match.location]
    if bgInfo then
        row.bgIcon:SetTexture(bgInfo.icon)
        row.bgIcon:Show()
    else
        row.bgIcon:Hide()
    end

    -- Text fields
    row.dateText:SetText(Utils.FormatDateTime(match.endTime or match.startTime))
    row.durationText:SetText(Utils.FormatDuration(match.duration))

    -- Queue type
    local qt = match.queueType or "?"
    if qt == "solo" then
        row.queueText:SetText("|cffaaaaaa" .. "Solo" .. "|r")
    elseif qt == "group" then
        row.queueText:SetText("|cff55aaff" .. "Group" .. "|r")
    else
        row.queueText:SetText("|cff666666?|r")
    end

    -- Player stats
    local ps = match.playerStats or {}
    row.kbText:SetText(tostring(ps.killingBlows or 0))
    row.hkText:SetText(tostring(ps.honorableKills or 0))
    row.deathsText:SetText(tostring(ps.deaths or 0))
    row.honorText:SetText(Utils.FormatNumber(ps.honorGained or 0))
    row.damageText:SetText(Utils.FormatNumber(ps.damageDone or 0))
    row.healingText:SetText(Utils.FormatNumber(ps.healingDone or 0))
    row.bgStatText:SetText(FormatPlayerBGStat(match))
end
