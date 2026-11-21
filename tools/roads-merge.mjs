// The roads players walk, merged (server/roads/README.md): reads the uploads the Spellmind roads Worker keeps,
// keeps each crossing at least K installs walked, and puts the roads back for the app; or, for the release
// build, writes the roads into the addon's Roads.lua.
//
//   node tools/roads-merge.mjs                       merge, put the roads to the Worker, drop uploads past the window
//   node tools/roads-merge.mjs --lua <file>          also write Roads.lua
//   node tools/roads-merge.mjs --fetch --lua <file>  only fetch the roads already merged into Roads.lua (release build)
//
// ROADS_URL (the Worker) and, to merge, ROADS_ADMIN_TOKEN come from the environment.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const K = 3; // installs a crossing needs before it's a road (one player's odd path never shows)
export const WINDOW_DAYS = 90; // uploads kept this long, then dropped
export const CHUNK = 4096; // squares a string, as Ground.lua packs them

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const DEC = Object.fromEntries([...B64].map((c, i) => [c, i]));
// The eight directions, as Ground.lua's DIRS: east first, then round.
export const DIRS = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]];

const enc = (n, len) => { let s = ''; for (let i = 0; i < len; i++) { s = B64[n % 64] + s; n = Math.floor(n / 64); } return s; };
const dec = (s) => [...s].reduce((n, c) => n * 64 + DEC[c], 0);

// Packed squares → [{ X, Y, v }] (X, Y as Ground.lua keeps them: column and row + 32768).
export function decode(packed) {
  const out = [];
  for (let i = 0; i + 8 <= packed.length; i += 8) out.push({ X: dec(packed.slice(i, i + 3)), Y: dec(packed.slice(i + 3, i + 6)), v: dec(packed.slice(i + 6, i + 8)) });
  return out;
}
export function encode(squares) {
  const chunks = [];
  for (let i = 0; i < squares.length; i += CHUNK) {
    chunks.push(squares.slice(i, i + CHUNK).map(s => enc(s.X, 3) + enc(s.Y, 3) + enc(s.v, 2)).join(''));
  }
  return chunks;
}

// uploads: [{ install, c: { [continent]: packed } }] → { players, c: { [continent]: chunks } }.
export function merge(uploads, { k = K } = {}) {
  const per = new Map(); // install → continent → "X:Y" → { edges, wet }
  for (const u of uploads) {
    if (!per.has(u.install)) per.set(u.install, new Map());
    const mine = per.get(u.install);
    for (const [cont, packed] of Object.entries(u.c || {})) {
      if (!mine.has(cont)) mine.set(cont, new Map());
      const cells = mine.get(cont);
      for (const s of decode(packed)) {
        const key = s.X + ':' + s.Y;
        const had = cells.get(key) || { edges: 0, wet: false };
        cells.set(key, { edges: had.edges | (s.v & 255), wet: had.wet || (s.v & 256) !== 0 });
      }
    }
  }
  // How many installs crossed each way, and swam each square.
  const conts = new Map(); // continent → { cross: Map("X:Y:d" → n), wet: Map("X:Y" → n), seen: Map("X:Y" → n) }
  for (const mine of per.values()) {
    for (const [cont, cells] of mine) {
      if (!conts.has(cont)) conts.set(cont, { cross: new Map(), wet: new Map(), seen: new Map() });
      const C = conts.get(cont);
      for (const [key, { edges, wet }] of cells) {
        C.seen.set(key, (C.seen.get(key) || 0) + 1);
        if (wet) C.wet.set(key, (C.wet.get(key) || 0) + 1);
        for (let d = 0; d < 8; d++) if (edges & (1 << d)) C.cross.set(key + ':' + d, (C.cross.get(key + ':' + d) || 0) + 1);
      }
    }
  }
  const out = { players: per.size, c: {} };
  for (const [cont, C] of conts) {
    const cells = new Map(); // "X:Y" → { edges, most }
    const cell = (key) => { if (!cells.has(key)) cells.set(key, { edges: 0, most: 0 }); return cells.get(key); };
    for (const [ck, n] of C.cross) {
      if (n < k) continue;
      const [X, Y, d] = ck.split(':').map(Number);
      const from = cell(X + ':' + Y);
      from.edges |= 1 << d;
      from.most = Math.max(from.most, n);
      const to = cell((X + DIRS[d][0]) + ':' + (Y + DIRS[d][1]));
      to.most = Math.max(to.most, n);
    }
    const squares = [];
    for (const [key, { edges, most }] of cells) {
      const [X, Y] = key.split(':').map(Number);
      const wet = (C.wet.get(key) || 0) * 2 >= (C.seen.get(key) || 1) && (C.wet.get(key) || 0) > 0;
      const tier = Math.min(7, Math.floor(Math.log2(Math.max(1, most))));
      squares.push({ X, Y, v: edges + (wet ? 256 : 0) + tier * 512 });
    }
    squares.sort((a, b) => a.X - b.X || a.Y - b.Y);
    if (squares.length) out.c[cont] = encode(squares);
  }
  return out;
}

// The roads as Roads.lua.
export function roadsLua(roads) {
  const head = fs.readFileSync(new URL('../addon/Spellmind/Roads.lua', import.meta.url), 'utf8').split('\n').filter(l => l.startsWith('--')).join('\n');
  if (!roads || !roads.c || !Object.keys(roads.c).length) return head + '\nSpellmindRoads = nil\n';
  const conts = Object.entries(roads.c).map(([cont, chunks]) => `\t[${Number(cont)}] = {\n${chunks.map(s => `\t\t"${s}",`).join('\n')}\n\t},`).join('\n');
  return `${head}\nSpellmindRoads = { v = 1, date = "${roads.date}", players = ${Number(roads.players) || 0}, c = {\n${conts}\n} }\n`;
}

// The upload's day from its key: up/<install>/<YYYY-MM-DD>-<HHMMSS>.json.
export const keyDay = (key) => (/\/(\d{4}-\d{2}-\d{2})-/.exec(key) || [])[1] || null;

async function main(argv) {
  const base = (process.env.ROADS_URL || '').replace(/\/$/, '');
  if (!base) throw new Error('ROADS_URL is not set');
  const lua = argv.includes('--lua') ? argv[argv.indexOf('--lua') + 1] : null;
  if (argv.includes('--fetch')) {
    const r = await fetch(base + '/v1/roads');
    const roads = r.ok ? await r.json() : null;
    if (lua) fs.writeFileSync(lua, roadsLua(roads));
    console.log(roads ? `roads of ${roads.date}, ${roads.players} players` : 'no roads yet');
    return;
  }
  const token = process.env.ROADS_ADMIN_TOKEN;
  if (!token) throw new Error('ROADS_ADMIN_TOKEN is not set');
  const auth = { authorization: `Bearer ${token}` };
  const now = Date.now();
  const oldest = new Date(now - WINDOW_DAYS * 86400e3).toISOString().slice(0, 10);
  const uploads = [];
  let cursor = null, dropped = 0;
  do {
    const r = await fetch(base + '/v1/admin/list' + (cursor ? '?cursor=' + encodeURIComponent(cursor) : ''), { headers: auth });
    if (!r.ok) throw new Error('list: ' + r.status);
    const page = await r.json();
    for (const { key } of page.keys) {
      const d = keyDay(key);
      if (d && d < oldest) {
        await fetch(base + '/v1/admin/object?key=' + encodeURIComponent(key), { method: 'DELETE', headers: auth });
        dropped++;
        continue;
      }
      const o = await fetch(base + '/v1/admin/object?key=' + encodeURIComponent(key), { headers: auth });
      if (o.ok) { try { uploads.push(await o.json()); } catch { /* a broken upload is skipped */ } }
    }
    cursor = page.cursor;
  } while (cursor);
  const roads = { v: 1, date: new Date(now).toISOString().slice(0, 10), ...merge(uploads) };
  const put = await fetch(base + '/v1/admin/roads', { method: 'PUT', headers: { ...auth, 'content-type': 'application/json' }, body: JSON.stringify(roads) });
  if (!put.ok) throw new Error('put roads: ' + put.status);
  if (lua) fs.writeFileSync(lua, roadsLua(roads));
  const squares = Object.values(roads.c).reduce((n, chunks) => n + chunks.join('').length / 8, 0);
  console.log(`${uploads.length} uploads from ${roads.players} installs: ${squares} road squares; ${dropped} past ${WINDOW_DAYS} days dropped`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === fs.realpathSync(process.argv[1])) {
  main(process.argv.slice(2)).catch(e => { console.error(e.message); process.exit(1); });
}
