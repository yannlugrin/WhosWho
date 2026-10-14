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
local REQUEST_WAIT_SECONDS = 5 -- wait before answering GETs, gathering the GETs that follow
local MAX_WAIT_SECONDS = 300 -- longest wait from its start, however often it is pushed back
local LOCK_WAIT_SECONDS = 5 -- between two tries while sending is locked
local REACHED_DELAY_SECONDS = 30 -- after a REC was sent, GETs from the players it reached are ignored
local REQUEST_DELAY_SECONDS = 60 -- between two GETs for the same identity, and before a GET is sent again if no REC was answered it
local RETRY_LIMIT = 1 -- GETs sent again when no REC answers
local ANNOUNCEMENT_WAIT_SECONDS = 5 -- before answering announcements, gathering the ones that follow
local GUILD_SETTINGS_WAIT_SECONDS = 5 -- before a change of the guild settings goes out, gathering the ones that follow
-- The delays a player may change are advanced settings (Store.Advanced).

local issecretvalue = issecretvalue or function() return false end

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

-- Announcements ----------------------------------------------------------------------------------

-- My announcement from the character I play, when it announces; otherwise NOID from a character I unlinked, nil from one
-- never linked.
local function announcementText(level, acceptsGet, wantsAnnouncement)
    local guid = UnitGUID("player")
    local revision = Identity.AnnouncedRevision(guid)
    if not revision then return Identity.IsRemoved(guid) and Codec.NoIdentity() or nil end
    local listAt, listHash
    if guildListsActive() then
        local _
        _, listAt, listHash = ownGuildList()
    end
    return Codec.Announcement(Identity.Id(), revision, level, acceptsGet, wantsAnnouncement, listAt, listHash,
        GuildSettings.Revision(Identity.GuildId(guid)))
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
---@type number? when the pending RECs go out (GetTime), nil while none is pending
local sendAt
---@type number? when the pending wait started (GetTime)
local waitStartedAt

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
-- everyone's. The others ask again at my next announcement.
local function answerRequesters(recordUpdate)
    local guildClubId, guildRuleset = Scopes.EnforcedGuild()
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
    answer(names)
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
        if channel == "GUILD" or not guildOnly then sendQueued(channel == "GUILD" and guildMessage or message, channel) end
    end
    for _, name in ipairs(audience.guildMembers) do sendQueued(guildMessage, "WHISPER", name) end
    if not guildOnly then
        for _, name in ipairs(audience.names) do sendQueued(message, "WHISPER", name) end
    end
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
        if friend.connected and Scopes.AnnouncementReaches(friend.name) and not Scopes.GuildReaches(friend.name)
            and not Scopes.GroupReaches(friend.name) then
            sendQueued(message, "WHISPER", friend.name)
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
---@type table<integer, true> revisions of guild settings I refused: never asked for again
local refusedGuildSettings = {}

-- One GSGET to a member who announced newer guild settings; another member announcing them gets none while it waits.
local function requestGuildSettings(name, rev)
    local request = guildSettingsRequest
    if refusedGuildSettings[rev] then return end
    -- One request at a time, but a member trusted for a guild's first settings is asked over one who isn't.
    local trusted = Scopes.TrustedForGuildSettings(name)
    if request and request.rev >= rev and GetTime() - request.sentAt < REQUEST_DELAY_SECONDS
        and (request.trusted or not trusted) then
        return
    end
    guildSettingsRequest = { rev = rev, sentAt = GetTime(), trusted = trusted }
    sendQueued(Codec.GuildSettingsRequest(), "WHISPER", name)
end

---@type WhosWho.GuildSettingsRecord? the newest verified record held back until its signing character is confirmed and
---in my roster, tried again as they change
local pendingGuildSettings
-- Whether a member trusted for a guild's first settings sent the record held back.
local pendingSentByTrusted = false

local function acceptGuildSettings(signedRecord, sentByTrusted)
    local result = GuildSettings.Accept(signedRecord, Scopes.GuildRankIndex(signedRecord.signerGuid), sentByTrusted)
    traceGuildSettings(signedRecord, result)
    if result == "accepted" then
        guildSettingsRequest = nil
    elseif result == "refused" then
        refusedGuildSettings[signedRecord.rev] = true
    elseif result == "pending"
        and not (pendingGuildSettings and GuildSettings.IsNewerThan(pendingGuildSettings, signedRecord)) then
        pendingGuildSettings, pendingSentByTrusted = signedRecord, sentByTrusted
    end
end

local function retryPendingGuildSettings()
    local signedRecord = pendingGuildSettings
    if not signedRecord then return end
    pendingGuildSettings = nil
    acceptGuildSettings(signedRecord, pendingSentByTrusted)
end

local guildSettingsWaiting = false
-- Whether the settings waiting to go out enabled Who's Who for the guild: my announcement follows them, so that the
-- members compare their lists with mine, and not each with every other.
local guildListsEnabledByMe = false

-- My current guild's settings, to its members.
local function sendGuildSettings()
    guildSettingsWaiting = false
    local announceList = guildListsEnabledByMe
    guildListsEnabledByMe = false
    local signedRecord = GuildSettings.Record(Identity.GuildId(UnitGUID("player")))
    if not (signedRecord and Scopes.Get("guild") and IsInGuild()) then return end
    sendToGuild(Codec.GuildSettingsUpdate(signedRecord))
    local announcement = announceList and signedRecord.settings.enable and announcementText(UnitLevel("player"), true, false)
    if announcement then sendToGuild(announcement) end
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
    if guildSettingsWaiting then return end
    guildSettingsWaiting = true
    C_Timer.After(GUILD_SETTINGS_WAIT_SECONDS, sendGuildSettings)
end

-- Guild lists ------------------------------------------------------------------------------------

---@type table<string, { at: integer, hash: string }> by name: the list revision each member of my guild last announced
local listOffers = {}
---@type table<string, true> hashes of the lists I took, and of mine: never asked for again this session
local takenListHashes = {}
---@type { name: string, sentAt: number }? my GLGET in flight
local listRequest
local listEvaluationWaiting = false
---@type table<string, true> members waiting for my list
local listRequesters = {}
local listAnswerWaiting = false
---@type table<string, table<string, true>> by identity ID, then name: members asking me for an identity I hold
local relayRequesters = {}
local relayAnswerWaiting = false
---@type table<string, table<string, true>> by identity ID, then name: members asking me for a guild's record I hold
local guildRecordRequesters = {}
local guildRecordAnswerWaiting = false

-- Whether that member's rank in my roster lets it pass on identities I don't hold yet.
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
    listEvaluationWaiting = false
    if not guildListsActive() or listRequestInFlight() then return end
    local _, at, hash = ownGuildList()
    takenListHashes[hash] = true
    local newest = newestOffer(false)
    if newest and GuildList.IsLater(newest.at, newest.hash, at, hash) then requestGuildList(newest.hash) end
end

local function scheduleGuildListEvaluation()
    if listEvaluationWaiting then return end
    listEvaluationWaiting = true
    C_Timer.After(ANNOUNCEMENT_WAIT_SECONDS, evaluateGuildLists)
end

-- A member's list: the identities I hold at an older revision, and the guild's records I lack or hold older, from the
-- members holding that list; the identities I don't hold, from its trusted holders only, otherwise from the most recent
-- list a trusted member announced.
---@param update WhosWho.GuildListUpdate
local function takeGuildList(update)
    takenListHashes[update.hash] = true
    local held, unknown = GuildList.Missing(update.entries)
    requestFromHolders(held, listHolders(update.hash), RECORDS)
    requestFromHolders(GuildList.MissingGuildRecords(update.guild, update.guildEntries), listHolders(update.hash),
        GUILD_RECORDS)
    if not unknown[1] then return end
    local trusted = listHolders(update.hash, true)
    if trusted[1] then
        requestFromHolders(unknown, trusted, RECORDS)
        return
    end
    local newest = newestOffer(true)
    if newest and not listRequestInFlight() then requestGuildList(newest.hash) end
end

-- My list, to the members who asked for it: one GLIST on GUILD for several, a whisper for one.
local function sendGuildList()
    listAnswerWaiting = false
    local names = {}
    for name in pairs(listRequesters) do
        if Scopes.GuildReaches(name) then names[#names + 1] = name end
    end
    listRequesters = {}
    if not (names[1] and guildListsActive()) then return end

    local clubId, at, hash = ownGuildList()
    local message = Codec.GuildListUpdate(clubId, at, hash, GuildList.Entries(clubId, Identity.Ruleset(UnitGUID("player"))),
        GuildList.GuildRecordEntries(clubId))
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
    relayAnswerWaiting = false
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
    guildRecordAnswerWaiting = false
    local asked = guildRecordRequesters
    guildRecordRequesters = {}
    if not guildListsActive() then return end

    local clubId = Identity.GuildId(UnitGUID("player"))
    answerRelayed(asked, function(id)
        local signedRecord = GuildRecord.Held(clubId, id)
        return signedRecord and Codec.GuildRecordUpdate(signedRecord)
    end)
end

-- Receiving --------------------------------------------------------------------------------------

---@param announcement WhosWho.Announcement
local function receiveAnnouncement(announcement, sender)
    local id = announcement.id
    -- Empty: a member with nothing to share wants mine, nothing more. My own comes back on GUILD.
    if not id then
        if announcement.wantsAnnouncement and sender ~= ns.UnitWholeName("player") and Scopes.Allows(sender) then
            queueAnnouncement(sender)
        end
        return
    end
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
                scheduleRecordSending(REQUEST_WAIT_SECONDS)
            end
        elseif guildListsActive() and Scopes.GuildReaches(sender) then
            relayRequesters[id] = relayRequesters[id] or {}
            relayRequesters[id][sender] = true
            if not relayAnswerWaiting then
                relayAnswerWaiting = true
                C_Timer.After(REQUEST_WAIT_SECONDS, sendRelayedRecords)
            end
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
        local relayable = signedRecord.guild.consent or Record.HasGuildMarkers(signedRecord)
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
    -- Right after joining, the game may not give my guild's club ID yet: the record is then kept under its own.
    local clubId = Identity.GuildId(UnitGUID("player"))
    if clubId and signedRecord.guild ~= clubId then return traceGuildSettings(signedRecord, "another guild") end
    if not GuildSettings.IsNewer(signedRecord) then return traceGuildSettings(signedRecord, "not newer") end
    traceGuildSettings(signedRecord, "checking its signature")
    local sentByTrusted = Scopes.TrustedForGuildSettings(sender)
    RecordVerification.Queue(signedRecord, GuildSettings, function(verified) acceptGuildSettings(verified, sentByTrusted) end)
end

-- A member of my current guild asking for my list of it.
local function receiveGuildListRequest(sender)
    if not (guildListsActive() and Scopes.GuildReaches(sender)) then return end
    listRequesters[sender] = true
    if listAnswerWaiting then return end
    listAnswerWaiting = true
    C_Timer.After(REQUEST_WAIT_SECONDS, sendGuildList)
end

-- A member's list of my current guild, asked for by me or by another member: taken unless taken already or the same
-- as mine.
---@param update WhosWho.GuildListUpdate
local function receiveGuildListUpdate(update, sender)
    local clubId, _, hash = ownGuildList()
    if update.guild ~= clubId then return end
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
    if guildRecordAnswerWaiting then return end
    guildRecordAnswerWaiting = true
    C_Timer.After(REQUEST_WAIT_SECONDS, sendGuildRecords)
end

-- A record of my current guild, from any of its members (PAYLOAD_SENDERS): the signature and the signer's rank decide.
---@param update WhosWho.GuildRecordUpdate
local function receiveGuildRecordUpdate(update)
    local signedRecord = update.signedRecord
    if signedRecord.guild ~= Identity.GuildId(UnitGUID("player")) or not GuildRecord.IsNewer(signedRecord) then return end
    RecordVerification.Queue(signedRecord, GuildRecord, function(verified)
        guildRecordRequests[verified.id] = nil
        GuildRecord.Accept(verified, Scopes.GuildRankIndex(verified.signerGuid))
    end)
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

local function receive(_, text, distribution, sender)
    if issecretvalue(text) or issecretvalue(sender) then return end
    Diagnostic.MessageReceived(text, distribution, sender)
    local messageType = Codec.Type(text)
    if not messageType then return end
    -- Without a linked character, I take nothing but announcements and my guild's settings, which hold no identity, and
    -- what a guild I opted in to sends; a character I unlinked still answers an announcement with NOID.
    local takenAnyway = messageType == "ANNOUNCE" or messageType == "GSGET" or messageType == "GSET"
    if Identity.LinkedCount() == 0 and not Scopes.EnforcedGuild() and not takenAnyway then return end
    local allowedSender = PAYLOAD_SENDERS[messageType]
    if allowedSender and not allowedSender(distribution, sender) then
        return Diagnostic.Print(L["%s from %s not unpacked: not taken from that sender"]:format(messageType, sender))
    end
    local message = Codec.Decode(text)
    if not message then return end
    -- A member who joined the guild since my roster was read.
    if distribution == "GUILD" and not Scopes.ReceivedOnGuild(sender) and message.type == "ANNOUNCE" then
        C_GuildInfo.GuildRoster()
    end

    if message.type == "ANNOUNCE" then
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
        receiveGuildRecordUpdate(message)
    end
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

---PLAYER_LOGIN, after the character refresh: registers the prefix, takes the current revision as announced, announces
---each change of revision and each scope turned on.
function Protocol.Start()
    Protocol:RegisterComm(PREFIX, receive)
    -- A change found at login reaches online players through the login announcement and their GETs.
    publishedRevision, publishedSharingWithGuild = Identity.Revision(), Scopes.SharesWithGuild()
    publishedBytes = Identity.RecordBytesWithoutRevision()
    Identity.OnRevisionChanged(function() scheduleRecordSending(Store.Advanced("revisionWaitSeconds")) end)
    Scopes.OnEnabled(scopeEnabled)
    People.OnChanged(retryPendingGuildSettings)
    GuildSettings.OnChanged(scheduleGuildListEvaluation)
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
    announce(Scopes.LoginAudience(), UnitLevel("player"), true, true, sendQueued)
    -- Sharing nothing with my guild, I still want its members' announcements: they carry its settings.
    if IsInGuild() and not Scopes.AnnouncesToGuild() then sendToGuild(Codec.EmptyAnnouncement()) end
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
    if joined or not inGuild then listOffers, takenListHashes, listRequest = {}, {}, nil end
    -- A guild update while already in the guild keeps the announcement waiting.
    if joined then
        Scopes.GuildJoined()
        guildJoinAnnouncementPending = true
    elseif not inGuild then
        guildJoinAnnouncementPending = false
    end
end

---GUILD_ROSTER_UPDATE, after Scopes.GuildRosterChanged: guild settings held back until their signer is in my roster,
---and the announcement to the guild I joined, to each online member, once the roster gives the guild's club ID.
function Protocol.GuildRosterChanged()
    retryPendingGuildSettings()
    if not guildJoinAnnouncementPending or GetNumGuildMembers() == 0 then return end
    if Identity.GuildIdPending(UnitGUID("player")) then return end
    guildJoinAnnouncementPending = false
    -- My announcement when I share with the guild (NOID from a character I unlinked).
    local announcement = Scopes.SharesWithGuild() and announcementText(UnitLevel("player"), true, true)
    -- When my identity doesn't reach the guild that way, an empty announcement: its members still send theirs back.
    local emptyAnnouncement = not Scopes.AnnouncesToGuild() and Codec.EmptyAnnouncement()
    for _, name in ipairs(Scopes.OnlineGuildMembers()) do
        if announcement then sendQueued(announcement, "WHISPER", name) end
        if emptyAnnouncement then sendQueued(emptyAnnouncement, "WHISPER", name) end
    end
end

---GROUP_ROSTER_UPDATE: on joining a group, my announcement to the group, which every member answers with theirs.
function Protocol.GroupRosterChanged()
    -- The roster can arrive during the loading screen, before PLAYER_LOGIN.
    if wasInGroup == nil then return end
    local inGroup = IsInGroup()
    local joined = inGroup and not wasInGroup
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

    sendQueued(message, "WHISPER", name)
    rememberAnnouncement(name, revision)
end
