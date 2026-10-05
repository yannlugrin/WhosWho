std = "lua51"
max_line_length = false
codes = true
exclude_files = { "Libs/", ".release/", ".vscode/" }

ignore = {
    "212/self", -- unused self argument
}

globals = {
    "SLASH_WHOSWHO1", "SLASH_WHOSWHO2", "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
}

read_globals = {
    "bit", "date", "geterrorhandler", "time", "debugprofilestop", "fastrandom", "issecretvalue", "strlenutf8",
    "LibStub", "CreateFrame", "UIParent", "hooksecurefunc", "Enum", "Menu",
    "C_AddOns", "C_BattleNet", "C_ChatInfo", "C_Club", "C_CreatureInfo", "C_FriendList", "C_GameRules", "C_GuildInfo", "C_Timer",
    "ChatFrame_AddMessageEventFilter", "ChatFrameUtil", "ChatFontNormal", "NUM_CHAT_WINDOWS",
    "TooltipDataProcessor", "Settings", "SettingsPanel", "CreateSettingsListSectionHeaderInitializer",
    "CreateSettingsButtonInitializer", "StaticPopup_Show", "CANCEL", "EllesmereUI", "GetClassInfo", "C_ClassColor", "InputBoxInstructions_OnTextChanged", "NORMAL_FONT_COLOR", "GREEN_FONT_COLOR",
    "PanelTemplates_TabResize", "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab", "CreateScrollBoxListLinearView",
    "ScrollUtil", "CreateDataProvider", "FriendsFrame_GetLastOnline",
    "Ambiguate", "BNGetNumFriends", "BNSendGameData", "BNET_CLIENT_WOW",
    "CanEditGuildInfo", "GetBuildInfo", "GetCursorPosition", "GetGuildInfo", "GetGuildInfoText",
    "GetGuildRosterInfo", "GetLocale", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetNormalizedRealmName", "GetNumGuildMembers", "GetServerTime", "GetTime",
    "GuildControlGetNumRanks", "GuildControlGetRankName", "GuildRoster", "IsInGroup", "IsInGuild", "IsInInstance", "IsInRaid",
    "UnitClass", "UnitExists", "UnitLevel", "UnitFullName", "UnitGUID", "UnitIsPlayer", "UnitName", "UnitNameUnmodified",
    "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "WOW_PROJECT_MAINLINE",
}

files["Tests/"] = {
    globals = { "bit" },
}
