# Who's Who // Design

The frames of Who's Who: their structure, and their functional and visual description. For the code, see [README-Technical.md](README-Technical.md); for players, [README.md](README.md).

Who's Who is a World of Warcraft add-on (WoW: Forever, a Classic-era world with the modern game UI). A player links all their characters into one identity with a nickname, chooses who can see it, and recognises other people across their alts. For players who don't use the add-on, you can link their characters yourself and give them a nickname.

## One Concept: a Person

Everything in the add-on is a **person** (an identity): a nickname and the characters that belong to it. There are three kinds:

- **Created by me** for a player who doesn't use the add-on: I linked their characters myself. It is never confirmed.
- **Created by a guild member**, the same at guild level: a guild member linked the characters of a player who doesn't use the add-on, and it reaches me through the guild. It is never confirmed.
- **Shared by the player**: their add-on sent us their identity, directly or passed on by someone else (for example a guild member). It is confirmed as soon as at least one of its characters is confirmed. Until then (for example when it was passed on and we haven't met any of the player's characters yet), it is shared but not confirmed.

Inside a person, each character is in one of three states:

- **Confirmed**: the player declared it, and we have seen that character use this identity (it sent us a message carrying it).
- **Listed**: the player declared it, but we haven't seen that character yet. We trust it by default; it is shown as part of the person, marked as not confirmed yet.
- **Added**: attached by hand, never shared by the player: by me, or by a guild member for a person created in the guild. If the player later declares it, it becomes listed, then confirmed once we see it.

A character never belongs to two persons.

**When a player I linked installs the add-on.** If a player's shared identity includes a character of a person I created, both are the same player: my person disappears and its characters join the shared identity. The ones the player declared become listed (then confirmed); the others stay as alts I added, with the Added glyph. My nickname for that person moves to the shared identity, unless I had already set one there. An alt I added to someone else's shared identity moves on its own when its real player declares it. These changes happen without me doing anything, so each one is written to the Review tab (frame 11) where I can check it.

My own characters are always confirmed for me: an alt joins my identity by logging in on it.

**Main character.** Every person has one main character, marked with a small crown next to its name. The first character linked becomes the main; it can be changed at any time (except on a person shared by the player). A person is always shown under a name: their nickname, or their main character's name when no nickname is set. Setting a nickname overrides the main's name; clearing it goes back to it. The frames never show "no nickname".

**Which nickname wins.** A nickname I set replaces, for me only, the one the person has (the player's own for a shared identity, the guild's for a person created in the guild); removing mine brings it back. Where mine replaces another one, that other nickname is shown small and grey next to mine (no source), so I see what would come back.

**Glyphs.** There is no separate word for these cases in the interface. A small glyph before each nickname tells where it comes from; hovering it explains it in one line, including who set it when it came from the guild.

Each glyph has one short label, used in the keys, the filter and the hover text:

| Glyph | Label | On | Means |
|---|---|---|---|
| Person | **Confirmed** | A nickname | Identity shared by the player and confirmed |
| Pencil | **Renamed** | A nickname | Confirmed identity whose nickname I overrode |
| Banner | **Guild** | A nickname | Identity not confirmed, set by a guild member |
| Question mark | **Unconfirmed** | A nickname or character name | Identity shared by the player but none of its characters seen yet, or no identity received from the player (a person I created, or a guild member's character not linked to any identity) |
| Person | **Confirmed** | A character (state) | Declared by the player and seen |
| Hourglass | **Listed** | A character (state) | Declared by the player, not seen yet |
| Question mark | **Added by me** | A character (state) | Attached by me, never shared by the player |
| Banner | **Guild** | A character (state) | Attached by a guild member (a person created in the guild); its main always is |
| Crown | **Main** | A character | The person's main character |

The People and Guild tabs show a key of all these glyphs under both panels, full width, in this order: Main, Renamed, Confirmed, Listed, Guild, Unconfirmed / Added by me. The Listed glyph is shown on character names wherever other players' characters are listed (People detail panel, person editor, tooltip "Also:" line); never in My identity.

## Design Constraints

- **Look**: the default WoW Forever window style (Blizzard frames: title bar with close button, dark inset panels, gold headings, white body text, standard buttons). If the EllesmereUI add-on is installed, the same frames get a flat dark theme with an accent color, so layouts must not depend on decoration.
- **Widgets allowed** (the only ones the theme can restyle): window shell, panel, inset panel, tabs, buttons, text inputs, checkboxes, dropdowns, scroll lists with a scroll bar, close button, prev/next page arrows, square icons, sortable column headers.
- **Size**: main window about 640×460 px at default UI scale, movable. Dialogs about 360 px wide.
- **Text**: everything is translated; allow texts to be 30% longer than English.
- **Names**: characters are shown as "First Surname" (WoW: Forever has no realms), in their class color, with a class icon where there is room.
- **Glyphs**: small (about the text height), next to the name, never replacing it. Small actions on a nickname (edit, clear) are glyph buttons next to it; actions on a whole person (Edit, Forget) are text buttons at the bottom of its panel.
- **Colours**: each glyph keeps one colour everywhere (Main and Confirmed gold, Renamed blue, Guild green, Unconfirmed, Listed and Added grey); a nickname quoted in a sentence (dialogs, notices) takes the colour of its glyph. Unconfirmed names are shown in grey italics. "Online" is green.

## Frames

### 1. First-Login Prompt (Dialog)

Shown once per character, on its first login with the add-on.

- If no identity exists yet: "Set <Character> as your identity's main character?" with one line explaining what an identity is. A checkbox to set a nickname for the whole identity (instead of the main character's name); when checked, a nickname input appears with the character's name as placeholder.
- If an identity exists: "Link <Character> to <identity name>?", with one line naming the characters already in it (class colours).
- Buttons: **Link**, **Not this character**. Closing it asks again next login.
- Small note: "Nothing is shared until a character is linked."

### 2. Main Window — Tab "My identity"

- Header: the name I'm shown under — my nickname, or my main character's name with the crown glyph when no nickname is set — with an edit glyph button; and a one-line sharing status ("Shared with: Guild, Friends" / "Not shared").
- List of my characters, with a count ("3 of 5 linked"): class icon, name, ruleset (Normal / PvP / Hardcore…), level, last played, a **Main** marker (crown; a dim crown on the other linked characters moves it there), a **Linked** checkbox. The character I'm logged in on shows "Online" (green) after its name.
- One line under the list: "Other players see your nickname instead of your main character's name; each of them can still give you their own nickname, which only they see."
- Button: **Sharing settings** (opens frame 7).

### 3. Main Window — Tab "People"

Everyone I know about, one row per person.

- Search box; filter dropdown (All / Confirmed / Renamed / Guild / Unconfirmed); sortable by name and last seen (column headers); **New person** (frame 5) for a player without the add-on.
- Row: source glyph, nickname, and when the person is online the character they are playing (class color) right after it; number of characters; last seen ("Online" in green).
- Selecting a row shows a detail panel (right side or below):
  - source glyph and nickname;
  - under the nickname, small and grey: the nickname that applies without mine, if any;
  - characters, two lines each: the name (class color) with the main crown and, right after, "Online" (green) or the last seen time; under it, small and grey, a glyph for the character's state, without text (Confirmed, Listed, Guild or Added by me), then level · ruleset.
  - **Edit** (frame 5) and **Forget** (with confirmation) at the bottom of the panel, aligned right, Edit on the left of Forget.
- Empty state: how to start (right-click a player, or pick from recent contacts, the group or the guild), with one **Pick characters** button (frame 6; the picked character starts a new person in the editor).

### 4. Main Window — Tab "Guild"

Visible only in a guild.

Same list and detail panel as the People tab, with a status strip on top, but no search, filter or **New person**: everyone listed is already in the guild, and a member with an unknown identity is linked from the right-click menu (frame 8).

- Header: guild name, and the **Update now** button on the right.
- Status strip: sharing on/off, the trusted ranks as a rank name ("Officer and above", set in the Guild settings) and my rank; sync status (last update; then, among the guild's characters, the number of identities, of alts, and of characters with an unknown identity, e.g. "24 identities · 31 alts · 6 unknown").
- List of the guild's members, one row per person: source glyph, nickname (mine first with the guild's one small and grey after it when mine replaces it; characters not linked to any identity show their name in italics with the Unconfirmed glyph), number of characters, last seen ("Online" in green).
- Selecting a row shows the same detail panel as the People tab (frame 3).

### 5. Person Editor (Dialog)

Create or edit a person I linked, or add alts to a person shared by the player. Opened from **New person** (People tab), **Edit** (People and Guild tabs), and the right-click menu (**New person**, **Link to a person**).

- **Custom nickname** input (labelled so, since it overrides the person's own name), empty when no nickname is set, with as placeholder the main character's name, or the player's own nickname when the person is shared by the player. Typing a nickname overrides it; a clear glyph button (cross) right of the input removes my nickname, back to the one that applies without it.
- Characters list with the main crown (movable for a person I linked, fixed for a person shared by the player) and each character's state glyph (Confirmed, Listed, Guild, Added by me), as in the People tab; remove buttons only on alts added manually; the main of a person I linked can't be removed, so its last character is always the main. What is shared by the player cannot be changed. Removing a person is done with **Forget**.
- A new person starts from one character, which becomes its main.
- Add a character with two buttons: **Current target**, and **Pick characters** (opens frame 6). A character belongs to one person only: one that already belongs to a person cannot be added, and the picker doesn't list it.
- Buttons: **Forget** (with confirmation), **Save**, **Cancel**.

### 6. Character Picker (Dialog)

Opened by **Pick characters** in the person editor, to add characters to the person being edited. Also opened from the People tab's empty state: there, picking a character opens the person editor (frame 5) for a new person, with that character as its main.

- Source tabs, in this order: **Recent contacts** (whispered or grouped with), **Group** (current party or raid), **Guild** (not "roster", which means something else in many guilds).
- Search box; list with class icon, name, level, rank (guild); multi-select.
- Only characters that don't belong to any person yet are listed.
- Buttons: **Add**, **Cancel**.

### 7. Settings (in the Game's Options → AddOns Tab)

The game's own settings list: its section headers and controls. Each setting is explained in its tooltip. A section that needs more information has one line of text under its header.

- **Sharing**: under the header, "Nothing is shared until a character is linked. Your identity is your nickname and your linked characters." Guild, Friends (WoW and Battle.net), My party or raid, People I whisper, Selected people (the players I chose with **Share my identity** in the right-click menu; an alternative to sharing with everyone I whisper or group with); each tooltip says who sees what. Guild and Friends are on by default, the others off.
- **Display**: show nicknames in chat (on other add-on users' messages and on characters I or my guild linked), nickname in tooltips (dropdown: After the name / On its own line / Hidden; its tooltip warns that "After the name" changes the tooltip's first line, which other tooltip add-ons may also change), show other characters in tooltips (the "Also:" line), show the minimap button, show Who's Who in the add-on compartment next to the minimap (both on by default; clicking either opens or closes the main window, right-click opens a menu with **My identity** and **Settings**).
- **Data**: **Forget me** (my characters and my nickname; players who know me forget me too once Who's Who reaches them, which some never are) and **Forget everyone else** (every person I know about), each with a **Forget** button and a confirmation whose button is **Forget**.

**Guild** subcategory (Options → AddOns → Who's Who → Guild), shown only in a guild and only to officers and above, who are the only ones who can change it:

- **Enable Who's Who for the guild**.
- **Trusted ranks**: rank dropdown ("Officer and above" by default). Identities set by these ranks are used by the whole guild. Ranks below officer can be trusted, but never change these settings.
- **Data**: forget the identities set by the guild (with a confirmation).

### 8. In-World Touches (Not Windows)

- **Tooltip** on a player: the nickname only (no source, no source glyph), in a soft color, shown one of two ways depending on the setting: in brackets after the character's name on the same line, e.g. `Character Name (Ann)` — left out when it's the same as the character's name (e.g. a person without a nickname, hovered on their main) —, or on its own line under the name, e.g. `Who's Who: Ann`. A separate line `Also: Alt One, Alt Two` when there is room (Listed glyph on alts not seen yet), controlled by its own setting (frame 7).
- **Chat line**: `[Character Name] (Ann): hello` — the nickname in round brackets right after the usual name, in a soft color, so it can't be mistaken for a channel tag like `[Guild]`; left out when it's the same as the character's name. The message itself is unchanged.
- **Right-click menu** on a player (target, party, chat name, guild roster): **New person** (opens the person editor with this character as main) and **Link to a person** (person chooser, frame 9, then the person editor with this character added); both only when the character doesn't belong to a person yet. **Show in Who's Who** (opens the record we have for this person, in the People tab) only when the character already belongs to a person. **Share my identity** (sends my identity to that player and adds them to my selected people) only when the "Selected people" sharing option is on.
- **Notices**: chat lines prefixed "Who's Who:", e.g. "3 people updated from the guild"; the same notice can also show as a toast. Links in notices use the game's bracketed link style.
  - Automatic changes: one line per change, e.g. "Bob is now Ann's shared identity (2 characters moved). Review this change" — "Review this change" is a link that opens frame 11 on that change. Several changes at once are grouped: "3 changes from shared identities. Review these changes".

### 9. Person Chooser (Dialog)

Opened by **Link to a person** in the right-click menu, to choose the person the clicked character belongs to.

- Title "Link to a person", and the question "Which person does <Character> belong to?" (character in class color).
- Search box; list of the people I know, one row per person: source glyph, nickname, main character's name (class color, small), number of characters; sortable by nickname; single selection.
- Buttons: **Link** (opens the person editor, frame 5, with the character added), **Cancel**.

### 10. Confirmation (Dialog)

The game's standard confirmation popup (no title bar), for actions that can't be undone: **Forget** in the People and Guild tabs and the person editor, and the **Data** actions in Settings.

- A question naming what is affected, e.g. "Forget Tank Bob?" (nickname with its source color).
- One line on the consequence, e.g. "Tank Bob and their 2 characters are removed from your list. This can't be undone."
- Buttons: the action's own name (e.g. **Forget**), **Cancel**.

### 11. Main Window — Tab "Review"

What Who's Who changed in my links without me doing it. Lets me check each change and fix it by hand.

- Tab label with a count of unread entries, e.g. "Review (2)"; the panel title is "Changes to review", with the subtitle "What Who's Who changed on its own"; the count is the number of unread rows.
- Unread rows are marked (gold bar on the left); selecting a row marks it as read. A **Mark all as read** button in the header marks every row as read at once.
- List, newest first, one row per change: its kind and date and time, then a one-line summary (no glyphs in the list). Three kinds:
  - Merged: "Bob (created by me) became Ann's shared identity" — characters moved, and whether my nickname "Bob" was kept or dropped because I had already named Ann.
  - Alt moved: "Alt One left Carl: its player declares it in Dana's identity".
  - Dropped: "Alt Two is no longer in Ann's identity: the player removed it".
- Selecting a row shows a detail panel (same place as the People tab's): the change in one sentence; the person before → after on one line (glyph and nickname on each side, the player's own nickname small and grey); each character involved with what happened to it (already there, moved and declared, moved and still added) and its state glyph; and **Show person** (opens it in the People tab, where I can rename it or remove an added alt) and, later, **Undo**.
- Only the most recent changes are kept (about 100); a line under the list says so.
- Empty state: "Nothing has changed on its own yet. When a player you linked installs Who's Who, you'll see it here."

## Open Questions

- A guild-level nickname on a person that already has a confirmed identity: probably not allowed.
