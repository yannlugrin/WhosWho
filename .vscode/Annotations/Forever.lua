---@meta
---@diagnostic disable: inject-field

---@type integer?
Enum.GameRule.PvPRuleset = nil
---@type integer?
Enum.GameRule.RPRuleset = nil

---@return integer? guildClubId a number on Forever, not a string as on retail
function C_Club.GetGuildClubId() end
