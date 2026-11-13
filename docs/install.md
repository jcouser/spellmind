# Installing Spellmind on Windows

Spellmind is two parts: an addon in World of Warcraft: Forever, and a small app on your PC that talks to your AI. The installer puts in the app, and the app puts in the addon.

## Before you run it

- **Get it from one place only:** the link the Spellmind authors give. Don't take a copy someone sends you.
- **Check it's the real one.** Each release comes with a SHA-256 checksum. In PowerShell:

  ```
  Get-FileHash .\Spellmind-Setup-0.2.5.exe
  ```

  The `Hash` it prints must match the published one exactly. If it doesn't, don't run it.
- **Windows SmartScreen will warn you** ("Windows protected your PC"), because the installer isn't signed with a paid certificate yet. Click **More info**, then **Run anyway**.
- **It never asks for admin rights.** If something claiming to be Spellmind asks for them, it isn't Spellmind.

## What it does

- Installs the app for your Windows account only, in `%LOCALAPPDATA%\Programs\spellmind-desktop`, with Start menu and desktop shortcuts.
- Starts the app, which finds your WoW: Forever folder and asks you to set up your AI: sign in with your ChatGPT plan, or paste an API key.
- **The app installs the addon** into your WoW folder (with WoW closed) and keeps it up to date.
- **Starts with Windows,** quietly in the tray by the clock, so it's there when you play. You can turn this off in the app.
- **Keeps your settings** in `%APPDATA%\Spellmind`, and its log in `%APPDATA%\Spellmind\logs` (7 days, no keys).
- **Keeps your sign-in or API key** in Windows' Credential Manager, never in a file.

## Updating

Run the new installer. It closes the running app for you; close WoW first so the addon can update too.

## Removing it

Windows Settings → Apps → Spellmind → Uninstall. That removes the app and its start-with-Windows entry.

These stay behind, so a reinstall finds them:
- your settings, in `%APPDATA%\Spellmind`;
- your saved sign-in or keys, in Credential Manager under "Spellmind";
- the addon, in your WoW folder.

Delete any of them by hand if you want them gone.

## For whoever builds it

- Build from a clean checkout with `npm ci` (the lockfiles pin every package), then `npm run dist` in `app/desktop`. It prints the installer's SHA-256 and writes it beside the installer as `.sha256`.
- Run `npm audit --omit=dev` before a release, and check that the Electron version is still supported.
