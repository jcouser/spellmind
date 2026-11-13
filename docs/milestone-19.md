# Milestone 19: the review, batch 1

On 2026-11-12 three independent reviewers (Fable 5.2) went through the addon and app: one for features and UX, one for code robustness, and one for AI, privacy and security. Their findings were checked against the code, merged, and grouped. This batch fixes everything marked "fix before the desktop app". Batch 2 is the UX polish.

## Privacy and security
- **The name in quest text.** The game writes the character's name into quest text ("Greetings, <name>"), and Break it down sent it. `ns.Redact` (Core.lua) blanks it to "[you]" in a quest's text and objectives line. It's the only place in the addon that reads the name: never kept, stored or sent. The player chose this over dropping quest text. A test scans the addon to hold it, and features.md §1 rule 7 states it. Guild reputation (faction 1168, which carries the guild's name) is never read.
- **Guide import.**
  - Links are cleaned in the addon and the app: https only, no login ("user:pw@"), no local or bare-IP host, no fragment, and no query values whose names look like secrets.
  - No game data goes with an import.
  - A page's words that look like a link or a site are dropped.
  - A picked build name can't break out of its quotes.
  - The AI's own error text is replaced by a fixed line, since a page could steer it into a fake app message.
  - The prompt now says the guide describes a build and never instructs.
- **Forged records.** The app hears only a session that said hello (a hello is handled first in a frame), and at most 12 messages a minute. Every channel between the game and the app is readable Lua, so this narrows forgery but can't close it.

## Reliability
- **Caps match the app's.**
  - 5 objectives a quest in the log part (8 in focus).
  - At most 40 factions, the watched one first, with how many more.
  - 6 costs in the advisor part.

  A contract test builds the worst cases and runs them through the app's checker.
- **A refused part settles.** The slot confirms its seq, so the addon stops drawing it, and a question naming it doesn't wait for a part that will never come (`rejected` in charstate).
- **Parts arrive in time.** While a question waits for its parts, each part's arrival rings the slot at once, so the next frame is drawn without the 8 s wait. The world part no longer carries the player's spot, and lists its NPCs by name, so it doesn't change with every step.
- **Nothing lost or stuck.**
  - A reply is written before its message leaves the outbox.
  - The app logs unhandled promise rejections instead of dying.
  - A question the app took but never answered expires after 5 minutes with a line saying so.
  - The fast poll stops while the app is away.
- **Trainer.** A weapon master's or riding trainer's list no longer replaces the class trainer's: a kept list needs a ranked spell or a spellbook spell. TRAINER_UPDATE is coalesced.

## Performance
- **Builds only when asked.** Game data is built only when a question waits for it, not 2 s after every event. A part is fitted and deflated only when its JSON changed (compared in memory).
- **Nudges.**
  - No checks in combat; they run when the fight ends.
  - The 5 s look runs only for "turn-in nearby", only when it's on and a quest is ready, and only that kind's detector.
- **Upgrade answers are kept per item link.** They're dropped on gear, skill, level, spell or guide changes, and after 30 s. The cheap wearable check comes before the tooltip data.
- **Rewards.** A reward read reacts only to the items it was waiting on, not every item the client loads.
- **Dungeons.** The quest log is read once per frame, and a dungeon not found is tried again a minute later.

## Nudges
- **Resolved situations leave.** A situation that's resolved leaves the toast, the badge and the list, and its "seen" is forgotten, so it nudges again when it comes back (gear about to break, after a repair). "Turn-in nearby" keeps its own distance rule.
- **Changes update the nudge.** A situation that changed while waiting updates its nudge ("2 talent points" instead of 1).
- **Fights.** A toast that showed 5 s or more before a fight waits behind the badge afterwards, instead of returning after every kill.
- **Per character.** Dismissed situations are kept per character (`chars[key].nudgeSeen`), not account-wide.

## The AI
- **The double-check runs less often.** Its patterns are narrower, it ignores the "Next:" chips line, and everyday words ("is in", "find", "train") no longer trigger it.
- **A bad check doesn't win.** A check that comes back as a comment, under half the draft, or empty keeps the draft. One that lost the "Next:" line gets it back.
- **The check's own message.** It starts with `[Spellmind check]`, which players can't send, and says to keep claims the game data supports and to hedge, not delete, what the web can't confirm.
- **Prompt contradictions fixed.**
  - The AI can't act in the game, but it can search.
  - Chats are kept on the player's computer.
  - With `world` empty or off, search before naming an NPC.
  - Search and length budgets for briefings.
  - Headings in plain text.
  - The fit note's order.
- **Guide lines reach the AI whole.** Steps go up to 120 characters and weapon advice up to 200 (`NESTED_LONG`).

## The window
- A live redraw keeps the tab's scroll, clamped when the list got shorter. A tab switch starts at the top.

## Saved data
- At most 400 remembered NPCs (the most recently used), and none unused for 180 days.
- A character not logged in for a year has its Spellmind data dropped.
- `/sm probe`'s results are kept a week.
