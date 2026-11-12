# Milestone 11: one window

The chat window and the Advisor panel are now one Spellmind window (asked by the player, 2026-11-12). Two windows plus a card was a lot on screen, and the Settings tab still to come needed a home.

| Piece | File | What it does |
|---|---|---|
| The rail | `Panel.lua` | **Chat** sits at the top (the owl), then Quests, Gear, Talents, Spells, Professions, Gold and Nudges. The title is "Spellmind". |
| The Chat tab | `Window.lua` | The chat is drawn in the window's content area (`SpellmindWindow`, now a child of `SpellmindPanel`). Its row has Thinking and Web search at the left, Chats and + New at the right. Its status line (link, AI, model, "About: …") takes the header's second line, where the other tabs say who you are. |
| Ask buttons | `Panel.lua`, `Marks.lua` | Unchanged: the answer opens in the card beside the window, so the tab stays in view. **Ask more** switches to the Chat tab with that thread. |
| Compact | `Panel.lua` (SetCompact) | The chevron left of the fold button hides the rail, and the chat takes the whole width. It's 440×460 by default, 406×366 at least. Each mode keeps its own size (`SpellmindDB.panel.w/h` and `cw/ch`). Picking another tab, or the minimap right-click, brings the rail back. |
| Fold | `Panel.lua` (Fold) | "-" folds the whole window to its header. The tab and mode are kept. It was the chat window's before. |
| Minimap | `Minimap.lua`, `Chat.lua` | Click opens the Chat tab, or closes the window when Chat is showing. Right-click (and `/sm panel`) opens the last other tab (`SpellmindDB.panel.other`), or closes it. `/sm` toggles the Chat tab. |
| The place | `Panel.lua` | One saved place. The first time, the old chat window's spot is used (`SpellmindDB.ui.point`). Esc closes it. |

The chat's picks (effort, search) stay in `SpellmindDB.ui`. The old window's own size (`ui.w/h`) and fold (`ui.folded`) are no longer used.
