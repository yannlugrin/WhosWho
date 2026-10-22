local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local Lists = ns.Lists
local Glyphs = ns.Glyphs
local GuildRecord = ns.GuildRecord
local People = ns.People

---@class WhosWho.PeopleDialogs
---@field LinkCharacter Frame links a character to a person I know, or starts a new one; also for my guild
local PeopleDialogs = {}
ns.PeopleDialogs = PeopleDialogs

local WIDTH, HEIGHT = 360, 480
local SIDE_PADDING = 12
-- From the top of the dialog, below its title bar.
local TOP_PADDING = 32
local ROW_HEIGHT = 24
local GLYPH_SIZE = 14
local SCROLL_BAR_WIDTH = 16
local BUTTON_HEIGHT = 22
local BUTTON_TEXT_PADDING = 40
local BUTTON_SPACING = 6

-- The person's name as the popups show it, in its glyph's colour.
local function coloredNickname(id)
    local person = People.Get(id)
    return Glyphs.Nickname[Lists.NicknameSource(person)].color:WrapTextInColorCode(People.Nickname(id))
end

-- A character of the person, in its class colour.
local function coloredCharacter(id, guid)
    local character = People.Get(id).chars[guid]
    return Lists.ClassColoredName(character.name, character.classID)
end

-- Link character ---------------------------------------------------------------------------------

local dialog = CreateFrame("Frame", nil, UIParent, "DefaultPanelFlatTemplate")
dialog:SetSize(WIDTH, HEIGHT)
dialog:SetPoint("CENTER")
dialog:SetFrameStrata("DIALOG")
dialog:SetTitle(L["Link character"])
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)
dialog:Hide()
dialog.TitleContainer:EnableMouse(true)
dialog.TitleContainer:RegisterForDrag("LeftButton")
dialog.TitleContainer:SetScript("OnDragStart", function() dialog:StartMoving() end)
dialog.TitleContainer:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
dialog.CloseButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButtonDefaultAnchors")
PeopleDialogs.LinkCharacter = dialog

dialog.Question = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dialog.Question:SetPoint("TOPLEFT", SIDE_PADDING, -TOP_PADDING)
dialog.Question:SetPoint("TOPRIGHT", -SIDE_PADDING, -TOP_PADDING)
dialog.Question:SetJustifyH("LEFT")

dialog.SearchBox = CreateFrame("EditBox", nil, dialog, "SearchBoxTemplate")
dialog.SearchBox:SetHeight(20)
dialog.SearchBox:SetPoint("TOPLEFT", dialog.Question, "BOTTOMLEFT", 6, -10)
dialog.SearchBox:SetPoint("RIGHT", -SIDE_PADDING, 0)
dialog.SearchBox.Instructions:SetText(L["Search names or characters"])

local function createButton(text)
    local button = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(button:GetTextWidth() + BUTTON_TEXT_PADDING, BUTTON_HEIGHT)
    return button
end
dialog.CancelButton = createButton(CANCEL)
dialog.CancelButton:SetPoint("BOTTOMRIGHT", -SIDE_PADDING, SIDE_PADDING)
dialog.NewPersonButton = createButton(L["New person"])
dialog.NewPersonButton:SetPoint("RIGHT", dialog.CancelButton, "LEFT", -BUTTON_SPACING, 0)
dialog.LinkButton = createButton(L["Link"])
dialog.LinkButton:SetPoint("RIGHT", dialog.NewPersonButton, "LEFT", -BUTTON_SPACING, 0)

local inset = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
inset:SetPoint("TOPLEFT", SIDE_PADDING - 4, -TOP_PADDING - 44)
inset:SetPoint("BOTTOMRIGHT", -SIDE_PADDING + 4, SIDE_PADDING + BUTTON_HEIGHT + 8)

local COLUMNS = {
    { key = "Characters", width = 40, label = L["Chars"], justify = "RIGHT" },
}
local columnsWidth = Lists.LayOut(COLUMNS)
local NAME_LEFT = 6 + GLYPH_SIZE + 6

dialog.ListHeader = Lists.CreateHeader(inset, { key = "Name", label = L["Name"], left = NAME_LEFT, sortable = true },
    COLUMNS, columnsWidth)
dialog.ListHeader:SetPoint("TOPLEFT", 4, -4)
dialog.ListHeader:SetPoint("TOPRIGHT", -4 - SCROLL_BAR_WIDTH, -4)

local listBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
listBox:SetPoint("TOPLEFT", dialog.ListHeader, "BOTTOMLEFT", 0, -2)
listBox:SetPoint("BOTTOMRIGHT", -4 - SCROLL_BAR_WIDTH, 4)

local listBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 6, 0)

---A person the character can be linked to.
---@class WhosWho.LinkCharacterEntry
---@field id string
---@field nickname string
---@field source "confirmed"|"renamed"|"guild"|"unconfirmed"
---@field main { name: string, classID: integer }?
---@field characterCount integer

---A person row; createRow adds its regions the first time the row is used.
---@class WhosWho.LinkCharacterRow: Button
---@field Selected Texture
---@field Glyph Frame
---@field Nickname FontString
---@field Main FontString
---@field Characters FontString

---@param row WhosWho.LinkCharacterRow
local function createRow(row)
    row.Selected = Lists.CreateRowHighlight(row)

    row.Glyph = CreateFrame("Frame", nil, row)
    row.Glyph:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    row.Glyph:SetPoint("LEFT", 6, 0)
    row.Glyph.Texture = row.Glyph:CreateTexture(nil, "ARTWORK")
    row.Glyph.Texture:SetAllPoints()
    row.Glyph:SetScript("OnEnter", function(self) Glyphs.ShowTooltip(self, self.glyph) end)
    row.Glyph:SetScript("OnLeave", GameTooltip_Hide)

    row.Nickname = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Nickname:SetPoint("LEFT", NAME_LEFT, 0)
    row.Nickname:SetWordWrap(false)

    row.Main = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Main:SetPoint("LEFT", row.Nickname, "RIGHT", 6, 0)
    row.Main:SetPoint("RIGHT", row, "RIGHT", -columnsWidth - 4, 0)
    row.Main:SetJustifyH("LEFT")
    row.Main:SetWordWrap(false)

    row.Characters = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Lists.Place(row.Characters, row, COLUMNS[1])

    row:SetScript("OnClick", function(self) dialog:Select(self:GetElementData().id) end)
end

---@param row WhosWho.LinkCharacterRow
---@param person WhosWho.LinkCharacterEntry
local function initRow(row, person)
    if not row.Nickname then createRow(row) end

    row.Selected:SetShown(person.id == dialog.selectedId)
    row.Glyph.glyph = Glyphs.Nickname[person.source]
    Glyphs.Set(row.Glyph.Texture, row.Glyph.glyph)
    row.Nickname:SetText(person.nickname)
    -- The nickname keeps its width; the main character takes what is left before the columns.
    local nameSpace = listBox:GetWidth() - NAME_LEFT - columnsWidth - 4
    row.Nickname:SetWidth(math.min(row.Nickname:GetUnboundedStringWidth(), nameSpace))
    row.Main:SetText(person.main and Lists.ClassColoredName(person.main.name, person.main.classID) or "")
    row.Characters:SetText(tostring(person.characterCount))
end

local view = CreateScrollBoxListLinearView()
view:SetElementExtent(ROW_HEIGHT)
view:SetElementInitializer("Button", initRow)
ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, view)

-- Filling ----------------------------------------------------------------------------------------

local sortAscending = true

---Marks a person as selected; Link is enabled once one is.
---@param id string?
function dialog:Select(id)
    self.selectedId = id
    self.LinkButton:SetEnabled(id ~= nil)
    listBox:ForEachFrame(function(row, person) row.Selected:SetShown(person.id == id) end)
end

-- Whether my guild can link a character to that person: one of its guild identities, or a shared identity with a
-- character in it.
local function linkableForGuild(person, clubId)
    if person.madeByGuild then return person.madeByGuild == clubId end
    if not person.signedRecord then return false end
    for _, character in pairs(person.chars) do
        if character.guild == clubId then return true end
    end
    return false
end

---Fills the list from the people I hold, for the guild the ones my guild can link to, with the search and sort applied.
function dialog:Refresh()
    local text = self.SearchBox:GetText():lower()
    local entries, selectedShown = {}, false
    for _, person in pairs(People.All()) do
        if Lists.MatchesSearch(person, text) and (not self.clubId or linkableForGuild(person, self.clubId)) then
            local characterCount = 0
            for _ in pairs(person.chars) do characterCount = characterCount + 1 end
            local main = person.chars[person.main]
            entries[#entries + 1] = {
                id = person.id, nickname = People.Nickname(person.id), source = Lists.NicknameSource(person),
                main = main and { name = main.name, classID = main.classID }, characterCount = characterCount,
            }
            if person.id == self.selectedId then selectedShown = true end
        end
    end
    table.sort(entries, function(a, b)
        local aName, bName = a.nickname:lower(), b.nickname:lower()
        if aName ~= bName then
            if sortAscending then return aName < bName end
            return aName > bName
        end
        return a.id < b.id
    end)
    self.ListHeader:SetSort("Name", sortAscending)
    listBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
    self:Select(selectedShown and self.selectedId or nil)
end

-- A button's text, its width following it.
local function setButtonText(button, text)
    button:SetText(text)
    button:SetWidth(button:GetTextWidth() + BUTTON_TEXT_PADDING)
end

---Opens the dialog for a character that belongs to no person yet, or, for my guild, to one I added; with a club ID,
---for that guild: my guild's record links the character, and its members get it.
---@param guid string
---@param character WhosWho.NewCharacter
---@param clubId integer? my guild, for the guild master and the officers
---@param tab WhosWho.PersonTab? the tab of the menu it comes from
function dialog:Open(guid, character, clubId, tab)
    self.guid, self.character, self.clubId, self.tab = guid, character, clubId, tab
    self:SetTitle(clubId and L["Link for the guild"] or L["Link character"])
    setButtonText(self.NewPersonButton, clubId and L["New guild person"] or L["New person"])
    self.Question:SetText(L["Which person does %s belong to?"]:format(
        Lists.ClassColoredName(character.name, character.classID)))
    self.SearchBox:SetText("")
    self.selectedId = nil
    self:Show()
    self:Refresh()
end

-- Actions ----------------------------------------------------------------------------------------

dialog.ListHeader.Labels.Name:SetScript("OnClick", function()
    sortAscending = not sortAscending
    dialog:Refresh()
end)
dialog.SearchBox:HookScript("OnTextChanged", function() dialog:Refresh() end)

-- For the guild: signs my guild's record linking the character to that identity, and sends it to its members.
local function linkForGuild(id)
    ns.Protocol.SendGuildRecord(GuildRecord.Link(dialog.clubId, id, dialog.guid, dialog.character))
end

-- Both end on the person where the character now is: selected in the Guild tab when the link started there, in the
-- People tab otherwise; in the game's guild window, its list stays shown.
local function showLinkedPerson()
    local person = People.Find(dialog.guid)
    dialog:Hide()
    if not person or dialog.tab == "guildWindow" then return end
    if dialog.tab == "guild" then
        ns.Main.Guild:Select(person.id)
    else
        ns.Main.People:ShowPerson(person.id)
    end
end
dialog.LinkButton:SetScript("OnClick", function()
    if dialog.clubId then
        linkForGuild(dialog.selectedId)
    else
        People.AddCharacter(dialog.selectedId, dialog.guid, dialog.character)
    end
    showLinkedPerson()
end)
dialog.NewPersonButton:SetScript("OnClick", function()
    if dialog.clubId then
        linkForGuild(GuildRecord.NewGuildIdentityId(dialog.guid))
    else
        People.Create(dialog.guid, dialog.character)
    end
    showLinkedPerson()
end)
dialog.CancelButton:SetScript("OnClick", function() dialog:Hide() end)

-- Unlink -----------------------------------------------------------------------------------------

StaticPopupDialogs.WHOSWHO_UNLINK_FROM_PERSON = {
    text = L["Unlink %s from %s?"] .. "\n\n"
        .. L["The character is no longer part of this person. You can link it again later."],
    button1 = L["Unlink"],
    button2 = CANCEL,
    OnAccept = function(_, data) People.RemoveCharacter(data.id, data.guid) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

---Asks to unlink a character I added from a person; People.CanRemoveCharacter tells which ones.
---@param id string
---@param guid string
function PeopleDialogs.ConfirmUnlink(id, guid)
    StaticPopup_Show("WHOSWHO_UNLINK_FROM_PERSON", coloredCharacter(id, guid), coloredNickname(id),
        { id = id, guid = guid })
end

-- Nickname ---------------------------------------------------------------------------------------

-- The popup's data is the person's ID.
-- Saves the typed nickname; a refused one keeps the popup open with the reason under its text.
local function savePersonNickname(popup)
    local typed = popup:GetEditBox():GetText()
    local ok, err = People.Rename(popup.data, typed ~= "" and typed or nil)
    if not ok then
        popup:SetText(popup.baseText .. "\n\n" .. RED_FONT_COLOR:WrapTextInColorCode(ns.NameErrorMessages[err] or err))
        popup:Resize()
        return false
    end
    return true
end

StaticPopupDialogs.WHOSWHO_EDIT_PERSON_NICKNAME = {
    text = L["Your nickname for %s"] .. "\n\n" .. L["Only you see it. It replaces the name this person is shown under."],
    hasEditBox = true,
    maxLetters = ns.Record.MAX_NAME_LENGTH,
    button1 = L["Save"],
    button2 = CANCEL,
    button3 = L["Remove my nickname"],
    DisplayButton3 = function(_, id) return People.Get(id).customNickname ~= nil end,
    OnShow = function(popup, id)
        popup.baseText = popup:GetText()
        local editBox = popup:GetEditBox()
        editBox.Instructions:SetText(People.IdentityNickname(id) or "")
        editBox:SetText(People.Get(id).customNickname or "")
        editBox:SetFocus()
    end,
    OnAccept = function(popup) return not savePersonNickname(popup) end,
    OnAlt = function(_, id) People.Rename(id, nil) end,
    EditBoxOnEnterPressed = function(editBox)
        local popup = editBox:GetParent()
        if savePersonNickname(popup) then popup:Hide() end
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

---Asks for my nickname for a person.
---@param id string
function PeopleDialogs.EditNickname(id)
    StaticPopup_Show("WHOSWHO_EDIT_PERSON_NICKNAME", coloredNickname(id), nil, id)
end

-- Note -------------------------------------------------------------------------------------------

local NOTE_WIDTH, NOTE_HEIGHT = 360, 260

local noteEditor = CreateFrame("Frame", nil, UIParent, "DefaultPanelFlatTemplate")
noteEditor:SetSize(NOTE_WIDTH, NOTE_HEIGHT)
noteEditor:SetPoint("CENTER")
noteEditor:SetFrameStrata("DIALOG")
noteEditor:SetTitle(L["Note"])
noteEditor:SetMovable(true)
noteEditor:SetClampedToScreen(true)
noteEditor:Hide()
noteEditor.TitleContainer:EnableMouse(true)
noteEditor.TitleContainer:RegisterForDrag("LeftButton")
noteEditor.TitleContainer:SetScript("OnDragStart", function() noteEditor:StartMoving() end)
noteEditor.TitleContainer:SetScript("OnDragStop", function() noteEditor:StopMovingOrSizing() end)
noteEditor.CloseButton = CreateFrame("Button", nil, noteEditor, "UIPanelCloseButtonDefaultAnchors")
PeopleDialogs.NoteEditor = noteEditor

noteEditor.About = noteEditor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
noteEditor.About:SetPoint("TOPLEFT", SIDE_PADDING, -TOP_PADDING)
noteEditor.About:SetPoint("TOPRIGHT", -SIDE_PADDING, -TOP_PADDING)
noteEditor.About:SetJustifyH("LEFT")

local function createNoteButton(text)
    local button = CreateFrame("Button", nil, noteEditor, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(button:GetTextWidth() + BUTTON_TEXT_PADDING, BUTTON_HEIGHT)
    return button
end
noteEditor.CancelButton = createNoteButton(CANCEL)
noteEditor.CancelButton:SetPoint("BOTTOMRIGHT", -SIDE_PADDING, SIDE_PADDING)
noteEditor.SaveButton = createNoteButton(L["Save"])
noteEditor.SaveButton:SetPoint("RIGHT", noteEditor.CancelButton, "LEFT", -BUTTON_SPACING, 0)

local noteInset = CreateFrame("Frame", nil, noteEditor, "InsetFrameTemplate")
noteInset:SetPoint("TOPLEFT", noteEditor.About, "BOTTOMLEFT", -4, -8)
noteInset:SetPoint("BOTTOMRIGHT", -SIDE_PADDING + 4, SIDE_PADDING + BUTTON_HEIGHT + 8)

noteEditor.Text = CreateFrame("Frame", nil, noteInset, "ScrollingEditBoxTemplate")
noteEditor.Text:SetPoint("TOPLEFT", 8, -6)
noteEditor.Text:SetPoint("BOTTOMRIGHT", -8 - SCROLL_BAR_WIDTH, 6)
noteEditor.Text:GetEditBox():SetMaxLetters(People.NOTE_MAX_LENGTH)

local noteBar = CreateFrame("EventFrame", nil, noteInset, "MinimalScrollBar")
noteBar:SetPoint("TOPLEFT", noteEditor.Text, "TOPRIGHT", 6, 0)
noteBar:SetPoint("BOTTOMLEFT", noteEditor.Text, "BOTTOMRIGHT", 6, 0)
ScrollUtil.RegisterScrollBoxWithScrollBar(noteEditor.Text:GetScrollBox(), noteBar)

-- Characters used, of the most a note may hold.
noteEditor.Count = noteEditor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
noteEditor.Count:SetPoint("BOTTOMLEFT", SIDE_PADDING, SIDE_PADDING + 6)

local function updateCount()
    noteEditor.Count:SetText(("%d / %d"):format(strlenutf8(noteEditor.Text:GetInputText()), People.NOTE_MAX_LENGTH))
end
noteEditor.Text:RegisterCallback("OnTextChanged", updateCount, noteEditor)

---Opens the editor on my note about a person.
---@param id string
function noteEditor:Open(id)
    self.id = id
    self.About:SetText(L["About %s"]:format(coloredNickname(id)))
    self.Text:SetText(People.Get(id).note or "")
    updateCount()
    self:Show()
    self.Text:SetFocus()
end

-- A refused note keeps the editor open, the reason in place of its title, so the text typed is not lost.
noteEditor.SaveButton:SetScript("OnClick", function()
    local ok, err = People.SetNote(noteEditor.id, noteEditor.Text:GetInputText())
    if not ok then
        noteEditor.About:SetText(RED_FONT_COLOR:WrapTextInColorCode(ns.NameErrorMessages[err] or err))
        return
    end
    noteEditor:Hide()
end)
noteEditor.CancelButton:SetScript("OnClick", function() noteEditor:Hide() end)

-- Make main --------------------------------------------------------------------------------------

StaticPopupDialogs.WHOSWHO_MAKE_PERSON_MAIN = {
    text = L["Make %s the main character of %s?"] .. "\n\n"
        .. L["The person is shown under this character's name when you haven't given it a nickname."],
    button1 = L["Make main"],
    button2 = CANCEL,
    OnAccept = function(_, data) People.SetMain(data.id, data.guid) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

---Asks to make a character the main of a person I created; People.CanSetMain tells which ones.
---@param id string
---@param guid string
function PeopleDialogs.ConfirmMakeMain(id, guid)
    StaticPopup_Show("WHOSWHO_MAKE_PERSON_MAIN", coloredCharacter(id, guid), coloredNickname(id),
        { id = id, guid = guid })
end

-- Forget -----------------------------------------------------------------------------------------

-- The second text argument is the whole consequence line, which names the person and counts the characters.
StaticPopupDialogs.WHOSWHO_FORGET_PERSON = {
    text = L["Forget %s?"] .. "\n\n%s",
    button1 = L["Forget"],
    button2 = CANCEL,
    OnAccept = function(_, id) People.Forget(id) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

---Asks to forget a person and their characters.
---@param id string
function PeopleDialogs.ConfirmForget(id)
    local nickname = coloredNickname(id)
    local characterCount = 0
    for _ in pairs(People.Get(id).chars) do characterCount = characterCount + 1 end
    StaticPopup_Show("WHOSWHO_FORGET_PERSON", nickname,
        L["%s and their %d |4character:characters; are removed from your list. This can't be undone."]:format(
            nickname, characterCount), id)
end

-- For the guild ----------------------------------------------------------------------------------

-- Each change for the guild is signed by me and sent to its members, who all apply it.

StaticPopupDialogs.WHOSWHO_GUILD_UNLINK = {
    text = L["Unlink %s from %s for the guild?"] .. "\n\n" .. L["Every member of the guild who uses Who's Who sees the change."],
    button1 = L["Unlink"],
    button2 = CANCEL,
    OnAccept = function(_, data) ns.Protocol.SendGuildRecord(GuildRecord.Unlink(data.clubId, data.id, { data.guid })) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

StaticPopupDialogs.WHOSWHO_GUILD_MAKE_MAIN = {
    text = L["Make %s the main character of %s for the guild?"] .. "\n\n"
        .. L["Every member of the guild who uses Who's Who sees the change."],
    button1 = L["Make main"],
    button2 = CANCEL,
    OnAccept = function(_, data) ns.Protocol.SendGuildRecord(GuildRecord.SetMain(data.clubId, data.id, data.guid)) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

StaticPopupDialogs.WHOSWHO_GUILD_REMOVE = {
    text = L["Unlink every character of %s for the guild?"] .. "\n\n"
        .. L["Every member of the guild who uses Who's Who forgets this person and the characters the guild linked to it."],
    button1 = L["Unlink"],
    button2 = CANCEL,
    OnAccept = function(_, data) ns.Protocol.SendGuildRecord(GuildRecord.Remove(data.clubId, data.id)) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

StaticPopupDialogs.WHOSWHO_GUILD_MOVE = {
    text = L["Move every character of %s to %s, for the guild?"] .. "\n\n"
        .. L["Every member of the guild who uses Who's Who sees the change."],
    button1 = L["Move"],
    button2 = CANCEL,
    OnAccept = function(_, data)
        local moved, removed = GuildRecord.MoveTo(data.clubId, data.id, data.playerId)
        ns.Protocol.SendGuildRecord(moved)
        ns.Protocol.SendGuildRecord(removed)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

StaticPopupDialogs.WHOSWHO_GUILD_KEEP_APART = {
    text = L["Unlink %s from %s for the guild?"] .. "\n\n"
        .. L["The player declares them as theirs. Every member of the guild who uses Who's Who sees the change."],
    button1 = L["Unlink"],
    button2 = CANCEL,
    OnAccept = function(_, data) ns.Protocol.SendGuildRecord(GuildRecord.Unlink(data.clubId, data.id, data.guids)) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

-- The popup's data is { clubId, id }.
-- Saves the typed nickname for the guild; a refused one keeps the popup open with the reason under its text.
local function saveGuildNickname(popup)
    local typed = popup:GetEditBox():GetText()
    local clean, err = ns.Record.CleanName(typed ~= "" and typed or nil)
    if err then
        popup:SetText(popup.baseText .. "\n\n" .. RED_FONT_COLOR:WrapTextInColorCode(ns.NameErrorMessages[err] or err))
        popup:Resize()
        return false
    end
    ns.Protocol.SendGuildRecord(GuildRecord.Rename(popup.data.clubId, popup.data.id, clean))
    return true
end

StaticPopupDialogs.WHOSWHO_GUILD_NICKNAME = {
    text = L["The guild's nickname for %s"] .. "\n\n"
        .. L["Every member of the guild who uses Who's Who sees it, unless they gave this person their own nickname."],
    hasEditBox = true,
    maxLetters = ns.Record.MAX_NAME_LENGTH,
    button1 = L["Save"],
    button2 = CANCEL,
    button3 = L["Remove the nickname"],
    DisplayButton3 = function(_, data) return People.Get(data.id).nickname ~= nil end,
    OnShow = function(popup, data)
        popup.baseText = popup:GetText()
        local editBox = popup:GetEditBox()
        editBox:SetText(People.Get(data.id).nickname or "")
        editBox:SetFocus()
    end,
    OnAccept = function(popup) return not saveGuildNickname(popup) end,
    OnAlt = function(_, data) ns.Protocol.SendGuildRecord(GuildRecord.Rename(data.clubId, data.id, nil)) end,
    EditBoxOnEnterPressed = function(editBox)
        local popup = editBox:GetParent()
        if saveGuildNickname(popup) then popup:Hide() end
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

-- The popup's data is { clubId, id }.
-- Asks the typed nickname for the guild; a refused one keeps the popup open with the reason under its text.
local function askGuildNickname(popup)
    local typed = popup:GetEditBox():GetText()
    local clean, err = ns.Record.CleanName(typed ~= "" and typed or nil)
    if err or not clean then
        err = err or "short"
        popup:SetText(popup.baseText .. "\n\n" .. RED_FONT_COLOR:WrapTextInColorCode(ns.NameErrorMessages[err] or err))
        popup:Resize()
        return false
    end
    ns.Protocol.SendGuildRecord(GuildRecord.Ask(popup.data.clubId, popup.data.id, "nickname", clean))
    return true
end

StaticPopupDialogs.WHOSWHO_GUILD_ASK_NICKNAME = {
    text = L["Ask %s for a nickname in the guild"] .. "\n\n" .. L["They choose: they can accept it, change it or refuse."],
    hasEditBox = true,
    maxLetters = ns.Record.MAX_NAME_LENGTH,
    button1 = L["Ask"],
    button2 = CANCEL,
    OnShow = function(popup)
        popup.baseText = popup:GetText()
        popup:GetEditBox():SetFocus()
    end,
    OnAccept = function(popup) return not askGuildNickname(popup) end,
    EditBoxOnEnterPressed = function(editBox)
        local popup = editBox:GetParent()
        if askGuildNickname(popup) then popup:Hide() end
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

StaticPopupDialogs.WHOSWHO_GUILD_ASK_MAIN = {
    text = L["Ask %s to make %s their main in the guild?"] .. "\n\n" .. L["They can accept or refuse."],
    button1 = L["Ask"],
    button2 = CANCEL,
    OnAccept = function(_, data)
        ns.Protocol.SendGuildRecord(GuildRecord.Ask(data.clubId, data.id, "main", data.guid))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(popup) popup:SetPoint("CENTER") end,
}

---Asks, for my guild, the player of a shared identity to show its members a nickname.
---@param clubId integer
---@param id string
function PeopleDialogs.AskGuildNickname(clubId, id)
    StaticPopup_Show("WHOSWHO_GUILD_ASK_NICKNAME", coloredNickname(id), nil, { clubId = clubId, id = id })
end

---Asks, for my guild, the player of a shared identity to show its members one of their characters in it as main.
---@param clubId integer
---@param id string
---@param guid string
function PeopleDialogs.AskGuildMain(clubId, id, guid)
    StaticPopup_Show("WHOSWHO_GUILD_ASK_MAIN", coloredNickname(id), coloredCharacter(id, guid),
        { clubId = clubId, id = id, guid = guid })
end

---Asks to unlink, for my guild, a character its record links; GuildRecord.CanUnlink tells which ones.
---@param clubId integer
---@param id string
---@param guid string
function PeopleDialogs.ConfirmGuildUnlink(clubId, id, guid)
    StaticPopup_Show("WHOSWHO_GUILD_UNLINK", coloredCharacter(id, guid), coloredNickname(id),
        { clubId = clubId, id = id, guid = guid })
end

---Asks to make a character the main of one of my guild's identities, for the guild.
---@param clubId integer
---@param id string
---@param guid string
function PeopleDialogs.ConfirmGuildMakeMain(clubId, id, guid)
    StaticPopup_Show("WHOSWHO_GUILD_MAKE_MAIN", coloredCharacter(id, guid), coloredNickname(id),
        { clubId = clubId, id = id, guid = guid })
end

---Asks to move every character of one of my guild's identities to a player's identity, for the guild.
---@param clubId integer
---@param id string
---@param playerId string
function PeopleDialogs.ConfirmGuildMove(clubId, id, playerId)
    StaticPopup_Show("WHOSWHO_GUILD_MOVE", coloredNickname(id), coloredNickname(playerId),
        { clubId = clubId, id = id, playerId = playerId })
end

---Asks to unlink, for my guild, the characters of one of its identities that players' own records hold.
---@param clubId integer
---@param id string
---@param claims WhosWho.PlayerClaim[]
function PeopleDialogs.ConfirmGuildKeepApart(clubId, id, claims)
    local recordChars, guids, names = GuildRecord.Held(clubId, id).chars, {}, {}
    for _, claim in ipairs(claims) do
        for _, guid in ipairs(claim.guids) do
            guids[#guids + 1] = guid
            names[#names + 1] = Lists.ClassColoredName(recordChars[guid].name, recordChars[guid].classID)
        end
    end
    StaticPopup_Show("WHOSWHO_GUILD_KEEP_APART", table.concat(names, ", "), coloredNickname(id),
        { clubId = clubId, id = id, guids = guids })
end

---Asks to unlink every character of one of my guild's identities, for the guild, which removes it.
---@param clubId integer
---@param id string
function PeopleDialogs.ConfirmGuildRemove(clubId, id)
    StaticPopup_Show("WHOSWHO_GUILD_REMOVE", coloredNickname(id), nil, { clubId = clubId, id = id })
end

---Asks for the nickname of one of my guild's identities, for the guild.
---@param clubId integer
---@param id string
function PeopleDialogs.EditGuildNickname(clubId, id)
    StaticPopup_Show("WHOSWHO_GUILD_NICKNAME", coloredNickname(id), nil, { clubId = clubId, id = id })
end

-- A record can change the people while the dialog is open: it shows them as they are.
People.OnChanged(function()
    if dialog:IsShown() then dialog:Refresh() end
end)

-- Skin -------------------------------------------------------------------------------------------

ns.Skin.Apply(function(S)
    S.Shell(dialog)
    S.CloseButton(dialog.CloseButton)
    S.EditBox(dialog.SearchBox)
    S.Inset(inset)
    S.ScrollBar(listBar)
    S.Button(dialog.LinkButton)
    S.Button(dialog.NewPersonButton)
    S.Button(dialog.CancelButton)
    S.Shell(noteEditor)
    S.CloseButton(noteEditor.CloseButton)
    S.Inset(noteInset)
    S.ScrollBar(noteBar)
    S.Button(noteEditor.SaveButton)
    S.Button(noteEditor.CancelButton)
end)
