// The addon's record encoding (Link.lua L.Record and Core.lua's helpers) against the bridge's
// (core/link/records.mjs) on the shared vectors (tests/fixtures/protocol-v2.json): byte for byte.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodeRecord, encodeArg, decodeArg, cleanField, parseRecord } from '../../core/link/records.mjs';
import { newVM, lstr } from '../helpers/addon-vm.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const V = JSON.parse(fs.readFileSync(path.join(HERE, '..', 'fixtures', 'protocol-v2.json'), 'utf8'));

// A Lua args list ({ { name, value }, ... }) in the vector's order.
const luaArgs = args => `{ ${Object.entries(args).map(([k, v]) => `{ ${lstr(k)}, ${lstr(v)} }`).join(', ')} }`;

function vectorVM(token) {
  const vm = newVM({ db: `SpellmindDB = { token = "${token}" }` }).login();
  return vm;
}

test('Lua records: every shared vector encodes byte for byte as encodeRecord does (and as the vector\'s wire)', () => {
  for (const r of V.records) {
    const p = r.parsed;
    const vm = vectorVM(p.token);
    const lua = vm.bytesOf(`NS.Link.Record(${lstr(p.key)}, ${lstr(p.type)}, ${lstr(p.chat)}, ${luaArgs(p.args)}, ${lstr(p.body)})`);
    const js = Buffer.from(encodeRecord({ token: p.token, key: p.key, type: p.type, chat: p.chat, args: p.args, body: p.body }), 'utf8');
    assert.deepEqual(lua, js, r.name);
    assert.deepEqual(lua, Buffer.from(r.wire, 'utf8'), `${r.name}: the vector's wire`);
  }
});

test('Lua records: numbers go as whole numbers, the cursor first; ParseRecord reads back what Record wrote', () => {
  const vm = vectorVM('3fa9c2d1');
  const wire = vm.bytesOf('NS.Link.Record("a3f1_7", "msg", "c3f9a1e", { { "cur", 12.0 }, { "agent", "main" }, { "ctx", 0 } }, "hi")').toString('utf8');
  assert.equal(wire, encodeRecord({ token: '3fa9c2d1', key: 'a3f1_7', type: 'msg', chat: 'c3f9a1e', args: { cur: 12, agent: 'main', ctx: 0 }, body: 'hi' }));
  const back = vm.json(`NS.Link.ParseRecord(${lstr(wire)})`);
  assert.deepEqual(back, { token: '3fa9c2d1', key: 'a3f1_7', type: 'msg', chat: 'c3f9a1e', args: { cur: '12', agent: 'main', ctx: '0' }, body: 'hi' });
  assert.equal(parseRecord(wire).ok, true);
});

test('Lua args: percent-encoding matches encodeArg for every ASCII byte and multibyte text, and decodes back', () => {
  const vm = vectorVM('3fa9c2d1');
  const all = Array.from({ length: 128 }, (_, i) => String.fromCharCode(i)).join('');
  for (const s of [all, '50% off; a=b', 'héllo wörld ✓ — %41', '', '%%3B;;==']) {
    assert.deepEqual(vm.bytesOf(`NS.EncodeArg(${lstr(s)})`), Buffer.from(encodeArg(s), 'utf8'), JSON.stringify(s));
    assert.deepEqual(vm.bytesOf(`NS.DecodeArg(NS.EncodeArg(${lstr(s)}))`), Buffer.from(s, 'utf8'), `round trip ${JSON.stringify(s)}`);
    assert.deepEqual(vm.bytesOf(`NS.DecodeArg(${lstr(encodeArg(s))})`), Buffer.from(decodeArg(encodeArg(s)), 'utf8'));
  }
});

test('Lua fields: bytes 0x1D-0x1F in user text become spaces, as cleanField does; nothing else changes', () => {
  const vm = vectorVM('3fa9c2d1');
  const s = 'a\x1db\x1ec\x1fd\x1ce\x20f\x01 ✓';
  assert.deepEqual(vm.bytesOf(`NS.CleanField(${lstr(s)})`), Buffer.from(cleanField(s), 'utf8'));
  assert.equal(cleanField(s), 'a b c d\x1ce f\x01 ✓');
});

test('Lua ids: a token is 8 lowercase hex, a nonce 4, a chat id c + 6, and saved data keeps them', () => {
  const vm = newVM().login();
  assert.match(vm.evaluate('SpellmindDB.token'), /^[0-9a-f]{8}$/);
  assert.match(vm.evaluate('NS.R.nonce'), /^[0-9a-f]{4}$/);
  assert.match(vm.evaluate('SpellmindDB.chat'), /^c[0-9a-f]{6}$/);
  assert.match(vm.evaluate('NS.NewToken()'), /^[0-9a-f]{8}$/);
  assert.match(vm.evaluate('NS.NewChatId()'), /^c[0-9a-f]{6}$/);
  assert.deepEqual(vm.list('SpellmindDB.nonces'), [vm.evaluate('NS.R.nonce')]);
  const bad = newVM({ db: 'SpellmindDB = { token = "XYZ", chat = "nope", sendCounter = -4, cursor = "7", reported = 9, outbox = { { key = 1 }, { key = "k", hex = "zz" } } }' }).login();
  assert.match(bad.evaluate('SpellmindDB.token'), /^[0-9a-f]{8}$/);
  assert.match(bad.evaluate('SpellmindDB.chat'), /^c[0-9a-f]{6}$/);
  assert.equal(bad.num('SpellmindDB.sendCounter'), 0);
  assert.equal(bad.num('SpellmindDB.cursor'), 7);
  assert.equal(bad.num('SpellmindDB.reported'), 7, 'never above the cursor');
  assert.equal(bad.num('#SpellmindDB.outbox'), 0, 'entries that can\'t be drawn verbatim go');
});
