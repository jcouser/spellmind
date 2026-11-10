// The character's state parts (core/link/charstate.mjs): every fixture part validates; malformed
// ones are refused with a reason that names no value; z bodies inflate within their caps; a new sid
// starts over and only a higher seq replaces a part; st= is met or not; charstate.json round-trips (0600).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import {
  PARTS, PART_JSON_MAX, PART_BODY_MAX, validatePart, inflatePart, readStateRecord, mergeInto, parseSt, stReady,
  partSeqs, gameState, loadCharState, saveCharState, STATE_FILE,
} from '../../core/link/charstate.mjs';

const FIX = JSON.parse(fs.readFileSync(new URL('../fixtures/state-parts.json', import.meta.url), 'utf8'));
const z = text => zlib.deflateRawSync(Buffer.from(text, 'utf8')).toString('base64');
const args = (part, extra = {}) => ({ cur: '0', sid: FIX.sid, part, seq: String(FIX.seq), ...extra });

test('every fixture part validates, plain and as an object, and comes back as it was', () => {
  assert.deepEqual(Object.keys(FIX.parts), PARTS);
  for (const p of PARTS) {
    const json = JSON.stringify(FIX.parts[p]);
    const a = validatePart(p, json);
    assert.ok(a.ok, `${p}: ${a.reason}`);
    assert.deepEqual(a.value, FIX.parts[p]);
    assert.ok(validatePart(p, FIX.parts[p]).ok, p);
  }
  assert.ok(validatePart('gear', '{"v":1,"too_large":true}').ok, 'the last resort is a valid part');
});

test('malformed parts are refused, and the reason names a key, never a value', () => {
  const bad = [
    ['nope', '{"v":1}', 'part'],
    ['char', '{"v":1,', 'json'],
    ['char', '[1,2]', 'not an object'],
    ['char', '{"v":2,"race":"Dwarf"}', 'v'],
    ['char', '{"race":"Dwarf"}', 'v'],
    ['char', '{"v":1,"race":7}', 'field char.race'],
    ['char', '{"v":1,"level":"15"}', 'field char.level'],
    ['char', '{"v":1,"loc":{"zone":3}}', 'field char.loc'],
    ['gear', JSON.stringify({ v: 1, items: Array.from({ length: 20 }, (_, i) => ({ slot: 1, id: i })) }), 'field gear.items'],
    ['gear', '{"v":1,"items":[{"slot":1,"q":9}]}', 'field gear.items'],
    ['bags', JSON.stringify({ v: 1, items: Array.from({ length: 41 }, (_, i) => ({ id: i })) }), 'field bags.items'],
    ['quests', '{"v":1,"list":[{"id":1,"obj":[{},{},{},{},{},{}]}]}', 'field quests.list'],
    ['rep', '{"v":1,"list":[{"id":1,"r":9}]}', 'field rep.list'],
    ['talents', JSON.stringify({ v: 1, nodes: Array.from({ length: 61 }, (_, i) => ({ id: i })) }), 'field talents.nodes'],
    ['stats', '{"v":1,"res":{"fire":"hot"}}', 'field stats.res'],
    ['char', '{"v":1,"omitted":[1]}', 'field omitted'],
    ['char', JSON.stringify({ v: 1, class: 'x'.repeat(PART_JSON_MAX) }), 'too large'],
  ];
  for (const [part, json, reason] of bad) {
    const r = validatePart(part, json);
    assert.equal(r.ok, false, `${part} ${json.slice(0, 40)}`);
    assert.equal(r.reason, reason, `${part} ${json.slice(0, 40)}`);
  }
});

test('z bodies: raw deflate in base64 inflates; too long a body, too big a JSON or not deflate is refused', () => {
  const json = JSON.stringify(FIX.parts.quests);
  assert.deepEqual(inflatePart(z(json)), { ok: true, text: json });
  assert.equal(inflatePart('not base64 !').ok, false);
  assert.equal(inflatePart(Buffer.from('plain text').toString('base64')).reason, 'z: not deflate');
  const big = z(JSON.stringify({ v: 1, pad: 'a'.repeat(PART_JSON_MAX + 10) })); // small packed, big inflated
  assert.ok(big.length <= PART_BODY_MAX);
  assert.equal(inflatePart(big).reason, 'z: too large');
  const random = Buffer.from(Array.from({ length: 4000 }, (_, i) => (i * 7919) % 251)).toString('base64');
  assert.ok(random.length > PART_BODY_MAX);
  assert.equal(inflatePart(random).reason, 'z: too large');
});

test('readStateRecord: plain and z parts; off=1 for part=all; a bad sid, part or seq is refused', () => {
  for (const p of PARTS) {
    const json = JSON.stringify(FIX.parts[p]);
    const plain = readStateRecord(args(p), json);
    assert.ok(plain.ok, `${p}: ${plain.reason}`);
    assert.equal(plain.part, p);
    assert.equal(plain.seq, FIX.seq);
    assert.equal(plain.bytes, Buffer.byteLength(json));
    const zz = readStateRecord(args(p, { z: '1' }), z(json));
    assert.ok(zz.ok && zz.z, `${p} z: ${zz.reason}`);
    assert.deepEqual(zz.value, plain.value);
  }
  assert.deepEqual(readStateRecord({ cur: '0', part: 'all', off: '1' }, ''), { ok: true, off: true });
  assert.equal(readStateRecord({ cur: '0', part: 'char', off: '1' }, '').ok, false);
  assert.equal(readStateRecord(args('char', { sid: 'XYZ' }), '{"v":1}').reason, 'sid');
  assert.equal(readStateRecord(args('char', { sid: undefined }), '{"v":1}').reason, 'sid');
  assert.equal(readStateRecord(args('mount'), '{"v":1}').reason, 'part');
  assert.equal(readStateRecord(args('char', { seq: '-1' }), '{"v":1}').reason, 'seq');
  assert.equal(readStateRecord(args('char', { seq: 'x' }), '{"v":1}').reason, 'seq');
  assert.equal(readStateRecord(args('char', { z: '1' }), '{"v":1}').reason, 'z: not base64');
});

test('mergeInto: the first part, a higher seq replaces, the same or a lower is kept out, a new sid starts over', () => {
  const sid2 = 'aaaaaaaaaaaaaaaa';
  let m = mergeInto(null, { sid: FIX.sid, part: 'char', seq: 7, value: { v: 1, level: 15 } });
  assert.equal(m.changed, true);
  assert.equal(m.reset, false);
  m = mergeInto(m.stored, { sid: FIX.sid, part: 'gear', seq: 7, value: { v: 1 } });
  assert.deepEqual(partSeqs(m.stored), { char: 7, gear: 7 });
  const before = m.stored;
  for (const seq of [7, 6]) {
    const same = mergeInto(before, { sid: FIX.sid, part: 'char', seq, value: { v: 1, level: 99 } });
    assert.equal(same.changed, false, `seq ${seq}`);
    assert.equal(same.stored, before);
  }
  m = mergeInto(before, { sid: FIX.sid, part: 'char', seq: 8, value: { v: 1, level: 16 } });
  assert.equal(m.changed, true);
  assert.equal(m.stored.parts.char.value.level, 16);
  assert.equal(before.parts.char.value.level, 15, 'pure: the old object is untouched');
  const fresh = mergeInto(m.stored, { sid: sid2, part: 'quests', seq: 2, value: { v: 1 } });
  assert.equal(fresh.reset, true);
  assert.deepEqual(partSeqs(fresh.stored), { quests: 2 }, 'a new sid clears the old parts, whatever their seq');
  assert.equal(fresh.stored.sid, sid2);
});

test('parseSt and stReady: empty means ready; each named part at its seq or later', () => {
  assert.deepEqual(parseSt('char:41,gear:39'), [{ part: 'char', seq: 41 }, { part: 'gear', seq: 39 }]);
  assert.deepEqual(parseSt('char:41,bogus:2,gear:x,,quests:3'), [{ part: 'char', seq: 41 }, { part: 'quests', seq: 3 }]);
  const stored = { sid: FIX.sid, parts: { char: { seq: 41, value: {} }, gear: { seq: 38, value: {} } } };
  assert.equal(stReady('', stored), true);
  assert.equal(stReady('', null), true);
  assert.equal(stReady('char:41', stored), true);
  assert.equal(stReady('char:40', stored), true);
  assert.equal(stReady('char:41,gear:39', stored), false);
  assert.equal(stReady('quests:1', stored), false);
  assert.equal(stReady('char:1', null), false);
});

test('gameState: the parts held in contract order, or null', () => {
  assert.equal(gameState(null), null);
  assert.equal(gameState({ sid: FIX.sid, parts: {} }), null);
  const g = gameState({ sid: FIX.sid, parts: { rep: { seq: 1, value: FIX.parts.rep }, char: { seq: 1, value: FIX.parts.char } } });
  assert.deepEqual(Object.keys(g), ['char', 'rep']);
  assert.equal(g.char.race, 'Dwarf');
});

test('charstate.json: saved owner-only and loaded back; bad entries and a broken file are left out', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-charstate-'));
  try {
    assert.deepEqual(loadCharState(dir), { tokens: {} }, 'no file');
    const data = { tokens: { '3fa9c2d1': { sid: FIX.sid, parts: Object.fromEntries(PARTS.map(p => [p, { seq: FIX.seq, value: FIX.parts[p] }])) } } };
    saveCharState(dir, data);
    const file = path.join(dir, STATE_FILE);
    if (process.platform !== 'win32') assert.equal(fs.statSync(file).mode & 0o777, 0o600);
    assert.deepEqual(loadCharState(dir), data);
    const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
    raw.tokens['3fa9c2d1'].parts.char.value = { v: 1, race: 5 };
    raw.tokens['3fa9c2d1'].parts.bogus = { seq: 1, value: { v: 1 } };
    raw.tokens.NOTATOKEN = { sid: FIX.sid, parts: {} };
    raw.tokens['00000000'] = { sid: 'short', parts: {} };
    fs.writeFileSync(file, JSON.stringify(raw));
    const back = loadCharState(dir);
    assert.deepEqual(Object.keys(back.tokens), ['3fa9c2d1']);
    assert.deepEqual(Object.keys(back.tokens['3fa9c2d1'].parts), PARTS.filter(p => p !== 'char'));
    fs.writeFileSync(file, '{broken');
    assert.deepEqual(loadCharState(dir), { tokens: {} });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
