// Milestone 4's addon side (docs/milestone-4.md): State.lua in the VM on the WoW stub's level-15
// Dwarf rogue. Each part it builds is tests/fixtures/state-parts.json's; the parts come off the
// strip through the bridge's own decoder and parser (core/link/strip.mjs, records.mjs, z=1 bodies
// through inflateBody); only what changed goes again; a /reload keeps the sid and sends nothing, a
// login draws a new one and sends everything; trims; the caps; st on the message; privacy; /sm data.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { newVM, reloadVM } from '../helpers/addon-vm.mjs';
import { findAndDecode } from '../../core/link/strip.mjs';
import { parsePayload, inflateBody } from '../../core/link/records.mjs';
import { slotTable } from '../../core/link/luaenc.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE = JSON.parse(fs.readFileSync(path.join(HERE, '..', 'fixtures', 'state-parts.json'), 'utf8'));
const PARTS = ['char', 'stats', 'talents', 'gear', 'bags', 'skills', 'quests', 'rep'];
const LIMITS = { maxBody: 2900, maxText: 8000 };

// Saved data as an install that has sent six builds before (the fixture's parts are seq 7).
const DB = 'SpellmindDB = { stateSeq = 6 }';

function session(opts = {}) {
  return newVM({ db: DB, ...opts }).login().advance(3.1);
}

function stripText(vm) {
  const img = vm.screen();
  if (!img) return null;
  const r = findAndDecode(img);
  assert.equal(r.kind, 'decoded', `strip ${r.kind} ${r.reason || ''}`);
  return r.text;
}

function stripRecords(vm) {
  const text = stripText(vm);
  if (text === null) return [];
  const { records, rejected } = parsePayload(text);
  assert.equal(rejected.length, 0, JSON.stringify(rejected));
  return records;
}

// The state records on the strip, each with its part's JSON read back.
function stateRecords(vm) {
  return stripRecords(vm).filter(r => r.type === 'state').map(r => {
    let json = r.body;
    if (r.args.z === '1') {
      const inf = inflateBody(r.body, LIMITS);
      assert.ok(inf.ok, inf.reason);
      json = inf.text;
    }
    assert.ok(r.body.length <= 2900, `${r.args.part}: ${r.body.length} bytes on the strip`);
    return { ...r, json, part: r.args.part === 'all' ? null : JSON.parse(json) };
  });
}

// A slot from the app (luaenc slotTable) answering this session's hello, loaded.
function answer(vm, { caps = ['state', 'z'], state, acked = [], records = [] } = {}) {
  vm.push = (vm.push || 0) + 1;
  const bridge = { ver: '0.1.0', push: vm.push, nonce: vm.evaluate('NS.R.nonce'), acked, caps };
  if (state) bridge.state = state;
  const slot = { ts: '2026-11-10T12:00:00Z', now: vm.num('time()'), token: vm.evaluate('SpellmindDB.token'), bridge,
    gw: { state: 'ready', since: 0, queued: 0 }, agents: [{ id: 'main', name: 'Spellmind' }], chats: [], records };
  vm.slotText(slotTable('SpellmindSlotData', slot).text);
  vm.run('NS.Link.LoadSlot("push")'); // as a push ring does (without its 1.5 s spacing)
  return vm;
}

const sid = vm => vm.evaluate('NS.State.Sid()');
// What this character's saved data says was sent: { part: { seq, ok } }.
const sent = vm => vm.json('SpellmindDB.chars[NS.State.Key()].parts');
const seqs = vm => Object.fromEntries(Object.entries(sent(vm)).map(([p, r]) => [p, r.seq]));
// The app has everything that was sent.
const confirmAll = (vm, caps) => answer(vm, { caps, state: { sid: sid(vm), parts: seqs(vm) } });

// Every part off the strip, frame by frame: what's drawn is confirmed, so the rest follows.
function drain(vm, caps) {
  const got = {};
  for (let i = 0; i < 10; i++) {
    const recs = stateRecords(vm);
    if (recs.length === 0) break;
    for (const r of recs) got[r.args.part] = r;
    answer(vm, { caps, state: { sid: sid(vm), parts: Object.fromEntries(Object.values(got).map(r => [r.args.part, Number(r.args.seq)])) } });
  }
  return got;
}

test('each part State.lua builds from the stub is the fixture\'s, byte for byte (keys in the contract\'s order), deflated or not', () => {
  const vm = newVM().login();
  for (const z of [true, false]) {
    for (const p of PARTS) {
      const json = vm.evaluate(`(NS.State.Part("${p}", ${z}))`);
      assert.equal(json, JSON.stringify(FIXTURE.parts[p]), `${p} (z ${z})`);
      assert.deepEqual(JSON.parse(json), FIXTURE.parts[p]);
    }
  }
  assert.deepEqual(vm.json('STUB.questHeaders'), {}, 'no quest header was opened or closed');
  assert.deepEqual(vm.json('STUB.identityCalls'), {}, 'name, realm and guild never read');
});

test('after the hello is answered with caps state and z, all eight parts come off the strip: z=1 bodies inflate to the fixture, one seq, the hello\'s sid', () => {
  const vm = session();
  const hello = stripRecords(vm).find(r => r.type === 'hello');
  assert.match(hello.args.sid, /^[0-9a-f]{16}$/);
  assert.equal(stateRecords(vm).length, 0, 'nothing before the app is heard (no caps yet)');
  answer(vm);
  const first = stateRecords(vm);
  assert.ok(first.length > 0);
  assert.deepEqual(first.map(r => r.args.part), PARTS.filter(p => first.some(r => r.args.part === p)), 'drawn in part order');
  const got = drain(vm);
  assert.deepEqual(Object.keys(got).sort(), [...PARTS].sort());
  for (const p of PARTS) {
    const r = got[p];
    assert.deepEqual(r.part, FIXTURE.parts[p], p);
    assert.equal(r.json, JSON.stringify(FIXTURE.parts[p]), `${p}: the same bytes`);
    assert.equal(r.args.z, '1', `${p} deflated`);
    assert.deepEqual(Object.keys(r.args), ['cur', 'sid', 'part', 'seq', 'z'], 'the contract\'s args order');
    assert.equal(r.args.sid, hello.args.sid);
    assert.equal(r.args.seq, '7', 'one new seq for the build');
    assert.equal(r.key, hello.key, 'unkeyed: the key is the nonce');
    assert.equal(r.chat, '');
  }
  assert.equal(vm.num('SpellmindDB.stateSeq'), 7);
  assert.equal(stateRecords(vm).length, 0, 'all confirmed: none left on the strip');
  assert.deepEqual(vm.json('NS.R.stateErr'), {}, 'no part failed');
});

test('a part leaves the strip only when bridge.state has its seq, or a later one, under the same sid', () => {
  const vm = session();
  answer(vm);
  const all = seqs(vm);
  assert.equal(Object.keys(all).length, 8);
  answer(vm, { state: { sid: '0123456789abcdef', parts: all } });
  assert.equal(stateRecords(vm).length > 0, true, 'another sid confirms nothing');
  answer(vm, { state: { sid: sid(vm), parts: { char: all.char - 1 } } });
  assert.ok(Object.values(sent(vm)).every(r => !r.ok), 'an older seq confirms nothing');
  answer(vm, { state: { sid: sid(vm), parts: { char: all.char, stats: all.stats + 5 } } });
  const ok = Object.entries(sent(vm)).filter(([, r]) => r.ok).map(([p]) => p).sort();
  assert.deepEqual(ok, ['char', 'stats']);
  assert.ok(!stateRecords(vm).some(r => r.args.part === 'char' || r.args.part === 'stats'));
});

test('only changed parts go again: an equip change sends gear alone, with a new seq; events coalesce into one build per 2 s, none in combat', () => {
  const vm = session();
  answer(vm);
  confirmAll(vm);
  assert.equal(stateRecords(vm).length, 0);
  vm.run('STUB.equipped[1] = { id = 2140, link = STUB.ItemLink(2140), dur = { 30, 30 } }');
  vm.run('STUB.FireEvent("PLAYER_EQUIPMENT_CHANGED", 1, false); STUB.FireEvent("UNIT_INVENTORY_CHANGED", "player"); STUB.FireEvent("BAG_UPDATE_DELAYED")');
  vm.advance(1.5);
  assert.equal(stateRecords(vm).length, 0, 'not yet: builds wait 2 s');
  vm.advance(0.6);
  const recs = stateRecords(vm);
  assert.deepEqual(recs.map(r => r.args.part), ['gear']);
  assert.equal(recs[0].args.seq, '8');
  assert.equal(recs[0].part.items[0].name, 'Fine Longsword');
  assert.deepEqual(recs[0].part.empty, FIXTURE.parts.gear.empty.filter(s => s !== 1));
  confirmAll(vm);
  // In combat a build waits for the fight to end.
  vm.run('STUB.combat = true; STUB.player.money = 10000; STUB.FireEvent("PLAYER_MONEY")');
  vm.advance(3);
  assert.equal(stateRecords(vm).length, 0, 'nothing built in combat');
  vm.run('STUB.combat = false; STUB.FireEvent("PLAYER_REGEN_ENABLED")');
  const after = stateRecords(vm);
  assert.deepEqual(after.map(r => r.args.part), ['char']);
  assert.equal(after[0].part.money, 10000);
  assert.equal(after[0].args.seq, '9');
});

test('a /reload keeps the sid and sends nothing; a new login draws a new sid and every part goes again; an app that lost them gets the full set', () => {
  const vm = session();
  answer(vm);
  confirmAll(vm);
  const before = { sid: sid(vm), seqs: seqs(vm) };
  const state = { sid: before.sid, parts: before.seqs };

  const r1 = reloadVM(vm).login().advance(3.1);
  const hello = stripRecords(r1).find(r => r.type === 'hello');
  assert.equal(hello.args.sid, before.sid, '/reload keeps the sid');
  assert.equal(stateRecords(r1).length, 0);
  answer(r1, { state });
  assert.equal(stateRecords(r1).length, 0, 'the app has every part: nothing goes');
  assert.deepEqual(seqs(r1), before.seqs, 'no new seq');

  // The same /reload, but the app lost the character (bridge.state without it): the full set, once.
  const r2 = reloadVM(vm).login().advance(3.1);
  answer(r2, { state: { sid: before.sid, parts: {} } });
  assert.ok(stateRecords(r2).length > 0, 'parts go again');
  const again = drain(r2);
  assert.deepEqual(Object.keys(again).sort(), [...PARTS].sort());
  assert.ok(Object.values(again).every(r => r.args.seq === String(before.seqs[r.args.part])), 'the same seqs');

  // A login (or a relog after a crash): a new sid, everything again under it with a new seq.
  const l = reloadVM(vm).login({ initial: true }).advance(3.1);
  const h2 = stripRecords(l).find(r => r.type === 'hello');
  assert.notEqual(h2.args.sid, before.sid);
  answer(l, { state });
  const fresh = drain(l);
  assert.deepEqual(Object.keys(fresh).sort(), [...PARTS].sort());
  for (const r of Object.values(fresh)) {
    assert.equal(r.args.sid, h2.args.sid);
    assert.equal(Number(r.args.seq), Math.max(...Object.values(before.seqs)) + 1);
  }
});

test('a part over its limit runs its own trims, named in omitted: quests drop obj.text then obj, bags drop items from the end, gear drops st; last, too_large', () => {
  const vm = newVM().login();
  const long = 'An objective with a long, long name that goes on and on and on';
  vm.run(`
    STUB.quests, STUB.objectives = {}, {}
    for i = 1, 25 do
      STUB.quests[i] = { title = "A quest with quite a long title, number " .. i, questID = 5000 + i, level = 15 }
      local objs = {}
      for j = 1, 8 do objs[j] = { text = "${long} " .. j .. ": 0/5", numFulfilled = 0, numRequired = 5 } end
      STUB.objectives[5000 + i] = objs
    end`);
  const part = (p, z) => JSON.parse(vm.evaluate(`(NS.State.Part("${p}", ${z}))`));
  const body = (p, z) => vm.evaluate(`(select(2, NS.State.Part("${p}", ${z})))`);
  let q = part('quests', false);
  assert.deepEqual(q.omitted, ['obj.text', 'obj']);
  assert.equal(q.list.length, 25);
  assert.ok(q.list.every(x => x.obj === undefined));
  assert.ok(body('quests', false).length <= 2900);
  q = part('quests', true);
  assert.ok(q.omitted.length >= 1 && q.omitted[0] === 'obj.text', JSON.stringify(q.omitted));
  assert.ok(body('quests', true).length <= 2900);

  vm.run(`
    STUB.bags[0].items = {}
    STUB.bags[0].size = 16
    for b = 1, 4 do STUB.bags[b].size = 16; STUB.bags[b].items = {} end
    local n = 0
    for b = 0, 4 do
      for s = 1, 10 do
        n = n + 1
        local id = 70000 + n
        STUB.items[id] = { "A trade good with a long name, number " .. n, 1, 5, 0, "Trade Goods", "Cloth", 20, "", 1, 5, 7, 5 }
        STUB.bags[b].items[s] = { id, n }
      end
    end`);
  const bags = part('bags', false);
  assert.deepEqual(bags.omitted, ['items']);
  assert.ok(bags.items.length < 40 && bags.items.length > 0);
  assert.equal(bags.items.length + bags.more, 50, 'more counts the capped and the trimmed');
  assert.equal(bags.items[0].name, 'A trade good with a long name, number 1', 'in bag order: trimmed from the end');
  assert.ok(body('bags', false).length <= 2900);

  vm.run(`
    for slot = 1, 19 do
      local id = 80000 + slot
      STUB.items[id] = { "An item with a very long name that fills its sixty bytes, " .. slot, 4, 60, 60, "Armor", "Plate", 1, "INVTYPE_CHEST", 1, 1, 4, 4 }
      STUB.itemStats[id] = { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_AGILITY_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 20, ITEM_MOD_INTELLECT_SHORT = 20,
        ITEM_MOD_SPIRIT_SHORT = 20, RESISTANCE0_NAME = 900, ITEM_MOD_ATTACK_POWER_SHORT = 40, ITEM_MOD_CRIT_RATING_SHORT = 14,
        ITEM_MOD_HIT_RATING_SHORT = 10, RESISTANCE2_NAME = 10, RESISTANCE3_NAME = 10, RESISTANCE4_NAME = 10, RESISTANCE5_NAME = 10 }
      STUB.equipped[slot] = { id = id, link = STUB.ItemLink(id, 2564), dur = { 100, 100 } }
    end`);
  const gear = part('gear', false);
  assert.deepEqual(gear.omitted, ['st']);
  assert.ok(gear.items.every(i => i.st === undefined && i.ench === 2564));
  assert.equal(part('gear', true).omitted, undefined, 'deflated, it fits whole');

  // rep has no trims of its own.
  vm.run(`
    STUB.factions = {}
    for i = 1, 200 do STUB.factions[i] = { factionID = i, name = "A faction with a long name that fills it up " .. i, reaction = 4,
      currentStanding = 10, currentReactionThreshold = 0, nextReactionThreshold = 3000 } end`);
  assert.deepEqual(part('rep', false), { v: 1, too_large: true });
});

test('bags: merged by id; worn items of quality 2 and up first, then quest items, then quality 2 and up, then the rest; junk only summed', () => {
  const vm = newVM().login();
  vm.run(`
    STUB.items[12000] = { "A Quest Thing", 1, 1, 0, "Quest", "Quest", 1, "", 1, 0, 12, 0 }
    STUB.items[12001] = { "Green Boots", 2, 18, 13, "Armor", "Leather", 1, "INVTYPE_FEET", 1, 200, 4, 2 }
    STUB.items[12002] = { "Green Ore", 2, 20, 0, "Trade Goods", "Metal", 20, "", 1, 50, 7, 7 }
    STUB.bags[2].items = { { 12002, 3 }, { 12000, 1 }, { 12001, 1 } }`);
  const bags = JSON.parse(vm.evaluate('(NS.State.Part("bags", true))'));
  assert.deepEqual(bags.items.slice(0, 3).map(i => i.name), ['Green Boots', 'A Quest Thing', 'Green Ore']);
  assert.deepEqual(bags.items[0], { id: 12001, name: 'Green Boots', q: 2, n: 1, ilvl: 18, equip: 'INVTYPE_FEET' });
  assert.equal(bags.items.find(i => i.id === 2318).n, 20, 'two stacks of Light Leather, merged');
  assert.deepEqual(bags.junk, { n: 3, copper: 145 });
  assert.ok(!bags.items.some(i => i.q === 0));
});

test('without the z cap the bodies are plain JSON (no z=); without the state cap nothing is built or sent and a message has no st', () => {
  const vm = session();
  answer(vm, { caps: ['state'] });
  const got = drain(vm, ['state']);
  assert.deepEqual(Object.keys(got).sort(), [...PARTS].sort());
  for (const r of Object.values(got)) {
    assert.equal(r.args.z, undefined);
    assert.equal(r.body, JSON.stringify(FIXTURE.parts[r.args.part]));
  }

  const old = session();
  answer(old, { caps: [] });
  assert.equal(stateRecords(old).length, 0);
  old.slash('What race am I?');
  const m = stripRecords(old).find(r => r.type === 'msg');
  assert.deepEqual(m.args, { cur: '0', agent: 'main', ctx: '0' }, 'no st: no game data');
  assert.equal(stateRecords(old).length, 0);
  assert.equal(old.num('SpellmindDB.stateSeq'), 6, 'nothing was built');
});

test('a message carries st: the parts the app hasn\'t confirmed, as part:seq, or empty when it has them all; the state is built first, in the same draw', () => {
  const vm = session();
  answer(vm);
  vm.slash('What race am I?');
  let m = stripRecords(vm).find(r => r.type === 'msg');
  assert.equal(m.args.st, PARTS.map(p => `${p}:7`).join(','));
  assert.deepEqual(Object.keys(m.args), ['cur', 'agent', 'ctx', 'st']);
  confirmAll(vm);
  // A change no event announced: the send builds it, and the message and the part go in one frame.
  vm.run('STUB.player.xp = 3000');
  const frame = vm.num('NS.R.frame');
  vm.slash('And my level?');
  assert.equal(vm.num('NS.R.frame'), frame + 1, 'one draw');
  const recs = stripRecords(vm);
  m = recs.find(r => r.type === 'msg' && r.text === 'And my level?');
  assert.equal(m.args.st, 'char:8');
  assert.deepEqual(recs.filter(r => r.type === 'state').map(r => r.args.part), ['char']);
  confirmAll(vm);
  vm.slash('Thanks');
  m = stripRecords(vm).find(r => r.type === 'msg' && r.text === 'Thanks');
  assert.equal(m.args.st, '', 'the app has them all');
});

test('a state part that doesn\'t fit beside a long message is skipped, not a stop: smaller parts after it still go', () => {
  const vm = session();
  answer(vm, { caps: ['state'] });
  confirmAll(vm, ['state']);
  // The quest log (about 1 KB) and the reputation (about 300 bytes) change; a long message takes most of the frame.
  vm.run('STUB.quests[2].level = 11; STUB.factions[2].currentStanding = 3600');
  vm.slash('x'.repeat(2400));
  const drawn = stateRecords(vm).map(r => r.args.part);
  assert.ok(stripRecords(vm).some(r => r.type === 'msg'), 'the message is drawn');
  assert.deepEqual(drawn, ['rep'], 'quests waits; rep, after it, goes');
  assert.ok(stripText(vm).length <= 3200);
  answer(vm, { caps: ['state'], acked: [vm.outbox()[0].key] });
  assert.deepEqual(stateRecords(vm).map(r => r.args.part), ['quests', 'rep'], 'the message acked: quests fits now');
});

test('privacy: the name, realm and guild are never read and never on the strip; the saved data keys the character by a hash, not its name', () => {
  const vm = session();
  answer(vm);
  vm.slash('Who am I?');
  const text = stripText(vm) + Object.values(drain(vm)).map(r => r.json).join('');
  for (const s of ['Testchar', 'Test Realm', 'Test Guild', 'TestRealm', 'Player-4372']) assert.ok(!text.includes(s), s);
  assert.deepEqual(vm.json('STUB.identityCalls'), {});
  const saved = vm.saved();
  assert.ok(!saved.includes('Testchar') && !saved.includes('Player-4372'), 'nor in SpellmindDB');
  assert.match(vm.evaluate('NS.State.Key()'), /^g[0-9a-f]{8}$/);
  assert.deepEqual(vm.json('SpellmindDB.share'), { state: true, identity: false });
});

test('/sm data shows each part\'s size and whether the app has it; /sm data off makes the app forget (part=all;off=1) and stops; /sm data on sends everything again', () => {
  const vm = session();
  vm.slash('data');
  assert.ok(vm.chatLines().some(l => /hasn't been heard from yet/.test(l)), JSON.stringify(vm.chatLines()));
  answer(vm);
  confirmAll(vm);
  vm.run('STUB.player.money = 20000');
  vm.slash('data');
  const lines = vm.chatLines();
  const sizes = Object.fromEntries(PARTS.map(p => [p, lines.find(l => l.startsWith(`Spellmind: ${p}: `))]));
  for (const p of PARTS) {
    const bytes = JSON.stringify(FIXTURE.parts[p]).length;
    const shown = bytes >= 1000 ? `${Math.floor(bytes / 1000)},${String(bytes % 1000).padStart(3, '0')}` : String(bytes);
    if (p === 'char') assert.match(sizes[p], /bytes \(\d+ compressed\), on its way$/, 'the money changed: built again, not confirmed');
    else assert.match(sizes[p], new RegExp(`^Spellmind: ${p}: ${shown} bytes \\(\\d+ compressed\\), the app has it$`), sizes[p]);
  }

  vm.slash('data off');
  assert.equal(vm.bool('SpellmindDB.share.state'), false);
  let recs = stateRecords(vm);
  assert.deepEqual(recs.map(r => [r.args.part, r.args.off, r.body]), [['all', '1', '']]);
  assert.equal(recs[0].args.sid, sid(vm));
  vm.slash('Still there?');
  const m = stripRecords(vm).find(r => r.type === 'msg');
  assert.equal(m.args.st, undefined, 'no game data');
  answer(vm, { state: { sid: sid(vm), parts: {} } });
  assert.equal(stateRecords(vm).length, 0, 'the app forgot it: the record is done');
  vm.run('STUB.player.money = 30000; STUB.FireEvent("PLAYER_MONEY")');
  vm.advance(2.5);
  assert.equal(stateRecords(vm).length, 0, 'nothing goes while it\'s off');
  vm.slash('data');
  assert.ok(vm.chatLines().some(l => /Game data is off/.test(l)));

  const seqBefore = vm.num('SpellmindDB.stateSeq');
  vm.slash('data on');
  const back = drain(vm);
  assert.deepEqual(Object.keys(back).sort(), [...PARTS].sort());
  assert.ok(Object.values(back).every(r => Number(r.args.seq) === seqBefore + 1));
  assert.equal(back.char.part.money, 30000);
});
