-- Auction Coach - plain-English advice lines on item tooltips.

local _, ns = ...
local L, Rules = ns.L, ns.Rules

local HEADER_COLOR = { 1, 0.82, 0 }

local function OnTooltipSetItem(tooltip)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not ns.db or not ns.db.settings.tooltip or not ns.realmGroup then return end

    local _, link = tooltip:GetItem()
    if not link then return end

    local lines = Rules:ForLink(link)
    if not lines or #lines == 0 then return end

    tooltip:AddLine(" ")
    tooltip:AddLine(L.ADDON_TITLE, HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])
    for _, line in ipairs(lines) do
        local c = Rules.COLORS[line.color] or Rules.COLORS.info
        tooltip:AddLine(line.text, c[1], c[2], c[3], true)
    end
    -- A gap below too, so lines other addons add next do not run into ours.
    tooltip:AddLine(" ")
    tooltip:Show()
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)

ns:RegisterCommand("tooltip", function()
    local settings = ns.db.settings
    settings.tooltip = not settings.tooltip
    ns.Util.Print(settings.tooltip and L.TOOLTIP_ON or L.TOOLTIP_OFF)
end, L.HELP_TOOLTIP)
