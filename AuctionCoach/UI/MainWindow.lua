-- Auction Coach - main window with a simple tab strip.
-- Tabs register themselves with MainWindow:AddTab, in .toc order: Today,
-- My Stuff, Sell, Deals and Auctions. Tabs can be hidden in the options
-- (settings.hiddenTabs). The window can be dragged bigger from its
-- bottom right corner, never smaller than WIDTH x HEIGHT; size and place
-- are kept in settings.mainSize / mainPoint, and list columns grow with
-- it (Skin.Columns, AC_WINDOW_RESIZED).

local _, ns = ...
local L = ns.L

local MainWindow = {}
ns.MainWindow = MainWindow

local WIDTH, HEIGHT = 640, 516
local MAX_WIDTH, MAX_HEIGHT = 1400, 1000
local TAB_WIDTH, TAB_HEIGHT = 92, 24
-- Title row, then the tab row, then the open tab's panel.
local TABS_Y = -44

local frame
local tabs = {}
local activeTab
local priceStatus
local UpdateGphButton

-- How old the prices are, beside the close button: grey, or amber when old
-- (the desktop app has probably stopped).
local function UpdatePriceStatus()
    if not priceStatus then return end
    local text, old = ns.Freshness:StatusText()
    priceStatus:SetText(text)
    if old then
        priceStatus:SetTextColor(1, 0.65, 0.2)
    else
        priceStatus:SetTextColor(0.6, 0.6, 0.6)
    end
end

-- def = { name, Build = function(panel), Refresh = function(panel) }
function MainWindow:AddTab(def)
    table.insert(tabs, def)
end

-- Tab names in order, for the options page.
function MainWindow:TabNames()
    local names = {}
    for i, tab in ipairs(tabs) do names[i] = tab.name end
    return names
end

-- How much wider than its smallest size the window is.
function MainWindow:Extra()
    return frame and math.max(0, math.floor(frame:GetWidth() - WIDTH + 0.5)) or 0
end

local function Hidden(tab)
    local hidden = ns.db.settings.hiddenTabs
    return hidden ~= nil and hidden[tab.name] == true
end

-- Visible tab buttons left to right; a hidden tab's button goes away
-- (its slash command still opens it). At least one always shows.
local function LayoutTabs()
    local shown = 0
    for _, tab in ipairs(tabs) do
        if not Hidden(tab) then shown = shown + 1 end
    end
    local x = 0
    for i, tab in ipairs(tabs) do
        local show = shown == 0 and i == 1 or not Hidden(tab)
        tab.button:SetShown(show)
        if show then
            tab.button:SetPoint("TOPLEFT", 16 + x * (TAB_WIDTH + 4), TABS_Y)
            x = x + 1
        end
    end
end

local function FirstShown()
    for i, tab in ipairs(tabs) do
        if tab.button:IsShown() then return i end
    end
    return 1
end

local function SavePlace()
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then ns.db.settings.mainPoint = { left, top } end
    ns.db.settings.mainSize = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
end

-- Bottom right grip: drag to make the window bigger or smaller.
local function SizeGrip()
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePlace()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.WINDOW_RESIZE_TIP)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function SelectTab(index)
    activeTab = index
    for i, tab in ipairs(tabs) do
        tab.panel:SetShown(i == index)
        tab.button:SetActive(i == index)
    end
    MainWindow:Refresh()
end

local function Create()
    frame = ns.Skin.Window("AuctionCoachMainWindow", WIDTH, HEIGHT)
    frame.title:SetText(L.ADDON_TITLE)
    local size, point = ns.db.settings.mainSize, ns.db.settings.mainPoint
    if type(size) == "table" and size[1] then
        frame:SetSize(math.max(WIDTH, math.min(MAX_WIDTH, size[1])), math.max(HEIGHT, math.min(MAX_HEIGHT, size[2])))
    end
    if type(point) == "table" and point[1] then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", point[1], point[2])
    else
        frame:SetPoint("CENTER")
    end
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(WIDTH, HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    end
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePlace()
    end)
    frame:SetScript("OnSizeChanged", function()
        ns.Events:Fire("AC_WINDOW_RESIZED", MainWindow:Extra())
    end)
    SizeGrip()

    for i, tab in ipairs(tabs) do
        local button = ns.Skin.Tab(frame, tab.name, TAB_WIDTH, TAB_HEIGHT)
        button:SetPoint("TOPLEFT", 16 + (i - 1) * (TAB_WIDTH + 4), TABS_Y)
        button:SetScript("OnClick", function() SelectTab(i) end)
        tab.button = button

        local panel = CreateFrame("Frame", nil, frame)
        panel:SetPoint("TOPLEFT", 14, TABS_Y - TAB_HEIGHT - 10)
        panel:SetPoint("BOTTOMRIGHT", -14, 12)
        panel:Hide()
        tab.panel = panel
        tab.Build(panel)
    end

    -- Gold per hour, at the end of the tab row: its own window, so a
    -- button rather than a tab. Green while a session is running.
    local gph = ns.Skin.Button(frame, L.GPH_TITLE, 118, TAB_HEIGHT)
    gph:SetPoint("TOPRIGHT", -16, TABS_Y)
    gph:SetScript("OnClick", function() if ns.SessionWindow then ns.SessionWindow:Toggle() end end)
    gph:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.GPH_TITLE)
        local status = ns.SessionWindow and ns.SessionWindow:StatusLine()
        GameTooltip:AddLine(status or L.GPH_BUTTON_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    gph:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.gphButton = gph

    -- Divider under the tab row.
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.06)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 16, TABS_Y - TAB_HEIGHT - 4)
    divider:SetPoint("TOPRIGHT", -16, TABS_Y - TAB_HEIGHT - 4)

    -- How old the prices are, beside the close button.
    priceStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceStatus:SetPoint("RIGHT", frame.closeButton, "LEFT", -6, 0)
    priceStatus:SetJustifyH("RIGHT")

    -- Hooked, not set: Skin.Window already re-snaps the border on show.
    frame:HookScript("OnShow", function()
        UpdateGphButton()
        MainWindow:Refresh()
    end)
    LayoutTabs()
    SelectTab(FirstShown())
end

-- After the hidden tabs change in the options.
function MainWindow:UpdateTabs()
    if not frame then return end
    LayoutTabs()
    if not tabs[activeTab].button:IsShown() then SelectTab(FirstShown()) end
end

-- The gold per hour button's label: green while a session is running.
UpdateGphButton = function()
    local button = frame and frame.gphButton
    if not button then return end
    button:SetNormalFontObject(ns.Session and ns.Session:Running() and GameFontGreen or GameFontNormal)
end
ns.Events:On("AC_SESSION_CHANGED", UpdateGphButton)

function MainWindow:IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Opens the window on the tab with this name.
function MainWindow:ShowTab(name)
    if not ns.db then return end
    if not frame then Create() end
    for i, tab in ipairs(tabs) do
        if tab.name == name then
            SelectTab(i)
            break
        end
    end
    frame:Show()
end

function MainWindow:Toggle()
    if not ns.db then return end
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end

-- Event refreshes are gathered into one. Events come in bursts at the
-- Auction House (every search is a live price, one per item level for
-- gear) and each refresh rebuilds the open tab from scratch, so several in
-- one frame stalled the game. One refresh runs SOON after the first event;
-- live prices on their own redraw at most every LIVE_EVERY seconds, and any
-- other event brings a waiting refresh forward.
local SOON, LIVE_EVERY = 0.3, 5
local pending, pendingReason, pendingLive = nil, nil, false
local lastRefreshAt = 0

local function CancelPending()
    if pending then pending:Cancel() end
    pending, pendingReason, pendingLive = nil, nil, false
end

-- reason is the event that triggered the refresh, or nil for a full one.
function MainWindow:Refresh(reason)
    if not self:IsShown() or not activeTab then return end
    if reason ~= "AC_SCAN_PROGRESS" then
        CancelPending()
        lastRefreshAt = GetTime()
    end
    UpdatePriceStatus()
    local tab = tabs[activeTab]
    if tab.Refresh then tab.Refresh(tab.panel, reason) end
end

local function Schedule(delay)
    pending = C_Timer.NewTimer(delay, function()
        local reason = pendingReason or nil
        pending, pendingReason, pendingLive = nil, nil, false
        MainWindow:Refresh(reason)
    end)
end

local function RefreshIfShown(event)
    if not MainWindow:IsShown() then return end
    -- Scan progress only updates the status line, which is cheap.
    if event == "AC_SCAN_PROGRESS" then return MainWindow:Refresh(event) end
    local live = event == "AC_LIVE_PRICE"
    if pending then
        -- false: more than one kind of event, so a full refresh.
        if pendingReason ~= event then pendingReason = false end
        if pendingLive and not live then
            pending:Cancel()
            pendingLive = false
            Schedule(SOON)
        end
        return
    end
    pendingReason, pendingLive = event, live
    Schedule(live and math.max(SOON, LIVE_EVERY - (GetTime() - lastRefreshAt)) or SOON)
end

local refreshEvents = {}

-- Refresh the open tab when this event fires (each event only once).
function MainWindow:RefreshOn(event)
    if refreshEvents[event] then return end
    refreshEvents[event] = true
    ns.Events:On(event, RefreshIfShown)
end

for _, event in ipairs({
    "AC_SCAN_COMPLETE", "AC_SCAN_PROGRESS", "AC_INVENTORY_CHANGED", "AC_DATA_CHANGED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
}) do
    MainWindow:RefreshOn(event)
end

-- Open with the Auction House when the player asked for it, and close with
-- it again, but only when it was the AH that opened the window.
local openedByAH = false
ns.Events:On("AUCTION_HOUSE_SHOW", function()
    if not ns.db or not ns.db.settings.openWithAH or MainWindow:IsShown() then return end
    MainWindow:Toggle()
    openedByAH = MainWindow:IsShown()
end)
ns.Events:On("AUCTION_HOUSE_CLOSED", function()
    if openedByAH and MainWindow:IsShown() then frame:Hide() end
    openedByAH = false
end)

-- Rows show "Loading item..." until the client has the item's name. Redraw
-- once the names asked for have arrived.
ns.Events:On("GET_ITEM_INFO_RECEIVED", function()
    if not ns.Util.NamesPending() then return end
    ns.Util.Debounce("itemNames", 0.5, function()
        ns.Util.ClearNamesPending()
        MainWindow:Refresh()
    end)
end)
