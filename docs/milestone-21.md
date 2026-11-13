# Milestone 21: the audit (UX, AI support, security)

On 2026-11-13 three reviewers (Fable 5.2) went through the app and the addon: one for UX, one for each AI's support, one for security. Their findings were checked against the code. One was wrong: the login item's path is quoted in the registry. The player then sent five screenshots the UX reviewer asked for.

The work is in batches:
- **A:** answers and messages that are wrong or misleading.
- **B:** security before the installer is shared.
- **C:** app UX.
- **D:** addon UX.
- **E:** each AI made first-class.

## Done

### First run (C; the player's screenshot 1)
- **The WoW folder is found on its own** (`install.mjs` `findFlavorDirs`). Battle.net's InstallPath comes first, then the usual folders on each drive. When exactly one is found, it's set.
- **The picker** opens at it, and takes the "World of Warcraft" folder above `_forever_` too (`flavorIn`).
- **Each setup step has its button** (only the next one): Pick the folder, Install, Set it up. Nothing says "below".
- **The pill says "Finish the setup"** while any of the first three steps is undone. The Status card waits until setup is done.
- **A login start opens the window** when any setup step is undone.
- **config.json saved with a byte-order mark** (Notepad, PowerShell) is read; it read as no settings before.

### The app quit, a question asked (A; screenshots 3 and 4)
Seen: the chat and the card said "Thinking…" with the app closed. The game knew the app was away only from silence: 25 s with working doorbells, 2 minutes without. A session whose doorbells had died (the app killed while ringing) never knew.

- **The app says goodbye.**
  - On a clean stop (Quit in the tray, Ctrl+C), the service publishes one last slot with `bridge.closing`, rings it, and waits 1.2 s before it stops (`service.bye`, `runner.close`).
  - The addon marks the app gone at once (`Link.AppClosed`), until it's heard from again.
  - A goodbye slot loaded again later, older than the last word, says nothing.
- **One rule for "the app is gone"** (`Link.AppGone`: goodbye, away, or not heard): the chat's bubble ("Waiting for the Spellmind app to start…"), the card, the status line and the first "Start the Spellmind app" note.
- **The card's words:** "Start it from the Start menu, or its icon by the clock", not the developer command.

### Scrollbars (D; screenshot 5)
- **A thin scrollbar** on the panel's tabs, the chat and the answer card (`Window.ScrollBar`).
  - It shows only when there's more than fits.
  - The thumb's size is the share in view, and it follows the scroll.
  - It can be dragged, and turns gold on hover.
- **The chat's list stops 12 px from the edge** for it.

### Updating with the app running (the player: "Spellmind also needed to be closed")
- **The installer asks a running Spellmind to quit** (`app/desktop/installer.nsh` `customCheckAppRunning`): it starts `Spellmind.exe --quit`, which the running copy hears through its single-instance lock. That copy says goodbye to the game and ends.
  - electron-builder's own check asked for OK, and a plain taskkill only hid the window to the tray.
  - Then whatever is left (the app, its worker, the screen-reading helper) is ended.
  - Checked on the built app: everything gone within 3 s, the goodbye slot written.
- **Uninstall removes the start-at-login entry** (the Run value and Explorer's flag), not on an update (B).
- **No elevate.exe** in a per-user install (B).

### Batch A: what the player is told, and what each turn asks for
The turn moved to `core/app/turn.mjs` (`createTurn`), tested against a stand-in AI (`tests/app/turn_test.mjs`).
- **The output ceiling** is the reply's own (1,200 tokens) plus its thinking level's room (`THINK_ROOM`: Low 2,048, Medium 4,096, High 8,192…), held to the model's maximum. A model without levels gets the reply's room only.
  - Every AI counts thinking inside the ceiling, so a bare 1,200 at Medium could be all thinking.
  - The ChatGPT plan answered fine at 1,200; the room only adds.
- **The reply's finish is read:**
  - Cut at the ceiling: the text, then "(Cut short: ask "go on" for the rest.)".
  - No text: "couldn't finish a reply" (`empty_reply`).
  - A refusal with no text: "declined to answer that" (`content_blocked`).
- **One retry, for real:**
  - A busy or rate-limited AI (`retryable`) is tried once more after its wait, if that's 20 s or less and nothing came yet.
  - The words then go out as final ("Still busy. Try again in a minute."), never "Trying again…".
  - Lines pointing at app pages that don't exist ("Check Connections", "See the details") now name what the app has: Restart the link (its tray menu), Pick another AI, or ask again. "Can't reach … Then ask again." when it's final.
- **The ChatGPT plan's cache key** goes with every request: a hash of the chat id, the same for the draft and its check, so the backend reuses the chat's cached prompt. `turn()` dropped the chat id before.
- **Web search, said each turn:**
  - A note with the game data: "Web search: on this turn", or "off… never cite a site". It's never in the cached prompt.
  - The prompt points at it.
  - Without search the check is asked from the game data only (`checkAsk(false)`).
- **The double-check's answer** (`pickChecked`):
  - "OK" (asked for when nothing needs changing) keeps the draft, as do "Your answer is correct…", "Upon review…" and "I've verified…".
  - A lead-in like "Here is the corrected answer:" goes.
  - A check more than twice the draft's length keeps the draft.
  - An answer that starts "OK, …" is still an answer.
- **The app's words:**
  - Errors show the line the game showed ("Your ChatGPT sign-in ended. Sign in again in the Spellmind app."), in Status and in Activity, never the kind alone.
  - The pill and the notification say what to do in the AI's own terms (`ACT_ON` in main.mjs): "Sign in again", "Your AI key was refused", "out of credit", "daily limit". A slow-down or a busy AI shows only while it lasts.
  - "Linked since 14:02", cleared when WoW closes.
  - Activity in plain words ("Question received: asking ChatGPT…", "Answer sent to the game."). Character data no longer gets a line every few seconds. The screen reading says what it reads.
- **The game's header** says "Set up your AI in the Spellmind app", not "Connected", when the app finds no sign-in or key at start (`bridge.ai.ready = false`).
- **A "Next:" at the end of the last paragraph** ("…the count mismatch. Next: Where do I get…? / …?") makes chips, when what follows reads as suggestions. A plain "Next: head to Lakeshire." stays as text.

### Batch B: security before the installer is shared
- **Other's key belongs to its address** (`cfg.custom.keyHost`): a new address without a key drops the old one, and the link sends it only to that host.
- **A new Other address asks first,** in the app's own dialog: "Send your questions and game data to <host>?". It warns when a key would go over http on the network. Model names from a service are filtered to the shape of model names before they're shown.
- **Egress:** only Other may reach this computer (loopback). 169.254/16 (link-local, where a cloud's metadata service lives) isn't a home network, so it's https only.
- **Electron's fuses** (`electronFuses` in electron-builder.yml):
  - RunAsNode, NODE_OPTIONS and --inspect are off.
  - The app loads only from app.asar, checked against the hash in the exe.
  - Checked on the built exe with @electron/fuses, and the packed app run: worker, helper, keychain and --quit all work.
- **The window:**
  - Every permission request is refused.
  - Any web contents is denied webviews, new windows and navigation.
  - The calls check the frame's address, not only the window.
  - The `--shot` code (the only executeJavaScript) is in dev-shot.mjs, which the installer doesn't take.
- **The log:**
  - core/log.mjs: a file a day in `%APPDATA%\Spellmind\logs`, kept 7 days, through the key redactor.
  - The token and nonce fields are left out, and publishes are logged only when they fail.
  - The old `spellmind.log` (with tokens) is deleted.
- **The addon copy refuses links:** a junction or link at AddOns\Spellmind (or a file that's a link) is removed, never written through. Tested with a real junction.
- **The addon update only goes forward:**
  - Each install leaves `.installed-by` (the app's version).
  - The automatic update runs only for an older one, or none: never over a newer app's addon, nor one changed by hand.
  - The window's Update still does as asked.
- **config.json is written whole** (a temp file, renamed). One that can't be read is kept as config.json.bad.
- **Restarts are capped:** after 20 stops in a row the supervisor gives up. The pill says "The link keeps stopping: restart it".
- **The sign-in's listener** answers only to `127.0.0.1:<port>` (421 otherwise: DNS rebinding).
- **The clipboard toast** says Windows' clipboard history keeps its own copy of a pasted key.
- **The installer:**
  - `npm run dist` prints its SHA-256 and writes it beside it.
  - [docs/install.md](install.md): one download place, checking the hash, SmartScreen's warning, never admin, what it installs, what an uninstall leaves.
  - `npm audit --omit=dev`: 0 vulnerabilities (2026-11-13).

### Words
- **Settings:** "Full answer: a short one whole…" (it said "Whole").

## Still to do

- **B:** a code-signing certificate (then the helper's and the keyring's own signatures checked); a public download place for the installer and its checksum.
- **C:** errors that stay on screen, API keys billed by use, Other's state and Disconnect, Paste key following the key's AI, accessibility basics.
- **D:** Stop on a waiting question, a "Spellmind app" section in Settings, the game's thinking pick overriding the app's, small wording.
- **E:**
  - Grok's web search;
  - Claude's search and models (Fable 5.2, Haiku 5.5);
  - OpenAI's default to Luna;
  - Gemini's models, then a native adapter;
  - guardrails for local models;
  - live tests per AI.
