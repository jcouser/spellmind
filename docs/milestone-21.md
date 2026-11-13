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

### Words
- **Settings:** "Full answer: a short one whole…" (it said "Whole").

## Still to do

- **A:**
  - replies cut by the 1,200-token ceiling (thinking counts in it), and the reply's finish ignored;
  - error lines that promise retries that never happen;
  - the ChatGPT plan's cache key not sent;
  - the prompt and the double-check not knowing when search is off;
  - `pickChecked` taking "No changes needed" for an answer;
  - "Linked" never cleared;
  - "Connected" with the AI signed out;
  - raw error codes in the app;
  - a "Next:" line inside a paragraph.
- **B:**
  - the Other key bound to its host;
  - Electron's fuses;
  - a confirmation before a new Other address;
  - the log's rotation and redaction;
  - the Run value removed on uninstall;
  - the addon update going only up, never down: the installed app writes its own addon's files over newer ones;
  - junction checks, atomic config writes, a cap on restarts, no elevate.exe;
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
