# Milestone 5: Spellmind in the game's own windows (step 1)

The first of features.md §6's build steps: the shared pieces of §2.1, with the two first integrations.

| Piece | File | What it does |
|---|---|---|
| The mark | `addon/Spellmind/Marks.lua` | A 20 px button with `Media\Mark`. Hover: local facts in the game tooltip. Click: Explain. Shift-click: the question in the chat box, to edit first. |
| The answer card | `Marks.lua` | `SpellmindCard`: beside the window it explains (anchored, parented to `UIParent`), movable, with the reply, **Ask more** and close. It closes with the mark's window. |
| Quest details | `addon/Spellmind/Quests.lua` | The mark at the top right of `QuestMapFrame.DetailsFrame`, shown by a hook on `QuestMapFrame_ShowQuestDetails(questID)`. Its click is **Break it down**. |
| The tooltip line | `addon/Spellmind/Tooltip.lua` | One line on item tooltips (`GameTooltip`, `ItemRefTooltip`) through `TooltipDataProcessor.AddTooltipPostCall`: can't use (a red requirement in the game's own tooltip data), fills an empty slot, or the stat differences against the worn item. |
| The focus part | `State.lua`, `core/link/charstate.mjs` | The tenth part. |
| about= | `Chat.lua`, `core/link/service.mjs`, `core/ai/context.mjs` | The message's link to the focus. |

`/sm marks off` and `/sm marks on` turn the marks and the tooltip line off and on (`SpellmindDB.marks.all`).

## The contract

### The focus part

`focus` is `{"v":1}` until the player clicks a mark. Then it's the thing clicked, built when it's clicked and kept until the next click (or a /reload). It goes like every part: only when its JSON changed, with its own seq, and plain JSON when deflating doesn't make it shorter.

For a quest (`kind` "quest"):

```json
{"v":1,"kind":"quest","id":297,"title":"Gathering Idols","level":18,"diff":"VeryDifficult","trivial":false,"elite":false,
 "complete":false,"text":"…","goal":"Bring 8 Carved Stone Idols to Prospector Ironband.",
 "obj":[{"text":"Carved Stone Idol","have":0,"need":8}],"money":650,"xp":1350,
 "choices":[{"id":7001,"name":"Ironband's Gloves","q":2,"n":1,"usable":true}],"items":[…],
 "where":{"zone":"Loch Modan","x":70.6,"y":25,"dist":560}}
```

- `level` is the quest's `difficultyLevel` (scaling quests), else its `level`. `diff` is the suffix of `GetQuestDifficultyColor(level).font`.
- `text` and `goal` come from `GetQuestLogQuestText(logIndex)`, cut to 1,200 and 400 bytes. They're the only strings past 60, and the sanitizer keeps those two lengths (`LONG_STRINGS`).
- `choices` are read only when the quest is the selected one, because `GetQuestLogChoiceInfo` reads the selection. `items` come from `GetQuestLogRewardInfo(i, id)`. Each list holds at most 6.
- `where` comes from `C_QuestLog.GetQuestsOnMap(map)`, the game's own marker on the player's map, and `dist` from `GetDistanceSqToQuest`, rounded to 10 yards. `where` is left out when the quest isn't on this map, but `dist` can stay.
- The trims, in order: `text` halves until 200 bytes and then goes, then `choices` and `items` go.

### about=

A message from an Explain click, or from the chat window after **Ask more**, carries `about=<kind>:<id>` (`quest:297`, matching `^(quest|item|spell|talent):\d{1,10}$`). Its text is fixed ("Break this quest down for me."), and the window shows "Break it down: <title>" instead.

The service passes about to the turn (`game.about`). `buildRequest` keeps `focus` in the game data block only when about names it (`kind:id`), and adds the note "Focus: the player clicked Spellmind's mark…". Otherwise it leaves focus out, so an old click can't steer a new question. An empty or missing focus is never reported as missing.

### The answer

The addon's pending send carries `card = true`. Its answer (reply, error or aborted) goes to the card while the card waits for that key. A card that has closed lets the answer go to the chat frame as usual. The window's history always keeps both the question and the answer. Closing the card ends the "About:" thread of Ask more.

## Rules kept

- Read only: no quest is selected, no window opened, no waypoint set. The hook is `hooksecurefunc`, and nothing here touches a protected frame.
- The quest text is game data: it's fenced, sanitized and described in the prompt as data, never instructions.
- The tooltip line states facts, never a score; Pawn's lines stay Pawn's. The red check reads only the game's own tooltip data for the item.

## Still to see live

- Where the mark sits in the real details pane, and whether it collides with the pane's own buttons or Questie's.
- Real reward choices: `GetQuestLogChoiceInfo` returns on Forever, checked on a quest that has choices.
- That the tooltip post-call fires on bags, the character frame and links, and that the red check sees the game's red text.
