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
---@field automaticChanges WhosWho.AutomaticChange[] most recent first, at most 100

---Settings (WhosWhoDB.profile; one "Default" profile shared by every character).
---@class WhosWho.Settings
---@field scopes { guild: boolean, friends: boolean, whispers: boolean, group: boolean }
---@field chat { nickname: { enable: boolean } } the nickname after the sender's name
---@field tooltip { nickname: { enable: boolean, position: "afterName"|"ownLine" }, otherCharacters: { enable: boolean, classColor: boolean, limit: integer } } the nickname, and the "Also:" line: shown, names in class colour, characters named before the others are counted
---@field debugMessages boolean every Who's Who message sent or received, printed in chat
---@field launcher { hide: boolean, showInCompartment: boolean, minimapPos: number? } LibDBIcon's own format: the minimap button and the add-on compartment entry

Store.DEFAULTS = {
    global = {
        identity = { rev = 1, chars = {} },
        people = {},
        nextManual = 1,
        forgotten = {},
        automaticChanges = {},
    },
    profile = {
        scopes = { guild = true, friends = true, whispers = false, group = false },
        chat = { nickname = { enable = true } },
        tooltip = {
            nickname = { enable = true, position = "afterName" },
            otherCharacters = { enable = true, classColor = true, limit = 4 },
        },
        debugMessages = false,
        launcher = { hide = false, showInCompartment = true },
    },
}

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

---Sets ns.db, ns.data and ns.settings. Call on ADDON_LOADED.
function Store.Init()
    local db = LibStub("AceDB-3.0"):New(addonName .. "DB", Store.DEFAULTS, true)
    ns.db = db
    ns.data = db.global
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
    return copy(Store.DEFAULTS.global)
end
