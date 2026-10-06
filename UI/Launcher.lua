local addonName, ns = ...
---@cast ns WhosWho.Namespace

local L = ns.L
local LibDBIcon = LibStub("LibDBIcon-1.0")

---@class WhosWho.Launcher
local Launcher = {}
ns.Launcher = Launcher

local function toggleWindow()
    if ns.Main.Window:IsShown() then
        ns.Main.Window:Hide()
    else
        ns.Commands.open("")
    end
end

local dataObject = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
    type = "launcher",
    label = L["Who's Who"],
    icon = C_AddOns.GetAddOnMetadata(addonName, "IconTexture"),
    OnClick = function(owner, button)
        if button ~= "RightButton" then
            toggleWindow()
            return
        end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateButton(L["My identity"], function() ns.Commands.open("") end)
            root:CreateButton(L["Settings"], function() ns.Commands.settings("") end)
        end)
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine(L["Who's Who"])
        tooltip:AddLine(L["Click: open your identity"], 1, 1, 1)
        tooltip:AddLine(L["Right-click: menu"], 1, 1, 1)
    end,
})

---Shows the minimap button and the add-on compartment entry as the settings say. Call once the settings are loaded.
function Launcher.Register()
    LibDBIcon:Register(addonName, dataObject, ns.settings.launcher)
end

---@param shown boolean
function Launcher.SetMinimapButtonShown(shown)
    ns.settings.launcher.hide = not shown
    if shown then LibDBIcon:Show(addonName) else LibDBIcon:Hide(addonName) end
end

---@param shown boolean
function Launcher.SetCompartmentShown(shown)
    if shown then
        LibDBIcon:AddButtonToCompartment(addonName)
    else
        LibDBIcon:RemoveButtonFromCompartment(addonName)
        -- LibDBIcon clears the field; nil would read back as the default, shown.
        ns.settings.launcher.showInCompartment = false
    end
end
