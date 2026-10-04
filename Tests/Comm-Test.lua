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
    world.log[#world.log + 1] = { from = session.character.name, type = messageType, distribution = distribution, target = target }
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
    local AceDB = {
        New = function(_, _, defaults)
            account.saved = account.saved or { global = copy(defaults.global), profile = copy(defaults.profile) }
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

local function login(acc, c)
    assert(not online(c.name), c.name .. " is already online")
    local session = { account = acc, character = c, frames = {}, online = true, ns = {} }
    c.session = session
    session.env = newEnvironment(session)
    for _, chunk in ipairs(chunks) do
        setfenv(chunk, session.env)
        chunk("WhosWho", session.ns)
    end
    fire(session, "ADDON_LOADED", "WhosWho")
    fire(session, "PLAYER_LOGIN")
    -- The friend list arrives after login.
    fire(session, "FRIENDLIST_UPDATE")
    return session
end

local function logout(session)
    fire(session, "PLAYER_LOGOUT")
    session.online = false
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

local function state(session, guid)
    local _, entry = session.ns.People.Find(guid)
    return entry and entry.state
end

-- Characters -------------------------------------------------------------------------------------

local GUILD = "22835221"
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
check(sent({ type = "REC" }) == 0, "a REC waits a few seconds after a change")
run(5)
check(sent({ from = "Ann Main", type = "REC", distribution = "GUILD" }) == 1, "a new revision goes to the guild")
check(sent({ from = "Ann Main", type = "REC", target = "Dan Main" }) == 1, "and to an online friend outside the guild")
check(sent({ from = "Ann Main", type = "REC", target = "Bob Main" }) == 0, "a friend in the guild gets no copy of their own")
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
run(10)
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
run(10)
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

-- An alt ---------------------------------------------------------------------------------------------

logout(ann)
ann = login(annAccount, annAlt)
run(1)
check(sent({ from = "Ann Alt", type = "ANNOUNCE" }) == 0, "an unlinked character does not announce")
slash(ann, "link")
run(10)
check(bob.ns.People.Find(annAlt.guid) == annId and state(bob, annAlt.guid) == "listed", "a new alt arrives listed")
logout(ann)
run(1)
check(state(bob, annAlt.guid) == "confirmed", "its logout announcement confirms it")

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

-- Removing a character while a holder is offline -------------------------------------------------------

logout(bob)
logout(ann)
ann = login(annAccount, annAlt)
slash(ann, "unlink")
-- Past the 30 seconds in which a GET from a guild member is taken as answered by the guild REC of that change.
run(40)
bob = login(bobAccount, bobMain)
run(1)
check(bob.ns.People.Find(annAlt.guid) == annId, "a player offline at the removal still lists the character")
clearLog()
levelUp(ann)
run(10)
check(sent({ from = "Bob Main", type = "GET" }) == 1 and bob.ns.People.Find(annAlt.guid) == nil
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
check(bob.ns.People.Get(annId) == nil and bob.ns.People.Find(annMain.guid) == nil,
    "the last removed character's announcement makes others forget the identity")

clearLog()
slash(dan, "nick Danny")
run(10)
check(sent({ from = "Dan Main" }) == 0, "a change while nothing was ever linked sends nothing")

if failures > 0 then
    print(("%d of %d checks FAILED"):format(failures, checks))
    os.exit(1)
end
print(("ALL %d COMM CHECKS PASSED"):format(checks))
