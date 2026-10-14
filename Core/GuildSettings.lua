local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto, Identity, People, Record = ns.Crypto, ns.Identity, ns.People, ns.Record

-- A guild's settings, shared between its members as a record signed by its guild master or one of its officers.

---@class WhosWho.GuildSettings
local GuildSettings = {}
ns.GuildSettings = GuildSettings

-- Raised only for a field the versions before it must not ignore: they refuse the record. Version 1, up to 0.2.0, was
-- signed over a fixed list of fields.
GuildSettings.VERSION = 2
-- The guild master (rank index 0) and the officers (1) change the settings.
GuildSettings.LOWEST_RANK_INDEX = 1

---@class WhosWho.GuildSettingsValues
---@field enable boolean Who's Who enabled for the guild
---@field enforceLinking boolean members' characters in the guild known under their identity; only with enable

---A guild's settings as its members share them; data, kept as received.
---@class WhosWho.GuildSettingsRecord
---@field v integer GuildSettings.VERSION
---@field guild integer club ID
---@field settings WhosWho.GuildSettingsValues
---@field signer string identity ID of the member who signed it
---@field signerGuid string the character it was signed from
---@field rev integer server time when it was signed
---@field sig string signature over the other fields, 128 hex characters

---@type WhosWho.GuildSettingsValues
local DEFAULTS = { enable = false, enforceLinking = false }

-- Records ----------------------------------------------------------------------------------------

---A guild's settings as I hold them.
---@class WhosWho.HeldGuildSettings
---@field record WhosWho.GuildSettingsRecord the latest record accepted, as signed
---@field signerUnconfirmed true? the guild's first settings, taken before I could confirm their signer

---@return table<integer, WhosWho.HeldGuildSettings> by club ID
local function heldByGuild()
    return ns.data.guildSettings
end

---@type fun(clubId: integer)[]
local changeListeners = {}

---Calls the listener with the club ID each time a guild's record changes.
---@param listener fun(clubId: integer)
function GuildSettings.OnChanged(listener)
    changeListeners[#changeListeners + 1] = listener
end

---The record I hold for that guild.
---@param clubId integer?
---@return WhosWho.GuildSettingsRecord?
function GuildSettings.Record(clubId)
    local held = clubId and heldByGuild()[clubId]
    return held and held.record or nil
end

---The guilds I hold settings of.
---@return integer[] clubIds
function GuildSettings.HeldGuilds()
    local clubIds = {}
    for clubId in pairs(heldByGuild()) do clubIds[#clubIds + 1] = clubId end
    return clubIds
end

---The character I play joined that guild: the settings I held of it from before count as its first settings again.
---@param clubId integer
function GuildSettings.Joined(clubId)
    local held = heldByGuild()[clubId]
    if held then held.signerUnconfirmed = true end
end

---Whether I want that revision of a guild's settings a member announced: a later one than mine, or any other while mine
---is unconfirmed.
---@param clubId integer?
---@param rev integer 0 for none
---@return boolean
function GuildSettings.IsWanted(clubId, rev)
    local held = clubId and heldByGuild()[clubId]
    if not held then return rev > 0 end
    if held.signerUnconfirmed then return rev > 0 and rev ~= held.record.rev end
    return rev > held.record.rev
end

---The revision of the record I hold for that guild, 0 without one.
---@param clubId integer?
---@return integer
function GuildSettings.Revision(clubId)
    local record = GuildSettings.Record(clubId)
    return record and record.rev or 0
end

---Whether that guild enforces linking: its members' characters in it known under their identity, linked or not.
---@param clubId integer?
---@return boolean
function GuildSettings.EnforcesLinking(clubId)
    local settings = GuildSettings.Get(clubId)
    return settings.enable and settings.enforceLinking == true
end

---That guild's settings: its record's, otherwise the defaults. Read only.
---@param clubId integer?
---@return WhosWho.GuildSettingsValues
function GuildSettings.Get(clubId)
    local record = GuildSettings.Record(clubId)
    return record and record.settings or DEFAULTS
end

-- Format -----------------------------------------------------------------------------------------

local function isPositiveInteger(n)
    return type(n) == "number" and n >= 1 and n <= Record.MAX_REVISION and n % 1 == 0
end

---Checks the structure only: the fields this version knows, and the limits of the signed bytes; fields a later version
---adds are kept. The signature is checked by GuildSettings.Verify.
---@param record any
---@return boolean
function GuildSettings.Validate(record)
    return type(record) == "table"
        and record.v == GuildSettings.VERSION
        and isPositiveInteger(record.guild)
        and type(record.settings) == "table"
        and type(record.settings.enable) == "boolean"
        and type(record.settings.enforceLinking) == "boolean"
        and Record.IsId(record.signer)
        and Record.IsGuid(record.signerGuid)
        and isPositiveInteger(record.rev)
        and Record.IsSignature(record.sig)
        and GuildSettings.Canonical(record) ~= nil
end

---The signed bytes: every field but the signature, whatever its name (Record.SignedBytes).
---@param record WhosWho.GuildSettingsRecord
---@return string? bytes nil past a limit
function GuildSettings.Canonical(record)
    return Record.SignedBytes("WWG", record)
end

---Slow (about 250 ms in game); call it from a coroutine with Ed25519 slicing on.
---@param signedRecord WhosWho.GuildSettingsRecord
---@return boolean
function GuildSettings.Verify(signedRecord)
    if not GuildSettings.Validate(signedRecord) then return false end
    return Crypto.Ed25519.Verify(GuildSettings.Canonical(signedRecord), Crypto.FromHex(signedRecord.sig),
        Crypto.FromHex(signedRecord.signer))
end

-- Changes ----------------------------------------------------------------------------------------

-- The bytes of the record that guild's members get from me, without its revision.
local function guildRecordBytes(clubId, ruleset)
    return Identity.RecordBytesWithoutRevision(GuildSettings.EnforcesLinking(clubId) and clubId or nil, ruleset)
end

-- Holds a guild's record. When it turns enforced linking on or off and what that guild's members get from me changes,
-- a new revision.
local function hold(signedRecord, signerUnconfirmed)
    local clubId, ruleset = signedRecord.guild, Identity.Ruleset(UnitGUID("player"))
    local bytes, first = guildRecordBytes(clubId, ruleset), heldByGuild()[clubId] == nil
    heldByGuild()[clubId] = { record = signedRecord, signerUnconfirmed = signerUnconfirmed or nil }
    if guildRecordBytes(clubId, ruleset) ~= bytes then Identity.GuildContentChanged() end
    -- Nothing to answer once the guild no longer enforces linking.
    if not GuildSettings.EnforcesLinking(clubId) then Identity.SetEnforcedLinkingOptIn(clubId, nil) end
    -- The first settings I hold of my current guild, enforcing linking (I joined it, or came from 0.1.x): what I hold
    -- of its members came from outside it.
    if first and GuildSettings.EnforcesLinking(clubId) and Identity.GuildId(UnitGUID("player")) == clubId then
        People.MarkOutdated(clubId)
    end
    for _, listener in ipairs(changeListeners) do listener(clubId) end
end

---Signs a new record of that guild's settings with my identity, from that character, and holds it. Its revision is
---the server time, or one more than the record held when that is not later.
---@param clubId integer
---@param settings WhosWho.GuildSettingsValues
---@param signerGuid string the character I play
---@param serverTime integer GetServerTime()
---@return WhosWho.GuildSettingsRecord
function GuildSettings.Change(clubId, settings, signerGuid, serverTime)
    local record = {
        v = GuildSettings.VERSION, guild = clubId,
        settings = { enable = settings.enable, enforceLinking = settings.enforceLinking }, signer = Identity.Id(),
        signerGuid = signerGuid, rev = math.max(serverTime, GuildSettings.Revision(clubId) + 1),
    }
    record.sig = Identity.Sign(GuildSettings.Canonical(record))
    hold(record)
    return record
end

---Whether a record of a guild's settings wins over another one: a later revision, or the same one from a greater
---signer ID.
---@param signedRecord WhosWho.GuildSettingsRecord
---@param other WhosWho.GuildSettingsRecord
---@return boolean
function GuildSettings.IsNewerThan(signedRecord, other)
    if signedRecord.rev ~= other.rev then return signedRecord.rev > other.rev end
    return signedRecord.signer > other.signer
end

---Whether that record would replace the one I hold for its guild.
---@param signedRecord WhosWho.GuildSettingsRecord
---@return boolean
function GuildSettings.IsNewer(signedRecord)
    local held = heldByGuild()[signedRecord.guild]
    -- One held without its signer confirmed may give way to any confirmed one (GuildSettings.Accept).
    return not held or held.signerUnconfirmed == true or GuildSettings.IsNewerThan(signedRecord, held.record)
end

-- Whether the record's signing character is a confirmed character of its signing identity; for my own identity, one of
-- my linked characters.
local function signerConfirmed(signedRecord)
    if signedRecord.signer == Identity.Id() then return Identity.IsLinked(signedRecord.signerGuid) end
    local person, character = People.Find(signedRecord.signerGuid)
    return person ~= nil and person.id == signedRecord.signer and character ~= nil and character.state == "confirmed"
end

---Holds a verified record that is newer, when its signer may change the settings: its signing character confirmed,
---and at a rank index up to GuildSettings.LOWEST_RANK_INDEX in my roster. A guild's first settings (none held, or held
---unconfirmed), whose signer I can't confirm yet, are taken unconfirmed when their signer is at such a rank, or when a
---trusted member sent them (an officer, or who invited me), until a confirmed record replaces them whatever its revision.
---"pending": the signing character is not confirmed yet, or not in my roster yet; the record may be accepted later.
---@param signedRecord WhosWho.GuildSettingsRecord signature verified
---@param signerRankIndex integer? the signing character's rank index in my roster, nil when it does not list it
---@param sentByTrusted boolean sent by a member trusted for a guild's first settings
---@return "accepted"|"stale"|"pending"|"refused"
function GuildSettings.Accept(signedRecord, signerRankIndex, sentByTrusted)
    if not GuildSettings.IsNewer(signedRecord) then return "stale" end
    local signerOfficer = signerRankIndex ~= nil and signerRankIndex <= GuildSettings.LOWEST_RANK_INDEX
    if signerOfficer and signerConfirmed(signedRecord) then
        hold(signedRecord, false)
        return "accepted"
    end
    local held = heldByGuild()[signedRecord.guild]
    local first = not held or held.signerUnconfirmed == true
    if first and (signerOfficer or sentByTrusted) then
        if held and not GuildSettings.IsNewerThan(signedRecord, held.record) then return "stale" end
        hold(signedRecord, true)
        return "accepted"
    end
    if signerRankIndex and not signerOfficer then return "refused" end
    return "pending"
end
