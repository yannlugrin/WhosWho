# Contributing to Who's Who

Thanks for helping. Who's Who is an add-on for **World of Warcraft: Forever**; the other flavors are not supported.

## Reporting a problem

Open an issue with what you did, what you expected and what happened. For a problem between players, turn on `/ww debug on` on both sides, reproduce it, and paste the lines Who's Who printed. Include any Lua error in full (BugSack, or `/console scriptErrors 1`).

## Setting up

1. Clone the repository and link it into the Forever client's `Interface\AddOns` folder under the name `WhosWho`, for example on Windows (cmd):
   ```
   mklink /J "<Forever client>\Interface\AddOns\WhosWho" "<clone>"
   ```
2. Fetch the libraries. `Libs/` is not in the repository: the [BigWigs packager](https://github.com/BigWigsMods/packager) builds it from the `externals` in `.pkgmeta`. It needs `git` and `svn` (Subversion). From the repository root:
   ```
   mkdir -p .release
   curl -fsSL -o .release/release.sh https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh
   bash .release/release.sh -dlz
   ```
   Then link `Libs` to the libraries it built, for example on Windows (cmd): `mklink /J Libs .release\WhosWho\Libs`. Running `release.sh -dlz` again refreshes them. Never copy library files into the repository; a new library goes in `.pkgmeta` and `Libs.xml`.
3. Restart the client: `/reload` does not pick up new files.

## Checking your change

Every push runs the same checks (`.github/workflows/checks.yml`):

- [luacheck](https://github.com/lunarmodules/luacheck) from the repository root (`luacheck .`), with the configuration in `.luacheckrc`.
- The offline suites, under plain Lua 5.1:
  ```
  lua Tests/Crypto-Test.lua
  lua Tests/Model-Test.lua
  lua Tests/Comm-Test.lua
  lua Tests/Locale-Test.lua
  ```

A change to what players exchange also needs a run between two clients: [README-Testing.md](README-Testing.md) is the plan.

## Code

- Lua 5.1, the add-on namespace (`local _, ns = ...`), no new globals; functions are `local function` where they are defined.
- Detect APIs before using them; never compare build numbers. Registering an event the client doesn't know throws on Forever.
- Values read from the game may be secret: check `issecretvalue` before comparing, storing or concatenating them.
- Every text players see goes through `L["..."]` with its English key in `Locales/enUS.lua`, and its translation in `Locales/frFR.lua` (the locale suite fails on a key missing from either).
- Comments say what the code does or why, in a short sentence.

## Documentation

Update the documents your change touches, in the same pull request:

- [README.md](README.md): what players can do, and the commands.
- [README-Technical.md](README-Technical.md): how it is built (file map, data, protocol).
- [README-Design.md](README-Design.md): the frames, as designed.
- [README-Testing.md](README-Testing.md): the in-game tests.
- [CHANGELOG.md](CHANGELOG.md): one line for players under `## [Unreleased]`, in the section that fits (Added, Changed, Fixed, Removed, Security), following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Commits and pull requests

- One subject line saying what the change does and why; a body only for context the diff doesn't show.
- One topic per pull request, with the checks passing.

## Releasing (maintainers)

1. In `CHANGELOG.md`, rename `## [Unreleased]` to the version and date, `## [0.1.0-beta.1] - 2026-10-07`, add an empty `## [Unreleased]` above it, and update the links at the bottom.
2. Commit, then tag the commit with the version itself (`0.1.0-beta.1`) and push the branch and the tag. A tag containing `alpha` or `beta` makes an alpha or beta release; any other tag, a full release.
3. `.github/workflows/package.yml` packages the add-on and uploads it to CurseForge, then creates the GitHub release (a pre-release for alpha and beta) with that version's section of the changelog. It stops if the changelog has no section for the tag.
