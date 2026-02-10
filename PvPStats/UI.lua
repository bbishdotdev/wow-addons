-- PvPStats: Basic modal UI with filters and match list
local _, PvPStats = ...

local Utils = PvPStats.Utils
local UI = {}
PvPStats.UI = UI

-- ============================================================
-- Constants
-- ============================================================
local FRAME_WIDTH = 720
local FRAME_HEIGHT = 500
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 20
local VISIBLE_ROWS = 18
local FILTER_BTN_WIDTH = 70

-- Layout offsets from main frame top
local FILTER_BAR_Y = -30
local FILTER_BAR_HEIGHT = 26
local COLUMN_HEADER_Y = FILTER_BAR_Y - FILTER_BAR_HEIGHT - 4  -- -60
local LIST_Y = COLUMN_HEADER_Y - HEADER_HEIGHT - 2             -- -82

-- Active filters
local activeFilters = {
    queueType = nil,  -- nil = all, "solo", "group"
    location  = nil,  -- nil = all, "Warsong Gulch", etc.
}

-- ============================================================
-- Main frame creation
-- ============================================================
local mainFrame = nil
local rowFrames = {}

local function CreateMainFrame()
    local f = CreateFrame("Frame", "PvPStatsMainFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")

    -- Title (safety check for TBC template differences)
    if f.TitleText then
        f.TitleText:SetText("PvPStats — Battleground Tracker")
    end

    -- Close with Escape
    tinsert(UISpecialFrames, "PvPStatsMainFrame")

    f:Hide()
    return f
end

-- ============================================================
-- Filter bar — anchored to main frame, below title
-- ============================================================
local function CreateFilterBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, FILTER_BAR_Y)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, FILTER_BAR_Y)
    bar:SetHeight(FILTER_BAR_HEIGHT)

    local filters = {
        { label = "Overall",  queueType = nil,     location = nil },
        { label = "Solo",     queueType = "solo",  location = nil },
        { label = "Group",    queueType = "group", location = nil },
        { label = "WSG",      queueType = nil,     location = "Warsong Gulch" },
        { label = "AB",       queueType = nil,     location = "Arathi Basin" },
        { label = "AV",       queueType = nil,     location = "Alterac Valley" },
    }

    local prevBtn = nil
    for _, cfg in ipairs(filters) do
        local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        btn:SetSize(FILTER_BTN_WIDTH, 22)
        btn:SetText(cfg.label)

        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end

        btn:SetScript("OnClick", function()
            activeFilters.queueType = cfg.queueType
            activeFilters.location  = cfg.location
            UI:RefreshMatchList()
        end)

        prevBtn = btn
    end

    return bar
end

-- ============================================================
-- Column header — anchored below filter bar
-- ============================================================
local COLUMNS = {
    { label = "Date",     width = 90 },
    { label = "BG",       width = 40 },
    { label = "Type",     width = 45 },
    { label = "Result",   width = 45 },
    { label = "Duration", width = 60 },
    { label = "KB",       width = 35 },
    { label = "HK",       width = 35 },
    { label = "Deaths",   width = 45 },
    { label = "Honor",    width = 50 },
    { label = "Damage",   width = 65 },
    { label = "Healing",  width = 65 },
    { label = "BG Stat",  width = 80 },
}

local function CreateColumnHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, COLUMN_HEADER_Y)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, COLUMN_HEADER_Y)
    header:SetHeight(HEADER_HEIGHT)

    local xOffset = 0
    for _, col in ipairs(COLUMNS) do
        local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", header, "LEFT", xOffset, 0)
        text:SetWidth(col.width)
        text:SetJustifyH("LEFT")
        text:SetText(col.label)
        xOffset = xOffset + col.width
    end

    return header
end

-- ============================================================
-- Match row creation
-- ============================================================
local function CreateMatchRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    -- Highlight on hover
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Alt-row background
    if index % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end

    -- Create text columns
    row.texts = {}
    local xOffset = 0
    for _, col in ipairs(COLUMNS) do
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", xOffset, 0)
        text:SetWidth(col.width)
        text:SetJustifyH("LEFT")
        table.insert(row.texts, text)
        xOffset = xOffset + col.width
    end

    row.matchData = nil
    row:SetScript("OnClick", function(self)
        if self.matchData then
            UI:ShowMatchDetail(self.matchData)
        end
    end)

    return row
end

-- ============================================================
-- Format BG-specific stat for the summary column
-- ============================================================
local function FormatBGStatSummary(match)
    local ps = match.playerStats
    if not ps then return "" end

    local loc = match.location
    if loc == "Warsong Gulch" then
        local caps = ps.flagsCaptured or 0
        local rets = ps.flagsReturned or 0
        return caps .. "C/" .. rets .. "R"
    elseif loc == "Arathi Basin" then
        local assaulted = ps.basesAssaulted or 0
        local defended  = ps.basesDefended or 0
        return assaulted .. "A/" .. defended .. "D"
    end

    return ""
end

-- ============================================================
-- Populate a row with match data
-- ============================================================
local function SetRowData(row, match)
    row.matchData = match
    local ps = match.playerStats or {}
    local texts = row.texts

    texts[1]:SetText(Utils.FormatDateTime(match.endTime or match.startTime))
    texts[2]:SetText(Utils.ShortBGName(match.location))
    texts[3]:SetText(match.queueType or "?")
    texts[4]:SetText(Utils.ColorResult(match.result))
    texts[5]:SetText(Utils.FormatDuration(match.duration))
    texts[6]:SetText(ps.killingBlows or 0)
    texts[7]:SetText(ps.honorableKills or 0)
    texts[8]:SetText(ps.deaths or 0)
    texts[9]:SetText(Utils.FormatNumber(ps.honorGained))
    texts[10]:SetText(Utils.FormatNumber(ps.damageDone))
    texts[11]:SetText(Utils.FormatNumber(ps.healingDone))
    texts[12]:SetText(FormatBGStatSummary(match))
end

local function ClearRow(row)
    row.matchData = nil
    for _, text in ipairs(row.texts) do
        text:SetText("")
    end
end

-- ============================================================
-- Row container — anchored below column header (no scroll frame for now)
-- ============================================================
local function CreateRowContainer(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, LIST_Y)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 10)

    for i = 1, VISIBLE_ROWS do
        rowFrames[i] = CreateMatchRow(container, i)
    end

    return container
end

-- ============================================================
-- Filter matches based on active filters
-- ============================================================
local function GetFilteredMatches()
    if not PvPStats.db or not PvPStats.db.matches then return {} end

    local filtered = {}
    for _, match in ipairs(PvPStats.db.matches) do
        local pass = true

        if activeFilters.queueType and match.queueType ~= activeFilters.queueType then
            pass = false
        end
        if activeFilters.location and match.location ~= activeFilters.location then
            pass = false
        end

        if pass then
            table.insert(filtered, match)
        end
    end

    -- Newest first
    table.sort(filtered, function(a, b)
        return (a.endTime or a.startTime or 0) > (b.endTime or b.startTime or 0)
    end)

    return filtered
end

-- ============================================================
-- Refresh the match list display
-- ============================================================
local rowContainer = nil
local filteredMatches = {}
local displayOffset = 0

function UI:RefreshMatchList()
    filteredMatches = GetFilteredMatches()

    if not rowContainer then return end

    local total = #filteredMatches

    for i = 1, VISIBLE_ROWS do
        local dataIdx = displayOffset + i
        if dataIdx <= total then
            SetRowData(rowFrames[i], filteredMatches[dataIdx])
            rowFrames[i]:Show()
        else
            ClearRow(rowFrames[i])
            rowFrames[i]:Hide()
        end
    end
end

-- ============================================================
-- Match detail panel (FontString-based, no EditBox)
-- ============================================================
local detailFrame = nil

local function CreateDetailFrame(parent)
    local f = CreateFrame("Frame", "PvPStatsDetailFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_WIDTH, 400)
    f:SetPoint("TOP", parent, "BOTTOM", 0, -4)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")

    if f.TitleText then
        f.TitleText:SetText("Match Detail")
    end

    -- Scrolling text area using FontString (no EditBox = no focus stealing)
    local sf = CreateFrame("ScrollFrame", "PvPStatsDetailScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 10)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(FRAME_WIDTH - 60)

    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(2)

    sf:SetScrollChild(content)

    f.content = content
    f.text = text
    f:Hide()
    return f
end

-- Build a text dump of the full scoreboard for a match
local function BuildScoreboardText(match)
    local lines = {}

    table.insert(lines, "=== " .. (match.location or "Unknown") .. " ===")
    table.insert(lines, "Date: " .. Utils.FormatDateTime(match.endTime or match.startTime))
    table.insert(lines, "Result: " .. (match.result or "N/A")
        .. "  |  Duration: " .. Utils.FormatDuration(match.duration)
        .. "  |  Queue: " .. (match.queueType or "?"))
    table.insert(lines, "")

    -- Column headers for BG-specific stats
    local bgCols = match.bgStatColumns or {}
    local bgHeader = ""
    for _, col in ipairs(bgCols) do
        bgHeader = bgHeader .. "  " .. col
    end

    -- Separate by faction
    local horde, alliance = {}, {}
    if match.scoreboard then
        for _, p in ipairs(match.scoreboard) do
            if p.faction == 0 then
                table.insert(horde, p)
            else
                table.insert(alliance, p)
            end
        end
    end

    for _, group in ipairs({
        { label = "--- HORDE ---", players = horde },
        { label = "--- ALLIANCE ---", players = alliance },
    }) do
        table.insert(lines, group.label)
        table.insert(lines, string.format("  %-20s %-10s %5s %5s %5s %7s %8s %8s%s",
            "Name", "Class", "KB", "HK", "D", "Honor", "Damage", "Healing", bgHeader))

        for _, p in ipairs(group.players) do
            local bgVals = ""
            for j = 1, #bgCols do
                bgVals = bgVals .. string.format("  %5d", (p.bgStats and p.bgStats[j]) or 0)
            end

            table.insert(lines, string.format("  %-20s %-10s %5d %5d %5d %7s %8s %8s%s",
                p.name or "?",
                p.class or "?",
                p.killingBlows or 0,
                p.honorableKills or 0,
                p.deaths or 0,
                Utils.FormatNumber(p.honorGained),
                Utils.FormatNumber(p.damageDone),
                Utils.FormatNumber(p.healingDone),
                bgVals))
        end
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

function UI:ShowMatchDetail(match)
    if not detailFrame then
        detailFrame = CreateDetailFrame(mainFrame)
    end

    local text = BuildScoreboardText(match)
    detailFrame.text:SetText(text)
    -- Resize content frame to fit the text
    detailFrame.content:SetHeight(detailFrame.text:GetStringHeight() + 20)

    if detailFrame.TitleText then
        detailFrame.TitleText:SetText("Match Detail — " .. Utils.ShortBGName(match.location)
            .. " " .. Utils.FormatDateTime(match.endTime or match.startTime))
    end
    detailFrame:Show()
end

-- ============================================================
-- Toggle main frame
-- ============================================================
function UI:Toggle()
    if not mainFrame then
        mainFrame = CreateMainFrame()
        CreateFilterBar(mainFrame)
        CreateColumnHeader(mainFrame)
        rowContainer = CreateRowContainer(mainFrame)
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
        if detailFrame then detailFrame:Hide() end
    else
        UI:RefreshMatchList()
        mainFrame:Show()
    end
end
