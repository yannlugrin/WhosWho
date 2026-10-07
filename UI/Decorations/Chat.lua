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
