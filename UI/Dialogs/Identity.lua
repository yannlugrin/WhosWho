local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

---@class WhosWho.IdentityDialogs
---@field NewIdentity WhosWho.NewIdentityDialog the first-login dialog while no character is linked
---@field LinkCharacter WhosWho.LinkCharacterDialog the first-login dialog once an identity exists
---@field GuildRule WhosWho.GuildRuleDialog my answer to a guild enforcing linking
---@field GuildEntry WhosWho.GuildEntryDialog my nickname and main in one guild
---@field NicknameRequest WhosWho.GuildRequestDialog my guild asks me for a nickname
---@field MainRequest WhosWho.GuildRequestDialog my guild asks me for a main
---@field GuildInvite WhosWho.GuildInviteDialog the character I play asks an officer of one of my guilds for an invite
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
        self.Question:SetText(L["Set %s as your identity's main character?"]:format(
            ns.Lists.ClassColoredName(name, classID)))
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
        local Lists = ns.Lists
        self.characterGuid = characterGuid
        local names = {}
        for i, character in ipairs(characters) do names[i] = Lists.ClassColoredName(character.name, character.classID) end
        local coloredIdentityName = NORMAL_FONT_COLOR:WrapTextInColorCode(identityName)
        self.Question:SetText(L["Link %s to %s?"]:format(Lists.ClassColoredName(name, classID), coloredIdentityName))
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
        local Lists = ns.Lists
        self.clubId = clubId
        self.characterGuids = ns.Identity.CharactersInGuild(clubId, ruleset)
        local characters, mainGuid = ns.Identity.Characters(), ns.Identity.Main()
        local names, mainInGuild = {}, false
        for i, guid in ipairs(self.characterGuids) do
            local character = characters[guid]
            local name = Lists.ClassColoredName(character.name, character.classID)
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
                root:CreateRadio(Lists.ClassColoredName(character.name, character.classID),
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

-- Guild nickname and main -----------------------------------------------------------------------

local function addLabel(dialog, text)
    local label = addText(dialog, "GameFontNormal")
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function addHint(dialog)
    local hint = addText(dialog, "GameFontDisableSmall")
    hint:SetJustifyH("LEFT")
    return hint
end

local function createGuildEntryDialog()
    ---@class WhosWho.GuildEntryDialog: WhosWho.PromptDialog
    ---@field SaveButton Button
    ---@field CancelButton Button
    local dialog = createDialog(WIDTH)
    dialog.GuildName = addText(dialog, "GameFontNormalLarge")
    -- Replaced by the error of a nickname refused (SetError).
    dialog.Explanation = addText(dialog, "GameFontDisableSmall")

    addLabel(dialog, L["Nickname in this guild"])
    -- LargeInputBoxTemplate has no placeholder: one like InputBoxInstructionsTemplate's.
    local input = CreateFrame("EditBox", nil, dialog, "LargeInputBoxTemplate")
    input.Instructions = input:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    input.Instructions:SetPoint("LEFT", INPUT_TEXT_LEFT, 0)
    input:SetScript("OnTextChanged", InputBoxInstructions_OnTextChanged)
    input:SetWidth(WIDTH - 2 * SIDE_PADDING)
    input:SetAutoFocus(false)
    input:SetMaxLetters(ns.Record.MAX_NAME_LENGTH)
    dialog.NicknameInput = input
    dialog.rows[#dialog.rows + 1] = { region = input }
    dialog.NicknameHint = addHint(dialog)

    -- Hidden while the guild sees none of my characters in it.
    dialog.MainLabel = addLabel(dialog, L["Main in this guild"])
    dialog.MainDropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
    dialog.MainDropdown:SetWidth(WIDTH - 2 * SIDE_PADDING)
    dialog.rows[#dialog.rows + 1] = { region = dialog.MainDropdown }
    dialog.MainHint = addHint(dialog)
    dialog.MainHint:SetText(L["Your characters in this guild."])

    addButtons(dialog, { { "SaveButton", L["Save"] }, { "CancelButton", CANCEL } })

    -- The guild main is set only when another character is chosen: the one shown by default stays a default.
    dialog.SaveButton:SetScript("OnClick", function()
        local nickname = dialog.NicknameInput:GetText()
        local ok, err = ns.Identity.SetGuildNickname(dialog.clubId, nickname ~= "" and nickname or nil)
        if not ok then
            dialog:SetError(ns.NameErrorMessages[err] or err)
            return
        end
        if dialog.mainGuid ~= dialog.shownMainGuid then ns.Identity.SetGuildMain(dialog.mainGuid) end
        dialog:Hide()
    end)
    dialog.CancelButton:SetScript("OnClick", function() dialog:Hide() end)

    ---@param clubId integer
    ---@param guildName string? nil while unknown
    ---@param nickname string? my nickname in that guild, nil when not set
    ---@param identityNickname string my identity's nickname, or my main's name
    ---@param characters { guid: string, name: string, classID: integer }[] my characters in that guild that its members
    ---see, in the order shown
    ---@param mainGuid string? the one it shows me under
    function dialog:SetGuild(clubId, guildName, nickname, identityNickname, characters, mainGuid)
        local Lists = ns.Lists
        self.clubId = clubId
        self.GuildName:SetText(guildName and ("<%s>"):format(guildName) or L["Unknown guild"])
        self.Explanation:SetText(L["What this guild's members see."])
        self.NicknameInput:SetText(nickname or "")
        self.NicknameInput.Instructions:SetText(identityNickname)
        self.NicknameHint:SetText(L["Empty: your nickname, %s."]:format(identityNickname))

        local hasCharacters = characters[1] ~= nil
        self.MainLabel:SetShown(hasCharacters)
        self.MainDropdown:SetShown(hasCharacters)
        self.MainHint:SetShown(hasCharacters)
        self.mainGuid, self.shownMainGuid = mainGuid, mainGuid
        self.MainDropdown:SetupMenu(function(_, root)
            for _, character in ipairs(characters) do
                root:CreateRadio(Lists.ClassColoredName(character.name, character.classID),
                    function() return self.mainGuid == character.guid end,
                    function() self.mainGuid = character.guid end)
            end
        end)
        layOut(self)
    end

    ---Shows an error in red in place of the explanation, until the next SetGuild.
    ---@param message string
    function dialog:SetError(message)
        self.Explanation:SetText(RED_FONT_COLOR:WrapTextInColorCode(message))
        layOut(self)
    end

    ns.Skin.Apply(function(S)
        S.Shell(dialog)
        S.CloseButton(dialog.CloseButton)
        S.EditBox(dialog.NicknameInput)
        S.Dropdown(dialog.MainDropdown)
        S.Button(dialog.SaveButton)
        S.Button(dialog.CancelButton)
    end)
    return dialog
end

-- Guild requests -------------------------------------------------------------------------------

-- What the members of my current guild see of me: my nickname there, and my main there.
local function shownInGuild(clubId, ruleset)
    local record = ns.Identity.UnsignedRecord(true, clubId, ruleset)
    local mainGuid = ns.Record.ShownMain(record, clubId)
    local main = ns.Identity.Characters()[mainGuid]
    return ns.Record.ShownNickname(record, clubId) or main.name, mainGuid
end

---@param buttons { [1]: string, [2]: string }[] key and label, in order
local function createGuildRequestDialog(buttons)
    ---@class WhosWho.GuildRequestDialog: WhosWho.PromptDialog
    ---@field AcceptButton Button
    ---@field EditButton Button? the nickname's only
    ---@field RefuseButton Button
    local dialog = createDialog(WIDTH)
    dialog.GuildName = addText(dialog, "GameFontNormalLarge")
    dialog.Question = addText(dialog, "GameFontHighlight")
    dialog.Now = addText(dialog, "GameFontDisableSmall")
    addButtons(dialog, buttons)

    -- Each answer is kept, so the request isn't asked again until an officer makes a newer one.
    local function answered()
        ns.Identity.AnswerRequest(dialog.clubId, dialog.kind, dialog.request.at)
        dialog:Hide()
    end
    dialog.AcceptButton:SetScript("OnClick", function()
        if dialog.kind == "nickname" then
            ns.Identity.SetGuildNickname(dialog.clubId, dialog.request.value)
        else
            ns.Identity.SetGuildMain(dialog.request.value)
        end
        answered()
    end)
    dialog.RefuseButton:SetScript("OnClick", answered)
    if dialog.EditButton then
        -- The guild's dialog opens first: the next request waits until it is closed.
        dialog.EditButton:SetScript("OnClick", function()
            ns.Main.MyIdentity:EditGuild(dialog.clubId, dialog.request.value)
            answered()
        end)
    end

    ---@param clubId integer my current guild
    ---@param ruleset WhosWho.Ruleset
    ---@param kind "nickname"|"main"
    ---@param request WhosWho.GuildRequest
    function dialog:SetRequest(clubId, ruleset, kind, request)
        self.clubId, self.kind, self.request = clubId, kind, request
        local asker = NORMAL_FONT_COLOR:WrapTextInColorCode(ns.People.Nickname(request.by) or L["An officer"])
        local nickname, mainGuid = shownInGuild(clubId, ruleset)
        self.GuildName:SetText(("<%s>"):format(GetGuildInfo("player") or ""))
        if kind == "nickname" then
            self.Question:SetText(L["%s asks you to be shown as %s to the guild's members."]
                :format(asker, NORMAL_FONT_COLOR:WrapTextInColorCode(request.value)))
            self.Now:SetText(L["Now: %s. Only this guild's members see it."]:format(nickname))
        else
            local characters = ns.Identity.Characters()
            local asked, main = characters[request.value], characters[mainGuid]
            self.Question:SetText(L["%s asks you to make %s your main in the guild."]
                :format(asker, ns.Lists.ClassColoredName(asked.name, asked.classID)))
            self.Now:SetText(L["Now: %s. Only this guild's members see it."]
                :format(ns.Lists.ClassColoredName(main.name, main.classID)))
        end
        layOut(self)
    end

    ns.Skin.Apply(function(S)
        S.Shell(dialog)
        S.CloseButton(dialog.CloseButton)
        for _, button in ipairs(buttons) do S.Button(dialog[button[1]]) end
    end)
    return dialog
end

-- Guild invite -----------------------------------------------------------------------------------

-- The officers' characters just asked: the game's line for each one not playing is hidden.
local NOT_PLAYING_SECONDS = 10
---@type table<string, number> by name: when it was asked (GetTime())
local askedOfficers = {}

local function hideNotPlaying(_, _, message)
    for name, at in pairs(askedOfficers) do
        if GetTime() - at < NOT_PLAYING_SECONDS and message == ERR_CHAT_PLAYER_NOT_FOUND_S:format(name) then return true end
    end
    return false
end
local addMessageEventFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
addMessageEventFilter("CHAT_MSG_SYSTEM", hideNotPlaying)

local function createGuildInviteDialog()
    ---@class WhosWho.GuildInviteDialog: WhosWho.PromptDialog
    ---@field AskButton Button
    ---@field CancelButton Button
    local dialog = createDialog(WIDTH)
    dialog.GuildName = addText(dialog, "GameFontNormalLarge")
    dialog.Question = addText(dialog, "GameFontHighlight")
    dialog.OfficerLabel = addLabel(dialog, L["Officer"])
    dialog.OfficerDropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
    dialog.OfficerDropdown:SetWidth(WIDTH - 2 * SIDE_PADDING)
    dialog.rows[#dialog.rows + 1] = { region = dialog.OfficerDropdown }
    dialog.Hint = addHint(dialog)
    addButtons(dialog, { { "AskButton", L["Ask"] }, { "CancelButton", CANCEL } })

    -- To each of the officer's characters: the one playing gets it, and its Who's Who checks who asks.
    dialog.AskButton:SetScript("OnClick", function()
        for _, name in ipairs(dialog.officer.names) do askedOfficers[name] = GetTime() end
        ns.Protocol.AskGuildInvite(dialog.officer.names)
        dialog:Hide()
    end)
    dialog.CancelButton:SetScript("OnClick", function() dialog:Hide() end)

    ---@param guildName string? nil while unknown
    ---@param characterName string the character I play
    ---@param officers WhosWho.KnownOfficer[]
    function dialog:SetGuild(guildName, characterName, officers)
        self.GuildName:SetText(guildName and ("<%s>"):format(guildName) or L["Unknown guild"])
        self.Question:SetText(L["Ask an officer to invite %s into the guild."]:format(characterName))
        local known = officers[1] ~= nil
        self.OfficerLabel:SetShown(known)
        self.OfficerDropdown:SetShown(known)
        self.AskButton:SetEnabled(known)
        self.Hint:SetText(known and L["Sent to each of their officer characters: the one playing gets it."]
            or L["You know no officer of this guild."])
        self.officer = officers[1]
        self.OfficerDropdown:SetupMenu(function(_, root)
            for _, officer in ipairs(officers) do
                root:CreateRadio(officer.nickname, function() return self.officer == officer end,
                    function() self.officer = officer end)
            end
        end)
        layOut(self)
    end

    ns.Skin.Apply(function(S)
        S.Shell(dialog)
        S.CloseButton(dialog.CloseButton)
        S.Dropdown(dialog.OfficerDropdown)
        S.Button(dialog.AskButton)
        S.Button(dialog.CancelButton)
    end)
    return dialog
end

IdentityDialogs.NewIdentity = createNewIdentityDialog()
IdentityDialogs.LinkCharacter = createLinkCharacterDialog()
IdentityDialogs.GuildRule = createGuildRuleDialog()
IdentityDialogs.GuildEntry = createGuildEntryDialog()
IdentityDialogs.NicknameRequest = createGuildRequestDialog({
    { "AcceptButton", L["Accept"] }, { "EditButton", L["Edit…"] }, { "RefuseButton", L["Refuse"] },
})
IdentityDialogs.MainRequest = createGuildRequestDialog({ { "AcceptButton", L["Accept"] }, { "RefuseButton", L["Refuse"] } })
IdentityDialogs.GuildInvite = createGuildInviteDialog()

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

-- My current guild's requests, asked one after the other, out of combat: at login, and when one arrives. Each is shown
-- once a session; an answer keeps it from being asked again until a newer one.
local REQUEST_KINDS = { "nickname", "main" }
local shownRequests, requestWaitingForCombatEnd = {}, false

-- Whether my guild's members already see what the request asks.
local function requestMet(clubId, ruleset, kind, request)
    local nickname, mainGuid = shownInGuild(clubId, ruleset)
    if kind == "nickname" then return ns.Identity.GuildNickname(clubId) == request.value or nickname == request.value end
    return mainGuid == request.value
end

-- The first request of my current guild I haven't answered, not shown this session, not met; a main asked must be one
-- of my characters in the guild.
local function pendingRequest()
    local guid, id = UnitGUID("player"), ns.Identity.Id()
    local clubId = IsInGuild() and ns.Identity.GuildId(guid)
    local held = clubId and id and ns.GuildRecord.Held(clubId, id)
    if not (held and held.requests and ns.Identity.LinkedCount() > 0) then return nil end
    local ruleset = ns.Identity.Ruleset(guid)
    for _, kind in ipairs(REQUEST_KINDS) do
        local request = held.requests[kind]
        local key = ("%d:%s:%d"):format(clubId, kind, request and request.at or 0)
        if request and not shownRequests[key] and request.at > (ns.Identity.AnsweredRequestAt(clubId, kind) or 0)
            and (kind ~= "main" or ns.Identity.GuildId(request.value) == clubId)
            and not requestMet(clubId, ruleset, kind, request) then
            return clubId, ruleset, kind, request, key
        end
    end
    return nil
end

-- Shows the next request, unless another of my dialogs is open.
local function askGuildRequest()
    for _, dialog in ipairs({ IdentityDialogs.NicknameRequest, IdentityDialogs.MainRequest, IdentityDialogs.GuildRule,
        IdentityDialogs.GuildEntry, IdentityDialogs.NewIdentity, IdentityDialogs.LinkCharacter }) do
        if dialog:IsShown() then return end
    end
    local clubId, ruleset, kind, request, key = pendingRequest()
    if not clubId then return end
    if UnitAffectingCombat("player") then
        requestWaitingForCombatEnd = true
        return
    end
    requestWaitingForCombatEnd = false
    shownRequests[key] = true
    local dialog = kind == "nickname" and IdentityDialogs.NicknameRequest or IdentityDialogs.MainRequest
    dialog:SetRequest(clubId, ruleset, kind, request)
    dialog:Show()
end

local requestEvents = CreateFrame("Frame")
-- My guild known, once the roster arrives.
requestEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
requestEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
requestEvents:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_REGEN_ENABLED" or requestWaitingForCombatEnd then askGuildRequest() end
end)
-- A guild's record arriving changes the people.
ns.People.OnChanged(askGuildRequest)
for _, dialog in ipairs({ IdentityDialogs.NicknameRequest, IdentityDialogs.MainRequest, IdentityDialogs.GuildRule,
    IdentityDialogs.GuildEntry, IdentityDialogs.NewIdentity, IdentityDialogs.LinkCharacter }) do
    dialog:HookScript("OnHide", askGuildRequest)
end

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
