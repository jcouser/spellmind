# Milestone 23: the route (design)

*Status: design 2026-11-18; built 2026-11-19 (the notes marked "Built" below), tried in game by the maintainer; released in 0.5.0. Still to come: paths learned from where the player walks and roads traced by hand (the line and arrow bending around terrain), the AI's suggestions as one-click skips.*

The player (2026-11-18), after a fixed leveling guide's "Redridge 25-26" sent them to Stormwind for a turn-in across the world, with quests still open around them: a route that follows **this character** (its quest log, where it stands, what it has done), efficient like a hand-tuned guide, with navigation (a step tracker, an arrow, the world map), steps that advance by themselves, and the AI where judgment helps.

Written from scratch: other guide addons (OpenXP) showed what players expect, nothing is taken from them.

## What the player gets

1. **Where next:** the nearby zones by what's actually left for this character at its level (quests in the log, quests it can pick up there, not done), with XP. Not a zone's general level range: a zone the player has emptied isn't suggested (seen: the AI suggested Duskwood at 26 after the player had done it at 23-25).
   *Built (2026-11-19, `RT.Zones`):* each zone's quests to pick up (the route's own rules: open now, at the level, the giver there and of the faction) and the log's quests there, valued (a few levels below counts less) per minute: about 5 minutes a quest, plus the way there, the quickest of: on foot (straight line × 1.3, mounted from 40); a flight path the character knows (walk to the nearest one, fly at about 25 yards a second plus a minute, walk from the one nearest the zone); the hearthstone when it's in the bags, off cooldown and its landing spot known, then on foot or by air. Another continent with no known way: about 12 minutes. Where the flight paths are comes from the flight map (`TaxiNodePosition` on its continent's map), trusted only when the one the player stands at comes out where they stand; the hearthstone's landing spot is noted a moment after it's used, or at the innkeeper of its inn. The tracker shows the best three under "Where next" once three steps or fewer are left; with none left, the band names the best and Go pins its quest givers. The AI gets the same ranking, the player's zone marked "here" (the advisor part's `whereNext`), so "stay" can be its answer.
2. **The route:** ordered steps for the chosen area: pick up, do (kill, loot, use, collect), turn in, travel. Each with Go (the game's pin), the Spellmind mark (ask the AI about it) and its progress.
3. **The tracker:** a small movable window (closed by default; `/sm route`, the minimap button's menu): the current step with its objectives live, Up next (5-10), done steps folded; Back, Next, Skip.
4. **The arrow:** on screen, pointing at the current step, with the distance in yards; hidden in instances (no position there), saying so.
   *Built (2026-11-19):* shown with the tracker; the game's minimap arrow art turned by the game's facing against world positions (`C_Map.GetWorldPosFromMapPos`: x north, y west), green within 20° of straight on, "You're there" within 12 yards. With nothing left in the zone it points along Where next's first leg: the flight master to fly from, or the next zone's quest giver on foot; the hearthstone is said in words. Drag moves it (kept); right-click hides it, `/sm arrow` brings it back.
5. **The world map:** numbered step markers and the route line through them. Objective areas only without Questie (Questie already draws them; Spellmind doesn't draw them twice).
   *Built (2026-11-19), changed by the player's ask:* a numbered dot at each step still to do (up to 12; the tracker's step numbers; hover for the step) and, over each kill or loot objective, the area of its densest spawns shaded (current step gold, the rest purple), with Questie or without: Questie marks each spawn, the area says which step it's for. On the route's zone map while the tracker is open, drawn on the map canvas under the map's pins. The route line (2026-11-19): from the player to the current step in gold, moved with them while the map is open, then on through the next steps in purple; to a chosen zone, green through its legs; a switch on the Route tab. Straight for now: the game has no road or terrain data, so bending lines wait for paths learned from where the player walks, and roads traced by hand for the main zones.
6. **The AI (with the app):** "Plan my next hour" returns route steps, not only text; the player can ask why this order, or say "skip Duskwood". The AI reviews and reorders; Spellmind checks every step it returns against the quest log and drops what doesn't fit.
   *Changed (the maintainer, 2026-11-19):* the AI doesn't write routes; it reviews Spellmind's. The game data carries the route (advisor.route: the zone, the step, the next ten in words, what waits for a level) and Where next, so every answer starts from the plan the player sees. "Plan my next hour" became "Review my route", with "Why this order?"; the player's own questions go through the chat. Next: a suggestion to skip a step comes back as a chip that skips it (as the chat's Pin chips set pins).
7. **The Route tab** (the maintainer, 2026-11-19: "one of the core features", known only by switches in Settings): in the Spellmind window after Quests. The route's switches (the route, the arrow, the map's steps; moved from Settings); every step numbered (done, now, skipped, to come) with Skip or Unskip; Where next, every zone, with Aim for the arrow; Elsewhere; Ask about your route; the two quick asks. The tracker's owl opens it; the Quests tab's first row has Show or Hide and Open.

Every part works without the app; the AI parts need it.

8. **A chosen zone holds until you get there** (the maintainer, 2026-11-19: flying to Wetlands through Loch Modan, the route switched to Loch Modan's quests). Aim on a zone lasts until the player arrives there or clicks it again. Zone changes on the way don't end it. Meanwhile the steps where the player stands wait: the tracker reads "On the way to Wetlands" with the way there, the map and minimap show only the way, and "Quest here instead" (on the tracker and the Route tab) brings the local steps back. The AI is told where the player is heading. Where next always keeps the chosen zone, however it ranks. Where next is on the tracker always (it waited until three steps or fewer were left here, so Wetlands couldn't be chosen from Loch Modan), and the choice is saved per character (a hash of its GUID) through /reload and logins.

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
- **Questie first, said openly** (the maintainer, 2026-11-19): Questie is the popular choice, so the route is built for it and credits it ("Quest data from Questie" in the tracker; OptionalDeps in the TOC so it loads first). Questie's own hidden-quest list (QuestieCorrections.hiddenQuests) is read, read only, the one exception to "public interfaces only": the quest database has quests that aren't in Forever (Season of Discovery's), the server even knows their titles, and nothing else marks them. Without Questie, on Forever, Season of Discovery's ids (76000-91999) are left out as a fallback, and the tracker says what Questie would add.
- **A Forever source of what players have seen** (AHledger's "what players see in game": quests and NPCs) would confirm what really exists; it has no API for it yet (asked for, 2026-11-19).

## Phases (a release each, tried in game before the next)

1. **Where next, the route, the tracker** (with the routing above and auto-advance).
2. **Navigation:** the arrow; world map markers and route line; objective areas without Questie.
3. **The AI:** reviews the route ("Review my route", "Why this order?", the player's questions), its suggestions applied with a click.

## Open questions

- The tracker's look: Spellmind's own (purple frame, the owl), not a copy of another addon's.
- Running speed and mount: the estimate changes at 40 with a mount.
- Group play: a party member's quests aren't known; the route is the player's own.
