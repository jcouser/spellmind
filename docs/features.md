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

**Decided (2026-11-10):** the home base is the chat window plus the Advisor panel, with the marks in the game's own windows (§2.1). Explain answers go to an answer card beside the window. Nudges are a toast by the minimap. The build order is §6.

| Surface | What it is | Used by |
|---|---|---|
| **Chat window** (`/sm`) | The conversation: movable, resizable, scrollable, remembers its place. An input box with **item and quest links** (shift-click an item or quest into it, as with the game's chat). A row of **suggestion chips** under a reply ("Compare with my dagger", "What do I train next?"). | Everything |
| **Advisor panel** | One frame with tabs: **Quests · Gear · Talents · Spells · Professions · Gold**. Each tab shows the local facts at once (live), with Ask buttons beside them. It opens from the minimap button, `/sm panel`, or a nudge. | §3.1–3.6 |
| **Tooltip line** | One quiet line at the bottom of item tooltips: "Spellmind: can't use: no Bows skill", or "upgrade over Cheese Knife (+0.3 dps)", from local rules only (no AI). Shift-right-click asks about the item. | Gear |
| **Nudge** | A small toast near the minimap (a chat line instead is a setting): an icon, one line and **Ask** / **Dismiss**. Grouped, at most one at a time, never in combat. | Talents, Spells, Bags, Quests, Dungeons |
| **Minimap button** | Opens the panel; right-click opens chat. Its icon shows a dot while a nudge waits. | All |
| **Waypoint** | The game's own map pin and super-tracked arrow (`C_Map.SetUserWaypoint`, `C_SuperTrack`), set when the player clicks **Go** on a quest or a stop. *To probe on Forever.* | Quests, Dungeons, Professions |

Style (with Codex for art): Spellmind's own frame and icon, a small persona portrait in the chat header, and quality colors for items. Text sizes follow the game's UI scale.

### 2.1 In the game's own windows

Spellmind meets the player where they already are, as well as in its chat and panel. One pattern everywhere:

- **The Spellmind mark:** a small icon button in a corner of a game window or a row. It sits unobtrusively beside what's there and never covers the game's own controls.
- **Hover:** instant local facts in a tooltip, with no AI call and no cost.
- **Click:** **Explain**. The AI answers about *that exact thing*, its context attached: the quest's full text and objectives, the item's stats, the talent's description. Shift-click puts it in the chat box to edit first.
- **Where the answer goes:** an **answer card** anchored beside the window it came from, for quick reads that stay with the window. It holds the reply, **Ask more** (which opens the chat with the thread), and close. Every answer is also kept in the chat window's history.

| Game window | Spellmind adds | Hover: local, instant | Click: AI |
|---|---|---|---|
| **Quest details** (quest log and map, and the NPC's quest window) | the mark in the details header | quest level against yours (difficulty color), group or elite, what's left, rewards you can use | **"Break it down"**: what to do in steps, where, what you'll need, whether it's worth it now, which reward to take |
| **Quest reward choice** (turning in) | a "Spellmind picks" badge on one choice | why (stat delta over your worn item; usable or not) | the reasoning, or "compare all three" |
| **Item tooltips** (anywhere: bags, character, loot, merchant, chat links, AH) | one quiet line at the bottom | can't use (skill, armor, level); upgrade or downgrade over worn, with the delta; vendor value | **"Should I…?"** keep, equip, vendor, auction, disenchant |
| **Character frame** (gear slots) | a tiny dot on a slot that has a better item in your bags; the mark in the frame's corner | which bag item and why | "review my gear": weakest slots, what to look for next |
| **Bags** | nothing on the slots by default (bag addons already mark upgrades; avoid clutter); the mark on the bag frame | free slots, junk value | "clean up my bags": vendor, keep, bank lists |
| **Talent tree** | the mark on the frame; a small "next in plan" glow on one node | a node's role in your plan, its ranks | "what should I take next and why", "make me a build" |
| **Spellbook** | the mark on the frame; a line in spell tooltips | the next rank and the level it comes at | "what's my rotation now", "what is this spell for" |
| **Class trainer** | a "Spellmind suggests" tag on rows | what's new since your last visit | "what's worth buying first with my gold" |
| **Merchant** | the mark on the window | your junk and worse-than-worn items, and their total value (no auto-sell) | "anything here worth buying?" |
| **Loot roll** | a small Need/Greed hint beside the item | upgrade or not, usable or not | why |
| **Profession window** | the mark; a "skill-up" tag on recipes worth crafting | colour and skill-ups left per recipe, materials you have | "plan my skill-ups to the next cap" |
| **World map** *(optional, with routing)* | nothing by default | none | "where do I find this?", answered with a waypoint |

**Rules for these:**
- **Off switches per window** in Settings. Every addition is small and labelled as Spellmind's.
- **Other addons come first.** Where another addon (Questie, Pawn, a bag addon, Forever Leveling BiS) already marks something, Spellmind's mark moves aside, or it stays off until the player turns it on.
- **Secure frames:** hooks only (`hooksecurefunc`, `TooltipDataProcessor.AddTooltipPostCall`, frames parented, never Blizzard functions replaced), so nothing taints the game's own UI. Nothing new is built or shown on a secure frame in combat; it waits for combat to end.
- **Game text is data.** The quest's text, the item's name and so on go in the game data block, under the prompt's rule. Text another addon or player could set is never followed as instructions.

## 3. Features

Each feature lists: **what the player gets**, **triggers**, **UI**, **data** (✓ already sent, ◐ partly, ✗ new), **local vs AI**, and **open questions**.

### 3.1 Quest help

**What the player gets:** quest advice that knows *this* character, kept up to date as the log changes. NeverQuestAlone's routing plans from a snapshot, without the level or the details, and goes stale; these features shouldn't.
- which quests are worth doing now, which are too high, trivial, or need a group;
- what's left of each quest;
- which reward to take;
- where to find what an objective needs;
- which to hand in first.

**Scope:** the core is the quest *help*. **Routing** (the "Next" line with distance, waypoints, a session plan) is **optional** and decided later, since it overlaps NeverQuestAlone. It's marked *(optional)* below.

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
- *(optional)* **Top of the tab:** "**Next:** turn in *Stormpike's Order* — 120 yd ahead", which updates as you move.
- *(optional)* **Plan my session** (AI): "I have an hour; what's the best order?" returns a stop list that the tab then follows live, ticking stops off as objectives complete. If the log changes under it (a new quest, an abandoned one), the plan is marked "out of date — re-plan?", never silently kept.

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
- *Probe round 4 (2026-11-10): `CombatLogGetCurrentEventInfo` is **missing** on Forever, and `C_CombatLog` has only filter and settings functions plus `IsCombatLogRestricted`. Addons can't read the combat log, so this feature is **parked** unless a later client opens it. Counting your own casts (`UNIT_SPELLCAST_SUCCEEDED` on "player") may still work and stays a possible small version.*

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

**In the chat window (in game, as NeverQuestAlone's chat has):**
- A **thinking dropdown** in the window's header: the levels the app's model offers (low, medium, high, and more for some), each with its trade-off from the test of 2026-11-10 (low about 3 s, high about 10 s; higher uses more of the plan's limits). The default is medium with web search, high without.
- A **web search** toggle beside it, shown only when the AI has search.
- How it works:
  - The app lists the model's levels and whether it can search in its slot (`bridge.ai = { efforts, effort, search }`).
  - Each message carries the player's choice (`effort=high;search=0`). The service checks it against the list, falling back to its default.
  - The choice is saved in `SpellmindDB`, so it sticks across sessions.
  - It's a plain dropdown of Spellmind's own (the modern client's menu API, or a simple list frame), never a secure template.
- Today it's `--effort` and `--search off` when the app starts (or `effort` and `search` in config.json).

**In the app (milestone 3):** sign-in, the AI and model, per-part sharing, usage, and the default thinking level and search setting that the chat window starts from.

## 4. Data still to add (by part)

| Part | Adds | For |
|---|---|---|
| `quests` | per-quest `poi` (map x,y), `diff` (difficulty color), `trivial`, `tag` (elite, group, dungeon), `track` | 3.1 |
| `tree` (new, rare) | every talent node: name, max, available | 3.3 |
| `bags` | `sell` per item | 3.2, 3.6 |
| `recipes` (new, cached on open) | known recipes per profession | 3.5 |
| `fight` (new, opt-in) | the last fight's aggregates | 3.8 |
| message context | a linked item's or quest's full details; for an Explain click, that exact thing (the quest's text and objectives, the item, the talent node) | 2.1, 3.2, 3.9 |

## 5. Research to do (probe first, as before)

### 5.0 Probe round 4 results (2026-11-10, client 1.60.1.70888)

**Quests** (tried on a turn-in quest, Stormpike's Order):
- `C_QuestLog.GetInfo(i)` has `level`, `difficultyLevel`, `suggestedGroup`, `isScaling`, `questClassification` and `isOnMap`; headers come first (`isHeader`).
- The text: `GetQuestLogQuestText(logIndex)` returns the description and the objectives text. `C_QuestLog.GetQuestObjectives(id)` returns `{text, type, finished, numFulfilled, numRequired}`.
- Difficulty: `GetQuestDifficultyColor(level)` (with its font name: Trivial, Standard, Difficult, VeryDifficult, Impossible). `UnitQuestTrivialLevelRange("player")` is 5. `C_QuestLog.IsQuestTrivial` and `IsEliteQuest` are there. `GetQuestTagInfo` (the global) is missing; `C_QuestLog.GetQuestTagInfo` returned nothing for a normal quest.
- Rewards: `GetQuestLogRewardMoney(id)`, `GetQuestLogRewardXP(id)` and `GetNumQuestLogChoices(id)` work. `GetQuestLogItemLink("choice", i)` is still to be checked on a quest that has choices. `C_QuestInfoSystem` has reward spells and currencies.
- Where: `C_QuestLog.GetQuestsOnMap(mapID)` gives **x, y for each quest of yours on that map** (objective areas), with `numObjectives` and `inProgress`. `C_QuestLog.GetDistanceSqToQuest(id)` works. `GetNextWaypoint` returned nothing (no cross-zone hints for this one).
- Waypoints: `C_Map.CanSetUserWaypointOnMap` is true; `SetUserWaypoint`, `GetUserWaypointHyperlink` and the full `C_SuperTrack` are there. So the **Go** button can set the game's own pin and arrow.
- Selection: `C_QuestLog.GetSelectedQuest()` follows the quest log.

**The game's windows:**
- The quest log is the **world map's quest panel**: `QuestMapFrame`, with its details in `QuestMapDetailsScrollFrame`. The global `QuestMapFrame_ShowQuestDetails` exists to hook. The old `QuestLogFrame` and `QuestLogDetailFrame` are gone. `QuestLogPopupDetailFrame` (the pop-out) is there.
- The NPC's quest window is `QuestFrame`, with `QuestInfoDescriptionText`, `QuestInfoObjectivesText` and `QuestInfoRewardsFrame`, plus the `GetQuestText`/`GetObjectiveText`/`GetQuestItemLink` family. **DialogueUI is installed and replaces this window**, so the mark goes on the quest log first, and on the NPC window only when it's the game's own.
- **`PlayerSpellsFrame` is protected.** It holds the talents and the spellbook in one window (`Blizzard_PlayerSpells`). Spellmind marks there are parented to `UIParent` and only anchored to it, never its children, and are never shown or moved in combat.
- Load on demand, so hook them when their addon loads (`ADDON_LOADED`): the trainer (`Blizzard_TrainerUI`) and professions (`Blizzard_Professions`).
- The character frame, its slot buttons, the bags, the merchant and the loot roll frames are there as before.

**Tooltips and links:**
- `TooltipDataProcessor.AddTooltipPostCall` is there, and `Enum.TooltipDataType` has `Item`, `Spell`, `Quest`, `Unit` and others. `OnTooltipSetItem` is **gone**, so the tooltip line uses `TooltipDataProcessor`.
- `C_TooltipInfo` has `GetTrainerService`, `GetQuestLogItem` and `GetTalent`. `ChatEdit_InsertLink` and `HandleModifiedItemClick` are there for links.

**Other addons loaded** (by name), which shape what Spellmind adds:
- **Questie** (+ QuestieDB): it draws quest givers and objectives on the map and in tooltips. Spellmind doesn't redraw any of that.
- **Pawn**: it puts upgrade arrows and scale values in tooltips, and has a large global API (`PawnGetItemValue`, `PawnIsItemAnUpgrade` and similar, still to read). Spellmind's tooltip line stays one line, below Pawn's.
- **WhatsTraining**: it lists what to train at the trainer. Spellmind's trainer help explains and prioritises instead of listing again.
- Also: DialogueUI (quest dialogs), Baganator and Syndicator (bags), Auctionator, ForeverLevelingBiS, ForeverMouseTooltip, ForeverRecipeBook, Leatrix Plus and Maps, MoveAny, NeedRoll, GTFO, Spy and Spoken.
- An open question: Questie's database knows where quest givers and objectives are, even for quests that aren't on the current map. Spellmind may only use another addon's data through a public API or data it deliberately exposes, so check whether Questie offers one before using it.

**Not available:** the combat log (§3.8), and `GetQuestGreenRange`.

### 5.1 Still to research

- Quest POIs and waypoints: `C_QuestLog.GetQuestsOnMap`, `GetNextWaypoint`, `C_Map.SetUserWaypoint`, `C_SuperTrack.*`.
- Quest difficulty, trivial and tags: `GetQuestDifficultyLevel`, `IsQuestTrivial`, `GetQuestTagInfo`.
- Quest reward items: `GetNumQuestChoices`, `GetQuestItemLink`.
- Talent tree, all nodes.
- Recipes: `C_TradeSkillUI`.
- Instances: `GetInstanceInfo`.
- Combat log access and Midnight's restrictions on Forever.
- Pawn's API and license.
- Hooking item links into our input box (`ChatEdit_InsertLink`) and tooltips (`TooltipDataProcessor`).
- The game windows of §2.1 on Forever: the names of the frames and their details panes (`QuestFrame`, `QuestMapFrame` and its details, `CharacterFrame`, `PlayerSpellsFrame` or `ClassTalentFrame`, the spellbook, `ClassTrainerFrame`, `MerchantFrame`, `GroupLootFrame`, the professions frame), and which of them are secure. Also the quest text: `GetQuestText`, `C_QuestLog.GetQuestDescription` or how the details pane gets it.
- How Questie, Pawn and the installed bag addons decorate the same frames, so Spellmind's marks don't collide.

## 6. Build order (decided 2026-11-10)

1. **Surfaces first:**
   - the Spellmind mark, the hover tooltip and the answer card (§2.1), with the first two integrations: **quest details: Break it down**, and the **item tooltip line**;
   - the Advisor panel shell with its tabs;
   - nudges;
   - the minimap button;
   - the chat window redesign, with the thinking dropdown and the web search toggle (§3.10);
   - item and quest links into the chat box;
   - chips;
   - Codex art.

   Everything after plugs into these.
2. **Quest help** (3.1): the core first; routing only if we decide we want it.
3. **Gear advisor** (3.2), with the tooltip line and quest rewards.
4. **Talents and spells** (3.3, 3.4): nudges, plan, rotation.
5. **Bags and gold** (3.6).
6. **Professions** (3.5).
7. **Dungeon prep** (3.7).
8. **Combat review** (3.8), if the combat APIs allow it.

Milestone 3, the desktop app, can go in parallel at any point. It's independent of the in-game features.
