// The app's part in shared roads (server/roads/README.md; the player, 2026-11-21: foot traffic shared, on unless
// the player turns it off, the app keeping it up to date):
//
//   uploadGround(): what's new in the ground the addon recorded (SpellmindDB.routeGround in each account's
//     SavedVariables), at most once a day, under a random id this app made, unless that account's
//     "Share the ground I walk" is off (SpellmindDB.routeShareOff). Only the squares and their crossings are
//     read from the file; nothing else in it is looked at.
//   syncRoads(): the roads merged, once a day (with an ETag), kept here and written into the addon's Roads.lua
//     when they're newer than the game's.
//   applyRoads(): the roads kept here written again (after an addon update put the app's own copy in place).
//
// ROADS_URL: the Worker (server/roads); an empty one turns sharing off.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { savedStatements } from '../link/slots.mjs';
import { decode, record, roadsLua, roadsDate } from './pack.mjs';

export const ROADS_URL = 'https://spellmind-roads.spellmind.workers.dev'; // server/roads (deployed 2026-11-21)
export const UPLOAD_EVERY_MS = 20 * 3600e3; // about once a day
export const ROADS_EVERY_MS = 24 * 3600e3;
export const MAX_SQUARES = 60000; // an upload's squares, at most (the Worker takes 512 KB)

const stateFile = (dir) => path.join(dir, 'roads.json');
export function readState(dir) {
  try { return JSON.parse(fs.readFileSync(stateFile(dir), 'utf8')); } catch { return {}; }
}
function writeState(dir, st) {
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${stateFile(dir)}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(st));
  fs.renameSync(tmp, stateFile(dir));
}
// This app's random id: made once, tied to nothing.
export function installId(dir) {
  const st = readState(dir);
  if (typeof st.install === 'string' && /^[0-9a-f]{32}$/.test(st.install)) return st.install;
  st.install = crypto.randomBytes(16).toString('hex');
  writeState(dir, st);
  return st.install;
}

// Each WoW account's Spellmind SavedVariables.
export function savedFiles(flavorDir) {
  const root = path.join(flavorDir, 'WTF', 'Account');
  let accounts = [];
  try { accounts = fs.readdirSync(root, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name); } catch { return []; }
  return accounts.map(a => path.join(root, a, 'SavedVariables', 'Spellmind.lua')).filter(f => { try { return fs.statSync(f).isFile(); } catch { return false; } });
}

const entry = (table, name) => table?.type === 'table' ? table.entries.find(e => e.key?.type === 'string' && e.key.value === name)?.value : undefined;
// From one SavedVariables file: { off, c: { [continent]: packed } }, the ground walked and nothing else.
export function readGround(text) {
  const db = savedStatements(text).find(s => s.name === 'SpellmindDB')?.value;
  const off = entry(db, 'routeShareOff');
  const c = {};
  const conts = entry(entry(db, 'routeGround'), 'c');
  for (const e of conts?.type === 'table' ? conts.entries : []) {
    const cont = e.key?.type === 'number' ? e.key.value : null;
    if (cont == null || !/^\d{1,5}$/.test(cont) || e.value?.type !== 'table') continue;
    c[cont] = e.value.entries.filter(x => x.value?.type === 'string' && /^[A-Za-z0-9+/]*$/.test(x.value.value)).map(x => x.value.value).join('');
  }
  return { off: off?.type === 'boolean' && off.value === 'true', c };
}

// What hasn't been sent yet: squares new to sent, or with a crossing it hadn't (times walked dropped).
// → { c: { [continent]: packed }, squares, next (sent with these added) }.
export function newGround(ground, sent = {}) {
  const next = {}, c = {};
  let squares = 0;
  for (const [cont, packed] of Object.entries(ground)) {
    const had = sent[cont] || {};
    const now = { ...had };
    let out = '';
    for (const s of decode(packed)) {
      const key = s.X * 65536 + s.Y;
      const v = s.v & 511;
      const before = had[key] || 0;
      const merged = before | v;
      if (merged !== before || !(key in had)) {
        if (squares < MAX_SQUARES) { out += record(s.X, s.Y, merged); squares++; now[key] = merged; }
      }
    }
    next[cont] = now;
    if (out) c[cont] = out;
  }
  for (const [cont, had] of Object.entries(sent)) if (!next[cont]) next[cont] = had;
  return { c, squares, next };
}

export async function uploadGround({ flavorDir, dataDir, version = null, game = null, url = ROADS_URL, now = Date.now(), fetchFn = fetch, log = () => {} } = {}) {
  if (!url || !flavorDir) return { skipped: 'off' };
  const st = readState(dataDir);
  if (st.lastUpload && now - st.lastUpload < UPLOAD_EVERY_MS) return { skipped: 'recent' };
  const all = {};
  let on = 0, off = 0;
  for (const file of savedFiles(flavorDir)) {
    let g;
    try { g = readGround(fs.readFileSync(file, 'latin1')); } catch { continue; }
    if (g.off) { off++; continue; } // that account's "Share the ground I walk" is off
    on++;
    for (const [cont, packed] of Object.entries(g.c)) all[cont] = (all[cont] || '') + packed;
  }
  // Turned off on every account here: what this PC sent before is deleted too, and nothing more goes.
  if (off > 0 && on === 0) {
    if (st.sent && Object.keys(st.sent).length && typeof st.install === 'string') {
      const r = await fetchFn(url.replace(/\/$/, '') + '/v1/ground/' + st.install, { method: 'DELETE' });
      if (r.ok) {
        const st3 = readState(dataDir);
        delete st3.sent;
        writeState(dataDir, st3);
        log('Roads: sharing is off, and what this PC shared before was deleted.');
        return { deleted: true };
      }
      return { error: r.status };
    }
    return { skipped: 'off' };
  }
  const install = installId(dataDir);
  const { c, squares, next } = newGround(all, readState(dataDir).sent || {});
  const st2 = readState(dataDir);
  if (!squares) { st2.lastUpload = now; writeState(dataDir, st2); return { sent: 0 }; }
  const r = await fetchFn(url.replace(/\/$/, '') + '/v1/ground', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ v: 1, install, game, addon: version, c }),
  });
  if (!r.ok) { log(`Roads: the upload was refused (${r.status}).`); return { error: r.status }; }
  st2.sent = next;
  st2.lastUpload = now;
  writeState(dataDir, st2);
  log(`Roads: ${squares} squares of ground walked shared.`);
  return { sent: squares };
}

const roadsFile = (flavorDir) => path.join(flavorDir, 'Interface', 'AddOns', 'Spellmind', 'Roads.lua');
const cacheFile = (dir) => path.join(dir, 'roads-latest.json');

// The roads kept here into the addon, when they're newer than the game's.
export function applyRoads({ flavorDir, dataDir }) {
  let roads;
  try { roads = JSON.parse(fs.readFileSync(cacheFile(dataDir), 'utf8')); } catch { return { applied: false }; }
  const file = roadsFile(flavorDir);
  if (!fs.existsSync(path.dirname(file))) return { applied: false };
  let have = null;
  try { have = roadsDate(fs.readFileSync(file, 'utf8')); } catch { /* none yet */ }
  if (have && roads.date && have >= roads.date) return { applied: false };
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, roadsLua(roads));
  fs.renameSync(tmp, file);
  return { applied: true, date: roads.date };
}

export async function syncRoads({ flavorDir, dataDir, url = ROADS_URL, now = Date.now(), fetchFn = fetch, log = () => {} } = {}) {
  if (!url || !flavorDir) return { skipped: 'off' };
  const st = readState(dataDir);
  if (st.lastRoads && now - st.lastRoads < ROADS_EVERY_MS) return applyRoads({ flavorDir, dataDir });
  const r = await fetchFn(url.replace(/\/$/, '') + '/v1/roads', { headers: st.roadsEtag ? { 'if-none-match': st.roadsEtag } : {} });
  const st2 = readState(dataDir);
  st2.lastRoads = now;
  if (r.status === 200) {
    const roads = await r.json();
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(cacheFile(dataDir), JSON.stringify(roads));
    st2.roadsEtag = r.headers.get('etag') || null;
    log(`Roads: the roads of ${roads.date} (${roads.players} players).`);
  }
  writeState(dataDir, st2);
  return applyRoads({ flavorDir, dataDir });
}
