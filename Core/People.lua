local _, ns = ...
---@cast ns WhosWho.Namespace

-- Other players' identities, by identity ID: shared ones built from the player's record, manual ones ("M<n>")
-- created by me for players without the add-on.

---@class WhosWho.People
local People = {}
ns.People = People

-- Data -------------------------------------------------------------------------------------------

---Saved in ns.data.people, by identity ID.
---@class WhosWho.Person
---@field record WhosWho.IdentityRecord? the player's record as received, for revisions and relaying; nil for a manual person
---@field received number? seconds, from time(): when the record arrived
---@field nickname string? the player's own nickname, from the record
---@field myNickname string? my nickname for this person
---@field main string? GUID of the main character; nil for a shared person whose record lists no characters
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
---@type table<string, string>? GUID -> ID of the person the character belongs to
local personIdByGuid

-- Several records can list the same character: the one that confirmed it wins, otherwise the one received last.
-- A character I added is in one person only.
local function claimStrength(person, character)
    if character.state == "confirmed" then return math.huge end
    return person.received or 0
end

local function buildIndex()
    local personIds, strengths = {}, {}
    for id, person in pairs(ns.data.people) do
        for guid, character in pairs(person.chars) do
            local strength = claimStrength(person, character)
            if not personIds[guid] or strength > strengths[guid] then
                personIds[guid], strengths[guid] = id, strength
            end
        end
    end
    return personIds
end

---Drops the GUID index; the next lookup rebuilds it. Call after replacing ns.data.
function People.Reset()
    personIdByGuid = nil
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
    personIdByGuid = personIdByGuid or buildIndex()

    local id = personIdByGuid[guid]
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

    local main = person.chars[person.main]
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

    People.Reset()
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

    People.Reset()
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

    People.Reset()
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
    ns.data.people[id] = nil
    People.Reset()
end

-- Received from players --------------------------------------------------------------------------

---Stores a newer revision of a player's record. Its characters become listed; confirmed ones stay confirmed and
---every character keeps its activity. A manual identity of mine holding one of its characters is the same person and
---merges into it (several can); an alt I added to another player's identity moves alone.
---@param record WhosWho.IdentityRecord already validated and verified
---@return "updated"|"stale"
function People.Accept(record)
    local people = ns.data.people
    local sharedPerson = people[record.id]
    if sharedPerson and sharedPerson.record.rev >= record.rev then return "stale" end

    sharedPerson = sharedPerson or { chars = {} }
    people[record.id] = sharedPerson

    for guid in pairs(record.chars) do
        local personId, character = People.Find(guid)
        local person = personId and personId ~= record.id and people[personId]

        -- My manual identities holding one of this player's characters are this player: they merge into it.
        if personId and person and not person.record then
            for personGuid, personCharacter in pairs(person.chars) do
                sharedPerson.chars[personGuid] = personCharacter
            end
            sharedPerson.myNickname = sharedPerson.myNickname or person.myNickname

            people[personId] = nil
            People.Reset()
        end

        -- My alts on other players' identities that this player lists move here.
        if personId and person and person.record and character and character.state == "added" then
            person.chars[guid] = nil
        end
    end

    -- Characters from the new revision: the ones it lists (confirmed ones stay confirmed) and my added ones;
    -- the ones the player dropped are left out.
    local characters = {}
    for sharedGuid, sharedCharacter in pairs(sharedPerson.chars) do
        if sharedCharacter.state == "added" then characters[sharedGuid] = sharedCharacter end
    end
    for recordGuid, recordCharacter in pairs(record.chars) do
        local character = sharedPerson.chars[recordGuid] or {}
        character.name, character.ruleset, character.classID = recordCharacter.name, recordCharacter.ruleset, recordCharacter.classID
        if character.state ~= "confirmed" then character.state = "listed" end
        characters[recordGuid] = character
    end

    sharedPerson.record, sharedPerson.received = record, time()
    sharedPerson.nickname, sharedPerson.main, sharedPerson.chars = record.nickname, record.main, characters

    People.Reset()
    return "updated"
end

---A message sent from the character carried the identity, while the character was at that level. Ignored unless
---the identity's record lists the character. Another identity's confirmation of it becomes a listing.
---@param id string
---@param guid string
---@param level integer
---@return boolean confirmed
function People.Confirm(id, guid, level)
    local person = ns.data.people[id]
    local character = person and person.chars[guid]
    if not character or character.state == "added" then return false end

    local storedPersonId, storedCharacter = People.Find(guid)
    if storedCharacter and storedCharacter.state == "confirmed" and storedPersonId ~= id then storedCharacter.state = "listed" end

    character.state, character.level, character.lastSeen = "confirmed", level, time()

    People.Reset()
    return true
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
