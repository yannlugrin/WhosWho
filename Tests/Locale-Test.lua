-- luacheck: allow defined, ignore 121 122 131 143
-- Offline suite: every L["..."] key used by a file in the TOC exists in Locales/enUS.lua, and every enUS key is used.
-- Run from the add-on root: lua Tests/Locale-Test.lua [root]

local root = (arg and arg[1]) or "."

local function read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local defined = {}
for key in read("Locales/enUS.lua"):gmatch('L%["(.-)"%]%s*=') do defined[key] = true end

local used, failures = {}, 0
for line in read("WhosWho_Camelot.toc"):gmatch("[^\r\n]+") do
    local path = line:match("^([%w_\\/%-]+%.lua)$")
    if path and not path:find("^Locales") then
        path = path:gsub("\\", "/")
        for key in read(path):gmatch('L%["(.-)"%]') do
            used[key] = true
            if not defined[key] then
                failures = failures + 1
                print(("FAIL missing in enUS (%s): %s"):format(path, key))
            end
        end
    end
end

for key in pairs(defined) do
    if not used[key] then
        failures = failures + 1
        print("FAIL unused enUS key: " .. key)
    end
end

if failures > 0 then
    print(("%d LOCALE PROBLEMS"):format(failures))
    os.exit(1)
end
print("ALL LOCALE CHECKS PASSED")
