// Spellmind: adapted from NeverQuestAlone's bridge/byok/runtime/pack.mjs (MIT; see NOTICE.md).
// The prompt: prompts/spellmind.md, the whole system prompt of every turn, sent as the cached prefix.
//
//   loadPack() → { text, version, tokens }
//
// A leading <!-- … --> comment (notes for whoever edits the prompt) is taken out. {{code.NAME}} is
// filled from the constant in the code that enforces the number (CODE below), so the prompt never
// says a number the code doesn't hold; a placeholder with no constant is an error, never sent. The
// version is the first 12 hex of the text's sha256, so a log line says exactly which prompt a turn
// went with. tokens is an estimate, at 4 characters a token.
import fs from 'node:fs';
import crypto from 'node:crypto';
import { TEXT_MAX, SUMMARY_MAX } from '../link/render.mjs';
import { PART_JSON_MAX, LIST_MAX as PART_LIST_MAX } from '../link/charstate.mjs';
import { GAME_STRING_MAX } from './sanitize.mjs';
import { DATA_MAX_CHARS } from './context.mjs';

export const PACK_FILE = new URL('../../prompts/spellmind.md', import.meta.url);
/** The numbers the prompt may name, each from the code that enforces it. */
export const CODE = Object.freeze({
  TEXT_MAX, SUMMARY_MAX, GAME_STRING_MAX, DATA_MAX_CHARS, PART_JSON_MAX,
  GEAR_ITEMS: PART_LIST_MAX.gearItems, BAG_ITEMS: PART_LIST_MAX.bagItems, QUESTS: PART_LIST_MAX.quests,
  OBJECTIVES: PART_LIST_MAX.obj, REPS: PART_LIST_MAX.rep, TALENT_NODES: PART_LIST_MAX.nodes,
});
const COMMENT_RE = /^\s*<!--[\s\S]*?-->\s*\n/;
const PLACEHOLDER_RE = /\{\{\s*code\.([A-Za-z0-9_]+)\s*\}\}/g;

export const estimateTokens = text => Math.ceil(String(text ?? '').length / 4);

/** The prompt's template with its numbers filled. Throws on a placeholder the code has no number for. */
export function fillPack(template, code = CODE) {
  const text = String(template).replace(COMMENT_RE, '').replace(PLACEHOLDER_RE, (m, name) => {
    if (!Object.hasOwn(code, name)) throw new Error(`prompt: no constant for {{code.${name}}}`);
    const v = code[name];
    return typeof v === 'number' ? v.toLocaleString('en-US') : String(v);
  });
  if (/\{\{[^}]*\}\}/.test(text)) throw new Error('prompt: a placeholder is left unfilled');
  return text;
}

let cached = null;

/** { text, version, tokens }, read once. */
export function loadPack({ file = PACK_FILE, fresh = false } = {}) {
  if (cached && !fresh && file === PACK_FILE) return cached;
  const text = fillPack(fs.readFileSync(file, 'utf8'));
  const version = crypto.createHash('sha256').update(text, 'utf8').digest('hex').slice(0, 12);
  const pack = Object.freeze({ text, version, tokens: estimateTokens(text) });
  if (file === PACK_FILE) cached = pack;
  return pack;
}
