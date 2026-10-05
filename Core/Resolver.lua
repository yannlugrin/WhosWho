local _, ns = ...
---@cast ns WhosWho.Namespace
local Identity, People = ns.Identity, ns.People

-- One answer per character: own identity first, then the person it belongs to.

---@class WhosWho.Resolver
local Resolver = {}
ns.Resolver = Resolver

---@class WhosWho.Resolution
---@field id string identity ID
---@field nickname string
---@field mine boolean this account's own identity
---@field shared boolean the player shares this identity themselves
---@field state WhosWho.CharacterState how the character belongs to the identity

---@param guid string
---@return WhosWho.Resolution?
function Resolver.Resolve(guid)
    if Identity.IsLinked(guid) then
        return { id = Identity.Id(), nickname = Identity.Nickname(), mine = true, shared = true, state = "confirmed" }
    end

    local person, character = People.Find(guid)
    if not (person and character) then return nil end
    local nickname = People.Nickname(person.id)
    if not nickname then return nil end

    return { id = person.id, nickname = nickname, mine = false, shared = person.signedRecord ~= nil, state = character.state }
end
