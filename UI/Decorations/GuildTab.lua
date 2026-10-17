local addonName, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local Lists, Glyphs = ns.Lists, ns.Glyphs

-- The Who's Who tab on the right of the game's guild window: my guild's members, one row per identity, built like the
-- game's roster, with a member panel next to the window as the game has; and, for the guild master and the officers,
-- the guild's settings in place of the list.

-- EllesmereUI draws the checkbox border on the button's edge, where the template's label starts.
local SKINNED_CHECKBOX_LABEL_GAP = 6
local SKINNED_SMALL_CHECKBOX_SIZE = 16
local SEARCH_WIDTH = 160
local ROW_HEIGHT = 20
-- Under the list: the sharing line, then the glyph key.
local LIST_BOTTOM = 74
-- The member panel's characters stop growing there, and scroll.
local CHARACTERS_MAX_HEIGHT = 400
-- Above and below the member panel's characters.
local MEMBER_PANEL_TOP = 40
local MEMBER_PANEL_BOTTOM = 14
-- The member panel's nickname, as GuildTab.xml sizes it, and the edit button after it with its gap.
local NICKNAME_WIDTH = 150
local EDIT_BUTTON_EXTENT = 16
-- Under the member panel's characters, as GuildTab.xml lays them out: the claims text, or Unlink without claims, 8
-- under them; each button 22 high, 6 under what is above it.
local ACTIONS_TOP = 8
local BUTTON_EXTENT = 28
-- The member panel's characters, as GuildTab.xml lays them out: a line each; the open one with its zone and rank lines
-- and the space after them.
local CHARACTER_LINE_HEIGHT = 20
local OPEN_CHARACTER_HEIGHT = 72
local SEPARATOR_HEIGHT = 30

-- The list's columns, in the order of WhosWhoGuildTabRowTemplate's cells; Zone / Last seen runs to Rank, which sits
-- at the right as the game's roster places its extra column.
local COLUMNS = {
    { key = "Name", title = L["Nickname"], width = 140 },
    { key = "Class", title = COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS, width = 45 },
    { key = "Level", title = LEVEL_ABBR, width = 40 },
    { key = "Character", title = L["Character"], width = 120 },
    { key = "Zone", title = L["Zone / Last seen"], width = 0 },
}
local RANK_COLUMN = { key = "Rank", title = COMMUNITIES_ROSTER_COLUMN_TITLE_RANK, width = 85 }

-- The guild master and the officers change the settings.
local function hasSettingsRank()
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil and rankIndex <= ns.GuildSettings.LOWEST_RANK_INDEX
end

-- The settings are signed from the character I play, which the other members must know as mine, and sent to the guild.
local function canChangeSettings()
    return ns.Identity.IsLinked(UnitGUID("player")) and ns.Scopes.Get("guild")
end

-- Since when a character was seen offline: a time from my data, else the roster's; nil when neither knows.
local function lastSeenText(lastSeen, lastOnline)
    if lastSeen then return FriendsFrame_GetLastOnline(lastSeen) end
    if lastOnline then return FriendsFrame_GetLastOnline(lastOnline, true) end
    return nil
end

local function showGlyphTooltip(glyphFrame)
    Glyphs.ShowTooltip(glyphFrame, glyphFrame.glyph)
end

---@param frame Frame CommunitiesFrame
-- The Who's Who tab, once the game's guild window is loaded.
---@type CheckButton?
local guildTab

local function addTab(frame)
    local blizzardTabs = {
        frame.ChatTab, frame.RosterTab, frame.GuildBenefitsTab, frame.GuildInfoTab, frame.GuildPreferredPlaySettingsTab,
    }

    local tab = CreateFrame("CheckButton", nil, frame, "RightSideTabTemplate")
    tab:SetFrameLevel(frame.GuildInfoTab:GetFrameLevel())
    tab.Icon:SetTexture(C_AddOns.GetAddOnMetadata(addonName, "IconTexture"))
    tab.tooltip = L["Who's Who"]
    tab:Hide()
    guildTab = tab

    -- Placed like the game's Preferred Play Settings tab.
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame.CommunitiesList, "TOPRIGHT", 24, -40)
    panel:SetPoint("BOTTOMRIGHT", -12, 30)
    panel:Hide()

    local listView = CreateFrame("Frame", nil, panel)
    listView:SetAllPoints()
    local settingsView = CreateFrame("Frame", nil, panel)
    settingsView:SetAllPoints()
    settingsView:Hide()

    -- Settings view ------------------------------------------------------------------------------

    local title = settingsView:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText(L["Who's Who"])

    local closeButton = CreateFrame("Button", nil, settingsView, "UIPanelButtonTemplate")
    closeButton:SetText(CLOSE)
    closeButton:SetSize(closeButton:GetTextWidth() + 40, 22)
    closeButton:SetPoint("TOPRIGHT", -8, -12)

    -- My current guild's settings.
    local function currentSettings()
        return ns.GuildSettings.Get(ns.Identity.GuildId(UnitGUID("player")))
    end

    -- A checkbox of the settings; while disabled, its tooltip says why.
    local function createCheckbox(label, disabledReason)
        local checkbox = CreateFrame("CheckButton", nil, settingsView, "UICheckButtonTemplate")
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
        ns.Protocol.ChangeGuildSettings({
            enable = self:GetChecked(), enforceLinking = currentSettings().enforceLinking,
        })
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

    local function refreshSettings()
        local settings = currentSettings()
        enableCheckbox:SetChecked(settings.enable)
        enableCheckbox:SetEnabled(canChangeSettings())
        enforceCheckbox:SetChecked(settings.enforceLinking == true)
        enforceCheckbox:SetEnabled(canChangeSettings() and settings.enable)
    end

    -- List view: list ----------------------------------------------------------------------------

    -- Where the game's roster puts its list, with room below for the sharing line and the key.
    local list = CreateFrame("Frame", nil, listView, "WhosWhoGuildTabListTemplate")
    list:SetPoint("TOPLEFT", frame.CommunitiesList, "TOPRIGHT", 26, -60)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, LIST_BOTTOM)
    list.ColumnDisplay:LayoutColumns(COLUMNS, RANK_COLUMN)

    -- List view: top bar, above the column headers as the game's Show Offline checkbox ------------

    -- On the list, above the column headers' background.
    local offlineCheckbox = CreateFrame("CheckButton", nil, list, "UICheckButtonTemplate")
    offlineCheckbox:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, 26)
    offlineCheckbox.Text:SetText(COMMUNITIES_MEMBER_LIST_SHOW_OFFLINE)

    local searchBox = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
    searchBox:SetSize(SEARCH_WIDTH, 20)
    searchBox:SetPoint("LEFT", offlineCheckbox.Text, "RIGHT", 18, 0)
    searchBox.Instructions:SetText(L["Search names or characters"])

    local counts = list.ColumnDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    counts:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
    counts:SetPoint("RIGHT", list, "TOPRIGHT", 0, 39)
    counts:SetJustifyH("RIGHT")
    counts:SetWordWrap(false)

    ---@type string? the selected row: an identity ID, or the GUID of a character no identity holds
    local selectedKey

    local function rowKey(entry)
        return entry.id or entry.unknownCharacter.guid
    end

    -- List view: sharing line, key and settings button ---------------------------------------------

    local sharingIcon = listView:CreateTexture(nil, "OVERLAY")
    sharingIcon:SetSize(14, 14)
    sharingIcon:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -8)
    sharingIcon:SetTexture(Glyphs.Nickname.guild.texture)
    sharingIcon:SetVertexColor(NORMAL_FONT_COLOR:GetRGB())

    local sharingButton = CreateFrame("Button", nil, listView, "UIPanelButtonTemplate")
    sharingButton:SetSize(96, 20)
    sharingButton:SetPoint("RIGHT", list, "BOTTOMRIGHT", 12, -15)

    local sharingText = listView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sharingText:SetPoint("LEFT", sharingIcon, "RIGHT", 6, 0)
    sharingText:SetPoint("RIGHT", sharingButton, "LEFT", -8, 0)
    sharingText:SetJustifyH("LEFT")
    sharingText:SetWordWrap(false)

    ---@type fun()?
    local sharingAction
    sharingButton:SetScript("OnClick", function() if sharingAction then sharingAction() end end)

    Glyphs.AddKey(listView, 4, 4)

    -- In the window's bottom bar, where the game's roster has its Guild Settings button.
    local settingsButton = CreateFrame("Button", nil, listView, "UIPanelButtonTemplate")
    settingsButton:SetText(L["Who's Who settings"])
    settingsButton:SetSize(math.max(130, settingsButton:GetTextWidth() + 30), 20)
    settingsButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)

    -- Member panel -------------------------------------------------------------------------------

    -- Next to the window, where the game puts its member panel.
    local memberPanel = CreateFrame("Frame", nil, frame, "WhosWhoGuildMemberPanelTemplate")
    memberPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", -8, -76)
    memberPanel:SetFrameLevel(1000)
    memberPanel:Hide()
    memberPanel.Glyph:SetScript("OnEnter", showGlyphTooltip)
    memberPanel.Glyph:SetScript("OnLeave", GameTooltip_Hide)
    memberPanel.ScrollBar:SetHideIfUnscrollable(true)
    memberPanel.UnlinkButton:SetText(L["Unlink"])
    memberPanel.EditNicknameButton:SetNormalTexture(Glyphs.EDIT_TEXTURE)
    memberPanel.EditNicknameButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Edit the guild's nickname"], HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:Show()
    end)
    memberPanel.EditNicknameButton:SetScript("OnLeave", GameTooltip_Hide)
    memberPanel.KeepApartButton:SetText(L["Keep apart"])
    -- Anchored here: the edit button after the nickname, the claims text and the buttons under the characters' list.
    memberPanel.EditNicknameButton:SetPoint("LEFT", memberPanel.Nickname, "RIGHT", 4, 0)
    memberPanel.Claims:SetPoint("TOPLEFT", memberPanel.ScrollBox, "BOTTOMLEFT", 0, -ACTIONS_TOP)
    memberPanel.MoveButton:SetPoint("TOPLEFT", memberPanel.Claims, "BOTTOMLEFT", 0, -6)
    local claimRegions = { memberPanel.Claims, memberPanel.MoveButton, memberPanel.KeepApartButton }

    ---A line of the member panel's list: a character, with its member when it is in the guild; or the separator before
    ---those not in the guild.
    ---@class WhosWho.GuildTabCharacterElement
    ---@field character WhosWho.PersonDetailCharacter?
    ---@field member WhosWho.GuildMember?
    ---@field open boolean?

    ---@param element WhosWho.GuildTabCharacterElement
    local function characterExtent(_, element)
        if not element.character then return SEPARATOR_HEIGHT end
        return element.open and OPEN_CHARACTER_HEIGHT or CHARACTER_LINE_HEIGHT
    end

    ---@type string? the GUID of the member panel's open character
    local openGuid
    -- The roster as the list's last refresh read it.
    ---@type table<string, WhosWho.GuildMember>
    local membersByGuid = {}
    -- What the member panel shows, to show it again with another character open.
    ---@type WhosWho.PersonDetail?
    local shownDetail
    ---@type string?
    local shownRowGuid

    ---Shows a person, my own identity or a character no identity holds: its characters in the guild first, one of them
    ---open; the one I opened while it is still in the guild, else the row's.
    ---@param detailData WhosWho.PersonDetail
    ---@param rowGuid string the character the list's row shows
    local function showMemberPanel(detailData, rowGuid)
        memberPanel.Glyph.glyph = Glyphs.Nickname[detailData.source]
        Glyphs.Set(memberPanel.Glyph.Texture, memberPanel.Glyph.glyph)
        local guild = detailData.changes == "guild"
        memberPanel.EditNicknameButton:SetShown(guild)
        memberPanel.UnlinkButton:SetShown(guild)
        memberPanel.Nickname:SetText(detailData.nickname)
        -- The edit button follows the nickname.
        local nicknameSpace = guild and NICKNAME_WIDTH - EDIT_BUTTON_EXTENT or NICKNAME_WIDTH
        memberPanel.Nickname:SetWidth(math.min(memberPanel.Nickname:GetUnboundedStringWidth(), nicknameSpace))

        local claims = detailData.claims
        for _, region in ipairs(claimRegions) do region:SetShown(claims ~= nil) end
        local actionsHeight = 0
        if claims then
            local lines = {}
            for i, claim in ipairs(claims) do
                lines[i] = L["%s declares %s as theirs."]:format(claim.nickname, claim.characters)
            end
            memberPanel.Claims:SetText(table.concat(lines, "\n"))
            -- Everything goes to one player only.
            local moveShown = #claims == 1
            memberPanel.MoveButton:SetShown(moveShown)
            memberPanel.MoveButton:SetText(L["Move all to %s"]:format(claims[1].nickname))
            memberPanel.KeepApartButton:SetPoint("TOPLEFT", moveShown and memberPanel.MoveButton or memberPanel.Claims,
                "BOTTOMLEFT", 0, -6)
            actionsHeight = ACTIONS_TOP + memberPanel.Claims:GetStringHeight()
                + (moveShown and 2 or 1) * BUTTON_EXTENT
        end
        if guild then
            memberPanel.UnlinkButton:ClearAllPoints()
            if claims then
                memberPanel.UnlinkButton:SetPoint("TOPLEFT", memberPanel.KeepApartButton, "BOTTOMLEFT", 0, -6)
                actionsHeight = actionsHeight + BUTTON_EXTENT
            else
                memberPanel.UnlinkButton:SetPoint("TOPLEFT", memberPanel.ScrollBox, "BOTTOMLEFT", 0, -ACTIONS_TOP)
                actionsHeight = ACTIONS_TOP + BUTTON_EXTENT - 6
            end
        end

        local openInGuild = false
        for _, character in ipairs(detailData.characters) do
            if character.guid == openGuid and membersByGuid[character.guid] then openInGuild = true end
        end
        if not openInGuild then openGuid = rowGuid end

        local elements, others = {}, {}
        for _, character in ipairs(detailData.characters) do
            local member = membersByGuid[character.guid]
            if member then
                elements[#elements + 1] = { character = character, member = member, open = character.guid == openGuid }
            else
                others[#others + 1] = { character = character }
            end
        end
        if others[1] then
            elements[#elements + 1] = {}
            for _, element in ipairs(others) do elements[#elements + 1] = element end
        end

        local height = 0
        for index, element in ipairs(elements) do height = height + characterExtent(index, element) end
        height = math.min(height, CHARACTERS_MAX_HEIGHT)
        memberPanel.ScrollBox:SetHeight(height)
        memberPanel:SetHeight(MEMBER_PANEL_TOP + height + actionsHeight + MEMBER_PANEL_BOTTOM)
        -- The same row shown again keeps its place in the list.
        memberPanel.ScrollBox:SetDataProvider(CreateDataProvider(elements),
            rowGuid == shownRowGuid and ScrollBoxConstants.RetainScrollPosition or nil)
        shownDetail, shownRowGuid = detailData, rowGuid
        memberPanel:Show()
    end

    -- A click opens a character in the guild; a right-click shows the Guild tab's menu on any of them.
    local function clickCharacterLine(line, button)
        local element = line:GetElementData()
        local character = element.character
        if button == "RightButton" then
            ns.UnitMenu.OpenCharacterMenu(line, character.name, character.guid, {
                name = character.name, ruleset = character.ruleset, classID = character.classID,
                level = character.level,
            }, "guildWindow")
        elseif element.member then
            openGuid = character.guid
            showMemberPanel(shownDetail, shownRowGuid)
        end
    end

    local function initSeparator(line)
        line.Text:SetText(L["Not in the guild"])
    end

    -- A character's line: its level in the guild; when it was last seen outside.
    ---@param line Button WhosWhoGuildCharacterLineTemplate
    ---@param element WhosWho.GuildTabCharacterElement
    local function initCharacterLine(line, element)
        local character, member = element.character, element.member
        -- A character no identity holds has no state.
        local glyph = character.state and Glyphs.Character[character.state]
        line.StateGlyph:SetShown(glyph ~= nil)
        if glyph then
            line.StateGlyph.glyph = glyph
            Glyphs.Set(line.StateGlyph.Texture, glyph)
            line.StateGlyph:SetScript("OnEnter", showGlyphTooltip)
            line.StateGlyph:SetScript("OnLeave", GameTooltip_Hide)
        end
        line.Class:SetShown(character.classID ~= nil)
        if character.classID then Lists.SetClassIcon(line.Class, character.classID) end
        line.Name:SetText(character.classID and Lists.ClassColoredName(character.name, character.classID)
            or character.name)
        line.Crown:SetShown(character.main)
        if member then
            line.Aside:SetText(tostring(member.level))
        else
            line.Aside:SetText(character.online and GUILD_ONLINE_LABEL or lastSeenText(character.lastSeen) or "")
        end
        line:SetScript("OnClick", clickCharacterLine)
    end

    -- The open character: its line, marked, then as the game's member panel shows a member.
    ---@param block Button WhosWhoGuildOpenCharacterTemplate
    ---@param element WhosWho.GuildTabCharacterElement
    local function initOpenCharacter(block, element)
        initCharacterLine(block, element)
        block:LockHighlight()
        local character, member = element.character, element.member
        if character.online and member.zone then
            block.SeenLabel:SetText(ZONE_COLON)
            block.SeenText:SetText(member.zone)
        else
            block.SeenLabel:SetText(LAST_ONLINE_COLON)
            block.SeenText:SetText(character.online and GUILD_ONLINE_LABEL
                or lastSeenText(character.lastSeen, member.lastOnline) or "")
        end
        block.RankText:SetText(member.rank)
    end

    local charactersView = CreateScrollBoxListLinearView()
    charactersView:SetElementFactory(function(factory, element)
        if element.open then
            factory("WhosWhoGuildOpenCharacterTemplate", initOpenCharacter)
        elseif element.character then
            factory("WhosWhoGuildCharacterLineTemplate", initCharacterLine)
        else
            factory("WhosWhoGuildSeparatorTemplate", initSeparator)
        end
    end)
    charactersView:SetElementExtentCalculator(characterExtent)
    ScrollUtil.InitScrollBoxListWithScrollBar(memberPanel.ScrollBox, memberPanel.ScrollBar, charactersView)

    -- Data and filling ---------------------------------------------------------------------------

    local GuildRoster = ns.GuildRoster
    local showOffline = false
    -- The list's sort, by column key. At first, online first and the most recently seen.
    local sortKey, sortAscending = "Zone", false

    -- For the Zone column: online rows first, then by zone; the others by when they were last seen.
    local function seenAt(entry)
        if entry.online then return math.huge end
        if entry.lastSeen then return entry.lastSeen end
        local lastOnline = entry.member and entry.member.lastOnline
        return lastOnline and (time() - lastOnline) or 0
    end

    local function sortEntries(entries)
        table.sort(entries, function(a, b)
            local aValue, bValue
            if sortKey == "Level" then
                aValue, bValue = a.member and a.member.level or 0, b.member and b.member.level or 0
            elseif sortKey == "Class" then
                aValue, bValue = a.member and a.member.classID or 0, b.member and b.member.classID or 0
            elseif sortKey == "Rank" then
                aValue, bValue = a.member and a.member.rankIndex or 0, b.member and b.member.rankIndex or 0
            elseif sortKey == "Character" then
                aValue, bValue = a.member and a.member.name:lower() or "", b.member and b.member.name:lower() or ""
            elseif sortKey == "Zone" then
                aValue, bValue = seenAt(a), seenAt(b)
                if aValue == math.huge and bValue == math.huge then
                    aValue, bValue = a.member and a.member.zone or "", b.member and b.member.zone or ""
                    -- Online rows by zone A to Z, whichever way the column goes.
                    if aValue ~= bValue then return aValue < bValue end
                end
            end
            if aValue ~= nil and aValue ~= bValue then
                if sortAscending then return aValue < bValue end
                return aValue > bValue
            end
            local aName, bName = a.nickname:lower(), b.nickname:lower()
            if aName ~= bName then
                if sortKey == "Name" and not sortAscending then return aName > bName end
                return aName < bName
            end
            return rowKey(a) < rowKey(b)
        end)
    end

    -- The detail of a row: a person or my own identity, or the character no identity holds.
    local function detailOf(entry)
        if entry.id then return GuildRoster.Detail(entry.id) end
        local member = entry.member
        return {
            nickname = member.name, source = "unconfirmed",
            characters = { { guid = member.guid, name = member.name, classID = member.classID, main = true,
                online = member.online, level = member.level, ruleset = ns.Identity.Ruleset(UnitGUID("player")) } },
        }
    end

    local function markSelected(row, entry)
        if rowKey(entry) == selectedKey then row:LockHighlight() else row:UnlockHighlight() end
    end

    -- Another row opens its own character in the member panel; the same row again keeps the one I opened.
    local function selectRow(entry)
        local key = entry and rowKey(entry) or nil
        if key ~= selectedKey then openGuid = nil end
        selectedKey = key
        list.ScrollBox:ForEachFrame(markSelected)
        local detailData = entry and detailOf(entry)
        if not detailData then
            memberPanel:Hide()
            return
        end
        showMemberPanel(detailData, entry.member.guid)
    end

    local function refreshList()
        local members = GuildRoster.Members()
        membersByGuid = {}
        for _, member in ipairs(members) do membersByGuid[member.guid] = member end
        local entries, guildCounts = GuildRoster.Entries(searchBox:GetText():lower(), members)
        counts:SetText(L["%d |4main character:main characters; · %d |4alt:alts; · %d unknown"]:format(
            guildCounts.main, guildCounts.alt, guildCounts.unknown))
        local shownEntries = {}
        local selected
        for _, entry in ipairs(entries) do
            if showOffline or entry.online then
                shownEntries[#shownEntries + 1] = entry
                if rowKey(entry) == selectedKey then selected = entry end
            end
        end
        sortEntries(shownEntries)
        list.ScrollBox:SetDataProvider(CreateDataProvider(shownEntries), ScrollBoxConstants.RetainScrollPosition)
        selectRow(selected)

        local text, button, action = GuildRoster.Sharing()
        sharingText:SetText(text)
        sharingButton:SetText(button or "")
        sharingButton:SetShown(button ~= nil)
        sharingAction = action
        settingsButton:SetShown(hasSettingsRank())
    end

    -- A click on the active column reverses it; another column starts A to Z for names, in class order for classes,
    -- highest rank first for ranks, highest or most recent first for the others.
    list.ColumnDisplay.sortingFunction = function(_, columnIndex)
        local key = (COLUMNS[columnIndex] or RANK_COLUMN).key
        if key == sortKey then
            sortAscending = not sortAscending
        else
            sortKey, sortAscending = key, key == "Name" or key == "Character" or key == "Class" or key == "Rank"
        end
        refreshList()
    end

    searchBox:HookScript("OnTextChanged", function() if listView:IsVisible() then refreshList() end end)
    offlineCheckbox:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        showOffline = self:GetChecked()
        refreshList()
    end)
    memberPanel.CloseButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        selectRow(nil)
    end)

    -- The guild's changes, on the shown identity.
    local function guildId() return ns.Identity.GuildId(UnitGUID("player")) end
    memberPanel.EditNicknameButton:SetScript("OnClick", function()
        ns.PeopleDialogs.EditGuildNickname(guildId(), shownDetail.id)
    end)
    memberPanel.UnlinkButton:SetScript("OnClick", function()
        ns.PeopleDialogs.ConfirmGuildRemove(guildId(), shownDetail.id)
    end)
    memberPanel.MoveButton:SetScript("OnClick", function()
        ns.PeopleDialogs.ConfirmGuildMove(guildId(), shownDetail.id, shownDetail.claims[1].playerId)
    end)
    memberPanel.KeepApartButton:SetScript("OnClick", function()
        ns.PeopleDialogs.ConfirmGuildKeepApart(guildId(), shownDetail.id, shownDetail.claims)
    end)

    -- A click selects the row; a right-click shows the Guild tab's menu on the character the row shows.
    local function clickRow(row, button)
        local entry = row:GetElementData()
        if button ~= "RightButton" then
            selectRow(entry)
            return
        end
        local character = entry.unknownCharacter and entry.unknownCharacter.newCharacter
        ns.UnitMenu.OpenCharacterMenu(row, entry.member.name, entry.member.guid, character, "guildWindow")
    end

    ---@param row Button WhosWhoGuildTabRowTemplate
    ---@param entry WhosWho.GuildRosterEntry
    local function initRow(row, entry)
        markSelected(row, entry)
        row.Glyph.glyph = Glyphs.Nickname[entry.source]
        Glyphs.Set(row.Glyph.Texture, row.Glyph.glyph)
        row.Glyph:SetScript("OnEnter", showGlyphTooltip)
        row.Glyph:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", clickRow)

        -- As the game's roster: online rows in white with the name in class colour, the others grey.
        local color = entry.online and HIGHLIGHT_FONT_COLOR or DISABLED_FONT_COLOR
        local member = entry.member
        row.Nickname:SetText(entry.nickname)
        row.Class:SetShown(member ~= nil and member.classID ~= nil)
        if member and member.classID then Lists.SetClassIcon(row.Class, member.classID) end
        row.Level:SetText(member and tostring(member.level) or "")
        row.Rank:SetText(member and member.rank or "")
        if entry.online and member and member.classID then
            row.Character:SetText(Lists.ClassColoredName(member.name, member.classID))
        else
            row.Character:SetText(member and member.name or "")
        end
        if entry.online then
            row.Zone:SetText(member and member.zone or "")
        else
            row.Zone:SetText(lastSeenText(entry.lastSeen, member and member.lastOnline) or "")
        end
        for _, cell in ipairs({ row.Nickname, row.Level, row.Character, row.Zone, row.Rank }) do
            cell:SetTextColor(color:GetRGB())
        end
    end

    local rowsView = CreateScrollBoxListLinearView()
    rowsView:SetElementExtent(ROW_HEIGHT)
    rowsView:SetElementInitializer("WhosWhoGuildTabRowTemplate", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(list.ScrollBox, list.ScrollBar, rowsView)

    -- Views --------------------------------------------------------------------------------------

    local function showList()
        settingsView:Hide()
        listView:Show()
        refreshList()
    end

    local function showSettings()
        selectRow(nil)
        listView:Hide()
        settingsView:Show()
        refreshSettings()
    end

    settingsButton:SetScript("OnClick", showSettings)
    closeButton:SetScript("OnClick", showList)

    local function refreshShown()
        if listView:IsVisible() then refreshList() end
        if settingsView:IsVisible() then refreshSettings() end
    end
    ns.GuildSettings.OnChanged(refreshShown)
    ns.People.OnChanged(refreshShown)
    ns.Identity.OnRevisionChanged(refreshShown)

    -- Tab ----------------------------------------------------------------------------------------

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
        showList()
        -- The roster comes from the game, which sends it again when asked.
        C_GuildInfo.GuildRoster()
    end)
    panel:SetScript("OnHide", function()
        if frame:GetDisplayMode() == hiddenInMode then
            for _, blizzardFrame in ipairs(hiddenFrames) do blizzardFrame:Show() end
        end
        hiddenFrames, hiddenInMode = {}, nil
        tab:SetChecked(false)
        selectRow(nil)
    end)

    -- A click on the tab while it is shown goes back to the list.
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        tab:SetChecked(true)
        if panel:IsShown() then showList() else panel:Show() end
    end)
    -- Clicking the tab of the current mode changes nothing in the game's panel code, so the panel is hidden here.
    for _, blizzardTab in ipairs(blizzardTabs) do
        blizzardTab:HookScript("OnClick", function() panel:Hide() end)
    end
    -- The game switching its panel to another mode on its own.
    hooksecurefunc(frame, "SetDisplayMode", function()
        if frame:GetDisplayMode() ~= hiddenInMode then panel:Hide() end
    end)

    -- The game shows its Guild Information tab for a guild, in the modes with tabs. Every member sees the list.
    local function updateTab()
        local shown = frame.GuildInfoTab:IsShown()
        tab:SetShown(shown)
        if not shown then panel:Hide() end
        local tabAbove = frame.GuildPreferredPlaySettingsTab:IsShown() and frame.GuildPreferredPlaySettingsTab
            or frame.GuildInfoTab
        tab:SetPoint("TOPLEFT", tabAbove, "BOTTOMLEFT", 0, -20)
        if panel:IsShown() then uncheckBlizzardTabs() end
    end

    hooksecurefunc(frame, "UpdateCommunitiesTabs", updateTab)
    -- Members joining, leaving, coming online, changing rank.
    tab:RegisterEvent("GUILD_ROSTER_UPDATE")
    tab:RegisterEvent("PLAYER_GUILD_UPDATE")
    tab:SetScript("OnEvent", function()
        updateTab()
        refreshShown()
    end)

    ns.Skin.Apply(function(S)
        for _, checkbox in ipairs({ enableCheckbox, enforceCheckbox, offlineCheckbox }) do
            S.Checkbox(checkbox)
            checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", SKINNED_CHECKBOX_LABEL_GAP, 0)
        end
        -- EllesmereUI's box is the checkbox's whole frame: small, as on the game's Show Offline checkbox, at the
        -- centre height of the unskinned one.
        offlineCheckbox:SetSize(SKINNED_SMALL_CHECKBOX_SIZE, SKINNED_SMALL_CHECKBOX_SIZE)
        offlineCheckbox:ClearAllPoints()
        offlineCheckbox:SetPoint("LEFT", list, "TOPLEFT", 4, 42)
        S.White(offlineCheckbox.Text)
        S.EditBox(searchBox)
        S.White(counts)
        -- The header bar's background and the list's border lines, then each column header's art.
        S.FadeRegions(list.ColumnDisplay)
        for _, header in ipairs({ list.ColumnDisplay:GetChildren() }) do
            S.FadeRegions(header)
            S.White(header:GetFontString())
        end
        S.Inset(list.InsetFrame)
        S.ScrollBar(list.ScrollBar)
        S.ScrollBar(memberPanel.ScrollBar)
        S.Button(sharingButton)
        S.Button(settingsButton)
        S.Button(closeButton)
        S.FadeRegions(memberPanel.Border)
        S.Panel(memberPanel)
        S.CloseButton(memberPanel.CloseButton)
        S.Button(memberPanel.UnlinkButton)
        S.Button(memberPanel.MoveButton)
        S.Button(memberPanel.KeepApartButton)
    end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", function() addTab(CommunitiesFrame) end)

-- Slash command ----------------------------------------------------------------------------------

-- The game's guild window, opened if needed (which loads it), on my guild and its Who's Who tab; closed when it shows
-- that tab already.
ns.Commands.guild = function()
    if not IsInGuild() then return end
    if guildTab and guildTab:GetChecked() and CommunitiesFrame:IsShown() then
        ToggleGuildFrame()
        return
    end
    if not (CommunitiesFrame and CommunitiesFrame:IsShown()) then ToggleGuildFrame() end
    -- The game refuses to open it at times (Battle.net down).
    if not CommunitiesFrame:IsShown() then return end
    local guildClubId = C_Club.GetGuildClubId()
    if CommunitiesFrame:GetSelectedClubId() ~= guildClubId then CommunitiesFrame:SelectClub(guildClubId) end
    if guildTab:IsShown() then guildTab:Click() end
end
