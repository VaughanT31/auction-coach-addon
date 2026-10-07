-- Auction Coach - "Today" tab: Today's Plan (Advice/Plan.lua).
-- Pick how much time you have, get a ranked to-do list with the gold each
-- step should make. Steps can be ticked off; at the AH, clicking a step
-- starts it (puts the item in the sell box, or opens its listings).

local _, ns = ...
local L, Util, Compat, Phrases = ns.L, ns.Util, ns.Compat, ns.Phrases

local ROW_HEIGHT = 24
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- Column layout: x offset and width, shared by header and rows.
local COLUMNS = {
    tag = { 26, 52 },
    name = { 102, 190 },
    reason = { 298, 200 },
    gold = { 500, 80 },
}

local TAG_COLORS = {
    POST = { 0.4, 1, 0.4 },
    REPOST = { 1, 0.82, 0 },
    BUY = { 0.4, 0.7, 1 },
    VENDOR = { 0.75, 0.75, 0.75 },
    SKIP = { 0.55, 0.55, 0.55 },
}

local function Column(parent, name, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetPoint("LEFT", COLUMNS[name][1], 0)
    fs:SetWidth(COLUMNS[name][2])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function ShowRowTooltip(row)
    local step = row.step
    if not step then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local link = step.key and Util.NamedLink(step.key)
    if link and link:find("item:") then
        GameTooltip:SetHyperlink(link)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
    else
        GameTooltip:SetText(L.ADDON_TITLE, 1, 0.82, 0)
    end
    for _, line in ipairs(Phrases.PlanDetails(step)) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end
    if step.kind ~= "SKIP" then
        GameTooltip:AddLine(L.PLAN_DONE_TIP, 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
end

local function StartStep(step)
    if not step or not step.key then return false end
    if step.kind == "POST" then
        return ns.Sell:PutInSellBox(step.key)
    elseif step.kind == "REPOST" or step.kind == "BUY" then
        return Compat.ShowAtAuctionHouse(step.key, Util.NamedLink(step.key), step.price)
    end
    return false
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT")

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
        if row.step then
            ns.Plan:SetDone(row.step.id, self:GetChecked())
            row:SetAlpha(self:GetChecked() and 0.45 or 1)
        end
    end)

    row.tag = Column(row, "tag", "GameFontNormalSmall")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 80, 0)
    row.name = Column(row, "name", "GameFontHighlight")
    row.reason = Column(row, "reason", "GameFontHighlightSmall")
    row.gold = Column(row, "gold", "GameFontHighlight", "RIGHT")

    -- Section heading text ("Leave alone today").
    row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.heading:SetPoint("LEFT", 4, -2)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row.highlight = highlight

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if StartStep(self.step) then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end)
    return row
end

local function SetHeading(row, text)
    row.step = nil
    row.check:Hide()
    row.tag:SetText("")
    row.icon:Hide()
    row.name:SetText("")
    row.reason:SetText("")
    row.gold:SetText("")
    row.heading:SetText(text)
    row.highlight:Hide()
    row:EnableMouse(false)
    row:SetAlpha(1)
    row:Show()
end

local function SetStep(row, step)
    row.step = step
    row.heading:SetText("")
    row.highlight:Show()
    row:EnableMouse(true)

    local color = TAG_COLORS[step.kind]
    row.tag:SetText(L["PLAN_TAG_" .. step.kind])
    row.tag:SetTextColor(color[1], color[2], color[3])

    row.icon:Show()
    if step.kind == "VENDOR" then
        row.icon:SetTexture(COIN_ICON)
        row.name:SetText(L.PLAN_VENDOR_ITEMS:format(step.count))
    else
        local itemID = Util.ItemIDFromKey(step.key) or Util.PET_CAGE_ITEM_ID
        row.icon:SetTexture(Compat.GetItemIconByID(itemID))
        local name = Util.NamedLink(step.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
        if step.count and step.count > 1 then name = name .. " x" .. step.count end
        row.name:SetText(name)
    end

    row.reason:SetText(Phrases.PlanShort(step, Util.FormatMoneyIcons))
    row.gold:SetText(step.gold and step.gold > 0 and ("|cff66ff66+" .. Util.FormatMoneyIcons(step.gold) .. "|r") or "")

    if step.kind == "SKIP" then
        row.check:Hide()
        row:SetAlpha(0.8)
    else
        local done = ns.Plan:IsDone(step.id)
        row.check:Show()
        row.check:SetChecked(done)
        row:SetAlpha(done and 0.45 or 1)
    end
    row:Show()
end

local function UpdateTimeButtons(panel)
    local current = ns.db.settings.planMinutes or 15
    for _, button in ipairs(panel.timeButtons) do
        button:SetEnabled(button.minutes ~= current)
    end
end

local function Build(panel)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 4, -4)

    -- Time buttons, right to left from the panel's top right corner.
    panel.timeButtons = {}
    local previous
    for i = #ns.Plan.BUDGETS, 1, -1 do
        local minutes = ns.Plan.BUDGETS[i]
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(54, 20)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -2, 0)
        else
            button:SetPoint("TOPRIGHT", -4, -2)
        end
        button:SetText(L.PLAN_MINUTES:format(minutes))
        button.minutes = minutes
        button:SetScript("OnClick", function()
            ns.db.settings.planMinutes = minutes
            ns.MainWindow:Refresh()
        end)
        table.insert(panel.timeButtons, button)
        previous = button
    end
    local timeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeLabel:SetPoint("RIGHT", previous, "LEFT", -6, 0)
    timeLabel:SetText(L.PLAN_TIME)

    panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -8)
    panel.sub:SetPoint("RIGHT", -4, 0)
    panel.sub:SetJustifyH("LEFT")

    panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.footer:SetPoint("BOTTOMLEFT", 4, 4)
    panel.footer:SetPoint("RIGHT", -4, 0)
    panel.footer:SetJustifyH("LEFT")
    panel.footer:SetTextColor(0.75, 0.75, 0.75)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel.sub, "BOTTOMLEFT", 0, -10)
    scroll:SetPoint("BOTTOMRIGHT", -26, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    panel.content = content
    panel.rows = {}

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    panel.empty:SetPoint("RIGHT", -30, 0)
    panel.empty:SetJustifyH("LEFT")
end

local function ElsewhereText(elsewhere)
    local parts = {}
    for i = 1, math.min(#elsewhere, 3) do
        local o = elsewhere[i]
        local who = o.owner == "warband" and L.TREASURE_WARBAND or (o.owner:match("^(.-)%-") or o.owner)
        parts[#parts + 1] = who .. " " .. Util.FormatMoneyIcons(o.value)
    end
    return L.PLAN_ELSEWHERE:format(table.concat(parts, ", "))
end

local function Refresh(panel, reason)
    if reason == "AC_SCAN_PROGRESS" then return end
    UpdateTimeButtons(panel)
    local plan = ns.Plan:Build()

    if #plan.steps > 0 then
        panel.title:SetText(L.PLAN_TITLE:format(Util.FormatMoneyIcons(plan.gold), Util.FormatDuration(plan.seconds)))
    else
        panel.title:SetText(L.PLAN_TITLE_EMPTY)
    end
    panel.sub:SetText(L.PLAN_SUB:format(plan.budget)
        .. (Compat.IsAuctionHouseOpen() and (" " .. L.PLAN_SUB_AH) or ""))
    panel.empty:SetText((#plan.steps == 0 and #plan.skips == 0) and L.PLAN_EMPTY or "")

    local notes = {}
    if plan.left > 0 then notes[#notes + 1] = L.PLAN_LEFT:format(plan.left) end
    if #plan.elsewhere > 0 then notes[#notes + 1] = ElsewhereText(plan.elsewhere) end
    if #plan.steps > 0 and not plan.hasSpeed then notes[#notes + 1] = L.PLAN_NO_SPEED end
    panel.footer:SetText(table.concat(notes, "\n"))

    local n = 0
    local function NextRow()
        n = n + 1
        local row = panel.rows[n] or CreateRow(panel.content, n)
        panel.rows[n] = row
        return row
    end
    for _, step in ipairs(plan.steps) do SetStep(NextRow(), step) end
    if #plan.skips > 0 then
        SetHeading(NextRow(), L.PLAN_SKIP_HEADER)
        for _, step in ipairs(plan.skips) do SetStep(NextRow(), step) end
    end
    for i = n + 1, #panel.rows do
        panel.rows[i]:Hide()
    end
    panel.content:SetHeight(math.max(1, n * ROW_HEIGHT))
end

ns.MainWindow:AddTab({ name = L.TAB_PLAN, Build = Build, Refresh = Refresh })
ns.MainWindow:RefreshOn("AC_LIVE_PRICE")
ns.MainWindow:RefreshOn("OWNED_AUCTIONS_UPDATED")

ns:RegisterCommand("plan", function() ns.MainWindow:ShowTab(L.TAB_PLAN) end, L.HELP_PLAN)
