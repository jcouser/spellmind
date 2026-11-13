// The audit's batch A (docs/milestone-21.md): one turn with the player's AI, against a stand-in AI.
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadManifests } from '../../core/ai/providers/index.mjs';
import { loadPack } from '../../core/ai/pack.mjs';
import { createTurn } from '../../core/app/turn.mjs';
import { pickChecked } from '../../core/ai/check.mjs';
import { SEARCH_OFF_NOTE, SEARCH_ON_NOTE } from '../../core/ai/context.mjs';

const manifests = loadManifests();
const pack = loadPack();
const byId = id => manifests.find(m => m.id === id);
const GAME = { state: { char: { class: 'Rogue', level: 18 } }, stale: false };

// A stand-in AI: each call takes the next script (a list of events), and the requests are kept.
function rig(id, scripts, opts = {}) {
  const m = byId(id);
  const calls = [];
  const provider = {
    async *stream(req) {
      calls.push(req);
      for (const ev of scripts.shift() || [{ type: 'text', delta: 'Fine.' }, { type: 'done', finish: 'stop' }]) yield ev;
    },
  };
  const lines = [];
  const t = createTurn({ m, model: opts.model || m.models.default, provider, pack, log: (k, d) => lines.push([k, d]), effort: 'medium', search: !!m.webSearch, retryMaxMs: 50, ...opts });
  return { ...t, calls, lines, m };
}
const reply = (text, finish = 'stop') => [{ type: 'text', delta: text }, { type: 'done', finish }];
const fail = (kind, extra = {}) => [{ type: 'error', error: { kind, provider: 'x', retryable: kind === 'overloaded' || kind === 'rate_limited', retryAfterMs: 10, ...extra } }];

test('the ceiling: the reply\'s 1,200 plus room for the thinking level, held to the model\'s maximum; none for a model without levels', async () => {
  const r = rig('anthropic', [reply('Hello.')]);
  assert.equal(r.maxTokensFor('low'), 1200 + 2048);
  assert.equal(r.maxTokensFor('medium'), 1200 + 4096);
  assert.equal(r.maxTokensFor('max'), 1200 + 65536 > 128000 ? 128000 : 1200 + 65536, 'held to Claude\'s 128K');
  await r.turn({ chatId: 'c1', text: 'hi', history: [], game: GAME, effort: 'high', check: false });
  assert.equal(r.calls[0].maxTokens, 1200 + 8192);
  // A model with no levels: the reply's room only (Grok 4.20 without thinking).
  const plain = rig('xai', [], { model: 'grok-4.20-0309-non-reasoning' });
  assert.equal(plain.maxTokensFor('high'), byId('xai').limits.maxOutputTokens);
});

test('the ChatGPT plan: a chat\'s draft and its check share one cache key; another chat has another', async () => {
  const r = rig('chatgpt', [reply('Gryan Stoutmantle sells it (source: Wowhead).'), reply('OK')]);
  const out = await r.turn({ chatId: 'chatA', text: 'Where do I turn in The People\'s Militia?', history: [], game: GAME });
  assert.equal(out.text, 'Gryan Stoutmantle sells it (source: Wowhead).', 'the check said OK: the draft goes');
  assert.equal(r.calls.length, 2);
  assert.match(r.calls[0].cacheKey, /^[0-9a-f]{32}$/);
  assert.equal(r.calls[1].cacheKey, r.calls[0].cacheKey);
  const other = rig('chatgpt', [reply('Hi.')]);
  await other.turn({ chatId: 'chatB', text: 'hi', history: [], game: GAME, check: false });
  assert.notEqual(other.calls[0].cacheKey, r.calls[0].cacheKey);
  assert.ok(!r.calls[0].cacheKey.includes('chatA'), 'a hash, not the chat id');
});

test('a busy AI is tried once more after its wait; the second failure says what\'s true (no "trying again")', async () => {
  const r = rig('anthropic', [fail('overloaded'), reply('Here you go.')]);
  assert.equal((await r.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false })).text, 'Here you go.');
  assert.ok(r.lines.some(([k]) => k === 'retry'));
  const twice = rig('anthropic', [fail('overloaded'), fail('overloaded')]);
  const out = await twice.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false });
  assert.equal(out.error.kind, 'overloaded');
  assert.doesNotMatch(out.error.text, /Trying again/);
  assert.match(out.error.text, /Try again in a minute|Still busy/);
  // A wait longer than allowed isn't waited for; a refused key isn't retried at all.
  const long = rig('anthropic', [fail('rate_limited', { retryAfterMs: 999999 })]);
  assert.equal((await long.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false })).error.kind, 'rate_limited');
  assert.equal(long.calls.length, 1);
  const key = rig('anthropic', [fail('auth_invalid')]);
  assert.match((await key.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false })).error.text, /key was rejected/);
  assert.equal(key.calls.length, 1);
});

test('a reply cut at the ceiling says so; none at all, or a refusal with none, is an error to act on', async () => {
  const cut = rig('anthropic', [reply('Go north to Sentinel Hill and', 'length')]);
  assert.match((await cut.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false })).text, /Sentinel Hill and\n\n\(Cut short: ask "go on" for the rest\.\)$/);
  const empty = rig('anthropic', [[{ type: 'done', finish: 'length' }]]);
  const e = await empty.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false });
  assert.equal(e.error.kind, 'empty_reply');
  assert.match(e.error.text, /couldn't finish a reply/);
  const refused = rig('anthropic', [[{ type: 'done', finish: 'refusal' }]]);
  assert.equal((await refused.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false })).error.kind, 'content_blocked');
});

test('the search note goes with the game data each turn; without search the check is asked from the game data only', async () => {
  const on = rig('chatgpt', [reply('Hi.')]);
  await on.turn({ chatId: 'c', text: 'hi', history: [], game: GAME, check: false });
  assert.ok(JSON.stringify(on.calls[0].messages).includes(SEARCH_ON_NOTE));
  const off = rig('google', [reply('Thor sells it at (52, 53).'), reply('OK')]);
  await off.turn({ chatId: 'c', text: 'Who sells arrows?', history: [], game: GAME });
  const sent = JSON.stringify(off.calls[0].messages);
  assert.ok(sent.includes('Web search: off this turn'));
  assert.ok(!JSON.stringify(off.calls[0].system).includes('Web search: off'), 'never in the cached prompt');
  assert.match(JSON.stringify(off.calls[1].messages), /can't search the web this turn/);
  assert.equal(off.calls[0].webSearch, false);
  assert.ok(SEARCH_OFF_NOTE.length > 0);
});

test('the check\'s answer: "OK" and comments keep the draft; a lead-in line goes; far longer keeps the draft', () => {
  const draft = 'Thor sells arrows in Sentinel Hill (52, 53).\nNext: Where is the flight master? / What else does Thor sell?';
  for (const c of ['OK', 'OK.', 'Your answer is correct. No changes needed.', 'Upon review, everything checks out.', 'I\'ve verified it: all correct.']) {
    assert.equal(pickChecked(draft, c).used, false, c);
  }
  const lead = pickChecked(draft, 'Here is the corrected answer:\n\nKelsey sells arrows in Sentinel Hill (52, 53).\nNext: Where is the flight master?');
  assert.equal(lead.used, true);
  assert.match(lead.text, /^Kelsey sells/);
  assert.equal(pickChecked(draft, `OK, Thor sells arrows at the inn in Sentinel Hill (52, 53), by the stairs.`).used, true, 'an answer starting "OK," is an answer');
  assert.equal(pickChecked(draft, 'x'.repeat(2000)).why, 'long');
});
