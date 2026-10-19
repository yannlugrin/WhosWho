local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto = ns.Crypto

---@class WhosWho.Record
local Record = {}
ns.Record = Record

-- Format -----------------------------------------------------------------------------------------

-- Raised only for a field the versions before it must not ignore: they refuse the record. Version 1, up to 0.2.0, was
-- signed over a fixed list of fields.
Record.VERSION = 2
Record.MAX_CHARACTERS = 50
-- Larger numbers would lose digits once written into the signed bytes.
Record.MAX_REVISION = 2 ^ 31 - 1

---A self-declared identity, as stored and exchanged.
---@class WhosWho.IdentityRecord
---@field v integer format version
---@field id string public key, 64 hex characters
---@field rev integer
---@field nickname string? override of the main character's name
---@field main string? GUID of the main character, one of chars; nil without characters, or when a guild main stands in
---@field chars table<string, WhosWho.Character> by GUID
---@field guild WhosWho.GuildSharing

---What the owner allows within the guilds of their characters.
---@class WhosWho.GuildSharing
---@field consent boolean the record may be passed on to the members of those guilds: the owner's Guild scope

---An identity record with its signature.
---@class WhosWho.SignedIdentityRecord: WhosWho.IdentityRecord
---@field sig string signature, 128 hex characters

---@enum WhosWho.Ruleset
Record.RULESET = { Normal = 1, PvP = 2, RP = 3, Hardcore = 4 }

---What a record says about one character.
---@class WhosWho.Character
---@field name string "First Surname"
---@field ruleset WhosWho.Ruleset
---@field classID integer the game's class ID, as UnitClass returns it
---@field guild WhosWho.CharacterGuild? only in the record sent to the members of a guild that enforces linking

---What the record of a guild's members says about one of the owner's characters in that guild.
---@class WhosWho.CharacterGuild
---@field forced true? in the record only because the guild enforces linking
---@field main true? the character the guild shows the identity under, the main not being in the guild

-- Names ------------------------------------------------------------------------------------------

Record.MIN_NAME_LENGTH = 2
Record.MAX_NAME_LENGTH = 25

-- Control characters would corrupt saved data and records; "|" starts WoW escape sequences (colors, links).
Record.FORBIDDEN = "[%c|]"

---@alias WhosWho.NameErrorCode "short"|"long"|"invalid"

local function collapseSpaces(s)
    s = s:gsub("%s+", " ")
    return s:match("^ ?(.-) ?$")
end

---A name as it may appear in shared data: spaces trimmed and collapsed, no forbidden character, length checked.
---@param name string? nil stays nil: no name
---@return string? clean
---@return WhosWho.NameErrorCode? err when refused
function Record.CleanName(name)
    if name == nil then return nil end

    name = collapseSpaces(name)
    if name:find(Record.FORBIDDEN) then return nil, "invalid" end

    local length = strlenutf8(name)
    if length < Record.MIN_NAME_LENGTH then return nil, "short" end
    if length > Record.MAX_NAME_LENGTH then return nil, "long" end

    return name
end

-- Validation -------------------------------------------------------------------------------------

local function isHex(s, length)
    return type(s) == "string" and #s == length and not s:find("[^0-9a-f]")
end

---An identity ID: a public key, 64 lowercase hex characters.
---@param s any
---@return boolean
function Record.IsId(s)
    return isHex(s, 64)
end

---A signature: 128 lowercase hex characters.
---@param s any
---@return boolean
function Record.IsSignature(s)
    return isHex(s, 128)
end

---@param s any
---@return boolean
function Record.IsGuid(s)
    return type(s) == "string" and s:find("^Player%-%d+%-%x+$") ~= nil
end

---A name as a record holds it: already clean (Record.CleanName).
---@param s any
---@return boolean
function Record.IsName(s)
    return type(s) == "string" and Record.CleanName(s) == s
end

---An integer from 1 to Record.MAX_REVISION, the largest the signed bytes write exactly: a revision, a club ID.
---@param n any
---@return boolean
function Record.IsPositiveInteger(n)
    return type(n) == "number" and n >= 1 and n <= Record.MAX_REVISION and n % 1 == 0
end

---@param n any
---@return boolean
function Record.IsRuleset(n)
    for _, ruleset in pairs(Record.RULESET) do
        if n == ruleset then return true end
    end
    return false
end

---A class the game knows.
---@param n any
---@return boolean
function Record.IsClassID(n)
    return Record.IsPositiveInteger(n) and C_CreatureInfo.GetClassInfo(n) ~= nil
end

-- Absent, or a table of markers, each one this version knows true.
local function isCharacterGuild(guild)
    if guild == nil then return true end
    return type(guild) == "table" and next(guild) ~= nil
        and (guild.forced == nil or guild.forced == true) and (guild.main == nil or guild.main == true)
end

local function isCharacter(character)
    return type(character) == "table"
        and Record.IsName(character.name)
        and Record.IsRuleset(character.ruleset)
        and Record.IsClassID(character.classID)
        and isCharacterGuild(character.guild)
end

---Checks the structure only: the fields this version knows, and the limits of the signed bytes; fields a later version
---adds are kept. The signature is checked by Record.Verify.
---@param record any
---@return boolean ok
---@return string? err the first check that failed
function Record.Validate(record)
    if type(record) ~= "table" then return false, "not a table" end
    if record.v ~= Record.VERSION then return false, "version" end
    if not Record.IsId(record.id) then return false, "id" end
    if not Record.IsPositiveInteger(record.rev) then return false, "rev" end
    if record.nickname ~= nil and not Record.IsName(record.nickname) then return false, "nickname" end
    if record.sig ~= nil and not Record.IsSignature(record.sig) then return false, "sig" end
    if type(record.chars) ~= "table" then return false, "chars" end
    if type(record.guild) ~= "table" or type(record.guild.consent) ~= "boolean" then
        return false, "guild"
    end

    local count, guildMains = 0, 0
    for guid, character in pairs(record.chars) do
        if not Record.IsGuid(guid) then return false, "guid" end
        if not isCharacter(character) then return false, "character" end
        count = count + 1
        if character.guild and character.guild.main then guildMains = guildMains + 1 end
    end
    if count > Record.MAX_CHARACTERS then return false, "chars" end

    if guildMains > 1 then return false, "main" end
    if count == 0 then
        if record.main ~= nil then return false, "main" end
    elseif record.main == nil then
        -- The record of a guild's members without my main: its guild main stands for it.
        if guildMains == 0 then return false, "main" end
    elseif not record.chars[record.main] then
        return false, "main"
    end

    if not Record.Canonical(record) then return false, "limits" end
    return true
end

---Whether the record carries guild markers: it was sent to the members of a guild enforcing linking.
---@param record WhosWho.IdentityRecord
---@return boolean
function Record.HasGuildMarkers(record)
    for _, character in pairs(record.chars) do
        if character.guild then return true end
    end
    return false
end

---The character the record shows the identity under: its guild main when it has one, otherwise its main.
---@param record WhosWho.IdentityRecord
---@return string? guid
function Record.ShownMain(record)
    for guid, character in pairs(record.chars) do
        if character.guild and character.guild.main then return guid end
    end
    return record.main
end

-- Signature --------------------------------------------------------------------------------------

-- Limits of the signed bytes, checked while they are built, so that hashing them stays short (about 4.6 ms per KB in
-- game): each one at least twice what the largest legitimate record needs (Tests/Model-Test.lua builds it). A limit
-- raised later is refused by every older client.
Record.MAX_SIGNED_LENGTH = 32768
local MAX_KEYS = 1024
local MAX_DEPTH = 6
local MAX_STRING_LENGTH = 4096

-- Appends the value's bytes: strings with their length, integers, booleans, and tables with their entries sorted by
-- key bytes. False once a limit is passed or another kind of value is met.
---@param value any
---@param out { parts: string[], length: integer, keys: integer }
---@param depth integer
---@return boolean
local function encode(value, out, depth)
    local bytes
    local kind = type(value)
    if kind == "string" then
        if #value > MAX_STRING_LENGTH then return false end
        bytes = "s" .. #value .. ":" .. value
    elseif kind == "number" then
        if value % 1 ~= 0 or math.abs(value) > Record.MAX_REVISION then return false end
        bytes = ("i%d;"):format(value)
    elseif kind == "boolean" then
        bytes = value and "t" or "f"
    elseif kind == "table" then
        if depth > MAX_DEPTH then return false end
        local entries = {}
        for key, item in pairs(value) do
            out.keys = out.keys + 1
            local keyOut = { parts = {}, length = 0, keys = 0 }
            if out.keys > MAX_KEYS or type(key) == "table" or type(key) == "boolean"
                or not encode(key, keyOut, depth) then
                return false
            end
            entries[#entries + 1] = { key = table.concat(keyOut.parts), item = item }
        end
        table.sort(entries, function(a, b) return a.key < b.key end)
        out.parts[#out.parts + 1] = "{"
        out.length = out.length + 1
        for _, entry in ipairs(entries) do
            out.parts[#out.parts + 1] = entry.key
            out.length = out.length + #entry.key
            if out.length > Record.MAX_SIGNED_LENGTH or not encode(entry.item, out, depth + 1) then
                return false
            end
        end
        bytes = "}"
    else
        return false
    end
    out.parts[#out.parts + 1] = bytes
    out.length = out.length + #bytes
    return out.length <= Record.MAX_SIGNED_LENGTH
end

---The signed bytes of a record, whatever its kind: the prefix naming the kind, then every field but the signature and
---the ones left out, whatever their names. Nil when the record passes a limit or holds another kind of value than
---strings, integers, booleans and tables.
---@param prefix string
---@param record table
---@param leftOut table<string, true>? top-level fields left out besides the signature
---@return string?
function Record.SignedBytes(prefix, record, leftOut)
    local signed = {}
    for key, value in pairs(record) do
        if key ~= "sig" and not (leftOut and leftOut[key]) then signed[key] = value end
    end
    local out = { parts = { prefix }, length = #prefix, keys = 0 }
    if not encode(signed, out, 1) then return nil end
    return table.concat(out.parts)
end

local WITHOUT_REVISION = { rev = true }

---The signed bytes of an identity record.
---@param record WhosWho.IdentityRecord
---@return string? bytes nil past a limit
function Record.Canonical(record)
    return Record.SignedBytes("WWI", record)
end

---The signed bytes without the revision: equal for two records that say the same at different revisions.
---@param record WhosWho.IdentityRecord
---@return string? bytes nil past a limit
function Record.CanonicalWithoutRevision(record)
    return Record.SignedBytes("WWI", record, WITHOUT_REVISION)
end

---Sets record.sig.
---@param record WhosWho.IdentityRecord
---@param seedHex string private key, 64 hex characters
---@return WhosWho.SignedIdentityRecord signedRecord the same table, signed
function Record.Sign(record, seedHex)
    ---@cast record WhosWho.SignedIdentityRecord
    record.sig = Crypto.ToHex(Crypto.Ed25519.Sign(Record.Canonical(record), Crypto.FromHex(seedHex), Crypto.FromHex(record.id)))
    return record
end

---Slow (about 250 ms in game); call it from a coroutine with crypto slicing on.
---@param signedRecord WhosWho.SignedIdentityRecord
---@return boolean
function Record.Verify(signedRecord)
    if not Record.Validate(signedRecord) or not signedRecord.sig then return false end
    return Crypto.Ed25519.Verify(Record.Canonical(signedRecord), Crypto.FromHex(signedRecord.sig), Crypto.FromHex(signedRecord.id))
end
