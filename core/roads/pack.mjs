// The roads players walk (server/roads/README.md): the packed squares Ground.lua keeps, merged from many installs,
// and Roads.lua made from them. Shared by the weekly merge (tools/roads-merge.mjs) and the app (core/roads/share.mjs).

export const K = 3; // installs a crossing needs before it's a road (one player's odd path never shows)
export const WINDOW_DAYS = 90; // uploads kept this long, then dropped
export const CHUNK = 4096; // squares a string, as Ground.lua packs them

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const DEC = Object.fromEntries([...B64].map((c, i) => [c, i]));
// The eight directions, as Ground.lua's DIRS: east first, then round.
export const DIRS = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]];

const enc = (n, len) => { let s = ''; for (let i = 0; i < len; i++) { s = B64[n % 64] + s; n = Math.floor(n / 64); } return s; };
const dec = (s) => [...s].reduce((n, c) => n * 64 + DEC[c], 0);
export const record = (X, Y, v) => enc(X, 3) + enc(Y, 3) + enc(v, 2);

// Packed squares → [{ X, Y, v }] (X, Y as Ground.lua keeps them: column and row + 32768).
export function decode(packed) {
  const out = [];
  for (let i = 0; i + 8 <= packed.length; i += 8) out.push({ X: dec(packed.slice(i, i + 3)), Y: dec(packed.slice(i + 3, i + 6)), v: dec(packed.slice(i + 6, i + 8)) });
  return out;
}
export function encode(squares) {
  const chunks = [];
  for (let i = 0; i < squares.length; i += CHUNK) chunks.push(squares.slice(i, i + CHUNK).map(s => record(s.X, s.Y, s.v)).join(''));
  return chunks;
}

// uploads: [{ install, c: { [continent]: packed } }] → { players, c: { [continent]: chunks } }.
export function merge(uploads, { k = K } = {}) {
  const per = new Map(); // install → continent → "X:Y" → { edges, wet }
  for (const u of uploads) {
    if (!u || typeof u.install !== 'string') continue;
    if (!per.has(u.install)) per.set(u.install, new Map());
    const mine = per.get(u.install);
    for (const [cont, packed] of Object.entries(u.c || {})) {
      if (typeof packed !== 'string') continue;
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
  const conts = new Map();
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
    const cells = new Map();
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
      const wetN = C.wet.get(key) || 0;
      const wet = wetN > 0 && wetN * 2 >= (C.seen.get(key) || 1);
      const tier = Math.min(7, Math.floor(Math.log2(Math.max(1, most))));
      squares.push({ X, Y, v: edges + (wet ? 256 : 0) + tier * 512 });
    }
    squares.sort((a, b) => a.X - b.X || a.Y - b.Y);
    if (squares.length) out.c[cont] = encode(squares);
  }
  return out;
}

export const ROADS_HEAD = [
  '-- Spellmind: the roads players walk, merged (server/roads/README.md): squares crossed, each crossing kept only when',
  "-- at least 3 players' installs walked it. Written by the release build and kept up to date by the Spellmind app.",
].join('\n');
// The roads' day in a Roads.lua ("2026-11-28"), or null.
export const roadsDate = (text) => (/date = "(\d{4}-\d{2}-\d{2})"/.exec(String(text || '')) || [])[1] || null;

// The roads as Roads.lua.
export function roadsLua(roads) {
  if (!roads || !roads.c || !Object.keys(roads.c).length) return ROADS_HEAD + '\nSpellmindRoads = nil\n';
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(roads.date)) ? roads.date : '1970-01-01';
  const conts = Object.entries(roads.c)
    .filter(([cont, chunks]) => /^\d{1,5}$/.test(cont) && Array.isArray(chunks))
    .map(([cont, chunks]) => `\t[${Number(cont)}] = {\n${chunks.filter(s => typeof s === 'string' && /^[A-Za-z0-9+/]*$/.test(s)).map(s => `\t\t"${s}",`).join('\n')}\n\t},`).join('\n');
  return `${ROADS_HEAD}\nSpellmindRoads = { v = 1, date = "${date}", players = ${Number(roads.players) || 0}, c = {\n${conts}\n} }\n`;
}
