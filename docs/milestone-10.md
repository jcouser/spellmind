# Milestone 10: the class trainer

On Forever the spellbook shows no spells to come (seen in game: `spells.next` was always empty), so the "spells to train" nudge never fired and the Spells tab had nothing to say. The class trainer's own window does know, so Spellmind reads it when it opens and keeps it.

| Piece | File | What it does |
|---|---|---|
| The read | `Trainer.lua` (Read) | On `TRAINER_SHOW` (and `TRAINER_UPDATE`, when the filter changes), every service via `GetNumTrainerServices` and `GetTrainerServiceInfo`: name, rank (from "Rank 2"), the trainer's own kind (available, unavailable, used), `GetTrainerServiceCost` and `GetTrainerServiceLevelReq`. Headers are left out, and a profession trainer's list (`IsTradeskillTrainer`) isn't kept. It goes in `SpellmindDB.chars[key].trainer = { at, services }`. Each call is guarded, and nothing is learned or changed. |
| The plan | `Trainer.lua` (Plan) | Worked out each time from the kept list, the character's level now and the spellbook. **Due** means at or below the level and not known at that rank. **Soon** is the next 8 above it, by level. A visit at 15 still says what's due at 16 once the character gets there. |
| The Spells tab | `Panel.lua` | **Train now: 9s**, each spell with its cost. A red line shows when the total is more than the gold carried. **Coming next** lists levels, and a grey line says how old the list is. Without a visit it says to open the class trainer once. |
| The nudge | `Nudges.lua` | "2 spells to train: Sprint (rank 1), Backstab (rank 2)". It uses the trainer's list when the spellbook names nothing coming. Ask asks which come first when gold is short, and where the nearest trainer is. |
| At the trainer | `Trainer.lua` (ShowButton) | A "Spellmind: what to train" button beside the trainer's window (Marks key `trainer`). Its card lists what can be learned now with costs, the total against the gold carried, and what's next. **Ask more** takes it to the chat. It closes with the window. |
| The AI | `State.lua`, `charstate.mjs`, the prompt | The spells part gains `trainer: { at, due: [{ name, rank, cost }], soon: [{ name, rank, level }] }`, 10 of each at most. It's the first thing dropped when the part is too big. The prompt says to trust it over memory, and that it can be a level or two old. |

## Notes

- **The trainer's filter:** the game lists only what its filter shows. With "available" alone ticked, Coming next is empty until the filter is widened. TRAINER_UPDATE reads it again.
- **Known spells** are matched by name and rank against the spellbook. A spell the trainer calls "used" counts as known too.
- **Still to verify in game:** the API names on Forever, a full restart (it's a new file), and the button's place beside the trainer's window.

## Fix: ranks on Forever (2026-11-12)

Seen in game: the trainer offered Eviscerate (Rank 3) and Gouge (Rank 2), but Spellmind's list left both out. The AI then kept saying Eviscerate 3 wasn't offered, until the player said what they were looking at. Forever's `GetTrainerServiceInfo` gave every service an empty rank, so "Eviscerate" with no rank looked like the Eviscerate 2 already known.
- The rank is now also read from the service's name ("(Rank 3)") and from the game's tooltip data for it (`C_TooltipInfo.GetTrainerService`).
- The trainer's own status comes first: only "used" is learned. A service is taken as learned since the visit only when the spellbook has that rank, or, with no rank read, when the spellbook's spell has no rank either.

Seen again (a player's friend, 2026-11-20): Mend Pet 3, trained, stayed "a spell to train". The kept lists (SpellmindDB) showed why: on Forever `GetTrainerServiceInfo`'s third value is the service's icon (a number), not the trainer's word, and no rank came back, so "used" was never seen and an unranked Mend Pet with Mend Pet 3 in the book read as not learned. The read now takes each value by what it is (`TR.ServiceInfo`: the word available, unavailable, used or header; a "Rank N"), and `SpellmindDB.trainerShape` records the types the game gave and where the word was, to confirm the order. A list kept by the old read (its word a number, no rank) counts a spell in the book as learned, so the nudge stops without another visit; the cost is that a new rank of a spell you have isn't flagged until the trainer is visited again.
