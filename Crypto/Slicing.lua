-- Slicing for the crypto code: inside a coroutine, long hashes and signature operations yield along the way, so a
-- caller can spread one over several frames. Each slice point marks about 0.3 to 0.6 ms of work in game: a SHA-512
-- block, a bit of scalar multiplication, 16 steps of a field inversion or square root.

local _, ns = ...
---@cast ns WhosWho.Namespace

---@class WhosWho.Crypto
---@field SHA512 fun(message: string): string set by SHA512.lua
---@field ToHex fun(binary: string): string set by SHA512.lua
---@field FromHex fun(hex: string): string set by SHA512.lua
---@field Ed25519 WhosWho.Ed25519 set by Ed25519.lua
local Crypto = {}
ns.Crypto = Crypto

local sliceEvery
local points = 0

---Inside a coroutine, the crypto code yields once every `points` slice points.
---@param slicePoints integer? nil never yields
function Crypto.SetSlicing(slicePoints)
    sliceEvery = slicePoints
    points = 0
end

---A slice point: yields when slicing is on, inside a coroutine, once enough points passed since the last yield.
function Crypto.Slice()
    if not (sliceEvery and coroutine.running()) then return end
    points = points + 1
    if points < sliceEvery then return end
    points = 0
    coroutine.yield()
end
