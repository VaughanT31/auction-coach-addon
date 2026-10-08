-- Auction Coach - main window with a simple tab strip.
-- Tabs register themselves with MainWindow:AddTab, in .toc order: Today,
-- My Stuff, Sell, Deals and Auctions.

local _, ns = ...
local L = ns.L

local MainWindow = {}
ns.MainWindow = MainWindow

local WIDTH, HEIGHT = 640, 516
local TAB_WIDTH, TAB_HEIGHT = 92, 24
-- Title row, then the tab row, then the open tab's panel.
local TABS_Y = -44

local frame
local tabs = {}
local activeTab
local priceStatus

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
    frame:SetPoint("CENTER")
    frame.title:SetText(L.ADDON_TITLE)

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
    frame:HookScript("OnShow", function() MainWindow:Refresh() end)
    SelectTab(1)
end

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

-- reason is the event that triggered the refresh, or nil for a full one.
function MainWindow:Refresh(reason)
    if not self:IsShown() or not activeTab then return end
    UpdatePriceStatus()
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
    "AC_SCAN_COMPLETE", "AC_SCAN_PROGRESS", "AC_INVENTORY_CHANGED", "AC_DATA_CHANGED",
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
