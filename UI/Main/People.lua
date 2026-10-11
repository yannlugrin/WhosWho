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
local FILTER_WIDTH = 130
local LIST_TOP = -62
local EMPTY_TEXT_WIDTH = 400

local panel = CreateFrame("Frame", nil, window)
panel:SetAllPoints()
Main.People = panel
Main.AddTab(L["People"], panel)

-- Top bar ----------------------------------------------------------------------------------------

panel.SearchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
panel.SearchBox:SetSize(SEARCH_WIDTH, 20)
panel.SearchBox:SetPoint("TOPLEFT", TOP_BAR_LEFT + 6, -34)
panel.SearchBox.Instructions:SetText(L["Search names or characters"])

panel.FilterLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.FilterLabel:SetPoint("LEFT", panel.SearchBox, "RIGHT", 12, 0)
panel.FilterLabel:SetText(L["Show"])

-- The filters in the order the dropdown lists them; the dropdown keeps the chosen one in panel.filter.
local FILTERS = {
    { key = "all", label = L["All"] },
    { key = "confirmed", label = L["Confirmed"] },
    { key = "renamed", label = L["Renamed"] },
    { key = "guild", label = L["Guild"] },
    { key = "unconfirmed", label = L["Unconfirmed"] },
}
panel.filter = "all"

panel.FilterDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
panel.FilterDropdown:SetWidth(FILTER_WIDTH)
panel.FilterDropdown:SetPoint("LEFT", panel.FilterLabel, "RIGHT", 6, 0)
panel.FilterDropdown:SetupMenu(function(_, root)
    for _, filter in ipairs(FILTERS) do
        root:CreateRadio(filter.label, function() return panel.filter == filter.key end, function()
            panel.filter = filter.key
            panel:Refresh()
        end)
    end
end)

-- List and detail panel --------------------------------------------------------------------------

local browser = PersonBrowser.Create(panel, LIST_TOP)
panel.Browser = browser

-- Empty state ------------------------------------------------------------------------------------

-- In place of both panels while no one is known.
panel.Empty = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
panel.Empty:SetPoint("TOPLEFT", browser.ListInset)
panel.Empty:SetPoint("BOTTOMRIGHT", browser.DetailInset)
panel.Empty:Hide()

panel.Empty.Text = panel.Empty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
panel.Empty.Text:SetPoint("CENTER")
panel.Empty.Text:SetWidth(EMPTY_TEXT_WIDTH)
panel.Empty.Text:SetText(L["This list fills with players who share their identity with you, and with players you or your guild give a nickname to — no add-on needed on their side."])

panel.Empty.Heading = panel.Empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.Empty.Heading:SetPoint("BOTTOM", panel.Empty.Text, "TOP", 0, 12)
panel.Empty.Heading:SetText(L["No one here yet"])

---Shows the empty state in place of both panels while no one is known.
---@param shown boolean
function panel:SetEmpty(shown)
    self.Empty:SetShown(shown)
    browser.ListInset:SetShown(not shown)
    browser.DetailInset:SetShown(not shown)
end

-- Data -------------------------------------------------------------------------------------------

local People = ns.People

-- The list's sort: "Name" (A to Z when ascending) or "LastSeen" (oldest first when ascending). At first, online
-- people, then the most recently seen; equal ones by name.
local sortKey, sortAscending = "LastSeen", false

---Selects a person: their row is marked and the detail panel shows them; nil clears the selection.
---@param id string?
function panel:Select(id)
    local person = id and People.Get(id)
    browser:SetSelected(person and id or nil)
    browser:SetPerson(person and PersonBrowser.PersonDetail(person, ns.Scopes.OnlineGuids()) or nil)
end

---Fills the list from the people I hold, with the search, filter and sort applied, and the selected person again
---while the list still shows them.
function panel:Refresh()
    local people = People.All()
    self:SetEmpty(next(people) == nil)

    local text = self.SearchBox:GetText():lower()
    local onlineGuids = ns.Scopes.OnlineGuids()
    local entries, selectedShown = {}, false
    for _, person in pairs(people) do
        local entry = PersonBrowser.ListEntry(person, onlineGuids)
        if (self.filter == "all" or entry.source == self.filter) and Lists.MatchesSearch(person, text) then
            -- The character the person is playing, after the nickname.
            local online = entry.onlineCharacter
            entry.nicknameAside = online and Lists.ClassColoredName(online.name, online.classID) or nil
            entries[#entries + 1] = entry
            if entry.id == browser.selectedId then selectedShown = true end
        end
    end
    PersonBrowser.SortEntries(entries, sortKey, sortAscending)
    browser.ListHeader:SetSort(sortKey, sortAscending)
    browser:SetEntries(entries)
    self:Select(selectedShown and browser.selectedId or nil)
end

---Opens the main window on this tab with a person selected and in view, clearing the search and filter that could
---hide them.
---@param id string
function panel:ShowPerson(id)
    self.filter = "all"
    self.FilterDropdown:GenerateMenu()
    self.SearchBox:SetText("")
    browser.selectedId = id
    window:Show()
    Main.SelectTab(self)
    self:Refresh()
    browser:ScrollTo(id)
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
    -- Online guild members come from the roster, which the game sends again when asked.
    if IsInGuild() then C_GuildInfo.GuildRoster() end
end)

local function refreshIfShown()
    if panel:IsVisible() then panel:Refresh() end
end
-- Records, announcements and my own changes while the panel is open.
People.OnChanged(refreshIfShown)
-- Players coming online or leaving, as the roster, the friend list and the group show them.
panel:RegisterEvent("GUILD_ROSTER_UPDATE")
panel:RegisterEvent("FRIENDLIST_UPDATE")
panel:RegisterEvent("GROUP_ROSTER_UPDATE")
panel:RegisterEvent("UNIT_CONNECTION")
panel:SetScript("OnEvent", refreshIfShown)

-- Skin -------------------------------------------------------------------------------------------

ns.Skin.Apply(function(S)
    S.EditBox(panel.SearchBox)
    S.Dropdown(panel.FilterDropdown)
    S.Inset(panel.Empty)
end)
