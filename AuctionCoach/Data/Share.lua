-- Auction Coach - export and import strings, for copy-paste between the
-- addon and the website (no desktop app needed).
--
--   export  the player's characters, gold and item counts. Pasted into the
--           website, it gives a personal "what is it all worth" report.
--   import  prices for those items from the website, in the Data.lua
--           format. Stored in SavedVariables and used like Data.lua (the
--           newer of the two wins).
--
-- String format: "AC1:" .. base64(zlib(JSON)). The JSON has kind =
-- "inventory" or "prices". The platform reads and writes the same format
-- (api/share.py).

local _, ns = ...
local Util = ns.Util

local Share = {}
ns.Share = Share

local PREFIX = "AC1:"

-- C_EncodingUtil arrived in 11.1. Nil when this client lacks it.
local function Codec()
    local E = C_EncodingUtil
    if not (E and E.SerializeJSON and E.DeserializeJSON and E.CompressString
            and E.DecompressString and E.EncodeBase64 and E.DecodeBase64) then
        return nil
    end
    return E
end

function Share.IsSupported()
    return Codec() ~= nil
end

function Share.Encode(payload)
    local E = Codec()
    if not E then return nil end
    local ok, result = pcall(function()
        local json = E.SerializeJSON(payload)
        return PREFIX .. E.EncodeBase64(E.CompressString(json, Enum.CompressionMethod.Zlib))
    end)
    return ok and result or nil
end

-- Returns the decoded table, or nil when the string is not ours or broken.
function Share.Decode(text)
    local E = Codec()
    if not E or type(text) ~= "string" then return nil end
    text = text:gsub("%s+", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return nil end
    local ok, result = pcall(function()
        local json = E.DecompressString(E.DecodeBase64(text:sub(#PREFIX + 1)), Enum.CompressionMethod.Zlib)
        return E.DeserializeJSON(json)
    end)
    return ok and type(result) == "table" and result or nil
end

-- ---------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------

-- Everything the website needs for the report: per character its realm,
-- class, gold and item counts (all locations added up), plus the warband
-- bank. Guild banks are left out: they are not the player's to sell.
function Share:BuildExport()
    local chars = {}
    for charKey, char in pairs(ns.db.characters) do
        local items = {}
        local any = false
        for _, loc in ipairs(ns.Inventory.LOCATIONS) do
            for key, count in pairs(char.inventory and char.inventory[loc] or {}) do
                items[key] = (items[key] or 0) + count
                any = true
            end
        end
        local name, realm = charKey:match("^(.-)%-(.+)$")
        table.insert(chars, {
            name = name or charKey,
            realm = realm or "",
            class = char.class or "",
            gold = char.gold or 0,
            -- An empty table would come out as a JSON list.
            items = any and items or nil,
        })
    end
    table.sort(chars, function(a, b) return a.name < b.name end)

    local warband = next(ns.db.warbank) and ns.db.warbank or nil
    return {
        kind = "inventory",
        v = 1,
        region = ns.Compat.RegionCode(),
        realm = GetNormalizedRealmName(),
        at = Util.Now(),
        chars = chars,
        warband = warband,
    }
end

function Share:ExportString()
    return Share.Encode(self:BuildExport())
end

-- ---------------------------------------------------------------------
-- Import
-- ---------------------------------------------------------------------

local function ValidPrices(data)
    return type(data) == "table" and data.kind == "prices" and data.format == 1
        and type(data.generatedAt) == "number"
        and (data.commodities == nil or type(data.commodities) == "table")
        and (data.realms == nil or type(data.realms) == "table")
        and (data.realmIndex == nil or type(data.realmIndex) == "table")
end

-- Returns true, item count when the string held prices; false, reason
-- ("invalid" | "notPrices" | "older") otherwise.
function Share:Import(text)
    local data = Share.Decode(text)
    if not data then return false, "invalid" end
    if not ValidPrices(data) then return false, "notPrices" end
    local current = ns.db.imported
    if current and (current.generatedAt or 0) > data.generatedAt then
        return false, "older"
    end

    data.commodities = data.commodities or {}
    data.realms = data.realms or {}
    data.realmIndex = data.realmIndex or {}
    local count = 0
    for _ in pairs(data.commodities) do count = count + 1 end
    for _, items in pairs(data.realms) do
        for _ in pairs(items) do count = count + 1 end
    end

    ns.db.imported = data
    ns.Prices:DataChanged()
    return true, count
end
