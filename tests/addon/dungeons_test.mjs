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
  assert.match(d[1].sub, /1 in your log · level 16/);
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
  assert.deepEqual(d.slice(at + 1).filter(x => x.kind === 'item').map(x => `${x.text} ${x.right}`), ['Ragefire Chasm 13–18', 'Wailing Caverns 17–24', 'The Deadmines 18–23']);
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
  assert.match(d[1].sub, /Normal/);
  assert.equal(d[2].text, 'Old Ironforge Incursion', 'your quest for it, under it');
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

// With QuestieDB installed: each dungeon's quests for this character, from its public API.
function withDB({ lfg = false } = {}) {
  const vm = newVM();
  vm.run(HALL);
  vm.run('STUB.UseQuestieDB(); STUB.completed[96390] = true');
  if (lfg) vm.run('STUB.lfg = { { 1, "Hall of Thanes", 13, 20 }, { 2, "Deadmines", 17, 26 } }; STUB.UseLFG(); STUB.completed[1001] = true; STUB.completed[1002] = true');
  vm.login().advance(9);
  vm.run('NS.Panel.Show("dungeons")');
  vm.advance(1); // QuestieDB's quests are read a few hundred a frame, then the tab redraws
  return vm;
}

test('QuestieDB: what you haven\'t picked up, who gives it and where; locked ones say what opens them; done and in-log counted', () => {
  const vm = withDB();
  const d = drawn(vm);
  const hall = d.find(x => x.text === 'The Hall of Thanes');
  assert.match(hall.sub, /^.cff888888level 16 · .cffffd1001 to pick up.r · 2 later · 1 in your log · 1 done/);
  const oh = d.find(x => x.text === 'Oh Brother...');
  assert.match(oh.sub, /^.cffffd100Pick up.r · /, 'ready: "Pick up" leads its line');
  assert.equal(oh.tag, undefined, 'no tag: it read as a button');
  assert.match(oh.sub, /from Thane Ironbelly, Ironforge \(45, 51\)/);
  const under = d.find(x => x.text === 'Underground Assault');
  assert.match(under.sub, /after Oh Brother\.\.\./);
  assert.equal(under.tag, undefined, 'not yet: no "pick up" tag');
  const vault = d.find(x => x.text === 'The Deep Vault');
  assert.match(vault.sub, /at level 22/);
  for (const other of ['A Horde Errand', 'A Warrior\'s Trial', 'Shadowy Orders', 'Collecting Memories', 'Elwynn Wolves'])
    assert.ok(!d.some(x => x.text === other), `${other}: another race, class or faction, done, or another zone`);
});

test('QuestieDB: a dungeon with every quest done says so; the LFG list\'s "Hall of Thanes" is your log\'s "The Hall of Thanes"', () => {
  const vm = withDB({ lfg: true });
  const d = drawn(vm);
  assert.equal(d.filter(x => /Hall of Thanes$/.test(x.text || '')).length, 1, 'one row, not two');
  const dm = d.find(x => x.text === 'Deadmines');
  assert.match(dm.sub, /All 2 quests done/);
});

test('QuestieDB: the briefing names the quests to pick up and who gives them', () => {
  const vm = withDB();
  const q = vm.evaluate('NS.Dungeons.Briefing("The Hall of Thanes")');
  assert.match(q, /Quests for it I haven't picked up: Oh Brother\.\.\. \(from Thane Ironbelly, Ironforge \(45, 51\)\); Underground Assault \(from Thane Ironbelly, Ironforge \(45, 51\)\) after Oh Brother\.\.\./);
  assert.match(q, /Already done: Collecting Memories\./);
  assert.match(q, /the best order to pick up the missing quests/);
});

test('QuestieDB: an at-your-level dungeon\'s quests open under it on Quests, and close on Hide', () => {
  const vm = newVM();
  vm.run('STUB.UseQuestieDB(); STUB.lfg = { { 1, "Hall of Thanes", 13, 20 } }; STUB.UseLFG()');
  vm.login().advance(9);
  vm.run('NS.Panel.Show("dungeons")');
  vm.advance(1);
  let d = drawn(vm);
  const i = d.findIndex(x => x.text === 'Hall of Thanes');
  assert.match(d[i].sub, /to pick up/);
  assert.ok(!d.some(x => x.text === 'Oh Brother...'), 'closed at first');
  vm.run(`SpellmindPanel.rows[${i + 1}].actions[1].scripts.OnClick(SpellmindPanel.rows[${i + 1}].actions[1], "LeftButton")`);
  d = list(vm, 'SpellmindPanel.drawn');
  assert.ok(d.some(x => x.text === 'Oh Brother...'));
  assert.equal(vm.evaluate(`SpellmindPanel.rows[${i + 1}].actions[1].text:GetText()`), 'Hide');
});

test('without QuestieDB: a line says what it would add', () => {
  const vm = session();
  assert.ok(drawn(vm).some(x => /With the QuestieDB addon installed/.test(x.text || '')));
});

// The Deadmines' chain as seen in game: its last step and Red Silk Bandanas wait on The Defias
// Brotherhood, whose first steps (same name) start in Westfall, outside the dungeon.
const DEFIAS = `STUB.qdb.npcs[902] = { name = "Gryan Stoutmantle", zone = 40, spawns = { [40] = { { 56, 47.6 } } }, friendly = "A" }
STUB.qdb.quests[2040] = { name = "The Defias Brotherhood", zone = 40, level = 14, npc = 902 }
STUB.qdb.quests[2041] = { name = "The Defias Brotherhood", zone = 40, level = 16, npc = 902, single = { 2040 } }
STUB.qdb.quests[2042] = { name = "The Defias Brotherhood", zone = 1581, level = 22, npc = 902, single = { 2041 } }
STUB.qdb.quests[2043] = { name = "Red Silk Bandanas", zone = 1581, level = 17, npc = 902, single = { 2041 } }
STUB.qdb.quests[1001] = nil; STUB.qdb.quests[1002] = nil`;

test('a chain that starts outside the dungeon: its first step is listed to pick up, with what it leads to; the later ones point at it', () => {
  const vm = newVM();
  vm.run(DEFIAS);
  vm.run('STUB.UseQuestieDB(); STUB.lfg = { { 2, "Deadmines", 17, 26 } }; STUB.UseLFG()');
  vm.login().advance(9);
  vm.run('NS.Dungeons.Quests("The Deadmines")'); // starts the read of QuestieDB's quests
  vm.advance(1);
  const q = vm.json('NS.Dungeons.Quests("The Deadmines")');
  const pick = Object.values(q.pickup);
  const first = pick.find(x => x.id === 2040);
  assert.ok(first, 'the first step, from Westfall');
  assert.equal(first.first, true);
  assert.deepEqual(Object.values(first.opens).sort(), ['Red Silk Bandanas', 'The Defias Brotherhood']);
  assert.equal(pick.find(x => x.id === 2042).after, 'The Defias Brotherhood');
  assert.equal(pick[0].id, 2040, 'what you can take now comes first');
  vm.run('NS.Panel.openDungeons = { deadmines = true }; NS.Panel.Show("dungeons")');
  const d = list(vm, 'SpellmindPanel.drawn');
  const row = d.find(x => x.text === 'The Defias Brotherhood (first step)');
  assert.match(row.sub, /Pick up/);
  assert.match(row.sub, /from Gryan Stoutmantle, Westfall \(56, 48\) · leads to /);
  assert.ok(d.some(x => x.text === 'Red Silk Bandanas' && /after The Defias Brotherhood \(pick it up first, above\)/.test(x.sub)));
});

test('a chain whose step is in your log: the later quest says so', () => {
  const vm = newVM();
  vm.run(DEFIAS);
  vm.run('STUB.UseQuestieDB(); STUB.completed[2040] = true; C_QuestLog.IsOnQuest = function(id) return id == 2041 end');
  vm.login().advance(9);
  vm.run('NS.Dungeons.Quests("The Deadmines")');
  vm.advance(1);
  const pick = Object.values(vm.json('NS.Dungeons.Quests("The Deadmines")').pickup);
  const bandanas = pick.find(x => x.id === 2043);
  assert.equal(bandanas.after, 'The Defias Brotherhood');
  assert.equal(bandanas.afterLog, true);
  assert.ok(!pick.some(x => x.id === 2041), 'in your log: not a pickup');
});

test('Go on a quest to pick up: the game\'s map pin on its giver (QuestieDB\'s zone to the game\'s map), and a line saying so', () => {
  const vm = withDB();
  const d = drawn(vm);
  const i = d.findIndex(x => x.text === 'Oh Brother...');
  vm.run(`SpellmindPanel.rows[${i + 1}].actions[1].scripts.OnClick(SpellmindPanel.rows[${i + 1}].actions[1], "LeftButton")`);
  assert.equal(vm.num('STUB.waypoints[1].uiMapID'), 1455, 'Ironforge');
  assert.equal(vm.evaluate('string.format("%.3f", STUB.waypoints[1].position.x)'), '0.452');
  assert.ok(vm.savedLines().some(l => /Map pin set for Thane Ironbelly: follow the arrow\./.test(l)));
  const locked = d.findIndex(x => x.text === 'Underground Assault');
  assert.notEqual(vm.evaluate(`tostring(SpellmindPanel.rows[${locked + 1}].actions[1] and SpellmindPanel.rows[${locked + 1}].actions[1]:IsShown())`), 'true', 'a locked one has no Go');
});
