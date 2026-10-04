-- Auction Coach - main window with a simple tab strip.
-- Tabs register themselves with MainWindow:AddTab: My Stuff, Sell and
-- Deals so far, Today's Plan arrives in a later version.

local _, ns = ...
local L = ns.L

local MainWindow = {}
ns.MainWindow = MainWindow

local WIDTH, HEIGHT = 640, 500
local TAB_WIDTH, TAB_HEIGHT = 110, 22

local frame
local tabs = {}
local activeTab

-- def = { name, Build = function(panel), Refresh = function(panel) }
function MainWindow:AddTab(def)
    table.insert(tabs, def)
end

local function SelectTab(index)
    activeTab = index
    for i, tab in ipairs(tabs) do
        tab.panel:SetShown(i == index)
        tab.button:SetEnabled(i ~= index)
    end
    MainWindow:Refresh()
end

local function Create()
    frame = CreateFrame("Frame", "AuctionCoachMainWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    -- Close with Escape.
    table.insert(UISpecialFrames, frame:GetName())

    local title = frame.TitleText
    if not title then
        title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText(L.ADDON_TITLE)

    for i, tab in ipairs(tabs) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(TAB_WIDTH, TAB_HEIGHT)
        button:SetPoint("TOPLEFT", 12 + (i - 1) * (TAB_WIDTH + 4), -30)
        button:SetText(tab.name)
        button:SetScript("OnClick", function() SelectTab(i) end)
        tab.button = button

        local panel = CreateFrame("Frame", nil, frame)
        panel:SetPoint("TOPLEFT", 14, -30 - TAB_HEIGHT - 8)
        panel:SetPoint("BOTTOMRIGHT", -14, 12)
        panel:Hide()
        tab.panel = panel
        tab.Build(panel)
    end

    frame:SetScript("OnShow", function() MainWindow:Refresh() end)
    SelectTab(1)
end

function MainWindow:IsShown()
    return frame ~= nil and frame:IsShown()
end

function MainWindow:Toggle()
    if not ns.db then return end
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end

-- reason is the event that triggered the refresh, or nil for a full one.
function MainWindow:Refresh(reason)
    if not self:IsShown() or not activeTab then return end
    local tab = tabs[activeTab]
    if tab.Refresh then tab.Refresh(tab.panel, reason) end
end

local function RefreshIfShown(event)
    MainWindow:Refresh(event)
end

local refreshEvents = {}

-- Refresh the open tab when this event fires (each event only once).
function MainWindow:RefreshOn(event)
    if refreshEvents[event] then return end
    refreshEvents[event] = true
    ns.Events:On(event, RefreshIfShown)
end

for _, event in ipairs({
    "AC_SCAN_COMPLETE", "AC_SCAN_PROGRESS", "AC_INVENTORY_CHANGED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
}) do
    MainWindow:RefreshOn(event)
end

-- Rows show "Loading item..." until the client has the item's name. Redraw
-- once the names asked for have arrived.
ns.Events:On("GET_ITEM_INFO_RECEIVED", function()
    if not ns.Util.NamesPending() then return end
    ns.Util.Debounce("itemNames", 0.5, function()
        ns.Util.ClearNamesPending()
        MainWindow:Refresh()
    end)
end)
