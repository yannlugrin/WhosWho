# Changelog

All notable changes to Who's Who. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Tooltips**: the nickname of the people you know, after their name or on its own line, and an "Also:" line with their other characters, each adjustable in the settings.
- **People who don't use Who's Who.** Start a person from one of their characters and link their other characters to them, or add an alt you know to someone's shared identity. A small mark shows what the player didn't share themselves.
- **Right-click menu** on a player, from their unit frame, the guild roster, your friends and Battle.net friends, recent contacts or their name in chat, with what applies to that character: link it to a person, show that person in the People tab, make it their main or unlink it. On your own characters, it opens My identity.
- **Forget** a person from the People tab.
- **Notes** about the people you know, in the People tab, seen only by you. The start of the note shows in their tooltips, which you can turn off in the settings.
- **Your nickname for a person**, set or removed from the People tab.
- **Turning a sharing option on**, joining a guild or adding a friend now sends your identity to the players it adds, and gets theirs back, without waiting for your next login.

### Fixed

- **My identity**: clicking the Name, Level or Last played header sorts your characters.
- **Logout**: your guild, friends and group receive the logout announcement, and logging out or reloading no longer throws an error. Canceling a logout tells them you stayed.

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

[Unreleased]: https://github.com/yannlugrin/WhosWho/compare/0.1.0-beta.1...HEAD
[0.1.0-beta.1]: https://github.com/yannlugrin/WhosWho/releases/tag/0.1.0-beta.1
