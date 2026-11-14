# The CurseForge listing

What to fill in on CurseForge for the addon, and the rules it has to follow. The project page is created by hand by the maintainer; nothing here uploads anything.

## Project

- **Page:** https://www.curseforge.com/wow/addons/spellmind-ai-companion (project ID 1804129, created and approved 2026-11-14). The ID is the TOC's `X-Curse-Project-ID`.

- **Game:** World of Warcraft. **Game version / flavor:** WoW Forever (interface 16001).
- **Name:** Spellmind: AI Companion
- **Summary** (what CurseForge's search reads most; the names people search for, in a sentence, never a keyword list): *AI chat companion for WoW Forever: ask ChatGPT, Claude, Gemini or Grok about your quests, dungeons, gear and talents. The quest, gear and spell advice works on its own.*
- **Categories:** Quests & Leveling (main), Bags & Inventory, Professions, Map & Minimap. (Not "Companions": on CurseForge that means battle pets.)
- **License:** MIT.
- **Avatar:** `art/curseforge-avatar.png` (400×400, from `art/source/logo.png`).
- **Screenshots:** `docs/images/` (each checked for character, guild and realm names before upload).
- **Release type:** Beta for the first files, until signing is set up and a few players have used it.

## Files

**Uploaded by GitHub Actions** ([curseforge.yml](../.github/workflows/curseforge.yml)) when a GitHub release is published: the release's own `Spellmind-<version>.zip`, its notes as the changelog, as Beta (the variable `CF_RELEASE_TYPE` changes that). It needs the secret `CF_API_TOKEN` and the variable `CF_GAME_VERSION_IDS`; run the workflow by hand with no tag to list the game versions (WoW Forever 1.60.1 is 17053, type 88568 "wow-forever", set 2026-11-14). A release published before it existed is uploaded by running it with that tag.


Upload `Spellmind-<version>.zip` from the GitHub release, the same file, unchanged. It holds the `Spellmind` folder and the 200 `Spellmind_S001`…`Spellmind_S200` parts. The display name is `Spellmind <version>`; the changelog is the GitHub release's notes.

## The rules that matter here

- **No download links for files outside CurseForge** in the description. The app is a separate program, not this project's file, and is linked as the project's home page; the description's last line names the GitHub page, which CurseForge allows.
- **The addon has to work on its own,** and it does: every tab, the tooltip lines and the nudges need no app. The description says plainly which parts need the app.
- **It follows the game's terms:** no automation, nothing that plays for the player. The description says so and links how the app reads the game.
- **No copied text or files from other CurseForge projects.**
- Moderation reviews new projects and files in order, on European working days; a first file can take a day or two.

## Description

> **Spellmind** is an AI companion for WoW Forever. Its panel shows what your quests lead to, which dungeons fit your level and what each needs first, gear and bag advice, the talents to take next, spells to train, profession caps and gold, and quiet nudges by the minimap. **All of that works on its own.**
>
> With the free **Spellmind app** for Windows, Spellmind becomes an AI chatbot for your character: ask **your own AI** anything about it, in the game's chat window: a ChatGPT plan, or an API key for Claude, ChatGPT, Grok or Gemini. Type `/sm app` in game to see where to get it.
>
> **Advice only.** Spellmind never plays for you, never sends input to the game and never reads its memory. The app reads only Spellmind's own strip from the game's window.
>
> **Private.** Your character's name, realm and guild are never sent. Your questions go to the AI you chose, and nothing goes to the Spellmind authors.
>
> **Commands:** `/sm` opens the chat, `/sm quests`, `/sm dungeons`, `/sm gear` and the rest open a tab, `/sm help` lists them all.
>
> **Keep all the "Spellmind Part" addons checked:** they carry the app's answers into the game.
>
> Spellmind is unofficial and not made or endorsed by Blizzard Entertainment.
>
> Source, the app, privacy and how it works: github.com/jcouser/spellmind
