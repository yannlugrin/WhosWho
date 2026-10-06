local addonName, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L

---@class WhosWho.Main
---@field Window Frame the main window
---@field MyIdentity Frame the My identity tab
---@field People Frame the People tab
local Main = {}
ns.Main = Main

local WIDTH, HEIGHT = 700, 460
local TAB_SPACING = 3

-- Window -----------------------------------------------------------------------------------------

-- Named: the game closes the frames listed in UISpecialFrames, by name, on Escape.
local window = CreateFrame("Frame", "WhosWhoMainWindow", UIParent, "ButtonFrameTemplate")
window:SetSize(WIDTH, HEIGHT)
window:SetPoint("CENTER")
window:SetTitle(L["Who's Who"])
window:SetPortraitToAsset(C_AddOns.GetAddOnMetadata(addonName, "IconTexture"))
window:SetMovable(true)
window:SetClampedToScreen(true)
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
table.insert(UISpecialFrames, "WhosWhoMainWindow")
window:Hide()
window.TitleContainer:EnableMouse(true)
window.TitleContainer:RegisterForDrag("LeftButton")
window.TitleContainer:SetScript("OnDragStart", function() window:StartMoving() end)
window.TitleContainer:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
Main.Window = window

-- Each tab lays out its own inset.
window.Inset:Hide()
-- The window offers its own way to link the character.
window:HookScript("OnShow", function() ns.IdentityDialogs.HideLinkPrompts() end)

-- Tabs -------------------------------------------------------------------------------------------

---@type { tab: Button, panel: Frame }[] in tab order
local tabs = {}

---Shows the panel of a tab and hides the others.
---@param panel Frame
function Main.SelectTab(panel)
    for id, entry in ipairs(tabs) do
        entry.panel:SetShown(entry.panel == panel)
        if entry.panel == panel then PanelTemplates_SetTab(window, id) end
    end
end

---Adds a tab after the others; the first one added is selected.
---@param label string
---@param panel Frame the tab's content, a child of the window
function Main.AddTab(label, panel)
    local tab = CreateFrame("Button", nil, window, "PanelTabButtonTemplate")
    tab:SetID(#tabs + 1)
    tab:SetText(label)
    if tabs[1] then
        tab:SetPoint("LEFT", tabs[#tabs].tab, "RIGHT", TAB_SPACING, 0)
    else
        tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12, 2)
    end
    PanelTemplates_TabResize(tab, 0)
    tab:SetScript("OnClick", function() Main.SelectTab(panel) end)
    tabs[#tabs + 1] = { tab = tab, panel = panel }
    PanelTemplates_SetNumTabs(window, #tabs)
    Main.SelectTab(tabs[1].panel)
    ns.Skin.Apply(function(S) S.Tab(tab) end)
end

-- Skin -------------------------------------------------------------------------------------------

ns.Skin.Apply(function(S)
    S.Shell(window)
    S.CloseButton(window.CloseButton)
end)
