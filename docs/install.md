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

## The app on Linux (preview)

For WoW Forever running under Proton or Wine on a Linux desktop (first tried on Bazzite with KDE, the game started by Faugus Launcher with Proton-CachyOS; issue #1). It's a preview: tell us how it goes on [GitHub](https://github.com/jcouser/spellmind/issues).

1. Download `Spellmind-<version>.AppImage` from the [releases page](https://github.com/jcouser/spellmind/releases/latest) and check it against `SHA256SUMS.txt` (`sha256sum Spellmind-*.AppImage`).
2. Make it executable and run it: `chmod +x Spellmind-*.AppImage && ./Spellmind-*.AppImage`, or with your file manager (Properties, "Allow executing").
3. It looks for WoW: Forever inside the prefixes Faugus, Steam, Lutris, Heroic and Bottles make. If it doesn't find yours, pick the `_forever_` folder inside your prefix's `drive_c`, for Faugus usually `~/Faugus/<name>/drive_c/Program Files (x86)/World of Warcraft/_forever_`.
4. Set up your AI as on Windows. Keys and the ChatGPT sign-in go into your desktop's keyring (KWallet or GNOME Keyring).
5. Start WoW. The app says "Connected to WoW" when it hears the addon.

**What it needs:** `python3` (every gaming distro has it), and the game drawn through X11 or XWayland, which is how Proton runs games unless told otherwise.

**If it can't see the game:**
- "WoW is running with Wine's Wayland driver": the game is drawing straight to Wayland, where Spellmind can't read it yet. Turn that off in your launcher (`PROTON_ENABLE_WAYLAND=0`, or its Wayland option) and restart the game.
- "Waiting for the WoW window": with WoW open, run `python3 ~/.config/spellmind/bin/capture_x11.py --list-windows` to see the windows Spellmind can see, and `--probe probe.png` to see what it reads (crop your character's name out before sharing it).
- The AppImage doesn't start: on Ubuntu 24.04 and later, install `libfuse2t64`; if it then says the sandbox isn't configured, start it with `--no-sandbox`.

**Closing the window** keeps Spellmind running in the background, talking to WoW. On GNOME there's no tray icon without an extension: start Spellmind again to open its window. Quit is in the tray menu.

**Updates:** the AppImage updates itself, like the Windows app. Your settings are in `~/.config/spellmind`.

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
