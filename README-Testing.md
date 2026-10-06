# Who's Who // In-Game Test Plan

Manual tests between two clients, for what the offline suites cannot check: the real game API, the add-on channel and the server. For the code, see [README-Technical.md](README-Technical.md).

## Setup

- Two test accounts, A and B, each with a character in the same ruleset, that don't know each other yet (`/ww people`). Friends are disabled on the Forever beta, so these tests use the group and whispers.
- Test accounts only: the tests link and unlink characters and change scopes, and other players running Who's Who see these changes.
- On both: `/ww debug on` (every message sent or received is printed in chat), `/ww scope group on`, then `/ww link`.
- Two clients on one computer are slow: wait a few seconds before reading a result.

Useful commands: `/ww status` (my identity), `/ww people` (the identities I hold), `/ww scope` (my scopes).

## Group

**Announcement, request and record.** Group A and B, then `/reload` A.

| A's chat | B's chat |
|---|---|
| `Sent, PARTY: 1 ANNOUNCE <A's ID> <rev> <level> 1` | `Received, PARTY <A>: 1 ANNOUNCE …` |
| `Received, WHISPER <B>: 1 GET <A's ID>` | `Sent, WHISPER <A>: 1 GET …` |
| after about 5 s: `Sent, WHISPER <B>: 1 REC (… bytes)` | `Received, WHISPER <A>: 1 REC (… bytes)` |

On B, `/ww people` lists A's character as **confirmed**, with its level. Then `/reload` B: the same on the other side.

A's own `GUILD` and `PARTY` messages come back to A; they are printed and ignored.

**Linking while grouped.** On A, link another character while playing it.

- A, after 15 s: `Sent, PARTY: 1 REC …`, then `Sent, PARTY: 1 ANNOUNCE … 0`.
- B: no `GET`; `/ww people` lists the new character as **confirmed**, with its level.

**Unlinking while grouped.** On A, `/ww unlink` on a linked character.

- A, after 15 s: `Sent, PARTY: 1 REC …` (and `GUILD` if A is in a guild).
- B: `/ww people` no longer lists that character.

## Removal While Offline

1. B logs out.
2. On A, unlink a character, then play that character.
3. B logs back in; group A and B.
4. `/reload` A.

- A: `Sent, PARTY: 1 ANNOUNCE <A's ID> <removal rev> …`, then B's `GET`, then a `REC`.
- B: `/ww people` no longer lists the removed character.
- A second `/reload` of A: B sends no `GET` (it already has that revision).

**Unlinking every character** works the same way: after the last unlink, B, offline at the time, forgets A's identity once the last removed character announces. `/ww people <A's character>` on B then finds no one.

## Scopes

**A scope turned off.** On B, `/ww scope group off`. On A, link or unlink a character.

- A: `Sent, PARTY: 1 REC …`.
- B: `Received, PARTY <A>: 1 REC …`, but `/ww people` does not change.

**Whispers.** On both, `/ww scope whispers on`; leave the group. A and B whisper each other once. On A, link or unlink a character.

- A: `Sent, WHISPER <B>: 1 REC …`.
- B: `/ww people` follows the change.
- After a `/reload` of A, A sends B nothing more: the list of players whispered with is kept for the session only.

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

## Still to Test

- Inside an instance and during an encounter: add-on messages, secret values.
- Guild: two members of one guild get the same club ID (`/dump C_Club.GetGuildClubId()`).
- Battle.net friends, once a Battle.net round trip is possible.
