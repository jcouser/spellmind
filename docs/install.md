# Installing Spellmind on Windows

Spellmind is two parts: an addon in World of Warcraft: Forever, and a small app on your PC that talks to your AI. You can install either first.

- **Addon only:** every tab of the panel, the tooltip lines and the nudges. No AI.
- **Addon and app:** the chat with your AI too. The app installs the addon for you if it isn't there.

## The addon

**From CurseForge:** [Spellmind: AI Companion](https://www.curseforge.com/wow/addons/spellmind-ai-companion), for WoW Forever. Install it with the CurseForge app, or any addon manager that uses CurseForge (WowUp, for one).

**By hand:**

1. Download `Spellmind-<version>.zip` from the [releases page](https://github.com/jcouser/spellmind/releases/latest).
2. Close WoW.
3. Unzip it into `World of Warcraft\_forever_\Interface\AddOns`. You get a `Spellmind` folder and 200 `Spellmind_S001`…`Spellmind_S200` folders (the parts that carry answers in). Keep them all.
4. Start WoW. Type `/sm` in game.

## The app

### Before you run it

- **Get it from one place only:** the [releases page](https://github.com/jcouser/spellmind/releases) of this repository. Don't run a copy someone sends you.
- **Check it's the real one.** Each release lists the installer's SHA-256. In PowerShell, in your Downloads folder:

  ```
  Get-FileHash .\Spellmind-Setup-0.4.0.exe
  ```

  The `Hash` it prints must match the release's exactly. If it doesn't, don't run it.
- **Windows SmartScreen may warn you** ("Windows protected your PC") while the installer is new or unsigned. Click **More info**, then **Run anyway**.
- **It never asks for admin rights.** If something claiming to be Spellmind asks for them, it isn't Spellmind.

### What it does

- Installs the app for your Windows account only, in `%LOCALAPPDATA%\Programs\spellmind-desktop`, with Start menu and desktop shortcuts.
- Starts the app, which finds your WoW: Forever folder and walks you through setting up your AI: sign in with your ChatGPT plan, or paste an API key.
- **Installs the addon** into your WoW folder if it isn't there (with WoW closed), and keeps it up to date. It never replaces a newer addon, from CurseForge for example, with an older one.
- **Starts with Windows,** quietly in the tray by the clock, so it's there when you play. You can turn this off in the app.
- **Keeps your settings** in `%APPDATA%\Spellmind`, and its log in `%APPDATA%\Spellmind\logs` (7 days, no keys, no questions or answers).
- **Keeps your sign-in or API keys** in Windows' Credential Manager, never in a file.

## Updating

- **The app** checks this repository's releases and offers each new version in its window and its tray menu. It installs when you choose, never while WoW is running. You can also run a newer installer yourself; it closes the running app first.
- **The addon** updates with the app (while WoW is closed), or through CurseForge.

## Removing it

Windows Settings → Apps → Spellmind → Uninstall. That removes the app and its start-with-Windows entry.

These stay behind, so a reinstall finds them:
- your settings, in `%APPDATA%\Spellmind`;
- your saved sign-in or keys, in Credential Manager under "Spellmind";
- the addon, in your WoW folder.

Delete any of them by hand if you want them gone ([privacy.md](privacy.md#removing-everything) lists where).

## For whoever builds it

- Build from a clean checkout with `npm ci` (the lockfiles pin every package), then `npm run dist` in `app/desktop`. It prints the installer's SHA-256 and writes it beside the installer as `.sha256`.
- `node tools/package-addon.mjs` builds the addon zip.
- Releases are built by GitHub Actions: see [releasing.md](releasing.md).
