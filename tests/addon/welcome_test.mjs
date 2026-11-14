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
