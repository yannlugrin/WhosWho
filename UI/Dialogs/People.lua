local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local Lists = ns.Lists
local Glyphs = ns.Glyphs
local People = ns.People

---@class WhosWho.PeopleDialogs
---@field LinkCharacter Frame links a character to a person I know, or starts a new person with it
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
---@field source "confirmed"|"renamed"|"unconfirmed"
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

---Fills the list from the people I hold, with the search and sort applied.
function dialog:Refresh()
    local text = self.SearchBox:GetText():lower()
    local entries, selectedShown = {}, false
    for _, person in pairs(People.All()) do
        if Lists.MatchesSearch(person, text) then
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

---Opens the dialog for a character that belongs to no person yet.
---@param guid string
---@param character WhosWho.NewCharacter
function dialog:Open(guid, character)
    self.guid, self.character = guid, character
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

-- Both end on the person in the People tab, where the character now is.
dialog.LinkButton:SetScript("OnClick", function()
    People.AddCharacter(dialog.selectedId, dialog.guid, dialog.character)
    local person = People.Find(dialog.guid)
    dialog:Hide()
    if person then ns.Main.People:ShowPerson(person.id) end
end)
dialog.NewPersonButton:SetScript("OnClick", function()
    People.Create(dialog.guid, dialog.character)
    local person = People.Find(dialog.guid)
    dialog:Hide()
    if person then ns.Main.People:ShowPerson(person.id) end
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
    local person = People.Get(id)
    local character = person.chars[guid]
    local nickname = Glyphs.Nickname[Lists.NicknameSource(person)].color:WrapTextInColorCode(People.Nickname(id))
    StaticPopup_Show("WHOSWHO_UNLINK_FROM_PERSON", Lists.ClassColoredName(character.name, character.classID), nickname,
        { id = id, guid = guid })
end

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
    local person = People.Get(id)
    local character = person.chars[guid]
    local nickname = Glyphs.Nickname[Lists.NicknameSource(person)].color:WrapTextInColorCode(People.Nickname(id))
    StaticPopup_Show("WHOSWHO_MAKE_PERSON_MAIN", Lists.ClassColoredName(character.name, character.classID), nickname,
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
    local person = People.Get(id)
    local nickname = Glyphs.Nickname[Lists.NicknameSource(person)].color:WrapTextInColorCode(People.Nickname(id))
    local characterCount = 0
    for _ in pairs(person.chars) do characterCount = characterCount + 1 end
    StaticPopup_Show("WHOSWHO_FORGET_PERSON", nickname,
        L["%s and their %d |4character:characters; are removed from your list. This can't be undone."]:format(
            nickname, characterCount), id)
end

-- A record can change the people while the dialog is open: it closes once the character belongs to a person,
-- and shows the people as they are otherwise.
People.OnChanged(function()
    if not dialog:IsShown() then return end
    if People.Exists(dialog.guid) then
        dialog:Hide()
    else
        dialog:Refresh()
    end
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
end)
