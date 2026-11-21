// Spellmind roads: a Cloudflare Worker (free tier) that keeps what the Spellmind app sends of the ground
// its players walk, and hands out the roads merged from it (the player, 2026-11-21: "sharing of foot
// traffic data ... for the best pathing possible", a free Cloudflare Worker).
//
// What comes in is squares crossed and nothing else: for each continent, packed squares (Ground.lua's 8
// characters: column, row, the directions crossed out of it and whether it was swum), under a random id the
// app made for itself. No times beyond the day, no order of travel, no character, realm or account.
//
// The Worker stores, it doesn't merge (a free Worker has 10 ms of CPU a request): each upload is one object
// in R2, up/<install>/<day>-<time>.json. tools/roads-merge.mjs (a weekly GitHub Action) reads them through
// the admin routes, merges them, and puts the roads back here for the app and the release build.
//
//   POST   /v1/ground                 an upload: { v: 1, install, game, addon, c: { [continent]: packed } }
//   GET    /v1/roads                  the roads merged (roads/latest.json), with an ETag
//   DELETE /v1/ground/<install>       every upload of an install (the app's "delete what I sent")
//   admin (Authorization: Bearer ADMIN_TOKEN):
//   GET    /v1/admin/list?cursor=     uploads, a page at a time: { keys: [{ key, uploaded }], cursor }
//   GET    /v1/admin/object?key=      one upload
//   DELETE /v1/admin/object?key=      one upload (older than the window)
//   PUT    /v1/admin/roads            the roads merged

export const MAX_BYTES = 512 * 1024;
const INSTALL = /^[0-9a-f]{32}$/;
const PACKED = /^[A-Za-z0-9+/]*$/;
const CONTINENT = /^\d{1,5}$/;
const SHORT = /^[0-9A-Za-z.\- ]{0,24}$/;

const json = (status, body, headers = {}) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
});

// An upload as it may be kept, or why not.
export function checkUpload(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return { error: 'not an object' };
  if (body.v !== 1) return { error: 'version' };
  if (typeof body.install !== 'string' || !INSTALL.test(body.install)) return { error: 'install' };
  if (body.game != null && (typeof body.game !== 'string' || !SHORT.test(body.game))) return { error: 'game' };
  if (body.addon != null && (typeof body.addon !== 'string' || !SHORT.test(body.addon))) return { error: 'addon' };
  if (!body.c || typeof body.c !== 'object' || Array.isArray(body.c)) return { error: 'continents' };
  const c = {};
  let squares = 0;
  for (const [k, packed] of Object.entries(body.c)) {
    if (!CONTINENT.test(k) || typeof packed !== 'string' || packed.length % 8 !== 0 || !PACKED.test(packed)) return { error: 'continent ' + k };
    if (packed.length) { c[k] = packed; squares += packed.length / 8; }
  }
  if (!squares) return { error: 'empty' };
  return { upload: { v: 1, install: body.install, game: body.game ?? null, addon: body.addon ?? null, c }, squares };
}

const day = (now) => new Date(now).toISOString().slice(0, 10);
const stamp = (now) => new Date(now).toISOString().slice(11, 19).replace(/:/g, '');

function admin(request, env) {
  const auth = request.headers.get('authorization') || '';
  return Boolean(env.ADMIN_TOKEN) && auth === `Bearer ${env.ADMIN_TOKEN}`;
}

export async function handle(request, env, now = Date.now()) {
  const url = new URL(request.url);
  const p = url.pathname;
  const R2 = env.ROADS;

  if (p === '/v1/ground' && request.method === 'POST') {
    const size = Number(request.headers.get('content-length') || 0);
    if (size > MAX_BYTES) return json(413, { error: 'too big' });
    const text = await request.text();
    if (text.length > MAX_BYTES) return json(413, { error: 'too big' });
    let body;
    try { body = JSON.parse(text); } catch { return json(400, { error: 'not json' }); }
    const { upload, squares, error } = checkUpload(body);
    if (error) return json(400, { error });
    const key = `up/${upload.install}/${day(now)}-${stamp(now)}.json`;
    await R2.put(key, JSON.stringify(upload), { httpMetadata: { contentType: 'application/json' } });
    return json(200, { ok: true, squares });
  }

  if (p === '/v1/roads' && request.method === 'GET') {
    const obj = await R2.get('roads/latest.json');
    if (!obj) return json(404, { error: 'no roads yet' });
    const etag = obj.httpEtag || obj.etag;
    if (etag && request.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers: { etag } });
    return new Response(obj.body, { headers: { 'content-type': 'application/json; charset=utf-8', etag: etag || '', 'cache-control': 'public, max-age=3600' } });
  }

  const del = /^\/v1\/ground\/([0-9a-f]{32})$/.exec(p);
  if (del && request.method === 'DELETE') {
    let cursor, n = 0;
    do {
      const page = await R2.list({ prefix: `up/${del[1]}/`, cursor });
      const keys = page.objects.map(o => o.key);
      if (keys.length) { await R2.delete(keys); n += keys.length; }
      cursor = page.truncated ? page.cursor : undefined;
    } while (cursor);
    return json(200, { ok: true, deleted: n });
  }

  if (p.startsWith('/v1/admin/')) {
    if (!admin(request, env)) return json(401, { error: 'admin only' });
    if (p === '/v1/admin/list' && request.method === 'GET') {
      const page = await R2.list({ prefix: 'up/', cursor: url.searchParams.get('cursor') || undefined, limit: 1000 });
      return json(200, {
        keys: page.objects.map(o => ({ key: o.key, uploaded: o.uploaded ? new Date(o.uploaded).toISOString() : null })),
        cursor: page.truncated ? page.cursor : null,
      });
    }
    const key = url.searchParams.get('key') || '';
    if (p === '/v1/admin/object' && /^up\/[0-9a-f]{32}\/[0-9-]+\.json$/.test(key)) {
      if (request.method === 'GET') {
        const obj = await R2.get(key);
        return obj ? new Response(obj.body, { headers: { 'content-type': 'application/json' } }) : json(404, { error: 'gone' });
      }
      if (request.method === 'DELETE') { await R2.delete(key); return json(200, { ok: true }); }
    }
    if (p === '/v1/admin/roads' && request.method === 'PUT') {
      const text = await request.text();
      try { JSON.parse(text); } catch { return json(400, { error: 'not json' }); }
      await R2.put('roads/latest.json', text, { httpMetadata: { contentType: 'application/json' } });
      return json(200, { ok: true });
    }
    return json(404, { error: 'no such admin route' });
  }

  return json(404, { error: 'not here' });
}

export default { fetch: (request, env) => handle(request, env) };
