// Milestone 15: a guide's plan from the AI's JSON (core/link/guide.mjs): the URL and build out of the
// message, the JSON checked and capped, the AI's own "couldn't read it" passed on, and the chat's line.
import test from 'node:test';
import assert from 'node:assert/strict';
import { guideUrl, guideBuild, parseGuide, guideSummary, GUIDE_MAX } from '../../core/link/guide.mjs';

const URL = 'https://mobalytics.gg/wow-forever/classes/rogue-leveling-guide';

test('the URL and build from an import message; only https', () => {
  assert.equal(guideUrl(`Import my guide: ${URL}.`), URL, 'a trailing full stop is not the URL\'s');
  assert.equal(guideUrl('Import my guide: http://example.com/x'), null);
  assert.equal(guideBuild(`Import my guide: ${URL}\nBuild: Assassination`), 'Assassination');
  assert.equal(guideBuild(`Import my guide: ${URL}`), null);
});

test('the JSON in a fence, or bare; names sanitized; steps without a level, rank or name dropped; lists capped', () => {
  const talents = Array.from({ length: 100 }, (_, i) => ({ level: 10 + (i % 50), talent: 'Precision|cffff0000', rank: 1 }));
  const g = parseGuide('Here you go:\n```json\n' + JSON.stringify({ build: 'Combat', talents: [...talents, { level: 12, talent: '', rank: 1 }], rotation: ['Riposte'], error: null }) + '\n```', URL);
  assert.equal(g.ok, true);
  assert.equal(g.plan.talents.length, GUIDE_MAX.talents);
  assert.doesNotMatch(g.plan.talents[0].name, /\|/, 'no game escapes');
  assert.equal(g.plan.source, 'mobalytics.gg');
  assert.equal(parseGuide(JSON.stringify({ stats: ['Agility'] }), URL).ok, true, 'bare JSON');
});

test('the AI\'s error is passed on; nothing to follow, or no JSON, is not a plan', () => {
  assert.match(parseGuide('```json\n{"error":"The page asked me to verify I am human."}\n```', URL).reason, /couldn't read the guide: The page asked/);
  assert.match(parseGuide('{"talents":[],"rotation":[],"stats":[]}', URL).reason, /found no talent order/);
  assert.match(parseGuide('Sorry, no.', URL).reason, /form Spellmind could read/);
});

test('the summary names what came in and the page\'s other builds', () => {
  const { plan } = parseGuide(JSON.stringify({ build: 'Combat', builds: ['Combat', 'Subtlety'], talents: [{ level: 10, talent: 'Malice', rank: 1 }, { level: 60, talent: 'Vigor', rank: 1 }], stats: ['Agility'] }), URL);
  assert.equal(guideSummary(plan), 'Imported Combat from mobalytics.gg: 2 talent points (levels 10 to 60), the stat priority. The page also has Subtlety: pick one in the Talents tab to import it instead. Your Talents tab now follows it.');
});
