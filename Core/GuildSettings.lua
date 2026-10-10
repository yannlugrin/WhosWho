local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto, Identity, People, Record = ns.Crypto, ns.Identity, ns.People, ns.Record

-- A guild's settings, shared between its members as a record signed by its guild master or one of its officers.

---@class WhosWho.GuildSettings
local GuildSettings = {}
ns.GuildSettings = GuildSettings

GuildSettings.VERSION = 1
-- The guild master (rank index 0) and the officers (1) change the settings.
GuildSettings.LOWEST_RANK_INDEX = 1

---@class WhosWho.GuildSettingsValues
---@field enable boolean Who's Who enabled for the guild

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
local DEFAULTS = { enable = false }

-- Records ----------------------------------------------------------------------------------------

---@return table<integer, WhosWho.GuildSettingsRecord> by club ID
local function records()
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
    return clubId and records()[clubId] or nil
end

---The revision of the record I hold for that guild, 0 without one.
---@param clubId integer?
---@return integer
function GuildSettings.Revision(clubId)
    local record = GuildSettings.Record(clubId)
    return record and record.rev or 0
end

---That guild's settings: its record's, otherwise the defaults. Read only.
---@param clubId integer?
---@return WhosWho.GuildSettingsValues
function GuildSettings.Get(clubId)
    local record = GuildSettings.Record(clubId)
    return record and record.settings or DEFAULTS
end

-- Format -----------------------------------------------------------------------------------------

-- The signature covers these fields only, so a record holding any other key has been changed.
local RECORD_FIELDS = { v = true, guild = true, settings = true, signer = true, signerGuid = true, rev = true, sig = true }
local SETTINGS_FIELDS = { enable = true }

local function hasOnlyFields(t, fields)
    for key in pairs(t) do
        if not fields[key] then return false end
    end
    return true
end

local function isPositiveInteger(n)
    return type(n) == "number" and n >= 1 and n <= Record.MAX_REVISION and n % 1 == 0
end

---Checks the structure only; the signature is checked by GuildSettings.Verify.
---@param record any
---@return boolean
function GuildSettings.Validate(record)
    return type(record) == "table" and hasOnlyFields(record, RECORD_FIELDS)
        and record.v == GuildSettings.VERSION
        and isPositiveInteger(record.guild)
        and type(record.settings) == "table" and hasOnlyFields(record.settings, SETTINGS_FIELDS)
        and type(record.settings.enable) == "boolean"
        and Record.IsId(record.signer)
        and Record.IsGuid(record.signerGuid)
        and isPositiveInteger(record.rev)
        and Record.IsSignature(record.sig)
end

---The signed bytes: every field but the signature.
---@param record WhosWho.GuildSettingsRecord
---@return string
function GuildSettings.Canonical(record)
    return table.concat({
        "WWG" .. record.v, tostring(record.guild), record.settings.enable and "1" or "0", record.signer,
        record.signerGuid, tostring(record.rev),
    }, "\31")
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

---Signs a new record of that guild's settings with my identity, from that character, and holds it. Its revision is
---the server time, or one more than the record held when that is not later.
---@param clubId integer
---@param settings WhosWho.GuildSettingsValues
---@param signerGuid string the character I play
---@param serverTime integer GetServerTime()
---@return WhosWho.GuildSettingsRecord
function GuildSettings.Change(clubId, settings, signerGuid, serverTime)
    local record = {
        v = GuildSettings.VERSION, guild = clubId, settings = { enable = settings.enable }, signer = Identity.Id(),
        signerGuid = signerGuid, rev = math.max(serverTime, GuildSettings.Revision(clubId) + 1),
    }
    record.sig = Identity.Sign(GuildSettings.Canonical(record))
    records()[clubId] = record
    for _, listener in ipairs(changeListeners) do listener(clubId) end
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
    local held = records()[signedRecord.guild]
    return not held or GuildSettings.IsNewerThan(signedRecord, held)
end

-- Whether the record's signing character is a confirmed character of its signing identity; for my own identity, one of
-- my linked characters.
local function signerConfirmed(signedRecord)
    if signedRecord.signer == Identity.Id() then return Identity.IsLinked(signedRecord.signerGuid) end
    local person, character = People.Find(signedRecord.signerGuid)
    return person ~= nil and person.id == signedRecord.signer and character ~= nil and character.state == "confirmed"
end

---Holds a verified record that is newer, when its signer may change the settings: its signing character confirmed,
---and at a rank index up to GuildSettings.LOWEST_RANK_INDEX in my roster. "pending": the signing character is not
---confirmed yet, or not in my roster yet; the record may be accepted later.
---@param signedRecord WhosWho.GuildSettingsRecord signature verified
---@param signerRankIndex integer? the signing character's rank index in my roster, nil when it does not list it
---@return "accepted"|"stale"|"pending"|"refused"
function GuildSettings.Accept(signedRecord, signerRankIndex)
    if not GuildSettings.IsNewer(signedRecord) then return "stale" end
    if signerRankIndex and signerRankIndex > GuildSettings.LOWEST_RANK_INDEX then return "refused" end
    if not (signerRankIndex and signerConfirmed(signedRecord)) then return "pending" end
    records()[signedRecord.guild] = signedRecord
    for _, listener in ipairs(changeListeners) do listener(signedRecord.guild) end
    return "accepted"
end
