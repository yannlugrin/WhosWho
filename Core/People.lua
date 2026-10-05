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
---@field id string identity ID, the same as its key in ns.data.people
---@field signedRecord WhosWho.SignedIdentityRecord? the player's record as received, for revisions and relaying; nil for a manual person
---@field nickname string? the player's own nickname, from the record
---@field customNickname string? my nickname for this person
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
---@field guild integer? club ID of the guild in which one of my characters saw it
---@field friendOf table<string, true>? GUIDs of my characters that have it as a WoW friend

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
---@return WhosWho.Person? person
---@return WhosWho.PersonCharacter? character
function People.Find(guid)
    local id = index()[guid]
    if not id then return nil end

    local person = ns.data.people[id]
    return person, person.chars[guid]
end

---Whether a person holds that character.
---@param guid string
---@return boolean
function People.Exists(guid)
    return index()[guid] ~= nil
end

---The person holding a confirmed character with that whole name in that ruleset (the secondary key).
---@param name string "First Surname"
---@param ruleset WhosWho.Ruleset
---@return WhosWho.Person?
function People.FindConfirmedByName(name, ruleset)
    for _, person in pairs(ns.data.people) do
        for _, character in pairs(person.chars) do
            if character.state == "confirmed" and character.name == name and character.ruleset == ruleset then return person end
        end
    end
    return nil
end

---Whether a record of that identity and revision would be new: not held at that revision or a later one, and not
---forgotten at that revision or a later one.
---@param id string
---@param rev integer
---@return boolean
function People.IsNewer(id, rev)
    local person = ns.data.people[id]
    if person and person.signedRecord and person.signedRecord.rev >= rev then return false end

    local forgottenRevision = ns.data.forgotten[id]
    return not (forgottenRevision and forgottenRevision >= rev)
end

---The nickname the identity itself gives, whatever overrides it: the player's own (shared person), otherwise the
---main character's name.
---@param id string
---@return string? nickname nil for an unknown person
function People.IdentityNickname(id)
    local person = ns.data.people[id]
    if not person then return nil end

    -- Another identity can hold the main (a confirmation moved it there); its name is still in the record.
    local main = person.chars[person.main] or (person.signedRecord and person.signedRecord.chars[person.main])
    return person.nickname or (main and main.name)
end

---The name a person is shown under: my nickname, otherwise the identity's own.
---@param id string
---@return string? nickname nil for an unknown person
function People.Nickname(id)
    local person = ns.data.people[id]
    if not person then return nil end

    return person.customNickname or People.IdentityNickname(id)
end

---The people whose characters were seen most recently (their latest lastSeen), most recent first.
---@param count integer
---@return string[] ids
function People.MostRecentIds(count)
    local lastSeenById, ids = {}, {}
    for id, person in pairs(ns.data.people) do
        local lastSeen = 0
        for _, character in pairs(person.chars) do
            if character.lastSeen and character.lastSeen > lastSeen then lastSeen = character.lastSeen end
        end
        lastSeenById[id] = lastSeen
        ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b)
        if lastSeenById[a] ~= lastSeenById[b] then return lastSeenById[a] > lastSeenById[b] end
        return a < b
    end)
    for i = #ids, count + 1, -1 do ids[i] = nil end
    return ids
end

---The people holding a character with that whole name, in any ruleset, sorted by ID; letter case is ignored.
---@param name string "First Surname"
---@return WhosWho.Person[]
function People.FindByCharacterName(name)
    local wanted, persons = name:lower(), {}
    for _, person in pairs(ns.data.people) do
        for _, character in pairs(person.chars) do
            if character.name:lower() == wanted then
                persons[#persons + 1] = person
                break
            end
        end
    end
    table.sort(persons, function(a, b) return a.id < b.id end)
    return persons
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
    if People.Exists(guid) then return nil, "taken" end

    local data = ns.data
    local id = "M" .. data.nextManual
    data.nextManual = data.nextManual + 1
    data.people[id] = { id = id, main = guid, chars = { [guid] = addedCharacter(character) } }
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
    if People.Exists(guid) then return false, "taken" end

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
    person.customNickname = clean

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
    if person.signedRecord then return false, "shared" end
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

-- Puts one of a record's characters in `toPerson`, and removes it from the person it no longer belongs to.
-- `confirmedLevel` is given when a message from the character proved it (its level then); without it, another
-- player's identity keeps the character.
local function storeCharacter(toPerson, guid, recordCharacter, confirmedLevel)
    -- Another player keeps a character they declared, unless this is a confirmation.
    local fromPersonId = index()[guid]
    local fromPerson = fromPersonId and fromPersonId ~= toPerson.id and ns.data.people[fromPersonId] or nil
    local fromCharacter
    if fromPerson and fromPerson.signedRecord then
        fromCharacter = fromPerson.chars[guid]
        if not confirmedLevel and fromCharacter.state ~= "added" then return false end
        AutomaticChanges.Record(fromCharacter.state == "added" and "moved" or "taken", fromPerson, toPerson, { [guid] = true })
        fromPerson.chars[guid] = nil
    end

    -- A manual identity I created for this player: merge it into this identity.
    if fromPerson and not fromPerson.signedRecord then
        AutomaticChanges.Record("merged", fromPerson, toPerson, fromPerson.chars)
        for movedGuid, movedCharacter in pairs(fromPerson.chars) do
            toPerson.chars[movedGuid] = movedCharacter
            indexCharacter(movedGuid, toPerson.id)
        end
        toPerson.customNickname = toPerson.customNickname or fromPerson.customNickname
        People.Forget(fromPerson.id)
    end

    -- The character itself, its entry moved from the identity it left, with the record's data: listed, or confirmed
    -- once proven.
    local character = toPerson.chars[guid] or fromCharacter or {}
    character.name, character.ruleset, character.classID = recordCharacter.name, recordCharacter.ruleset, recordCharacter.classID
    if character.state ~= "confirmed" then character.state = "listed" end
    if confirmedLevel then character.state, character.level, character.lastSeen = "confirmed", confirmedLevel, time() end
    toPerson.chars[guid] = character
    indexCharacter(guid, toPerson.id)

    return true
end

---Stores a newer revision of a player's record. A revision without characters means the player unlinked them all:
---the person is forgotten, my nickname and added alts with it.
---@param signedRecord WhosWho.SignedIdentityRecord already validated and verified
---@return "updated"|"stale"|"forgotten"
function People.Accept(signedRecord)
    local people, forgotten = ns.data.people, ns.data.forgotten
    if not People.IsNewer(signedRecord.id, signedRecord.rev) then return "stale" end
    local sharedPerson = people[signedRecord.id]

    if not signedRecord.main then
        if sharedPerson then
            AutomaticChanges.Record("forgotten", sharedPerson, nil, sharedPerson.chars)
            People.Forget(signedRecord.id)
        end
        forgotten[signedRecord.id] = signedRecord.rev
        return "forgotten"
    end
    forgotten[signedRecord.id] = nil

    -- Characters the player dropped leave; my added alts stay. Recorded before the revision changes the person.
    if sharedPerson then
        local droppedGuids = {}
        for guid, character in pairs(sharedPerson.chars) do
            if character.state ~= "added" and not signedRecord.chars[guid] then droppedGuids[guid] = true end
        end
        if next(droppedGuids) then AutomaticChanges.Record("dropped", sharedPerson, nil, droppedGuids) end
        for guid in pairs(droppedGuids) do
            sharedPerson.chars[guid] = nil
            unindexCharacter(guid, signedRecord.id)
        end
    end

    sharedPerson = sharedPerson or { id = signedRecord.id, chars = {} }
    people[signedRecord.id] = sharedPerson
    sharedPerson.signedRecord, sharedPerson.nickname, sharedPerson.main = signedRecord, signedRecord.nickname, signedRecord.main

    -- Confirmations of characters this revision now lists, received before it arrived.
    local pending = pendingConfirmations[signedRecord.id] or {}
    pendingConfirmations[signedRecord.id] = nil

    -- Update or add the characters this revision lists.
    AutomaticChanges.BeginOperation(sharedPerson)
    for guid, recordCharacter in pairs(signedRecord.chars) do
        storeCharacter(sharedPerson, guid, recordCharacter, pending[guid])
    end
    AutomaticChanges.EndOperation()

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

    -- The player's record must list the character; otherwise the confirmation waits for the revision that does.
    local recordCharacter = person and person.signedRecord and person.signedRecord.chars[guid]
    if not recordCharacter then
        pendingConfirmations[id] = pendingConfirmations[id] or {}
        pendingConfirmations[id][guid] = level
        return false
    end

    -- Already confirmed in this identity: only its activity changes.
    local personCharacter = person.chars[guid]
    if personCharacter and personCharacter.state == "confirmed" then
        personCharacter.level, personCharacter.lastSeen = level, time()
        return true
    end

    AutomaticChanges.BeginOperation(person)
    local stored = storeCharacter(person, guid, recordCharacter, level)
    AutomaticChanges.EndOperation()
    return stored
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

-- Relationships ----------------------------------------------------------------------------------

-- What my characters saw themselves, kept on any character I hold. Only confirmed characters count for sharing
-- (Scopes), so a record listing a character never makes it count.

---A character seen in the guild roster of one of my characters.
---@param guid string
---@param clubId integer
function People.SetGuild(guid, clubId)
    local _, character = People.Find(guid)
    if character then character.guild = clubId end
end

---Applies a whole guild roster: its characters get the guild, the others lose it.
---@param clubId integer
---@param memberGuids table<string, true>
function People.UpdateGuildMembers(clubId, memberGuids)
    for _, person in pairs(ns.data.people) do
        for guid, character in pairs(person.chars) do
            if memberGuids[guid] then
                character.guild = clubId
            elseif character.guild == clubId then
                character.guild = nil
            end
        end
    end
end

---A character in the friend list of one of my characters.
---@param guid string
---@param ownCharacterGuid string my character whose friend it is
function People.SetFriendOf(guid, ownCharacterGuid)
    local _, character = People.Find(guid)
    if not character then return end

    character.friendOf = character.friendOf or {}
    character.friendOf[ownCharacterGuid] = true
end

---Applies the whole friend list of one of my characters.
---@param ownCharacterGuid string
---@param friendGuids table<string, true>
function People.UpdateFriends(ownCharacterGuid, friendGuids)
    for _, person in pairs(ns.data.people) do
        for guid, character in pairs(person.chars) do
            if friendGuids[guid] then
                character.friendOf = character.friendOf or {}
                character.friendOf[ownCharacterGuid] = true
            elseif character.friendOf then
                character.friendOf[ownCharacterGuid] = nil
                if not next(character.friendOf) then character.friendOf = nil end
            end
        end
    end
end
