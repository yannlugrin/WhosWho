local _, ns = ...
---@cast ns WhosWho.Namespace

---@class WhosWho.Tooltip
local Tooltip = {}
ns.Tooltip = Tooltip

local L = ns.L
local Glyphs = ns.Glyphs
local issecretvalue = issecretvalue or function() return false end

local function soft(text)
    return LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(text)
end

-- The person's other characters on the hovered character's ruleset: main first, then the most recently seen.
local function otherCharactersLine(person, guid)
    local ruleset = person.chars[guid].ruleset
    local others = {}
    for otherGuid, character in pairs(person.chars) do
        if otherGuid ~= guid and character.ruleset == ruleset then
            others[#others + 1] = { guid = otherGuid, character = character }
        end
    end
    if not others[1] then return nil end

    table.sort(others, function(a, b)
        local aMain, bMain = a.guid == person.main, b.guid == person.main
        if aMain ~= bMain then return aMain end
        return (a.character.lastSeen or 0) > (b.character.lastSeen or 0)
    end)

    local settings = ns.settings.tooltip.otherCharacters
    local names = {}
    for i = 1, math.min(#others, settings.limit) do
        local entry = others[i]
        local character = entry.character
        local name = character.name
        if settings.classColor then
            name = ns.Lists.ClassColoredName(name, character.classID)
        end
        if character.state == "listed" then name = Glyphs.Markup(Glyphs.Character.listed) .. name end
        if entry.guid == person.main then name = name .. Glyphs.Markup(Glyphs.Main) end
        names[#names + 1] = name
    end
    local line = table.concat(names, ", ")
    if #others > settings.limit then
        line = line .. " " .. L["+%d more"]:format(#others - settings.limit)
    end
    return soft(L["Also: %s"]:format(line))
end

local NOTE_START_LENGTH = 60

-- The note's first line, shortened to NOTE_START_LENGTH characters, a whole UTF-8 character at a time.
local function noteStart(note)
    local firstLine = note:match("^[^\n]*")
    local text, length = {}, 0
    for character in firstLine:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if length == NOTE_START_LENGTH then
            return table.concat(text) .. "…"
        end
        text[#text + 1] = character
        length = length + 1
    end
    local start = table.concat(text)
    return firstLine ~= note and start .. "…" or start
end

-- A player's tooltip: the nickname after the name or on its own line, and the person's other characters. Not on
-- my own characters.
local function decorate(tooltip, data)
    if tooltip ~= GameTooltip then return end
    local guid = data and data.guid
    if not guid or issecretvalue(guid) then return end

    local resolution = ns.Resolver.Resolve(guid)
    if not resolution or resolution.mine then return end
    local person = ns.People.Get(resolution.id)
    if not (person and person.chars[guid]) then return end

    local settings = ns.settings
    local nickname = resolution.nickname
    if settings.tooltip.nickname.enable and nickname ~= person.chars[guid].name then
        if settings.tooltip.nickname.position == "afterName" then
            local nameLine = GameTooltipTextLeft1
            local text = nameLine:GetText()
            if text and not issecretvalue(text) then nameLine:SetText(text .. " " .. soft("(" .. nickname .. ")")) end
        elseif settings.tooltip.nickname.position == "ownLine" then
            tooltip:AddLine(soft(L["Who's Who: %s"]:format(nickname)))
        end
    end

    if settings.tooltip.otherCharacters.enable then
        local line = otherCharactersLine(person, guid)
        if line then tooltip:AddLine(line, nil, nil, nil, true) end
    end

    if settings.tooltip.note.enable and person.note then
        tooltip:AddLine(soft(L["Note: %s"]:format(noteStart(person.note))))
    end
end

---Decorates player tooltips. Call on PLAYER_LOGIN: one frame later, the decoration runs after the post-calls other
---add-ons register at login, so one that rewrites the name line (EllesmereUI hides player titles) keeps the nickname.
function Tooltip.Register()
    C_Timer.After(0, function() TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, decorate) end)
end
