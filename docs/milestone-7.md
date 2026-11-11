# Milestone 7: the Advisor panel

The panel is built from mockup B of 2026-11-10 (side tabs). Its file is `addon/Spellmind/Panel.lua`. It opens from the minimap button's right-click or `/sm panel`, and it's movable; its place and last tab are saved in `SpellmindDB.panel`.

- **Header:** the owl, "Spellmind Advisor", and "Level 15 · Dwarf Rogue". The name, realm and guild are never shown or read.
- **Rail:** six tabs with the game's own icons: Quests, Gear, Talents, Spells, Professions, Gold.
- **Content:** each tab's rows, read locally from the game when the tab is shown. While the panel is open it redraws on the game's events (quest log, bags, equipment, level, money, skills), at most once a second.
- **Ask buttons:** two per tab. The question goes into the chat (shown as "Advisor: …"), and its answer goes to the card beside the panel. Ask more continues in the chat, and the card closes with the panel.

## The tabs

| Tab | Rows | Ask |
|---|---|---|
| Quests (done) | The sections below | Plan my next hour; What's worth skipping? |
| Gear (done) | The sections below | Any upgrades?; What should I sell? |
| Talents | Spent, and unspent to spend; each talent taken with its rank | Plan my next points; Is my build good? |
| Spells | The spells coming from the spellbook, with their level; "train now" when due | What do I train next?; My rotation |
| Professions | Each profession's rank and cap ("train the next rank" within 5 of it); weapon skills | Level my professions; Which suit me? |
| Gold | Money, the grey junk's value, bag space ("nearly full" at 4 or fewer free) | Make gold; Bag space |

**Quests:**
- The sections are "Ready to turn in", "Worth doing now", "Later" and "Grey: little XP left".
  - "Later" holds elite or group quests, and those coloured orange or red for the player's level.
  - "Grey" holds trivial ones.
- Each row shows the quest's level in its difficulty colour (with + for elite or group), the title, and a hint. The hint is "ready to turn in", "on your map · 340 yd", or "2 of 3 done".
- An Elite or Group tag sits on the right, next to the quest's Spellmind mark. The mark works as in the quest log: hover for facts, click to Break it down, and the card shows beside the panel.

**Gear:**
- Worn items in slot order, coloured by quality, with item level, dps and a durability tag (orange below 75%, red below 25%).
- "In your bags", with the free slot count, shows up to 8 items. A wearable item carries the tooltip line's verdict: a tag such as "needs Bows skill", or its stat differences. Anything else shows its vendor value, followed by the grey junk's total.
- "Empty slots" leaves out the shirt and tabard.

The tabs read the same builders as the state parts (`State.Collect`), so the panel and the AI see the same facts.

## Next

- Fill out the other four tabs:
  - Talents: the next point's options.
  - Spells: training cost and the trainer, once trainer data is in.
  - Professions: the next recipes.
  - Gold: auction prices, if an addon exposes them.
- Nudges, which come from the same facts.

## Quest help, finished (features.md §3.1, 2026-11-11)

**Sections**, re-read live on quest log, quest watch, level and zone changes:
- Ready to turn in (nearest first)
- Do now: <zone or dungeon>, by the quest log's own headers (as the log and Questie group them), the zone you're in first, then the nearest group; nearest first inside. A map marker isn't "here": dungeon quests have none outside.
- Group (elite or a suggested group)
- Later (orange or red, with "+N levels" when the game has no spot for it)
- Skip? Little XP left (grey)

**Each row** is two lines:
- **First line:** the level in its difficulty colour and the title. At the right: direction and distance ("NE · 560 yd", the direction from the player's map position, scaled by the map's world size), an Elite or Group tag, **Go**, and the quest's mark.
- **Second line:** what's left ("0/8 Carved Stone Idol", up to two objectives), or "Ready to turn in".

**Go** (Quests.Go) acts only on the player's click:
- With the quest's spot on this map, it sets the game's own map pin (`C_Map.SetUserWaypoint` with `UiMapPoint`) and super-tracks it, so the game's arrow points there.
- Otherwise it super-tracks the quest (`C_SuperTrack.SetSuperTrackedQuestID`).
- A line in the chat says which happened.

The "Next:" line and Plan my session stay optional (§3.1).

## XP and LFG (2026-11-11)

- **XP:** each quest row's second line shows its XP reward (`GetQuestLogRewardXP`). Under "Ready to turn in", a line says what turning them all in does: "takes you from 43% to 78% of level 15", or "gets you to level 16" (only this level's XP is known, so "or further" past that).
- **LFG**, on group, elite and dungeon quests that aren't done:
  - It builds a short line, as players write them: "LFG Hall of Thanes DPS Rogue". Any of a dungeon's quests gives the dungeon (its log header); a group quest gives its own title. A leading "The" goes, and the role comes from the talents part. There's no quest list or level: the player found that too long.
  - It opens the game's chat box with the message, prefixed with the LookingForGroup channel's number when the player is in it. The player edits it and presses Enter; Spellmind never sends it.
- **Where the LFG line goes** (2026-11-11): every click opens a menu: "Current chat channel" (no prefix, so the chat box's own sticky channel), the channels the player is in now (`GetChannelList`: "2. General - Ironforge", "3. Trade - City"), then Say, Party and Guild. A pick puts the line in the chat box at once; nothing is kept, so the next click asks again (the player preferred that). The chat box parses the "/3 " prefix when the player presses Enter.
