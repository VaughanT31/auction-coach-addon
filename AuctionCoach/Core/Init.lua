-- Auction Coach - bootstrap: SavedVariables setup, version migration and
-- slash commands. Other modules wait for these internal messages:
--   AC_DB_READY  ns.db is ready (fired on ADDON_LOADED)
--   AC_LOGIN     the character is in the world (fired on PLAYER_LOGIN)

local ADDON_NAME, ns = ...
local L = ns.L

local DB_VERSION = 1

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
    },
    characters = {},
    warbank = {},
    guilds = {},
    accounting = { sales = {}, buys = {}, cancels = {}, expired = {} },
    undercuts = {},
    -- Per connected-realm group: scans, competition samples, scan times.
    realms = {},
    -- One example link per item key, for names, icons and tooltips.
    links = {},
    treasureNoticeAt = 0,
}

-- MIGRATIONS[n] upgrades a database from version n - 1 to version n.
local MIGRATIONS = {}

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
function AuctionCoach_OnAddonCompartmentClick()
    if ns.MainWindow then ns.MainWindow:Toggle() end
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
