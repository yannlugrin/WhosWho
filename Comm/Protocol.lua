local _, ns = ...
---@cast ns WhosWho.Namespace
local Codec, Identity, People, RecordVerification, Scopes = ns.Codec, ns.Identity, ns.People, ns.RecordVerification, ns.Scopes

-- Announcements, record requests (GET) and records (REC) between clients.

---@class WhosWho.Protocol
---@field RegisterComm fun(self, prefix: string, method: function)
---@field SendCommMessage fun(self, prefix: string, text: string, distribution: string, target: string?, prio: string?, callbackFn: function?, callbackArg: any?)
local Protocol = {}
ns.Protocol = Protocol
LibStub("AceComm-3.0"):Embed(Protocol)

local PREFIX = "WhosWho"
local REVISION_WAIT_SECONDS = 15 -- wait before sending a new revision, gathering the changes that follow
local REQUEST_WAIT_SECONDS = 5 -- wait before answering GETs, gathering the GETs that follow
local MAX_WAIT_SECONDS = 300 -- longest wait from its start, however often it is pushed back
local LOCK_WAIT_SECONDS = 5 -- between two tries while record sending is locked
local REACHED_DELAY_SECONDS = 30 -- after a REC was sent, GETs from the players it reached are ignored
local REQUEST_DELAY_SECONDS = 60 -- between two GETs for the same identity, and before a GET is sent again if no REC was answered it
local RETRY_LIMIT = 1 -- GETs sent again when no REC answers
local ANNOUNCEMENT_WAIT_SECONDS = 5 -- before answering announcements, gathering the ones that follow

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

-- My announcement from the character I play, nil while it never was linked.
local function announcementText(level, acceptsGet, wantsAnnouncement)
    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    return revision and Codec.Announcement(Identity.Id(), revision, level, acceptsGet, wantsAnnouncement)
end

local function announce(level, acceptsGet, wantsAnnouncement, send)
    local message = announcementText(level, acceptsGet, wantsAnnouncement)
    if not message then return end

    local audience = Scopes.BroadcastAudience()
    for _, channel in ipairs(audience.memberChannels) do send(message, channel) end
    for _, name in ipairs(audience.names) do send(message, "WHISPER", name) end
end

local function sendQueued(message, channel, name)
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

-- Last revision sent to every audience this session, and whether that record had characters.
local publishedRevision, publishedWithCharacters
---@type table<string, true> names of the players who sent a GET for my identity
local requesters = {}
---@type table<string, WhosWho.Delivery> by channel (GUILD, PARTY, RAID) or by name (WHISPER)
local deliveries = {}
local locked = false
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

-- Requesters left after any broadcast, in the fewest messages.
local function answerRequesters(recordUpdate)
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

local function sendRecords()
    -- Pushed back by a later change or GET.
    if GetTime() < sendAt then
        C_Timer.After(sendAt - GetTime(), sendRecords)
        return
    end
    if locked then
        C_Timer.After(LOCK_WAIT_SECONDS, sendRecords)
        return
    end
    sendAt, waitStartedAt = nil, nil

    -- The REC text, built once for every REC this wait sends, and only when one goes out.
    local message
    local function recordUpdate()
        message = message or Codec.RecordUpdate(Identity.SignedRecord())
        return message
    end

    -- A change of revision goes to every audience; nothing goes out while no record ever had characters.
    local withCharacters = Identity.Main() ~= nil
    if Identity.Revision() ~= publishedRevision and (withCharacters or publishedWithCharacters) then
        local audience = Scopes.BroadcastAudience()
        for _, channel in ipairs(audience.memberChannels) do sendRecord(recordUpdate(), channel) end
        for _, name in ipairs(audience.names) do sendRecord(recordUpdate(), "WHISPER", name) end
        for name in pairs(requesters) do
            if Scopes.BroadcastReaches(audience, name) then requesters[name] = nil end
        end
        publishedWithCharacters = withCharacters
        announce(UnitLevel("player"), false, false, sendQueued)
    end
    publishedRevision = Identity.Revision()

    answerRequesters(recordUpdate)
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

---Held while the player edits their identity: RECs wait until it is released.
function Protocol.LockRecordSending()
    locked = true
end

function Protocol.UnlockRecordSending()
    locked = false
end

-- Answering announcements ---------------------------------------------------------------------------

---@type table<string, true> names of the players waiting for my announcement in answer to theirs
local announcementRecipients = {}
---@type table<string, integer> by name, the revision my last announcement to that player carried this session
local announcedRevisions = {}
local announcementWaiting = false

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
    for _, name in ipairs(names) do announcedRevisions[name] = revision end
end

-- One wait for every player waiting for my answer, from the first one.
local function queueAnnouncement(name)
    announcementRecipients[name] = true
    if announcementWaiting then return end
    announcementWaiting = true
    C_Timer.After(ANNOUNCEMENT_WAIT_SECONDS, sendAnnouncements)
end

-- Requesting a record ---------------------------------------------------------------------------

---@class WhosWho.Request
---@field sentAt number
---@field retries integer GETs sent again, REQUEST_DELAY_SECONDS apart, without an answer

---@type table<string, WhosWho.Request> by identity ID
local requests = {}

local function sendRequest(id, name)
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

    local guid = Scopes.SenderGuid(sender, distribution)
    if guid then
        People.Confirm(id, guid, announcement.level)
        Scopes.SetRelationships(guid, sender)
    end

    if not announcement.acceptsGet then
        -- The owner left: a GET would get no answer, and my announcement would not reach them.
        requests[id] = nil
        announcementRecipients[sender] = nil
    elseif People.IsNewer(id, announcement.rev) and Scopes.Allows(sender) then
        requestRecord(id, sender)
    end

    if announcement.wantsAnnouncement and Scopes.Allows(sender) then queueAnnouncement(sender) end
end

---@param request WhosWho.RecordRequest
local function receiveRecordRequest(request, sender)
    if request.id ~= Identity.Id() or reachedRecently(sender) then return end
    requesters[sender] = true
    scheduleRecordSending(REQUEST_WAIT_SECONDS)
end

-- A REC is used only from a channel I share on, so strangers cannot fill my saved data.
local function sharedChannel(distribution, sender)
    local scopes = ns.settings.scopes
    if distribution == "GUILD" then return scopes.guild end
    if distribution == "PARTY" or distribution == "RAID" then return scopes.group end
    if distribution == "WHISPER" then return Scopes.Allows(sender) end
    return false
end

---@param recordUpdate WhosWho.RecordUpdate
local function receiveRecordUpdate(recordUpdate, distribution, sender)
    local signedRecord = recordUpdate.signedRecord
    if signedRecord.id == Identity.Id() or not sharedChannel(distribution, sender) then return end
    if not People.IsNewer(signedRecord.id, signedRecord.rev) then return end

    RecordVerification.Queue(signedRecord, function(verified)
        if People.Accept(verified) ~= "stale" then
            requests[verified.id] = nil
            Scopes.KeepSentWhispers()
        end
    end)
end

local function receive(_, text, distribution, sender)
    if issecretvalue(text) or issecretvalue(sender) then return end
    traceReceived(text, distribution, sender)
    local message = Codec.Decode(text)
    if not message then return end

    if message.type == "ANNOUNCE" then
        receiveAnnouncement(message, distribution, sender)
    elseif message.type == "GET" then
        receiveRecordRequest(message, sender)
    elseif message.type == "REC" then
        receiveRecordUpdate(message, distribution, sender)
    end
end

-- Game events ----------------------------------------------------------------------------------

---@type boolean? nil until Protocol.Start
local wasInGroup

---PLAYER_LOGIN, after the character refresh: registers the prefix, takes the current revision as published, sends
---a REC after each change of revision.
function Protocol.Start()
    Protocol:RegisterComm(PREFIX, receive)
    -- A change found at login reaches online players through the login announcement and their GETs.
    publishedRevision, publishedWithCharacters = Identity.Revision(), Identity.Main() ~= nil
    Identity.OnRevisionChanged(function() scheduleRecordSending(REVISION_WAIT_SECONDS) end)
    -- The login announcement already reaches a group I am in.
    wasInGroup = IsInGroup()
end

---PLAYER_LOGIN, after Protocol.Start: every player it reaches answers with their announcement.
function Protocol.AnnounceLogin()
    announce(UnitLevel("player"), true, true, sendQueued)
end

---PLAYER_LEVEL_UP.
---@param level integer the new level
function Protocol.AnnounceLevel(level)
    announce(level, true, false, sendQueued)
end

---PLAYER_LOGOUT: sent directly, since the throttled queue would not empty in time; a GET would get no answer.
function Protocol.AnnounceLogout()
    announce(UnitLevel("player"), false, false, sendNow)
end

---GROUP_ROSTER_UPDATE: on joining a group, my announcement to the group, which every member answers with theirs.
function Protocol.GroupChanged()
    -- The roster can arrive during the loading screen, before PLAYER_LOGIN.
    if wasInGroup == nil then return end
    local inGroup = IsInGroup()
    local joined = inGroup and not wasInGroup
    wasInGroup = inGroup
    if not (joined and ns.settings.scopes.group) then return end

    local message = announcementText(UnitLevel("player"), true, true)
    if message then sendQueued(message, Scopes.GroupChannel()) end
end

---CHAT_MSG_WHISPER_INFORM, after Scopes.WhisperSent: my announcement to the player I whispered, once per revision this
---session, sent right away. The player answers with theirs if they allow me.
---@param name any
function Protocol.Whispered(name)
    if not name or issecretvalue(name) or name == ns.UnitWholeName("player") then return end
    if not (ns.settings.scopes.whispers and Scopes.Allows(name)) then return end
    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    if not revision or announcedRevisions[name] == revision then return end

    sendQueued(announcementText(UnitLevel("player"), true, true), "WHISPER", name)
    announcedRevisions[name] = revision
end
