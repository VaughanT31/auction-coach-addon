-- Auction Coach - bootstrap: SavedVariables setup, version migration and
-- slash commands. Other modules wait for these internal messages:
--   AC_DB_READY  ns.db is ready (fired on ADDON_LOADED)
--   AC_LOGIN     the character is in the world (fired on PLAYER_LOGIN)

local ADDON_NAME, ns = ...
local L = ns.L

local DB_VERSION = 2

local DEFAULTS = {
    version = DB_VERSION,
    settings = {
        sellerStyle = "casual", -- "casual" | "active" | "camper"
        shareData = false,
        autoScan = true,
        tooltip = true,
        vendorGuard = true,
        -- Warn when the AH pays at least this much more than a vendor (copper).
        guardMinGain = 10 * 10000,
        treasureNotice = true,
        -- Deals tab: at least this far below the usual price, and at
        -- least this much profit after the AH cut (copper).
        dealMinDiscount = 0.3,
        dealMinProfit = 5 * 10000,
        -- Chat line with what each sale made.
        saleMessages = true,
        -- At login, warn when the desktop app's prices are old (Data/Freshness.lua).
        staleWarning = true,
        -- Today's Plan: minutes the player has (Advice/Plan.lua).
        planMinutes = 15,
        minimapHide = false,
        minimapAngle = 200,
    },
    characters = {},
    warbank = {},
    guilds = {},
    accounting = { sales = {}, buys = {}, cancels = {}, expired = {} },
    undercuts = {},
    -- The player's posts of the last 48 hours, per realm group (Data/Sales.lua).
    posts = {},
    -- Per connected-realm group: scans, competition samples, scan times.
    realms = {},
    -- One example link per item key, for names, icons and tooltips.
    links = {},
    treasureNoticeAt = 0,
}

-- MIGRATIONS[n] upgrades a database from version n - 1 to version n.
local MIGRATIONS = {}

local OLD_GEAR_KEY = ":i%d+$"

-- v2: gear keys changed from item level ("123:i639") to bonus IDs
-- ("123:b6652.12817") so they match the server. Inventory counts are moved
-- using each key's saved link. Scan rows have no link, so old gear rows are
-- dropped and the next scan replaces them.
MIGRATIONS[2] = function(db)
    local rename = {}
    for key, link in pairs(db.links or {}) do
        if key:find(OLD_GEAR_KEY) then
            local newKey = ns.Util.ItemKeyFromLink(link)
            if newKey and newKey ~= key then rename[key] = newKey end
        end
    end

    local function Move(items)
        if type(items) ~= "table" then return end
        for old, new in pairs(rename) do
            if items[old] then
                items[new] = (items[new] or 0) + items[old]
                items[old] = nil
            end
        end
    end
    for _, char in pairs(db.characters or {}) do
        for _, items in pairs(char.inventory or {}) do Move(items) end
    end
    Move(db.warbank)
    for _, guild in pairs(db.guilds or {}) do
        for _, items in pairs(guild.tabs or {}) do Move(items) end
    end
    for old, new in pairs(rename) do
        db.links[new] = db.links[new] or db.links[old]
        db.links[old] = nil
    end

    for _, realm in pairs(db.realms or {}) do
        for _, field in ipairs({ "scans", "competition" }) do
            for key in pairs(realm[field] or {}) do
                if key:find(OLD_GEAR_KEY) then realm[field][key] = nil end
            end
        end
    end
end

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                ApplyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end

local function Migrate(db)
    local version = db.version or DB_VERSION
    while version < DB_VERSION do
        version = version + 1
        if MIGRATIONS[version] then
            MIGRATIONS[version](db)
        end
    end
    db.version = DB_VERSION
end

-- Scan data for the realm group the current character is on.
function ns:GetRealmData(groupKey)
    groupKey = groupKey or ns.realmGroup
    local realm = ns.db.realms[groupKey]
    if not realm then
        realm = { scans = {}, competition = {}, lastFullScan = 0, lastFullScanStart = 0 }
        ns.db.realms[groupKey] = realm
    end
    return realm
end

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------

local commands = {}
local commandOrder = {}

-- fn(args) runs for "/ac <name> <args>". help is shown by "/ac help".
function ns:RegisterCommand(name, fn, help)
    commands[name] = { fn = fn, help = help }
    table.insert(commandOrder, name)
end

local function ShowHelp()
    ns.Util.Print(L.HELP_HEADER)
    print("  " .. L.HELP_TOGGLE)
    for _, name in ipairs(commandOrder) do
        if commands[name].help then
            print("  " .. commands[name].help)
        end
    end
end

SLASH_AUCTIONCOACH1 = "/ac"
SLASH_AUCTIONCOACH2 = "/auctioncoach"
SlashCmdList.AUCTIONCOACH = function(input)
    local name, args = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    name = (name or ""):lower()
    if name == "" then
        if ns.MainWindow then ns.MainWindow:Toggle() end
    elseif name == "help" then
        ShowHelp()
    elseif commands[name] then
        commands[name].fn(args)
    else
        ns.Util.Print(L.UNKNOWN_COMMAND:format(name))
        ShowHelp()
    end
end

-- Addon compartment (the addons button by the minimap).
function AuctionCoach_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" and ns.Options then
        ns.Options:Open()
    elseif ns.MainWindow then
        ns.MainWindow:Toggle()
    end
end

-- ---------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------

ns.Events:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    AuctionCoachDB = AuctionCoachDB or {}
    Migrate(AuctionCoachDB)
    ApplyDefaults(AuctionCoachDB, DEFAULTS)
    ns.db = AuctionCoachDB
    ns.Events:Fire("AC_DB_READY")
end)

ns.Events:On("PLAYER_LOGIN", function()
    ns.charKey = UnitName("player") .. "-" .. GetNormalizedRealmName()
    ns.realmGroup = ns.Compat.GetRealmGroupKey()
    ns.Events:Fire("AC_LOGIN")
end)
