# Milestone 12: the Settings tab

Every switch is in one place now: the last tab in the Spellmind window's rail (the gear icon), or `/sm settings`. Each setting stays where its slash command keeps it, so the tab and `/sm marks off`, `/sm nudges off`, `/sm data off` and `/sm minimap off` always agree.

| Section | Switches | Stored in |
|---|---|---|
| On the game's windows | Quest log: Break it down, Item tooltips, Quest rewards: the pick, Character sheet: the dots, Merchant: what to sell, Class trainer: what to train | `SpellmindDB.marks[key]` (the keys `Marks.On` reads). After `/sm marks off` (`all = false`), turning one on leaves the others off: each gets its own switch. |
| Nudges | Nudges by the minimap (the main switch), then each kind: talent points, spells to train, gear about to break, bags nearly full, quests ready to turn in, a turn-in nearby, professions near their cap. **Reset** shows dismissed ones again. | `SpellmindDB.nudges.off` and `.kinds[kind] = false`. Turning a kind off drops its waiting ones (`turnin:297` is a turnin), and it isn't detected until it's on again. |
| Game data the AI gets | Game data (the main switch, as `/sm data off`), then each part: stats, talents, spells, gear, bags, skills, quests, reputations. **Show** lists what the app has (as `/sm data`). | `SpellmindDB.share.state` and `.share.parts[part] = false`. A part kept back goes as `{"v":1,"off":true}`, so the app forgets what it had. The service says "the player keeps this back" in the turn's notes, and the prompt says not to guess it. `char` (class, level, zone) and `focus` (only what the player clicked) have no switch. |
| Chat and the minimap | Answers in the game's chat: **Whole** (a short answer in full, a long one's summary), **First line** (the summary or first line only) or **Off** (only in the window). The minimap button. | `SpellmindDB.ui.chatLines` and `SpellmindDB.minimap.hide`. |

A setting under a main switch that's off is greyed. Clicking a button flips it and redraws in place, keeping the scroll.
