-- Auction Coach - event dispatcher.
-- One frame for all game events, plus internal messages prefixed "AC_".
-- Handlers are called as fn(event, ...). Errors in one handler are reported
-- but do not stop the others.

local _, ns = ...

local Events = {}
ns.Events = Events

local frame = CreateFrame("Frame")
local handlers = {}

local function Dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        xpcall(list[i], geterrorhandler(), event, ...)
    end
end

function Events:On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if not event:find("^AC_") then
            -- pcall: registering an event this client does not know errors.
            pcall(frame.RegisterEvent, frame, event)
        end
    end
    list[#list + 1] = fn
end

function Events:Fire(message, ...)
    Dispatch(message, ...)
end

frame:SetScript("OnEvent", function(_, event, ...)
    Dispatch(event, ...)
end)
