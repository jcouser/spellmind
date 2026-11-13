// Milestone 15 (docs/milestone-15.md): the player's guide. A link set once (/sm guide, or Set link);
// Import sends guide=1; the reply's plan is kept per character; the Talents tab tracks it against the
// character's own talents (next points, off plan, names the tree doesn't have); the nudge names the
// pick; the Spells tab shows its priority; the AI gets it in the talents part.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';
import { validatePart } from '../../core/link/charstate.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
const URL = 'https://mobalytics.gg/wow-forever/classes/rogue-leveling-guide';

// The stub rogue has Malice 1/3, Improved Sinister Strike 2/2 and Lightning Reflexes 3/5.
const PLAN = `NS.Chat.OnRecord({ t = "reply", text = "Imported Combat from mobalytics.gg.", plan = {
  title = "WoW Forever Rogue Leveling Guide", build = "Combat", builds = { "Combat", "Assassination" }, source = "mobalytics.gg", url = "${URL}",
  talents = {
    { level = 10, name = "Improved Sinister Strike", rank = 1 }, { level = 11, name = "Improved Sinister Strike", rank = 2 },
    { level = 12, name = "Malice", rank = 1 }, { level = 13, name = "Malice", rank = 2 }, { level = 14, name = "Improved Gouge", rank = 1 },
    { level = 15, name = "Flash of Steel", rank = 1 }, { level = 16, name = "Malice", rank = 3 } },
  rotation = { "Riposte when it lights up", "Slice and Dice at 2+ combo points", "Sinister Strike" },
  stats = { "Agility", "Strength", "Attack Power" }, weapons = "A slow main hand and a fast off hand." } })`;

const session = () => newVM().login().advance(3.1);
const drawn = (vm, tab) => { vm.run(`NS.Panel.Show("${tab}")`); return list(vm, 'SpellmindPanel.drawn'); };

test('no guide yet: the Talents tab says so with Set link; /sm guide <link> keeps the link and sends the import with guide=1', () => {
  const vm = session();
  const d = drawn(vm, 'talents');
  assert.equal(d[1].text, 'No guide yet');
  vm.slash(`guide ${URL}`);
  assert.equal(vm.evaluate('NS.State.Me().guide.url'), URL);
  // The record as it goes: its fields split by the unit separator; args then text.
  const f = vm.outbox().at(-1).wire.split('\u001f');
  assert.equal(f[3], 'msg');
  assert.match(f[5], /(^|;)guide=1(;|$)/);
  assert.equal(f[6], `Import my guide: ${URL}`);
  vm.slash('guide not-a-link');
  assert.ok(vm.chatLines().some(l => /that isn't an https:\/\/ link/.test(l)));
});

test('the link box: paste, Import; a bad link says so and stays open', () => {
  const vm = session();
  vm.run('NS.Panel.Show("talents")');
  vm.run('NS.Guide.AskLink(SpellmindPanel)');
  vm.run('SpellmindGuideBox.input:SetText("nope"); SpellmindGuideBox.ok.scripts.OnClick(SpellmindGuideBox.ok)');
  assert.match(vm.evaluate('SpellmindGuideBox.note:GetText()'), /isn't an https:\/\/ link/);
  vm.run(`SpellmindGuideBox.input:SetText("${URL}"); SpellmindGuideBox.ok.scripts.OnClick(SpellmindGuideBox.ok)`);
  assert.equal(vm.evaluate('tostring(SpellmindGuideBox.shown)'), 'false');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Import mobalytics.gg', 'the answer in the card beside the window');
});

test('an imported plan: the next points against your talents, spent ones skipped; off plan and names not in your tree flagged', () => {
  const vm = session();
  vm.run(PLAN);
  const p = vm.json('NS.Guide.Progress()');
  assert.equal(p.done, 3, 'Improved Sinister Strike 2/2 and Malice 1 are taken');
  assert.deepEqual(list(vm, 'NS.Guide.Progress().next').map(s => `${s.level} ${s.name} ${s.rank}`), ['13 Malice 2', '14 Improved Gouge 1', '15 Flash of Steel 1', '16 Malice 3']);
  assert.deepEqual(list(vm, 'NS.Guide.Progress().off').map(o => o.name), ['Lightning Reflexes']);
  assert.deepEqual(list(vm, 'NS.Guide.Progress().unknown'), ['Flash of Steel'], 'not in the tree: shown, never quietly followed');
  const d = drawn(vm, 'talents');
  assert.equal(d[0].text, 'Your guide: Combat');
  assert.match(d[1].sub, /3 of 7 points taken/);
  assert.equal(d[2].text, 'Next points');
  assert.match(d[3].text, /Malice 2\/3/, 'counted to the tree\'s top rank');
  assert.match(d[3].right, /behind: the guide takes it at 13/, 'level 15 with no point left for it');
  assert.ok(d.some(x => /Off plan:.*Lightning Reflexes 3/.test(x.text || '') && /doesn't take it/.test(x.sub)));
  assert.ok(d.some(x => /Not in your talents: Flash of Steel/.test(x.text || '')));
  assert.ok(d.some(x => x.text === 'Assassination'), 'the page\'s other build, to import instead');
});

test('points to spend: the steps you can take now are green and tagged; the nudge names the pick', () => {
  const vm = newVM();
  vm.run('STUB.talents.currency[1].quantity = 2');
  vm.login().advance(3.1);
  vm.run(PLAN);
  const d = drawn(vm, 'talents');
  assert.equal(d[2].text, 'Spend your 2 points');
  assert.equal(d[3].tag, 'now');
  assert.equal(d[4].tag, 'now');
  assert.equal(d[5].tag, undefined, 'a third step: only 2 points');
  vm.advance(6);
  assert.equal(vm.evaluate('SpellmindNudge.title:GetText()'), '2 talent points to spend');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), 'Your guide: Malice 2/3.');
});

test('the Spells tab shows the guide\'s priority, stats and weapons; the AI gets the guide in the talents part, valid', () => {
  const vm = session();
  vm.run(PLAN);
  const d = drawn(vm, 'spells');
  assert.ok(d.some(x => x.text === 'Your guide\'s priority'));
  assert.ok(d.some(x => x.text === '2. Slice and Dice at 2+ combo points'));
  assert.ok(d.some(x => x.text === 'Agility > Strength > Attack Power'));
  const part = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.State.Collect.talents())'));
  assert.equal(part.guide.build, 'Combat');
  assert.equal(part.guide.next[0], 'Malice 2/3');
  assert.equal(validatePart('talents', part).ok, true);
});

test('a new link forgets the old plan', () => {
  const vm = session();
  vm.run(PLAN);
  vm.run('NS.Guide.SetUrl("https://example.com/other-guide")');
  assert.equal(vm.evaluate('tostring(NS.Guide.Get().plan)'), 'nil');
  assert.equal(drawn(vm, 'talents')[1].sub.includes('Not imported yet'), true);
});

test('behind and early (seen in game: 8 points at 17, not the guide\'s first 8): the skipped steps say so in orange, the early picks are shown', () => {
  const vm = newVM();
  vm.run('STUB.player.level = 13');
  vm.login().advance(3.1);
  // The guide: Improved Gouge at 10 and 11, then the rogue's Malice and Improved Sinister Strike later.
  vm.run(`NS.Chat.OnRecord({ t = "reply", text = "Imported.", plan = { build = "Combat", source = "mobalytics.gg", talents = {
    { level = 10, name = "Improved Gouge", rank = 1 }, { level = 11, name = "Improved Gouge", rank = 2 },
    { level = 14, name = "Improved Sinister Strike", rank = 1 }, { level = 15, name = "Improved Sinister Strike", rank = 2 },
    { level = 16, name = "Malice", rank = 1 }, { level = 17, name = "Lightning Reflexes", rank = 1 } } } })`);
  const p = vm.json('NS.Guide.Progress()');
  assert.equal(p.behind, 2);
  assert.deepEqual(list(vm, 'NS.Guide.Progress().early').map(e => `${e.name} ${e.rank} ${e.from}-${e.to}`),
    ['Improved Sinister Strike 2 14-15', 'Malice 1 16-16', 'Lightning Reflexes 1 17-17']);
  const d = drawn(vm, 'talents');
  const gouge = d.find(x => /Improved Gouge 1\/2/.test(x.text || ''));
  assert.match(gouge.right, /behind: the guide takes it at 10/);
  assert.equal(gouge.tag, undefined, 'no point to spend: not "now"');
  assert.ok(d.some(x => /Your next points go here first/.test(x.text || '')));
  const early = d.find(x => /Taken early:.*Improved Sinister Strike 2/.test(x.text || ''));
  assert.match(early.sub, /takes it at level 14 to 15/);
});
