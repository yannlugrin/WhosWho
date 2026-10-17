local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

local category, layout = Settings.RegisterVerticalLayoutCategory(L["Who's Who"])

-- Sections ---------------------------------------------------------------------------------------

local function addSectionHeader(name)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
end

-- The text's left and right inset in WhosWhoSettingsTextTemplate.
local TEXT_INSET = 7
local TEXT_BOTTOM_PADDING = 10

-- Measures a text's height at the list's width, before its row exists.
local textMeasure = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
textMeasure:Hide()

local function addSectionText(text)
    local initializer = Settings.CreateElementInitializer("WhosWhoSettingsTextTemplate", { text = text })
    initializer.GetExtent = function(self)
        textMeasure:SetWidth(SettingsPanel.Container.SettingsList.ScrollBox:GetWidth() - 2 * TEXT_INSET)
        textMeasure:SetText(self.data.text)
        return textMeasure:GetStringHeight() + TEXT_BOTTOM_PADDING
    end
    initializer.InitFrame = function(self, frame)
        frame.Text:SetText(self.data.text)
    end
    layout:AddInitializer(initializer)
end

-- Introduction -----------------------------------------------------------------------------------

addSectionText(L["Who's Who links your characters into one identity, so people recognise you on each character you link, and lets you recognise others across theirs. Identities are shared between players who use Who's Who; for those who don't, you can link their characters yourself."])

local linkInitializer = CreateSettingsButtonInitializer("", L["Link this character"],
    function()
        SettingsPanel:Close(true)
        ns.IdentityDialogs.AskToLink()
    end, nil, true)
linkInitializer:AddModifyPredicate(function() return not ns.Identity.IsLinked(UnitGUID("player")) end)
layout:AddInitializer(linkInitializer)

-- Sharing ----------------------------------------------------------------------------------------

-- While the settings are open, what changing them would send waits until they close.
SettingsPanel:HookScript("OnShow", function() ns.Protocol.LockSending() end)
SettingsPanel:HookScript("OnHide", function() ns.Protocol.UnlockSending() end)

local function registerScopeSetting(scope, name)
    return Settings.RegisterProxySetting(category, "WhosWho_Scope_" .. scope, Settings.VarType.Boolean, name,
        ns.Store.DEFAULTS.profile.scopes[scope],
        function() return ns.Scopes.Get(scope) end,
        function(value) ns.Scopes.Set(scope, value) end)
end

local function addScopeCheckbox(scope, name, tooltip)
    return Settings.CreateCheckbox(category, registerScopeSetting(scope, name), tooltip)
end

StaticPopupDialogs.WHOSWHO_CLEAR_WHISPERS = {
    text = L["Clear the whisper history?"] .. "\n\n"
        .. L["Who's Who forgets which players you whispered: until you whisper them again, People I whisper no longer shares with them. This can't be undone."],
    button1 = L["Clear"],
    button2 = CANCEL,
    OnAccept = function() ns.Scopes.ForgetWhispers() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(dialog) dialog:SetPoint("CENTER") end,
}

addSectionHeader(L["Sharing"])
addSectionText(L["Nothing is shared until a character is linked. Your identity is your nickname and your linked characters."])
addScopeCheckbox("guild", L["Guild"], L["Guild members who also have this option on see your identity, and you see theirs."])
addScopeCheckbox("friends", L["Friends"], L["Friends who also have this option on see your identity, and you see theirs."])
addScopeCheckbox("group", L["My party or raid"],
    L["Members of your party or raid who also have this option on see your identity, and you see theirs."])
do
    -- The whisper window is greyed out while the Whispers scope is off.
    -- The history button sits right of the checkbox, usable while the scope is off: whispers are recorded either way.
    local whispersSetting = registerScopeSetting("whispers", L["People I whisper"])
    local whispersTooltip = L["When you whisper a player who also has this option on, you see each other's identity. Turning it on shares right away with everyone you whispered within the time below; clear the history first to start from no one."]
    local function clearHistory() StaticPopup_Show("WHOSWHO_CLEAR_WHISPERS") end
    local whispersInitializer
    if CreateSettingsCheckboxWithButtonInitializer then
        whispersInitializer = CreateSettingsCheckboxWithButtonInitializer(whispersSetting, L["Clear history"], clearHistory,
            nil, false, whispersTooltip)
        layout:AddInitializer(whispersInitializer)
    else
        whispersInitializer = Settings.CreateCheckbox(category, whispersSetting, whispersTooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer("", L["Clear history"], clearHistory, nil, true))
    end
    local whisperHoursInitializer = Settings.CreateDropdown(category, Settings.RegisterProxySetting(category,
        "WhosWho_WhisperHours", Settings.VarType.Number, L["Whispers count for"],
        ns.Store.DEFAULTS.profile.whisperHours,
        function() return ns.settings.whisperHours end,
        function(value) ns.settings.whisperHours = value end),
        function()
            local container = Settings.CreateControlTextContainer()
            container:Add(1, L["1 hour"])
            container:Add(3, L["3 hours"])
            container:Add(6, L["6 hours"])
            container:Add(12, L["12 hours"])
            container:Add(24, L["1 day"])
            container:Add(72, L["3 days"])
            container:Add(168, L["1 week"])
            return container:GetData()
        end,
        L["How long after your last whisper to a player you keep seeing each other's identity."])
    whisperHoursInitializer:SetParentInitializer(whispersInitializer, function() return ns.Scopes.Get("whispers") end)
end

-- Display ----------------------------------------------------------------------------------------

addSectionHeader(L["Display"])
Settings.CreateCheckbox(category, Settings.RegisterProxySetting(category, "WhosWho_ChatNicknames",
    Settings.VarType.Boolean, L["Show nicknames in chat"], ns.Store.DEFAULTS.profile.chat.nickname.enable,
    function() return ns.settings.chat.nickname.enable end,
    function(value) ns.settings.chat.nickname.enable = value end),
    L["Adds the nickname after the name, for every player you know."])
-- "hidden" turns the nickname off and keeps its position for when it is shown again.
Settings.CreateDropdown(category, Settings.RegisterProxySetting(category, "WhosWho_TooltipNickname",
    Settings.VarType.String, L["Nickname in tooltips"], ns.Store.DEFAULTS.profile.tooltip.nickname.position,
    function()
        local nickname = ns.settings.tooltip.nickname
        return nickname.enable and nickname.position or "hidden"
    end,
    function(value)
        local nickname = ns.settings.tooltip.nickname
        nickname.enable = value ~= "hidden"
        if value ~= "hidden" then nickname.position = value end
    end),
    function()
        local container = Settings.CreateControlTextContainer()
        container:Add("afterName", L["After the name"])
        container:Add("ownLine", L["On its own line"])
        container:Add("hidden", L["Hidden"])
        return container:GetData()
    end,
    L["\"After the name\" changes the tooltip's first line, which other tooltip add-ons may also change; choose \"On its own line\" if they conflict."])
do
    -- One dropdown for the "Also:" line: shown in class colours, shown in plain text, or hidden; "hidden" keeps the
    -- colour choice for when it is shown again. The number of characters is greyed out while it is hidden.
    local otherCharactersInitializer = Settings.CreateDropdown(category, Settings.RegisterProxySetting(category,
        "WhosWho_TooltipOtherCharacters", Settings.VarType.String, L["Other characters in tooltips"], "classColor",
        function()
            local otherCharacters = ns.settings.tooltip.otherCharacters
            if not otherCharacters.enable then return "hidden" end
            return otherCharacters.classColor and "classColor" or "plain"
        end,
        function(value)
            local otherCharacters = ns.settings.tooltip.otherCharacters
            otherCharacters.enable = value ~= "hidden"
            if value ~= "hidden" then otherCharacters.classColor = value == "classColor" end
        end),
        function()
            local container = Settings.CreateControlTextContainer()
            container:Add("classColor", L["Class colors"])
            container:Add("plain", L["Plain text"])
            container:Add("hidden", L["Hidden"])
            return container:GetData()
        end,
        L["Adds an \"Also:\" line with the person's other characters on the same ruleset, in their class color or in plain text."])

    local options = Settings.CreateSliderOptions(1, 10, 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    local limitInitializer = Settings.CreateSlider(category, Settings.RegisterProxySetting(category,
        "WhosWho_TooltipOtherCharactersLimit", Settings.VarType.Number, L["Other characters shown"],
        ns.Store.DEFAULTS.profile.tooltip.otherCharacters.limit,
        function() return ns.settings.tooltip.otherCharacters.limit end,
        function(value) ns.settings.tooltip.otherCharacters.limit = value end),
        options, L["How many other characters the \"Also:\" line names; the others are counted as \"+N more\"."])
    limitInitializer:SetParentInitializer(otherCharactersInitializer,
        function() return ns.settings.tooltip.otherCharacters.enable end)
end
Settings.CreateCheckbox(category, Settings.RegisterProxySetting(category, "WhosWho_TooltipNote",
    Settings.VarType.Boolean, L["Show notes in tooltips"], ns.Store.DEFAULTS.profile.tooltip.note.enable,
    function() return ns.settings.tooltip.note.enable end,
    function(value) ns.settings.tooltip.note.enable = value end),
    L["Adds the start of your note about the person."])

-- Minimap ----------------------------------------------------------------------------------------

addSectionHeader(L["Minimap"])
Settings.CreateCheckbox(category, Settings.RegisterProxySetting(category, "WhosWho_MinimapButton",
    Settings.VarType.Boolean, L["Show minimap button"], true,
    function() return not ns.settings.launcher.hide end,
    function(value) ns.Launcher.SetMinimapButtonShown(value) end),
    L["A button on the edge of the minimap: click to show or hide the window, right-click for a menu."])
Settings.CreateCheckbox(category, Settings.RegisterProxySetting(category, "WhosWho_AddOnsMenu",
    Settings.VarType.Boolean, L["Show in the add-on compartment"], true,
    function() return ns.settings.launcher.showInCompartment == true end,
    function(value) ns.Launcher.SetCompartmentShown(value) end),
    L["Who's Who in the add-on compartment next to the minimap: click to show or hide the window, right-click for a menu."])

-- Data -------------------------------------------------------------------------------------------

StaticPopupDialogs.WHOSWHO_FORGET_EVERYONE_ELSE = {
    text = L["Forget everyone else?"] .. "\n\n"
        .. L["Who's Who forgets every person you know about. This can't be undone."],
    button1 = L["Forget"],
    button2 = CANCEL,
    OnAccept = function()
        ns.People.ForgetAll()
        ns.GuildList.Forget()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    -- Centred, where the game stacks its popups at the top of the screen.
    AnchorDialogFrame = function(dialog) dialog:SetPoint("CENTER") end,
}

addSectionHeader(L["Data"])
layout:AddInitializer(CreateSettingsButtonInitializer(L["Forget me"], L["Forget"],
    function()
        -- The settings list checks the Link button's predicate only when it builds the row.
        StaticPopup_Show("WHOSWHO_FORGET_ME", nil, nil, function()
            local linkButtonRow = SettingsPanel.Container.SettingsList.ScrollBox:FindFrame(linkInitializer)
            if linkButtonRow then linkButtonRow:EvaluateState() end
        end)
    end,
    L["Forgets your characters and your nickname. Players who know you forget you too, once Who's Who reaches them; some may never be reached."],
    true))
layout:AddInitializer(CreateSettingsButtonInitializer(L["Forget everyone else"], L["Forget"],
    function() StaticPopup_Show("WHOSWHO_FORGET_EVERYONE_ELSE") end,
    L["Forgets every person you know about."], true))

-- Diagnostic -------------------------------------------------------------------------------------

local diagnosticCategory, diagnosticLayout = Settings.RegisterVerticalLayoutSubcategory(category, L["Diagnostic"])
do
    local enableInitializer = Settings.CreateCheckbox(diagnosticCategory, Settings.RegisterProxySetting(
        diagnosticCategory, "WhosWho_Diagnostic", Settings.VarType.Boolean, L["Diagnostic mode"],
        ns.Store.DEFAULTS.profile.diagnostic.enable,
        function() return ns.settings.diagnostic.enable end,
        function(value) ns.settings.diagnostic.enable = value end),
        L["Keeps the last %d messages Who's Who sends and receives, to report a problem. Turned off, the messages kept are deleted at logout."]
            :format(ns.Diagnostic.KEPT_MESSAGES))
    local chatInitializer = Settings.CreateCheckbox(diagnosticCategory, Settings.RegisterProxySetting(
        diagnosticCategory, "WhosWho_DiagnosticChat", Settings.VarType.Boolean, L["Show messages in chat"],
        ns.Store.DEFAULTS.profile.diagnostic.chat,
        function() return ns.settings.diagnostic.chat end,
        function(value) ns.settings.diagnostic.chat = value end),
        L["Prints each message in chat as it is sent or received."])
    chatInitializer:SetParentInitializer(enableInitializer, function() return ns.settings.diagnostic.enable end)
end

local STATS_TEXT_HEIGHT = 216 -- the lines under a column's title, wrapped ones included
local STATS_HEIGHT = 250
local STATS_SPACING = 12
local LOG_HEIGHT = 330
local LOG_ROW_HEIGHT = 18
local LOG_HEADER_HEIGHT = 18
local LOG_SCROLL_BAR_WIDTH = 10

-- From left to right; the last one takes the space left.
local LOG_COLUMNS = {
    { key = "Time", width = 65, label = L["Time"] },
    { key = "Direction", width = 70, label = L["Direction"] },
    { key = "Channel", width = 75, label = L["Channel"] },
    { key = "Player", width = 140, label = L["Player"] },
    { key = "Message", label = L["Message"] },
}
do
    local left = 4
    for _, column in ipairs(LOG_COLUMNS) do
        column.left = left
        left = left + (column.width or 0)
    end
end

local function placeInLogColumn(region, row, column)
    region:SetPoint("LEFT", row, "LEFT", column.left, 0)
    if column.width then
        region:SetWidth(column.width - 6)
    else
        region:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    end
    region:SetJustifyH("LEFT")
    region:SetWordWrap(false)
end

local SCOPE_KEYS = { "guild", "friends", "whispers", "group" }
local SCOPE_NAMES = { guild = L["Guild"], friends = L["Friends"], whispers = L["Whispers"], group = L["Group"] }

local function onOrOff(on)
    return on and L["on"] or L["off"]
end

local function identityStats()
    local Identity = ns.Identity
    local guid = UnitGUID("player")
    local id = Identity.Id()
    local scopesOn = {}
    for _, key in ipairs(SCOPE_KEYS) do
        if ns.Scopes.Get(key) then scopesOn[#scopesOn + 1] = SCOPE_NAMES[key] end
    end
    local lines = {
        L["Version: %s"]:format(ns.Version),
        L["Identity ID: %s"]:format(id and id:sub(1, 8) or L["none"]),
        L["Revision: %d"]:format(Identity.Revision()),
        L["Linked characters: %d"]:format(Identity.LinkedCount()),
        L["Sharing with: %s"]:format(scopesOn[1] and table.concat(scopesOn, ", ") or L["none"]),
    }
    local clubId = Identity.GuildId(guid)
    lines[#lines + 1] = clubId and L["Guild: %d"]:format(clubId) or L["Guild: none"]
    if clubId then
        lines[#lines + 1] = L["Who's Who for the guild: %s"]:format(onOrOff(ns.GuildSettings.Get(clubId).enable))
        lines[#lines + 1] = L["Linking enforced: %s"]:format(onOrOff(ns.GuildSettings.EnforcesLinking(clubId)))
        lines[#lines + 1] = L["Guild settings revision: %d"]:format(ns.GuildSettings.Revision(clubId))
        lines[#lines + 1] = ns.Scopes.CanSendOnGuild() and L["Guild channel: sends"]
            or L["Guild channel: whispers each member until the next login"]
    end
    return table.concat(lines, "\n")
end

local function peopleStats()
    local personCount, characterCounts = 0, { confirmed = 0, listed = 0, relayed = 0, added = 0, guild = 0 }
    for _, person in pairs(ns.People.All()) do
        personCount = personCount + 1
        for _, character in pairs(person.chars) do
            characterCounts[character.state] = characterCounts[character.state] + 1
        end
    end
    return table.concat({
        L["People: %d"]:format(personCount),
        L["Confirmed characters: %d"]:format(characterCounts.confirmed),
        L["Listed characters: %d"]:format(characterCounts.listed),
        L["Characters listed by the guild: %d"]:format(characterCounts.relayed),
        L["Characters linked by the guild: %d"]:format(characterCounts.guild),
        L["Characters added by you: %d"]:format(characterCounts.added),
        L["Automatic changes: %d, %d unread"]:format(#ns.AutomaticChanges.List(), ns.AutomaticChanges.UnreadCount()),
    }, "\n")
end

local function messageStats()
    local messages = ns.Diagnostic.Messages()
    local lines = { L["Messages kept: %d of %d"]:format(#messages, ns.Diagnostic.KEPT_MESSAGES) }
    if messages[1] then
        lines[#lines + 1] = L["Since: %s"]:format(date("%Y-%m-%d %H:%M", messages[#messages].time))
    end
    local counts = ns.Diagnostic.CountsByType()
    local messageTypes = {}
    for messageType in pairs(counts) do messageTypes[#messageTypes + 1] = messageType end
    table.sort(messageTypes)
    for _, messageType in ipairs(messageTypes) do
        local count = counts[messageType]
        lines[#lines + 1] = L["%s: %d sent, %d received"]:format(messageType, count.sent, count.received)
    end
    return table.concat(lines, "\n")
end

---A logged message's row; createLogRow adds its regions the first time the row is used.
---@class WhosWho.MessageLogRow: Button
---@field Time FontString
---@field Direction FontString
---@field Channel FontString
---@field Player FontString
---@field Message FontString

---@param row WhosWho.MessageLogRow
local function createLogRow(row)
    for _, column in ipairs(LOG_COLUMNS) do
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        placeInLogColumn(text, row, column)
        row[column.key] = text
    end
    -- The whole message, which the row may cut, and its date.
    row:SetScript("OnEnter", function(self)
        local message = self:GetElementData()
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(date("%Y-%m-%d %H:%M:%S", message.time), HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:AddLine(ns.Diagnostic.Describe(message), nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

---@param row WhosWho.MessageLogRow
---@param message WhosWho.LoggedMessage
local function initLogRow(row, message)
    if not row.Time then createLogRow(row) end
    row.Time:SetText(date("%H:%M:%S", message.time))
    row.Direction:SetText(message.sent and L["Sent"] or L["Received"])
    row.Channel:SetText(message.distribution)
    row.Player:SetText(message.name or "")
    row.Message:SetText(ns.Diagnostic.Describe(message))
end

---The Diagnostic page's stats and message log; createDiagnosticPanel adds its regions the first time it is used.
---@class WhosWho.DiagnosticPanel: Frame
---@field Stats { Title: FontString, Text: FontString }[] my identity, the people I know, the message log
---@field LogBox Frame
---@field Empty FontString

---@param panel WhosWho.DiagnosticPanel
local function createDiagnosticPanel(panel)
    panel.Stats = {}
    for i, title in ipairs({ L["My identity"], L["People"], L["Message log"] }) do
        local stat = {}
        stat.Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        stat.Title:SetText(title)
        stat.Title:SetJustifyH("LEFT")
        stat.Text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        stat.Text:SetPoint("TOPLEFT", stat.Title, "BOTTOMLEFT", 0, -4)
        stat.Text:SetPoint("TOPRIGHT", stat.Title, "BOTTOMRIGHT", 0, -4)
        stat.Text:SetHeight(STATS_TEXT_HEIGHT)
        stat.Text:SetJustifyH("LEFT")
        stat.Text:SetJustifyV("TOP")
        if i == 1 then
            stat.Title:SetPoint("TOPLEFT", TEXT_INSET, 0)
        else
            stat.Title:SetPoint("TOPLEFT", panel.Stats[i - 1].Title, "TOPRIGHT", STATS_SPACING, 0)
        end
        panel.Stats[i] = stat
    end
    -- Three columns of the same width.
    local function sizeStats(self)
        local columnWidth = (self:GetWidth() - 2 * TEXT_INSET - 2 * STATS_SPACING) / 3
        for _, stat in ipairs(self.Stats) do stat.Title:SetWidth(columnWidth) end
    end
    panel:SetScript("OnSizeChanged", sizeStats)
    sizeStats(panel)

    local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", TEXT_INSET, -STATS_HEIGHT)
    inset:SetPoint("BOTTOMRIGHT", -TEXT_INSET, 0)

    local header = CreateFrame("Frame", nil, inset)
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4 - LOG_SCROLL_BAR_WIDTH, -4)
    header:SetHeight(LOG_HEADER_HEIGHT)
    for _, column in ipairs(LOG_COLUMNS) do
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(column.label)
        placeInLogColumn(label, header, column)
    end

    panel.LogBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    panel.LogBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    panel.LogBox:SetPoint("BOTTOMRIGHT", -4 - LOG_SCROLL_BAR_WIDTH, 4)

    local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", panel.LogBox, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", panel.LogBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(LOG_ROW_HEIGHT)
    view:SetElementInitializer("Button", initLogRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(panel.LogBox, bar, view)

    panel.Empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.Empty:SetPoint("LEFT", 20, 0)
    panel.Empty:SetPoint("RIGHT", -20, 0)
    panel.Empty:SetText(L["No message kept yet."])

    ns.Skin.Apply(function(S)
        S.Inset(inset)
        S.ScrollBar(bar)
    end)
end

---@param panel WhosWho.DiagnosticPanel
local function refreshDiagnosticPanel(panel)
    panel.Stats[1].Text:SetText(identityStats())
    panel.Stats[2].Text:SetText(peopleStats())
    panel.Stats[3].Text:SetText(messageStats())
    local messages = ns.Diagnostic.Messages()
    panel.LogBox:SetDataProvider(CreateDataProvider(messages), ScrollBoxConstants.RetainScrollPosition)
    panel.Empty:SetShown(not messages[1])
end

---@type WhosWho.DiagnosticPanel? the settings list's row for the panel, once it was shown
local diagnosticPanel

local diagnosticInitializer = Settings.CreateElementInitializer("WhosWhoSettingsDiagnosticTemplate", {})
diagnosticInitializer.GetExtent = function() return STATS_HEIGHT + LOG_HEIGHT end
diagnosticInitializer.InitFrame = function(_, frame)
    if not frame.Stats then createDiagnosticPanel(frame) end
    diagnosticPanel = frame
    refreshDiagnosticPanel(frame)
end
diagnosticInitializer:AddShownPredicate(function() return ns.settings.diagnostic.enable end)
diagnosticLayout:AddInitializer(diagnosticInitializer)

ns.Diagnostic.OnMessageLogged(function()
    if diagnosticPanel and diagnosticPanel:IsVisible() then refreshDiagnosticPanel(diagnosticPanel) end
end)

-- Register & Slash commands ----------------------------------------------------------------------

Settings.RegisterAddOnCategory(category)

-- The settings offer their own way to link the character.
SettingsPanel:HookScript("OnShow", function() ns.IdentityDialogs.HideLinkPrompts() end)

ns.Commands.settings = function()
    Settings.OpenToCategory(category:GetID())
end
