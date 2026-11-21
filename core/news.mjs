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
  Object.freeze({
    version: '0.6.1',
    changes: Object.freeze([
      "Skipping a step skips what needs it: skip a pickup or an objective and the quest's turn-in and follow-ups go with it; skip a turn-in and its follow-ups go. Back brings them back.",
      'The route counts the steps left ("22 steps left · 2 skipped"), not "Step 3 of 25".',
      'When a fresh plan from where you stand would be clearly shorter, Rebuild says so ("Rebuild: 1,300 yd shorter"). After you finish a step, a much shorter order is taken by itself, your next step kept (a switch on the Route tab).',
      'Fixed: in a step with goals at several NPCs close together, the arrow and the map pointed at the first one placed, not the one to do now.',
    ]),
  }),
  Object.freeze({
    version: '0.6.2',
    changes: Object.freeze([
      "Fixed: Lua errors in combat from the route's arrow (the game's \"large number of errors\" warning).",
    ]),
  }),
  Object.freeze({
    version: '0.6.3',
    changes: Object.freeze([
      "Class questlines include every step: objectives placed (class quests have no zone of their own), and items to buy at a vendor.",
      "Items a vendor sells are bought from the nearest friendly seller, not farmed in a zone far away.",
      "On a flight path, the way there starts where you land (\"In flight to Stormwind\").",
      "Fixed: the map's gold line could run to another step when your current one was on a different map.",
      "/sm route why lists every seller of a step's items: where, whose, and how far.",
    ]),
  }),
  Object.freeze({
    version: '0.6.4',
    changes: Object.freeze([
      "A quest's items each get their own step, with their own seller and navigation: in class questlines and in your zone's quests.",
      "Items picked up off the ground are listed as \"take ... (on the ground)\", so no item goes unsaid.",
      "When another quest in your log needs the same item, the step says how many to buy (\"buy 2: ... needs one too\").",
      "A vendor seen sold out of an item is noticed on these steps too: the next seller, or the Auction House.",
      "At one NPC, the finished quest is turned in before its follow-up is picked up.",
      "Fixed: the minimap line and the arrow cut through walls when the target was nearer in a straight line.",
      "Out in the open, the line and the arrow go straight to the step unless a trail you walked heads there anyway: no more going back along another trip.",
      "Fixed: the world map's line ran back to a trail point you had already walked past.",
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
  // The newest headline's highlights alone (the player, 2026-11-20: every version's made a window too
  // long to read); an older version with a headline is its headline in one line.
  const leadAt = lead ? list.indexOf(lead) : list.length - 1;
  const features = [...(lead?.features || [])], changes = [];
  for (const e of newestFirst) {
    const i = list.indexOf(e);
    if (i < leadAt && e.headline) changes.push({ version: e.version, text: e.headline });
    else for (const c of e.changes || []) changes.push({ version: e.version, text: c });
  }
  return { version: n.version, headline: lead?.headline || "What's changed", tagline: lead?.tagline || null,
    features, note: lead?.note || null, changes, versions: list.length };
}

/** The app's What's new card after it updated (the player, 2026-11-20: keep the release's showcase,
 * with a version history under it): the newest release with a headline up to this version (its line,
 * highlights, footnote), even when a fix came after it; and history, every version up to this one,
 * newest first, each with its changes, "isNew" on the ones since the version last seen. null when
 * nothing since has a headline: a fix alone shows nothing (it's in the history). */
export function card(list, all = NEWS) {
  if (!list?.length || !list.some((e) => e.headline)) return null;
  const current = list[list.length - 1].version;
  const upTo = all.filter((e) => !newer(e.version, current));
  const lead = upTo.slice().reverse().find((e) => e.headline);
  const fresh = new Set(list.map((e) => e.version));
  return { version: current, headline: lead.headline, tagline: lead.tagline || null, features: [...(lead.features || [])],
    note: lead.note || null,
    history: upTo.slice().reverse().map((e) => ({ version: e.version, headline: e.headline || null, changes: [...(e.changes || [])], isNew: fresh.has(e.version) })) };
}

/** The entries after the version last seen, up to the one running now, oldest first. */
export function newsSince(seen, current) {
  return NEWS.filter((n) => newer(n.version, seen || '0') && !newer(n.version, current));
}
