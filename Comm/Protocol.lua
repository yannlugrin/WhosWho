local _, ns = ...
---@cast ns WhosWho.Namespace
local Codec, Diagnostic, GuildList, GuildRecord, GuildSettings, Identity, People, Record, RecordVerification, Scopes, Store =
    ns.Codec, ns.Diagnostic, ns.GuildList, ns.GuildRecord, ns.GuildSettings, ns.Identity, ns.People, ns.Record,
    ns.RecordVerification, ns.Scopes, ns.Store

-- Announcements, record requests (GET) and records (REC) between clients, the guild settings (GSGET, GSET), the guild
-- lists (GLGET, GLIST) and the guild's records (GIGET, GIREC).

---@class WhosWho.Protocol
---@field RegisterComm fun(self, prefix: string, method: function)
---@field SendCommMessage fun(self, prefix: string, text: string, distribution: string, target: string?, prio: string?, callbackFn: function?, callbackArg: any?)
local Protocol = {}
ns.Protocol = Protocol
LibStub("AceComm-3.0"):Embed(Protocol)

local PREFIX = "WhosWho"
-- Waits gathering what follows before sending (newGathering): after the last call, and at most after the first one.
local REQUEST_WAIT = { seconds = 5, maxSeconds = 30 } -- answering GETs of identities I relay, GIGETs, GLGETs
local ANNOUNCEMENT_WAIT = { seconds = 5, maxSeconds = 30 } -- answering announcements; comparing the lists they carry
local GUILD_CHANGES_WAIT = { seconds = 5, maxSeconds = 30 } -- my changes to my guild's settings and records
local RECORD_WAIT = { seconds = 5, maxSeconds = 300 } -- my change of revision (revisionWaitSeconds), my RECs to GETs
local REACHED_DELAY_SECONDS = 30 -- after a REC was sent, GETs from the players it reached are ignored
local REQUEST_DELAY_SECONDS = 60 -- between two GETs for the same identity, and before a GET is sent again if no REC was answered it
local RETRY_LIMIT = 1 -- GETs sent again when no REC answers
-- The delays a player may change are advanced settings (Store.Advanced).

local issecretvalue = issecretvalue or function() return false end

-- Gathering --------------------------------------------------------------------------------------

---How long a gathering waits: after the last call, and at most after the first one.
---@class WhosWho.GatheringWait
---@field seconds number after each call, before sending; a call never brings the send forward
---@field maxSeconds number from the first call of a batch: the send happens by then, however many calls follow

-- Runs `send` once the calls have stopped for `wait.seconds` (each call pushes the send back), and at the latest
-- `wait.maxSeconds` after the first call of the batch, so a steady flow of calls never holds it forever. While I am in
-- combat, or while `held` says so, the send waits, checking again every `wait.seconds`: what a send builds (a record or
-- a guild list packed, a guild's record signed) takes tens of ms. A call made during `send` starts the next batch.
-- Returns the function to call, which may give its own wait, and whether a batch is waiting.
---@param wait WhosWho.GatheringWait
---@param send fun()
---@param held (fun(): boolean)?
---@return fun(seconds: number?) gather
---@return fun(): boolean waiting
local function newGathering(wait, send, held)
    local sendAt, startedAt, timerRunning = nil, nil, false

    local function fire()
        timerRunning = false
        if not sendAt then return end
        local now = GetTime()
        local due = math.min(sendAt, startedAt + wait.maxSeconds)
        if now >= due and (UnitAffectingCombat("player") or held and held()) then due = now + wait.seconds end
        if now < due then
            timerRunning = true
            C_Timer.After(due - now, fire)
            return
        end
        sendAt, startedAt = nil, nil
        send()
    end

    local function gather(seconds)
        local now = GetTime()
        startedAt = startedAt or now
        sendAt = math.max(sendAt or 0, now + (seconds or wait.seconds))
        if timerRunning then return end
        timerRunning = true
        C_Timer.After(sendAt - now, fire)
    end

    return gather, function() return sendAt ~= nil end
end

-- Debug -----------------------------------------------------------------------------------------

local L = ns.L

-- What became of a guild settings record received: dropped, checked, then accepted, held back, refused or stale.
local function traceGuildSettings(signedRecord, outcome)
    Diagnostic.Print(L["Guild settings %d: %s"]:format(signedRecord.rev, outcome))
end

-- Sending ----------------------------------------------------------------------------------------

-- Whether my logout announcement went out, until the logout is canceled: nothing else goes out meanwhile, so it is the
-- last message the other players get from me.
local loggingOut = false

local function sendQueued(message, channel, name)
    if loggingOut then return end
    Diagnostic.MessageSent(message, channel, name)
    Protocol:SendCommMessage(PREFIX, message, channel, name)
end

local function sendNow(message, channel, name)
    Diagnostic.MessageSent(message, channel, name)
    C_ChatInfo.SendAddonMessage(PREFIX, message, channel, name)
end

-- Hello ------------------------------------------------------------------------------------------

-- My add-on version in a HELLO: the TOC version, "x.y.z" with the suffix of a pre-release or of a build after a tag, or
-- "-" for a copy without one.
local OWN_VERSION = ns.Version:match("^%d+%.%d+%.%d+%S*$") and ns.Version or "-"

---@type table<string, true> the channels I greeted this session: GUILD, PARTY, RAID, or the name of a player whispered
local greeted = {}

-- My HELLO, before the first announcement I start on that channel this session.
local function greet(channel, name)
    local key = name or channel
    if greeted[key] then return end
    greeted[key] = true
    sendQueued(Codec.Hello(OWN_VERSION), channel, name)
end

-- An announcement I start, not an answer: my HELLO first on a channel not greeted yet. NOID goes alone.
local function sendAnnouncement(message, channel, name)
    if message ~= Codec.NoIdentity() then greet(channel, name) end
    sendQueued(message, channel, name)
end

local PRE_RELEASES = { alpha = 1, beta = 2, rc = 3 }

-- A version as the numbers it compares by: x, y, z, then where it stands among those of its x.y.z. A pre-release comes
-- before the release (alpha, beta, then rc, each by its number: "-beta.2"), a build after the tag after it (the
-- packager's git describe: "-3-g1a2b3c4", by its count of commits); any other suffix counts as the release. Nil without
-- "x.y.z".
local function versionOrder(version)
    local major, minor, patch, suffix = version:match("^(%d+)%.(%d+)%.(%d+)(%S*)$")
    if not major then return nil end
    local stage, step = 2, 0
    local preRelease, number = suffix:match("^%-(%a+)%.?(%d*)$")
    local commits = suffix:match("^%-(%d+)%-g%x+$")
    if commits then
        stage, step = 3, tonumber(commits)
    elseif preRelease and PRE_RELEASES[preRelease:lower()] then
        stage, step = 1, PRE_RELEASES[preRelease:lower()] * 100000 + (tonumber(number) or 0)
    end
    return { tonumber(major), tonumber(minor), tonumber(patch), stage, step }
end

-- Whether a version is older than another; false when either doesn't start with "x.y.z".
local function isOlderVersion(version, than)
    local order, thanOrder = versionOrder(version), versionOrder(than)
    if not (order and thanOrder) then return false end
    for i = 1, #order do
        if order[i] ~= thanOrder[i] then return order[i] < thanOrder[i] end
    end
    return false
end

-- Whether a version is a release: "x.y.z", without a suffix.
local function isRelease(version)
    return version:match("^%d+%.%d+%.%d+$") ~= nil
end

-- Whether a version is an update for mine: newer, and a release unless mine isn't one either. A player on a release
-- isn't told about pre-releases or builds they didn't choose to follow.
local function isUpdate(version)
    return isOlderVersion(OWN_VERSION, version) and (isRelease(version) or not isRelease(OWN_VERSION))
end

---@type { version: string, name: string }? the newest add-on version a HELLO carried this session, and its sender
local newestVersion
---@type fun(version: string, name: string)[]
local updateListeners = {}
-- Whether an update was seen this session: its listeners are called once.
local updateSeen = false
---@type table<string, true> the players a HELLO of mine answered this session, their version being older
local helloAnswered = {}

-- Guild ------------------------------------------------------------------------------------------

-- Whether I exchange guild lists: in a guild whose settings enable Who's Who, with the Guild scope, from a linked
-- character.
local function guildListsActive()
    local guid = UnitGUID("player")
    return IsInGuild() and Scopes.SharesWithGuild() and Identity.IsLinked(guid)
        and GuildSettings.Get(Identity.GuildId(guid)).enable
end

-- My list of my current guild: its club ID, and its revision.
---@return integer clubId
---@return integer at
---@return string hash
local function ownGuildList()
    local guid = UnitGUID("player")
    local clubId = Identity.GuildId(guid)
    local at, hash = GuildList.Revision(clubId, Identity.Ruleset(guid), GetServerTime())
    return clubId, at, hash
end

-- To the members of my current guild: on GUILD, or to each online member while my messages on it reach no one
-- (Scopes.CanSendOnGuild).
local function sendToGuild(message)
    if Scopes.CanSendOnGuild() then
        sendQueued(message, "GUILD")
        return
    end
    for _, name in ipairs(Scopes.OnlineGuildMembers()) do sendQueued(message, "WHISPER", name) end
end

-- An announcement I start, to the members of my current guild (sendToGuild).
local function announceToGuild(message)
    if Scopes.CanSendOnGuild() then
        sendAnnouncement(message, "GUILD")
        return
    end
    for _, name in ipairs(Scopes.OnlineGuildMembers()) do sendAnnouncement(message, "WHISPER", name) end
end

-- Announcements ----------------------------------------------------------------------------------

-- My announcement from the character I play, when it announces; otherwise NOID from a character I unlinked, nil from one
-- never linked.
local function announcementText(level, acceptsGet, wantsAnnouncement)
    local guid = UnitGUID("player")
    local revision = Identity.AnnouncedRevision(guid)
    if not revision then return Identity.IsRemoved(guid) and Codec.NoIdentity() or nil end
    -- Logging out, I answer no request: no guild list or settings to offer.
    local listAt, listHash
    if acceptsGet and guildListsActive() then
        local _, at, hash = ownGuildList()
        -- A first list is only there to be replaced: never offered.
        if at > 0 then listAt, listHash = at, hash end
    end
    local settingsRevision = acceptsGet and GuildSettings.Revision(Identity.GuildId(guid)) or 0
    return Codec.Announcement(Identity.Id(), revision, level, acceptsGet, wantsAnnouncement, listAt, listHash,
        settingsRevision)
end

-- My announcement to that audience, in its order: at logout, the client drops the messages past its limit. One that
-- answers a GET keeps the revision it carried, for the next login.
---@param audience WhosWho.Audience
local function announce(audience, level, acceptsGet, wantsAnnouncement, send)
    local message = announcementText(level, acceptsGet, wantsAnnouncement)
    if not message then return end

    for _, channel in ipairs(audience.memberChannels) do send(message, channel) end
    for _, name in ipairs(audience.guildMembers) do send(message, "WHISPER", name) end
    for _, name in ipairs(audience.names) do send(message, "WHISPER", name) end
    if acceptsGet then Identity.SetLastBroadcastRevision(Identity.AnnouncedRevision(UnitGUID("player"))) end
end

-- Sending a record ------------------------------------------------------------------------------

---A REC sent: the revision it carried, and when its last part left (nil while queued).
---@class WhosWho.Delivery
---@field revision integer
---@field clubId integer? the guild enforcing linking whose members' record it was; nil for everyone's
---@field leftAt number?

-- Last revision published to every audience this session, and whether I shared with my guild then.
local publishedRevision, publishedSharingWithGuild
-- The bytes of everyone's record as last published, without its revision.
local publishedBytes
---@type table<string, true> names of the players who sent a GET for my identity
local requesters = {}
---@type table<string, WhosWho.Delivery> by channel (GUILD, PARTY, RAID) or by name (WHISPER)
local deliveries = {}
-- How many holders keep sending locked (Protocol.LockSending).
local lockCount = 0

-- Whether a REC of my current revision that reaches that player, with the record it gets, is still queued, or was sent
-- less than REACHED_DELAY_SECONDS ago: a GET from that player is then answered by that REC.
local function reachedRecently(name)
    local clubId = Scopes.RecordGuildOf(name)
    local function deliveredRecently(key)
        local delivery = key and deliveries[key]
        return delivery and delivery.revision == Identity.Revision() and delivery.clubId == clubId
            and (not delivery.leftAt or GetTime() - delivery.leftAt < REACHED_DELAY_SECONDS)
    end
    return deliveredRecently(name)
        or (Scopes.GuildReaches(name) and deliveredRecently("GUILD"))
        or (Scopes.GroupReaches(name) and deliveredRecently(Scopes.GroupChannel()))
end

local function sendRecord(message, channel, name, clubId)
    if loggingOut then return end
    local delivery = { revision = Identity.Revision(), clubId = clubId }
    deliveries[name or channel] = delivery
    Diagnostic.MessageSent(message, channel, name)
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
        reachedByGuild[name] = Scopes.CanSendOnGuild() and Scopes.GuildReaches(name)
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

-- Every requester my record still reaches, in the fewest messages for each record they get: my guild's members' one,
-- everyone's. The others ask again at my next announcement. Each record is signed when its first REC goes out, about
-- 110 ms in one frame: when both go out, everyone's waits for the next frame.
local function answerRequesters(recordUpdate)
    local guildClubId, guildRuleset = Scopes.GuildContent()
    local guildNames, names = {}, {}
    for name in pairs(requesters) do
        if Scopes.RecordReaches(name) then
            if Scopes.RecordGuildOf(name) then
                guildNames[#guildNames + 1] = name
            else
                names[#names + 1] = name
            end
        end
    end
    requesters = {}

    local function answer(list, clubId, ruleset)
        local bestChoice, bestWhispered = fewestMessages(list)
        if bestChoice.guild then sendRecord(recordUpdate(clubId, ruleset), "GUILD", nil, clubId) end
        if bestChoice.group then sendRecord(recordUpdate(clubId, ruleset), Scopes.GroupChannel(), nil, clubId) end
        for _, name in ipairs(bestWhispered) do sendRecord(recordUpdate(clubId, ruleset), "WHISPER", name, clubId) end
    end
    answer(guildNames, guildClubId, guildRuleset)
    if guildNames[1] and names[1] then
        C_Timer.After(0, function() answer(names) end)
    else
        answer(names)
    end
end

-- Whether the character I play was anonymous at login, until its first announcement.
local anonymousAtLogin = false

-- A change of revision, to every audience, or to my guild alone when only its members' record changed: the players
-- holding an older one ask for it. When I started sharing with my guild since the last one (the Guild scope turned on, or
-- its rule answered), the guild members send theirs back: until then they ignored mine, and I theirs. When the character I play was anonymous at login, everyone sends
-- theirs back: it asked nobody.
local function announceRevision(guildOnly)
    local guid = UnitGUID("player")
    local level = UnitLevel("player")
    local wantsAnnouncements = anonymousAtLogin
    local message = announcementText(level, true, wantsAnnouncements)
    if not message then return end

    -- Only an announcement asks: NOID, from a character I unlinked, leaves the flag for when it is linked again.
    if Identity.IsLinked(guid) then anonymousAtLogin = false end
    local guildSharingStarted = Scopes.SharesWithGuild() and not publishedSharingWithGuild
    publishedSharingWithGuild = Scopes.SharesWithGuild()
    local guildMessage = guildSharingStarted and not wantsAnnouncements and announcementText(level, true, true) or message
    local audience = Scopes.BroadcastAudience()
    for _, channel in ipairs(audience.memberChannels) do
        if channel == "GUILD" or not guildOnly then
            sendAnnouncement(channel == "GUILD" and guildMessage or message, channel)
        end
    end
    for _, name in ipairs(audience.guildMembers) do sendAnnouncement(guildMessage, "WHISPER", name) end
    if not guildOnly then
        for _, name in ipairs(audience.names) do sendAnnouncement(message, "WHISPER", name) end
    end
    Identity.SetLastBroadcastRevision(Identity.AnnouncedRevision(guid))
end

local function sendRecords()
    if Identity.Revision() ~= publishedRevision then
        -- Everyone's record unchanged: the change is only in what my guild's members get.
        local bytes = Identity.RecordBytesWithoutRevision()
        announceRevision(bytes == publishedBytes)
        publishedBytes = bytes
    end
    publishedRevision = Identity.Revision()

    -- Each REC text, built once for every REC this wait sends, and only when one goes out.
    local messages = {}
    answerRequesters(function(clubId, ruleset)
        local key = clubId or 0
        messages[key] = messages[key] or Codec.RecordUpdate(Identity.SignedRecord(clubId, ruleset))
        return messages[key]
    end)
end

-- One wait for my change of revision and every pending REC. Held while I edit my identity, and once my logout
-- announcement went out (a logout makes the next login announce).
local scheduleRecordSending, recordSendingWaiting = newGathering(RECORD_WAIT, sendRecords,
    function() return lockCount > 0 or loggingOut end)

-- Answering announcements ---------------------------------------------------------------------------

---@type table<string, true> names of the players waiting for my announcement in answer to theirs
local announcementRecipients = {}
---My last announcement to one player this session.
---@class WhosWho.AnnouncementSent
---@field revision integer
---@field sentAt number GetTime()

---@type table<string, WhosWho.AnnouncementSent> by name
local announcements = {}

local function rememberAnnouncement(name, revision)
    announcements[name] = { revision = revision, sentAt = GetTime() }
end

local function sendAnnouncements()
    local names = {}
    for name in pairs(announcementRecipients) do
        if Scopes.AnnouncementReaches(name) then names[#names + 1] = name end
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

-- One wait for every player waiting for my answer.
local answerAnnouncements = newGathering(ANNOUNCEMENT_WAIT, sendAnnouncements)

local function queueAnnouncement(name)
    announcementRecipients[name] = true
    answerAnnouncements()
end

-- Players new to my audience ----------------------------------------------------------------------
-- A scope turned on, a group or guild joined, a friend added: they missed my announcements, so each gets one now and
-- sends theirs back.

local function announceToChannel(channel)
    local message = announcementText(UnitLevel("player"), true, true)
    if message then sendAnnouncement(message, channel) end
end

-- The online ones among those friends that no member channel reaches.
---@param friends WhosWho.Friend[]
local function announceToFriends(friends)
    local message = announcementText(UnitLevel("player"), true, true)
    if not message then return end

    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    for _, friend in ipairs(friends) do
        if friend.connected and Scopes.AnnouncementReaches(friend.name) and not Scopes.GuildReaches(friend.name)
            and not Scopes.GroupReaches(friend.name) then
            sendAnnouncement(message, "WHISPER", friend.name)
            rememberAnnouncement(friend.name, revision)
        end
    end
end

-- Requesting a record ---------------------------------------------------------------------------

---@class WhosWho.Request
---@field sentAt number
---@field retries integer GETs sent again, REQUEST_DELAY_SECONDS apart, without an answer

---@type table<string, WhosWho.Request> by identity ID: players' records asked for (GET)
local recordRequests = {}
---@type table<string, WhosWho.Request> by identity ID: my guild's records asked for (GIGET)
local guildRecordRequests = {}

---What is asked for: the requests waiting for an answer, and the message that asks.
---@class WhosWho.RequestedRecords
---@field requests table<string, WhosWho.Request>
---@field encode fun(ids: string[]): string

---@type WhosWho.RequestedRecords players' records
local RECORDS = { requests = recordRequests, encode = Codec.RecordRequest }
---@type WhosWho.RequestedRecords my guild's records
local GUILD_RECORDS = { requests = guildRecordRequests, encode = Codec.GuildRecordRequest }

local function sendRequest(message, name)
    if loggingOut then return end
    Diagnostic.MessageSent(message, "WHISPER", name)
    Protocol:SendCommMessage(PREFIX, message, "WHISPER", name)
end

local function requestRecord(id, name)
    local request = recordRequests[id]
    if request and GetTime() - request.sentAt < REQUEST_DELAY_SECONDS then return end

    request = { sentAt = GetTime(), retries = 0 }
    recordRequests[id] = request
    sendRequest(Codec.RecordRequest({ id }), name)

    local function retry()
        if recordRequests[id] ~= request or request.retries >= RETRY_LIMIT then return end
        request.sentAt, request.retries = GetTime(), request.retries + 1
        sendRequest(Codec.RecordRequest({ id }), name)
        C_Timer.After(REQUEST_DELAY_SECONDS, retry)
    end
    C_Timer.After(REQUEST_DELAY_SECONDS, retry)
end

-- Records from the members holding them, players' (RECORDS: GET) or my guild's (GUILD_RECORDS: GIGET): a batch of up
-- to Codec.MAX_REQUESTED_IDS to each holder in turn, from a random one, so that the requests of several members spread
-- over the holders. A batch not answered within REQUEST_DELAY_SECONDS goes once to the next holder. An identity already
-- asked for meanwhile is left out.
---@param ids string[]
---@param holders string[]
---@param records WhosWho.RequestedRecords RECORDS or GUILD_RECORDS
local function requestFromHolders(ids, holders, records)
    if not holders[1] then return end
    local holderIndex, batch = fastrandom(1, #holders), {}

    local function sendBatch()
        if not batch[1] then return end
        local sentBatch, holder = batch, holderIndex
        batch, holderIndex = {}, holderIndex % #holders + 1
        local request = { sentAt = GetTime(), retries = 0 }
        for _, id in ipairs(sentBatch) do records.requests[id] = request end
        sendRequest(records.encode(sentBatch), holders[holder])

        C_Timer.After(REQUEST_DELAY_SECONDS, function()
            local unanswered = {}
            for _, id in ipairs(sentBatch) do
                if records.requests[id] == request then unanswered[#unanswered + 1] = id end
            end
            if not unanswered[1] then return end
            request.sentAt, request.retries = GetTime(), request.retries + 1
            sendRequest(records.encode(unanswered), holders[holder % #holders + 1])
        end)
    end

    for _, id in ipairs(ids) do
        local request = records.requests[id]
        if not (request and GetTime() - request.sentAt < REQUEST_DELAY_SECONDS) then
            batch[#batch + 1] = id
            if #batch == Codec.MAX_REQUESTED_IDS then sendBatch() end
        end
    end
    sendBatch()
end

-- Guild settings --------------------------------------------------------------------------------

---@type { rev: integer, sentAt: number }? my GSGET in flight: the revision it asks for, and when it left (GetTime)
local guildSettingsRequest
---@type table<string, integer> by member, the revision of the guild settings I refused from them: never asked of
---them again
local refusedGuildSettings = {}

-- One GSGET to a member who announced newer guild settings; another member announcing them gets none while it waits.
local function requestGuildSettings(name, rev)
    local request = guildSettingsRequest
    if refusedGuildSettings[name] == rev then return end
    -- One request at a time, but a member trusted for a guild's first settings is asked over one who isn't.
    local trusted = Scopes.TrustedForGuildSettings(name)
    if request and request.rev >= rev and GetTime() - request.sentAt < REQUEST_DELAY_SECONDS
        and (request.trusted or not trusted) then
        return
    end
    guildSettingsRequest = { rev = rev, sentAt = GetTime(), trusted = trusted }
    sendQueued(Codec.GuildSettingsRequest(), "WHISPER", name)
end

---@type WhosWho.GuildSettingsRecord? the newest verified record held back until the game gives my guild's club ID, and
---its signing character is confirmed and in my roster, tried again as they change
local pendingGuildSettings
-- The member who sent the record held back.
local pendingSender

local function acceptGuildSettings(signedRecord, sender)
    -- Right after joining, the game may not give my guild's club ID yet: the record waits for it.
    local clubId = Identity.GuildId(UnitGUID("player"))
    local result
    if not clubId then
        result = "pending"
    elseif signedRecord.guild ~= clubId then
        result = "another guild"
    else
        result = GuildSettings.Accept(signedRecord, Scopes.GuildRankIndex(signedRecord.signerGuid),
            Scopes.TrustedForGuildSettings(sender))
    end
    traceGuildSettings(signedRecord, result)
    if result == "accepted" then
        guildSettingsRequest = nil
    elseif result == "refused" then
        refusedGuildSettings[sender] = signedRecord.rev
    elseif result == "pending"
        and not (pendingGuildSettings and GuildSettings.IsNewerThan(pendingGuildSettings, signedRecord)) then
        pendingGuildSettings, pendingSender = signedRecord, sender
    end
end

local function retryPendingGuildSettings()
    local signedRecord = pendingGuildSettings
    if not signedRecord then return end
    pendingGuildSettings = nil
    acceptGuildSettings(signedRecord, pendingSender)
end

-- Whether my guild's settings changed since they last went out.
local guildSettingsChanged = false
-- Whether the settings waiting to go out enabled Who's Who for the guild: my announcement follows them, so that the
-- members compare their lists with mine, and not each with every other.
local guildListsEnabledByMe = false

-- My current guild's settings, to its members.
local function sendGuildSettings()
    local announceList = guildListsEnabledByMe
    guildListsEnabledByMe = false
    local signedRecord = GuildSettings.Record(Identity.GuildId(UnitGUID("player")))
    if not (signedRecord and Scopes.Get("guild") and IsInGuild()) then return end
    sendToGuild(Codec.GuildSettingsUpdate(signedRecord))
    local announcement = announceList and signedRecord.settings.enable and announcementText(UnitLevel("player"), true, false)
    if announcement then announceToGuild(announcement) end
end

---Whether the character I play may change my guild's records (GuildRecord): while I exchange guild lists, at a rank
---index up to GuildList.TRUSTED_RANK_INDEX in my roster, the rank the members check.
---@return boolean
function Protocol.CanChangeGuildRecords()
    local rankIndex = Scopes.GuildRankIndex(UnitGUID("player"))
    return guildListsActive() and rankIndex ~= nil and rankIndex <= GuildList.TRUSTED_RANK_INDEX
end

---@type table<string, true> by identity ID: my guild's records I changed, sent once the changes that follow gathered
local changedGuildRecords = {}

-- Each record of my guild I changed, once, at its latest revision.
local function sendChangedGuildRecords()
    local clubId = Identity.GuildId(UnitGUID("player"))
    for id in pairs(changedGuildRecords) do
        local signedRecord = GuildRecord.Held(clubId, id)
        if signedRecord then sendToGuild(Codec.GuildRecordUpdate(signedRecord)) end
    end
    changedGuildRecords = {}
end

-- My changes to my guild, gathered: its settings when they changed, then each record I changed.
local gatherGuildChanges = newGathering(GUILD_CHANGES_WAIT, function()
    if guildSettingsChanged then
        guildSettingsChanged = false
        sendGuildSettings()
    end
    sendChangedGuildRecords()
end)

local function queueGuildRecord(signedRecord)
    changedGuildRecords[signedRecord.id] = true
    gatherGuildChanges()
end

-- My guild's records catching up, by the guild master or an officer for every member, after a record of the guild or a
-- player's record changed, or the guild's members: a character that left the guild is unlinked
-- (GuildRecord.LinkedFormerMembers); a character two records link is unlinked from the older one
-- (GuildRecord.LinkedByNewer), which keeps its other characters; a guild identity whose characters players' own records
-- all hold goes (GuildRecord.ClaimedByPlayers). One with only some of them held waits for an officer's answer, in the
-- Guild tab.
local function tidyGuildRecords()
    if not Protocol.CanChangeGuildRecords() then return end
    local clubId = Identity.GuildId(UnitGUID("player"))
    local memberGuids = Scopes.GuildMemberGuids(clubId)
    if memberGuids then
        for id, guids in pairs(GuildRecord.LinkedFormerMembers(clubId, memberGuids)) do
            queueGuildRecord(GuildRecord.Unlink(clubId, id, guids))
        end
    end
    for id, guids in pairs(GuildRecord.LinkedByNewer(clubId)) do queueGuildRecord(GuildRecord.Unlink(clubId, id, guids)) end
    for id, claimed in pairs(GuildRecord.ClaimedByPlayers(clubId)) do
        local allClaimed = true
        for guid in pairs(GuildRecord.Held(clubId, id).chars) do allClaimed = allClaimed and claimed[guid] ~= nil end
        if allClaimed then queueGuildRecord(GuildRecord.Remove(clubId, id)) end
    end
end

---Sends a record of my guild I just signed (GuildRecord.Link, Unlink, SetMain, Rename, Remove) to its members, once
---the changes that follow have gathered.
---@param signedRecord WhosWho.SignedGuildRecord
function Protocol.SendGuildRecord(signedRecord)
    queueGuildRecord(signedRecord)
    tidyGuildRecords()
end

---Signs new settings for my current guild, from the character I play, and sends them to its members once the changes
---that follow have gathered. For the guild master and the officers.
---@param settings WhosWho.GuildSettingsValues
function Protocol.ChangeGuildSettings(settings)
    local ownCharacterGuid = UnitGUID("player")
    local clubId, rankIndex = Identity.GuildId(ownCharacterGuid), Scopes.GuildRankIndex(ownCharacterGuid)
    if not (clubId and rankIndex and rankIndex <= GuildSettings.LOWEST_RANK_INDEX) then return end
    local enabling = settings.enable and not GuildSettings.Get(clubId).enable
    GuildSettings.Change(clubId, settings, UnitGUID("player"), GetServerTime())
    if enabling then
        guildListsEnabledByMe = true
        GuildList.Renew(clubId, Identity.Ruleset(UnitGUID("player")), GetServerTime())
    end
    guildSettingsChanged = true
    gatherGuildChanges()
end

-- Guild lists ------------------------------------------------------------------------------------

---@type table<string, { at: integer, hash: string }> by name: the list revision each member of my guild last announced
local listOffers = {}
---@type table<string, true> hashes of the lists I took, and of mine: never asked for again this session
local takenListHashes = {}
---@type { name: string, sentAt: number }? my GLGET in flight
local listRequest
---@type table<string, true> members waiting for my list
local listRequesters = {}
---@type table<string, table<string, true>> by identity ID, then name: members asking me for an identity I hold
local relayRequesters = {}
---@type table<string, table<string, true>> by identity ID, then name: members asking me for a guild's record I hold
local guildRecordRequesters = {}
---@type table<string, true> IDs of my guild's records refused from members outside the trusted rank, for the session
local unvouchedGuildRecords = {}
---@type table<string, integer> by name: the members who took my list, with when I gave it to them (server time)
local listGivenTo = {}

-- Whether that member's rank in my roster lets it pass on identities I don't hold yet, and guild records whose signer I
-- haven't confirmed.
local function trustedMember(name)
    local guid = Scopes.SenderGuid(name)
    local rankIndex = guid and Scopes.GuildRankIndex(guid)
    return rankIndex ~= nil and rankIndex <= GuildList.TRUSTED_RANK_INDEX
end

-- The members who announced that list (the same hash, the same content), trusted ones only when asked.
---@return string[] names
local function listHolders(hash, trustedOnly)
    local names = {}
    for name, offer in pairs(listOffers) do
        if offer.hash == hash and Scopes.GuildReaches(name) and (not trustedOnly or trustedMember(name)) then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

-- The most recent list announced that I did not take yet, among trusted members only when asked.
---@return { at: integer, hash: string }?
local function newestOffer(trustedOnly)
    local newest
    for name, offer in pairs(listOffers) do
        if not takenListHashes[offer.hash] and Scopes.GuildReaches(name) and (not trustedOnly or trustedMember(name))
            and (not newest or GuildList.IsLater(offer.at, offer.hash, newest.at, newest.hash)) then
            newest = offer
        end
    end
    return newest
end

local function listRequestInFlight()
    return listRequest ~= nil and GetTime() - listRequest.sentAt < REQUEST_DELAY_SECONDS
end

-- One GLGET to one of the members holding that list, a trusted one if any: its list then also gives the identities I
-- don't hold.
local function requestGuildList(hash)
    local holders = listHolders(hash, true)
    if not holders[1] then holders = listHolders(hash) end
    local name = holders[fastrandom(1, #holders)]
    listRequest = { name = name, sentAt = GetTime() }
    sendQueued(Codec.GuildListRequest(), "WHISPER", name)
end

-- After the announcements that came together: the most recent list announced, when it is later than mine.
local function evaluateGuildLists()
    if not guildListsActive() or listRequestInFlight() then return end
    local _, at, hash = ownGuildList()
    takenListHashes[hash] = true
    local newest = newestOffer(false)
    if newest and GuildList.IsLater(newest.at, newest.hash, at, hash) then
        requestGuildList(newest.hash)
        return
    end

    -- A list changed after a member took mine: mine merged with more. My own list may have changed since I gave it, and
    -- be dated after theirs.
    for name, givenAt in pairs(listGivenTo) do
        local offer = listOffers[name]
        if offer and offer.at > givenAt and not takenListHashes[offer.hash] and Scopes.GuildReaches(name) then
            requestGuildList(offer.hash)
            return
        end
    end
end

local scheduleGuildListEvaluation = newGathering(ANNOUNCEMENT_WAIT, evaluateGuildLists)

-- My list renewed and announced to the guild, asking for none back, after a list I took lacked what its member would
-- take from mine: the members holding another list take mine. Renewed when it goes out, so that it holds what I asked
-- for meanwhile, and once for the lists taken close together.
local announceRenewedList = newGathering(ANNOUNCEMENT_WAIT, function()
    if not guildListsActive() then return end

    local ownCharacterGuid = UnitGUID("player")
    GuildList.Renew(Identity.GuildId(ownCharacterGuid), Identity.Ruleset(ownCharacterGuid), GetServerTime())
    local announcement = announcementText(UnitLevel("player"), true, false)
    if announcement then announceToGuild(announcement) end
end)

-- A member's list: the identities I hold at an older revision, from the members holding that list; the guild's records
-- I lack or hold older, from its trusted holders when any is online (theirs need no confirmed signer), otherwise from
-- any holder; the identities I don't hold, from its trusted holders only, otherwise from the most recent list a trusted
-- member announced. When it lacks what its member would take from mine, my list is announced back.
---@param update WhosWho.GuildListUpdate
local function takeGuildList(update)
    takenListHashes[update.hash] = true
    local held, unknown = GuildList.Missing(update.entries)
    local trusted = listHolders(update.hash, true)
    requestFromHolders(held, listHolders(update.hash), RECORDS)
    requestFromHolders(GuildList.MissingGuildRecords(update.guild, update.guildEntries),
        trusted[1] and trusted or listHolders(update.hash), GUILD_RECORDS)
    local ruleset = Identity.Ruleset(UnitGUID("player"))
    if GuildList.LacksFromMine(update.guild, ruleset, update, Protocol.CanChangeGuildRecords()) then
        announceRenewedList()
    end

    if not unknown[1] then return end
    if trusted[1] then
        requestFromHolders(unknown, trusted, RECORDS)
        return
    end
    local newest = newestOffer(true)
    if newest and not listRequestInFlight() then requestGuildList(newest.hash) end
end

-- The guild's records refused from members outside the trusted rank, from a member of that rank offering the guild's
-- list: theirs need no confirmed signer.
local function requestUnvouchedGuildRecords(name)
    if not (next(unvouchedGuildRecords) and guildListsActive() and trustedMember(name)) then return end

    local ids = {}
    for id in pairs(unvouchedGuildRecords) do ids[#ids + 1] = id end
    table.sort(ids)
    unvouchedGuildRecords = {}
    requestFromHolders(ids, { name }, GUILD_RECORDS)
end

-- My list, to the members who asked for it: one GLIST on GUILD for several, a whisper for one.
local function sendGuildList()
    local names = {}
    for name in pairs(listRequesters) do
        if Scopes.GuildReaches(name) then names[#names + 1] = name end
    end
    listRequesters = {}
    if not (names[1] and guildListsActive()) then return end

    local clubId, at, hash = ownGuildList()
    local message = Codec.GuildListUpdate(clubId, at, hash, GuildList.Entries(clubId, Identity.Ruleset(UnitGUID("player"))),
        GuildList.GuildRecordEntries(clubId))
    local givenAt = GetServerTime()
    for _, name in ipairs(names) do listGivenTo[name] = givenAt end
    if names[2] and Scopes.CanSendOnGuild() then
        sendQueued(message, "GUILD")
        return
    end
    for _, name in ipairs(names) do sendQueued(message, "WHISPER", name) end
end

-- Each record members asked me for, to its requesters: one message on GUILD for several, a whisper for one.
---@param asked table<string, table<string, true>> by identity ID, then name
---@param messageFor fun(id: string): string? the message carrying that record, nil when I don't pass it on
local function answerRelayed(asked, messageFor)
    for id, requesterNames in pairs(asked) do
        local names = {}
        for name in pairs(requesterNames) do
            if Scopes.GuildReaches(name) then names[#names + 1] = name end
        end
        local message = names[1] and messageFor(id)
        if message and names[2] and Scopes.CanSendOnGuild() then
            sendQueued(message, "GUILD")
        elseif message then
            for _, name in ipairs(names) do sendQueued(message, "WHISPER", name) end
        end
    end
end

-- The identities members asked me for, from my list (REC).
local function sendRelayedRecords()
    local asked = relayRequesters
    relayRequesters = {}
    if not guildListsActive() then return end

    local guid = UnitGUID("player")
    local entries = GuildList.Entries(Identity.GuildId(guid), Identity.Ruleset(guid))
    answerRelayed(asked, function(id)
        local person = People.Get(id)
        return entries[id] and person and person.signedRecord and Codec.RecordUpdate(person.signedRecord) or nil
    end)
end

-- My guild's records members asked me for (GIREC).
local function sendGuildRecords()
    local asked = guildRecordRequesters
    guildRecordRequesters = {}
    if not guildListsActive() then return end

    local clubId = Identity.GuildId(UnitGUID("player"))
    answerRelayed(asked, function(id)
        local signedRecord = GuildRecord.Held(clubId, id)
        return signedRecord and Codec.GuildRecordUpdate(signedRecord)
    end)
end

local answerListRequests = newGathering(REQUEST_WAIT, sendGuildList)
local answerRelayRequests = newGathering(REQUEST_WAIT, sendRelayedRecords)
local answerGuildRecordRequests = newGathering(REQUEST_WAIT, sendGuildRecords)

-- Receiving --------------------------------------------------------------------------------------

---@param announcement WhosWho.Announcement
local function receiveAnnouncement(announcement, sender)
    local id = announcement.id
    if id == Identity.Id() then return end

    -- My answer, whatever the character I play: what it sends, if anything, is decided when the answers go out.
    if announcement.wantsAnnouncement and Scopes.Allows(sender) then queueAnnouncement(sender) end
    if announcement.acceptsGet and Scopes.GuildMember(sender)
        and GuildSettings.IsWanted(Identity.GuildId(UnitGUID("player")), announcement.guildSettingsRev) then
        requestGuildSettings(sender, announcement.guildSettingsRev)
    end
    -- Kept even while my lists are off: the settings enabling them may arrive right after.
    if announcement.guildListAt and Scopes.GuildReaches(sender) then
        listOffers[sender] = { at = announcement.guildListAt, hash = announcement.guildListHash }
        scheduleGuildListEvaluation()
        requestUnvouchedGuildRecords(sender)
    end
    -- An anonymous character only updates the identities I hold, and asks nothing; without any linked character, it
    -- takes nothing.
    local sharing = Scopes.RecordReaches(sender)
    if not (sharing or (People.Get(id) and Identity.LinkedCount() > 0)) then return end

    local senderGuid = Scopes.SenderGuid(sender)
    if senderGuid then
        People.Confirm(id, senderGuid, announcement.level)
        Scopes.SetRelationships(senderGuid, sender)
    end

    if not announcement.acceptsGet then
        -- The owner left: a GET would get no answer, and my announcement would not reach them.
        recordRequests[id] = nil
        announcementRecipients[sender] = nil
    elseif sharing and People.IsWanted(id, announcement.rev) then
        requestRecord(id, sender)
    end
end

-- My identity, from its owner's requesters; another one I hold, from a member of my guild.
---@param request WhosWho.RecordRequest
local function receiveRecordRequest(request, sender)
    for _, id in ipairs(request.ids) do
        if id == Identity.Id() then
            if Scopes.RecordReaches(sender) and not reachedRecently(sender) then
                requesters[sender] = true
                scheduleRecordSending()
            end
        elseif guildListsActive() and Scopes.GuildReaches(sender) then
            relayRequesters[id] = relayRequesters[id] or {}
            relayRequesters[id][sender] = true
            answerRelayRequests()
        end
    end
end

-- Whether I share with that sender on that channel.
local function sharedChannel(distribution, sender)
    if distribution == "GUILD" then return Scopes.SharesWithGuild() end
    if distribution == "PARTY" or distribution == "RAID" then return Scopes.Get("group") end
    if distribution == "WHISPER" then return Scopes.Allows(sender) end
    return false
end

-- Whether the player sent its record from one of its own characters: the sender's name is one the record lists.
local function sentByOwner(signedRecord, sender)
    for _, character in pairs(signedRecord.chars) do
        if character.name == sender then return true end
    end
    return false
end

---@param recordUpdate WhosWho.RecordUpdate
local function receiveRecordUpdate(recordUpdate, distribution, sender)
    local signedRecord = recordUpdate.signedRecord
    if signedRecord.id == Identity.Id() then return end
    local fromMyGuild = distribution == "GUILD" or (distribution == "WHISPER" and Scopes.GuildReaches(sender))
    local wanted = People.IsNewer(signedRecord.id, signedRecord.rev) or People.ReplacesHeld(signedRecord, fromMyGuild)
    if not wanted then return end
    -- Relayed by a member of my guild: only with the player's consent; an identity I don't hold yet, only from a trusted
    -- member, and its characters are then listed by the guild.
    local fromGuild = false
    if not sentByOwner(signedRecord, sender) then
        local relayable = signedRecord.guild.consent or Record.HasGuildEntry(signedRecord)
        if not (guildListsActive() and relayable and Scopes.GuildReaches(sender)) then return end
        if not People.Get(signedRecord.id) then
            if not trustedMember(sender) then return end
            fromGuild = true
        end
    end
    -- An anonymous character stores a new identity only from the guild of one of my linked characters.
    if not (Scopes.RecordReaches(sender) or People.Get(signedRecord.id)
        or (distribution == "GUILD" and Scopes.LinkedCharacterInGuild())) then
        return
    end

    RecordVerification.Queue(signedRecord, Record, function(verified)
        -- My guild vouches for its members' characters, even after their NOID.
        local guildMembers = fromMyGuild and Scopes.GuildMembersIn(verified) or nil
        if People.Accept(verified, fromGuild, guildMembers) ~= "stale" then
            recordRequests[verified.id] = nil
            Scopes.KeepSentWhispers()
            Scopes.KeepGuildMembers(verified)
            tidyGuildRecords()
        end
    end)
end

-- A character declaring no identity leaves the shared identity holding it.
local function receiveNoIdentity(sender)
    local guid = Scopes.SenderGuid(sender)
    if guid and not Identity.Characters()[guid] then People.DeclaredNoIdentity(guid) end
end

-- A member of my current guild asking for its settings.
local function receiveGuildSettingsRequest(sender)
    local signedRecord = GuildSettings.Record(Identity.GuildId(UnitGUID("player")))
    if signedRecord and Scopes.GuildMember(sender) then
        sendQueued(Codec.GuildSettingsUpdate(signedRecord), "WHISPER", sender)
    end
end

-- Settings of my current guild, from any of its members: the signature and the signer's rank decide.
---@param update WhosWho.GuildSettingsUpdate
local function receiveGuildSettingsUpdate(update, sender)
    local signedRecord = update.signedRecord
    -- Right after joining, the game may not give my guild's club ID yet: the record then waits for it (acceptGuildSettings).
    local clubId = Identity.GuildId(UnitGUID("player"))
    if clubId and signedRecord.guild ~= clubId then return traceGuildSettings(signedRecord, "another guild") end
    if not GuildSettings.IsNewer(signedRecord) then return traceGuildSettings(signedRecord, "not newer") end
    traceGuildSettings(signedRecord, "checking its signature")
    RecordVerification.Queue(signedRecord, GuildSettings, function(verified) acceptGuildSettings(verified, sender) end)
end

-- A member of my current guild asking for my list of it.
local function receiveGuildListRequest(sender)
    if not (guildListsActive() and Scopes.GuildReaches(sender)) then return end
    listRequesters[sender] = true
    answerListRequests()
end

-- A member's list of my current guild, asked for by me or by another member: taken unless taken already or the same
-- as mine. One whose hash isn't that of its content is dropped: its hash would name another member's list.
---@param update WhosWho.GuildListUpdate
local function receiveGuildListUpdate(update, sender)
    local clubId, _, hash = ownGuildList()
    if update.guild ~= clubId then return end
    if GuildList.Hash(update.entries, update.guildEntries) ~= update.hash then return end
    listOffers[sender] = { at = update.at, hash = update.hash }
    if listRequest and listRequest.name == sender then listRequest = nil end
    if takenListHashes[update.hash] or update.hash == hash then return end
    takeGuildList(update)
end

-- A member of my current guild asking me for its records about these identities.
---@param request WhosWho.GuildRecordRequest
local function receiveGuildRecordRequest(request, sender)
    if not (guildListsActive() and Scopes.GuildReaches(sender)) then return end
    for _, id in ipairs(request.ids) do
        guildRecordRequesters[id] = guildRecordRequesters[id] or {}
        guildRecordRequesters[id][sender] = true
    end
    answerGuildRecordRequests()
end

-- A record of my current guild, from any of its members (PAYLOAD_SENDERS): the signature, the signer's rank, and the
-- signer confirmed or the sender trusted decide. One refused from a member outside the trusted rank is asked for again
-- from the first trusted member offering the guild's list.
---@param update WhosWho.GuildRecordUpdate
local function receiveGuildRecordUpdate(update, sender)
    local signedRecord = update.signedRecord
    if signedRecord.guild ~= Identity.GuildId(UnitGUID("player")) or not GuildRecord.IsNewer(signedRecord) then return end

    local fromTrustedMember = trustedMember(sender)
    RecordVerification.Queue(signedRecord, GuildRecord, function(verified)
        guildRecordRequests[verified.id] = nil
        local result = GuildRecord.Accept(verified, Scopes.GuildRankIndex(verified.signerGuid), fromTrustedMember)
        unvouchedGuildRecords[verified.id] = result == "refused" and not fromTrustedMember or nil
        if result == "accepted" then tidyGuildRecords() end
    end)
end

-- A player's HELLO: Who's Who is here. My answer joins the pending ones, as for an announcement that wants mine. A sender
-- with an older version gets my HELLO back, once a session: the players online before it answer with announcements,
-- which carry no version.
---@param hello WhosWho.Hello
local function receiveHello(hello, sender)
    if sender == ns.UnitWholeName("player") then return end
    if hello.version and (not newestVersion or isOlderVersion(newestVersion.version, hello.version)) then
        newestVersion = { version = hello.version, name = sender }
    end
    if hello.version and not updateSeen and isUpdate(hello.version) then
        updateSeen = true
        for _, listener in ipairs(updateListeners) do listener(hello.version, sender) end
    end
    if hello.version and isOlderVersion(hello.version, OWN_VERSION) and not helloAnswered[sender] then
        helloAnswered[sender] = true
        greeted[sender] = true
        sendQueued(Codec.Hello(OWN_VERSION), "WHISPER", sender)
    end
    if Scopes.Allows(sender) then queueAnnouncement(sender) end
end

-- Who may send me a payload, checked before it is unpacked (Codec.Decode): unpacking costs up to 41 ms per KB received.
-- A REC, from a channel I share on, so strangers cannot fill my saved data; my current guild's settings, from any of its
-- members, whatever I share with the guild (they hold no identity); a guild list or a guild's record, from a member of
-- my guild while I exchange lists.
local PAYLOAD_SENDERS = {
    REC = sharedChannel,
    GSET = function(_, sender) return Scopes.GuildMember(sender) end,
    GLIST = function(_, sender) return guildListsActive() and Scopes.GuildReaches(sender) end,
    GIREC = function(_, sender) return guildListsActive() and Scopes.GuildReaches(sender) end,
}

-- A message taken at arrival (receive), unpacked and handled.
local function handle(text, distribution, sender)
    local message = Codec.Decode(text)
    if not message then return end
    -- A member who joined the guild since my roster was read.
    if distribution == "GUILD" and not Scopes.ReceivedOnGuild(sender) and message.type == "ANNOUNCE" then
        C_GuildInfo.GuildRoster()
    end

    if message.type == "HELLO" then
        receiveHello(message, sender)
    elseif message.type == "ANNOUNCE" then
        receiveAnnouncement(message, sender)
    elseif message.type == "GET" then
        receiveRecordRequest(message, sender)
    elseif message.type == "REC" then
        receiveRecordUpdate(message, distribution, sender)
    elseif message.type == "NOID" then
        receiveNoIdentity(sender)
    elseif message.type == "GSGET" then
        receiveGuildSettingsRequest(sender)
    elseif message.type == "GSET" then
        receiveGuildSettingsUpdate(message, sender)
    elseif message.type == "GLGET" then
        receiveGuildListRequest(sender)
    elseif message.type == "GLIST" then
        receiveGuildListUpdate(message, sender)
    elseif message.type == "GIGET" then
        receiveGuildRecordRequest(message, sender)
    elseif message.type == "GIREC" then
        receiveGuildRecordUpdate(message, sender)
    end
end

---@class WhosWho.ReceivedMessage
---@field text string
---@field distribution string
---@field sender string
---@field messageType string

-- The messages taken at arrival, handled in that order, each in a coroutine, where a long hash yields along the way
-- (Crypto.Slice). In each frame, the messages up to the first payload (PAYLOAD_SENDERS): unpacking one takes up to tens
-- of ms, in one piece. None while I am in combat: they wait for its end.
---@type WhosWho.ReceivedMessage[]
local inbox = {}
---@type thread? handling inbox[1], paused in a hash
local handling

local inboxFrame = CreateFrame("Frame")
inboxFrame:Hide()
inboxFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
inboxFrame:SetScript("OnEvent", function()
    if inbox[1] then inboxFrame:Show() end
end)
inboxFrame:SetScript("OnUpdate", function()
    if UnitAffectingCombat("player") then
        inboxFrame:Hide()
        return
    end

    while inbox[1] do
        local received = inbox[1]
        handling = handling or coroutine.create(function()
            handle(received.text, received.distribution, received.sender)
        end)

        local success, err = coroutine.resume(handling)
        if not success then
            geterrorhandler()(err)
        elseif coroutine.status(handling) ~= "dead" then
            return
        end

        handling = nil
        table.remove(inbox, 1)
        if PAYLOAD_SENDERS[received.messageType] then break end
    end

    if not inbox[1] then inboxFrame:Hide() end
end)

-- Whether a payload is worth unpacking, from its header: a REC of an identity revision I would take (the one I hold
-- too: a copy from my guild may replace it), settings or a guild record of my current guild not older than the ones I
-- hold, a list of it whose hash I haven't taken and isn't mine. The content must match the header (Codec.Decode).
local PAYLOAD_WANTED = {
    ---@param header WhosWho.PayloadHeader
    REC = function(header)
        if header.id == Identity.Id() then return false end
        local held = People.Get(header.id)
        return People.IsNewer(header.id, header.rev)
            or (held ~= nil and held.signedRecord ~= nil and held.signedRecord.rev == header.rev)
    end,
    ---@param header WhosWho.PayloadHeader
    GSET = function(header)
        -- Right after joining, the game may not give my guild's club ID yet: the record then waits for it.
        local clubId = Identity.GuildId(UnitGUID("player"))
        if clubId and header.guild ~= clubId then return false end
        local held = GuildSettings.Record(header.guild)
        return not held or held.rev <= header.rev
    end,
    ---@param header WhosWho.PayloadHeader
    GLIST = function(header)
        local clubId, _, hash = ownGuildList()
        return header.guild == clubId and not takenListHashes[header.hash] and header.hash ~= hash
    end,
    ---@param header WhosWho.PayloadHeader
    GIREC = function(header)
        local clubId = Identity.GuildId(UnitGUID("player"))
        if header.guild ~= clubId then return false end
        local held = GuildRecord.Held(clubId, header.id)
        return not held or held.rev <= header.rev
    end,
}

local function receive(_, text, distribution, sender)
    if issecretvalue(text) or issecretvalue(sender) then return end
    Diagnostic.MessageReceived(text, distribution, sender)

    local messageType, header = Codec.Header(text)
    if not messageType then return end

    -- Without a linked character, I take nothing but announcements and my guild's settings, which hold no identity, and
    -- what a guild I opted in to sends; a character I unlinked still answers an announcement with NOID.
    local takenAnyway = messageType == "HELLO" or messageType == "ANNOUNCE" or messageType == "GSGET"
        or messageType == "GSET"
    if Identity.LinkedCount() == 0 and not Scopes.EnforcedGuild() and not takenAnyway then return end

    local allowedSender = PAYLOAD_SENDERS[messageType]
    if allowedSender and not allowedSender(distribution, sender) then
        return Diagnostic.Print(L["%s from %s not unpacked: not taken from that sender"]:format(messageType, sender))
    end
    local wanted = PAYLOAD_WANTED[messageType]
    if wanted and not wanted(header) then
        return Diagnostic.Print(L["%s from %s not unpacked: nothing I would take"]:format(messageType, sender))
    end

    inbox[#inbox + 1] = { text = text, distribution = distribution, sender = sender, messageType = messageType }
    inboxFrame:Show()
end

-- Scopes turned on and the sending lock ----------------------------------------------------------

-- Turning the Guild scope on makes a change of revision, whose announcement brings the guild's back (announceRevision).
-- Turning the Whispers scope on sends nothing: it applies to the players I whisper from then on.
---@param key "guild"|"friends"|"whispers"|"group"
local function announceScope(key)
    if key == "group" and Scopes.AnnouncesToGroup() and IsInGroup() then
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

-- Game events ------------------------------------------------------------------------------------

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

---Calls the listener once a session, at the first HELLO whose version is an update for mine: newer, and a release
---unless mine isn't one either.
---@param listener fun(version: string, name: string)
function Protocol.OnUpdateSeen(listener)
    updateListeners[#updateListeners + 1] = listener
end

---The newest add-on version a HELLO carried this session, and who sent it; nil before any.
---@return string? version
---@return string? name
function Protocol.NewestVersion()
    if newestVersion then return newestVersion.version, newestVersion.name end
end

---PLAYER_LOGIN, after the character refresh: registers the prefix, takes the current revision as announced, announces
---each change of revision and each scope turned on.
function Protocol.Start()
    Protocol:RegisterComm(PREFIX, receive)
    -- A change found at login reaches online players through the login announcement and their GETs.
    publishedRevision, publishedSharingWithGuild = Identity.Revision(), Scopes.SharesWithGuild()
    publishedBytes = Identity.RecordBytesWithoutRevision()
    Identity.OnRevisionChanged(function() scheduleRecordSending(Store.Advanced("revisionWaitSeconds")) end)
    Scopes.OnEnabled(scopeEnabled)
    Scopes.OnGuildMembersChanged(tidyGuildRecords)
    People.OnChanged(retryPendingGuildSettings)
    GuildSettings.OnChanged(function() scheduleGuildListEvaluation() end)
    anonymousAtLogin = not Identity.IsLinked(UnitGUID("player"))
    -- The login announcement already reaches a group or guild I am in, and my friends online.
    wasInGroup, wasInGuild = IsInGroup(), IsInGuild()
    friendGuids = guidsOf(Scopes.Friends())
end

---PLAYER_ENTERING_WORLD of a login or a /reload, after Protocol.Start: every player it reaches answers with their
---announcement. Nothing on a quick
---relog: the same character as the account's last logout, less than the quickRelogSeconds setting ago, announcing the revision
---my last announcement to every audience already carried.
function Protocol.AnnounceLogin()
    local guid, lastLogout = UnitGUID("player"), Identity.LastLogout()
    local quickRelog = lastLogout and lastLogout.guid == guid
        and time() - lastLogout.at < Store.Advanced("quickRelogSeconds")
    if quickRelog and Identity.AnnouncedRevision(guid) == Identity.LastBroadcastRevision() then return end
    announce(Scopes.LoginAudience(), UnitLevel("player"), true, true, sendAnnouncement)
    -- Sharing nothing with my guild, I still want its members' announcements: they carry its settings.
    if IsInGuild() and not Scopes.AnnouncesToGuild() then
        if Scopes.CanSendOnGuild() then
            greet("GUILD")
        else
            for _, name in ipairs(Scopes.OnlineGuildMembers()) do greet("WHISPER", name) end
        end
    end
end

---PLAYER_LEVEL_UP.
---@param level integer the new level
function Protocol.AnnounceLevel(level)
    announce(Scopes.BroadcastAudience(), level, true, false, sendAnnouncement)
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
    local recordOwed = next(requesters) ~= nil or recordSendingWaiting()
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

-- Whether my announcement to the guild I joined waits for its roster: my messages on GUILD reach no one until my next
-- login (Scopes.CanSendOnGuild), so it goes to each online member, which the roster gives.
local guildJoinAnnouncementPending = false

---PLAYER_GUILD_UPDATE for my character: on joining a guild, my announcement to it once its roster arrives, which every
---member answers with theirs.
function Protocol.GuildChanged()
    if wasInGuild == nil then return end
    local inGuild = IsInGuild()
    local joined = inGuild and not wasInGuild
    wasInGuild = inGuild
    if joined or not inGuild then
        listOffers, takenListHashes, listRequest, unvouchedGuildRecords, listGivenTo = {}, {}, nil, {}, {}
        greeted.GUILD = nil
    end
    -- A guild update while already in the guild keeps the announcement waiting.
    if joined then
        Scopes.GuildJoined()
        guildJoinAnnouncementPending = true
    elseif not inGuild then
        guildJoinAnnouncementPending = false
    end
end

---GUILD_ROSTER_UPDATE, after Scopes.GuildRosterChanged: guild settings held back until my guild's club ID is given and
---their signer is in my roster, and the announcement to the guild I joined, to each online member, once the roster
---gives the guild's club ID.
function Protocol.GuildRosterChanged()
    retryPendingGuildSettings()
    if not guildJoinAnnouncementPending or GetNumGuildMembers() == 0 then return end
    if Identity.GuildIdPending(UnitGUID("player")) then return end
    guildJoinAnnouncementPending = false
    -- My announcement when I share with the guild (NOID from a character I unlinked); otherwise my HELLO alone: its
    -- members still send theirs back.
    local announcement = Scopes.SharesWithGuild() and announcementText(UnitLevel("player"), true, true)
    for _, name in ipairs(Scopes.OnlineGuildMembers()) do
        if announcement then
            sendAnnouncement(announcement, "WHISPER", name)
        elseif not Scopes.AnnouncesToGuild() then
            greet("WHISPER", name)
        end
    end
end

---GROUP_ROSTER_UPDATE: on joining a group, my announcement to the group, which every member answers with theirs.
function Protocol.GroupRosterChanged()
    -- The roster can arrive during the loading screen, before PLAYER_LOGIN.
    if wasInGroup == nil then return end
    local inGroup = IsInGroup()
    local joined = inGroup and not wasInGroup
    -- Another group, or none: the next one is greeted again.
    if inGroup ~= wasInGroup then greeted.PARTY, greeted.RAID = nil, nil end
    wasInGroup = inGroup
    if not (joined and Scopes.AnnouncesToGroup()) then return end

    announceToChannel(Scopes.GroupChannel())
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
    if not (Scopes.Get("whispers") and Scopes.AnnouncementReaches(name)) then return end
    if Scopes.GuildReaches(name) or Scopes.GroupReaches(name) or Scopes.FriendReaches(name) then return end
    local message = announcementText(UnitLevel("player"), true, true)
    if not message then return end
    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    local last = announcements[name]
    local announcedRecently = last and GetTime() - last.sentAt < Store.Advanced("whisperAnnouncementSeconds")
    if announcedRecently and last.revision == revision then return end

    sendAnnouncement(message, "WHISPER", name)
    rememberAnnouncement(name, revision)
end
