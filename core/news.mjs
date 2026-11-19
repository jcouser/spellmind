// What's new in each version: the addon's "What's new" window after it updates (Welcome.lua's
// WL.NEWS, kept word for word the same by tests/app/news_test.mjs) and the app's card after it
// updates itself (main.mjs, renderer/app.js). Newest last; a version's entry is written when it's
// released (docs/releasing.md).

export const NEWS = Object.freeze([
  Object.freeze({
    version: '0.5.0',
    title: 'The quest route',
    lines: Object.freeze([
      'Your next steps from your quest log and where you stand: pick up, do and turn in, in a short order, ticked off as you go.',
      'An arrow points at the current step, and the world map numbers the steps and shades where each objective is.',
      'Where next ranks the zones by what is left for your level, with your flight paths and hearthstone.',
      'Best with Questie installed: it adds the quests to pick up and where the mobs are.',
      'Turn it on in the new Route tab. Your AI gets the route too: try Review my route.',
    ]),
  }),
]);

const parts = (v) => String(v ?? '').split('.').map((n) => parseInt(n, 10) || 0);

/** Is version a newer than b? ("0.5.0" > "0.4.7") */
export function newer(a, b) {
  const x = parts(a), y = parts(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const p = x[i] ?? 0, q = y[i] ?? 0;
    if (p !== q) return p > q;
  }
  return false;
}

/** The entries after the version last seen, up to the one running now, oldest first. */
export function newsSince(seen, current) {
  return NEWS.filter((n) => newer(n.version, seen || '0') && !newer(n.version, current));
}
