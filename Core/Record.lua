local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto = ns.Crypto

---@class WhosWho.Record
local Record = {}
ns.Record = Record

-- Format -----------------------------------------------------------------------------------------

Record.VERSION = 1
Record.MAX_CHARACTERS = 50
-- Larger numbers would lose digits once written into the signed bytes.
Record.MAX_REVISION = 2 ^ 31 - 1

---A self-declared identity, as stored and exchanged.
---@class WhosWho.IdentityRecord
---@field v integer format version
---@field id string public key, 64 hex characters
---@field rev integer
---@field nickname string? override of the main character's name
---@field main string? GUID of the main character, one of chars; nil when the player unlinked every character
---@field chars table<string, WhosWho.Character> by GUID

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

-- Names ------------------------------------------------------------------------------------------

Record.MIN_NAME_LENGTH = 2
Record.MAX_NAME_LENGTH = 25

-- Control characters would corrupt saved data and records; "|" starts WoW escape sequences (colors, links).
Record.FORBIDDEN = "[%c|]"

---@alias WhosWho.ErrorCode "short"|"long"|"invalid"

local function collapseSpaces(s)
    s = s:gsub("%s+", " ")
    return s:match("^ ?(.-) ?$")
end

---A name as it may appear in shared data: spaces trimmed and collapsed, no forbidden character, length checked.
---@param name string? nil stays nil: no name
---@return string? clean
---@return WhosWho.ErrorCode? err when refused
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

---@param s any
---@return boolean
function Record.IsGuid(s)
    return type(s) == "string" and s:find("^Player%-%d+%-%x+$") ~= nil
end

local function isName(s)
    return type(s) == "string" and Record.CleanName(s) == s
end

local function isPositiveInteger(n)
    return type(n) == "number" and n >= 1 and n % 1 == 0
end

local function isRevision(n)
    return isPositiveInteger(n) and n <= Record.MAX_REVISION
end

local function isRuleset(n)
    for _, ruleset in pairs(Record.RULESET) do
        if n == ruleset then return true end
    end
    return false
end

local function isClassID(n)
    return isPositiveInteger(n) and C_CreatureInfo.GetClassInfo(n) ~= nil
end

-- The signature covers these fields only, so a record holding any other key has been changed.
local RECORD_FIELDS = { v = true, id = true, rev = true, nickname = true, main = true, chars = true, sig = true }
local CHARACTER_FIELDS = { name = true, ruleset = true, classID = true }

local function hasOnlyFields(t, fields)
    for key in pairs(t) do
        if not fields[key] then return false end
    end
    return true
end

local function isCharacter(character)
    return type(character) == "table"
        and hasOnlyFields(character, CHARACTER_FIELDS)
        and isName(character.name)
        and isRuleset(character.ruleset)
        and isClassID(character.classID)
end

---Checks the structure only; the signature is checked by Record.Verify.
---@param record any
---@return boolean ok
---@return string? err the first check that failed
function Record.Validate(record)
    if type(record) ~= "table" then return false, "not a table" end
    if not hasOnlyFields(record, RECORD_FIELDS) then return false, "field" end
    if record.v ~= Record.VERSION then return false, "version" end
    if not Record.IsId(record.id) then return false, "id" end
    if not isRevision(record.rev) then return false, "rev" end
    if record.nickname ~= nil and not isName(record.nickname) then return false, "nickname" end
    if record.sig ~= nil and not isHex(record.sig, 128) then return false, "sig" end
    if type(record.chars) ~= "table" then return false, "chars" end

    local count = 0
    for guid, character in pairs(record.chars) do
        if not Record.IsGuid(guid) then return false, "guid" end
        if not isCharacter(character) then return false, "character" end
        count = count + 1
    end
    if count > Record.MAX_CHARACTERS then return false, "chars" end

    if count == 0 then
        if record.main ~= nil then return false, "main" end
    elseif not record.chars[record.main] then
        return false, "main"
    end

    return true
end

-- Signature --------------------------------------------------------------------------------------

-- Control characters, which Record.FORBIDDEN keeps out of every field.
local SEP_FIELD, SEP_CHAR, SEP_PART = "\31", "\30", "\29"

---The signed bytes: every field but the signature, characters sorted by GUID.
---@param record WhosWho.IdentityRecord
---@return string
function Record.Canonical(record)
    local guids = {}
    for guid in pairs(record.chars) do guids[#guids + 1] = guid end
    table.sort(guids)

    local chars = {}
    for i, guid in ipairs(guids) do
        local character = record.chars[guid]
        chars[i] = table.concat({ guid, character.name, character.ruleset, character.classID }, SEP_PART)
    end

    return table.concat({
        "WW" .. record.v, record.id, tostring(record.rev), record.nickname or "", record.main or "",
        table.concat(chars, SEP_CHAR),
    }, SEP_FIELD)
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

---Slow (about 250 ms in game); call it from a coroutine with Ed25519 slicing on.
---@param signedRecord WhosWho.SignedIdentityRecord
---@return boolean
function Record.Verify(signedRecord)
    if not Record.Validate(signedRecord) or not signedRecord.sig then return false end
    return Crypto.Ed25519.Verify(Record.Canonical(signedRecord), Crypto.FromHex(signedRecord.sig), Crypto.FromHex(signedRecord.id))
end
