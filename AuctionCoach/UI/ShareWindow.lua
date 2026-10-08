-- Auction Coach - copy and paste window for export and import strings.
-- /ac export shows the export string ready to copy; /ac import takes a
-- prices string from the website.

local _, ns = ...
local L, Util = ns.L, ns.Util

local ShareWindow = {}
ns.ShareWindow = ShareWindow

local WIDTH, HEIGHT = 520, 340

local frame

local function Create()
    frame = ns.Skin.Window("AuctionCoachShareWindow", WIDTH, HEIGHT, "DIALOG")
    frame:SetPoint("CENTER", 0, 40)

    frame.help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.help:SetPoint("TOPLEFT", 16, -42)
    frame.help:SetPoint("RIGHT", -16, 0)
    frame.help:SetJustifyH("LEFT")

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", frame.help, "BOTTOMLEFT", -4, -10)
    box:SetPoint("BOTTOMRIGHT", -14, 44)
    ns.Skin.Backdrop(box, { 0, 0, 0, 0.5 }, ns.Skin.BORDER)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
    edit:SetWidth(WIDTH - 80)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(_, width) edit:SetWidth(width) end)
    -- Clicking anywhere in the box focuses the text.
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    frame.edit = edit

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 16, 18)
    frame.status:SetPoint("RIGHT", -230, 0)
    frame.status:SetJustifyH("LEFT")

    frame.close = ns.Skin.Button(frame, CLOSE or "Close", 100, 22)
    frame.close:SetPoint("BOTTOMRIGHT", -14, 12)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.action = ns.Skin.Button(frame, nil, 110, 22)
    frame.action:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
end

local function Show(title, help)
    if not frame then Create() end
    frame.title:SetText(title)
    frame.help:SetText(help)
    frame.status:SetText("")
    frame.edit:SetText("")
    frame:Show()
end

function ShareWindow:ShowExport()
    if not ns.Share.IsSupported() then
        Util.Print(L.SHARE_UNSUPPORTED)
        return
    end
    local text = ns.Share:ExportString()
    if not text then
        Util.Print(L.EXPORT_FAILED)
        return
    end
    Show(L.EXPORT_TITLE, L.EXPORT_HELP)
    local edit = frame.edit
    edit:SetText(text)
    edit:SetScript("OnTextChanged", function(self, userInput)
        -- Read only: put the string back if it gets typed over.
        if userInput then self:SetText(text) self:HighlightText() end
    end)
    edit:SetFocus()
    edit:HighlightText()
    frame.status:SetText(L.EXPORT_SIZE:format(BreakUpLargeNumbers(#text)))
    frame.action:SetText(L.EXPORT_SELECT)
    frame.action:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
    end)
end

local IMPORT_ERRORS = {
    invalid = "IMPORT_INVALID",
    notPrices = "IMPORT_NOT_PRICES",
    older = "IMPORT_OLDER",
}

function ShareWindow:ShowImport()
    if not ns.Share.IsSupported() then
        Util.Print(L.SHARE_UNSUPPORTED)
        return
    end
    Show(L.IMPORT_TITLE, L.IMPORT_HELP)
    local edit = frame.edit
    edit:SetScript("OnTextChanged", nil)
    edit:SetFocus()
    frame.action:SetText(L.IMPORT_BUTTON)
    frame.action:SetScript("OnClick", function()
        local ok, result = ns.Share:Import(edit:GetText())
        if ok then
            local message = L.IMPORT_DONE:format(BreakUpLargeNumbers(result))
            Util.Print(message)
            frame:Hide()
        else
            frame.status:SetText("|cffff6666" .. L[IMPORT_ERRORS[result]] .. "|r")
        end
    end)
end

ns:RegisterCommand("export", function() ShareWindow:ShowExport() end, L.HELP_EXPORT)
ns:RegisterCommand("import", function() ShareWindow:ShowImport() end, L.HELP_IMPORT)
