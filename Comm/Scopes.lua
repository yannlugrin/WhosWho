local _, ns = ...
---@cast ns WhosWho.Namespace
local Identity, People = ns.Identity, ns.People

-- Who my record goes to and through which channel, the GUIDs the game gives for the players I share with, and the
-- relationships kept on confirmed characters (guild, friendOf).

---@class WhosWho.Scopes
local Scopes = {}
ns.Scopes = Scopes

local issecretvalue = issecretvalue or function() return false end

---@alias WhosWho.Channel "GUILD"|"PARTY"|"RAID"|"WHISPER"

---Every player a message for all my enabled scopes reaches.
---@class WhosWho.Audience
---@field memberChannels WhosWho.Channel[] GUILD, PARTY or RAID: one message reaches every member
---@field names string[] players reached by no member channel, one message each

-- Sources ----------------------------------------------------------------------------------------

---@type table<string, string> whole name -> GUID, players whispered with this session (sent or received)
local whisperGuids = {}

---Whether no value read from the game is secret. A secret value (Midnight-era API) may only be displayed: never
---compared, stored or used as a key.
local function notSecret(...)
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return false end
    end
    return true
end

-- A member of my current guild, from the roster; stops at the name.
local function guildMemberGuid(name)
    for i = 1, GetNumGuildMembers() do
        local memberName = GetGuildRosterInfo(i)
        if memberName and notSecret(memberName) and memberName == name then
            local guid = select(17, GetGuildRosterInfo(i))
            return guid and notSecret(guid) and guid or nil
        end
    end
    return nil
end

-- Another member of my group, from the group units; stops at the name.
local function groupMemberGuid(name)
    local unitPrefix, unitCount
    if IsInRaid() then
        unitPrefix, unitCount = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        unitPrefix, unitCount = "party", GetNumSubgroupMembers()
    else
        return nil
    end

    for i = 1, unitCount do
        local unit = unitPrefix .. i
        local unitName, guid = ns.UnitWholeName(unit), UnitGUID(unit)
        if unitName and guid and notSecret(unitName, guid) and unitName == name and guid ~= UnitGUID("player") then
            return guid
        end
    end
    return nil
end

local function friendGuid(name)
    local info = C_FriendList.GetFriendInfo(name)
    local guid = info and info.guid
    return guid and notSecret(guid) and guid or nil
end

---The GUID of an add-on message's sender, from the one source its channel names: the guild roster for GUILD, the
---group units for PARTY and RAID, my friend list or the whispers of this session for WHISPER. Names match exactly.
---@param name string "First Surname", as the add-on message gives it
---@param distribution string the channel the message came on
---@return string? guid
function Scopes.SenderGuid(name, distribution)
    if distribution == "GUILD" then return guildMemberGuid(name) end
    if distribution == "PARTY" or distribution == "RAID" then return groupMemberGuid(name) end
    if distribution == "WHISPER" then return friendGuid(name) or whisperGuids[name] end
    return nil
end

---A whisper sent or received (CHAT_MSG_WHISPER, CHAT_MSG_WHISPER_INFORM: arguments 2 and 12).
---@param name any
---@param guid any
function Scopes.Whispered(name, guid)
    if name and guid and notSecret(name, guid) then whisperGuids[name] = guid end
end

-- Relationships ----------------------------------------------------------------------------------

---GUILD_ROSTER_UPDATE: my current character's guild, and the guild of the characters I hold.
function Scopes.ReadGuildRoster()
    local count = GetNumGuildMembers()
    local clubId = C_Club.GetGuildClubId()
    -- The roster is empty until the game has loaded it.
    if count == 0 or not clubId then return end

    local memberGuids = {}
    for i = 1, count do
        local guid = select(17, GetGuildRosterInfo(i))
        if guid and notSecret(guid) then memberGuids[guid] = true end
    end

    Identity.SetGuild(UnitGUID("player"), clubId)
    People.UpdateGuildMembers(clubId, memberGuids)
end

---PLAYER_GUILD_UPDATE for my character: a guild left, or joined (its roster follows).
function Scopes.GuildChanged()
    if IsInGuild() then
        C_GuildInfo.GuildRoster()
        return
    end
    Identity.SetGuild(UnitGUID("player"), nil)
end

---FRIENDLIST_UPDATE: friendOf of the characters I hold, for my current character.
function Scopes.ReadFriends()
    local friendGuids = {}
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.guid and notSecret(info.guid) then friendGuids[info.guid] = true end
    end
    People.UpdateFriends(UnitGUID("player"), friendGuids)
end

---After an announcement from this character: its guild and friendOf, when it is in my guild or friend list.
---@param guid string
---@param name string
function Scopes.SetRelationships(guid, name)
    local clubId = IsInGuild() and C_Club.GetGuildClubId()
    if clubId and C_GuildInfo.MemberExistsByName(name) then People.SetGuild(guid, clubId) end
    if friendGuid(name) == guid then People.SetFriendOf(guid, UnitGUID("player")) end
end

-- Sharing ----------------------------------------------------------------------------------------

---Whether my scopes allow sharing identities with that player, both ways: sending my record, and using or asking
---for theirs.
---@param name string "First Surname"
---@return boolean
function Scopes.Allows(name)
    local scopes = ns.settings.scopes
    if scopes.guild and C_GuildInfo.MemberExistsByName(name) then return true end
    if scopes.friends and C_FriendList.GetFriendInfo(name) then return true end
    if scopes.group and groupMemberGuid(name) then return true end
    if scopes.whispers and whisperGuids[name] then return true end

    -- An alt of a player my scopes allow: one of the person's confirmed characters has a guild one of my characters is
    -- in (Guild scope), or is the WoW friend of one of my characters (Friends scope).
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    local person = ruleset and People.FindConfirmedByName(name, ruleset)
    if not person then return false end

    for _, character in pairs(person.chars) do
        if character.state == "confirmed" then
            if scopes.guild and character.guild and Identity.HasCharacterInGuild(character.guild, character.ruleset) then
                return true
            end
            if scopes.friends and character.friendOf then return true end
        end
    end

    return false
end

---My group's channel: RAID in a raid, PARTY otherwise.
---@return WhosWho.Channel
function Scopes.GroupChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

---Whether that player is in my guild and the Guild scope is on: the GUILD channel reaches it.
---@param name string
---@return boolean
function Scopes.GuildReaches(name)
    return ns.settings.scopes.guild and C_GuildInfo.MemberExistsByName(name)
end

---Whether that player is in my group and the Group scope is on: the group channel reaches it.
---@param name string
---@return boolean
function Scopes.GroupReaches(name)
    return ns.settings.scopes.group and groupMemberGuid(name) ~= nil
end

---Every player my enabled scopes reach, each once: the member channels (GUILD, PARTY or RAID), and one message to
---each online friend or player whispered with this session that no member channel reaches.
---@return WhosWho.Audience
function Scopes.BroadcastAudience()
    local scopes = ns.settings.scopes
    local memberChannels, names, seen = {}, {}, { [ns.UnitWholeName("player")] = true }

    if scopes.guild and IsInGuild() then memberChannels[#memberChannels + 1] = "GUILD" end
    if scopes.group and IsInGroup() then memberChannels[#memberChannels + 1] = Scopes.GroupChannel() end

    local function add(name)
        if seen[name] or Scopes.GuildReaches(name) or Scopes.GroupReaches(name) then return end
        seen[name] = true
        names[#names + 1] = name
    end
    if scopes.friends then
        for i = 1, C_FriendList.GetNumFriends() do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected and info.name and notSecret(info.name) then add(info.name) end
        end
    end
    if scopes.whispers then
        for name in pairs(whisperGuids) do add(name) end
    end

    return { memberChannels = memberChannels, names = names }
end

---Whether a broadcast to that audience reaches the player.
---@param audience WhosWho.Audience
---@param name string
---@return boolean
function Scopes.BroadcastReaches(audience, name)
    if Scopes.GuildReaches(name) or Scopes.GroupReaches(name) then return true end
    for _, audienceName in ipairs(audience.names) do
        if audienceName == name then return true end
    end
    return false
end
