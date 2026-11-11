// Milestone 7 (docs/milestone-7.md): the Advisor panel. Side tabs; the Quests tab sorted into ready,
// worth doing now, later and grey with each quest's mark; the Gear tab's worn items, bag items with
// the tooltip line's verdicts, and empty slots; the other tabs' facts; the Ask buttons' answers in
// the card beside the panel; live redraws; the minimap button's right-click and /sm panel.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
const drawn = vm => list(vm, 'SpellmindPanel.drawn');
const session = () => newVM().login().advance(3.1);

test('opens from the minimap button\'s right-click and /sm panel; the header says who', () => {
  const vm = session();
  vm.run('SpellmindMinimapButton.scripts.OnClick(SpellmindMinimapButton, "RightButton")');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.shown)'), 'true');
  assert.equal(vm.evaluate('SpellmindPanel.title:GetText()'), 'Spellmind Advisor');
  assert.equal(vm.evaluate('SpellmindPanel.who:GetText()'), 'Level 15 · Dwarf Rogue');
  vm.slash('panel');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.shown)'), 'false', '/sm panel toggles');
  vm.slash('panel');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.shown)'), 'true');
  assert.equal(vm.num('#SpellmindPanel.tabs'), 7, 'six, and Nudges');
});

test('Quests: ready to turn in, worth doing now, later (orange), each with its level, a hint and a Break it down mark', () => {
  const vm = session();
  vm.run('NS.Panel.Show("quests")');
  const d = drawn(vm);
  const heads = d.filter(x => x.kind === 'head').map(x => x.text);
  assert.deepEqual(heads, ['Ready to turn in', 'Worth doing now', 'Later']);
  const after = h => d.slice(d.findIndex(x => x.text === h) + 1).filter((x, i, a) => i < (a.findIndex(y => y.kind === 'head') + 1 || a.length) && x.kind === 'item');
  const ready = after('Ready to turn in').map(x => x.text);
  assert.ok(ready.some(t => /Stormpike's Order/.test(t)), JSON.stringify(ready));
  assert.ok(after('Ready to turn in').every(x => /ready to turn in/.test(x.right)));
  const later = after('Later');
  assert.ok(later.some(x => /\[18\]\|r Gathering Idols/.test(x.text) && /on your map · 560 yd/.test(x.right)), JSON.stringify(later));
  assert.ok(after('Worth doing now').some(x => /Bingles' Missing Supplies/.test(x.text)));
  assert.ok(d.filter(x => x.kind === 'item').every(x => typeof x.quest === 'number'), 'every quest row has its mark');
  assert.equal(vm.evaluate('SpellmindPanel.asks[1].text:GetText()'), 'Ask: Plan my next hour');
});

test('Gear: worn items in slot order with item level and dps, the bow tagged "needs Bows skill", empty slots', () => {
  const vm = session();
  vm.run('table.insert(STUB.bags[2].items, { 2504, 1 })'); // the bow into a bag
  vm.run('NS.Panel.Show("gear")');
  const d = drawn(vm);
  const worn = d.filter(x => x.kind === 'item').slice(0, 3).map(x => x.text);
  assert.match(worn[0], /^Chest · \|cff1eff00Simple Robe of the Monkey/);
  assert.match(worn[2], /^Main Hand · .*Craftsman's Dagger/);
  assert.match(d.find(x => /Craftsman's Dagger/.test(x.text)).right, /ilvl 15 · 6\.1 dps/);
  const bow = d.find(x => /Worn Shortbow/.test(x.text || ''));
  assert.ok(bow, JSON.stringify(d.map(x => x.text)));
  assert.equal(bow.tag, 'needs Bows skill');
  assert.ok(d.some(x => x.kind === 'head' && /^In your bags \(\d+ of \d+ free\)$/.test(x.text)));
  const empty = d[d.findIndex(x => x.text === 'Empty slots') + 1].text;
  assert.match(empty, /^Head, Neck, Shoulder, Waist/);
  assert.doesNotMatch(empty, /Shirt|Tabard/, 'cosmetic slots aren\'t "empty"');
});

test('the other tabs: talents, the spells coming (train now when due), professions near their cap, gold and bag space', () => {
  const vm = session();
  vm.run('NS.Panel.Show("talents")');
  assert.ok(drawn(vm).some(x => x.text === 'Malice' && x.right === '1 / 3'));
  vm.run('NS.Panel.Show("spells")');
  const sprint = drawn(vm).find(x => /Sprint/.test(x.text || ''));
  assert.equal(sprint.tag, 'train now', 'level 10 spell at level 15');
  assert.equal(drawn(vm).find(x => /Kick/.test(x.text || '')).tag, undefined, 'level 16: not yet');
  vm.run('NS.Panel.Show("professions")');
  assert.ok(drawn(vm).some(x => x.text === 'Leatherworking' && x.right === '61 / 75'));
  vm.run('NS.Panel.Show("gold")');
  assert.ok(drawn(vm).some(x => x.text === 'On you' && /98s/.test(x.right)));
  assert.equal(vm.evaluate('SpellmindDB.panel.tab'), 'gold', 'the tab is remembered');
});

test('an Ask button: asked in the chat, its answer in the card beside the panel; closing the panel closes the card', () => {
  const vm = session();
  vm.run('NS.Panel.Show("gear")');
  vm.run('SpellmindPanel.asks[1].scripts.OnClick(SpellmindPanel.asks[1])');
  assert.equal(vm.evaluate('tostring(SpellmindCard.shown)'), 'true');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Advisor: Any upgrades?');
  assert.equal(vm.evaluate('tostring(SpellmindCard.anchor.rel == SpellmindPanel)'), 'true');
  assert.ok(vm.savedLines().some(l => /Advisor: Any upgrades\?/.test(l)), 'the chat keeps the question');
  vm.run('NS.Panel.Show("gear")'); // a redraw (rows hidden and shown again) keeps the card
  assert.equal(vm.evaluate('tostring(SpellmindCard.shown)'), 'true');
  vm.run('SpellmindPanel:Hide()');
  assert.equal(vm.evaluate('tostring(SpellmindCard.shown)'), 'false');
});

test('live: a game event redraws an open panel once, a second later', () => {
  const vm = session();
  vm.run('NS.Panel.Show("gold")');
  vm.run('STUB.player.money = 25000; STUB.FireEvent("PLAYER_MONEY"); STUB.FireEvent("PLAYER_MONEY")');
  assert.ok(!drawn(vm).some(x => /2g/.test(x.right || '')), 'not yet');
  vm.advance(1.1);
  assert.ok(drawn(vm).some(x => x.text === 'On you' && /2g/.test(x.right)), JSON.stringify(drawn(vm)));
});
