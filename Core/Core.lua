local addonName, ns = ...
---@cast ns WhosWho.Namespace

---The add-on's private table, shared by every file.
---@class WhosWho.Namespace
---@field L table<string, string>
---@field Version string
---@field Print fun(msg: string)
---@field UnitWholeName fun(unit: string): string?
---@field Commands table<string, fun(rest: string)>
---@field db table AceDB object
---@field data WhosWho.Data
---@field settings WhosWho.Settings
---@field Crypto WhosWho.Crypto
---@field Store WhosWho.Store
---@field Record WhosWho.Record
---@field Identity WhosWho.Identity
---@field AutomaticChanges WhosWho.AutomaticChanges
---@field People WhosWho.People
---@field Resolver WhosWho.Resolver
---@field RecordVerification WhosWho.RecordVerification
---@field Codec WhosWho.Codec
---@field Scopes WhosWho.Scopes
---@field Protocol WhosWho.Protocol

-- Add-on -----------------------------------------------------------------------------------------

ns.L = LibStub("AceLocale-3.0"):GetLocale(addonName)
local L = ns.L

-- Unpackaged builds keep the packager's version keyword.
local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
ns.Version = (not version or version:find("^@")) and "Dev" or version

---Prints to the chat frame with the add-on's prefix.
---@param msg string
function ns.Print(msg)
    print("|cff66bbff" .. L["Who's Who"] .. "|r " .. msg)
end

---A player's whole name, "First Surname" (UnitName returns the first name only).
---@param unit string
---@return string?
function ns.UnitWholeName(unit)
    local name, surname = UnitNameUnmodified(unit)
    return surname and (name .. " " .. surname) or name
end

-- Events -----------------------------------------------------------------------------------------

local function ruleset()
    local RULESET, rules = ns.Record.RULESET, Enum.GameRule
    if not (C_GameRules and rules) then return RULESET.Normal end
    if rules.HardcoreRuleset and C_GameRules.IsGameRuleActive(rules.HardcoreRuleset) then return RULESET.Hardcore end
    if rules.RPRuleset and C_GameRules.IsGameRuleActive(rules.RPRuleset) then return RULESET.RP end
    if rules.PvPRuleset and C_GameRules.IsGameRuleActive(rules.PvPRuleset) then return RULESET.PvP end
    return RULESET.Normal
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("FRIENDLIST_UPDATE")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
frame:SetScript("OnEvent", function(_, event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" and arg1 == addonName then
        ns.Store.Init()
    elseif event == "PLAYER_LOGIN" then
        ns.Identity.EnsureKeys()
        local _, _, classID = UnitClass("player")
        ns.Identity.Refresh(UnitGUID("player"), ns.UnitWholeName("player"), ruleset(), classID, UnitLevel("player"))
        ns.Protocol.Start()
        ns.Protocol.AnnounceLogin()
        if IsInGuild() then C_GuildInfo.GuildRoster() end
    elseif event == "PLAYER_LOGOUT" then
        -- Also fires on /reload; saved variables are written right after it.
        ns.Identity.Seen(UnitGUID("player"), UnitLevel("player"))
        ns.Protocol.AnnounceLogout()
    elseif event == "PLAYER_LEVEL_UP" then
        -- arg1 is the new level.
        ns.Identity.Seen(UnitGUID("player"), arg1)
        ns.Protocol.AnnounceLevel(arg1)
    elseif event == "PLAYER_GUILD_UPDATE" and arg1 == "player" then
        ns.Scopes.GuildChanged()
    elseif event == "GUILD_ROSTER_UPDATE" then
        ns.Scopes.ReadGuildRoster()
    elseif event == "FRIENDLIST_UPDATE" then
        ns.Scopes.ReadFriends()
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        -- The other player's name and GUID.
        local name, guid = select(2, ...), select(12, ...)
        ns.Scopes.Whispered(name, guid)
    end
end)

-- Slash commands ---------------------------------------------------------------------------------

ns.Commands = {}

local function help()
    ns.Print(L["Commands: /ww status, /ww link, /ww unlink, /ww main, /ww nick <name>, /ww nick (back to the main character's name)"])
end

ns.Commands.status = function()
    local guid = UnitGUID("player")
    ns.Print(L["Version: %s"]:format(ns.Version))
    ns.Print(L["Nickname: %s"]:format(ns.Identity.Nickname() or L["(no linked character)"]))
    local state
    if ns.Identity.Main() == guid then
        state = L["linked, main"]
    elseif ns.Identity.IsLinked(guid) then
        state = L["linked"]
    else
        state = ns.Identity.IsAsked(guid) and L["not linked"] or L["not asked yet"]
    end
    ns.Print(L["This character: %s"]:format(state))
    ns.Print(L["Linked characters: %d"]:format(ns.Identity.LinkedCount()))
end

ns.Commands.link = function()
    ns.Identity.Link(UnitGUID("player"))
    ns.Print(L["This character is now linked to your identity."])
end

ns.Commands.unlink = function()
    ns.Identity.Unlink(UnitGUID("player"))
    ns.Print(L["This character is no longer linked to your identity."])
end

ns.Commands.main = function()
    if not ns.Identity.SetMain(UnitGUID("player")) then
        ns.Print(L["Link this character first: /ww link"])
        return
    end
    ns.Print(L["This character is now your main."])
end

local REASONS = {
    short = L["The name is too short."],
    long = L["The name is too long."],
    invalid = L["The name contains characters that are not allowed."],
}

ns.Commands.nick = function(rest)
    local ok, err = ns.Identity.SetNickname(rest ~= "" and rest or nil)
    if not ok then
        ns.Print(REASONS[err] or err)
        return
    end
    ns.Print(L["Nickname: %s"]:format(ns.Identity.Nickname() or L["(no linked character)"]))
end

SLASH_WHOSWHO1 = "/ww"
SLASH_WHOSWHO2 = "/whoswho"
SlashCmdList.WHOSWHO = function(input)
    local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local fn = ns.Commands[command:lower()]
    if fn then fn(rest) else help() end
end
