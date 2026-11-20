// What's new in each version: the addon's "What's new" window after it updates (Welcome.lua's
// WL.NEWS, kept word for word the same by tests/app/news_test.mjs) and the app's card after it
// updates itself (main.mjs, renderer/app.js). Newest last; a version's entry is written when it's
// released (docs/releasing.md). Written to say what each thing does for the player (the maintainer,
// 2026-11-19: "more producty"): a headline, a line under it, a few highlights, a footnote. Any version
// can instead (or as well) list its changes, plainly (the maintainer: "release note changes as things
// change from version to version"); a version without a headline shows "What's changed".

export const NEWS = Object.freeze([
  Object.freeze({
    version: '0.5.0',
    headline: 'Meet your quest route',
    tagline: 'Spellmind now plans your leveling for you: built from your own quest log, and kept up to date as you play.',
    features: Object.freeze([
      Object.freeze({ title: 'A plan that knows your character', text: 'Every pickup, objective and turn-in around you, in the shortest order, ticked off the moment you finish it.' }),
      Object.freeze({ title: 'Never lose your way', text: 'An arrow on screen points to your next step. The world map numbers each step and shades where to go, and the minimap draws the line to it.' }),
      Object.freeze({ title: 'The way there, leg by leg', text: 'Flight paths you know, the roads between zones, the tram and the boats: the arrow and the map take you there by the fastest way you have.' }),
      Object.freeze({ title: 'Always know where to go next', text: 'When a zone runs dry, Spellmind ranks the best zones for your level. Pick one and the route takes you there, and holds to it until you arrive.' }),
      Object.freeze({ title: 'Ready for any dungeon', text: 'Pick a dungeon on the Route tab: Spellmind routes you through its quests and the questlines that open them, across zones, to its door.' }),
      Object.freeze({ title: 'Ask your AI about it', text: 'Your AI sees the same route. Ask "Review my route" for what to skip, and why.' }),
    ]),
    note: 'Works best with Questie installed. Find it all in the new Route tab.',
    changes: Object.freeze([
      "The Quests tab's \"Plan my next hour\" is now \"Review my route\", and each quest your AI says to skip gets a Skip button.",
      "After each update, this window says what's new. /sm news shows it again.",
      "A quest handed in in another zone is planned as a trip there and back when what it opens makes it worth it.",
      "The arrow and the lines follow the roads you've walked (learned on your PC only), and hold still on a flight path.",
      "Far quests that give little XP for the walk are marked \"worth skipping?\", and each kill step goes to the mobs least out of your way.",
      "Up next numbers each step as the map does. /sm route why <step> says why a step is where it is.",
    ]),
  }),
  Object.freeze({
    version: '0.6.0',
    headline: 'Your class quests, planned',
    tagline: 'Spellmind now finds your class\'s own questlines, wherever they start, and takes you through them.',
    features: Object.freeze([
      Object.freeze({ title: 'Every class questline for you', text: 'The Quests tab lists your class\'s questlines at your level, with the step you\'re on and where it starts. Versions from other starting areas fold under yours.' }),
      Object.freeze({ title: 'Routed like a dungeon', text: 'Pick one and the route takes you through it, across zones, by boat and flight path, to its last turn-in.' }),
      Object.freeze({ title: 'Never miss one', text: 'A nudge when a new class questline opens at your level, and a pointer in the route window while you quest.' }),
      Object.freeze({ title: 'Know when you\'re there', text: 'Inside an objective\'s area, the arrow says so and the minimap shades it, with no line pointing at its middle.' }),
    ]),
    note: 'Works best with Questie installed. Find it on the Quests tab and the Route tab.',
    changes: Object.freeze([
      'Class quests, and quests whose reward is an upgrade for you, are never marked "worth skipping?".',
      'The route keeps its order as you quest: new steps slot in where they fit, and Rebuild plans it afresh.',
      'Fixed: a spell you had trained could stay "to train" after a trainer visit.',
      'Season of Discovery quests no longer slip into the route on WoW Forever.',
      'Spellmind\'s lines in the game\'s chat have their own colours, and nudges grow to fit their words.',
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

/** What one window shows for the entries since the version last seen: the newest headline (with its
 * line and footnote; "What's changed" when none has one), every entry's highlights and changes, newest
 * first (a change with its version when there's more than one entry). */
export function digest(list) {
  if (!list?.length) return null;
  const n = list[list.length - 1];
  const newestFirst = list.slice().reverse();
  const lead = newestFirst.find((e) => e.headline) || null;
  const features = [], changes = [];
  for (const e of newestFirst) {
    for (const f of e.features || []) features.push(f);
    for (const c of e.changes || []) changes.push({ version: e.version, text: c });
  }
  return { version: n.version, headline: lead?.headline || "What's changed", tagline: lead?.tagline || null,
    features, note: lead?.note || null, changes, versions: list.length };
}

/** The entries after the version last seen, up to the one running now, oldest first. */
export function newsSince(seen, current) {
  return NEWS.filter((n) => newer(n.version, seen || '0') && !newer(n.version, current));
}
