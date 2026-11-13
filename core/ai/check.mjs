// The double-check (docs/milestone-17.md): an answer that names places, people, routes, items or quest
// steps is checked once more before the player sees it. The player found facts were often wrong until
// they asked a few times (a vendor who wasn't there, a pass that doesn't exist), so the app now asks
// once more itself: the same AI, the same game data, its draft in front of it, told to verify each
// concrete claim and send back the corrected answer. Plain chat ("thanks", "what's my rotation")
// goes out unchecked, so it stays quick.

// A question about where, who, what sells or teaches, how to get somewhere, drops or quest steps.
const FACT_QUESTION = /\b(where|who|whom|which (npc|vendor|trainer|quest)|sells?|buy|vendor|trainer|teach(es)?|train|route|get to|reach|travel|find|drops?|located|path|go to|turn(ed)? in|starts?|flight|fly|boat|zeppelin|tram|portal|entrance|coords?|coordinates)\b/i;
// A draft that cites the web, gives coordinates, or names who to see or where to go.
const FACT_DRAFT = /\(sources?:|\(\d{1,3}(\.\d)?,\s*\d{1,3}(\.\d)?\)|\b(sells|teaches|is in|stands|head (north|south|east|west)|take the|fly (to|from)|from [A-Z][a-z]+ [A-Z][a-z]+)\b/;

/** Is this answer worth checking? */
export function needsCheck(question, draft) {
  if (!String(draft ?? '').trim()) return false;
  return FACT_QUESTION.test(String(question ?? '')) || FACT_DRAFT.test(String(draft ?? ''));
}

/** The check's own message, after the question and the draft. */
export const CHECK_ASK = [
  'Check your answer above before the player sees it.',
  'Verify every concrete claim in it: NPC names and where they stand, who sells or teaches what, routes between zones, quest givers and steps, items, drops and levels.',
  'Check against the game data first (`world`: NPCs nearby and what they sell, the flight paths known, the hearth; and the zone links in your instructions), then search the web.',
  'Fix what\'s wrong; where you can\'t confirm a claim, say plainly that you\'re not sure, or leave it out. Keep what\'s right.',
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
