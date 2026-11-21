# Privacy

Spellmind has no account. What leaves your PC goes to the AI you chose, only when you ask it something; the app's check for a new version on GitHub; and, with the app, the ground you walk for shared roads, which you can turn off ([below](#shared-roads)). The Spellmind authors receive nothing else: no telemetry, no analytics, no crash reports.

## What the addon reads in the game

What your character is and has, so the panel and your AI can give advice that fits:

- class, race, level, spec, zone and position on the map;
- stats, gear, bags, talents, spells, professions, reputations and gold;
- your quest log and the quest text the game shows you;
- the dungeons and quests around your level.

**Never read:** your realm, your guild, your account or Battle.net details, other players' names, and chat. The one exception: the addon reads your character's name in a single place, only to blank it out of quest text the game wrote it into (`ns.Redact` in `Core.lua`). The name is never kept, saved or sent; a test checks this.

## What is sent, and where

| What | Where it goes | When |
|---|---|---|
| Your question, and the game data you allow (above) | The desktop app on your PC, through the screen (see [screen-reading.md](screen-reading.md)) | When you ask, and as the data changes |
| Your question and that game data | **Your AI** (OpenAI, Anthropic, xAI, Google, or the service you set under Other) | Only when you ask something |
| Your leveling guide's link | Your AI, which reads the page with its web search | Only when you import a guide |
| Web searches your AI chooses to make | Your AI's own search | When web search is on and your AI decides to look something up |
| A request for the newest version (no data about you or the game) | GitHub, this repository's releases page | 30 s after the app starts, then every 6 hours, while "Check for new versions of Spellmind" is on (it is by default) |
| The ground you walked: squares of the world (8 yards each), which way you crossed each and whether you swam it, under a random id the app made (see [Shared roads](#shared-roads)) | The Spellmind roads server, run by the Spellmind authors on Cloudflare | About once a day while the app runs, while "Share the ground I walk" (the Route tab) is on (it is by default) |
| A request for the shared roads (no data about you or the game) | The same server | About once a day while the app runs |

Your AI's own privacy policy covers what it does with your messages. If you sign in with a ChatGPT plan, OpenAI's terms for that plan apply.

**You choose the game data.** In game, Settings → "Game data the AI gets" has a switch for each part (gear, bags, quests, talents and so on) and one for all of it. With it off, your AI gets only your class, level and zone. "What the app has now", in the same section, shows each part it has.

## Shared roads

The route follows the roads players walk, so every player's route gets better as people play. The addon records the ground you walk while the route is on (squares of the world, 8 yards each, and which way you crossed from one into the next); with the app, what's new of it goes to the Spellmind roads server about once a day.

- **Sent:** those squares and crossings, whether you swam them, the game's and the addon's version, and a random id the app made for itself (`%APPDATA%\Spellmind\roads.json`), tied to nothing else.
- **Never sent:** when you walked (beyond the day it arrived), the order you walked it in, your character's name, realm or guild, your account, or anything else in your saved data. The app reads only the ground from it.
- **Shared back:** a crossing becomes part of the roads only once at least 3 different installs walked it, so no one player's path ever shows.
- **Kept:** 90 days, then dropped.
- **Off:** "Share the ground I walk" on the Route tab. With it off on every account on your PC, the app sends nothing more and deletes what it sent before.
- **The server** is a Cloudflare Worker that stores uploads and serves the roads; it keeps no IP addresses. Cloudflare's own privacy policy covers the connection. Its code is in [server/roads](../server/roads).

## What stays on your PC

- **Your API keys and your ChatGPT sign-in:** in Windows' Credential Manager, under "Spellmind". Never in a file, never in the game, never in the log.
- **Settings:** `%APPDATA%\Spellmind\config.json`.
- **The game data the app was last given,** so a question after a restart still has it: `%APPDATA%\Spellmind\link`.
- **The log:** `%APPDATA%\Spellmind\logs`, kept 7 days. It has what the app did (connected, a question's size, an error's kind), not your questions or answers. Keys and tokens are scrubbed from every line.
- **The ground you walk:** in the game's own saved data for the addon, as your trails. "Forget my trails" on the Route tab clears it.
- **Your chat history:** in the game's own saved data for the addon (`WTF\Account\...\SavedVariables\Spellmind.lua`), like any addon's settings.

## Removing everything

1. Uninstall the app (Windows Settings → Apps → Spellmind).
2. Delete `%APPDATA%\Spellmind`.
3. In Credential Manager → Windows Credentials, remove the entries under "Spellmind".
4. Delete the `Spellmind` and `Spellmind_S001` to `Spellmind_S200` folders from `World of Warcraft\_forever_\Interface\AddOns`, and `Spellmind.lua` from your `SavedVariables` folders.

## Questions

Open an issue on [GitHub](https://github.com/jcouser/spellmind/issues), or see [SECURITY.md](../SECURITY.md) for anything sensitive.
