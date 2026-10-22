std = "lua51"
max_line_length = false
codes = true
exclude_files = { "Libs/", ".release/", ".vscode/" }

ignore = {
    "212/self", -- unused self argument
}

globals = {
    "SLASH_WHOSWHO1", "SLASH_WHOSWHO2", "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
    "BINDING_HEADER_WHOSWHO", "BINDING_NAME_WHOSWHO_WINDOW", "BINDING_NAME_WHOSWHO_GUILD",
}

read_globals = {
    "bit", "date", "geterrorhandler", "time", "debugprofilestop", "fastrandom", "issecretvalue", "strlenutf8",
    "LibStub", "CreateFrame", "UIParent", "hooksecurefunc", "Enum", "Menu", "EventUtil", "CommunitiesFrame", "PlaySound",
    "ToggleGuildFrame",
    "SOUNDKIT", "GameFontHighlight", "CLOSE", "COMMUNITIES_MEMBER_LIST_SHOW_OFFLINE",
    "LEVEL_ABBR", "ZONE_COLON", "LAST_ONLINE_COLON", "GUILD_ONLINE_LABEL",
    "DISABLED_FONT_COLOR", "COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS", "COMMUNITIES_ROSTER_COLUMN_TITLE_RANK",
    "C_AddOns", "C_BattleNet", "C_ChatInfo", "C_Club", "C_CreatureInfo", "C_FriendList", "C_GameRules", "C_GuildInfo", "C_Timer",
    "ChatFrame_AddMessageEventFilter", "ChatFrameUtil", "LIGHTGRAY_FONT_COLOR", "ChatFontNormal", "NUM_CHAT_WINDOWS",
    "TooltipDataProcessor", "Settings", "SettingsPanel", "CreateSettingsListSectionHeaderInitializer",
    "CreateSettingsButtonInitializer", "StaticPopup_Show", "CANCEL", "EllesmereUI", "GetClassInfo", "C_ClassColor", "InputBoxInstructions_OnTextChanged", "NORMAL_FONT_COLOR", "GREEN_FONT_COLOR", "ORANGE_FONT_COLOR", "YELLOW_FONT_COLOR",
    "PanelTemplates_TabResize", "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab", "CreateScrollBoxListLinearView",
    "ScrollUtil", "CreateDataProvider", "FriendsFrame_GetLastOnline", "MenuUtil", "GameTooltip", "GameTooltip_Hide", "HIGHLIGHT_FONT_COLOR", "GRAY_FONT_COLOR", "RED_FONT_COLOR", "GameTooltipTextLeft1", "MinimalSliderWithSteppersMixin", "UnitIsFriend", "GetPlayerInfoByGUID", "C_PlayerInfo", "PlayerLocation", "ChatFrame_SendTell", "CreateSettingsCheckboxWithButtonInitializer", "WHISPER", "INVITE", "C_PartyInfo", "CreateColor", "Mixin", "ScrollBoxConstants",
    "Ambiguate", "BNConnected", "BNGetNumFriends", "C_EventUtils", "BNSendGameData", "BNET_CLIENT_WOW",
    "CanEditGuildInfo", "CanGuildInvite", "DECLINE", "ERR_CHAT_PLAYER_NOT_FOUND_S", "GetBuildInfo", "GetCursorPosition", "GetGuildInfo", "GetGuildInfoText",
    "GetGuildRosterInfo", "GetGuildRosterLastOnline", "GetLocale", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetNormalizedRealmName", "GetNumClasses", "GetNumGuildMembers", "GetServerTime", "GetTime",
    "GuildControlGetNumRanks", "GuildControlGetRankName", "GuildRoster", "IsInGroup", "IsInGuild", "IsInInstance", "IsInRaid", "IsResting",
    "UnitAffectingCombat", "UnitClass", "UnitRace", "GetMaxLevelForPlayerExpansion", "UnitExists", "UnitLevel", "UnitFullName", "UnitGUID", "UnitIsConnected", "UnitIsPlayer", "UnitName", "UnitNameUnmodified",
    "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "WOW_PROJECT_MAINLINE",
}

files["Tests/"] = {
    globals = { "bit" },
}
