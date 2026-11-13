# Milestone 3: the desktop app

Before this, the link to the game was a command (`node tools/spellmind.mjs start`) that ended with the game, the PC or a crash. The game then said "Waiting for the Spellmind app to start…" until someone started it by hand. The app keeps the link running, starts with Windows and gives the settings a window.

Built 2026-11-13, Windows first: from source, and as an installer (`Spellmind-Setup-0.1.0.exe`).

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

## The app's switches (config.json "app", all on unless turned off)

- **Start when I log in to Windows.** The installed app writes it on every start, naming its own exe. A run from source never writes it, and has its own app id (`gg.spellmind.app.dev`): sharing the installed app's let Windows show Electron's atom as Spellmind's taskbar icon (2026-11-13).
- **The atom on the taskbar, and a reopen into bare Electron (2026-11-13).** A run from source showed a notification, and Electron made a Start menu shortcut for its app id: "Electron", its own exe with no app. That run shared the installed app's id, so Windows used that shortcut for Spellmind's taskbar icon and to relaunch it (Electron's "To run a local app" page).
  - A run from source now has its own id and shows no notifications (a line in Activity instead).
  - The installed app's window names its own icon and relaunch command (`setAppDetails`).
  - The stray shortcut was removed by hand.
- **Minimize to the tray, not the taskbar.**
- **Notifications** (Windows' own, silent; a click opens the window), each once until it's resolved:
  - The sign-in is gone or refused (`oauth_expired`, `auth_invalid`, `no_key`). The pill says "Sign in again".
  - The link stopped three times in a row.
  - The addon was updated.
  - An out-of-credit, spend-limit or rate-limit error has no notification; the pill says "Your AI plan's limit is reached".
- **Keep the addon up to date.** The app's copy goes over the game's when the app starts and when WoW closes. It only happens while WoW is closed, and only once the addon is installed.

A bug found on the way: a turn error's own kind (`oauth_expired`) overwrote the event's kind, so turn errors never showed, in the command line either. It now goes as `what`.

## The installer (`npm run dist` in app/desktop: electron-builder 26, NSIS)

- **One click, per user,** with no admin rights. It installs to `%LOCALAPPDATA%\Programs\spellmind-desktop` (the package's name; changing it would install a second copy beside the first), with Start menu and desktop shortcuts. The settings and log in `%APPDATA%\Spellmind` stay on uninstall.
- **Inside app.asar the repo's layout is kept** (`app/desktop/`, `core/`, `addon/Spellmind/`, `prompts/`, LICENSE and NOTICE), so the imports work the same packed.
- **Unpacked beside it,** since nothing runs from inside app.asar:
  - the screen-reading helper (`core/link/capture.mjs` looks under `app.asar.unpacked`);
  - the keychain binding.
- **Checked on 2026-11-13 from the packed build:** the worker ran, the helper started from the unpacked folder, the sign-in read from the keychain, and the Run value named `Spellmind.exe`.
- **Unsigned:** Windows SmartScreen warns on the first run ("More info", then "Run anyway"). A code-signing certificate is for later.
- **English only:** Chromium's other locale packs stay out. The installer is about 113 MB.

## Choosing the AI (0.2.0)

The core had every AI NeverQuestAlone's has; the window offered only the ChatGPT plan. Now **Your AI** starts with a picker.

- **The choices:**
  - ChatGPT plan (sign in)
  - Claude (Anthropic API key)
  - ChatGPT (OpenAI API key)
  - Grok (xAI API key)
  - Gemini (Google API key)
  - Other (OpenAI-compatible)

  Each says "in use" or "not set up". Picking one that's set up switches to it at once; picking another shows its setup below, and nothing changes until that works.
- **The plan:** Sign in, Cancel, Sign out (the browser flow, as before). Signing in switches to it.
- **An API key** (`core/app/ai.mjs`):
  - **Get a key** opens that AI's own key page. The link comes from its manifest only, never from the window.
  - **Paste key** reads the clipboard in the app, so the window never sees the key.
  - The key's shape says which AI it's for (`providers/keytext.mjs`). It's unwrapped from quotes and spaces, then tested with a live call (the AI's models list).
  - Only a key that works is kept, in Windows' credential store. Then the clipboard is cleared and the link switches to that AI.
  - Turned away with plain words, and nothing sent: an empty clipboard, text that isn't a key, an admin key, a Claude sign-in token, an OpenRouter key (it goes under Other).
  - Remove key.
- **Other:**
  - An address: https, or http for this computer or the home network, with no user name, password or query. A pasted `/chat/completions` is cut to the base.
  - A model name, and optionally the key on the clipboard.
  - It's tested the same way. A model the service doesn't list is refused, with the ones it does.
- **Model, Thinking and Web search** are the AI in use's own:
  - no Thinking menu for a model without levels (Other);
  - web search off and greyed, saying "has no web search in Spellmind yet", where the manifest has none (Claude, Gemini, Grok and Other for now).
  - A model kept from another AI falls back to this one's default, and a thinking level to the nearest it has (`runner.mjs` `pickAI`).
- **Setup step 3** is "Set up your AI", done by any AI that's ready.
- **Found on the way:** a name declared twice in the window's script left the whole window blank. A test now parses the script and checks every element it looks up is in the page.

## Next

- **The AI audit:** web search for Claude and Gemini (their own tools), the manifests' model lists (Claude Fable 5.2 and Haiku 5.5 aren't in them yet), and the double-check and prompt tried on each AI.
- **Updates:** they need a public release feed, which waits until the repository is public.
- **Usage** (how much of the plan's limit was used) and per-part sharing in the window (the game's Settings tab has the parts today).
