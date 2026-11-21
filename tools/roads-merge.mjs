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
import { merge, roadsLua, WINDOW_DAYS } from '../core/roads/pack.mjs';
export { K, WINDOW_DAYS, CHUNK, DIRS, decode, encode, merge, roadsLua } from '../core/roads/pack.mjs';

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
  // --min <n>: installs a crossing needs, for a test by hand only (one tester's own ground back as roads); the
  // weekly run and anything before a release use the default.
  const min = argv.includes('--min') ? Math.max(1, Number(argv[argv.indexOf('--min') + 1]) || 2) : undefined;
  const roads = { v: 1, date: new Date(now).toISOString().slice(0, 10), ...merge(uploads, min ? { k: min } : {}) };
  const put = await fetch(base + '/v1/admin/roads', { method: 'PUT', headers: { ...auth, 'content-type': 'application/json' }, body: JSON.stringify(roads) });
  if (!put.ok) throw new Error('put roads: ' + put.status);
  if (lua) fs.writeFileSync(lua, roadsLua(roads));
  const squares = Object.values(roads.c).reduce((n, chunks) => n + chunks.join('').length / 8, 0);
  console.log(`${uploads.length} uploads from ${roads.players} installs: ${squares} road squares; ${dropped} past ${WINDOW_DAYS} days dropped`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === fs.realpathSync(process.argv[1])) {
  main(process.argv.slice(2)).catch(e => { console.error(e.message); process.exit(1); });
}
