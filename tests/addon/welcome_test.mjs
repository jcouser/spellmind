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
  assert.notEqual(fresh.evaluate('tostring(SpellmindWelcome.labels[1] and SpellmindWelcome.labels[1].shown)'), 'true', 'no "New in" heading');
  assert.equal(fresh.evaluate('SpellmindWelcome.features[1].title:GetText()'), 'Your quest route');
  assert.equal(fresh.evaluate('SpellmindWelcome.features[2].title:GetText()'), 'A panel that knows your character');
  assert.equal(fresh.evaluate('SpellmindWelcome.appTitle:GetText()'), 'Ask your own AI');
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

test('What\'s new: the changes under the highlights; a version with only changes says "What\'s changed"; skipped versions\' changes too', () => {
  const vm = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.4.7" }', before: 'NS.VERSION = "0.5.0"' }).login().advance(7);
  assert.equal(vm.evaluate('SpellmindNews.alsoLabel:GetText()'), 'Also in this update');
  assert.match(vm.evaluate('SpellmindNews.changes[1]:GetText()'), /Review my route/);
  // Two versions later, the second with only changes.
  const v2 = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.4.7" }', before: `NS.VERSION = "0.5.1"
    table.insert(NS.Welcome.NEWS, { version = "0.5.1", changes = { "The arrow turns smoother." } })` }).login().advance(7);
  assert.equal(v2.evaluate('SpellmindNews.headline:GetText()'), 'Meet your quest route', 'skipped 0.5.0: its headline leads');
  assert.equal(v2.evaluate('SpellmindNews.features[1].title:GetText()'), 'A plan that knows your character', 'and its highlights');
  assert.match(v2.evaluate('SpellmindNews.changes[1]:GetText()'), /0\.5\.1.*The arrow turns smoother/);
  assert.match(v2.evaluate('SpellmindNews.changes[2]:GetText()'), /0\.5\.0.*Review my route/);
  assert.equal(v2.evaluate('tostring(SpellmindNews.go.shown)'), 'true', 'the route to try');
  // Seen 0.5.0, then 0.5.1 alone: only its changes.
  const v3 = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.5.0" }', before: `NS.VERSION = "0.5.1"
    table.insert(NS.Welcome.NEWS, { version = "0.5.1", changes = { "The arrow turns smoother." } })` }).login().advance(7);
  assert.equal(v3.evaluate('SpellmindNews.headline:GetText()'), 'What\'s changed');
  assert.equal(v3.evaluate('tostring(SpellmindNews.go.shown)'), 'false', 'nothing to try');
});

test('the welcome: highlights of the versions after the last public one first, then what\'s always there', () => {
  const vm = newVM({ welcome: true, before: `NS.VERSION = "0.6.1"
    table.insert(NS.Welcome.NEWS, { version = "0.6.1", features = { { icon = "x", title = "The way there", text = "Leg by leg." } } })` }).login().advance(7);
  assert.equal(vm.evaluate('SpellmindWelcome.labels[1]:GetText()'), 'New in 0.6.1');
  assert.equal(vm.evaluate('SpellmindWelcome.features[1].title:GetText()'), 'The way there');
  assert.equal(vm.evaluate('SpellmindWelcome.labels[2]:GetText()'), 'Always in Spellmind');
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

test('What\'s new across versions: the newest headline\'s highlights alone, an older headline in one line; /sm news, this version\'s (the player, 2026-11-20)', () => {
  const vm = newVM({ welcome: true, db: 'SpellmindDB = { welcomed = true, seenVersion = "0.4.7" }', before: 'NS.VERSION = "0.6.0"' }).login().advance(7);
  const feats = [1, 2, 3, 4, 5].map(k => vm.evaluate(`tostring(SpellmindNews.features[${k}] and SpellmindNews.features[${k}].shown and SpellmindNews.features[${k}].title:GetText())`));
  assert.equal(vm.evaluate('SpellmindNews.headline:GetText()'), 'Your class quests, planned');
  assert.ok(!feats.includes('A plan that knows your character'), '0.5.0\'s highlights not again: ' + feats);
  const lines = []; for (let k = 1; k <= 12; k++) { const t = vm.evaluate(`tostring(SpellmindNews.changes[${k}] and SpellmindNews.changes[${k}].shown and SpellmindNews.changes[${k}]:GetText())`); if (t !== 'false' && t !== 'nil') lines.push(t); }
  assert.ok(lines.some(l => /0\.5\.0.*Meet your quest route/.test(l)), '0.5.0 in one line: ' + lines.join(' / '));
  assert.ok(!lines.some(l => /Plan my next hour/.test(l)), 'not its changes');
  // /sm news: this version's alone.
  vm.run('SpellmindNews:Hide()');
  vm.slash('news');
  const after = []; for (let k = 1; k <= 12; k++) { const t = vm.evaluate(`tostring(SpellmindNews.changes[${k}] and SpellmindNews.changes[${k}].shown and SpellmindNews.changes[${k}]:GetText())`); if (t !== 'false' && t !== 'nil') after.push(t); }
  assert.ok(!after.some(l => /0\.5\.0|Meet your quest route/.test(l)), after.join(' / '));
  assert.ok(after.some(l => /keeps its order/.test(l)));
});
