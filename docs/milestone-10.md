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
