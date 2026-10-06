local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

---@class WhosWho.IdentityDialogs
---@field NewIdentity WhosWho.NewIdentityDialog the first-login dialog while no character is linked
---@field LinkCharacter WhosWho.LinkCharacterDialog the first-login dialog once an identity exists
local IdentityDialogs = {}
ns.IdentityDialogs = IdentityDialogs

local WIDTH = 360
local SIDE_PADDING = 16
-- From the top of the dialog, below its title bar.
local TOP_PADDING = 34
local BOTTOM_PADDING = 14
local SPACING = 10
local BUTTON_HEIGHT = 22
local BUTTON_MIN_WIDTH = 96
local BUTTON_TEXT_PADDING = 40
-- LargeInputBoxTemplate's left text inset.
local INPUT_TEXT_LEFT = 10
-- EllesmereUI draws the checkbox border on the button's edge, where the template's label starts.
local SKINNED_CHECKBOX_LABEL_GAP = 6

local function classColoredName(name, classID)
    local _, classFile = GetClassInfo(classID)
    return classFile and C_ClassColor.GetClassColor(classFile):WrapTextInColorCode(name) or name
end

-- Layout -----------------------------------------------------------------------------------------

-- Stacks the dialog's shown rows from the top and sizes the dialog to them.
local function layOut(dialog)
    local y = TOP_PADDING
    for _, row in ipairs(dialog.rows) do
        local region = row.region
        if region:IsShown() then
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", dialog, "TOPLEFT", SIDE_PADDING + (row.x or 0), -y)
            y = y + (region.GetStringHeight and region:GetStringHeight() or region:GetHeight()) + SPACING
        end
    end
    dialog:SetHeight(y - SPACING + BOTTOM_PADDING)
end

---What every prompt dialog has; createDialog and addButtons add it.
---@class WhosWho.PromptDialog: Frame
---@field CloseButton Button
---@field rows { region: Region, x: number? }[] stacked from the top by layOut
---@field LinkButton Button
---@field NotThisCharacterButton Button

---@return WhosWho.PromptDialog
local function createDialog()
    local dialog = CreateFrame("Frame", nil, UIParent, "DefaultPanelFlatTemplate")
    dialog:SetWidth(WIDTH)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetTitle(L["Who's Who"])
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:Hide()
    dialog.TitleContainer:EnableMouse(true)
    dialog.TitleContainer:RegisterForDrag("LeftButton")
    dialog.TitleContainer:SetScript("OnDragStart", function() dialog:StartMoving() end)
    dialog.TitleContainer:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
    dialog.CloseButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButtonDefaultAnchors")
    dialog.rows = {}
    return dialog
end

local function addText(dialog, fontObject)
    local text = dialog:CreateFontString(nil, "OVERLAY", fontObject)
    text:SetWidth(WIDTH - 2 * SIDE_PADDING)
    text:SetJustifyH("CENTER")
    dialog.rows[#dialog.rows + 1] = { region = text }
    return text
end

local function createButton(parent, text)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetSize(math.max(BUTTON_MIN_WIDTH, button:GetTextWidth() + BUTTON_TEXT_PADDING), BUTTON_HEIGHT)
    return button
end

-- Link and Not this character, centred side by side.
---@param dialog WhosWho.PromptDialog
local function addButtons(dialog)
    local row = CreateFrame("Frame", nil, dialog)
    row:SetSize(WIDTH - 2 * SIDE_PADDING, BUTTON_HEIGHT)
    dialog.LinkButton = createButton(row, L["Link"])
    dialog.NotThisCharacterButton = createButton(row, L["Not this character"])
    local width = dialog.LinkButton:GetWidth() + SPACING + dialog.NotThisCharacterButton:GetWidth()
    dialog.LinkButton:SetPoint("LEFT", row, "LEFT", (row:GetWidth() - width) / 2, 0)
    dialog.NotThisCharacterButton:SetPoint("LEFT", dialog.LinkButton, "RIGHT", SPACING, 0)
    dialog.rows[#dialog.rows + 1] = { region = row }
end

-- No identity yet --------------------------------------------------------------------------------

local function createNewIdentityDialog()
    ---@class WhosWho.NewIdentityDialog: WhosWho.PromptDialog
    local dialog = createDialog()
    dialog.Question = addText(dialog, "GameFontNormalLarge")
    dialog.Explanation = addText(dialog, "GameFontHighlight")
    dialog.Explanation:SetText(L["An identity groups the characters you link to it, so people recognise you on each of them. It is shown under your main character's name."])

    local checkbox = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
    checkbox.Text:SetText(L["Use a nickname for the whole identity instead"])
    dialog.NicknameCheckbox = checkbox
    dialog.rows[#dialog.rows + 1] = { region = checkbox }

    -- LargeInputBoxTemplate has no placeholder: one like InputBoxInstructionsTemplate's.
    local input = CreateFrame("EditBox", nil, dialog, "LargeInputBoxTemplate")
    input.Instructions = input:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    input.Instructions:SetPoint("LEFT", INPUT_TEXT_LEFT, 0)
    input:SetScript("OnTextChanged", InputBoxInstructions_OnTextChanged)
    input:SetWidth(WIDTH - 2 * SIDE_PADDING)
    input:SetAutoFocus(false)
    input:SetMaxLetters(ns.Record.MAX_NAME_LENGTH)
    input:Hide()
    dialog.NicknameInput = input
    dialog.rows[#dialog.rows + 1] = { region = input }

    checkbox:SetScript("OnClick", function(self)
        input:SetShown(self:GetChecked())
        layOut(dialog)
    end)

    addButtons(dialog)
    addText(dialog, "GameFontDisableSmall"):SetText(L["Nothing is shared until a character is linked."])

    dialog.LinkButton:SetScript("OnClick", function()
        local nickname = checkbox:GetChecked() and input:GetText() or ""
        local ok, err = ns.Identity.SetNickname(nickname ~= "" and nickname or nil)
        if not ok then
            ns.Print(ns.NameErrorMessages[err] or err)
            return
        end
        ns.Identity.Link(UnitGUID("player"))
        dialog:Hide()
    end)
    -- Registers the character unlinked; closing the dialog leaves it unregistered.
    dialog.NotThisCharacterButton:SetScript("OnClick", function()
        ns.Identity.Unlink(UnitGUID("player"))
        dialog:Hide()
    end)

    ---@param name string the character logged in, "First Surname"
    ---@param classID integer
    function dialog:SetCharacter(name, classID)
        self.Question:SetText(L["Set %s as your identity's main character?"]:format(classColoredName(name, classID)))
        self.NicknameInput.Instructions:SetText(name)
        layOut(self)
    end

    ns.Skin.Apply(function(S)
        S.Shell(dialog)
        S.CloseButton(dialog.CloseButton)
        S.Checkbox(dialog.NicknameCheckbox)
        dialog.NicknameCheckbox.Text:SetPoint("LEFT", dialog.NicknameCheckbox, "RIGHT", SKINNED_CHECKBOX_LABEL_GAP, 0)
        S.EditBox(dialog.NicknameInput)
        S.Button(dialog.LinkButton)
        S.Button(dialog.NotThisCharacterButton)
    end)
    return dialog
end

-- Identity exists --------------------------------------------------------------------------------

local function createLinkCharacterDialog()
    ---@class WhosWho.LinkCharacterDialog: WhosWho.PromptDialog
    local dialog = createDialog()
    dialog.Question = addText(dialog, "GameFontNormalLarge")
    dialog.Explanation = addText(dialog, "GameFontHighlight")
    addButtons(dialog)
    addText(dialog, "GameFontDisableSmall"):SetText(L["Nothing is shared until a character is linked."])

    dialog.LinkButton:SetScript("OnClick", function()
        ns.Identity.Link(dialog.characterGuid)
        dialog:Hide()
    end)
    -- Registers the character unlinked; closing the dialog leaves it unregistered.
    dialog.NotThisCharacterButton:SetScript("OnClick", function()
        ns.Identity.Unlink(dialog.characterGuid)
        dialog:Hide()
    end)

    ---@param characterGuid string the character to link
    ---@param name string "First Surname"
    ---@param classID integer
    ---@param identityName string
    ---@param characters { name: string, classID: integer }[] the characters already linked, in the order shown
    function dialog:SetCharacter(characterGuid, name, classID, identityName, characters)
        self.characterGuid = characterGuid
        local names = {}
        for i, character in ipairs(characters) do names[i] = classColoredName(character.name, character.classID) end
        local coloredIdentityName = NORMAL_FONT_COLOR:WrapTextInColorCode(identityName)
        self.Question:SetText(L["Link %s to %s?"]:format(classColoredName(name, classID), coloredIdentityName))
        self.Explanation:SetText(L["%s already groups %s. People who see your identity will recognise this character too."]
            :format(coloredIdentityName, table.concat(names, ", ")))
        layOut(self)
    end

    ns.Skin.Apply(function(S)
        S.Shell(dialog)
        S.CloseButton(dialog.CloseButton)
        S.Button(dialog.LinkButton)
        S.Button(dialog.NotThisCharacterButton)
    end)
    return dialog
end

IdentityDialogs.NewIdentity = createNewIdentityDialog()
IdentityDialogs.LinkCharacter = createLinkCharacterDialog()

---Asks whether to link the character logged in. Without a main character, the identity starts with it.
function IdentityDialogs.AskToLink()
    local name = ns.UnitWholeName("player")
    local _, _, classID = UnitClass("player")
    local _, main = ns.Identity.Main()
    if not main then
        IdentityDialogs.NewIdentity:SetCharacter(name, classID)
        IdentityDialogs.NewIdentity:Show()
        return
    end
    IdentityDialogs.LinkCharacter:SetCharacter(UnitGUID("player"), name, classID, ns.Identity.Nickname(),
        ns.Identity.LinkedCharacters())
    IdentityDialogs.LinkCharacter:Show()
end

---Closes both first-login dialogs, leaving the character unanswered.
function IdentityDialogs.HideLinkPrompts()
    IdentityDialogs.NewIdentity:Hide()
    IdentityDialogs.LinkCharacter:Hide()
end

-- Nickname ---------------------------------------------------------------------------------------

local NICKNAME_TEXT = L["Your nickname"] .. "\n\n" .. L["Other players see it instead of your main character's name."]

-- Saves the typed nickname; a refused one keeps the popup open with the reason. The popup's data2, when set, is
-- called after a change.
local function saveNickname(popup)
    local typed = popup:GetEditBox():GetText()
    local ok, err = ns.Identity.SetNickname(typed ~= "" and typed or nil)
    if not ok then
        popup:SetText(NICKNAME_TEXT .. "\n\n" .. RED_FONT_COLOR:WrapTextInColorCode(ns.NameErrorMessages[err] or err))
        popup:Resize()
        return false
    end
    if popup.data2 then popup.data2() end
    return true
end

StaticPopupDialogs.WHOSWHO_EDIT_NICKNAME = {
    text = NICKNAME_TEXT,
    hasEditBox = true,
    maxLetters = ns.Record.MAX_NAME_LENGTH,
    button1 = L["Save"],
    button2 = CANCEL,
    button3 = L["Use main's name"],
    DisplayButton3 = function() return ns.Identity.HasNickname() end,
    OnShow = function(popup)
        local _, main = ns.Identity.Main()
        local editBox = popup:GetEditBox()
        editBox.Instructions:SetText(main and main.name or "")
        editBox:SetText(ns.Identity.HasNickname() and ns.Identity.Nickname() or "")
        editBox:SetFocus()
    end,
    OnAccept = function(popup) return not saveNickname(popup) end,
    OnAlt = function(popup)
        ns.Identity.SetNickname(nil)
        if popup.data2 then popup.data2() end
    end,
    EditBoxOnEnterPressed = function(editBox)
        local popup = editBox:GetParent()
        if saveNickname(popup) then popup:Hide() end
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(dialog) dialog:SetPoint("CENTER") end,
}

-- Confirmations ----------------------------------------------------------------------------------

-- The character's name in class colour is the text argument of the main and unlink ones.

StaticPopupDialogs.WHOSWHO_CHANGE_MAIN = {
    text = L["Make %s your main character?"] .. "\n\n"
        .. L["When you have no nickname, your identity is shown under this character's name. Players who know you see the change once Who's Who reaches them."],
    button1 = L["Make main"],
    button2 = CANCEL,
    -- `characterGuid`, the popup's data: the new main; `onMainChanged`, its data2: called after the change.
    OnAccept = function(_, characterGuid, onMainChanged)
        ns.Identity.SetMain(characterGuid)
        if onMainChanged then onMainChanged() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(dialog) dialog:SetPoint("CENTER") end,
}

StaticPopupDialogs.WHOSWHO_UNLINK = {
    text = L["Unlink %s from your identity?"] .. "\n\n"
        .. L["Players who know you stop seeing this character as yours once Who's Who reaches them. You can link it again later."],
    button1 = L["Unlink"],
    button2 = CANCEL,
    -- `characterGuid`, the popup's data: the character to unlink; `onUnlinked`, its data2: called after unlinking.
    OnAccept = function(_, characterGuid, onUnlinked)
        ns.Identity.Unlink(characterGuid)
        if onUnlinked then onUnlinked() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(dialog) dialog:SetPoint("CENTER") end,
}

StaticPopupDialogs.WHOSWHO_FORGET_ME = {
    text = L["Forget your characters and your nickname?"] .. "\n\n"
        .. L["Players who know you forget you too, once Who's Who reaches them; some may never be reached. This can't be undone."],
    button1 = L["Forget"],
    button2 = CANCEL,
    -- `onForgotten`, the popup's data: called after forgetting.
    OnAccept = function(_, onForgotten)
        ns.Identity.Forget()
        if onForgotten then onForgotten() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(dialog) dialog:SetPoint("CENTER") end,
}
