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

### Words
- **Settings:** "Full answer: a short one whole…" (it said "Whole").

## Still to do

- **B:**
  - the Other key bound to its host;
  - Electron's fuses;
  - a confirmation before a new Other address;
  - the log's rotation and redaction;
  - the addon update going only up, never down: the installed app writes its own addon's files over newer ones;
  - junction checks, atomic config writes, a cap on restarts;
  - the installer's hash and instructions.
- **C:** Activity in plain words, errors that stay on screen, API keys billed by use, Other's state and Disconnect, Paste key following the key's AI, accessibility basics.
- **D:** Stop on a waiting question, a "Spellmind app" section in Settings, the game's thinking pick overriding the app's, small wording.
- **E:**
  - Grok's web search;
  - Claude's search and models (Fable 5.2, Haiku 5.5);
  - OpenAI's default to Luna;
  - Gemini's models, then a native adapter;
  - guardrails for local models;
  - live tests per AI.
