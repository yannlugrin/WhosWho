local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto, Identity, People = ns.Crypto, ns.Identity, ns.People

-- My guild list: the identities of a guild I hold, each with the highest revision I hold, which members compare to
-- pass newer revisions to each other. A hint, not data: every record is still verified with its owner's key.

---@class WhosWho.GuildList
local GuildList = {}
ns.GuildList = GuildList

-- A member at this rank index or above (0 = guild master) passes on identities I don't hold yet.
GuildList.TRUSTED_RANK_INDEX = 1
-- Characters of an identity that place it in the guild's list.
local IN_LIST_STATES = { confirmed = true, guild = true }

---When my list of a guild last changed, and the hash of its content then.
---@class WhosWho.GuildListRevision
---@field at integer server time; 0 until it first changes, so that a member's first list is older than everyone's
---@field hash string 8 hex characters

---@return table<integer, WhosWho.GuildListRevision> by club ID
local function revisions()
    return ns.data.guildLists
end

---My list of that guild: each identity whose record consents to being passed on in the guild and that has a
---confirmed character, or one listed by the guild, in it; mine too, while its record consents and the character I
---play is linked in it.
---@param clubId integer
---@param ruleset WhosWho.Ruleset the ruleset of the character I play
---@return table<string, integer> revision by identity ID
function GuildList.Entries(clubId, ruleset)
    local entries = {}
    for id, person in pairs(ns.data.people) do
        local record = person.signedRecord
        if record and record.guild.consent then
            for _, character in pairs(person.chars) do
                if IN_LIST_STATES[character.state] and character.guild == clubId and character.ruleset == ruleset then
                    entries[id] = record.rev
                    break
                end
            end
        end
    end
    local ownCharacterGuid = UnitGUID("player")
    if Identity.IsLinked(ownCharacterGuid) and Identity.GuildId(ownCharacterGuid) == clubId
        and Identity.UnsignedRecord().guild.consent then
        entries[Identity.Id()] = Identity.Revision()
    end
    return entries
end

-- The hashed bytes: "id:rev" for each identity, sorted.
local function canonical(entries)
    local pairsList = {}
    for id, rev in pairs(entries) do pairsList[#pairsList + 1] = id .. ":" .. rev end
    table.sort(pairsList)
    return table.concat(pairsList, ",")
end

---The short hash of a list's content: the same content always gives the same hash.
---@param entries table<string, integer>
---@return string hash 8 hex characters
function GuildList.Hash(entries)
    return Crypto.ToHex(Crypto.SHA512(canonical(entries))):sub(1, 8)
end

---My list's revision for that guild: when its content last changed, at the latest when this is called, and its hash.
---@param clubId integer
---@param ruleset WhosWho.Ruleset
---@param serverTime integer GetServerTime()
---@return integer at
---@return string hash
function GuildList.Revision(clubId, ruleset, serverTime)
    local hash = GuildList.Hash(GuildList.Entries(clubId, ruleset))
    local revision = revisions()[clubId]
    if not revision or revision.hash ~= hash then
        revision = { at = revision and serverTime or 0, hash = hash }
        revisions()[clubId] = revision
    end
    return revision.at, revision.hash
end

---Makes my list of that guild the most recent one: the members holding a different one ask me for it.
---@param clubId integer
---@param ruleset WhosWho.Ruleset
---@param serverTime integer GetServerTime()
function GuildList.Renew(clubId, ruleset, serverTime)
    revisions()[clubId] = { at = serverTime, hash = GuildList.Hash(GuildList.Entries(clubId, ruleset)) }
end

---Forgets my lists' revisions, with the people they listed: my next list of each guild is a first one, older than
---everyone's, so I ask a member for theirs.
function GuildList.Forget()
    ns.data.guildLists = {}
end

---Whether a list revision is later than another: a later time, or the same time with a greater hash.
---@param at integer
---@param hash string
---@param otherAt integer
---@param otherHash string
---@return boolean
function GuildList.IsLater(at, hash, otherAt, otherHash)
    if at ~= otherAt then return at > otherAt end
    return hash > otherHash
end

---The identities of another member's list that it holds at a newer revision than I do, apart from mine: the ones I
---hold, which any member may pass on, and the ones I don't, which only a trusted member may.
---@param entries table<string, integer> revision by identity ID
---@return string[] held
---@return string[] unknown
function GuildList.Missing(entries)
    local held, unknown = {}, {}
    for id, rev in pairs(entries) do
        if id ~= Identity.Id() and People.IsNewer(id, rev) then
            if People.Get(id) then held[#held + 1] = id else unknown[#unknown + 1] = id end
        end
    end
    table.sort(held)
    table.sort(unknown)
    return held, unknown
end
