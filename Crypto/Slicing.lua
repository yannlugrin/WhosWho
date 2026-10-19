-- Slicing for the crypto code: inside a coroutine, long hashes and signature operations yield along the way, so a
-- caller can spread one over several frames; outside one, they never yield. Each slice point marks about 0.3 to 0.6 ms
-- of work in game: a SHA-512 block, a bit of scalar multiplication, 16 steps of a field inversion or square root.

local _, ns = ...
---@cast ns WhosWho.Namespace

---@class WhosWho.Crypto
---@field SHA512 fun(message: string): string set by SHA512.lua
---@field ToHex fun(binary: string): string set by SHA512.lua
---@field FromHex fun(hex: string): string set by SHA512.lua
---@field Ed25519 WhosWho.Ed25519 set by Ed25519.lua
local Crypto = {}
ns.Crypto = Crypto

-- Slice points between two yields: about 1.5 to 2.4 ms of work in a frame.
local POINTS_PER_SLICE = 4

-- The coroutine that last passed a slice point, and the points it passed since its last yield: each coroutine starts
-- counting from zero, whatever another one left.
---@type thread?
local counting
local points = 0

---A slice point: inside a coroutine, yields once POINTS_PER_SLICE points passed since its last yield.
function Crypto.Slice()
    local thread = coroutine.running()
    if not thread then return end
    if thread ~= counting then counting, points = thread, 0 end
    points = points + 1
    if points < POINTS_PER_SLICE then return end
    points = 0
    coroutine.yield()
end
