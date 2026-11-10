// The service's side of milestone 4's contract (docs/milestone-4.md): state records in, plain and
// z=1, merged per token and confirmed in the slot (bridge.caps, bridge.state, read through a Lua VM
// as the addon reads it); a new sid starts over and an older seq is ignored; a message and its parts
// in one payload meet; a message whose st= isn't met waits for its parts, then goes stale; off=1
// forgets; the state survives a restart; the log has part names and sizes, never their contents.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { createService, CAPS } from '../../core/link/service.mjs';
import { encodeRecord, RS } from '../../core/link/records.mjs';
import { PARTS, STATE_FILE } from '../../core/link/charstate.mjs';
import { newLuaVM } from '../helpers/luavm.mjs';

const FIX = JSON.parse(fs.readFileSync(new URL('../fixtures/state-parts.json', import.meta.url), 'utf8'));
const TOKEN = '3fa9c2d1';
const NONCE = 'a3f1';
const CHAT = 'c3f9a1e';
const SID2 = '0123456789abcdef';
const ALL_ST = PARTS.map(p => `${p}:${FIX.seq}`).join(',');

function dirs(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-state-'));
  const addonsDir = path.join(root, 'AddOns');
  fs.mkdirSync(path.join(addonsDir, 'Spellmind', 'sig', 'ctl'), { recursive: true });
  fs.mkdirSync(path.join(addonsDir, 'Spellmind_S001'), { recursive: true });
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return { root, addonsDir, stateDir: path.join(root, 'state') };
}

function rig(t, { turn, stateWaitMs = 4000, where = dirs(t) } = {}) {
  const lines = [];
  const calls = [];
  const svc = createService({ addonsDir: where.addonsDir, stateDir: where.stateDir, slotCount: 1, timers: false, ackRingMs: 0, stateWaitMs,
    log: (k, d) => lines.push([k, d]),
    turn: turn ?? (async (a) => { calls.push(a); return { text: 'Aye.' }; }) });
  svc.start();
  t.after(() => svc.stop());
  const slot = () => {
    svc.flushNow();
    const vm = newLuaVM();
    vm.run(fs.readFileSync(path.join(where.addonsDir, 'Spellmind_S001', 'Inbox.lua'), 'utf8'));
    return vm.global('SpellmindSlotData');
  };
  const send = (...recs) => svc.handlePayload(recs.map(r => encodeRecord(r)).join(RS));
  return { svc, lines, calls, slot, send, where };
}

const hello = (sid = FIX.sid) => ({ token: TOKEN, key: NONCE, type: 'hello', args: { cur: 0, ver: '0.1.0', sid } });
const part = (name, { z = false, sid = FIX.sid, seq = FIX.seq, value = FIX.parts[name] } = {}) => {
  const json = JSON.stringify(value);
  return { token: TOKEN, key: NONCE, type: 'state', args: { cur: 0, sid, part: name, seq, ...(z ? { z: 1 } : {}) },
    body: z ? zlib.deflateRawSync(Buffer.from(json, 'utf8')).toString('base64') : json };
};
const msg = (n, text, st) => ({ token: TOKEN, key: `${NONCE}_${n}`, type: 'msg', chat: CHAT, args: { cur: 0, ctx: 0, ...(st !== undefined ? { st } : {}) }, text });
const toArr = v => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.keys(v).sort((a, b) => a - b).map(k => v[k]) : []);
const sleep = ms => new Promise(r => setTimeout(r, ms));

for (const z of [false, true]) {
  test(`every fixture part ${z ? 'deflated (z=1)' : 'plain'} is stored and listed in the slot's bridge.state; caps say state and z`, async (t) => {
    const r = rig(t);
    r.send(hello());
    const before = r.slot();
    assert.deepEqual(toArr(before.bridge.caps), [...CAPS]);
    assert.deepEqual(toArr(before.bridge.caps), ['state', 'z']);
    assert.equal(before.bridge.state, undefined, 'nothing held yet');
    const p0 = before.bridge.push;
    r.send(...PARTS.map(p => part(p, { z })));
    const held = r.svc.charState.tokens[TOKEN];
    assert.equal(held.sid, FIX.sid);
    for (const p of PARTS) assert.deepEqual(held.parts[p].value, FIX.parts[p], p);
    const s = r.slot();
    assert.equal(s.bridge.state.sid, FIX.sid);
    assert.deepEqual(s.bridge.state.parts, Object.fromEntries(PARTS.map(p => [p, FIX.seq])));
    assert.ok(s.bridge.push > p0, 'the confirmation rang');
    assert.equal(r.lines.filter(([k]) => k === 'state').length, PARTS.length);
  });
}

test('a new sid clears the parts; an older or the same seq is ignored; a bad part is refused and logged', async (t) => {
  const r = rig(t);
  r.send(hello(), part('char'), part('gear'));
  r.send(part('char', { seq: FIX.seq - 1, value: { v: 1, race: 'Gnome' } }), part('char', { value: { v: 1, race: 'Gnome' } }));
  assert.equal(r.svc.charState.tokens[TOKEN].parts.char.value.race, 'Dwarf');
  r.send(part('char', { seq: FIX.seq + 1, value: { ...FIX.parts.char, level: 16 } }));
  assert.deepEqual(r.slot().bridge.state.parts, { char: FIX.seq + 1, gear: FIX.seq });
  r.send(part('quests', { sid: SID2, seq: 3 }));
  const s = r.slot();
  assert.equal(s.bridge.state.sid, SID2);
  assert.deepEqual(s.bridge.state.parts, { quests: 3 }, 'the old session\'s parts went, though their seq is higher');
  r.send(part('char', { sid: SID2, seq: 4, value: { v: 1, race: 9 } }));
  assert.equal(r.svc.charState.tokens[TOKEN].parts.char, undefined);
  assert.ok(r.lines.some(([k, d]) => k === 'state-rejected' && d.part === 'char' && d.reason === 'field char.race'));
});

test('a hello with a new sid clears the parts held from the old one (a relog); the same sid keeps them (a /reload)', async (t) => {
  const r = rig(t);
  r.send(hello(), part('char'));
  r.send(hello());
  assert.deepEqual(r.slot().bridge.state.parts, { char: FIX.seq });
  r.send(hello(SID2));
  const s = r.slot();
  assert.equal(s.bridge.state.sid, SID2);
  assert.deepEqual(s.bridge.state.parts, {});
});

test('a message and its parts in ONE payload (the message drawn first): the turn sees the character, not stale', async (t) => {
  const r = rig(t);
  r.send(hello());
  r.send(msg(1, 'What race am I?', ALL_ST), ...PARTS.map(p => part(p, { z: p === 'quests' })));
  await sleep(30);
  assert.equal(r.calls.length, 1);
  const { game, history, text } = r.calls[0];
  assert.equal(text, 'What race am I?');
  assert.equal(game.stale, false);
  assert.equal(game.state.char.race, 'Dwarf');
  assert.deepEqual(Object.keys(game.state), PARTS);
  assert.deepEqual(history, []);
});

test('st= empty: the parts held go; no st: no game data, though parts are held; history stays typed text', async (t) => {
  const r = rig(t);
  r.send(hello(), part('char'));
  r.send(msg(1, 'first', ''));
  await sleep(30);
  assert.equal(r.calls[0].game.state.char.level, 15);
  assert.equal(r.calls[0].game.stale, false);
  r.send(msg(2, 'second'));
  await sleep(30);
  assert.deepEqual(r.calls[1].game, { state: null, stale: false });
  assert.deepEqual(r.calls[1].history.map(m => m.content), ['first', 'Aye.']);
});

test('a message whose st= isn\'t met is acked at once with a ring, waits, and runs when its parts come: not stale', async (t) => {
  const r = rig(t, { stateWaitMs: 2000 });
  r.send(hello(), part('char'));
  const p0 = r.slot().bridge.push;
  r.send(msg(1, 'Is this robe good?', `char:${FIX.seq},gear:${FIX.seq}`));
  const s = r.slot();
  assert.deepEqual(toArr(s.bridge.acked), [`${NONCE}_1`], 'acked while it waits');
  assert.ok(s.bridge.push > p0, 'and rung, so the strip frees for the parts');
  assert.equal(toArr(s.chats)[0].busy, true);
  await sleep(50);
  assert.equal(r.calls.length, 0, 'waiting for gear');
  r.send(part('gear'));
  await sleep(30);
  assert.equal(r.calls.length, 1);
  assert.equal(r.calls[0].game.stale, false);
  assert.equal(r.calls[0].game.state.gear.items[0].name, 'Simple Robe of the Monkey');
});

test('a message whose parts never come runs after the wait with stale: true and what is held', async (t) => {
  const r = rig(t, { stateWaitMs: 120 });
  r.send(hello(), part('char'));
  r.send(msg(1, 'Is this robe good?', `char:${FIX.seq},gear:${FIX.seq}`));
  await sleep(40);
  assert.equal(r.calls.length, 0);
  await sleep(200);
  assert.equal(r.calls.length, 1);
  assert.equal(r.calls[0].game.stale, true);
  assert.equal(r.calls[0].game.state.char.race, 'Dwarf');
  assert.equal(r.calls[0].game.state.gear, undefined);
  assert.ok(r.lines.some(([k]) => k === 'state-wait-over'));
});

test('stop while a message waits for its parts: it never runs', async (t) => {
  const r = rig(t, { stateWaitMs: 100 });
  r.send(hello());
  r.send(msg(1, 'wait for me', `char:${FIX.seq}`));
  r.send({ token: TOKEN, key: `${NONCE}_2`, type: 'stop', chat: CHAT, args: { cur: 0 } });
  await sleep(200);
  assert.equal(r.calls.length, 0);
  assert.equal(r.svc.store.outbox.length, 0);
});

test('part=all;off=1 forgets the token\'s state: gone from the slot, the turn and the file', async (t) => {
  const r = rig(t);
  r.send(hello(), ...PARTS.map(p => part(p)));
  assert.ok(r.slot().bridge.state);
  r.send({ token: TOKEN, key: NONCE, type: 'state', args: { cur: 0, part: 'all', off: 1 }, body: '' });
  assert.equal(r.slot().bridge.state, undefined);
  const file = JSON.parse(fs.readFileSync(path.join(r.where.stateDir, STATE_FILE), 'utf8'));
  assert.deepEqual(file.tokens, {});
  r.send(msg(1, 'What race am I?', ''));
  await sleep(30);
  assert.deepEqual(r.calls[0].game, { state: null, stale: false });
  assert.ok(r.lines.some(([k]) => k === 'state-off'));
});

test('the state is on disk: a restart confirms the same parts and the next turn has them', async (t) => {
  const where = dirs(t);
  const one = createService({ addonsDir: where.addonsDir, stateDir: where.stateDir, slotCount: 1, timers: false, turn: async () => ({ text: 'x' }) });
  one.start();
  one.handlePayload([hello(), ...PARTS.map(p => part(p, { z: true }))].map(x => encodeRecord(x)).join(RS));
  one.stop();
  const r = rig(t, { where });
  assert.deepEqual(r.slot().bridge.state.parts, Object.fromEntries(PARTS.map(p => [p, FIX.seq])));
  r.send(msg(1, 'What race am I?', ''));
  await sleep(30);
  assert.equal(r.calls[0].game.state.char.race, 'Dwarf');
});

test('the log has part names and sizes, never their contents', async (t) => {
  const r = rig(t, { stateWaitMs: 50 });
  r.send(hello(), ...PARTS.map(p => part(p, { z: p === 'bags' })));
  r.send(part('char', { seq: FIX.seq + 1, value: { v: 1, race: 42 } })); // refused
  r.send(msg(1, 'What race am I?', ALL_ST));
  r.send(msg(2, 'later', `quests:${FIX.seq + 5}`));
  await sleep(150);
  const text = JSON.stringify(r.lines);
  const secrets = ['Dwarf', 'Rogue', 'Loch Modan', 'Stoutlager', 'Snowbound', 'Simple Robe', 'Hearthstone', 'Ironforge', 'Skinning', 'Malice', 'Jar of Snow', '9851'];
  for (const s of secrets) assert.ok(!text.includes(s), `the log holds "${s}"`);
  const st = r.lines.filter(([k]) => k === 'state').map(([, d]) => d);
  assert.deepEqual(st.map(d => d.part), PARTS);
  for (const d of st) assert.equal(typeof d.bytes, 'number');
});
