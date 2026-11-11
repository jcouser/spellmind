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
