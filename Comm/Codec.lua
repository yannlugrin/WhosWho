local _, ns = ...
---@cast ns WhosWho.Namespace
local GuildRecord, GuildSettings, Record = ns.GuildRecord, ns.GuildSettings, ns.Record
local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate")

-- Message text: "<version> <type> <fields>". Announcements, GETs and GIGETs are plain text that fits in one message; a
-- REC, a GSET, a GLIST and a GIREC carry their record or list serialized, compressed and encoded for the add-on channel;
-- NOID, GSGET and GLGET have no fields.

---@class WhosWho.Codec
local Codec = {}
ns.Codec = Codec

local VERSION = "1"

---@class WhosWho.Announcement
---@field type "ANNOUNCE"
---@field id string? identity ID; nil for an empty announcement, from a character with nothing to share
---@field rev integer
---@field level integer the sending character's level
---@field acceptsGet boolean whether the sender answers a GET now
---@field wantsAnnouncement boolean whether the sender wants the receiver's announcement
---@field guildListAt integer? when the guild list the sender holds last changed (server time), nil for none
---@field guildListHash string? the hash of that list's content, nil for none
---@field guildSettingsRev integer the revision of the settings record the sender holds for its guild, 0 for none

---@class WhosWho.RecordRequest
---@field type "GET"
---@field ids string[] identity IDs, 1 to Codec.MAX_REQUESTED_IDS

---@class WhosWho.RecordUpdate
---@field type "REC"
---@field signedRecord WhosWho.SignedIdentityRecord structure validated, signature not verified

---A character declaring that it belongs to no identity.
---@class WhosWho.NoIdentity
---@field type "NOID"

---A request for the settings record of the guild the sender and the receiver are in.
---@class WhosWho.GuildSettingsRequest
---@field type "GSGET"

---@class WhosWho.GuildSettingsUpdate
---@field type "GSET"
---@field signedRecord WhosWho.GuildSettingsRecord structure validated, signature not verified

---A request for the guild list of the receiver, in the guild the sender and the receiver are in.
---@class WhosWho.GuildListRequest
---@field type "GLGET"

---A member's guild list.
---@class WhosWho.GuildListUpdate
---@field type "GLIST"
---@field guild integer club ID
---@field at integer when the list last changed (server time)
---@field hash string the hash of its content
---@field entries table<string, integer> revision by identity ID
---@field guildEntries table<string, integer> revision by identity ID of the guild's records; empty from 0.3.0

---A request for what the guild says about some identities.
---@class WhosWho.GuildRecordRequest
---@field type "GIGET"
---@field ids string[] player or guild identity IDs, 1 to Codec.MAX_REQUESTED_IDS

---@class WhosWho.GuildRecordUpdate
---@field type "GIREC"
---@field signedRecord WhosWho.SignedGuildRecord structure validated, signature not verified

---@alias WhosWho.Message WhosWho.Announcement|WhosWho.RecordRequest|WhosWho.RecordUpdate|WhosWho.NoIdentity|WhosWho.GuildSettingsRequest|WhosWho.GuildSettingsUpdate|WhosWho.GuildListRequest|WhosWho.GuildListUpdate|WhosWho.GuildRecordRequest|WhosWho.GuildRecordUpdate

-- The identity IDs one GET names: three fit in one message.
Codec.MAX_REQUESTED_IDS = 3
-- The identities and guild records one GLIST holds at most, together.
local MAX_LIST_ENTRIES = 2000
-- Encoded payload lengths, checked before unpacking: LibDeflate unpacks without limit, about 41 ms per KB received at
-- worst in game. The largest legitimate payloads: a REC of 50 characters, 2 470 bytes; a GSET, 232 bytes; a GLIST of
-- MAX_LIST_ENTRIES identities, 90 731 bytes. A record's follows its signed bytes (Record.MAX_SIGNED_LENGTH), so a record
-- they allow is never refused on the way: serialized, compressed and encoded, it stays within 0.5% of them, more for
-- incompressible content (measured: 28 905 signed bytes, 29 008 on the wire). A limit raised later is refused by every
-- older client.
local MAX_RECORD_PAYLOAD = Record.MAX_SIGNED_LENGTH + Record.MAX_SIGNED_LENGTH / 16
local MAX_LIST_PAYLOAD = 131072

-- Encoding ---------------------------------------------------------------------------------------

---@param id string
---@param rev integer
---@param level integer
---@param acceptsGet boolean
---@param wantsAnnouncement boolean
---@param guildListAt integer? nil without a guild list
---@param guildListHash string? nil without a guild list
---@param guildSettingsRev integer
---@return string
function Codec.Announcement(id, rev, level, acceptsGet, wantsAnnouncement, guildListAt, guildListHash, guildSettingsRev)
    local guildListRev = guildListAt and (guildListAt .. "." .. guildListHash) or "0"
    return ("%s ANNOUNCE %s %d %d %d %d %s %d"):format(VERSION, id, rev, level, acceptsGet and 1 or 0,
        wantsAnnouncement and 1 or 0, guildListRev, guildSettingsRev)
end

---An announcement from a character with no identity to share: it carries nothing, and only asks for the receivers'
---announcements. 0.1.x refuses it (no identity ID).
---@return string
function Codec.EmptyAnnouncement()
    return ("%s ANNOUNCE 0 0 0 0 1 0 0"):format(VERSION)
end

---@param ids string[] 1 to Codec.MAX_REQUESTED_IDS identity IDs
---@return string
function Codec.RecordRequest(ids)
    return ("%s GET %s"):format(VERSION, table.concat(ids, " "))
end

---@param signedRecord WhosWho.SignedIdentityRecord
---@return string
function Codec.RecordUpdate(signedRecord)
    local payload = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(signedRecord)))
    return ("%s REC %s"):format(VERSION, payload)
end

---@return string
function Codec.NoIdentity()
    return ("%s NOID"):format(VERSION)
end

---@return string
function Codec.GuildSettingsRequest()
    return ("%s GSGET"):format(VERSION)
end

---@param signedRecord WhosWho.GuildSettingsRecord
---@return string
function Codec.GuildSettingsUpdate(signedRecord)
    local payload = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(signedRecord)))
    return ("%s GSET %s"):format(VERSION, payload)
end

---@return string
function Codec.GuildListRequest()
    return ("%s GLGET"):format(VERSION)
end

---@param guild integer club ID
---@param at integer
---@param hash string
---@param entries table<string, integer>
---@param guildEntries table<string, integer>
---@return string
function Codec.GuildListUpdate(guild, at, hash, entries, guildEntries)
    local list = { guild = guild, at = at, hash = hash, entries = entries, guildEntries = guildEntries }
    local payload = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(list)))
    return ("%s GLIST %s"):format(VERSION, payload)
end

---@param ids string[] 1 to Codec.MAX_REQUESTED_IDS player or guild identity IDs
---@return string
function Codec.GuildRecordRequest(ids)
    return ("%s GIGET %s"):format(VERSION, table.concat(ids, " "))
end

---@param signedRecord WhosWho.SignedGuildRecord
---@return string
function Codec.GuildRecordUpdate(signedRecord)
    local payload = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(signedRecord)))
    return ("%s GIREC %s"):format(VERSION, payload)
end

-- Decoding ---------------------------------------------------------------------------------------

local function revision(s)
    local n = tonumber(s)
    return n and n >= 1 and n <= Record.MAX_REVISION and n or nil
end

-- The guild list revision: 0 for none, otherwise <server time>.<hash of the list>.
---@return boolean valid
---@return integer? at
---@return string? hash
local function parseGuildListRev(s)
    if s == "0" then return true, nil, nil end
    local at, hash = s:match("^(%d+)%.(%x+)$")
    if not at then return false, nil, nil end
    return true, tonumber(at), hash
end

-- Fields a later version adds after the known ones are ignored. The guild settings revision is missing from 0.1.0's.
local function decodeAnnouncement(fields)
    local id, rev, level, acceptsGet, wantsAnnouncement, guildListRev, guildSettingsRev =
        fields:match("^(%x+) (%d+) (%d%d?%d?) ([01]) ([01]) (%S+) ?(%d*)")
    if id == "0" then return { type = "ANNOUNCE", wantsAnnouncement = wantsAnnouncement == "1" } end
    if not (Record.IsId(id) and revision(rev) and tonumber(level) >= 1) then return nil end
    local validListRev, guildListAt, guildListHash = parseGuildListRev(guildListRev)
    if not validListRev then return nil end
    return {
        type = "ANNOUNCE", id = id, rev = revision(rev), level = tonumber(level),
        acceptsGet = acceptsGet == "1", wantsAnnouncement = wantsAnnouncement == "1",
        guildListAt = guildListAt, guildListHash = guildListHash, guildSettingsRev = revision(guildSettingsRev) or 0,
    }
end

-- 0.1.0 names one identity.
local function decodeRecordRequest(fields)
    local ids = {}
    for id in fields:gmatch("%S+") do
        if not Record.IsId(id) or #ids == Codec.MAX_REQUESTED_IDS then return nil end
        ids[#ids + 1] = id
    end
    if not ids[1] then return nil end
    return { type = "GET", ids = ids }
end

-- A payload no longer than maxLength, decoded, unpacked and deserialized; nil when it isn't.
local function unpackPayload(fields, maxLength)
    if #fields > maxLength then return nil end
    local compressed = LibDeflate:DecodeForWoWAddonChannel(fields)
    local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end
    local ok, value = LibSerialize:Deserialize(serialized)
    return ok and value or nil
end

local function decodeRecordUpdate(fields)
    local signedRecord = unpackPayload(fields, MAX_RECORD_PAYLOAD)
    if not (Record.Validate(signedRecord) and signedRecord.sig) then return nil end
    return { type = "REC", signedRecord = signedRecord }
end

-- Fields a later version adds are ignored.
local function decodeNoIdentity()
    return { type = "NOID" }
end

-- Fields a later version adds are ignored.
local function decodeGuildSettingsRequest()
    return { type = "GSGET" }
end

local function decodeGuildSettingsUpdate(fields)
    local signedRecord = unpackPayload(fields, MAX_RECORD_PAYLOAD)
    if not GuildSettings.Validate(signedRecord) then return nil end
    return { type = "GSET", signedRecord = signedRecord }
end

-- Fields a later version adds are ignored.
local function decodeGuildListRequest()
    return { type = "GLGET" }
end

-- A player's identity ID or a guild identity ID: what a guild record is about.
local function isGuildRecordId(id)
    return Record.IsId(id) or GuildRecord.IsGuildIdentityId(id)
end

local function decodeGuildListUpdate(fields)
    local list = unpackPayload(fields, MAX_LIST_PAYLOAD)
    if not (type(list) == "table" and type(list.guild) == "number" and revision(list.at)
        and type(list.hash) == "string" and list.hash:match("^%x+$") and type(list.entries) == "table") then
        return nil
    end
    -- A list from 0.3.0 has no guild records.
    local guildEntries = list.guildEntries or {}
    if type(guildEntries) ~= "table" then return nil end
    local count = 0
    for id, rev in pairs(list.entries) do
        count = count + 1
        if not (Record.IsId(id) and revision(rev)) or count > MAX_LIST_ENTRIES then return nil end
    end
    for id, rev in pairs(guildEntries) do
        count = count + 1
        if not (isGuildRecordId(id) and revision(rev)) or count > MAX_LIST_ENTRIES then return nil end
    end
    return {
        type = "GLIST", guild = list.guild, at = list.at, hash = list.hash, entries = list.entries,
        guildEntries = guildEntries,
    }
end

local function decodeGuildRecordRequest(fields)
    local ids = {}
    for id in fields:gmatch("%S+") do
        if not isGuildRecordId(id) or #ids == Codec.MAX_REQUESTED_IDS then return nil end
        ids[#ids + 1] = id
    end
    if not ids[1] then return nil end
    return { type = "GIGET", ids = ids }
end

local function decodeGuildRecordUpdate(fields)
    local signedRecord = unpackPayload(fields, MAX_RECORD_PAYLOAD)
    if not GuildRecord.Validate(signedRecord) then return nil end
    return { type = "GIREC", signedRecord = signedRecord }
end

local DECODERS = {
    ANNOUNCE = decodeAnnouncement, GET = decodeRecordRequest, REC = decodeRecordUpdate, NOID = decodeNoIdentity,
    GSGET = decodeGuildSettingsRequest, GSET = decodeGuildSettingsUpdate,
    GLGET = decodeGuildListRequest, GLIST = decodeGuildListUpdate,
    GIGET = decodeGuildRecordRequest, GIREC = decodeGuildRecordUpdate,
}

---The type of a message in this protocol version, read without its fields; nil for another version.
---@param text string
---@return string?
function Codec.Type(text)
    local version, messageType = text:match("^(%d+) (%u+)")
    return version == VERSION and messageType or nil
end

---Unknown versions and types, and malformed fields, give nil.
---@param text string
---@return WhosWho.Message?
function Codec.Decode(text)
    local version, messageType, fields = text:match("^(%d+) (%u+) ?(.*)$")
    if version ~= VERSION then return nil end
    local decode = DECODERS[messageType]
    return decode and decode(fields)
end
