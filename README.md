# Who's Who

Link all your characters into one identity, choose who can see it, and recognise people across their alts.

For **World of Warcraft: Forever**.

> **In development.** Nothing is shared yet: this build only stores your own identity locally.

## Features

- **One identity for all your characters.** The first time you log in on a character, Who's Who asks whether to link it. Pick your main character: you're shown under its name, or under a nickname if you set one.
- **You decide who sees it.** Share with your guild, your friends, or the people you whisper and group with. Guild and friends are on by default, and nothing is shared until you link a character.
- **Recognise people across their alts.** When someone shares their identity with you, their nickname appears next to their messages in chat and in their tooltip, on every character they linked.
- **Link players who don't use the add-on.** Group someone's characters and give them a nickname, or add an alt you know to someone's shared identity. A small mark shows what the player didn't share themselves.
- **Share your links with your guild** (optional), so the whole guild benefits without everyone installing Who's Who. Guild officers decide which ranks may share.

## Privacy

- Nothing leaves your client as long as you haven't linked a character to your identity.
- Who's Who never sends BattleTags or Battle.net account information.
- Your identity is signed with a key that stays on your computer, so nobody else can change it, even when it is passed along by other players.
- What a player shares about themselves can't be changed by others. You can still give anyone your own nickname for them; only you see it.

## Commands

| Command | What it does |
|---|---|
| `/ww status` | The version, your nickname, this character's link and how many characters are linked |
| `/ww main` | Make the character you are playing your main |
| `/ww link` / `/ww unlink` | Link or unlink the character you are playing |
| `/ww nick <name>` | Set your nickname (`/ww nick` alone goes back to your main character's name) |
| `/ww scope` | Who you share your identity with: guild, friends, whispers, group, each on or off |
| `/ww scope <scope> <on\|off>` | Turn one of them on or off, for example `/ww scope group on` |
| `/ww people` | The 10 people you saw most recently, with their characters |
| `/ww people <character name>` | The people with a character of that name |
| `/ww debug <on\|off>` | Print every Who's Who message sent or received in chat, to report a problem |

## Looks

Who's Who uses the default game look. With EllesmereUI installed, its windows follow your EllesmereUI theme.

## License

MIT. See [LICENSE](LICENSE).
