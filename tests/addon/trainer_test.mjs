// Milestone 10 (docs/milestone-10.md): the class trainer's list. Forever's spellbook shows no coming
// spells (seen in game), so the trainer's window is read when it opens and kept per character: the
// Spells tab, the "spells to train" nudge and the AI's spells part use it; a button beside the
// trainer's window lists what to learn and its cost. Nothing is learned.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };

// The rogue (level 15) knows Backstab 1, Sinister Strike 2 and Evasion. The book's own "coming"
// entries are taken out, as on Forever.
const TRAINER = `STUB.trainer = {
  { "Combat", "", "header", 0, 0 },
  { "Backstab", "Rank 2", "available", 300, 12 },
  { "Sinister Strike", "Rank 2", "used", 100, 6 },
  { "Sprint", "Rank 1", "available", 600, 10 },
  { "Kick", "Rank 2", "unavailable", 1000, 16 },
  { "Gouge", "Rank 2", "unavailable", 900, 18 },
  { "Evasion", "", "available", 0, 8 },
}`;
const NO_FUTURE = 'for _, t in ipairs(STUB.spellbook.tabs) do for i = #t.items, 1, -1 do if t.items[i].itemType == 2 then table.remove(t.items, i) end end end';

function session({ visit = true } = {}) {
  const vm = newVM();
  vm.run(NO_FUTURE);
  vm.login().advance(9);
  if (visit) {
    vm.run(TRAINER);
    vm.run('STUB.FireEvent("TRAINER_SHOW")');
    vm.advance(0.3);
  }
  return vm;
}

test('the trainer\'s window is read and kept: headers left out, ranks as numbers, cost and level', () => {
  const vm = session();
  const s = list(vm, 'NS.State.Me().trainer.services');
  assert.equal(s.length, 6, 'the header isn\'t a service');
  assert.deepEqual(s[0], { name: 'Backstab', rank: 2, kind: 'available', cost: 300, level: 12 });
  assert.equal(s[5].rank, undefined, 'Evasion has no rank');
});

test('the plan: due = learnable at your level and not in your spellbook; soon = the next by level', () => {
  const vm = session();
  const p = vm.json('NS.Trainer.Plan()');
  assert.deepEqual(list(vm, 'NS.Trainer.Plan().due').map(x => x.name), ['Sprint', 'Backstab'], 'by level; Evasion is known, Sinister Strike used');
  assert.equal(p.total, 900);
  assert.deepEqual(list(vm, 'NS.Trainer.Plan().soon').map(x => `${x.name}@${x.level}`), ['Kick@16', 'Gouge@18']);
});

test('the list is kept after the window closes, and a level up moves a spell from soon to due', () => {
  const vm = session();
  vm.run('STUB.trainer = nil; STUB.FireEvent("TRAINER_CLOSED")');
  vm.run('STUB.player.level = 16');
  assert.deepEqual(list(vm, 'NS.Trainer.Plan().due').map(x => x.name), ['Sprint', 'Backstab', 'Kick']);
});

test('a profession trainer\'s list isn\'t kept as the class trainer\'s', () => {
  const vm = session({ visit: false });
  vm.run(TRAINER);
  vm.run('STUB.tradeskillTrainer = true; STUB.FireEvent("TRAINER_SHOW")');
  vm.advance(0.3);
  assert.equal(vm.evaluate('tostring(NS.State.Me().trainer)'), 'nil');
});

test('the nudge: spells to train from the trainer\'s list when the book shows nothing coming', () => {
  const vm = session();
  vm.run('NS.Nudges.Check()');
  vm.advance(4);
  assert.equal(vm.evaluate('SpellmindNudge.title:GetText()'), '2 spells to train');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), 'Sprint (rank 1), Backstab (rank 2)');
});

test('the Spells tab: Train now with costs and the total, then Coming next with levels', () => {
  const vm = session();
  vm.run('NS.Panel.Show("spells")');
  const d = list(vm, 'SpellmindPanel.drawn');
  assert.equal(d[0].text, 'Train now: 9s');
  assert.ok(d.some(x => x.text === 'Backstab (rank 2)' && x.right === '3s' && x.tag === 'train now'));
  assert.ok(d.some(x => x.text === 'Coming next'));
  assert.ok(d.some(x => x.text === 'Kick (rank 2)' && x.right === 'level 16'));
  assert.ok(!d.some(x => /You have/.test(x.text || '')), 'enough gold: no warning');
});

test('the Spells tab without a visit says to open the trainer', () => {
  const vm = session({ visit: false });
  vm.run('NS.Panel.Show("spells")');
  assert.ok(list(vm, 'SpellmindPanel.drawn').some(x => /Open your class trainer once/.test(x.text || '')));
});

test('the button beside the trainer: what to learn, the total against your gold, what\'s next', () => {
  const vm = session();
  vm.run('STUB.player.money = 500');
  vm.run('NS.Trainer.button.scripts.OnClick(NS.Trainer.button)');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Spellmind: what to train');
  const text = list(vm, 'SpellmindCard.lines').join('\n');
  assert.match(text, /You can learn now, \|cffffd1009s\|r in all \|cffff6060\(you have 5s\)/);
  assert.match(text, /Sprint \(rank 1\): 6s/);
  assert.match(text, /level 18: Gouge \(rank 2\)/);
  vm.run('STUB.FireEvent("TRAINER_CLOSED")');
  assert.equal(vm.evaluate('tostring(SpellmindCard.shown)'), 'false');
});

test('the AI\'s spells part carries the trainer\'s due and soon lists, and the contract takes it', async () => {
  const vm = session();
  const part = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.State.Collect.spells())'));
  assert.deepEqual(part.trainer.due, [{ name: 'Sprint', rank: 1, cost: 600 }, { name: 'Backstab', rank: 2, cost: 300 }]);
  assert.deepEqual(part.trainer.soon[0], { name: 'Kick', rank: 2, level: 16 });
  const { validatePart } = await import('../../core/link/charstate.mjs');
  assert.equal(validatePart('spells', part).ok, true);
  assert.equal(validatePart('spells', { v: 1, trainer: { due: [{ name: 'Kick', cost: 'lots' }] } }).reason, 'field spells.trainer');
});

// Seen in game on Forever: the services' rank text came back empty, so Eviscerate (Rank 3) was taken
// for the Eviscerate 2 already known and left out; the AI then insisted it wasn't offered.
test('an empty rank (as on Forever): an offered spell you know a lower rank of is still due; the tooltip\'s "Rank 3" is read', () => {
  const vm = newVM();
  vm.run(NO_FUTURE);
  vm.run('table.insert(STUB.spellbook.tabs[2].items, { name = "Eviscerate", subName = "Rank 2", itemType = 1 }); STUB.player.level = 17');
  vm.login().advance(9);
  vm.run(`STUB.trainer = {
    { "Eviscerate", "", "available", 1500, 16 },
    { "Gouge", "", "unavailable", 1600, 18 },
    { "Pick Lock", "", "available", 1500, 16 },
  }
  C_TooltipInfo.GetTrainerService = function(i) if i == 1 then return { lines = { { leftText = "Eviscerate", rightText = "Rank 3" } } } end end
  STUB.FireEvent("TRAINER_SHOW")`);
  vm.advance(0.3);
  const s = list(vm, 'NS.State.Me().trainer.services');
  assert.equal(s[0].rank, 3, 'from the tooltip');
  assert.equal(s[1].rank, undefined, 'no rank anywhere');
  const p = vm.json('NS.Trainer.Plan()');
  assert.deepEqual(list(vm, 'NS.Trainer.Plan().due').map(x => x.name), ['Eviscerate', 'Pick Lock'], 'Eviscerate 3 due: the trainer says available');
  assert.deepEqual(list(vm, 'NS.Trainer.Plan().soon').map(x => x.name), ['Gouge'], 'Gouge 2 at 18, though Gouge 1 is known');
  assert.equal(p.total, 3000);
});
