# Milestone 15: your guide

The player follows a leveling guide (Mobalytics' WoW Forever rogue guide) and asked for "as much as possible imported from a simple link vs copy and pasting chunks". The Talents tab was also the last tab that only repeated the game.

## Getting the guide in

- **Mobalytics refuses automated readers:** Cloudflare's "Just a moment…" challenge answered both a plain fetch and a browser-like one from the player's own machine (403). Spellmind doesn't try to get past it.
- **The AI can read it:** a test on 2026-11-12, through the player's ChatGPT plan with web search, read the page itself. It returned the Combat build's full point order, levels 10 to 60, with Forever-only talents such as Efficient Strikes and Flash of Steel, plus the ability priority, stat priority and weapon advice.
- **So the import is a turn:** the player gives the link once, and the app's AI reads the page.

| Piece | File | What it does |
|---|---|---|
| The link | `Guide.lua`, `Chat.lua`, `Panel.lua` | `/sm guide <link>`, or **Set link** in the Talents tab or Settings. Set link opens a small box to paste into (Ctrl+V). Only `https://` links are taken. It's kept per character, and a new link forgets the old plan. |
| The import | `Guide.lua` (Import), `core/link/guide.mjs`, `service.mjs` | The addon sends "Import my guide: <link>" (and "Build: <name>" for a build picked by name) with `guide=1`. The app asks the AI to read the page with web search on and no chat history, reporting only what the page says and never filling gaps. It gives back one JSON object: title, build, builds, talents (level, talent, rank), rotation, stats, weapons, and an error when it couldn't read the page. The app checks the JSON: names sanitized, lists capped, and steps without a level, rank or name dropped. |
| The reply | `service.mjs`, `Chat.lua` | The chat gets one line ("Imported Combat from mobalytics.gg: 51 talent points (levels 10 to 60), the ability priority, …"). The reply record carries the plan, which the addon keeps (`SpellmindDB.chars[key].guide`). A failure is an error line with the reason, such as the AI's own "couldn't read it". |
| The Talents tab | `Panel.lua`, `Guide.lua` (Progress) | **Your guide: Combat**, with how many points are taken, and **Change** and **Re-import**. **Next points** (or **Spend your 2 points**) shows the next four steps not taken, counted to the tree's top rank ("Malice 2/3"). A step you have a point for now is green and tagged "now". **Off plan** flags a talent with more points than the guide gives it. **Not in your talents** lists any name the tree doesn't have (the import may have misread it): shown, never quietly followed. The page's **other builds** each have **Import**. The game's own list of talents is gone: it only repeated the talent window. |
| The nudge | `Nudges.lua` | "A talent point to spend: Your guide: Malice 2/3." |
| The Spells tab | `Panel.lua` | **Your guide's priority** (numbered steps) and **Stats and weapons**. |
| The AI | `State.lua`, `charstate.mjs`, the prompt | The talents part gains `guide`: build, source, next (4), stats, rotation, weapons. It's dropped first when the part is too big. The prompt says to answer talent, rotation, stat and weapon questions from the guide first, and to disagree only for a concrete reason, said as its own view. |

## Still to do

- Verify in game: an import of the real guide, the name check against Forever's tree, and Re-import.
- The guide's stat priority could weigh the gear scoring (`Gear.MAIN`). For now it goes to the AI's upgrade answers only.
