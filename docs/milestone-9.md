# Milestone 9: the gear advisor

This covers features.md §3.2, with the player's addition: not just best in slot (Forever Leveling BiS shows that), but **your next upgrade and how to get it**.

| Piece | File | What it does |
|---|---|---|
| Weak slots | `Gear.lua` (WeakSlots) | Empty slots first, then gear 5 or more item levels below the character's level, then common or poor quality. The shirt and tabard don't count. |
| Upgrades within reach | `Gear.lua` (Candidates, Upgrade) | Wearables in the bags, and the rewards of quests in the log. Each must be usable (no requirement in red in the game's own tooltip data) and clearly ahead of what's worn in that slot. |
| Quest rewards, cached | `Gear.lua` | A quest's reward choices can only be read while it's the selected quest, or while its NPC window is open. So they're kept as the player sees them (`SpellmindDB.rewards[id]`): from the details hook, `QUEST_DETAIL` and `QUEST_COMPLETE`. They're dropped when the quest leaves the log. |
| The Gear tab | `Panel.lua` | **Next upgrades** comes first. Each upgrade within reach has its slot, where it's from (bags, or "Reward of …") with a Go button for a quest, an "upgrade" tag and its differences. Then up to 5 weak slots with nothing within reach. **Find my next upgrades** asks the AI (see below). |
| The reward pick | `GearUI.lua` | Turning in a quest with a choice opens a small "Spellmind picks: …" box beside the quest's window (or at the top, when DialogueUI replaces it), saying why. **Why?** asks the AI with every choice named. The box closes with the window. |
| The character sheet | `GearUI.lua` | A dot on each gear slot that needs attention: green when an upgrade is waiting, orange below 50% durability, red below 25%. The slot's tooltip says which and from where. |
| The merchant | `GearUI.lua` | A "Spellmind: what to sell" button beside the merchant's window. Its card lists grey junk, and bound gear that can't be used or is worse than what's worn, with values and a total. Nothing is sold. |

## Find my next upgrades

The question names the weakest slots ("starting with my weakest slots: Head (empty); Legs (item level 10, 5 below your level); …"). The prompt asks for:
- one realistic item a slot, usable by the class, at or near the character's level;
- exactly how to get it: the quest, the dungeon and boss, the vendor, a recipe from the character's professions, or the auction house;
- a web search with sources cited;
- no far-off best-in-slot items, since BiS shows those.

## How "better" is judged

There's no invented score. Each class has a rough order of its main stats (`Gear.MAIN`), used only to compare two items for the same slot. An item is an upgrade when:
- the slot is empty, or
- it has clearly more of those stats, or as many with 3 or more higher item level.

The reward pick is labelled "likely", and the AI can say why or why not.

## Still to come

- Dungeon loot, if the Dungeon Journal is on Forever (probe round 5).
- Off-hand rules for classes that can't dual wield. One-handers are compared with the main hand only.
