local _, ns = ...
---@cast ns WhosWho.Namespace
local Identity, People = ns.Identity, ns.People

-- Who my record goes to and through which channel, the GUIDs the game gives for the players I share with, and the
-- relationships kept on confirmed characters (guild, friendOf, whisperedAt).

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

---@class WhosWho.Whisper
---@field guid string
---@field sentAt number? seconds, from time(): my last whisper to that player this session, nil while I only received

---@type table<string, WhosWho.Whisper> whole name -> players whispered with this session (sent or received)
local whispers = {}

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

-- The units of the other members of my group (in a raid, mine too).
local function groupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[i] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[i] = "party" .. i end
    end
    return units
end

-- Another member of my group, from the group units; stops at the name.
local function groupMemberGuid(name)
    for _, unit in ipairs(groupUnits()) do
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
    if distribution == "WHISPER" then return friendGuid(name) or (whispers[name] and whispers[name].guid) end
    return nil
end

---The characters the game shows me online now: guild members from the roster, friends and group members.
---@return table<string, true> by GUID
function Scopes.OnlineGuids()
    local guids = {}
    for i = 1, GetNumGuildMembers() do
        local online, guid = select(9, GetGuildRosterInfo(i)), select(17, GetGuildRosterInfo(i))
        if online and guid and notSecret(online, guid) then guids[guid] = true end
    end
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected and info.guid and notSecret(info.connected, info.guid) then guids[info.guid] = true end
    end
    for _, unit in ipairs(groupUnits()) do
        local online, guid = UnitIsConnected(unit), UnitGUID(unit)
        if online and guid and notSecret(online, guid) then guids[guid] = true end
    end
    return guids
end

---A whisper received (CHAT_MSG_WHISPER: arguments 2 and 12): the sender's GUID, for confirmations only.
---@param name any
---@param guid any
function Scopes.WhisperReceived(name, guid)
    if not (name and guid and notSecret(name, guid)) then return end
    -- An answer keeps my whisper to that character.
    if whispers[name] and whispers[name].guid == guid then return end
    whispers[name] = { guid = guid }
end

---A whisper sent (CHAT_MSG_WHISPER_INFORM: arguments 2 and 12): the receiver's GUID, and the Whispers scope.
---@param name any
---@param guid any
function Scopes.WhisperSent(name, guid)
    if not (name and guid and notSecret(name, guid)) then return end
    local now = time()
    whispers[name] = { guid = guid, sentAt = now }
    People.SetWhisperedAt(guid, now)
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

---After a record is stored: whisperedAt of the characters I whispered this session that I now hold.
function Scopes.KeepSentWhispers()
    for _, whisper in pairs(whispers) do
        if whisper.sentAt then People.SetWhisperedAt(whisper.guid, whisper.sentAt) end
    end
end

-- Sharing ----------------------------------------------------------------------------------------

---Turns a scope on or off (settings and /ww scope).
---@param key "guild"|"friends"|"whispers"|"group"
---@param enabled boolean
function Scopes.Set(key, enabled)
    if ns.settings.scopes[key] == enabled then return end
    ns.settings.scopes[key] = enabled
    if key == "guild" then Identity.GuildScopeChanged() end
end

---Whether my scopes allow sharing identities with that player, both ways: sending my record, and using or asking
---for theirs.
---@param name string "First Surname"
---@return boolean
function Scopes.Allows(name)
    local scopes = ns.settings.scopes
    if scopes.guild and C_GuildInfo.MemberExistsByName(name) then return true end
    if scopes.friends and C_FriendList.GetFriendInfo(name) then return true end
    if scopes.group and groupMemberGuid(name) then return true end
    if scopes.whispers and whispers[name] and whispers[name].sentAt then return true end

    -- An alt of a player my scopes allow: one of the person's confirmed characters has a guild one of my characters is
    -- in (Guild scope), is the WoW friend of one of my characters (Friends scope), or was whispered by one of my
    -- characters (Whispers scope).
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    local person = ruleset and People.FindConfirmedByName(name, ruleset)
    if not person then return false end

    for _, character in pairs(person.chars) do
        if character.state == "confirmed" then
            if scopes.guild and character.guild and Identity.HasCharacterInGuild(character.guild, character.ruleset) then
                return true
            end
            if scopes.friends and character.friendOf then return true end
            if scopes.whispers and character.whisperedAt then return true end
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
---each online friend or player I whispered this session that no member channel reaches.
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
        for name, whisper in pairs(whispers) do
            if whisper.sentAt then add(name) end
        end
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
