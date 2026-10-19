local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto, People, Record = ns.Crypto, ns.People, ns.Record

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
---@field nickname string? read for a guild identity only
---@field main string? read for a guild identity only: GUID, one of chars; nil without characters
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

    -- A guild identity's own nickname and main; a shared identity has the player's.
    if guildIdentity then
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

---Slow (about 250 ms in game); call it from a coroutine, where it yields along the way (Crypto.Slice).
---@param signedRecord WhosWho.SignedGuildRecord
---@return boolean
function GuildRecord.Verify(signedRecord)
    if not GuildRecord.Validate(signedRecord) then return false end
    return Crypto.Ed25519.Verify(GuildRecord.Canonical(signedRecord), Crypto.FromHex(signedRecord.sig),
        Crypto.FromHex(signedRecord.signer))
end

-- Records ----------------------------------------------------------------------------------------

---@return table<integer, table<string, WhosWho.SignedGuildRecord>> by club ID, then identity ID
local function heldByGuild()
    return ns.data.guildRecords
end

---The record I hold of what that guild says about that identity.
---@param clubId integer
---@param id string
---@return WhosWho.SignedGuildRecord?
function GuildRecord.Held(clubId, id)
    local held = heldByGuild()[clubId]
    return held and held[id]
end

---Whether that record replaces the one I hold: a later revision, or the same one from a greater signer ID, so that
---every member keeps the same one.
---@param signedRecord WhosWho.SignedGuildRecord
---@return boolean
function GuildRecord.IsNewer(signedRecord)
    local held = GuildRecord.Held(signedRecord.guild, signedRecord.id)
    return not held or GuildRecord.IsNewerThan(signedRecord, held)
end

---Whether a record of a guild is more recent than another: a later revision, or the same one from a greater signer ID.
---@param signedRecord WhosWho.SignedGuildRecord
---@param other WhosWho.SignedGuildRecord
---@return boolean
function GuildRecord.IsNewerThan(signedRecord, other)
    if signedRecord.rev ~= other.rev then return signedRecord.rev > other.rev end
    return signedRecord.signer > other.signer
end

-- Holds a record, and applies its guild's records again to the people I hold.
local function hold(signedRecord)
    local held = heldByGuild()
    held[signedRecord.guild] = held[signedRecord.guild] or {}
    held[signedRecord.guild][signedRecord.id] = signedRecord
    People.ApplyGuild(signedRecord.guild)
end

---The characters each record of a guild lists that its roster no longer lists: they left the guild.
---@param clubId integer
---@param memberGuids table<string, true> the guild's roster
---@return table<string, string[]> guids by identity ID, only for the records listing some
function GuildRecord.LinkedFormerMembers(clubId, memberGuids)
    local linked = {}
    for id, signedRecord in pairs(heldByGuild()[clubId] or {}) do
        for guid in pairs(signedRecord.chars) do
            if not memberGuids[guid] then
                linked[id] = linked[id] or {}
                table.insert(linked[id], guid)
            end
        end
    end
    return linked
end

---The characters each record of a guild lists that a newer record of the guild lists too: the newer one has them.
---@param clubId integer
---@return table<string, string[]> guids by identity ID, only for the records listing some
function GuildRecord.LinkedByNewer(clubId)
    local records, linked = heldByGuild()[clubId] or {}, {}
    for id, signedRecord in pairs(records) do
        for guid in pairs(signedRecord.chars) do
            for otherId, other in pairs(records) do
                if otherId ~= id and other.chars[guid] and GuildRecord.IsNewerThan(other, signedRecord) then
                    linked[id] = linked[id] or {}
                    table.insert(linked[id], guid)
                    break
                end
            end
        end
    end
    return linked
end

---The characters each guild identity of a guild lists that a player's own record holds (the player's word wins):
---their GUIDs, with that player's identity ID.
---@param clubId integer
---@return table<string, table<string, string>> player identity ID by GUID, by guild identity ID; only the ones with some
function GuildRecord.ClaimedByPlayers(clubId)
    local claimed = {}
    for id, signedRecord in pairs(heldByGuild()[clubId] or {}) do
        if GuildRecord.IsGuildIdentityId(id) then
            for guid in pairs(signedRecord.chars) do
                local person, character = People.Find(guid)
                if person and person.signedRecord and character.state ~= "added" and character.state ~= "guild" then
                    claimed[id] = claimed[id] or {}
                    claimed[id][guid] = person.id
                end
            end
        end
    end
    return claimed
end

---At login: applies every guild's records again, so a person that disappeared since (forgotten, its characters taken
---by another record) comes back from its record.
function GuildRecord.ApplyHeld()
    for clubId in pairs(heldByGuild()) do People.ApplyGuild(clubId) end
end

---Holds a verified record that is newer, when its signer may write it: its signing character at a rank index up to
---GuildList.TRUSTED_RANK_INDEX in my roster, and confirmed under its identity unless a member of that rank sent me the
---record. Then applies it to the people I hold.
---@param signedRecord WhosWho.SignedGuildRecord signature verified
---@param signerRankIndex integer? the signing character's rank index in my roster, nil when it does not list it
---@param fromTrustedMember boolean? sent by a member at a rank index up to GuildList.TRUSTED_RANK_INDEX in my roster
---@return "accepted"|"stale"|"refused"
function GuildRecord.Accept(signedRecord, signerRankIndex, fromTrustedMember)
    if not GuildRecord.IsNewer(signedRecord) then return "stale" end
    if not (signerRankIndex and signerRankIndex <= ns.GuildList.TRUSTED_RANK_INDEX
        and (fromTrustedMember or People.IsConfirmedCharacter(signedRecord.signer, signedRecord.signerGuid))) then
        return "refused"
    end
    hold(signedRecord)
    return "accepted"
end

---None of my characters is in that guild any more: its records go (People.GuildLeft removes what they linked).
---@param clubId integer
function GuildRecord.ForgetGuild(clubId)
    heldByGuild()[clubId] = nil
end

-- Changes ----------------------------------------------------------------------------------------

-- A copy of a table and the tables it holds.
local function copy(t)
    local out = {}
    for key, value in pairs(t) do out[key] = type(value) == "table" and copy(value) or value end
    return out
end

-- Signs my change to what my guild says about one identity, from the character I play, holds it and applies it: the
-- record I hold, fields a later version added included, or a new one, changed by `change`. Its revision is the server
-- time, or one more than the record held when that is not later.
---@param clubId integer
---@param id string
---@param change fun(record: WhosWho.SignedGuildRecord)
---@return WhosWho.SignedGuildRecord
local function sign(clubId, id, change)
    local held = GuildRecord.Held(clubId, id)
    local record = held and copy(held) or { v = GuildRecord.VERSION, guild = clubId, id = id, chars = {} }
    change(record)
    record.signer, record.signerGuid = ns.Identity.Id(), UnitGUID("player")
    record.rev = math.max(GetServerTime(), held and held.rev + 1 or 0)
    record.sig = ns.Identity.Sign(GuildRecord.Canonical(record))
    hold(record)
    return record
end

---A new guild identity's ID, for the character it starts from.
---@param guid string
---@return string
function GuildRecord.NewGuildIdentityId(guid)
    local bytes = guid .. ns.Identity.Id() .. GetServerTime()
    return "G" .. Crypto.ToHex(Crypto.SHA512(bytes)):sub(1, 16)
end

---Links a character in my guild to an identity: a guild identity, its main when it has none (a new one), or a shared
---one. Signed by me, held and applied; Protocol.SendGuildRecord passes it on.
---@param clubId integer
---@param id string
---@param guid string
---@param character WhosWho.Character
---@return WhosWho.SignedGuildRecord
function GuildRecord.Link(clubId, id, guid, character)
    return sign(clubId, id, function(record)
        record.chars[guid] = { name = character.name, ruleset = character.ruleset, classID = character.classID }
        if GuildRecord.IsGuildIdentityId(id) and not record.main then record.main = guid end
    end)
end

---Whether GuildRecord.Unlink accepts that character: one the guild links, and not a guild identity's main while it
---has other characters.
---@param clubId integer
---@param id string
---@param guid string
---@return boolean
function GuildRecord.CanUnlink(clubId, id, guid)
    local held = GuildRecord.Held(clubId, id)
    if not (held and held.chars[guid]) then return false end
    return guid ~= held.main or next(held.chars, next(held.chars)) == nil
end

---Unlinks characters the guild links. A guild identity whose main leaves gets the first of its other characters by name;
---one without characters left is removed.
---@param clubId integer
---@param id string
---@param guids string[]
---@return WhosWho.SignedGuildRecord
function GuildRecord.Unlink(clubId, id, guids)
    return sign(clubId, id, function(record)
        for _, guid in ipairs(guids) do record.chars[guid] = nil end
        if not (record.main and record.chars[record.main]) then
            local main
            for guid, character in pairs(record.chars) do
                if not main or character.name < record.chars[main].name then main = guid end
            end
            record.main = GuildRecord.IsGuildIdentityId(id) and main or nil
        end
    end)
end

---Makes a character of a guild identity its main.
---@param clubId integer
---@param id string
---@param guid string
---@return WhosWho.SignedGuildRecord
function GuildRecord.SetMain(clubId, id, guid)
    return sign(clubId, id, function(record) record.main = guid end)
end

---Sets or removes a guild identity's nickname.
---@param clubId integer
---@param id string
---@param nickname string? already clean (Record.CleanName); nil removes it
---@return WhosWho.SignedGuildRecord
function GuildRecord.Rename(clubId, id, nickname)
    return sign(clubId, id, function(record) record.nickname = nickname end)
end

---Moves a guild identity's characters to a player's identity, for the guild: the guild's record about the player links
---them, and the guild identity is removed. Its characters the player's own record holds are left out: the player has
---them.
---@param clubId integer
---@param fromId string the guild identity
---@param toId string the player's identity ID
---@return WhosWho.SignedGuildRecord moved the guild's record about the player
---@return WhosWho.SignedGuildRecord removed the guild identity's
function GuildRecord.MoveTo(clubId, fromId, toId)
    local claimed = GuildRecord.ClaimedByPlayers(clubId)[fromId] or {}
    local fromChars = GuildRecord.Held(clubId, fromId).chars
    local moved = sign(clubId, toId, function(record)
        for guid, character in pairs(fromChars) do
            if not claimed[guid] then record.chars[guid] = copy(character) end
        end
    end)
    return moved, GuildRecord.Remove(clubId, fromId)
end

---Removes a guild identity: a record without characters, which every member applies by forgetting it.
---@param clubId integer
---@param id string
---@return WhosWho.SignedGuildRecord
function GuildRecord.Remove(clubId, id)
    return sign(clubId, id, function(record) record.chars, record.main, record.nickname = {}, nil, nil end)
end
