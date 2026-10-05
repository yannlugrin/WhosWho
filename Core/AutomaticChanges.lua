local _, ns = ...
---@cast ns WhosWho.Namespace

-- Changes to my links that Who's Who made on its own, most recent first, for the Review tab.

---@class WhosWho.AutomaticChanges
local AutomaticChanges = {}
ns.AutomaticChanges = AutomaticChanges

local KEPT_CHANGES = 100

---@alias WhosWho.AutomaticChangeKind
---| "merged"     # my manual identity merged into a player's identity
---| "moved"      # an alt I added to a shared identity moved to another player's identity
---| "taken"      # a character a player listed, taken by the identity a message from it confirmed
---| "dropped"    # characters a new revision of the player's record no longer lists
---| "forgotten"  # an identity whose player unlinked every character

---An identity as it was when the change happened.
---@class WhosWho.IdentitySnapshot
---@field id string
---@field nickname string? the identity's own nickname (People.IdentityNickname)
---@field customNickname string?
---@field main string GUID of the main character

---A character as it was when the change happened.
---@class WhosWho.CharacterSnapshot: WhosWho.Character
---@field state WhosWho.CharacterState
---@field stateAfter WhosWho.CharacterState? merged, moved and taken: its state in the identity it joined, once the change is complete

---Saved in ns.data.automaticChanges.
---@class WhosWho.AutomaticChange
---@field time number seconds, from time()
---@field kind WhosWho.AutomaticChangeKind
---@field from WhosWho.IdentitySnapshot the identity the characters left
---@field to WhosWho.IdentitySnapshot? the identity they joined: merged, moved and taken only
---@field chars table<string, WhosWho.CharacterSnapshot> by GUID
---@field toChars table<string, WhosWho.CharacterSnapshot>? merged, moved and taken: the characters the identity they joined already had
---@field read boolean

---People storing characters into one identity: a revision's characters (People.Accept) or a confirmation
---(People.Confirm). The changes that join characters to an identity happen inside one.
---@class WhosWho.AutomaticChangesOperation
---@field person WhosWho.Person the identity the characters join
---@field characterSnapshotsBefore table<string, WhosWho.CharacterSnapshot> its characters when the operation began
---@field pendingChanges WhosWho.AutomaticChange[] recorded during it, saved once complete, in the order recorded

---@type WhosWho.AutomaticChangesOperation?
local operation

local function identitySnapshot(person)
    return {
        id = person.id, nickname = ns.People.IdentityNickname(person.id), customNickname = person.customNickname,
        main = person.main,
    }
end

local function characterSnapshot(character)
    return { name = character.name, ruleset = character.ruleset, classID = character.classID, state = character.state }
end

-- A saved change is complete and never changed again (only its read flag).
local function save(change)
    local changes = ns.data.automaticChanges
    table.insert(changes, 1, change)
    changes[KEPT_CHANGES + 1] = nil
end

---Begins an operation on a person: its characters as they are now are the ones already there for every change that
---joins it during the operation.
---@param person WhosWho.Person
function AutomaticChanges.BeginOperation(person)
    local characterSnapshotsBefore = {}
    for guid, character in pairs(person.chars) do characterSnapshotsBefore[guid] = characterSnapshot(character) end
    operation = { person = person, characterSnapshotsBefore = characterSnapshotsBefore, pendingChanges = {} }
end

---Records a change about to happen, with the identities and characters as they are now. A change outside an operation
---is saved at once; one joining an identity is saved when the operation ends, once complete.
---@param kind WhosWho.AutomaticChangeKind
---@param fromPerson WhosWho.Person the identity the characters leave
---@param toPerson WhosWho.Person? the identity they join: merged, moved and taken, recorded inside an operation
---@param guids table<string, any> the changed characters of `fromPerson`, as keys
function AutomaticChanges.Record(kind, fromPerson, toPerson, guids)
    local characterSnapshots = {}
    for guid in pairs(guids) do characterSnapshots[guid] = characterSnapshot(fromPerson.chars[guid]) end

    local change = {
        time = time(), kind = kind, from = identitySnapshot(fromPerson), to = toPerson and identitySnapshot(toPerson),
        chars = characterSnapshots, read = false,
    }
    if not toPerson then
        save(change)
        return
    end
    assert(operation, "a change joining an identity is recorded inside an operation")
    table.insert(operation.pendingChanges, change)
end

---Ends the operation: each change recorded in it gets the characters the identity already had, and the state each of
---its characters ended in there, then is saved. A merge's characters only get their final state once the whole
---revision is applied.
function AutomaticChanges.EndOperation()
    assert(operation, "no operation to end")
    for _, change in ipairs(operation.pendingChanges) do
        change.toChars = operation.characterSnapshotsBefore
        for guid, snapshot in pairs(change.chars) do
            local character = operation.person.chars[guid]
            snapshot.stateAfter = character and character.state
        end
        save(change)
    end
    operation = nil
end

---@return WhosWho.AutomaticChange[] changes most recent first
function AutomaticChanges.List()
    return ns.data.automaticChanges
end

---@return integer
function AutomaticChanges.UnreadCount()
    local unread = 0
    for _, change in ipairs(ns.data.automaticChanges) do
        if not change.read then unread = unread + 1 end
    end
    return unread
end

---@param change WhosWho.AutomaticChange one of AutomaticChanges.List()
function AutomaticChanges.MarkRead(change)
    change.read = true
end
