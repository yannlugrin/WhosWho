local _, ns = ...
---@cast ns WhosWho.Namespace

-- Signature verification queue for received records, identity records and guild settings: one record at a time,
-- spread over frames.

---@class WhosWho.RecordVerification
local RecordVerification = {}
ns.RecordVerification = RecordVerification

-- At 16 bits per slice, one verification takes about 33 frames of at most 21 ms each (build 1.60.1).
local SLICE_BITS = 16

---A kind of signed record: Record for identity records, GuildSettings for guild settings.
---@class WhosWho.SignedFormat
---@field Canonical fun(signedRecord: table): string the signed bytes
---@field Verify fun(signedRecord: table): boolean

---@class WhosWho.QueuedRecord
---@field signedRecord table
---@field format WhosWho.SignedFormat
---@field key string canonical bytes and signature: what the result is about
---@field onVerified fun(signedRecord: table)

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
            return verification.format.Verify(verification.signedRecord)
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
---@param signedRecord table structure validated
---@param format WhosWho.SignedFormat
---@param onVerified fun(signedRecord: table)
function RecordVerification.Queue(signedRecord, format, onVerified)
    local key = format.Canonical(signedRecord) .. signedRecord.sig
    if results[key] ~= nil then
        if results[key] then onVerified(signedRecord) end
        return
    end
    if queued[key] then return end

    queued[key] = true
    queue[#queue + 1] = { signedRecord = signedRecord, format = format, key = key, onVerified = onVerified }
    frame:Show()
end
