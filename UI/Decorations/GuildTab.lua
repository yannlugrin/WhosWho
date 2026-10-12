local addonName, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

-- The Who's Who tab on the right of the guild panel, with the guild's settings.

-- EllesmereUI draws the checkbox border on the button's edge, where the template's label starts.
local SKINNED_CHECKBOX_LABEL_GAP = 6

-- The guild master and the officers see the tab: the ranks that change the settings.
local function hasSettingsRank()
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil and rankIndex <= ns.GuildSettings.LOWEST_RANK_INDEX
end

-- The settings are signed from the character I play, which the other members must know as mine, and sent to the guild.
local function canChangeSettings()
    return ns.Identity.IsLinked(UnitGUID("player")) and ns.Scopes.Get("guild")
end

---@param frame Frame CommunitiesFrame
local function addTab(frame)
    local blizzardTabs = {
        frame.ChatTab, frame.RosterTab, frame.GuildBenefitsTab, frame.GuildInfoTab, frame.GuildPreferredPlaySettingsTab,
    }

    local tab = CreateFrame("CheckButton", nil, frame, "RightSideTabTemplate")
    tab:SetFrameLevel(frame.GuildInfoTab:GetFrameLevel())
    tab.Icon:SetTexture(C_AddOns.GetAddOnMetadata(addonName, "IconTexture"))
    tab.tooltip = L["Who's Who"]
    tab:Hide()

    -- Placed and laid out like the game's Preferred Play Settings tab.
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame.CommunitiesList, "TOPRIGHT", 24, -40)
    panel:SetPoint("BOTTOMRIGHT", -12, 30)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText(L["Who's Who"])

    -- My current guild's settings.
    local function currentSettings()
        return ns.GuildSettings.Get(ns.Identity.GuildId(UnitGUID("player")))
    end

    -- A checkbox of the settings; while disabled, its tooltip says why.
    local function createCheckbox(label, disabledReason)
        local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        checkbox.Text:SetFontObject(GameFontHighlight)
        checkbox.Text:SetText(label)
        checkbox:SetMotionScriptsWhileDisabled(true)
        checkbox:SetScript("OnEnter", function(self)
            if self:IsEnabled() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(disabledReason(), nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        checkbox:SetScript("OnLeave", GameTooltip_Hide)
        return checkbox
    end

    local enableCheckbox = createCheckbox(L["Enable Who's Who for the guild"], function()
        return L["Link this character and share with your guild to change the guild's settings."]
    end)
    enableCheckbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -4, -20)
    enableCheckbox:SetScript("OnClick", function(self)
        ns.Protocol.ChangeGuildSettings({ enable = self:GetChecked(), enforceLinking = currentSettings().enforceLinking })
    end)

    -- Only with Who's Who enabled for the guild.
    local enforceCheckbox = createCheckbox(L["Require members' characters in the guild to be linked"], function()
        if not canChangeSettings() then
            return L["Link this character and share with your guild to change the guild's settings."]
        end
        return L["Enable Who's Who for the guild first."]
    end)
    enforceCheckbox:SetPoint("TOPLEFT", enableCheckbox, "BOTTOMLEFT", 0, -4)
    enforceCheckbox:SetScript("OnClick", function(self)
        ns.Protocol.ChangeGuildSettings({ enable = currentSettings().enable, enforceLinking = self:GetChecked() })
    end)

    local function refresh()
        local settings = currentSettings()
        enableCheckbox:SetChecked(settings.enable)
        enableCheckbox:SetEnabled(canChangeSettings())
        enforceCheckbox:SetChecked(settings.enforceLinking == true)
        enforceCheckbox:SetEnabled(canChangeSettings() and settings.enable)
    end
    ns.GuildSettings.OnChanged(function() if panel:IsShown() then refresh() end end)

    local function uncheckBlizzardTabs()
        for _, blizzardTab in ipairs(blizzardTabs) do blizzardTab:SetChecked(false) end
    end

    -- The game's panel stays in its current mode while the tab is shown, so the panel hides that mode's frames
    -- (a mode is the list of its frames' keys) and shows them again when it closes in the same mode. Switching the
    -- game's panel to a mode of our own would run the game's panel code from add-on code.
    ---@type Frame[]
    local hiddenFrames = {}
    local hiddenInMode

    panel:SetScript("OnShow", function()
        hiddenInMode = frame:GetDisplayMode()
        for _, key in ipairs(hiddenInMode) do
            local blizzardFrame = frame[key]
            if key ~= "CommunitiesList" and blizzardFrame:IsShown() then
                blizzardFrame:Hide()
                hiddenFrames[#hiddenFrames + 1] = blizzardFrame
            end
        end
        uncheckBlizzardTabs()
        tab:SetChecked(true)
        refresh()
    end)
    panel:SetScript("OnHide", function()
        if frame:GetDisplayMode() == hiddenInMode then
            for _, blizzardFrame in ipairs(hiddenFrames) do blizzardFrame:Show() end
        end
        hiddenFrames, hiddenInMode = {}, nil
        tab:SetChecked(false)
    end)

    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        tab:SetChecked(true)
        panel:Show()
    end)
    -- Clicking the tab of the current mode changes nothing in the game's panel code, so the panel is hidden here.
    for _, blizzardTab in ipairs(blizzardTabs) do
        blizzardTab:HookScript("OnClick", function() panel:Hide() end)
    end
    -- The game switching its panel to another mode on its own.
    hooksecurefunc(frame, "SetDisplayMode", function()
        if frame:GetDisplayMode() ~= hiddenInMode then panel:Hide() end
    end)

    -- The game shows its Guild Information tab for a guild, in the modes with tabs.
    local function updateTab()
        local shown = frame.GuildInfoTab:IsShown() and hasSettingsRank()
        tab:SetShown(shown)
        if not shown then panel:Hide() end
        local tabAbove = frame.GuildPreferredPlaySettingsTab:IsShown() and frame.GuildPreferredPlaySettingsTab
            or frame.GuildInfoTab
        tab:SetPoint("TOPLEFT", tabAbove, "BOTTOMLEFT", 0, -20)
        if panel:IsShown() then uncheckBlizzardTabs() end
    end

    hooksecurefunc(frame, "UpdateCommunitiesTabs", updateTab)
    -- A change of rank.
    tab:RegisterEvent("GUILD_ROSTER_UPDATE")
    tab:RegisterEvent("PLAYER_GUILD_UPDATE")
    tab:SetScript("OnEvent", updateTab)

    ns.Skin.Apply(function(S)
        for _, checkbox in ipairs({ enableCheckbox, enforceCheckbox }) do
            S.Checkbox(checkbox)
            checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", SKINNED_CHECKBOX_LABEL_GAP, 0)
        end
    end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", function() addTab(CommunitiesFrame) end)
