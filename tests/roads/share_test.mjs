// The app's part in shared roads (core/roads/share.mjs; the player, 2026-11-21): only the ground walked is read and
// sent, not when "Share the ground I walk" is off, only what's new, about once a day; the roads come back into
// the addon, and an addon install keeps newer ones.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readGround, newGround, uploadGround, syncRoads, installId, readState } from '../../core/roads/share.mjs';
import { encode, decode, roadsLua } from '../../core/roads/pack.mjs';
import { installAddon, addonState } from '../../core/link/install.mjs';

const road = (X, Y, n, v = 1) => encode(Array.from({ length: n }, (_, i) => ({ X: X + i, Y, v }))).join('');
// A SavedVariables file as the game writes it: the ground, and things that must never be sent.
const saved = ({ packed, off = false }) => `
SpellmindDB = {
	["playerName"] = "Jaina",
	["routeGround"] = {
		["c"] = {
			[0] = {
				"${packed}", -- [1]
			},
		},
		["v"] = 1,
	},
	${off ? '["routeShareOff"] = true,' : ''}
	["chats"] = { "my secret question" },
}
`;
function flavor(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-roads-'));
  for (const [account, text] of Object.entries(files)) {
    const sv = path.join(dir, 'WTF', 'Account', account, 'SavedVariables');
    fs.mkdirSync(sv, { recursive: true });
    fs.writeFileSync(path.join(sv, 'Spellmind.lua'), text);
  }
  fs.mkdirSync(path.join(dir, 'Interface', 'AddOns', 'Spellmind'), { recursive: true });
  return dir;
}
const dataDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'sm-data-'));
const URL0 = 'https://roads.example';

test('read from the saved file: the ground walked and the switch, nothing else', () => {
  const g = readGround(saved({ packed: road(32768, 32768, 3, 1 + 512 * 3) }));
  assert.deepEqual(Object.keys(g), ['off', 'c']);
  assert.equal(g.off, false);
  assert.equal(decode(g.c[0]).length, 3);
  assert.equal(readGround(saved({ packed: road(32768, 32768, 3), off: true })).off, true);
});

test('only what\'s new is sent, times walked dropped', () => {
  const first = newGround({ 0: road(32768, 32768, 3, 1 + 512 * 5) });
  assert.equal(first.squares, 3);
  assert.ok(decode(first.c[0]).every(s => s.v === 1), 'no times walked');
  const again = newGround({ 0: road(32768, 32768, 3, 1) }, first.next);
  assert.equal(again.squares, 0, 'the same again: nothing');
  const more = newGround({ 0: road(32768, 32768, 3, 1 + 4) + road(32780, 32768, 2) }, first.next);
  assert.equal(more.squares, 5, 'a new crossing on the 3, and 2 new squares');
});

test('the upload: the ground of accounts sharing, under a random id, about once a day; off sends nothing', async () => {
  const wow = flavor({ A: saved({ packed: road(32768, 32768, 4) }), B: saved({ packed: road(40000, 40000, 4), off: true }) });
  const data = dataDir();
  const sent = [];
  const fetchFn = async (url, init) => { sent.push({ url, body: JSON.parse(init.body) }); return { ok: true, status: 200 }; };
  let r = await uploadGround({ flavorDir: wow, dataDir: data, version: '0.6.5', url: URL0, now: 1e12, fetchFn });
  assert.equal(r.sent, 4, 'account A only: B turned it off');
  assert.equal(sent[0].url, URL0 + '/v1/ground');
  assert.deepEqual(Object.keys(sent[0].body).sort(), ['addon', 'c', 'game', 'install', 'v']);
  assert.match(sent[0].body.install, /^[0-9a-f]{32}$/);
  assert.ok(!JSON.stringify(sent[0].body).includes('Jaina') && !JSON.stringify(sent[0].body).includes('secret'), 'nothing else from the file');
  assert.equal(sent[0].body.install, installId(data), 'the same id each time');
  r = await uploadGround({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12 + 3600e3, fetchFn });
  assert.equal(r.skipped, 'recent');
  r = await uploadGround({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12 + 21 * 3600e3, fetchFn });
  assert.equal(r.sent, 0, 'a day on, nothing new');
  assert.equal(sent.length, 1);
  // No Worker set: off.
  assert.equal((await uploadGround({ flavorDir: wow, dataDir: dataDir(), url: '', fetchFn })).skipped, 'off');
});

test('the roads come back into the addon\'s Roads.lua, newer only; an addon install keeps them', async () => {
  const wow = flavor({});
  const data = dataDir();
  const roads = { v: 1, date: '2026-11-28', players: 5, c: { 0: [road(32768, 32768, 3)] } };
  let calls = 0;
  const fetchFn = async (url, init) => {
    calls++;
    if (init?.headers?.['if-none-match'] === '"r1"') return { status: 304, headers: { get: () => '"r1"' } };
    return { status: 200, ok: true, headers: { get: () => '"r1"' }, json: async () => roads };
  };
  let r = await syncRoads({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12, fetchFn });
  assert.equal(r.applied, true);
  const file = path.join(wow, 'Interface', 'AddOns', 'Spellmind', 'Roads.lua');
  assert.match(fs.readFileSync(file, 'utf8'), /date = "2026-11-28", players = 5/);
  r = await syncRoads({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12 + 3600e3, fetchFn });
  assert.equal(calls, 1, 'once a day');
  r = await syncRoads({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12 + 25 * 3600e3, fetchFn });
  assert.equal(calls, 2);
  assert.equal(readState(data).roadsEtag, '"r1"');
  // An addon install (its own Roads.lua, no roads yet) leaves the newer roads in place, and they don't make it
  // "outdated".
  const src = fs.mkdtempSync(path.join(os.tmpdir(), 'sm-src-'));
  fs.writeFileSync(path.join(src, 'Spellmind.toc'), '## Interface: 11508\n## Version: 0.6.5\nRoads.lua\n');
  fs.writeFileSync(path.join(src, 'Roads.lua'), roadsLua(null));
  installAddon({ flavorDir: wow, source: src, running: () => ({ running: false }), count: 0 });
  assert.match(fs.readFileSync(file, 'utf8'), /2026-11-28/, 'kept');
  assert.equal(addonState({ flavorDir: wow, source: src }).state, 'current');
  // A release with newer roads than the game's: those go in.
  fs.writeFileSync(path.join(src, 'Roads.lua'), roadsLua({ ...roads, date: '2026-12-05' }));
  installAddon({ flavorDir: wow, source: src, running: () => ({ running: false }), count: 0 });
  assert.match(fs.readFileSync(file, 'utf8'), /2026-12-05/);
});

test('turned off on every account: what this PC shared before is deleted, and nothing more goes', async () => {
  const data = dataDir();
  const calls = [];
  const fetchFn = async (url, init) => { calls.push({ url, method: init?.method }); return { ok: true, status: 200 }; };
  const on = flavor({ A: saved({ packed: road(32768, 32768, 4) }) });
  await uploadGround({ flavorDir: on, dataDir: data, url: URL0, now: 1e12, fetchFn });
  assert.ok(readState(data).sent, 'shared');
  const off = flavor({ A: saved({ packed: road(32768, 32768, 6), off: true }) });
  const r = await uploadGround({ flavorDir: off, dataDir: data, url: URL0, now: 1e12 + 21 * 3600e3, fetchFn });
  assert.equal(r.deleted, true);
  assert.deepEqual(calls[1], { url: URL0 + '/v1/ground/' + installId(data), method: 'DELETE' });
  assert.equal(readState(data).sent, undefined);
  const again = await uploadGround({ flavorDir: off, dataDir: data, url: URL0, now: 1e12 + 50 * 3600e3, fetchFn });
  assert.equal(again.skipped, 'off');
  assert.equal(calls.length, 2, 'nothing more');
});

test('the app\'s Status: squares shared and when, the roads received, or off', async () => {
  const { roadsStatus } = await import('../../core/roads/share.mjs');
  const data = dataDir();
  assert.deepEqual(roadsStatus(data), { on: true, off: false, shared: 0, lastSent: null, roads: null });
  const fetchFn = async (url, init) => init?.method === 'POST' ? { ok: true, status: 200 }
    : { status: 200, ok: true, headers: { get: () => '"r"' }, json: async () => ({ v: 1, date: '2026-11-28', players: 14, c: { 0: [road(32768, 32768, 3)] } }) };
  const wow = flavor({ A: saved({ packed: road(32768, 32768, 4) }) });
  await uploadGround({ flavorDir: wow, dataDir: data, url: URL0, now: Date.parse('2026-11-22T12:00:00Z'), fetchFn });
  await syncRoads({ flavorDir: wow, dataDir: data, url: URL0, now: Date.parse('2026-11-22T12:00:00Z'), fetchFn });
  const s = roadsStatus(data);
  assert.equal(s.shared, 4);
  assert.equal(s.lastSent, Date.parse('2026-11-22T12:00:00Z'));
  assert.deepEqual(s.roads, { date: '2026-11-28', players: 14, squares: 3 });
  const off = flavor({ A: saved({ packed: road(32768, 32768, 4), off: true }) });
  await uploadGround({ flavorDir: off, dataDir: data, url: URL0, now: Date.parse('2026-11-24T12:00:00Z'), fetchFn });
  assert.equal(roadsStatus(data).off, true);
});

test('just after WoW closes: uploaded sooner, but not twice in 30 minutes (the player, 2026-11-21)', async () => {
  const { AFTER_GAME_MS } = await import('../../core/roads/share.mjs');
  const data = dataDir();
  let posts = 0;
  const fetchFn = async () => { posts++; return { ok: true, status: 200 }; };
  await uploadGround({ flavorDir: flavor({ A: saved({ packed: road(32768, 32768, 4) }) }), dataDir: data, url: URL0, now: 1e12, fetchFn });
  const more = flavor({ A: saved({ packed: road(32768, 32768, 4) + road(33000, 33000, 3) }) });
  // 10 minutes on, the game closed again: too soon.
  assert.equal((await uploadGround({ flavorDir: more, dataDir: data, url: URL0, now: 1e12 + 10 * 60e3, fetchFn, every: AFTER_GAME_MS })).skipped, 'recent');
  // 40 minutes on: the new ground goes, long before the daily check would have sent it.
  assert.equal((await uploadGround({ flavorDir: more, dataDir: data, url: URL0, now: 1e12 + 40 * 60e3, fetchFn, every: AFTER_GAME_MS })).sent, 3);
  assert.equal(posts, 2);
});

test('"Check shared roads now": the roads fetched whatever the last check was (the player, 2026-11-22)', async () => {
  const wow = flavor({});
  const data = dataDir();
  let calls = 0;
  const fetchFn = async () => { calls++; return { status: 200, ok: true, headers: { get: () => '"r' + calls + '"' }, json: async () => ({ v: 1, date: '2026-11-2' + calls, players: calls, c: { 0: [road(32768, 32768, 3)] } }) }; };
  await syncRoads({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12, fetchFn });
  await syncRoads({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12 + 60e3, fetchFn });
  assert.equal(calls, 1, 'a minute on: not again');
  const r = await syncRoads({ flavorDir: wow, dataDir: data, url: URL0, now: 1e12 + 120e3, fetchFn, force: true });
  assert.equal(calls, 2, 'Check now: fetched');
  assert.equal(r.applied, true);
});
