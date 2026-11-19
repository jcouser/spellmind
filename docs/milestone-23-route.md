# Milestone 23: the route (design)

*Status: design, 2026-11-18. Not built yet.*

The player (2026-11-18), after a fixed leveling guide's "Redridge 25-26" sent them to Stormwind for a turn-in across the world, with quests still open around them: a route that follows **this character** (its quest log, where it stands, what it has done), efficient like a hand-tuned guide, with navigation (a step tracker, an arrow, the world map), steps that advance by themselves, and the AI where judgment helps.

Written from scratch: other guide addons (OpenXP) showed what players expect, nothing is taken from them.

## What the player gets

1. **Where next:** the nearby zones by what's actually left for this character at its level (quests in the log, quests it can pick up there, not done), with XP. Not a zone's general level range: a zone the player has emptied isn't suggested (seen: the AI suggested Duskwood at 26 after the player had done it at 23-25).
2. **The route:** ordered steps for the chosen area: pick up, do (kill, loot, use, collect), turn in, travel. Each with Go (the game's pin), the Spellmind mark (ask the AI about it) and its progress.
3. **The tracker:** a small movable window (closed by default; `/sm route`, the minimap button's menu): the current step with its objectives live, Up next (5-10), done steps folded; Back, Next, Skip.
4. **The arrow:** on screen, pointing at the current step, with the distance in yards; hidden in instances (no position there), saying so.
5. **The world map:** numbered step markers and the route line through them. Objective areas only without Questie (Questie already draws them; Spellmind doesn't draw them twice).
6. **The AI (with the app):** "Plan my next hour" returns route steps, not only text; the player can ask why this order, or say "skip Duskwood". The AI reviews and reorders; Spellmind checks every step it returns against the quest log and drops what doesn't fit.

Every part works without the app; the AI parts need it.

## Building the route

**Order rules (hard):** pick up before doing; doing before turning in; a chain's earlier step before its later ones; a quest the character can't take yet (level, prerequisite) isn't a step.

**Costs:**
- Travel: real distance (map coordinates through the game's world positions), at running speed; flight paths the character knows, the hearthstone (if it's off cooldown and set somewhere useful), boats and trams as edges with their own time.
- Objectives: an estimate of the time each takes (kills and loot by count, a drop-rate guess for loot; tuned from play).
- Value: each quest's XP (the quest log's reward XP; for pickups, an estimate from its level); quests far below the character's level count less, and ones far above are flagged, not routed.

**Steps:**
1. Choose the area: the zone(s) with the most XP left per estimated minute.
2. Group: objectives whose areas overlap or lie near the path are one stop ("kill Skeletal Warriors" and "loot Skeleton Fingers" in one graveyard); a pickup or turn-in is done when the route passes its giver.
3. Order: nearest next, then improve by swaps (2-opt / or-opt) while the order rules hold. 30-50 stops: a moment, in game.
4. Turn-ins wait until the route passes their giver, unless one opens a follow-up worth doing now.

**When:** rebuilt on a zone change and when the quest log changes; never in combat (it waits, as the game-data build does now). Done steps are kept.

## Steps advance by themselves

By state, not by step number: a step done out of order is ticked when it happens, and a step already done when the route is built never shows.

| Step | Done when |
|---|---|
| Pick up | the quest is in the log |
| Kill / loot / use (an objective) | the objective's count is full (the quest log) |
| Collect an item that isn't an objective (a starter item, a reagent to bring) | the bags hold enough (item count) |
| Buy | the item is in the bags |
| Turn in | the quest left the log and the game counts it completed |
| Talk (no quest change) | within a few yards of the NPC, or the next step's quest appears |
| Go / travel | within range of the spot, or in the new zone after a flight, hearthstone or boat |
| Train / level | the spell is learned / the level is reached |

The events: quest log and objective updates, quest accepted and turned in, bag updates, zone changes, taxi, spells learned, level up; position checks a few times a second only while a "go" or "talk" step is current.

## Data

- **The quest log and the game's quest map markers:** always; enough to route the log's quests and their turn-ins.
- **Questie's database (optional, its runtime interface only):** quest givers and turn-ins with coordinates, NPC and object spawns, quest levels, prerequisites, the zone's other quests; the completed quests from the game. What makes efficient routing and "Where next" possible.
- Without Questie: the route covers the quests in the log; "Where next" counts only those.

## Phases (a release each, tried in game before the next)

1. **Where next, the route, the tracker** (with the routing above and auto-advance).
2. **Navigation:** the arrow; world map markers and route line; objective areas without Questie.
3. **The AI:** route steps from "Plan my next hour", review, "why", "skip".

## Open questions

- The tracker's look: Spellmind's own (purple frame, the owl), not a copy of another addon's.
- Running speed and mount: the estimate changes at 40 with a mount.
- Group play: a party member's quests aren't known; the route is the player's own.
