-- Auction Coach - collect buttons beside the mailbox.
--
--  +-- Auction Coach ------------+
--  |  [ Sold: 4, 1,234g      ]   |
--  |  [ Cancelled: 2         ]   |
--  |  [ Expired: 5           ]   |
--  |  [ Bought: 1            ]   |
--  |  [ All AH mail: 12      ]   |
--  |  Collecting 3 of 12...      |
--  +-----------------------------+
--
-- Each button takes that kind of Auction House mail one at a time, waiting
-- for the inbox to update before the next, and stops when the bags are
-- full or the mailbox closes. Mail with cash on delivery is never taken.
-- Collected sales still reach the gold history and "gold on the way":
-- they go through the same TakeInboxMoney / AutoLootMailItem hooks.

local _, ns = ...
local L, Util = ns.L, ns.Util

local MailPanel = {}
ns.MailPanel = MailPanel

local WIDTH = 200
local BUTTON_HEIGHT = 22
-- After the inbox updates, a short pause before the next mail: taking mail
-- too fast makes the server refuse it.
local STEP_DELAY = 0.3
-- No inbox update this long after taking a mail: try again, a few times.
local STEP_TIMEOUT = 3
local MAX_TRIES = 3

local KINDS = { "sold", "cancelled", "expired", "bought", "all" }

local panel
local run           -- { kinds = { [kind] = true }, taken, total, tries, trying, timer }
                    -- trying: a mail was taken and the inbox hasn't updated yet

-- A localised subject such as "Auction expired: %s" as a pattern.
local function SubjectPattern(text)
    if type(text) ~= "string" then return nil end
    return "^" .. text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+") .. "$"
end

local CANCELLED = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT)
local EXPIRED = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
local OUTBID = SubjectPattern(AUCTION_OUTBID_MAIL_SUBJECT)

local function Readable(value)
    return type(value) == "string" and not (issecretvalue and issecretvalue(value))
end

-- The kind of Auction House mail at index, with its gold and whether it
-- has items, or nil for other mail (and anything with cash on delivery).
local function Classify(index)
    local _, _, _, subject, money, cod, _, hasItem = GetInboxHeaderInfo(index)
    if (cod or 0) > 0 then return nil end
    money = money or 0
    local invoiceType = GetInboxInvoiceInfo(index)
    local kind
    if invoiceType == "seller" then
        kind = money > 0 and "sold" or nil
    elseif invoiceType == "buyer" then
        kind = "bought"
    elseif Readable(subject) then
        if CANCELLED and subject:match(CANCELLED) then
            kind = "cancelled"
        elseif EXPIRED and subject:match(EXPIRED) then
            kind = "expired"
        elseif OUTBID and subject:match(OUTBID) then
            kind = "outbid"
        end
    end
    if not kind or (money <= 0 and not hasItem) then return nil end
    return kind, money, hasItem
end

local function Matches(kind, kinds)
    return kinds.all or kinds[kind]
end

-- Counts and gold of each kind in the inbox.
local function Count()
    local counts = {}
    for _, kind in ipairs(KINDS) do counts[kind] = { n = 0, gold = 0 } end
    for i = 1, GetInboxNumItems() do
        local kind, money = Classify(i)
        if kind then
            for _, k in ipairs({ kind, "all" }) do
                if counts[k] then
                    counts[k].n = counts[k].n + 1
                    counts[k].gold = counts[k].gold + money
                end
            end
        end
    end
    return counts
end

local function FreeBagSlots()
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
    end
    return free
end

-- ---------------------------------------------------------------------
-- Collecting
-- ---------------------------------------------------------------------

local function SetStatus(text)
    if panel then panel.status:SetText(text or "") end
end

local function Stop(message)
    if run and run.timer then run.timer:Cancel() end
    run = nil
    SetStatus(message)
    MailPanel:Refresh()
end

local Step

local function Wait()
    if run.timer then run.timer:Cancel() end
    run.timer = C_Timer.NewTimer(STEP_TIMEOUT, function()
        if not run then return end
        run.timer = nil
        run.tries = run.tries + 1
        if run.tries > MAX_TRIES then
            Stop(L.MAILP_STUCK)
        else
            Step()
        end
    end)
end

Step = function()
    if not run then return end
    if not (MailFrame and MailFrame:IsShown()) then return Stop() end
    -- With full bags only the gold is taken: gold-only mail, and the gold
    -- from mail that also has items (the items stay in the mail).
    local bagsFull = run.bagsFull or FreeBagSlots() == 0
    local index, hasItem, money, skipped
    for i = 1, GetInboxNumItems() do
        local kind, m, items = Classify(i)
        if kind and Matches(kind, run.kinds) then
            if items and bagsFull then
                if m > 0 then
                    index, money, hasItem = i, m, false
                    break
                end
                skipped = true
            else
                index, money, hasItem = i, m, items
                break
            end
        end
    end
    if not index then
        local shown, total = GetInboxNumItems()
        if skipped then return Stop(L.MAILP_BAGS_FULL:format(run.taken)) end
        return Stop((total or shown) > shown and L.MAILP_DONE_MORE:format(run.taken) or L.MAILP_DONE:format(run.taken))
    end
    if not run.trying then
        run.trying, run.tries = true, 0
        run.taken = math.min(run.taken + 1, run.total)
    end
    SetStatus(L.MAILP_COLLECTING:format(run.taken, run.total))
    if hasItem then
        AutoLootMailItem(index)
    elseif money > 0 then
        TakeInboxMoney(index)
    end
    Wait()
end

function MailPanel:Collect(kind)
    if run then return end
    local counts = Count()
    if counts[kind].n == 0 then return end
    run = { kinds = { [kind] = true }, taken = 0, total = counts[kind].n, tries = 0 }
    Step()
end

ns.Events:On("MAIL_INBOX_UPDATE", function()
    if run then
        run.trying = false
        if run.timer then run.timer:Cancel() end
        run.timer = C_Timer.NewTimer(STEP_DELAY, function()
            if run then run.timer = nil; Step() end
        end)
    elseif panel and panel:IsShown() then
        Util.Debounce("mailPanel", 0.2, function() MailPanel:Refresh() end)
    end
end)

ns.Events:On("UI_ERROR_MESSAGE", function(_, _, message)
    if run and (message == ERR_INV_FULL or message == ERR_ITEM_MAX_COUNT) then
        -- That mail wasn't taken: carry on with the gold only.
        run.bagsFull, run.trying = true, false
        run.taken = math.max(0, run.taken - 1)
        if run.timer then run.timer:Cancel() end
        run.timer = C_Timer.NewTimer(STEP_DELAY, function()
            if run then run.timer = nil; Step() end
        end)
    end
end)

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------

local function Build()
    panel = CreateFrame("Frame", "AuctionCoachMailPanel", MailFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    ns.Skin.Backdrop(panel)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetText(L.ADDON_TITLE)

    panel.buttons = {}
    local anchor = panel.title
    for _, kind in ipairs(KINDS) do
        local button = ns.Skin.Button(panel, "", WIDTH - 20, BUTTON_HEIGHT)
        button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        button:SetScript("OnClick", function() MailPanel:Collect(kind) end)
        button:SetMotionScriptsWhileDisabled(true)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["MAILP_" .. kind:upper() .. "_TIP"], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.buttons[kind] = button
        anchor = button
    end

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    panel.status:SetWidth(WIDTH - 20)
    panel.status:SetJustifyH("LEFT")

    panel:SetHeight(10 + 14 + #KINDS * (BUTTON_HEIGHT + 6) + 8 + 28 + 10)
end

function MailPanel:Refresh()
    if not panel or not panel:IsShown() then return end
    local counts = Count()
    for _, kind in ipairs(KINDS) do
        local c = counts[kind]
        local label = L["MAILP_" .. kind:upper()]
        local text
        if c.n == 0 then
            text = label
        elseif c.gold > 0 and (kind == "sold" or kind == "all") then
            text = L.MAILP_COUNT_GOLD:format(label, c.n, Util.FormatMoney(c.gold))
        else
            text = L.MAILP_COUNT:format(label, c.n)
        end
        local button = panel.buttons[kind]
        button:SetText(text)
        button:SetEnabled(c.n > 0 and not run)
    end
end

ns.Events:On("MAIL_SHOW", function()
    if not ns.db or not ns.db.settings.mailPanel or not MailFrame then return end
    if not panel then Build() end
    panel:Show()
    SetStatus("")
    MailPanel:Refresh()
end)

ns.Events:On("MAIL_CLOSED", function()
    if run then Stop() end
    if panel then panel:Hide() end
end)

function MailPanel:Hide()
    if run then Stop() end
    if panel then panel:Hide() end
end
