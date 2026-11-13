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

## The quests you're missing (2026-11-12)

The player's ask: "list any missing quests, where to get them … Hall of Thanes could display that all quests are completed". The game alone can't list a dungeon's quests that aren't in the log, so this comes from **QuestieDB's public API** (`LibQuestieDB`, contract 4) when that addon is installed. Spellmind calls it at runtime and ships none of its data (QuestieDB's content is all rights reserved, so nothing of it is copied).

- **The list:** one pass over QuestieDB's quests (400 a frame, once a session) sorts them by zone. A dungeon's quests have the dungeon as their zone. The dungeon is found from a quest of its in the log, else by name (QuestieDB's named areas, then `C_Map.GetAreaInfo`). "The Hall of Thanes" and "Hall of Thanes" are one dungeon, so the LFG list no longer shows a dungeon twice (seen in game: "The Deadmines" and "Deadmines").
- **For this character:** a quest is left out when it's for another race, class or faction (by its giver), needs a profession, is past its max level, or is shut out by an exclusive quest already done or taken.
- **Each quest is one of:**
  - **done**: `C_QuestLog.IsQuestFlaggedCompleted`;
  - **in your log**;
  - **to pick up**: tagged, with "from Thane Ironbelly, Ironforge (45, 51)";
  - **later**: "after Oh Brother…" (a prerequisite not done) or "at level 22".
- **The tab:**
  - each dungeon's line reads "1 to pick up · 2 later · 1 in your log · 1 done", or "All 4 quests done" in green;
  - the quests to pick up are listed under your log's dungeons and the one you're in;
  - an at-your-level dungeon has a **Quests** button that opens its list under it (and **Hide** closes it);
  - without QuestieDB, a grey line says what it would add.
- **The briefing:** the question names the quests to pick up and their givers, and what's done, so the AI orders the pickups instead of guessing the list.

**Chains (seen in game):** "Red Silk Bandanas: after The Defias Brotherhood" pointed at nothing the player could act on. That quest is a chain of steps with the same name, and its first steps start in Westfall, outside the dungeon, so they weren't listed. Now a locked quest's chain is walked back to the step to do next:
- a step in the log: "after The Defias Brotherhood (in your log)";
- otherwise the earliest step whose own prerequisites are done. It's listed as a pickup, "The Defias Brotherhood (first step)", with its giver and "leads to Red Silk Bandanas, The Defias Brotherhood". The later quests say "after The Defias Brotherhood (pick it up first, above)".

The briefing names those first steps too.

**Go to the giver (seen in game: the "pick up" tag looked like a button that did nothing).** The tag is gone. A quest ready to take now has **Pick up** in gold at the start of its line, and a **Go** button. Go sets the game's map pin and arrow on the giver (`Quests.Pin`, as quest Go does). QuestieDB's coordinates are used as Questie shows them, and QuestieDB's own zone-to-map table (`Support.Get("ZoneDB").private.areaIdToUiMapId`) gives the game's map. Locked quests have no Go.

**Fix: Go couldn't pin (seen in game, 2026-11-12).** In Westfall, Go on Alba Fairmoon and Gryan Stoutmantle said 'The game can't pin � on the map'. QuestieDB keeps its zone-to-map table as Lua source text, not a table, so no map was ever found. Spellmind doesn't run another addon's text: it finds the map by the zone's name in the game's own map list instead (`Dungeons.MapNamed`: the player's map, then each continent's zones; kept for the session), which needs no other addon. `World.lua`'s QuestieDB NPCs had the same flaw and use the same lookup by name.
