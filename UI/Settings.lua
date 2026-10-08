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

local function addScopeCheckbox(scope, name, tooltip)
    local setting = Settings.RegisterProxySetting(category, "WhosWho_Scope_" .. scope, Settings.VarType.Boolean, name,
        ns.Store.DEFAULTS.profile.scopes[scope],
        function() return ns.Scopes.Get(scope) end,
        function(value) ns.Scopes.Set(scope, value) end)
    Settings.CreateCheckbox(category, setting, tooltip)
end

addSectionHeader(L["Sharing"])
addSectionText(L["Nothing is shared until a character is linked. Your identity is your nickname and your linked characters."])
addScopeCheckbox("guild", L["Guild"], L["Guild members who also have this option on see your identity, and you see theirs."])
addScopeCheckbox("friends", L["Friends"], L["Friends who also have this option on see your identity, and you see theirs."])
addScopeCheckbox("group", L["My party or raid"],
    L["Members of your party or raid who also have this option on see your identity, and you see theirs."])
addScopeCheckbox("whispers", L["People I whisper"], L["When you whisper a player who also has this option on, you see each other's identity."])

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

-- Minimap ----------------------------------------------------------------------------------------

addSectionHeader(L["Minimap"])
Settings.CreateCheckbox(category, Settings.RegisterProxySetting(category, "WhosWho_MinimapButton",
    Settings.VarType.Boolean, L["Show minimap button"], true,
    function() return not ns.settings.launcher.hide end,
    function(value) ns.Launcher.SetMinimapButtonShown(value) end),
    L["A button on the edge of the minimap: click to open your identity, right-click for a menu."])
Settings.CreateCheckbox(category, Settings.RegisterProxySetting(category, "WhosWho_AddOnsMenu",
    Settings.VarType.Boolean, L["Show in the add-on compartment"], true,
    function() return ns.settings.launcher.showInCompartment == true end,
    function(value) ns.Launcher.SetCompartmentShown(value) end),
    L["Who's Who in the add-on compartment next to the minimap: click to open your identity, right-click for a menu."])

-- Data -------------------------------------------------------------------------------------------

StaticPopupDialogs.WHOSWHO_FORGET_EVERYONE_ELSE = {
    text = L["Forget everyone else?"] .. "\n\n"
        .. L["Who's Who forgets every person you know about. This can't be undone."],
    button1 = L["Forget"],
    button2 = CANCEL,
    OnAccept = function() ns.People.ForgetAll() end,
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

-- Register & Slash commands ----------------------------------------------------------------------

Settings.RegisterAddOnCategory(category)

-- The settings offer their own way to link the character.
SettingsPanel:HookScript("OnShow", function() ns.IdentityDialogs.HideLinkPrompts() end)

ns.Commands.settings = function()
    Settings.OpenToCategory(category:GetID())
end
