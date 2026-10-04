-- Ed25519 signatures (RFC 8032) on Lua 5.1 numbers, following the TweetNaCl algorithms.
-- Field elements are 16 limbs of 16 bits held in doubles; every intermediate stays below 2^53.
-- Byte arrays are 0-based tables. Curve constants are computed at load, not typed in.
-- Not constant-time.

local _, ns = ...
---@cast ns WhosWho.Namespace

local floor = math.floor
local byte, char, concat = string.byte, string.char, table.concat
local SHA512 = ns.Crypto.SHA512

-- Field arithmetic modulo p = 2^255 - 19 ------------------------------------------------

local function gf(init)
    local o = {}
    for i = 1, 16 do o[i] = init and init[i] or 0 end
    return o
end

local function set(o, a)
    for i = 1, 16 do o[i] = a[i] end
end

local function car(o)
    for i = 1, 15 do
        local c = floor(o[i] / 65536)
        o[i] = o[i] - c * 65536
        o[i + 1] = o[i + 1] + c
    end
    local c = floor(o[16] / 65536)
    o[16] = o[16] - c * 65536
    o[1] = o[1] + 38 * c
end

local function A(o, a, b)
    for i = 1, 16 do o[i] = a[i] + b[i] end
end

local function Z(o, a, b)
    for i = 1, 16 do o[i] = a[i] - b[i] end
end

local T = {}
local function M(o, a, b)
    for i = 1, 31 do T[i] = 0 end
    for i = 1, 16 do
        local ai = a[i]
        if ai ~= 0 then
            for j = 1, 16 do
                local k = i + j - 1
                T[k] = T[k] + ai * b[j]
            end
        end
    end
    for i = 1, 15 do T[i] = T[i] + 38 * T[i + 16] end
    for i = 1, 16 do o[i] = T[i] end
    car(o)
    car(o)
end

local function S(o, a) M(o, a, a) end

local function inv(o, x)
    local c = gf(x)
    for a = 253, 0, -1 do
        S(c, c)
        if a ~= 2 and a ~= 4 then M(c, c, x) end
    end
    set(o, c)
end

local function pow2523(o, x)
    local c = gf(x)
    for a = 250, 0, -1 do
        S(c, c)
        if a ~= 1 then M(c, c, x) end
    end
    set(o, c)
end

-- Fully reduced little-endian 32-byte encoding.
local function pack25519(n)
    local t, m = gf(n), gf()
    car(t); car(t); car(t)
    for _ = 1, 2 do
        m[1] = t[1] - 0xffed
        for i = 2, 15 do
            m[i] = t[i] - 0xffff - (m[i - 1] < 0 and 1 or 0)
            m[i - 1] = m[i - 1] % 65536
        end
        m[16] = t[16] - 0x7fff - (m[15] < 0 and 1 or 0)
        m[15] = m[15] % 65536
        if m[16] >= 0 then set(t, m) end
    end
    local o = {}
    for i = 1, 16 do
        o[2 * i - 2] = t[i] % 256
        o[2 * i - 1] = floor(t[i] / 256)
    end
    return o
end

local function unpack25519(n)
    local o = gf()
    for i = 1, 16 do o[i] = n[2 * i - 2] + n[2 * i - 1] * 256 end
    o[16] = o[16] % 32768
    return o
end

local function neq(a, b)
    local c, d = pack25519(a), pack25519(b)
    for i = 0, 31 do
        if c[i] ~= d[i] then return true end
    end
    return false
end

local function par(a)
    return pack25519(a)[0] % 2
end

-- Constants --------------------------------------------------------------------------

local gf0, gf1 = gf(), gf({ 1 })

local D, D2, I = gf(), gf(), gf()
do
    local num, den = gf(), gf({ 121666 })
    Z(num, gf0, gf({ 121665 }))
    inv(den, den)
    M(D, num, den)
    A(D2, D, D)

    -- sqrt(-1) = 2^((p - 1) / 4); the exponent 2^253 - 5 has every bit set but bit 2.
    local two = gf({ 2 })
    set(I, gf1)
    for bitIndex = 252, 0, -1 do
        S(I, I)
        if bitIndex ~= 2 then M(I, I, two) end
    end
end

-- Group operations on extended coordinates {X, Y, Z, T} --------------------------------

local ta, tb, tc, td, tt, te, tf, tg, th = gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf()

local function add(p, q)
    Z(ta, p[2], p[1]); Z(tt, q[2], q[1]); M(ta, ta, tt)
    A(tb, p[1], p[2]); A(tt, q[1], q[2]); M(tb, tb, tt)
    M(tc, p[4], q[4]); M(tc, tc, D2)
    M(td, p[3], q[3]); A(td, td, td)
    Z(te, tb, ta); Z(tf, td, tc); A(tg, td, tc); A(th, tb, ta)
    M(p[1], te, tf); M(p[2], th, tg); M(p[3], tg, tf); M(p[4], te, th)
end

-- When set, scalar multiplication yields every `sliceEvery` bits if it runs inside a coroutine,
-- so a caller can spread one signature check over several frames.
local sliceEvery

local function scalarmult(q, s)
    local p = { gf(), gf(gf1), gf(gf1), gf() }
    for i = 255, 0, -1 do
        if sliceEvery and i % sliceEvery == 0 and coroutine.running() then coroutine.yield() end
        local b = floor(s[floor(i / 8)] / 2 ^ (i % 8)) % 2
        if b == 1 then
            for k = 1, 4 do p[k], q[k] = q[k], p[k] end
        end
        add(q, p)
        add(p, p)
        if b == 1 then
            for k = 1, 4 do p[k], q[k] = q[k], p[k] end
        end
    end
    return p
end

local function pack(p)
    local zi, tx, ty = gf(), gf(), gf()
    inv(zi, p[3])
    M(tx, p[1], zi)
    M(ty, p[2], zi)
    local r = pack25519(ty)
    r[31] = r[31] + par(tx) * 128
    return r
end

-- Decodes a point and returns its negation, or nil if the bytes are not a point.
local function unpackneg(bytes)
    local r = { gf(), gf(), gf(gf1), gf() }
    local num, den, den2, den4, den6, t, chk = gf(), gf(), gf(), gf(), gf(), gf(), gf()
    r[2] = unpack25519(bytes)
    S(num, r[2])
    M(den, num, D)
    Z(num, num, r[3])
    A(den, r[3], den)

    S(den2, den)
    S(den4, den2)
    M(den6, den4, den2)
    M(t, den6, num)
    M(t, t, den)

    pow2523(t, t)
    M(t, t, num)
    M(t, t, den)
    M(t, t, den)
    M(r[1], t, den)

    S(chk, r[1])
    M(chk, chk, den)
    if neq(chk, num) then M(r[1], r[1], I) end

    S(chk, r[1])
    M(chk, chk, den)
    if neq(chk, num) then return nil end

    if par(r[1]) == floor(bytes[31] / 128) then Z(r[1], gf0, r[1]) end
    M(r[4], r[1], r[2])
    return r
end

-- Base point: y = 4/5, x even.
local BX, BY = gf(), gf()
do
    local five = gf({ 5 })
    inv(five, five)
    M(BY, gf({ 4 }), five)
    local neg = assert(unpackneg(pack25519(BY)), "base point")
    Z(BX, gf0, neg[1])
    car(BX)
end
local BT = gf()
M(BT, BX, BY)

local function scalarbase(s)
    return scalarmult({ gf(BX), gf(BY), gf(gf1), gf(BT) }, s)
end

-- Scalars modulo L = 2^252 + 27742317777372353535851937790883648493 -----------------------

local L = {
    [0] = 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10,
}

local function modL(r, x)
    for i = 63, 32, -1 do
        local carry = 0
        local j = i - 32
        while j < i - 12 do
            x[j] = x[j] + carry - 16 * x[i] * L[j - (i - 32)]
            carry = floor((x[j] + 128) / 256)
            x[j] = x[j] - carry * 256
            j = j + 1
        end
        x[j] = x[j] + carry
        x[i] = 0
    end
    local carry = 0
    for j = 0, 31 do
        x[j] = x[j] + carry - floor(x[31] / 16) * L[j]
        carry = floor(x[j] / 256)
        x[j] = x[j] % 256
    end
    for j = 0, 31 do x[j] = x[j] - carry * L[j] end
    for i = 0, 31 do
        x[i + 1] = x[i + 1] + floor(x[i] / 256)
        r[i] = x[i] % 256
    end
end

local function reduce(bytes)
    local x, r = {}, {}
    for i = 0, 63 do x[i] = bytes[i] end
    modL(r, x)
    return r
end

-- Byte helpers -------------------------------------------------------------------------

local function toBytes(s)
    local t = {}
    for i = 1, #s do t[i - 1] = byte(s, i) end
    return t
end

local function fromBytes(t, n)
    local out = {}
    for i = 0, n - 1 do out[i + 1] = char(t[i]) end
    return concat(out)
end

local function expandSeed(seed)
    local d = toBytes(SHA512(seed))
    d[0] = d[0] - d[0] % 8
    d[31] = d[31] % 64 + 64
    return d
end

-- Public API: binary strings in and out ---------------------------------------------------

---@class WhosWho.Ed25519
local Ed25519 = {}

---Inside a coroutine, scalar multiplication yields every `bits` bits, so one call can be spread over frames.
---@param bits integer? nil never yields
function Ed25519.SetSlicing(bits)
    sliceEvery = bits
end

---@param seed string private key, 32 bytes
---@return string publicKey 32 bytes
function Ed25519.PublicKey(seed)
    assert(#seed == 32, "seed must be 32 bytes")
    return fromBytes(pack(scalarbase(expandSeed(seed))), 32)
end

---@param message string
---@param seed string private key, 32 bytes
---@param publicKey string? 32 bytes; derived from the seed when nil
---@return string signature 64 bytes
function Ed25519.Sign(message, seed, publicKey)
    assert(#seed == 32, "seed must be 32 bytes")
    local d = expandSeed(seed)
    publicKey = publicKey or fromBytes(pack(scalarbase(d)), 32)

    local prefix = {}
    for i = 32, 63 do prefix[#prefix + 1] = char(d[i]) end
    local r = reduce(toBytes(SHA512(concat(prefix) .. message)))
    local R = fromBytes(pack(scalarbase(r)), 32)

    local h = reduce(toBytes(SHA512(R .. publicKey .. message)))
    local x = {}
    for i = 0, 63 do x[i] = i < 32 and r[i] or 0 end
    for i = 0, 31 do
        for j = 0, 31 do x[i + j] = x[i + j] + h[i] * d[j] end
    end
    local s = {}
    modL(s, x)
    return R .. fromBytes(s, 32)
end

---@param message string
---@param signature string 64 bytes
---@param publicKey string 32 bytes
---@return boolean
function Ed25519.Verify(message, signature, publicKey)
    if type(signature) ~= "string" or #signature ~= 64 then return false end
    if type(publicKey) ~= "string" or #publicKey ~= 32 then return false end

    local q = unpackneg(toBytes(publicKey))
    if not q then return false end

    -- Reject a non-canonical S (S >= L) so signatures cannot be altered.
    local s = toBytes(signature:sub(33))
    for i = 31, 0, -1 do
        if s[i] < L[i] then break end
        if s[i] > L[i] or i == 0 then return false end
    end

    local R = signature:sub(1, 32)
    local h = reduce(toBytes(SHA512(R .. publicKey .. message)))
    local p = scalarmult(q, h)
    add(p, scalarbase(s))
    return fromBytes(pack(p), 32) == R
end

ns.Crypto.Ed25519 = Ed25519
