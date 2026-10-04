-- Auction Coach - inventory tracking across characters.
-- Records tradeable items (soulbound and warbound items are skipped, since
-- they can never be sold on the AH) from bags, bank, reagent bank, warband
-- bank, guild bank, mailbox and active auctions.
-- Fires AC_INVENTORY_CHANGED after any change.

local _, ns = ...
local Util, Compat = ns.Util, ns.Compat

local Inventory = {}
ns.Inventory = Inventory

-- Character inventory locations, in display order.
Inventory.LOCATIONS = { "bags", "bank", "reagentBank", "mail", "auctions" }

local bankOpen = false
local totalsCache = nil

local function Changed()
    totalsCache = nil
    Util.Debounce("inventoryChanged", 0.5, function()
        ns.Events:Fire("AC_INVENTORY_CHANGED")
    end)
end

local function GetChar()
    local db = ns.db
    local char = db.characters[ns.charKey]
    if not char then
        char = {}
        db.characters[ns.charKey] = char
    end
    char.class = select(2, UnitClass("player"))
    char.realmGroup = ns.realmGroup
    char.lastSeen = Util.Now()
    char.gold = char.gold or 0
    char.professions = char.professions or {}
    char.inventory = char.inventory or {}
    for _, loc in ipairs(Inventory.LOCATIONS) do
        char.inventory[loc] = char.inventory[loc] or {}
    end
    return char
end

local function Add(target, link, count)
    local key = Util.ItemKeyFromLink(link)
    if not key then return end
    target[key] = (target[key] or 0) + (count or 1)
    -- Links of items the client has not loaded yet have no name, so
    -- replace them once a complete link comes along.
    local stored = ns.db.links[key]
    if not Util.LinkHasName(stored) then
        ns.db.links[key] = link
    end
end

local function ScanContainers(bagIDs, target)
    wipe(target)
    for _, bagID in ipairs(bagIDs) do
        Compat.ForEachContainerItem(bagID, function(info)
            if not info.isBound then
                Add(target, info.hyperlink, info.stackCount)
            end
        end)
    end
end

function Inventory:ScanBags()
    ScanContainers(Compat.Bags.bags, GetChar().inventory.bags)
    Changed()
end

function Inventory:ScanBank()
    local inv = GetChar().inventory
    ScanContainers(Compat.Bags.bank, inv.bank)
    if #Compat.Bags.reagentBank > 0 then
        ScanContainers(Compat.Bags.reagentBank, inv.reagentBank)
    end
    ScanContainers(Compat.Bags.warband, ns.db.warbank)
    Changed()
end

function Inventory:ScanMail()
    local mail = GetChar().inventory.mail
    wipe(mail)
    local numItems = GetInboxNumItems()
    for i = 1, numItems do
        for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            local link = GetInboxItemLink(i, j)
            if link then
                local count = select(4, GetInboxItem(i, j))
                Add(mail, link, count)
            end
        end
    end
    Changed()
end

function Inventory:ScanAuctions()
    local auctions = GetChar().inventory.auctions
    wipe(auctions)
    local num = C_AuctionHouse.GetNumOwnedAuctions()
    for i = 1, num do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
        -- Sold auctions are waiting as gold in the mailbox, not items.
        if info and info.itemLink and info.status == Enum.AuctionStatus.Active then
            Add(auctions, info.itemLink, info.quantity)
        end
    end
    Changed()
end

-- The guild bank only sends the contents of the tab being viewed, so each
-- tab is recorded when the player opens it.
function Inventory:ScanGuildBankTab()
    local guildName = GetGuildInfo("player")
    if not guildName or not GetCurrentGuildBankTab then return end
    local tab = GetCurrentGuildBankTab()
    if not tab or tab < 1 then return end

    local guildKey = guildName .. "-" .. GetNormalizedRealmName()
    local guild = ns.db.guilds[guildKey] or { tabs = {} }
    ns.db.guilds[guildKey] = guild
    local items = {}
    guild.tabs[tab] = items
    guild.lastSeen = Util.Now()

    for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            local count = select(2, GetGuildBankItemInfo(tab, slot))
            Add(items, link, count)
        end
    end
    Changed()
end

function Inventory:ScanCharacter()
    local char = GetChar()
    char.gold = GetMoney()
    wipe(char.professions)
    local prof1, prof2 = GetProfessions()
    for _, index in ipairs({ prof1, prof2 }) do
        local name, _, level, _, _, _, skillLine = GetProfessionInfo(index)
        if name then
            table.insert(char.professions, { skillLine = skillLine, name = name, level = level })
        end
    end
end

-- ---------------------------------------------------------------------
-- Totals across all characters
-- ---------------------------------------------------------------------

-- Returns { [itemKey] = { total = n, where = { [owner] = { [location] = n } } } }
-- Owner is a character key or "warband". Guild banks are left out because
-- their contents belong to the guild, not the player.
function Inventory:GetTotals()
    if totalsCache then return totalsCache end
    local totals = {}

    local function AddLocation(owner, location, items)
        for key, count in pairs(items) do
            local entry = totals[key]
            if not entry then
                entry = { total = 0, where = {} }
                totals[key] = entry
            end
            entry.total = entry.total + count
            local byOwner = entry.where[owner] or {}
            entry.where[owner] = byOwner
            byOwner[location] = (byOwner[location] or 0) + count
        end
    end

    for charKey, char in pairs(ns.db.characters) do
        for _, loc in ipairs(Inventory.LOCATIONS) do
            if char.inventory and char.inventory[loc] then
                AddLocation(charKey, loc, char.inventory[loc])
            end
        end
    end
    AddLocation("warband", "bank", ns.db.warbank)

    totalsCache = totals
    return totals
end

function Inventory:GetCount(key)
    local entry = self:GetTotals()[key]
    return entry and entry.total or 0
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------

local Events = ns.Events

Events:On("AC_LOGIN", function()
    Inventory:ScanCharacter()
    Inventory:ScanBags()
end)

Events:On("BAG_UPDATE_DELAYED", function()
    if not ns.charKey then return end
    Inventory:ScanBags()
    if bankOpen then Inventory:ScanBank() end
end)

Events:On("PLAYER_MONEY", function()
    if ns.charKey then GetChar().gold = GetMoney() end
end)

Events:On("BANKFRAME_OPENED", function()
    bankOpen = true
    Inventory:ScanBank()
end)

Events:On("BANKFRAME_CLOSED", function()
    bankOpen = false
end)

for _, event in ipairs({ "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED", "BANK_TABS_CHANGED" }) do
    Events:On(event, function()
        if bankOpen then
            Util.Debounce("bankScan", 0.3, function() Inventory:ScanBank() end)
        end
    end)
end

Events:On("MAIL_INBOX_UPDATE", function()
    Util.Debounce("mailScan", 0.3, function() Inventory:ScanMail() end)
end)

Events:On("AUCTION_HOUSE_SHOW", function()
    C_AuctionHouse.QueryOwnedAuctions({})
end)

Events:On("OWNED_AUCTIONS_UPDATED", function()
    Inventory:ScanAuctions()
end)

Events:On("GUILDBANKBAGSLOTS_CHANGED", function()
    Util.Debounce("guildScan", 0.3, function() Inventory:ScanGuildBankTab() end)
end)
