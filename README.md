# Who's Who

Link all your characters into one identity, choose who can see it, and recognise people across their alts.

For **World of Warcraft: Forever**. Source code, issues and releases: [github.com/yannlugrin/WhosWho](https://github.com/yannlugrin/WhosWho).

> **In development.** What is marked *coming* isn't built yet. Please report what goes wrong or any suggestion (see [Reporting a problem](#reporting-a-problem)).

## Features

- **One identity for all your characters.** Link the characters you play and pick your main: you're shown under its name, or under a nickname if you set one. The first time you log in on a character, Who's Who asks whether to link it. Manage it all in the **My identity** tab, or with `/ww link`, `/ww main` and `/ww nick`.
- **You decide who sees it.** Share with your guild, your friends, your party or raid, or the people you whisper. Guild and friends are on by default, and nothing is shared until you link a character.
- **Recognise people across their alts.** When someone shares their identity with you, the **People** tab lists them with their characters, who is online and when you last saw them. Their nickname shows next to their name in chat and in their tooltip, on every character they linked, and the tooltip lists their other characters.
- **Your own nickname and notes.** In the People tab, give anyone your own nickname for them and write notes about them, seen only by you, or forget them. The start of the note shows in their tooltip.
- **Always up to date.** Your identity reaches the people you share with when you log in, level up, log out, join a group or a guild, add a friend, turn a sharing option on or whisper someone, and people who come online or join your group later get it too. The people you whisper keep getting it for a time you choose in the settings (3 hours by default).
- **Link players who don't use the add-on.** Start a person from one of their characters and link their other characters to them, or add an alt you know to someone's shared identity. A small mark shows what the player didn't share themselves.
- **Right-click any player**, from their unit frame, the guild roster, your friends, recent contacts or their name in chat, to link their character to a person, show that person, make it their main or unlink it.
- *Coming:* **Your whole guild, known to everyone.** Guild members pass on to each other the identities guildmates shared, so you recognise every guildmate who uses Who's Who, even one you've never been online with.
- *Coming:* **Review** what Who's Who changed on its own, for example when a player you linked yourself starts sharing their own identity.

Open the window with the minimap button, the add-on compartment next to the minimap, or `/ww open`. Right-click the button for a menu.

## Privacy

- Nothing leaves your client as long as you haven't linked a character to your identity.
- A character you unlink tells the players who knew it, each time you log in on it, that it belongs to no identity, so they drop it, even if they were offline when you unlinked it. That message doesn't carry your identity: nobody can trace the character back to you from it.
- Who's Who never sends BattleTags or Battle.net account information.
- Your identity is signed with a key that stays on your computer, so nobody else can change it, even when it is passed along by other players.
- What a player shares about themselves can't be changed by others. You can still give anyone your own nickname for them; only you see it.
- **Forget me** in the settings unlinks all your characters and removes your nickname; players who know you forget you too, once Who's Who reaches them.

## Commands

| Command | What it does |
|---|---|
| `/ww open` | Open the Who's Who window |
| `/ww status` | The version, your nickname, this character's link and how many characters are linked |
| `/ww main` | Make the character you are playing your main |
| `/ww link` / `/ww unlink` | Link or unlink the character you are playing |
| `/ww nick <name>` | Set your nickname (`/ww nick` alone goes back to your main character's name) |
| `/ww scope` | Who you share your identity with: guild, friends, whispers, group, each on or off |
| `/ww scope <scope> <on\|off>` | Turn one of them on or off, for example `/ww scope group on` |
| `/ww people` | The 10 people you saw most recently, with their characters |
| `/ww people <character name>` | The people with a character of that name |
| `/ww settings` | Open the Who's Who settings |
| `/ww debug <on\|off>` | Print every Who's Who message sent or received in chat, to report a problem |

## Looks

The windows use the default game look. With EllesmereUI installed, they take your EllesmereUI theme.

## Reporting a problem

Open an issue on [GitHub](https://github.com/yannlugrin/WhosWho/issues) with what you did, what you expected and what happened. For a problem between two players, turn on `/ww debug on` on both sides, reproduce it, and add the lines Who's Who printed.

## Contributing

Contributions are welcome. [CONTRIBUTING.md](https://github.com/yannlugrin/WhosWho/blob/main/CONTRIBUTING.md) explains how to set up the add-on from the repository, run the checks, and which documents to update.

## License

MIT. See [LICENSE](https://github.com/yannlugrin/WhosWho/blob/main/LICENSE).
