# Spellmind: AI Companion — Design Notes

*Status: idea capture, 2026-11-09; named 2026-11-10.*

## Summary

**Spellmind** (in game and on listings, "Spellmind: AI Companion") is a general-purpose AI assistant for World of Warcraft: Forever. Where NeverQuestAlone answers "where do I go next?", this answers everything else: gear, talents, professions, gold, dungeons, class play, and open questions — using the player's live character state and a local game-data knowledge base so answers are specific and correct.

## Goals

- Advice grounded in *this* character: class, spec, level, gear, talents, bags, professions, reputation.
- Accurate game facts. The AI looks things up instead of recalling vanilla-era stats from memory.
- Always-available chat in game, plus proactive nudges at the right moments.
- Run on the AI the player already pays for: ChatGPT subscription sign-in, BYOK API keys, or a local model.

## Non-goals

- Automation of any kind. No movement, casting, targeting, clicking or key presses. Advice and on-screen drawing only (Blizzard add-on policy, protected functions).
- Real-time combat coaching. Round-trip latency is seconds; advice happens between fights.
- Being a quest router. NeverQuestAlone does that well; interoperate instead of duplicating.
- Being a gear scorer. Stat-weight and BiS addons (for example, the "Forever Leveling BiS" style tooltip: per-spec upgrade %, "% of best", slot rank) already answer "is this better?" instantly, offline and for free. Read their numbers; don't recompute them.

## Features

**MVP**

1. Free-form chat with full character state attached.
2. "Should I…?" gear decisions: keep, equip, vendor, sell at auction or disenchant, and which quest reward to pick. Judged in context (upcoming quest rewards and drops, Bind on Equip value, bag space, the next levels) on top of the installed scorer's numbers. With no scorer installed, it explains the item without a score of its own.
3. Talent planner: a build plan per level, with a nudge when a point is available.
4. Every AI NeverQuestAlone offers, from day one (inherited from the fork):
   - API key: Claude, ChatGPT, Grok, Gemini.
   - ChatGPT plan sign-in.
   - Other: any OpenAI-compatible service (OpenRouter, Groq, Together), or a local or home-network model (Ollama, LM Studio).

**Next**

- Profession planner: cheapest leveling path from bags and bank, with a shopping list.
- Gold and inventory advice: vendor, keep, sell or disenchant.
- Dungeon prep on entering an instance: boss tips by role, quests to grab first, loot worth hoping for.
- Post-fight review from the combat log (for example, "you clipped Auto Shot 14 times").
- Nudges: bags nearly full, repair, new spells to train, rested XP.

**Later / ideas**

- Gear plan across slots: the weakest slots, and the nearest upgrades within a few levels (quests, drops, crafted, auction).
- Goal planner ("get me ready for Molten Core") broken into a tracked checklist.
- Reputation and attunement tracker.
- "Explain this" for any tooltip or mechanic.
- New-character planner: race, class and profession combinations.
- Session recap and a long-term character journal.
- Macro and addon snippet writer (NeverQuestAlone's companion already does this).

## Architecture

```
 WoW client (addon, Lua)                       Desktop app (Node/Electron)
 ┌──────────────────────────┐   pixel strip   ┌──────────────────────────────┐
 │ State collectors          │ ──────────────▶ │ Capture helper → bridge       │
 │ (gear, talents, bags,     │   (screen read) │                               │
 │  rep, combat log summary) │                 │ Orchestrator                  │
 │ Chat UI, tooltip hooks,   │ ◀────────────── │  ├─ prompt + state packer     │
 │ nudges, map pins          │  slot addons +  │  ├─ tools (read-only):        │
 └──────────────────────────┘  sound doorbell  │  │   item / talent / recipe / │
                                                │  │   drop-source lookup       │
                                                │  ├─ reply validator           │
                                                │  └─ provider layer            │
                                                │      (ChatGPT sign-in, BYOK,  │
                                                │       local OpenAI-compatible)│
                                                │ Local game-data DB (SQLite)   │
                                                └──────────────────────────────┘
```

- **Transport: reuse NeverQuestAlone's (MIT).** Game → app: the addon draws a colored strip that a capture helper reads. App → game: replies go into pre-installed "slot" addons, and a sound-file change rings the doorbell. Keep its attribution in NOTICE and CREDITS.
- **Tools are the key difference.** NeverQuestAlone deliberately gives the AI no tools. Here the AI gets read-only lookups over a local database, so item stats, talent ranks and recipes come from data, not memory. Still no tools that act on the game or the computer.
- **State budget.** State goes with every turn, so keep it compact and shed detail in a fixed priority order when it's too big (NeverQuestAlone's `DROP_ORDER` pattern). Send full detail only for what the question needs.
- **Provider layer.** OpenAI Responses API to `chatgpt.com/backend-api/codex` with ChatGPT OAuth: PKCE, a loopback callback, refresh-token rotation, and only the refresh token stored in the OS keychain. Plus Anthropic, OpenAI, Gemini, xAI with API keys, and any OpenAI-compatible base URL. Built first as a NeverQuestAlone PR, then shared.

## Game ↔ app link (researched 2026-11-10)

An addon has no network, no file I/O and no clipboard. These are the ways data can cross:

| Direction | Method | Latency | Used by | Standing |
|---|---|---|---|---|
| Game → app | **Screen strip**: the addon draws coded pixels, a helper reads that region | ~0.25–1 s, mid-session | NeverQuestAlone; experiments (decktation's "pixel companion" proposal) | Gray: see below |
| Game → app | **SavedVariables** file, read by the app | Only on `/reload`, logout or exit | TSM, Raider.IO, WeakAuras Companion, GSE | Long tolerated |
| App → game | **Load-on-demand slot addons**: the app fills pre-registered addon files, the addon `LoadAddOn`s the next one; a sound-file "doorbell" says when | Seconds, no reload | NeverQuestAlone | Uses only the addon API |
| App → game | **Data file + `/reload`** | A reload per update | TSM AppHelper, WeakAuras Companion, GSE | Long tolerated |
| Rejected | Chat or addon channels to an outside account, screenshots, memory reading, network | — | — | `SendChatMessage` needs a hardware event and posts to chat; memory reading is banned; there is no network |

**Standing of the screen strip:**
- The EULA bars unauthorized software that "intercepts, collects, reads, or 'mines' information generated or stored by the Platform", and anything "not expressly authorized" that "changes and/or facilitates the gameplay or other functionality". That wording is broad enough to cover a screen reader.
- Blizzard's August 2025 notice ("Prohibitions on Third-party Software", Kaivax) frames enforcement around modifying the client, bypassing security and controlling the game.
- The same pixel technique powers rotation bots, which also send keys. Coverage of the January 2026 crackdown places the violation in the external program that reads and acts.
- We found no Blizzard statement on a reader that only reads and never sends input.
- So this is a real but unquantified risk, and NeverQuestAlone carries it today.

**Plan:**
- Reuse NeverQuestAlone's link, which already has both modes: the screen strip, and a reload-only mode (`/nqa reading off`) that uses only SavedVariables and slot addons.
- **Decision (2026-11-10): live mode by default.** Reload-only play is too painful to be used. Keep reload mode as a documented fallback (a privacy switch, and when the helper can't run), and copy-and-paste as the no-app option.
- State the screen-reading standing plainly in the README and privacy page, as NeverQuestAlone's How it works does.
- Give Spellmind its own strip spot and marker, so it can run beside NeverQuestAlone.

## Data sources

Rule: each feature's data is researched when that feature is built (what the client exposes, what's licensed, what other addons deliberately share), and recorded here before code depends on it.

| Source | Use | Note |
|---|---|---|
| In-game API (`C_Item`, tooltips, talent and skill functions) | Character state; item facts the client knows | Safest. Always matches this client |
| Item and tooltip cache harvested in game | Seed the local DB over time | Coverage grows with play |
| Community or emulator databases | Drops, recipes, quest data | Check licenses: many are GPL, which constrains ours |
| Installed gear scorers (BiS and stat-weight addons) | Per-spec upgrade %, % of best, slot rank, attached to each item in the state | Only through a public API or data the addon deliberately exposes; never tooltip scraping or copied files. Optional: never required |
| Model knowledge | General strategy and explanations | Never trusted for exact numbers |

## Risks

- **Accuracy.** Wrong stats or drop sources cost the player time. Mitigate with tools plus citing the data source in replies.
- **Policy.** Stay strictly advisory. Re-check Blizzard's add-on policy as features grow.
- **Subscription terms.** ChatGPT sign-in relies on OpenAI's support for third-party use and the Codex public client ID, which could change. Keep BYOK as the fallback. Claude stays API-key only (Anthropic disallows subscription OAuth in third-party apps).
- **Client churn.** Forever is in beta: APIs move, and SavedVariables sometimes get wiped. Keep nothing irreplaceable in game.
- **Cost and limits.** Large state plus tool calls burn tokens and plan quota. Use caching, compact state and per-feature budgets.

## Open questions

- Fork NeverQuestAlone's transport, or depend on it as a shared library? Can both addons coexist?
  - Leaning fork. NeverQuestAlone supports forks that rename the app: `plugins/<name>/identity.json` sets the app id, product name, keychain service and installer GUID. The name NeverQuestAlone and its artwork aren't MIT, so a fork needs its own name and icons. Starting there inherits the transport, the provider layer and the ChatGPT plan sign-in (PR #2) as-is. Coexistence still needs checking: separate slot addons, strip region and keychain service.
- Which data sources are licensable for the item, recipe and drop database?
- Name: **Spellmind** (decided 2026-11-10).
  - Slash commands: `/spellmind` and `/sm` (decided 2026-11-10). Neither clashes with the 241 addon folders installed on the dev machine. Check the popular Forever addons before release.
  - Name check (2026-11-10): no WoW addon, and only one empty GitHub repo (the `spellmind` handle is free). Two unrelated match-3 puzzle games use it (Dekovir on iOS and Android, DPGames in the browser).
  - Always use the full title, "Spellmind: AI Companion". Search the USPTO and EUIPO trademark databases before any public release.
- Persona and voice: open.
- License: MIT for Spellmind's own code (decided 2026-11-10). Copied parts keep their MIT notice in NOTICE.md. The name and art are kept out of the license.
- Should talent and gear plans be stored per character in the app (survives SavedVariables wipes)?
- Which gear scorers do Forever players actually run, and do any have a public API (vs. reading tooltip lines, which breaks when they change their wording)?
  - Forever Leveling BiS (CurseForge 1719370, by Thunder / Timearc, v1.2.0 of 2026-11-09, about 95K downloads), checked 2026-11-09:
    - No public API: its scoring (`ns.ScoreItem`, `ns.PctWeights`, `ns.SlotPick`) lives on the addon's private table. The only globals are `ForeverLevelingBiSDB` (settings and per-character data, no scores) and `ForeverLevelingBiS_OnAddonCompartmentClick`.
    - License: All Rights Reserved ("may not be copied, modified, redistributed or republished … without the author's written permission"). Earlier versions were MIT; don't fork them.
    - Its tooltip section is part `AddLine` text and part custom frames (the score box). Reading it is possible but brittle, and it ships zhCN, zhTW, deDE and koKR.
    - Its data (`Data\Items.lua`, `Quests.lua`, `ModelWeights.lua`) is on the same private table, so it can't be read at runtime, and its license rules out copying it.
    - Decision (2026-11-10): not used. Rule: use another addon's scores only through a public API or data it deliberately exposes; never scrape tooltips or copy files. Decisions work without a score.
- Item data source: Forever Leveling BiS credits "Wowhead's WoW: Forever database". Wowhead's terms restrict scraping, so our DB should come from the in-game API and item cache, or from licensed data.

## Prior art

- NeverQuestAlone (MIT): transport, provider layer, privacy defaults, state packing. https://github.com/tommygeoco/neverquestalone
- OpenClaw: ChatGPT/Codex subscription sign-in in a third-party tool.
