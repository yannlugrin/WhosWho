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
---@field note string? my note about this person, never shared; may hold several lines
---@field main string GUID of the main character. Another identity can hold a shared person's main.
---@field chars table<string, WhosWho.PersonCharacter> by GUID
---@field updatedAt number? seconds, from time(): the person's last change, by the player or by me

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
---@field whisperedAt number? seconds, from time(): when one of my characters last whispered it

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

---@type fun()[]
local changeListeners = {}

-- Called once at the end of each public change, so listeners never see a change half done.
local function changed()
    for _, listener in ipairs(changeListeners) do listener() end
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

---Every person I hold.
---@return table<string, WhosWho.Person> by identity ID
function People.All()
    return ns.data.people
end

---Adds a function called after each change to the people I hold: a person, a character, a nickname or an activity.
---@param listener fun()
function People.OnChanged(listener)
    changeListeners[#changeListeners + 1] = listener
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

    local forgotten = ns.data.forgotten[id]
    return not (forgotten and forgotten.rev >= rev)
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
    data.people[id] = { id = id, main = guid, chars = { [guid] = addedCharacter(character) }, updatedAt = time() }
    indexCharacter(guid, id)
    changed()

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
    person.updatedAt = time()
    indexCharacter(guid, id)
    changed()

    return true
end

---Whether People.RemoveCharacter accepts this character: one I added, and not a manual person's main.
---@param id string
---@param guid string
---@return boolean
function People.CanRemoveCharacter(id, guid)
    local person = ns.data.people[id]
    local character = person and person.chars[guid]
    return character ~= nil and character.state == "added" and guid ~= person.main
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
    person.updatedAt = time()
    unindexCharacter(guid, id)
    changed()

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
    person.customNickname, person.updatedAt = clean, time()
    changed()

    return true
end

People.NOTE_MAX_LENGTH = 500

---Sets or removes my note about a person. Spaces and empty lines around it are dropped; an empty note removes it.
---@param id string
---@param note string?
---@return boolean ok
---@return "missing"|"long"? err
function People.SetNote(id, note)
    local person = ns.data.people[id]
    if not person then return false, "missing" end

    note = note and note:match("^%s*(.-)%s*$") or ""
    if strlenutf8(note) > People.NOTE_MAX_LENGTH then return false, "long" end
    person.note, person.updatedAt = note ~= "" and note or nil, time()
    changed()

    return true
end

---Whether People.SetMain would change this person's main to this character: a manual person, not its main yet.
---@param id string
---@param guid string
---@return boolean
function People.CanSetMain(id, guid)
    local person = ns.data.people[id]
    return person ~= nil and not person.signedRecord and person.chars[guid] ~= nil and guid ~= person.main
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

    person.main, person.updatedAt = guid, time()
    changed()

    return true
end

local function forget(id)
    local person = ns.data.people[id]
    if not person then return end

    for guid in pairs(person.chars) do unindexCharacter(guid, id) end
    ns.data.people[id] = nil
end

---@param id string
function People.Forget(id)
    if not ns.data.people[id] then return end
    forget(id)
    changed()
end

---Forgets every person, shared and manual.
function People.ForgetAll()
    ns.data.people = {}
    People.Reset()
    changed()
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
        if fromPerson.note then
            toPerson.note = toPerson.note and (toPerson.note .. "\n" .. fromPerson.note) or fromPerson.note
        end
        forget(fromPerson.id)
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

-- Forgets a shared person whose player unlinked every character, my nickname and added alts with it, silently: the
-- Review tab would invite me to add them again by hand. Its revision then makes an older copy relayed later stale.
local function forgetUnlinked(id, rev)
    forget(id)
    ns.data.forgotten[id] = { rev = rev, at = time() }
end

---Stores a newer revision of a player's record. Its characters that declared no identity are left out. A revision
---without characters, or with only such ones, means the player unlinked them all: the person is forgotten, my nickname
---and added alts with it.
---@param signedRecord WhosWho.SignedIdentityRecord already validated and verified
---@return "updated"|"stale"|"forgotten"
function People.Accept(signedRecord)
    local people, noIdentity = ns.data.people, ns.data.noIdentity
    if not People.IsNewer(signedRecord.id, signedRecord.rev) then return "stale" end
    local sharedPerson = people[signedRecord.id]

    local recordCharacters = {}
    for guid, recordCharacter in pairs(signedRecord.chars) do
        if not noIdentity[guid] then recordCharacters[guid] = recordCharacter end
    end
    if not next(recordCharacters) then
        forgetUnlinked(signedRecord.id, signedRecord.rev)
        if sharedPerson then changed() end
        return "forgotten"
    end
    ns.data.forgotten[signedRecord.id] = nil

    -- Characters the player removed leave, silently; my added alts stay.
    if sharedPerson then
        for guid, character in pairs(sharedPerson.chars) do
            if character.state ~= "added" and not recordCharacters[guid] then
                sharedPerson.chars[guid] = nil
                unindexCharacter(guid, signedRecord.id)
            end
        end
    end

    sharedPerson = sharedPerson or { id = signedRecord.id, chars = {} }
    people[signedRecord.id] = sharedPerson
    sharedPerson.signedRecord, sharedPerson.nickname, sharedPerson.main = signedRecord, signedRecord.nickname, signedRecord.main
    sharedPerson.updatedAt = time()

    -- Confirmations of characters this revision now lists, received before it arrived.
    local pending = pendingConfirmations[signedRecord.id] or {}
    pendingConfirmations[signedRecord.id] = nil

    -- Update or add the characters this revision lists.
    AutomaticChanges.BeginOperation(sharedPerson)
    for guid, recordCharacter in pairs(recordCharacters) do
        storeCharacter(sharedPerson, guid, recordCharacter, pending[guid])
    end
    AutomaticChanges.EndOperation()
    changed()

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
    -- The character declares an identity again.
    ns.data.noIdentity[guid] = nil

    -- The player's record must list the character; otherwise the confirmation waits for the revision that does.
    local recordCharacter = person and person.signedRecord and person.signedRecord.chars[guid]
    if not recordCharacter then
        pendingConfirmations[id] = pendingConfirmations[id] or {}
        pendingConfirmations[id][guid] = level
        return false
    end

    -- Already confirmed in this identity: only its activity changes.
    person.updatedAt = time()
    local personCharacter = person.chars[guid]
    if personCharacter and personCharacter.state == "confirmed" then
        personCharacter.level, personCharacter.lastSeen = level, time()
        changed()
        return true
    end

    AutomaticChanges.BeginOperation(person)
    local stored = storeCharacter(person, guid, recordCharacter, level)
    AutomaticChanges.EndOperation()
    if stored then changed() end
    return stored
end

---A message from that character declared that it belongs to no identity (NOID): it leaves the shared identity holding it,
---listed or confirmed, silently; a character I added stays. A shared person left without characters of the player's
---is forgotten. Records listing it leave it out until a message from it confirms an identity.
---@param guid string
function People.DeclaredNoIdentity(guid)
    ns.data.noIdentity[guid] = time()
    local person, character = People.Find(guid)
    if not (person and person.signedRecord and character and character.state ~= "added") then return end

    person.chars[guid] = nil
    person.updatedAt = time()
    unindexCharacter(guid, person.id)
    for _, other in pairs(person.chars) do
        if other.state ~= "added" then
            changed()
            return
        end
    end
    forgetUnlinked(person.id, person.signedRecord.rev)
    changed()
end

---Activity of characters I hold, from what the game shows (the guild roster, my group, my friend list, whispers):
---each is kept only when more recent, and never confirms anything. One change for them all.
---@param activities table<string, { level: integer?, lastSeen: number }> by GUID; lastSeen in seconds, from time()
function People.Activity(activities)
    local kept = false
    for guid, activity in pairs(activities) do
        local _, character = People.Find(guid)
        if character and not (character.lastSeen and character.lastSeen >= activity.lastSeen) then
            character.level, character.lastSeen = activity.level or character.level, activity.lastSeen
            kept = true
        end
    end
    if kept then changed() end
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

---A character one of my characters whispered.
---@param guid string
---@param whisperedAt number seconds, from time()
function People.SetWhisperedAt(guid, whisperedAt)
    local _, character = People.Find(guid)
    if character then character.whisperedAt = whisperedAt end
end

---Clears every whisperedAt older than that time.
---@param before number seconds, from time()
function People.ClearWhisperedBefore(before)
    for _, person in pairs(ns.data.people) do
        for _, character in pairs(person.chars) do
            if character.whisperedAt and character.whisperedAt < before then character.whisperedAt = nil end
        end
    end
end
