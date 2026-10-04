-- Offline stand-in for the game's `bit` library (plain Lua 5.1 has none).
-- Results are unsigned 32-bit; the add-on folds every result into [0, 2^32) anyway.

if bit then return end

local floor = math.floor
local TWO32 = 4294967296

local XOR8, AND8 = {}, {}
for a = 0, 255 do
    for b = 0, 255 do
        local x, y, r, s, p = a, b, 0, 0, 1
        for _ = 1, 8 do
            local ba, bb = x % 2, y % 2
            if ba ~= bb then r = r + p end
            if ba == 1 and bb == 1 then s = s + p end
            x, y, p = floor(x / 2), floor(y / 2), p * 2
        end
        XOR8[a * 256 + b], AND8[a * 256 + b] = r, s
    end
end

local function bytewise(t, a, b)
    a, b = a % TWO32, b % TWO32
    local r, p = 0, 1
    for _ = 1, 4 do
        r = r + t[(a % 256) * 256 + b % 256] * p
        a, b, p = floor(a / 256), floor(b / 256), p * 256
    end
    return r
end

bit = {
    bxor = function(a, b) return bytewise(XOR8, a, b) end,
    band = function(a, b) return bytewise(AND8, a, b) end,
    bor = function(a, b) a, b = a % TWO32, b % TWO32; return a + b - bytewise(AND8, a, b) end,
    bnot = function(a) return TWO32 - 1 - a % TWO32 end,
    lshift = function(a, n) return (a * 2 ^ n) % TWO32 end,
    rshift = function(a, n) return floor((a % TWO32) / 2 ^ n) end,
}
