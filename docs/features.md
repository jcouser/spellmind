# Spellmind: features and interactions

*Status: plan for review, 2026-11-10. It replaces the feature list in design.md, which keeps the architecture.*

Spellmind is one companion with a few surfaces, not a set of separate tools. This page has:

- the rules every feature follows;
- the surfaces they share;
- each feature, with when it appears, what the player sees, the data behind it and what the AI does;
- the research still open;
- the order to build in.

## 1. Rules every feature follows

1. **Live, not a snapshot.** Anything on screen updates from the game's own events: a quest objective ticks, a level, a new item, a talent point. It never waits for the player to ask again. *This is the gap in NeverQuestAlone's routing: it plans once and goes stale.*
2. **Local first, AI on top.** What the addon can work out itself, it does, in game and instantly, at no cost. That covers sorting quests, counting bag space, spotting an unspent talent point and comparing an item's stats. The AI is for judgment, explanation and plans: "why", "what should I", "make me a plan". *A panel never sits waiting on an AI call to show its facts.*
3. **Ask, don't interrupt.** Spellmind never pops up in combat, never steals keyboard focus, and never speaks unprompted except through a small, dismissible nudge. Nudges are off for anything the player turns off, and grouped so there's never a stream of them.
4. **The data is the truth.** Every verdict names the fact behind it ("+3 agility over your robe"). A missing fact is said, never guessed. *This is what the prompt already enforces.*
5. **One question away.** Every panel and nudge has an **Ask** that opens the chat with the question and its context already in place (the item, the quest, the talent). The player edits it or just presses Enter.
6. **Advice only.** No automation, ever: Spellmind never clicks, casts, buys or equips. It can set a map waypoint, which is the game's own player-facing feature, and only when the player clicks for one.

## 2. Shared surfaces

Every feature is built from these, so the addon stays coherent and small.

| Surface | What it is | Used by |
|---|---|---|
| **Chat window** (`/sm`) | The conversation: movable, resizable, scrollable, remembers its place. An input box with **item and quest links** (shift-click an item or quest into it, as with the game's chat). A row of **suggestion chips** under a reply ("Compare with my dagger", "What do I train next?"). | Everything |
| **Advisor panel** | One frame with tabs: **Quests · Gear · Talents · Spells · Professions · Gold**. Each tab shows the local facts at once (live), with Ask buttons beside them. It opens from the minimap button, `/sm panel`, or a nudge. | §3.1–3.6 |
| **Tooltip line** | One quiet line at the bottom of item tooltips: "Spellmind: can't use: no Bows skill", or "upgrade over Cheese Knife (+0.3 dps)", from local rules only (no AI). Shift-right-click asks about the item. | Gear |
| **Nudge** | A small toast near the minimap (or a chat line, by setting): an icon, one line and **Ask** / **Dismiss**. Grouped, at most one at a time, never in combat. | Talents, Spells, Bags, Quests, Dungeons |
| **Minimap button** | Opens the panel; right-click opens chat. Its icon shows a dot while a nudge waits. | All |
| **Waypoint** | The game's own map pin and super-tracked arrow (`C_Map.SetUserWaypoint`, `C_SuperTrack`), set when the player clicks **Go** on a quest or a stop. *To probe on Forever.* | Quests, Dungeons, Professions |

Style (with Codex for art): Spellmind's own frame and icon, a small persona portrait in the chat header, and quality colors for items. Text sizes follow the game's UI scale.

## 3. Features

Each feature lists: **what the player gets**, **triggers**, **UI**, **data** (✓ already sent, ◐ partly, ✗ new), **local vs AI**, and **open questions**.

### 3.1 Quest guide (replaces relying on NeverQuestAlone)

**What the player gets:**
- the log in a sensible order for *this* character;
- what's left of each quest;
- where to go next, kept up to date as they play;
- advice on which quests to skip, do in a group, or hand in first.

**Triggers:** `QUEST_LOG_UPDATE`, `QUEST_WATCH_UPDATE`, `UNIT_QUEST_LOG_CHANGED`, a level-up, a zone change, an objective ticking. The list re-sorts **locally** on each; no AI call.

**UI:**
- **Quests tab.** Groups:
  - **Ready to turn in** (nearest first)
  - **Do now** (at your level, in this zone)
  - **Later** (too high: the level gap shown)
  - **Skip?** (grey: trivial XP)
  - **Group** (elite or group quests)
- **Each row:**
  - a difficulty color from the quest's level against yours;
  - the remaining objectives ("0/8 Carved Stone Idol");
  - the distance and direction from you when the game knows the quest's spot;
  - **Go** (set the waypoint), **Ask**.
- **Top of the tab:** "**Next:** turn in *Stormpike's Order* — 120 yd ahead", which updates as you move.
- **Plan my session** (AI): "I have an hour; what's the best order?" returns a stop list that the tab then follows live, ticking stops off as objectives complete. If the log changes under it (a new quest, an abandoned one), the plan is marked "out of date — re-plan?", never silently kept.

**Data:**
- ✓ `quests` (titles, levels, objectives with have and need).
- ✗ per-quest **map positions**: the quest's POI (`C_QuestLog.GetQuestsOnMap` / `GetNextWaypoint`; to probe), plus the player's position (✓ `char.loc`).
- ✗ **difficulty and trivial** (`C_QuestLog.GetQuestDifficultyLevel`, `IsQuestTrivial`; to probe).
- ✗ **group or elite tags** (`C_QuestLog.GetQuestTagInfo`; to probe).
- ✗ the **reward choices** (on the quest's details; to probe).

**Local vs AI:**
- Local: grouping, sorting, distance and direction, the "Next" line, progress, the plan's live ticking.
- AI: the session plan, "is this worth it", where an objective's mobs or items are (from memory, hedged), and quest reward picks (§3.2).

**Open questions:**
- Does Forever give quest POIs for every quest, or only tracked ones?
- Coordinates for turn-ins (NPCs) may need the quest's "ready" POI.

### 3.2 Gear advisor ("Should I…?")

**What the player gets:** for any item (worn, in bags, a quest reward, on the auction house, in a loot roll), a verdict: **Equip**, **Keep for later**, **Vendor**, **Auction** or **Disenchant**, with the reason in one line.

**Triggers:**
- Local: a new item in the bags (`BAG_UPDATE_DELAYED`).
- Local: a quest reward window opening (`QUEST_COMPLETE`).
- Local: a loot roll (`START_LOOT_ROLL`).
- Player: shift-click into chat, Ask on the tooltip or the Gear tab.

**UI:**
- **Tooltip line** (local rules):
  - "can't use: no Bows skill / armor too heavy / level 20";
  - "**upgrade** over *Cheese Knife*: +0.3 dps, +1 agility, −1 stamina";
  - "**vendor**: 72c, soulbound, worse than worn".
- **Gear tab:**
  - each slot with what's worn, its item level and durability;
  - the best item in your bags for that slot, when there is one, with **Equip?** (Ask);
  - empty slots highlighted.
- **Quest reward window:** a small "Spellmind suggests: *Frontier Britches*" badge beside the choices (local first pick, AI on Ask).
- **Bag cleanup** (with §3.6): "**12 free slots**. Vendor these 7 (1g 45s) · Keep these 3."

**Data:**
- ✓ `gear` with stats, ✓ `bags` with `sub` and `st`, ✓ `skills.weapon`, ✓ `char`, ✓ `talents` and `spells` (role).
- ✗ Quest reward items (by hovering or on `QUEST_COMPLETE`).
- ✗ Loot-roll items.
- ✗ Stat weights: **Pawn**, if its functions for other addons fit the rule, else a simple per-class priority table we write ourselves (licensed by us).

**Local vs AI:**
- Local: can-use, stat deltas, sell value, "best in bags for this slot".
- AI: the verdict where it's a judgment (stamina vs agility at this level, keep for an off-spec), and explaining it.

**Open questions:**
- Pawn's API and license.
- Our own stat priorities per class and spec at leveling ranges: ours to write, as data.

### 3.3 Talent planner

**What the player gets:** a build for their goal (leveling, dungeons, PvP), what to take with the next point, and a nudge when a point is unspent.

**Triggers:**
- `PLAYER_LEVEL_UP` / `TRAIT_CONFIG_UPDATED`: an unspent point gives a **nudge** ("1 talent point to spend: Ask what to take").
- Talents tab.

**UI:** the **Talents tab** shows:
- spent and unspent points;
- your nodes;
- the **plan** (AI-made, saved per character):
  - a list of "next 5 points", with the reason for each;
  - progress against it;
  - it re-checks after every change, and if you spend off-plan it says so once.

**Data:**
- ✓ `talents` (nodes with ranks).
- ✗ The **whole tree**: every node's name, max rank and position, and which are available now (`C_Traits.GetTreeNodes`, `GetNodeInfo` for all, not only ranked). A bigger part, sent once per character and cached.

**Local vs AI:**
- Local: the unspent nudge, "next in plan", plan progress.
- AI: making the plan and explaining choices.

**Open questions:**
- Tree size on the wire: 54 nodes × name ≈ 2.5 KB plain. Fine as its own `tree` part, sent rarely.
- Advice on spec respec cost.

### 3.4 Spells and training

**What the player gets:** what they'll learn next and when, a reminder to visit the trainer, and "what's my rotation now" from their actual spellbook.

**Triggers:**
- `PLAYER_LEVEL_UP` when `spells.next` has entries at or below the new level: a **nudge** "New at your trainer: Kick (Rank 2), Sprint. Your trainer is in Thelsamar."
- Spells tab.

**UI:** the **Spells tab** shows:
- the spellbook grouped by tab;
- **Coming up**: level, then spell;
- **Rotation** (AI, saved): a short priority list from the spells you have, refreshed when a new rank or spell arrives.

**Data:**
- ✓ `spells` (with `next`).
- ✗ Trainer location: from memory (AI, hedged), or by zone from our own data later.

**Local vs AI:**
- Local: the train nudge, "coming up".
- AI: the rotation, the explanations.

### 3.5 Professions

**What the player gets:** the cheapest path to the next skill milestone, from what's in the bags; what to gather where; when to visit a trainer.

**Triggers:**
- `SKILL_LINES_CHANGED` at a cap (75/150/225): a **nudge** "Leatherworking 75/75: train Journeyman".
- Professions tab.

**UI:** the **Professions tab** shows:
- each profession's rank against its cap;
- a **Path** (AI): "Craft 6 Light Armor Kits (you have the leather) → 33…", which ticks as the skill rises;
- a **Shopping list**: what's missing.

**Data:**
- ✓ `skills.prof`, ✓ `bags`.
- ✗ **Known recipes** (`C_TradeSkillUI`, only while the profession window is open; to probe).
- ✗ Recipe data: the client's own recipe info when the window is open; otherwise the AI's memory, hedged.

**Local vs AI:**
- Local: caps, trainer nudges, path ticking.
- AI: the path itself.

**Open questions:** known recipes are only readable with the window open, so the addon caches them on open.

### 3.6 Gold and bags

**What the player gets:** bag space kept sane, junk sold, and what's worth selling at auction.

**Triggers:**
- `BAG_UPDATE_DELAYED` with free slots ≤ 4: a **nudge** "Bags nearly full: 7 to vendor".
- `MERCHANT_SHOW`: a quiet list "Sell to this vendor: …". *No auto-sell: the player clicks.*

**UI:** a **Gold tab** with:
- money;
- junk value;
- vendor and keep lists (local);
- **Ask** "how should I make gold at my level?" (AI).

**Data:**
- ✓ `bags` (junk, sell value per item would be new: ✗ add `sell` to bag items).
- Auction prices: none (no network, no AH scan) unless the player opens the auction house: an **AH scan on open** is a later idea.

### 3.7 Dungeon prep

**What the player gets:** going into a dungeon, the quests to grab first, the bosses and their tips for their role, and loot worth hoping for.

**Triggers:** a zone change into an instance (`PLAYER_ENTERING_WORLD` with `IsInInstance`): a **nudge** "Entering the Deadmines: 3 quests here, Ask for a briefing".

**UI:**
- A **briefing** in chat (AI): quests in the log for it, the bosses in order with one tip each for the role, loot for the class.
- **Quests for this dungeon** in the Quests tab.

**Data:**
- ✓ `quests`, ✓ `char`, ✓ `talents` (role).
- ✗ Instance name and difficulty (`GetInstanceInfo`; to probe).
- Bosses and loot: AI memory, hedged; our own data later.

### 3.8 After the fight (combat review)

**What the player gets:** a short review after a long or lost fight: damage taken by source, abilities used, idle time, "you used Sinister Strike 14×, Eviscerate at 1–2 combo points 4×".

**Triggers:** `PLAYER_REGEN_ENABLED` after a fight longer than ~15 s, or a death. It is **opt-in**, and off by default.

**UI:**
- A one-line summary in chat (local), with **Review** to get the AI's take.
- The fight's summary goes as a ✗ new **`fight` part**: counts and totals only, never other players' names.

**Data:**
- ✗ `COMBAT_LOG_EVENT_UNFILTERED`, aggregated locally during the fight: ability counts, damage taken by source type, deaths.
- *To check: Blizzard's 2026 combat-API restrictions (Midnight) and how Forever applies them. They may limit this feature.*

### 3.9 Free chat

Always available: anything the player asks, with the character attached. Chips under replies suggest follow-ups. Item and quest links in the input box add that item's or quest's details to the message.

### 3.10 Settings and privacy

**In game:**
- `/sm data` already exists.
- A **Settings** tab with:
  - game data on or off, per part;
  - nudges on or off, per kind;
  - the tooltip line on or off;
  - the combat review on or off;
  - the chat frame lines, for short replies.

**In the app (milestone 3):** sign-in, the AI and model, per-part sharing, usage.

## 4. Data still to add (by part)

| Part | Adds | For |
|---|---|---|
| `quests` | per-quest `poi` (map x,y), `diff` (difficulty color), `trivial`, `tag` (elite, group, dungeon), `track` | 3.1 |
| `tree` (new, rare) | every talent node: name, max, available | 3.3 |
| `bags` | `sell` per item | 3.2, 3.6 |
| `recipes` (new, cached on open) | known recipes per profession | 3.5 |
| `fight` (new, opt-in) | the last fight's aggregates | 3.8 |
| message context | a linked item's or quest's full details | 3.2, 3.9 |

## 5. Research to do (probe first, as before)

- Quest POIs and waypoints: `C_QuestLog.GetQuestsOnMap`, `GetNextWaypoint`, `C_Map.SetUserWaypoint`, `C_SuperTrack.*`.
- Quest difficulty, trivial and tags: `GetQuestDifficultyLevel`, `IsQuestTrivial`, `GetQuestTagInfo`.
- Quest reward items: `GetNumQuestChoices`, `GetQuestItemLink`.
- Talent tree, all nodes.
- Recipes: `C_TradeSkillUI`.
- Instances: `GetInstanceInfo`.
- Combat log access and Midnight's restrictions on Forever.
- Pawn's API and license.
- Hooking item links into our input box (`ChatEdit_InsertLink`) and tooltips (`TooltipDataProcessor`).

## 6. Build order (proposed)

1. **Surfaces first:**
   - the Advisor panel shell with its tabs;
   - nudges;
   - the minimap button;
   - item and quest links into the chat box;
   - chips;
   - Codex art.

   Everything after plugs into these.
2. **Quest guide** (3.1): the player's top ask, and the one the NeverQuestAlone gap shows.
3. **Gear advisor** (3.2), with the tooltip line and quest rewards.
4. **Talents and spells** (3.3, 3.4): nudges, plan, rotation.
5. **Bags and gold** (3.6).
6. **Professions** (3.5).
7. **Dungeon prep** (3.7).
8. **Combat review** (3.8), if the combat APIs allow it.

Milestone 3, the desktop app, can go in parallel at any point. It's independent of the in-game features.
