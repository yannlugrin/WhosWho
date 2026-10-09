local _, ns = ...
---@cast ns WhosWho.Namespace
local Codec, Identity, People, RecordVerification, Scopes, Store =
    ns.Codec, ns.Identity, ns.People, ns.RecordVerification, ns.Scopes, ns.Store

-- Announcements, record requests (GET) and records (REC) between clients.

---@class WhosWho.Protocol
---@field RegisterComm fun(self, prefix: string, method: function)
---@field SendCommMessage fun(self, prefix: string, text: string, distribution: string, target: string?, prio: string?, callbackFn: function?, callbackArg: any?)
local Protocol = {}
ns.Protocol = Protocol
LibStub("AceComm-3.0"):Embed(Protocol)

local PREFIX = "WhosWho"
local REQUEST_WAIT_SECONDS = 5 -- wait before answering GETs, gathering the GETs that follow
local MAX_WAIT_SECONDS = 300 -- longest wait from its start, however often it is pushed back
local LOCK_WAIT_SECONDS = 5 -- between two tries while sending is locked
local REACHED_DELAY_SECONDS = 30 -- after a REC was sent, GETs from the players it reached are ignored
local REQUEST_DELAY_SECONDS = 60 -- between two GETs for the same identity, and before a GET is sent again if no REC was answered it
local RETRY_LIMIT = 1 -- GETs sent again when no REC answers
local ANNOUNCEMENT_WAIT_SECONDS = 5 -- before answering announcements, gathering the ones that follow
-- The delays a player may change are advanced settings (Store.Advanced).

local issecretvalue = issecretvalue or function() return false end

-- Debug -----------------------------------------------------------------------------------------

local L = ns.L

-- A REC's payload is binary: only its size is shown.
local function describe(text)
    local recordUpdate = text:match("^%d+ REC ")
    return recordUpdate and L["%s(%d bytes)"]:format(recordUpdate, #text) or text
end

local function traceSent(text, distribution, name)
    if not ns.settings.debugMessages then return end
    ns.Print(L["Sent, %s: %s"]:format(name and (distribution .. " " .. name) or distribution, describe(text)))
end

local function traceReceived(text, distribution, sender)
    if not ns.settings.debugMessages then return end
    ns.Print(L["Received, %s: %s"]:format(distribution .. " " .. sender, describe(text)))
end

-- Announcements ----------------------------------------------------------------------------------

-- My announcement from the character I play; from a character I unlinked, NOID in its place; nil while it never was
-- linked.
local function announcementText(level, acceptsGet, wantsAnnouncement)
    local guid = UnitGUID("player")
    if Identity.IsRemoved(guid) then return Codec.NoIdentity() end
    local revision = Identity.AnnouncedRevision(guid)
    return revision and Codec.Announcement(Identity.Id(), revision, level, acceptsGet, wantsAnnouncement)
end

-- My announcement to that audience, in its order: at logout, the client drops the messages past its limit. One that
-- answers a GET keeps the revision it carried, for the next login.
---@param audience WhosWho.Audience
local function announce(audience, level, acceptsGet, wantsAnnouncement, send)
    local message = announcementText(level, acceptsGet, wantsAnnouncement)
    if not message then return end

    for _, channel in ipairs(audience.memberChannels) do send(message, channel) end
    for _, name in ipairs(audience.names) do send(message, "WHISPER", name) end
    if acceptsGet then Identity.SetLastBroadcastRevision(Identity.AnnouncedRevision(UnitGUID("player"))) end
end

-- Whether my logout announcement went out, until the logout is canceled: nothing else goes out meanwhile, so it is the
-- last message the other players get from me.
local loggingOut = false

local function sendQueued(message, channel, name)
    if loggingOut then return end
    traceSent(message, channel, name)
    Protocol:SendCommMessage(PREFIX, message, channel, name)
end

local function sendNow(message, channel, name)
    traceSent(message, channel, name)
    C_ChatInfo.SendAddonMessage(PREFIX, message, channel, name)
end

-- Sending a record ------------------------------------------------------------------------------

---A REC sent: the revision it carried, and when its last part left (nil while queued).
---@class WhosWho.Delivery
---@field revision integer
---@field leftAt number?

-- Last revision published to every audience this session, and whether the Guild scope was on then.
local publishedRevision, publishedWithGuildScope
---@type table<string, true> names of the players who sent a GET for my identity
local requesters = {}
---@type table<string, WhosWho.Delivery> by channel (GUILD, PARTY, RAID) or by name (WHISPER)
local deliveries = {}
-- How many holders keep sending locked (Protocol.LockSending).
local lockCount = 0
---@type number? when the pending RECs go out (GetTime), nil while none is pending
local sendAt
---@type number? when the pending wait started (GetTime)
local waitStartedAt

-- Whether a REC of my current revision that reaches that player is still queued, or was sent less than
-- REACHED_DELAY_SECONDS ago: a GET from that player is then answered by that REC.
local function reachedRecently(name)
    local function deliveredRecently(key)
        local delivery = key and deliveries[key]
        return delivery and delivery.revision == Identity.Revision()
            and (not delivery.leftAt or GetTime() - delivery.leftAt < REACHED_DELAY_SECONDS)
    end
    return deliveredRecently(name)
        or (Scopes.GuildReaches(name) and deliveredRecently("GUILD"))
        or (Scopes.GroupReaches(name) and deliveredRecently(Scopes.GroupChannel()))
end

local function sendRecord(message, channel, name)
    if loggingOut then return end
    local delivery = { revision = Identity.Revision() }
    deliveries[name or channel] = delivery
    traceSent(message, channel, name)
    Protocol:SendCommMessage(PREFIX, message, channel, name, "NORMAL", function(_, sent, total)
        if sent >= total then delivery.leftAt = GetTime() end
    end)
end

-- Ways to answer requesters, in order of preference at equal message count: fewer member channels first, then GUILD
-- before the group channel.
local MEMBER_CHANNEL_CHOICES = {
    {},
    { guild = true },
    { group = true },
    { guild = true, group = true },
}

-- The fewest messages reaching every one of those players: a member channel reaching every player on it, and one whisper
-- to each player left.
---@param names string[]
---@return { guild: true?, group: true? } memberChannels
---@return string[] whispered
local function fewestMessages(names)
    local reachedByGuild, reachedByGroup = {}, {}
    for _, name in ipairs(names) do
        reachedByGuild[name] = Scopes.GuildReaches(name)
        reachedByGroup[name] = Scopes.GroupReaches(name)
    end

    local bestChoice, bestWhispered, bestCount
    for _, choice in ipairs(MEMBER_CHANNEL_CHOICES) do
        local whispered = {}
        for _, name in ipairs(names) do
            if not (choice.guild and reachedByGuild[name]) and not (choice.group and reachedByGroup[name]) then
                whispered[#whispered + 1] = name
            end
        end
        local count = #whispered + (choice.guild and 1 or 0) + (choice.group and 1 or 0)
        if not bestCount or count < bestCount then bestChoice, bestWhispered, bestCount = choice, whispered, count end
    end
    return bestChoice, bestWhispered
end

-- Every requester my scopes still allow, in the fewest messages. An anonymous character answers nobody: the
-- requesters ask again at my next announcement.
local function answerRequesters(recordUpdate)
    if not Identity.IsLinked(UnitGUID("player")) then
        requesters = {}
        return
    end
    local names = {}
    for name in pairs(requesters) do
        if Scopes.Allows(name) then names[#names + 1] = name end
    end
    requesters = {}

    local bestChoice, bestWhispered = fewestMessages(names)
    if bestChoice.guild then sendRecord(recordUpdate(), "GUILD") end
    if bestChoice.group then sendRecord(recordUpdate(), Scopes.GroupChannel()) end
    for _, name in ipairs(bestWhispered) do sendRecord(recordUpdate(), "WHISPER", name) end
end

-- Whether the character I play was anonymous at login, until its first announcement.
local anonymousAtLogin = false

-- A change of revision, to every audience: the players holding an older one ask for it. When the Guild scope was
-- turned on since the last one, the guild members send theirs back: until then they ignored mine, and I theirs. When
-- the character I play was anonymous at login, everyone sends theirs back: it asked nobody.
local function announceRevision()
    local guid = UnitGUID("player")
    local level = UnitLevel("player")
    local wantsAnnouncements = anonymousAtLogin
    local message = announcementText(level, true, wantsAnnouncements)
    if not message then return end

    -- Only an announcement asks: NOID, from a character I unlinked, leaves the flag for when it is linked again.
    if Identity.IsLinked(guid) then anonymousAtLogin = false end
    local guildScopeTurnedOn = Scopes.Get("guild") and not publishedWithGuildScope
    publishedWithGuildScope = Scopes.Get("guild")
    local audience = Scopes.BroadcastAudience()
    for _, channel in ipairs(audience.memberChannels) do
        if channel == "GUILD" and guildScopeTurnedOn and not wantsAnnouncements then
            sendQueued(announcementText(level, true, true), channel)
        else
            sendQueued(message, channel)
        end
    end
    for _, name in ipairs(audience.names) do sendQueued(message, "WHISPER", name) end
    Identity.SetLastBroadcastRevision(Identity.AnnouncedRevision(guid))
end

local function sendRecords()
    -- Pushed back by a later change or GET.
    if GetTime() < sendAt then
        C_Timer.After(sendAt - GetTime(), sendRecords)
        return
    end
    -- Held while I edit my identity, and once my logout announcement went out (a logout makes the next login announce).
    if lockCount > 0 or loggingOut then
        C_Timer.After(LOCK_WAIT_SECONDS, sendRecords)
        return
    end
    sendAt, waitStartedAt = nil, nil

    if Identity.Revision() ~= publishedRevision then announceRevision() end
    publishedRevision = Identity.Revision()

    -- The REC text, built once for every REC this wait sends, and only when one goes out.
    local message
    answerRequesters(function()
        message = message or Codec.RecordUpdate(Identity.SignedRecord())
        return message
    end)
end

-- One wait for every pending REC: a call never brings the send forward, and pushes it back to waitSeconds from now, up
-- to MAX_WAIT_SECONDS after the wait started.
---@param waitSeconds number
local function scheduleRecordSending(waitSeconds)
    local now = GetTime()
    if not sendAt then
        sendAt, waitStartedAt = now + waitSeconds, now
        C_Timer.After(waitSeconds, sendRecords)
        return
    end
    sendAt = math.min(math.max(sendAt, now + waitSeconds), waitStartedAt + MAX_WAIT_SECONDS)
end


-- Answering announcements ---------------------------------------------------------------------------

---@type table<string, true> names of the players waiting for my announcement in answer to theirs
local announcementRecipients = {}
---My last announcement to one player this session.
---@class WhosWho.AnnouncementSent
---@field revision integer
---@field sentAt number GetTime()

---@type table<string, WhosWho.AnnouncementSent> by name
local announcements = {}
local announcementWaiting = false

local function rememberAnnouncement(name, revision)
    announcements[name] = { revision = revision, sentAt = GetTime() }
end

local function sendAnnouncements()
    announcementWaiting = false
    local names = {}
    for name in pairs(announcementRecipients) do
        if Scopes.Allows(name) then names[#names + 1] = name end
    end
    announcementRecipients = {}

    local message = announcementText(UnitLevel("player"), true, false)
    if not (message and names[1]) then return end

    local bestChoice, bestWhispered = fewestMessages(names)
    if bestChoice.guild then sendQueued(message, "GUILD") end
    if bestChoice.group then sendQueued(message, Scopes.GroupChannel()) end
    for _, name in ipairs(bestWhispered) do sendQueued(message, "WHISPER", name) end

    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    for _, name in ipairs(names) do rememberAnnouncement(name, revision) end
end

-- One wait for every player waiting for my answer, from the first one.
local function queueAnnouncement(name)
    announcementRecipients[name] = true
    if announcementWaiting then return end
    announcementWaiting = true
    C_Timer.After(ANNOUNCEMENT_WAIT_SECONDS, sendAnnouncements)
end

-- Players new to my audience ----------------------------------------------------------------------
-- A scope turned on, a group or guild joined, a friend added: they missed my announcements, so each gets one now and
-- sends theirs back.

local function announceToChannel(channel)
    local message = announcementText(UnitLevel("player"), true, true)
    if message then sendQueued(message, channel) end
end

-- The online ones among those friends that no member channel reaches.
---@param friends WhosWho.Friend[]
local function announceToFriends(friends)
    local message = announcementText(UnitLevel("player"), true, true)
    if not message then return end

    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    for _, friend in ipairs(friends) do
        if friend.connected and not Scopes.GuildReaches(friend.name) and not Scopes.GroupReaches(friend.name) then
            sendQueued(message, "WHISPER", friend.name)
            rememberAnnouncement(friend.name, revision)
        end
    end
end

-- Requesting a record ---------------------------------------------------------------------------

---@class WhosWho.Request
---@field sentAt number
---@field retries integer GETs sent again, REQUEST_DELAY_SECONDS apart, without an answer

---@type table<string, WhosWho.Request> by identity ID
local requests = {}

local function sendRequest(id, name)
    if loggingOut then return end
    local message = Codec.RecordRequest(id)
    traceSent(message, "WHISPER", name)
    Protocol:SendCommMessage(PREFIX, message, "WHISPER", name)
end

local function requestRecord(id, name)
    local request = requests[id]
    if request and GetTime() - request.sentAt < REQUEST_DELAY_SECONDS then return end

    request = { sentAt = GetTime(), retries = 0 }
    requests[id] = request
    sendRequest(id, name)

    local function retry()
        if requests[id] ~= request or request.retries >= RETRY_LIMIT then return end
        request.sentAt, request.retries = GetTime(), request.retries + 1
        sendRequest(id, name)
        C_Timer.After(REQUEST_DELAY_SECONDS, retry)
    end
    C_Timer.After(REQUEST_DELAY_SECONDS, retry)
end

-- Receiving --------------------------------------------------------------------------------------

---@param announcement WhosWho.Announcement
local function receiveAnnouncement(announcement, distribution, sender)
    local id = announcement.id
    if id == Identity.Id() then return end

    -- My answer, whatever the character I play: what it sends, if anything, is decided when the answers go out.
    if announcement.wantsAnnouncement and Scopes.Allows(sender) then queueAnnouncement(sender) end
    local linked = Identity.IsLinked(UnitGUID("player"))

    -- An anonymous character only updates the identities I hold, and asks nothing; without any linked character, it
    -- takes nothing.
    if not (linked or (People.Get(id) and Identity.LinkedCount() > 0)) then return end

    local senderGuid = Scopes.SenderGuid(sender, distribution)
    if senderGuid then
        People.Confirm(id, senderGuid, announcement.level)
        Scopes.SetRelationships(senderGuid, sender)
    end

    if not announcement.acceptsGet then
        -- The owner left: a GET would get no answer, and my announcement would not reach them.
        requests[id] = nil
        announcementRecipients[sender] = nil
    elseif linked and People.IsNewer(id, announcement.rev) and Scopes.Allows(sender) then
        requestRecord(id, sender)
    end
end

---@param request WhosWho.RecordRequest
local function receiveRecordRequest(request, sender)
    if request.id ~= Identity.Id() or not Identity.IsLinked(UnitGUID("player")) or reachedRecently(sender) then return end
    requesters[sender] = true
    scheduleRecordSending(REQUEST_WAIT_SECONDS)
end

-- A REC is used only from a channel I share on, so strangers cannot fill my saved data.
local function sharedChannel(distribution, sender)
    if distribution == "GUILD" then return Scopes.Get("guild") end
    if distribution == "PARTY" or distribution == "RAID" then return Scopes.Get("group") end
    if distribution == "WHISPER" then return Scopes.Allows(sender) end
    return false
end

---@param recordUpdate WhosWho.RecordUpdate
local function receiveRecordUpdate(recordUpdate, distribution, sender)
    local signedRecord = recordUpdate.signedRecord
    if signedRecord.id == Identity.Id() or not sharedChannel(distribution, sender) then return end
    if not People.IsNewer(signedRecord.id, signedRecord.rev) then return end
    -- An anonymous character stores a new identity only from the guild of one of my linked characters.
    if not (Identity.IsLinked(UnitGUID("player")) or People.Get(signedRecord.id)
        or (distribution == "GUILD" and Scopes.LinkedCharacterInGuild())) then
        return
    end

    RecordVerification.Queue(signedRecord, function(verified)
        if People.Accept(verified) ~= "stale" then
            requests[verified.id] = nil
            Scopes.KeepSentWhispers()
        end
    end)
end

-- A character declaring no identity leaves the shared identity holding it.
local function receiveNoIdentity(distribution, sender)
    local guid = Scopes.SenderGuid(sender, distribution)
    if guid and not Identity.Characters()[guid] then People.DeclaredNoIdentity(guid) end
end

local function receive(_, text, distribution, sender)
    if issecretvalue(text) or issecretvalue(sender) then return end
    traceReceived(text, distribution, sender)
    local message = Codec.Decode(text)
    if not message then return end
    -- Without a linked character, I take nothing; a character I unlinked still answers an announcement with NOID.
    if Identity.LinkedCount() == 0 and message.type ~= "ANNOUNCE" then return end

    if message.type == "ANNOUNCE" then
        receiveAnnouncement(message, distribution, sender)
    elseif message.type == "GET" then
        receiveRecordRequest(message, sender)
    elseif message.type == "REC" then
        receiveRecordUpdate(message, distribution, sender)
    elseif message.type == "NOID" then
        receiveNoIdentity(distribution, sender)
    end
end

-- Game events ----------------------------------------------------------------------------------

---@type boolean? nil until Protocol.Start
local wasInGroup, wasInGuild
---@type table<string, true>? GUIDs of my WoW friends at the previous FRIENDLIST_UPDATE, nil until Protocol.Start
local friendGuids

---@param friends WhosWho.Friend[]
local function guidsOf(friends)
    local guids = {}
    for _, friend in ipairs(friends) do guids[friend.guid] = true end
    return guids
end

-- Turning the Guild scope on makes a change of revision, whose announcement brings the guild's back (announceRevision).
-- Turning the Whispers scope on sends nothing: it applies to the players I whisper from then on.
---@param key "guild"|"friends"|"whispers"|"group"
local function announceScope(key)
    if key == "group" and IsInGroup() then
        announceToChannel(Scopes.GroupChannel())
    elseif key == "friends" then
        announceToFriends(Scopes.Friends())
    end
end

---@type table<string, true> scopes turned on while sending was locked
local heldScopes = {}

-- While sending is locked, a scope turned on waits: only the ones still on when it is released are announced.
local function scopeEnabled(key)
    if lockCount > 0 then
        heldScopes[key] = true
        return
    end
    announceScope(key)
end

---Locks sending until every holder released it: the RECs wait, and so do the announcements of the scopes turned on.
---Held while the settings are open, so that only what is set when they close goes out.
function Protocol.LockSending()
    lockCount = lockCount + 1
end

function Protocol.UnlockSending()
    if lockCount == 0 then return end
    lockCount = lockCount - 1
    if lockCount > 0 then return end
    for key in pairs(heldScopes) do
        if Scopes.Get(key) then announceScope(key) end
    end
    heldScopes = {}
end

---PLAYER_LOGIN, after the character refresh: registers the prefix, takes the current revision as announced, announces
---each change of revision and each scope turned on.
function Protocol.Start()
    Protocol:RegisterComm(PREFIX, receive)
    -- A change found at login reaches online players through the login announcement and their GETs.
    publishedRevision, publishedWithGuildScope = Identity.Revision(), Scopes.Get("guild")
    Identity.OnRevisionChanged(function() scheduleRecordSending(Store.Advanced("revisionWaitSeconds")) end)
    Scopes.OnEnabled(scopeEnabled)
    anonymousAtLogin = not Identity.IsLinked(UnitGUID("player"))
    -- The login announcement already reaches a group or guild I am in, and my friends online.
    wasInGroup, wasInGuild = IsInGroup(), IsInGuild()
    friendGuids = guidsOf(Scopes.Friends())
end

---PLAYER_LOGIN, after Protocol.Start: every player it reaches answers with their announcement. Nothing on a quick
---relog: the same character as the account's last logout, less than the quickRelogSeconds setting ago, announcing the revision
---my last announcement to every audience already carried.
function Protocol.AnnounceLogin()
    local guid, lastLogout = UnitGUID("player"), Identity.LastLogout()
    local quickRelog = lastLogout and lastLogout.guid == guid
        and time() - lastLogout.at < Store.Advanced("quickRelogSeconds")
    if quickRelog and Identity.AnnouncedRevision(guid) == Identity.LastBroadcastRevision() then return end
    announce(Scopes.LoginAudience(), UnitLevel("player"), true, true, sendQueued)
end

---PLAYER_LEVEL_UP.
---@param level integer the new level
function Protocol.AnnounceLevel(level)
    announce(Scopes.BroadcastAudience(), level, true, false, sendQueued)
end

---When the logout or quit countdown starts, and on an immediate logout or quit: once per logout. Sent directly, since
---the throttled queue would not empty in time; a GET would get no answer. Nothing on a /reload, and SendAddonMessage
---fails during a logout's PLAYER_LOGOUT.
function Protocol.AnnounceLogout()
    if loggingOut then return end
    loggingOut = true
    announce(Scopes.BroadcastAudience(), UnitLevel("player"), false, false, sendNow)
end

---PLAYER_LOGOUT (a logout or a /reload): when a REC is still owed (requesters waiting, the wait running, or a REC not
---left yet), the next login announces again, even on a quick relog: the requesters dropped their GET at my logout
---announcement.
function Protocol.SessionEnding()
    local recordOwed = next(requesters) ~= nil or sendAt ~= nil
    for _, delivery in pairs(deliveries) do
        if not delivery.leftAt then recordOwed = true end
    end
    if recordOwed then Identity.SetLastBroadcastRevision(nil) end
end

---The logout or quit countdown is canceled: nothing is sent, and the next logout is announced again. The players who
---need my record ask for it at my next announcement.
function Protocol.LogoutCanceled()
    loggingOut = false
end

---GROUP_ROSTER_UPDATE: on joining a group, my announcement to the group, which every member answers with theirs.
function Protocol.GroupRosterChanged()
    -- The roster can arrive during the loading screen, before PLAYER_LOGIN.
    if wasInGroup == nil then return end
    local inGroup = IsInGroup()
    local joined = inGroup and not wasInGroup
    wasInGroup = inGroup
    if not (joined and Scopes.Get("group")) then return end

    announceToChannel(Scopes.GroupChannel())
end

---PLAYER_GUILD_UPDATE for my character: on joining a guild, my announcement to it, which every member answers with
---theirs.
function Protocol.GuildChanged()
    if wasInGuild == nil then return end
    local inGuild = IsInGuild()
    local joined = inGuild and not wasInGuild
    wasInGuild = inGuild
    if joined and Scopes.Get("guild") then announceToChannel("GUILD") end
end

---FRIENDLIST_UPDATE, after Scopes.FriendListChanged: my announcement to each friend added, which they answer with theirs.
function Protocol.FriendListChanged()
    if not friendGuids then return end
    local friends, added = Scopes.Friends(), {}
    for _, friend in ipairs(friends) do
        if not friendGuids[friend.guid] then added[#added + 1] = friend end
    end
    friendGuids = guidsOf(friends)
    if Scopes.Get("friends") then announceToFriends(added) end
end

---CHAT_MSG_WHISPER_INFORM, after Scopes.WhisperSent: my announcement to the player I whispered, sent right away, when
---none reached them this session, the last one carried an older revision, or it left the whisperAnnouncementSeconds setting ago.
---A player my guild, group or friends announcements reach gets none. The player answers with theirs if they allow me.
---@param name any
function Protocol.Whispered(name)
    if not name or issecretvalue(name) or name == ns.UnitWholeName("player") then return end
    if not (Scopes.Get("whispers") and Scopes.Allows(name)) then return end
    if Scopes.GuildReaches(name) or Scopes.GroupReaches(name) or Scopes.FriendReaches(name) then return end
    local message = announcementText(UnitLevel("player"), true, true)
    if not message then return end
    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    local last = announcements[name]
    local announcedRecently = last and GetTime() - last.sentAt < Store.Advanced("whisperAnnouncementSeconds")
    if announcedRecently and last.revision == revision then return end

    sendQueued(message, "WHISPER", name)
    rememberAnnouncement(name, revision)
end
