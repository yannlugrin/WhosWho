local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local Main = ns.Main
local Lists = ns.Lists
local window = Main.Window

local SIDE_PADDING = 14
-- Right of the window's portrait.
local HEADER_LEFT = 70
local ROW_HEIGHT = 24
local CLASS_ICON_SIZE = 18
local GLYPH_SIZE = 14
local CHECKBOX_SIZE = 24
local SCROLL_BAR_WIDTH = 16
-- The inset's padding and a list header's height, with the gap under it.
local INSET_PADDING = 4
local HEADER_SPACE = 18 + 2
-- Between a heading and its inset.
local HEADING_SPACE = 18

local CROWN_TEXTURE = ns.Glyphs.CROWN_TEXTURE
local EDIT_TEXTURE = ns.Glyphs.EDIT_TEXTURE
-- The crown on linked characters other than the main.
local DIM_CROWN_ALPHA = 0.4

-- The scopes in the order the sharing status lists them.
local SCOPES = {
    { key = "guild", name = L["Guild"] },
    { key = "friends", name = L["Friends"] },
    { key = "whispers", name = L["Whispers"] },
    { key = "group", name = L["Group"] },
}

-- My identity: header ----------------------------------------------------------------------------

local panel = CreateFrame("Frame", nil, window)
panel:SetAllPoints()
Main.MyIdentity = panel
Main.AddTab(L["My identity"], panel)

panel.IdentityName = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
panel.IdentityName:SetPoint("TOPLEFT", HEADER_LEFT, -32)

-- Shown when the identity goes by its main character's name.
panel.MainCrown = panel:CreateTexture(nil, "OVERLAY")
panel.MainCrown:SetTexture(CROWN_TEXTURE)
panel.MainCrown:SetSize(GLYPH_SIZE, GLYPH_SIZE)
panel.MainCrown:SetPoint("LEFT", panel.IdentityName, "RIGHT", 6, 0)

panel.EditNicknameButton = CreateFrame("Button", nil, panel)
panel.EditNicknameButton:SetSize(GLYPH_SIZE, GLYPH_SIZE)
panel.EditNicknameButton:SetNormalTexture(EDIT_TEXTURE)
panel.EditNicknameButton:SetScript("OnClick", function()
    local popup = StaticPopup_Show("WHOSWHO_EDIT_NICKNAME")
    if popup then popup.data2 = function() panel:Refresh() end end
end)
panel.EditNicknameButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Edit nickname"], HIGHLIGHT_FONT_COLOR:GetRGB())
    GameTooltip:Show()
end)
panel.EditNicknameButton:SetScript("OnLeave", GameTooltip_Hide)

panel.SharingStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
panel.SharingStatus:SetPoint("TOPRIGHT", -SIDE_PADDING, -38)

panel.CharactersHeading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.CharactersHeading:SetPoint("TOPLEFT", SIDE_PADDING, -70)
panel.CharactersHeading:SetText(L["My characters"])

panel.LinkedCount = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.LinkedCount:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -SIDE_PADDING, -82)

-- My identity: characters list -------------------------------------------------------------------

local INSET_BOTTOM = Lists.FOOTER_SPACE + 4

local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
inset:SetPoint("TOPLEFT", 8, -88)
inset:SetPoint("BOTTOMRIGHT", -6, INSET_BOTTOM)

local COLUMNS = {
    { key = "Linked", width = 50, label = L["Linked"], justify = "CENTER" },
    { key = "Main", width = 40, label = L["Main"], justify = "CENTER" },
    { key = "LastPlayed", width = 100, label = L["Last played"], sortable = true },
    { key = "Level", width = 40, label = L["Level"], sortable = true },
    { key = "Ruleset", width = 80, label = L["Ruleset"] },
}
local columnsWidth = Lists.LayOut(COLUMNS)
local NAME_LEFT = 6 + CLASS_ICON_SIZE + 8

panel.ListHeader = Lists.CreateHeader(inset, { key = "Name", label = L["Name"], left = NAME_LEFT, sortable = true },
    COLUMNS, columnsWidth)
local header = panel.ListHeader
header:SetPoint("TOPLEFT", 4, -4)
header:SetPoint("TOPRIGHT", -4 - SCROLL_BAR_WIDTH, -4)

local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
scrollBox:SetPoint("BOTTOMRIGHT", -4 - SCROLL_BAR_WIDTH, 4)

local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

local columnByKey = {}
for _, column in ipairs(COLUMNS) do columnByKey[column.key] = column end

---@type table? EllesmereUI's skinning functions, for rows created after they were handed over
local skin

---A character row of the list; createRow adds its regions the first time the row is used.
---@class WhosWho.MyIdentityRow: Frame
---@field Online Texture the gold bar behind the character logged in
---@field ClassIcon Texture
---@field Name FontString
---@field Ruleset FontString
---@field Level FontString
---@field LastPlayed FontString
---@field MainButton Button
---@field LinkedCheckbox CheckButton

-- The tooltip of a row's crown or Linked checkbox: what a click does, set when the row is filled.
local function showControlTooltip(control)
    GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
    GameTooltip:SetText(control.tooltipTitle, HIGHLIGHT_FONT_COLOR:GetRGB())
    GameTooltip:AddLine(control.tooltipText, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, true)
    GameTooltip:Show()
end

---@param row WhosWho.MyIdentityRow
local function createRow(row)
    row.Online = Lists.CreateRowHighlight(row)

    local iconFrame = CreateFrame("Frame", nil, row)
    iconFrame:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
    iconFrame:SetPoint("LEFT", 6, 0)
    row.ClassIcon = iconFrame:CreateTexture(nil, "ARTWORK")
    row.ClassIcon:SetAllPoints()

    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Name:SetPoint("LEFT", NAME_LEFT, 0)
    row.Name:SetPoint("RIGHT", row, "RIGHT", -columnsWidth - 6, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Ruleset = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    Lists.Place(row.Ruleset, row, columnByKey.Ruleset)

    row.Level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Lists.Place(row.Level, row, columnByKey.Level)

    row.LastPlayed = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    Lists.Place(row.LastPlayed, row, columnByKey.LastPlayed)

    row.MainButton = CreateFrame("Button", nil, row)
    row.MainButton:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    row.MainButton:SetNormalTexture(CROWN_TEXTURE)
    Lists.Place(row.MainButton, row, columnByKey.Main)
    -- The main's crown and checkbox are disabled but still explain why.
    row.MainButton:SetMotionScriptsWhileDisabled(true)
    row.MainButton:SetScript("OnEnter", showControlTooltip)
    row.MainButton:SetScript("OnLeave", GameTooltip_Hide)

    row.LinkedCheckbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.LinkedCheckbox:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
    Lists.Place(row.LinkedCheckbox, row, columnByKey.Linked)
    row.LinkedCheckbox:SetMotionScriptsWhileDisabled(true)
    row.LinkedCheckbox:SetScript("OnEnter", showControlTooltip)
    row.LinkedCheckbox:SetScript("OnLeave", GameTooltip_Hide)

    if skin then
        skin.SquareIcon(row.ClassIcon, iconFrame)
        skin.Checkbox(row.LinkedCheckbox)
    end
end

---@param row WhosWho.MyIdentityRow
---@param character WhosWho.MyIdentityCharacter
local function initRow(row, character)
    if not row.Name then createRow(row) end

    local coloredName = Lists.ClassColoredName(character.name, character.classID)
    Lists.SetClassIcon(row.ClassIcon, character.classID)
    row.Name:SetText(coloredName)
    row.Online:SetShown(character.online)
    -- The grey texts are hard to read on the gold bar: they turn white there.
    row.Ruleset:SetFontObject(character.online and "GameFontHighlight" or "GameFontDisable")
    row.LastPlayed:SetFontObject(character.online and "GameFontHighlight" or "GameFontDisable")
    row.Ruleset:SetText(Lists.RulesetName(character.ruleset))
    row.Level:SetText(tostring(character.level))
    row.LastPlayed:SetText(character.online and GREEN_FONT_COLOR:WrapTextInColorCode(L["Online"])
        or FriendsFrame_GetLastOnline(character.lastSeen))

    row.MainButton:SetShown(character.linked)
    row.MainButton:GetNormalTexture():SetDesaturated(not character.main)
    row.MainButton:SetAlpha(character.main and 1 or DIM_CROWN_ALPHA)
    row.MainButton:SetEnabled(not character.main)
    if character.main then
        row.MainButton.tooltipTitle = L["Main character"]
        row.MainButton.tooltipText = L["To change it, click the crown of another linked character."]
    else
        row.MainButton.tooltipTitle = L["Alt character"]
        row.MainButton.tooltipText = L["Make this character your main."]
    end
    row.MainButton:SetScript("OnClick", function()
        local popup = StaticPopup_Show("WHOSWHO_CHANGE_MAIN", coloredName, nil, character.guid)
        if popup then popup.data2 = function() panel:Refresh() end end
    end)

    row.LinkedCheckbox:SetChecked(character.linked)
    row.LinkedCheckbox:SetEnabled(not character.main)
    if character.main then
        row.LinkedCheckbox.tooltipTitle = L["Linked character"]
        row.LinkedCheckbox.tooltipText = L["Your main character can't be unlinked. Make another character your main first."]
    elseif character.linked then
        row.LinkedCheckbox.tooltipTitle = L["Linked character"]
        row.LinkedCheckbox.tooltipText = L["Click to unlink this character from your identity."]
    else
        row.LinkedCheckbox.tooltipTitle = L["Not linked character"]
        row.LinkedCheckbox.tooltipText = L["Click to link this character to your identity."]
    end
    -- The checkbox keeps the character's state until the player confirms the change.
    row.LinkedCheckbox:SetScript("OnClick", function(self)
        self:SetChecked(character.linked)
        if character.linked then
            local popup = StaticPopup_Show("WHOSWHO_UNLINK", coloredName, nil, character.guid)
            if popup then popup.data2 = function() panel:Refresh() end end
            return
        end
        local dialog = ns.IdentityDialogs.LinkCharacter
        dialog:SetCharacter(character.guid, character.name, character.classID, ns.Identity.Nickname(),
            ns.Identity.LinkedCharacters())
        dialog:Show()
    end)
end

local view = CreateScrollBoxListLinearView()
view:SetElementExtent(ROW_HEIGHT)
view:SetElementInitializer("Frame", initRow)
ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

-- My identity: guilds list ----------------------------------------------------------------------

-- Under My characters, whose list gets shorter by its height, while one of my characters is in a guild.
local guildsInset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
guildsInset:SetPoint("BOTTOMLEFT", 8, INSET_BOTTOM)
guildsInset:SetPoint("BOTTOMRIGHT", -6, INSET_BOTTOM)
guildsInset:Hide()
panel.GuildsInset = guildsInset

panel.GuildsHeading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.GuildsHeading:SetPoint("BOTTOMLEFT", guildsInset, "TOPLEFT", SIDE_PADDING - 8, 6)
panel.GuildsHeading:SetText(L["In my guilds"])
panel.GuildsHeading:Hide()

local GUILD_COLUMNS = {
    { key = "Edit", width = 30, label = "", justify = "CENTER" },
    { key = "Invite", width = 110, label = "" },
    { key = "Main", width = 195, label = L["Main"] },
    { key = "Nickname", width = 185, label = L["Nickname"] },
}
local guildColumnsWidth = Lists.LayOut(GUILD_COLUMNS)
local GUILD_NAME_LEFT = 6

panel.GuildsHeader = Lists.CreateHeader(guildsInset, { key = "Guild", label = L["Guild"], left = GUILD_NAME_LEFT },
    GUILD_COLUMNS, guildColumnsWidth)
panel.GuildsHeader:SetPoint("TOPLEFT", INSET_PADDING, -INSET_PADDING)
panel.GuildsHeader:SetPoint("TOPRIGHT", -INSET_PADDING, -INSET_PADDING)

local guildColumnByKey = {}
for _, column in ipairs(GUILD_COLUMNS) do guildColumnByKey[column.key] = column end

---A line of the guilds list.
---@class WhosWho.MyIdentityGuildRow: Frame
---@field GuildName FontString
---@field Nickname FontString
---@field MainCrown Texture
---@field MainName FontString
---@field InviteButton Button
---@field EditButton Button

---@type WhosWho.MyIdentityGuildRow[]
local guildRows = {}

---@param index integer
---@return WhosWho.MyIdentityGuildRow
local function guildRow(index)
    if guildRows[index] then return guildRows[index] end

    local row = CreateFrame("Frame", nil, guildsInset)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", panel.GuildsHeader, "BOTTOMLEFT", 0, -2 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", panel.GuildsHeader, "BOTTOMRIGHT", 0, -2 - (index - 1) * ROW_HEIGHT)

    row.GuildName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.GuildName:SetPoint("LEFT", GUILD_NAME_LEFT, 0)
    row.GuildName:SetPoint("RIGHT", row, "RIGHT", -guildColumnsWidth - 6, 0)
    row.GuildName:SetJustifyH("LEFT")
    row.GuildName:SetWordWrap(false)

    row.Nickname = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Lists.Place(row.Nickname, row, guildColumnByKey.Nickname)
    row.Nickname:SetWordWrap(false)

    local main = guildColumnByKey.Main
    row.MainCrown = row:CreateTexture(nil, "OVERLAY")
    row.MainCrown:SetTexture(CROWN_TEXTURE)
    row.MainCrown:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    row.MainCrown:SetPoint("LEFT", row, "RIGHT", main.right - main.width, 0)
    row.MainName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.MainName:SetPoint("LEFT", row.MainCrown, "RIGHT", 4, 0)
    row.MainName:SetPoint("RIGHT", row, "RIGHT", main.right, 0)
    row.MainName:SetJustifyH("LEFT")
    row.MainName:SetWordWrap(false)

    -- In a guild the character I play isn't in, which accepts invite requests.
    local invite = guildColumnByKey.Invite
    row.InviteButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.InviteButton:SetText(L["Invitation…"])
    row.InviteButton:SetSize(invite.width - 8, 20)
    row.InviteButton:SetPoint("RIGHT", row, "RIGHT", invite.right - 4, 0)
    if skin then skin.Button(row.InviteButton) end

    row.EditButton = CreateFrame("Button", nil, row)
    row.EditButton:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    row.EditButton:SetNormalTexture(EDIT_TEXTURE)
    Lists.Place(row.EditButton, row, guildColumnByKey.Edit)
    row.EditButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipTitle, HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:Show()
    end)
    row.EditButton:SetScript("OnLeave", GameTooltip_Hide)

    guildRows[index] = row
    return row
end

-- My identity: footer ----------------------------------------------------------------------------

local footer = Lists.CreateFooter(panel)
panel.Footer = footer

panel.SharingSettingsButton = CreateFrame("Button", nil, footer.Content, "UIPanelButtonTemplate")
panel.SharingSettingsButton:SetText(L["Sharing settings"])
panel.SharingSettingsButton:SetSize(panel.SharingSettingsButton:GetTextWidth() + 40, 22)
panel.SharingSettingsButton:SetPoint("RIGHT", -5, 0)
panel.SharingSettingsButton:SetScript("OnClick", function() ns.Commands.settings("") end)

panel.NicknameNote = footer.Content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.NicknameNote:SetPoint("LEFT", 10, 0)
panel.NicknameNote:SetPoint("RIGHT", panel.SharingSettingsButton, "LEFT", -16, 0)
panel.NicknameNote:SetJustifyH("LEFT")
panel.NicknameNote:SetText(L["Other players see your nickname instead of your main character's name; each of them can still give you their own nickname, which only they see."])

-- My identity: no identity -----------------------------------------------------------------------

local EMPTY_TEXT_WIDTH = 400

panel.Empty = CreateFrame("Frame", nil, inset)
panel.Empty:SetAllPoints()

panel.Empty.Text = panel.Empty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
panel.Empty.Text:SetPoint("CENTER")
panel.Empty.Text:SetWidth(EMPTY_TEXT_WIDTH)
panel.Empty.Text:SetText(L["An identity groups the characters you link to it, so people who use Who's Who recognise you on each of them. Link the character you are playing to start yours."])

panel.Empty.Heading = panel.Empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.Empty.Heading:SetPoint("BOTTOM", panel.Empty.Text, "TOP", 0, 12)
panel.Empty.Heading:SetText(L["No identity yet"])

panel.Empty.LinkButton = CreateFrame("Button", nil, panel.Empty, "UIPanelButtonTemplate")
panel.Empty.LinkButton:SetText(L["Link this character"])
panel.Empty.LinkButton:SetSize(panel.Empty.LinkButton:GetTextWidth() + 40, 22)
panel.Empty.LinkButton:SetPoint("TOP", panel.Empty.Text, "BOTTOM", 0, -16)
panel.Empty.LinkButton:SetScript("OnClick", function() ns.IdentityDialogs.AskToLink() end)

-- Shown while the identity has a linked character, in place of the empty state.
local identityRegions = {
    panel.IdentityName, panel.MainCrown, panel.EditNicknameButton, panel.SharingStatus, panel.CharactersHeading, panel.LinkedCount,
    header, scrollBox, scrollBar, panel.NicknameNote,
}

-- My identity: filling ---------------------------------------------------------------------------

---@param name string the nickname, or the main character's name
---@param isMainName boolean the identity has no nickname: it goes by its main character's name
function panel:SetIdentityName(name, isMainName)
    self.IdentityName:SetText(name)
    self.MainCrown:SetShown(isMainName)
    self.EditNicknameButton:SetPoint("LEFT", isMainName and self.MainCrown or self.IdentityName, "RIGHT", 6, 0)
end

---@param scopeNames string[] the scopes the identity is shared on; empty when it is not shared
function panel:SetSharing(scopeNames)
    self.SharingStatus:SetText(scopeNames[1] and L["Shared with: %s"]:format(table.concat(scopeNames, ", "))
        or L["Not shared"])
end

---@class WhosWho.MyIdentityCharacter
---@field guid string
---@field name string
---@field classID integer
---@field ruleset WhosWho.Ruleset
---@field level integer
---@field lastSeen number seconds, from time()
---@field online boolean the character logged in
---@field main boolean
---@field linked boolean

---@param characters WhosWho.MyIdentityCharacter[] in the order shown
function panel:SetCharacters(characters)
    local linked = 0
    for _, character in ipairs(characters) do
        if character.linked then linked = linked + 1 end
    end
    self.LinkedCount:SetText(L["%d of %d linked"]:format(linked, #characters))
    scrollBox:SetDataProvider(CreateDataProvider(characters))
end

---@class WhosWho.MyIdentityGuild
---@field clubId integer
---@field ruleset WhosWho.Ruleset
---@field name string? nil while none of my characters in it was played since its name is saved
---@field nickname string the name that guild shows me under: my nickname there, otherwise the one its members see
---@field nicknameSet boolean I set a nickname in that guild
---@field mainGuid string the character that guild shows me under
---@field mainName string
---@field mainClassID integer
---@field characters { guid: string, name: string, classID: integer }[] my characters in that guild that its members see
---@field officers WhosWho.KnownOfficer[]? its officers I know of, when the character I play may ask it for an invite

---Shows a line per guild under My characters, or hides the section when the list is empty.
---@param guilds WhosWho.MyIdentityGuild[] in the order shown
function panel:SetGuilds(guilds)
    local shown = guilds[1] ~= nil
    self.GuildsHeading:SetShown(shown)
    guildsInset:SetShown(shown)
    local guildsHeight = 2 * INSET_PADDING + HEADER_SPACE + #guilds * ROW_HEIGHT
    guildsInset:SetHeight(guildsHeight)
    inset:SetPoint("BOTTOMRIGHT", -6, shown and INSET_BOTTOM + guildsHeight + HEADING_SPACE + 8 or INSET_BOTTOM)

    for i, guild in ipairs(guilds) do
        local row = guildRow(i)
        local guildName = guild.name and ("<%s>"):format(guild.name) or L["Unknown guild"]
        row.GuildName:SetText(guild.name and GREEN_FONT_COLOR:WrapTextInColorCode(guildName) or guildName)
        row.GuildName:SetFontObject(guild.name and "GameFontHighlight" or "GameFontDisable")
        row.Nickname:SetText(guild.nickname)
        row.Nickname:SetFontObject(guild.nicknameSet and "GameFontHighlight" or "GameFontDisable")
        row.MainName:SetText(Lists.ClassColoredName(guild.mainName, guild.mainClassID))
        row.EditButton.tooltipTitle = L["Edit for %s"]:format(guildName)
        row.EditButton:SetScript("OnClick", function() panel:EditGuild(guild.clubId) end)
        row.InviteButton:SetShown(guild.officers ~= nil)
        row.InviteButton:SetScript("OnClick", function()
            local dialog = ns.IdentityDialogs.GuildInvite
            dialog:SetGuild(guild.name, ns.UnitWholeName("player"), guild.officers)
            dialog:Show()
        end)
        row:Show()
    end
    for i = #guilds + 1, #guildRows do guildRows[i]:Hide() end
end

-- The list's sort: "Name" (A to Z when ascending), "Level" (lowest first when ascending) or "LastPlayed" (oldest first
-- when ascending; the character logged in counts as the most recent). The main always comes first.
local sortKey, sortAscending = "Name", true

local function playedAt(character)
    return character.online and math.huge or character.lastSeen or 0
end

local function sortCharacters(characters)
    table.sort(characters, function(a, b)
        if a.main ~= b.main then return a.main end
        local aValue, bValue
        if sortKey == "Level" then
            aValue, bValue = a.level or 0, b.level or 0
        elseif sortKey == "LastPlayed" then
            aValue, bValue = playedAt(a), playedAt(b)
        end
        if aValue ~= bValue then
            if sortAscending then return aValue < bValue end
            return aValue > bValue
        end
        local aName, bName = a.name:lower(), b.name:lower()
        if sortKey == "Name" and not sortAscending then return aName > bName end
        return aName < bName
    end)
end

---An officer of a guild I know of: a player's identity with characters of the guild master's or an officer's rank in
---it, as the roster of one of my characters last showed them.
---@class WhosWho.KnownOfficer
---@field nickname string
---@field names string[] those characters

-- The officers of that guild I know of, by nickname.
---@return WhosWho.KnownOfficer[]
local function knownOfficers(clubId)
    local officers = {}
    for id, person in pairs(ns.People.All()) do
        local names = {}
        for _, character in pairs(person.signedRecord and person.chars or {}) do
            if character.guild == clubId and character.rankIndex
                and character.rankIndex <= ns.GuildList.TRUSTED_RANK_INDEX then
                names[#names + 1] = character.name
            end
        end
        if names[1] then
            table.sort(names)
            officers[#officers + 1] = { nickname = ns.People.Nickname(id), names = names }
        end
    end
    table.sort(officers, function(a, b) return a.nickname < b.nickname end)
    return officers
end

-- The guilds my characters are in, unknown names last, each with what its members see of me: my record as they get it,
-- with its general part unless the guild enforces linking with my Guild scope off.
---@return WhosWho.MyIdentityGuild[]
local function ownGuilds()
    local Identity = ns.Identity
    local characters = Identity.Characters()
    local guilds, byClub = {}, {}
    for _, character in pairs(characters) do
        local clubId = character.guild and character.guild.id
        if clubId then
            if not byClub[clubId] then
                byClub[clubId] = { clubId = clubId, ruleset = character.ruleset }
                guilds[#guilds + 1] = byClub[clubId]
            end
            byClub[clubId].name = byClub[clubId].name or character.guild.name
        end
    end

    for _, guild in ipairs(guilds) do
        local general = ns.Scopes.Get("guild") or not ns.GuildSettings.EnforcesLinking(guild.clubId)
        local record = Identity.UnsignedRecord(general, guild.clubId, guild.ruleset)
        guild.mainGuid = ns.Record.ShownMain(record, guild.clubId)
        local main = characters[guild.mainGuid]
        guild.mainName, guild.mainClassID = main.name, main.classID
        guild.nicknameSet = Identity.GuildNickname(guild.clubId) ~= nil
        guild.nickname = ns.Record.ShownNickname(record, guild.clubId) or main.name
        local playing = UnitGUID("player")
        if Identity.GuildId(playing) ~= guild.clubId and Identity.Ruleset(playing) == guild.ruleset
            and ns.GuildSettings.AcceptsInviteRequests(guild.clubId) then
            guild.officers = knownOfficers(guild.clubId)
        end
        guild.characters = {}
        for _, guid in ipairs(Identity.CharactersInGuild(guild.clubId, guild.ruleset)) do
            if record.chars[guid] then
                guild.characters[#guild.characters + 1] = {
                    guid = guid, name = characters[guid].name, classID = characters[guid].classID,
                }
            end
        end
    end

    table.sort(guilds, function(a, b)
        if (a.name == nil) ~= (b.name == nil) then return a.name ~= nil end
        if a.name ~= b.name then return a.name:lower() < b.name:lower() end
        return a.clubId < b.clubId
    end)
    return guilds
end

---Opens the dialog setting my nickname and main in one of my characters' guilds.
---@param clubId integer
---@param nickname string? the nickname filled in; nil: mine there
function panel:EditGuild(clubId, nickname)
    for _, guild in ipairs(ownGuilds()) do
        if guild.clubId == clubId then
            local dialog = ns.IdentityDialogs.GuildEntry
            dialog:SetGuild(guild.clubId, guild.name, nickname or ns.Identity.GuildNickname(clubId), ns.Identity.Nickname(),
                guild.characters, guild.mainGuid)
            dialog:Show()
            return
        end
    end
end

---Fills the panel from the identity, or shows the empty state while no character is linked.
function panel:Refresh()
    local Identity = ns.Identity
    local empty = Identity.LinkedCount() == 0
    self.Empty:SetShown(empty)
    for _, region in ipairs(identityRegions) do region:SetShown(not empty) end
    self:SetGuilds(empty and {} or ownGuilds())
    if empty then return end

    self:SetIdentityName(Identity.Nickname(), not Identity.HasNickname())

    local scopeNames = {}
    for _, scope in ipairs(SCOPES) do
        if ns.Scopes.Get(scope.key) then scopeNames[#scopeNames + 1] = scope.name end
    end
    self:SetSharing(scopeNames)

    local mainGuid = Identity.Main()
    local onlineGuid = UnitGUID("player")
    local characters = {}
    for guid, character in pairs(Identity.Characters()) do
        characters[#characters + 1] = {
            guid = guid, name = character.name, classID = character.classID, ruleset = character.ruleset,
            level = character.level, lastSeen = character.lastSeen,
            online = guid == onlineGuid, main = guid == mainGuid, linked = character.linked == true,
        }
    end
    sortCharacters(characters)
    self.ListHeader:SetSort(sortKey, sortAscending)
    self:SetCharacters(characters)
end

window:HookScript("OnShow", function() panel:Refresh() end)

local function refreshIfShown()
    if window:IsShown() then panel:Refresh() end
end
-- The link dialogs opened from the panel change the identity when the player answers.
ns.IdentityDialogs.NewIdentity:HookScript("OnHide", refreshIfShown)
ns.IdentityDialogs.LinkCharacter:HookScript("OnHide", refreshIfShown)
-- Changes made while the window is open, from the panel or elsewhere (Settings, slash commands).
ns.Identity.OnRevisionChanged(refreshIfShown)

-- A click on the active column reverses it; another column starts A to Z for names, highest first for levels and most
-- recent first for last played.
local function sortBy(key)
    if key == sortKey then
        sortAscending = not sortAscending
    else
        sortKey, sortAscending = key, key == "Name"
    end
    panel:Refresh()
end
panel.ListHeader.Labels.Name:SetScript("OnClick", function() sortBy("Name") end)
panel.ListHeader.Labels.Level:SetScript("OnClick", function() sortBy("Level") end)
panel.ListHeader.Labels.LastPlayed:SetScript("OnClick", function() sortBy("LastPlayed") end)

-- Skin -------------------------------------------------------------------------------------------

ns.Skin.Apply(function(S)
    skin = S
    S.Inset(inset)
    S.Inset(guildsInset)
    S.ScrollBar(scrollBar)
    S.Button(panel.SharingSettingsButton)
    S.Button(panel.Empty.LinkButton)
end)

-- Slash command ----------------------------------------------------------------------------------

-- Shows the window, or hides it when it is shown.
ns.Commands.open = function()
    window:SetShown(not window:IsShown())
end
