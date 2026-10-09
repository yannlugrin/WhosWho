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

---A whisper with another character, saved in ns.data.whispers by its GUID.
---@class WhosWho.Whisper
---@field name string
---@field ruleset integer Record.RULESET, the same as my character's: whispers never cross rulesets
---@field sentAt number? seconds, from time(): when one of my characters last whispered it
---@field receivedAt number? seconds, from time(): when one of my characters last received a whisper from it

-- The whisper window, in seconds. On PLAYER_LOGOUT, AceDB may already have removed the values equal to their defaults.
local function whisperWindow()
    return (ns.settings.whisperHours or ns.Store.DEFAULTS.profile.whisperHours) * 3600
end

-- Whether a whisper at that time still counts.
---@param at number?
local function withinWhisperWindow(at)
    return at ~= nil and time() - at < whisperWindow()
end

-- The saved whisper with that player on the ruleset I play.
---@return string? guid
---@return WhosWho.Whisper? whisper
local function findWhisper(name)
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    for guid, whisper in pairs(ns.data.whispers) do
        if whisper.name == name and whisper.ruleset == ruleset then return guid, whisper end
    end
    return nil, nil
end

---@class WhosWho.Friend
---@field guid string
---@field name string
---@field connected boolean

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

---My WoW friends. Empty on PLAYER_LOGOUT: the friend list is already cleared.
---@return WhosWho.Friend[]
function Scopes.Friends()
    local friends = {}
    for i = 1, C_FriendList.GetNumFriends() or 0 do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.guid and info.name and notSecret(info.guid, info.name, info.connected) then
            friends[#friends + 1] = { guid = info.guid, name = info.name, connected = info.connected == true }
        end
    end
    return friends
end

local function friendGuid(name)
    local info = C_FriendList.GetFriendInfo(name)
    local guid = info and info.guid
    return guid and notSecret(guid) and guid or nil
end

---The GUID of an add-on message's sender, from the one source its channel names: the guild roster for GUILD, the
---group units for PARTY and RAID, my friend list or the saved whispers within the whisper window for WHISPER. Names
---match exactly.
---@param name string "First Surname", as the add-on message gives it
---@param distribution string the channel the message came on
---@return string? guid
function Scopes.SenderGuid(name, distribution)
    if distribution == "GUILD" then return guildMemberGuid(name) end
    if distribution == "PARTY" or distribution == "RAID" then return groupMemberGuid(name) end
    if distribution == "WHISPER" then
        local guid, whisper = findWhisper(name)
        local whispered = whisper and (withinWhisperWindow(whisper.sentAt) or withinWhisperWindow(whisper.receivedAt))
        return friendGuid(name) or (whispered and guid or nil)
    end
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
    for _, friend in ipairs(Scopes.Friends()) do
        if friend.connected then guids[friend.guid] = true end
    end
    for _, unit in ipairs(groupUnits()) do
        local online, guid = UnitIsConnected(unit), UnitGUID(unit)
        if online and guid and notSecret(online, guid) then guids[guid] = true end
    end
    return guids
end

-- The saved whisper with that character, created when missing. A name names one character per ruleset: a whisper
-- saved under that name for another GUID (a character renamed or deleted) is removed.
---@return WhosWho.Whisper
local function saveWhisper(name, guid)
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    local whispers = ns.data.whispers
    for otherGuid, whisper in pairs(whispers) do
        if otherGuid ~= guid and whisper.name == name and whisper.ruleset == ruleset then whispers[otherGuid] = nil end
    end
    local whisper = whispers[guid] or {}
    whisper.name, whisper.ruleset = name, ruleset
    whispers[guid] = whisper
    return whisper
end

---A whisper received (CHAT_MSG_WHISPER: arguments 2 and 12): the sender's GUID, for confirmations only.
---@param name any
---@param guid any
function Scopes.WhisperReceived(name, guid)
    if not (name and guid and notSecret(name, guid)) then return end
    saveWhisper(name, guid).receivedAt = time()
end

---A whisper sent (CHAT_MSG_WHISPER_INFORM: arguments 2 and 12): the receiver's GUID, and the Whispers scope.
---@param name any
---@param guid any
function Scopes.WhisperSent(name, guid)
    if not (name and guid and notSecret(name, guid)) then return end
    local now = time()
    saveWhisper(name, guid).sentAt = now
    People.SetWhisperedAt(guid, now)
end

---PLAYER_LOGOUT: removes the whispers neither sent nor received within the whisper window, and clears the older
---whisperedAt.
function Scopes.ForgetOldWhispers()
    local whispers = ns.data.whispers
    for guid, whisper in pairs(whispers) do
        if not withinWhisperWindow(whisper.sentAt) and not withinWhisperWindow(whisper.receivedAt) then
            whispers[guid] = nil
        end
    end
    People.ClearWhisperedBefore(time() - whisperWindow())
end

-- Relationships ----------------------------------------------------------------------------------

---GUILD_ROSTER_UPDATE: my current character's guild, and the guild of the characters I hold.
function Scopes.GuildRosterChanged()
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
function Scopes.FriendListChanged()
    local friendGuids = {}
    for _, friend in ipairs(Scopes.Friends()) do friendGuids[friend.guid] = true end
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

---After a record is stored: whisperedAt of the characters I whispered that I now hold.
function Scopes.KeepSentWhispers()
    for guid, whisper in pairs(ns.data.whispers) do
        if whisper.sentAt then People.SetWhisperedAt(guid, whisper.sentAt) end
    end
end

-- Sharing ----------------------------------------------------------------------------------------

---@type fun(key: "guild"|"friends"|"whispers"|"group")[]
local enabledListeners = {}

---Whether that scope is on. On PLAYER_LOGOUT, AceDB may already have removed the values equal to their defaults.
---@param key "guild"|"friends"|"whispers"|"group"
---@return boolean
function Scopes.Get(key)
    local scopes = ns.settings.scopes
    local enabled = scopes and scopes[key]
    if enabled == nil then return ns.Store.DEFAULTS.profile.scopes[key] end
    return enabled
end

---Turns a scope on or off (settings and /ww scope).
---@param key "guild"|"friends"|"whispers"|"group"
---@param enabled boolean
function Scopes.Set(key, enabled)
    if Scopes.Get(key) == enabled then return end
    ns.settings.scopes[key] = enabled
    if key == "guild" then Identity.GuildScopeChanged() end
    if not enabled then return end
    for _, listener in ipairs(enabledListeners) do listener(key) end
end

---Calls the listener with the scope's key each time a scope is turned on.
---@param listener fun(key: "guild"|"friends"|"whispers"|"group")
function Scopes.OnEnabled(listener)
    enabledListeners[#enabledListeners + 1] = listener
end

---Whether my scopes allow sharing identities with that player, both ways: sending my record, and using or asking
---for theirs.
---@param name string "First Surname"
---@return boolean
function Scopes.Allows(name)
    local guild, friends = Scopes.Get("guild"), Scopes.Get("friends")
    local whispersOn = Scopes.Get("whispers")
    if guild and C_GuildInfo.MemberExistsByName(name) then return true end
    if friends and C_FriendList.GetFriendInfo(name) then return true end
    if Scopes.Get("group") and groupMemberGuid(name) then return true end
    if whispersOn then
        local _, whisper = findWhisper(name)
        if whisper and withinWhisperWindow(whisper.sentAt) then return true end
    end

    -- An alt of a player my scopes allow: one of the person's confirmed characters has a guild one of my characters is
    -- in (Guild scope), is the WoW friend of one of my characters (Friends scope), or was whispered by one of my
    -- characters within the whisper window (Whispers scope).
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    local person = ruleset and People.FindConfirmedByName(name, ruleset)
    if not person then return false end

    for _, character in pairs(person.chars) do
        if character.state == "confirmed" then
            if guild and character.guild and Identity.HasCharacterInGuild(character.guild, character.ruleset) then
                return true
            end
            if friends and character.friendOf then return true end
            if whispersOn and withinWhisperWindow(character.whisperedAt) then return true end
        end
    end

    return false
end

---My group's channel: RAID in a raid, PARTY otherwise.
---@return WhosWho.Channel
function Scopes.GroupChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

---Whether one of my linked characters is in my current character's guild, in its ruleset: an anonymous character may
---store a new identity from that guild.
---@return boolean
function Scopes.LinkedCharacterInGuild()
    local clubId = IsInGuild() and C_Club.GetGuildClubId()
    if not clubId then return false end
    return Identity.HasLinkedCharacterInGuild(clubId, Identity.Ruleset(UnitGUID("player")))
end

---Whether that player is in my guild and the Guild scope is on: the GUILD channel reaches it.
---@param name string
---@return boolean
function Scopes.GuildReaches(name)
    return Scopes.Get("guild") and C_GuildInfo.MemberExistsByName(name)
end

---Whether that player is my WoW friend and the Friends scope is on: my announcements to my friends reach it.
---@param name string
---@return boolean
function Scopes.FriendReaches(name)
    return Scopes.Get("friends") and friendGuid(name) ~= nil
end

---Whether that player is in my group and the Group scope is on: the group channel reaches it.
---@param name string
---@return boolean
function Scopes.GroupReaches(name)
    return Scopes.Get("group") and groupMemberGuid(name) ~= nil
end

-- One character for each shared person the character I play whispered since its login, within the whisper window: the
-- confirmed character I last whispered with, sent or received, the one they most likely play. A person my guild, group
-- or friends announcements reach is left out.
---@return string[] names
local function whisperedPeople()
    local guid = UnitGUID("player")
    local loggedInAt, ruleset = Identity.LoggedInAt(guid), Identity.Ruleset(guid)
    if not (Scopes.Get("whispers") and loggedInAt) then return {} end

    local whisperedSinceLogin, lastCharacter = {}, {}
    for otherGuid, whisper in pairs(ns.data.whispers) do
        local person, character = People.Find(otherGuid)
        if person and character.state == "confirmed" and whisper.ruleset == ruleset then
            local sentAt = whisper.sentAt
            if sentAt and sentAt >= loggedInAt and withinWhisperWindow(sentAt) then whisperedSinceLogin[person.id] = true end
            local at = math.max(sentAt or 0, whisper.receivedAt or 0)
            local last = lastCharacter[person.id]
            if not last or at > last.at then lastCharacter[person.id] = { name = whisper.name, at = at } end
        end
    end

    local names = {}
    for id in pairs(whisperedSinceLogin) do
        local name = lastCharacter[id].name
        if not (Scopes.GuildReaches(name) or Scopes.GroupReaches(name) or Scopes.FriendReaches(name)) then
            names[#names + 1] = name
        end
    end
    return names
end

---Every player my login announcement reaches, each once: the member channels (GUILD, PARTY or RAID), then one message
---to each online friend that no member channel reaches.
---@return WhosWho.Audience
function Scopes.LoginAudience()
    local memberChannels, names = {}, {}

    if Scopes.Get("guild") and IsInGuild() then memberChannels[#memberChannels + 1] = "GUILD" end
    if Scopes.Get("group") and IsInGroup() then memberChannels[#memberChannels + 1] = Scopes.GroupChannel() end

    if Scopes.Get("friends") then
        for _, friend in ipairs(Scopes.Friends()) do
            if friend.connected and not Scopes.GuildReaches(friend.name) and not Scopes.GroupReaches(friend.name) then
                names[#names + 1] = friend.name
            end
        end
    end

    return { memberChannels = memberChannels, names = names }
end

---Every player my other broadcasts reach, each once: the login audience, then one message to each person I whispered
---this session that no other way reaches.
---@return WhosWho.Audience
function Scopes.BroadcastAudience()
    local audience = Scopes.LoginAudience()
    for _, name in ipairs(whisperedPeople()) do audience.names[#audience.names + 1] = name end
    return audience
end
