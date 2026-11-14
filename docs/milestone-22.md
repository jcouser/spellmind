# Milestone 22: going public (0.4.0)

Built 2026-11-13: what Spellmind needs to be on GitHub and CurseForge.

## The addon on its own

- **One version for a release.** The addon's TOC, `ns.VERSION` and the app are all 0.4.0; tests keep them equal and the release workflow refuses a tag that doesn't match.
- **The CurseForge zip** (`tools/package-addon.mjs`): the addon, `LICENSE.txt`, its doorbells and the 200 parts, laid out as the app installs them, the same bytes every build.
- **Only forward** (`core/link/install.mjs` `shouldUpdate`): the app puts its addon over the game's only when the game's is older. A newer one from CurseForge is left; the window says "A newer addon is installed… Update the app to match", with a quiet button to use the app's anyway.
- **Get the app:** `/sm app`, a button on the Settings tab's App row while the app isn't heard, and a line under "Start the Spellmind app" open a box with the project's link to copy. It says every tab but the chat works without the app.
- **TOC:** new Notes, `X-License: MIT`, `X-Website`.

## The first-time welcome (0.4.3)

- `Welcome.lua`: once per account (`SpellmindDB.welcomed`), 6 s after login, never in combat. What works with no setup (the minimap button, the tabs, nudges, tooltips), then the free app with the project's link to copy, or "connected" when the app already talks to the game. **Open the panel** and **Close**; nudges wait while it's open; `/sm welcome` shows it again.
- Why (the player, 2026-11-14): a player who installs the addon from CurseForge only heard of the app by trying the chat or opening Settings.

## The app's own updates (`app/desktop/updater.mjs`)

- electron-updater 6.8.9 against this repository's GitHub releases (`publish` in `electron-builder.yml`).
- Checks 30 s after the start, then every 6 hours, while "Check for new versions of Spellmind" is on; **Check now** in the window.
- A newer version is offered (window, tray, one notification). Nothing downloads until the player clicks. **Restart to update** installs it, never while WoW is running; otherwise it installs when Spellmind quits.
- Only forward, and errors in plain words (never a raw message, which can hold a path).

## The repository

- README with screenshots (each checked for character, guild and realm names), [privacy](privacy.md), [how it reads the game](screen-reading.md), [FAQ](faq.md), [install](install.md), [releasing](releasing.md), [the CurseForge listing](curseforge.md), SECURITY.md.
- **Workflows:** `test.yml` (every push and pull request) and `release.yml` (a `v*` tag: the helper with the pinned Zig, the tests, the installer, the zip, checksums, then a draft release for a person to publish).
- **Signing:** SignPath Foundation's free open-source program, applied for once the repository is public ([releasing.md](releasing.md)). Unsigned until then.

## Seen working (2026-11-13)

- v0.4.0 and v0.4.1 built by the release workflow, published by hand.
- An installed 0.4.0 found 0.4.1 (Check now), downloaded it on a click, and restarted into 0.4.1 on Restart to update; the addon followed. (Not yet tried: the refusal while WoW runs.) Before 0.4.0 was published its check read "didn't work": the words matched only the error's code (fixed in 0.4.1).

## Still to do

- Screenshot still missing: a talent plan answer (after 0.4.2, which sends the AI 10 next points).
- SignPath: applied 2026-11-14, declined until the project has more community traction; apply again later (docs/releasing.md). Unsigned meanwhile.
- CurseForge: approved 2026-11-14 (spellmind-ai-companion, project 1804129); uploads come from curseforge.yml when a release is published.
