local _, ns = ...
---@cast ns WhosWho.Namespace

-- The nickname on friendly players' nameplates, on a line of its own above or below the name. The game gives add-ons no
-- friendly nameplate in instances, and a nameplate add-on that hides the game's own frame hides the line with it.
---@class WhosWho.Nameplates
local Nameplates = {}
ns.Nameplates = Nameplates

local issecretvalue = issecretvalue or function() return false end

-- The line on each nameplate that got one; kept apart from the game's frames, which other add-ons read.
---@type table<Frame, FontString>
local lines = setmetatable({}, { __mode = "k" })
---@type table<string, true> the nameplate units shown now
local shownUnits = {}

-- The nickname of the player of that nameplate, when it isn't the character's own name; nil for nothing to show.
local function nicknameOf(unit)
    if not (UnitIsPlayer(unit) and UnitIsFriend("player", unit)) then return nil end
    local guid = UnitGUID(unit)
    if not guid or issecretvalue(guid) then return nil end
    local resolution = ns.Resolver.Resolve(guid)
    if not resolution or resolution.mine then return nil end
    local person = ns.People.Get(resolution.id)
    if not (person and person.chars[guid]) or resolution.nickname == person.chars[guid].name then return nil end
    return resolution.nickname
end

-- Shows or hides the line of that unit's nameplate, as the setting and the person want it.
local function update(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local settings = ns.settings.nameplates.nickname
    local nickname = settings.enable and nicknameOf(unit)
    local nameText = plate.UnitFrame and plate.UnitFrame.name
    local line = lines[plate]
    if not (nickname and nameText) then
        if line then line:Hide() end
        return
    end

    if not line then
        line = plate.UnitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lines[plate] = line
    end
    line:ClearAllPoints()
    if settings.position == "above" then
        line:SetPoint("BOTTOM", nameText, "TOP", 0, 1)
    else
        line:SetPoint("TOP", nameText, "BOTTOM", 0, -1)
    end
    line:SetText(nickname)
    line:Show()
end

---Shows every shown nameplate again: the setting changed, or the people.
function Nameplates.Refresh()
    for unit in pairs(shownUnits) do update(unit) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        shownUnits[unit] = true
        update(unit)
        return
    end
    shownUnits[unit] = nil
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate and lines[plate] then lines[plate]:Hide() end
end)
ns.People.OnChanged(Nameplates.Refresh)
