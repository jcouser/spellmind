# Milestone 8: nudges

Nudges are small toasts by the minimap (`addon/Spellmind/Nudges.lua`), built from local facts only, with no AI and no cost until the player asks:

| Nudge | When | Ask sends |
|---|---|---|
| A talent point to spend | Unspent points (after a level, a respec) | What to take, and why |
| N spells to train | Spells the spellbook shows as coming, at or below the character's level | Which are worth it, roughly the cost, where the trainer is |
| Gear about to break | A worn item below 20% durability | Where the nearest repair is |
| Bags nearly full | 3 or fewer free slots (with the grey junk count) | What to sell, bank or destroy |
| Ready to turn in | A quest that becomes complete this session (not the ones already complete at login) | Where to turn it in, and what comes after |
| A profession near its cap | Within 5 of its rank's cap | Where to train the next rank, and what it needs |

- **The toast:**
  - It holds the nudge's icon, a title, one line, "+N more" when others wait, and **Dismiss**, **Ask** and close buttons.
  - Only one shows at a time, with 3 seconds before the next.
  - It's movable, and its place is saved.
- **Never in combat:** a toast showing when a fight starts hides, and the queue goes on when the fight ends.
- **Ask:** the question goes into the chat (shown as "Nudge: …"). Its answer opens in the card to the toast's left, because the minimap sits at the screen's right edge.
- **Once only:** a dismissed or asked nudge is kept as `SpellmindDB.nudges.seen[kind] = key`, where the key is its situation (for spells, the level and how many are due). It comes back only when that changes. Bags come back once they've been cleared (more than 6 free) and fill up again.
- **Fading:** a toast fades after 20 seconds (a mouse over it holds it) but isn't dismissed: it keeps waiting.
- **The dot:** the minimap button shows a gold dot while a nudge waits. Clicking the dot brings the toast back, and the button's tooltip lists what's waiting. A new situation shows the toast again on its own.
- **Checks:** game events (level, bags, durability, quest log, skills, spells, talents) are checked at most once every 2 seconds. The first look comes 8 seconds after login, once the game's data has settled.
- **Off switch:** `/sm nudges off` and `/sm nudges on`.

## Next

- Settings for each kind of nudge.
- A dungeon nudge ("Hall of Thanes is your level: you have its three quests"), with the dungeon prep feature.
