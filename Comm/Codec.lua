local _, ns = ...
---@cast ns WhosWho.Namespace
local Record = ns.Record
local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate")

-- Message text: "<version> <type> <fields>". Announcements and GETs are plain text that fits in one message; a REC
-- carries the record serialized, compressed and encoded for the add-on channel; NOID has no fields.

---@class WhosWho.Codec
local Codec = {}
ns.Codec = Codec

local VERSION = "1"

---@class WhosWho.Announcement
---@field type "ANNOUNCE"
---@field id string identity ID
---@field rev integer
---@field level integer the sending character's level
---@field acceptsGet boolean whether the sender answers a GET now
---@field wantsAnnouncement boolean whether the sender wants the receiver's announcement

---@class WhosWho.RecordRequest
---@field type "GET"
---@field id string identity ID

---@class WhosWho.RecordUpdate
---@field type "REC"
---@field signedRecord WhosWho.SignedIdentityRecord structure validated, signature not verified

---A character declaring that it belongs to no identity.
---@class WhosWho.NoIdentity
---@field type "NOID"

---@alias WhosWho.Message WhosWho.Announcement|WhosWho.RecordRequest|WhosWho.RecordUpdate|WhosWho.NoIdentity

-- Encoding ---------------------------------------------------------------------------------------

---@param id string
---@param rev integer
---@param level integer
---@param acceptsGet boolean
---@param wantsAnnouncement boolean
---@return string
function Codec.Announcement(id, rev, level, acceptsGet, wantsAnnouncement)
    -- The last field is the revision of the guild list I hold, 0 until guild lists exist.
    return ("%s ANNOUNCE %s %d %d %d %d 0"):format(VERSION, id, rev, level, acceptsGet and 1 or 0,
        wantsAnnouncement and 1 or 0)
end

---@param id string
---@return string
function Codec.RecordRequest(id)
    return ("%s GET %s"):format(VERSION, id)
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

-- Decoding ---------------------------------------------------------------------------------------

local function revision(s)
    local n = tonumber(s)
    return n and n >= 1 and n <= Record.MAX_REVISION and n or nil
end

-- The guild list revision: 0 for none, otherwise <server time>.<hash of the list>.
local function isGuildListRev(s)
    return s == "0" or s:match("^%d+%.%x+$") ~= nil
end

-- Fields a later version adds after the known ones are ignored.
local function decodeAnnouncement(fields)
    local id, rev, level, acceptsGet, wantsAnnouncement, guildListRev =
        fields:match("^(%x+) (%d+) (%d%d?%d?) ([01]) ([01]) (%S+)")
    if not (Record.IsId(id) and revision(rev) and tonumber(level) >= 1 and isGuildListRev(guildListRev)) then
        return nil
    end
    return {
        type = "ANNOUNCE", id = id, rev = revision(rev), level = tonumber(level),
        acceptsGet = acceptsGet == "1", wantsAnnouncement = wantsAnnouncement == "1",
    }
end

local function decodeRecordRequest(fields)
    if not Record.IsId(fields) then return nil end
    return { type = "GET", id = fields }
end

local function decodeRecordUpdate(fields)
    local compressed = LibDeflate:DecodeForWoWAddonChannel(fields)
    local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end
    local ok, signedRecord = LibSerialize:Deserialize(serialized)
    if not (ok and Record.Validate(signedRecord) and signedRecord.sig) then return nil end
    return { type = "REC", signedRecord = signedRecord }
end

-- Fields a later version adds are ignored.
local function decodeNoIdentity()
    return { type = "NOID" }
end

local DECODERS = {
    ANNOUNCE = decodeAnnouncement, GET = decodeRecordRequest, REC = decodeRecordUpdate, NOID = decodeNoIdentity,
}

---Unknown versions and types, and malformed fields, give nil.
---@param text string
---@return WhosWho.Message?
function Codec.Decode(text)
    local version, messageType, fields = text:match("^(%d+) (%u+) ?(.*)$")
    if version ~= VERSION then return nil end
    local decode = DECODERS[messageType]
    return decode and decode(fields)
end
