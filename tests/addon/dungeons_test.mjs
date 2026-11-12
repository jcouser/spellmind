// Milestone 13 (docs/milestone-13.md): dungeon prep. The Dungeons tab: the instance you're in, the
// dungeons your quest log has quests for (the log's own headers), and the LFG tool's dungeons at
// your level when the client lists them. Brief asks the AI for a briefing; LFG puts a short line in
// the chat box. A nudge on entering a dungeon, gone when you leave.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };

// Old Ironforge Incursion, a Dungeon quest, under its own header in the log (as the game files it).
const HALL = `table.insert(STUB.quests, 11, { title = "The Hall of Thanes", isHeader = true })
C_QuestLog.GetQuestTagInfo = function(id) if id == 96393 then return { tagID = 81, tagName = "Dungeon" } end end`;

function session({ hall = true } = {}) {
  const vm = newVM();
  if (hall) vm.run(HALL);
  return vm.login().advance(9);
}
const drawn = vm => { vm.run('NS.Panel.Show("dungeons")'); return list(vm, 'SpellmindPanel.drawn'); };

test('the tab: second in the rail; your quests\' dungeons with their quests, level and Go', () => {
  const vm = session();
  const d = drawn(vm);
  assert.equal(vm.evaluate('SpellmindPanel.tabs[3].text:GetText()'), 'Dungeons');
  assert.equal(d[0].text, 'Your quests are for');
  assert.equal(d[1].text, 'The Hall of Thanes');
  assert.match(d[1].sub, /1 quest · level 16/);
  assert.equal(d[2].text, 'Old Ironforge Incursion');
  assert.equal(d[2].quest, 96393, 'with its Break it down mark');
  assert.ok(!d.some(x => x.text === 'At your level'), 'no LFG list on this client: no section');
});

test('Brief: the question names the dungeon, your level, role and class, and your quests for it; the answer in the card', () => {
  const vm = session();
  drawn(vm);
  vm.run('SpellmindPanel.rows[2].actions[2].scripts.OnClick(SpellmindPanel.rows[2].actions[2], "LeftButton")');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Advisor: Brief me: The Hall of Thanes');
  const q = vm.evaluate('NS.Dungeons.Briefing("The Hall of Thanes")');
  assert.match(q, /^Brief me for The Hall of Thanes as a level 15 DPS Rogue\./);
  assert.match(q, /My quests for it: Old Ironforge Incursion\./);
  assert.match(q, /the bosses in order with one tip each for my role/);
});

test('LFG for a dungeon: the short line, its leading "The" gone', () => {
  const vm = session();
  assert.equal(vm.evaluate('NS.Quests.LFGFor("The Hall of Thanes")'), 'LFG Hall of Thanes DPS Rogue');
  drawn(vm);
  vm.run('SpellmindPanel.rows[2].actions[1].scripts.OnClick(SpellmindPanel.rows[2].actions[1], "LeftButton")');
  assert.equal(vm.evaluate('tostring(SpellmindLFGMenu.shown)'), 'true', 'asks where, as on a quest');
});

test('no dungeon quests: says so; Brief my next one asks which fits', () => {
  const vm = session({ hall: false });
  const d = drawn(vm);
  assert.match(d[1].text, /No dungeon quests in your log/);
  assert.match(vm.evaluate('NS.Panel.NextDungeonQuestion()'), /^Which dungeons fit my level and class right now/);
});

test('the LFG tool\'s dungeons at your level, when the client lists them (a dungeon far above is left out)', () => {
  const vm = newVM();
  vm.run('STUB.lfg = { { 1, "The Deadmines", 18, 23 }, { 2, "Wailing Caverns", 17, 24 }, { 3, "Scarlet Monastery", 30, 40 }, { 4, "Ragefire Chasm", 13, 18 } }; STUB.UseLFG()');
  vm.login().advance(9);
  const d = drawn(vm);
  const at = d.findIndex(x => x.text === 'At your level');
  assert.ok(at > 0);
  assert.deepEqual(d.slice(at + 1).map(x => `${x.text} ${x.right}`), ['Ragefire Chasm 13–18', 'Wailing Caverns 17–24', 'The Deadmines 18–23']);
});

test('entering a dungeon: a nudge with your quests there and a briefing to ask; the tab says where you are; leaving drops it', () => {
  const vm = session();
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)'); // the spells one
  vm.run('STUB.instance = { name = "The Hall of Thanes", type = "party", diff = "Normal" }; STUB.FireEvent("PLAYER_ENTERING_WORLD")');
  vm.advance(4);
  assert.equal(vm.evaluate('SpellmindNudge.title:GetText()'), 'Entering The Hall of Thanes');
  assert.equal(vm.evaluate('SpellmindNudge.text:GetText()'), '1 of your quests here. Want a briefing?');
  const d = drawn(vm);
  assert.equal(d[0].text, 'You\'re in The Hall of Thanes');
  assert.match(d[1].sub, /1 of your quests here · Normal/);
  vm.run('STUB.instance = nil; STUB.FireEvent("PLAYER_ENTERING_WORLD")');
  vm.advance(4);
  assert.ok(!list(vm, 'NS.Nudges.List()').some(n => n.kind === 'dungeon'), 'out of it: gone');
});

test('the dungeon nudge has its own switch in Settings', () => {
  const vm = session();
  vm.run('NS.Settings.Flip("nudge:dungeon")');
  vm.run('SpellmindNudge.dismiss.scripts.OnClick(SpellmindNudge.dismiss)');
  vm.run('STUB.instance = { name = "The Hall of Thanes", type = "party" }; STUB.FireEvent("PLAYER_ENTERING_WORLD")');
  vm.advance(4);
  assert.ok(!list(vm, 'NS.Nudges.List()').some(n => n.kind === 'dungeon'));
});

test('a login inside a dungeon stays quiet until the first look, then nudges', () => {
  const vm = newVM();
  vm.run(HALL);
  vm.run('STUB.instance = { name = "The Hall of Thanes", type = "party" }');
  vm.login().advance(3);
  assert.equal(list(vm, 'NS.Nudges.List()').length, 0);
  vm.advance(6);
  assert.equal(list(vm, 'NS.Nudges.List()')[0].title, 'Entering The Hall of Thanes');
});
