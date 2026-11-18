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

const looksLikeHost = t => /^[a-z0-9-]+(\.[a-z0-9-]+)+$/i.test(String(t).trim());
/** A citation's site, short: the link's own words when they're a host name, else the URL's host (no www.). */
function sourceName(text, url) {
  if (looksLikeHost(text)) return String(text).trim().replace(/^www\./i, '');
  try { return new URL(url).hostname.replace(/^www\./i, ''); } catch { return 'the web'; }
}

/**
 * Sources side by side made one (seen in game: "(Sources: WoWHead Classic; …) (source: wowhead.com)",
 * the model's own words and the citation's). A site already named ("wowhead" in "WoWHead Classic")
 * isn't named again.
 */
export function mergeSources(s) {
  return String(s).replace(/\((?:sources?)\s*:\s*[^()]*\)(?:\s*\((?:sources?)\s*:\s*[^()]*\))+/gi, (run) => {
    const groups = run.match(/\((?:sources?)\s*:\s*([^()]*)\)/gi) || [];
    const names = [];
    for (const g of groups) {
      const inner = g.replace(/^\((?:sources?)\s*:\s*/i, '').replace(/\)$/, '');
      for (const raw of inner.split(/\s*;\s*/)) {
        const n = raw.trim().replace(/\.$/, '');
        if (!n) continue;
        const key = n.toLowerCase().replace(/^www\./, '').replace(/\.(com|org|net|gg|io|wiki|gg)$/, '').replace(/[^a-z0-9]/g, '');
        if (names.some(x => x.key.includes(key) || key.includes(x.key))) continue;
        names.push({ n, key });
      }
    }
    return `(${names.length > 1 ? 'sources' : 'source'}: ${names.map(x => x.n).join('; ')})`;
  });
}

/** Markdown to the plain text the window shows: headings, emphasis, code and links flattened; lists kept. */
export function markdownToWow(md) {
  let s = String(md ?? '').replace(/\r\n?/g, '\n').replace(CONTROL, '');
  // A model's thinking written into its reply (local models: "<think>…</think>"), never shown.
  s = s.replace(/<think>[\s\S]*?<\/think>\s*/gi, '').replace(/^[\s\S]*?<\/think>\s*/i, '');
  s = s.replace(/```[a-z0-9_-]*\n?([\s\S]*?)```/gi, (_, code) => code.replace(/\n+$/, ''));
  // Tables (Gemini, Grok, local models): the game can't draw them. A row becomes "• a · b · c"; the
  // "|---|" line under the header goes.
  s = s.replace(/^[ \t]*\|?([ \t]*:?-{2,}:?[ \t]*\|)+[ \t]*:?-{0,}:?[ \t]*\n?/gm, '');
  s = s.replace(/^[ \t]*\|(.+)\|[ \t]*$/gm, (_, row) => `• ${row.split('|').map(c => c.trim()).filter(Boolean).join(' · ')}`);
  s = s.replace(/~~(.+?)~~/g, '$1');
  // Grok's inline citations, "[[1]](https://…)": a source like any other.
  s = s.replace(/\s*\[\[(\d+)\]\]\((https?:[^)\s]+)\)/g, (_, n, url) => ` (source: ${sourceName('', url)})`);
  s = s.replace(/^#{1,6}\s+(.+?)\s*#*\s*$/gm, '$1');
  s = s.replace(/^\s*[-*+]\s+/gm, '• ');
  s = s.replace(/^\s*>\s?/gm, '');
  s = s.replace(/\*\*(.+?)\*\*|__(.+?)__/g, (_, a, b) => a ?? b);
  s = s.replace(/(^|[^*\w])\*(?!\s)(.+?)\*(?!\w)/g, '$1$2');
  s = s.replace(/`([^`\n]+)`/g, '$1');
  s = s.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');
  // Links can't be clicked in game, so a URL is never shown: a web search's citation,
  // "([wowhead.com](https://…))", becomes "(source: wowhead.com)", and a link in the text keeps its words.
  s = s.replace(/\(\s*\[([^\]]+)\]\((https?:[^)\s]+)\)\s*\)/g, (_, text, url) => `(source: ${sourceName(text, url)})`);
  s = s.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, (_, text, url) => (looksLikeHost(text) ? `(source: ${sourceName(text, url)})` : text));
  s = s.replace(/https?:\/\/\S+/g, m => `(source: ${sourceName('', m)})`);
  s = mergeSources(s);
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

export const CHIPS_MAX = 3;
export const CHIP_MAX = 40;
const CHIPS_LINE = /^\s*(?:\*\*|__)?\s*Next\s*(?:\*\*|__)?\s*:\s*(?:\*\*|__)?\s*(.+?)\s*$/i;
/**
 * The reply's suggestion chips (the prompt asks for a last line "Next: a / b / c"): that line taken off
 * the text, its suggestions as at most CHIPS_MAX short one-line strings. A reply without one has none.
 */
export function splitChips(raw) {
  const lines = String(raw ?? '').replace(/\r\n?/g, '\n').split('\n');
  let i = lines.length - 1;
  while (i >= 0 && !lines[i].trim()) i--;
  let m = i >= 0 ? lines[i].match(CHIPS_LINE) : null;
  // "Next:" at the end of the last paragraph, after a sentence (seen in game: "…the count mismatch.
  // Next: Where do I get Red Silk Bandanas? / Which Deadmines quests do I have?"): taken when what
  // follows reads as suggestions (a "/" or a question), so a plain "Next: head to Lakeshire." stays.
  if (!m && i >= 0) {
    const inline = lines[i].match(/^(.*?[.!?)])\s+(?:\*\*|__)?Next\s*(?:\*\*|__)?\s*:\s*(?:\*\*|__)?\s*(.+?)\s*$/i);
    if (inline && /\s\/\s|\?/.test(inline[2])) {
      lines.splice(i, 1, inline[1], `Next: ${inline[2]}`);
      i += 1;
      m = lines[i].match(CHIPS_LINE);
    }
  }
  if (!m) return { body: String(raw ?? ''), chips: [] };
  const chips = m[1].split(/\s+\/\s+|\s*;\s*/)
    .map(c => markdownToWow(c).replace(/^["“']|["”']$/g, '').replace(/\s+/g, ' ').trim())
    .filter(c => c && c.length <= CHIP_MAX).slice(0, CHIPS_MAX).map(escapePipes);
  return { body: lines.slice(0, i).join('\n').trimEnd(), chips };
}

export const PINS_MAX = 3;
const PIN_LINE = /^\s*(?:\*\*|__)?\s*Pin\s*(?:\*\*|__)?\s*:\s*(?:\*\*|__)?\s*(.+?)\s*$/i;
const PIN_PARTS = /^(.{1,40}?)\s*\|\s*([A-Za-z][A-Za-z' .-]{1,39}?)\s*\|\s*\(?\s*(\d{1,3}(?:\.\d+)?)\s*,\s*(\d{1,3}(?:\.\d+)?)\s*\)?$/;
/**
 * The reply's map pins (the prompt asks for lines "Pin: who | zone | x, y"): those lines taken off the
 * text, as at most PINS_MAX { n, z, x, y } with x and y 0-100 (one decimal). A line that doesn't read
 * as a pin stays in the text. The player's click sets the game's pin; nothing here does.
 */
export function splitPins(raw) {
  const pins = [];
  const keep = [];
  for (const line of String(raw ?? '').replace(/\r\n?/g, '\n').split('\n')) {
    const m = line.match(PIN_LINE);
    const p = m ? m[1].replace(/[*_`]/g, '').match(PIN_PARTS) : null;
    const x = p ? Number(p[3]) : NaN, y = p ? Number(p[4]) : NaN;
    if (p && x >= 0 && x <= 100 && y >= 0 && y <= 100) {
      if (pins.length < PINS_MAX) pins.push({ n: escapePipes(p[1].trim()), z: p[2].trim(), x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 });
    } else keep.push(line);
  }
  return { body: keep.join('\n').trimEnd(), pins };
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
