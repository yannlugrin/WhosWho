local _, ns = ...
---@cast ns WhosWho.Namespace

-- Saved data and settings moved from the formats of older versions to the current ones, at load (Store.Init). Each
-- step runs once, in order: the number of the last one run is saved as migrationVersion. A step only reads and changes
-- the saved tables: what needs the game (roster, sending) is not a migration. The beta's steps went with its data
-- (Migrations.LeaveBeta): the steps below are the live game's.

---@class WhosWho.Migrations
local Migrations = {}
ns.Migrations = Migrations

---@type fun(data: WhosWho.Data)[]
local DATA_STEPS = {}

---@type fun(settings: WhosWho.Settings)[]
local SETTINGS_STEPS = {}

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

---Before the migrations. 1.0.0 came out after the beta closed: data no 1.0.0 or later loaded yet (no addonVersion) comes
---from the beta, whose characters, people and guilds ended with it. It starts over, once, as on a first install, my
---identity included (new keys at the first link). The settings keep everything; their migration count starts again.
---@param data WhosWho.Data the account-wide data, with its logout tables
---@param settings WhosWho.Settings the profile
function Migrations.LeaveBeta(data, settings)
    if data.addonVersion then return end

    for key in pairs(data) do data[key] = nil end
    for key, value in pairs(ns.Store.NewData()) do data[key] = value end
    settings.migrationVersion = nil
end
