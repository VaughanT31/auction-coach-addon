-- Auction Coach - the mailbox inbox.
-- Covers Blizzard's inbox inside the mail window (its "Blizzard inbox"
-- button swaps back, and the "Auction Coach" tab next to Send Mail
-- returns), with every mail in one list and a button per kind:
--
--  +-- Auction Coach mail ----------------------- [Blizzard inbox] x -+
--  |  [ Search your mail                                          ]  |
--  |  Item                          Type        Expires        Gold  |
--  |  [i] Sunfire Silk x20          Sold        29 days        812g  |
--  |  [i] Bright Linen x200         Expired     29 days              |
--  |  [i] Zed: Thanks for the flasks Other       3 days              |
--  |  12 mails, 220 items, 1,234g. On the way: 2 sales, next at 14:32 |
--  |  [                    Collect all AH mail                      ]  |
--  |  [Sold 4] [Bought 1] [Cancelled 2] [Expired 5] [Outbid] [Other 2] |
--  |  Collecting 3 of 12...                                           |
--  +------------------------------------------------------------------+
--
-- Clicking an Auction House mail takes just that one; clicking other mail
-- opens it in Blizzard's mail view. The buttons take their kind one mail
-- at a time, waiting for the inbox to update before the next, and with
-- full bags take only the gold. Mail with cash on delivery is never
-- collected. Collected sales still reach the gold history and "gold on the
-- way": they go through the same TakeInboxMoney / AutoLootMailItem hooks.

local _, ns = ...
local L, Util = ns.L, ns.Util

local MailPanel = {}
ns.MailPanel = MailPanel

local WIDTH = 560
local ROW = 18
local TAB_WIDTH, TAB_HEIGHT = 110, 24
-- Columns from the right edge: { right offset, width }.
local COL = {
    gold = { -4, 110 },
    expires = { -120, 70 },
    kind = { -196, 80 },
}
-- After the inbox updates, a short pause before the next mail: taking mail
-- too fast makes the server refuse it.
local STEP_DELAY = 0.3
-- No inbox update this long after taking a mail: try again, a few times.
local STEP_TIMEOUT = 3
local MAX_TRIES = 3
local MAX_ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16

-- The kind buttons, in order. "all" (Collect all AH mail) is every kind but "other".
local KINDS = { "sold", "bought", "cancelled", "expired", "outbid", "other" }
local KIND_COLORS = {
    sold = "|cff66ff66",
    bought = "|cff66bbff",
    cancelled = "|cffcccccc",
    expired = "|cffffaa33",
    outbid = "|cffffd100",
    other = "|cff9d9d9d",
}

local frame, tab
local useOurs = true    -- our view or Blizzard's, reset to ours each time the mailbox opens
local run               -- { kinds = { [kind] = true }, taken, total, tries, trying, bagsFull, timer }
                        -- trying: a mail was taken and the inbox hasn't updated yet
local openMailPoints    -- where Blizzard put its mail reading window, to put it back

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

-- The kind of mail at index, its gold and whether it has items, when there
-- is something to collect. nil for mail with cash on delivery, letters
-- with nothing attached and sales still pending.
local function Classify(index)
    local _, _, _, subject, money, cod, _, hasItem = GetInboxHeaderInfo(index)
    if (cod or 0) > 0 then return nil end
    money = money or 0
    if money <= 0 and not hasItem then return nil end
    local invoiceType = GetInboxInvoiceInfo(index)
    local kind = "other"
    if invoiceType == "seller" then
        kind = "sold"
    elseif invoiceType == "buyer" then
        kind = "bought"
    elseif invoiceType then
        return nil -- "seller_temp_invoice": a sale whose gold isn't here yet
    elseif Readable(subject) then
        if CANCELLED and subject:match(CANCELLED) then
            kind = "cancelled"
        elseif EXPIRED and subject:match(EXPIRED) then
            kind = "expired"
        elseif OUTBID and subject:match(OUTBID) then
            kind = "outbid"
        end
    end
    return kind, money, hasItem
end

local function Matches(kind, kinds)
    if kinds.all then return kind ~= "other" end
    return kinds[kind]
end

local function FreeBagSlots()
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
    end
    return free
end

-- Every mail in inbox order, and what each button would collect:
-- { mails = { { index, kind, collect, money, hasItem, name, count, extra,
--   icon, link, days, sender, cod } }, counts = { [kind] = { n, gold } },
--   items, gold }.
local function ReadInbox()
    local result = { mails = {}, counts = {}, items = 0, gold = 0 }
    for _, kind in ipairs(KINDS) do result.counts[kind] = { n = 0, gold = 0 } end
    result.counts.all = { n = 0, gold = 0 }
    for i = 1, GetInboxNumItems() do
        local icon, _, sender, subject, money, cod, days, hasItem = GetInboxHeaderInfo(i)
        local kind = Classify(i)
        local mail = { index = i, kind = kind or "other", collect = kind ~= nil, money = money or 0,
                       hasItem = hasItem, days = days, icon = icon, cod = (cod or 0) > 0,
                       sender = Readable(sender) and sender or nil }
        if mail.kind == "sold" then
            local _, itemName, _, _, _, _, _, _, _, _, count = GetInboxInvoiceInfo(i)
            mail.name, mail.count = Readable(itemName) and itemName or nil, count
            local ok, _, _, _, _, itemIcon = pcall(C_Item.GetItemInfoInstant, mail.name or "")
            if ok and itemIcon then mail.icon = itemIcon end
        end
        if hasItem then
            local attachments = 0
            for a = 1, MAX_ATTACHMENTS do
                local name, _, itemIcon, count = GetInboxItem(i, a)
                if name then
                    attachments = attachments + 1
                    result.items = result.items + (count or 1)
                    if attachments == 1 and mail.kind ~= "other" then
                        mail.name, mail.icon, mail.count = name, itemIcon or icon, count
                        mail.link = GetInboxItemLink(i, a)
                    end
                end
            end
            if attachments > 1 then mail.extra = attachments - 1 end
        end
        if not mail.name then
            mail.name = Readable(subject) and subject or ""
            if mail.kind == "other" and mail.sender then mail.name = mail.sender .. ": " .. mail.name end
        end
        result.gold = result.gold + mail.money
        if kind then
            for _, k in ipairs({ kind, kind ~= "other" and "all" or nil }) do
                local c = result.counts[k]
                c.n, c.gold = c.n + 1, c.gold + mail.money
            end
        end
        result.mails[#result.mails + 1] = mail
    end
    return result
end

-- ---------------------------------------------------------------------
-- Collecting
-- ---------------------------------------------------------------------

local function SetStatus(text)
    if frame then frame.status:SetText(text or "") end
end

-- Takes one mail: everything (items and gold), or only its gold. It's read
-- first, as opening it in Blizzard's inbox does: mail collected unread
-- keeps the minimap's new mail icon lit.
local function Take(index, money, items)
    local wasRead = select(9, GetInboxHeaderInfo(index))
    if not wasRead then GetInboxText(index) end
    if items then
        AutoLootMailItem(index)
    elseif money > 0 then
        TakeInboxMoney(index)
    end
end

local function Stop(message)
    local finished = run ~= nil
    if run and run.timer then run.timer:Cancel() end
    run = nil
    SetStatus(message)
    MailPanel:Refresh()
    -- Ask the server for the mailbox again, so the new mail icon catches up.
    if finished and MailFrame and MailFrame:IsShown() then CheckInbox() end
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
    MailPanel:Refresh()
    Take(index, money, hasItem)
    Wait()
end

function MailPanel:Collect(kind)
    if run then return end
    local count = ReadInbox().counts[kind]
    if not count or count.n == 0 then return end
    run = { kinds = { [kind] = true }, taken = 0, total = count.n, tries = 0 }
    Step()
end

-- One mail, clicked in the list.
function MailPanel:TakeOne(mail)
    if run then return end
    if mail.kind == "other" or not mail.collect then
        -- Opened in Blizzard's mail view, as if clicked in its inbox.
        local ok = pcall(InboxFrame_OnClick, { GetChecked = function() return true end }, mail.index)
        if not ok then MailPanel:ShowBlizzard() end
        return
    end
    if mail.hasItem and FreeBagSlots() == 0 then
        if mail.money > 0 then Take(mail.index, mail.money, false) else SetStatus(L.MAILP_BAGS_FULL_ONE) end
        return
    end
    SetStatus("")
    Take(mail.index, mail.money, mail.hasItem)
end

ns.Events:On("MAIL_INBOX_UPDATE", function()
    if run then
        run.trying = false
        if run.timer then run.timer:Cancel() end
        run.timer = C_Timer.NewTimer(STEP_DELAY, function()
            if run then run.timer = nil; Step() end
        end)
    end
    if frame and frame:IsShown() then
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

ns.Events:On("AC_MAIL_DUE_CHANGED", function()
    if frame and frame:IsShown() then MailPanel:Refresh() end
end)

-- ---------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------

local function Cell(row, col, font)
    local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("RIGHT", row, "RIGHT", COL[col][1], 0)
    fs:SetWidth(COL[col][2])
    fs:SetJustifyH(col == "gold" and "RIGHT" or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
    row:SetPoint("RIGHT")
    if index % 2 == 0 then ns.Skin.RowBand(row) end
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    row:GetHighlightTexture():SetVertexColor(1, 0.82, 0.15, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.gold = Cell(row, "gold")
    row.expires = Cell(row, "expires")
    row.kind = Cell(row, "kind")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.kind, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        if self.mail then MailPanel:TakeOne(self.mail) end
    end)
    row:SetScript("OnEnter", function(self)
        local mail = self.mail
        if not mail then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if mail.link then
            GameTooltip:SetHyperlink(mail.link)
        else
            GameTooltip:SetText(mail.name, 1, 1, 1, 1, true)
        end
        if mail.sender then GameTooltip:AddLine(L.MAILP_FROM:format(mail.sender), 0.8, 0.8, 0.8) end
        if mail.extra then GameTooltip:AddLine(L.MAILP_EXTRA:format(mail.extra), 0.8, 0.8, 0.8) end
        if mail.money > 0 then GameTooltip:AddLine(Util.FormatMoneyIcons(mail.money), 1, 1, 1) end
        local open = mail.kind == "other" or not mail.collect
        GameTooltip:AddLine(open and L.MAILP_CLICK_OPEN or L.MAILP_CLICK_TAKE, 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function ExpiresText(days)
    if not days then return "" end
    if days < 1 then return "|cffff4444" .. L.MAILP_HOURS:format(math.max(1, math.floor(days * 24))) .. "|r" end
    local color = days < 3 and "|cffff4444" or days < 7 and "|cffffaa33" or "|cff66cc66"
    return color .. L.MAILP_DAYS:format(math.floor(days)) .. "|r"
end

local function SetRow(row, mail)
    row.mail = mail
    row.icon:SetTexture(mail.icon or 134400)
    local name = mail.link or mail.name
    if (mail.count or 1) > 1 then name = name .. " x" .. BreakUpLargeNumbers(mail.count) end
    if mail.extra then name = name .. " |cff9d9d9d+" .. mail.extra .. "|r" end
    row.name:SetText(name)
    row.kind:SetText(KIND_COLORS[mail.kind] .. L["MAILP_" .. mail.kind:upper()] .. "|r")
    row.expires:SetText(ExpiresText(mail.days))
    if mail.cod then
        row.gold:SetText("|cffff6666" .. L.MAILP_COD .. "|r")
    elseif mail.money > 0 then
        row.gold:SetText(Util.FormatMoneyIcons(mail.money))
    else
        row.gold:SetText("")
    end
    row:Show()
end

local function Shown(mail, filter)
    if filter == "" then return true end
    local text = ((mail.name or "") .. " " .. (mail.sender or "")):lower()
    return text:find(filter, 1, true) ~= nil
end

function MailPanel:Refresh()
    if not frame or not frame:IsShown() then return end
    local inbox = ReadInbox()
    local filter = (frame.search:GetText() or ""):lower()

    local n = 0
    for _, mail in ipairs(inbox.mails) do
        if Shown(mail, filter) then
            n = n + 1
            local row = frame.rows[n] or CreateRow(n)
            frame.rows[n] = row
            SetRow(row, mail)
        end
    end
    for i = n + 1, #frame.rows do frame.rows[i]:Hide() end
    frame.content:SetHeight(math.max(1, n * ROW))
    frame.empty:SetShown(#inbox.mails == 0)

    -- Footer: what's here, then what's on the way.
    local shown, total = GetInboxNumItems()
    local summary = L.MAILP_SUMMARY:format(#inbox.mails, BreakUpLargeNumbers(inbox.items),
        Util.FormatMoneyIcons(inbox.gold))
    if (total or shown) > shown then summary = summary .. " " .. L.MAILP_MORE:format(total - shown) end
    frame.summary:SetText(summary)
    local way = ns.Sales:OnTheWay().coming
    if way.n > 0 then
        frame.way:SetText(L.MAILP_WAY:format(
            (way.n == 1 and L.WAY_SALE_ONE or L.WAY_SALES):format(way.n, Util.FormatMoneyIcons(way.gold) .. (way.more and "+" or "")),
            date("%H:%M", way.next)))
    else
        frame.way:SetText("")
    end

    frame.collectAll:SetText(inbox.counts.all.n > 0
        and L.MAILP_ALL_COUNT:format(inbox.counts.all.n, Util.FormatMoney(inbox.counts.all.gold))
        or L.MAILP_ALL_BUTTON)
    frame.collectAll:SetEnabled(inbox.counts.all.n > 0 and not run)
    for _, kind in ipairs(KINDS) do
        local button, c = frame.kindButtons[kind], inbox.counts[kind]
        local label = L["MAILP_" .. kind:upper()]
        button:SetText(c.n > 0 and (label .. " (" .. c.n .. ")") or label)
        button:SetEnabled(c.n > 0 and not run)
    end
end

-- ---------------------------------------------------------------------
-- The frame, and swapping with Blizzard's inbox
-- ---------------------------------------------------------------------

local function Build()
    frame = CreateFrame("Frame", "AuctionCoachMailInbox", MailFrame, "BackdropTemplate")
    -- Over the whole mail window, wider so names fit. Its tabs stay below.
    frame:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMLEFT", MailFrame, "BOTTOMLEFT", 0, 0)
    frame:SetWidth(math.max(WIDTH, MailFrame:GetWidth()))
    -- Well above everything in the mail window (skins add their own layers),
    -- and solid, so nothing of Blizzard's inbox shows through.
    frame:SetFrameLevel(math.min(MailFrame:GetFrameLevel() + 500, 9000))
    frame:EnableMouse(true)
    local bg = ns.Skin.BG
    ns.Skin.Backdrop(frame, { bg[1], bg[2], bg[3], 1 })

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText(L.MAILP_TITLE)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -2, -2)
    frame.close:SetScript("OnClick", function() HideUIPanel(MailFrame) end)

    frame.blizzard = ns.Skin.Button(frame, L.MAILP_BLIZZARD, 110, 20)
    frame.blizzard:SetPoint("RIGHT", frame.close, "LEFT", -4, 0)
    frame.blizzard:SetScript("OnClick", function() MailPanel:ShowBlizzard() end)

    frame.search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    frame.search:SetHeight(20)
    frame.search:SetPoint("TOPLEFT", 16, -36)
    frame.search:SetPoint("RIGHT", -10, 0)
    frame.search:SetAutoFocus(false)
    if frame.search.Instructions then frame.search.Instructions:SetText(L.MAILP_SEARCH) end
    frame.search:HookScript("OnTextChanged", function() MailPanel:Refresh() end)

    -- Column headings.
    local heads = CreateFrame("Frame", nil, frame)
    heads:SetHeight(16)
    heads:SetPoint("TOPLEFT", 8, -62)
    heads:SetPoint("RIGHT", -30, 0)
    for col, text in pairs({ gold = L.MAILP_COL_GOLD, expires = L.MAILP_COL_EXPIRES, kind = L.MAILP_COL_TYPE }) do
        local fs = heads:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("RIGHT", heads, "RIGHT", COL[col][1], 0)
        fs:SetWidth(COL[col][2])
        fs:SetJustifyH(col == "gold" and "RIGHT" or "LEFT")
        fs:SetText(text)
    end
    local itemHead = heads:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemHead:SetPoint("LEFT", 24, 0)
    itemHead:SetText(L.MAILP_COL_ITEM)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", heads, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", -8, 0)

    -- Bottom up: status, kind buttons, Collect all, footer lines.
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 10, 8)
    frame.status:SetPoint("RIGHT", -10, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetHeight(12)

    frame.kindButtons = {}
    local gap = 4
    local buttonWidth = (frame:GetWidth() - 20 - gap * (#KINDS - 1)) / #KINDS
    for i, kind in ipairs(KINDS) do
        local button = ns.Skin.Button(frame, "", buttonWidth, 22)
        button:SetPoint("BOTTOMLEFT", 10 + (i - 1) * (buttonWidth + gap), 24)
        button:SetScript("OnClick", function() MailPanel:Collect(kind) end)
        button:SetMotionScriptsWhileDisabled(true)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["MAILP_" .. kind:upper() .. "_TIP"], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.kindButtons[kind] = button
    end

    frame.collectAll = ns.Skin.Button(frame, L.MAILP_ALL_BUTTON, frame:GetWidth() - 20, 24)
    frame.collectAll:SetPoint("BOTTOMLEFT", 10, 50)
    frame.collectAll:SetScript("OnClick", function() MailPanel:Collect("all") end)
    frame.collectAll:SetMotionScriptsWhileDisabled(true)
    frame.collectAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.MAILP_ALL_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.collectAll:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.way = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.way:SetPoint("BOTTOMLEFT", frame.collectAll, "TOPLEFT", 0, 6)
    frame.way:SetPoint("RIGHT", -10, 0)
    frame.way:SetJustifyH("LEFT")
    frame.way:SetWordWrap(false)

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("BOTTOMLEFT", frame.way, "TOPLEFT", 0, 4)
    frame.summary:SetPoint("RIGHT", -10, 0)
    frame.summary:SetJustifyH("LEFT")
    frame.summary:SetWordWrap(false)

    local footLine = frame:CreateTexture(nil, "ARTWORK")
    footLine:SetColorTexture(1, 1, 1, 0.1)
    footLine:SetHeight(1)
    footLine:SetPoint("BOTTOMLEFT", frame.summary, "TOPLEFT", -2, 6)
    footLine:SetPoint("RIGHT", -8, 0)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", heads, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOM", footLine, "TOP", 0, 4)
    scroll:SetPoint("RIGHT", -30, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    frame.content = content
    frame.rows = {}

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    frame.empty:SetText(L.MAILP_EMPTY)

    frame:SetScript("OnShow", function() MailPanel:Refresh() end)

    -- The tab next to Send Mail that brings this view back.
    tab = ns.Skin.Tab(MailFrame, L.ADDON_TITLE, TAB_WIDTH, TAB_HEIGHT)
    local anchor = _G.MailFrameTab2 or _G.MailFrameTab1
    if anchor then
        tab:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        tab:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 220, 2)
    end
    tab:SetScript("OnClick", function() MailPanel:ShowOurs() end)
end

local function Enabled()
    return ns.db and ns.db.settings.mailPanel ~= false and MailFrame and InboxFrame
end

-- Blizzard's mail reading window sits beside its inbox; with ours (wider)
-- in front it moves beside ours, and goes back when ours is closed.
local function PlaceOpenMail(ours)
    local open = _G.OpenMailFrame
    if not open then return end
    if not openMailPoints then
        openMailPoints = {}
        for i = 1, open:GetNumPoints() do openMailPoints[i] = { open:GetPoint(i) } end
    end
    open:ClearAllPoints()
    if ours then
        open:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    else
        for _, p in ipairs(openMailPoints) do open:SetPoint(unpack(p)) end
    end
end

-- Blizzard's title and close button, faded out while ours is in front
-- (ours has its own). Faded rather than hidden, so nothing else that shows
-- them fights over it.
local function BlizzardTitle(visible)
    for _, region in ipairs({ MailFrame.TitleContainer, _G.MailFrameTitleText, MailFrame.CloseButton,
                              _G.MailFrameCloseButton }) do
        if region and region.SetAlpha then region:SetAlpha(visible and 1 or 0) end
    end
end

-- Ours shows while Blizzard's inbox page is up (not Send Mail) and ours is picked.
local function Update()
    if not frame then return end
    local show = (Enabled() and useOurs and InboxFrame:IsShown()) and true or false
    frame:SetShown(show)
    BlizzardTitle(not show)
    tab:SetShown(Enabled() and true or false)
    tab:SetActive(show)
    PlaceOpenMail(show)
end

function MailPanel:ShowBlizzard()
    useOurs = false
    Update()
end

function MailPanel:ShowOurs()
    useOurs = true
    -- From Send Mail, go back to the inbox page first.
    if not InboxFrame:IsShown() and _G.MailFrameTab1 then _G.MailFrameTab1:Click() end
    Update()
end

ns.Events:On("MAIL_SHOW", function()
    if not Enabled() then return end
    if not frame then
        Build()
        InboxFrame:HookScript("OnShow", Update)
        InboxFrame:HookScript("OnHide", Update)
    end
    useOurs = true
    SetStatus("")
    frame.search:SetText("")
    Update()
end)

ns.Events:On("MAIL_CLOSED", function()
    if run then Stop() end
end)

-- The option was turned off: back to Blizzard's inbox.
function MailPanel:Hide()
    if run then Stop() end
    Update()
end
