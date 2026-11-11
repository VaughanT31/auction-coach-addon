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
-- The column starts past anything tab-sized sticking out of the window's
-- right edge (WoW Forever's profession tabs sit there). Shift-drag any panel
-- to move the whole column; Shift-right-click one to put it back. The move
-- is saved in every registered addon's store, so it survives whichever of
-- them is installed.
--
--   SidePanels:Register(id, {
--       frame = frame,          the panel; placed here while it shows
--       label = "Order queue",  its button
--       tip = "...",            the button's tooltip
--       order = 10,             smaller is higher up
--       pages = { orders = true, recipes = true },  where its button shows
--       isOn = function() return true end,          the addon's own setting
--       toggle = function() end,  turns it on or off; the addon refreshes it
--       store = function() return MyAddonDB end,    a saved table for the move
--   })
--   SidePanels:Layout()         after a panel changes what it holds (shows,
--                               hides and size changes are hooked)

local _, ns = ...

local VERSION = 2
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
-- Narrower than this and sticking out past the window's right edge by at
-- least TAB_MIN_OUT counts as a tab to clear. The close button only pokes
-- out a few pixels; the Crafting Results log and other panels are wider.
local TAB_MAX_WIDTH = 80
local TAB_MIN_OUT = 12
local SAVE_KEY = "czSidePanelOffset"

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
    self:AttachDrag(frame)
    self:Hook()
    self:QueueLayout()
end

-- Moving the column ----------------------------------------------------------

-- The column's move from where it would sit, in the window's units: the live
-- drag while one is going, else the saved one from the first store that has it.
function SidePanels:Offset()
    if self.live then return self.live.x, self.live.y end
    if not self.saved then
        for _, panel in ipairs(self.list) do
            local ok, store = pcall(panel.store or function() end)
            local saved = ok and type(store) == "table" and store[SAVE_KEY]
            if type(saved) == "table" then
                self.saved = { x = tonumber(saved.x) or 0, y = tonumber(saved.y) or 0 }
                break
            end
        end
    end
    if self.saved then return self.saved.x, self.saved.y end
    return 0, 0
end

function SidePanels:SaveOffset(x, y)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    self.saved = { x = x, y = y }
    for _, panel in ipairs(self.list) do
        local ok, store = pcall(panel.store or function() end)
        if ok and type(store) == "table" then
            store[SAVE_KEY] = (x ~= 0 or y ~= 0) and { x = x, y = y } or nil
        end
    end
end

function SidePanels:EndDrag()
    if not self.drag then return end
    if self.live then self:SaveOffset(self.live.x, self.live.y) end
    self.drag, self.live = nil, nil
    if self.driver then self.driver:Hide() end
    self:QueueLayout()
end

-- Follows the cursor while a drag is going, moving every panel with it.
function SidePanels:Driver()
    if self.driver then return self.driver end
    self.driver = CreateFrame("Frame")
    self.driver:Hide()
    self.driver:SetScript("OnUpdate", function()
        local drag, window = SidePanels.drag, Window()
        if not (drag and window and IsMouseButtonDown("LeftButton")) then return SidePanels:EndDrag() end
        local cx, cy = GetCursorPosition()
        local scale = window:GetEffectiveScale()
        SidePanels.live = { x = drag.x + (cx - drag.cx) / scale, y = drag.y + (cy - drag.cy) / scale }
        SidePanels:Layout()
    end)
    return self.driver
end

function SidePanels:AttachDrag(frame)
    if frame.czSidePanelDrag then return end
    frame.czSidePanelDrag = true
    frame:EnableMouse(true)
    frame:HookScript("OnMouseDown", function(_, button)
        if not IsShiftKeyDown() then return end
        if button == "RightButton" then
            SidePanels:SaveOffset(0, 0)
            SidePanels:QueueLayout()
        elseif button == "LeftButton" then
            local x, y = SidePanels:Offset()
            local cx, cy = GetCursorPosition()
            SidePanels.drag = { x = x, y = y, cx = cx, cy = cy }
            SidePanels:Driver():Show()
        end
    end)
    frame:HookScript("OnMouseUp", function() SidePanels:EndDrag() end)
end

-- How far tab-sized frames stick out past the window's right edge, in screen
-- units: its children and their children, skipping the panels themselves.
function SidePanels:TabsClearance(window)
    local scale = window:GetEffectiveScale()
    local edge, top, bottom = window:GetRight(), window:GetTop(), window:GetBottom()
    if not (edge and top and bottom) then return 0 end
    edge, top, bottom = edge * scale, top * scale, bottom * scale
    local most = 0
    local function check(frame, depth)
        if frame.czSidePanel or frame == self.strip or not frame:IsShown() then return end
        local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        if l and r and t and b then
            local s = frame:GetEffectiveScale()
            l, r, t, b = l * s, r * s, t * s, b * s
            if r - l <= TAB_MAX_WIDTH * s and r - edge >= TAB_MIN_OUT * s and t > bottom and b < top then
                most = math.max(most, r - edge)
            end
        end
        if depth < 2 then
            for _, child in ipairs({ frame:GetChildren() }) do check(child, depth + 1) end
        end
    end
    for _, child in ipairs({ window:GetChildren() }) do check(child, 1) end
    return most
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
        local dx, dy = self:Offset()
        local clear = #shown > 0 and self:TabsClearance(window) or 0
        top, edge = top * scale, edge * scale
        local columnTop = top + dy * scale
        local x, y, columnWidth, first = edge + clear + (GAP + dx) * scale, columnTop, 0, true
        for _, panel in ipairs(shown) do
            local frame = panel.frame
            local s = frame:GetEffectiveScale()
            local width, height = frame:GetWidth() * s, frame:GetHeight() * s
            if not first and y - height < MARGIN * scale then
                x, y, columnWidth, first = x + columnWidth + GAP * scale, columnTop, 0, true
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
        GameTooltip:AddLine("Shift-drag a panel to move them all, Shift-right-click to put them back.", 0.6, 0.6, 0.6, true)
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

-- Panels an older copy registered before this one loaded get the drag too.
for _, panel in ipairs(SidePanels.list) do SidePanels:AttachDrag(panel.frame) end
