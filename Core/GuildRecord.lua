local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto, Record = ns.Crypto, ns.Record

-- What a guild says about one person: the characters it links to them, signed by its guild master or one of its
-- officers.

---@class WhosWho.GuildRecord
local GuildRecord = {}
ns.GuildRecord = GuildRecord

-- Raised only for a field the versions before it must not ignore: they refuse the record.
GuildRecord.VERSION = 1

---What a guild says about one person, as stored and exchanged; it may hold fields a later version adds.
---@class WhosWho.SignedGuildRecord
---@field v integer GuildRecord.VERSION
---@field guild integer club ID
---@field id string the identity it is about: a player's identity ID, or a guild identity ID
---@field nickname string? guild identity only
---@field main string? guild identity only: GUID, one of chars; nil without characters
---@field chars table<string, WhosWho.Character> by GUID, the characters in the guild it links to that identity
---@field signer string identity ID of the member who signed it
---@field signerGuid string the character it was signed from
---@field rev integer server time when it was signed
---@field sig string signature, 128 hex characters

-- Format -----------------------------------------------------------------------------------------

---A guild identity ID: "G" and 16 lowercase hex characters.
---@param s any
---@return boolean
function GuildRecord.IsGuildIdentityId(s)
    return type(s) == "string" and #s == 17 and s:find("^G[0-9a-f]+$") ~= nil
end

local function isCharacter(character)
    return type(character) == "table" and Record.IsName(character.name) and Record.IsRuleset(character.ruleset)
        and Record.IsClassID(character.classID)
end

---Checks the structure only: the fields this version knows, and the limits of the signed bytes; fields a later version
---adds are kept. The signature is checked by GuildRecord.Verify.
---@param record any
---@return boolean ok
---@return string? err the first check that failed
function GuildRecord.Validate(record)
    if type(record) ~= "table" then return false, "not a table" end
    if record.v ~= GuildRecord.VERSION then return false, "version" end
    if not Record.IsPositiveInteger(record.guild) then return false, "guild" end
    local guildIdentity = GuildRecord.IsGuildIdentityId(record.id)
    if not (guildIdentity or Record.IsId(record.id)) then return false, "id" end
    if not (Record.IsId(record.signer) and Record.IsGuid(record.signerGuid)) then return false, "signer" end
    if not Record.IsPositiveInteger(record.rev) then return false, "rev" end
    if not Record.IsSignature(record.sig) then return false, "sig" end
    if type(record.chars) ~= "table" then return false, "chars" end

    local count = 0
    for guid, character in pairs(record.chars) do
        if not Record.IsGuid(guid) then return false, "guid" end
        if not isCharacter(character) then return false, "character" end
        count = count + 1
    end
    if count > Record.MAX_CHARACTERS then return false, "chars" end

    -- The player's own nickname and main apply to a shared identity.
    if not guildIdentity then
        if record.nickname ~= nil or record.main ~= nil then return false, "main" end
    else
        if record.nickname ~= nil and not Record.IsName(record.nickname) then return false, "nickname" end
        if count == 0 then
            if record.main ~= nil then return false, "main" end
        elseif not record.chars[record.main] then
            return false, "main"
        end
    end

    if not GuildRecord.Canonical(record) then return false, "limits" end
    return true
end

---The signed bytes: every field but the signature, whatever its name (Record.SignedBytes).
---@param record WhosWho.SignedGuildRecord
---@return string? bytes nil past a limit
function GuildRecord.Canonical(record)
    return Record.SignedBytes("WWGR", record)
end

---Slow (about 250 ms in game); call it from a coroutine with Ed25519 slicing on.
---@param signedRecord WhosWho.SignedGuildRecord
---@return boolean
function GuildRecord.Verify(signedRecord)
    if not GuildRecord.Validate(signedRecord) then return false end
    return Crypto.Ed25519.Verify(GuildRecord.Canonical(signedRecord), Crypto.FromHex(signedRecord.sig),
        Crypto.FromHex(signedRecord.signer))
end
