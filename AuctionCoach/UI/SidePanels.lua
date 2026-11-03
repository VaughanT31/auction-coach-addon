-- CtrlShiftZed side panels: one layout for the panels CtrlShiftZed's addons
-- put beside the profession window (Patron Planner's order queue, Auction
-- Coach's cheapest materials, Alt Inventory's other characters), so they
-- never cover each other. Each addon ships this same file; the newest copy
-- loaded runs the layout for all of them.
--
-- Shown panels stack in a column to the right of the window, lowest order
-- first (the order queue always on top). One that doesn't fit above the
-- bottom of the screen starts a new column. A strip of buttons beside the
-- window's tabs turns each panel on and off, and the game's Crafting Results
-- log moves to the right of the panels while any show.
--
--   SidePanels:Register(id, {
--       frame = frame,          the panel; placed here while it shows
--       label = "Order queue",  its button
--       tip = "...",            the button's tooltip
--       order = 10,             smaller is higher up
--       pages = { orders = true, recipes = true },  where its button shows
--       isOn = function() return true end,          the addon's own setting
--       toggle = function() end,  turns it on or off; the addon refreshes it
--   })
--   SidePanels:Layout()         after a panel changes what it holds (shows,
--                               hides and size changes are hooked)

local _, ns = ...

local VERSION = 1
local SidePanels = _G.CtrlShiftZedSidePanels
if SidePanels and (SidePanels.version or 0) >= VERSION then
    ns.SidePanels = SidePanels
    return
end
SidePanels = SidePanels or { list = {}, logHome = {} }
SidePanels.version = VERSION
_G.CtrlShiftZedSidePanels = SidePanels
ns.SidePanels = SidePanels

local GAP = 6
local MARGIN = 10

local function Window()
    return _G.ProfessionsFrame
end

-- "orders", "recipes" or nil (specializations, or the window is closed).
function SidePanels:Page()
    local window = Window()
    if not (window and window:IsShown()) then return nil end
    if window.OrdersPage and window.OrdersPage:IsShown() then return "orders" end
    if window.CraftingPage and window.CraftingPage:IsShown() then return "recipes" end
    return nil
end

function SidePanels:Register(id, info)
    for i, panel in ipairs(self.list) do
        if panel.id == id then table.remove(self.list, i) break end
    end
    info.id = id
    self.list[#self.list + 1] = info
    local frame = info.frame
    if not frame.czSidePanel then
        frame.czSidePanel = true
        frame:HookScript("OnShow", function() SidePanels:QueueLayout() end)
        frame:HookScript("OnHide", function() SidePanels:QueueLayout() end)
        frame:HookScript("OnSizeChanged", function() SidePanels:QueueLayout() end)
    end
    self:Hook()
    self:QueueLayout()
end

-- Once per frame at most, after whatever showed or hid has settled.
function SidePanels:QueueLayout()
    if self.pending then return end
    self.pending = true
    C_Timer.After(0, function()
        SidePanels.pending = false
        SidePanels:Layout()
    end)
end

function SidePanels:Hook()
    local window = Window()
    if self.hooked or not window then return end
    self.hooked = true
    window:HookScript("OnShow", function() SidePanels:QueueLayout() end)
    window:HookScript("OnHide", function() SidePanels:QueueLayout() end)
    for _, key in ipairs({ "OrdersPage", "CraftingPage", "SpecPage" }) do
        local page = window[key]
        if page then
            page:HookScript("OnShow", function() SidePanels:QueueLayout() end)
            page:HookScript("OnHide", function() SidePanels:QueueLayout() end)
        end
    end
end

-- Stacks the shown panels: down from the window's top, then a new column.
function SidePanels:Layout()
    local window = Window()
    if not window then return end
    local shown = {}
    for _, panel in ipairs(self.list) do
        if panel.frame:IsShown() then shown[#shown + 1] = panel end
    end
    table.sort(shown, function(a, b)
        if a.order ~= b.order then return (a.order or 50) < (b.order or 50) end
        return a.id < b.id
    end)

    -- Worked out in screen units, since the panels can have their own scale.
    local scale = window:GetEffectiveScale()
    local top, edge = window:GetTop(), window:GetRight()
    self.right = nil
    if top and edge then
        top, edge = top * scale, edge * scale
        local x, y, columnWidth, first = edge + GAP * scale, top, 0, true
        for _, panel in ipairs(shown) do
            local frame = panel.frame
            local s = frame:GetEffectiveScale()
            local width, height = frame:GetWidth() * s, frame:GetHeight() * s
            if not first and y - height < MARGIN * scale then
                x, y, columnWidth, first = x + columnWidth + GAP * scale, top, 0, true
            end
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", window, "TOPRIGHT", (x - edge) / s, (y - top) / s)
            y = y - height - GAP * scale
            columnWidth = math.max(columnWidth, width)
            first = false
        end
        if #shown > 0 then self.right = (x + columnWidth) / scale end
    end
    self:PlaceLogs()
    self:RefreshButtons()
end

-- The game's Crafting Results log opens beside the window too: while any
-- panel shows it moves to their right, unless that would leave the screen.
function SidePanels:PlaceLogs()
    local window = Window()
    local logs = {}
    local crafting = window.CraftingPage
    local view = window.OrdersPage and window.OrdersPage.OrderView
    logs[#logs + 1] = crafting and crafting.CraftingOutputLog
    logs[#logs + 1] = view and view.CraftingOutputLog
    local right, edge = self.right, window:GetRight()
    local fits = right and edge
    if fits then
        for _, log in ipairs(logs) do
            if (right + GAP + log:GetWidth()) * window:GetEffectiveScale() > UIParent:GetRight() * UIParent:GetEffectiveScale() then
                fits = false
            end
        end
    end
    for _, log in ipairs(logs) do
        if fits then
            if not self.logHome[log] then
                local points = {}
                for i = 1, log:GetNumPoints() do points[i] = { log:GetPoint(i) } end
                self.logHome[log] = points
            end
            log:ClearAllPoints()
            log:SetPoint("TOPLEFT", window, "TOPRIGHT", math.floor(right - edge + GAP + 0.5), 0)
        elseif self.logHome[log] then
            log:ClearAllPoints()
            for _, point in ipairs(self.logHome[log]) do log:SetPoint(unpack(point)) end
            self.logHome[log] = nil
        end
    end
end

-- Buttons ----------------------------------------------------------------

local function PaintButton(button, on)
    button.text:SetTextColor(on and 1 or 0.55, on and 0.82 or 0.55, on and 0 or 0.55)
    button.light:SetColorTexture(on and 1 or 0.4, on and 0.82 or 0.4, on and 0 or 0.4, on and 0.9 or 0.5)
    button.line:SetShown(on)
end

function SidePanels:Button(panel)
    self.buttons = self.buttons or {}
    local button = self.buttons[panel.id]
    if button then return button end
    button = CreateFrame("Button", nil, self.strip)
    button:SetHeight(22)
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.06, 0.06, 0.07, 0.92)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)
    button.light = button:CreateTexture(nil, "ARTWORK")
    button.light:SetSize(6, 6)
    button.light:SetPoint("LEFT", 8, 0)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("LEFT", button.light, "RIGHT", 6, 0)
    button.line = button:CreateTexture(nil, "ARTWORK")
    button.line:SetColorTexture(1, 0.82, 0, 0.8)
    button.line:SetHeight(2)
    button.line:SetPoint("BOTTOMLEFT", 4, 0)
    button.line:SetPoint("BOTTOMRIGHT", -4, 0)
    button:SetScript("OnClick", function(self)
        local p = self.panel
        if p and p.toggle then
            local ok, err = pcall(p.toggle)
            if not ok then geterrorhandler()(err) end
        end
        SidePanels:QueueLayout()
    end)
    button:SetScript("OnEnter", function(self)
        local p = self.panel
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(p.label, 1, 0.82, 0)
        if p.tip then GameTooltip:AddLine(p.tip, 1, 1, 1, true) end
        GameTooltip:AddLine(p.isOn() and "Click to hide it." or "Click to show it.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.buttons[panel.id] = button
    return button
end

-- Beside the window's tabs, at its bottom right: a button for each panel
-- that belongs on this page.
function SidePanels:RefreshButtons()
    local window = Window()
    if not self.strip then
        self.strip = CreateFrame("Frame", nil, window)
        self.strip:SetHeight(22)
        self.strip:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", -4, 0)
    end
    local page = self:Page()
    local here = {}
    for _, panel in ipairs(self.list) do
        if page and panel.pages and panel.pages[page] and panel.isOn then here[#here + 1] = panel end
    end
    table.sort(here, function(a, b) return (a.order or 50) < (b.order or 50) end)
    for _, button in pairs(self.buttons or {}) do button:Hide() end
    local width = 0
    for i = #here, 1, -1 do
        local panel = here[i]
        local button = self:Button(panel)
        button.panel = panel
        button.text:SetText(panel.label)
        button:SetWidth(math.ceil(button.text:GetStringWidth()) + 28)
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", self.strip, "TOPRIGHT", -width, 0)
        local ok, on = pcall(panel.isOn)
        PaintButton(button, ok and on)
        button:Show()
        width = width + button:GetWidth() + 2
    end
    self.strip:SetWidth(math.max(1, width))
    self.strip:SetShown(#here > 0)
end
