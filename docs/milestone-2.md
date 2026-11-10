# Milestone 2: the game ↔ app link

**Goal:** in game, `/sm <question>` (or a minimal chat window) brings back a reply from the player's AI, live through the screen strip, with a headless `node tools/spellmind.mjs start` and no app window yet. Windows 11 first; keep macOS possible.

The source is NeverQuestAlone (NQA, MIT) at `../NeverQuestAlone`. Each copied file gets a provenance header and a line in NOTICE.md.

## What comes from where

**Copied** into `core/link/` and trimmed:

| NQA file | Keep | Strip |
|---|---|---|
| `bridge/transport/records.mjs` | everything | `TYPES` cut to hello, msg, seen, stop; the deflate `z` body; `upd` |
| `bridge/transport/luaenc.mjs` | all | map lines |
| `bridge/transport/strip.mjs` | `LIVE`, `decodeAt`, `findAndDecode` (tests) | `SHOT` |
| `bridge/transport/fsretry.mjs` | all | none |
| `bridge/transport/slots.mjs` | `slotToc`, `installSlots`, `writeSlots`, names, placeholders | AddOns-list fold, slot window (later) |
| `bridge/transport/signals.mjs` | all | `act` bell, legacy cleanup |
| `bridge/transport/publisher.mjs` | write slots, then ring; push-counter rollback; `pushWithin` | worker, `heard`, `range`, map |
| `bridge/transport/capture.mjs` | line splitter, handler, launch limiter, retry, `createWindowsCapture` | macOS, X11 |
| `bridge/byok/wow.mjs` | flavors, `wowRunning`, `copyAddon`, a slim `installAddon` | `findWow`, patch day, permissions, uninstall |

**Rewritten** (about 650 lines, modeled on NQA `service.mjs` and `app/store.mjs`):
- Store: add record, push counter, 7-day dedupe, records-for-token with replay, report cursor, outbox.
- Service:
  - hello: nonce, then publish with push.
  - msg: refuse the `[Spellmind` prefix and key-shaped text; outbox, then ack.
  - Turns run through the run queue and `core/ai` `createProvider().stream`.
  - Also: seen, stop (abort), a slimmed `buildSlot`, re-ring, a beat every 10 s, `signals.ensure()` at start.
- Render: escape pipes, markdown to WoW text, first sentence, system lines.

**Capture helper:** NQA's `bridge/capture/windows/*`, renamed `spellmind-capture.*`, built with `build.sh --native` (MinGW gcc). One C change: a `--search-rows N` option in `parse_options` (main.c, after `wc_spec_default`). Optionally raise the candidate limit from 4 to 8.

**Addon** (`addon/Spellmind/`):
- `Codec.lua`: copied, with its magic and global changed.
- `Core.lua`: about 200 lines from `Store.lua`'s helpers.
- `Link.lua`: about 600 lines, rewritten from `Transport.lua`: records and outbox, strip drawing, bells, hello/seen, slot loading, tick.
- `Chat.lua`: about 150 lines: `/sm`, `/spellmind`, send, and replies printed into a window.

## Coexistence with NQA (both installed and running)

| What | NQA | Spellmind |
|---|---|---|
| Strip magic | `C7 2C` | `53 4D` ("SM"); first cells 2,4,6,4,6 |
| Strip position | top-left (0, 0), 800×192 px plus label | (0, −272) in strip units (physical px) |
| Helper args | `--magic C72C` | `--magic 534D --height 640 --search-rows 600` |
| Slot addons | `NQA_S001…S200` | `Spellmind_S001…S200` |
| Slot global | `NQA_SlotData` | `SpellmindSlotData` |
| Doorbells | `NeverQuestAlone/sig/ctl/` | `Spellmind/sig/ctl/` |
| SavedVariables | `NQADB`, `NQAMapDB` | `SpellmindDB` |
| Helper exe | `nqa-capture.exe` | `spellmind-capture.exe` |
| Reserved text prefix | `[NeverQuestAlone` | `[Spellmind` |
| Idempotency prefix | `nqa:` | `sm:` |

Windows has no named pipe or mutex: the helper talks over its spawn pipes.

## Build order (each step tested before the next)

1. Pure protocol: records, luaenc and strip, plus the Codec render, in JS and fengari. Coexistence tests: an NQA-magic strip decodes as `none`; a Spellmind strip at y = 272 under an NQA strip decodes.
2. Addon pure parts in fengari: Lua `Record` output byte-equal to `encodeRecord`, and the Codec round-trips.
3. C helper: build, `--version`, `--test-image`, then the ported decoder tests with Spellmind and NQA fixtures.
4. Files: signals, slots install and write, the installer on a fake WoW tree, tasklist parsing.
5. Capture supervisor with a spawn stub.
6. Service with the mock provider: hello → nonce and ring; msg → ack → reply; duplicate re-ack; seen trims; stop aborts; re-ring.
7. Addon in a VM (WoW stub): `/sm` puts a msg on the strip; a slot load prints the reply; the outbox survives `/reload`.
8. Headless end to end: VM addon, real service, stand-in capture, mock provider.
9. Manual: sign in, install (WoW closed), start.
10. Live in game:
    - Spellmind alone first.
    - Then with NQA running, sending from both at once.
    - Also `/reload` mid-turn, a UI scale change, and windowed mode.
    - Check that two DXGI duplication sessions can run at once.
