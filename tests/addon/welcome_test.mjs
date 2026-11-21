// The first-time welcome (addon/Spellmind/Welcome.lua): once per account, 6 s after login, never in
// combat; the app's link to copy, or "connected" when the app already talks to the game; nudges wait
// while it's open; /sm welcome shows it again.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM, reloadVM } from '../helpers/addon-vm.mjs';

const open = vm => vm.evaluate('tostring(SpellmindWelcome ~= nil and SpellmindWelcome.shown)') === 'true';
const nudge = vm => vm.evaluate('tostring(SpellmindNudge ~= nil and SpellmindNudge.shown)') === 'true';

test('a new account: the welcome 6 s after login, with the app\'s link to copy; nudges wait until it closes', () => {
  const vm = newVM({ welcome: true }).login();
  vm.advance(5);
  assert.ok(!open(vm), 'not before the login settles');
  vm.advance(1.5);
  assert.ok(open(vm));
  assert.equal(vm.evaluate('SpellmindWelcome.title:GetText()'), 'Welcome to Spellmind');
  assert.match(vm.evaluate('SpellmindWelcome.app:GetText()'), /free Spellmind app/);
  assert.equal(vm.evaluate('SpellmindWelcome.link:GetText()'), 'https://github.com/jcouser/spellmind');
  assert.equal(vm.evaluate('tostring(SpellmindWelcome.link.shown)'), 'true');
  assert.equal(vm.evaluate('tostring(SpellmindDB.welcomed)'), 'true');
  vm.advance(4);
  assert.ok(!nudge(vm), 'the spell nudge waits while the welcome is open');
  vm.run('SpellmindWelcome.ok.scripts.OnClick(SpellmindWelcome.ok)');
  assert.ok(!open(vm));
  assert.ok(nudge(vm), 'and shows when it closes');
});

test('once per account: not after a /reload; /sm welcome shows it again', () => {
  const vm = newVM({ welcome: true }).login().advance(7);
  assert.ok(open(vm));
  vm.run('SpellmindWelcome.ok.scripts.OnClick(SpellmindWelcome.ok)');
  const back = reloadVM(vm, { welcome: true }).login().advance(10);
  assert.ok(!open(back), 'welcomed already');
  back.slash('welcome');
  assert.ok(open(back));
});

test('never in combat: it waits for the fight to end', () => {
  const vm = newVM({ welcome: true }).login();
  vm.run('STUB.combat = true');
  vm.advance(12);
  assert.ok(!open(vm));
  assert.equal(vm.evaluate('tostring(SpellmindDB.welcomed)'), 'nil', 'not counted as seen');
  vm.run('STUB.combat = false');
  vm.advance(6);
  assert.ok(open(vm));
});

test('the app already talks to the game: "connected", no link', () => {
  const vm = newVM({ welcome: true }).login();
  vm.run('NS.Link.AppGone = function() return false end');
  vm.advance(7);
  assert.ok(open(vm));
  assert.match(vm.evaluate('SpellmindWelcome.app:GetText()'), /app is connected/);
  assert.equal(vm.evaluate('tostring(SpellmindWelcome.link.shown)'), 'false');
});

test('Open the panel: the welcome closes and the Quests tab opens', () => {
  const vm = newVM({ welcome: true }).login().advance(7);
  vm.run('SpellmindWelcome.panel.scripts.OnClick(SpellmindWelcome.panel)');
  assert.ok(!open(vm));
  assert.equal(vm.evaluate('NS.Panel.tab'), 'quests');
});

// What's new (the player, 2026-11-19: the route is a big one). The addon at 0.5.0 here.
const news = vm => vm.evaluate('tostring(SpellmindNews ~= nil and SpellmindNews.shown)') === 'true';

test('updated from an earlier version: What\'s new once, 6 s after login, an announcement; Try it now; /sm news again', () => {
  const vm = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.4.7" }', before: 'NS.VERSION = "0.5.0"' }).login();
  vm.advance(7);
  assert.ok(news(vm));
  assert.ok(!open(vm), 'not the welcome');
  assert.equal(vm.evaluate('SpellmindNews.title:GetText()'), 'What\'s new in Spellmind 0.5.0');
  assert.equal(vm.evaluate('SpellmindNews.headline:GetText()'), 'Meet your quest route');
  assert.match(vm.evaluate('SpellmindNews.tagline:GetText()'), /plans your leveling for you/);
  assert.equal(vm.evaluate('SpellmindNews.features[2].title:GetText()'), 'Never lose your way');
  assert.equal(vm.evaluate('tostring(SpellmindNews.features[4].icon.shown)'), 'true');
  assert.match(vm.evaluate('SpellmindNews.note:GetText()'), /Questie/);
  assert.equal(vm.evaluate('SpellmindDB.seenVersion'), '0.5.0');
  // Each highlight below the last, with room between.
  const top = k => vm.num(`select(5, SpellmindNews.features[${k}].title:GetPoint())`);
  assert.ok(top(1) - top(2) >= 50, `room between: ${top(1) - top(2)}`);
  // Try it now: the route on, and its tab.
  vm.run('SpellmindNews.go.scripts.OnClick(SpellmindNews.go)');
  assert.ok(!news(vm));
  assert.equal(vm.evaluate('tostring(NS.Route.On())'), 'true');
  assert.equal(vm.evaluate('NS.Panel.tab'), 'route');
  // Not again for this version; /sm news shows it.
  vm.run('NS.Welcome.MaybeShow()');
  assert.ok(!news(vm));
  vm.slash('news');
  assert.ok(news(vm));
});

test('a new account: the welcome (which names the route), not What\'s new; an old account from before seenVersion gets it', () => {
  const fresh = newVM({ welcome: true, before: 'NS.VERSION = "0.5.0"' }).login().advance(7);
  assert.ok(open(fresh) && !news(fresh));
  // The welcome, 0.5.0 published (FRESH_SINCE 0.5.0): nothing newer, so what's always there, the
  // route first.
  assert.equal(fresh.evaluate('SpellmindWelcome.labels[1]:GetText()'), 'Works right away, no setup', 'no "New in" heading');
  assert.equal(fresh.evaluate('SpellmindWelcome.features[1].title:GetText()'), 'Your quest route');
  assert.equal(fresh.evaluate('SpellmindWelcome.features[2].title:GetText()'), 'A panel that knows your character');
  assert.equal(fresh.evaluate('SpellmindWelcome.appTitle:GetText()'), 'Even better with the free app');
  // What the app adds, each its own line in the box (the player, 2026-11-21).
  assert.equal(fresh.evaluate('SpellmindWelcome.appRows[1].title:GetText()'), 'Ask your own AI');
  assert.equal(fresh.evaluate('SpellmindWelcome.appRows[2].title:GetText()'), 'Break it down');
  assert.equal(fresh.evaluate('tostring(SpellmindWelcome.appBox.shown ~= false)'), 'true');
  // Try the route, from the welcome.
  assert.equal(fresh.evaluate('tostring(SpellmindWelcome.go.shown)'), 'true');
  fresh.run('SpellmindWelcome.go.scripts.OnClick(SpellmindWelcome.go)');
  assert.equal(fresh.evaluate('tostring(NS.Route.On())'), 'true');
  assert.equal(fresh.evaluate('NS.Panel.tab'), 'route');
  assert.equal(fresh.evaluate('SpellmindDB.seenVersion'), '0.5.0');
  const old = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true }', before: 'NS.VERSION = "0.5.0"' }).login().advance(7);
  assert.ok(news(old), 'welcomed before seenVersion existed: an update');
});

test('no news for this version: nothing shows, and the version is noted', () => {
  const vm = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.5.0" }', before: 'NS.VERSION = "0.5.1"' }).login().advance(7);
  assert.ok(!news(vm));
  assert.equal(vm.evaluate('SpellmindDB.seenVersion'), '0.5.1');
});


test('the welcome: highlights of the versions after the last public one first, then what\'s always there', () => {
  const vm = newVM({ welcome: true, before: `NS.VERSION = "0.6.1"
    table.insert(NS.Welcome.NEWS, { version = "0.6.1", features = { { icon = "x", title = "The way there", text = "Leg by leg." } } })` }).login().advance(7);
  assert.equal(vm.evaluate('SpellmindWelcome.labels[1]:GetText()'), 'New in 0.6.1');
  assert.equal(vm.evaluate('SpellmindWelcome.features[1].title:GetText()'), 'The way there');
  assert.equal(vm.evaluate('SpellmindWelcome.labels[2]:GetText()'), 'Works right away, no setup');
  assert.equal(vm.evaluate('SpellmindWelcome.features[2].title:GetText()'), 'Your quest route', '0.5.0 is public: no longer new');
});

test('a What\'s new taller than the screen is scaled down to fit', () => {
  const vm = newVM().login().advance(9);
  vm.run('UIParent.GetHeight = function() return 1200 end; NS.Welcome.ShowNews()');
  const full = vm.json('{ h = SpellmindNews:GetHeight(), s = SpellmindNews:GetScale() }');
  assert.equal(full.s, 1, 'room enough: full size');
  vm.run('UIParent.GetHeight = function() return 400 end; NS.Welcome.ShowNews()');
  const s = vm.json('{ h = SpellmindNews:GetHeight(), s = SpellmindNews:GetScale() }');
  assert.ok(s.h > 340, 'taller than the room: ' + s.h);
  assert.ok(Math.abs(s.h * s.s - 340) < 0.5, 'scaled to fit: ' + JSON.stringify(s));
});


// The history's lines as the player reads them.
const heads = vm => { const o = []; for (let k = 1; k <= 12; k++) { const x = vm.evaluate(`tostring(SpellmindNews.heads[${k}] and SpellmindNews.heads[${k}].shown and SpellmindNews.heads[${k}]:GetText())`); if (x !== 'false' && x !== 'nil') o.push(x.replace(/\|c\x66{2}[0-9a-f]{6}|\|cff[0-9a-f]{6}|\|r/g, '')); } return o; };

test('What\'s new (the player, 2026-11-20): the showcase of the newest release with a headline, then the version history newest first, the ones since your last look marked new', () => {
  const vm = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.5.0" }', before: 'NS.VERSION = "0.6.1"' }).login().advance(7);
  assert.ok(news(vm), 'a release with a headline since: it opens');
  assert.equal(vm.evaluate('SpellmindNews.title:GetText()'), "What's new in Spellmind 0.6.1");
  assert.equal(vm.evaluate('SpellmindNews.headline:GetText()'), 'Your class quests, planned', 'the showcase: 0.6.0, though 0.6.1 came after');
  assert.equal(vm.evaluate('SpellmindNews.features[1].title:GetText()'), 'Every class questline for you');
  assert.equal(vm.evaluate('SpellmindNews.alsoLabel:GetText()'), 'Version history');
  const h = heads(vm);
  assert.deepEqual(h, ['0.6.1  new', '0.6.0  Your class quests, planned  new', '0.5.0  Meet your quest route']);
  assert.match(vm.evaluate('SpellmindNews.changes[1]:GetText()'), /Skipping a step skips what needs it/);
  // In a scroll of its own: the window keeps its size.
  assert.ok(vm.num('SpellmindNews.hist:GetHeight()') <= 190);
  assert.equal(vm.evaluate('tostring(SpellmindNews.go.shown)'), 'true', 'its Try it now');
});

test('a fix alone (no headline since your last look) doesn\'t open What\'s new; /sm news has it in the history', () => {
  const vm = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.6.0" }', before: 'NS.VERSION = "0.6.1"' }).login().advance(7);
  assert.ok(!news(vm), 'quiet');
  assert.equal(vm.evaluate('SpellmindDB.seenVersion'), '0.6.1');
  vm.slash('news');
  assert.ok(news(vm));
  assert.equal(vm.evaluate('SpellmindNews.headline:GetText()'), 'Your class quests, planned');
  assert.equal(heads(vm)[0], '0.6.1', 'no "new" from /sm news');
});
