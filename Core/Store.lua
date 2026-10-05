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
---@field chatNicknames boolean
---@field tooltipNickname "afterName"|"ownLine"|"hidden"
---@field tooltipOtherCharacters boolean the "Also:" line
---@field debugMessages boolean every Who's Who message sent or received, printed in chat

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
        chatNicknames = true,
        tooltipNickname = "ownLine",
        tooltipOtherCharacters = true,
        debugMessages = false,
    },
}

---Sets ns.db, ns.data and ns.settings. Call on ADDON_LOADED.
function Store.Init()
    local db = LibStub("AceDB-3.0"):New(addonName .. "DB", Store.DEFAULTS, true)
    ns.db = db
    ns.data = db.global
    ns.settings = db.profile
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
