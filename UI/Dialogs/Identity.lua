local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

---@class WhosWho.IdentityDialogs
---@field NewIdentity WhosWho.NewIdentityDialog the first-login dialog while no character is linked
---@field LinkCharacter WhosWho.LinkCharacterDialog the first-login dialog once an identity exists
---@field GuildRule WhosWho.GuildRuleDialog my answer to a guild enforcing linking
local IdentityDialogs = {}
ns.IdentityDialogs = IdentityDialogs

local WIDTH = 360
-- Three buttons side by side.
local GUILD_RULE_WIDTH = 440
local GUILD_MAIN_DROPDOWN_WIDTH = 180
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

---@param width number
---@return WhosWho.PromptDialog
local function createDialog(width)
    local dialog = CreateFrame("Frame", nil, UIParent, "DefaultPanelFlatTemplate")
    dialog:SetWidth(width)
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
    text:SetWidth(dialog:GetWidth() - 2 * SIDE_PADDING)
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

-- Buttons centred side by side, each set on the dialog under its key.
---@param dialog WhosWho.PromptDialog
---@param buttons { [1]: string, [2]: string }[] key and label, in order
local function addButtons(dialog, buttons)
    local row = CreateFrame("Frame", nil, dialog)
    row:SetSize(dialog:GetWidth() - 2 * SIDE_PADDING, BUTTON_HEIGHT)
    local width = -SPACING
    for _, button in ipairs(buttons) do
        dialog[button[1]] = createButton(row, button[2])
        width = width + SPACING + dialog[button[1]]:GetWidth()
    end
    for i, button in ipairs(buttons) do
        if i == 1 then
            dialog[button[1]]:SetPoint("LEFT", row, "LEFT", (row:GetWidth() - width) / 2, 0)
        else
            dialog[button[1]]:SetPoint("LEFT", dialog[buttons[i - 1][1]], "RIGHT", SPACING, 0)
        end
    end
    dialog.rows[#dialog.rows + 1] = { region = row }
end

-- Link and Not this character.
local LINK_BUTTONS = { { "LinkButton", L["Link"] }, { "NotThisCharacterButton", L["Not this character"] } }

-- No identity yet --------------------------------------------------------------------------------

local function createNewIdentityDialog()
    ---@class WhosWho.NewIdentityDialog: WhosWho.PromptDialog
    ---@field NotThisCharacterButton Button
    local dialog = createDialog(WIDTH)
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

    addButtons(dialog, LINK_BUTTONS)
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
    ---@field NotThisCharacterButton Button
    local dialog = createDialog(WIDTH)
    dialog.Question = addText(dialog, "GameFontNormalLarge")
    dialog.Explanation = addText(dialog, "GameFontHighlight")
    addButtons(dialog, LINK_BUTTONS)
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

-- Guild rule -------------------------------------------------------------------------------------

local function createGuildRuleDialog()
    ---@class WhosWho.GuildRuleDialog: WhosWho.PromptDialog
    ---@field ShareButton Button
    ---@field RefuseButton Button
    local dialog = createDialog(GUILD_RULE_WIDTH)
    dialog.Question = addText(dialog, "GameFontNormalLarge")
    dialog.Characters = addText(dialog, "GameFontHighlight")
    dialog.Explanation = addText(dialog, "GameFontHighlight")
    dialog.Explanation:SetText(L["Link them to your identity, or share them with this guild only, without linking them. If you refuse, Who's Who shares nothing with this guild, which may go against its rules."])
    -- Only while the Guild scope is off, which Link turns on.
    dialog.LinkSharesAll = addText(dialog, "GameFontHighlight")
    dialog.LinkSharesAll:SetText(L["Linking also turns sharing with your guild on: it then sees all your linked characters, not only the ones in it."])

    -- The character the guild shows me under, my main not being in it.
    local guildMain = CreateFrame("Frame", nil, dialog)
    guildMain:SetSize(GUILD_RULE_WIDTH - 2 * SIDE_PADDING, BUTTON_HEIGHT)
    guildMain.Label = guildMain:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildMain.Label:SetPoint("LEFT")
    guildMain.Label:SetText(L["Shown to the guild as"])
    guildMain.Dropdown = CreateFrame("DropdownButton", nil, guildMain, "WowStyle1DropdownTemplate")
    guildMain.Dropdown:SetWidth(GUILD_MAIN_DROPDOWN_WIDTH)
    guildMain.Dropdown:SetPoint("LEFT", guildMain.Label, "RIGHT", SPACING, 0)
    dialog.GuildMain = guildMain
    dialog.rows[#dialog.rows + 1] = { region = guildMain }

    addButtons(dialog, {
        { "LinkButton", L["Link"] }, { "ShareButton", L["Share without linking"] }, { "RefuseButton", L["Refuse"] },
    })
    addText(dialog, "GameFontDisableSmall"):SetText(L["Only this guild's members see the characters you share without linking."])

    -- Whatever the answer, the character I play is answered too: this dialog takes its first-login prompt's place.
    local function answered()
        local guid = UnitGUID("player")
        if not ns.Identity.IsRegistered(guid) then ns.Identity.Unlink(guid) end
        dialog:Hide()
    end
    dialog.LinkButton:SetScript("OnClick", function()
        for _, guid in ipairs(dialog.characterGuids) do
            if not ns.Identity.IsLinked(guid) then ns.Identity.Link(guid) end
        end
        ns.Scopes.Set("guild", true)
        if dialog.guildMainGuid then ns.Identity.SetGuildMain(dialog.guildMainGuid) end
        answered()
    end)
    dialog.ShareButton:SetScript("OnClick", function()
        if dialog.guildMainGuid then ns.Identity.SetGuildMain(dialog.guildMainGuid) end
        ns.Identity.SetEnforcedLinkingOptIn(dialog.clubId, true)
        answered()
    end)
    dialog.RefuseButton:SetScript("OnClick", function()
        ns.Identity.SetEnforcedLinkingOptIn(dialog.clubId, false)
        answered()
    end)

    ---@param clubId integer my current guild
    ---@param ruleset WhosWho.Ruleset the ruleset of the character I play
    function dialog:SetGuild(clubId, ruleset)
        self.clubId = clubId
        self.characterGuids = ns.Identity.CharactersInGuild(clubId, ruleset)
        local characters, mainGuid = ns.Identity.Characters(), ns.Identity.Main()
        local names, mainInGuild = {}, false
        for i, guid in ipairs(self.characterGuids) do
            local character = characters[guid]
            local name = classColoredName(character.name, character.classID)
            names[i] = character.linked and name or L["%s (not linked)"]:format(name)
            if guid == mainGuid then mainInGuild = true end
        end
        self.Question:SetText(L["%s requires its members to link their characters in it."]
            :format(NORMAL_FONT_COLOR:WrapTextInColorCode(GetGuildInfo("player") or "")))
        self.Characters:SetText(L["Your characters in this guild: %s."]:format(table.concat(names, ", ")))
        self.LinkSharesAll:SetShown(not ns.Scopes.Get("guild"))

        -- Several characters, none of them my main: the one the guild shows me under, the first by default.
        self.guildMainGuid = not mainInGuild and #self.characterGuids > 1 and self.characterGuids[1] or nil
        self.GuildMain:SetShown(self.guildMainGuid ~= nil)
        self.GuildMain.Dropdown:SetupMenu(function(_, root)
            for _, guid in ipairs(self.characterGuids) do
                local character = characters[guid]
                root:CreateRadio(classColoredName(character.name, character.classID),
                    function() return self.guildMainGuid == guid end, function() self.guildMainGuid = guid end)
            end
        end)
        layOut(self)
    end

    ns.Skin.Apply(function(S)
        S.Shell(dialog)
        S.CloseButton(dialog.CloseButton)
        S.Dropdown(dialog.GuildMain.Dropdown)
        S.Button(dialog.LinkButton)
        S.Button(dialog.ShareButton)
        S.Button(dialog.RefuseButton)
    end)
    return dialog
end

IdentityDialogs.NewIdentity = createNewIdentityDialog()
IdentityDialogs.LinkCharacter = createLinkCharacterDialog()
IdentityDialogs.GuildRule = createGuildRuleDialog()

---Closes both first-login dialogs, leaving the character unanswered.
function IdentityDialogs.HideLinkPrompts()
    IdentityDialogs.NewIdentity:Hide()
    IdentityDialogs.LinkCharacter:Hide()
end

-- The guild rule is asked once a session, out of combat: at login, or once the guild's settings arrive; leaving the
-- guild makes it asked again. A rule turned on during the session, in a guild whose settings I held at login, waits for
-- the next login.
local guildRuleAsked, waitingForCombatEnd = false, false
---@type table<integer, boolean>? by club ID, whether each guild I held settings of enforced linking at login
local enforcedAtLogin

-- Shows the guild rule dialog when the character I play must answer it; whether it is asked, now or once out of combat.
local function askGuildRule()
    if not enforcedAtLogin then
        enforcedAtLogin = {}
        for _, clubId in ipairs(ns.GuildSettings.HeldGuilds()) do
            enforcedAtLogin[clubId] = ns.GuildSettings.EnforcesLinking(clubId)
        end
    end
    local clubId = ns.Scopes.EnforcedLinkingChoiceNeeded()
    if guildRuleAsked or not clubId then return false end
    local guid = UnitGUID("player")
    if enforcedAtLogin[clubId] == false and not ns.Identity.JoinedGuildSinceLogin(guid) then return false end
    if UnitAffectingCombat("player") then
        waitingForCombatEnd = true
        return true
    end
    guildRuleAsked, waitingForCombatEnd = true, false
    IdentityDialogs.ShowGuildRule()
    return true
end

---Shows the guild rule dialog for my current guild, in place of the first-login prompt.
function IdentityDialogs.ShowGuildRule()
    local guid = UnitGUID("player")
    IdentityDialogs.HideLinkPrompts()
    IdentityDialogs.GuildRule:SetGuild(ns.Identity.GuildId(guid), ns.Identity.Ruleset(guid))
    IdentityDialogs.GuildRule:Show()
end

-- A change that would have stopped sharing with a guild whose rule I accepted: it keeps getting my characters in it.
ns.Identity.OnGuildRuleKept(function(clubId)
    local guildName = clubId == ns.Identity.GuildId(UnitGUID("player")) and GetGuildInfo("player")
    if guildName then
        ns.Print(L["%s requires linking: your characters in it stay shared with its members. Leave the guild to stop."]
            :format(guildName))
    else
        ns.Print(L["Your characters in a guild whose rule you accepted stay shared with its members. Leave it to stop."])
    end
end)

local guildRuleEvents = CreateFrame("Frame")
guildRuleEvents:RegisterEvent("PLAYER_LOGIN")
-- My guild known, once the roster arrives.
guildRuleEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
guildRuleEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
guildRuleEvents:RegisterUnitEvent("PLAYER_GUILD_UPDATE", "player")
guildRuleEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_GUILD_UPDATE" then
        -- A guild left; a guild joined is asked once its roster arrives.
        if not IsInGuild() then guildRuleAsked = false end
    elseif event ~= "PLAYER_REGEN_ENABLED" or waitingForCombatEnd then
        askGuildRule()
    end
end)
ns.GuildSettings.OnChanged(function() askGuildRule() end)

---Asks whether to link the character logged in. Without a main character, the identity starts with it. In a guild
---enforcing linking that I must answer, its dialog takes the place of this one.
function IdentityDialogs.AskToLink()
    if askGuildRule() then return end
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
