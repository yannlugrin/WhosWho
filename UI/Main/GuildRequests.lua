local _, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local Lists = ns.Lists
local Glyphs = ns.Glyphs

-- My guild's requests to its members, as the trusted ranks see them: their lines in a member's panel, the list of all of
-- them, and Dismiss.
---@class WhosWho.GuildRequests
local GuildRequests = {}
ns.GuildRequests = GuildRequests

local ROW_HEIGHT = 24
local GLYPH_SIZE = 12
local SCROLL_BAR_WIDTH = 16
local DISMISS_WIDTH = 80

---The glyph before a request: not done yet, or done.
---@param request WhosWho.ShownGuildRequest
---@return WhosWho.Glyph
function GuildRequests.Glyph(request)
    return request.done and Glyphs.RequestDone or Glyphs.Request
end

---What was asked, and what the member shows now, or done.
---@param request WhosWho.ShownGuildRequest
---@return string
function GuildRequests.What(request)
    local now = request.now and L["now %s"]:format(request.now) or GREEN_FONT_COLOR:WrapTextInColorCode(L["done"])
    return request.asked .. " · " .. now
end

---Who asked, and how long ago.
---@param request WhosWho.ShownGuildRequest
---@return string
function GuildRequests.AskedBy(request)
    return L["Asked by %s, %s ago"]:format(request.by, FriendsFrame_GetLastOnline(request.at))
end

---Signs my guild's record about the member without that request, and sends it to the guild.
---@param request WhosWho.ShownGuildRequest
function GuildRequests.Dismiss(request)
    ns.Protocol.SendGuildRecord(ns.GuildRecord.Dismiss(request.clubId, request.id, request.kind))
end

-- The list of all requests ------------------------------------------------------------------------

local COLUMNS = {
    { key = "Dismiss", width = DISMISS_WIDTH + 8, label = "" },
    { key = "By", width = 150, label = L["Asked by"] },
    { key = "Now", width = 120, label = L["Now"] },
    { key = "Asked", width = 150, label = L["Asked"] },
}
local columnsWidth = Lists.LayOut(COLUMNS)
local columnByKey = {}
for _, column in ipairs(COLUMNS) do columnByKey[column.key] = column end
local MEMBER_LEFT = 6 + GLYPH_SIZE + 6

---A row of the requests list; createRow adds its regions the first time the row is used.
---@class WhosWho.GuildRequestRow: Frame
---@field Glyph Frame
---@field Member FontString
---@field Asked FontString
---@field Now FontString
---@field By FontString
---@field DismissButton Button

---@type table? EllesmereUI's skinning functions, for rows created after they were handed over
local skin
ns.Skin.Apply(function(S) skin = S end)

---@param row WhosWho.GuildRequestRow
local function createRow(row)
    row.Glyph = CreateFrame("Frame", nil, row)
    row.Glyph:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    row.Glyph:SetPoint("LEFT", 6, 0)
    row.Glyph.Texture = row.Glyph:CreateTexture(nil, "ARTWORK")
    row.Glyph.Texture:SetAllPoints()
    row.Glyph:SetScript("OnEnter", function(self) Glyphs.ShowTooltip(self, self.glyph) end)
    row.Glyph:SetScript("OnLeave", GameTooltip_Hide)

    row.Member = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Member:SetPoint("LEFT", MEMBER_LEFT, 0)
    row.Member:SetPoint("RIGHT", row, "RIGHT", -columnsWidth - 6, 0)
    row.Member:SetJustifyH("LEFT")
    row.Member:SetWordWrap(false)

    for _, key in ipairs({ "Asked", "Now", "By" }) do
        row[key] = row:CreateFontString(nil, "OVERLAY", key == "Asked" and "GameFontHighlight" or "GameFontDisable")
        Lists.Place(row[key], row, columnByKey[key])
        row[key]:SetWordWrap(false)
    end

    row.DismissButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.DismissButton:SetText(L["Dismiss"])
    row.DismissButton:SetSize(DISMISS_WIDTH, 20)
    row.DismissButton:SetPoint("RIGHT", -4, 0)

    if skin then skin.Button(row.DismissButton) end
end

---@param row WhosWho.GuildRequestRow
---@param request WhosWho.ShownGuildRequest
local function initRow(row, request)
    if not row.Member then createRow(row) end

    row.Glyph.glyph = GuildRequests.Glyph(request)
    Glyphs.Set(row.Glyph.Texture, row.Glyph.glyph)
    row.Member:SetText(request.member)
    row.Asked:SetText(request.asked)
    row.Now:SetText(request.now or GREEN_FONT_COLOR:WrapTextInColorCode(L["done"]))
    row.By:SetText(L["%s, %s ago"]:format(request.by, FriendsFrame_GetLastOnline(request.at)))
    row.DismissButton:SetScript("OnClick", function() GuildRequests.Dismiss(request) end)
end

---The requests view: its title and Close button at the top, the list of every request below.
---@class WhosWho.GuildRequestsView: Frame
---@field Title FontString
---@field CloseButton Button
---@field Empty FontString
---@field listBox Frame

---Builds the requests view; the caller anchors it and wires its Close button.
---@param parent Frame
---@return WhosWho.GuildRequestsView
function GuildRequests.CreateView(parent)
    local view = CreateFrame("Frame", nil, parent)
    ---@cast view WhosWho.GuildRequestsView

    view.Title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.Title:SetPoint("TOPLEFT", 8, -4)
    view.Title:SetText(L["Requests"])

    view.CloseButton = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.CloseButton:SetText(CLOSE)
    view.CloseButton:SetSize(view.CloseButton:GetTextWidth() + 40, 22)
    view.CloseButton:SetPoint("TOPRIGHT", 0, 0)

    local inset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 0, -30)
    inset:SetPoint("BOTTOMRIGHT")

    local header = Lists.CreateHeader(inset, { key = "Member", label = L["Member"], left = MEMBER_LEFT }, COLUMNS,
        columnsWidth)
    header:SetPoint("TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", -4 - SCROLL_BAR_WIDTH, -4)

    local listBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    listBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    listBox:SetPoint("BOTTOMRIGHT", -4 - SCROLL_BAR_WIDTH, 4)
    view.listBox = listBox

    local listBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
    listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 6, 0)

    view.Empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.Empty:SetPoint("CENTER")
    view.Empty:SetText(L["No requests."])

    local listView = CreateScrollBoxListLinearView()
    listView:SetElementExtent(ROW_HEIGHT)
    listView:SetElementInitializer("Frame", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, listView)

    ns.Skin.Apply(function(S)
        S.Inset(inset)
        S.ScrollBar(listBar)
        S.Button(view.CloseButton)
    end)
    return view
end

---@param view WhosWho.GuildRequestsView
---@param requests WhosWho.ShownGuildRequest[] in the order shown
function GuildRequests.SetRequests(view, requests)
    view.Empty:SetShown(requests[1] == nil)
    view.listBox:SetDataProvider(CreateDataProvider(requests), ScrollBoxConstants.RetainScrollPosition)
end

---The label of the button opening the view: how many requests aren't done yet.
---@param requests WhosWho.ShownGuildRequest[]
---@return string
function GuildRequests.ButtonLabel(requests)
    local open = 0
    for _, request in ipairs(requests) do
        if not request.done then open = open + 1 end
    end
    return L["Requests (%d)"]:format(open)
end
