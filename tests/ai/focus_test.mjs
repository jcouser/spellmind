// The focus part (docs/milestone-5.md): what the player clicked Explain on. The contract's checks, its
// long strings through the sanitizer, and the turn rule: focus goes only to the message about it.
import test from 'node:test';
import assert from 'node:assert/strict';
import { validatePart, ABOUT_RE, PARTS, OPTIONAL_PARTS } from '../../core/link/charstate.mjs';
import { sanitizeState, GAME_STRING_MAX } from '../../core/ai/sanitize.mjs';
import { buildRequest, focusFor, partNotes, FOCUS_NOTE } from '../../core/ai/context.mjs';

const QUEST = { v: 1, kind: 'quest', id: 297, title: 'Gathering Idols', level: 18, diff: 'VeryDifficult', complete: false,
  text: 'The troggs carry stone idols. '.repeat(20), goal: 'Bring 8 Carved Stone Idols to Prospector Ironband.',
  obj: [{ text: 'Carved Stone Idol', have: 0, need: 8 }], money: 650, xp: 1350,
  choices: [{ id: 7001, name: "Ironband's Gloves", q: 2, n: 1, usable: true }], where: { zone: 'Loch Modan', x: 70.6, y: 25, dist: 560 } };

test('focus: the tenth part, optional; a quest focus and an empty one are valid, a wrong kind or field is not', () => {
  assert.ok(PARTS.includes('focus'));
  assert.deepEqual(OPTIONAL_PARTS, ['focus', 'world', 'advisor'], 'world and advisor (milestones 17, 18) are optional too');
  assert.ok(validatePart('focus', { v: 1 }).ok);
  assert.ok(validatePart('focus', QUEST).ok);
  assert.equal(validatePart('focus', { ...QUEST, kind: 'npc' }).reason, 'field focus.kind');
  assert.equal(validatePart('focus', { ...QUEST, where: { x: 'east' } }).reason, 'field focus.where');
  assert.equal(validatePart('focus', { ...QUEST, choices: Array(7).fill(QUEST.choices[0]) }).reason, 'field focus.choices');
});

test('about=: kind and id only', () => {
  for (const ok of ['quest:297', 'item:2504', 'spell:1752', 'talent:105708']) assert.ok(ABOUT_RE.test(ok), ok);
  for (const bad of ['quest:', 'quest:abc', 'npc:1', 'quest:297;x=1', 'QUEST:297', 'quest:12345678901']) assert.ok(!ABOUT_RE.test(bad), bad);
});

test('the sanitizer: focus.text and focus.goal keep their length (1,200 and 400), every other string 60, and nested ones too', () => {
  const s = sanitizeState({ focus: { ...QUEST, title: 'x'.repeat(100), text: 'y'.repeat(2000), goal: 'z'.repeat(900), obj: [{ text: 'w'.repeat(100) }] }, char: { zone: 'q'.repeat(100), text: 'r'.repeat(100) } });
  assert.equal(s.focus.text.length, 1200);
  assert.equal(s.focus.goal.length, 400);
  assert.equal(s.focus.title.length, GAME_STRING_MAX);
  assert.equal(s.focus.obj[0].text.length, GAME_STRING_MAX, 'an objective inside focus: the usual cap');
  assert.equal(s.char.text.length, GAME_STRING_MAX, 'text outside focus: the usual cap');
});

test('focusFor: kept with its note when about names it; left out otherwise (an old click can\'t steer a new question)', () => {
  const state = { char: { v: 1, level: 15 }, focus: QUEST };
  assert.equal(focusFor(state, 'quest:297').focused, true);
  for (const about of [undefined, 'quest:298', 'item:297', 'nonsense']) {
    const r = focusFor(state, about);
    assert.equal(r.focused, false, String(about));
    assert.equal('focus' in r.state, false, String(about));
  }
  const kept = buildRequest({ pack: 'P', game: { state, stale: false, about: 'quest:297' }, userText: 'Break this quest down for me.', nonce: 'abcd' });
  assert.match(kept.messages[0].content, /"focus":\{"v":1,"kind":"quest"/);
  assert.ok(kept.messages[0].content.includes(JSON.stringify(FOCUS_NOTE).slice(1, -1)));
  const dropped = buildRequest({ pack: 'P', game: { state, stale: false }, userText: 'hi', nonce: 'abcd' });
  assert.doesNotMatch(dropped.messages[0].content, /"focus"|Focus:/);
});

test('notes: an empty or missing focus isn\'t "missing" or reported', () => {
  const full = Object.fromEntries(PARTS.filter(p => p !== 'focus').map(p => [p, { v: 1 }]));
  assert.deepEqual(partNotes(full), []);
  assert.deepEqual(partNotes({ ...full, focus: { v: 1 } }), []);
  assert.deepEqual(partNotes({ ...full, focus: { v: 1, too_large: true } }), ['focus: too large to send this turn.']);
});

test('web search: offered on the Responses request only when the turn asks and the AI has it; its events keep the stream alive', async () => {
  const { loadManifests } = await import('../../core/ai/providers/index.mjs');
  const { responsesRequest, responsesParse } = await import('../../core/ai/providers/adapters/openai.mjs');
  const ms = loadManifests();
  const chatgpt = ms.find(m => m.id === 'chatgpt');
  assert.deepEqual(chatgpt.webSearch, { type: 'web_search' });
  assert.deepEqual(ms.find(m => m.id === 'openai').webSearch, { type: 'web_search' });
  // Claude's server tool and Grok's Responses tool (the audit's batch E); Gemini's needs its own adapter.
  assert.deepEqual(ms.find(m => m.id === 'anthropic').webSearch, { type: 'web_search_20250305', name: 'web_search', max_uses: 3 });
  assert.deepEqual(ms.find(m => m.id === 'xai').webSearch, { type: 'web_search' });
  assert.equal(ms.find(m => m.id === 'google').webSearch, undefined, 'google: no adapter for it yet');
  const req = { model: chatgpt.models.default, effort: 'medium', system: [{ text: 'S' }], messages: [{ role: 'user', content: 'hi' }] };
  const body = t => { const b = t.body ?? t.init?.body; return typeof b === 'string' ? JSON.parse(b) : b; };
  assert.deepEqual(body(responsesRequest(chatgpt, { ...req, webSearch: true })).tools, [{ type: 'web_search' }]);
  assert.equal(body(responsesRequest(chatgpt, req)).tools, undefined, 'not asked: no tools');
  assert.equal(body(responsesRequest({ ...chatgpt, webSearch: undefined }, { ...req, webSearch: true })).tools, undefined, 'an AI without it: no tools');
  const sse = ['response.web_search_call.in_progress', 'response.web_search_call.searching', 'response.web_search_call.completed']
    .map(type => `event: ${type}\ndata: ${JSON.stringify({ type })}\n\n`).join('')
    + `data: ${JSON.stringify({ type: 'response.output_text.delta', delta: 'Darnassus.' })}\n\n`
    + `data: ${JSON.stringify({ type: 'response.completed', response: { usage: {} } })}\n\n`;
  const res = { body: new Response(sse).body };
  const evs = [];
  for await (const ev of responsesParse(res, { fail: x => x })) evs.push(ev);
  assert.deepEqual(evs.filter(e => e.type === 'progress').map(e => e.searching), [true, true, true]);
  assert.equal(evs.find(e => e.type === 'text').delta, 'Darnassus.');
});

test('a citation shows as its site: the game can\'t show links, so no URL reaches it', async () => {
  const { markdownToWow } = await import('../../core/link/render.mjs');
  assert.equal(markdownToWow('Ilyenia Moonfire teaches Bows. ([worldofwarcraft.blizzard.com](https://worldofwarcraft.blizzard.com/en-us/news/1?utm_source=openai))'),
    'Ilyenia Moonfire teaches Bows. (source: worldofwarcraft.blizzard.com)');
  assert.equal(markdownToWow('See [Wowhead](https://www.wowhead.com/classic/npc=4204) for her spot.'), 'See Wowhead for her spot.');
  assert.equal(markdownToWow('[www.wowhead.com](https://www.wowhead.com/x)'), '(source: wowhead.com)');
  assert.equal(markdownToWow('Bare: https://warcraft.wiki.gg/wiki/Weapon_master.'), 'Bare: (source: warcraft.wiki.gg)');
});
