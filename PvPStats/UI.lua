-- PvPStats: Main frame shell, tab management, view navigation
local _, PvPStats = ...
local C = PvPStats.C

local UI = {}
PvPStats.UI = UI

-- ============================================================
-- State
-- ============================================================
local mainFrame, contentArea, comingSoonText
local currentView = "list"
local forceClose = false
local tabs = {}
local selectedTab = 1

local TAB_NAMES = { "Battlegrounds", "Arenas", "Duels", "World" }
local ENABLED_TABS = { [1] = true }
local TAB_WIDTHS = { 120, 80, 70, 70 }

-- Tab textures (same as Questie/AceGUI — confirmed working on TBC Anniversary)
local TEX_ACTIVE = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab"
local TEX_INACTIVE = "Interface\\OptionsFrame\\UI-OptionsFrame-InActiveTab"
local TEX_HIGHLIGHT = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight"

-- 3-piece TexCoords: left cap, middle stretch, right cap
local TC_LEFT  = { 0, 0.15625, 0, 1.0 }
local TC_MID   = { 0.15625, 0.84375, 0, 1.0 }
local TC_RIGHT = { 0.84375, 1.0, 0, 1.0 }
local CAP_WIDTH = 20

-- ============================================================
-- Initialization (lazy, called on first toggle)
-- ============================================================
function UI:Init()
    if mainFrame then return end
    self:CreateMainFrame()
    self:CreateTabs()

    if PvPStats.BGListView then
        PvPStats.BGListView:Create(contentArea)
    end
    if PvPStats.BGDetailView then
        PvPStats.BGDetailView:Create(contentArea)
    end
end

-- ============================================================
-- Main frame
-- ============================================================
function UI:CreateMainFrame()
    mainFrame = CreateFrame("Frame", "PvPStatsMainFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(C.FRAME_WIDTH, C.FRAME_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetClampedToScreen(true)
    mainFrame.TitleText:SetText("PvPStats")

    tinsert(UISpecialFrames, "PvPStatsMainFrame")

    -- Intercept Hide so ESC navigates back from detail view
    local origHide = mainFrame.Hide
    mainFrame.Hide = function(self)
        if not forceClose and currentView == "detail" then
            UI:ShowView("list")
            return
        end
        forceClose = false
        origHide(self)
    end

    -- X button always force-closes
    if mainFrame.CloseButton then
        mainFrame.CloseButton:SetScript("OnClick", function()
            forceClose = true
            mainFrame:Hide()
        end)
    end

    -- Content area starts below tab row inside the inset
    contentArea = CreateFrame("Frame", nil, mainFrame)
    contentArea:SetPoint("TOPLEFT", mainFrame.InsetBg, "TOPLEFT", 4, -28)
    contentArea:SetPoint("BOTTOMRIGHT", mainFrame.InsetBg, "BOTTOMRIGHT", -4, 4)

    -- Placeholder for disabled tabs
    comingSoonText = contentArea:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    comingSoonText:SetPoint("CENTER")
    comingSoonText:SetText("|cff888888Coming Soon|r")
    comingSoonText:Hide()

    mainFrame:Hide()
end

-- ============================================================
-- Tab bar: 3-piece manual tabs (Questie/AceGUI approach)
-- ============================================================
local function CreateTabTexPiece(tab, name, texture, width, anchor, relFrame, relPoint, xOff, yOff, tc)
    local tex = tab:CreateTexture(name, "BORDER")
    tex:SetTexture(texture)
    tex:SetSize(width, 24)
    tex:SetPoint(anchor, relFrame, relPoint, xOff or 0, yOff or 0)
    tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    return tex
end

function UI:CreateTabs()
    for i, name in ipairs(TAB_NAMES) do
        local tabWidth = TAB_WIDTHS[i]
        local midWidth = tabWidth - (CAP_WIDTH * 2)
        local tabName = "PvPStatsTab" .. i

        local tab = CreateFrame("Button", tabName, mainFrame)
        tab:SetSize(tabWidth, 24)
        tab:SetID(i)
        tab:SetFrameLevel(mainFrame:GetFrameLevel() + 4)

        if i == 1 then
            tab:SetPoint("TOPLEFT", mainFrame.InsetBg, "TOPLEFT", 4, 0)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -10, 0)
        end

        -- Active (selected) tab art — 3 pieces anchored at BOTTOMLEFT with -3 overhang
        tab.activeL = CreateTabTexPiece(tab, tabName.."AL", TEX_ACTIVE, CAP_WIDTH,
            "BOTTOMLEFT", tab, "BOTTOMLEFT", 0, -3, TC_LEFT)
        tab.activeM = CreateTabTexPiece(tab, tabName.."AM", TEX_ACTIVE, midWidth,
            "LEFT", tab.activeL, "RIGHT", 0, 0, TC_MID)
        tab.activeR = CreateTabTexPiece(tab, tabName.."AR", TEX_ACTIVE, CAP_WIDTH,
            "LEFT", tab.activeM, "RIGHT", 0, 0, TC_RIGHT)
        tab.activeL:Hide()
        tab.activeM:Hide()
        tab.activeR:Hide()

        -- Inactive tab art — 3 pieces anchored at TOPLEFT
        tab.inactiveL = CreateTabTexPiece(tab, tabName.."IL", TEX_INACTIVE, CAP_WIDTH,
            "TOPLEFT", tab, "TOPLEFT", 0, 0, TC_LEFT)
        tab.inactiveM = CreateTabTexPiece(tab, tabName.."IM", TEX_INACTIVE, midWidth,
            "LEFT", tab.inactiveL, "RIGHT", 0, 0, TC_MID)
        tab.inactiveR = CreateTabTexPiece(tab, tabName.."IR", TEX_INACTIVE, CAP_WIDTH,
            "LEFT", tab.inactiveM, "RIGHT", 0, 0, TC_RIGHT)

        -- Highlight
        tab:SetHighlightTexture(TEX_HIGHLIGHT, "ADD")
        local hl = tab:GetHighlightTexture()
        hl:ClearAllPoints()
        hl:SetPoint("LEFT", tab, "LEFT", 10, -4)
        hl:SetPoint("RIGHT", tab, "RIGHT", -10, -4)

        -- Label with proper left/right padding
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.label:SetPoint("LEFT", 14, -3)
        tab.label:SetPoint("RIGHT", -12, -3)
        tab.label:SetText(name)

        tab:SetScript("OnClick", function()
            if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
            UI:SelectTab(i)
        end)

        tabs[i] = tab
    end

    self:UpdateTabStyles()
end

function UI:UpdateTabStyles()
    for i = 1, #TAB_NAMES do
        local tab = tabs[i]
        if not tab then return end

        if i == selectedTab then
            -- Show active art, hide inactive
            tab.activeL:Show()
            tab.activeM:Show()
            tab.activeR:Show()
            tab.inactiveL:Hide()
            tab.inactiveM:Hide()
            tab.inactiveR:Hide()
            tab.label:SetTextColor(1.0, 0.82, 0.0)
        else
            -- Show inactive art, hide active
            tab.activeL:Hide()
            tab.activeM:Hide()
            tab.activeR:Hide()
            tab.inactiveL:Show()
            tab.inactiveM:Show()
            tab.inactiveR:Show()
            if ENABLED_TABS[i] then
                tab.label:SetTextColor(0.85, 0.85, 0.85)
            else
                tab.label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
end

-- ============================================================
-- View management
-- ============================================================
function UI:SelectTab(index)
    selectedTab = index
    self:UpdateTabStyles()

    if ENABLED_TABS[index] then
        comingSoonText:Hide()
        self:ShowView("list")
    else
        self:HideAllViews()
        comingSoonText:Show()
        currentView = "comingSoon"
    end
end

function UI:HideAllViews()
    comingSoonText:Hide()
    if PvPStats.BGListView and PvPStats.BGListView.frame then
        PvPStats.BGListView.frame:Hide()
    end
    if PvPStats.BGDetailView and PvPStats.BGDetailView.frame then
        PvPStats.BGDetailView.frame:Hide()
    end
end

function UI:ShowView(view)
    self:HideAllViews()
    currentView = view

    if view == "list" and PvPStats.BGListView then
        if PvPStats.BGListView.frame then
            PvPStats.BGListView.frame:Show()
        end
        PvPStats.BGListView:Refresh()
    elseif view == "detail" and PvPStats.BGDetailView then
        if PvPStats.BGDetailView.frame then
            PvPStats.BGDetailView.frame:Show()
        end
    end
end

function UI:ShowMatchDetail(match)
    if PvPStats.BGDetailView then
        PvPStats.BGDetailView:SetMatch(match)
    end
    self:ShowView("detail")
end

-- ============================================================
-- Public API
-- ============================================================
function UI:Toggle()
    self:Init()
    if mainFrame:IsShown() then
        forceClose = true
        mainFrame:Hide()
    else
        mainFrame:Show()
        self:SelectTab(1)
    end
end
