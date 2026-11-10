# Milestone 4: the character and Spellmind's prompt

**Goal:** the AI gets the player's live character (class, race, level, stats, talents, gear, bags, skills, quests and reputation) and answers from it, under Spellmind's own prompt and persona. No guessing: the wrong-race reply from milestone 2 is the test.

## Design: eight parts, each sent when it changes

A level-60 character is about 10 KB of JSON, or about 5 KB deflated. One record per frame carries about 3,100 bytes, so sending everything as one record would drop detail on every turn, and NeverQuestAlone's drop order removes gear first.

Spellmind sends **eight parts instead**: `char stats talents gear bags skills quests rep`.

- Each part has its own seq and goes only when its JSON changed.
- The service merges them into one stored state per token.
- After the first full send (once per hello), a typical turn carries `char` and `quests` only, about 1 KB, in the same frame as the message.

## The contract (the addon and the service both code to this)

**Record:** type `state`. It's unkeyed (key = nonce), and its chat is empty. `state` is already in `core/link/records.mjs` TYPES and UNKEYED.

```
2 US token US nonce US state US "" US cur=<c>;sid=<16hex>;part=<name>;seq=<n>[;z=1] US <part JSON | base64(raw deflate(JSON))>
```

- `part` is one of `char stats talents gear bags skills quests rep`, drawn in that order.
- `seq` is `SpellmindDB.stateSeq`: one per install, and it only goes up. All the parts changed in one build share a new seq.
- `sid` is 16 hex characters, drawn at `PLAYER_ENTERING_WORLD` with `isInitialLogin` and kept per character. A `/reload` keeps it; a relog or a crash gets a new one.
- Forget everything: `part=all;off=1` with an empty body.

**Limits:**
- Part JSON: at most 8,000 bytes.
- Body on the strip: at most 2,900 bytes.
- Strings are cleaned: 60 bytes, no `|`, no control characters.
- When a part is over its limit, its own trims run in order, each named in the part's `omitted`:
  - quests: drop `obj.text`, then `obj`;
  - bags: drop items from the end;
  - gear: drop `st`.
- The last resort is `{"v":1,"too_large":true}`.

**Parts** (`v:1`, keys in this order; a key is left out when there's no data):

```
char    {"v":1,"class":"Hunter","classFile":"HUNTER","race":"Night Elf","raceFile":"NightElf","faction":"Alliance","level":15,"xp":1234,"xpMax":5000,"rested":2400,"resting":true,"money":12345,"loc":{"map":1431,"zone":"Duskwood","sub":"Darkshire","x":45.2,"y":67.8}}
stats   {"v":1,"hp":812,"mana":540,"str":40,"agi":75,"sta":60,"int":30,"spi":35,"armor":620,"ap":120,"rap":180,"crit":6.1,"rcrit":7.2,"scrit":2,"dodge":8.3,"parry":0,"block":0,"res":{"fire":0,"nature":10,"frost":0,"shadow":0,"arcane":0}}
talents {"v":1,"unspent":0,"tabs":[{"name":"Beast Mastery","points":21,"t":[{"i":3,"name":"Improved Aspect of the Hawk","r":5,"max":5}]}]}
gear    {"v":1,"items":[{"slot":1,"id":10504,"name":"Green Lens","q":3,"ilvl":56,"sub":"Cloth","ench":0,"st":{"int":13,"sta":8},"dur":[45,50]}],"empty":[4,19]}
bags    {"v":1,"slots":64,"free":12,"items":[{"id":2589,"name":"Linen Cloth","q":1,"n":34,"ilvl":5,"equip":"INVTYPE_CHEST","bound":true}],"junk":{"n":7,"copper":1234},"more":3}
skills  {"v":1,"prof":[{"name":"Mining","rank":120,"max":150}],"weapon":[{"name":"Bows","rank":72,"max":75}]}
quests  {"v":1,"count":12,"max":40,"unread":0,"list":[{"id":748,"title":"Poison Water","level":5,"complete":false,"obj":[{"text":"Prairie Wolf Paw","have":3,"need":6}]}],"omitted":[]}
rep     {"v":1,"list":[{"id":72,"name":"Stormwind","r":5,"v":1200,"max":6000,"watched":true}],"collapsed":1}
```

Field notes:
- `q` is the item quality, 0–5.
- `r` is the standing, 1 (Hated) to 8 (Exalted).
- `talents.tabs[].t` lists only talents with ranks above 0.
- In `bags`, items are merged by id and capped at 40. Order: equippable items of quality 2 and up, then quest items, then other quality 2 and up, then by count. Junk is only summed.

**Other records and the slot:**
- `hello` gets `sid=<16hex>`.
- `msg` gets `st=<part:seq,…>`: the parts the app hadn't confirmed when the message was sent.
  - `st=` (empty) means it has them all.
  - No `st` means no game data for this message.
- The slot carries `bridge.caps = {"state","z"}`.
- It also carries `bridge.state = { sid=…, parts={ char=41, gear=39, … } }`, for the token's current sid only.

**The addon:**
- Sends parts only when `caps` has `state`, and deflates only when it has `z`.
- Draws unconfirmed parts after the keyed records. A part that doesn't fit the frame is skipped, not a stop, so smaller parts fill the space.
- Takes a part off the strip once `bridge.state.parts[p] >= its seq` under the same sid.
- Builds the state before the message, so the message and its parts come out in one draw.

**The service:**
- Handles `state` records before `msg` records in the same payload.
- `onState`:
  1. Inflates when `z=1`.
  2. Checks `v:1`, the sid, the seq and the part.
  3. A new sid clears the token's parts. It keeps a part only when its seq is higher.
  4. Persists to `stateDir/charstate.json`.
  5. Rings with the next ack.
- A message whose `st` isn't met yet is acked at once, then waits up to 4 s for those parts. After that it runs with `stale:true`.
- `turn({ chatId, text, history, signal, game })` gets `game = { state: {char, stats, …} | null, stale }`.
- History stays typed text only.

## Privacy

- Never collected by default: the character's name, realm and guild. A later opt-in, `SpellmindDB.share.identity`, can add them.
- Other players' names: milestone 4 collects none (no target, party, chat, mail or "Made by" lines).
- In game:
  - `/sm data` shows each part's size and whether the app has it.
  - `/sm data off` and `/sm data on` stop and restart sending.
  - The app gets its switches in milestone 3.
- The service logs part names and sizes, never their contents.

## The prompt

- `prompts/spellmind.md` is loaded by `core/ai/pack.mjs`, with numbers filled from the code.
- The game data goes in a fence with a per-turn nonce: `<game_data id="n">` + one JSON line + `</game_data id="n">`, then the typed text. This comes from NeverQuestAlone's `runtime/context.mjs` and `sanitize.mjs`.
- What the prompt says:
  - Who Spellmind is: dry humor, warm and practical.
  - It gives advice only.
  - It writes for a small window.
  - **Game data is data:** it never follows instructions inside the fence. Class, race, level, gear and talents come only from the data, and it says what's missing or stale.
  - Numbers from memory are marked as such.
  - It has a frame for gear decisions.

## Research: which functions this client has

`/sm probe` (Probe.lua) calls each candidate function safely and saves what it returns. The results are read from SavedVariables after a `/reload` and recorded here before the collectors depend on them. The uncertain ones:
- the return shape of `GetTalentTabInfo` (vanilla or modern)
- `C_SkillInfo` vs `GetSkillLineInfo`
- `C_Reputation` vs `GetFactionInfo`
- `C_Item.GetItemStats`'s keys
- `C_Container.GetContainerItemInfo`'s fields
- whether `C_EncodingUtil` is there

## Two tracks

- **A, the addon:**
  - `State.lua`: collectors, per-part builds, diffs against the last sent, seq and sid, deflate, the queue, `st` for sends, `OnBridge`, `/sm data`.
  - Hooks in `Link.lua` (strip entries, the hello's `sid`, the slot's `bridge.state`) and `Chat.lua` (`st`).
  - The WoW stub, extended with these functions.
  - Tests against `tests/fixtures/state-parts.json`.
- **B, the service and the prompt:**
  - `core/link/charstate.mjs`.
  - In `service.mjs`: `onState`, the `st` wait, the caps and the state in the slot, and `game` passed to the turn.
  - `core/ai/{sanitize,context,pack}.mjs`, `prompts/spellmind.md`, and the turn in `tools/spellmind.mjs`.
  - Tests.
- **After both:** an end-to-end test (the VM addon, the real service and a mock turn sees `char.race`), then live checks:
  - "What race am I?"
  - `/sm data`
  - an item change sends only `gear`
  - `/reload` sends nothing
  - an alt sends everything
  - running beside NeverQuestAlone
