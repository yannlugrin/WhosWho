local _, ns = ...
---@cast ns WhosWho.Namespace
local AutomaticChanges = ns.AutomaticChanges

-- Other players' identities, by identity ID: shared ones built from the player's record, manual ones ("M<n>")
-- created by me for players without the add-on, and guild identities ("G<hex>") a guild's record makes (GuildRecord).

---@class WhosWho.People
local People = {}
ns.People = People

-- Data -------------------------------------------------------------------------------------------

---Saved in ns.data.people, by identity ID.
---@class WhosWho.Person
---@field id string identity ID, the same as its key in ns.data.people
---@field signedRecord WhosWho.SignedIdentityRecord? the player's record as received, for revisions and relaying; nil for a manual person or a guild identity
---@field madeByGuild integer? for a guild identity, the guild (club ID) whose record makes it
---@field nickname string? the player's own nickname, from the record; a guild identity's, from its guild's record
---@field customNickname string? my nickname for this person
---@field note string? my note about this person, never shared; may hold several lines
---@field main string GUID of the main, or of the record's guild main; another identity can hold a shared person's main
---@field chars table<string, WhosWho.PersonCharacter> by GUID
---@field updatedAt number? seconds, from time(): the person's last change, by the player or by me
---@field outdated true? its record came from outside a guild enforcing linking I joined since: fetched again

---@alias WhosWho.CharacterState
---| "confirmed"  # in the player's record, and a message sent from that character carried the identity
---| "listed"     # in the player's record, not confirmed yet
---| "relayed"    # in the player's record, passed on by a trusted member of my guild, not by the player; not confirmed yet
---| "added"      # added by me
---| "guild"      # linked by my guild's record (GuildRecord), not by the player

---@class WhosWho.PersonCharacter: WhosWho.Character
---@field state WhosWho.CharacterState
---@field level integer?
---@field lastSeen number? seconds, from time()
---@field guild integer? club ID of the guild in which one of my characters saw it; for the state "guild", the guild whose record links it
---@field friendOf table<string, true>? GUIDs of my characters that have it as a WoW friend
---@field bnetFriend string? BattleTag of my Battle.net friend seen playing it; kept locally, never sent
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

---Whether a message sent from that character proved it belongs to that identity: a confirmed character of a person I
---hold, or one of my linked characters for my own identity.
---@param id string
---@param guid string
---@return boolean
function People.IsConfirmedCharacter(id, guid)
    if id == ns.Identity.Id() then return ns.Identity.IsLinked(guid) end
    local person, character = People.Find(guid)
    return person ~= nil and person.id == id and character ~= nil and character.state == "confirmed"
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

---Whether I want a record of that identity and revision: a newer one, or the revision I hold when it is outdated.
---@param id string
---@param rev integer
---@return boolean
function People.IsWanted(id, rev)
    local person = ns.data.people[id]
    if person and person.outdated and person.signedRecord and person.signedRecord.rev == rev then return true end
    return People.IsNewer(id, rev)
end

-- Whether a record of the revision I hold could replace mine: mine is outdated, or it holds another content (another
-- signature).
local function replaceable(signedRecord)
    local person = ns.data.people[signedRecord.id]
    local held = person and person.signedRecord
    if not (held and held.rev == signedRecord.rev) then return false end
    return person.outdated == true or held.sig ~= signedRecord.sig
end

---Whether a record of the revision I hold replaces mine: only one from my guild (its channel, or a guild member's
---whisper), whose content was chosen for me as its member, when mine is outdated or holds another content.
---@param signedRecord WhosWho.SignedIdentityRecord
---@param fromMyGuild boolean
---@return boolean
function People.ReplacesHeld(signedRecord, fromMyGuild)
    return fromMyGuild and replaceable(signedRecord)
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
---@return WhosWho.NameErrorCode|"missing"? err
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
    return person ~= nil and not person.signedRecord and not person.madeByGuild and person.chars[guid] ~= nil
        and guid ~= person.main
end

---Sets a manual person's main character. A shared identity's main is the player's own, a guild identity's its guild's.
---@param id string
---@param guid string one of the person's characters
---@return boolean ok
---@return "missing"|"shared"|"guild"|"character"? err
function People.SetMain(id, guid)
    local person = ns.data.people[id]
    if not person then return false, "missing" end
    if person.signedRecord then return false, "shared" end
    if person.madeByGuild then return false, "guild" end
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

-- A person is shown under one of its characters: when its main left it (a player's record took it, the roster dropped
-- it), or a shared person's record names none (its guild main stood for it), the first of the others by name.
local function keepShownMain(person)
    if person.chars[person.main] then return end
    local main
    for guid, character in pairs(person.chars) do
        if not main or character.name < person.chars[main].name then main = guid end
    end
    person.main = main
end

-- One of my manual identities merges into the identity a player's record or my guild's links one of its characters
-- to: its characters, my nickname unless I already named that identity, and my note below the one I had.
local function mergeManualPerson(fromPerson, toPerson)
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

-- Who declares a character, weakest first: me, my guild, the player.
local CLAIMS = { added = 1, guild = 2, relayed = 3, listed = 3, confirmed = 3 }
-- A message from the character itself, which takes it whatever declares it.
local CONFIRMATION_CLAIM = 4

-- Puts a character a record declares in `toPerson` with that state ("listed" or "relayed" from a player's record,
-- "guild" from my guild's), and removes it from the person it no longer belongs to. `takesGuildLink`: a more recent
-- record of my guild takes the character from an older one that links it. A stronger claim takes it from
-- another person, an equal one updates it on its own person: a player keeps a character they declared, my guild's
-- link gives way to the player's record, mine to both. `confirmedLevel` is given when a message from the character
-- proved it (its level then). My manual identity holding the character merges into `toPerson`; an identity left
-- without characters goes. Whether the character is in `toPerson`.
local function storeCharacter(toPerson, guid, recordCharacter, state, confirmedLevel, takesGuildLink)
    local claim = confirmedLevel and CONFIRMATION_CLAIM or CLAIMS[state]
    local fromPersonId = index()[guid]
    local fromPerson = fromPersonId and ns.data.people[fromPersonId]
    local fromCharacter = fromPerson and fromPerson.chars[guid]
    if fromPerson == toPerson then
        if claim < CLAIMS[fromCharacter.state] then return false end
    elseif fromPerson and (fromPerson.signedRecord or fromPerson.madeByGuild) then
        local takesIt = claim > CLAIMS[fromCharacter.state] or (takesGuildLink and fromCharacter.state == "guild")
        if not takesIt then return false end
        -- My link moved, or a player's character taken by a confirmation; my guild's link is not mine.
        if fromCharacter.state ~= "guild" then
            AutomaticChanges.Record(fromCharacter.state == "added" and "moved" or "taken", fromPerson, toPerson, { [guid] = true })
        end
        fromPerson.chars[guid] = nil
        if next(fromPerson.chars) then
            if fromPerson.madeByGuild then keepShownMain(fromPerson) end
        else
            -- Nothing left to it: a guild identity's characters went to stronger claims, a player's confirmed others.
            forget(fromPerson.id)
        end
    elseif fromPerson then
        mergeManualPerson(fromPerson, toPerson)
    end

    -- The character itself, its entry moved from the identity it left, with the record's data. A player's record
    -- passed on by my guild doesn't make listed relayed again, nor anything make confirmed less.
    local character = toPerson.chars[guid] or fromCharacter or {}
    character.name, character.ruleset, character.classID = recordCharacter.name, recordCharacter.ruleset, recordCharacter.classID
    if confirmedLevel then
        character.state, character.level, character.lastSeen = "confirmed", confirmedLevel, time()
    elseif character.state ~= "confirmed" and not (state == "relayed" and character.state == "listed") then
        character.state = state
    end
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

-- Received from my guild ------------------------------------------------------------------------

-- Brings the person a guild's record is about in line with it: the characters that guild linked and the record no
-- longer lists leave, the ones it lists are linked; a guild identity takes its nickname and main, and goes when the
-- record holds no characters (my nickname and note with it) or none is left to it. A link to a shared identity I don't
-- hold waits in ns.data.guildRecords until its record arrives (People.Accept).
---@param signedRecord WhosWho.SignedGuildRecord
local function applyGuildRecord(signedRecord)
    local people, clubId, id = ns.data.people, signedRecord.guild, signedRecord.id
    local guildIdentity = ns.GuildRecord.IsGuildIdentityId(id)
    local person = people[id]
    if not (person or guildIdentity) then return end

    if person then
        for guid, character in pairs(person.chars) do
            if character.state == "guild" and character.guild == clubId and not signedRecord.chars[guid] then
                person.chars[guid] = nil
                unindexCharacter(guid, id)
            end
        end
    end
    if guildIdentity and not next(signedRecord.chars) then
        forget(id)
        return
    end
    if guildIdentity then
        person = person or { id = id, madeByGuild = clubId, chars = {} }
        people[id] = person
        person.nickname, person.main = signedRecord.nickname, signedRecord.main
    end
    ---@cast person WhosWho.Person
    person.updatedAt = time()

    AutomaticChanges.BeginOperation(person)
    for guid, recordCharacter in pairs(signedRecord.chars) do
        local holder, held = People.Find(guid)
        local takesGuildLink = holder ~= nil and held.state == "guild" and held.guild == clubId
            and ns.GuildRecord.IsNewerThan(signedRecord, ns.data.guildRecords[clubId][holder.id])
        if storeCharacter(person, guid, recordCharacter, "guild", nil, takesGuildLink) then
            person.chars[guid].guild = clubId
        end
    end
    AutomaticChanges.EndOperation()
    if guildIdentity and not next(person.chars) then
        forget(id)
    elseif guildIdentity then
        keepShownMain(person)
    end
end

-- Applies every record of a guild I hold, the most recent first: what a newer record releases is free before an older
-- one is applied, and a character goes to the most recent record listing it, whatever order they came in.
local function applyGuild(clubId)
    local records = {}
    for _, signedRecord in pairs(ns.data.guildRecords[clubId] or {}) do records[#records + 1] = signedRecord end
    table.sort(records, ns.GuildRecord.IsNewerThan)
    for _, signedRecord in ipairs(records) do applyGuildRecord(signedRecord) end
end

---Applies every record of a guild I hold (GuildRecord), after one of them changed or at login.
---@param clubId integer
function People.ApplyGuild(clubId)
    applyGuild(clubId)
    changed()
end

---Stores a newer revision of a player's record, or the one replacing the revision I hold. Its characters that declared
---no identity are left out, but those my guild vouches for: a record my guild sent, and its roster lists them. A
---revision without characters, or with only such ones, means the player unlinked them all: the person is forgotten, my
---nickname and added alts with it. One whose characters other identities hold more strongly (messages from them
---confirmed those) is not kept either, but its revision is not held as forgotten: a new identity can arrive before the
---message from its character that takes the character from the old one.
---@param signedRecord WhosWho.SignedIdentityRecord already validated and verified
---@param fromGuild boolean? relayed by a member of my guild, not sent by the player: the new characters are "guild"
---@param guildMembers table<string, true>? by GUID, the record's characters my guild's roster lists, when my guild sent it
---@return "updated"|"stale"|"forgotten"
function People.Accept(signedRecord, fromGuild, guildMembers)
    local people, noIdentity = ns.data.people, ns.data.noIdentity
    -- Replacing the revision I hold: the caller checked where it came from (People.ReplacesHeld).
    local wanted = People.IsNewer(signedRecord.id, signedRecord.rev) or replaceable(signedRecord)
    if not wanted then return "stale" end
    local sharedPerson = people[signedRecord.id]

    local recordCharacters = {}
    for guid, recordCharacter in pairs(signedRecord.chars) do
        if not noIdentity[guid] or (guildMembers and guildMembers[guid]) then
            recordCharacters[guid] = recordCharacter
        end
    end
    if not next(recordCharacters) then
        forgetUnlinked(signedRecord.id, signedRecord.rev)
        if sharedPerson then changed() end
        return "forgotten"
    end
    ns.data.forgotten[signedRecord.id] = nil

    -- Characters the player removed leave, silently; the alts I or my guild linked stay.
    if sharedPerson then
        for guid, character in pairs(sharedPerson.chars) do
            if character.state ~= "added" and character.state ~= "guild" and not recordCharacters[guid] then
                sharedPerson.chars[guid] = nil
                unindexCharacter(guid, signedRecord.id)
            end
        end
    end

    local created = sharedPerson == nil
    sharedPerson = sharedPerson or { id = signedRecord.id, chars = {} }
    people[signedRecord.id] = sharedPerson
    sharedPerson.signedRecord, sharedPerson.nickname = signedRecord, ns.Record.ShownNickname(signedRecord)
    sharedPerson.main, sharedPerson.updatedAt, sharedPerson.outdated = ns.Record.ShownMain(signedRecord), time(), nil

    -- Confirmations of characters this revision now lists, received before it arrived.
    local pending = pendingConfirmations[signedRecord.id] or {}
    pendingConfirmations[signedRecord.id] = nil

    -- Update or add the characters this revision lists.
    AutomaticChanges.BeginOperation(sharedPerson)
    for guid, recordCharacter in pairs(recordCharacters) do
        storeCharacter(sharedPerson, guid, recordCharacter, fromGuild and "relayed" or "listed", pending[guid])
    end
    AutomaticChanges.EndOperation()
    -- What my guilds link to this identity, held until it arrived.
    if created then
        for clubId, records in pairs(ns.data.guildRecords) do
            if records[signedRecord.id] then applyGuild(clubId) end
        end
    end
    if not next(sharedPerson.chars) then
        forget(signedRecord.id)
        changed()
        return "forgotten"
    end
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
    local stored = storeCharacter(person, guid, recordCharacter, "listed", level)
    AutomaticChanges.EndOperation()
    if stored then changed() end
    return stored
end

---A message from that character declared that it belongs to no identity (NOID): it leaves the shared identity holding it,
---listed or confirmed, silently; a character I or my guild linked stays. A shared person left without characters of
---the player's is forgotten. Records listing it leave it out until a message from it confirms an identity.
---@param guid string
function People.DeclaredNoIdentity(guid)
    ns.data.noIdentity[guid] = time()
    local person, character = People.Find(guid)
    if not (person and person.signedRecord and character and character.state ~= "added" and character.state ~= "guild") then
        return
    end

    person.chars[guid] = nil
    person.updatedAt = time()
    unindexCharacter(guid, person.id)
    for _, other in pairs(person.chars) do
        if other.state ~= "added" and other.state ~= "guild" then
            changed()
            return
        end
    end
    forgetUnlinked(person.id, person.signedRecord.rev)
    changed()
end

---Activity of characters I hold, from what the game shows (the guild roster, my group, my friend list, whispers): a
---last seen time is kept only when more recent, a level only when higher. Without a last seen time, the game shows the
---character without my seeing it (a guild member offline in the roster). Never confirms anything. One change for them
---all.
---@param activities table<string, { level: integer?, lastSeen: number? }> by GUID; lastSeen in seconds, from time()
function People.Activity(activities)
    local kept = false
    for guid, activity in pairs(activities) do
        local _, character = People.Find(guid)
        if character then
            if activity.lastSeen and not (character.lastSeen and character.lastSeen >= activity.lastSeen) then
                character.lastSeen = activity.lastSeen
                kept = true
            end
            if activity.level and not (character.level and character.level >= activity.level) then
                character.level = activity.level
                kept = true
            end
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

-- Whether the record holds the character only because its guild enforces linking.
local function isForced(person, guid)
    local forced = person.signedRecord and person.signedRecord.guild.forced
    return forced ~= nil and forced[guid] == true
end

-- Whether the person holds a character the player told me of: one neither I nor my guild linked, and, for one only
-- that guild passed on, still in it (members).
local function holdsPlayersCharacter(person, memberGuids)
    for guid, character in pairs(person.chars) do
        if character.state ~= "added" and character.state ~= "guild" and (character.state ~= "relayed" or memberGuids[guid]) then
            return true
        end
    end
    return false
end

-- Forgets what I hold of a person through that guild, for the characters its roster no longer lists (members): the
-- characters its rule added, but those never seen in my roster, and the ones its records linked. A character its roster
-- lists left the guild whose records linked it: that link goes too. A shared person goes too when it had a character in
-- that guild and is left without a character the player told me of; a guild identity, when it is left without
-- characters, or, made by that guild, when no roster is given (I left the guild). Whether anything was forgotten.
local function forgetFormerMember(person, clubId, memberGuids)
    local inThatGuild, removedFromPerson = false, {}
    for guid, character in pairs(person.chars) do
        inThatGuild = inThatGuild or character.guild == clubId
        local forcedThere = (character.guild == clubId or character.guild == nil) and isForced(person, guid)
        local linkedThere = character.state == "guild" and character.guild == clubId
        local linkedElsewhere = character.state == "guild" and character.guild ~= clubId
        if (not memberGuids[guid] and (forcedThere or linkedThere)) or (memberGuids[guid] and linkedElsewhere) then
            person.chars[guid] = nil
            unindexCharacter(guid, person.id)
            removedFromPerson[guid] = true
        end
    end
    if person.madeByGuild then
        if not next(person.chars) or (person.madeByGuild == clubId and not next(memberGuids)) then
            forget(person.id)
            return true
        end
        keepShownMain(person)
        return next(removedFromPerson) ~= nil
    end
    if (inThatGuild or next(removedFromPerson)) and not holdsPlayersCharacter(person, memberGuids) then
        forget(person.id)
        return true
    end
    if not next(removedFromPerson) then return false end
    -- Its guild main forgotten, the person is shown under the record's main again.
    if removedFromPerson[person.main] then
        person.main = person.signedRecord.main
        keepShownMain(person)
    end
    return true
end

-- forgetFormerMember for every shared person and guild identity. Whether anything was forgotten.
local function forgetFormerMembers(clubId, memberGuids)
    local removed = false
    for _, person in pairs(ns.data.people) do
        if (person.signedRecord or person.madeByGuild) and forgetFormerMember(person, clubId, memberGuids) then
            removed = true
        end
    end
    return removed
end

---Applies a whole guild roster: its characters get the guild, the others lose it. What I hold only through that guild,
---a player or what its records linked, is forgotten once the roster no longer lists them; another guild's links, once it
---lists them.
---@param clubId integer
---@param memberGuids table<string, true>
function People.UpdateGuildMembers(clubId, memberGuids)
    local removed = forgetFormerMembers(clubId, memberGuids)
    for _, person in pairs(ns.data.people) do
        for guid, character in pairs(person.chars) do
            if memberGuids[guid] then
                character.guild = clubId
            elseif character.guild == clubId then
                character.guild = nil
            end
        end
    end
    if removed then changed() end
end

---None of my characters is in that guild any more: what I hold only through it, its members or what its records linked,
---is forgotten.
---@param clubId integer
function People.GuildLeft(clubId)
    if forgetFormerMembers(clubId, {}) then changed() end
end

---I joined a guild enforcing linking: the records I hold of identities with a character in it came from outside it,
---without the characters its rule adds, and are fetched again.
---@param clubId integer
function People.MarkOutdated(clubId)
    for _, person in pairs(ns.data.people) do
        for _, character in pairs(person.chars) do
            if person.signedRecord and character.guild == clubId then
                person.outdated = true
                break
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

---Applies my Battle.net friend list: the characters my friends play get their BattleTag; a character loses it once
---its BattleTag is no longer in the list.
---@param characterTags table<string, string> BattleTag by GUID of the character played
---@param battleTags table<string, true> every friend's BattleTag, online or not
function People.UpdateBnetFriends(characterTags, battleTags)
    for _, person in pairs(ns.data.people) do
        for guid, character in pairs(person.chars) do
            if characterTags[guid] then
                character.bnetFriend = characterTags[guid]
            elseif character.bnetFriend and not battleTags[character.bnetFriend] then
                character.bnetFriend = nil
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
