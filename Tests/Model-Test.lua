-- luacheck: allow defined, ignore 121 122 131 143
-- Offline suite: name rules, Record, Identity, People, automatic changes and Resolver on a fresh data table.
-- Run from the add-on root: lua Tests/Model-Test.lua [root]

local root = (arg and arg[1]) or "."
dofile(root .. "/Tests/Support/Bit.lua")

-- Game functions read by the model. time() is a clock the tests set.
local clock = 0
GetCursorPosition = function() return 0.5, 0.25 end
debugprofilestop = os.clock
GetTime = os.clock
time = function() return clock end
GetServerTime = os.time
UnitGUID = function() return "Player-70-00000001" end
fastrandom = math.random
C_CreatureInfo = { GetClassInfo = function(classID) if classID <= 13 then return {} end end }
strlenutf8 = function(s) return select(2, s:gsub("[^\128-\191]", "")) end

local ns = {}
for _, file in ipairs({
    "Crypto/SHA512.lua", "Crypto/Ed25519.lua", "Core/Store.lua", "Core/Record.lua",
    "Core/Identity.lua", "Core/AutomaticChanges.lua", "Core/People.lua", "Core/Resolver.lua",
}) do
    assert(loadfile(root .. "/" .. file))("WhosWho", ns)
end

local failures, checks = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL " .. label)
    end
end

local function fresh()
    ns.data = ns.Store.NewData()
    ns.People.Reset()
end

local G1, G2, G3, G4 = "Player-70-0000000A", "Player-70-0000000B", "Player-70-0000000C", "Player-70-0000000D"
local NORMAL, PVP = ns.Record.RULESET.Normal, ns.Record.RULESET.PvP
local WARRIOR, ROGUE, PRIEST, MAGE = 1, 4, 5, 8

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Names ---------------------------------------------------------------------------------------

do
    local T = ns.Record
    check(T.CleanName("  Bob   the  Tank ") == "Bob the Tank", "name trimmed and collapsed")
    check(T.CleanName("Okrãg") == "Okrãg", "accented name kept")
    check(T.CleanName(string.rep("ã", 25)) ~= nil, "length counts characters, not bytes")
    check(select(2, T.CleanName("a")) == "short", "one character refused")
    check(select(2, T.CleanName(string.rep("x", 26))) == "long", "26 characters refused")
    check(select(2, T.CleanName("a|cffff0000b")) == "invalid", "escape sequence refused")
    check(select(2, T.CleanName("a\1b")) == "invalid", "control character refused")
    check(T.CleanName("a\nb") == "a b", "newline collapsed like any space")
    check(T.CleanName(nil) == nil and select(2, T.CleanName(nil)) == nil, "no name stays no name")
end

-- Identity and Record ----------------------------------------------------------------------------

fresh()
do
    local I = ns.Identity
    I.EnsureKeys()
    local id = I.Id()
    check(type(id) == "string" and #id == 64, "keys created, identity ID is 64 hex characters")
    I.EnsureKeys()
    check(I.Id() == id, "keys never replaced")

    I.Refresh(G2, "Okrãg Sorn", NORMAL, WARRIOR, 10)
    I.Refresh(G1, "Alt Two", PVP, MAGE, 10)
    check(not I.IsAsked(G1), "a new character is not asked yet")
    check(I.Revision() == 1, "touching an unlinked character keeps the revision")

    check(I.Nickname() == nil, "no nickname while no character is linked")
    I.Link(G2)
    I.Link(G1)
    check(I.Revision() == 3, "each link bumps the revision")
    check(I.LinkedCount() == 2, "linked characters counted")
    check(I.Main() == G2, "the first linked character becomes the main")
    check(I.Nickname() == "Okrãg Sorn", "without override, the nickname is the main character's name")
    I.Link(G1)
    check(I.Revision() == 3, "linking twice does not bump")
    I.Refresh(G1, "Alt Renamed", PVP, MAGE, 10)
    check(I.Revision() == 4, "renaming a linked character bumps")
    I.Refresh(G1, "Alt Renamed", NORMAL, MAGE, 10)
    check(I.Revision() == 5, "a linked character moving ruleset bumps")
    I.Refresh(G1, "Alt Renamed", NORMAL, ROGUE, 10)
    check(I.Revision() == 5 and I.Record().chars[G1].classID == MAGE, "class kept from the first touch")
    clock = 2
    I.Refresh(G1, "Alt Renamed", NORMAL, MAGE, 11)
    check(I.Revision() == 5, "level and last seen do not bump")
    check(ns.data.identity.chars[G1].level == 11 and ns.data.identity.chars[G1].lastSeen == 2,
        "level and last seen refreshed at login")
    clock = 3
    I.Seen(G1, 12)
    check(ns.data.identity.chars[G1].level == 12 and ns.data.identity.chars[G1].lastSeen == 3 and I.Revision() == 5,
        "level and last seen refreshed at logout, record unchanged")

    check(I.SetNickname("  Yann "), "nickname accepted")
    check(I.Nickname() == "Yann" and I.Revision() == 6, "nickname cleaned, revision bumped")
    check(not I.SetNickname("x"), "short nickname refused")
    check(I.Nickname() == "Yann", "refused nickname leaves the old one")
    check(I.SetNickname(nil) and I.Nickname() == "Okrãg Sorn" and I.Revision() == 7, "removing the override falls back to the main")
    check(I.Record().nickname == nil, "the main's name is not copied into the record's nickname")
    I.SetNickname("Yann")

    check(not I.SetMain(G4), "an unlinked character cannot be the main")
    check(I.SetMain(G1) and I.Main() == G1 and I.Revision() == 9, "main changed, revision bumped")
    check(I.Nickname() == "Yann", "the override stays when the main changes")

    local record = I.Record()
    check(ns.Record.Validate(record), "own record is valid: " .. tostring((select(2, ns.Record.Validate(record)))))
    check(count(record.chars) == 2 and record.chars[G1] and record.chars[G2], "linked characters in the record")

    local signed = I.SignedRecord()
    check(ns.Record.Verify(signed), "signed record verifies")
    local again = I.SignedRecord()
    check(again.sig == signed.sig, "signature reused while nothing changed")

    local tampered = I.SignedRecord()
    tampered.nickname = "Someone"
    check(not ns.Record.Verify(tampered), "changed nickname breaks the signature")
    tampered = I.SignedRecord()
    tampered.chars[G2].name = "Someone Else"
    check(ns.Record.Validate(tampered) and not ns.Record.Verify(tampered), "changed character breaks the signature")
    tampered = I.SignedRecord()
    tampered.junk = "added by a relay"
    check(not ns.Record.Verify(tampered), "an added field breaks the signature check")
    tampered = I.SignedRecord()
    tampered.chars[G2].junk = "added by a relay"
    check(not ns.Record.Verify(tampered), "a field added to a character breaks the signature check")

    I.Unlink(G1)
    check(count(I.Record().chars) == 1 and I.Revision() == 10, "unlinking removes the character and bumps")
    check(I.Main() == G2, "unlinking the main makes another linked character the main")
    check(I.SignedRecord().sig ~= signed.sig and ns.Record.Verify(I.SignedRecord()), "new revision signed again")

    I.Unlink(G2)
    check(I.Nickname() == nil, "no nickname once nothing is linked, even with an override")

end

-- Record validation -------------------------------------------------------------------------------

do
    local R = ns.Record
    local base = function()
        return { v = 1, id = string.rep("a", 64), rev = 2, main = G1,
            chars = { [G1] = { name = "A B", ruleset = NORMAL, classID = MAGE } } }
    end
    check(R.Validate(base()), "base record valid")
    local r = base(); r.id = "xyz"
    check(not R.Validate(r), "bad id refused")
    r = base(); r.rev = 1.5
    check(not R.Validate(r), "fractional revision refused")
    r = base(); r.chars["Creature-0-1"] = { name = "C", ruleset = NORMAL, classID = MAGE }
    check(select(2, R.Validate(r)) == "guid", "non-player GUID refused")
    r = base(); r.nickname = "a|r"
    check(not R.Validate(r), "nickname with escape refused")
    r = base(); r.chars[G1].name = "A\31B"
    check(not R.Validate(r), "separator byte in a name refused")
    r = base(); r.chars[G1].name = string.rep("ã", 12) .. " " .. string.rep("é", 12)
    check(R.Validate(r), "25-character name, accented letters included")
    r = base(); r.chars[G1].classID = "MAGE"
    check(select(2, R.Validate(r)) == "character", "class given by name refused")
    r = base(); r.chars[G1].ruleset = 99
    check(select(2, R.Validate(r)) == "character", "unknown ruleset refused")
    r = base(); r.chars[G1].classID = 99
    check(select(2, R.Validate(r)) == "character", "unknown class refused")
    r = base(); r.rev = 2 ^ 31
    check(select(2, R.Validate(r)) == "rev", "revision past the maximum refused")
    r = base(); r.chars[G1].ruleset = 0
    check(select(2, R.Validate(r)) == "character", "ruleset 0 refused")
    r = base(); r.chars[G1].name = string.rep("a", 26)
    check(not R.Validate(r), "26-character name refused")
    r = base(); r.v = 2
    check(not R.Validate(r), "unknown version refused")
    r = base(); r.main = nil
    check(not R.Validate(r), "missing main refused")
    r = base(); r.main = G2
    check(not R.Validate(r), "main outside the characters refused")
end

-- People: shared identities ------------------------------------------------------------------------

local function makeRecord(id, rev, guids, nickname)
    local chars = {}
    for i, g in ipairs(guids) do chars[g] = { name = "N" .. i, ruleset = NORMAL, classID = MAGE } end
    return { v = 1, id = id, rev = rev, nickname = nickname, main = guids[1], chars = chars }
end
local INFO = { name = "Tank Bob", ruleset = NORMAL, classID = WARRIOR }
local G5 = "Player-70-0000000E"

local function state(guid)
    local _, c = ns.People.Find(guid)
    return c and c.state
end

-- The index kept up to date change by change gives the same answers as one rebuilt from the saved data.
local function indexMatchesSavedData(guids)
    local before = {}
    for i, guid in ipairs(guids) do before[i] = ns.People.Find(guid) or false end
    ns.People.Reset()
    for i, guid in ipairs(guids) do
        if (ns.People.Find(guid) or false) ~= before[i] then return false end
    end
    return true
end

fresh()
do
    local P = ns.People
    local A, B = string.rep("a", 64), string.rep("b", 64)

    local Z = string.rep("f", 64)
    check(not P.Confirm(Z, G1, 10) and P.Get(Z) == nil, "a confirmation for an unknown identity leaves no data")
    check(P.Accept(makeRecord(A, 1, { G1, G2 }, "Ann")) == "updated", "record accepted")
    check(P.Find(G1) == A and state(G1) == "listed", "a listed character is trusted before any confirmation")
    check(P.Accept(makeRecord(A, 1, { G1, G2 }, "Ann")) == "stale", "same revision is stale")
    check(P.Nickname(A) == "Ann", "the player's own nickname")

    check(not P.Confirm(A, G3, 10), "a character the record does not list is not confirmed")
    check(P.Confirm(A, G2, 10) and state(G2) == "confirmed", "listed character confirmed")

    P.Accept(makeRecord(B, 1, { G2 }, "Bob"))
    check(P.Find(G2) == A and P.Get(B).chars[G2] == nil, "a character another identity holds is not taken by a later record")
    P.Confirm(B, G2, 10)
    check(P.Find(G2) == B and P.Get(A).chars[G2] == nil, "a confirmation moves the character; the other identity no longer has it")

    P.Accept(makeRecord(A, 2, { G2, G3 }, "Ann"))
    check(P.Get(A).chars[G1] == nil and P.Find(G1) == nil, "a character dropped from the record is gone")
    check(P.Get(A).chars[G2] == nil, "a new revision does not take back a character another identity holds")
    P.Confirm(A, G3, 10)
    P.Accept(makeRecord(A, 3, { G2, G3 }, "Ann"))
    check(state(G3) == "confirmed", "a confirmed character stays confirmed in a new revision")

    P.Reset()
    check(P.Find(G3) == A and P.Find(G2) == B, "index rebuilt from saved data")
    P.Forget(A)
    check(P.Find(G3) == nil and P.Find(G2) == B, "forgetting an identity")

    local C, D = string.rep("c", 64), string.rep("d", 64)
    clock = 30
    P.Confirm(B, G2, 25)
    check(P.Get(B).chars[G2].level == 25 and P.Get(B).chars[G2].lastSeen == 30,
        "a confirmation records the character's level and last seen")
    check(not P.Activity(G2, 20, 29), "older activity is ignored")
    check(P.Activity(G2, 26, 31) and P.Get(B).chars[G2].level == 26 and P.Get(B).chars[G2].lastSeen == 31,
        "newer activity from any source is kept")
    check(not P.Activity(G1, 10, 40), "activity for an unknown character is ignored")
    P.Accept(makeRecord(B, 2, { G2 }, "Bob"))
    check(P.Get(B).chars[G2].level == 26, "a new revision keeps the character's activity")
    local changeCount = #ns.AutomaticChanges.List()
    clock = 40
    check(P.Confirm(B, G2, 27) and P.Get(B).chars[G2].level == 27 and P.Get(B).chars[G2].lastSeen == 40
        and state(G2) == "confirmed" and P.Get(B).chars[G2].name == "N1" and #ns.AutomaticChanges.List() == changeCount,
        "a confirmed character's next confirmation only updates its activity")

    P.Accept(makeRecord(C, 1, { G5 }))
    P.Accept(makeRecord(D, 1, { G5 }))
    check(P.Find(G5) == C and P.Get(D).chars[G5] == nil, "listed by two records: the first one keeps it")
    P.Confirm(D, G5, 10)
    check(P.Find(G5) == D and state(G5) == "confirmed" and P.Get(C).chars[G5] == nil,
        "a confirmation takes a character the identity never held")
    check(indexMatchesSavedData({ G1, G2, G3, G4, G5 }), "index kept up to date: shared identities")
end

-- People: a main held by another identity ------------------------------------------------------------

fresh()
do
    local P, R = ns.People, ns.Resolver
    local A, B, C = string.rep("a", 64), string.rep("b", 64), string.rep("c", 64)
    P.Accept(makeRecord(A, 1, { G1, G2 }))
    P.Accept(makeRecord(B, 1, { G3, G1 }))
    P.Confirm(B, G1, 10)
    check(P.Find(G1) == B and P.Nickname(A) == "N1" and R.Resolve(G2) ~= nil,
        "an identity whose main another identity confirmed keeps its name and its other characters")

    P.Accept(makeRecord(C, 1, { G2, G4 }))
    check(P.Find(G2) == A and P.Nickname(C) == "N1" and R.Resolve(G4) ~= nil,
        "a record whose main another identity holds still gives a name")
end

-- People: a confirmation of a character in my manual identity ------------------------------------------

fresh()
do
    local P = ns.People
    local A, B = string.rep("a", 64), string.rep("b", 64)
    P.Accept(makeRecord(A, 1, { G1, G2 }))
    P.Accept(makeRecord(B, 1, { G3, G1 }))
    P.Accept(makeRecord(A, 2, { G2 }))
    local manual = P.Create(G1, INFO)
    P.AddCharacter(manual, G4, INFO)
    P.Rename(manual, "Tanky")
    check(P.Confirm(B, G1, 10) and P.Find(G1) == B and state(G1) == "confirmed", "the confirmed character moves to its player")
    check(P.Get(manual) == nil and P.Find(G4) == B and state(G4) == "added" and P.Get(B).customNickname == "Tanky",
        "my manual identity holding it merges into that player")
    local merge = ns.AutomaticChanges.List()[1]
    check(merge.kind == "merged" and merge.from.id == manual and merge.to.id == B and count(merge.chars) == 2,
        "a merge from a confirmation is an automatic change too")
    check(indexMatchesSavedData({ G1, G2, G3, G4 }), "index kept up to date: confirmation merge")
end

-- People: a confirmation before the record listing the character ----------------------------------------

fresh()
do
    local P = ns.People
    local A, B = string.rep("a", 64), string.rep("b", 64)
    P.Accept(makeRecord(A, 1, { G1 }))
    check(not P.Confirm(A, G2, 12) and P.Find(G2) == nil, "a new character's confirmation waits for the record")
    P.Accept(makeRecord(A, 2, { G1, G2 }))
    check(state(G2) == "confirmed" and select(2, P.Find(G2)).level == 12, "it applies when the revision listing it arrives")

    check(not P.Confirm(B, G3, 5) and P.Get(B) == nil, "a confirmation for an identity not received yet waits")
    P.Accept(makeRecord(B, 1, { G3 }))
    check(state(G3) == "confirmed", "it applies when the identity's first record arrives")
end

-- People: a player who unlinks every character ---------------------------------------------------------

fresh()
do
    local P = ns.People
    local A = string.rep("a", 64)
    local empty = { v = 1, id = A, rev = 2, chars = {} }
    check(ns.Record.Validate(empty), "a record without characters is valid")
    check(not ns.Record.Validate({ v = 1, id = A, rev = 2, main = G1, chars = {} }), "a main without characters refused")

    P.Accept(makeRecord(A, 1, { G1, G2 }, "Ann"))
    P.AddCharacter(A, G3, INFO)
    P.Rename(A, "Annie")
    check(P.Accept(empty) == "forgotten", "a revision without characters forgets the person")
    check(P.Get(A) == nil and P.Find(G1) == nil and P.Find(G3) == nil,
        "its characters, my nickname and my added alts are gone")
    check(P.Accept(makeRecord(A, 1, { G1, G2 }, "Ann")) == "stale" and P.Get(A) == nil,
        "an older copy relayed later does not bring the person back")
    check(P.Accept(makeRecord(A, 3, { G1 }, "Ann")) == "updated" and P.Find(G1) == A and ns.data.forgotten[A] == nil,
        "a newer revision with characters brings the player back")
end

-- People: manual persons and added characters ---------------------------------------------------------

fresh()
do
    local P = ns.People
    local A = string.rep("a", 64)
    P.Accept(makeRecord(A, 1, { G1 }, "Ann"))

    local BOB = { name = "Bob Main", ruleset = NORMAL, classID = WARRIOR }
    clock = 2
    local m1 = P.Create(G2, { name = "Bob Main", ruleset = NORMAL, classID = WARRIOR, level = 30 })
    check(select(2, P.Find(G2)).level == 30 and select(2, P.Find(G2)).lastSeen == 2,
        "a character I can see when I add it gets its level and last seen")
    check(m1 == "M1" and P.Find(G2) == m1 and state(G2) == "added", "manual person created from its first character")
    check(P.Get(m1).main == G2 and P.Nickname(m1) == "Bob Main", "first character is the main and gives the nickname")
    check(select(2, P.Create(G1, BOB)) == "taken", "a listed character cannot start a manual person")
    check(select(2, P.Create(G2, BOB)) == "taken", "a character of a manual person cannot start another one")
    check(select(2, P.Create("nope", BOB)) == "guid", "invalid GUID refused")

    check(P.AddCharacter(m1, G4, INFO) and P.Find(G4) == m1, "character added to a manual person")
    check(select(2, P.AddCharacter(m1, G1, INFO)) == "taken", "a listed character cannot be added elsewhere")
    check(select(2, P.AddCharacter(m1, G4, INFO)) == "taken", "a character already added cannot be added again")
    check(not P.Confirm(m1, G4, 10), "a manual person's character is never confirmed")

    check(P.Rename(m1, "Bobby") and P.Nickname(m1) == "Bobby", "my nickname for a manual person")
    check(P.IdentityNickname(m1) == "Bob Main", "under my nickname, the identity's own is still the main's name")
    check(P.Rename(m1, nil) and P.Nickname(m1) == "Bob Main", "mine removed: back to the main's name")
    check(select(2, P.Rename(m1, "x")) == "short", "short nickname refused")
    check(P.Rename(A, "Annie") and P.Nickname(A) == "Annie", "my nickname for a shared person")
    check(P.IdentityNickname(A) == "Ann", "under my nickname, the identity's own is still the player's")
    check(P.Rename(A, nil) and P.Nickname(A) == "Ann", "mine removed: back to the player's own")

    check(P.SetMain(m1, G4) and P.Nickname(m1) == "Tank Bob", "main changed")
    check(select(2, P.SetMain(m1, G3)) == "character", "main must be one of the person's characters")
    check(select(2, P.SetMain(A, G1)) == "shared", "a shared identity's main is the player's own")

    check(select(2, P.RemoveCharacter(m1, G4)) == "main", "a manual person's main cannot be removed")
    P.SetMain(m1, G2)
    check(P.RemoveCharacter(m1, G4) and P.Find(G4) == nil, "another character of a manual person removed")
    check(P.AddCharacter(A, G3, INFO) and P.Find(G3) == A and state(G3) == "added", "alt added to a shared identity")
    check(select(2, P.RemoveCharacter(A, G1)) == "character", "a listed character cannot be removed by me")
    check(select(2, P.RemoveCharacter(m1, G2)) == "main", "a manual person's last character is its main: refused")
    P.Forget(m1)
    check(P.Get(m1) == nil and P.Find(G2) == nil, "forgetting the manual person removes it")

    P.Accept(makeRecord(A, 2, { G1, G3 }, "Ann"))
    check(state(G3) == "listed", "an alt I added that the player now lists becomes listed")
    P.Confirm(A, G3, 10)
    check(state(G3) == "confirmed", "then confirmed by its own message")

    local B, C, D = string.rep("b", 64), string.rep("c", 64), string.rep("d", 64)
    local G6, G7 = "Player-70-0000000F", "Player-70-00000010"
    local m3 = P.Create(G4, INFO)
    P.AddCharacter(m3, G6, INFO)
    P.Rename(m3, "Tanky")
    P.Accept(makeRecord(B, 1, { G4 }))
    check(P.Find(G4) == B and state(G4) == "listed", "a manual person's character listed by its player")
    check(P.Find(G6) == B and state(G6) == "added", "the manual person's other characters merge as added ones")
    check(P.Get(m3) == nil, "the merged manual person is removed")
    check(P.Get(B).customNickname == "Tanky", "my nickname for the manual person moves to the shared person")

    local m4 = P.Create(G5, INFO)
    P.Rename(m4, "Other")
    P.Accept(makeRecord(C, 1, { G2 }, "Cee"))
    P.Rename(C, "Mine")
    P.Accept(makeRecord(C, 2, { G2, G5 }, "Cee"))
    check(P.Get(C).customNickname == "Mine" and P.Get(m4) == nil, "an existing nickname of mine is kept")

    P.AddCharacter(A, G7, INFO)
    P.Accept(makeRecord(D, 1, { G7 }))
    check(P.Find(G7) == D and P.Find(G3) == A, "an alt I added to another player's identity moves alone")

    local E = string.rep("e", 64)
    local G8, G9, G10 = "Player-70-00000011", "Player-70-00000012", "Player-70-00000013"
    local m5 = P.Create(G8, INFO)
    P.AddCharacter(m5, G9, INFO)
    P.Rename(m5, "First")
    local m6 = P.Create(G10, INFO)
    P.Rename(m6, "Second")
    P.Accept(makeRecord(E, 1, { G8, G9, G10 }))
    check(P.Get(m5) == nil and P.Get(m6) == nil, "a record listing characters of two manual identities merges both")
    check(state(G8) == "listed" and state(G9) == "listed" and state(G10) == "listed",
        "every character the record lists is listed, two of them from the same manual identity")
    local nickname = P.Get(E).customNickname
    check(nickname == "First" or nickname == "Second", "my nickname comes from one of the merged identities")
    check(indexMatchesSavedData({ G1, G2, G3, G4, G5, G6, G7, G8, G9, G10 }),
        "index kept up to date: manual identities, added alts, merges")

    P.Reset()
    check(P.Find(G3) == A and P.Find(G4) == B, "index rebuilt from saved data")
end

-- Automatic changes -------------------------------------------------------------------------------------------

fresh()
do
    local P, AC = ns.People, ns.AutomaticChanges
    local A, B, C, D, F = string.rep("a", 64), string.rep("b", 64), string.rep("c", 64), string.rep("d", 64), string.rep("f", 64)
    local G6, G7, G8 = "Player-70-0000000F", "Player-70-00000010", "Player-70-00000011"
    local function latest() return AC.List()[1] end

    P.Accept(makeRecord(A, 1, { G1, G2, G3 }, "Ann"))
    check(#AC.List() == 0, "a first record changes nothing of mine")

    clock = 5
    local manual = P.Create(G4, INFO)
    P.AddCharacter(manual, G5, INFO)
    P.Rename(manual, "Tanky")
    P.Accept(makeRecord(B, 1, { G4 }, "Bob"))
    local change = latest()
    check(change.kind == "merged" and change.time == 5 and change.read == false, "merge logged, unread")
    check(change.from.id == manual and change.from.customNickname == "Tanky" and change.from.nickname == "Tank Bob"
        and change.from.main == G4, "the manual identity as it was")
    check(change.to.id == B and change.to.nickname == "Bob" and change.to.customNickname == nil,
        "the player's identity as it was, before my nickname moved to it")
    check(count(change.chars) == 2 and change.chars[G5].name == "Tank Bob" and change.chars[G5].state == "added",
        "every character of the manual identity")

    P.AddCharacter(A, G6, INFO)
    P.Accept(makeRecord(C, 1, { G6 }, "Cee"))
    change = latest()
    check(change.kind == "moved" and change.from.id == A and change.from.nickname == "Ann" and change.to.id == C
        and count(change.chars) == 1 and change.chars[G6].state == "added", "an alt I added moving away logged")

    local before = #AC.List()
    P.Accept(makeRecord(D, 1, { G7, G1 }, "Dee"))
    check(#AC.List() == before, "a character another player keeps logs nothing")
    P.Confirm(D, G1, 10)
    change = latest()
    check(change.kind == "taken" and change.from.id == A and change.from.main == G1 and change.to.id == D
        and change.chars[G1].state == "listed", "a listed character taken by a confirmation logged, with the main it was")

    P.Rename(A, "Annie")
    P.Accept(makeRecord(A, 2, { G2 }, "Anna"))
    change = latest()
    check(change.kind == "dropped" and change.to == nil and change.from.nickname == "Ann"
        and change.from.customNickname == "Annie", "a dropped character logged, with the nicknames before the revision")
    check(count(change.chars) == 1 and change.chars[G3] ~= nil, "only the characters this revision dropped")
    before = #AC.List()
    P.Accept(makeRecord(A, 3, { G2 }, "Anna"))
    check(#AC.List() == before, "a revision dropping nothing logs nothing")

    P.AddCharacter(A, G8, INFO)
    P.Accept({ v = 1, id = A, rev = 4, chars = {} })
    change = latest()
    check(change.kind == "forgotten" and change.from.nickname == "Anna" and change.from.customNickname == "Annie",
        "a forgotten identity logged with my nickname for it")
    check(count(change.chars) == 2 and change.chars[G2].state == "listed" and change.chars[G8].state == "added",
        "with its characters and my added alts")
    before = #AC.List()
    P.Accept({ v = 1, id = F, rev = 1, chars = {} })
    check(#AC.List() == before, "forgetting an identity I never had logs nothing")

    check(AC.UnreadCount() == before, "every change unread")
    AC.MarkRead(latest())
    check(latest().read and AC.UnreadCount() == before - 1, "a change marked read")

    for i = 1, 105 do
        clock = 100 + i
        AC.Add("dropped", { id = A, main = G1 }, nil, {})
    end
    check(#AC.List() == 100 and AC.List()[1].time == 205 and AC.List()[100].time == 106,
        "only the 100 most recent changes kept, most recent first")
end

-- Automatic changes: one revision, several changes ------------------------------------------------------------

fresh()
do
    local P, AC = ns.People, ns.AutomaticChanges
    local A, B, C = string.rep("a", 64), string.rep("b", 64), string.rep("c", 64)
    P.Accept(makeRecord(A, 1, { G1 }, "Ann"))
    P.Accept(makeRecord(B, 1, { G2, G3 }, "Bob"))
    P.AddCharacter(A, G4, INFO)
    P.Accept(makeRecord(B, 2, { G2, G4 }, "Bobby"))
    local moved, dropped = AC.List()[1], AC.List()[2]
    check(#AC.List() == 2 and dropped.kind == "dropped" and dropped.chars[G3] ~= nil and moved.kind == "moved"
        and moved.chars[G4] ~= nil, "a revision dropping one character and taking my alt logs both")
    check(dropped.from.nickname == "Bob" and moved.from.id == A and moved.to.nickname == "Bobby",
        "dropped shows the identity before the revision, moved the identity the alt joins")

    P.Accept(makeRecord(C, 1, { G5 }, "Cee"))
    check(not P.Confirm(B, G5, 10), "a confirmation of a character the record does not list yet waits")
    P.Accept(makeRecord(B, 3, { G2, G4, G5 }, "Bobby"))
    local taken = AC.List()[1]
    check(taken.kind == "taken" and taken.from.id == C and taken.to.id == B and taken.chars[G5].state == "listed",
        "a waiting confirmation applied by the revision logs the character taken")
end

-- Resolver ---------------------------------------------------------------------------------------------------

fresh()
do
    local I, P, R = ns.Identity, ns.People, ns.Resolver
    I.EnsureKeys()
    I.Refresh(G1, "Me Myself", NORMAL, PRIEST, 10)
    I.Link(G1)
    I.SetNickname("Yann")

    local A = string.rep("c", 64)
    P.Accept(makeRecord(A, 1, { G2 }, "Ann"))
    P.Confirm(A, G2, 10)
    P.AddCharacter(A, G3, INFO)
    P.Create(G4, INFO)

    local r = R.Resolve(G1)
    check(r.mine and r.nickname == "Yann", "own linked character")
    r = R.Resolve(G2)
    check(r.shared and r.state == "confirmed" and r.nickname == "Ann", "confirmed character of a shared identity")
    r = R.Resolve(G3)
    check(r.shared and r.state == "added" and r.nickname == "Ann", "alt added to a shared identity")
    r = R.Resolve(G4)
    check(not r.shared and r.state == "added" and r.nickname == "Tank Bob", "manual person, main's name as nickname")
    check(R.Resolve(G5) == nil, "unknown character")

end

if failures > 0 then
    print(("%d of %d checks FAILED"):format(failures, checks))
    os.exit(1)
end
print(("ALL %d MODEL CHECKS PASSED"):format(checks))
