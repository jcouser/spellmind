<p align="center">
  <img src="art/source/logo.png" alt="Spellmind" width="120">
</p>

<h1 align="center">Spellmind: AI Companion</h1>

<p align="center">
  An AI companion for <b>World of Warcraft: Forever</b>. It knows your character as you play and helps with what you're deciding: quests, dungeons, gear, talents, spells, professions and gold.<br>
  <b>Free and open source. Advice only: it never plays for you.</b>
</p>

<p align="center">
  <a href="https://github.com/jcouser/spellmind/releases/latest">Download the app</a> ·
  <a href="docs/install.md">Install guide</a> ·
  <a href="docs/privacy.md">Privacy</a> ·
  <a href="docs/screen-reading.md">How it reads the game</a> ·
  <a href="docs/faq.md">FAQ</a>
</p>

<p align="center">
  <img src="docs/images/chat-answer.png" alt="Spellmind's chat window answering how to get from Ironforge to the Deadmines quests in Westfall" width="760">
</p>

> **Unofficial.** Spellmind isn't made, reviewed or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.

## What it does

Spellmind is two parts:

- **The addon**, in the game. Its panel works on its own, with no app and no AI: what your quests lead to, which dungeons fit your level, gear and bag advice, talents to take next, spells to train, profession caps and gold. Quiet nudges by the minimap tell you when something's waiting.
- **The free desktop app** (Windows 10 and 11). It sends your question, with the game data you allow, to **your own AI**, and brings the answer back into the game's chat window.

| | Addon alone | Addon + app |
|---|---|---|
| Quests, Dungeons, Gear, Talents, Spells, Professions, Gold tabs | ✓ | ✓ |
| Tooltip lines, nudges, waypoints on click | ✓ | ✓ |
| Chat: ask anything about your character | | ✓ |
| "Break it down" on quests, items, trainers and merchants | | ✓ |
| Read your leveling guide's page (talents, rotation) | | ✓ |

<table>
  <tr>
    <td width="50%"><img width="1066" height="844" alt="Screenshot 2026-11-13 202427" src="https://github.com/user-attachments/assets/ea80be2c-cb7b-4074-acd4-bbbc3c4a7720" /></td>
    <td width="50%"><img src="docs/images/talents-tab.png" alt="The Talents tab: your guide's next points and other builds"></td>
  </tr>
  <tr>
    <td><b>Dungeons:</b> which dungeons your quests are for, what each needs first and who gives it, and what's at your level.</td>
    <td><b>Talents:</b> your leveling guide's build, read by your AI, with the next points to take.</td>
  </tr>
  <tr>
    <td><img src="docs/images/settings-tab.png" alt="The Settings tab: switches for each mark on the game's windows and each kind of nudge"></td>
    <td><img src="docs/images/desktop-app.png" alt="The desktop app's window: Status, Your AI (signed in with a ChatGPT plan, GPT-6 Luna, Medium thinking, web search on) and the WoW folder"></td>
  </tr>
  <tr>
    <td><b>Settings:</b> every mark and nudge has its own switch, and you choose which game data your AI gets.</td>
    <td><b>The app:</b> pick your AI, its model and thinking level. It sits by the clock and keeps the addon up to date.</td>
  </tr>
</table>

<p>
  <img src="docs/images/nudge-toast.png" alt="A nudge: 5 spells to train, with Dismiss and Ask" height="80">
  &nbsp;
  <img src="docs/images/tooltip-quest.png" alt="Spellmind's tooltip on a quest: its level against yours, what's left, where it is on the map and the rewards" height="150">
</p>

## Your AI, your choice

The app talks to the AI you pick. You pay that AI (or use a plan you already have); Spellmind itself is free and has no account, server or subscription.

- **ChatGPT plan** (Plus or Pro): sign in in your browser, no API key.
- **An API key** for Claude (Anthropic), ChatGPT (OpenAI), Grok (xAI) or Gemini (Google).
- **Other:** any OpenAI-compatible service, such as OpenRouter or Groq, or a model on your own computer with Ollama or LM Studio.

Keys and sign-ins stay in Windows' Credential Manager on your PC. The game never sees them.

## Install

**The addon:** from CurseForge (WoW Forever), or the `Spellmind-<version>.zip` on the [releases page](https://github.com/jcouser/spellmind/releases/latest), unzipped into `World of Warcraft\_forever_\Interface\AddOns`. The zip carries the addon and its parts (`Spellmind_S001` to `Spellmind_S200`, which bring answers in); keep them all.

**The app:** `Spellmind-Setup-<version>.exe` from the [releases page](https://github.com/jcouser/spellmind/releases/latest). It needs no admin rights, finds your WoW folder, installs the addon if it isn't there, and walks you through setting up your AI. [The install guide](docs/install.md) covers checking the download, the SmartScreen warning, updating and removing it.

In game, `/sm` opens the chat and `/sm help` lists the commands. `/sm app` shows where to get the app.

## Privacy, in short

- **Never sent:** your character's name, realm or guild, your account, other players' names or chat.
- **Sent to your AI only, when you ask:** your question and the game data you allow (class, level, gear, quests, talents and so on; each part has a switch in Settings).
- **Nothing goes to the Spellmind authors.** No telemetry, no analytics, no server.

The details are in [docs/privacy.md](docs/privacy.md).

## How it works

An addon can't reach the internet or write files while you play, so the two parts talk through the screen and the addon folder:

1. The addon draws a small strip of colored squares in the corner of the game's window, holding your question.
2. The app reads only that strip, from the game's window, and sends the question to your AI. [What it reads, and what it doesn't](docs/screen-reading.md).
3. The answer comes back as files in the addon's own folders, which the addon loads.

The app never reads the game's memory, never sends keys or clicks, and never changes the game's files outside Spellmind's own addon folders. [The design notes](docs/design.md) have more.

## Building from source

Node 22.19 or newer.

```
npm ci
npm test                              # the addon (in a Lua VM), the app's core and the link
node tools/package-addon.mjs          # dist/Spellmind-<version>.zip, for CurseForge
cd app/desktop && npm ci && npm start # the app from source
npm run dist                          # (in app/desktop) the Windows installer and its SHA-256
```

The app's screen-reading helper is C, built with `npm run capture:build` (Git Bash with MinGW-w64's gcc) or `core/capture/windows/build.sh` (Zig 0.16.0). Releases are built by [GitHub Actions](.github/workflows/release.yml) from a tagged commit; [docs/releasing.md](docs/releasing.md) has the steps.

## Support and security

- Questions and bugs: [GitHub issues](https://github.com/jcouser/spellmind/issues). Leave out your character's name, keys and anything personal.
- Security problems: see [SECURITY.md](SECURITY.md); please don't open a public issue.

## License

MIT, see [LICENSE](LICENSE). Parts come from NeverQuestAlone and wow-ai under the MIT license: see [NOTICE](NOTICE.md). The Spellmind name and artwork aren't covered by the license.
