-- luacheck: allow defined, ignore 121 122 131 143
-- Offline suite: clients exchanging announcements, GETs and RECs over a simulated add-on channel. Each logged-in
-- character runs the shipping files in its own environment; accounts keep their saved data between sessions.
-- Run from the add-on root: lua Tests/Comm-Test.lua [root]

local root = (arg and arg[1]) or "."
dofile(root .. "/Tests/Support/Bit.lua")

local FILES = {
    "Crypto/SHA512.lua", "Crypto/Ed25519.lua",
    "Core/Core.lua", "Core/Store.lua", "Core/Record.lua", "Core/Identity.lua", "Core/AutomaticChanges.lua",
    "Core/People.lua", "Core/Resolver.lua", "Core/RecordVerification.lua",
    "Comm/Codec.lua", "Comm/Scopes.lua", "Comm/Protocol.lua",
}
local chunks = {}
for i, file in ipairs(FILES) do chunks[i] = assert(loadfile(root .. "/" .. file)) end

local failures, checks = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL " .. label)
    end
end

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- World ------------------------------------------------------------------------------------------

local world = { clock = 1000, timers = {}, messages = {}, log = {}, characters = {}, group = {} }

local function character(name, guid, classID, guild)
    local c = { name = name, guid = guid, classID = classID, level = 10, guild = guild, friends = {} }
    world.characters[name] = c
    return c
end

local function online(name)
    local c = world.characters[name]
    return c and c.session and c.session.online and c.session or nil
end

local function guildMembers(guild)
    local members = {}
    for _, c in pairs(world.characters) do
        if guild and c.guild == guild then members[#members + 1] = c end
    end
    table.sort(members, function(a, b) return a.name < b.name end)
    return members
end

local function inGroup(c)
    for _, member in ipairs(world.group) do
        if member == c then return true end
    end
    return false
end

-- Records serialized by one client and read by another: the libraries themselves are not under test.
local serialized = {}
local LibSerialize = {
    Serialize = function(_, value)
        serialized[#serialized + 1] = copy(value)
        return "S" .. #serialized
    end,
    Deserialize = function(_, text)
        local value = serialized[tonumber(text:match("^S(%d+)$") or 0)]
        return value ~= nil, copy(value)
    end,
}
local function same(_, text) return text end
local LibDeflate = {
    CompressDeflate = same, DecompressDeflate = same,
    EncodeForWoWAddonChannel = same, DecodeForWoWAddonChannel = same,
}

local function send(session, text, distribution, target, onSent)
    local messageType = text:match("^%d+ (%u+)")
    world.log[#world.log + 1] = {
        from = session.character.name, type = messageType, distribution = distribution, target = target, text = text,
    }
    world.messages[#world.messages + 1] = {
        from = session, text = text, distribution = distribution, target = target, onSent = onSent,
    }
end

local function deliver(message)
    local sender = message.from.character
    if message.onSent then message.onSent() end

    local receivers = {}
    if message.distribution == "GUILD" then
        for _, c in ipairs(guildMembers(sender.guild)) do receivers[#receivers + 1] = online(c.name) end
    elseif message.distribution == "PARTY" or message.distribution == "RAID" then
        for _, c in ipairs(world.group) do receivers[#receivers + 1] = online(c.name) end
    elseif message.distribution == "WHISPER" then
        -- Offline: lost without a word.
        receivers[1] = online(message.target)
    end
    for _, session in ipairs(receivers) do
        if session.comm then session.comm("WhosWho", message.text, message.distribution, sender.name) end
    end
end

local function busyFrames()
    local frames = {}
    for _, c in pairs(world.characters) do
        local session = c.session
        if session and session.online then
            for _, frame in ipairs(session.frames) do
                if frame.shown and frame.scripts.OnUpdate then frames[#frames + 1] = frame end
            end
        end
    end
    return frames
end

-- Delivers messages and runs OnUpdate scripts (signature verification) until nothing moves.
local function settle()
    for _ = 1, 10000 do
        local message = table.remove(world.messages, 1)
        if message then
            deliver(message)
        else
            local frames = busyFrames()
            if not frames[1] then return end
            for _, frame in ipairs(frames) do frame.scripts.OnUpdate(frame, 0.016) end
        end
    end
    error("the world never settled")
end

local function run(seconds)
    local target = world.clock + seconds
    settle()
    while true do
        table.sort(world.timers, function(a, b) return a.at < b.at end)
        local timer = world.timers[1]
        if not timer or timer.at > target then break end
        table.remove(world.timers, 1)
        world.clock = timer.at
        if timer.session.online then timer.fn() end
        settle()
    end
    world.clock = target
end

-- Sessions ---------------------------------------------------------------------------------------

local function fire(session, event, ...)
    for _, frame in ipairs(session.frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end

-- Saved values missing, from the defaults.
local function fillDefaults(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = copy(v)
        elseif type(v) == "table" and type(saved[k]) == "table" then
            fillDefaults(saved[k], v)
        end
    end
end

-- Saved values equal to their defaults removed, empty tables included, as AceDB does on PLAYER_LOGOUT.
local function removeDefaults(saved, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" and type(saved[k]) == "table" then
            removeDefaults(saved[k], v)
            if next(saved[k]) == nil then saved[k] = nil end
        elseif saved[k] == v then
            saved[k] = nil
        end
    end
end

local function newEnvironment(session)
    local account, c = session.account, session.character
    local env = setmetatable({}, { __index = _G })

    local function unitCharacter(unit)
        if unit == "player" then return c end
        local i = tonumber(unit:match("^party(%d+)$") or 0)
        local others = {}
        for _, member in ipairs(world.group) do
            if member ~= c then others[#others + 1] = member end
        end
        return others[i]
    end

    env.print = function() end
    env.time = function() return world.clock end
    env.GetTime = function() return world.clock end
    env.GetServerTime = os.time
    env.debugprofilestop = os.clock
    env.fastrandom = math.random
    env.GetCursorPosition = function() return 0.5, 0.25 end
    env.strlenutf8 = function(s) return select(2, s:gsub("[^\128-\191]", "")) end
    env.geterrorhandler = function() return error end
    env.Enum = { GameRule = {} }
    env.SlashCmdList = {}
    env.C_AddOns = { GetAddOnMetadata = function() return nil end }
    env.C_CreatureInfo = { GetClassInfo = function(classID) if classID <= 13 then return {} end end }

    env.UnitGUID = function(unit)
        local u = unitCharacter(unit)
        return u and u.guid
    end
    env.UnitFullName = function(unit)
        local u = unitCharacter(unit)
        if not u then return nil end
        return u.name:match("^(%S+) (.+)$")
    end
    env.UnitClass = function() return nil, nil, c.classID end
    env.UnitLevel = function() return c.level end
    env.IsResting = function() return c.resting == true end
    env.UnitAffectingCombat = function() return c.inCombat == true end
    env.Logout, env.Quit = function() end, function() end
    env.StaticPopupDialogs = { CAMP = { OnCancel = function() end }, QUIT = { OnHide = function() end } }
    env.hooksecurefunc = function(target, name, hook)
        if type(target) == "string" then target, name, hook = env, target, name end
        local original = target[name]
        target[name] = function(...)
            original(...)
            hook(...)
        end
    end

    env.IsInGuild = function() return c.guild ~= nil end
    env.C_Club = { GetGuildClubId = function() return c.guild end }
    env.GetNumGuildMembers = function() return #guildMembers(c.guild) end
    env.GetGuildRosterInfo = function(i)
        local member = guildMembers(c.guild)[i]
        local info = { member.name }
        info[17] = member.guid
        return unpack(info, 1, 17)
    end
    env.C_GuildInfo = {
        GuildRoster = function()
            world.timers[#world.timers + 1] = { at = world.clock, session = session, fn = function() fire(session, "GUILD_ROSTER_UPDATE") end }
        end,
        MemberExistsByName = function(name)
            for _, member in ipairs(guildMembers(c.guild)) do
                if member.name == name then return true end
            end
            return false
        end,
    }

    local function friendInfo(friend)
        return { name = friend.name, guid = friend.guid, connected = online(friend.name) ~= nil }
    end
    env.C_FriendList = {
        GetNumFriends = function() return #c.friends end,
        GetFriendInfoByIndex = function(i) return c.friends[i] and friendInfo(c.friends[i]) end,
        GetFriendInfo = function(name)
            for _, friend in ipairs(c.friends) do
                if friend.name == name then return friendInfo(friend) end
            end
            return nil
        end,
    }

    env.IsInGroup = function() return inGroup(c) end
    env.IsInRaid = function() return false end
    env.GetNumSubgroupMembers = function() return inGroup(c) and #world.group - 1 or 0 end
    env.GetNumGroupMembers = function() return inGroup(c) and #world.group or 0 end

    env.C_Timer = {
        After = function(seconds, fn)
            world.timers[#world.timers + 1] = { at = world.clock + seconds, session = session, fn = fn }
        end,
    }
    env.C_ChatInfo = {
        SendAddonMessage = function(_, text, distribution, target) send(session, text, distribution, target) end,
    }
    env.CreateFrame = function()
        local frame = { events = {}, scripts = {}, shown = true }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(name, fn) self.scripts[name] = fn end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        session.frames[#session.frames + 1] = frame
        return frame
    end

    local AceComm = {
        Embed = function(_, target)
            function target:RegisterComm(_, method) session.comm = method end
            function target:SendCommMessage(_, text, distribution, name, _, callbackFn, callbackArg)
                send(session, text, distribution, name, callbackFn and function() callbackFn(callbackArg, #text, #text) end)
            end
        end,
    }
    -- Like AceDB: the defaults fill what the saved data lacks, and PLAYER_LOGOUT removes them again before the
    -- add-on's own handler runs (see logout).
    local AceDB = {
        New = function(_, _, defaults)
            account.saved = account.saved or { global = {}, profile = {} }
            fillDefaults(account.saved.global, defaults.global)
            fillDefaults(account.saved.profile, defaults.profile)
            session.defaults = defaults
            return account.saved
        end,
    }
    local AceLocale = {
        GetLocale = function() return setmetatable({}, { __index = function(_, key) return key end }) end,
    }
    local libraries = {
        ["AceComm-3.0"] = AceComm, ["AceDB-3.0"] = AceDB, ["AceLocale-3.0"] = AceLocale,
        LibSerialize = LibSerialize, LibDeflate = LibDeflate,
    }
    env.LibStub = function(name) return assert(libraries[name], name) end

    return env
end

local function account(name)
    return { name = name }
end

-- how: nil for a login long after the account's last logout (the world's clock does not move while every character of
-- the account is offline), "relog" for a login right after it, "reload" for a /reload, as PLAYER_ENTERING_WORLD tells.
local function login(acc, c, how)
    assert(not online(c.name), c.name .. " is already online")
    local identity = acc.saved and acc.saved.global.identity
    if not how and identity and identity.lastLogout then identity.lastLogout.at = identity.lastLogout.at - 3600 end
    -- The UI files are not loaded: no first-login prompt.
    local session = { account = acc, character = c, frames = {}, online = true, ns = { IdentityDialogs = { AskToLink = function() end }, Launcher = { Register = function() end }, Tooltip = { Register = function() end } } }
    c.session = session
    session.env = newEnvironment(session)
    for _, chunk in ipairs(chunks) do
        setfenv(chunk, session.env)
        chunk("WhosWho", session.ns)
    end
    fire(session, "ADDON_LOADED", "WhosWho")
    fire(session, "PLAYER_LOGIN")
    fire(session, "PLAYER_ENTERING_WORLD", how ~= "reload", how == "reload")
    -- The friend list arrives after login.
    fire(session, "FRIENDLIST_UPDATE")
    return session
end

-- PLAYER_LOGOUT, after AceDB removed the defaults: a logout's last event, or a /reload's.
local function endSession(session)
    local saved, defaults = session.account.saved, session.defaults
    removeDefaults(saved.global, defaults.global)
    removeDefaults(saved.profile, defaults.profile)
    fire(session, "PLAYER_LOGOUT")
    session.online = false
end

-- A logout: the countdown starts, then runs out.
local function logout(session)
    fire(session, "PLAYER_CAMPING")
    endSession(session)
end

-- A /reload: PLAYER_LOGOUT, then the same character loads again.
local function reload(session)
    endSession(session)
    return login(session.account, session.character, "reload")
end

-- Ends a session without PLAYER_LOGOUT, like a crash or a lost connection.
local function disconnect(session)
    session.online = false
end

local function slash(session, input)
    session.env.SlashCmdList.WHOSWHO(input)
end

local function levelUp(session)
    session.character.level = session.character.level + 1
    fire(session, "PLAYER_LEVEL_UP", session.character.level)
end

-- A chat whisper: CHAT_MSG_WHISPER_INFORM on the sender's client, CHAT_MSG_WHISPER on the receiver's (name and GUID of
-- the other player in arguments 2 and 12).
local function whisper(session, c)
    fire(session, "CHAT_MSG_WHISPER_INFORM", "hi", c.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, c.guid)
    local receiver = online(c.name)
    if receiver then
        local from = session.character
        fire(receiver, "CHAT_MSG_WHISPER", "hi", from.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, from.guid)
    end
end

local function sent(filter)
    local n = 0
    for _, entry in ipairs(world.log) do
        local match = true
        for k, v in pairs(filter) do
            if entry[k] ~= v then match = false end
        end
        if match then n = n + 1 end
    end
    return n
end

local function clearLog()
    world.log = {}
end

-- The ID of the person holding the character on that client, nil when none does.
local function holderId(session, guid)
    local person = session.ns.People.Find(guid)
    return person and person.id
end

local function state(session, guid)
    local _, entry = session.ns.People.Find(guid)
    return entry and entry.state
end

-- Characters -------------------------------------------------------------------------------------

local GUILD = 22835221
local WARRIOR, MAGE, PRIEST, ROGUE = 1, 8, 5, 4

local annAccount, bobAccount, catAccount, danAccount, eveAccount =
    account("Ann"), account("Bob"), account("Cat"), account("Dan"), account("Eve")
local annMain = character("Ann Main", "Player-1-0000A001", MAGE, GUILD)
local annAlt = character("Ann Alt", "Player-1-0000A002", PRIEST, GUILD)
local bobMain = character("Bob Main", "Player-1-0000B001", WARRIOR, GUILD)
local catMain = character("Cat Main", "Player-1-0000C001", ROGUE, GUILD)
local danMain = character("Dan Main", "Player-1-0000D001", MAGE)
local eveMain = character("Eve Main", "Player-1-0000E001", MAGE)
annMain.friends = { danMain, bobMain }

-- A first link -----------------------------------------------------------------------------------

local dan = login(danAccount, danMain)
local ann = login(annAccount, annMain)
run(1)
check(sent({ from = "Ann Main" }) == 0, "nothing goes out before a character is linked")
slash(ann, "link")
run(1)
check(sent({ from = "Ann Main" }) == 0, "a change waits")
run(30)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1, "a new revision is announced to the guild")
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Dan Main" }) == 1, "and to an online friend outside the guild")
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Bob Main" }) == 0, "a friend in the guild gets no copy of their own")
check(sent({ from = "Ann Main", type = "REC" }) == 0, "no REC goes out without a GET")
local annId = ann.ns.Identity.Id()
check(ann.ns.People.Get(annId) == nil, "my own REC coming back from the guild is ignored")

-- Login announcement, GET, REC, confirmation -----------------------------------------------------------

local bob = login(bobAccount, bobMain)
run(1)
logout(ann)
clearLog()
ann = login(annAccount, annMain)
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1, "login announcement on the guild")
check(sent({ from = "Bob Main", type = "GET", target = "Ann Main" }) == 1, "a guild member without the record asks for it")
check(state(bob, annMain.guid) == nil, "the confirmation waits for the record")
run(5)
check(sent({ from = "Ann Main", type = "REC", target = "Bob Main", distribution = "WHISPER" }) == 1,
    "a requester alone on the guild channel gets the REC by whisper")
check(sent({ from = "Ann Main", type = "REC", distribution = "GUILD" }) == 0, "no guild REC for one requester")
check(state(bob, annMain.guid) == "confirmed", "record verified and accepted, then the waiting confirmation applied")
check(bob.ns.People.Nickname(annId) == "Ann Main", "Bob knows Ann by her main's name")

fire(bob, "GUILD_ROSTER_UPDATE")
check(select(2, bob.ns.People.Find(annMain.guid)).guild == GUILD, "the roster gives a confirmed character its guild")

-- Level-up --------------------------------------------------------------------------------------------

clearLog()
levelUp(ann)
run(1)
check(select(2, bob.ns.People.Find(annMain.guid)).level == 11, "a level-up announcement updates the level")
check(sent({ type = "GET" }) == 0, "same revision: no GET")

-- A GET answered by a REC that just left is not answered again ---------------------------------------

clearLog()
bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
run(10)
check(sent({ from = "Ann Main", type = "REC" }) == 0, "a GET within 30 seconds of the REC reaching that player is ignored")
run(30)
bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
run(10)
check(sent({ from = "Ann Main", type = "REC", target = "Bob Main" }) == 1, "later, a GET is answered again")

-- Two requesters on the guild share one REC ----------------------------------------------------------

local cat = login(catAccount, catMain)
run(1)
slash(ann, "nick Annie")
-- The revision change reaches both; the next ones come from GETs.
run(30)
check(bob.ns.People.Nickname(annId) == "Annie" and cat.ns.People.Nickname(annId) == "Annie",
    "a change of revision reaches every guild member online")

clearLog()
logout(bob)
logout(cat)
run(1)
bob = login(bobAccount, bobMain)
cat = login(catAccount, catMain)
run(1)
ann.ns.Protocol.LockRecordSending()
slash(ann, "nick Ann")
run(10)
check(sent({ from = "Ann Main", type = "REC" }) == 0, "nothing goes out while record sending is locked")
levelUp(ann)
run(1)
check(sent({ type = "GET", target = "Ann Main" }) == 2, "both guild members ask for the new revision")
ann.ns.Protocol.UnlockRecordSending()
run(20)
check(sent({ from = "Ann Main", type = "REC", distribution = "GUILD" }) == 1, "the change goes to the guild once unlocked")
check(sent({ from = "Ann Main", type = "REC", distribution = "WHISPER", target = "Bob Main" }) == 0,
    "requesters reached by that REC leave the queue")
check(bob.ns.People.Nickname(annId) == "Ann" and cat.ns.People.Nickname(annId) == "Ann", "both have the new revision")

clearLog()
bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
cat.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
run(40)
check(sent({ from = "Ann Main", type = "REC" }) == 0, "GETs that crossed a guild REC are ignored")
bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
cat.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
run(10)
check(sent({ from = "Ann Main", type = "REC", distribution = "GUILD" }) == 1
    and sent({ from = "Ann Main", type = "REC", distribution = "WHISPER" }) == 0,
    "two requesters on the guild get one REC there")

-- One wait for every REC ----------------------------------------------------------------------------

local function getFromBob()
    bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
end

run(40)
clearLog()
slash(ann, "nick Ann Waits")
run(5)
getFromBob()
run(5)
check(sent({ from = "Ann Main", type = "REC" }) == 0, "a GET does not bring forward the wait of a change")
run(6)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1
    and sent({ from = "Ann Main", type = "REC", target = "Bob Main" }) == 1,
    "the change is announced 15 seconds after it, and the waiting GET is answered then")

run(40)
clearLog()
slash(ann, "nick Ann Waits More")
run(13)
getFromBob()
run(3)
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 0 and sent({ from = "Ann Main", type = "REC" }) == 0,
    "a GET with less than 5 seconds left pushes the send back")
run(3)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1
    and sent({ from = "Ann Main", type = "REC", target = "Bob Main" }) == 1, "then everything goes out")

run(40)
clearLog()
getFromBob()
for _ = 1, 75 do
    run(4)
    getFromBob()
end
run(1)
check(sent({ from = "Ann Main", type = "REC", target = "Bob Main" }) == 1,
    "GETs that keep coming delay the answer by 300 seconds at most")

-- An alt ---------------------------------------------------------------------------------------------

logout(ann)
ann = login(annAccount, annAlt)
run(1)
check(sent({ from = "Ann Alt", type = "ANNOUNCE" }) == 0, "an unlinked character does not announce")
clearLog()
slash(ann, "link")
run(30)
check(holderId(bob, annAlt.guid) == annId and state(bob, annAlt.guid) == "confirmed"
    and select(2, bob.ns.People.Find(annAlt.guid)).level == annAlt.level,
    "an alt linked while played arrives confirmed, with its level: its announcement waits for the record")
check(sent({ type = "GET", target = "Ann Alt" }) == 2 and sent({ from = "Ann Alt", type = "REC", distribution = "GUILD" }) == 1
    and sent({ from = "Ann Alt", type = "REC" }) == 1,
    "the guild members ask for the new revision, and get one REC on the guild")
logout(ann)
run(1)

-- Asking again --------------------------------------------------------------------------------------

ann = login(annAccount, annMain)
run(1)
slash(ann, "nick Ann Again")
clearLog()
disconnect(ann)
ann = login(annAccount, annMain)
run(1)
check(sent({ from = "Bob Main", type = "GET" }) == 1, "an announcement with a newer revision is answered by a GET")
disconnect(ann)
run(61)
check(sent({ from = "Bob Main", type = "GET" }) == 2, "without a REC, the GET is sent once more after 60 seconds")
run(120)
check(sent({ from = "Bob Main", type = "GET" }) == 2, "and no more")

clearLog()
ann = login(annAccount, annMain)
run(1)
check(sent({ from = "Bob Main", type = "GET" }) == 1, "the next announcement asks again")
logout(ann)
run(120)
check(sent({ from = "Bob Main", type = "GET" }) == 1, "a logout announcement cancels the GET waiting for an answer")
check(state(bob, annMain.guid) == "confirmed" and select(2, bob.ns.People.Find(annMain.guid)).level == annMain.level,
    "the logout announcement is still a confirmation")

-- Strangers and forgeries ---------------------------------------------------------------------------

local eve = login(eveAccount, eveMain)
slash(eve, "link")
run(10)
local eveId = eve.ns.Identity.Id()
eve.ns.Protocol:SendCommMessage("WhosWho", eve.ns.Codec.RecordUpdate(eve.ns.Identity.SignedRecord()), "WHISPER", "Bob Main")
run(1)
check(bob.ns.People.Get(eveId) == nil, "a REC whispered by a stranger is ignored")

ann = login(annAccount, annMain)
run(10)
local forged = ann.ns.Identity.SignedRecord()
forged.rev, forged.nickname = forged.rev + 1, "Forged"
cat.ns.Protocol:SendCommMessage("WhosWho", cat.ns.Codec.RecordUpdate(forged), "GUILD")
run(1)
check(bob.ns.People.Nickname(annId) == "Ann Again", "a REC with a broken signature is refused")

-- Requesters in my guild and my group ----------------------------------------------------------------------

world.group = { annMain, bobMain, danMain }
ann.ns.settings.scopes.group = true
run(40)
clearLog()
bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
dan.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
run(10)
check(sent({ from = "Ann Main", type = "REC", distribution = "PARTY" }) == 1
    and sent({ from = "Ann Main", type = "REC", distribution = "GUILD" }) == 0
    and sent({ from = "Ann Main", type = "REC", distribution = "WHISPER" }) == 0,
    "alone in my guild but with another requester in my group: one REC on PARTY for both")

-- A and B in my guild, B and C in my group (the README's first example).
world.group = { annMain, bobMain, danMain }
run(40)
clearLog()
cat.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
dan.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
run(10)
check(sent({ from = "Ann Main", type = "REC", distribution = "GUILD" }) == 1
    and sent({ from = "Ann Main", type = "REC", distribution = "PARTY" }) == 0
    and sent({ from = "Ann Main", type = "REC", target = "Dan Main" }) == 1
    and sent({ from = "Ann Main", type = "REC" }) == 2,
    "two in my guild, one more in my group: one REC on GUILD and one whisper")

-- A and B in my guild, A, B and C in my group.
world.group = { annMain, bobMain, catMain, danMain }
run(40)
clearLog()
cat.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
bob.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
dan.ns.Protocol:SendCommMessage("WhosWho", "1 GET " .. annId, "WHISPER", "Ann Main")
run(10)
check(sent({ from = "Ann Main", type = "REC", distribution = "PARTY" }) == 1
    and sent({ from = "Ann Main", type = "REC" }) == 1,
    "everyone in my group, two also in my guild: one REC on PARTY only")
world.group = {}
ann.ns.settings.scopes.group = false

-- Sharing with an alt of a player my scopes allow --------------------------------------------------------

do
    local Scopes, settings = bob.ns.Scopes, bob.ns.settings
    check(Scopes.Allows("Ann Alt"), "Ann Alt is in my guild")
    annAlt.guild = nil
    check(Scopes.Allows("Ann Alt"), "out of my guild, Ann Alt is still allowed: Ann Main is confirmed in it")
    settings.scopes.guild = false
    check(not Scopes.Allows("Ann Alt"), "not once the Guild scope is off")
    settings.scopes.guild = true
    local annMainEntry, annAltEntry = select(2, bob.ns.People.Find(annMain.guid)), select(2, bob.ns.People.Find(annAlt.guid))
    annAltEntry.guild, annMainEntry.state = nil, "listed"
    check(not Scopes.Allows("Ann Alt"), "the guild of a character only listed does not count")
    annMainEntry.state = "confirmed"
    annAlt.guild = GUILD
    check(not Scopes.Allows("Eve Main"), "a stranger is not allowed")
end

-- Whispers ----------------------------------------------------------------------------------------------

do
    local function eveSends(text) eve.ns.Protocol:SendCommMessage("WhosWho", text, "WHISPER", "Bob Main") end
    local function eveAnnouncement() return eve.ns.Codec.Announcement(eveId, eve.ns.Identity.Revision(), eveMain.level, true) end
    local function eveRecord() return eve.ns.Codec.RecordUpdate(eve.ns.Identity.SignedRecord()) end

    bob.ns.settings.scopes.whispers = true
    clearLog()
    whisper(eve, bobMain)
    eveSends(eveAnnouncement())
    eveSends(eveRecord())
    run(1)
    check(sent({ from = "Bob Main", type = "GET" }) == 0 and bob.ns.People.Get(eveId) == nil,
        "a player who only whispered me is not asked for their record, and their REC is ignored")
    check(not bob.ns.Scopes.BroadcastAudience().names[1], "nor is in my audience")

    local whisperedAt = world.clock
    whisper(bob, eveMain)
    -- Their answer keeps my whisper.
    whisper(eve, bobMain)
    eveSends(eveAnnouncement())
    eveSends(eveRecord())
    run(1)
    check(sent({ from = "Bob Main", type = "GET" }) == 1 and state(bob, eveMain.guid) == "confirmed",
        "once I whisper them, they are asked and their REC is stored")
    check(select(2, bob.ns.People.Find(eveMain.guid)).whisperedAt == whisperedAt,
        "the stored character keeps when I whispered it")
    check(bob.ns.Scopes.BroadcastAudience().names[1] == "Eve Main" and not bob.ns.Scopes.LoginAudience().names[1],
        "and, whispered this session, in my broadcasts' audience, not in my login's")

    logout(bob)
    bob = login(bobAccount, bobMain)
    run(1)
    check(bob.ns.Scopes.Allows("Eve Main"), "after a reload, the saved whisper still allows the player")
    check(bob.ns.Scopes.SenderGuid("Eve Main", "WHISPER") == eveMain.guid, "and gives the sender's GUID")
    bob.ns.settings.scopes.whispers = false
    check(not bob.ns.Scopes.Allows("Eve Main"), "not once the Whispers scope is off")
    bob.ns.settings.scopes.whispers = true

    run(3 * 3600)
    check(not bob.ns.Scopes.Allows("Eve Main"), "past the whisper window, the player is no longer allowed")
    check(bob.ns.Scopes.SenderGuid("Eve Main", "WHISPER") == nil, "nor gives the sender's GUID")
    logout(bob)
    check(next(bobAccount.saved.global.whispers) == nil
        and select(2, bob.ns.People.Find(eveMain.guid)).whisperedAt == nil,
        "logout removes the whispers and clears the whisperedAt older than the window")
    bob = login(bobAccount, bobMain)
    run(1)
    bob.ns.settings.whisperHours = 168
    whisper(bob, eveMain)
    run(3 * 3600)
    check(bob.ns.Scopes.Allows("Eve Main"), "a longer window keeps the player allowed")
    bob.ns.settings.whisperHours = 3
    bob.ns.settings.scopes.whispers = false
end

-- Removing a character while a holder is offline -------------------------------------------------------

logout(bob)
logout(ann)
ann = login(annAccount, annAlt)
slash(ann, "unlink")
-- Past the change's wait, and the GETs its announcement brings.
run(70)
bob = login(bobAccount, bobMain)
run(1)
check(holderId(bob, annAlt.guid) == annId, "a player offline at the removal still lists the character")
clearLog()
levelUp(ann)
run(10)
check(sent({ from = "Bob Main", type = "GET" }) == 1 and not bob.ns.People.Exists(annAlt.guid)
    and bob.ns.People.Get(annId) ~= nil, "the removed character's announcement brings its removal")
clearLog()
levelUp(ann)
run(10)
check(sent({ from = "Ann Alt", type = "ANNOUNCE" }) > 0 and sent({ from = "Bob Main", type = "GET" }) == 0,
    "once the removal is known, the removed character's announcement asks nothing")

-- Unlinking every character -----------------------------------------------------------------------------

logout(bob)
logout(ann)
ann = login(annAccount, annMain)
slash(ann, "unlink")
run(10)
logout(ann)
bob = login(bobAccount, bobMain)
run(1)
check(bob.ns.People.Get(annId) ~= nil, "a player offline at the last removal still holds the identity")
login(annAccount, annMain)
run(10)
check(bob.ns.People.Get(annId) == nil and not bob.ns.People.Exists(annMain.guid),
    "the last removed character's announcement makes others forget the identity")

-- Debug messages -----------------------------------------------------------------------------------------

local printed = {}
bob.env.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
levelUp(annMain.session)
run(1)
check(not printed[1], "nothing printed while debug messages are off")
slash(bob, "debug on")
printed = {}
levelUp(annMain.session)
run(1)
local traced = false
for _, line in ipairs(printed) do
    if line:find("Received, GUILD Ann Main: 1 ANNOUNCE " .. annId, 1, true) then traced = true end
end
check(traced, "with debug messages on, a received announcement is printed")
slash(bob, "debug off")

clearLog()
slash(dan, "nick Danny")
run(10)
check(sent({ from = "Dan Main" }) == 0, "a change while nothing was ever linked sends nothing")

-- Reaching players who come later ------------------------------------------------------------------------

ann = annMain.session
slash(ann, "link")
slash(bob, "link")
run(30)

clearLog()
logout(bob)
bob = login(bobAccount, bobMain)
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 0, "an answer to a login waits")
run(5)
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Bob Main" }) == 1, "a login is answered with an announcement")
check(sent({ from = "Bob Main", type = "ANNOUNCE", distribution = "WHISPER" }) == 0, "an answer is not answered")

clearLog()
logout(bob)
bob = login(bobAccount, bobMain)
run(1)
logout(bob)
run(10)
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Bob Main" }) == 0,
    "a logout cancels the answer waiting for that player")
bob = login(bobAccount, bobMain)
run(10)

world.group = { annMain, bobMain }
ann.ns.settings.scopes.group, bob.ns.settings.scopes.group = true, true
clearLog()
fire(bob, "GROUP_ROSTER_UPDATE")
run(1)
check(sent({ from = "Bob Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1, "joining a group announces to it")
run(5)
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Bob Main" }) == 1, "a member answers")
clearLog()
fire(bob, "GROUP_ROSTER_UPDATE")
run(6)
check(sent({ type = "ANNOUNCE" }) == 0, "a change in a group I am already in announces nothing")
world.group = {}
fire(bob, "GROUP_ROSTER_UPDATE")
world.group = { annMain, bobMain }
fire(bob, "GROUP_ROSTER_UPDATE")
run(6)
check(sent({ from = "Bob Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1
    and sent({ from = "Ann Main", type = "ANNOUNCE", target = "Bob Main" }) == 1,
    "a group joined again is announced and answered again")

world.group = {}
fire(bob, "GROUP_ROSTER_UPDATE")
world.group = { annMain, bobMain, eveMain }
eve.ns.settings.scopes.group = true
clearLog()
fire(bob, "GROUP_ROSTER_UPDATE")
fire(eve, "GROUP_ROSTER_UPDATE")
run(6)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1
    and sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "WHISPER" }) == 0,
    "two members joining at once: one answer on PARTY")
world.group = {}
ann.ns.settings.scopes.group, bob.ns.settings.scopes.group, eve.ns.settings.scopes.group = false, false, false

-- A new session: Bob answered Eve joining the group, which already reached her with his revision.
logout(bob)
bob = login(bobAccount, bobMain)
run(10)
bob.ns.settings.scopes.whispers = true
clearLog()
whisper(bob, eveMain)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1,
    "whispering a player sends my announcement right away")
run(6)
check(sent({ from = "Eve Main", type = "ANNOUNCE", target = "Bob Main" }) == 0,
    "the player I whisper does not answer while they do not allow me")
whisper(bob, eveMain)
run(6)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1, "once per revision")
slash(bob, "nick Bobby")
run(30)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 2,
    "a change of revision goes to the person I whispered this session")
-- Eve whispered Bob more than the whisper window ago: she whispers him again, with her Whispers scope still off.
whisper(eve, bobMain)
eve.ns.settings.scopes.whispers = true
clearLog()
whisper(bob, eveMain)
run(6)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1, "a new revision is announced again")
check(sent({ from = "Eve Main", type = "ANNOUNCE", target = "Bob Main" }) == 1,
    "the player I whisper answers once they allow me (they whispered me before)")
whisper(eve, bobMain)
run(6)
check(sent({ from = "Eve Main", type = "ANNOUNCE", target = "Bob Main" }) == 1,
    "their answer already reached me: whispering me sends nothing more")
run(30 * 60)
clearLog()
whisper(bob, eveMain)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1,
    "30 minutes after my last announcement, whispering the player announces again")
clearLog()
whisper(bob, annMain)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Ann Main" }) == 0,
    "whispering a player my guild announcements reach sends nothing")
eve.ns.settings.scopes.whispers = false
clearLog()
whisper(cat, bobMain)
run(6)
check(sent({ from = "Bob Main", target = "Cat Main" }) == 0, "a whisper received sends nothing")

-- The people I whispered this session ------------------------------------------------------------------

clearLog()
levelUp(bob)
run(1)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1,
    "a level-up goes to the person I whispered this session")
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Ann Main" }) == 0,
    "not to a person I whispered that my guild announcement reaches")

bob = reload(bob)
run(10)
clearLog()
levelUp(bob)
run(1)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1, "a /reload keeps the session's whispers")

logout(bob)
clearLog()
bob = login(bobAccount, bobMain)
run(10)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 0,
    "the login announcement does not go to the person I whispered in an earlier session")
clearLog()
levelUp(bob)
run(1)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 0, "nor the next ones")

-- Eve plays an alt she links, and whispers Bob from it.
local eveAlt = character("Eve Alt", "Player-1-0000E002", PRIEST)
logout(eve)
eve = login(eveAccount, eveAlt)
slash(eve, "link")
eve.ns.settings.scopes.whispers = true
run(30)
whisper(bob, eveMain)
whisper(eve, bobMain)
whisper(bob, eveAlt)
run(30)
check(state(bob, eveAlt.guid) == "confirmed", "Eve's alt, whispered both ways, is confirmed")
clearLog()
levelUp(bob)
run(1)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Alt" }) == 1
    and sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 0,
    "one announcement per person, to the character I last whispered with")

do
    local whispers = bobAccount.saved.global.whispers
    local mainWhisper, altWhisper = whispers[eveMain.guid], whispers[eveAlt.guid]
    local altSentAt, altReceivedAt = altWhisper.sentAt, altWhisper.receivedAt
    altWhisper.sentAt, altWhisper.receivedAt = mainWhisper.sentAt - 1, nil
    clearLog()
    levelUp(bob)
    run(1)
    check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1
        and sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Alt" }) == 0,
        "with the main whispered last, the announcement goes to the main")
    altWhisper.sentAt, altWhisper.receivedAt = altSentAt, altReceivedAt

    local altEntry = select(2, bob.ns.People.Find(eveAlt.guid))
    altEntry.state = "listed"
    clearLog()
    levelUp(bob)
    run(1)
    check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Alt" }) == 0
        and sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Main" }) == 1,
        "a character not confirmed is never the one announced to")
    altEntry.state = "confirmed"
end

bobMain.friends = { eveAlt }
fire(bob, "FRIENDLIST_UPDATE")
clearLog()
levelUp(bob)
run(1)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Alt" }) == 1,
    "a person I whispered who is also my friend gets one announcement")
bobMain.friends = {}
fire(bob, "FRIENDLIST_UPDATE")

clearLog()
fire(bob, "PLAYER_CAMPING")
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Eve Alt" }) == 1, "the logout announcement goes to them too")
bob.env.StaticPopupDialogs.CAMP.OnCancel(nil, nil, "clicked")
run(1)
eve.ns.settings.scopes.whispers = false
bob.ns.settings.scopes.whispers = false
logout(eve)
eve = login(eveAccount, eveMain)
run(10)

-- Players new to my audience -----------------------------------------------------------------------------

-- Whether the last announcement matching the filter wants the receiver's.
local function lastWantsAnnouncement(filter)
    filter.type = "ANNOUNCE"
    for i = #world.log, 1, -1 do
        local entry, match = world.log[i], true
        for k, v in pairs(filter) do
            if entry[k] ~= v then match = false end
        end
        if match then return entry.text:match("^%d+ ANNOUNCE %S+ %d+ %d+ %d (%d)") == "1" end
    end
    return false
end

world.group = { annMain, bobMain }
bob.ns.settings.scopes.group = true
clearLog()
slash(ann, "scope group on")
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1
    and lastWantsAnnouncement({ from = "Ann Main", distribution = "PARTY" }),
    "turning the Group scope on in a group announces to it right away")
run(6)
check(sent({ from = "Bob Main", type = "ANNOUNCE", target = "Ann Main" }) == 1, "and the members answer")
clearLog()
slash(ann, "scope group on")
run(6)
check(sent({ type = "ANNOUNCE" }) == 0, "a scope already on sends nothing")
world.group = {}
slash(ann, "scope group off")
bob.ns.settings.scopes.group = false
clearLog()
slash(ann, "scope group on")
run(6)
check(sent({ from = "Ann Main" }) == 0, "outside a group, turning the Group scope on sends nothing")
slash(ann, "scope group off")

clearLog()
whisper(ann, eveMain)
slash(ann, "scope whispers on")
run(6)
check(sent({ from = "Ann Main" }) == 0, "turning the Whispers scope on sends nothing, even to a player whispered before")
slash(ann, "scope whispers off")

slash(ann, "scope friends off")
clearLog()
slash(ann, "scope friends on")
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Dan Main" }) == 1
    and lastWantsAnnouncement({ from = "Ann Main", target = "Dan Main" }),
    "turning the Friends scope on announces to an online friend outside the guild")
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Bob Main" }) == 0, "not to a friend the guild reaches")

clearLog()
annMain.friends = { danMain, bobMain, eveMain }
fire(ann, "FRIENDLIST_UPDATE")
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Eve Main" }) == 1
    and sent({ from = "Ann Main", type = "ANNOUNCE" }) == 1, "a friend added gets my announcement, the others nothing")
fire(ann, "FRIENDLIST_UPDATE")
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 1, "a friend list update without a friend added sends nothing")
annMain.friends = { danMain, bobMain }
fire(ann, "FRIENDLIST_UPDATE")
ann.ns.settings.scopes.friends = false
annMain.friends = { danMain, bobMain, eveMain }
fire(ann, "FRIENDLIST_UPDATE")
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 1, "a friend added sends nothing with the Friends scope off")
annMain.friends = { danMain, bobMain }
fire(ann, "FRIENDLIST_UPDATE")
ann.ns.settings.scopes.friends = true
run(6)

slash(bob, "scope guild off")
run(30)
clearLog()
slash(bob, "scope guild on")
run(10)
check(sent({ from = "Bob Main", type = "ANNOUNCE" }) == 0, "turning the Guild scope on waits, as any change of revision")
run(6)
check(sent({ from = "Bob Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1
    and lastWantsAnnouncement({ from = "Bob Main", distribution = "GUILD" }),
    "then its announcement on the guild wants the members' back")
run(6)
check(sent({ from = "Ann Main", type = "ANNOUNCE", target = "Bob Main" }) == 1, "and they answer")
clearLog()
slash(bob, "nick Bob Again")
run(30)
check(sent({ from = "Bob Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1
    and not lastWantsAnnouncement({ from = "Bob Main", distribution = "GUILD" }),
    "the next change of revision does not")

eveMain.guild = GUILD
clearLog()
fire(eve, "PLAYER_GUILD_UPDATE", "player")
check(sent({ from = "Eve Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1
    and lastWantsAnnouncement({ from = "Eve Main", distribution = "GUILD" }),
    "joining a guild announces to it right away")
run(6)
check(sent({ type = "ANNOUNCE", target = "Eve Main" }) == 2, "and the members answer")
clearLog()
fire(eve, "PLAYER_GUILD_UPDATE", "player")
run(6)
check(sent({ from = "Eve Main" }) == 0, "a guild update while already in it sends nothing")
eveMain.guild = nil
fire(eve, "PLAYER_GUILD_UPDATE", "player")

-- Logging out -----------------------------------------------------------------------------------------

-- Whether Ann's last announcement answers a GET.
local function lastAcceptsGet()
    for i = #world.log, 1, -1 do
        local entry = world.log[i]
        if entry.from == "Ann Main" and entry.type == "ANNOUNCE" then
            return entry.text:match("^%d+ ANNOUNCE %S+ %d+ %d+ (%d)") == "1"
        end
    end
    return false
end

world.group = { annMain, bobMain }
ann.ns.settings.scopes.group = true
run(40)
clearLog()
fire(ann, "PLAYER_CAMPING")
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1 and not lastAcceptsGet(),
    "the logout countdown announces my logout right away")
ann.env.StaticPopupDialogs.CAMP.OnCancel(nil, nil, "clicked")
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1, "a canceled logout sends nothing")
clearLog()
fire(ann, "PLAYER_QUITING")
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1,
    "after a canceled logout, the next one is announced again")
ann.env.StaticPopupDialogs.QUIT.OnHide({ timeleft = 12 })
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1, "a canceled quit sends nothing")
clearLog()
fire(ann, "PLAYER_CAMPING")
ann.env.StaticPopupDialogs.CAMP.OnCancel(nil, nil, "timeout")
logout(ann)
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1,
    "a countdown that runs out announces my logout once, PLAYER_LOGOUT not again")
ann = login(annAccount, annMain)
run(40)
clearLog()
ann.env.Logout()
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 0, "a logout outside a rested area waits for the countdown")
annMain.resting, annMain.inCombat = true, true
ann.env.Logout()
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 0, "a logout in combat announces nothing")
annMain.inCombat = false
ann.env.Quit()
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "PARTY" }) == 1 and not lastAcceptsGet(),
    "an immediate quit while resting announces my logout")
annMain.resting = false
ann.env.StaticPopupDialogs.QUIT.OnHide({ timeleft = 12 })
world.group = {}
ann.ns.settings.scopes.group = false

-- A quick relog ----------------------------------------------------------------------------------------

clearLog()
ann = reload(ann)
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 0, "a /reload announces nothing, at logout nor at login")
logout(ann)
clearLog()
ann = login(annAccount, annMain, "relog")
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE" }) == 0, "nor a login of the same character within 5 minutes")
logout(ann)
run(5 * 60)
clearLog()
ann = login(annAccount, annMain, "relog")
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1, "5 minutes later, the login announces")

-- Ann Alt, linked again, announces the same revision as Ann Main.
logout(ann)
local annAltSession = login(annAccount, annAlt, "relog")
slash(annAltSession, "link")
run(30)
logout(annAltSession)
clearLog()
ann = login(annAccount, annMain, "relog")
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1,
    "after another character's session, the login announces, even at the same revision")

slash(ann, "nick Ann Quick")
run(1)
logout(ann)
clearLog()
ann = login(annAccount, annMain, "relog")
run(1)
check(sent({ from = "Ann Main", type = "ANNOUNCE", distribution = "GUILD" }) == 1,
    "a change of revision not announced before the logout is announced at login")
run(30)

-- Announcement format -----------------------------------------------------------------------------------

do
    local Codec, id = ann.ns.Codec, ann.ns.Identity.Id()
    local decoded = Codec.Decode(Codec.Announcement(id, 3, 20, true, false))
    check(decoded and decoded.type == "ANNOUNCE" and decoded.rev == 3 and decoded.acceptsGet and not decoded.wantsAnnouncement,
        "an announcement decodes, its guild list revision 0")
    check(Codec.Decode("1 ANNOUNCE " .. id .. " 3 20 1 0 1791403200.9f2c41ab") ~= nil,
        "a guild list revision <time>.<hash> is accepted")
    check(Codec.Decode("1 ANNOUNCE " .. id .. " 3 20 1 0 0 later fields") ~= nil, "fields a later version adds are ignored")
    check(Codec.Decode("1 ANNOUNCE " .. id .. " 3 20 1 0") == nil, "an announcement without the guild list field is refused")
    check(Codec.Decode("1 ANNOUNCE " .. id .. " 3 20 1 0 x") == nil, "a malformed guild list revision is refused")
end

if failures > 0 then
    print(("%d of %d checks FAILED"):format(failures, checks))
    os.exit(1)
end
print(("ALL %d COMM CHECKS PASSED"):format(checks))
