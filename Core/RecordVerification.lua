local _, ns = ...
---@cast ns WhosWho.Namespace
local Record = ns.Record

-- Signature verification queue for received records: one record at a time, spread over frames.

---@class WhosWho.RecordVerification
local RecordVerification = {}
ns.RecordVerification = RecordVerification

-- At 16 bits per slice, one verification takes about 33 frames of at most 21 ms each (build 1.60.1).
local SLICE_BITS = 16

---@class WhosWho.QueuedRecord
---@field signedRecord WhosWho.SignedIdentityRecord
---@field key string canonical bytes and signature: what the result is about
---@field onVerified fun(signedRecord: WhosWho.SignedIdentityRecord)

---@type WhosWho.QueuedRecord[]
local queue = {}
---@type table<string, boolean> by key, for the session
local results = {}
---@type table<string, true> keys in the queue or running
local queued = {}
---@type thread?
local running

local frame = CreateFrame("Frame")
frame:Hide()

local function finish(queuedRecord, signatureValid)
    running = nil
    queued[queuedRecord.key] = nil
    results[queuedRecord.key] = signatureValid
    table.remove(queue, 1)
    if not queue[1] then frame:Hide() end
    if signatureValid then queuedRecord.onVerified(queuedRecord.signedRecord) end
end

frame:SetScript("OnUpdate", function()
    local verification = queue[1]
    if not running then
        running = coroutine.create(function()
            ns.Crypto.Ed25519.SetSlicing(SLICE_BITS)
            return Record.Verify(verification.signedRecord)
        end)
    end

    local success, returned = coroutine.resume(running)
    if not success then
        finish(verification, false)
        geterrorhandler()(returned)
    elseif coroutine.status(running) == "dead" then
        finish(verification, returned)
    end
end)

---Verifies a record's signature in the background and calls onVerified once it holds. A record already verified this
---session is answered at once; one already in the queue is not queued again.
---@param signedRecord WhosWho.SignedIdentityRecord structure validated
---@param onVerified fun(signedRecord: WhosWho.SignedIdentityRecord)
function RecordVerification.Queue(signedRecord, onVerified)
    local key = Record.Canonical(signedRecord) .. signedRecord.sig
    if results[key] ~= nil then
        if results[key] then onVerified(signedRecord) end
        return
    end
    if queued[key] then return end

    queued[key] = true
    queue[#queue + 1] = { signedRecord = signedRecord, key = key, onVerified = onVerified }
    frame:Show()
end
