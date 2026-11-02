local _, ns = ...
---@cast ns WhosWho.Namespace
local Identity, LinkedAccounts, People = ns.Identity, ns.LinkedAccounts, ns.People

-- One answer per character: own identity first, then my linked accounts, then the person it belongs to.

---@class WhosWho.Resolver
local Resolver = {}
ns.Resolver = Resolver

---@class WhosWho.Resolution
---@field id string identity ID
---@field nickname string
---@field characterName string
---@field mine boolean this account's own identity
---@field shared boolean the player shares this identity themselves
---@field state WhosWho.CharacterState how the character belongs to the identity

---@param guid string
---@return WhosWho.Resolution?
function Resolver.Resolve(guid)
    if Identity.IsLinked(guid) then
        return {
            id = Identity.Id(), nickname = Identity.Nickname(), characterName = Identity.Characters()[guid].name,
            mine = true, shared = true, state = "confirmed",
        }
    end

    -- A character of my other account goes by my nickname.
    local accountId, accountCharacter = LinkedAccounts.Holding(guid)
    if accountId then
        return {
            id = accountId, nickname = Identity.Nickname(), characterName = accountCharacter.name,
            mine = false, shared = true, state = "listed",
        }
    end

    local person, character = People.Find(guid)
    if not (person and character) then return nil end
    local nickname = People.Nickname(person.id)
    if not nickname then return nil end

    return {
        id = person.id, nickname = nickname, characterName = character.name, mine = false,
        shared = person.signedRecord ~= nil, state = character.state,
    }
end
