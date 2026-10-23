local _, ns = ...
---@cast ns WhosWho.Namespace
local Crypto = ns.Crypto

---@class WhosWho.Identity
local Identity = {}
ns.Identity = Identity

-- Data -------------------------------------------------------------------------------------------

---Saved as ns.data.identity.
---@class WhosWho.IdentityData
---@field id string? public key, 64 hex characters
---@field seed string? private key, 64 hex characters
---@field rev integer
---@field nickname string? override; the main character's name is shown otherwise
---@field main string? GUID of the main character, always a linked one
---@field chars table<string, WhosWho.OwnCharacter> by GUID
---@field signatures table<string, string>? the current revision's records' signatures, by SHA-512 (hex) of their bytes
---@field enforcedLinkingOptIns table<integer, boolean>? by club ID, my answer to a guild enforcing linking: true opts in
---@field guilds table<integer, WhosWho.OwnGuildEntry>? by club ID: what I say in that guild, in its members' record
---@field lastLogout { guid: string, at: number }? the account's last logout or /reload: the character, and when (time())
---@field lastBroadcastRevision integer? the revision my last announcement to every audience that answers a GET carried

---@class WhosWho.OwnCharacter: WhosWho.Character
---@field linked boolean? nil until the character is registered in the identity, linked or not
---@field level integer at the end of the last session
---@field lastSeen number seconds, from time(): end of the last session (or its start, after a crash)
---@field guild WhosWho.OwnCharacterGuild? the character's guild
---@field removedAt number? seconds, from time(): when it was unlinked after being linked; it declares no identity (NOID)
---@field loggedInAt number? seconds, from time(): when its current or last session started; a /reload keeps it

---@class WhosWho.OwnCharacterGuild
---@field id integer? club ID (C_Club.GetGuildClubId), nil until the game gives it after joining
---@field name string? the guild's name, as last seen
---@field joinedAt number? seconds, from time(): when the character joined it, unknown for a guild it was in before

---What I say in one guild, which its members get in my record (Record: the guild's entry).
---@class WhosWho.OwnGuildEntry
---@field main string? GUID of the character of mine in that guild it shows me under, as I chose
---@field nickname string? my nickname in that guild
---@field answered table<string, integer>? by request kind: when the guild's request I last answered was made; never sent

---@return WhosWho.IdentityData
local function data()
    return ns.data.identity
end

---@type fun()[]
local revisionListeners = {}

local function nextRevision()
    local identity = data()
    identity.rev = identity.rev + 1
    identity.signatures = nil
    for _, listener in ipairs(revisionListeners) do listener() end
end

-- Keys -------------------------------------------------------------------------------------------

-- WoW has no secure random source for add-ons: the seed hashes values that differ on every machine and moment.
local function entropy()
    local x, y = GetCursorPosition()
    local parts = {
        tostring(debugprofilestop()), tostring(GetTime()), tostring(time()), tostring(GetServerTime()),
        tostring(collectgarbage("count")), tostring({}), tostring(UnitGUID("player")), tostring(x), tostring(y),
    }
    for _ = 1, 16 do parts[#parts + 1] = tostring(fastrandom(0, 2147483647)) end
    return table.concat(parts, "|")
end

---Creates the account's key pair if there is none yet.
function Identity.EnsureKeys()
    local identity = data()
    if identity.id then return end
    local seed = Crypto.SHA512(entropy()):sub(1, 32)
    identity.seed = Crypto.ToHex(seed)
    identity.id = Crypto.ToHex(Crypto.Ed25519.PublicKey(seed))
end

---@return string? id
function Identity.Id()
    return data().id
end

-- Characters -------------------------------------------------------------------------------------

---Records one of this account's characters at login, or refreshes a known one.
---A name change keeps the GUID; a dead Hardcore character moves to another ruleset; a race change service changes the
---race, which characters saved before it was recorded get at their next login.
---@param guid string
---@param name string "First Surname"
---@param ruleset WhosWho.Ruleset
---@param classID integer never changes
---@param raceID integer? nil when the game doesn't give it
---@param level integer
function Identity.Refresh(guid, name, ruleset, classID, raceID, level)
    local identity = data()
    local character = identity.chars[guid]
    if not character then
        identity.chars[guid] = {
            name = name, ruleset = ruleset, classID = classID, raceID = raceID, level = level, lastSeen = time(),
        }
        return
    end

    Identity.Seen(guid, level)
    raceID = raceID or character.raceID
    if character.name == name and character.ruleset == ruleset and character.raceID == raceID then return end
    character.name, character.ruleset, character.raceID = name, ruleset, raceID
    if Identity.AnnouncedRevision(guid) then nextRevision() end
end

---The character reached the highest level the game allows: when, in its record.
---@param guid string
function Identity.ReachedMaxLevel(guid)
    local character = data().chars[guid]
    if not character then return end
    character.maxLevelAt = time()
    if Identity.AnnouncedRevision(guid) then nextRevision() end
end

---Refreshes the level and last seen time of one of this account's characters; does not change the record.
---@param guid string
---@param level integer
function Identity.Seen(guid, level)
    local character = data().chars[guid]
    if not character then return end
    character.level, character.lastSeen = level, time()
end

---PLAYER_ENTERING_WORLD on a login, not on a /reload: the start of the character's session.
---@param guid string
function Identity.LoggedIn(guid)
    local character = data().chars[guid]
    if character then character.loggedInAt = time() end
end

---When the character's current or last session started, in seconds from time().
---@param guid string
---@return number? loggedInAt
function Identity.LoggedInAt(guid)
    local character = data().chars[guid]
    return character and character.loggedInAt
end

---PLAYER_LOGOUT (a logout or a /reload): the account's last logout.
---@param guid string
function Identity.LoggedOut(guid)
    data().lastLogout = { guid = guid, at = time() }
end

---@return { guid: string, at: number }? lastLogout
function Identity.LastLogout()
    return data().lastLogout
end

---@param revision integer? the revision my last announcement to everyone carried; nil makes the next login announce
function Identity.SetLastBroadcastRevision(revision)
    data().lastBroadcastRevision = revision
end

---@return integer? lastBroadcastRevision
function Identity.LastBroadcastRevision()
    return data().lastBroadcastRevision
end

---Whether the character is registered in the identity, linked or not.
---@param guid string
---@return boolean
function Identity.IsRegistered(guid)
    local character = data().chars[guid]
    return character ~= nil and character.linked ~= nil
end

---@param guid string
---@return boolean
function Identity.IsLinked(guid)
    local character = data().chars[guid]
    return character ~= nil and character.linked == true
end

---@param guid string
---@return WhosWho.Ruleset? ruleset nil for a character this account never logged in
function Identity.Ruleset(guid)
    local character = data().chars[guid]
    return character and character.ruleset
end

---Sets or clears the guild of one of this account's characters; does not change the record. The guild it joined keeps
---its join time.
---@param guid string
---@param clubId integer?
---@param name string? the guild's name; nil keeps the one last seen
function Identity.SetGuild(guid, clubId, name)
    local character = data().chars[guid]
    if not character then return end
    local guild = character.guild
    if not clubId then
        character.guild = nil
    elseif guild and (guild.id == nil or guild.id == clubId) then
        guild.id, guild.name = clubId, name or guild.name
    else
        character.guild = { id = clubId, name = name }
    end
end

---What the members of a guild enforcing linking get from me changed: a character of mine joined it, or the guild
---turned the rule on or off.
function Identity.GuildContentChanged()
    nextRevision()
end

---The club ID of the character's guild, as last seen.
---@param guid string
---@return integer?
function Identity.GuildId(guid)
    local character = data().chars[guid]
    return character and character.guild and character.guild.id
end

---Whether the character joined a guild whose club ID the game hasn't given yet.
---@param guid string
---@return boolean
function Identity.GuildIdPending(guid)
    local character = data().chars[guid]
    return character ~= nil and character.guild ~= nil and character.guild.id == nil
end

---PLAYER_GUILD_UPDATE: the character joined a guild.
---@param guid string
---@param clubId integer? nil when the game does not give it yet
function Identity.GuildJoined(guid, clubId)
    local character = data().chars[guid]
    if character then character.guild = { id = clubId, joinedAt = time() } end
end

---Whether the character joined its guild since its last login, /reloads included.
---@param guid string
---@return boolean
function Identity.JoinedGuildSinceLogin(guid)
    local character = data().chars[guid]
    local joinedAt = character and character.guild and character.guild.joinedAt
    return joinedAt ~= nil and character.loggedInAt ~= nil and joinedAt >= character.loggedInAt
end

---Whether one of this account's linked characters is in that guild.
---@param clubId integer
---@param ruleset WhosWho.Ruleset
---@return boolean
function Identity.HasLinkedCharacterInGuild(clubId, ruleset)
    for _, character in pairs(data().chars) do
        if character.linked and character.guild and character.guild.id == clubId and character.ruleset == ruleset then
            return true
        end
    end
    return false
end

---Whether one of this account's characters is in that guild.
---@param clubId integer
---@param ruleset WhosWho.Ruleset the ruleset of the character seen in that guild
---@return boolean
function Identity.HasCharacterInGuild(clubId, ruleset)
    for _, character in pairs(data().chars) do
        if character.guild and character.guild.id == clubId and character.ruleset == ruleset then return true end
    end
    return false
end

---The revision a character announces: the current one, while it is linked, or in a guild enforcing linking whose rule
---I opted in to.
---@param guid string
---@return integer? revision nil for a character that is not linked, unless its guild's rule adds it
function Identity.AnnouncedRevision(guid)
    local character = data().chars[guid]
    if not character then return nil end
    if character.linked then return data().rev end
    local clubId = character.guild and character.guild.id
    if clubId and ns.GuildSettings.EnforcesLinking(clubId) and Identity.EnforcedLinkingOptIn(clubId) == true then
        return data().rev
    end
    return nil
end

---Whether every character of mine in that guild is linked.
---@param clubId integer
---@param ruleset WhosWho.Ruleset
---@return boolean
function Identity.AllLinkedInGuild(clubId, ruleset)
    for _, character in pairs(data().chars) do
        if character.guild and character.guild.id == clubId and character.ruleset == ruleset and not character.linked then
            return false
        end
    end
    return true
end

---My answer to a guild enforcing linking: true opts in (my characters in it shared without linking), false refuses.
---@param clubId integer
---@return boolean? optIn nil while not answered
function Identity.EnforcedLinkingOptIn(clubId)
    local optIns = data().enforcedLinkingOptIns
    return optIns and optIns[clubId]
end

---Whether my identity is complete in a guild enforcing linking: I opted in, or all my characters in it are linked with
---my Guild scope on.
---@param clubId integer
---@param ruleset WhosWho.Ruleset
---@return boolean
function Identity.CompleteInGuild(clubId, ruleset)
    return Identity.EnforcedLinkingOptIn(clubId) == true
        or (ns.Scopes.Get("guild") and Identity.AllLinkedInGuild(clubId, ruleset))
end

---@type fun(clubId: integer)[]
local guildRuleKeptListeners = {}

---Adds a function called with a guild's club ID when a change would have stopped sharing with that guild, whose rule I
---had accepted: its members keep getting my characters in it.
---@param listener fun(clubId: integer)
function Identity.OnGuildRuleKept(listener)
    guildRuleKeptListeners[#guildRuleKeptListeners + 1] = listener
end

-- Before a change that would leave my identity incomplete in a guild enforcing linking (the Guild scope turned off, a
-- character unlinked): my identity complete there means I accepted its rule, which only leaving the guild undoes. It is
-- saved as accepted, so the guild keeps getting my characters in it. Only that guild (clubId), or all of them.
local function keepGuildRulesAccepted(clubId)
    local kept = {}
    for _, character in pairs(data().chars) do
        local guildId = character.guild and character.guild.id
        if guildId and (clubId == nil or guildId == clubId) and not kept[guildId]
            and ns.GuildSettings.EnforcesLinking(guildId) and Identity.EnforcedLinkingOptIn(guildId) ~= true
            and Identity.CompleteInGuild(guildId, character.ruleset) then
            kept[guildId] = true
        end
    end
    for guildId in pairs(kept) do
        Identity.SetEnforcedLinkingOptIn(guildId, true)
        for _, listener in ipairs(guildRuleKeptListeners) do listener(guildId) end
    end
end

---Before the Guild scope turns off: the guilds whose rule I accepted keep getting my characters in them.
function Identity.KeepGuildRulesAccepted()
    keepGuildRulesAccepted(nil)
end

---Saves my answer to a guild enforcing linking, or drops it (nil). Opting in or out changes what its members get.
---@param clubId integer
---@param optIn boolean?
function Identity.SetEnforcedLinkingOptIn(clubId, optIn)
    local identity = data()
    local wasOptedIn = Identity.EnforcedLinkingOptIn(clubId) == true
    identity.enforcedLinkingOptIns = identity.enforcedLinkingOptIns or {}
    identity.enforcedLinkingOptIns[clubId] = optIn
    if (optIn == true) ~= wasOptedIn then nextRevision() end
end

-- What I say in that guild, created when missing.
local function ownGuildEntry(clubId)
    local identity = data()
    identity.guilds = identity.guilds or {}
    identity.guilds[clubId] = identity.guilds[clubId] or {}
    return identity.guilds[clubId]
end

---Makes that character the one its guild shows me under.
---@param guid string
function Identity.SetGuildMain(guid)
    local character = data().chars[guid]
    local clubId = character and character.guild and character.guild.id
    if not clubId then return end
    local entry = ownGuildEntry(clubId)
    if entry.main == guid then return end
    entry.main = guid
    nextRevision()
end

---Sets my nickname in that guild; nil or an empty name goes back to my nickname.
---@param clubId integer
---@param nickname string?
---@return boolean ok
---@return WhosWho.NameErrorCode? err
function Identity.SetGuildNickname(clubId, nickname)
    local clean, err = ns.Record.CleanName(nickname)
    if err then return false, err end

    local entry = ownGuildEntry(clubId)
    if entry.nickname ~= clean then
        entry.nickname = clean
        nextRevision()
    end
    return true
end

---My nickname in that guild, nil when I set none.
---@param clubId integer
---@return string?
function Identity.GuildNickname(clubId)
    local entry = data().guilds and data().guilds[clubId]
    return entry and entry.nickname
end

---When the request of that kind from that guild I last answered was made; nil when I answered none.
---@param clubId integer
---@param kind string
---@return integer?
function Identity.AnsweredRequestAt(clubId, kind)
    local entry = data().guilds and data().guilds[clubId]
    return entry and entry.answered and entry.answered[kind]
end

---Remembers that I answered that guild's request of that kind, made at that time: it isn't asked again until a newer
---one. Changes no record.
---@param clubId integer
---@param kind string
---@param at integer
function Identity.AnswerRequest(clubId, kind, at)
    local entry = ownGuildEntry(clubId)
    entry.answered = entry.answered or {}
    entry.answered[kind] = at
end

---Whether that guild's members get a record of their own from me: the guild enforces linking, or I chose my main or my
---nickname in it.
---@param clubId integer
---@return boolean
function Identity.HasGuildContent(clubId)
    local entry = data().guilds and data().guilds[clubId]
    return ns.GuildSettings.EnforcesLinking(clubId) or (entry ~= nil and (entry.main ~= nil or entry.nickname ~= nil))
end

---Whether the character was unlinked after being linked: it declares no identity (NOID).
---@param guid string
---@return boolean
function Identity.IsRemoved(guid)
    local character = data().chars[guid]
    return character ~= nil and character.removedAt ~= nil
end

---@return integer
function Identity.LinkedCount()
    local count = 0
    for _, character in pairs(data().chars) do
        if character.linked then count = count + 1 end
    end
    return count
end

---Every character of this account, registered or not.
---@return table<string, WhosWho.OwnCharacter> characters by GUID
function Identity.Characters()
    return data().chars
end

---This account's linked characters, the main first, then by name.
---@return WhosWho.OwnCharacter[]
function Identity.LinkedCharacters()
    local identity = data()
    local characters = { identity.chars[identity.main] }

    local others = {}
    for guid, character in pairs(identity.chars) do
        if character.linked and guid ~= identity.main then others[#others + 1] = character end
    end
    table.sort(others, function(a, b) return a.name < b.name end)
    for _, character in ipairs(others) do characters[#characters + 1] = character end

    return characters
end

local function findFirstLinked(identity)
    local first
    for guid, character in pairs(identity.chars) do
        if character.linked and (not first or guid < first) then first = guid end
    end
    return first
end

local function setLinked(guid, linked)
    local identity = data()
    local character = identity.chars[guid]
    if not character then return end

    local wasLinked = character.linked == true
    character.linked = linked
    if wasLinked == linked then return end

    if linked and not identity.main then identity.main = guid end
    if not linked and identity.main == guid then identity.main = findFirstLinked(identity) end
    nextRevision()
    character.removedAt = not linked and time() or nil
end

---Adds one of this account's characters to the identity. The first one linked becomes the main.
---@param guid string
function Identity.Link(guid)
    setLinked(guid, true)
end

---Removes one of this account's characters from the identity. Unlinking the main makes another linked
---character the main.
---@param guid string
function Identity.Unlink(guid)
    local clubId = Identity.GuildId(guid)
    if clubId then keepGuildRulesAccepted(clubId) end
    setLinked(guid, false)
end

---Unlinks every character and removes the nickname, in one revision: each unlinked character declares no identity, and
---players forget the identity once its last character did. Every character becomes unregistered, so each one is asked
---again at its next login.
function Identity.Forget()
    keepGuildRulesAccepted(nil)
    local identity = data()
    local unlinked = {}
    for _, character in pairs(identity.chars) do
        if character.linked then unlinked[#unlinked + 1] = character end
        character.linked = nil
    end
    if not unlinked[1] and not identity.nickname then return end

    identity.main, identity.nickname = nil, nil
    nextRevision()
    for _, character in ipairs(unlinked) do character.removedAt = time() end
end

-- Main and nickname ------------------------------------------------------------------------------

---@return string? guid nil while no character is linked
---@return WhosWho.OwnCharacter? character
function Identity.Main()
    local identity = data()
    return identity.main, identity.chars[identity.main]
end

---@param guid string a linked character
---@return boolean ok false when the character is not linked
function Identity.SetMain(guid)
    if not Identity.IsLinked(guid) then return false end

    local identity = data()
    if identity.main ~= guid then
        identity.main = guid
        nextRevision()
    end
    return true
end

---Whether the identity has a nickname override; without one, it goes by its main character's name.
---@return boolean
function Identity.HasNickname()
    return data().nickname ~= nil
end

---The nickname override, or the main character's name.
---@return string? nickname nil while no character is linked
function Identity.Nickname()
    local _, main = Identity.Main()
    if not main then return nil end

    return data().nickname or main.name
end

---@param nickname string? nil removes the override: the main character's name is shown
---@return boolean ok
---@return WhosWho.NameErrorCode? err when refused
function Identity.SetNickname(nickname)
    local clean, err = ns.Record.CleanName(nickname)
    if err then return false, err end

    local identity = data()
    if identity.nickname ~= clean then
        identity.nickname = clean
        nextRevision()
    end
    return true
end

-- Record -----------------------------------------------------------------------------------------

---@return integer
function Identity.Revision()
    return data().rev
end

---Adds a function called after each change of revision.
---@param listener fun()
function Identity.OnRevisionChanged(listener)
    revisionListeners[#revisionListeners + 1] = listener
end

---My characters in that guild, the one I chose as its guild main first, then the linked ones, then by name: the first one
---stands for me there when I chose it, or when my main is not in it.
---@param clubId integer
---@param ruleset WhosWho.Ruleset?
---@return string[] guids
function Identity.CharactersInGuild(clubId, ruleset)
    local characters = data().chars
    local chosen = data().guilds and data().guilds[clubId] and data().guilds[clubId].main
    local guids = {}
    for guid, character in pairs(characters) do
        if character.guild and character.guild.id == clubId and character.ruleset == ruleset then
            guids[#guids + 1] = guid
        end
    end
    table.sort(guids, function(a, b)
        local aChosen, bChosen = a == chosen, b == chosen
        if aChosen ~= bChosen then return aChosen end
        local aLinked, bLinked = characters[a].linked == true, characters[b].linked == true
        if aLinked ~= bLinked then return aLinked end
        if characters[a].name ~= characters[b].name then return characters[a].name < characters[b].name end
        return a < b
    end)
    return guids
end

---The unsigned record of the current revision. Its general part: my linked characters, my nickname and my main. For the
---members of a guild whose members get a record of their own (Identity.HasGuildContent), that guild's entry: when it
---enforces linking, my characters in that guild too, listed as forced when the record has no general part or they
---aren't linked; the guild main I chose there, otherwise my main when it is in the guild, otherwise, when the guild
---enforces linking or the record has no general part, the first of my characters in it; my nickname there. Past
---Record.MAX_CHARACTERS, the main, the guild main and the lowest GUIDs are kept.
---@param general boolean whether the record holds the general part
---@param clubId integer? the guild whose members get the record; nil for no guild's entry
---@param ruleset WhosWho.Ruleset? that guild's ruleset
---@return WhosWho.IdentityRecord
function Identity.UnsignedRecord(general, clubId, ruleset)
    local identity = data()
    ---@type table<string, boolean> by GUID: the characters in the record, true for the ones that guild's rule adds
    local included = {}
    if general then
        for guid, character in pairs(identity.chars) do
            if character.linked then included[guid] = false end
        end
    end
    local main = general and identity.main or nil
    local guildMain
    local entry = clubId and identity.guilds and identity.guilds[clubId] or {}
    if clubId then
        local enforced = ns.GuildSettings.EnforcesLinking(clubId)
        local inGuild, mainInGuild = {}, false
        for _, guid in ipairs(Identity.CharactersInGuild(clubId, ruleset)) do
            if enforced and included[guid] == nil then included[guid] = true end
            if included[guid] ~= nil then
                inGuild[#inGuild + 1] = guid
                if guid == identity.main then mainInGuild = true end
            end
        end
        local chosen = inGuild[1] ~= nil and inGuild[1] == entry.main and inGuild[1] or nil
        guildMain = chosen or mainInGuild and identity.main or (enforced or not general) and inGuild[1] or nil
        if guildMain == main then guildMain = nil end
    end

    local others = {}
    for guid in pairs(included) do
        if guid ~= main and guid ~= guildMain then others[#others + 1] = guid end
    end
    table.sort(others)
    local guids = {}
    if main then guids[#guids + 1] = main end
    if guildMain then guids[#guids + 1] = guildMain end
    for i = 1, math.min(#others, ns.Record.MAX_CHARACTERS - #guids) do guids[#guids + 1] = others[i] end

    local chars, forced = {}, nil
    for _, guid in ipairs(guids) do
        local character = identity.chars[guid]
        chars[guid] = {
            name = character.name, ruleset = character.ruleset, classID = character.classID, raceID = character.raceID,
            maxLevelAt = character.maxLevelAt,
        }
        if included[guid] then
            forced = forced or {}
            forced[guid] = true
        end
    end
    -- The guild's entry only when it says something: otherwise its members get everyone's record.
    local guild = { consent = ns.Scopes.Get("guild") }
    if clubId and (guildMain or forced or entry.nickname) then
        guild.id, guild.main, guild.nickname, guild.forced = clubId, guildMain, entry.nickname, forced
    end
    return {
        v = ns.Record.VERSION, id = identity.id, rev = identity.rev, nickname = general and identity.nickname or nil,
        main = main, chars = chars, guild = guild,
    }
end

---The signed bytes of my record without its revision: equal while it says the same.
---@param general boolean
---@param clubId integer?
---@param ruleset WhosWho.Ruleset?
---@return string
function Identity.RecordBytesWithoutRevision(general, clubId, ruleset)
    return ns.Record.CanonicalWithoutRevision(Identity.UnsignedRecord(general, clubId, ruleset))
end

---Signing takes about 120 ms in game, so each record's signature is kept while it covers the same bytes.
---@param general boolean
---@param clubId integer?
---@param ruleset WhosWho.Ruleset?
---@return WhosWho.SignedIdentityRecord
function Identity.SignedRecord(general, clubId, ruleset)
    local identity = data()
    local record = Identity.UnsignedRecord(general, clubId, ruleset)
    ---@cast record WhosWho.SignedIdentityRecord
    local digest = ns.Crypto.ToHex(ns.Crypto.SHA512(ns.Record.Canonical(record)))
    local signatures = identity.signatures or {}
    identity.signatures = signatures
    if signatures[digest] then
        record.sig = signatures[digest]
        return record
    end

    ns.Record.Sign(record, identity.seed)
    signatures[digest] = record.sig
    return record
end

---Signs bytes with my identity's key (about 120 ms in game).
---@param bytes string
---@return string sig 128 hex characters
function Identity.Sign(bytes)
    local identity = data()
    return ns.Crypto.ToHex(ns.Crypto.Ed25519.Sign(bytes, ns.Crypto.FromHex(identity.seed), ns.Crypto.FromHex(identity.id)))
end

---The Guild scope changed: it is the record's guild consent, so the record gets a new revision.
function Identity.GuildScopeChanged()
    nextRevision()
end
