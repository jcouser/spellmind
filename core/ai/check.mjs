// The double-check (docs/milestone-17.md): an answer that names places, people, routes, items or quest
// steps is checked once more before the player sees it. The player found facts were often wrong until
// they asked a few times (a vendor who wasn't there, a pass that doesn't exist), so the app now asks
// once more itself: the same AI, the same game data, its draft in front of it, told to verify each
// concrete claim and send back the corrected answer. Plain chat ("thanks", "what's my rotation")
// goes out unchecked, so it stays quick.
//
// The review (2026-11-12): the patterns were too wide (a "Next:" chip like "Who sells arrows?" made
// "thanks" a fact answer; "is in" matched most sentences), and a check that came back as a comment
// ("Everything above is correct."), much shorter, or without its "Next:" line replaced a good draft.
import { splitChips } from '../link/render.mjs';

// A question about where, who sells or teaches, how to get somewhere, drops or quest steps.
const FACT_QUESTION = /\b(where|whom?\s+(sells|teaches|gives|has|starts)|which (npc|vendor|trainer|quest|flight)|sells?|vendors?|trainers?|teach(es)?|route|get to|travel to|drops?|located|go to|turn(ed)? in|quest (giver|start)|flight (path|master)|fly to|boat|zeppelin|tram|portal|entrance|coords?|coordinates)\b/i;
// A draft that cites the web, gives coordinates, or names who to see or where to go.
const FACT_DRAFT = /\(sources?:|\(\d{1,3}(\.\d)?,\s*\d{1,3}(\.\d)?\)|\b(sells|teaches|head (north|south|east|west)|fly (to|from))\b/;

/** Is this answer worth checking? The draft without its "Next:" chips line. */
export function needsCheck(question, draft) {
  const body = splitChips(String(draft ?? '')).body;
  if (!body.trim()) return false;
  return FACT_QUESTION.test(String(question ?? '')) || FACT_DRAFT.test(body);
}

/** The check's own message, after the question and the draft. It starts with the app's own prefix. */
export const CHECK_ASK = [
  '[Spellmind check] Check your answer above before the player sees it.',
  'Verify every concrete claim in it: NPC names and where they stand, who sells or teaches what, routes between zones, quest givers and steps, items, drops and levels.',
  'Check against the game data first (`world`: NPCs nearby and what they sell, the flight paths known, the hearth; `advisor`; and the zone links in your instructions), then search the web.',
  'Fix what\'s wrong. Keep every claim the game data supports, even when the web says nothing about it; hedge a claim you can\'t confirm ("from memory, …") rather than delete it.',
  'Also make sure it answers what the player asked, and doesn\'t contradict what you said earlier in this chat.',
  'Reply with the corrected answer only, in the same style and about the same length, with its "Next:" line if it had one. Don\'t mention that you checked.',
].join(' ');

/**
 * The check's history: the chat so far, the question and the draft, so the check's message (with the
 * game data again) comes last.
 */
export function checkHistory(history, question, draft) {
  return [...(Array.isArray(history) ? history : []), { role: 'user', content: String(question) }, { role: 'assistant', content: String(draft) }];
}

// A check that came back as a comment on the draft, not an answer.
const META = /^\s*(everything|all of (it|this|the above)|the (draft|answer)( above)? (is|looks|was)|i (checked|verified|reviewed)|no (changes|corrections)|(that|this) (is|looks) (correct|right|accurate))/i;

/**
 * Which to send: the checked answer, or the draft when the check is unusable (empty, a comment, under
 * half the draft's length). A checked answer that lost the draft's "Next:" line gets it back.
 */
export function pickChecked(draft, checked) {
  const d = String(draft ?? ''), c = String(checked ?? '');
  if (!c.trim() || META.test(c)) return { text: d, used: false, why: c.trim() ? 'comment' : 'empty' };
  const dParts = splitChips(d), cParts = splitChips(c);
  if (cParts.body.trim().length < dParts.body.trim().length * 0.5) return { text: d, used: false, why: 'short' };
  if (dParts.chips.length && !cParts.chips.length) {
    const next = d.split('\n').reverse().find(l => /^\s*(\*\*|__)?\s*Next\s*(\*\*|__)?\s*:/i.test(l));
    if (next) return { text: `${c.trimEnd()}\n\n${next.trim()}`, used: true };
  }
  return { text: c, used: true };
}
