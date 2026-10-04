-- luacheck: allow defined, ignore 121 122 131 143
-- Offline suite: SHA-512 and Ed25519 against OpenSSL-generated and RFC 8032 vectors.
-- Run from the add-on root: lua Tests/Crypto-Test.lua [root]

local root = (arg and arg[1]) or "."
dofile(root .. "/Tests/Support/Bit.lua")

local ns = {}
assert(loadfile(root .. "/Crypto/SHA512.lua"))("WhosWho", ns)
assert(loadfile(root .. "/Crypto/Ed25519.lua"))("WhosWho", ns)

local Crypto = ns.Crypto
local ToHex, FromHex = Crypto.ToHex, Crypto.FromHex
local vectors = dofile(root .. "/Tests/Data/Crypto-Vectors.lua")

local failures, checks = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL " .. label)
    end
end

for _, v in ipairs(vectors.sha512) do
    local got = ToHex(Crypto.SHA512(FromHex(v.msg)))
    check(got == v.digest, ("sha512 of %d bytes: %s"):format(#v.msg / 2, got))
end
check(ToHex(Crypto.SHA512("abc")) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
    .. "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "sha512 abc")

local Ed = Crypto.Ed25519
for n, v in ipairs(vectors.ed25519) do
    local seed, msg = FromHex(v.seed), FromHex(v.msg)
    local pk = Ed.PublicKey(seed)
    check(ToHex(pk) == v.pk, ("ed25519 #%d public key: %s"):format(n, ToHex(pk)))
    local sig = Ed.Sign(msg, seed, pk)
    check(ToHex(sig) == v.sig, ("ed25519 #%d signature: %s"):format(n, ToHex(sig)))
    check(Ed.Verify(msg, FromHex(v.sig), FromHex(v.pk)), ("ed25519 #%d verifies"):format(n))

    -- Tampering with the message, the signature or the key must fail.
    check(not Ed.Verify(msg .. "x", FromHex(v.sig), FromHex(v.pk)), ("ed25519 #%d longer message rejected"):format(n))
    local badSig = FromHex(v.sig):sub(1, 10) .. string.char((FromHex(v.sig):byte(11) + 1) % 256) .. FromHex(v.sig):sub(12)
    check(not Ed.Verify(msg, badSig, FromHex(v.pk)), ("ed25519 #%d altered signature rejected"):format(n))
    local other = vectors.ed25519[n % #vectors.ed25519 + 1]
    check(not Ed.Verify(msg, FromHex(v.sig), FromHex(other.pk)), ("ed25519 #%d other key rejected"):format(n))
end

-- S + L must be rejected (malleability).
do
    local v = vectors.ed25519[1]
    local sig = FromHex(v.sig)
    local L = { 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10 }
    local out, carry = {}, 0
    for i = 1, 32 do
        local b = sig:byte(32 + i) + L[i] + carry
        out[i], carry = string.char(b % 256), math.floor(b / 256)
    end
    check(not Ed.Verify(FromHex(v.msg), sig:sub(1, 32) .. table.concat(out), FromHex(v.pk)), "ed25519 S + L rejected")
end

check(not Ed.Verify("m", "short", ("\0"):rep(32)), "ed25519 short signature rejected")

-- Sliced verification gives the same answer and yields along the way.
do
    local v = vectors.ed25519[3]
    Ed.SetSlicing(16)
    local co = coroutine.create(function() return Ed.Verify(FromHex(v.msg), FromHex(v.sig), FromHex(v.pk)) end)
    local resumes, ok, result = 0
    repeat
        ok, result = coroutine.resume(co)
        resumes = resumes + 1
    until coroutine.status(co) == "dead"
    Ed.SetSlicing(nil)
    check(ok and result == true, "ed25519 sliced verify")
    check(resumes > 16, ("ed25519 sliced verify yields (%d resumes)"):format(resumes))
    check(Ed.Verify(FromHex(v.msg), FromHex(v.sig), FromHex(v.pk)), "ed25519 unsliced outside a coroutine")
end

-- Rough offline timing (PUC Lua 5.1, bit shim: slower than in game for SHA-512).
local clock = os.clock
local seed = FromHex(vectors.ed25519[2].seed)
local t0 = clock()
local pk = Ed.PublicKey(seed)
local t1 = clock()
local sig = Ed.Sign(("record"):rep(20), seed, pk)
local t2 = clock()
Ed.Verify(("record"):rep(20), sig, pk)
local t3 = clock()
print(("timing: public key %.0f ms, sign %.0f ms, verify %.0f ms"):format((t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000))

if failures > 0 then
    print(("%d of %d checks FAILED"):format(failures, checks))
    os.exit(1)
end
print(("ALL %d CRYPTO CHECKS PASSED"):format(checks))
