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
        local owed = math.max(0, (data.totalCopper or 0) - (data.paidCopper or 0))
        local paid = data.paidCopper or 0
        local status = owed > 0 and ("owed " .. Utils.GoldStringFromCopper(owed)) or "PAID"
        local line = killer .. ": " .. Utils.GoldStringFromCopper(data.totalCopper) .. " (" .. (data.claimCount or 0) .. " kill) - " .. status
        if paid > 0 and owed > 0 then
            line = line .. " (paid " .. Utils.GoldStringFromCopper(paid) .. ")"
        end
        table.insert(lines, line)
    end
    table.sort(lines)
    if #lines == 0 then
        return "None"
    end
    return table.concat(lines, "\n")
end

local function FormatBountyColumn(target)
    local amount = target.bountyAmount or 0
    if amount <= 0 then return "None" end
    local status = target.bountyStatus or "open"
    -- Check if all claims are fully paid
    local allPaid = true
    if target.bountyClaims then
        for _, claim in pairs(target.bountyClaims) do
            if (claim.totalCopper or 0) - (claim.paidCopper or 0) > 0 then
                allPaid = false
                break
            end
        end
    end
    local label
    if status == "claimed" and allPaid then
        label = "Paid"
    elseif status == "claimed" then
        label = "Owed"
    else
        label = "Open"
    end
    return Utils.GoldStringFromCopper(amount) .. " (" .. label .. ")"
end

function UI:RefreshList()
    self.names = HitList:SortedNamesForCurrentGuild()
    local startIndex = self.pageOffset + 1

    -- Update title with current guild
    if self.title then
        local guildTitle = Utils.GuildName() or "Personal"
        self.title:SetText(guildTitle .. " Kill Targets")
    end

    for rowIndex = 1, ROWS_PER_PAGE do
        local listIndex = startIndex + rowIndex - 1
        local row = self.rows[rowIndex]
        local name = self.names[listIndex]
        if name then
            local target = HitList:Get(name)
            row.name = name
            row.colName:SetText(name)
            row.colRace:SetText(target.race or "-")
            row.colClass:SetText(target.classToken or "-")
            local statusLabels = { active = "Active", completed = "Done", closed = "Closed" }
            row.colStatus:SetText(statusLabels[target.hitStatus] or "Active")
            row.colBounty:SetText(FormatBountyColumn(target))
            row.colSubmitter:SetText(target.submitter or "-")
            row:Show()
        else
            row.name = nil
            row.colName:SetText("")
            row.colRace:SetText("")
            row.colClass:SetText("")
            row.colStatus:SetText("")
            row.colBounty:SetText("")
            row.colSubmitter:SetText("")
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
        if self.hitModeDropdown then UIDropDownMenu_SetText(self.hitModeDropdown, "Kill on Sight") end
        if self.bountyModeDropdown then UIDropDownMenu_SetText(self.bountyModeDropdown, "Bounty Payout") end
        if self.callOffButton then self.callOffButton:Hide() end
        if self.reopenButton then self.reopenButton:Hide() end
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
        "Hit Status: " .. ({ active = "Active", completed = "Done", closed = "Closed" })[target.hitStatus or "active"] or "Active",
        "Bounty Status: " .. (target.bountyStatus or "open"),
        "Class/Race/Faction: " .. classLine .. " / " .. raceLine .. " / " .. factionLine,
        "Kill Count: " .. (target.killCount or 0),
        "Bounty Owed:",
        BuildClaimsText(target),
    }, "\n")

    self.detailText:SetText(detail)
    self.reasonEdit:SetText(target.reason or "")
    self.bountyEdit:SetText(tostring(math.floor((target.bountyAmount or 0) / 10000)))

    local hitModeLabel = target.hitMode == "kos" and "Indefinitely" or "One-time"
    if self.hitModeDropdown then UIDropDownMenu_SetText(self.hitModeDropdown, hitModeLabel) end

    local bountyModeLabels = { none = "None", first_kill = "One-time", infinite = "Indefinitely" }
    local bountyLabel = bountyModeLabels[target.bountyMode] or "None"
    if self.bountyModeDropdown then UIDropDownMenu_SetText(self.bountyModeDropdown, bountyLabel) end

    local isSubmitter = Utils.IsSubmitter(target)
    local isActive = target.hitStatus == "active"

    if self.callOffButton then
        if isSubmitter and isActive then
            self.callOffButton:Show()
        else
            self.callOffButton:Hide()
        end
    end
    if self.reopenButton then
        if isSubmitter and not isActive then
            self.reopenButton:Show()
        else
            self.reopenButton:Hide()
        end
    end
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

    self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.title:SetPoint("TOP", frame, "TOP", 0, -12)
    local guildTitle = Utils.GuildName() or "Personal"
    self.title:SetText(guildTitle .. " Kill Targets")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    self.pageOffset = 0
    self.names = {}
    self.rows = {}
    self.selectedName = nil

    -- Column headers
    local COL_NAME_X = 16
    local COL_RACE_X = 120
    local COL_CLASS_X = 190
    local COL_STATUS_X = 260
    local COL_BOUNTY_X = 330
    local COL_SUBMITTER_X = 400

    local colY = -40
    local colName = MakeLabel(frame, "Name", COL_NAME_X, colY)
    colName:SetTextColor(1, 0.8, 0.1)
    local colRace = MakeLabel(frame, "Race", COL_RACE_X, colY)
    colRace:SetTextColor(1, 0.8, 0.1)
    local colClass = MakeLabel(frame, "Class", COL_CLASS_X, colY)
    colClass:SetTextColor(1, 0.8, 0.1)
    local colStatus = MakeLabel(frame, "Status", COL_STATUS_X, colY)
    colStatus:SetTextColor(1, 0.8, 0.1)
    local colBounty = MakeLabel(frame, "Bounty", COL_BOUNTY_X, colY)
    colBounty:SetTextColor(1, 0.8, 0.1)
    local colSubmitter = MakeLabel(frame, "Submitter", COL_SUBMITTER_X, colY)
    colSubmitter:SetTextColor(1, 0.8, 0.1)

    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(440, 22)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -56 - ((i - 1) * 24))
        row.colName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.colName:SetPoint("LEFT", row, "LEFT", COL_NAME_X, 0)
        row.colName:SetWidth(100)
        row.colName:SetJustifyH("LEFT")

        row.colRace = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.colRace:SetPoint("LEFT", row, "LEFT", COL_RACE_X, 0)
        row.colRace:SetWidth(66)
        row.colRace:SetJustifyH("LEFT")

        row.colClass = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.colClass:SetPoint("LEFT", row, "LEFT", COL_CLASS_X, 0)
        row.colClass:SetWidth(66)
        row.colClass:SetJustifyH("LEFT")

        row.colStatus = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.colStatus:SetPoint("LEFT", row, "LEFT", COL_STATUS_X, 0)
        row.colStatus:SetWidth(66)
        row.colStatus:SetJustifyH("LEFT")

        row.colBounty = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.colBounty:SetPoint("LEFT", row, "LEFT", COL_BOUNTY_X, 0)
        row.colBounty:SetWidth(66)
        row.colBounty:SetJustifyH("LEFT")

        row.colSubmitter = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.colSubmitter:SetPoint("LEFT", row, "LEFT", COL_SUBMITTER_X, 0)
        row.colSubmitter:SetWidth(66)
        row.colSubmitter:SetJustifyH("LEFT")

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
    local reasonScroll = CreateFrame("ScrollFrame", "GUnitReasonScroll", frame, "UIPanelScrollFrameTemplate")
    reasonScroll:SetSize(320, 60)
    reasonScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -316)

    self.reasonEdit = CreateFrame("EditBox", "GUnitReasonEdit", reasonScroll)
    self.reasonEdit:SetMultiLine(true)
    self.reasonEdit:SetFontObject("ChatFontNormal")
    self.reasonEdit:SetWidth(300)
    self.reasonEdit:SetAutoFocus(false)
    self.reasonEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    self.reasonEdit:SetScript("OnEditFocusLost", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local newReason = UI.reasonEdit:GetText()
        if newReason == (target.reason or "") then return end
        local updated, err = HitList:SetReason(target.name, newReason, Utils.PlayerName())
        if not updated then return end
        SaveTargetAndBroadcast(updated)
    end)
    reasonScroll:SetScrollChild(self.reasonEdit)

    -- Reason box backdrop
    local reasonBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    reasonBg:SetPoint("TOPLEFT", reasonScroll, "TOPLEFT", -4, 4)
    reasonBg:SetPoint("BOTTOMRIGHT", reasonScroll, "BOTTOMRIGHT", 22, -4)
    reasonBg:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    reasonBg:SetBackdropColor(0, 0, 0, 0.5)
    reasonBg:SetFrameLevel(frame:GetFrameLevel())

    MakeLabel(frame, "Bounty (gold)", 460, -392)
    self.bountyEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    self.bountyEdit:SetSize(120, 24)
    self.bountyEdit:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -408)
    self.bountyEdit:SetAutoFocus(false)
    self.bountyEdit:SetNumeric(true)
    self.bountyEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    self.bountyEdit:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    self.bountyEdit:SetScript("OnEditFocusLost", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local gold = tonumber(UI.bountyEdit:GetText())
        if not gold or gold < 0 then return end
        local copper = gold * 10000
        if copper == (target.bountyAmount or 0) then return end
        local updated, err = HitList:SetBountyAmount(target.name, copper, Utils.PlayerName())
        if not updated then return end
        SaveTargetAndBroadcast(updated)
    end)

    -- Kill on Sight dropdown
    MakeLabel(frame, "Kill on Sight", 460, -442)
    self.hitModeDropdown = CreateFrame("Frame", "GUnitHitModeDropdown", frame, "UIDropDownMenuTemplate")
    self.hitModeDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 548, -438)
    UIDropDownMenu_SetWidth(self.hitModeDropdown, 100)
    UIDropDownMenu_SetText(self.hitModeDropdown, "One-time")
    UIDropDownMenu_Initialize(self.hitModeDropdown, function(dropdown, level)
        local options = {
            { text = "One-time", value = "one_time" },
            { text = "Indefinitely", value = "kos" },
        }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                local target = RequireSelectedTarget()
                if not target then return end
                local updated, err = HitList:SetHitMode(target.name, btn.value, Utils.PlayerName())
                if not updated then
                    GUnit:Print(err)
                    return
                end
                UIDropDownMenu_SetText(dropdown, btn:GetText())
                SaveTargetAndBroadcast(updated)
            end
            info.checked = nil
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Bounty Payout dropdown
    MakeLabel(frame, "Bounty Payout", 460, -474)
    self.bountyModeDropdown = CreateFrame("Frame", "GUnitBountyModeDropdown", frame, "UIDropDownMenuTemplate")
    self.bountyModeDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 548, -470)
    UIDropDownMenu_SetWidth(self.bountyModeDropdown, 100)
    UIDropDownMenu_SetText(self.bountyModeDropdown, "None")
    UIDropDownMenu_Initialize(self.bountyModeDropdown, function(dropdown, level)
        local options = {
            { text = "None", value = "none" },
            { text = "One-time", value = "first_kill" },
            { text = "Indefinitely", value = "infinite" },
        }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.func = function(btn)
                local target = RequireSelectedTarget()
                if not target then return end
                local updated, err = HitList:SetBountyMode(target.name, btn.value, Utils.PlayerName())
                if not updated then
                    GUnit:Print(err)
                    return
                end
                UIDropDownMenu_SetText(dropdown, btn:GetText())
                SaveTargetAndBroadcast(updated)
            end
            info.checked = nil
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Call Off button (active hits only, submitter only)
    self.callOffButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.callOffButton:SetSize(100, 24)
    self.callOffButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 460, -504)
    self.callOffButton:SetText("Call Off")
    self.callOffButton:Hide()
    self.callOffButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        -- Store target name for the confirmation dialog
        UI._callOffTargetName = target.name
        StaticPopup_Show("GUNIT_CALL_OFF_CONFIRM", target.name)
    end)

    -- Re-open button (completed/closed hits only, submitter only)
    self.reopenButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    self.reopenButton:SetSize(100, 24)
    self.reopenButton:SetPoint("LEFT", self.callOffButton, "RIGHT", 8, 0)
    self.reopenButton:SetText("Re-open")
    self.reopenButton:Hide()
    self.reopenButton:SetScript("OnClick", function()
        local target = RequireSelectedTarget()
        if not target then return end
        local updated, err = HitList:SetHitStatus(target.name, "active", Utils.PlayerName())
        if not updated then
            GUnit:Print(err)
            return
        end
        SaveTargetAndBroadcast(updated)
        Utils.SendGuildChat(Utils.PlayerName() .. " has re-opened the hit on " .. target.name .. ".")
    end)

    -- Call Off confirmation dialog
    StaticPopupDialogs["GUNIT_CALL_OFF_CONFIRM"] = {
        text = "Are you sure you want to call off the hit on %s?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            local targetName = UI._callOffTargetName
            if not targetName then return end
            local target = HitList:Get(targetName)
            if not target then return end

            local hasKills = (target.killCount or 0) > 0
            if hasKills then
                local updated, err = HitList:SetHitStatus(targetName, "closed", Utils.PlayerName())
                if updated then
                    Comm:BroadcastUpsert(updated)
                    GUnit:Print("Hit on " .. targetName .. " closed (kill history preserved).")
                    Utils.SendGuildChat(Utils.PlayerName() .. " has closed the hit on " .. targetName .. ".")
                end
            else
                HitList:Delete(targetName)
                Comm:BroadcastDelete(targetName)
                GUnit:Print("Hit on " .. targetName .. " has been called off.")
                Utils.SendGuildChat(Utils.PlayerName() .. " has called off the hit on " .. targetName .. ".")
            end
            UI.selectedName = nil
            UI._callOffTargetName = nil
            GUnit:NotifyDataChanged()
        end,
        OnCancel = function()
            UI._callOffTargetName = nil
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

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
