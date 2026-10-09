local addonName, ns = ...
---@cast ns WhosWho.Namespace

---@class WhosWho.Store
local Store = {}
ns.Store = Store

---Account-wide saved data (WhosWhoDB.global), the table every model module works on.
---@class WhosWho.Data
---@field identity WhosWho.IdentityData
---@field people table<string, WhosWho.Person> by identity ID
---@field nextManual integer number of the next manual person ("M<n>")
---@field forgotten table<string, integer> identity ID -> revision in which the player unlinked every character
---@field noIdentity table<string, number> GUID -> when (time()) the character last declared no identity (NOID), until it confirms one
---@field automaticChanges WhosWho.AutomaticChange[] most recent first, at most 100
---@field whispers table<string, WhosWho.Whisper> by the other character's GUID, within the whisper window

---Settings (WhosWhoDB.profile; one "Default" profile shared by every character).
---@class WhosWho.Settings
---@field scopes { guild: boolean, friends: boolean, whispers: boolean, group: boolean }
---@field whisperHours integer the whisper window: how long a whisper counts
---@field advanced WhosWho.AdvancedSettings delays of the protocol a player may change (no screen yet)
---@field chat { nickname: { enable: boolean } } the nickname after the sender's name
---@field tooltip { nickname: { enable: boolean, position: "afterName"|"ownLine" }, otherCharacters: { enable: boolean, classColor: boolean, limit: integer }, note: { enable: boolean } } the nickname, and the "Also:" line: shown, names in class colour, characters named before the others are counted; the start of my note about the person
---@field debugMessages boolean every Who's Who message sent or received, printed in chat
---@field launcher { hide: boolean, showInCompartment: boolean, minimapPos: number? } LibDBIcon's own format: the minimap button and the add-on compartment entry

Store.DEFAULTS = {
    global = {
        identity = { rev = 1, chars = {} },
        nextManual = 1,
        forgotten = {},
        noIdentity = {},
        automaticChanges = {},
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
        debugMessages = false,
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
---@field loginWhispersSeconds number at login, the people the same character whispered this long before its logout get
---the announcement

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

---Moves settings saved under older keys to the current ones, and removes the older keys.
---@param settings table the profile, with the current defaults
function Store.MigrateSettings(settings)
    -- 0.1.0-beta.1: chatNicknames, tooltipNickname, tooltipOtherCharacters (a boolean, later a table).
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
end

---Moves data saved in older formats to the current one.
---@param data WhosWho.Data
function Store.MigrateData(data)
    -- 0.1.0-beta.1: an unlinked character kept the revision that removed it, which it announced; its removal time is
    -- unknown, so it gets the migration's.
    for _, character in pairs(data.identity.chars) do
        if character.removedInRevision then character.removedAt, character.removedInRevision = time(), nil end
    end
end

---Sets ns.db, ns.data and ns.settings. Call on ADDON_LOADED.
function Store.Init()
    local db = LibStub("AceDB-3.0"):New(addonName .. "DB", Store.DEFAULTS, true)
    ns.db = db
    ns.data = db.global
    createLogoutTables(ns.data)
    Store.MigrateData(ns.data)
    ns.settings = db.profile
    Store.MigrateSettings(ns.settings)
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
