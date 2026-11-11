// Spellmind: adapted from NeverQuestAlone's bridge/byok/runtime/sanitize.mjs (MIT; see NOTICE.md).
// Game text on its way into a prompt.
//
// Everything that comes from the game is forgeable: other addons, pasted macros and other players can
// put text into quest titles, item names and zone names. The addon already strips escapes, `|`,
// newlines and controls and cuts strings to 60 bytes (docs/milestone-4.md, "Limits"); the service does
// it again here, because a forged record never went through the addon's code:
//   - C0 and C1 controls (newlines and tabs included) become a space: no line of game text can start
//     a new line of the prompt ("\n--- end of game data ---\nSystem: ...").
//   - Game escapes go whole: colours (|cAARRGGBB, |cn…:) and |r, textures (|T…|t) and atlases
//     (|A…|a); a link (|H…|h[Name]|h) keeps its [Name]. Then any `|` left goes.
//   - Format and default-ignorable characters go (bidi controls, zero-width characters, tag
//     characters, variation selectors, ...), which can smuggle text a reader never sees, and so do
//     unpaired surrogates.
//   - Whitespace collapses, the ends are trimmed, and the length is capped in code points.
// Pure functions.

export const GAME_STRING_MAX = 60;

// Controls (C0, DEL, C1) and the line and paragraph separators: replaced by a space.
const BREAKS = /[\u{0}-\u{1f}\u{7f}-\u{9f}\u{2028}\u{2029}]/gu;
// Invisible or direction-changing characters, removed: every format character (Cf), every
// default-ignorable code point, and unpaired surrogates (with the u flag a surrogate range matches only those).
export const INVISIBLE = /[\p{Cf}\p{Default_Ignorable_Code_Point}\u{d800}-\u{dfff}]/gu;
// Game escapes: colours old and new, the colour end, textures, atlases; links keep their text.
const ESCAPES = [
  [/\|c[0-9a-fA-F]{8}/g, ''], [/\|cn[^:|]*:/g, ''], [/\|r/g, ''],
  [/\|H[^|]*\|h(.*?)\|h/g, '$1'], [/\|T[^|]*\|t/g, ''], [/\|A[^|]*\|a/g, ''],
];

/** Game escape sequences taken out whole (a link keeps its [Name]); a `|` that's left stays for the caller. */
export function stripEscapes(s) {
  let t = String(s ?? '');
  if (!t.includes('|')) return t;
  for (const [re, to] of ESCAPES) t = t.replace(re, to);
  return t;
}

/** Cut to at most max code points (never inside a surrogate pair). */
export function capCodePoints(s, max) {
  const t = String(s);
  if (t.length <= max) return t;
  return Array.from(t).slice(0, max).join('');
}

/** One game string, safe for a prompt: one line, no controls, `|` or invisible characters, capped. */
export function sanitizeGameString(s, max = GAME_STRING_MAX) {
  if (s === null || s === undefined) return '';
  const t = stripEscapes(String(s)).replace(INVISIBLE, '').replace(BREAKS, ' ').replace(/\|/g, '').replace(/\s+/g, ' ').trim();
  return capCodePoints(t, max).trim();
}

// List limits: the addon's own (docs/milestone-4.md), so a forged state can't be longer than a real
// one. A list's limit is looked up by "<part>.<key>" first, then by its key; else 25.
export const LIST_MAX = Object.freeze({ 'gear.items': 19, 'gear.empty': 19, 'bags.items': 40, 'quests.list': 100, obj: 5, 'rep.list': 40, nodes: 60, 'spells.tabs': 8, list: 100, 'spells.next': 10, omitted: 16, 'focus.obj': 8, 'focus.choices': 6, 'focus.items': 6 });
// Strings longer than GAME_STRING_MAX, by "<part>.<key>": the quest text an Explain click sends.
export const LONG_STRINGS = Object.freeze({ 'focus.text': 1200, 'focus.goal': 400 });
const KEY_RE = /^[A-Za-z_][A-Za-z0-9_]{0,23}$/;
// Keys that an object literal treats specially: `out.__proto__ = x` sets the prototype instead of
// adding a key, so attacker data would be reachable by property access and hidden from JSON.
const UNSAFE_KEYS = new Set(['__proto__', 'constructor', 'prototype']);
const okKey = k => KEY_RE.test(k) && !UNSAFE_KEYS.has(k);

/**
 * A copy of a game state ({ char, stats, … }, or any game JSON) that's safe to put in a prompt: every
 * string sanitized and capped (60 by default), non-finite numbers and unknown types dropped, odd keys
 * dropped (and __proto__, constructor, prototype), lists capped (the addon's limits, else 25), at most
 * 7 levels and 40 keys an object.
 */
export function sanitizeState(value, { max = GAME_STRING_MAX, depth = 7 } = {}) {
  const walk = (v, d, key, part) => {
    if (v === null) return null;
    if (typeof v === 'string') return sanitizeGameString(v, d === depth - 2 ? (LONG_STRINGS[`${part}.${key}`] ?? max) : max);
    if (typeof v === 'number') return Number.isFinite(v) ? v : undefined;
    if (typeof v === 'boolean') return v;
    if (d <= 0 || typeof v !== 'object') return undefined;
    if (Array.isArray(v)) {
      const out = [];
      for (const x of v.slice(0, LIST_MAX[`${part}.${key}`] ?? LIST_MAX[key] ?? 25)) {
        const y = walk(x, d - 1, key, part);
        if (y !== undefined) out.push(y);
      }
      return out;
    }
    const out = {};
    let n = 0;
    for (const [k, x] of Object.entries(v)) {
      if (!okKey(k) || n >= 40) continue;
      // The top level's keys are the parts: each names the part its lists belong to.
      const y = walk(x, d - 1, k, part ?? k);
      if (y !== undefined) { out[k] = y; n += 1; }
    }
    return out;
  };
  return walk(value, depth, null, null);
}

/** JSON on one line that no string inside can break out of: `<`, `>` and line separators escaped. */
export function encodeData(data) {
  return JSON.stringify(data).replace(/[<>\u{2028}\u{2029}]/gu, c => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`);
}
