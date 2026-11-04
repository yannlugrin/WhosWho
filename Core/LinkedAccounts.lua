local _, ns = ...
---@cast ns WhosWho.Namespace

-- The records of my other accounts. They are me, not people: a link takes the person I knew out of People and keeps it
-- here, and removing the link gives it back.

---@class WhosWho.LinkedAccounts
local LinkedAccounts = {}
ns.LinkedAccounts = LinkedAccounts

---Saved in ns.data.linkedAccounts, by identity ID.
---@class WhosWho.LinkedAccount
---@field signedRecord WhosWho.SignedIdentityRecord? the account's newest record as received
---@field unlinked table<string, true>? GUIDs the record lists that declared no identity since (NOID)
---@field person WhosWho.Person? the person I knew before the link, my nickname and note included, without its record

---@type fun()[]
local changeListeners = {}

local function changed()
    for _, listener in ipairs(changeListeners) do listener() end
end

---Adds a function called after each change to what I hold of my linked accounts.
---@param listener fun()
function LinkedAccounts.OnChanged(listener)
    changeListeners[#changeListeners + 1] = listener
end

local function recordOf(id)
    local account = ns.data.linkedAccounts[id]
    return account and account.signedRecord
end

---The record I hold of an account, as received.
---@param id string
---@return WhosWho.SignedIdentityRecord?
function LinkedAccounts.Record(id)
    return recordOf(id)
end

---What the record I hold of an account says it goes by: its nickname, or its main's name.
---@param id string
---@return string? nickname nil without a record, or when it names no main
function LinkedAccounts.Nickname(id)
    local signedRecord = recordOf(id)
    if not signedRecord then return nil end

    local main = signedRecord.chars[signedRecord.main]
    return signedRecord.nickname or (main and main.name)
end

---The characters of the record I hold of an account, without those that declared no identity since.
---@param id string
---@return table<string, WhosWho.Character> by GUID; empty without a record
function LinkedAccounts.Characters(id)
    local signedRecord = recordOf(id)
    local unlinked = signedRecord and ns.data.linkedAccounts[id].unlinked or {}
    local characters = {}
    for guid, character in pairs(signedRecord and signedRecord.chars or {}) do
        if not unlinked[guid] then characters[guid] = character end
    end
    return characters
end

---The linked account holding that character.
---@param guid string
---@return string? id
---@return WhosWho.Character? character
function LinkedAccounts.Holding(guid)
    for id in pairs(ns.data.linkedAccounts) do
        local character = LinkedAccounts.Characters(id)[guid]
        if character then return id, character end
    end
    return nil, nil
end

---The accounts linked to mine: my main identity on another account, my other accounts on my main identity.
---`waiting`: the record I hold of it doesn't declare the link back, or I hold none.
---@return { id: string, waiting: boolean }[] by ID
function LinkedAccounts.List()
    local Identity = ns.Identity
    local ownId, mainId = Identity.Id(), Identity.PartOf()
    local accounts = {}
    if mainId then
        local signedRecord = recordOf(mainId)
        local declared = signedRecord and signedRecord.accounts
        accounts[1] = { id = mainId, waiting = not (declared and declared[ownId]) }
    else
        for id in pairs(Identity.Accounts() or {}) do
            local signedRecord = recordOf(id)
            accounts[#accounts + 1] = { id = id, waiting = not (signedRecord and signedRecord.partOf == ownId) }
        end
    end
    table.sort(accounts, function(a, b) return a.id < b.id end)
    return accounts
end

---Whether a record of that account and revision would be new.
---@param id string
---@param rev integer
---@return boolean
function LinkedAccounts.IsNewer(id, rev)
    local signedRecord = recordOf(id)
    return not signedRecord or signedRecord.rev < rev
end

---Stores a newer record of a linked account, which decides its characters again. One without the general part is
---what a guild gets: it says neither the name nor every character. An account part of another goes by the name of its
---main identity's record.
---@param signedRecord WhosWho.SignedIdentityRecord already validated and verified
function LinkedAccounts.Accept(signedRecord)
    local id = signedRecord.id
    if not (signedRecord.main and LinkedAccounts.IsNewer(id, signedRecord.rev)) then return end

    local account = ns.data.linkedAccounts[id] or {}
    ns.data.linkedAccounts[id] = account
    account.signedRecord, account.unlinked = signedRecord, nil
    if id == ns.Identity.PartOf() then ns.Identity.SetMainIdentityNickname(LinkedAccounts.Nickname(id)) end
    changed()
end

---A character of a linked account declared no identity (NOID): it leaves the account until a newer record lists it.
---@param guid string
function LinkedAccounts.DeclaredNoIdentity(guid)
    local id = LinkedAccounts.Holding(guid)
    if not id then return end

    local account = ns.data.linkedAccounts[id]
    account.unlinked = account.unlinked or {}
    account.unlinked[guid] = true
    changed()
end

---That identity became one of my linked accounts: the person I knew moves here, with its record.
---@param id string
function LinkedAccounts.Hold(id)
    local person = ns.People.TakeOut(id)
    if not person then return end

    ns.data.linkedAccounts[id] = { signedRecord = person.signedRecord, person = person }
    person.signedRecord = nil
    changed()
end

---That identity is no longer one of my linked accounts: it is a person again, with what I held of it.
---@param id string
function LinkedAccounts.Release(id)
    local account = ns.data.linkedAccounts[id]
    if not account then return end

    ns.data.linkedAccounts[id] = nil
    ns.People.GiveBack(account.person, account.signedRecord)
    for guid in pairs(account.unlinked or {}) do ns.People.DeclaredNoIdentity(guid) end
    changed()
end
