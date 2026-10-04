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
---@field myNickname string?
---@field main string GUID of the main character

---A character as it was when the change happened.
---@class WhosWho.CharacterSnapshot: WhosWho.Character
---@field state WhosWho.CharacterState

---Saved in ns.data.automaticChanges.
---@class WhosWho.AutomaticChange
---@field time number seconds, from time()
---@field kind WhosWho.AutomaticChangeKind
---@field from WhosWho.IdentitySnapshot the identity the characters left
---@field to WhosWho.IdentitySnapshot? the identity they joined: merged, moved and taken only
---@field chars table<string, WhosWho.CharacterSnapshot> by GUID
---@field read boolean

---@param id string
---@return WhosWho.IdentitySnapshot
function AutomaticChanges.IdentitySnapshot(id)
    local person = ns.People.Get(id)
    ---@cast person -nil
    return { id = id, nickname = ns.People.IdentityNickname(id), myNickname = person.myNickname, main = person.main }
end

---@param character WhosWho.PersonCharacter
---@return WhosWho.CharacterSnapshot
function AutomaticChanges.CharacterSnapshot(character)
    return { name = character.name, ruleset = character.ruleset, classID = character.classID, state = character.state }
end

---Adds a change from snapshots already taken.
---@param kind WhosWho.AutomaticChangeKind
---@param from WhosWho.IdentitySnapshot
---@param to WhosWho.IdentitySnapshot?
---@param chars table<string, WhosWho.CharacterSnapshot>
function AutomaticChanges.Add(kind, from, to, chars)
    local changes = ns.data.automaticChanges
    table.insert(changes, 1, { time = time(), kind = kind, from = from, to = to, chars = chars, read = false })
    changes[KEPT_CHANGES + 1] = nil
end

---Adds a change about to happen, with the identities and characters as they are now.
---@param kind WhosWho.AutomaticChangeKind
---@param fromPersonId string
---@param toPersonId string?
---@param guids table<string, any> the changed characters of `fromPersonId`, as keys
function AutomaticChanges.Record(kind, fromPersonId, toPersonId, guids)
    local fromPerson = ns.People.Get(fromPersonId)
    ---@cast fromPerson -nil
    local characterSnapshots = {}
    for guid in pairs(guids) do characterSnapshots[guid] = AutomaticChanges.CharacterSnapshot(fromPerson.chars[guid]) end
    local toSnapshot = toPersonId and AutomaticChanges.IdentitySnapshot(toPersonId)
    AutomaticChanges.Add(kind, AutomaticChanges.IdentitySnapshot(fromPersonId), toSnapshot, characterSnapshots)
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
