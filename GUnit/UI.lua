local _, GUnit = ...
local Utils = GUnit.Utils
local HitList = GUnit.HitList
local Comm = GUnit.Comm

GUnit.UI = {}
local UI = GUnit.UI

local ROWS_PER_PAGE = 12

local function MakeLabel(parent, text, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(text)
    return label
end

local function ModeLabel(target)
    local hit = target.hitMode == "kos" and "KOS" or "One-time"
    local bounty = target.bountyMode or "none"
    return hit .. " | Bounty: " .. bounty
end

local function BuildClaimsText(target)
    local claims = target.bountyClaims or {}
    local lines = {}
    for killer, data in pairs(claims) do
        table.insert(lines, killer .. ": " .. Utils.GoldStringFromCopper(data.totalCopper) .. " (" .. (data.claimCount or 0) .. " claim)")
    end
    table.sort(lines)
    if #lines == 0 then
        return "None"
    end
    return table.concat(lines, "\n")
end

function UI:RefreshList()
    self.names = HitList:SortedNamesForCurrentGuild()
    local startIndex = self.pageOffset + 1

    for rowIndex = 1, ROWS_PER_PAGE do
        local listIndex = startIndex + rowIndex - 1
        local row = self.rows[rowIndex]
        local name = self.names[listIndex]
        if name then
            local target = HitList:Get(name)
            local line = name .. " | " .. target.submitter .. " | Kills: " .. (target.killCount or 0)
            if target.hitStatus == "completed" then
                line = line .. " | COMPLETED"
            end
            row.name = name
            row.text:SetText(line)
            row:Show()
        else
            row.name = nil
            row.text:SetText("")
            row:Hide()
        end
    end

    local totalPages = math.max(1, math.ceil(#self.names / ROWS_PER_PAGE))
    local currentPage = math.floor(self.pageOffset / ROWS_PER_PAGE) + 1
    self.pageText:SetText("Page " .. currentPage .. "/" .. totalPages)
end

function UI:RefreshDetails()
    local target = self.selectedName and HitList:Get(self.selectedName) or nil
    if not target then
        self.detailText:SetText("Select a target from the list.")
        self.reasonEdit:SetText("")
        self.bountyEdit:SetText("")
        self.hitModeButton:SetText("Hit Mode")
        self.bountyModeButton:SetText("Bounty Mode")
        self.statusButton:SetText("Status")
        return
    end

    local classLine = target.classToken or "Unknown"
    local raceLine = target.race or "Unknown"
    local factionLine = target.faction or "Unknown"
    local detail = table.concat({
        "Target: " .. target.name,
        "Submitter: " .. target.submitter,
        "Reason: " .. (target.reason ~= "" and target.reason or "None"),
        "Bounty: " .. Utils.GoldStringFromCopper(target.bountyAmount or 0),
        "Modes: " .. ModeLabel(target),
        "Hit Status: " .. (target.hitStatus or "active"),
        "Bounty Status: " .. (target.bountyStatus or "open"),
        "Class/Race/Faction: " .. classLine .. " / " .. raceLine .. " / " .. factionLine,
        "Kill Count: " .. (target.killCount or 0),
        "Bounty Owed:",
        BuildClaimsText(target),
    }, "\n")

    self.detailText:SetText(detail)
    self.reasonEdit:SetText(target.reason or "")
    self.bountyEdit:SetText(string.format("%.2f", (target.bountyAmount or 0) / 10000))
    self.hitModeButton:SetText("Hit: " .. (target.hitMode == "kos" and "KOS" or "One-time"))
    self.bountyModeButton:SetText("Bounty: " .. (target.bountyMode or "none"))
    self.statusButton:SetText("Status: " .. (target.hitStatus or "active"))
end

function UI:Refresh()
    if not self.frame then return end
    self:RefreshList()
    self:RefreshDetails()
end

local function RequireSelectedTarget()
    if not UI.selectedName then
        GUnit:Print("Select a target first.")
        return nil
    end
    local target = HitList:Get(UI.selectedName)
    if not target then
        GUnit:Print("Target no longer exists.")
        UI.selectedName = nil
        UI:Refresh()
        return nil
    end
    return target
end

local function SaveTargetAndBroadcast(target)
    Comm:BroadcastUpsert(target)
    GUnit:NotifyDataChanged()
end

function UI:Init()
    if self.frame then return end

    local frame = CreateFrame("Frame", "GUnitMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(920, 560)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:Hide()
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -12)
    title:SetText("G-Unit Hit List")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    self.pageOffset = 0
    self.names = {}
    self.rows = {}
    self.selectedName = nil

    local listHeader = MakeLabel(frame, "Targets", 16, -40)
    listHeader:SetTextColor(1, 0.8, 0.1)

    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(420, 22)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -60 - ((i - 1) * 24))
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetAllPoints()
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(selfRow)
            UI.selectedName = selfRow.name
            UI:RefreshDetails()
        end)
        self.rows[i] = row
    end

    local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    prev:SetSize(70, 22)
    prev:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    prev:SetText("Prev")
    prev:SetScript("OnClick", function()
        UI.pageOffset = math.max(0, UI.pageOffset - ROWS_PER_PAGE)
        UI:RefreshList()
    end)

    local next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    next:SetSize(70, 22)
    next:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    next:SetText("Next")
    next:SetScript("OnClick", function()
        local maxOffset = math.max(0, #UI.names - ROWS_PER_PAGE)
        UI.pageOffset = math.min(maxOffset, UI.pageOffset + ROWS_PER_PAGE)
        UI:RefreshList()
    end)

    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.pageText:SetPoint("LEFT", next, "RIGHT", 12, 0)
    self.pageText:SetText("Page 1/1")

    local detailHeader = MakeLabel(frame, "Details", 460, -40)
    detailHeader:SetTextColor(1, 0.8, 0.1)

    self.detailText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.detailText:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -60)
    self.detailText:SetWidth(430)
    self.detailText:SetJustifyH("LEFT")
    self.detailText:SetJustifyV("TOP")
    self.detailText:SetText("Select a target from the list.")

    MakeLabel(frame, "Reason", 460, -300)
    self.reasonEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    self.reasonEdit:SetSize(280, 24)
    self.reasonEdit:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -320)
    self.reasonEdit:SetAutoFocus(false)

    local saveReason = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveReason:SetSize(120, 24)
    saveReason:SetPoint("LEFT", self.reasonEdit, "RIGHT", 8, 0)
    saveReason:SetText("Save Reason")
    saveReason:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local updated, err = HitList:SetReason(target.name, UI.reasonEdit:GetText(), Utils.PlayerName())
        if not updated then
            GUnit:Print(err)
            return
        end
        SaveTargetAndBroadcast(updated)
    end)

    MakeLabel(frame, "Bounty (gold)", 460, -356)
    self.bountyEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    self.bountyEdit:SetSize(120, 24)
    self.bountyEdit:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -376)
    self.bountyEdit:SetAutoFocus(false)

    local saveBounty = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBounty:SetSize(120, 24)
    saveBounty:SetPoint("LEFT", self.bountyEdit, "RIGHT", 8, 0)
    saveBounty:SetText("Save Bounty")
    saveBounty:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local copper = Utils.CopperFromGoldString(UI.bountyEdit:GetText())
        if not copper then
            GUnit:Print("Invalid bounty amount.")
            return
        end
        local updated, err = HitList:SetBountyAmount(target.name, copper, Utils.PlayerName())
        if not updated then
            GUnit:Print(err)
            return
        end
        SaveTargetAndBroadcast(updated)
    end)

    self.hitModeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.hitModeButton:SetSize(130, 24)
    self.hitModeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -420)
    self.hitModeButton:SetText("Hit: One-time")
    self.hitModeButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local newMode = target.hitMode == "kos" and "one_time" or "kos"
        local updated, err = HitList:SetHitMode(target.name, newMode, Utils.PlayerName())
        if not updated then
            GUnit:Print(err)
            return
        end
        SaveTargetAndBroadcast(updated)
    end)

    self.bountyModeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.bountyModeButton:SetSize(150, 24)
    self.bountyModeButton:SetPoint("LEFT", self.hitModeButton, "RIGHT", 8, 0)
    self.bountyModeButton:SetText("Bounty: none")
    self.bountyModeButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local nextMode
        if target.bountyMode == "none" then
            nextMode = "first_kill"
        elseif target.bountyMode == "first_kill" then
            nextMode = "infinite"
        else
            nextMode = "none"
        end
        local updated, err = HitList:SetBountyMode(target.name, nextMode, Utils.PlayerName())
        if not updated then
            GUnit:Print(err)
            return
        end
        SaveTargetAndBroadcast(updated)
    end)

    self.statusButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.statusButton:SetSize(150, 24)
    self.statusButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -452)
    self.statusButton:SetText("Status: active")
    self.statusButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local nextStatus = target.hitStatus == "active" and "completed" or "active"
        local updated, err = HitList:SetHitStatus(target.name, nextStatus, Utils.PlayerName())
        if not updated then
            GUnit:Print(err)
            return
        end
        SaveTargetAndBroadcast(updated)
    end)

    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(90, 22)
    exportBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -110, 16)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        UI:ShowExportFrame()
    end)

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(90, 22)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        UI:ShowImportFrame()
    end)

    self:Refresh()
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
    end
end

local function CreateTextFrame(title, bodyText, editable)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.95)

    local titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    titleLabel:SetPoint("TOP", frame, "TOP", 0, -12)
    titleLabel:SetText(title)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local bottomPadding = editable and 50 or 16
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, bottomPadding)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scroll:GetWidth() or 440)
    editBox:SetAutoFocus(false)
    editBox:SetText(bodyText or "")
    editBox:SetCursorPosition(0)
    scroll:SetScrollChild(editBox)

    if not editable then
        editBox:SetScript("OnTextChanged", function(self)
            self:SetText(bodyText or "")
            self:HighlightText()
        end)
    end

    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    frame.editBox = editBox
    return frame
end

function UI:ShowExportFrame()
    local data = HitList:ExportCurrentGuild()
    if not data or data == "" then
        GUnit:Print("No hits to export for current guild.")
        return
    end
    if self.exportFrame then
        self.exportFrame:Hide()
        self.exportFrame = nil
    end
    self.exportFrame = CreateTextFrame("G-Unit Export (Ctrl+A, Ctrl+C)", data, false)
    self.exportFrame.editBox:HighlightText()
end

function UI:ShowImportFrame()
    if self.importFrame then
        self.importFrame:Hide()
        self.importFrame = nil
    end
    self.importFrame = CreateTextFrame("G-Unit Import (Paste & Click Import)", "", true)

    local importBtn = CreateFrame("Button", nil, self.importFrame, "UIPanelButtonTemplate")
    importBtn:SetSize(100, 24)
    importBtn:SetPoint("BOTTOMRIGHT", self.importFrame, "BOTTOMRIGHT", -12, 20)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local text = UI.importFrame.editBox:GetText()
        local count = HitList:ImportFromString(text)
        GUnit:Print("Imported " .. count .. " hit(s).")
        GUnit:NotifyDataChanged()
        UI.importFrame:Hide()
        UI.importFrame = nil
    end)
end
