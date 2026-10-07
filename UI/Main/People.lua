local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local Main = ns.Main
local Lists = ns.Lists
local Glyphs = ns.Glyphs
local window = Main.Window

-- Right of the window's portrait.
local TOP_BAR_LEFT = 70
local SEARCH_WIDTH = 190
local FILTER_WIDTH = 130
local LIST_WIDTH = 380
local PANEL_GAP = 6
-- The key runs under both panels.
local KEY_HEIGHT = 26
local ROW_HEIGHT = 24
local CHARACTER_ROW_HEIGHT = 42
local GLYPH_SIZE = 14
local SMALL_GLYPH_SIZE = 12
local CLASS_ICON_SIZE = 16
local SCROLL_BAR_WIDTH = 16
local DETAIL_PADDING = 12
local EMPTY_TEXT_WIDTH = 400

---@type table? EllesmereUI's skinning functions, for rows created after they were handed over
local skin

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

-- People list ------------------------------------------------------------------------------------

local listInset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
listInset:SetPoint("TOPLEFT", 8, -62)
listInset:SetPoint("BOTTOMLEFT", 8, KEY_HEIGHT + 4)
listInset:SetWidth(LIST_WIDTH)

local COLUMNS = {
    { key = "Characters", width = 40, label = L["Chars"], justify = "RIGHT" },
    { key = "LastSeen", width = 100, label = L["Last seen"], justify = "RIGHT", sortable = true },
}
local columnsWidth = Lists.LayOut(COLUMNS)
local columnByKey = {}
for _, column in ipairs(COLUMNS) do columnByKey[column.key] = column end
local NAME_LEFT = 6 + GLYPH_SIZE + 6

panel.ListHeader = Lists.CreateHeader(listInset, { key = "Name", label = L["Name"], left = NAME_LEFT, sortable = true },
    COLUMNS, columnsWidth)
panel.ListHeader:SetPoint("TOPLEFT", 4, -4)
panel.ListHeader:SetPoint("TOPRIGHT", -4 - SCROLL_BAR_WIDTH, -4)

local listBox = CreateFrame("Frame", nil, listInset, "WowScrollBoxList")
listBox:SetPoint("TOPLEFT", panel.ListHeader, "BOTTOMLEFT", 0, -2)
listBox:SetPoint("BOTTOMRIGHT", -4 - SCROLL_BAR_WIDTH, 4)

local listBar = CreateFrame("EventFrame", nil, listInset, "MinimalScrollBar")
listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 6, 0)

-- A glyph with its tooltip: a texture on a small frame that takes the mouse.
local function createGlyph(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.Texture = holder:CreateTexture(nil, "ARTWORK")
    holder.Texture:SetAllPoints()
    holder:SetScript("OnEnter", function(self) Glyphs.ShowTooltip(self, self.glyph) end)
    holder:SetScript("OnLeave", GameTooltip_Hide)
    return holder
end

local function setGlyph(holder, glyph)
    holder.glyph = glyph
    Glyphs.Set(holder.Texture, glyph)
end

---A person row of the list; createPersonRow adds its regions the first time the row is used.
---@class WhosWho.PeopleRow: Button
---@field Selected Texture
---@field Glyph Frame
---@field Nickname FontString
---@field OnlineCharacter FontString
---@field Characters FontString
---@field LastSeen FontString

---@param row WhosWho.PeopleRow
local function createPersonRow(row)
    row.Selected = Lists.CreateRowHighlight(row)

    row.Glyph = createGlyph(row, GLYPH_SIZE)
    row.Glyph:SetPoint("LEFT", 6, 0)

    row.Nickname = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Nickname:SetPoint("LEFT", NAME_LEFT, 0)
    row.Nickname:SetWordWrap(false)

    row.OnlineCharacter = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.OnlineCharacter:SetPoint("LEFT", row.Nickname, "RIGHT", 6, 0)
    row.OnlineCharacter:SetPoint("RIGHT", row, "RIGHT", -columnsWidth - 4, 0)
    row.OnlineCharacter:SetJustifyH("LEFT")
    row.OnlineCharacter:SetWordWrap(false)

    row.Characters = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Lists.Place(row.Characters, row, columnByKey.Characters)

    row.LastSeen = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    Lists.Place(row.LastSeen, row, columnByKey.LastSeen)

    row:SetScript("OnClick", function(self) panel:Select(self:GetElementData().id) end)
end

---A person as the list shows it.
---@class WhosWho.PeopleListEntry
---@field id string
---@field nickname string the name the person is shown under
---@field source "confirmed"|"renamed"|"guild"|"unconfirmed"
---@field characterCount integer
---@field lastSeen number? seconds, from time()
---@field onlineCharacter { name: string, classID: integer }? the character the person is playing

-- The grey last seen time is hard to read on the selection bar: it turns white there.
local function setRowSelected(row, selected)
    row.Selected:SetShown(selected)
    row.LastSeen:SetFontObject(selected and "GameFontHighlight" or "GameFontDisable")
end

---@param row WhosWho.PeopleRow
---@param person WhosWho.PeopleListEntry
local function initPersonRow(row, person)
    if not row.Nickname then createPersonRow(row) end

    setRowSelected(row, person.id == panel.selectedId)
    setGlyph(row.Glyph, Glyphs.Nickname[person.source])

    row.Nickname:SetText(person.nickname)
    -- The nickname keeps its width; the online character takes what is left before the columns.
    local nameSpace = listBox:GetWidth() - NAME_LEFT - columnsWidth - 4
    row.Nickname:SetWidth(math.min(row.Nickname:GetUnboundedStringWidth(), nameSpace))
    local online = person.onlineCharacter
    row.OnlineCharacter:SetText(online and Lists.ClassColoredName(online.name, online.classID) or "")

    row.Characters:SetText(tostring(person.characterCount))
    if online then
        row.LastSeen:SetText(GREEN_FONT_COLOR:WrapTextInColorCode(L["Online"]))
    else
        row.LastSeen:SetText(person.lastSeen and FriendsFrame_GetLastOnline(person.lastSeen) or "")
    end
end

local listView = CreateScrollBoxListLinearView()
listView:SetElementExtent(ROW_HEIGHT)
listView:SetElementInitializer("Button", initPersonRow)
ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, listView)

-- Detail panel -----------------------------------------------------------------------------------

local detailInset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
detailInset:SetPoint("TOPLEFT", listInset, "TOPRIGHT", PANEL_GAP, 0)
detailInset:SetPoint("BOTTOMRIGHT", -6, KEY_HEIGHT + 4)

panel.NoSelection = detailInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
panel.NoSelection:SetPoint("LEFT", DETAIL_PADDING, 0)
panel.NoSelection:SetPoint("RIGHT", -DETAIL_PADDING, 0)
panel.NoSelection:SetText(L["Select a person to see their characters."])

local detail = CreateFrame("Frame", nil, detailInset)
detail:SetAllPoints()
panel.Detail = detail

detail.Glyph = createGlyph(detail, GLYPH_SIZE)
detail.Glyph:SetPoint("TOPLEFT", DETAIL_PADDING, -DETAIL_PADDING - 3)

detail.Nickname = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
detail.Nickname:SetPoint("LEFT", detail.Glyph, "RIGHT", 6, 0)
detail.Nickname:SetPoint("RIGHT", -DETAIL_PADDING, 0)
detail.Nickname:SetJustifyH("LEFT")
detail.Nickname:SetWordWrap(false)

-- The nickname that applies without mine.
detail.BaseNickname = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
detail.BaseNickname:SetPoint("TOPLEFT", detail.Nickname, "BOTTOMLEFT", 0, -2)

detail.CharactersHeading = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detail.CharactersHeading:SetPoint("TOPLEFT", DETAIL_PADDING, -56)
detail.CharactersHeading:SetText(L["Characters"])

detail.ForgetButton = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
detail.ForgetButton:SetText(L["Forget"])
detail.ForgetButton:SetSize(detail.ForgetButton:GetTextWidth() + 40, 22)
detail.ForgetButton:SetPoint("BOTTOMRIGHT", -8, 8)

local charactersBox = CreateFrame("Frame", nil, detail, "WowScrollBoxList")
charactersBox:SetPoint("TOPLEFT", detail.CharactersHeading, "BOTTOMLEFT", 0, -4)
charactersBox:SetPoint("BOTTOMRIGHT", detail.ForgetButton, "TOPRIGHT", -SCROLL_BAR_WIDTH, 8)

local charactersBar = CreateFrame("EventFrame", nil, detail, "MinimalScrollBar")
charactersBar:SetPoint("TOPLEFT", charactersBox, "TOPRIGHT", 6, 0)
charactersBar:SetPoint("BOTTOMLEFT", charactersBox, "BOTTOMRIGHT", 6, 0)

---A character of the selected person, on two lines; createCharacterRow adds its regions the first time.
---@class WhosWho.PersonCharacterRow: Frame
---@field ClassIcon Texture
---@field Name FontString
---@field MainCrown Frame
---@field Seen FontString
---@field StateGlyph Frame
---@field Details FontString

---@param row WhosWho.PersonCharacterRow
local function createCharacterRow(row)
    local iconFrame = CreateFrame("Frame", nil, row)
    iconFrame:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
    iconFrame:SetPoint("TOPLEFT", 0, -2)
    row.ClassIcon = iconFrame:CreateTexture(nil, "ARTWORK")
    row.ClassIcon:SetAllPoints()

    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 6, 0)
    row.Name:SetWordWrap(false)

    row.MainCrown = createGlyph(row, SMALL_GLYPH_SIZE)
    row.MainCrown:SetPoint("LEFT", row.Name, "RIGHT", 4, 0)
    setGlyph(row.MainCrown, Glyphs.Main)

    row.Seen = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.Seen:SetWordWrap(false)

    row.StateGlyph = createGlyph(row, SMALL_GLYPH_SIZE)
    row.StateGlyph:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -3)

    row.Details = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.Details:SetPoint("LEFT", row.StateGlyph, "RIGHT", 4, 0)

    -- Right-click: the game's player menu, as on a name in chat.
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        local character = self:GetElementData()
        UnitPopup_OpenMenu("FRIEND", { name = character.name, guid = character.guid, fromPeoplePanel = true })
    end)

    if skin then skin.SquareIcon(row.ClassIcon, iconFrame) end
end

---A character of the selected person.
---@class WhosWho.PersonDetailCharacter
---@field guid string
---@field name string
---@field classID integer
---@field state "confirmed"|"listed"|"added"|"guild"
---@field main boolean
---@field online boolean
---@field lastSeen number? seconds, from time()
---@field level integer?
---@field ruleset WhosWho.Ruleset

---@param row WhosWho.PersonCharacterRow
---@param character WhosWho.PersonDetailCharacter
local function initCharacterRow(row, character)
    if not row.Name then createCharacterRow(row) end

    Lists.SetClassIcon(row.ClassIcon, character.classID)
    row.Name:SetText(Lists.ClassColoredName(character.name, character.classID))
    row.MainCrown:SetShown(character.main)
    row.Seen:ClearAllPoints()
    row.Seen:SetPoint("LEFT", character.main and row.MainCrown or row.Name, "RIGHT", 6, 0)
    if character.online then
        row.Seen:SetText(GREEN_FONT_COLOR:WrapTextInColorCode(L["Online"]))
    else
        row.Seen:SetText(character.lastSeen and FriendsFrame_GetLastOnline(character.lastSeen) or "")
    end

    setGlyph(row.StateGlyph, Glyphs.Character[character.state])
    local ruleset = Lists.RulesetName(character.ruleset)
    row.Details:SetText(character.level and L["Lvl %d · %s"]:format(character.level, ruleset) or ruleset)
end

local charactersView = CreateScrollBoxListLinearView()
charactersView:SetElementExtent(CHARACTER_ROW_HEIGHT)
charactersView:SetElementInitializer("Frame", initCharacterRow)
ScrollUtil.InitScrollBoxListWithScrollBar(charactersBox, charactersBar, charactersView)

-- Key --------------------------------------------------------------------------------------------

do
    local previous
    for _, glyph in ipairs(Glyphs.Key) do
        local texture = panel:CreateTexture(nil, "OVERLAY")
        texture:SetSize(SMALL_GLYPH_SIZE, SMALL_GLYPH_SIZE)
        Glyphs.Set(texture, glyph)
        if previous then
            texture:SetPoint("LEFT", previous, "RIGHT", 14, 0)
        else
            texture:SetPoint("BOTTOMLEFT", 14, 10)
        end
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("LEFT", texture, "RIGHT", 3, 0)
        label:SetText(glyph.label)
        previous = label
    end
end

-- Empty state ------------------------------------------------------------------------------------

-- In place of both panels while no one is known.
panel.Empty = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
panel.Empty:SetPoint("TOPLEFT", listInset)
panel.Empty:SetPoint("BOTTOMRIGHT", detailInset)
panel.Empty:Hide()

panel.Empty.Text = panel.Empty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
panel.Empty.Text:SetPoint("CENTER")
panel.Empty.Text:SetWidth(EMPTY_TEXT_WIDTH)
panel.Empty.Text:SetText(L["This list fills with players who share their identity with you, and with players you or your guild give a nickname to — no add-on needed on their side."])

panel.Empty.Heading = panel.Empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.Empty.Heading:SetPoint("BOTTOM", panel.Empty.Text, "TOP", 0, 12)
panel.Empty.Heading:SetText(L["No one here yet"])

-- Filling ----------------------------------------------------------------------------------------

---@param people WhosWho.PeopleListEntry[] in the order shown
function panel:SetPeople(people)
    listBox:SetDataProvider(CreateDataProvider(people), ScrollBoxConstants.RetainScrollPosition)
end

---Marks a person's row as selected, or none.
---@param id string?
function panel:SetSelected(id)
    self.selectedId = id
    listBox:ForEachFrame(function(row, person) setRowSelected(row, person.id == id) end)
end

---A person in the detail panel.
---@class WhosWho.PersonDetail
---@field nickname string the name the person is shown under
---@field source "confirmed"|"renamed"|"guild"|"unconfirmed"
---@field baseNickname string? the nickname that applies without mine, when mine replaces it
---@field characters WhosWho.PersonDetailCharacter[] in the order shown

---Shows a person in the detail panel, or the line asking to select one.
---@param person WhosWho.PersonDetail?
function panel:SetPerson(person)
    self.NoSelection:SetShown(person == nil)
    detail:SetShown(person ~= nil)
    if not person then return end

    setGlyph(detail.Glyph, Glyphs.Nickname[person.source])
    detail.Nickname:SetText(person.nickname)
    detail.BaseNickname:SetText(person.baseNickname or "")
    charactersBox:SetDataProvider(CreateDataProvider(person.characters))
end

---Shows the empty state in place of both panels while no one is known.
---@param shown boolean
function panel:SetEmpty(shown)
    self.Empty:SetShown(shown)
    listInset:SetShown(not shown)
    detailInset:SetShown(not shown)
end

panel:SetPerson(nil)

-- Data -------------------------------------------------------------------------------------------

local People = ns.People

-- The list's sort: "Name" (A to Z when ascending) or "LastSeen" (oldest first when ascending). At first, online
-- people, then the most recently seen; equal ones by name.
local sortKey, sortAscending = "LastSeen", false

---@param person WhosWho.Person
---@param onlineGuids table<string, true>
---@return WhosWho.PeopleListEntry
local function listEntry(person, onlineGuids)
    local characterCount, lastSeen, onlineCharacter = 0, nil, nil
    for guid, character in pairs(person.chars) do
        characterCount = characterCount + 1
        if character.lastSeen and (not lastSeen or character.lastSeen > lastSeen) then lastSeen = character.lastSeen end
        if onlineGuids[guid] then onlineCharacter = { name = character.name, classID = character.classID } end
    end
    return {
        id = person.id, nickname = People.Nickname(person.id), source = Lists.NicknameSource(person),
        characterCount = characterCount, lastSeen = lastSeen, onlineCharacter = onlineCharacter,
    }
end

-- For the last seen sort: a person online comes before everyone seen in the past.
local function seenAt(entry)
    return entry.onlineCharacter and math.huge or entry.lastSeen or 0
end

-- By the chosen column, then by name and ID so the order never changes between refreshes.
local function sortEntries(entries)
    table.sort(entries, function(a, b)
        if sortKey == "LastSeen" and seenAt(a) ~= seenAt(b) then
            if sortAscending then return seenAt(a) < seenAt(b) end
            return seenAt(a) > seenAt(b)
        end
        local aName, bName = a.nickname:lower(), b.nickname:lower()
        if aName ~= bName then
            if sortKey == "Name" and not sortAscending then return aName > bName end
            return aName < bName
        end
        return a.id < b.id
    end)
end

---@param person WhosWho.Person
---@param onlineGuids table<string, true>
---@return WhosWho.PersonDetail
local function personDetail(person, onlineGuids)
    local characters = {}
    for guid, character in pairs(person.chars) do
        characters[#characters + 1] = {
            guid = guid,
            name = character.name, classID = character.classID, state = character.state, main = guid == person.main,
            online = onlineGuids[guid] == true, lastSeen = character.lastSeen, level = character.level,
            ruleset = character.ruleset,
        }
    end
    table.sort(characters, function(a, b)
        if a.main ~= b.main then return a.main end
        return a.name < b.name
    end)

    local nickname, identityNickname = People.Nickname(person.id), People.IdentityNickname(person.id)
    return {
        nickname = nickname, source = Lists.NicknameSource(person), characters = characters,
        baseNickname = person.customNickname and identityNickname ~= nickname and identityNickname or nil,
    }
end

---Selects a person: their row is marked and the detail panel shows them; nil clears the selection.
---@param id string?
function panel:Select(id)
    local person = id and People.Get(id)
    self:SetSelected(person and id or nil)
    self:SetPerson(person and personDetail(person, ns.Scopes.OnlineGuids()) or nil)
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
        local entry = listEntry(person, onlineGuids)
        if (self.filter == "all" or entry.source == self.filter) and Lists.MatchesSearch(person, text) then
            entries[#entries + 1] = entry
            if entry.id == self.selectedId then selectedShown = true end
        end
    end
    sortEntries(entries)
    self.ListHeader:SetSort(sortKey, sortAscending)
    self:SetPeople(entries)
    self:Select(selectedShown and self.selectedId or nil)
end

---Opens the main window on this tab with a person selected and in view, clearing the search and filter that could
---hide them.
---@param id string
function panel:ShowPerson(id)
    self.filter = "all"
    self.FilterDropdown:GenerateMenu()
    self.SearchBox:SetText("")
    self.selectedId = id
    window:Show()
    Main.SelectTab(self)
    self:Refresh()
    listBox:ScrollToElementDataByPredicate(function(entry) return entry.id == id end, ScrollBoxConstants.AlignCenter)
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
panel.ListHeader.Labels.Name:SetScript("OnClick", function() sortBy("Name") end)
panel.ListHeader.Labels.LastSeen:SetScript("OnClick", function() sortBy("LastSeen") end)

panel.SearchBox:HookScript("OnTextChanged", function() panel:Refresh() end)
detail.ForgetButton:SetScript("OnClick", function() ns.PeopleDialogs.ConfirmForget(panel.selectedId) end)
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
    skin = S
    S.EditBox(panel.SearchBox)
    S.Dropdown(panel.FilterDropdown)
    S.Inset(listInset)
    S.Inset(detailInset)
    S.Inset(panel.Empty)
    S.ScrollBar(listBar)
    S.ScrollBar(charactersBar)
    S.Button(detail.ForgetButton)
end)
