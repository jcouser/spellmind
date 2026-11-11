# Milestone 6: the chat window redesign

Mockup A of 2026-11-10 (bubbles and chip buttons; Codex's drafts in the session's scratchpad), built:

| Piece | File | What it does |
|---|---|---|
| The window | `addon/Spellmind/Window.lua` | Movable, resizable (grip at the bottom right, 360×300 to 900×900), folds to its header (−/+). Its place, size, fold and picks are saved in `SpellmindDB.ui`. |
| Header | `Window.lua` | The owl, "Spellmind", **Thinking: Medium v** (a menu of the levels the app's model offers, each with its trade-off), **Web search: On/Off** (only when the AI has it), fold, close. |
| Status line | `Window.lua` | "Connected · ChatGPT · GPT-6 Luna", the link's own status when it isn't fine, and "About: …" during an Ask more thread. |
| Bubbles | `Window.lua` | Yours on the right (dark gold), Spellmind's on the left (violet) with the owl; a system line or an error centred, without a bubble. A short message gets a short bubble. The newest scrolls into view; the wheel scrolls. |
| Chips | `Window.lua`, `core/link/render.mjs` | Under the last reply: up to three buttons from the reply's "Next: a / b / c" line. A click asks. |
| Links | `Chat.lua`, `Tooltip.lua` | A shift-clicked item or quest goes into the focused box (a hook on `ChatFrameUtil.InsertLink`, else `ChatEdit_InsertLink`). Sent, it shows in green or yellow; the AI gets "[Name]" and, for the first link, the item or quest as the focus part (`about=item:<id>` or `quest:<id>`). |
| Minimap button | `addon/Spellmind/Minimap.lua` | The book logo on the minimap's rim. Click: the chat. Drag: around the rim (angle in `SpellmindDB.minimap`). `/sm minimap off` and `on`. Right-click: the Advisor panel, later. |

`SpellmindDB.msgs` keeps the last 80 messages (`{ w = "you"|"sm"|"sys"|"err", t = shown text, c = chips }`), and `SpellmindDB.lines` keeps the flat text as before.

## The contract

- **The slot's `bridge.ai`:** `{ name, model, efforts = { "low", "medium", "high", … }, effort, search, searchOn }`. `efforts` is the model's own list from its manifest, `effort` is the app's default, `search` says whether the AI has web search, and `searchOn` is the app's default for it. An app without `bridge.ai` shows neither control.
- **A message's `effort=<level>` and `search=0|1`:** sent only when the player picked one the app offers. The service checks `effort` against `efforts`, and takes `search` only when the AI has search; otherwise it uses its defaults.
- **A reply's `chips`:** an array of at most 3 strings, each at most 40 characters, with pipes doubled. The model's last line `Next: a / b / c` becomes `chips` and is taken off both the text and the history.
- **The item focus** (`kind` "item"):
  - `id`, `name`, `q`, `ilvl`, `req`, `type`, `sub`, `equip`, `st`;
  - `usable` and `why`, from the game's red text, as the tooltip line has them;
  - `vs`, the tooltip line's comparison in words.

## Not yet

- The gold corner trim of the mockup (it needs Codex art in the flat style).
- The game's own title font is used, so the text looks less smooth than the mockup's.
- Quest links from the quest log: the game may not hand them to a box that isn't its own chat box. Check this live.
