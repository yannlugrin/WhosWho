# Who's Who // In-Game Test Plan

Manual tests between two clients, for what the offline suites cannot check: the real game API, the add-on channel and the server. For the code, see [README-Technical.md](README-Technical.md).

## Setup

- Two test accounts, A and B, each with a character in the same ruleset, that don't know each other yet (`/ww people`). Friends are disabled on the Forever beta, so these tests use the group and whispers.
- Test accounts only: the tests link and unlink characters and change scopes, and other players running Who's Who see these changes.
- On both: `/ww debug on` (every message sent or received is printed in chat), `/ww scope group on`, then `/ww link`.
- Two clients on one computer are slow: wait a few seconds before reading a result.

Useful commands: `/ww status` (my identity), `/ww people` (the identities I hold), `/ww scope` (my scopes).

**Re-log** a character: log out and back in on another linked character, or on the same one more than 5 minutes later. A `/reload`, or logging back in on the same character sooner, sends no login announcement (see Quick Relog).

## Group

**Announcement, request and record.** Group A and B, then re-log A.

| A's chat | B's chat |
|---|---|
| `Sent, PARTY: 1 ANNOUNCE <A's ID> <rev> <level> 1 1 0` | `Received, PARTY <A>: 1 ANNOUNCE …` |
| `Received, WHISPER <B>: 1 GET <A's ID>` | `Sent, WHISPER <A>: 1 GET …` |
| after about 5 s: `Sent, WHISPER <B>: 1 REC (… bytes)` | `Received, WHISPER <A>: 1 REC (… bytes)` |
| after about 5 s: `Received, WHISPER <B>: 1 ANNOUNCE … 1 0 0` | `Sent, WHISPER <A>: 1 ANNOUNCE <B's ID> <rev> <level> 1 0 0` (B's answer to the login) |

On B, `/ww people` lists A's character as **confirmed**, with its level. Then re-log B: the same on the other side.

A's own `GUILD` and `PARTY` messages come back to A; they are printed and ignored.

**Linking while grouped.** On A, link another character while playing it.

- A, after 15 s: `Sent, PARTY: 1 ANNOUNCE … 1 0 0`, and no `REC` yet.
- B: `Sent, WHISPER <A>: 1 GET …`; after about 5 s, A: `Sent, WHISPER <B>: 1 REC …`.
- B: `/ww people` lists the new character as **confirmed**, with its level.

**Unlinking while grouped.** On A, `/ww unlink` on a linked character.

- A, after 15 s: `Sent, PARTY: 1 ANNOUNCE …` (and `GUILD` if A is in a guild), then B's `GET`, then a `REC`.
- B: `/ww people` no longer lists that character.

## Removal While Offline

1. B logs out.
2. On A, unlink a character, then play that character.
3. B logs back in; group A and B.
4. Re-log A on that character.

- A: `Sent, PARTY: 1 NOID`, without A's ID, and no announcement.
- B: no `GET`; `/ww people` no longer lists the removed character, and B's Review tab shows nothing.
- A second re-log of A: the same `NOID`, which changes nothing on B.
- In a guild together instead: A playing the removed character when B logs in answers B's login announcement with `1 NOID` by whisper, which already removes it on B (the roster gives A's GUID).

**Removal reaching a player met in a group.** A and B not in a guild together, not friends; A whispered B and they grouped, so B holds A's character. B logs out; on A, unlink that character (while playing it); B logs back in.

- A whispers B: `Sent, WHISPER <B>: 1 NOID`; B's `/ww people` no longer lists the character. A whispering B again: nothing more.
- A and B group again: `Sent, PARTY: 1 NOID` from the one joining, and A answers B's group announcement with `1 NOID` by whisper. Never an announcement from A.

**Unlinking every character** works the same way: after the last unlink, B, offline at the time, forgets A's identity once the last removed character sends `NOID`. `/ww people <A's character>` on B then finds no one.

## Scopes

**A scope turned off.** On B, `/ww scope group off`. On A, link or unlink a character.

- A: `Sent, PARTY: 1 ANNOUNCE …`.
- B: `Received, PARTY <A>: 1 ANNOUNCE …`, but no `GET`, and `/ww people` does not change.

**Whispers.** On both, `/ww scope whispers on`; leave the group; A and B don't know each other (`/ww people`).

- B whispers A; A doesn't answer. A gets `Received, WHISPER <B>: 1 ANNOUNCE …`, but sends no `GET`, and `/ww people` does not change: a whisper received allows nothing.
- A whispers B. A sends `Sent, WHISPER <B>: 1 ANNOUNCE … 1 1 0`, B a `GET`, A the `REC`, and B's answer brings B's record the same way: each `/ww people` shows the other's character, confirmed.
- On A, link or unlink a character: after 15 s, nothing goes to B (a whispered player is never in a broadcast). A whispers B: the announcement goes out, B sends a `GET` and follows the change.
- A: `/reload`, then B whispers A: A sends a `GET` (B is still allowed from the saved whisper). `/reload` again, then log out and back in: the same.
- In A's settings, **Clear history** is on the right of **People I whisper**, usable while it is off. It asks for a confirmation; after it, B whispering A brings no `GET` from A until A whispers B again.
- Settings open, A grouped with B: turning **My party or raid** on sends nothing until the settings close, then one `1 ANNOUNCE … 1 1 0` on `PARTY`. Turned on then off again before closing: nothing.
- In A's settings, **Whispers count for** is greyed out while **People I whisper** is off. Set it to **1 hour**; one hour after A's last whisper to B, B whispering A brings no `GET` from A.

## Reaching Players Who Come Later

**Joining a group.** On both, `/ww scope group on`; A and B not grouped. Invite B into A's group.

- B (the one joining): `Sent, PARTY: 1 ANNOUNCE … 1 1 0`. A, the group's only other member, has also just joined, so the same from A.
- Each, after about 5 s: `Sent, WHISPER <other>: 1 ANNOUNCE … 1 0 0`, and nothing more: an answer is not answered.
- B leaves and is invited again: the same exchange again. A change in the group (a third player joining) sends nothing from A or B unless they join.

**Turning the Group scope on.** A and B grouped, B's Group scope on, A's off; `/reload` both. On A, `/ww scope group on`.

- A, right away: `Sent, PARTY: 1 ANNOUNCE … 1 1 0`.
- B: a `GET` if it doesn't hold A's revision; after about 5 s, `Sent, WHISPER <A>: 1 ANNOUNCE … 1 0 0`. A then asks for B's record if it doesn't hold it.
- `/ww scope group off`, then on again: the same announcement again; turning the Whispers scope on sends nothing.

**Turning the Guild scope on** (needs a guild). A and B in the same guild, B's Guild scope on, A's off. On A, `/ww scope guild on`.

- A, after 15 s (the change of revision it makes): `Sent, GUILD: 1 ANNOUNCE … 1 1 0`.
- B: a `GET`, then its answer `1 ANNOUNCE … 1 0 0`; A gets B's record in turn.

**Joining a guild** (needs a guild). A linked, Guild scope on, not in a guild. A joins B's guild.

- A, once its guild roster arrives (a moment after joining): `Sent, WHISPER <member>: 1 ANNOUNCE … 1 1 0` to each online member, nothing on `GUILD` (see Workarounds in README-Technical). B answers as for a login when its roster lists A. *To verify*: whether it does by then (`/dump C_GuildInfo.MemberExistsByName("<A's name>")` on B).
- A changes its revision in that session (`/ww nick …`): after 15 s, its announcement goes by whisper to each online member, and the `REC`s answering their `GET`s by whisper too; nothing on `GUILD`.
- A logs out and back in: `Sent, GUILD: 1 ANNOUNCE … 1 1 0`, and B receives it. A member whose roster does not list A yet answers anyway, and its roster is requested (`/dump C_GuildInfo.MemberExistsByName("<A's name>")` on it gives `true` once it comes back).

**Adding a friend** (needs friends). A and B online, Friends scope on, B lists A as a friend. A adds B.

- A, right away: `Sent, WHISPER <B>: 1 ANNOUNCE … 1 1 0`; B answers as for a login. Turning the Friends scope on sends the same to each online friend.
- *To verify*: whether the friend list is loaded at login. If it isn't, the first `FRIENDLIST_UPDATE` sends this announcement to every online friend, which the login announcement missed.

**Logging in.** A and B in the same guild, or grouped with the Group scope on. Re-log B.

- B: `Sent, GUILD (or PARTY): 1 ANNOUNCE … 1 1 0`.
- A, after about 5 s: `Sent, WHISPER <B>: 1 ANNOUNCE … 1 0 0`.

**Logging out.** A and B grouped, A's Group scope on, A outside a rested area.

- A logs out: when the countdown starts, `Sent, PARTY: 1 ANNOUNCE … 0 0 0`. B receives it.
- A logs out and moves to cancel: nothing after the cancel. A logs out again: the logout announcement goes out again.
- On A, `/ww nick Test`, then right away log out (countdown): after the logout announcement, nothing more from A, not even the change's announcement 15 s later. A's next login announces it. The same, canceled: the change's announcement goes out after the cancel.
- `/reload` A: no logout announcement.
- A logs out in an inn (immediate): B receives `1 ANNOUNCE … 0 0 0`.

**Quick relog.** A and B grouped, A's Group scope on.

- `/reload` A: no `Sent, PARTY: 1 ANNOUNCE … 1 1 0` after the reload.
- A logs out to character select and back in on the same character within 5 minutes: no login announcement either.
- The same more than 5 minutes later, or after playing another character in between: the login announcement goes out.
- On A, `/ww nick Test`, then `/reload` within 15 s: the login announcement goes out, carrying the new revision; B sends a `GET`.
- On A, `/ww nick Test2`; about 16 s later, when B's `GET` arrives, log out in an inn (immediate): A's next login, even right away, announces again, and B sends its `GET` again.

**Whispering.** On A, `/ww scope whispers on`; A and B not grouped, not in a guild together; `/reload` both first, so neither has reached the other this session.

- A whispers B: right away, `Sent, WHISPER <B>: 1 ANNOUNCE … 1 1 0`. With B's Whispers scope off, or B never having whispered A, B sends no announcement back.
- A whispers B again: nothing more. After a change of A's revision, or 30 minutes after the last one, the next whisper sends the announcement again. Whispering a guild member (Guild scope on) sends none.
- Once B's character is confirmed on A, A levels up (or changes its revision, or starts a logout): `Sent, WHISPER <B>: 1 ANNOUNCE …`. After a `/reload` of A, the same. After a logout and a login of A more than 5 minutes later, A's login announcement goes to B if A whispered B in the 30 minutes before the logout; otherwise, or after playing another character in between, nothing goes to B until A whispers B again.
- B on another linked character of the same ruleset, confirmed on A, whispers A and A answers: A's next level-up goes to that character only.
- B whispers A: A sends nothing.
- On B, `/ww scope whispers on`, then a change of A's revision and A whispers B: B, having whispered A, answers after about 5 s with `Sent, WHISPER <A>: 1 ANNOUNCE … 1 0 0`. B whispering A again sends nothing more: the answer already reached A.

## First-Login Prompt

With a test account whose characters are not registered yet (`/ww status`: "not asked yet").

- First login, no linked character: "Set <Character> as your identity's main character?". Check the nickname box, type a nickname, **Link**: `/ww status` shows that nickname and "linked, main".
- A nickname of one letter: the chat prints why it is refused, the dialog stays open.
- Another character: "Link <Character> to <nickname>?", naming the linked characters in their class colours. **Not this character**: "not linked", and no prompt at the next login.
- Closing the dialog with its close button: the prompt comes back at the next login.

## Chat Nicknames

With A and B knowing each other (see Group), B sets a nickname (`/ww nick Bee`).

- A, B says something in the group: `[B's character (Bee)]: …`, the nickname in light grey; clicking the name still opens a whisper to B's character.
- `/ww nick` on B (back to the main's name), B speaks from its main: no nickname on A's side.
- A's own lines: never a nickname.

## People Tab Menu

Right-click a character in the People tab's detail panel, or a person in the list who is online (the character they play is shown after the nickname).

- The menu shows the character's name as its title, **Whisper**, **Invite**, then the Who's Who section (Make main or Unlink when they apply; no Show person).
- **Whisper** opens a whisper to that character in the chat box; **Invite** invites it. A character already in my group has no **Invite**. In the list, right-clicking a person whose online character isn't known opens nothing, and the selection doesn't change. No Lua error, and BugSack shows no blocked action.

## People Tab Filter

Needs B a WoW friend of one of my characters, C a member of my current character's guild, E neither; all three known.

- **Show** lists Friends, Guild mates and Everyone else, all checked: the dropdown reads "All", and B, C and E are listed.
- Unchecking Guild mates hides C, and every person the Guild tab lists, unless they are also a friend; the dropdown names the checked ones. Unchecking Friends hides B; unchecking Everyone else hides E. All unchecked: "No one", an empty list.
- On a character in another guild, or in none, C counts as Everyone else.
- A Battle.net friend's character, once seen while they play it, counts as Friends, also after they log off; their detail panel shows "Battle.net: <BattleTag>" under the nickname, after the original nickname when mine replaces it. Removing them from my Battle.net friends moves it to Everyone else.
- **Show person** (from a player's menu) on a hidden person checks all three again.

## Guild Tab

Needs a guild with Who's Who enabled (see Guild Settings): A and B members, both linked with the Guild scope on; C a member without Who's Who; D, B's alt, in the guild while B's main is not.

- A character out of any guild, or in a guild without Who's Who enabled: no Guild tab. Joining the guild shows it, leaving hides it; an officer turning Who's Who off for the guild hides it, on shows it (the first tab is selected if it was open).
- Header, on one line: the guild's name in angle brackets, my rank in grey, the search box, and at the right the counts of main characters, alts and unknown characters, which add up to the roster's members.
- Search: typing part of a nickname or of a character's name (an alt's too, or C's name) keeps only the matching rows; the counts don't change.
- List: a row for A (my own identity, Confirmed glyph, Online), one for B, one for C (its name in grey, Unconfirmed glyph, 1 character, no last seen while offline: the roster's last online isn't used); none for D (its main, B's, is not in the guild), counted as an alt. C is counted as unknown, and so is a character of mine in the guild that is not linked, shown like C.
- Selecting B shows the same detail panel as the People tab; selecting A shows my linked characters, without Forget, nickname edit or note; a left click on C selects nothing.
- Right-click C: Whisper, Invite, then Who's Who **Link character**. Right-click B while online: its menu, without Show person.

## Last Seen

In the People tab, a person's last seen moves to now when one of their characters is online in your guild, in your group, online in your friend list, or whispers with you, also for a person you created yourself. A guild member you link while they are offline shows their level from the roster and no last seen time until you see them online.

## Guild Settings

Needs a guild where A is the guild master or an officer and B a member below; both linked, Guild scope on, B holding A's identity with A's character confirmed.

- B opens the guild panel: the Who's Who tab under the game's own shows the guild's list, without a **Who's Who settings** button. A opens it: the button under the list; it shows the settings, the checkbox off.
- A ticks **Enable Who's Who for the guild**; after 5 s: `Sent, GUILD: 1 GSET …`. B: `Received, GUILD <A's name>: 1 GSET …`, then `/dump WhosWhoDB.global.guildSettings` on B shows the record with `enable = true`.
- A unticks and ticks again within 5 s: one `GSET`, with the last state.
- B logs out; A changes the setting; B logs back in: A's answer to B's login announcement ends with A's revision, B sends `Sent, WHISPER <A's name>: 1 GSGET`, A answers `1 GSET …` by whisper, and B holds the new record.
- With the Guild scope off on A, or on an unlinked character of A's: the checkbox is greyed out, its tooltip says why.

## Guild Lists

Needs a guild with Who's Who enabled (see Guild Settings): A an officer, B and C members, all linked with the Guild scope on.

- With A, B and C online and knowing each other, a login of any of them: no `GLGET` (their lists have the same hash).
- C logs out. D, a new member, links and logs in with A and B online: D sends one `Sent, WHISPER <A>: 1 GLGET` (the officer), A answers `1 GLIST …` by whisper, then D asks A for C's identity (`1 GET <C's ID>`), A answers with C's `REC`, and `/ww people <C's character>` on D shows it `listed by the guild`. When C logs back in, its announcement confirms it.
- A turns Who's Who off then on for the guild: `Sent, GUILD: 1 GSET …` then `Sent, GUILD: 1 ANNOUNCE …` ending with A's list revision; members holding the same list send nothing.

## Enforced Linking

Needs a guild with Who's Who enabled (see Guild Settings): A an officer; B a member whose main is outside the guild, with two characters in it, B1 linked and B2 never linked (B logged in on B2 once, answering **Not this character**); C, B's friend, outside the guild; D a player not in the guild who knows B. All linked, Guild scope on.

- A's guild panel, Who's Who tab, **Who's Who settings**: **Require members' characters in the guild to be linked** under **Enable Who's Who for the guild**, greyed out while Who's Who is off for the guild (its tooltip says to enable it first). A ticks it: `Sent, GUILD: 1 GSET …`.
- B's side: one new revision, announced on `GUILD` only (no whisper to C). A's People tab: B shown under B1's name (the guild main), B2 among B's characters. C's People tab after B's next level-up: B under B's main, without B2.
- B plays B2: `Sent, GUILD: 1 ANNOUNCE <B's ID> …`, nothing to C or a group; A's People tab shows B2 confirmed.
- B turns the Guild scope off: A still gets B's record, with B1 and B2 only; C keeps B's record without them.
- D joins the guild: within a minute D's People tab shows B2 under B (fetched again through the guild lists or from B). D leaves the guild: B2 disappears from D's People tab, B stays.
- A unticks the setting: the members whose records change make a new revision; B2 disappears from A's People tab once B's new record arrives.

## Enforced Linking Opt-In

Needs the guild of Enforced Linking with the rule on: B a member with an unlinked character in it, E a player who never linked any character, in the guild.

- B logs in: one dialog, "<guild> requires its members to link their characters in it.", listing B's characters in the guild (the unlinked ones marked), with **Link**, **Share without linking**, **Refuse**; the guild-main dropdown when B's main isn't in the guild and B has several characters there. In combat at login: the dialog waits until combat ends. Before answering, nothing from B on `GUILD` but `Sent, GUILD: 1 ANNOUNCE 0 0 0 0 1 0 0`.
- **Refuse**: nothing to the guild; no dialog until B's next login in another state, nor when another of B's characters logs in in the guild. When another of B's characters joins the guild, the dialog shows again. **Share without linking**: A's People tab shows B's characters in the guild, under the guild main chosen. B's Guild tab shows B's own identity, with those characters, under that guild main. **Link**: they are linked in **My identity**, and the Guild scope is on.
- E logs in: `Sent, GUILD: 1 ANNOUNCE 0 0 0 0 1 0 0`, the members answer, and the same dialog shows once the guild's settings arrive, in place of the first-login prompt. **Share without linking**: A's People tab shows E's character under an identity of its own.
- A turns the rule off and on again while B plays: no dialog until B's next login.
- B's Guild tab, bottom line: "Requires linking:" and B's answer; **Answer** while not answered, **Change** after a refusal (opens the dialog), no button once accepted. In a guild without the rule: whether B's identity reaches it, **Share** with the Guild scope off.
- B accepted (shared without linking, or all linked with the Guild scope on): turning the Guild scope off, or unlinking one of B's characters in the guild, prints "<guild> requires linking: your characters in it stay shared with its members. Leave the guild to stop." A still sees B's characters in the guild.
- B's character in the guild unlinked, the rule refused or not answered; B's other character, linked, with the Guild scope on, joins the guild (`/ww debug on`): only `Sent, WHISPER <member>: 1 ANNOUNCE 0 0 0 0 1 0 0`, never B's identity ID, even while the game hasn't given the guild's club ID yet.

## Leaving a Guild

Needs the guild of Guild Lists: A in it, and a guildmate C whom A only knows through the guild list (Guild glyph in A's People tab).

- A's People tab: C shows the green banner (Guild), with "Shared by your guild, not by the player." in its tooltip, until one of C's characters is confirmed to A.
- C leaves the guild: once A's roster updates, C is gone from A's People tab. A guildmate with a character confirmed to A stays when they leave.
- A leaves the guild while none of A's other characters is in it: C is gone; a guildmate confirmed to A stays. With another of A's characters still in the guild, nothing goes.
- A's character is removed from the guild while offline (an officer kicks it): at its next login, `/ww status` shows no guild line, and the guild's rule no longer adds that character to A's record.
- A character the guild linked (to a guild identity or to a member's identity) leaves the guild, with A an officer online: `Sent, GUILD: 1 GIREC …` once A's roster updates, and `/dump WhosWhoDB.global.guildRecords` on A and on another member no longer lists it in that record. With no officer online when it leaves, the first officer to log in sends it.

## Still to Test

- During a boss fight, in a real group run: `/dump C_ChatInfo.InChatMessagingLockdown(), C_ChatInfo.SendAddonMessage("WhosWho", "test", "PARTY"), issecretvalue(UnitGUID("party1")), issecretvalue(UnitName("party1"))` (inside a dungeon out of a boss fight, all are fine).
- Guild: two members of one guild get the same club ID (`/dump C_Club.GetGuildClubId()`).
- Battle.net friends, once a Battle.net round trip is possible.
