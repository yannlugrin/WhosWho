local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local Lists = ns.Lists
local Glyphs = ns.Glyphs

-- The person list, detail panel and glyph key of the People and Guild tabs.
---@class WhosWho.PersonBrowser
local PersonBrowser = {}
ns.PersonBrowser = PersonBrowser

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

local COLUMNS = {
    { key = "Characters", width = 40, label = L["Chars"], justify = "RIGHT" },
    { key = "LastSeen", width = 100, label = L["Last seen"], justify = "RIGHT", sortable = true },
}
local columnsWidth = Lists.LayOut(COLUMNS)
local columnByKey = {}
for _, column in ipairs(COLUMNS) do columnByKey[column.key] = column end
local NAME_LEFT = 6 + GLYPH_SIZE + 6

---@type table? EllesmereUI's skinning functions, for rows created after they were handed over
local skin
ns.Skin.Apply(function(S) skin = S end)

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

---A row of the list: a person, or a character no identity holds.
---@class WhosWho.PersonListEntry
---@field id string? identity ID; nil for a character no identity holds
---@field nickname string the name the row shows: the person's nickname, or the character's name
---@field source "confirmed"|"renamed"|"guild"|"unconfirmed"
---@field nicknameAside string? small text right after the nickname, with its colour codes
---@field characterCount integer
---@field lastSeen number? seconds, from time()
---@field online boolean
---@field onlineCharacter { guid: string, name: string, classID: integer }? the character the person is playing
---@field unknownCharacter { guid: string, name: string, newCharacter: WhosWho.NewCharacter? }? the character no identity holds, with what Link character needs when its class is known

---A row of the person list; createPersonRow adds its regions the first time the row is used.
---@class WhosWho.PersonListRow: Button
---@field Selected Texture
---@field Glyph Frame
---@field Nickname FontString
---@field NicknameAside FontString
---@field Characters FontString
---@field LastSeen FontString

---A character of the selected person, on two lines; createCharacterRow adds its regions the first time.
---@class WhosWho.PersonCharacterRow: Frame
---@field ClassIcon Texture
---@field Name FontString
---@field MainCrown Frame
---@field Seen FontString
---@field StateGlyph Frame
---@field Details FontString

---A character of the selected person.
---@class WhosWho.PersonDetailCharacter
---@field guid string
---@field name string
---@field classID integer
---@field state WhosWho.CharacterState
---@field main boolean
---@field online boolean
---@field lastSeen number? seconds, from time()
---@field level integer?
---@field ruleset WhosWho.Ruleset

---A person in the detail panel.
---@class WhosWho.PersonDetail
---@field nickname string the name the person is shown under
---@field source "confirmed"|"renamed"|"guild"|"unconfirmed"
---@field baseNickname string? the nickname that applies without mine, when mine replaces it
---@field battleTag string? BattleTag of my Battle.net friend seen playing one of the person's characters
---@field id string
---@field note string? my note about the person
---@field own boolean my own identity: no nickname, note or Forget of mine
---@field characters WhosWho.PersonDetailCharacter[] in the order shown

---The list and detail panel of a tab.
---@class WhosWho.PersonBrowserFrames
---@field ListInset Frame
---@field DetailInset Frame
---@field ListHeader WhosWho.ListHeader
---@field NoSelection FontString
---@field Detail Frame
---@field selectedId string? the identity ID of the selected row
---@field listBox Frame
---@field charactersBox Frame
---@field setRowSelected fun(row: WhosWho.PersonListRow, selected: boolean)
local Browser = {}

---@param people WhosWho.PersonListEntry[] in the order shown
function Browser:SetEntries(people)
    self.listBox:SetDataProvider(CreateDataProvider(people), ScrollBoxConstants.RetainScrollPosition)
end

---Marks a person's row as selected, or none.
---@param id string?
function Browser:SetSelected(id)
    self.selectedId = id
    self.listBox:ForEachFrame(function(row, entry) self.setRowSelected(row, entry.id ~= nil and entry.id == id) end)
end

---Shows a person in the detail panel, or the line asking to select one.
---@param person WhosWho.PersonDetail?
function Browser:SetPerson(person)
    self.NoSelection:SetShown(person == nil)
    local detail = self.Detail
    detail:SetShown(person ~= nil)
    if not person then return end

    setGlyph(detail.Glyph, Glyphs.Nickname[person.source])
    detail.Nickname:SetText(person.nickname)
    -- The nickname keeps its width; the edit button follows it.
    local nicknameSpace = detail:GetWidth() - 2 * DETAIL_PADDING - GLYPH_SIZE * 2 - 12 - detail.ForgetButton:GetWidth()
    detail.Nickname:SetWidth(math.min(detail.Nickname:GetUnboundedStringWidth(), nicknameSpace))
    detail.BaseNickname:SetText(person.baseNickname or "")
    -- After the base nickname, or in its place.
    detail.BattleTag:ClearAllPoints()
    if person.baseNickname then
        detail.BattleTag:SetPoint("LEFT", detail.BaseNickname, "RIGHT", 12, 0)
    else
        detail.BattleTag:SetPoint("TOPLEFT", detail.Nickname, "BOTTOMLEFT", 0, -2)
    end
    detail.BattleTag:SetText(person.battleTag and L["Battle.net: %s"]:format(person.battleTag) or "")

    for _, region in ipairs(detail.personalRegions) do region:SetShown(not person.own) end
    detail.Note:SetFontObject(person.note and "GameFontHighlight" or "GameFontDisable")
    detail.Note:SetText(person.note or L["No note."])
    -- Without the note, the characters take the panel down to its bottom.
    self.charactersBox:SetPoint("BOTTOM", person.own and detail or detail.NoteHeading,
        person.own and "BOTTOM" or "TOP", 0, person.own and DETAIL_PADDING or 16)
    self.charactersBox:SetDataProvider(CreateDataProvider(person.characters))
end

---Scrolls the list to a person's row.
---@param id string
function Browser:ScrollTo(id)
    self.listBox:ScrollToElementDataByPredicate(function(entry) return entry.id == id end,
        ScrollBoxConstants.AlignCenter)
end

---Builds the list from listTop down, the detail panel at its right and the key under both, listBottom above the
---panel's bottom. A left click on a person's row calls panel:Select with its ID.
---@param panel Frame the tab, with a Select method
---@param listTop number offset of the list's top from the panel's top
---@param listBottom number space the tab keeps under the key
---@return WhosWho.PersonBrowserFrames
function PersonBrowser.Create(panel, listTop, listBottom)
    local browser = Mixin({}, Browser)

    -- List -------------------------------------------------------------------------------------------

    local listInset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    listInset:SetPoint("TOPLEFT", 8, listTop)
    listInset:SetPoint("BOTTOMLEFT", 8, listBottom + KEY_HEIGHT + 4)
    listInset:SetWidth(LIST_WIDTH)
    browser.ListInset = listInset

    browser.ListHeader = Lists.CreateHeader(listInset,
        { key = "Name", label = L["Name"], left = NAME_LEFT, sortable = true }, COLUMNS, columnsWidth)
    browser.ListHeader:SetPoint("TOPLEFT", 4, -4)
    browser.ListHeader:SetPoint("TOPRIGHT", -4 - SCROLL_BAR_WIDTH, -4)

    local listBox = CreateFrame("Frame", nil, listInset, "WowScrollBoxList")
    listBox:SetPoint("TOPLEFT", browser.ListHeader, "BOTTOMLEFT", 0, -2)
    listBox:SetPoint("BOTTOMRIGHT", -4 - SCROLL_BAR_WIDTH, 4)
    browser.listBox = listBox

    local listBar = CreateFrame("EventFrame", nil, listInset, "MinimalScrollBar")
    listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
    listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 6, 0)

    ---@param row WhosWho.PersonListRow
    local function createPersonRow(row)
        row.Selected = Lists.CreateRowHighlight(row)

        row.Glyph = createGlyph(row, GLYPH_SIZE)
        row.Glyph:SetPoint("LEFT", 6, 0)

        row.Nickname = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.Nickname:SetPoint("LEFT", NAME_LEFT, 0)
        row.Nickname:SetWordWrap(false)

        row.NicknameAside = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.NicknameAside:SetPoint("LEFT", row.Nickname, "RIGHT", 6, 0)
        row.NicknameAside:SetPoint("RIGHT", row, "RIGHT", -columnsWidth - 4, 0)
        row.NicknameAside:SetJustifyH("LEFT")
        row.NicknameAside:SetWordWrap(false)

        row.Characters = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        Lists.Place(row.Characters, row, columnByKey.Characters)

        row.LastSeen = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        Lists.Place(row.LastSeen, row, columnByKey.LastSeen)

        -- Right-click: the menu of the character no identity holds, or of the character the person is playing.
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            local entry = self:GetElementData()
            local menuCharacter = entry.unknownCharacter or entry.onlineCharacter
            if button ~= "RightButton" then
                if entry.id then panel:Select(entry.id) end
            elseif menuCharacter then
                ns.UnitMenu.OpenCharacterMenu(self, menuCharacter.name, menuCharacter.guid,
                    entry.unknownCharacter and entry.unknownCharacter.newCharacter)
            end
        end)
    end

    -- The grey last seen time is hard to read on the selection bar: it turns white there.
    local function setRowSelected(row, selected)
        row.Selected:SetShown(selected)
        row.LastSeen:SetFontObject(selected and "GameFontHighlight" or "GameFontDisable")
    end
    browser.setRowSelected = setRowSelected

    ---@param row WhosWho.PersonListRow
    ---@param entry WhosWho.PersonListEntry
    local function initPersonRow(row, entry)
        if not row.Nickname then createPersonRow(row) end

        setRowSelected(row, entry.id ~= nil and entry.id == browser.selectedId)
        setGlyph(row.Glyph, Glyphs.Nickname[entry.source])

        row.Nickname:SetFontObject(entry.unknownCharacter and "GameFontDisable" or "GameFontHighlight")
        row.Nickname:SetText(entry.nickname)
        -- The nickname keeps its width; the text after it takes what is left before the columns.
        local nameSpace = listBox:GetWidth() - NAME_LEFT - columnsWidth - 4
        row.Nickname:SetWidth(math.min(row.Nickname:GetUnboundedStringWidth(), nameSpace))
        row.NicknameAside:SetText(entry.nicknameAside or "")

        row.Characters:SetText(tostring(entry.characterCount))
        if entry.online then
            row.LastSeen:SetText(GREEN_FONT_COLOR:WrapTextInColorCode(L["Online"]))
        else
            row.LastSeen:SetText(entry.lastSeen and FriendsFrame_GetLastOnline(entry.lastSeen) or "")
        end
    end

    local listView = CreateScrollBoxListLinearView()
    listView:SetElementExtent(ROW_HEIGHT)
    listView:SetElementInitializer("Button", initPersonRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, listView)

    -- Detail panel -----------------------------------------------------------------------------------

    local detailInset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    detailInset:SetPoint("TOPLEFT", listInset, "TOPRIGHT", PANEL_GAP, 0)
    detailInset:SetPoint("BOTTOMRIGHT", -6, listBottom + KEY_HEIGHT + 4)
    browser.DetailInset = detailInset

    browser.NoSelection = detailInset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    browser.NoSelection:SetPoint("LEFT", DETAIL_PADDING, 0)
    browser.NoSelection:SetPoint("RIGHT", -DETAIL_PADDING, 0)
    browser.NoSelection:SetText(L["Select a person to see their characters."])

    local detail = CreateFrame("Frame", nil, detailInset)
    detail:SetAllPoints()
    browser.Detail = detail

    detail.Glyph = createGlyph(detail, GLYPH_SIZE)
    detail.Glyph:SetPoint("TOPLEFT", DETAIL_PADDING, -DETAIL_PADDING - 3)

    detail.Nickname = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    detail.Nickname:SetPoint("LEFT", detail.Glyph, "RIGHT", 6, 0)
    detail.Nickname:SetJustifyH("LEFT")
    detail.Nickname:SetWordWrap(false)

    -- A small button with the edit image, after a nickname or a heading.
    local function createEditButton(tooltipText)
        local button = CreateFrame("Button", nil, detail)
        button:SetSize(GLYPH_SIZE, GLYPH_SIZE)
        button:SetNormalTexture(Glyphs.EDIT_TEXTURE)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText, HIGHLIGHT_FONT_COLOR:GetRGB())
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        return button
    end

    detail.EditNicknameButton = createEditButton(L["Edit nickname"])
    detail.EditNicknameButton:SetPoint("LEFT", detail.Nickname, "RIGHT", 6, 0)

    -- The nickname that applies without mine.
    detail.BaseNickname = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail.BaseNickname:SetPoint("TOPLEFT", detail.Nickname, "BOTTOMLEFT", 0, -2)

    detail.BattleTag = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

    detail.CharactersHeading = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detail.CharactersHeading:SetPoint("TOPLEFT", DETAIL_PADDING, -56)
    detail.CharactersHeading:SetText(L["Characters"])

    detail.ForgetButton = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.ForgetButton:SetText(L["Forget"])
    detail.ForgetButton:SetSize(detail.ForgetButton:GetTextWidth() + 40, 22)
    detail.ForgetButton:SetPoint("TOPRIGHT", -8, -8)

    -- My note, under the characters at the bottom of the panel, whole: anchored by its bottom and sides only, it is as
    -- tall as its lines, and the characters list takes the space left above it.
    detail.Note = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail.Note:SetPoint("BOTTOMLEFT", DETAIL_PADDING, DETAIL_PADDING)
    detail.Note:SetPoint("BOTTOMRIGHT", -DETAIL_PADDING, DETAIL_PADDING)
    detail.Note:SetJustifyH("LEFT")
    detail.Note:SetJustifyV("TOP")

    detail.NoteHeading = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detail.NoteHeading:SetPoint("BOTTOMLEFT", detail.Note, "TOPLEFT", 0, 4)
    detail.NoteHeading:SetText(L["Note"])

    detail.EditNoteButton = createEditButton(L["Edit note"])
    detail.EditNoteButton:SetPoint("LEFT", detail.NoteHeading, "RIGHT", 6, 0)

    -- What I set on another player's person, hidden on my own identity.
    detail.personalRegions = {
        detail.EditNicknameButton, detail.ForgetButton, detail.Note, detail.NoteHeading, detail.EditNoteButton,
    }

    local charactersBox = CreateFrame("Frame", nil, detail, "WowScrollBoxList")
    charactersBox:SetPoint("TOPLEFT", detail.CharactersHeading, "BOTTOMLEFT", 0, -4)
    charactersBox:SetPoint("RIGHT", -8 - SCROLL_BAR_WIDTH, 0)
    charactersBox:SetPoint("BOTTOM", detail.NoteHeading, "TOP", 0, 16)
    browser.charactersBox = charactersBox

    local charactersBar = CreateFrame("EventFrame", nil, detail, "MinimalScrollBar")
    charactersBar:SetPoint("TOPLEFT", charactersBox, "TOPRIGHT", 6, 0)
    charactersBar:SetPoint("BOTTOMLEFT", charactersBox, "BOTTOMRIGHT", 6, 0)

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

        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(self, button)
            if button ~= "RightButton" then return end
            local character = self:GetElementData()
            ns.UnitMenu.OpenCharacterMenu(self, character.name, character.guid)
        end)

        if skin then skin.SquareIcon(row.ClassIcon, iconFrame) end
    end

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

    detail.ForgetButton:SetScript("OnClick", function() ns.PeopleDialogs.ConfirmForget(browser.selectedId) end)
    detail.EditNicknameButton:SetScript("OnClick", function() ns.PeopleDialogs.EditNickname(browser.selectedId) end)
    detail.EditNoteButton:SetScript("OnClick", function() ns.PeopleDialogs.NoteEditor:Open(browser.selectedId) end)

    -- Key --------------------------------------------------------------------------------------------

    local previous
    for _, glyph in ipairs(Glyphs.Key) do
        local texture = panel:CreateTexture(nil, "OVERLAY")
        texture:SetSize(SMALL_GLYPH_SIZE, SMALL_GLYPH_SIZE)
        Glyphs.Set(texture, glyph)
        if previous then
            texture:SetPoint("LEFT", previous, "RIGHT", 14, 0)
        else
            texture:SetPoint("BOTTOMLEFT", 14, listBottom + 10)
        end
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("LEFT", texture, "RIGHT", 3, 0)
        label:SetText(glyph.label)
        previous = label
    end

    browser:SetPerson(nil)

    ns.Skin.Apply(function(S)
        S.Inset(listInset)
        S.Inset(detailInset)
        S.ScrollBar(listBar)
        S.ScrollBar(charactersBar)
        S.Button(detail.ForgetButton)
    end)

    return browser
end

-- Data -------------------------------------------------------------------------------------------

local People = ns.People

---A person as the list shows it, without text after the nickname.
---@param person WhosWho.Person
---@param onlineGuids table<string, true>
---@return WhosWho.PersonListEntry
function PersonBrowser.ListEntry(person, onlineGuids)
    local characterCount, lastSeen, onlineCharacter = 0, nil, nil
    for guid, character in pairs(person.chars) do
        characterCount = characterCount + 1
        if character.lastSeen and (not lastSeen or character.lastSeen > lastSeen) then lastSeen = character.lastSeen end
        if onlineGuids[guid] then
            onlineCharacter = { guid = guid, name = character.name, classID = character.classID }
        end
    end
    return {
        id = person.id, nickname = People.Nickname(person.id), source = Lists.NicknameSource(person),
        characterCount = characterCount, lastSeen = lastSeen, online = onlineCharacter ~= nil,
        onlineCharacter = onlineCharacter,
    }
end

-- For the last seen sort: a row online comes before everyone seen in the past.
local function seenAt(entry)
    return entry.online and math.huge or entry.lastSeen or 0
end

---Sorts by "Name" (A to Z when ascending) or "LastSeen" (oldest first when ascending), then by name and ID so the order
---never changes between refreshes.
---@param entries WhosWho.PersonListEntry[]
---@param sortKey "Name"|"LastSeen"
---@param sortAscending boolean
function PersonBrowser.SortEntries(entries, sortKey, sortAscending)
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
        return (a.id or a.unknownCharacter.guid) < (b.id or b.unknownCharacter.guid)
    end)
end

---The main first, then by name.
---@param characters WhosWho.PersonDetailCharacter[]
function PersonBrowser.SortCharacters(characters)
    table.sort(characters, function(a, b)
        if a.main ~= b.main then return a.main end
        return a.name < b.name
    end)
end

---The nickname that applies without mine, when mine replaces it.
---@param person WhosWho.Person
---@return string?
function PersonBrowser.BaseNickname(person)
    local identityNickname = People.IdentityNickname(person.id)
    if person.customNickname and identityNickname ~= People.Nickname(person.id) then return identityNickname end
    return nil
end

---@param person WhosWho.Person
---@param onlineGuids table<string, true>
---@return WhosWho.PersonDetail
function PersonBrowser.PersonDetail(person, onlineGuids)
    local characters, battleTag = {}, nil
    for guid, character in pairs(person.chars) do
        battleTag = battleTag or character.bnetFriend
        characters[#characters + 1] = {
            guid = guid,
            name = character.name, classID = character.classID, state = character.state, main = guid == person.main,
            online = onlineGuids[guid] == true, lastSeen = character.lastSeen, level = character.level,
            ruleset = character.ruleset,
        }
    end
    PersonBrowser.SortCharacters(characters)

    return {
        nickname = People.Nickname(person.id), source = Lists.NicknameSource(person), characters = characters,
        baseNickname = PersonBrowser.BaseNickname(person), battleTag = battleTag, id = person.id, note = person.note,
        own = false,
    }
end
