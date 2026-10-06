local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local RULESET = ns.Record.RULESET

-- Character and person lists of the main window's tabs: columns, sortable headers, names.
---@class WhosWho.Lists
local Lists = {}
ns.Lists = Lists

local HEADER_HEIGHT = 18
local HIGHLIGHT_TEXTURE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local SORT_ARROW_TEXTURE = "Interface\\Buttons\\UI-SortArrow"
local SORT_ARROW_WIDTH, SORT_ARROW_HEIGHT = 9, 8

local RULESET_NAMES = {
    [RULESET.Normal] = L["Normal"],
    [RULESET.PvP] = L["PvP"],
    [RULESET.RP] = L["RP"],
    [RULESET.Hardcore] = L["Hardcore"],
}

---@param ruleset WhosWho.Ruleset
---@return string
function Lists.RulesetName(ruleset)
    return RULESET_NAMES[ruleset]
end

---@param name string
---@param classID integer
---@return string
function Lists.ClassColoredName(name, classID)
    local _, classFile = GetClassInfo(classID)
    return C_ClassColor.GetClassColor(classFile):WrapTextInColorCode(name)
end

---@param texture Texture
---@param classID integer
function Lists.SetClassIcon(texture, classID)
    local _, classFile = GetClassInfo(classID)
    texture:SetAtlas("classicon-" .. classFile:lower())
end

---The gold bar behind a selected or current row, hidden until shown.
---@param row Frame
---@return Texture
function Lists.CreateRowHighlight(row)
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetTexture(HIGHLIGHT_TEXTURE)
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()
    highlight:Hide()
    return highlight
end

-- Columns ----------------------------------------------------------------------------------------

---A column right of a list's name, which takes the space left of them.
---@class WhosWho.Column
---@field key string
---@field width number
---@field label string
---@field justify "LEFT"|"CENTER"|"RIGHT"|nil where its content sits (default LEFT); CENTER places glyphs and checkboxes at its centre
---@field sortable boolean?
---@field right number? offset of its right edge from the row's right edge, set by Lists.LayOut

---Sets each column's right offset, the first column against the row's right edge.
---@param columns WhosWho.Column[] from right to left
---@return number width of all the columns
function Lists.LayOut(columns)
    local width = 0
    for _, column in ipairs(columns) do
        column.right = -width
        width = width + column.width
    end
    return width
end

---Places a region in a column of a row.
---@param region Region
---@param row Frame
---@param column WhosWho.Column
function Lists.Place(region, row, column)
    if column.justify == "CENTER" and not region.SetJustifyH then
        region:SetPoint("CENTER", row, "RIGHT", column.right - column.width / 2, 0)
        return
    end
    region:SetPoint("LEFT", row, "RIGHT", column.right - column.width, 0)
    region:SetPoint("RIGHT", row, "RIGHT", column.right, 0)
    if region.SetJustifyH then region:SetJustifyH(column.justify or "LEFT") end
end

-- Headers ----------------------------------------------------------------------------------------

-- A column label: plain text, or a button for a sortable column, white on hover, with the sort arrow when it is the
-- active sort.
local function createLabel(header, text, sortable)
    if not sortable then
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(text)
        return label
    end
    local button = CreateFrame("Button", nil, header)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button:SetText(text)
    button:SetHeight(HEADER_HEIGHT)
    button.Arrow = button:CreateTexture(nil, "OVERLAY")
    button.Arrow:SetTexture(SORT_ARROW_TEXTURE)
    button.Arrow:SetSize(SORT_ARROW_WIDTH, SORT_ARROW_HEIGHT)
    button.Arrow:SetPoint("LEFT", button:GetFontString(), "RIGHT", 3, 0)
    button.Arrow:Hide()
    return button
end

---A list's header row.
---@class WhosWho.ListHeader: Frame
---@field Labels table<string, FontString|Button> by column key; a sortable column's label is a button
local Header = {}

---Shows the sort arrow on a column, or none.
---@param key string?
---@param ascending boolean?
function Header:SetSort(key, ascending)
    for labelKey, label in pairs(self.Labels) do
        if label.Arrow then
            label.Arrow:SetShown(labelKey == key)
            if ascending then
                label.Arrow:SetTexCoord(0, 0.5625, 1, 0)
            else
                label.Arrow:SetTexCoord(0, 0.5625, 0, 1)
            end
        end
    end
end

---@param parent Frame
---@param nameColumn { key: string, label: string, left: number, sortable: boolean? } the name, left of the columns
---@param columns WhosWho.Column[] laid out by Lists.LayOut
---@param columnsWidth number
---@return WhosWho.ListHeader
function Lists.CreateHeader(parent, nameColumn, columns, columnsWidth)
    local header = CreateFrame("Frame", nil, parent)
    Mixin(header, Header)
    header:SetHeight(HEADER_HEIGHT)
    header.Labels = {}

    local nameLabel = createLabel(header, nameColumn.label, nameColumn.sortable)
    nameLabel:SetPoint("LEFT", nameColumn.left, 0)
    if not nameColumn.sortable then
        nameLabel:SetPoint("RIGHT", header, "RIGHT", -columnsWidth, 0)
        nameLabel:SetJustifyH("LEFT")
    else
        nameLabel:SetWidth(nameLabel:GetTextWidth())
    end
    header.Labels[nameColumn.key] = nameLabel

    for _, column in ipairs(columns) do
        local label = createLabel(header, column.label, column.sortable)
        if column.sortable then
            -- The button fits its text, at the column's side; the arrow follows the text.
            local justify = column.justify or "LEFT"
            local x = justify == "LEFT" and column.right - column.width
                or justify == "RIGHT" and column.right - SORT_ARROW_WIDTH - 3
                or column.right - column.width / 2
            label:SetWidth(label:GetTextWidth())
            label:SetPoint(justify, header, "RIGHT", x, 0)
        else
            Lists.Place(label, header, column)
        end
        header.Labels[column.key] = label
    end
    return header
end
