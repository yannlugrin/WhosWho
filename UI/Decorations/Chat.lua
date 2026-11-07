local _, ns = ...
---@cast ns WhosWho.Namespace

local issecretvalue = issecretvalue or function() return false end

-- The sender's name in a chat line, followed by its nickname: the game puts the result inside the player link,
-- "[Ann Main (Annie)]". Returning nil leaves the name as it is.
local function addNickname(_, decoratedName, ...)
    if not ns.settings.chat.nickname.enable then return nil end

    -- The chat event's arguments: the sender's name is the second, its GUID the twelfth.
    local senderName, senderGuid = select(2, ...), select(12, ...)
    if not senderGuid or issecretvalue(senderGuid) or issecretvalue(senderName) then return nil end

    local resolution = ns.Resolver.Resolve(senderGuid)
    if not resolution or resolution.mine or resolution.nickname == senderName then return nil end
    return decoratedName .. " " .. LIGHTGRAY_FONT_COLOR:WrapTextInColorCode("(" .. resolution.nickname .. ")")
end

if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
    ChatFrameUtil.AddSenderNameFilter(addNickname)
end

-- The game's "No player named … is currently playing" line, as a pattern capturing the name.
local NOT_PLAYING_PATTERN = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    :gsub("%%%%s", "(.+)") .. "$"

-- That line for a character my add-on messages just whispered: hidden, the player never whispered it.
local function hideNotPlaying(_, _, message)
    if issecretvalue(message) then return false end

    local name = message:match(NOT_PLAYING_PATTERN)
    return name ~= nil and ns.Protocol.WhisperedRecently(name)
end
local addMessageEventFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
addMessageEventFilter("CHAT_MSG_SYSTEM", hideNotPlaying)
