// A reply as the addon shows it: plain WoW text from the model's Markdown, with every `|` doubled
// (WoW reads `|c`, `|H`, `|T` … as escapes: a doubled pipe is a literal one, so nothing in a reply can
// become a link, a colour or a texture: the injection barrier), control characters gone, and a short
// summary for the chat frame. Spellmind's own, modeled on NeverQuestAlone's bridge/app/render.mjs
// (MIT; see NOTICE.md), without its map, chip and quest blocks.

export const TEXT_MAX = 12000;
export const SUMMARY_MAX = 160;

/** Bytes WoW's renderer or the record format can't take: C0 controls but tab and newline, DEL, and RS/US/GS. */
const CONTROL = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g;

/** `|` doubled: a literal pipe in game, never an escape. */
export const escapePipes = s => String(s).replace(/\|/g, '||');

/** Markdown to the plain text the window shows: headings, emphasis, code and links flattened; lists kept. */
export function markdownToWow(md) {
  let s = String(md ?? '').replace(/\r\n?/g, '\n').replace(CONTROL, '');
  s = s.replace(/```[a-z0-9_-]*\n?([\s\S]*?)```/gi, (_, code) => code.replace(/\n+$/, ''));
  s = s.replace(/^#{1,6}\s+(.+?)\s*#*\s*$/gm, '$1');
  s = s.replace(/^\s*[-*+]\s+/gm, '• ');
  s = s.replace(/^\s*>\s?/gm, '');
  s = s.replace(/\*\*(.+?)\*\*|__(.+?)__/g, (_, a, b) => a ?? b);
  s = s.replace(/(^|[^*\w])\*(?!\s)(.+?)\*(?!\w)/g, '$1$2');
  s = s.replace(/`([^`\n]+)`/g, '$1');
  s = s.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');
  s = s.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '$1 ($2)');
  s = s.replace(/^\s*([-*_])\s*(?:\1\s*){2,}$/gm, '');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

/** The first sentence (or line) of plain text, at most `max` characters, for the chat frame. */
export function firstSentence(plain, max = SUMMARY_MAX) {
  const line = String(plain ?? '').split('\n').map(l => l.trim()).find(Boolean) ?? '';
  const m = line.match(/^(.+?[.!?])(\s|$)/);
  const s = (m ? m[1] : line).replace(/^•\s*/, '');
  return s.length <= max ? s : `${s.slice(0, max - 1).trimEnd()}…`;
}

/** A reply record's fields: {text, summary, more}. more: 1 when the text was cut to fit. */
export function renderReply(raw) {
  const plain = markdownToWow(raw);
  const more = plain.length > TEXT_MAX ? 1 : 0;
  const cut = more ? `${plain.slice(0, TEXT_MAX - 1).trimEnd()}…` : plain;
  return { text: escapePipes(cut), summary: escapePipes(firstSentence(cut)), more };
}

/** A line Spellmind itself writes (an error, a stop): one line, pipes doubled, at most 400 characters. */
export function systemLine(s) {
  const one = String(s ?? '').replace(CONTROL, '').replace(/\s+/g, ' ').trim().slice(0, 400);
  return escapePipes(one);
}
