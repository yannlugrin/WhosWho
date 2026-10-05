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
addScopeCheckbox("group", L["My party or raid"],
    L["Members of your current party or raid who use Who's Who see your identity."])
addScopeCheckbox("whispers", L["People I whisper"], L["Anyone you whisper, or who whispers you, can ask for your identity."])

-- Data -------------------------------------------------------------------------------------------

StaticPopupDialogs.WHOSWHO_FORGET_ME = {
    text = L["Forget your characters and your nickname?"] .. "\n\n"
        .. L["Players who know you forget you too, once Who's Who reaches them; some may never be reached. This can't be undone."],
    button1 = L["Forget"],
    button2 = CANCEL,
    OnAccept = function() ns.Identity.Forget() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs.WHOSWHO_FORGET_EVERYONE_ELSE = {
    text = L["Forget everyone else?"] .. "\n\n"
        .. L["Who's Who forgets every person you know about. This can't be undone."],
    button1 = L["Forget"],
    button2 = CANCEL,
    OnAccept = function() ns.People.ForgetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

addSectionHeader(L["Data"])
layout:AddInitializer(CreateSettingsButtonInitializer(L["Forget me"], L["Forget"],
    function() StaticPopup_Show("WHOSWHO_FORGET_ME") end,
    L["Forgets your characters and your nickname. Players who know you forget you too, once Who's Who reaches them; some may never be reached."],
    true))
layout:AddInitializer(CreateSettingsButtonInitializer(L["Forget everyone else"], L["Forget"],
    function() StaticPopup_Show("WHOSWHO_FORGET_EVERYONE_ELSE") end,
    L["Forgets every person you know about."], true))

-- Register & Slash commands ----------------------------------------------------------------------

Settings.RegisterAddOnCategory(category)

ns.Commands.settings = function()
    Settings.OpenToCategory(category:GetID())
end
