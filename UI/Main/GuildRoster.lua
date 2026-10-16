local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local issecretvalue = issecretvalue or function() return false end
local Lists = ns.Lists
local PersonBrowser = ns.PersonBrowser

-- My guild as Who's Who shows it, for the Guild tab and the game's guild window: its members from the roster, one row
-- per identity, the selected identity's detail and the sharing line.
---@class WhosWho.GuildRoster
local GuildRoster = {}
ns.GuildRoster = GuildRoster

local Identity, People = ns.Identity, ns.People

-- Class IDs by the class file name the roster gives, filled at first use.
---@type table<string, integer>?
local classIdByFile
-- Past it, no class ID is looked for: the scan below always ends.
local HIGHEST_CLASS_ID = 100

-- Class IDs have gaps (checked in game: 9 classes, Druid's ID 11), so they are scanned until every class is found.
local function classIdOf(classFile)
    if not classIdByFile then
        classIdByFile = {}
        local found, classCount = 0, GetNumClasses()
        for classID = 1, HIGHEST_CLASS_ID do
            if found == classCount then break end
            local _, file = GetClassInfo(classID)
            if file then
                classIdByFile[file] = classID
                found = found + 1
            end
        end
    end
    return classIdByFile[classFile]
end

---A member of my guild, as the roster shows it.
---@class WhosWho.GuildMember
---@field guid string
---@field name string
---@field classID integer?
---@field level integer
---@field online boolean
---@field zone string?
---@field rank string
---@field rankIndex integer 0 for the guild master, higher for lower ranks
---@field lastOnline number? seconds since the member was last online; nil while online or not known

---The members of my guild, from the roster.
---@return WhosWho.GuildMember[]
function GuildRoster.Members()
    local members = {}
    for i = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        local guid = select(17, GetGuildRosterInfo(i))
        local secret = issecretvalue(name) or issecretvalue(guid) or issecretvalue(level) or issecretvalue(online)
            or issecretvalue(classFile)
        if name and guid and not secret then
            local lastOnline
            if not online then
                local years, months, days, hours = GetGuildRosterLastOnline(i)
                if years then lastOnline = ((((years * 12 + months) * 30 + days) * 24) + hours) * 3600 end
            end
            members[#members + 1] = {
                guid = guid, name = name, classID = classIdOf(classFile), level = level, online = online == true,
                zone = zone, rank = rank, rankIndex = rankIndex, lastOnline = lastOnline,
            }
        end
    end
    return members
end

-- My own identity ---------------------------------------------------------------------------------

-- My record as my guild's members get it: the guild's content when it enforces linking and my identity is complete
-- there, my linked characters otherwise.
---@return WhosWho.IdentityRecord
local function ownGuildRecord()
    return Identity.UnsignedRecord(ns.Scopes.EnforcedGuild())
end

-- The name my guild's members show me under: my nickname, otherwise the name of the main they see.
local function ownNickname(record)
    return record.nickname or record.chars[ns.Record.ShownMain(record)].name
end

-- My own identity's row: the characters my guild gets, the one I play online.
---@param record WhosWho.IdentityRecord
---@return WhosWho.PersonListEntry
local function ownListEntry(record)
    local ownCharacterGuid, ownCharacters = UnitGUID("player"), Identity.Characters()
    local characterCount, lastSeen, onlineCharacter = 0, nil, nil
    for guid, character in pairs(record.chars) do
        characterCount = characterCount + 1
        local seen = ownCharacters[guid].lastSeen
        if not lastSeen or seen > lastSeen then lastSeen = seen end
        if guid == ownCharacterGuid then
            onlineCharacter = { guid = guid, name = character.name, classID = character.classID }
        end
    end
    return {
        id = Identity.Id(), nickname = ownNickname(record), source = "confirmed", characterCount = characterCount,
        lastSeen = lastSeen, online = onlineCharacter ~= nil, onlineCharacter = onlineCharacter,
    }
end

---@param record WhosWho.IdentityRecord
---@return WhosWho.PersonDetail
local function ownDetail(record)
    local ownCharacterGuid, ownCharacters = UnitGUID("player"), Identity.Characters()
    local mainGuid = ns.Record.ShownMain(record)
    local characters = {}
    for guid, character in pairs(record.chars) do
        local ownCharacter = ownCharacters[guid]
        characters[#characters + 1] = {
            guid = guid,
            name = character.name, classID = character.classID, state = "confirmed", main = guid == mainGuid,
            online = guid == ownCharacterGuid, lastSeen = ownCharacter.lastSeen, level = ownCharacter.level,
            ruleset = character.ruleset,
        }
    end
    PersonBrowser.SortCharacters(characters)
    return {
        nickname = ownNickname(record), source = "confirmed", characters = characters, id = Identity.Id(),
    }
end

-- Whether the search text, lowercased, is in my nickname or the name of a character my guild gets.
---@param record WhosWho.IdentityRecord
local function ownMatchesSearch(record, text)
    if text == "" or ownNickname(record):lower():find(text, 1, true) then return true end
    for _, character in pairs(record.chars) do
        if character.name:lower():find(text, 1, true) then return true end
    end
    return false
end

-- Rows -------------------------------------------------------------------------------------------

---A row of my guild's list: a person's row, with the member it shows in the game's guild window.
---@class WhosWho.GuildRosterEntry: WhosWho.PersonListEntry
---@field member WhosWho.GuildMember the identity's character in the guild being played, else its main there, else
---the first one met; the character itself for one no identity holds

---The identities of my guild's characters held as counts, as the Guild tab's header shows them.
---@class WhosWho.GuildCounts
---@field main integer
---@field alt integer
---@field unknown integer

---A row for each identity whose main is in my guild, mine included, and one for each character no identity holds,
---mine my guild doesn't get included, with the search applied.
---@param text string the search, lowercased
---@param members WhosWho.GuildMember[] the roster, from GuildRoster.Members
---@return WhosWho.GuildRosterEntry[] entries
---@return WhosWho.GuildCounts counts over the whole roster, the search left aside
function GuildRoster.Entries(text, members)
    local onlineGuids = ns.Scopes.OnlineGuids()
    local ownRecord = ownGuildRecord()
    local ownMainGuid = ns.Record.ShownMain(ownRecord)
    local entries, counts = {}, { main = 0, alt = 0, unknown = 0 }
    -- The member each identity's row shows: the one online, else its main, else the first met.
    local memberById = {}
    local function keepMember(id, member, isMain)
        local kept = memberById[id]
        if not kept or (member.online and not kept.online) or (isMain and not kept.online) then
            memberById[id] = member
        end
    end
    for _, member in ipairs(members) do
        local guid = member.guid
        local person = People.Find(guid)
        local entry
        if ownRecord.chars[guid] then
            keepMember(Identity.Id(), member, guid == ownMainGuid)
            if guid ~= ownMainGuid then
                counts.alt = counts.alt + 1
            else
                counts.main = counts.main + 1
                if ownMatchesSearch(ownRecord, text) then entry = ownListEntry(ownRecord) end
            end
        elseif person then
            keepMember(person.id, member, guid == person.main)
            if guid ~= person.main then
                counts.alt = counts.alt + 1
            else
                counts.main = counts.main + 1
                if Lists.MatchesSearch(person, text) then
                    entry = PersonBrowser.ListEntry(person, onlineGuids)
                    -- The nickname mine replaces, after mine.
                    local baseNickname = PersonBrowser.BaseNickname(person)
                    entry.nicknameAside = baseNickname and GRAY_FONT_COLOR:WrapTextInColorCode(baseNickname)
                end
            end
        else
            counts.unknown = counts.unknown + 1
            if text == "" or member.name:lower():find(text, 1, true) then
                entry = {
                    nickname = member.name, source = "unconfirmed", characterCount = 1, online = member.online,
                    member = member,
                    unknownCharacter = {
                        guid = guid, name = member.name,
                        newCharacter = member.classID and {
                            name = member.name, classID = member.classID, level = member.level,
                            ruleset = Identity.Ruleset(UnitGUID("player")),
                        },
                    },
                }
            end
        end
        if entry then entries[#entries + 1] = entry end
    end
    for _, entry in ipairs(entries) do
        if entry.id then entry.member = memberById[entry.id] end
    end
    return entries, counts
end

-- Detail -----------------------------------------------------------------------------------------

-- The players whose own record holds characters of my guild's identity, each with them, by nickname; nil for none.
---@return WhosWho.PlayerClaim[]?
local function playerClaims(clubId, id)
    local claimed = ns.GuildRecord.ClaimedByPlayers(clubId)[id]
    if not claimed then return nil end
    local recordChars = ns.GuildRecord.Held(clubId, id).chars
    local guidsByPlayer = {}
    for guid, playerId in pairs(claimed) do
        local guids = guidsByPlayer[playerId] or {}
        guidsByPlayer[playerId] = guids
        guids[#guids + 1] = guid
    end
    local claims = {}
    for playerId, guids in pairs(guidsByPlayer) do
        local names = {}
        for i, guid in ipairs(guids) do names[i] = recordChars[guid].name end
        table.sort(names)
        claims[#claims + 1] = {
            playerId = playerId, nickname = People.Nickname(playerId), characters = table.concat(names, ", "),
            guids = guids,
        }
    end
    table.sort(claims, function(a, b) return a.nickname < b.nickname end)
    return claims
end

---The detail of a person, or of my own identity as my guild gets it; nil for an identity I don't hold. The guild's
---view: the guild's nickname and Unlink, for an officer on one of my guild's identities; nothing of mine.
---@param id string
---@return WhosWho.PersonDetail?
function GuildRoster.Detail(id)
    if id == Identity.Id() then return ownDetail(ownGuildRecord()) end
    local person = People.Get(id)
    if not person then return nil end
    local detail = PersonBrowser.PersonDetail(person, ns.Scopes.OnlineGuids())
    local clubId = Identity.GuildId(UnitGUID("player"))
    local guildIdentity = person.madeByGuild ~= nil and person.madeByGuild == clubId
    detail.changes = guildIdentity and ns.Protocol.CanChangeGuildRecords() and "guild" or nil
    if detail.changes == "guild" then detail.claims = playerClaims(clubId, id) end
    return detail
end

-- Sharing ----------------------------------------------------------------------------------------

---The sharing line: my answer to my guild's rule while it enforces linking, otherwise the Guild scope; with the
---action that changes it when there is one.
---@return string text with its colour codes
---@return string? buttonLabel
---@return fun()? action
function GuildRoster.Sharing()
    local guid = UnitGUID("player")
    local answer = ns.Scopes.GuildRuleAnswer()
    local text, button, action
    if answer == "accepted" then
        local allLinked = Identity.AllLinkedInGuild(Identity.GuildId(guid), Identity.Ruleset(guid))
        text = allLinked and L["your characters here are linked and shared with the guild."]
            or L["your characters here are shared with the guild without being linked."]
    elseif answer == "refused" then
        text = ORANGE_FONT_COLOR:WrapTextInColorCode(L["you refused, so Who's Who shares nothing with this guild."])
        button, action = L["Change"], ns.IdentityDialogs.ShowGuildRule
    elseif answer == "unanswered" then
        text = YELLOW_FONT_COLOR:WrapTextInColorCode(L["you haven't answered yet, so Who's Who shares nothing with this guild."])
        button, action = L["Answer"], ns.IdentityDialogs.ShowGuildRule
    elseif Identity.LinkedCount() == 0 then
        text = L["Nothing is shared with this guild: no character is linked to your identity."]
        button, action = L["Link"], ns.IdentityDialogs.AskToLink
    elseif ns.Scopes.Get("guild") then
        text = L["Your identity is shared with this guild's members."]
    else
        text = L["Your identity isn't shared with this guild: sharing with your guild is off."]
        button, action = L["Share"], function() ns.Scopes.Set("guild", true) end
    end
    if answer then text = NORMAL_FONT_COLOR:WrapTextInColorCode(L["Requires linking:"]) .. " " .. text end
    return text, button, action
end
