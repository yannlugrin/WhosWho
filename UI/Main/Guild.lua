local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local issecretvalue = issecretvalue or function() return false end
local Main = ns.Main
local Lists = ns.Lists
local PersonBrowser = ns.PersonBrowser
local window = Main.Window

-- Right of the window's portrait.
local TOP_BAR_LEFT = 70
local SEARCH_WIDTH = 190
local LIST_TOP = -62

local panel = CreateFrame("Frame", nil, window)
panel:SetAllPoints()
Main.Guild = panel
Main.AddTab(L["Guild"], panel)

-- Header -----------------------------------------------------------------------------------------

-- The guild's name, my rank, the search and the counts at the right.
panel.GuildName = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.GuildName:SetPoint("TOPLEFT", TOP_BAR_LEFT + 6, -36)
panel.GuildName:SetWordWrap(false)

panel.Rank = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
panel.Rank:SetPoint("LEFT", panel.GuildName, "RIGHT", 12, 0)
panel.Rank:SetWordWrap(false)

panel.SearchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
panel.SearchBox:SetSize(SEARCH_WIDTH, 20)
panel.SearchBox:SetPoint("LEFT", panel.Rank, "RIGHT", 18, 0)
panel.SearchBox.Instructions:SetText(L["Search names or characters"])

panel.Counts = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
panel.Counts:SetPoint("LEFT", panel.SearchBox, "RIGHT", 12, 0)
panel.Counts:SetPoint("RIGHT", -12, 0)
panel.Counts:SetJustifyH("RIGHT")
panel.Counts:SetWordWrap(false)

-- Sharing ----------------------------------------------------------------------------------------

-- The footer: what the guild gets from me, and the action that changes it when there is one.
local sharing = Lists.CreateFooter(panel)
panel.Sharing = sharing

sharing.Icon = sharing.Content:CreateTexture(nil, "OVERLAY")
sharing.Icon:SetSize(14, 14)
sharing.Icon:SetPoint("LEFT", 10, 0)
sharing.Icon:SetTexture(ns.Glyphs.Nickname.guild.texture)
sharing.Icon:SetVertexColor(NORMAL_FONT_COLOR:GetRGB())

sharing.Button = CreateFrame("Button", nil, sharing.Content, "UIPanelButtonTemplate")
sharing.Button:SetSize(96, 22)
sharing.Button:SetPoint("RIGHT", -5, 0)

sharing.Text = sharing.Content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
sharing.Text:SetPoint("LEFT", sharing.Icon, "RIGHT", 6, 0)
sharing.Text:SetPoint("RIGHT", sharing.Button, "LEFT", -8, 0)
sharing.Text:SetJustifyH("LEFT")
sharing.Text:SetWordWrap(false)

-- List and detail panel --------------------------------------------------------------------------

local browser = PersonBrowser.Create(panel, LIST_TOP, Lists.FOOTER_SPACE)
panel.Browser = browser

-- Data -------------------------------------------------------------------------------------------

local Identity, People = ns.Identity, ns.People

-- Class IDs by the class file name the roster gives, filled at first use.
---@type table<string, integer>?
local classIdByFile

local function classIdOf(classFile)
    if not classIdByFile then
        classIdByFile = {}
        for classID = 1, GetNumClasses() do
            local _, file = GetClassInfo(classID)
            if file then classIdByFile[file] = classID end
        end
    end
    return classIdByFile[classFile]
end

---A member of my guild, as the roster shows it.
---@class WhosWho.GuildMember
---@field guid string
---@field name string
---@field classID integer?
---@field level integer
---@field online boolean

---The members of my guild, from the roster.
---@return WhosWho.GuildMember[]
local function guildMembers()
    local members = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        local guid = select(17, GetGuildRosterInfo(i))
        local secret = issecretvalue(name) or issecretvalue(guid) or issecretvalue(level) or issecretvalue(online)
            or issecretvalue(classFile)
        if name and guid and not secret then
            members[#members + 1] = {
                guid = guid, name = name, classID = classIdOf(classFile), level = level, online = online == true,
            }
        end
    end
    return members
end

-- The list's sort: "Name" (A to Z when ascending) or "LastSeen" (oldest first when ascending). At first, online
-- people, then the most recently seen; equal ones by name.
local sortKey, sortAscending = "LastSeen", false

-- My record as my guild's members get it: the guild's content when it enforces linking and my identity is complete
-- there, my linked characters otherwise.
---@return WhosWho.IdentityRecord
local function ownGuildRecord()
    return Identity.UnsignedRecord(ns.Scopes.EnforcedGuild())
end

-- The name my guild's members show me under: my nickname, otherwise the name of the main they see.
local function ownNickname(record)
    return record.nickname or record.chars[ns.Record.ShownMain(record)].name
end

-- My own identity's row: the characters my guild gets, the one I play online.
---@param record WhosWho.IdentityRecord
---@return WhosWho.PersonListEntry
local function ownListEntry(record)
    local ownCharacterGuid, ownCharacters = UnitGUID("player"), Identity.Characters()
    local characterCount, lastSeen, onlineCharacter = 0, nil, nil
    for guid, character in pairs(record.chars) do
        characterCount = characterCount + 1
        local seen = ownCharacters[guid].lastSeen
        if not lastSeen or seen > lastSeen then lastSeen = seen end
        if guid == ownCharacterGuid then
            onlineCharacter = { guid = guid, name = character.name, classID = character.classID }
        end
    end
    return {
        id = Identity.Id(), nickname = ownNickname(record), source = "confirmed", characterCount = characterCount,
        lastSeen = lastSeen, online = onlineCharacter ~= nil, onlineCharacter = onlineCharacter,
    }
end

---@param record WhosWho.IdentityRecord
---@return WhosWho.PersonDetail
local function ownDetail(record)
    local ownCharacterGuid, ownCharacters = UnitGUID("player"), Identity.Characters()
    local mainGuid = ns.Record.ShownMain(record)
    local characters = {}
    for guid, character in pairs(record.chars) do
        local ownCharacter = ownCharacters[guid]
        characters[#characters + 1] = {
            guid = guid,
            name = character.name, classID = character.classID, state = "confirmed", main = guid == mainGuid,
            online = guid == ownCharacterGuid, lastSeen = ownCharacter.lastSeen, level = ownCharacter.level,
            ruleset = character.ruleset,
        }
    end
    PersonBrowser.SortCharacters(characters)
    return {
        nickname = ownNickname(record), source = "confirmed", characters = characters, id = Identity.Id(), own = true,
    }
end

-- Whether the search text, lowercased, is in my nickname or the name of a character my guild gets.
---@param record WhosWho.IdentityRecord
local function ownMatchesSearch(record, text)
    if text == "" or ownNickname(record):lower():find(text, 1, true) then return true end
    for _, character in pairs(record.chars) do
        if character.name:lower():find(text, 1, true) then return true end
    end
    return false
end

-- The sharing line's action, nil when there is none.
---@type fun()?
local sharingAction

-- The sharing line: my answer to my guild's rule while it enforces linking, otherwise the Guild scope.
local function refreshSharing()
    local guid = UnitGUID("player")
    local answer = ns.Scopes.GuildRuleAnswer()
    local text, button
    if answer == "accepted" then
        local allLinked = Identity.AllLinkedInGuild(Identity.GuildId(guid), Identity.Ruleset(guid))
        text = allLinked and L["your characters here are linked and shared with the guild."]
            or L["your characters here are shared with the guild without being linked."]
    elseif answer == "refused" then
        text = ORANGE_FONT_COLOR:WrapTextInColorCode(L["you refused, so Who's Who shares nothing with this guild."])
        button, sharingAction = L["Change"], ns.IdentityDialogs.ShowGuildRule
    elseif answer == "unanswered" then
        text = YELLOW_FONT_COLOR:WrapTextInColorCode(L["you haven't answered yet, so Who's Who shares nothing with this guild."])
        button, sharingAction = L["Answer"], ns.IdentityDialogs.ShowGuildRule
    elseif Identity.LinkedCount() == 0 then
        text = L["Nothing is shared with this guild: no character is linked to your identity."]
        button, sharingAction = L["Link"], ns.IdentityDialogs.AskToLink
    elseif ns.Scopes.Get("guild") then
        text = L["Your identity is shared with this guild's members."]
    else
        text = L["Your identity isn't shared with this guild: sharing with your guild is off."]
        button, sharingAction = L["Share"], function() ns.Scopes.Set("guild", true) end
    end
    if answer then text = NORMAL_FONT_COLOR:WrapTextInColorCode(L["Requires linking:"]) .. " " .. text end
    sharing.Text:SetText(text)
    sharing.Button:SetText(button or "")
    sharing.Button:SetShown(button ~= nil)
    if not button then sharingAction = nil end
end
sharing.Button:SetScript("OnClick", function() if sharingAction then sharingAction() end end)

---Selects a person, or my own identity: their row is marked and the detail panel shows them; nil clears the
---selection.
---@param id string?
function panel:Select(id)
    if id and id == Identity.Id() then
        browser:SetSelected(id)
        browser:SetPerson(ownDetail(ownGuildRecord()))
        return
    end
    local person = id and People.Get(id)
    browser:SetSelected(person and id or nil)
    browser:SetPerson(person and PersonBrowser.PersonDetail(person, ns.Scopes.OnlineGuids()) or nil)
end

---Fills the header from my guild, and the list from its roster: a row for each identity whose main is in it,
---mine included, and one for each character no identity holds, mine my guild doesn't get included, with the search
---applied; the selected row again while the list still shows it.
function panel:Refresh()
    local guildName, rankName = GetGuildInfo("player")
    self.GuildName:SetText(guildName and ("<%s>"):format(guildName) or "")
    self.Rank:SetText(rankName or "")

    local text = self.SearchBox:GetText():lower()
    local onlineGuids = ns.Scopes.OnlineGuids()
    local ownRecord = ownGuildRecord()
    local ownMainGuid = ns.Record.ShownMain(ownRecord)
    local entries, selectedShown = {}, false
    local mainCount, altCount, unknownCount = 0, 0, 0
    for _, member in ipairs(guildMembers()) do
        local guid = member.guid
        local person = People.Find(guid)
        local entry
        if ownRecord.chars[guid] then
            if guid ~= ownMainGuid then
                altCount = altCount + 1
            else
                mainCount = mainCount + 1
                if ownMatchesSearch(ownRecord, text) then entry = ownListEntry(ownRecord) end
            end
        elseif person then
            if guid ~= person.main then
                altCount = altCount + 1
            else
                mainCount = mainCount + 1
                if Lists.MatchesSearch(person, text) then
                    entry = PersonBrowser.ListEntry(person, onlineGuids)
                    -- The nickname mine replaces, after mine.
                    local baseNickname = PersonBrowser.BaseNickname(person)
                    entry.nicknameAside = baseNickname and GRAY_FONT_COLOR:WrapTextInColorCode(baseNickname)
                end
            end
        else
            unknownCount = unknownCount + 1
            if text == "" or member.name:lower():find(text, 1, true) then
                entry = {
                    nickname = member.name, source = "unconfirmed", characterCount = 1, online = member.online,
                    unknownCharacter = {
                        guid = guid, name = member.name,
                        newCharacter = member.classID and {
                            name = member.name, classID = member.classID, level = member.level,
                            ruleset = Identity.Ruleset(UnitGUID("player")),
                        },
                    },
                }
            end
        end
        if entry then
            entries[#entries + 1] = entry
            if entry.id and entry.id == browser.selectedId then selectedShown = true end
        end
    end
    self.Counts:SetText(L["%d |4main character:main characters; · %d |4alt:alts; · %d unknown"]:format(mainCount,
        altCount, unknownCount))

    PersonBrowser.SortEntries(entries, sortKey, sortAscending)
    browser.ListHeader:SetSort(sortKey, sortAscending)
    browser:SetEntries(entries)
    self:Select(selectedShown and browser.selectedId or nil)
    refreshSharing()
end

-- A click on the active column reverses it; another column starts A to Z for names, most recent first for last seen.
local function sortBy(key)
    if key == sortKey then
        sortAscending = not sortAscending
    else
        sortKey, sortAscending = key, key == "Name"
    end
    panel:Refresh()
end
browser.ListHeader.Labels.Name:SetScript("OnClick", function() sortBy("Name") end)
browser.ListHeader.Labels.LastSeen:SetScript("OnClick", function() sortBy("LastSeen") end)

panel.SearchBox:HookScript("OnTextChanged", function() panel:Refresh() end)
panel:SetScript("OnShow", function(self)
    self:Refresh()
    -- The roster comes from the game, which sends it again when asked.
    if IsInGuild() then C_GuildInfo.GuildRoster() end
end)

local function refreshIfShown()
    if panel:IsVisible() then panel:Refresh() end
end
-- Records, announcements and my own changes while the panel is open.
People.OnChanged(refreshIfShown)
Identity.OnRevisionChanged(refreshIfShown)

-- The tab is shown only in a guild that enabled Who's Who. Its club ID comes with the roster.
local function updateTab()
    Main.SetTabShown(panel, IsInGuild() and ns.GuildSettings.Get(Identity.GuildId(UnitGUID("player"))).enable)
end
Main.SetTabShown(panel, false)
ns.GuildSettings.OnChanged(function()
    updateTab()
    refreshIfShown()
end)
panel:RegisterEvent("PLAYER_LOGIN")
panel:RegisterEvent("PLAYER_GUILD_UPDATE")
-- Members joining, leaving, coming online or changing rank.
panel:RegisterEvent("GUILD_ROSTER_UPDATE")
panel:SetScript("OnEvent", function(_, event, unit)
    -- PLAYER_GUILD_UPDATE also fires for other players.
    if event == "PLAYER_GUILD_UPDATE" and unit ~= "player" then return end
    updateTab()
    refreshIfShown()
end)

-- Skin -------------------------------------------------------------------------------------------

ns.Skin.Apply(function(S)
    S.EditBox(panel.SearchBox)
    S.Button(sharing.Button)
end)
