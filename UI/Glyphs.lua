local addonName, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

-- The small images before nicknames and character names: where a nickname comes from, a character's state, the main.
---@class WhosWho.Glyphs
local Glyphs = {}
ns.Glyphs = Glyphs

local PATH = "Interface\\AddOns\\" .. addonName .. "\\Media\\Glyphs\\"
local RENAMED_COLOR = CreateColor(0.44, 0.74, 1)

Glyphs.CROWN_TEXTURE = "Interface\\GroupFrame\\UI-Group-LeaderIcon"

---@class WhosWho.Glyph
---@field texture string
---@field color ColorMixin? tint of the white image; none for the crown
---@field label string
---@field text string? the tooltip's line

---Where a person's nickname comes from.
---@type table<"confirmed"|"renamed"|"guild"|"unconfirmed", WhosWho.Glyph>
Glyphs.Nickname = {
    confirmed = { texture = PATH .. "Person", color = NORMAL_FONT_COLOR, label = L["Confirmed"],
        text = L["The player shared this identity and confirmed it."] },
    renamed = { texture = PATH .. "Pencil", color = RENAMED_COLOR, label = L["Renamed"],
        text = L["A confirmed identity you gave your own nickname."] },
    guild = { texture = PATH .. "Banner", color = GREEN_FONT_COLOR, label = L["Guild"],
        text = L["Shared by your guild, not by the player."] },
    unconfirmed = { texture = PATH .. "Question", color = GRAY_FONT_COLOR, label = L["Unconfirmed"],
        text = L["Added by you: the player doesn't use Who's Who, or never confirmed anything to you."] },
}

---A character's state in a person.
---@type table<"confirmed"|"listed"|"added"|"guild", WhosWho.Glyph>
Glyphs.Character = {
    confirmed = { texture = PATH .. "Person", color = NORMAL_FONT_COLOR, label = L["Confirmed"],
        text = L["Declared by the player and seen."] },
    listed = { texture = PATH .. "Hourglass", color = GRAY_FONT_COLOR, label = L["Listed"],
        text = L["Declared by the player, not seen yet."] },
    added = { texture = PATH .. "Question", color = GRAY_FONT_COLOR, label = L["Added by me"],
        text = L["Not listed by the player: you added it yourself."] },
    guild = { texture = PATH .. "Banner", color = GREEN_FONT_COLOR, label = L["Guild"],
        text = L["Listed by your guild."] },
}

Glyphs.Main = { texture = Glyphs.CROWN_TEXTURE, label = L["Main"] }

---The key under the People and Guild lists, in its order.
---@type WhosWho.Glyph[]
Glyphs.Key = {
    Glyphs.Main,
    Glyphs.Nickname.renamed,
    Glyphs.Nickname.confirmed,
    Glyphs.Character.listed,
    Glyphs.Nickname.guild,
    { texture = PATH .. "Question", color = GRAY_FONT_COLOR, label = L["Unconfirmed / Added by me"] },
}

---@param texture Texture
---@param glyph WhosWho.Glyph
function Glyphs.Set(texture, glyph)
    texture:SetTexture(glyph.texture)
    if glyph.color then
        texture:SetVertexColor(glyph.color:GetRGB())
    else
        texture:SetVertexColor(1, 1, 1)
    end
end

---Shows a glyph's label and line in the game tooltip.
---@param owner Region
---@param glyph WhosWho.Glyph
function Glyphs.ShowTooltip(owner, glyph)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(glyph.label, HIGHLIGHT_FONT_COLOR:GetRGB())
    if glyph.text then
        GameTooltip:AddLine(glyph.text, GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b, true)
    end
    GameTooltip:Show()
end
