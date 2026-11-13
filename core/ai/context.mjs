// Spellmind: adapted from NeverQuestAlone's bridge/byok/runtime/context.mjs (MIT; see NOTICE.md).
// One provider request from the prompt pack, the character's state, the chat's history and the
// player's typed text.
//
//   buildRequest({ pack, game, history, userText, nonce }) → { system, messages, meta }
//     system    [{ text: pack.text, cache: true }]: the prompt, the cached prefix
//     messages  the chat's history ({ role, content }, typed text only), then one user turn:
//                 <game_data id="<nonce>">
//                 {"source":"game","game":{"char":{…},…,"notes":[…]}}      one line of JSON
//                 </game_data id="<nonce>">
//                 <the player's text>
//               With no game data (game null, or no state and nothing stale), just the text.
//     meta      { nonce, dataChars, omitted }: for the log (sizes and labels, never contents)
//
// Game data is data: every game string is sanitized (sanitize.mjs), the block is JSON on one line
// with `<`, `>` and the line separators escaped, and its closing line carries a random id drawn per
// turn, so no game text can end the block or start a line of its own. The block is fitted to
// DATA_MAX_CHARS encoded characters, dropping in order: bag items, the rep list, quest objectives,
// then stats; a note says what was left out. game.notes also says how many quests the log has (so a
// short list never reads as a cut one), when the data is stale, and each part that's missing, too
// large or trimmed by the addon (its `omitted`).
import crypto from 'node:crypto';
import { sanitizeState, encodeData } from './sanitize.mjs';
import { PARTS, OPTIONAL_PARTS, ABOUT_RE } from '../link/charstate.mjs';

export const TAG = 'game_data';
export const DATA_MAX_CHARS = 16000;
export const STALE_NOTE = 'Stale: some parts this message named didn\'t arrive in time, so what\'s here may be from before the player\'s latest change.';
export const FOCUS_NOTE = "Focus: the player clicked Spellmind's mark on the thing in `focus`, and this message is about it.";
export const NO_DATA_NOTE = 'No game data arrived for this message: the character\'s details aren\'t known this turn.';

const isObj = v => !!v && typeof v === 'object' && !Array.isArray(v);
const whole = v => (Number.isInteger(v) && v >= 0 ? v : null);

/** The quest log's line: how many quests the log has and whether every one is listed. */
export function questNote(quests) {
  if (!isObj(quests)) return 'Quest log: not in this game data.';
  if (quests.too_large) return 'Quest log: too large to send this turn.';
  const listed = Array.isArray(quests.list) ? quests.list.length : 0;
  const count = whole(quests.count) ?? listed;
  const max = whole(quests.max);
  const unread = whole(quests.unread) || 0;
  const of = max ? ` of ${max}` : '';
  if (!count && !unread) return `Quest log: empty (0${of} quests).`;
  if (listed >= count && !unread) return `Quest log: ${count}${of} quests, every one listed.`;
  const missing = [listed < count ? `${count - listed} not listed` : null, unread ? `${unread} the game hasn't read yet` : null].filter(Boolean).join(', ');
  return `Quest log: ${count}${of} quests, ${listed} listed (${missing}): a quest the player names that isn't listed may still be in their log.`;
}

/** The parts' own notes: missing, too large, or trimmed by the addon (its `omitted`). */
export function partNotes(state) {
  const out = [];
  const missing = PARTS.filter(p => !OPTIONAL_PARTS.includes(p) && !isObj(state?.[p]));
  if (missing.length) out.push(`Not in this game data: ${missing.join(', ')}.`);
  for (const p of PARTS) {
    const v = state?.[p];
    if (OPTIONAL_PARTS.includes(p) && isObj(v) && Object.keys(v).length <= 1) continue;
    if (!isObj(v)) continue;
    if (v.off) out.push(`${p}: the player keeps this back (Spellmind's Settings tab): don't guess it; they can turn it on there.`);
    else if (v.too_large) out.push(`${p}: too large to send this turn.`);
    else if (Array.isArray(v.omitted) && v.omitted.length) out.push(`${p}: the addon left out ${v.omitted.join(', ')} to fit.`);
  }
  return out;
}

// What fitData cuts, in order: [label, cut one piece (true) or nothing left (false)].
const FIT_STEPS = [
  ['bag items', g => Array.isArray(g.bags?.items) && g.bags.items.length > 0 && (g.bags.items.pop(), true)],
  ['reputations', g => Array.isArray(g.rep?.list) && g.rep.list.length > 0 && (g.rep.list.pop(), true)],
  ["vendors' goods", g => { const l = Array.isArray(g.world?.npcs) ? g.world.npcs : []; for (const n of l) if (isObj(n) && 'sells' in n) { delete n.sells; return true; } return false; }],
  ['NPCs nearby', g => Array.isArray(g.world?.npcs) && g.world.npcs.length > 0 && (g.world.npcs.pop(), true)],
  ['quest objectives', (g) => {
    const list = Array.isArray(g.quests?.list) ? g.quests.list : [];
    for (let i = list.length - 1; i >= 0; i--) if (isObj(list[i]) && 'obj' in list[i]) { delete list[i].obj; return true; }
    return false;
  }],
  ['stats', g => 'stats' in g && (delete g.stats, true)],
  // Past the contract's order, for a state no real addon makes: whole parts, char last of all.
  ...['advisor', 'world', 'bags', 'rep', 'skills', 'spells', 'talents', 'gear', 'quests'].map(p => [p, g => p in g && (delete g[p], true)]),
];

/**
 * Fit the game data ({ char, …, notes }) to max encoded characters (encodeData of the whole data
 * object). Cuts in FIT_STEPS order and adds a note naming what went. Returns { game, omitted }.
 */
export function fitData(game, max = DATA_MAX_CHARS) {
  const g = structuredClone(game);
  const omitted = [];
  const notes = Array.isArray(g.notes) ? g.notes : [];
  const withNote = () => (omitted.length ? { ...g, notes: [...notes, `Left out to fit the size limit: ${omitted.join(', ')}.`] } : g);
  const size = () => encodeData({ source: 'game', game: withNote() }).length;
  for (const [label, cut] of FIT_STEPS) {
    while (size() > max) {
      if (!cut(g)) break;
      if (!omitted.includes(label)) omitted.push(label);
    }
    if (size() <= max) break;
  }
  return { game: withNote(), omitted };
}

/** The chat's history as messages: user and assistant turns with string content only. */
function historyMessages(history) {
  return (Array.isArray(history) ? history : [])
    .filter(m => isObj(m) && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
    .map(m => ({ role: m.role, content: m.content }));
}

/**
 * focus goes only to the turn it's about: kept when the message's about= (game.about) names it
 * (kind:id), with a note saying so; otherwise left out, so an old click can't steer a new question.
 */
export function focusFor(state, about) {
  const f = state?.focus;
  if (!isObj(f)) return { state, focused: false };
  const { focus, ...rest } = state;
  const named = typeof about === 'string' && ABOUT_RE.test(about) && typeof f.kind === 'string' && `${f.kind}:${f.id}` === about;
  return named ? { state, focused: true } : { state: rest, focused: false };
}

/**
 * pack: { text } (loadPack) or the prompt's text; game: { state, stale, about } or null; history:
 * [{ role, content }]; userText: what the player typed; nonce: hex, drawn per turn by default.
 */
// Whether this turn has web search (the audit: the prompt said "most turns you also have web search", so an AI
// without it couldn't tell, and might cite a site it never read). A note with the game data, never in the
// cached prompt, so a change of search doesn't cost the cache.
export const SEARCH_ON_NOTE = 'Web search: on this turn.';
export const SEARCH_OFF_NOTE = 'Web search: off this turn. Answer from the game data and what you know, say plainly when you are not sure, and never cite a site as "(source: …)".';

export function buildRequest({ pack, game = null, history = [], userText = '', nonce = crypto.randomBytes(4).toString('hex'), dataMax = DATA_MAX_CHARS, search } = {}) {
  const packText = typeof pack === 'string' ? pack : pack?.text;
  if (!packText) throw new Error('buildRequest needs the prompt pack');
  if (!/^[0-9a-f]{4,32}$/.test(nonce)) throw new Error('nonce must be hex');
  const text = String(userText ?? '');
  const system = [{ text: packText, cache: true }];
  const messages = historyMessages(history);
  const picked = focusFor(isObj(game?.state) ? game.state : null, game?.about);
  const state = picked.state ? sanitizeState(picked.state) : null;
  const stale = game?.stale === true;
  if (!state && !stale) {
    messages.push({ role: 'user', content: text });
    return { system, messages, meta: { nonce: null, dataChars: 0, omitted: [] } };
  }
  const searchNote = search === true ? [SEARCH_ON_NOTE] : search === false ? [SEARCH_OFF_NOTE] : [];
  const notes = state ? [...searchNote, questNote(state.quests), ...(picked.focused ? [FOCUS_NOTE] : []), ...(stale ? [STALE_NOTE] : []), ...partNotes(state)] : [...searchNote, NO_DATA_NOTE, STALE_NOTE];
  const fitted = fitData({ ...(state || {}), notes }, Math.max(1000, Number(dataMax) || DATA_MAX_CHARS));
  const line = encodeData({ source: 'game', game: fitted.game });
  const content = `<${TAG} id="${nonce}">\n${line}\n</${TAG} id="${nonce}">\n${text}`;
  messages.push({ role: 'user', content });
  return { system, messages, meta: { nonce, dataChars: line.length, omitted: fitted.omitted } };
}
