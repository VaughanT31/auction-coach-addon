-- Auction Coach - post helper.
-- When an item sits in the Auction House sell box, a panel beside the AH
-- shows the suggested price and why. "Use this price" fills in the price
-- box; posting is still the player's own click on Blizzard's Post button.

local _, ns = ...
local L, Util, Phrases = ns.L, ns.Util, ns.Phrases

local PostHelper = {}
ns.PostHelper = PostHelper

local WIDTH = 270

local panel
local current -- { key, link, sellFrame, suggestion }

-- The commodity and item sell frames, whichever exist on this client.
local function SellFrames()
    if not AuctionHouseFrame then return {} end
    return { AuctionHouseFrame.CommoditiesSellFrame, AuctionHouseFrame.ItemSellFrame }
end

local function CreatePanel()
    panel = CreateFrame("Frame", "AuctionCoachPostHelper", AuctionHouseFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -24)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.08, 0.07, 0.06, 0.96)
    panel:SetBackdropBorderColor(0.88, 0.65, 0.15)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetText(L.POST_TITLE)

    panel.item = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.item:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.item:SetPoint("RIGHT", -12, 0)
    panel.item:SetJustifyH("LEFT")
    panel.item:SetWordWrap(false)

    panel.price = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    panel.price:SetPoint("TOPLEFT", panel.item, "BOTTOMLEFT", 0, -8)
    panel.price:SetJustifyH("LEFT")

    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.text:SetPoint("TOPLEFT", panel.price, "BOTTOMLEFT", 0, -8)
    panel.text:SetPoint("RIGHT", -12, 0)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetSpacing(3)

    panel.use = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.use:SetSize(WIDTH - 24, 24)
    panel.use:SetPoint("TOPLEFT", panel.text, "BOTTOMLEFT", 0, -10)
    panel.use:SetText(L.POST_USE)
    panel.use:SetScript("OnClick", function() PostHelper:UsePrice() end)
    panel.use:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.POST_USE_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.use:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel:Hide()
end

local function Layout()
    -- Grow the panel to fit its text.
    local height = 12 + panel.title:GetStringHeight() + 6 + panel.item:GetStringHeight() + 8
        + panel.price:GetStringHeight() + 8 + panel.text:GetStringHeight() + 12
    if panel.use:IsShown() then height = height + 10 + panel.use:GetHeight() end
    panel:SetHeight(height)
end

function PostHelper:Refresh()
    if not panel or not current then return end
    local s = ns.Rules:SuggestPrice(current.key, current.link)
    current.suggestion = s

    panel.item:SetText(current.link)
    if s.price then
        panel.price:SetText(Util.FormatMoneyIcons(s.price))
        local c = s.action == "HOLD" and { 1, 0.65, 0.2 } or { 1, 0.82, 0 }
        panel.price:SetTextColor(c[1], c[2], c[3])
    else
        panel.price:SetText(Phrases.SellShort(s))
        panel.price:SetTextColor(0.7, 0.7, 0.7)
    end
    local text = table.concat(Phrases.Sell(s, Util.FormatMoneyIcons), "\n\n")
    local quantity = PostHelper:Quantity()
    local chances = Phrases.SellChances(ns.SellChance:Options(current.key, s, quantity), quantity,
        Util.FormatMoneyIcons)
    if chances then
        text = text .. "\n\n|cffffd100" .. chances[1] .. "|r\n" .. table.concat(chances, "\n", 2)
    end
    panel.text:SetText(text)
    panel.use:SetShown(s.price ~= nil)
    panel:Show()
    Layout()
end

-- How many the player is about to post, from the sell frame.
function PostHelper:Quantity()
    local input = current and current.sellFrame and current.sellFrame.QuantityInput
    if input and input.GetQuantity then
        local ok, quantity = pcall(input.GetQuantity, input)
        if ok and type(quantity) == "number" and quantity > 0 then return quantity end
    end
    return 1
end

function PostHelper:Show(sellFrame, itemLocation)
    if not ns.db or not itemLocation or not C_Item.DoesItemExist(itemLocation) then
        self:Hide()
        return
    end
    local link = C_Item.GetItemLink(itemLocation)
    local key = Util.ItemKeyFromLink(link)
    if not key then
        self:Hide()
        return
    end
    if not panel then CreatePanel() end
    current = { key = key, link = link, sellFrame = sellFrame }
    self:Refresh()
end

function PostHelper:Hide()
    current = nil
    if panel then panel:Hide() end
end

-- Fills in the sell frame's price box. Only ever on the player's click.
function PostHelper:UsePrice()
    local s = current and current.suggestion
    local input = current and current.sellFrame and current.sellFrame.PriceInput
    if not s or not s.price or not input or not input.SetAmount then return end
    -- SetAmount fills the gold/silver/copper boxes, and the sell frame
    -- updates its total and Post button from those, as when typing. Calling
    -- its UpdatePostState directly errors while the deposit is unknown.
    input:SetAmount(s.price)
    Util.Print(L.POST_SET:format(Util.FormatMoneyIcons(s.price)))
end

local hooked = false

local function HookSellFrames()
    if hooked then return end
    for _, sellFrame in ipairs(SellFrames()) do
        if sellFrame and sellFrame.SetItem then
            hooked = true
            hooksecurefunc(sellFrame, "SetItem", function(frame, itemLocation)
                if frame:IsShown() then
                    PostHelper:Show(frame, itemLocation)
                end
            end)
            sellFrame:HookScript("OnHide", function(frame)
                if current and current.sellFrame == frame then PostHelper:Hide() end
            end)
            -- The chance to sell depends on how many are posted.
            local box = sellFrame.QuantityInput and sellFrame.QuantityInput.InputBox
            if box and box.HookScript then
                box:HookScript("OnTextChanged", function()
                    if current and current.sellFrame == sellFrame then
                        Util.Debounce("postHelperQuantity", 0.2, function() PostHelper:Refresh() end)
                    end
                end)
            end
        end
    end
end

-- The AH UI is load-on-demand, so hook it once it exists.
ns.Events:On("AUCTION_HOUSE_SHOW", HookSellFrames)
ns.Events:On("AUCTION_HOUSE_CLOSED", function() PostHelper:Hide() end)

-- Fresh prices from the search the sell frame does when an item goes in.
ns.Events:On("AC_LIVE_PRICE", function(_, key)
    if current and current.key == key then PostHelper:Refresh() end
end)
