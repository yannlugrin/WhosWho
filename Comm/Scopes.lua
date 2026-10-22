local _, ns = ...
---@cast ns WhosWho.Namespace
local GuildList, GuildRecord, GuildSettings, Identity, People = ns.GuildList, ns.GuildRecord, ns.GuildSettings, ns.Identity, ns.People

-- Who my record goes to and through which channel, the GUIDs the game gives for the players I share with, and the
-- relationships kept on confirmed characters (guild, friendOf, whisperedAt).

---@class WhosWho.Scopes
local Scopes = {}
ns.Scopes = Scopes

local issecretvalue = issecretvalue or function() return false end

---@alias WhosWho.Channel "GUILD"|"PARTY"|"RAID"|"WHISPER"

-- Sources ----------------------------------------------------------------------------------------

---Whether no value read from the game is secret. A secret value (Midnight-era API) may only be displayed: never
---compared, stored or used as a key.
local function notSecret(...)
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return false end
    end
    return true
end

-- Senders of a message on GUILD that my roster did not list then, by name, until it does: the game delivers GUILD
-- messages only from members of my guild. Emptied when my guild changes.
---@type table<string, true>
local unlistedGuildSenders = {}

-- Whether that player is a member of my current guild: in my roster, or a sender on GUILD it does not list yet. Until
-- the roster loads (at login), a confirmed character of that name last seen in my current character's guild.
local function guildMember(name)
    if C_GuildInfo.MemberExistsByName(name) or unlistedGuildSenders[name] then return true end
    if GetNumGuildMembers() > 0 or not IsInGuild() then return false end

    local ownCharacterGuid = UnitGUID("player")
    local clubId, ruleset = Identity.GuildId(ownCharacterGuid), Identity.Ruleset(ownCharacterGuid)
    local person = clubId and ruleset and People.FindConfirmedByName(name, ruleset)
    if not person then return false end
    for _, character in pairs(person.chars) do
        if character.state == "confirmed" and character.name == name and character.ruleset == ruleset then
            return character.guild == clubId
        end
    end
    return false
end

-- Whether I share with a guild one of my characters is in: with the Guild scope; one enforcing linking, only once my
-- identity is complete there, whatever my Guild scope.
local function sharesWith(clubId, ruleset)
    if GuildSettings.EnforcesLinking(clubId) then return Identity.CompleteInGuild(clubId, ruleset) end
    return Scopes.Get("guild")
end

---My current guild, when it enforces linking and my identity is complete there: I opted in, or all my characters in it
---are linked with my Guild scope on. I share with it whatever my Guild scope.
---@return integer? clubId
---@return WhosWho.Ruleset? ruleset
function Scopes.EnforcedGuild()
    local guid = UnitGUID("player")
    local clubId, ruleset = IsInGuild() and Identity.GuildId(guid), Identity.Ruleset(guid)
    if not (clubId and GuildSettings.EnforcesLinking(clubId) and Identity.CompleteInGuild(clubId, ruleset)) then
        return nil, nil
    end
    return clubId, ruleset
end

---My current guild, when it enforces linking, my identity isn't complete there and I haven't answered it yet: the
---character I play must be asked.
---@return integer? clubId
function Scopes.EnforcedLinkingChoiceNeeded()
    local clubId = IsInGuild() and Identity.GuildId(UnitGUID("player"))
    if not (clubId and GuildSettings.EnforcesLinking(clubId)) then return nil end
    if Scopes.EnforcedGuild() or Identity.EnforcedLinkingOptIn(clubId) ~= nil then return nil end
    return clubId
end

---My answer to my current guild's rule, nil while it doesn't enforce linking: accepted (my identity is complete there),
---refused, or not answered yet.
---@return "accepted"|"refused"|"unanswered"?
function Scopes.GuildRuleAnswer()
    local clubId = IsInGuild() and Identity.GuildId(UnitGUID("player"))
    if not (clubId and GuildSettings.EnforcesLinking(clubId)) then return nil end
    if Scopes.EnforcedGuild() then return "accepted" end
    return Identity.EnforcedLinkingOptIn(clubId) == false and "refused" or "unanswered"
end

-- Whether the character I play shares with my guild only: one I didn't link, which my guild's rule adds.
local function guildOnly()
    return not Identity.IsLinked(UnitGUID("player")) and Scopes.EnforcedGuild() ~= nil
end

---Whether I share with my current guild: with the Guild scope; a guild enforcing linking, only once my identity is
---complete there, whatever my Guild scope. Right after joining, nothing until the game gives the guild's club ID, which
---tells whether its rule applies.
---@return boolean
function Scopes.SharesWithGuild()
    local guid = UnitGUID("player")
    if IsInGuild() and Identity.GuildIdPending(guid) then return false end
    local clubId = IsInGuild() and Identity.GuildId(guid)
    if not clubId then return Scopes.Get("guild") end
    return sharesWith(clubId, Identity.Ruleset(guid))
end

-- Sets my current character's guild (apply). When the guild's members get a record of their own and it changes, a new
-- revision; a guild left needs none, its members forget the characters it added once their roster drops them.
local function setOwnGuild(clubId, apply)
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    local general = Scopes.Get("guild")
    local bytes = Identity.HasGuildContent(clubId) and Identity.RecordBytesWithoutRevision(general, clubId, ruleset)
    apply()
    if bytes and Identity.RecordBytesWithoutRevision(general, clubId, ruleset) ~= bytes then
        Identity.GuildContentChanged()
    end
end

---Whether that player is a member of my current guild, whatever I share with it: for the guild's settings.
---@param name string
---@return boolean
function Scopes.GuildMember(name)
    return guildMember(name)
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

---A message from that player came on GUILD, so it is a member of my guild, even when my roster does not list it yet.
---@param name string
---@return boolean listed whether my roster lists that player
function Scopes.ReceivedOnGuild(name)
    if C_GuildInfo.MemberExistsByName(name) then return true end
    unlistedGuildSenders[name] = true
    return false
end

---The rank index of that character in my roster, 0 for the guild master.
---@param guid string
---@return integer? rankIndex nil when my roster does not list it
function Scopes.GuildRankIndex(guid)
    for i = 1, GetNumGuildMembers() do
        local _, _, rankIndex = GetGuildRosterInfo(i)
        local memberGuid = select(17, GetGuildRosterInfo(i))
        if memberGuid and notSecret(memberGuid, rankIndex) and memberGuid == guid then return rankIndex end
    end
    return nil
end

-- The member who invited the character I play into a guild, this session.
local guildInviter

---GUILD_INVITE_REQUEST: who invites the character I play into a guild.
---@param inviter any
function Scopes.GuildInviteReceived(inviter)
    if inviter and notSecret(inviter) then guildInviter = inviter end
end

---Whether that member of my guild is trusted for its first settings: an officer (or the guild master) in my roster, or
---the member who invited me.
---@param name string
---@return boolean
function Scopes.TrustedForGuildSettings(name)
    if name == guildInviter then return true end
    local guid = guildMemberGuid(name)
    local rankIndex = guid and Scopes.GuildRankIndex(guid)
    return rankIndex ~= nil and rankIndex <= GuildSettings.LOWEST_RANK_INDEX
end

---The online members of my guild but me, from the roster: the member who invited me first, then by rank (the guild
---master first), then by name. The members trusted for the guild's first settings get my messages first.
---@return string[] names
function Scopes.OnlineGuildMembers()
    local names, rankIndexByName, ownName = {}, {}, ns.UnitWholeName("player")
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and notSecret(name, rankIndex, online) and online and name ~= ownName then
            names[#names + 1], rankIndexByName[name] = name, rankIndex
        end
    end
    table.sort(names, function(a, b)
        if (a == guildInviter) ~= (b == guildInviter) then return a == guildInviter end
        if rankIndexByName[a] ~= rankIndexByName[b] then return rankIndexByName[a] < rankIndexByName[b] end
        return a < b
    end)
    return names
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

---Whether that character is another member of my group.
---@param guid string
---@return boolean
function Scopes.InMyGroup(guid)
    for _, unit in ipairs(groupUnits()) do
        local unitGuid = UnitGUID(unit)
        if unitGuid and notSecret(unitGuid) and unitGuid == guid then return true end
    end
    return false
end

---@class WhosWho.Friend
---@field guid string
---@field name string
---@field connected boolean
---@field level integer? known while online

---My WoW friends. Empty on PLAYER_LOGOUT: the friend list is already cleared.
---@return WhosWho.Friend[]
function Scopes.Friends()
    local friends = {}
    for i = 1, C_FriendList.GetNumFriends() or 0 do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.guid and info.name and notSecret(info.guid, info.name, info.connected, info.level) then
            local connected = info.connected == true
            friends[#friends + 1] = {
                guid = info.guid, name = info.name, connected = connected, level = connected and info.level or nil,
            }
        end
    end
    return friends
end

-- A Battle.net friend's character is addressed by a key of its own, "BN:<game account ID>", valid for the session: its
-- name alone could be another character's on my ruleset.
local BNET_KEY_PREFIX = "BN:"

---A Battle.net friend playing my game (Forever) now, with the character the game gives for them.
---@class WhosWho.BnetFriend
---@field key string "BN:<game account ID>": how messages address them, in place of a name
---@field gameAccountID integer
---@field name string the character's
---@field guid string the character's

---My Battle.net friends playing Forever now. Empty while Battle.net is disconnected.
---@return WhosWho.BnetFriend[]
function Scopes.BnetFriends()
    local friends = {}
    if not BNConnected() then return friends end
    for i = 1, BNGetNumFriends() do
        local account = C_BattleNet.GetFriendAccountInfo(i)
        local game = account and account.gameAccountInfo
        local id, name, guid = game and game.gameAccountID, game and game.characterName, game and game.playerGuid
        if id and name and guid and notSecret(id, name, guid, game.isOnline, game.clientProgram, game.wowProjectID)
            and game.isOnline and game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID then
            friends[#friends + 1] = { key = BNET_KEY_PREFIX .. id, gameAccountID = id, name = name, guid = guid }
        end
    end

    return friends
end

-- The Battle.net friend a key addresses, playing Forever now; nil for a name, or a friend gone.
---@return WhosWho.BnetFriend?
local function bnetFriend(key)
    if type(key) ~= "string" or key:sub(1, #BNET_KEY_PREFIX) ~= BNET_KEY_PREFIX then return nil end
    for _, friend in ipairs(Scopes.BnetFriends()) do
        if friend.key == key then return friend end
    end
    return nil
end

---The game account a message to that player goes to over Battle.net: one of my Battle.net friends' keys; nil for a
---name.
---@param name string
---@return integer?
function Scopes.BnetGameAccount(name)
    local friend = bnetFriend(name)
    return friend and friend.gameAccountID
end

---The key a message from that game account comes from (BN_CHAT_MSG_ADDON): one of my Battle.net friends playing Forever;
---nil for another.
---@param gameAccountID integer
---@return string?
function Scopes.BnetSender(gameAccountID)
    for _, friend in ipairs(Scopes.BnetFriends()) do
        if friend.gameAccountID == gameAccountID then return friend.key end
    end
    return nil
end

---The name of the character that sent a message: the sender's name, or, for a Battle.net friend's key, their
---character's.
---@param sender string
---@return string
function Scopes.SenderName(sender)
    local friend = bnetFriend(sender)
    return friend and friend.name or sender
end

-- The GUID of a WoW friend, or of the character a Battle.net friend's key addresses.
local function friendGuid(name)
    local friend = bnetFriend(name)
    if friend then return friend.guid end
    local info = C_FriendList.GetFriendInfo(name)
    local guid = info and info.guid
    return guid and notSecret(guid) and guid or nil
end

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

-- Guild invite requests: a player whispers one of these words to an officer, or sends GINV (Protocol.AskGuildInvite), to
-- have the character invited into a guild where another character of their identity is. For a while after it, the two
-- share identities whatever their scopes, so the officer can check who asks.
local GUILD_INVITE_WORDS = { ginv = true, guildinv = true }
local GUILD_INVITE_SECONDS = 60
---@type table<string, number> by name: when I asked that player to invite me (GetTime())
local guildInvitesAsked = {}
---@type table<string, { guid: string, at: number }> by name: who asked me to invite them, with their character's GUID
---(given by the game for a whisper, by the player for GINV), when I may invite
local guildInviteRequests = {}
local guildInviteListeners = {}

local function isGuildInviteRequest(text)
    return type(text) == "string" and not issecretvalue(text) and GUILD_INVITE_WORDS[text:match("^%s*(.-)%s*$"):lower()]
        == true
end

-- Whether I asked that player to invite me, or that player asked me, within GUILD_INVITE_SECONDS.
local function inGuildInviteExchange(name)
    local asked, request = guildInvitesAsked[name], guildInviteRequests[name]
    return (asked ~= nil and GetTime() - asked < GUILD_INVITE_SECONDS)
        or (request ~= nil and GetTime() - request.at < GUILD_INVITE_SECONDS)
end

---A whisper received (CHAT_MSG_WHISPER: arguments 1, 2 and 12): the sender's GUID, for confirmations; a guild invite
---request when I may invite and my guild accepts them.
---@param name any
---@param guid any
---@param text any
function Scopes.WhisperReceived(name, guid, text)
    if not (name and guid and notSecret(name, guid)) then return end
    local now = time()
    saveWhisper(name, guid).receivedAt = now
    People.Activity({ [guid] = { lastSeen = now } })
    if isGuildInviteRequest(text) then Scopes.GuildInviteRequested(name, guid) end
end

---A whisper sent (CHAT_MSG_WHISPER_INFORM: arguments 1, 2 and 12): the receiver's GUID, and the Whispers scope; a guild
---invite request I sent.
---@param name any
---@param guid any
---@param text any
function Scopes.WhisperSent(name, guid, text)
    if not (name and guid and notSecret(name, guid)) then return end
    local now = time()
    saveWhisper(name, guid).sentAt = now
    People.SetWhisperedAt(guid, now)
    People.Activity({ [guid] = { lastSeen = now } })
    if isGuildInviteRequest(text) then Scopes.GuildInviteAsked(name) end
end

---A player asks me to invite their character into my guild: kept for GUILD_INVITE_SECONDS when I may invite and my
---guild accepts invite requests.
---@param name string
---@param guid string the character's
function Scopes.GuildInviteRequested(name, guid)
    if not (IsInGuild() and CanGuildInvite()
        and GuildSettings.AcceptsInviteRequests(Identity.GuildId(UnitGUID("player")))) then
        return
    end
    guildInviteRequests[name] = { guid = guid, at = GetTime() }
    for _, listener in ipairs(guildInviteListeners) do listener() end
end

---I ask that player to invite the character I play into their guild.
---@param name string
function Scopes.GuildInviteAsked(name)
    guildInvitesAsked[name] = GetTime()
end

---The GUID a player asking me for an invite gave with the request, within GUILD_INVITE_SECONDS; the game vouches for the
---name only.
---@param name string
---@return string? guid
function Scopes.GuildInviteGuid(name)
    local request = guildInviteRequests[name]
    return request and GetTime() - request.at < GUILD_INVITE_SECONDS and request.guid or nil
end

---Whether I asked that player to invite me into their guild, within GUILD_INVITE_SECONDS: my whisper sends my
---announcement whatever my Whispers scope.
---@param name string
---@return boolean
function Scopes.AskedGuildInvite(name)
    local asked = guildInvitesAsked[name]
    return asked ~= nil and GetTime() - asked < GUILD_INVITE_SECONDS
end

---The players who asked me to invite them, within GUILD_INVITE_SECONDS, with the character that asked.
---@return table<string, string> GUID by name
function Scopes.GuildInviteRequests()
    local requests = {}
    for name, request in pairs(guildInviteRequests) do
        if GetTime() - request.at < GUILD_INVITE_SECONDS then requests[name] = request.guid end
    end
    return requests
end

---Calls the listener each time a player asks me to invite them.
---@param listener fun()
function Scopes.OnGuildInviteRequested(listener)
    guildInviteListeners[#guildInviteListeners + 1] = listener
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

---Clears the whisper history: the saved whispers, and when I last whispered each character I hold.
function Scopes.ForgetWhispers()
    ns.data.whispers = {}
    People.ClearWhisperedBefore(math.huge)
end

---The GUID of an add-on message's sender, whatever channel it came on, from what that player is to me: the guild
---roster, the group units, my friend list (a Battle.net friend's key: their character), then the saved whispers within
---the whisper window. Names match exactly.
---@param name string "First Surname", as the add-on message gives it
---@return string? guid
function Scopes.SenderGuid(name)
    local guid, whisper = findWhisper(name)
    local whispered = whisper and (withinWhisperWindow(whisper.sentAt) or withinWhisperWindow(whisper.receivedAt))
    return guildMemberGuid(name) or groupMemberGuid(name) or friendGuid(name) or (whispered and guid or nil)
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

-- Relationships ----------------------------------------------------------------------------------

-- Right after joining, the game may send the roster before my guild's club ID: the roster is asked for again, that long
-- after, until it comes with it.
local CLUB_ID_RETRY_SECONDS = 10
local clubIdRetryPending = false

---@type table<string, true>? the GUIDs the last roster the game loaded listed, to tell when its members change
local listedGuids
---@type fun()[]
local guildMembersListeners = {}

-- Whether two sets of GUIDs hold the same ones.
local function sameGuids(a, b)
    for guid in pairs(a) do if not b[guid] then return false end end
    for guid in pairs(b) do if not a[guid] then return false end end
    return true
end

---GUILD_ROSTER_UPDATE: my current character's guild, the guild of the characters I hold, and their activity: seen now
---while online; offline, its level only.
function Scopes.GuildRosterChanged()
    local count = GetNumGuildMembers()
    local clubId = C_Club.GetGuildClubId()
    if count > 0 and not clubId and not clubIdRetryPending then
        clubIdRetryPending = true
        C_Timer.After(CLUB_ID_RETRY_SECONDS, function()
            clubIdRetryPending = false
            if IsInGuild() then C_GuildInfo.GuildRoster() end
        end)
    end
    -- The roster is empty until the game has loaded it.
    if count == 0 or not clubId then return end

    local memberGuids, rankIndexes, activities, now = {}, {}, {}, time()
    for i = 1, count do
        local _, _, rankIndex, level, _, _, _, _, online = GetGuildRosterInfo(i)
        local guid = select(17, GetGuildRosterInfo(i))
        if guid and notSecret(guid, rankIndex, level, online) then
            memberGuids[guid], rankIndexes[guid] = true, rankIndex
            activities[guid] = { level = level, lastSeen = online and now or nil }
        end
    end

    for name in pairs(unlistedGuildSenders) do
        if C_GuildInfo.MemberExistsByName(name) then unlistedGuildSenders[name] = nil end
    end
    local joined = Identity.GuildId(UnitGUID("player")) ~= clubId
    setOwnGuild(clubId, function() Identity.SetGuild(UnitGUID("player"), clubId, (GetGuildInfo("player"))) end)
    People.SetCurrentGuild(clubId)
    People.UpdateGuildMembers(clubId, memberGuids, rankIndexes)
    -- What I held of a guild I joined again dates from before: its settings count as first ones, my list as a first one.
    if joined then
        GuildSettings.Joined(clubId)
        GuildList.ForgetGuild(clubId)
    end
    -- A character joining a guild whose rule I refused: the rule is asked again.
    if joined and Identity.JoinedGuildSinceLogin(UnitGUID("player"))
        and Identity.EnforcedLinkingOptIn(clubId) == false then
        Identity.SetEnforcedLinkingOptIn(clubId, nil)
    end
    if joined and GuildSettings.EnforcesLinking(clubId) then People.MarkOutdated(clubId) end
    People.Activity(activities)

    local membersChanged = not (listedGuids and sameGuids(listedGuids, memberGuids))
    listedGuids = memberGuids
    if membersChanged then
        for _, listener in ipairs(guildMembersListeners) do listener() end
    end
end

---My current guild's members, from the roster; nil until the game has loaded it, or for another guild.
---@param clubId integer
---@return table<string, true>? by GUID
function Scopes.GuildMemberGuids(clubId)
    local count = GetNumGuildMembers()
    if count == 0 or C_Club.GetGuildClubId() ~= clubId then return nil end
    local guids = {}
    for i = 1, count do
        local guid = select(17, GetGuildRosterInfo(i))
        if guid and notSecret(guid) then guids[guid] = true end
    end
    return guids
end

---Calls the listener each time the roster the game loads lists other members than the last one: the first one, a
---member joining or leaving.
---@param listener fun()
function Scopes.OnGuildMembersChanged(listener)
    guildMembersListeners[#guildMembersListeners + 1] = listener
end

---PLAYER_GUILD_UPDATE for my character: a guild left, or joined (its roster follows). Also at login, for a guild left
---while offline. What I hold of a guild I left goes once none of my characters is in it.
function Scopes.GuildChanged()
    unlistedGuildSenders = {}
    listedGuids = nil
    if IsInGuild() then
        C_GuildInfo.GuildRoster()
        return
    end
    local guid = UnitGUID("player")
    local clubId = Identity.GuildId(guid)
    Identity.SetGuild(guid, nil)
    People.SetCurrentGuild(nil)
    if clubId and not Identity.HasCharacterInGuild(clubId, Identity.Ruleset(guid)) then
        People.GuildLeft(clubId)
        GuildRecord.ForgetGuild(clubId)
        Identity.SetEnforcedLinkingOptIn(clubId, nil)
        GuildList.ForgetGuild(clubId)
    end
end

---After a record is stored: the guild, rank and level of its characters my roster lists, as an announcement from them
---would have set them had it come before the record; not a last seen time, the record says nothing of when I saw them.
---@param signedRecord WhosWho.SignedIdentityRecord
function Scopes.KeepGuildMembers(signedRecord)
    local clubId = IsInGuild() and C_Club.GetGuildClubId()
    if not clubId then return end
    local activities = {}
    for i = 1, GetNumGuildMembers() do
        local _, _, rankIndex, level = GetGuildRosterInfo(i)
        local guid = select(17, GetGuildRosterInfo(i))
        if guid and notSecret(guid, rankIndex, level) and signedRecord.chars[guid] then
            People.SetGuild(guid, clubId, rankIndex)
            activities[guid] = { level = level }
        end
    end
    People.Activity(activities)
end

---The characters of a record that my current guild's roster lists.
---@param signedRecord WhosWho.SignedIdentityRecord
---@return table<string, true> by GUID
function Scopes.GuildMembersIn(signedRecord)
    local guids = {}
    for i = 1, GetNumGuildMembers() do
        local guid = select(17, GetGuildRosterInfo(i))
        if guid and notSecret(guid) and signedRecord.chars[guid] then guids[guid] = true end
    end
    return guids
end

---GROUP_ROSTER_UPDATE: the activity of the members connected.
function Scopes.GroupRosterChanged()
    local activities, now = {}, time()
    for _, unit in ipairs(groupUnits()) do
        local guid, connected, level = UnitGUID(unit), UnitIsConnected(unit), UnitLevel(unit)
        if guid and connected and notSecret(guid, connected, level) then
            activities[guid] = { level = level, lastSeen = now }
        end
    end
    People.Activity(activities)
end

---FRIENDLIST_UPDATE: friendOf of the characters I hold, for my current character, and the activity of the ones
---online.
function Scopes.FriendListChanged()
    local friendGuids, activities, now = {}, {}, time()
    for _, friend in ipairs(Scopes.Friends()) do
        friendGuids[friend.guid] = true
        if friend.connected then activities[friend.guid] = { level = friend.level, lastSeen = now } end
    end
    People.UpdateFriends(UnitGUID("player"), friendGuids)
    People.Activity(activities)
end

---BN_FRIEND_LIST_SIZE_CHANGED, BN_FRIEND_INFO_CHANGED: bnetFriend of the characters I hold, from my Battle.net
---friends: the character each one plays in WoW, and the BattleTags of all of them.
function Scopes.BnetFriendListChanged()
    local count = BNConnected() and BNGetNumFriends() or 0
    -- The list is empty while Battle.net is disconnected or until the game has loaded it.
    if count == 0 then return end

    local characterTags, battleTags = {}, {}
    for i = 1, count do
        local account = C_BattleNet.GetFriendAccountInfo(i)
        local battleTag = account and account.battleTag
        if battleTag and notSecret(battleTag) then
            battleTags[battleTag] = true
            local game = account.gameAccountInfo
            local guid = game and game.clientProgram == BNET_CLIENT_WOW and game.playerGuid
            if guid and notSecret(guid) then characterTags[guid] = battleTag end
        end
    end
    People.UpdateBnetFriends(characterTags, battleTags)
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
    if key == "guild" and not enabled then Identity.KeepGuildRulesAccepted() end
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

-- Whether my scopes allow sharing with that player; withoutGuildRule: not counting a guild enforcing linking, which I
-- share with whatever my Guild scope.
local function allows(name, withoutGuildRule)
    local friends = Scopes.Get("friends")
    local whispersOn = Scopes.Get("whispers")
    local guildOn = Scopes.Get("guild") or not withoutGuildRule
    if guildOn and Scopes.SharesWithGuild() and guildMember(name) then return true end
    if inGuildInviteExchange(name) then return true end
    if friends and (C_FriendList.GetFriendInfo(name) or bnetFriend(name)) then return true end
    if Scopes.Get("group") and groupMemberGuid(name) then return true end
    if whispersOn then
        local _, whisper = findWhisper(name)
        if whisper and withinWhisperWindow(whisper.sentAt) then return true end
    end

    -- An alt of a player my scopes allow: one of the person's confirmed characters has a guild one of my characters is
    -- in, which I share with (Guild scope, its rule), is the WoW friend of one of my characters (Friends scope), or was whispered by one of my
    -- characters within the whisper window (Whispers scope).
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    local person = ruleset and People.FindConfirmedByName(name, ruleset)
    if not person then return false end

    for _, character in pairs(person.chars) do
        if character.state == "confirmed" then
            if guildOn and character.guild and Identity.HasCharacterInGuild(character.guild, character.ruleset)
                and sharesWith(character.guild, character.ruleset) then
                return true
            end
            if friends and character.friendOf then return true end
            if whispersOn and withinWhisperWindow(character.whisperedAt) then return true end
        end
    end

    return false
end

---Whether my scopes allow sharing identities with that player, both ways: sending my record, and using or asking
---for theirs.
---@param name string "First Surname"
---@return boolean
function Scopes.Allows(name)
    return allows(name, false)
end

---Whether my announcement, from the character I play, goes to that player: one my scopes allow; only my guild's members
---from a character my guild's rule adds.
---@param name string
---@return boolean
function Scopes.AnnouncementReaches(name)
    return Scopes.Allows(name) and (not guildOnly() or Scopes.GuildReaches(name))
end

---Whether my announcements, from the character I play, go to my guild: I share with it, and the character announces.
---@return boolean
function Scopes.AnnouncesToGuild()
    return IsInGuild() and Scopes.SharesWithGuild() and Identity.AnnouncedRevision(UnitGUID("player")) ~= nil
end

---Whether my announcements, from the character I play, go to my group: with the Group scope, from a character that
---shares beyond my guild.
---@return boolean
function Scopes.AnnouncesToGroup()
    return Scopes.Get("group") and not guildOnly()
end

---Whether my record, from the character I play, goes to that player: one my scopes allow, from a linked character; only
---my guild's members from a character my guild's rule adds.
---@param name string
---@return boolean
function Scopes.RecordReaches(name)
    if not Scopes.Allows(name) then return false end
    return Identity.IsLinked(UnitGUID("player")) or (guildOnly() and Scopes.GuildReaches(name))
end

---My current guild, when its members get a record of their own from me: it enforces linking and my identity is
---complete there (Scopes.EnforcedGuild), or I chose my main or my nickname in it (Identity.HasGuildContent).
---@return integer? clubId
---@return WhosWho.Ruleset? ruleset
function Scopes.GuildContent()
    local clubId, ruleset = Scopes.EnforcedGuild()
    if clubId then return clubId, ruleset end
    local guid = UnitGUID("player")
    clubId = IsInGuild() and Identity.GuildId(guid)
    if not (clubId and not GuildSettings.EnforcesLinking(clubId) and Identity.HasGuildContent(clubId)) then
        return nil, nil
    end
    return clubId, Identity.Ruleset(guid)
end

---What my record holds for that player, from the character I play: the general part when the character is linked and a
---scope other than a guild's rule allows the player; my current guild's entry when its members get one of their own
---(Scopes.GuildContent) and the player is one of them.
---@param name string
---@return boolean general
---@return integer? clubId
---@return WhosWho.Ruleset? ruleset
function Scopes.RecordContentOf(name)
    local general = Identity.IsLinked(UnitGUID("player")) and allows(name, true)
    local clubId, ruleset = Scopes.GuildContent()
    if clubId and Scopes.GuildReaches(name) then return general, clubId, ruleset end
    return general, nil, nil
end

---What my record holds for my guild's members, as most of them get it: the general part with my Guild scope on, and
---the guild's entry when they get one of their own.
---@return boolean general
---@return integer? clubId
---@return WhosWho.Ruleset? ruleset
function Scopes.GuildMembersContent()
    return Scopes.Get("guild") and Identity.IsLinked(UnitGUID("player")), Scopes.GuildContent()
end

---Whether that player is in my guild and I share with it: the GUILD channel reaches it.
---@param name string
---@return boolean
function Scopes.GuildReaches(name)
    return Scopes.SharesWithGuild() and guildMember(name)
end

---Whether one of my linked characters is in my current character's guild, in its ruleset: an anonymous character may
---store a new identity from that guild.
---@return boolean
function Scopes.LinkedCharacterInGuild()
    local clubId = IsInGuild() and C_Club.GetGuildClubId()
    if not clubId then return false end
    return Identity.HasLinkedCharacterInGuild(clubId, Identity.Ruleset(UnitGUID("player")))
end

-- Workaround for a WoW Forever bug (checked in game 2026-10-10): after joining a guild, a character's add-on messages on
-- GUILD reach no one, not even its own echo, until it logs in again; it still receives the guild's, and its guild chat
-- works; a /reload does not end it. Until then, what would go on GUILD goes by whisper to each online member. Remove
-- Scopes.GuildJoined, Scopes.CanSendOnGuild, Identity.GuildJoined and Identity.JoinedGuildSinceLogin, and their
-- callers, once a character can send on GUILD right after joining.
---PLAYER_GUILD_UPDATE: the character I play joined a guild.
function Scopes.GuildJoined()
    local clubId = C_Club.GetGuildClubId()
    setOwnGuild(clubId, function() Identity.GuildJoined(UnitGUID("player"), clubId) end)
end

---Whether my add-on messages on GUILD reach the guild: not from a character that joined its guild since its last login.
---@return boolean
function Scopes.CanSendOnGuild()
    return not Identity.JoinedGuildSinceLogin(UnitGUID("player"))
end

---Whether that player is in my group and the Group scope is on: the group channel reaches it.
---@param name string
---@return boolean
function Scopes.GroupReaches(name)
    return Scopes.Get("group") and groupMemberGuid(name) ~= nil
end

---My group's channel: RAID in a raid, PARTY otherwise.
---@return WhosWho.Channel
function Scopes.GroupChannel()
    return IsInRaid() and "RAID" or "PARTY"
end

---Whether that player is my WoW friend, or a Battle.net friend's key, and the Friends scope is on: my announcements to
---my friends reach it.
---@param name string
---@return boolean
function Scopes.FriendReaches(name)
    return Scopes.Get("friends") and friendGuid(name) ~= nil
end

-- Audiences --------------------------------------------------------------------------------------

---Every player a message for all my enabled scopes reaches.
---@class WhosWho.Audience
---@field memberChannels WhosWho.Channel[] GUILD, PARTY or RAID: one message reaches every member
---@field guildMembers string[] the online members of my guild, one message each, in place of GUILD while my messages on
---it reach no one (Scopes.CanSendOnGuild)
---@field names string[] players reached by no member channel, one message each

-- One character for each shared person the character I play whispered since that time, within the whisper window: the
-- confirmed character I last whispered with, sent or received, the one they most likely play. A person my guild, group
-- or friends announcements reach is left out.
---@param since number? seconds, from time(); nil gives no one
---@return string[] names
local function whisperedPeople(since)
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    if not (Scopes.Get("whispers") and since) or guildOnly() then return {} end

    local whispered, lastCharacter = {}, {}
    for otherGuid, whisper in pairs(ns.data.whispers) do
        local person, character = People.Find(otherGuid)
        if person and character and character.state == "confirmed" and whisper.ruleset == ruleset then
            local sentAt = whisper.sentAt
            if sentAt and sentAt >= since and withinWhisperWindow(sentAt) then whispered[person.id] = true end
            local at = math.max(sentAt or 0, whisper.receivedAt or 0)
            local last = lastCharacter[person.id]
            if not last or at > last.at then lastCharacter[person.id] = { name = whisper.name, at = at } end
        end
    end

    local names = {}
    for id in pairs(whispered) do
        local name = lastCharacter[id].name
        if not (Scopes.GuildReaches(name) or Scopes.GroupReaches(name) or Scopes.FriendReaches(name)) then
            names[#names + 1] = name
        end
    end
    return names
end

-- The member channels (GUILD, PARTY or RAID); in place of GUILD while my messages on it reach no one, one message to
-- each online guild member that the group channel does not reach; then one message to each online friend that no
-- member channel reaches, and one over Battle.net to each Battle.net friend playing Forever that nothing else reaches
-- (the same character in my guild, group or friend list).
---@return WhosWho.Audience
local function membersAndFriends()
    local memberChannels, guildMembers, names = {}, {}, {}
    local guild = Scopes.SharesWithGuild() and IsInGuild()
    if guild and Scopes.CanSendOnGuild() then memberChannels[#memberChannels + 1] = "GUILD" end
    if Scopes.AnnouncesToGroup() and IsInGroup() then memberChannels[#memberChannels + 1] = Scopes.GroupChannel() end
    if guild and not Scopes.CanSendOnGuild() then
        for _, name in ipairs(Scopes.OnlineGuildMembers()) do
            if not Scopes.GroupReaches(name) then guildMembers[#guildMembers + 1] = name end
        end
    end

    if Scopes.Get("friends") and not guildOnly() then
        local reached = {}
        for _, friend in ipairs(Scopes.Friends()) do
            if friend.connected then reached[friend.guid] = true end
            if friend.connected and not Scopes.GuildReaches(friend.name) and not Scopes.GroupReaches(friend.name) then
                names[#names + 1] = friend.name
            end
        end
        for _, friend in ipairs(Scopes.BnetFriends()) do
            local inGuild = Scopes.GuildReaches(friend.name) and guildMemberGuid(friend.name) == friend.guid
            local inGroup = Scopes.GroupReaches(friend.name) and groupMemberGuid(friend.name) == friend.guid
            if not (reached[friend.guid] or inGuild or inGroup) then names[#names + 1] = friend.key end
        end
    end

    return { memberChannels = memberChannels, guildMembers = guildMembers, names = names }
end

---Every player my login announcement reaches, each once: my members and friends, then one message to each person the
---same character whispered in the loginWhispersSeconds setting before its previous logout, when the account's last logout
---was that character's, that no other way reaches.
---@return WhosWho.Audience
function Scopes.LoginAudience()
    local audience = membersAndFriends()
    local guid, lastLogout = UnitGUID("player"), Identity.LastLogout()
    local since = lastLogout and lastLogout.guid == guid and lastLogout.at - ns.Store.Advanced("loginWhispersSeconds") or nil
    for _, name in ipairs(whisperedPeople(since)) do audience.names[#audience.names + 1] = name end
    return audience
end

---Every player my other broadcasts reach, each once: my members and friends, then one message to each person I
---whispered this session that no other way reaches.
---@return WhosWho.Audience
function Scopes.BroadcastAudience()
    local audience = membersAndFriends()
    for _, name in ipairs(whisperedPeople(Identity.LoggedInAt(UnitGUID("player")))) do
        audience.names[#audience.names + 1] = name
    end
    return audience
end
