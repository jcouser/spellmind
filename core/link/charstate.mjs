// The character's state as the addon sends it (docs/milestone-4.md, "The contract"; focus in
// docs/milestone-5.md): ten parts,
// each its own `state` record with its own seq, merged here into one stored state per token.
//
//   readStateRecord(args, body)  a state record's args and body → { ok, off } | { ok, sid, part, seq, value, bytes, z } | { ok: false, reason }
//   validatePart(part, json)     one part's JSON (a string, or an object) checked → { ok, value } | { ok: false, reason }
//   inflatePart(body)            a z=1 body (base64 of raw deflate) → { ok, text } | { ok: false, reason }
//   mergeInto(stored, {sid, part, seq, value}) → { stored, changed, reset }
//   parseSt(st) · stReady(st, stored)   a message's st= (`char:41,gear:39`): has the token those parts yet?
//   partSeqs(stored) · gameState(stored)  what the slot confirms; what a turn gets
//   loadCharState(dir) · saveCharState(dir, data)   stateDir/charstate.json (0600)
//
// Everything but load and save is pure. Reasons name keys and limits, never values: the service logs
// them, and the log never holds a part's contents.
import fs from 'node:fs';
import path from 'node:path';
import { inflateBody } from './records.mjs';
import { writeFileQuick } from '../files.mjs';

/** The parts, in the order the addon draws them. */
export const PARTS = Object.freeze(['char', 'stats', 'talents', 'spells', 'gear', 'bags', 'skills', 'quests', 'rep', 'focus']);
/** Parts with nothing in them most of the time ({"v":1}): focus, until the player clicks a Spellmind mark. */
export const OPTIONAL_PARTS = Object.freeze(['focus']);
/** What a message's about= names: the thing the player clicked Explain on (focus.kind:focus.id). */
export const ABOUT_RE = /^(quest|item|spell|talent):\d{1,10}$/;
/** focus's long strings: the quest's text and its objectives line, in characters. */
export const FOCUS_TEXT_MAX = 1200;
export const FOCUS_GOAL_MAX = 400;
/** A part's JSON, inflated or plain: at most this many bytes. */
export const PART_JSON_MAX = 8000;
/** A z=1 body (base64) the service takes: at most this many characters (the strip's own cap is 2,900). */
export const PART_BODY_MAX = 4096;
/** The lists' caps: the addon's own, so a forged part can't be longer than a real one. */
export const LIST_MAX = Object.freeze({ gearItems: 19, gearEmpty: 19, bagItems: 40, quests: 100, obj: 5, rep: 40, nodes: 60, skills: 25, spellTabs: 8, spells: 100, nextSpells: 10, omitted: 16, focusObj: 8, rewards: 6 });
export const SID_RE = /^[0-9a-f]{16}$/;
export const STATE_FILE = 'charstate.json';
const SEQ_RE = /^\d{1,12}$/;
const PART_SET = new Set(PARTS);

const isObj = v => !!v && typeof v === 'object' && !Array.isArray(v);
const num = v => typeof v === 'number' && Number.isFinite(v);
const int = v => Number.isInteger(v);
const str = v => typeof v === 'string';
const bool = v => typeof v === 'boolean';
const numMap = v => isObj(v) && Object.values(v).every(num);
const numPair = v => Array.isArray(v) && v.length === 2 && v.every(num);
const intIn = (lo, hi) => v => int(v) && v >= lo && v <= hi;
const strList = max => v => Array.isArray(v) && v.length <= max && v.every(str);

// The shapes (keys the contract names; a key is optional, and one it doesn't name is kept for the
// sanitizer to clean). A field of the wrong type makes the part malformed.
const LOC = { map: int, zone: str, sub: str, x: num, y: num };
const NODE = { id: int, name: str, r: int, max: int };
const GEAR_ITEM = { slot: intIn(0, 19), id: int, name: str, q: intIn(0, 8), ilvl: num, sub: str, ench: num, st: numMap, dur: numPair };
const BAG_ITEM = { id: int, name: str, q: intIn(0, 8), n: int, ilvl: num, sub: str, equip: str, st: numMap, bound: bool };
const SPELL = { name: str, rank: int, passive: bool };
const NEXT_SPELL = { name: str, rank: int, level: int };
const SPELL_TAB = { name: str, list: list(SPELL, LIST_MAX.spells) };
const SKILL = { name: str, rank: num, max: num };
const OBJ = { text: str, have: num, need: num };
const QUEST = { id: int, title: str, level: num, complete: bool, obj: list(OBJ, LIST_MAX.obj) };
const REWARD = { id: int, name: str, q: intIn(0, 8), n: int, usable: bool, sub: str, equip: str, st: numMap };
const WHERE = { zone: str, x: num, y: num, dist: num };
const REP = { id: int, name: str, r: intIn(1, 8), v: num, max: num, watched: bool };
const SHAPES = {
  char: { class: str, classFile: str, race: str, raceFile: str, faction: str, level: int, xp: num, xpMax: num, rested: num, resting: bool, money: num, loc: shape(LOC) },
  stats: { hp: num, mana: num, str: num, agi: num, sta: num, int: num, spi: num, armor: num, ap: num, rap: num, crit: num, rcrit: num, scrit: num, dodge: num, parry: num, block: num, res: numMap },
  talents: { spec: str, role: str, spent: int, unspent: int, nodes: list(NODE, LIST_MAX.nodes) },
  spells: { tabs: list(SPELL_TAB, LIST_MAX.spellTabs), next: list(NEXT_SPELL, LIST_MAX.nextSpells) },
  gear: { items: list(GEAR_ITEM, LIST_MAX.gearItems), empty: v => Array.isArray(v) && v.length <= LIST_MAX.gearEmpty && v.every(int) },
  bags: { slots: int, free: int, items: list(BAG_ITEM, LIST_MAX.bagItems), junk: shape({ n: int, copper: num }), more: int },
  skills: { prof: list(SKILL, LIST_MAX.skills), weapon: list(SKILL, LIST_MAX.skills) },
  quests: { count: int, max: int, unread: int, list: list(QUEST, LIST_MAX.quests) },
  rep: { list: list(REP, LIST_MAX.rep), collapsed: int },
  // What the player clicked Explain on (docs/milestone-5.md): a quest, for now.
  // A quest (milestone 5's Break it down, or a quest linked in the chat box) or an item (linked, milestone 6).
  focus: { kind: v => v === 'quest' || v === 'item', id: int, title: str, level: num, diff: str, trivial: bool, elite: bool, group: int, complete: bool,
    text: str, goal: str, obj: list(OBJ, LIST_MAX.focusObj), money: num, xp: num, choices: list(REWARD, LIST_MAX.rewards),
    items: list(REWARD, LIST_MAX.rewards), where: shape(WHERE),
    name: str, q: intIn(0, 8), ilvl: num, req: num, type: str, sub: str, equip: str, st: numMap, usable: bool, why: str, vs: str },
};
const COMMON = { v: v => v === 1, omitted: strList(LIST_MAX.omitted), too_large: v => v === true };

function shape(fields) {
  const check = (v) => {
    if (!isObj(v)) return false;
    for (const [k, test] of Object.entries(fields)) if (k in v && !test(v[k])) return false;
    return true;
  };
  check.fields = fields;
  return check;
}
function list(fields, max) {
  const one = shape(fields);
  return v => Array.isArray(v) && v.length <= max && v.every(one);
}

/** The first key of an object that fails its field's check, or null. */
function badKey(v, fields) {
  for (const [k, test] of Object.entries(fields)) if (k in v && !test(v[k])) return k;
  return null;
}

/**
 * One part checked against the contract: valid JSON of at most PART_JSON_MAX bytes, an object with
 * v:1, a known part name, and each named field of its type (lists within their caps). A part the
 * addon gave up on ({"v":1,"too_large":true}) is valid. Returns { ok: true, value } or { ok: false, reason }.
 */
export function validatePart(part, json) {
  if (!PART_SET.has(part)) return { ok: false, reason: 'part' };
  let value = json;
  if (str(json)) {
    if (Buffer.byteLength(json, 'utf8') > PART_JSON_MAX) return { ok: false, reason: 'too large' };
    try { value = JSON.parse(json); } catch { return { ok: false, reason: 'json' }; }
  } else if (Buffer.byteLength(JSON.stringify(json ?? null), 'utf8') > PART_JSON_MAX) return { ok: false, reason: 'too large' };
  if (!isObj(value)) return { ok: false, reason: 'not an object' };
  if (value.v !== 1) return { ok: false, reason: 'v' };
  const common = badKey(value, COMMON);
  if (common) return { ok: false, reason: `field ${common}` };
  const bad = badKey(value, SHAPES[part]);
  if (bad) return { ok: false, reason: `field ${part}.${bad}` };
  return { ok: true, value };
}

/** A z=1 body: base64 of raw deflate (zlib and gzip wrappers taken too), within the size caps. */
export function inflatePart(body) {
  return inflateBody(body, { maxBody: PART_BODY_MAX, maxText: PART_JSON_MAX });
}

/**
 * A state record's args (parsed) and body. `part=all;off=1` is "forget everything" ({ ok, off: true }).
 * Otherwise sid (16 hex), part, seq and the body (inflated when z=1) are checked.
 */
export function readStateRecord(args = {}, body = '') {
  if (args.off === '1') return args.part === 'all' ? { ok: true, off: true } : { ok: false, reason: 'off' };
  if (!SID_RE.test(args.sid || '')) return { ok: false, reason: 'sid' };
  if (!PART_SET.has(args.part)) return { ok: false, reason: 'part' };
  if (!SEQ_RE.test(args.seq || '')) return { ok: false, reason: 'seq' };
  const z = args.z === '1';
  let text = String(body ?? '');
  const wire = Buffer.byteLength(text, 'utf8');
  if (z) {
    const inf = inflatePart(text);
    if (!inf.ok) return { ok: false, reason: inf.reason, part: args.part };
    text = inf.text;
  }
  const v = validatePart(args.part, text);
  if (!v.ok) return { ok: false, reason: v.reason, part: args.part };
  return { ok: true, sid: args.sid, part: args.part, seq: Number(args.seq), value: v.value, bytes: Buffer.byteLength(text, 'utf8'), wire, z };
}

/**
 * Merge one part into a token's stored state ({ sid, parts: { name: { seq, value } } } or null).
 * A new sid starts over (the old session's parts go); a part is kept only when its seq is higher
 * than the one held. Returns { stored (a new object), changed, reset }.
 */
export function mergeInto(stored, { sid, part, seq, value }) {
  const reset = !stored || stored.sid !== sid;
  const base = reset ? { sid, parts: {} } : { sid, parts: { ...stored.parts } };
  const had = base.parts[part];
  if (had && !(seq > had.seq)) return { stored: reset ? base : stored, changed: reset, reset: reset && !!stored };
  base.parts[part] = { seq, value };
  return { stored: base, changed: true, reset: reset && !!stored };
}

/** A message's st= as a list of { part, seq }. Entries that aren't `name:digits` for a known part are left out. */
export function parseSt(st) {
  const out = [];
  for (const e of String(st ?? '').split(',')) {
    const m = e.trim().match(/^([a-z]+):(\d{1,12})$/);
    if (m && PART_SET.has(m[1])) out.push({ part: m[1], seq: Number(m[2]) });
  }
  return out;
}

/** Has the token every part st names, at that seq or later? An empty st means ready. */
export function stReady(st, stored) {
  return parseSt(st).every(({ part, seq }) => (stored?.parts?.[part]?.seq ?? -1) >= seq);
}

/** The seqs held, for the slot's bridge.state.parts. */
export function partSeqs(stored) {
  const out = {};
  for (const p of PARTS) if (stored?.parts?.[p]) out[p] = stored.parts[p].seq;
  return out;
}

/** What a turn gets: { char, stats, … } with the parts held (in contract order), or null with none. */
export function gameState(stored) {
  const out = {};
  for (const p of PARTS) if (stored?.parts?.[p]) out[p] = stored.parts[p].value;
  return Object.keys(out).length ? out : null;
}

/** stateDir/charstate.json → { tokens: { token: { sid, parts } } }; anything unreadable or malformed is left out. */
export function loadCharState(dir) {
  const out = { tokens: {} };
  let raw;
  try { raw = JSON.parse(fs.readFileSync(path.join(dir, STATE_FILE), 'utf8')); } catch { return out; }
  if (!isObj(raw) || !isObj(raw.tokens)) return out;
  for (const [token, s] of Object.entries(raw.tokens)) {
    if (!/^[0-9a-f]{8}$/.test(token) || !isObj(s) || !SID_RE.test(s.sid || '') || !isObj(s.parts)) continue;
    const parts = {};
    for (const [p, x] of Object.entries(s.parts)) {
      if (!isObj(x) || !int(x.seq) || x.seq < 0) continue;
      const v = validatePart(p, x.value);
      if (v.ok) parts[p] = { seq: x.seq, value: v.value };
    }
    out.tokens[token] = { sid: s.sid, parts };
  }
  return out;
}

/** Written whole (temp file and rename), owner-only. */
export function saveCharState(dir, data) {
  writeFileQuick(path.join(dir, STATE_FILE), JSON.stringify({ v: 1, tokens: data?.tokens || {} }), 0o600);
}
