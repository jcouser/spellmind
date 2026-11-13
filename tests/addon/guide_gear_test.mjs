// Milestone 16 (docs/milestone-16.md): the guide reaches gear and spells. Its stat priority weighs
// gear comparisons (scaled per point), its weapon advice leans weapon picks by speed, and its ability
// priority says which abilities you have or train later. With Questie, the turn-in nudges start off.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
const session = () => newVM().login().advance(3.1);
const plan = (fields) => `NS.Chat.OnRecord({ t = "reply", text = "Imported.", plan = { build = "Combat", source = "mobalytics.gg", talents = {}, ${fields} } })`;

test('the guide\'s stats as weights: in its order, per point (Attack Power half of Agility), stats it doesn\'t name at nothing', () => {
  const vm = session();
  assert.equal(vm.evaluate('tostring(select(2, NS.Gear.Weights()))'), 'false', 'no guide: the class\'s own');
  vm.run(plan('stats = { "Agility", "Strength", "Attack Power", "Stamina", "Hit Chance", "Expertise", "Critical Strike" }'));
  assert.deepEqual(list(vm, 'NS.Gear.GuideOrder(NS.Guide.Get().plan.stats)'), ['agi', 'str', 'ap', 'sta', 'hit', 'crit'], 'Expertise has no item stat here');
  assert.equal(vm.evaluate('tostring(select(2, NS.Gear.Weights()))'), 'true');
  assert.equal(vm.num('NS.Gear.Weights().agi'), 2);
  assert.equal(vm.evaluate('string.format("%.2f", NS.Gear.Weights().ap)'), '0.76', 'third of six: 1.52, times 0.5 a point');
  assert.equal(vm.evaluate('string.format("%.1f", NS.Gear.Weights().crit)'), '8.0', 'last: 0.8, times 10 a point');
  assert.equal(vm.num('NS.Gear.Weights().dps'), 3, 'weapon damage keeps the class\'s weight');
  assert.equal(vm.evaluate('tostring(NS.Gear.Weights().int)'), 'nil');
});

test('the weapon advice leans by speed: a slower main hand, a faster off hand, a tie-breaker in size', () => {
  const vm = session();
  vm.run(plan('weapons = "Keep weapons upgraded; prioritize a slower main hand and a faster off hand."'));
  assert.equal(vm.evaluate('NS.Gear.SpeedAdvice().main'), 'slow');
  assert.equal(vm.evaluate('NS.Gear.SpeedAdvice().off'), 'fast');
  vm.run('NS.Gear.Speed = function(link) return link == "slow" and 2.6 or 1.5 end');
  assert.equal(vm.evaluate('string.format("%.1f", NS.Gear.SpeedLean("slow", 16))'), '1.2');
  assert.equal(vm.evaluate('string.format("%.1f", NS.Gear.SpeedLean("fast", 17))'), '1.0');
  assert.equal(vm.evaluate('string.format("%.1f", NS.Gear.SpeedLean("fast", 16))'), '-1.0', 'a fast main hand leans against');
  assert.equal(vm.num('NS.Gear.SpeedLean("slow", 5)'), 0, 'not a weapon slot');
});

test('a weapon\'s speed from the game\'s tooltip data', () => {
  const vm = session();
  vm.run('C_TooltipInfo.GetHyperlink = function() return { lines = { { leftText = "Worn Shortsword" }, { leftText = "One-Hand", rightText = "Sword" }, { leftText = "3 - 7 Damage", rightText = "Speed 1.90" } } } end');
  assert.equal(vm.num('NS.Gear.Speed("x")'), 1.9);
});

test('the guide\'s priority on the Spells tab: abilities you have, ones your trainer teaches later, the longest name matched', () => {
  const vm = session();
  vm.run('STUB.trainer = { { "Slice and Dice", "Rank 1", "unavailable", 300, 20 }, { "Slice", "Rank 1", "unavailable", 1, 30 } }; STUB.FireEvent("TRAINER_SHOW")');
  vm.advance(0.3);
  vm.run(plan('rotation = { "Riposte when it lights up", "Slice and Dice at 2+ combo points", "Sinister Strike" }'));
  const p = list(vm, 'NS.Guide.Priority()');
  assert.equal(p[0].have, undefined, 'Riposte: a talent not taken, not in the trainer\'s list');
  assert.equal(p[1].train, 'Slice and Dice');
  assert.equal(p[1].level, 20);
  assert.equal(p[2].have, 'Sinister Strike');
  vm.run('NS.Panel.Show("spells")');
  const d = list(vm, 'SpellmindPanel.drawn');
  assert.ok(d.some(x => x.text === '2. Slice and Dice at 2+ combo points' && /Slice and Dice: trains at 20/.test(x.right)));
  assert.ok(d.some(x => x.text === '3. Sinister Strike' && /you have it/.test(x.right)));
});

test('with Questie loaded, the turn-in nudges start off; turning one on sticks; without Questie they start on', () => {
  const vm = newVM();
  vm.run('STUB.loaded.Questie = true');
  vm.login().advance(3.1);
  assert.equal(vm.evaluate('tostring(NS.Nudges.KindOn("turnin"))'), 'false');
  assert.equal(vm.evaluate('tostring(NS.Nudges.KindOn("near"))'), 'false');
  assert.equal(vm.evaluate('tostring(NS.Nudges.KindOn("bags"))'), 'true');
  vm.run('NS.Settings.Flip("nudge:turnin")');
  assert.equal(vm.evaluate('tostring(NS.Nudges.KindOn("turnin"))'), 'true', 'the player\'s pick wins');
  const plain = session();
  assert.equal(plain.evaluate('tostring(NS.Nudges.KindOn("turnin"))'), 'true');
});

test('the Spells tab: what the trainer has now, the ones your guide uses first and marked (the review)', () => {
  const vm = session();
  vm.run('for _, t in ipairs(STUB.spellbook.tabs) do for i = #t.items, 1, -1 do if t.items[i].itemType == 2 then table.remove(t.items, i) end end end');
  vm.run('STUB.trainer = { { "Sprint", "Rank 1", "available", 600, 10 }, { "Slice and Dice", "Rank 1", "available", 300, 10 } }; STUB.FireEvent("TRAINER_SHOW")');
  vm.advance(0.3);
  vm.run(plan('rotation = { "Slice and Dice at 2+ combo points", "Sinister Strike" }'));
  vm.run('NS.Panel.Show("spells")');
  const d = list(vm, 'SpellmindPanel.drawn');
  assert.equal(d[0].text, 'At your trainer now: 9s');
  assert.match(d[1].text, /Slice and Dice/);
  assert.equal(d[1].tag, 'in your guide');
  assert.equal(d[2].tag, undefined, 'Sprint: not in the guide');
});
