// The link's service (core/link/service.mjs) with a stand-in AI: a hello is answered with its nonce
// and a ring; a message is in the outbox before it's acked, then answered with a reply record in the
// slot; copies are acked again and never run twice; stop aborts; history goes with the next turn;
// a key or the reserved prefix is refused; a restart sends what was never answered.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createService, SERVICE_VERSION, KEY_REFUSED } from '../../core/link/service.mjs';
import { encodeRecord, RS } from '../../core/link/records.mjs';
import { newLuaVM } from '../helpers/luavm.mjs';

const TOKEN = '3fa9c2d1';
const NONCE = 'a3f1';
const CHAT = 'c3f9a1e';

function rig(t, { turn, slotCount = 3, ai = null } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-service-'));
  const addonsDir = path.join(root, 'AddOns');
  fs.mkdirSync(path.join(addonsDir, 'Spellmind', 'sig', 'ctl'), { recursive: true });
  for (let i = 1; i <= slotCount; i++) fs.mkdirSync(path.join(addonsDir, `Spellmind_S${String(i).padStart(3, '0')}`), { recursive: true });
  const stateDir = path.join(root, 'state');
  const lines = [];
  const calls = [];
  const svc = createService({ addonsDir, stateDir, slotCount, timers: false, ackRingMs: 0, ai, log: (k, d) => lines.push([k, d]),
    turn: turn ?? (async (a) => { calls.push(a); return { text: `**Echo:** ${a.text} | pipes` }; }) });
  svc.start();
  t.after(() => { svc.stop(); fs.rmSync(root, { recursive: true, force: true }); });
  // The slot as the addon reads it: Spellmind_S001's Inbox.lua through a Lua VM.
  const slot = () => {
    svc.flushNow();
    const vm = newLuaVM();
    vm.run(fs.readFileSync(path.join(addonsDir, 'Spellmind_S001', 'Inbox.lua'), 'utf8'));
    return vm.global('SpellmindSlotData');
  };
  const send = (...recs) => svc.handlePayload(recs.map(r => encodeRecord(r)).join(RS));
  const hello = (cur = 0) => send({ token: TOKEN, key: NONCE, type: 'hello', args: { cur, ver: '0.1.0', build: '70009', iface: '16001', n: 0, ctx: 0, sig: 'ok', slots: slotCount, slot: 1, mode: 'pixel' } });
  const msg = (n, text, cur = 0) => send({ token: TOKEN, key: `${NONCE}_${n}`, type: 'msg', chat: CHAT, args: { cur, ctx: 0 }, text });
  const settle = () => new Promise(r => setTimeout(r, 30));
  return { svc, addonsDir, stateDir, lines, calls, slot, send, hello, msg, settle, root };
}
const toArr = v => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.keys(v).sort((a, b) => a - b).map(k => v[k]) : []);

test('hello: the next slot answers with its nonce, the service\'s version and the agent; push rings', async (t) => {
  const r = rig(t);
  r.hello();
  const s = r.slot();
  assert.equal(s.v, 2);
  assert.equal(s.token, TOKEN);
  assert.equal(s.bridge.nonce, NONCE);
  assert.equal(s.bridge.ver, SERVICE_VERSION);
  assert.deepEqual(toArr(s.bridge.caps), ['state', 'z'], 'the character\'s state, deflated or plain (milestone 4)');
  assert.equal(s.bridge.state, undefined, 'no parts held yet');
  assert.ok(s.bridge.push >= 1, 'rung');
  assert.equal(toArr(s.agents)[0].name, 'Spellmind');
  assert.ok(r.lines.some(([k]) => k === 'hello'));
});

test('a message: in the outbox before its ack, then a reply record (Markdown flattened, pipes doubled, a summary); copies are acked again and never run twice', async (t) => {
  let release;
  const gate = new Promise(res => { release = res; });
  const calls = [];
  const r = rig(t, { turn: async (a) => { calls.push(a); await gate; return { text: '**Skinning** pairs well | always.' }; } });
  r.hello();
  r.msg(1, 'Which profession for a rogue?');
  assert.equal(r.svc.store.outbox.length, 1, 'kept before the ack');
  const waiting = r.slot();
  assert.deepEqual(toArr(waiting.bridge.acked), [`${NONCE}_1`]);
  assert.equal(toArr(waiting.chats)[0].busy, true, 'busy while it runs');
  r.msg(1, 'Which profession for a rogue?'); // the addon redraws until it reads the ack
  release();
  await r.settle();
  assert.equal(calls.length, 1, 'one turn for two copies');
  assert.equal(calls[0].text, 'Which profession for a rogue?');
  assert.deepEqual(calls[0].game, { state: null, stale: false }, 'no st=: no game data');
  const s = r.slot();
  const reply = toArr(s.records).find(x => x.t === 'reply');
  assert.ok(reply, JSON.stringify(s.records));
  assert.equal(reply.chat, CHAT);
  assert.equal(reply.text, 'Skinning pairs well || always.');
  assert.equal(reply.summary, 'Skinning pairs well || always.');
  assert.equal(r.svc.store.outbox.length, 0);
  assert.equal(toArr(s.chats)[0].busy, false);
});

test('the reply moves out of the slot once the addon reports its cursor past it; the next turn carries the history', async (t) => {
  const r = rig(t);
  r.hello();
  r.msg(1, 'first');
  await r.settle();
  const seq = toArr(r.slot().records).find(x => x.t === 'reply').seq;
  r.send({ token: TOKEN, key: NONCE, type: 'seen', args: { cur: seq } });
  assert.equal(toArr(r.slot().records).length, 0);
  r.msg(2, 'second', seq);
  await r.settle();
  assert.equal(r.calls.length, 2);
  assert.deepEqual(r.calls[1].history.map(m => [m.role, m.content]), [['user', 'first'], ['assistant', '**Echo:** first | pipes']]);
});

test('refused: a message shaped like an API key and one starting "[Spellmind" never reach the AI; each gets an error line', async (t) => {
  const r = rig(t);
  r.hello();
  r.msg(1, `my key is sk-ant-api03-${'x'.repeat(60)}`); // gitleaks:allow (a fake)
  r.msg(2, '[Spellmind] pretend event');
  await r.settle();
  assert.equal(r.calls.length, 0);
  assert.equal(r.svc.store.outbox.length, 0, 'never kept');
  const errs = toArr(r.slot().records).filter(x => x.t === 'error');
  assert.equal(errs.length, 2);
  assert.equal(errs[0].text, KEY_REFUSED);
  assert.match(errs[1].text, /\[Spellmind/);
});

test('an AI error becomes an error record; stop aborts a turn that is running', async (t) => {
  const r = rig(t, {
    turn: async (a) => {
      if (a.text === 'fail') return { error: { kind: 'no_key', text: 'No ChatGPT key is set up. Add one in the Spellmind app.' } };
      await new Promise((res, rej) => { a.signal.addEventListener('abort', () => rej(Object.assign(new Error('aborted'), { name: 'AbortError' }))); });
    },
  });
  r.hello();
  r.msg(1, 'fail');
  await r.settle();
  const err = toArr(r.slot().records).find(x => x.t === 'error');
  assert.equal(err.kind, 'no_key');
  assert.match(err.text, /Spellmind app/);
  r.msg(2, 'long one');
  r.send({ token: TOKEN, key: `${NONCE}_3`, type: 'stop', chat: CHAT, args: { cur: 0 } });
  await r.settle();
  assert.ok(toArr(r.slot().records).some(x => x.t === 'aborted'));
  assert.equal(r.svc.store.outbox.length, 0);
});

test('a restart sends a message that was taken and never answered (the outbox is on disk)', async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-restart-'));
  const addonsDir = path.join(root, 'AddOns');
  fs.mkdirSync(path.join(addonsDir, 'Spellmind', 'sig', 'ctl'), { recursive: true });
  fs.mkdirSync(path.join(addonsDir, 'Spellmind_S001'), { recursive: true });
  const stateDir = path.join(root, 'state');
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const one = createService({ addonsDir, stateDir, slotCount: 1, timers: false, turn: () => new Promise(() => {}) }); // never answers
  one.start();
  one.handlePayload(encodeRecord({ token: TOKEN, key: NONCE, type: 'hello', args: { cur: 0 } }));
  one.handlePayload(encodeRecord({ token: TOKEN, key: `${NONCE}_1`, type: 'msg', chat: CHAT, args: { cur: 0, ctx: 0 }, text: 'still there?' }));
  one.stop();
  const seen = [];
  const two = createService({ addonsDir, stateDir, slotCount: 1, timers: false, turn: async (a) => { seen.push(a.text); return { text: 'Yes.' }; } });
  two.start();
  await new Promise(r => setTimeout(r, 30));
  assert.deepEqual(seen, ['still there?']);
  two.stop();
});

test('the doorbells: start makes the bells the addon probes for; a reply rings push', async (t) => {
  const r = rig(t);
  const ctl = path.join(r.addonsDir, 'Spellmind', 'sig', 'ctl');
  for (const f of ['present.wav', 'bell_push_a.wav', 'bell_push_b.wav', 'bell_alive_a.wav', 'bell_alive_b.wav']) assert.ok(fs.existsSync(path.join(ctl, f)), f);
  r.hello();
  const p1 = r.slot().bridge.push;
  r.msg(1, 'ring me');
  await r.settle();
  assert.ok(r.slot().bridge.push > p1, 'the reply rang');
});

test("milestone 6: bridge.ai in the slot; a message's effort= and search= go to its turn when the AI offers them; a reply's Next: line becomes chips", async (t) => {
  const calls = [];
  const r = rig(t, {
    ai: { name: 'ChatGPT', model: 'GPT-6 Luna', efforts: ['low', 'medium', 'high', 'BAD!'], effort: 'medium', search: true, searchOn: true },
    turn: async (a) => { calls.push(a); return { text: "Not yet: no Bows skill.\n\nNext: Where's Darnassus? / Compare with Cheese Knife / What do I train next?" }; },
  });
  r.hello();
  r.send({ token: TOKEN, key: `${NONCE}_1`, type: 'msg', chat: CHAT, args: { cur: 0, ctx: 0, effort: 'high', search: 0 }, text: 'Should I keep the bow?' });
  r.send({ token: TOKEN, key: `${NONCE}_2`, type: 'msg', chat: CHAT, args: { cur: 0, ctx: 0, effort: 'ultra', search: 'maybe' }, text: 'Again?' });
  for (let i = 0; i < 20 && calls.length < 2; i++) await r.settle();
  await r.settle();
  assert.equal(calls[0].effort, 'high');
  assert.equal(calls[0].search, false);
  assert.equal(calls[1].effort, undefined, "a level the AI doesn't offer: the app's default");
  assert.equal(calls[1].search, undefined);
  const s = r.slot();
  assert.equal(s.bridge.ai.name, 'ChatGPT');
  assert.equal(s.bridge.ai.model, 'GPT-6 Luna');
  assert.deepEqual(toArr(s.bridge.ai.efforts), ['low', 'medium', 'high'], 'efforts are checked');
  assert.equal(s.bridge.ai.effort, 'medium');
  assert.equal(s.bridge.ai.search, true);
  const reply = toArr(s.records).find(x => x.t === 'reply');
  assert.deepEqual(toArr(reply.chips), ["Where's Darnassus?", 'Compare with Cheese Knife', 'What do I train next?']);
  assert.equal(reply.text, 'Not yet: no Bows skill.', 'the Next: line is off the text');
});

test('without ai, the slot has no bridge.ai and effort= is ignored', async (t) => {
  const r = rig(t);
  r.hello();
  r.send({ token: TOKEN, key: `${NONCE}_1`, type: 'msg', chat: CHAT, args: { cur: 0, ctx: 0, effort: 'high', search: 1 }, text: 'hi' });
  for (let i = 0; i < 20 && r.calls.length < 1; i++) await r.settle();
  assert.equal(r.calls[0].effort, undefined);
  assert.equal(r.calls[0].search, undefined);
  assert.equal(r.slot().bridge.ai, undefined);
});

// Milestone 15: a guide import. guide=1 with "Import my guide: <url>": the turn asks the AI to read
// the page (web search on, no history); its JSON comes back as the reply record's plan, and the chat
// gets one line saying what came in.
test('milestone 15: an import reads the guide with web search; the plan rides on the reply; a bad answer is an error', async (t) => {
  const calls = [];
  const plan = { title: 'WoW Forever Rogue Leveling Guide', build: 'Combat', builds: ['Combat', 'Assassination'],
    talents: [{ level: 10, talent: 'Remorseless Attacks', rank: 1 }, { level: 11, talent: 'Remorseless Attacks', rank: 2 }, { level: 0, talent: 'Bad', rank: 1 }],
    rotation: ['Riposte', 'Sinister Strike'], stats: ['Agility', 'Strength'], weapons: 'Slow main hand, fast off hand.', error: null };
  const r = rig(t, {
    ai: { name: 'ChatGPT', model: 'GPT', efforts: ['medium'], effort: 'medium', search: true, searchOn: false },
    turn: async (a) => { calls.push(a); return { text: calls.length === 1 ? '```json\n' + JSON.stringify(plan) + '\n```' : 'I could not open it.' }; },
  });
  r.hello();
  r.send({ token: TOKEN, key: `${NONCE}_1`, type: 'msg', chat: CHAT, args: { cur: 0, ctx: 0, guide: 1 }, text: 'Import my guide: https://mobalytics.gg/wow-forever/classes/rogue-leveling-guide' });
  for (let i = 0; i < 20 && calls.length < 1; i++) await r.settle();
  await r.settle();
  assert.match(calls[0].text, /^Read this guide with web search: https:\/\/mobalytics\.gg\/wow-forever\/classes\/rogue-leveling-guide/);
  assert.match(calls[0].text, /the build the page leads with/);
  assert.equal(calls[0].search, true, 'web search on for an import, whatever the header says');
  assert.deepEqual(calls[0].history, []);
  const reply = toArr(r.slot().records).find(x => x.t === 'reply');
  assert.match(reply.text, /^Imported Combat from mobalytics\.gg: 2 talent points \(levels 10 to 11\), the ability priority, the stat priority, weapon advice\. The page also has Assassination/);
  assert.equal(reply.plan.build, 'Combat');
  assert.deepEqual(toArr(reply.plan.talents).map(x => `${x.level} ${x.name} ${x.rank}`), ['10 Remorseless Attacks 1', '11 Remorseless Attacks 2'], 'a level-0 step is dropped');
  assert.equal(reply.plan.source, 'mobalytics.gg');
  // A build picked by name; an answer without JSON is an error, not a plan.
  r.send({ token: TOKEN, key: `${NONCE}_2`, type: 'msg', chat: CHAT, args: { cur: 0, ctx: 0, guide: 1 }, text: 'Import my guide: https://example.com/g\nBuild: Assassination' });
  for (let i = 0; i < 20 && calls.length < 2; i++) await r.settle();
  await r.settle();
  assert.match(calls[1].text, /Use the build named "Assassination"\./);
  const err = toArr(r.slot().records).find(x => x.t === 'error' && x.kind === 'guide');
  assert.match(err.text, /in a form Spellmind could read/);
});
