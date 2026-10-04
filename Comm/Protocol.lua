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
local SEND_WAIT_SECONDS = 5
local REACHED_DELAY_SECONDS = 30
local REQUEST_DELAY_SECONDS = 60
local RETRY_LIMIT = 1

local issecretvalue = issecretvalue or function() return false end

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
local locked, waiting = false, false
local sendRecords

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

-- Requesters left after any broadcast: the fewest messages reaching them all, a member channel reaching every requester
-- on it and one whisper to each requester left.
local function answerRequesters(recordUpdate)
    local names, reachedByGuild, reachedByGroup = {}, {}, {}
    for name in pairs(requesters) do
        if Scopes.Allows(name) then
            names[#names + 1] = name
            reachedByGuild[name] = Scopes.GuildReaches(name)
            reachedByGroup[name] = Scopes.GroupReaches(name)
        end
    end
    requesters = {}

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

    if bestChoice.guild then sendRecord(recordUpdate(), "GUILD") end
    if bestChoice.group then sendRecord(recordUpdate(), Scopes.GroupChannel()) end
    for _, name in ipairs(bestWhispered) do sendRecord(recordUpdate(), "WHISPER", name) end
end

local function scheduleRecordSending()
    if waiting then return end
    waiting = true
    C_Timer.After(SEND_WAIT_SECONDS, sendRecords)
end

function sendRecords()
    waiting = false
    if locked then
        scheduleRecordSending()
        return
    end

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
    end
    publishedRevision = Identity.Revision()

    answerRequesters(recordUpdate)
end

---Held while the player edits their identity: RECs wait until it is released.
function Protocol.LockRecordSending()
    locked = true
end

function Protocol.UnlockRecordSending()
    locked = false
end

-- Requesting a record ---------------------------------------------------------------------------

---@class WhosWho.Request
---@field sentAt number
---@field retries integer GETs sent again, REQUEST_DELAY_SECONDS apart, without an answer

---@type table<string, WhosWho.Request> by identity ID
local requests = {}

local function sendRequest(id, name)
    Protocol:SendCommMessage(PREFIX, Codec.RecordRequest(id), "WHISPER", name)
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
        -- The owner left: a GET would get no answer.
        requests[id] = nil
    elseif People.IsNewer(id, announcement.rev) and Scopes.Allows(sender) then
        requestRecord(id, sender)
    end
end

---@param request WhosWho.RecordRequest
local function receiveRecordRequest(request, sender)
    if request.id ~= Identity.Id() or reachedRecently(sender) then return end
    requesters[sender] = true
    scheduleRecordSending()
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
        if People.Accept(verified) ~= "stale" then requests[verified.id] = nil end
    end)
end

local function receive(_, text, distribution, sender)
    if issecretvalue(text) or issecretvalue(sender) then return end
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

-- Announcements ----------------------------------------------------------------------------------

local function announce(level, acceptsGet, send)
    local revision = Identity.AnnouncedRevision(UnitGUID("player"))
    if not revision then return end

    local message = Codec.Announcement(Identity.Id(), revision, level, acceptsGet)
    local audience = Scopes.BroadcastAudience()
    for _, channel in ipairs(audience.memberChannels) do send(message, channel) end
    for _, name in ipairs(audience.names) do send(message, "WHISPER", name) end
end

local function sendQueued(message, channel, name)
    Protocol:SendCommMessage(PREFIX, message, channel, name)
end

local function sendNow(message, channel, name)
    C_ChatInfo.SendAddonMessage(PREFIX, message, channel, name)
end

---PLAYER_LOGIN, after the character refresh: registers the prefix, takes the current revision as published, sends
---a REC after each change of revision.
function Protocol.Start()
    Protocol:RegisterComm(PREFIX, receive)
    -- A change found at login reaches online players through the login announcement and their GETs.
    publishedRevision, publishedWithCharacters = Identity.Revision(), Identity.Main() ~= nil
    Identity.OnRevisionChanged(scheduleRecordSending)
end

---PLAYER_LOGIN, after Protocol.Start.
function Protocol.AnnounceLogin()
    announce(UnitLevel("player"), true, sendQueued)
end

---PLAYER_LEVEL_UP.
---@param level integer the new level
function Protocol.AnnounceLevel(level)
    announce(level, true, sendQueued)
end

---PLAYER_LOGOUT: sent directly, since the throttled queue would not empty in time; a GET would get no answer.
function Protocol.AnnounceLogout()
    announce(UnitLevel("player"), false, sendNow)
end
