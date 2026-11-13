# Milestone 17: accuracy (where things are, and a double-check)

Seen in game, 2026-11-12:
- "Head through the mountain pass from Loch Modan to Westfall" (there's none). The correction looped through Menethil and back.
- "Vrok Blunderblast sells bullets in Thelsamar" (not found; the General Supplies vendor had ammo).
- "Heavy Shot, not Light" contradicting the answer before it.
- The player: "there's always an accuracy issue until I ask a few times".

Who and where came from the model's memory, and nothing checked an answer. The player also set a rule: as a published addon, Spellmind can't rely on other addons, so every fix works on its own and other addons only add to it.

| Piece | File | What it does |
|---|---|---|
| The `world` part | `World.lua`, `State.lua`, `charstate.mjs` | Where you are, your hearthstone (`GetBindLocation`), the flight paths you know (noted at each flight master's map), and NPCs nearby, nearest first. **Your own visits** note an NPC's name and title from its tooltip data ("General Supplies"; never `UnitName`), zone and spot, what it offers (vendor, trainer, flight, innkeeper, banker, repair), and a vendor's goods (ammo and food first, 40 kept, 10 sent): `SpellmindDB.npcs`, account-wide, by faction. **QuestieDB, only if installed**: the zone's other service NPCs friendly to you, from its public API (one pass, 400 a frame, once a session). Without it, your visits are what there is. The eleventh part is optional, has a Settings switch ("Places"), and trims a vendor's goods first, then NPCs. |
| Travel in the prompt | `prompts/spellmind.md` | **Where things are and how to get there:** people nearby come from `world`, never memory. If nothing fits, the AI says a town guard gives directions, and names no one. Routes use only the zone links listed (classic, written from the map and only the certain ones), the boats, the tram, the zeppelins, the flights you know and the hearth. Never a made-up pass. |
| The double-check | `core/ai/check.mjs`, `tools/spellmind.mjs`, `service.mjs` | An answer to a where, who, sells, route, drop or quest-step question, or one that cites sources or gives coordinates, goes once more to the AI before you see it. It has the same game data, the chat, the question and its draft, and is told to verify each claim against the data then the web, fix or drop what it can't support, and check it answers the question without contradicting the chat. A failed check keeps the draft, and plain chat isn't checked. A guide import is never checked (its answer is JSON). **Double-check facts** in Settings (on by default) sends `check=0` when off. |
| Sources once | `core/link/render.mjs` (mergeSources) | "(Sources: WoWHead Classic; …) (source: wowhead.com)" becomes one "(sources: …)", a site named once. |

## Tested live (2026-11-12, the player's ChatGPT plan)

- "How do I get to Westfall from here?" (Stoutlager Inn): fly Thelsamar → Ironforge, the Deeprun Tram, west through Elwynn. The check confirmed it from the known flights. Each request took about 5.5 s.
- "Anyone sell ammo here?" with one visited vendor: "Yanni Stoutheart, the General Supplies vendor beside you, sells Light Shot and Heavy Shot." The check dropped a made-up source.
