# Changelog

All notable changes to Who's Who. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Characters**: your record now keeps each linked character's race, and when it reached the highest level, for features to come.
- **Updates**: once a session, Who's Who tells you in chat when another player's is a newer release than yours (any newer version while yours is a pre-release). You can turn it off in the settings, under Updates.
- **`/ww status`** and the Diagnostic page show the newest Who's Who version another player's add-on announced this session.
- **Guilds**: in My identity, "In my guilds" sets a nickname and a main for each guild your characters are in; only that guild's members see them.
- **Guild requests**: the guild master and officers can suggest a nickname or a main to a member, from the right-click menu in the Guild tab; the member accepts, edits or refuses it. Officers see each request, and whether it's done, in the member's panel and in a Requests list, and dismiss it there.
- **Guild invites**: from a character outside your guild, "Invitation…" on its line in My identity's "In my guilds" asks the guild's officers you know of to invite it (or whisper `ginv` to one); the officer is asked whether to invite it when another character of your identity is in the guild. The guild master or an officer turns it on in the guild's Who's Who settings.

### Changed

- **Protocol**: Who's Who 1.0 speaks a new version of its protocol and no longer exchanges with the beta versions. It skips the records and guild lists it already holds without unpacking them.
- **Guild sharing**: a guild member who is also your friend now gets both your linked characters and what your guild's rule adds. With your Guild scope off, a member of a guild enforcing linking who is not your friend sees only the characters its rule adds, without your nickname.

### Fixed

- **People**: a player's old identity, whose characters now show under their new one, no longer stays in your saved data without any character.
- **Guild sharing**: in a group, the characters a guild enforcing linking adds to your record are no longer sent to group members outside that guild.

## [0.4.3] - 2026-10-19

### Fixed

- **Guild links**: a member who logged in while no officer they had met was online no longer stays without the guild's links for the session: an officer passes them on as soon as one is online.
- **Guild lists**: a member whose list was more recent but lacked the guild's links or other members no longer waits for luck to get them: the first member holding them who takes that list announces its own back, and the member takes it.

## [0.4.2] - 2026-10-19

### Changed

- **Guild lists**: in a large guild, Who's Who no longer freezes the game for a moment each time it announces you or receives a guild list: your own list is hashed again only when it changed.
- **Records received**: checking a record's signature no longer makes the game stutter: the check is spread over more frames, in smaller pieces.
- **Messages from other players**: Who's Who no longer handles them during combat, and handles at most one record or guild list per frame, so a burst of them no longer lowers your frame rate.
- **Combat**: Who's Who no longer checks signatures or sends records and guild lists during combat; they wait for its end.

### Fixed

- **Mac**: Who's Who could fail to load on Mac, leaving an empty window on screen.

## [0.4.1] - 2026-10-18

### Fixed

- **Guild lists**: logging out no longer makes guild members ask you for your guild list or settings, which you could no longer send.

## [0.4.0] - 2026-10-18

### Added

- **Guild links**: the guild master and officers can link members' characters for the whole guild, from the Guild tab's right-click menu: to a member's identity, or to a new person for someone who doesn't use Who's Who, with its own nickname and main. Every member who uses Who's Who sees them, even for players they never met; what a player shares about themselves always comes first. When a player links characters the guild had linked for them, the guild's link gives way: the guild master or an officer chooses to move the rest to that player or keep it apart.
- **Who's Who in the guild window**: the Who's Who tab of the game's guild window now lists your guild by identity, like the game's roster: search, offline members, columns to sort by, and a panel next to the window with the person's characters, the one in the guild open with its zone and rank. The guild master and officers reach the guild's settings from a button there, and can link characters for the guild from its right-click menus.
- **Key bindings**: in the game's Key Bindings, a Who's Who section lets you set a key to show or hide the Who's Who window, and one to show or hide the guild window on its Who's Who tab (also `/ww guild`). None is set by default.

### Fixed

- **Guild roster**: removing a member or editing a note in the game's guild roster could be blocked, blaming Who's Who, after using a Who's Who entry in the roster's right-click menu. Who's Who no longer adds its entries to that menu; its own tab in the guild window has them.
- **Guild lists**: a member whose list hadn't changed yet no longer offers it to the guild; the members who asked for it got nothing.
- **Linked characters required by the guild**: a character you share with the guild without linking it now shows its new name to the guild after a rename, and its new ruleset after a Hardcore death.
- **Linked characters required by the guild**: when the character a guild member is shown under left the guild, and their main isn't in it, Who's Who could raise errors in its windows until that member shared again; they're now shown under another of their characters.
- **Notes and nicknames**: when the person you're editing merges into another or is forgotten before you save, the editor now says so and keeps what you typed, instead of closing and losing it.
- **Minimap button**: its tooltip and its settings now say that a click shows or hides the window, as it does.
- **Guild settings**: right after you join a guild, a member of it can no longer change the Who's Who settings you hold for another of your guilds.
- **Guild settings**: a guild member can no longer stop you from getting the officers' new settings by sending you a record of their own first.
- **Guild lists**: a guild member can no longer pass off a list of their own as an officer's and stop you from getting the officer's list; members still on 0.3.0 now recognise a list without guild records as their own.

## [0.3.0] - 2026-10-14

### Changed

- **Record format**: identities and guild settings are signed in a new format that later versions can add to without breaking this one. Players on 0.2.0 and on this version can't read each other's identities until both have updated. Guild masters and officers: change your guild's settings once after updating, so new members get them.

### Security

- **Messages from other players**: Who's Who no longer unpacks a record or a guild list from a player it doesn't take them from, and refuses one too long, so another player can't freeze your game for a moment with a crafted message.

## [0.2.0] - 2026-10-14

### Added

- **Guild settings**: the guild master and officers get a Who's Who tab in the guild panel, to enable Who's Who for the guild. The setting reaches every member who uses Who's Who, signed so that only those ranks can change it; `/ww status` shows it.
- **Your whole guild, known to everyone**: once Who's Who is enabled for the guild, members pass on to each other the identities guildmates shared with their guild, so you recognise every guildmate who uses Who's Who, even one you've never been online with. An identity only an officer passed on to you shows as listed by the guild until the player confirms it. One known only through the guild is forgotten once they leave it, or you do.
- **Guild tab**: once Who's Who is enabled for your guild, the window gets a Guild tab listing its members by identity, mains and alts together, and the members nobody knows yet, with how many of each.
- **Linked characters required by the guild**: the guild master or an officer can require the members' characters in the guild to be linked. Each member who uses Who's Who is asked first: link those characters, share them with the guild only without linking them, or refuse, and Who's Who then shares nothing with that guild, which may go against its rules. Shared characters are known to the guild's members under that member's identity, even with guild sharing off, shown to the guild only, and forgotten once they leave it. Once you accepted, only leaving the guild stops sharing with it; the Guild tab shows your answer, and lets you change a refusal.
- **Diagnostic**: a Diagnostic page in the settings turns the diagnostic mode on (also `/ww debug on`): Who's Who keeps its last 1000 messages and shows them in a table, with a few stats; printing them in chat is now an option. Turned off, the messages kept are deleted at logout.

### Changed

- **People tab filter**: show your friends, your guildmates, everyone else, or any mix of them, instead of filtering by how an identity was confirmed. A Battle.net friend's BattleTag shows in their detail panel.
- **Last seen**: a guild member you haven't seen online no longer gets a last seen time from the guild roster, only their level.

### Fixed

- **Guild left while offline**: a character removed from its guild while offline, or whose guild disbanded, no longer counts as in it at its next login.

## [0.1.1] - 2026-10-10

### Fixed

- **Unlinked characters**: receiving one could throw an error.
- **Joining a guild**: your identity now reaches the guild's members right away, and theirs reach you. The game drops a new member's add-on messages to the guild until their next login, so until then Who's Who whispers each online member instead.
- **Guild members who just joined** are answered even before your guild roster lists them.
- **Logging in**: a guild member or friend in your guild whom you whispered before logging out no longer gets your login announcement a second time by whisper.
- **Answers by whisper**: a guild or group member who answers your announcement by whisper is now recognised at once, without waiting for their next message to the guild or group, and a character they unlinked disappears just as fast.

## [0.1.0] - 2026-10-10

First stable release, for World of Warcraft: Forever.

Who's Who links your characters into one identity and lets you recognise the people you play with on all their characters:

- **One identity for all your characters**, with a main and a nickname, shared only with the players you choose: your guild, your friends, your group or the players you whisper. It is signed with a key that stays on your computer, so nobody else can change it.
- **People you know**, in the People tab, with their characters, who is online, your own nickname for them and your private notes. Characters of players who don't use Who's Who can be linked to them by hand.
- **Recognised everywhere**: their nickname in chat and in tooltips, the other characters they play, and a right-click menu on any player to link, show or unlink their character.
- **Settings** in Options → AddOns, slash commands under `/ww`, a minimap button, and a French translation.

Changes since 0.1.0-beta.1:

### Added

- **Tooltips**: the nickname of the people you know, after their name or on its own line, and an "Also:" line with their other characters, each adjustable in the settings.
- **People who don't use Who's Who.** Start a person from one of their characters and link their other characters to them, or add an alt you know to someone's shared identity. A small mark shows what the player didn't share themselves.
- **Right-click menu** on a player, from their unit frame, the guild roster, your friends and Battle.net friends, recent contacts or their name in chat, with what applies to that character: link it to a person, show that person in the People tab, make it their main or unlink it. On your own characters, it opens My identity.
- **Forget** a person from the People tab.
- **Notes** about the people you know, in the People tab, seen only by you. The start of the note shows in their tooltips, which you can turn off in the settings.
- **Your nickname for a person**, set or removed from the People tab.
- **Turning a sharing option on**, joining a guild or adding a friend now sends your identity to the players it adds, and gets theirs back, without waiting for your next login.
- **Whispers count for a time you choose** (3 hours by default, in the settings): the people you whisper stay recognised across a reload or a new login, and get your identity and its updates while you talk to them.
- **Fewer messages**: a reload, a quick relog of the same character or a canceled logout no longer sends announcements the other players already have.
- **Unlinked characters stay anonymous**: they never send your identity again, and the players who knew them drop them without being able to tell who they belonged to.
- **Clear whisper history** next to the Whispers option in the settings. While the settings are open, nothing is sent until you close them.

### Fixed

- **My identity**: clicking the Name, Level or Last played header sorts your characters.
- **Logout**: your guild, friends and group receive the logout announcement, and logging out or reloading no longer throws an error.

## [0.1.0-beta.1] - 2026-10-07

First beta, for World of Warcraft: Forever.

### Added

- **One identity for all your characters.** Link the characters you play, pick your main and set a nickname, from the My identity tab or with `/ww link`, `/ww unlink`, `/ww main` and `/ww nick`. The first time you log in on a character, Who's Who asks whether to link it.
- **You decide who sees it.** Share with your guild, your friends, your party or raid, or the players you whisper, each on or off in the settings or with `/ww scope`. Guild and friends are on by default, and nothing is shared until you link a character.
- **Identities shared between players.** Your identity goes out when you log in, level up, log out, join a group or whisper someone, and players who come online or join your group later get it too. It is signed with a key that stays on your computer, so nobody else can change it, even when it is passed along.
- **Characters confirmed by the game.** A character counts as confirmed once it has sent its identity itself. A character you unlink tells the players who knew it, so they drop it even if they were offline when you unlinked it.
- **Nicknames in chat**, after the sender's name, on every character of the people you know.
- **People tab**: everyone who shared their identity with you, with search, filter, sorting, who is online, and their characters.
- **Minimap button and add-on compartment entry**, each of which can be hidden.
- **Settings** in Options → AddOns: sharing, display, and **Forget me** / **Forget everyone else**.
- **Commands**: `/ww status`, `/ww people`, `/ww settings`, and `/ww debug` to print every message sent or received when you report a problem.
- **EllesmereUI**: its look, when it is installed.
- **French translation.**

[Unreleased]: https://github.com/yannlugrin/WhosWho/compare/0.4.3...HEAD
[0.4.3]: https://github.com/yannlugrin/WhosWho/compare/0.4.2...0.4.3
[0.4.2]: https://github.com/yannlugrin/WhosWho/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/yannlugrin/WhosWho/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/yannlugrin/WhosWho/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/yannlugrin/WhosWho/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/yannlugrin/WhosWho/compare/0.1.1...0.2.0
[0.1.1]: https://github.com/yannlugrin/WhosWho/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/yannlugrin/WhosWho/compare/0.1.0-beta.1...0.1.0
[0.1.0-beta.1]: https://github.com/yannlugrin/WhosWho/releases/tag/0.1.0-beta.1
