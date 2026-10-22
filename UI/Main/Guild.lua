local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
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

-- For the trusted ranks, while the guild has requests: the view of all of them.
panel.RequestsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
panel.RequestsButton:SetHeight(22)
-- At the height of the guild's name, whose line starts 36 below the top.
panel.RequestsButton:SetPoint("RIGHT", panel, "TOPRIGHT", -10, -44)
panel.RequestsButton:Hide()

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

local browser = PersonBrowser.Create(panel, LIST_TOP, Lists.FOOTER_SPACE, "guild")
panel.Browser = browser

-- Requests view ----------------------------------------------------------------------------------

-- In place of the list and the detail panel.
local requestsView = ns.GuildRequests.CreateView(panel)
requestsView:SetPoint("TOPLEFT", 8, LIST_TOP + 30)
requestsView:SetPoint("BOTTOMRIGHT", -6, Lists.FOOTER_SPACE + 4)
requestsView:SetFrameLevel(browser.DetailInset:GetFrameLevel() + 10)
requestsView:Hide()
panel.RequestsView = requestsView

local function showRequests(shown)
    requestsView:SetShown(shown)
    browser.ListInset:SetShown(not shown)
    browser.DetailInset:SetShown(not shown)
end

-- Data -------------------------------------------------------------------------------------------

local Identity, People, GuildRoster = ns.Identity, ns.People, ns.GuildRoster

-- The list's sort: "Name" (A to Z when ascending) or "LastSeen" (oldest first when ascending). At first, online
-- people, then the most recently seen; equal ones by name.
local sortKey, sortAscending = "LastSeen", false

-- The sharing line's action, nil when there is none.
---@type fun()?
local sharingAction

local function refreshSharing()
    local text, button, action = GuildRoster.Sharing()
    sharing.Text:SetText(text)
    sharing.Button:SetText(button or "")
    sharing.Button:SetShown(button ~= nil)
    sharingAction = action
end
sharing.Button:SetScript("OnClick", function() if sharingAction then sharingAction() end end)

---Selects a person, or my own identity: their row is marked and the detail panel shows them; nil clears the
---selection.
---@param id string?
function panel:Select(id)
    local detail = id and GuildRoster.Detail(id)
    browser:SetSelected(detail and id or nil)
    browser:SetPerson(detail)
end

---Fills the header from my guild, and the list from its roster: a row for each identity whose main is in it,
---mine included, and one for each character no identity holds, mine my guild doesn't get included, with the search
---applied; the selected row again while the list still shows it.
function panel:Refresh()
    local guildName, rankName = GetGuildInfo("player")
    self.GuildName:SetText(guildName and ("<%s>"):format(guildName) or "")
    self.Rank:SetText(rankName or "")

    local entries, counts = GuildRoster.Entries(self.SearchBox:GetText():lower(), GuildRoster.Members())
    local selectedShown = false
    for _, entry in ipairs(entries) do
        if entry.id and entry.id == browser.selectedId then selectedShown = true end
    end
    self.Counts:SetText(L["%d |4main character:main characters; · %d |4alt:alts; · %d unknown"]:format(counts.main,
        counts.alt, counts.unknown))

    PersonBrowser.SortEntries(entries, sortKey, sortAscending)
    browser.ListHeader:SetSort(sortKey, sortAscending)
    browser:SetEntries(entries)
    self:Select(selectedShown and browser.selectedId or nil)
    refreshSharing()

    local requests = GuildRoster.AllRequests()
    local hasRequests = requests ~= nil and requests[1] ~= nil
    self.RequestsButton:SetShown(hasRequests)
    if hasRequests then
        self.RequestsButton:SetText(ns.GuildRequests.ButtonLabel(requests))
        self.RequestsButton:SetWidth(self.RequestsButton:GetTextWidth() + 30)
    end
    self.Counts:SetPoint("RIGHT", hasRequests and self.RequestsButton or self, hasRequests and "LEFT" or "RIGHT", -12, 0)
    if not requests then showRequests(false) end
    if requestsView:IsShown() then ns.GuildRequests.SetRequests(requestsView, requests) end
end

panel.RequestsButton:SetScript("OnClick", function()
    showRequests(true)
    panel:Refresh()
end)
requestsView.CloseButton:SetScript("OnClick", function()
    showRequests(false)
    panel:Refresh()
end)
panel:HookScript("OnHide", function() showRequests(false) end)

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
    S.Button(panel.RequestsButton)
end)
