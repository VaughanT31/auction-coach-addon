-- Auction Coach - the shopping list beside the Auction House.
-- Opens by itself when the AH opens and the list has items (unless turned
-- off in the options), so the list is in front of the player while they
-- shop instead of a chat line. Items listed at or under the max come
-- first. Click a row to search for it, right-click to take it off.
--
--  +-- Shopping list (3, 1 to buy now) ---------- [x] -+
--  | [i] Sunfire Silk x12   9g 80s  max 11g   Buy now   |
--  | [i] Bright Linen x40   1g 20s  max 1g    Too high  |
--  +----------------------------------------------------+
--
-- When the post helper is open (selling), this sits under it.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local ShoppingPanel = {}
ns.ShoppingPanel = ShoppingPanel

local WIDTH = 330
local ROW = 22
local MAX_ROWS = 14

local STATUS_COLORS = {
    BUY = "|cff66ff66",
    WAIT = "|cffcccccc",
    OLD = "|cffffaa33",
    UNKNOWN = "|cff9d9d9d",
}

local panel, rows
local closedThisVisit = false

local function Enabled()
    return ns.db and ns.db.settings.shoppingPanel ~= false
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 8, -34 - (index - 1) * ROW)
    row:SetPoint("RIGHT", -8, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ns.Skin.RowBand(row)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    row:GetHighlightTexture():SetVertexColor(1, 0.82, 0.15, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", -4, 0)
    row.status:SetWidth(58)
    row.status:SetJustifyH("RIGHT")
    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.price:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.price:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function(self, mouse)
        local item = self.item
        if not item then return end
        if mouse == "RightButton" then
            ns.Shopping:Remove(item.key)
        else
            Compat.ShowAtAuctionHouse(item.key, Util.NamedLink(item.key), item.lowest, item.need)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local item = self.item
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = Util.NamedLink(item.key)
        if link and link:find("item:") then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(link or item.key) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.ADDON_TITLE, 1, 0.82, 0)
        for _, line in ipairs(ns.Phrases.Shop(item)) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:AddLine(L.SHOP_PANEL_CLICK, 0.6, 0.8, 1, true)
        GameTooltip:AddLine(L.SHOP_REMOVE_TIP, 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Create()
    panel = CreateFrame("Frame", "AuctionCoachShoppingPanel", AuctionHouseFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    ns.Skin.Backdrop(panel, ns.Skin.BG, { 0.88, 0.65, 0.15, 0.9 })
    panel:EnableMouse(true)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetPoint("RIGHT", -30, 0)
    panel.title:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonNoScripts")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function()
        closedThisVisit = true
        panel:Hide()
    end)

    panel.more = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.more:SetJustifyH("LEFT")

    rows = {}
    for i = 1, MAX_ROWS do rows[i] = CreateRow(i) end
    panel:Hide()
end

-- Under the post helper while that's open (PostHelper calls this when it
-- shows or hides), otherwise beside the AH.
function ShoppingPanel:Place()
    if not panel then return end
    panel:ClearAllPoints()
    local helper = _G.AuctionCoachPostHelper
    if helper and helper:IsShown() then
        panel:SetPoint("TOPLEFT", helper, "BOTTOMLEFT", 0, -6)
    else
        panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -24)
    end
end

function ShoppingPanel:IsShown()
    return panel ~= nil and panel:IsShown()
end

function ShoppingPanel:Refresh()
    if not Enabled() or closedThisVisit or not Compat.IsAuctionHouseOpen() then
        if panel then panel:Hide() end
        return
    end
    local items = ns.Shopping:Items()
    if #items == 0 then
        if panel then panel:Hide() end
        return
    end
    if not panel then Create() end

    local buy = 0
    for _, item in ipairs(items) do
        if item.status == "BUY" then buy = buy + 1 end
    end
    panel.title:SetText(L.SHOP_TITLE:format(#items, buy))

    local shown = math.min(#items, MAX_ROWS)
    for i, row in ipairs(rows) do
        local item = items[i]
        row.item = item
        row:SetShown(item ~= nil)
        if item then
            local itemID = Util.ItemIDFromKey(item.key) or Util.PET_CAGE_ITEM_ID
            row.icon:SetTexture(Compat.GetItemIconByID(itemID))
            local name = Util.NamedLink(item.key) or ("|cff9d9d9d" .. L.ITEM_LOADING .. "|r")
            row.name:SetText(item.need and (name .. " |cff9d9d9dx" .. item.need .. "|r") or name)
            row.price:SetText((item.lowest and Util.FormatMoneyIcons(item.lowest) or "|cff9d9d9d-|r")
                .. " |cff9d9d9d" .. L.SHOP_PANEL_MAX:format(Util.FormatMoneyIcons(item.max)) .. "|r")
            row.status:SetText(STATUS_COLORS[item.status] .. L["SHOP_STATUS_" .. item.status] .. "|r")
        end
    end
    local height = 34 + shown * ROW + 10
    if #items > MAX_ROWS then
        panel.more:ClearAllPoints()
        panel.more:SetPoint("TOPLEFT", 12, -34 - shown * ROW - 4)
        panel.more:SetText(L.SHOP_PANEL_MORE:format(#items - MAX_ROWS))
        panel.more:Show()
        height = height + 16
    else
        panel.more:Hide()
    end
    panel:SetHeight(height)
    self:Place()
    panel:Show()
end

local function Soon()
    Util.Debounce("shoppingPanel", 0.3, function() ShoppingPanel:Refresh() end)
end

ns.Events:On("AUCTION_HOUSE_SHOW", function()
    closedThisVisit = false
    -- Blizzard builds its frame first; draw on the next frame.
    C_Timer.After(0, function() ShoppingPanel:Refresh() end)
end)
ns.Events:On("AUCTION_HOUSE_CLOSED", function()
    if panel then panel:Hide() end
end)
for _, event in ipairs({ "AC_SHOPPING_CHANGED", "AC_SCAN_COMPLETE", "AC_LIVE_PRICE", "AC_DATA_CHANGED" }) do
    ns.Events:On(event, Soon)
end

-- /ac shop with nothing after it opens the panel again at the AH.
function ShoppingPanel:Open()
    closedThisVisit = false
    self:Refresh()
    return self:IsShown()
end
