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

### Batch C: the app's window
- **A setup failure stays in its box** (the plan's, the key's, Other's, WoW's) until the next try, in red, and goes in Activity ("Pasting the key didn't work: …").
- **One action at a time:** its button says "Testing…" or "Installing…", and the other controls wait. A click made meanwhile was dropped before.
- **API keys:** "billed by use at its company, apart from any subscription. No key? The ChatGPT plan sign-in needs none."
- **Paste key follows the key's AI:** the picker moves to it, and says "That's a ChatGPT key: now using ChatGPT" when it wasn't the one on screen.
- **Other:**
  - It's called "advanced", with "Skip this unless your service gave you an address".
  - Once connected it says what to ("Connected to llama3.3 at localhost:11434, key saved") and has Disconnect: the key and the address go, and the plan answers again.
  - A note: local models need Ollama's context at 16K or more, and answer from memory.
- **The picker:** the AI in use that isn't ready says "in use, not signed in". Setting up another says "Still using ChatGPT plan until this one works".
- **More sign-in endings in words:** timed out, no plan on that account, no lasting sign-in, the credential store.
- **A first install says** "Addon installed. Start WoW and log in.". Reinstall is a quiet button when nothing needs doing.
- **Accessibility:** the pill and toasts announce changes (`role="status"`), placeholders are readable, and zoom works (a hidden menu keeps Ctrl + and Ctrl −).

### Batch D: the addon
- **Stop:**
  - While a question waits, the send button is Stop (`Chat.Stop`).
  - One the app hasn't taken yet is taken back from the outbox (`Link.Drop`), with "Stopped before it was sent".
  - One it has gets a stop record, which the app answers "Stopped.".
  - Enter still sends.
- **Settings opens with "The Spellmind app":** running or not (and when it was last heard), the AI and model ("Not set up" when it isn't), the addon's version. Read only: the AI is chosen in the app.
- **The app's defaults win:** a Thinking or Web search pick made in the game holds while the app's own default stays what it was, and gives way when it changes.
- **Words:**
  - "Close WoW, open the Spellmind app and click Reinstall" (it said "run the app's setup").
  - "(cut short: ask for the rest)".
  - The toast's X hides it for now (still in the list), and Dismiss dismisses.
  - Thinking hints say "plan or credit", and Minimal has one.
  - The app says "Connected" as the game does.

### Batch E: each AI
- **Claude:**
  - Web search through Anthropic's server tool (`web_search_20250305`, at most 3 searches an answer, $10 per 1,000; platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool, read 2026-11-13).
  - The adapter reports a search starting, counts pings as life while a search runs, and writes each block's citations as "(source: site)", never the same site twice in a row.
  - Models: Claude Fable 5.2 ($8/$40, the "smarter" one) and Haiku 5.5 ($0.10/$0.50; Haiku 4.5 moves to it). Fable 5.1 is replaced by 5.2. Sonnet 5.5 stays the default, and its cache reads are $0.10.
- **Grok:** web search (xAI takes the Responses API's tool). Its inline citations, `[[1]](url)`, read "(source: site)".
- **OpenAI's API:** Luna by default, as on the plan (Sol cost 20x for no tested gain).
- **Gemini** (Google's models, thinking and pricing pages, read 2026-11-13):
  - 3.7 Flash and 3.5 Flash are gone (not listed any more); a saved choice of either falls back to the default.
  - Gemini 4 Hydrogen, Argon and Carbon are in, Carbon the "smarter" one. Argon's and Carbon's prices double on 2026-12-01.
  - Low to High through the OpenAI-compatible endpoint: Hydrogen's Extra high isn't documented there.
  - No web search yet: Google's needs a native adapter.
- **Every AI:**
  - Medium thinking by default (it was High without search).
  - The game's menu stops at High: Extra high and Max can pass the turn's 3 minutes, doubled by the check. The app's window still offers them.
  - A pasted key's default model is checked against the key's list (`resolveModel`'s job): one it can't use gives way to the first listed one it can.
  - Each request's usage, cached tokens included, goes in the log ("usage"): it shows whether the ChatGPT plan's cache key works.
  - Searches reach the turn's log ("web-search"): the provider layer used to swallow them.
- **Writing the game can't show** (`render.mjs`): tables become "•" lines, `<think>…</think>` goes, and so do strike marks.
- **Local models:** 3 minutes for the first word (they may load from disk first), and Ollama's context note in the window.
- **A guide import needs web search:** on an AI without it, it's refused in words instead of a made-up build.

## Still to do

- **Live tests per AI** (the player's keys; nothing here was run against Claude, Grok, Gemini or a local model). For each, with the double-check on and off:
  - "Which weapon master teaches Bows?" (the 2026-11-10 question; the answer named a wrong one from memory);
  - "Where do I buy arrows in Sentinel Hill?";
  - "Who takes The Defias Brotherhood?" with it in the log;
  - a guide import;
  - one long answer.
  
  Watch for: "(source: …)" on Claude and Grok answers; no cut-off replies; usage lines in the log with cacheRead above 0 from the second question on.
- **B:** a code-signing certificate (then the helper's and the keyring's own signatures checked); a public download place for the installer and its checksum.
- **E, later:**
  - Gemini's web search (a native adapter for Google Search grounding);
  - Ollama's context checked when connecting;
  - thinking options for the common Other gateways.
- **The player's call:** OpenAI's and Anthropic's terms ask that sources be shown to players. The game shows "(source: site)"; the app could list the last answer's links.

### Words
- **Settings:** "Full answer: a short one whole…" (it said "Whole").
