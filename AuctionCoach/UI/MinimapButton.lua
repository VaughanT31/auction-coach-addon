-- Auction Coach - minimap button. Left click opens the window, right click
-- the options. Drag it around the edge of the minimap. Hidden with the
-- "Minimap button" option; the addon compartment entry works either way.

local _, ns = ...
local L = ns.L

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local ICON = "Interface\\AddOns\\AuctionCoach\\Media\\icon"
local DEFAULT_ANGLE = 200

local button

local function Place()
    local angle = math.rad(ns.db.settings.minimapAngle or DEFAULT_ANGLE)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.db.settings.minimapAngle = math.floor(math.deg(math.atan2(cy - my, cx - mx)) + 0.5) % 360
    Place()
end

local function Create()
    button = CreateFrame("Button", "AuctionCoachMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Options:Open()
        else
            ns.MainWindow:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.ADDON_TITLE)
        GameTooltip:AddLine(L.MINIMAP_LEFT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_RIGHT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_DRAG, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function MinimapButton:Update()
    if ns.db.settings.minimapHide then
        if button then button:Hide() end
        return
    end
    if not button then Create() end
    Place()
    button:Show()
end

ns.Events:On("AC_LOGIN", function()
    if Minimap then MinimapButton:Update() end
end)
