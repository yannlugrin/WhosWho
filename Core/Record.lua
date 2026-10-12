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
local RECORD_FIELDS = { v = true, id = true, rev = true, nickname = true, main = true, chars = true, guild = true, sig = true }
local CHARACTER_FIELDS = { name = true, ruleset = true, classID = true, guild = true }
local CHARACTER_GUILD_FIELDS = { forced = true, main = true }
local GUILD_FIELDS = { consent = true }

local function hasOnlyFields(t, fields)
    for key in pairs(t) do
        if not fields[key] then return false end
    end
    return true
end

-- Absent, or at least one marker, each true.
local function isCharacterGuild(guild)
    if guild == nil then return true end
    return type(guild) == "table" and next(guild) ~= nil and hasOnlyFields(guild, CHARACTER_GUILD_FIELDS)
        and (guild.forced == nil or guild.forced == true) and (guild.main == nil or guild.main == true)
end

local function isCharacter(character)
    return type(character) == "table"
        and hasOnlyFields(character, CHARACTER_FIELDS)
        and isName(character.name)
        and isRuleset(character.ruleset)
        and isClassID(character.classID)
        and isCharacterGuild(character.guild)
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
    if record.sig ~= nil and not Record.IsSignature(record.sig) then return false, "sig" end
    if type(record.chars) ~= "table" then return false, "chars" end
    if type(record.guild) ~= "table" or not hasOnlyFields(record.guild, GUILD_FIELDS)
        or type(record.guild.consent) ~= "boolean" then
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

-- Control characters, which Record.FORBIDDEN keeps out of every field.
local SEP_FIELD, SEP_CHAR, SEP_PART = "\31", "\30", "\29"

-- Every field but the signature, the revision as given, characters sorted by GUID; a character's guild markers only when
-- it has some, so a record without them keeps the bytes it always had.
local function canonical(record, revision)
    local guids = {}
    for guid in pairs(record.chars) do guids[#guids + 1] = guid end
    table.sort(guids)

    local chars = {}
    for i, guid in ipairs(guids) do
        local character = record.chars[guid]
        local parts = { guid, character.name, character.ruleset, character.classID }
        local guild = character.guild
        if guild then parts[5] = (guild.forced and "f" or "") .. (guild.main and "m" or "") end
        chars[i] = table.concat(parts, SEP_PART)
    end

    return table.concat({
        "WW" .. record.v, record.id, revision, record.nickname or "", record.main or "",
        table.concat(chars, SEP_CHAR), record.guild.consent and "1" or "0",
    }, SEP_FIELD)
end

---The signed bytes.
---@param record WhosWho.IdentityRecord
---@return string
function Record.Canonical(record)
    return canonical(record, tostring(record.rev))
end

---The signed bytes without the revision: equal for two records that say the same at different revisions.
---@param record WhosWho.IdentityRecord
---@return string
function Record.CanonicalWithoutRevision(record)
    return canonical(record, "")
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
