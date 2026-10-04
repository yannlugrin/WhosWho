local _, ns = ...
---@cast ns WhosWho.Namespace
local AutomaticChanges = ns.AutomaticChanges

-- Other players' identities, by identity ID: shared ones built from the player's record, manual ones ("M<n>")
-- created by me for players without the add-on.

---@class WhosWho.People
local People = {}
ns.People = People

-- Data -------------------------------------------------------------------------------------------

---Saved in ns.data.people, by identity ID.
---@class WhosWho.Person
---@field record WhosWho.IdentityRecord? the player's record as received, for revisions and relaying; nil for a manual person
---@field nickname string? the player's own nickname, from the record
---@field myNickname string? my nickname for this person
---@field main string GUID of the main character. Another identity can hold a shared person's main.
---@field chars table<string, WhosWho.PersonCharacter> by GUID

---@alias WhosWho.CharacterState
---| "confirmed"  # in the player's record, and a message sent from that character carried the identity
---| "listed"     # in the player's record, not confirmed yet
---| "added"      # added by me

---@class WhosWho.PersonCharacter: WhosWho.Character
---@field state WhosWho.CharacterState
---@field level integer?
---@field lastSeen number? seconds, from time()

---A character I add, as I know it.
---@class WhosWho.NewCharacter: WhosWho.Character
---@field level integer? known when I can see the character

-- Index ------------------------------------------------------------------------------------------

-- A character is in one person only. Every change to a person's characters updates the index.
---@type table<string, string>? GUID -> ID of the person holding the character
local personIdByGuid

local function index()
    if personIdByGuid then return personIdByGuid end

    personIdByGuid = {}
    for id, person in pairs(ns.data.people) do
        for guid in pairs(person.chars) do personIdByGuid[guid] = id end
    end
    return personIdByGuid
end

local function indexCharacter(guid, id)
    index()[guid] = id
end

local function unindexCharacter(guid, id)
    if index()[guid] == id then index()[guid] = nil end
end

-- Confirmations that arrived before the record listing their character; kept for the session only.
---@type table<string, table<string, integer>> identity ID -> GUID -> level
local pendingConfirmations = {}

---Drops the GUID index (the next lookup rebuilds it from the saved data) and the pending confirmations. Call after
---replacing ns.data.
function People.Reset()
    personIdByGuid = nil
    pendingConfirmations = {}
end

-- Reading ----------------------------------------------------------------------------------------

---@param id string
---@return WhosWho.Person?
function People.Get(id)
    return ns.data.people[id]
end

---The person a character belongs to, and everything known about the character.
---@param guid string
---@return string? id
---@return WhosWho.PersonCharacter? character
function People.Find(guid)
    local id = index()[guid]
    if not id then return nil end

    return id, ns.data.people[id].chars[guid]
end

---The nickname the identity itself gives, whatever overrides it: the player's own (shared person), otherwise the
---main character's name.
---@param id string
---@return string? nickname nil for an unknown person
function People.IdentityNickname(id)
    local person = ns.data.people[id]
    if not person then return nil end

    -- Another identity can hold the main (a confirmation moved it there); its name is still in the record.
    local main = person.chars[person.main] or (person.record and person.record.chars[person.main])
    return person.nickname or (main and main.name)
end

---The name a person is shown under: my nickname, otherwise the identity's own.
---@param id string
---@return string? nickname nil for an unknown person
function People.Nickname(id)
    local person = ns.data.people[id]
    if not person then return nil end

    return person.myNickname or People.IdentityNickname(id)
end

-- My changes -------------------------------------------------------------------------------------

local function addedCharacter(character)
    return {
        name = character.name, ruleset = character.ruleset, classID = character.classID, state = "added",
        level = character.level, lastSeen = character.level and time(),
    }
end

---Creates a manual person from its first character, which becomes its main.
---@param guid string
---@param character WhosWho.NewCharacter
---@return string? id
---@return "guid"|"taken"? err taken when the character already belongs to a person
function People.Create(guid, character)
    if not ns.Record.IsGuid(guid) then return nil, "guid" end
    if People.Find(guid) then return nil, "taken" end

    local data = ns.data
    local id = "M" .. data.nextManual
    data.nextManual = data.nextManual + 1
    data.people[id] = { main = guid, chars = { [guid] = addedCharacter(character) } }
    indexCharacter(guid, id)

    return id
end

---@param id string
---@param guid string
---@param character WhosWho.NewCharacter
---@return boolean ok
---@return "missing"|"guid"|"taken"? err taken when the character already belongs to a person
function People.AddCharacter(id, guid, character)
    local person = ns.data.people[id]
    if not person then return false, "missing" end
    if not ns.Record.IsGuid(guid) then return false, "guid" end
    if People.Find(guid) then return false, "taken" end

    person.chars[guid] = addedCharacter(character)
    indexCharacter(guid, id)

    return true
end

---Removes a character I added. A manual person's main is refused: change the main first, or forget the person.
---@param id string
---@param guid string
---@return boolean ok
---@return "character"|"main"? err character when I did not add this character to this person
function People.RemoveCharacter(id, guid)
    local person = ns.data.people[id]
    local character = person and person.chars[guid]
    if not (person and character and character.state == "added") then return false, "character" end
    if guid == person.main then return false, "main" end

    person.chars[guid] = nil
    unindexCharacter(guid, id)

    return true
end

---Sets or removes my nickname for a person.
---@param id string
---@param nickname string? nil removes mine
---@return boolean ok
---@return WhosWho.ErrorCode|"missing"? err
function People.Rename(id, nickname)
    local person = ns.data.people[id]
    if not person then return false, "missing" end

    local clean, err = ns.Record.CleanName(nickname)
    if err then return false, err end
    person.myNickname = clean

    return true
end

---Sets a manual person's main character. A shared identity's main is the player's own.
---@param id string
---@param guid string one of the person's characters
---@return boolean ok
---@return "missing"|"shared"|"character"? err
function People.SetMain(id, guid)
    local person = ns.data.people[id]
    if not person then return false, "missing" end
    if person.record then return false, "shared" end
    if not person.chars[guid] then return false, "character" end

    person.main = guid

    return true
end

---@param id string
function People.Forget(id)
    local person = ns.data.people[id]
    if not person then return end

    for guid in pairs(person.chars) do unindexCharacter(guid, id) end
    ns.data.people[id] = nil
end

-- Received from players --------------------------------------------------------------------------

-- Puts one of a record's characters in identity `toPersonId`, and removes it from the person it no longer belongs to.
-- `confirmedLevel` is given when a message from the character proved it (its level then); without it, another
-- player's identity keeps the character.
local function storeCharacter(toPersonId, guid, recordCharacter, confirmedLevel)
    local people = ns.data.people

    -- Another player keeps a character they declared, unless this is a confirmation.
    local fromPersonId = index()[guid]
    local fromPerson = fromPersonId and fromPersonId ~= toPersonId and people[fromPersonId] or nil
    if fromPerson and fromPerson.record then
        if not confirmedLevel and fromPerson.chars[guid].state ~= "added" then return false end
        AutomaticChanges.Record(fromPerson.chars[guid].state == "added" and "moved" or "taken", fromPersonId, toPersonId, { [guid] = true })
        fromPerson.chars[guid] = nil
    end

    -- A manual identity I created for this player: merge it into this identity.
    local toPerson = people[toPersonId]
    if fromPersonId and fromPerson and not fromPerson.record then
        AutomaticChanges.Record("merged", fromPersonId, toPersonId, fromPerson.chars)
        for movedGuid, movedCharacter in pairs(fromPerson.chars) do
            toPerson.chars[movedGuid] = movedCharacter
            indexCharacter(movedGuid, toPersonId)
        end
        toPerson.myNickname = toPerson.myNickname or fromPerson.myNickname
        People.Forget(fromPersonId)
    end

    -- The character itself, with the record's data: listed, or confirmed once proven.
    local character = toPerson.chars[guid] or {}
    character.name, character.ruleset, character.classID = recordCharacter.name, recordCharacter.ruleset, recordCharacter.classID
    if character.state ~= "confirmed" then character.state = "listed" end
    if confirmedLevel then character.state, character.level, character.lastSeen = "confirmed", confirmedLevel, time() end
    toPerson.chars[guid] = character
    indexCharacter(guid, toPersonId)

    return true
end

---Stores a newer revision of a player's record. A revision without characters means the player unlinked them all:
---the person is forgotten, my nickname and added alts with it.
---@param record WhosWho.IdentityRecord already validated and verified
---@return "updated"|"stale"|"forgotten"
function People.Accept(record)
    local people, forgotten = ns.data.people, ns.data.forgotten
    local sharedPerson = people[record.id]
    if sharedPerson and sharedPerson.record.rev >= record.rev then return "stale" end
    if forgotten[record.id] and forgotten[record.id] >= record.rev then return "stale" end

    if not record.main then
        if sharedPerson then
            AutomaticChanges.Record("forgotten", record.id, nil, sharedPerson.chars)
            People.Forget(record.id)
        end
        forgotten[record.id] = record.rev
        return "forgotten"
    end
    forgotten[record.id] = nil

    local originalIdentitySnapshot = sharedPerson and AutomaticChanges.IdentitySnapshot(record.id)
    sharedPerson = sharedPerson or { chars = {} }
    people[record.id] = sharedPerson
    sharedPerson.record, sharedPerson.nickname, sharedPerson.main = record, record.nickname, record.main

    -- Characters the player dropped leave; my added alts stay.
    local droppedCharacterSnapshots = {}
    for guid, character in pairs(sharedPerson.chars) do
        if character.state ~= "added" and not record.chars[guid] then
            droppedCharacterSnapshots[guid] = AutomaticChanges.CharacterSnapshot(character)
            sharedPerson.chars[guid] = nil
            unindexCharacter(guid, record.id)
        end
    end
    if next(droppedCharacterSnapshots) then
        AutomaticChanges.Add("dropped", originalIdentitySnapshot, nil, droppedCharacterSnapshots)
    end

    -- Confirmations of characters this revision now lists, received before it arrived.
    local pending = pendingConfirmations[record.id] or {}
    pendingConfirmations[record.id] = nil

    -- Update or add the characters this revision lists.
    for guid, recordCharacter in pairs(record.chars) do
        storeCharacter(record.id, guid, recordCharacter, pending[guid])
    end

    return "updated"
end

---A message sent from the character carried the identity, while the character was at that level. When the record
---doesn't list the character yet, the confirmation waits for the revision that does (People.Accept).
---@param id string
---@param guid string
---@param level integer
---@return boolean confirmed false while it waits
function People.Confirm(id, guid, level)
    local person = ns.data.people[id]
    local recordCharacter = person and person.record and person.record.chars[guid]
    if not recordCharacter then
        pendingConfirmations[id] = pendingConfirmations[id] or {}
        pendingConfirmations[id][guid] = level
        return false
    end

    return storeCharacter(id, guid, recordCharacter, level)
end

---Activity of a character from any source, a relay included. Never confirms; kept only when more recent.
---@param guid string
---@param level integer
---@param lastSeen number seconds, from time()
---@return boolean kept false for an unknown character or older activity
function People.Activity(guid, level, lastSeen)
    local _, character = People.Find(guid)
    if not character or (character.lastSeen and character.lastSeen >= lastSeen) then return false end

    character.level, character.lastSeen = level, lastSeen

    return true
end
