local _, ns = ...
---@cast ns WhosWho.Namespace

-- The diagnostic mode: the Who's Who messages sent and received, kept in a log and printed in chat.

---@class WhosWho.Diagnostic
local Diagnostic = {}
ns.Diagnostic = Diagnostic

local L = ns.L

Diagnostic.KEPT_MESSAGES = 1000

---Saved in ns.data.messageLog.
---@class WhosWho.LoggedMessage
---@field time number seconds, from time()
---@field sent boolean false for a message received
---@field distribution string the add-on channel: GUILD, PARTY, RAID, WHISPER
---@field name string? the receiver of a whisper, or the sender of a message received
---@field text string the message; for a REC, a GSET, a GLIST or a GIREC, only its version, type and header
---@field size integer the message's length in bytes

---@type fun(message: WhosWho.LoggedMessage)[]
local listeners = {}

-- The payload of a REC, a GSET, a GLIST or a GIREC is binary: what comes before it, its header, is kept.
local function loggedText(text)
    return text:match("^(%d+ %u+ .-) : ") or text
end

-- Kept only while the diagnostic mode is on.
local function log(sent, text, distribution, name)
    if not ns.settings.diagnostic.enable then return end
    local message = {
        time = time(), sent = sent, distribution = distribution, name = name, text = loggedText(text), size = #text,
    }
    local messages = ns.data.messageLog
    table.insert(messages, 1, message)
    messages[Diagnostic.KEPT_MESSAGES + 1] = nil
    for _, listener in ipairs(listeners) do listener(message) end
    return message
end

---A logged message as shown: its text, with its size when its payload was left out.
---@param message WhosWho.LoggedMessage
---@return string
function Diagnostic.Describe(message)
    if message.size == #message.text then return message.text end
    return L["%s (%d bytes)"]:format(message.text, message.size)
end

---Prints a line in chat while the diagnostic mode and its chat output are on.
---@param line string
function Diagnostic.Print(line)
    local settings = ns.settings.diagnostic
    if settings.enable and settings.chat then ns.Print(line) end
end

---@param text string
---@param distribution string
---@param name string? the receiver of a whisper
function Diagnostic.MessageSent(text, distribution, name)
    local message = log(true, text, distribution, name)
    if not message then return end
    Diagnostic.Print(L["Sent, %s: %s"]:format(name and (distribution .. " " .. name) or distribution,
        Diagnostic.Describe(message)))
end

---@param text string
---@param distribution string
---@param sender string
function Diagnostic.MessageReceived(text, distribution, sender)
    local message = log(false, text, distribution, sender)
    if not message then return end
    Diagnostic.Print(L["Received, %s: %s"]:format(distribution .. " " .. sender, Diagnostic.Describe(message)))
end

---The logged messages, most recent first. Read only.
---@return WhosWho.LoggedMessage[]
function Diagnostic.Messages()
    return ns.data.messageLog
end

---The logged messages counted by type ("?" for a text that has none).
---@return table<string, { sent: integer, received: integer }>
function Diagnostic.CountsByType()
    local counts = {}
    for _, message in ipairs(ns.data.messageLog) do
        local messageType = message.text:match("^%d+ (%u+)") or "?"
        local count = counts[messageType] or { sent = 0, received = 0 }
        if message.sent then count.sent = count.sent + 1 else count.received = count.received + 1 end
        counts[messageType] = count
    end
    return counts
end

---PLAYER_LOGOUT: with the diagnostic mode off, the log is emptied. AceDB has removed the settings equal to their
---defaults, the mode's off included.
function Diagnostic.SessionEnding()
    local settings = ns.settings.diagnostic
    if not (settings and settings.enable) then ns.data.messageLog = {} end
end

---Calls listener(message) each time a message is logged.
---@param listener fun(message: WhosWho.LoggedMessage)
function Diagnostic.OnMessageLogged(listener)
    listeners[#listeners + 1] = listener
end
