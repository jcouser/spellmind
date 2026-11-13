# Milestone 18: the AI sees what the tabs show

Seen in game, 2026-11-12: the Dungeons tab listed "Testing the Wells" with its giver, yet the AI said it couldn't confirm the giver. It also said "you're missing The Defias Brotherhood" without saying where to get it. The AI had the raw game data, but not what Spellmind's tabs work out from it.

| Piece | File | What it does |
|---|---|---|
| The `advisor` part | `Advisor.lua`, `State.lua`, `charstate.mjs` | A compact copy of the tabs' conclusions. **dungeons**: the one you're in, then the log's, then the ones at your level, 4 at most, each with its range, quests in the log, done, to pick up and total, and up to 5 quests to pick up with their giver and place, what they wait on (and whether that's in your log), the first step of a chain, or the level they open at. **upgrades**: within reach, by slot, from the bags or a quest. **professions**: the next rank (train now, or at what skill and level) and up to 3 skill-ups with how many the bags make. **gold**: this session's net and rate, today's net, and the known costs coming up. Trims drop the pickups, then the skill-ups, then the upgrades. It's optional (`OPTIONAL_PARTS`) and has a Settings switch ("What the tabs work out"). |
| The prompt | `prompts/spellmind.md` | Describes the part. The AI answers from it and names it as the player sees it ("your Dungeons tab lists …"), trusting its quest lists over memory. |

The dungeon quest lists still need the QuestieDB addon. Without it, the part carries only the log's own dungeon quests, as the tab does.

## Fix: arriving in time (2026-11-12)

Seen in game: the first question after the change answered with stale data, without the Dungeons tab's quests. The app's log showed the advisor part arriving 0.6 s after the turn had stopped waiting (8 s). It had been built and sent again and again, because its gold per-hour rate changed every second. The rate is gone from the part (the Gold tab still shows it), a test holds the part still as time passes, and the app now waits up to 12 s (STATE_WAIT_MS) for the parts a question names, since there are twelve of them.
