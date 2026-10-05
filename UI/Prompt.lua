local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

---@class WhosWho.Prompt
---@field NewIdentity WhosWho.NewIdentityDialog the first-login dialog while no character is linked
---@field LinkCharacter WhosWho.LinkCharacterDialog the first-login dialog once an identity exists
local Prompt = {}
ns.Prompt = Prompt

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
    dialog:Hide()
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
    ---@param identityName string
    ---@param characters { name: string, classID: integer }[] the characters already linked, in the order shown
    function dialog:SetCharacter(name, classID, identityName, characters)
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

Prompt.NewIdentity = createNewIdentityDialog()
Prompt.LinkCharacter = createLinkCharacterDialog()

---Asks whether to link the character logged in. Without a main character, the identity starts with it.
function Prompt.AskToLink()
    local name = ns.UnitWholeName("player")
    local _, _, classID = UnitClass("player")
    local _, main = ns.Identity.Main()
    if not main then
        Prompt.NewIdentity:SetCharacter(name, classID)
        Prompt.NewIdentity:Show()
        return
    end
    Prompt.LinkCharacter:SetCharacter(name, classID, ns.Identity.Nickname(), ns.Identity.LinkedCharacters())
    Prompt.LinkCharacter:Show()
end
