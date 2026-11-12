# Milestone 13: dungeon prep

This covers features.md §3.7. Forever has dungeons of its own (the Hall of Thanes), so a built-in dungeon list would be wrong or stale. Spellmind reads what the game itself knows, and leaves the briefing to the AI with web search.

| Piece | File | What it does |
|---|---|---|
| Where you are | `Dungeons.lua` (Here) | `IsInInstance` and `GetInstanceInfo`: the dungeon or raid you're in, with its difficulty. |
| Your quests' dungeons | `Dungeons.lua` (FromLog) | Quests the game tags Dungeon or Raid, grouped by their quest log header (the game files a dungeon's quests under the dungeon's name). For each: how many, their levels, and how many are ready to turn in. |
| At your level | `Dungeons.lua` (Listed, AtLevel) | When the client has the LFG tool (`C_LFGList`), its dungeons (category 2) with their suggested levels. A dungeon shows when its range reaches within 3 levels below or 4 above. Without the tool, the section doesn't show. Probe round 6 checks which of these Forever has. |
| The Dungeons tab | `Panel.lua` | Second in the rail (the key icon). **You're in …** with Brief. **Your quests are for** has each dungeon with LFG and Brief, its quests underneath with Go and Break it down. **At your level** lists the rest. The Ask buttons are **Which dungeon now?** and **Brief my next one** (the dungeon you're in, else the first in your log). |
| Brief | `Dungeons.lua` (Briefing), the prompt | "Brief me for The Hall of Thanes as a level 15 DPS Rogue. My quests for it: … Tell me: …". The answer opens in the card beside the window. The prompt's **Dungeon briefings** section asks for a web search first, then: quests to pick up, the level range, the bosses in order with a tip each for the role, loot for the class, and what to bring. |
| LFG | `Quests.lua` (LFGFor), `Panel.lua` | The same short line as a quest's ("LFG Hall of Thanes DPS Rogue") and the same menu of where to post it. Nothing is sent: it goes in the chat box. |
| The nudge | `Nudges.lua` (Detect.dungeon) | Entering a dungeon (after a loading screen, past login's first look): "Entering The Hall of Thanes: 1 of your quests here. Want a briefing?" Ask sends the briefing. It's gone when you leave, and the next visit nudges again. Its own switch is in Settings. |

## To verify in game

- Run `/sm probe` then `/reload` (probe round 6), and see whether `C_LFGList` lists dungeons and levels on Forever. Check `GetInstanceInfo` inside a dungeon, and the dungeon entrances API for a Go to the entrance later.
- Check that a dungeon's quests sit under its name in the log.
- It's a new file (`Dungeons.lua`), so it needs a full restart.
