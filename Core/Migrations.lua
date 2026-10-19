local _, ns = ...
---@cast ns WhosWho.Namespace

-- Saved data and settings moved from the formats of older versions to the current ones, at load (Store.Init). Each
-- step runs once, in order: the number of the last one run is saved as migrationVersion. A step only reads and changes
-- the saved tables: what needs the game (roster, sending) is not a migration.

---@class WhosWho.Migrations
local Migrations = {}
ns.Migrations = Migrations

---@type fun(data: WhosWho.Data)[]
local DATA_STEPS = {
    -- 1. 0.1.0-beta.1: an unlinked character kept the revision that removed it, which it announced, and a forgotten
    -- identity only its revision; their times are unknown, so they get the migration's.
    function(data)
        for _, character in pairs(data.identity.chars) do
            if character.removedInRevision then character.removedAt, character.removedInRevision = time(), nil end
        end
        for id, forgotten in pairs(data.forgotten) do
            if type(forgotten) == "number" then data.forgotten[id] = { rev = forgotten, at = time() } end
        end
    end,
    -- 2. 0.1.0: my character's guild was its club ID.
    function(data)
        for _, character in pairs(data.identity.chars) do
            if type(character.guild) == "number" then character.guild = { id = character.guild } end
        end
    end,
    -- 3. 0.1.1: one signature, of the only record (each record is now signed apart, Identity.SignedRecord); a guild's
    -- settings were its record alone.
    function(data)
        data.identity.sig, data.identity.signedDigest = nil, nil
        for clubId, held in pairs(data.guildSettings) do
            if held.v then data.guildSettings[clubId] = { record = held } end
        end
    end,
    -- 4. 0.2.0: records were signed over a fixed list of fields (Record.VERSION 1), which the current version refuses.
    -- The others hold my revision in that format and would not ask for the same revision again: a new one makes them
    -- fetch it in the current format.
    function(data)
        local identity = data.identity
        if identity.id then identity.rev, identity.signatures = identity.rev + 1, nil end
    end,
    -- 5. 0.3.0: a character of a player's record passed on by my guild had the state "guild", now "relayed" ("guild"
    -- is what the guild itself links).
    function(data)
        for _, person in pairs(data.people) do
            for _, character in pairs(person.chars) do
                if character.state == "guild" then character.state = "relayed" end
            end
        end
    end,
    -- 6. 0.4.3: a player's identity whose characters all confirmed other identities was kept without any (People).
    function(data)
        for id, person in pairs(data.people) do
            if person.signedRecord and not next(person.chars) then data.people[id] = nil end
        end
    end,
}

---@type fun(settings: WhosWho.Settings)[]
local SETTINGS_STEPS = {
    -- 1. 0.1.0-beta.1: chatNicknames, tooltipNickname, tooltipOtherCharacters (a boolean, later a table).
    function(settings)
        if settings.chatNicknames ~= nil then
            settings.chat.nickname.enable = settings.chatNicknames
            settings.chatNicknames = nil
        end
        if settings.tooltipNickname ~= nil then
            if settings.tooltipNickname == "hidden" then
                settings.tooltip.nickname.enable = false
            else
                settings.tooltip.nickname.position = settings.tooltipNickname
            end
            settings.tooltipNickname = nil
        end
        local otherCharacters = settings.tooltipOtherCharacters
        if type(otherCharacters) == "table" then
            for key, value in pairs(otherCharacters) do settings.tooltip.otherCharacters[key] = value end
        elseif otherCharacters ~= nil then
            settings.tooltip.otherCharacters.enable = otherCharacters
        end
        settings.tooltipOtherCharacters = nil
    end,
    -- 2. 0.1.1: debugMessages, the diagnostic mode, which printed every message in chat.
    function(settings)
        if settings.debugMessages ~= nil then
            settings.diagnostic.enable = settings.debugMessages
            settings.debugMessages = nil
        end
    end,
}

-- Runs the steps after the saved migrationVersion. A version saved by a later release than this one is kept, so its
-- own steps don't run again once it is back.
local function run(steps, saved)
    local version = saved.migrationVersion or 0
    for i = version + 1, #steps do steps[i](saved) end
    saved.migrationVersion = math.max(version, #steps)
end

---@param data WhosWho.Data the account-wide data, with its logout tables
function Migrations.Data(data)
    run(DATA_STEPS, data)
end

---@param settings WhosWho.Settings the profile, with the current defaults
function Migrations.Settings(settings)
    run(SETTINGS_STEPS, settings)
end
