local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local issecretvalue = issecretvalue or function() return false end

-- The Who's Who section of a player's right-click menu: in the game's menus, and in the People tab's own menu.

---@class WhosWho.UnitMenu
local UnitMenu = {}
ns.UnitMenu = UnitMenu

-- The game's right-click menus on a player that get the Who's Who entry.
local MENUS = {
    "MENU_UNIT_SELF", "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_FRIEND_OFFLINE", "MENU_UNIT_GUILD",
    "MENU_UNIT_GUILD_OFFLINE", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_BN_FRIEND", "MENU_UNIT_RECENT_ALLY",
    "MENU_UNIT_RECENT_ALLY_OFFLINE",
}

-- The whole name, "First Surname", from its two parts; a name without a second part is already whole.
local function wholeName(name, surname)
    if surname and surname ~= "" then return name .. " " .. surname end
    return name
end

-- The player's GUID: from the menu, its unit, the character a Battle.net friend is playing or its chat line, else
-- from the guild roster, the group, my friends or the players whispered this session.
local function playerGuid(contextData)
    if contextData.guid then return contextData.guid end
    local unit = contextData.unit
    if unit then return UnitIsPlayer(unit) and UnitGUID(unit) or nil end
    if contextData.bnetIDAccount then
        local account = C_BattleNet.GetAccountInfoByID(contextData.bnetIDAccount)
        return account and account.gameAccountInfo and account.gameAccountInfo.playerGuid
    end
    -- A name in chat: the menu carries the line's ID, as text.
    local lineID = tonumber(contextData.lineID)
    if lineID then
        local guid = C_ChatInfo.GetChatLineSenderGUID(lineID)
        if guid then return guid end
    end
    if not contextData.name then return nil end
    local name = wholeName(contextData.name, contextData.surname)
    local Scopes = ns.Scopes
    return Scopes.SenderGuid(name, "GUILD") or Scopes.SenderGuid(name, "PARTY") or Scopes.SenderGuid(name, "WHISPER")
end

-- What a new person needs to know about the character: from its unit when there is one, from its GUID otherwise.
-- It is on my current character's ruleset, the only one I can meet.
---@return WhosWho.NewCharacter?
local function newCharacter(contextData, guid)
    local unit = contextData.unit
    if unit then
        local _, _, classID = UnitClass(unit)
        return { name = ns.UnitWholeName(unit), classID = classID, level = UnitLevel(unit),
            ruleset = ns.Identity.Ruleset(UnitGUID("player")) }
    end
    -- On Forever the realm part is the surname.
    local _, _, _, _, _, name, surname = GetPlayerInfoByGUID(guid)
    local _, _, classID = C_PlayerInfo.GetClass(PlayerLocation:CreateFromGUID(guid))
    if not (name and classID) then return nil end
    return { name = wholeName(name, surname), classID = classID, ruleset = ns.Identity.Ruleset(UnitGUID("player")) }
end

local function showMyIdentity()
    ns.Main.Window:Show()
    ns.Main.SelectTab(ns.Main.MyIdentity)
end

---Adds the Who's Who section, after a divider, when it has an entry for that player.
---@param root table the menu's root description
---@param contextData table the game's menu context: unit, guid, name and surname, Battle.net account or chat line
function UnitMenu.AddSection(root, contextData)
    if contextData.unit and not UnitIsFriend("player", contextData.unit) then return end
    local guid = playerGuid(contextData)
    if not guid or issecretvalue(guid) then return end

    if ns.Identity.Characters()[guid] then
        root:CreateDivider()
        root:CreateTitle(L["Who's Who"])
        root:CreateButton(L["Show my identity"], showMyIdentity)
        return
    end

    local People = ns.People
    local person = People.Find(guid)
    if person then
        local id = person.id
        local entries = {}
        -- The People panel's own menu is already on the person.
        if not contextData.fromPeoplePanel then
            entries[#entries + 1] = { L["Show person"], function() ns.Main.People:ShowPerson(id) end }
        end
        if People.CanSetMain(id, guid) then
            entries[#entries + 1] = { L["Make main"], function() ns.PeopleDialogs.ConfirmMakeMain(id, guid) end }
        end
        if People.CanRemoveCharacter(id, guid) then
            entries[#entries + 1] = { L["Unlink"], function() ns.PeopleDialogs.ConfirmUnlink(id, guid) end }
        end
        if not entries[1] then return end
        root:CreateDivider()
        root:CreateTitle(L["Who's Who: %s"]:format(People.Nickname(id)))
        for _, entry in ipairs(entries) do root:CreateButton(entry[1], entry[2]) end
        return
    end

    local character = newCharacter(contextData, guid)
    if not character then return end
    root:CreateDivider()
    root:CreateTitle(L["Who's Who"])
    root:CreateButton(L["Link character"], function() ns.PeopleDialogs.LinkCharacter:Open(guid, character) end)
end

for _, menu in ipairs(MENUS) do
    Menu.ModifyMenu(menu, function(_, root, contextData) UnitMenu.AddSection(root, contextData) end)
end
