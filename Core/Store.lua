local addonName, ns = ...
---@cast ns WhosWho.Namespace

---@class WhosWho.Store
local Store = {}
ns.Store = Store

---An identity whose player unlinked every character.
---@class WhosWho.ForgottenIdentity
---@field rev integer the revision in which the player unlinked every character
---@field at number seconds, from time(): when I forgot it

---Account-wide saved data (WhosWhoDB.global), the table every model module works on.
---@class WhosWho.Data
---@field identity WhosWho.IdentityData
---@field people table<string, WhosWho.Person> by identity ID
---@field nextManual integer number of the next manual person ("M<n>")
---@field forgotten table<string, WhosWho.ForgottenIdentity> by identity ID
---@field noIdentity table<string, number> GUID -> when (time()) the character last declared no identity (NOID), until it confirms one
---@field automaticChanges WhosWho.AutomaticChange[] most recent first, at most 100
---@field whispers table<string, WhosWho.Whisper> by the other character's GUID, within the whisper window
---@field guildSettings table<integer, WhosWho.HeldGuildSettings> by club ID: each guild's settings as I hold them
---@field guildLists table<integer, WhosWho.GuildListRevision> by club ID: my list's revision for each guild
---@field migrationVersion integer? the last migration step run on the data (Migrations)
---@field messageLog WhosWho.LoggedMessage[] while the diagnostic mode is on, most recent first, at most Diagnostic.KEPT_MESSAGES; emptied at logout while it is off

---Settings (WhosWhoDB.profile; one "Default" profile shared by every character).
---@class WhosWho.Settings
---@field scopes { guild: boolean, friends: boolean, whispers: boolean, group: boolean }
---@field whisperHours integer the whisper window: how long a whisper counts
---@field advanced WhosWho.AdvancedSettings delays of the protocol a player may change (no screen yet)
---@field chat { nickname: { enable: boolean } } the nickname after the sender's name
---@field tooltip { nickname: { enable: boolean, position: "afterName"|"ownLine" }, otherCharacters: { enable: boolean, classColor: boolean, limit: integer }, note: { enable: boolean } } the nickname, and the "Also:" line: shown, names in class colour, characters named before the others are counted; the start of my note about the person
---@field diagnostic { enable: boolean, chat: boolean } the diagnostic mode: every Who's Who message sent or received kept in the message log, and printed in chat
---@field launcher { hide: boolean, showInCompartment: boolean, minimapPos: number? } LibDBIcon's own format: the minimap button and the add-on compartment entry
---@field migrationVersion integer? the last migration step run on the settings (Migrations)

Store.DEFAULTS = {
    global = {
        identity = { rev = 1, chars = {} },
        nextManual = 1,
        forgotten = {},
        noIdentity = {},
        automaticChanges = {},
        guildSettings = {},
        guildLists = {},
        messageLog = {},
    },
    profile = {
        scopes = { guild = true, friends = true, whispers = false, group = false },
        whisperHours = 3,
        advanced = {
            revisionWaitSeconds = 15, quickRelogSeconds = 5 * 60, whisperAnnouncementSeconds = 30 * 60,
            loginWhispersSeconds = 30 * 60,
        },
        chat = { nickname = { enable = true } },
        tooltip = {
            nickname = { enable = true, position = "afterName" },
            otherCharacters = { enable = true, classColor = true, limit = 4 },
            note = { enable = true },
        },
        diagnostic = { enable = false, chat = true },
        launcher = { hide = false, showInCompartment = true },
    },
}

-- Data tables read on PLAYER_LOGOUT. AceDB removes the defaults from the saved data before the add-on's own handler
-- runs, an empty table included, so these are not defaults: they are created when missing.
local LOGOUT_TABLES = { "people", "whispers" }

---@param data table
local function createLogoutTables(data)
    for _, key in ipairs(LOGOUT_TABLES) do data[key] = data[key] or {} end
end

---Delays of the protocol a player may change, in seconds (no screen yet).
---@class WhosWho.AdvancedSettings
---@field revisionWaitSeconds number before a change of revision is announced, gathering the changes that follow
---@field quickRelogSeconds number a login this soon after the same character's logout announces nothing
---@field whisperAnnouncementSeconds number after that, whispering a player sends my announcement again
---@field loginWhispersSeconds number at login, the people whispered this long before the logout get the announcement

---An advanced setting: its saved value, otherwise its default. On PLAYER_LOGOUT, AceDB may already have removed the
---values equal to their defaults.
---@param key "revisionWaitSeconds"|"quickRelogSeconds"|"whisperAnnouncementSeconds"|"loginWhispersSeconds"
---@return number
function Store.Advanced(key)
    local advanced = ns.settings.advanced
    local value = advanced and advanced[key]
    if value == nil then return Store.DEFAULTS.profile.advanced[key] end
    return value
end

---Sets ns.db, ns.data and ns.settings. Call on ADDON_LOADED.
function Store.Init()
    local db = LibStub("AceDB-3.0"):New(addonName .. "DB", Store.DEFAULTS, true)
    ns.db = db
    ns.data = db.global
    createLogoutTables(ns.data)
    ns.Migrations.Data(ns.data)
    ns.settings = db.profile
    ns.Migrations.Settings(ns.settings)
end

---A fresh data table with the defaults, for the offline tests.
---@return WhosWho.Data
function Store.NewData()
    local function copy(t)
        local out = {}
        for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
        return out
    end
    local data = copy(Store.DEFAULTS.global)
    createLogoutTables(data)
    return data
end
