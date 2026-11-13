# Milestone 3: the desktop app

Before this, the link to the game was a command (`node tools/spellmind.mjs start`) that ended with the game, the PC or a crash. The game then said "Waiting for the Spellmind app to start…" until someone started it by hand. The app keeps the link running, starts with Windows and gives the settings a window.

Built 2026-11-13, Windows first, run from source. The installer is the next step.

## How it runs (`app/desktop/`, Electron 44)

- **The link runs in a worker** (`worker.mjs`, an Electron utility process): the same `core/app/runner.mjs` the command line uses.
- **The supervisor** (`core/app/supervisor.mjs`) starts the worker again when it stops by itself.
  - It waits 1 s, 2 s, 5 s, 15 s, then 30 s between tries. After two minutes up, it starts again from 1 s.
  - A worker that can't start until a setting changes (no WoW folder, an unknown AI) exits with 2 and waits for the window. Saving a setting restarts it.
  - Seen in a test on 2026-11-13: the worker was killed by hand and back within 4 s. The screen-reading helper went with the old worker, and only the new one's runs.
- **The tray icon** (the book and sigil): a line saying what the link is doing, then Open Spellmind, Start when I log in to Windows, Restart the link and Quit Spellmind. A click opens the window.
- **Start at login is on by default.**
  - It writes the HKCU Run value `gg.spellmind.app` with `--hidden`, so a login start stays in the tray.
  - A start by hand, or one that still needs setup, opens the window.
  - A run from source names Electron and this folder.
- **One copy runs.** A second launch opens the first one's window.
- **Closing the window keeps Spellmind in the tray.** Quit is in the tray's menu.

## The window

- **The header pill** shows one of: Linked to WoW · WoW is running: waiting for the addon · Waiting for WoW · Restarting the link in N s · the setup step needed · Sign in again.
- **Finish the setup** shows until the first three steps are done:
  1. Pick the WoW folder.
  2. Install the addon.
  3. Sign in.
  4. Start WoW: the game says hello.
- **Status:** WoW (running, not running), the game's link (when it last said hello), and the last answer.
- **Your AI:**
  - The ChatGPT plan's sign-in: the browser flow, from the app, with Cancel. Sign out is here too.
  - The model, the thinking level and web search. The game's chat window starts from these, and can still pick its own for a question.
  - A change is checked (`core/app/settings.mjs`), saved to `config.json`, and the link restarts with it.
- **World of Warcraft:**
  - The `_forever_` folder (a folder picker; one without Interface or WTF is refused).
  - The addon: not installed, up to date, or an update with how many files changed and how many are new (`install.mjs` `addonState`, file by file).
  - With WoW running, Update copies changed files and says to /reload. New files need WoW closed, since the game only reads new files when it starts.
- **The app:** Start when I log in, Restart the link, Open the log folder.
- **Activity:** the last 40 things the link did, newest first (`core/app/lines.mjs`, the command line's lines too). "WoW's window wasn't found" isn't shown while WoW is closed.

## Locked down

- **The window is sandboxed,** with context isolation and no Node. It reaches the app only through `window.spellmind`: one frozen object with one call per action (`preload.cjs`; a test checks it matches `main.mjs`).
- **Calls from any other page are refused.**
- **It can't navigate or open windows.** The content policy is `default-src 'none'`, with the page's own script and style only.
- **Text goes into the page as text,** never as HTML.

## Running it

- `npm run app` from the repo, or `npm start` in `app/desktop`. The first `npm install` there fetches Electron.
- Stop a running `node tools/spellmind.mjs start` first: two links would both answer the game.
- `--hidden` starts it in the tray. `--shot <file.png>` (from source only) saves a picture of the window, top and bottom, to check the layout.

## Next

- **The Windows installer** (electron-builder, NSIS, per user).
  - It needs the core, the addon and the screen-reading helper inside the app. The helper sits beside `app.asar`, since nothing runs from inside it.
  - Unsigned at first: Windows SmartScreen warns on the first run.
- **Updates:** they need a public release feed, which waits until the repository is public.
- **Usage** (how much of the plan's limit was used) and per-part sharing in the window (the game's Settings tab has the parts today).
