// A player's guide, imported from a link (docs/milestone-15.md). The message "Import my guide: <url>"
// with guide=1 makes the turn ask the AI to read that page with web search and give its build back
// as JSON. The app checks the JSON here and hands the addon a plain plan (the reply record's `plan`):
// the talent order, the ability priority, the stat priority and the weapon advice. Nothing of the
// page is kept but that plan, and only what the page says: the AI is told not to fill gaps.
import { sanitizeGameString } from '../ai/sanitize.mjs';

export const GUIDE_URL_RE = /\bhttps:\/\/[^\s<>"'|]{4,300}/i;
export const GUIDE_MAX = Object.freeze({ talents: 80, rotation: 10, stats: 10, builds: 6, name: 60, line: 120, weapons: 200 });

/** The URL in an import message, or null. */
export function guideUrl(text) {
  const m = GUIDE_URL_RE.exec(String(text ?? ''));
  return m ? m[0].replace(/[).,;]+$/, '') : null;
}

/** The build the player picked ("Build: Assassination" on its own line), or null. */
export function guideBuild(text) {
  const m = /^\s*Build:\s*(.{1,60})$/m.exec(String(text ?? ''));
  return m ? m[1].trim() : null;
}

/** What the turn asks the AI, in place of the player's short message. */
export function guideAsk(url, build) {
  return [
    `Read this guide with web search: ${url}`,
    `Open the page itself. Report only what it says; never fill gaps from memory or other sites. If you can't open or read it, say so in "error".`,
    build ? `Use the build named "${build}".` : `Use the build the page leads with (its main one).`,
    `Answer with one JSON object in a \`\`\`json block and nothing else after it:`,
    '```json',
    `{"title": "the page's title", "build": "the build's name", "builds": ["every build the page names"],`,
    ` "talents": [{"level": 10, "talent": "Talent Name", "rank": 1}],`,
    ` "rotation": ["ability priority, one short step a line, in order"],`,
    ` "stats": ["stat priority, most important first"],`,
    ` "weapons": "the weapon advice in one or two sentences",`,
    ` "error": null}`,
    '```',
    `talents: one entry per point, in the page's order, with the level it's taken at and the rank it reaches. Leave a list empty when the page doesn't give it.`,
  ].join('\n');
}

const str = (v, max) => (typeof v === 'string' ? sanitizeGameString(v, max) : '');
const int = (v, lo, hi) => (Number.isInteger(v) && v >= lo && v <= hi ? v : null);

/**
 * The plan in an AI's reply: { ok: true, plan } or { ok: false, reason }. plan = { title, build,
 * builds[], talents[{ level, name, rank }], rotation[], stats[], weapons, source (the host) }.
 */
export function parseGuide(raw, url) {
  const text = String(raw ?? '');
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(text);
  const body = fenced ? fenced[1] : (text.match(/\{[\s\S]*\}/) || [''])[0];
  let j;
  try { j = JSON.parse(body); } catch { return { ok: false, reason: 'Your AI didn\'t send the build back in a form Spellmind could read. Try the import again.' }; }
  if (!j || typeof j !== 'object' || Array.isArray(j)) return { ok: false, reason: 'Your AI sent no build.' };
  if (typeof j.error === 'string' && j.error.trim()) return { ok: false, reason: `Your AI couldn't read the guide: ${str(j.error, 200)}` };
  const talents = [];
  for (const t of Array.isArray(j.talents) ? j.talents.slice(0, GUIDE_MAX.talents) : []) {
    const level = int(t?.level, 1, 100), rank = int(t?.rank, 1, 10);
    const name = str(t?.talent ?? t?.name, GUIDE_MAX.name);
    if (level && rank && name) talents.push({ level, name, rank });
  }
  const list = (v, n, max) => (Array.isArray(v) ? v.slice(0, n).map(x => str(x, max)).filter(Boolean) : []);
  const plan = {
    title: str(j.title, GUIDE_MAX.line),
    build: str(j.build, GUIDE_MAX.name),
    builds: list(j.builds, GUIDE_MAX.builds, GUIDE_MAX.name),
    talents,
    rotation: list(j.rotation, GUIDE_MAX.rotation, GUIDE_MAX.line),
    stats: list(j.stats, GUIDE_MAX.stats, GUIDE_MAX.name),
    weapons: str(j.weapons, GUIDE_MAX.weapons),
    url: String(url ?? '').slice(0, 300),
    source: (() => { try { return new URL(url).hostname.replace(/^www\./, ''); } catch { return ''; } })(),
  };
  if (!plan.talents.length && !plan.rotation.length && !plan.stats.length) return { ok: false, reason: 'Your AI found no talent order, ability priority or stat priority on that page.' };
  return { ok: true, plan };
}

/** The chat's line for an imported plan. */
export function guideSummary(plan) {
  const bits = [];
  if (plan.talents.length) {
    const lo = Math.min(...plan.talents.map(t => t.level)), hi = Math.max(...plan.talents.map(t => t.level));
    bits.push(`${plan.talents.length} talent points (levels ${lo} to ${hi})`);
  }
  if (plan.rotation.length) bits.push('the ability priority');
  if (plan.stats.length) bits.push('the stat priority');
  if (plan.weapons) bits.push('weapon advice');
  const others = plan.builds.filter(b => b && b !== plan.build);
  return `Imported ${plan.build || 'the build'} from ${plan.source || 'your guide'}: ${bits.join(', ')}.` +
    (others.length ? ` The page also has ${others.join(', ')}: pick one in the Talents tab to import it instead.` : '') +
    ' Your Talents tab now follows it.';
}
