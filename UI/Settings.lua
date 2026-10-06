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
        function() return ns.settings.scopes[scope] end,
        function(value) ns.settings.scopes[scope] = value end)
    Settings.CreateCheckbox(category, setting, tooltip)
end

addSectionHeader(L["Sharing"])
addSectionText(L["Nothing is shared until a character is linked. Your identity is your nickname and your linked characters."])
addScopeCheckbox("guild", L["Guild"], L["Guild members who use Who's Who see your identity."])
addScopeCheckbox("friends", L["Friends"], L["Your friends who use Who's Who see your identity."])
addScopeCheckbox("group", L["My party or raid"],
    L["Members of your current party or raid who use Who's Who see your identity."])
addScopeCheckbox("whispers", L["People I whisper"], L["Anyone you whisper can ask for your identity."])

-- Display ----------------------------------------------------------------------------------------

addSectionHeader(L["Display"])
Settings.CreateCheckbox(category, Settings.RegisterProxySetting(category, "WhosWho_ChatNicknames",
    Settings.VarType.Boolean, L["Show nicknames in chat"], ns.Store.DEFAULTS.profile.chatNicknames,
    function() return ns.settings.chatNicknames end,
    function(value) ns.settings.chatNicknames = value end),
    L["Adds the nickname after the name, for every player you know."])
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
