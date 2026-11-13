# Milestone 20: the review, batch 2 (UX polish)

The UX reviewer's findings (2026-11-12), checked against the code. Each is fixed below unless it's listed at the end.

## Rows and buttons (`Panel.lua` Draw)
- **Text rows wrap** to the window's width and are as tall as they need. Second lines wrap to two lines. Hints, empty states and Settings descriptions no longer end in "…".
- **Tags are coloured words, with no border.** A bordered "Dungeon" beside LFG and Go read as a button. Redundant ones are gone:
  - "Dungeon" under a Dungeon heading;
  - "upgrade" under Upgrades within reach;
  - "now" on a green row.
- **Row buttons:**
  - As wide as their words.
  - A gold border on hover.
  - A line of help on hover (`P.ACTION_TIPS`). Go "sets the game's map pin and arrow, nothing else"; LFG "writes a line in your chat box, you press Enter".
  - The ones that ask your AI (Brief, Import, Re-import) carry the owl's mark.
  - Settings switches say what a click does.

## Tabs
- **Gear:** no copy of the character sheet or the bags.
  - **Needs repair:** worn items under 75%, red under 25%.
  - **Worth a look in your bags:** only items with something to say: can't use it, safe to sell, a profession's. Grey junk is summed.
- **Professions:** the Weapon skills list is gone. A weapon you wear whose skill is 25 or more under its cap gets an orange line: "Swords 40/75. You'll miss often with it. Use it on easy mobs to raise it."
- **Spells:** **At your trainer now: 9s**. The spells your guide's priority names come first, in green, marked "in your guide". The rest are plain, not all "train now".
- **Talents:** the "8 spent" section shows only without a guide, since the guide row already says it.
- **Dungeons:** the heading reads "Dungeons you have quests for", and the empty state points to the Which dungeon now? button.
- **Nudges:** a nudge's detail is on its own line under its title.
- **LFG menu:** "Write your LFG line for:", with "You press Enter to send it." Nothing is posted.

## Chat and the window
- **A "Thinking…" bubble** ends the conversation while a question waits ("Waiting for the Spellmind app to start…" when it's away).
- **`/sm help`** lists the commands, and nothing goes to the AI. `/sm quests`, `/sm gear` and so on open that tab. A bare `/sm nudges` or `/sm marks` says how to use it.
- **Keyboard:** a minimap click opens the chat without taking the keyboard, so the movement keys keep working. `/sm` typed by hand still focuses the box.
- **Esc** closes the full window, not the compact one kept open while questing.
- **The window sits at MEDIUM strata** and comes to the front on a click. At DIALOG it covered the game's windows and Spellmind's own trainer button.
- **The answer card** opens on the left when there's no room on the right, instead of landing on the window.
- **The header:** the Thinking dropdown is as wide as its label, and the fold button is a drawn bar.

## Words and colours
- **Card titles** are the question itself, with no "Advisor:". `/sm data` uses the Settings names ("Bags: off in Settings").
- **The quest mark** is called "Break it down (asks your AI)" everywhere.
- **Settings:** "Answers in the game's chat" is Full answer, First line or Off.
- **Colours:**
  - **Green** means do it now, or have it.
  - **Orange** means not yet, behind, or too high: waiting on a quest, the "+3 levels" note, and weak slots.
  - **Red** means short, can't, or an error.
  - **Grey** is information.
- **Money** has no zero parts ("1g", not "1g 0s 0c").

## Nudges
- **Professions** follow the tab's rank rules. Near the cap it's "Leatherworking: Journeyman ready, train it at a Leatherworking trainer", or "Skinning stops at 150, until level 20". It never urges a rank the level doesn't allow.
- **Spells to train** is keyed on the level, so buying one of three spells doesn't nudge again.

## Not done (needs the player's say or a screenshot)
- **The Quests tab vs the Questie tracker.** The reviewer suggested a "Next up" section, and collapsing each dungeon to one row that points to the Dungeons tab. The player asked earlier for a dungeon's quests together in the Quests tab, so this waits for their call.
- **Splitting Gold's "Coming up" into guide spells and everything.**
- **Visual checks:** the window at its minimum size, compact mode, and first-run states.

## Fix: quest details (seen in game, 2026-11-13)

Asked how to turn in The Defias Brotherhood, the AI said Gryan Stoutmantle at Sentinel Hill, twice, until the player said the quest's text says Lakeshire. The quests part had no quest text, and a quest with no objectives ('talk to Wiley in Lakeshire') is complete from the start, so the AI took 'complete' to mean 'back to the giver'.

- **Each log quest carries its one-line goal** (the game's own words, the name blanked, 120 characters), and `turnIn`, who takes it, from QuestieDB when it's installed (`Dungeons.TurnIn`). Over the size limit, goals go after objective text and before objectives.
- **A quest named in a question** (by its title, a leading 'The' optional, 5 letters at least, the longest match) goes as `focus` with its full text, as a shift-clicked link does: `Chat.NamedFocus`, for the chat box and `/sm`.
- **The prompt:** who takes a quest is in its `goal` or `turnIn`, never assumed to be its giver, and a quest with no objectives is complete from the start.
