-- SHA-512 (FIPS 180-4) on Lua 5.1 numbers.
-- Each 64-bit word is a pair of 32-bit halves (hi, lo) held in doubles. Shifts and
-- rotations are done with exact arithmetic; AND/XOR use the game's `bit` library.

local _, ns = ...
---@cast ns WhosWho.Namespace

local bxor, band = bit.bxor, bit.band
local floor = math.floor
local byte, char, rep, format = string.byte, string.char, string.rep, string.format

local TWO32 = 4294967296

-- First 64 bits of the fractional parts of the cube roots of the first 80 primes, as hi, lo pairs.
local K = {
    0x428a2f98, 0xd728ae22, 0x71374491, 0x23ef65cd, 0xb5c0fbcf, 0xec4d3b2f, 0xe9b5dba5, 0x8189dbbc,
    0x3956c25b, 0xf348b538, 0x59f111f1, 0xb605d019, 0x923f82a4, 0xaf194f9b, 0xab1c5ed5, 0xda6d8118,
    0xd807aa98, 0xa3030242, 0x12835b01, 0x45706fbe, 0x243185be, 0x4ee4b28c, 0x550c7dc3, 0xd5ffb4e2,
    0x72be5d74, 0xf27b896f, 0x80deb1fe, 0x3b1696b1, 0x9bdc06a7, 0x25c71235, 0xc19bf174, 0xcf692694,
    0xe49b69c1, 0x9ef14ad2, 0xefbe4786, 0x384f25e3, 0x0fc19dc6, 0x8b8cd5b5, 0x240ca1cc, 0x77ac9c65,
    0x2de92c6f, 0x592b0275, 0x4a7484aa, 0x6ea6e483, 0x5cb0a9dc, 0xbd41fbd4, 0x76f988da, 0x831153b5,
    0x983e5152, 0xee66dfab, 0xa831c66d, 0x2db43210, 0xb00327c8, 0x98fb213f, 0xbf597fc7, 0xbeef0ee4,
    0xc6e00bf3, 0x3da88fc2, 0xd5a79147, 0x930aa725, 0x06ca6351, 0xe003826f, 0x14292967, 0x0a0e6e70,
    0x27b70a85, 0x46d22ffc, 0x2e1b2138, 0x5c26c926, 0x4d2c6dfc, 0x5ac42aed, 0x53380d13, 0x9d95b3df,
    0x650a7354, 0x8baf63de, 0x766a0abb, 0x3c77b2a8, 0x81c2c92e, 0x47edaee6, 0x92722c85, 0x1482353b,
    0xa2bfe8a1, 0x4cf10364, 0xa81a664b, 0xbc423001, 0xc24b8b70, 0xd0f89791, 0xc76c51a3, 0x0654be30,
    0xd192e819, 0xd6ef5218, 0xd6990624, 0x5565a910, 0xf40e3585, 0x5771202a, 0x106aa070, 0x32bbd1b8,
    0x19a4c116, 0xb8d2d0c8, 0x1e376c08, 0x5141ab53, 0x2748774c, 0xdf8eeb99, 0x34b0bcb5, 0xe19b48a8,
    0x391c0cb3, 0xc5c95a63, 0x4ed8aa4a, 0xe3418acb, 0x5b9cca4f, 0x7763e373, 0x682e6ff3, 0xd6b2b8a3,
    0x748f82ee, 0x5defb2fc, 0x78a5636f, 0x43172f60, 0x84c87814, 0xa1f0ab72, 0x8cc70208, 0x1a6439ec,
    0x90befffa, 0x23631e28, 0xa4506ceb, 0xde82bde9, 0xbef9a3f7, 0xb2c67915, 0xc67178f2, 0xe372532b,
    0xca273ece, 0xea26619c, 0xd186b8c7, 0x21c0c207, 0xeada7dd6, 0xcde0eb1e, 0xf57d4f7f, 0xee6ed178,
    0x06f067aa, 0x72176fba, 0x0a637dc5, 0xa2c898a6, 0x113f9804, 0xbef90dae, 0x1b710b35, 0x131c471b,
    0x28db77f5, 0x23047d84, 0x32caab7b, 0x40c72493, 0x3c9ebe0a, 0x15c9bebc, 0x431d67c4, 0x9c100d4c,
    0x4cc5d4be, 0xcb3e42b6, 0x597f299c, 0xfc657e2a, 0x5fcb6fab, 0x3ad6faec, 0x6c44198c, 0x4a475817,
}

local IV = {
    0x6a09e667, 0xf3bcc908, 0xbb67ae85, 0x84caa73b, 0x3c6ef372, 0xfe94f82b, 0xa54ff53a, 0x5f1d36f1,
    0x510e527f, 0xade682d1, 0x9b05688c, 0x2b3e6c1f, 0x1f83d9ab, 0xfb41bd6b, 0x5be0cd19, 0x137e2179,
}

-- The game's bit library may return signed results; fold them back to [0, 2^32).
local function X(a, b) return bxor(a, b) % TWO32 end
local function N(a, b) return band(a, b) % TWO32 end

-- Rotate (hi, lo) right by n bits, 0 < n < 64, n ~= 32.
local function rotr(hi, lo, n)
    if n > 32 then hi, lo, n = lo, hi, n - 32 end
    local p, q = 2 ^ n, 2 ^ (32 - n)
    return floor(hi / p) + (lo % p) * q, floor(lo / p) + (hi % p) * q
end

-- Shift (hi, lo) right by n bits, 0 < n < 32.
local function shr(hi, lo, n)
    local p = 2 ^ n
    return floor(hi / p), floor(lo / p) + (hi % p) * 2 ^ (32 - n)
end

local Wh, Wl = {}, {}

local function compress(H, block, offset)
    for t = 1, 16 do
        local i = offset + (t - 1) * 8
        local b1, b2, b3, b4, b5, b6, b7, b8 = byte(block, i + 1, i + 8)
        Wh[t] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        Wl[t] = ((b5 * 256 + b6) * 256 + b7) * 256 + b8
    end
    for t = 17, 80 do
        local h15, l15 = Wh[t - 15], Wl[t - 15]
        local ah, al = rotr(h15, l15, 1)
        local bh, bl = rotr(h15, l15, 8)
        local ch, cl = shr(h15, l15, 7)
        local s0h, s0l = X(X(ah, bh), ch), X(X(al, bl), cl)
        local h2, l2 = Wh[t - 2], Wl[t - 2]
        ah, al = rotr(h2, l2, 19)
        bh, bl = rotr(h2, l2, 61)
        ch, cl = shr(h2, l2, 6)
        local s1h, s1l = X(X(ah, bh), ch), X(X(al, bl), cl)
        local lo = Wl[t - 16] + s0l + Wl[t - 7] + s1l
        Wl[t] = lo % TWO32
        Wh[t] = (Wh[t - 16] + s0h + Wh[t - 7] + s1h + floor(lo / TWO32)) % TWO32
    end

    local ah, al, bh, bl, chh, chl, dh, dl = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    local eh, el, fh, fl, gh, gl, hh, hl = H[9], H[10], H[11], H[12], H[13], H[14], H[15], H[16]

    for t = 1, 80 do
        local r1h, r1l = rotr(eh, el, 14)
        local r2h, r2l = rotr(eh, el, 18)
        local r3h, r3l = rotr(eh, el, 41)
        local S1h, S1l = X(X(r1h, r2h), r3h), X(X(r1l, r2l), r3l)
        local cHh = X(N(eh, fh), N(TWO32 - 1 - eh, gh))
        local cHl = X(N(el, fl), N(TWO32 - 1 - el, gl))
        local k = t * 2
        local t1l = hl + S1l + cHl + K[k] + Wl[t]
        local t1h = hh + S1h + cHh + K[k - 1] + Wh[t] + floor(t1l / TWO32)
        t1l = t1l % TWO32

        r1h, r1l = rotr(ah, al, 28)
        r2h, r2l = rotr(ah, al, 34)
        r3h, r3l = rotr(ah, al, 39)
        local S0h, S0l = X(X(r1h, r2h), r3h), X(X(r1l, r2l), r3l)
        local mh = X(X(N(ah, bh), N(ah, chh)), N(bh, chh))
        local ml = X(X(N(al, bl), N(al, chl)), N(bl, chl))
        local t2l = S0l + ml
        local t2h = S0h + mh + floor(t2l / TWO32)

        hh, hl = gh, gl
        gh, gl = fh, fl
        fh, fl = eh, el
        local sum = dl + t1l
        el = sum % TWO32
        eh = (dh + t1h + floor(sum / TWO32)) % TWO32
        dh, dl = chh, chl
        chh, chl = bh, bl
        bh, bl = ah, al
        sum = t1l + t2l % TWO32
        al = sum % TWO32
        ah = (t1h + t2h + floor(sum / TWO32)) % TWO32
    end

    local regs = { ah, al, bh, bl, chh, chl, dh, dl, eh, el, fh, fl, gh, gl, hh, hl }
    for i = 1, 16, 2 do
        local lo = H[i + 1] + regs[i + 1]
        H[i + 1] = lo % TWO32
        H[i] = (H[i] + regs[i] + floor(lo / TWO32)) % TWO32
    end
end

local function word(n)
    return char(floor(n / 16777216) % 256, floor(n / 65536) % 256, floor(n / 256) % 256, n % 256)
end

---@param message string binary
---@return string digest 64 bytes, binary
local function SHA512(message)
    local H = {}
    for i = 1, 16 do H[i] = IV[i] end

    local length = #message
    local padded = message .. "\128" .. rep("\0", (111 - length) % 128)
        .. rep("\0", 8) .. word(floor(length * 8 / TWO32)) .. word(length * 8 % TWO32)
    for offset = 0, #padded - 1, 128 do
        compress(H, padded, offset)
    end

    local out = {}
    for i = 1, 16 do out[i] = word(H[i]) end
    return table.concat(out)
end

---@param binary string
---@return string hex lowercase
local function ToHex(binary)
    return (binary:gsub(".", function(c) return format("%02x", byte(c)) end))
end

---@param hex string
---@return string binary
local function FromHex(hex)
    return (hex:gsub("%x%x", function(h) return char(tonumber(h, 16)) end))
end

---@class WhosWho.Crypto
---@field Ed25519 WhosWho.Ed25519 set by Ed25519.lua
local Crypto = {}
ns.Crypto = Crypto
Crypto.SHA512 = SHA512
Crypto.ToHex = ToHex
Crypto.FromHex = FromHex
