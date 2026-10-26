-- Auction Coach - the gold per hour window (0.13), /ac gph.
--
--   Start / Pause / Resume / Stop   by hand only (Data/Session.lua)
--   Now       time, gold per hour, gold looted, items' value, the best items
--   History   your last sessions: when, where, how long, gold per hour
--   Minimise  the button beside the X shrinks it to the numbers only (0.20)
-- Updates every second while it's open and a session is running.

local _, ns = ...
local L, Util, Skin = ns.L, ns.Util, ns.Skin

local Window = {}
ns.SessionWindow = Window

local WIDTH, HEIGHT = 340, 400
-- Minimised: the title, gold per hour and the four lines under it.
local MINI_HEIGHT = 156
local PAD = 14
local LIST_ROWS = 10
local ROW_HEIGHT = 18

local GREY = "|cff999999"

local frame, big, lines, rows, startButton, pauseButton, stopButton, historyButton, emptyText
local buttons
local showHistory = false
local ticker

local function Clock(seconds)
    seconds = math.floor(seconds or 0)
    return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

local function ItemText(link, key, count)
    local name = link and link:match("%[(.-)%]") or key
    return ("%dx %s"):format(count, name)
end

local function Row(index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", PAD, -170 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", -PAD, 0)
    row:EnableMouse(true)
    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT", 2, 0)
    row.left:SetPoint("RIGHT", -96, 0)
    row.left:SetJustifyH("LEFT")
    row.left:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -2, 0)
    row.right:SetWidth(92)
    row.right:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if index % 2 == 0 then Skin.RowBand(row) end
    return row
end

local function Line(y)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", PAD, y)
    fs:SetPoint("RIGHT", -PAD, 0)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Big or small (ns.db.gphMini). The top edge stays put, so the window
-- shrinks up towards its title instead of towards its middle.
local function ApplySize()
    local mini = ns.db.gphMini and true or false
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    frame:SetHeight(mini and MINI_HEIGHT or HEIGHT)
    frame.listTitle:SetShown(not mini)
    emptyText:SetShown(not mini)
    for _, button in ipairs(buttons) do button:SetShown(not mini) end
    if mini then
        for _, row in ipairs(rows) do row:Hide() end
    end
end

local function SetMini(mini)
    ns.db.gphMini = mini or nil
    ApplySize()
    Window:Refresh()
end

-- Blizzard's own minimise / maximise button (the world map's), beside the X.
local function MinimiseButton()
    local ok, button = pcall(CreateFrame, "Frame", nil, frame, "MaximizeMinimizeButtonFrameTemplate")
    if not ok or not button.SetOnMinimizedCallback then return end
    button:SetPoint("RIGHT", frame.closeButton, "LEFT", 6, 0)
    button:SetOnMinimizedCallback(function() SetMini(true) end)
    button:SetOnMaximizedCallback(function() SetMini(false) end)
    if ns.db.gphMini then button:Minimize(true) end
end

local function Create()
    -- Not closed by Escape or a loading screen: it stays up while farming
    -- until closed with its X (or the button / Shift-click that opened it).
    frame = Skin.Window("AuctionCoachSessionWindow", WIDTH, HEIGHT, nil, true)
    frame.closeButton:HookScript("OnClick", function() ns.db.gphOpen = nil end)
    frame:SetPoint("CENTER", 300, 0)
    frame.title:SetText(L.GPH_TITLE)

    big = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    big:SetPoint("TOPLEFT", PAD, -42)
    lines = { Line(-76), Line(-94), Line(-112), Line(-130) }

    -- Hovering the numbers: all the gold in and out this session, by
    -- category (Data/Ledger.lua), costs like repairs included.
    local hover = CreateFrame("Frame", nil, frame)
    hover:SetPoint("TOPLEFT", PAD, -42)
    hover:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -PAD, -146)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self) Window:ShowLedgerTooltip(self) end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT", PAD, -154)
    frame.listTitle = sub

    rows = {}
    for i = 1, LIST_ROWS do rows[i] = Row(i) end
    emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", PAD, -172)
    emptyText:SetPoint("RIGHT", -PAD, 0)
    emptyText:SetJustifyH("LEFT")

    startButton = Skin.Button(frame, L.GPH_START, 74, 22)
    startButton:SetPoint("BOTTOMLEFT", PAD, 12)
    startButton:SetScript("OnClick", function() ns.Session:Start() end)
    pauseButton = Skin.Button(frame, L.GPH_PAUSE, 74, 22)
    pauseButton:SetPoint("LEFT", startButton, "RIGHT", 6, 0)
    pauseButton:SetScript("OnClick", function()
        if ns.Session:Running() then ns.Session:Pause() else ns.Session:Resume() end
    end)
    stopButton = Skin.Button(frame, L.GPH_STOP, 74, 22)
    stopButton:SetPoint("LEFT", pauseButton, "RIGHT", 6, 0)
    stopButton:SetScript("OnClick", function()
        local t = ns.Session:Stop()
        if t then Util.Print(L.GPH_STOPPED:format(Clock(t.seconds), Util.FormatMoney(t.total), t.perHour and Util.FormatMoney(t.perHour) or "-")) end
    end)
    historyButton = Skin.Button(frame, L.GPH_HISTORY, 74, 22)
    historyButton:SetPoint("BOTTOMRIGHT", -PAD, 12)
    historyButton:SetScript("OnClick", function()
        showHistory = not showHistory
        Window:Refresh()
    end)
    buttons = { startButton, pauseButton, stopButton, historyButton }

    MinimiseButton()
    ApplySize()

    frame:HookScript("OnShow", function()
        if not ticker then ticker = C_Timer.NewTicker(1, function() Window:Refresh() end) end
    end)
    frame:HookScript("OnHide", function()
        if ticker then ticker:Cancel() ticker = nil end
    end)
end

local function ShowRows(list)
    for i, row in ipairs(rows) do
        local item = list[i]
        row:SetShown(item ~= nil and not ns.db.gphMini)
        if item then
            row.left:SetText(item.left)
            row.right:SetText(item.right)
            row.link = item.link
        end
    end
end

function Window:Refresh()
    if not frame or not frame:IsShown() then return end
    local session = ns.Session:Current()
    local running = ns.Session:Running()
    startButton:SetEnabled(session == nil)
    pauseButton:SetEnabled(session ~= nil)
    pauseButton:SetText(session and not running and L.GPH_RESUME or L.GPH_PAUSE)
    stopButton:SetEnabled(session ~= nil)
    historyButton:SetText(showHistory and L.GPH_NOW or L.GPH_HISTORY)

    local t = session and ns.Session:Totals(session)
    if t then
        big:SetText(t.perHour and L.GPH_PER_HOUR:format(Util.FormatMoney(t.perHour)) or L.GPH_PER_HOUR:format("-"))
        lines[1]:SetText(L.GPH_TIME:format(Clock(t.seconds)) .. (running and "" or ("  " .. GREY .. L.GPH_PAUSED .. "|r")))
        lines[2]:SetText(L.GPH_TOTAL:format(Util.FormatMoney(t.total)))
        lines[3]:SetText(L.GPH_MONEY:format(Util.FormatMoney(t.money)))
        lines[4]:SetText(L.GPH_ITEMS:format(t.items, Util.FormatMoney(t.value)))
    else
        big:SetText(L.GPH_PER_HOUR:format("-"))
        lines[1]:SetText(L.GPH_IDLE)
        for i = 2, 4 do lines[i]:SetText("") end
    end

    local list = {}
    if showHistory then
        frame.listTitle:SetText(L.GPH_HISTORY_TITLE)
        for _, h in ipairs(ns.Session:History()) do
            if #list >= LIST_ROWS then break end
            local perHour = h.duration > 0 and math.floor((h.money + h.value) / h.duration * 3600) or 0
            list[#list + 1] = {
                left = ("%s  %s  %s"):format(date("%d %b", h.at or 0), h.zone or "?", GREY .. Clock(h.duration) .. "|r"),
                right = L.GPH_PER_HOUR_SHORT:format(Util.FormatMoney(perHour)),
            }
        end
        emptyText:SetText(#list == 0 and L.GPH_NO_HISTORY or "")
    else
        frame.listTitle:SetText(L.GPH_TOP_TITLE)
        for _, item in ipairs(t and t.top or {}) do
            list[#list + 1] = { left = ItemText(item.link, item.key, item.count), right = Util.FormatMoney(item.value), link = item.link }
        end
        emptyText:SetText(#list == 0 and (t and L.GPH_NO_ITEMS or L.GPH_HOW) or "")
    end
    ShowRows(list)
end

function Window:Toggle()
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
    ns.db.gphOpen = frame:IsShown() or nil
    self:Refresh()
end

function Window:Show()
    if not frame then Create() end
    frame:Show()
    ns.db.gphOpen = true
    self:Refresh()
end

-- Open again after a zone change, portal, /reload or login when it was
-- open before and there's a session to show.
ns.Events:On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(0, function()
        if ns.db and ns.db.gphOpen and ns.Session:Current() and not (frame and frame:IsShown()) then
            Window:Show()
        end
    end)
end)

function Window:ShowLedgerTooltip(owner)
    local s = ns.Session:Current()
    local ledger = s and s.ledger
    if not ledger or not next(ledger) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.LEDGER_SESSION, 1, 0.82, 0)
    local net = 0
    for _, cat in ipairs(ns.Ledger.CATEGORIES) do
        local entry = ledger[cat]
        if entry then
            net = net + entry[1] - entry[2]
            if entry[1] > 0 then GameTooltip:AddDoubleLine(L["LEDGER_CAT_" .. cat], "+" .. Util.FormatMoney(entry[1]), 1, 1, 1, 0.4, 1, 0.4) end
            if entry[2] > 0 then GameTooltip:AddDoubleLine(L["LEDGER_CAT_" .. cat], "-" .. Util.FormatMoney(entry[2]), 1, 1, 1, 1, 0.4, 0.4) end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.LEDGER_SESSION_NET:format((net < 0 and "-" or "+") .. Util.FormatMoney(math.abs(net))), 1, 1, 1)
    GameTooltip:Show()
end

-- One line for tooltips (the main window's button, the minimap button):
-- the running or paused session, or nil when there is none.
function Window:StatusLine()
    local s = ns.Session:Current()
    if not s then return nil end
    local t = ns.Session:Totals(s)
    local rate = t and t.perHour and L.GPH_PER_HOUR:format(Util.FormatMoney(t.perHour)) or "-"
    if ns.Session:Running() then
        return L.GPH_STATUS_RUNNING:format(Clock(t and t.seconds), rate)
    end
    return L.GPH_STATUS_PAUSED:format(Clock(t and t.seconds), rate)
end

ns.Events:On("AC_SESSION_CHANGED", function() Window:Refresh() end)

-- /ac gph [start | pause | stop]
ns:RegisterCommand("gph", function(args)
    local action = (args or ""):lower()
    if action == "start" then
        ns.Session:Start()
        Window:Show()
    elseif action == "pause" then
        if ns.Session:Running() then ns.Session:Pause() else ns.Session:Resume() end
    elseif action == "stop" then
        local t = ns.Session:Stop()
        if t then Util.Print(L.GPH_STOPPED:format(Clock(t.seconds), Util.FormatMoney(t.total), t.perHour and Util.FormatMoney(t.perHour) or "-")) end
    else
        Window:Toggle()
    end
end, L.HELP_GPH)
