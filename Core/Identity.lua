local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto = ns.Crypto

---@class WhosWho.Identity
local Identity = {}
ns.Identity = Identity

-- Data -------------------------------------------------------------------------------------------

---Saved as ns.data.identity.
---@class WhosWho.IdentityData
---@field id string? public key, 64 hex characters
---@field seed string? private key, 64 hex characters
---@field rev integer
---@field nickname string? override; the main character's name is shown otherwise
---@field main string? GUID of the main character, always a linked one
---@field chars table<string, WhosWho.OwnCharacter> by GUID
---@field sig string? signature of the current revision

---@class WhosWho.OwnCharacter: WhosWho.Character
---@field linked boolean? nil until the character is registered in the identity, linked or not
---@field level integer at the end of the last session
---@field lastSeen number seconds, from time(): end of the last session (or its start, after a crash)
---@field guild integer? club ID of the character's guild (C_Club.GetGuildClubId)
---@field removedInRevision integer? unlinked: the first revision without it, which it announces

---@return WhosWho.IdentityData
local function data()
    return ns.data.identity
end

---@type fun()[]
local revisionListeners = {}

local function nextRevision()
    local identity = data()
    identity.rev = identity.rev + 1
    identity.sig = nil
    for _, listener in ipairs(revisionListeners) do listener() end
end

-- Keys -------------------------------------------------------------------------------------------

-- WoW has no secure random source for add-ons: the seed hashes values that differ on every machine and moment.
local function entropy()
    local x, y = GetCursorPosition()
    local parts = {
        tostring(debugprofilestop()), tostring(GetTime()), tostring(time()), tostring(GetServerTime()),
        tostring(collectgarbage("count")), tostring({}), tostring(UnitGUID("player")), tostring(x), tostring(y),
    }
    for _ = 1, 16 do parts[#parts + 1] = tostring(fastrandom(0, 2147483647)) end
    return table.concat(parts, "|")
end

---Creates the account's key pair if there is none yet.
function Identity.EnsureKeys()
    local identity = data()
    if identity.id then return end
    local seed = Crypto.SHA512(entropy()):sub(1, 32)
    identity.seed = Crypto.ToHex(seed)
    identity.id = Crypto.ToHex(Crypto.Ed25519.PublicKey(seed))
end

---@return string? id
function Identity.Id()
    return data().id
end

-- Characters -------------------------------------------------------------------------------------

---Records one of this account's characters at login, or refreshes a known one.
---A name change keeps the GUID; a dead Hardcore character moves to another ruleset.
---@param guid string
---@param name string "First Surname"
---@param ruleset WhosWho.Ruleset
---@param classID integer never changes
---@param level integer
function Identity.Refresh(guid, name, ruleset, classID, level)
    local identity = data()
    local character = identity.chars[guid]
    if not character then
        identity.chars[guid] = { name = name, ruleset = ruleset, classID = classID, level = level, lastSeen = time() }
        return
    end

    Identity.Seen(guid, level)
    if character.name == name and character.ruleset == ruleset then return end
    character.name, character.ruleset = name, ruleset
    if character.linked then nextRevision() end
end

---Refreshes the level and last seen time of one of this account's characters; does not change the record.
---@param guid string
---@param level integer
function Identity.Seen(guid, level)
    local character = data().chars[guid]
    if not character then return end
    character.level, character.lastSeen = level, time()
end

---Whether the character is registered in the identity, linked or not.
---@param guid string
---@return boolean
function Identity.IsRegistered(guid)
    local character = data().chars[guid]
    return character ~= nil and character.linked ~= nil
end

---@param guid string
---@return boolean
function Identity.IsLinked(guid)
    local character = data().chars[guid]
    return character ~= nil and character.linked == true
end

---@param guid string
---@return WhosWho.Ruleset? ruleset nil for a character this account never logged in
function Identity.Ruleset(guid)
    local character = data().chars[guid]
    return character and character.ruleset
end

---Sets or clears the guild of one of this account's characters; does not change the record.
---@param guid string
---@param clubId integer?
function Identity.SetGuild(guid, clubId)
    local character = data().chars[guid]
    if character then character.guild = clubId end
end

---Whether one of this account's characters is in that guild.
---@param clubId integer
---@param ruleset WhosWho.Ruleset the ruleset of the character seen in that guild
---@return boolean
function Identity.HasCharacterInGuild(clubId, ruleset)
    for _, character in pairs(data().chars) do
        if character.guild == clubId and character.ruleset == ruleset then return true end
    end
    return false
end

---The revision a character announces: the current one when linked, the one that removed it when unlinked.
---@param guid string
---@return integer? revision nil for a character that never was linked
function Identity.AnnouncedRevision(guid)
    local character = data().chars[guid]
    if not character then return nil end
    if character.linked then return data().rev end
    return character.removedInRevision
end

---@return integer
function Identity.LinkedCount()
    local count = 0
    for _, character in pairs(data().chars) do
        if character.linked then count = count + 1 end
    end
    return count
end

---Every character of this account, registered or not.
---@return table<string, WhosWho.OwnCharacter> characters by GUID
function Identity.Characters()
    return data().chars
end

---This account's linked characters, the main first, then by name.
---@return WhosWho.OwnCharacter[]
function Identity.LinkedCharacters()
    local identity = data()
    local characters = { identity.chars[identity.main] }

    local others = {}
    for guid, character in pairs(identity.chars) do
        if character.linked and guid ~= identity.main then others[#others + 1] = character end
    end
    table.sort(others, function(a, b) return a.name < b.name end)
    for _, character in ipairs(others) do characters[#characters + 1] = character end

    return characters
end

local function findFirstLinked(identity)
    local first
    for guid, character in pairs(identity.chars) do
        if character.linked and (not first or guid < first) then first = guid end
    end
    return first
end

local function setLinked(guid, linked)
    local identity = data()
    local character = identity.chars[guid]
    if not character then return end

    local wasLinked = character.linked == true
    character.linked = linked
    if wasLinked == linked then return end

    if linked and not identity.main then identity.main = guid end
    if not linked and identity.main == guid then identity.main = findFirstLinked(identity) end
    nextRevision()
    character.removedInRevision = not linked and identity.rev or nil
end

---Adds one of this account's characters to the identity. The first one linked becomes the main.
---@param guid string
function Identity.Link(guid)
    setLinked(guid, true)
end

---Removes one of this account's characters from the identity. Unlinking the main makes another linked
---character the main.
---@param guid string
function Identity.Unlink(guid)
    setLinked(guid, false)
end

---Unlinks every character and removes the nickname, in one revision: players who hold the identity forget it once
---that revision reaches them. Every character becomes unregistered, so each one is asked again at its next login.
function Identity.Forget()
    local identity = data()
    local unlinked = {}
    for _, character in pairs(identity.chars) do
        if character.linked then unlinked[#unlinked + 1] = character end
        character.linked = nil
    end
    if not unlinked[1] and not identity.nickname then return end

    identity.main, identity.nickname = nil, nil
    nextRevision()
    for _, character in ipairs(unlinked) do character.removedInRevision = identity.rev end
end

-- Main and nickname ------------------------------------------------------------------------------

---@return string? guid nil while no character is linked
---@return WhosWho.OwnCharacter? character
function Identity.Main()
    local identity = data()
    return identity.main, identity.chars[identity.main]
end

---@param guid string a linked character
---@return boolean ok false when the character is not linked
function Identity.SetMain(guid)
    if not Identity.IsLinked(guid) then return false end

    local identity = data()
    if identity.main ~= guid then
        identity.main = guid
        nextRevision()
    end
    return true
end

---Whether the identity has a nickname override; without one, it goes by its main character's name.
---@return boolean
function Identity.HasNickname()
    return data().nickname ~= nil
end

---The nickname override, or the main character's name.
---@return string? nickname nil while no character is linked
function Identity.Nickname()
    local _, main = Identity.Main()
    if not main then return nil end

    return data().nickname or main.name
end

---@param nickname string? nil removes the override: the main character's name is shown
---@return boolean ok
---@return WhosWho.ErrorCode? err when refused
function Identity.SetNickname(nickname)
    local clean, err = ns.Record.CleanName(nickname)
    if err then return false, err end

    local identity = data()
    if identity.nickname ~= clean then
        identity.nickname = clean
        nextRevision()
    end
    return true
end

-- Record -----------------------------------------------------------------------------------------

---@return integer
function Identity.Revision()
    return data().rev
end

---Adds a function called after each change of revision.
---@param listener fun()
function Identity.OnRevisionChanged(listener)
    revisionListeners[#revisionListeners + 1] = listener
end

---The unsigned record of the current revision, with linked characters only. Past Record.MAX_CHARACTERS, the main
---and the lowest GUIDs are kept.
---@return WhosWho.IdentityRecord
function Identity.UnsignedRecord()
    local identity = data()
    local others = {}
    for guid, character in pairs(identity.chars) do
        if character.linked and guid ~= identity.main then others[#others + 1] = guid end
    end
    table.sort(others)
    local guids = { identity.main }
    for i = 1, math.min(#others, ns.Record.MAX_CHARACTERS - #guids) do guids[#guids + 1] = others[i] end

    local chars = {}
    for _, guid in ipairs(guids) do
        local character = identity.chars[guid]
        chars[guid] = { name = character.name, ruleset = character.ruleset, classID = character.classID }
    end
    return {
        v = ns.Record.VERSION, id = identity.id, rev = identity.rev, nickname = identity.nickname,
        main = identity.main, chars = chars,
    }
end

---Signing takes about 120 ms in game, so the signature is kept until the next change.
---@return WhosWho.SignedIdentityRecord
function Identity.SignedRecord()
    local identity = data()
    if identity.sig then
        local signedRecord = Identity.UnsignedRecord()
        ---@cast signedRecord WhosWho.SignedIdentityRecord
        signedRecord.sig = identity.sig
        return signedRecord
    end

    local signedRecord = ns.Record.Sign(Identity.UnsignedRecord(), identity.seed)
    identity.sig = signedRecord.sig
    return signedRecord
end
