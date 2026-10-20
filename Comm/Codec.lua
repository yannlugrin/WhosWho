local _, ns = ...
---@cast ns WhosWho.Namespace
local GuildRecord, GuildSettings, Record = ns.GuildRecord, ns.GuildSettings, ns.Record
local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate")

-- Message text: "<version> <type> <fields>". Hellos, announcements, GETs and GIGETs are plain text that fits in one
-- message; a REC, a GSET, a GLIST and a GIREC carry a header in clear, " : ", then their record or list serialized,
-- compressed and encoded for the add-on channel; NOID, GSGET and GLGET have no fields. Fields a later version adds after
-- the known ones, and header fields before the " : ", are ignored.

---@class WhosWho.Codec
local Codec = {}
ns.Codec = Codec

local VERSION = "2"

---Who's Who is here: nothing about an identity.
---@class WhosWho.Hello
---@field type "HELLO"
---@field version string? the sender's add-on version, "x.y.z" with an optional suffix; nil for a copy without one

---@class WhosWho.Announcement
---@field type "ANNOUNCE"
---@field id string identity ID
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
---@field guildEntries table<string, integer> revision by identity ID of the guild's records

---A request for what the guild says about some identities.
---@class WhosWho.GuildRecordRequest
---@field type "GIGET"
---@field ids string[] player or guild identity IDs, 1 to Codec.MAX_REQUESTED_IDS

---@class WhosWho.GuildRecordUpdate
---@field type "GIREC"
---@field signedRecord WhosWho.SignedGuildRecord structure validated, signature not verified

---What a REC, a GSET, a GLIST or a GIREC says in clear about its payload (Codec.Header), checked against it once
---unpacked.
---@class WhosWho.PayloadHeader
---@field id string? REC, GIREC: whose record
---@field rev integer? REC, GSET, GIREC: the record's revision
---@field guild integer? GSET, GLIST, GIREC: club ID
---@field at integer? GLIST: when the list last changed
---@field hash string? GLIST: the hash of its content

---@alias WhosWho.Message WhosWho.Hello|WhosWho.Announcement|WhosWho.RecordRequest|WhosWho.RecordUpdate|WhosWho.NoIdentity|WhosWho.GuildSettingsRequest|WhosWho.GuildSettingsUpdate|WhosWho.GuildListRequest|WhosWho.GuildListUpdate|WhosWho.GuildRecordRequest|WhosWho.GuildRecordUpdate

-- The identity IDs one GET reads: three fit in one message.
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

-- A message with a payload: its header in clear, " : ", then the value serialized, compressed and encoded.
local function payloadMessage(messageType, header, value)
    local payload = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(value)))
    return ("%s %s %s : %s"):format(VERSION, messageType, header, payload)
end

---@param version string the add-on version, "x.y.z" with an optional suffix, or "-" for a copy without one
---@return string
function Codec.Hello(version)
    return ("%s HELLO %s"):format(VERSION, version)
end

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

---@param ids string[] 1 to Codec.MAX_REQUESTED_IDS identity IDs
---@return string
function Codec.RecordRequest(ids)
    return ("%s GET %s"):format(VERSION, table.concat(ids, " "))
end

---@param signedRecord WhosWho.SignedIdentityRecord
---@return string
function Codec.RecordUpdate(signedRecord)
    return payloadMessage("REC", ("%s %d"):format(signedRecord.id, signedRecord.rev), signedRecord)
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
    return payloadMessage("GSET", ("%d %d"):format(signedRecord.guild, signedRecord.rev), signedRecord)
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
    return payloadMessage("GLIST", ("%d %d %s"):format(guild, at, hash), { entries = entries, guildEntries = guildEntries })
end

---@param ids string[] 1 to Codec.MAX_REQUESTED_IDS player or guild identity IDs
---@return string
function Codec.GuildRecordRequest(ids)
    return ("%s GIGET %s"):format(VERSION, table.concat(ids, " "))
end

---@param signedRecord WhosWho.SignedGuildRecord
---@return string
function Codec.GuildRecordUpdate(signedRecord)
    return payloadMessage("GIREC", ("%d %s %d"):format(signedRecord.guild, signedRecord.id, signedRecord.rev), signedRecord)
end

-- Decoding ---------------------------------------------------------------------------------------

local function revision(s)
    local n = tonumber(s)
    return n and n >= 1 and n <= Record.MAX_REVISION and n or nil
end

local function clubId(s)
    local n = tonumber(s)
    return n and n >= 1 and n % 1 == 0 and n or nil
end

-- A player's identity ID or a guild identity ID: what a guild record is about.
local function isGuildRecordId(id)
    return Record.IsId(id) or GuildRecord.IsGuildIdentityId(id)
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

local function decodeHello(fields)
    local version = fields:match("^(%S+)")
    return { type = "HELLO", version = version and version:match("^%d+%.%d+%.%d+") and version or nil }
end

local function decodeAnnouncement(fields)
    local id, rev, level, acceptsGet, wantsAnnouncement, guildListRev, guildSettingsRev =
        fields:match("^(%x+) (%d+) (%d%d?%d?) ([01]) ([01]) (%S+) (%d+)")
    if not (Record.IsId(id) and revision(rev) and tonumber(level) >= 1) then return nil end

    local validListRev, guildListAt, guildListHash = parseGuildListRev(guildListRev)
    if not validListRev then return nil end

    return {
        type = "ANNOUNCE", id = id, rev = revision(rev), level = tonumber(level),
        acceptsGet = acceptsGet == "1", wantsAnnouncement = wantsAnnouncement == "1",
        guildListAt = guildListAt, guildListHash = guildListHash, guildSettingsRev = revision(guildSettingsRev) or 0,
    }
end

-- The IDs a request names: tokens that aren't IDs this version knows are skipped, and at most MAX_REQUESTED_IDS are
-- read, so that a later version can name other kinds; nil without any.
local function requestedIds(fields, isId)
    local ids = {}
    for token in fields:gmatch("%S+") do
        if isId(token) then
            ids[#ids + 1] = token
            if #ids == Codec.MAX_REQUESTED_IDS then break end
        end
    end

    return ids[1] and ids or nil
end

local function decodeRecordRequest(fields)
    local ids = requestedIds(fields, Record.IsId)
    return ids and { type = "GET", ids = ids }
end

local function decodeGuildRecordRequest(fields)
    local ids = requestedIds(fields, isGuildRecordId)
    return ids and { type = "GIGET", ids = ids }
end

-- Fields a later version adds are ignored.
local function decodeNoIdentity()
    return { type = "NOID" }
end

-- Fields a later version adds are ignored.
local function decodeGuildSettingsRequest()
    return { type = "GSGET" }
end

-- Fields a later version adds are ignored.
local function decodeGuildListRequest()
    return { type = "GLGET" }
end

-- A payload no longer than maxLength, decoded, unpacked and deserialized; nil when it isn't.
local function unpackPayload(payload, maxLength)
    if #payload > maxLength then return nil end

    local compressed = LibDeflate:DecodeForWoWAddonChannel(payload)
    local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end

    local ok, value = LibSerialize:Deserialize(serialized)
    return ok and value or nil
end

---@param header WhosWho.PayloadHeader
local function decodeRecordUpdate(header, payload)
    local signedRecord = unpackPayload(payload, MAX_RECORD_PAYLOAD)
    if not (Record.Validate(signedRecord) and signedRecord.sig) then return nil end
    if signedRecord.id ~= header.id or signedRecord.rev ~= header.rev then return nil end

    return { type = "REC", signedRecord = signedRecord }
end

---@param header WhosWho.PayloadHeader
local function decodeGuildSettingsUpdate(header, payload)
    local signedRecord = unpackPayload(payload, MAX_RECORD_PAYLOAD)
    if not GuildSettings.Validate(signedRecord) then return nil end
    if signedRecord.guild ~= header.guild or signedRecord.rev ~= header.rev then return nil end

    return { type = "GSET", signedRecord = signedRecord }
end

-- The list's hash is checked against its content by Protocol, which hashes it spread over frames.
---@param header WhosWho.PayloadHeader
local function decodeGuildListUpdate(header, payload)
    local list = unpackPayload(payload, MAX_LIST_PAYLOAD)
    if not (type(list) == "table" and type(list.entries) == "table" and type(list.guildEntries) == "table") then
        return nil
    end

    local count = 0
    for id, rev in pairs(list.entries) do
        count = count + 1
        if not (Record.IsId(id) and revision(rev)) or count > MAX_LIST_ENTRIES then return nil end
    end
    for id, rev in pairs(list.guildEntries) do
        count = count + 1
        if not (isGuildRecordId(id) and revision(rev)) or count > MAX_LIST_ENTRIES then return nil end
    end

    return {
        type = "GLIST", guild = header.guild, at = header.at, hash = header.hash, entries = list.entries,
        guildEntries = list.guildEntries,
    }
end

---@param header WhosWho.PayloadHeader
local function decodeGuildRecordUpdate(header, payload)
    local signedRecord = unpackPayload(payload, MAX_RECORD_PAYLOAD)
    if not GuildRecord.Validate(signedRecord) then return nil end
    if signedRecord.guild ~= header.guild or signedRecord.id ~= header.id or signedRecord.rev ~= header.rev then
        return nil
    end

    return { type = "GIREC", signedRecord = signedRecord }
end

local PLAIN_DECODERS = {
    HELLO = decodeHello, ANNOUNCE = decodeAnnouncement, GET = decodeRecordRequest, NOID = decodeNoIdentity,
    GSGET = decodeGuildSettingsRequest, GLGET = decodeGuildListRequest, GIGET = decodeGuildRecordRequest,
}

-- The header of each type with a payload, from its fields before " : "; fields a later version adds after them are
-- ignored.
local HEADER_MATCHERS = {
    REC = function(fields)
        local id, rev = fields:match("^(%x+) (%d+)")
        return Record.IsId(id) and revision(rev) and { id = id, rev = revision(rev) } or nil
    end,
    GSET = function(fields)
        local guild, rev = fields:match("^(%d+) (%d+)")
        return clubId(guild) and revision(rev) and { guild = clubId(guild), rev = revision(rev) } or nil
    end,
    GLIST = function(fields)
        local guild, at, hash = fields:match("^(%d+) (%d+) (%x+)")
        return clubId(guild) and revision(at) and { guild = clubId(guild), at = revision(at), hash = hash } or nil
    end,
    GIREC = function(fields)
        local guild, id, rev = fields:match("^(%d+) (%S+) (%d+)")
        return clubId(guild) and isGuildRecordId(id) and revision(rev)
            and { guild = clubId(guild), id = id, rev = revision(rev) } or nil
    end,
}

local PAYLOAD_DECODERS = {
    REC = decodeRecordUpdate, GSET = decodeGuildSettingsUpdate, GLIST = decodeGuildListUpdate,
    GIREC = decodeGuildRecordUpdate,
}

-- A message's type and fields, the header and the payload apart for a type with a payload: nil for another version,
-- and for a payload message without its " : " or with a malformed header.
---@return string? messageType
---@return string|WhosWho.PayloadHeader|nil fieldsOrHeader
---@return string? payload
local function split(text)
    local version, messageType, fields = text:match("^(%d+) (%u+) ?(.*)$")
    if version ~= VERSION then return nil end

    local matchHeader = HEADER_MATCHERS[messageType]
    if not matchHeader then return messageType, fields end

    local headerFields, payload = fields:match("^(.-) : (.*)$")
    local header = headerFields and matchHeader(headerFields)
    if not header then return nil end

    return messageType, header, payload
end

---A message's type in this protocol version, and the header of a REC, a GSET, a GLIST or a GIREC, read without
---unpacking anything; nil for another version, or a malformed header.
---@param text string
---@return string? messageType
---@return WhosWho.PayloadHeader? header
function Codec.Header(text)
    local messageType, header = split(text)
    if not messageType then return nil end

    return messageType, HEADER_MATCHERS[messageType] and header or nil
end

---Unknown versions and types, malformed fields, and a payload that doesn't match its header give nil.
---@param text string
---@return WhosWho.Message?
function Codec.Decode(text)
    local messageType, fieldsOrHeader, payload = split(text)
    if not messageType then return nil end
    if PAYLOAD_DECODERS[messageType] then return PAYLOAD_DECODERS[messageType](fieldsOrHeader, payload) end

    local decode = PLAIN_DECODERS[messageType]
    return decode and decode(fieldsOrHeader)
end
