-- Auction Coach - full Auction House scan.
-- Uses C_AuctionHouse.ReplicateItems, which Blizzard allows once every 15
-- minutes. The result can hold 100,000+ auctions, so it is processed in
-- small chunks across frames to avoid freezing the game.
--
-- Fires AC_SCAN_PROGRESS (fraction) while running and AC_SCAN_COMPLETE
-- (itemCount) when done.

local _, ns = ...
local L, Util, Compat = ns.L, ns.Util, ns.Compat

local FullScan = {}
ns.FullScan = FullScan

local THROTTLE = 15 * 60
local CHUNK_SIZE = 1000
local MAX_RETRIES = 3
local RETRY_DELAY = 2

-- "idle" | "waiting" (requested, no data yet) | "processing"
FullScan.state = "idle"
FullScan.progress = 0

function FullScan:SecondsUntilAllowed()
    local realm = ns:GetRealmData()
    return math.max(0, (realm.lastFullScanStart or 0) + THROTTLE - Util.Now())
end

function FullScan:IsRunning()
    return self.state ~= "idle"
end

function FullScan:Start(manual)
    if self:IsRunning() then
        if manual then Util.Print(L.SCAN_BUSY) end
        return
    end
    if not Compat.IsAuctionHouseOpen() then
        if manual then Util.Print(L.SCAN_NEED_AH) end
        return
    end
    local wait = self:SecondsUntilAllowed()
    if wait > 0 then
        if manual then Util.Print(L.SCAN_TOO_SOON:format(Util.FormatDuration(wait))) end
        return
    end

    self.state = "waiting"
    self.progress = 0
    self.startedAt = Util.Now()
    ns:GetRealmData().lastFullScanStart = self.startedAt
    Util.Print(L.SCAN_STARTED)
    C_AuctionHouse.ReplicateItems()
    self:StartPolling()
end

-- ---------------------------------------------------------------------
-- Processing
-- ---------------------------------------------------------------------

local listings      -- [itemKey] = { { unitPrice, qty }, ... }
local pending       -- indexes whose item data was not loaded yet
local ownNames      -- seller names of the player's own characters

-- The player's own listings are left out of prices, so an item is never
-- valued at whatever the player happened to ask for it.
local function BuildOwnNames()
    local names = {}
    local realm = GetNormalizedRealmName()
    for charKey in pairs(ns.db.characters) do
        names[charKey] = true
        local name, charRealm = charKey:match("^(.-)%-(.+)$")
        if name and charRealm == realm then
            names[name] = true
        end
    end
    return names
end

local function Collect(index)
    local count, buyout, itemID, hasAllInfo, owner = Compat.GetReplicateItem(index)
    if not itemID or not buyout or buyout <= 0 or not count or count <= 0 then
        return true -- bid-only or empty entry, nothing to record
    end
    if owner and ownNames[owner] then
        return true
    end

    -- Most items can be keyed from the item ID alone. Gear and pets need
    -- the full link, which is only available once the item data is loaded.
    local key = Util.SimpleItemKey(itemID)
    if not key then
        local link = hasAllInfo and C_AuctionHouse.GetReplicateItemLink(index)
        if not link then
            Compat.RequestLoadItemDataByID(itemID)
            return false
        end
        key = Util.ItemKeyFromLink(link)
        if not key then return true end
    end

    local list = listings[key]
    if not list then
        list = {}
        listings[key] = list
    end
    -- buyoutPrice covers the whole auction, so split it per item.
    list[#list + 1] = { math.floor(buyout / count), count }
    return true
end

local function Finish()
    local results = {}
    for key, list in pairs(listings) do
        local minPrice, qty = math.huge, 0
        for i = 1, #list do
            if list[i][1] < minPrice then minPrice = list[i][1] end
            qty = qty + list[i][2]
        end
        results[key] = {
            min = minPrice,
            market = ns.Prices.MarketValue(list),
            qty = qty,
            auctions = #list,
        }
    end
    listings, pending = nil, nil

    local now = Util.Now()
    local count = ns.Prices:RecordFullScan(ns.realmGroup, results, now)

    -- Competition samples only for items the player owns.
    local owned = ns.Inventory:GetTotals()
    for key in pairs(owned) do
        local r = results[key]
        if r then
            ns.Competition:Sample(ns.realmGroup, key, r.min, now)
        end
    end
    -- Own listings are left out of results, so a missing item means nobody
    -- else has it listed: the player's listing is still the cheapest.
    for key in pairs(ns.Undercuts:Watched(ns.realmGroup)) do
        ns.Undercuts:Observe(ns.realmGroup, key, results[key] and results[key].min, now)
    end

    FullScan.state = "idle"
    FullScan.progress = 1
    if count == 0 then
        Util.Print(L.SCAN_FAILED)
    else
        Util.Print(L.SCAN_DONE:format(BreakUpLargeNumbers(count)))
    end
    ns.Events:Fire("AC_SCAN_COMPLETE", count)
end

local function ProcessPending(attempt)
    local stillPending = {}
    for _, index in ipairs(pending) do
        if not Collect(index) then
            stillPending[#stillPending + 1] = index
        end
    end
    pending = stillPending
    if #pending > 0 and attempt < MAX_RETRIES then
        C_Timer.After(RETRY_DELAY, function() ProcessPending(attempt + 1) end)
    else
        -- Items that never loaded are skipped this time round.
        Finish()
    end
end

-- Replicate indexes run from 0 to total - 1.
local function ProcessChunk(startIndex, total)
    local last = math.min(startIndex + CHUNK_SIZE, total) - 1
    for index = startIndex, last do
        if not Collect(index) then
            pending[#pending + 1] = index
        end
    end

    FullScan.progress = (last + 1) / total
    ns.Events:Fire("AC_SCAN_PROGRESS", FullScan.progress)

    if last + 1 < total then
        C_Timer.After(0, function() ProcessChunk(last + 1, total) end)
    elseif #pending > 0 then
        C_Timer.After(RETRY_DELAY, function() ProcessPending(1) end)
    else
        Finish()
    end
end

-- Stops a scan and resets its state, so a failure never leaves the scan
-- stuck as "running".
function FullScan:Abort(message)
    self:StopPolling()
    self.state = "idle"
    listings, pending = nil, nil
    if message then Util.Print(message) end
end

local function BeginProcessing()
    if FullScan.state ~= "waiting" then return end
    FullScan:StopPolling()

    local total = C_AuctionHouse.GetNumReplicateItems()
    if not total or total == 0 then
        FullScan:Abort(L.SCAN_FAILED)
        return
    end
    FullScan.state = "processing"
    FullScan.total = total
    listings, pending = {}, {}
    ownNames = BuildOwnNames()
    ProcessChunk(0, total)
end

-- Errors inside timer callbacks are easy to miss (WoW hides Lua errors by
-- default), so the scan steps report and reset instead of hanging.
local function Guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            FullScan.lastError = tostring(err)
            FullScan:Abort(L.SCAN_ERROR:format(FullScan.lastError))
        end
    end
end
ProcessChunk = Guarded(ProcessChunk)
ProcessPending = Guarded(ProcessPending)
BeginProcessing = Guarded(BeginProcessing)

-- REPLICATE_ITEM_LIST_UPDATE does not always arrive, so also poll the
-- replicate list and start once its size has been stable for 2 seconds.
local POLL_TIMEOUT = 120

function FullScan:StartPolling()
    self:StopPolling()
    local lastCount, stableTicks = -1, 0
    self.ticker = C_Timer.NewTicker(1, function()
        if self.state ~= "waiting" then
            self:StopPolling()
            return
        end
        local count = C_AuctionHouse.GetNumReplicateItems() or 0
        if count > 0 and count == lastCount then
            stableTicks = stableTicks + 1
            if stableTicks >= 2 then BeginProcessing() end
        else
            stableTicks = 0
        end
        lastCount = count
        if self.state == "waiting" and Util.Now() - self.startedAt > POLL_TIMEOUT then
            self:Abort(L.SCAN_NO_DATA)
        end
    end)
end

function FullScan:StopPolling()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

ns.Events:On("REPLICATE_ITEM_LIST_UPDATE", function()
    BeginProcessing()
end)

-- Auto scan: start shortly after the AH opens. If the 15 minute limit is
-- still running, say so and start by itself once it ends, as long as the
-- AH is still open.
local autoScanTimer

local function CancelAutoScan()
    if autoScanTimer then
        autoScanTimer:Cancel()
        autoScanTimer = nil
    end
end

ns.Events:On("AUCTION_HOUSE_SHOW", function()
    if not ns.db.settings.autoScan then return end
    CancelAutoScan()
    local wait = FullScan:SecondsUntilAllowed()
    if wait > 0 and not FullScan:IsRunning() then
        Util.Print(L.SCAN_AUTO_LATER:format(Util.FormatDuration(wait)))
    end
    autoScanTimer = C_Timer.NewTimer(wait + 1, function()
        autoScanTimer = nil
        FullScan:Start(false)
    end)
end)

ns.Events:On("AUCTION_HOUSE_CLOSED", function()
    CancelAutoScan()
    -- A scan that never received data is dropped. One that is already
    -- processing keeps going: the data is already on the client.
    if FullScan.state == "waiting" then
        FullScan:Abort()
    end
end)

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------

local OTHER_SCANNERS = { "Auctionator", "TradeSkillMaster", "Auc-Advanced", "Journalator" }

function FullScan:PrintStatus()
    local realm = ns:GetRealmData()
    if self.state == "waiting" then
        Util.Print(L.STATUS_WAITING:format(Util.Now() - self.startedAt,
            C_AuctionHouse.GetNumReplicateItems() or 0))
    elseif self.state == "processing" then
        Util.Print(L.STATUS_PROCESSING:format(math.floor(self.progress * 100),
            BreakUpLargeNumbers(self.total or 0)))
    else
        Util.Print(L.STATUS_IDLE)
    end

    local priced = 0
    for _ in pairs(realm.scans) do priced = priced + 1 end
    if (realm.lastFullScan or 0) > 0 then
        print("  " .. L.STATUS_LAST_SCAN:format(Util.FormatAge(realm.lastFullScan), BreakUpLargeNumbers(priced)))
    else
        print("  " .. L.STATUS_NEVER)
    end

    local wait = self:SecondsUntilAllowed()
    if wait > 0 then
        print("  " .. L.STATUS_NEXT:format(Util.FormatDuration(wait)))
    end
    print("  " .. L.STATUS_REALM:format(ns.realmGroup or "?"))
    if self.lastError then
        print("  " .. L.STATUS_ERROR:format(self.lastError))
    end

    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local others = {}
    for _, name in ipairs(OTHER_SCANNERS) do
        if IsLoaded(name) then table.insert(others, name) end
    end
    if #others > 0 then
        print("  " .. L.STATUS_OTHERS:format(table.concat(others, ", ")))
    end
end

ns:RegisterCommand("scan", function() FullScan:Start(true) end, L.HELP_SCAN)
ns:RegisterCommand("status", function() FullScan:PrintStatus() end, L.HELP_STATUS)
