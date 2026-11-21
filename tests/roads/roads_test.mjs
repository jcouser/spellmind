// Shared roads (the player, 2026-11-21): the Worker that keeps what the app sends (server/roads/worker.mjs) and
// the weekly merge into roads (tools/roads-merge.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import fengari from 'fengari';
import { handle, checkUpload } from '../../server/roads/worker.mjs';
import { merge, encode, decode, roadsLua, keyDay } from '../../tools/roads-merge.mjs';

const ID = (n) => String(n).padStart(32, 'a').slice(-32).replace(/[^0-9a-f]/g, 'b');
function fakeR2() {
  const m = new Map();
  return {
    m,
    async put(key, body) { m.set(key, { body: String(body), uploaded: new Date('2026-11-21T10:00:00Z'), etag: '"e' + m.size + '"' }); },
    async get(key) { const o = m.get(key); return o ? { body: o.body, httpEtag: o.etag } : null; },
    async list({ prefix = '', cursor } = {}) { return { objects: [...m.keys()].filter(k => k.startsWith(prefix)).sort().map(key => ({ key, uploaded: m.get(key).uploaded })), truncated: false, cursor }; },
    async delete(keys) { for (const k of [].concat(keys)) m.delete(k); },
  };
}
const req = (method, path, body, headers = {}) => new Request('https://roads.example' + path, { method, body: body == null ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)), headers });
// A straight road east: squares X..X+n on row Y, each crossed east.
const road = (X, Y, n, v = 1) => encode(Array.from({ length: n }, (_, i) => ({ X: X + i, Y, v }))).join('');

test('an upload: only squares, under a random id; anything else is refused', () => {
  assert.equal(checkUpload({ v: 1, install: 'x', c: { 0: road(32768, 32768, 3) } }).error, 'install');
  assert.equal(checkUpload({ v: 1, install: ID(1), c: { 0: 'not base64!' } }).error, 'continent 0');
  assert.equal(checkUpload({ v: 1, install: ID(1), c: { 0: 'ABC' } }).error, 'continent 0', 'whole squares only');
  assert.equal(checkUpload({ v: 1, install: ID(1), c: {} }).error, 'empty');
  assert.equal(checkUpload({ v: 1, install: ID(1), name: 'Jaina', c: { 0: road(32768, 32768, 3) } }).upload.name, undefined, 'nothing else kept');
  assert.equal(checkUpload({ v: 1, install: ID(1), c: { 0: road(32768, 32768, 3) } }).squares, 3);
});

test('the Worker keeps uploads, hands out the roads with an ETag, deletes an install\'s uploads, and its admin routes need the token', async () => {
  const env = { ROADS: fakeR2(), ADMIN_TOKEN: 'secret' };
  let r = await handle(req('POST', '/v1/ground', { v: 1, install: ID(1), game: '1.60.1', addon: '0.6.5', c: { 0: road(32768, 32768, 5) } }), env, Date.parse('2026-11-21T10:11:12Z'));
  assert.equal(r.status, 200);
  assert.deepEqual([...env.ROADS.m.keys()], [`up/${ID(1)}/2026-11-21-101112.json`]);
  r = await handle(req('POST', '/v1/ground', 'x'.repeat(600 * 1024)), env);
  assert.equal(r.status, 413);
  r = await handle(req('GET', '/v1/roads'), env);
  assert.equal(r.status, 404, 'no roads yet');
  // Admin: refused without the token.
  r = await handle(req('GET', '/v1/admin/list'), env);
  assert.equal(r.status, 401);
  const auth = { authorization: 'Bearer secret' };
  r = await handle(req('GET', '/v1/admin/list', null, auth), env);
  assert.equal((await r.json()).keys.length, 1);
  r = await handle(req('PUT', '/v1/admin/roads', { v: 1, date: '2026-11-28', players: 3, c: {} }, auth), env);
  assert.equal(r.status, 200);
  r = await handle(req('GET', '/v1/roads'), env);
  assert.equal(r.status, 200);
  const etag = r.headers.get('etag');
  assert.equal((await r.json()).players, 3);
  r = await handle(req('GET', '/v1/roads', null, { 'if-none-match': etag }), env);
  assert.equal(r.status, 304, 'unchanged: not sent again');
  // "Delete what I sent".
  r = await handle(req('DELETE', `/v1/ground/${ID(1)}`), env);
  assert.equal((await r.json()).deleted, 1);
  assert.ok(![...env.ROADS.m.keys()].some(k => k.startsWith('up/')));
});

test('the merge: a crossing is a road once 2 installs walked it; one player\'s path never shows; swum by most, swum', () => {
  const ups = [
    { install: ID(1), c: { 0: road(32768, 32768, 6) } },
    { install: ID(2), c: { 0: road(32768, 32768, 6) } },
    { install: ID(3), c: { 0: road(32768, 32768, 4, 1 + 256) } }, // swam the first 4
    { install: ID(3), c: { 0: road(32768, 32768, 4, 1 + 256) } }, // the same install again counts once
    { install: ID(4), c: { 0: road(40000, 40000, 10) } }, // alone
  ];
  const roads = merge(ups);
  assert.equal(roads.players, 4);
  const sq = decode(roads.c[0].join(''));
  const at = (X, Y) => sq.find(s => s.X === X && s.Y === Y);
  assert.ok(at(32768, 32768) && (at(32768, 32768).v & 1), 'walked east by 3');
  assert.ok(at(32768 + 4, 32768), 'the square crossed into is kept too');
  assert.ok(at(32768 + 5, 32768) && (at(32768 + 5, 32768).v & 1), '2 crossed on from the 5th: enough');
  assert.ok(!sq.some(s => s.X >= 40000), 'one player\'s road: not shown');
  assert.equal(at(32768, 32768).v & 256, 0, 'swum by 1 of 3: not swum');
  // One install alone, never; with a second, shown.
  assert.ok(!merge([{ install: ID(9), c: { 0: road(50000, 50000, 3) } }]).c[0], 'one install: nothing');
  assert.ok(at(32768, 32768).v >= 512, 'counted: 3 players');
  assert.equal(keyDay(`up/${ID(1)}/2026-11-21-101112.json`), '2026-11-21');
});

test('Roads.lua as the release build writes it loads in the game', () => {
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
  const roads = { v: 1, date: '2026-11-28', ...merge([1, 2, 3].map(n => ({ install: ID(n), c: { 0: road(32768, 32768, 6), 1: road(30000, 30000, 3) } })) ) };
  const text = roadsLua(roads);
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  assert.equal(lauxlib.luaL_dostring(L, to_luastring(text + '\nreturn SpellmindRoads.date .. "|" .. SpellmindRoads.players .. "|" .. #SpellmindRoads.c[0][1] .. "|" .. #SpellmindRoads.c[1][1]')), 0);
  assert.equal(to_jsstring(lua.lua_tostring(L, -1)), '2026-11-28|3|56|32', 'each road and the square it runs into');
  assert.match(roadsLua(null), /SpellmindRoads = nil/);
});
