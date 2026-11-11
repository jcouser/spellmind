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

test('Quests: ready; Do now grouped by the log\'s own headers (the zone you\'re in first); later with its gap; what\'s left, direction and distance; a Dungeon tag', () => {
  const vm = session();
  // Bingles' Missing Supplies on this map, south-west of the player (at 35.4, 48.2); Old Ironforge
  // Incursion a dungeon quest, with no marker on this map (as the game has them outside).
  vm.run('table.insert(STUB.questsOnMap[1432], { questID = 2038, x = 0.30, y = 0.60 }); STUB.questDist[2038] = 200');
  vm.run('C_QuestLog.GetQuestTagInfo = function(id) if id == 96393 then return { tagID = 81, tagName = "Dungeon" } end end');
  vm.run('NS.Panel.Show("quests")');
  const d = drawn(vm);
  const heads = d.filter(x => x.kind === 'head').map(x => x.text);
  assert.deepEqual(heads, ['Ready to turn in', 'Do now: Loch Modan', 'Do now: Ironforge', 'Later'], 'the zone you\'re in (Loch Modan) first');
  const section = h => { const i = d.findIndex(x => x.text === h); const j = d.findIndex((x, k) => k > i && x.kind === 'head'); return d.slice(i + 1, j < 0 ? d.length : j); };
  const ready = section('Ready to turn in');
  assert.ok(ready.filter(x => x.kind === 'item').every(x => /Ready to turn in/.test(x.sub)));
  // XP: Stormpike's Order gives 975 (the stub's other ready quests none); the rogue has 2,944 of 14,400.
  assert.match(ready.find(x => /Stormpike's Order/.test(x.text || '')).sub, /975 XP/);
  assert.equal(ready[0].kind, 'text');
  assert.match(ready[0].text, /^Turning these in takes you from 20% to \|cff19ff1927%\|r of level 15 \(975 XP\)\.$/);
  // Gathering Idols' 1,350 XP on its line too.
  assert.match(section('Later')[0].sub, /1,350 XP/);
  const here = section('Do now: Loch Modan');
  assert.match(here[0].text, /Bingles' Missing Supplies/, 'nearest first');
  assert.equal(here[0].sub, "|cffbbbbbb0/1 Bingles' Wrench, 0/1 Bingles' Screwdriver|r", 'what\'s left');
  assert.equal(here[0].right, 'SW · 200 yd', 'direction and distance');
  assert.match(here[1].text, /Snowbound/);
  const dungeon = section('Do now: Ironforge');
  assert.match(dungeon[0].text, /Old Ironforge Incursion/, 'with its header\'s group, though no marker is on this map');
  assert.equal(dungeon[0].tag, 'Dungeon');
  const later = section('Later');
  assert.match(later[0].text, /\[18\]\|r Gathering Idols/);
  assert.equal(later[0].right, 'NE · 560 yd');
  assert.ok(d.filter(x => x.kind === 'item').every(x => typeof x.quest === 'number'), 'every quest row has its mark');
  assert.equal(vm.evaluate('SpellmindPanel.asks[1].text:GetText()'), 'Ask: Plan my next hour');
});

test('Go: the game\'s own map pin and arrow for a quest on this map; super-tracking for one elsewhere; a line says which', () => {
  const vm = session();
  vm.run('NS.Panel.Go(297)');
  assert.equal(vm.num('STUB.waypoints[1].uiMapID'), 1432);
  assert.equal(vm.evaluate('string.format("%.3f", STUB.waypoints[1].position.x)'), '0.706');
  assert.equal(vm.evaluate('STUB.superTracked[1]'), 'waypoint');
  assert.ok(vm.chatLines().some(l => /Map pin set for Gathering Idols/.test(l)));
  vm.run('NS.Panel.Go(96393)'); // not on this map
  assert.equal(vm.evaluate('STUB.superTracked[2]'), 'quest:96393');
  assert.ok(vm.chatLines().some(l => /Tracking Old Ironforge Incursion/.test(l)));
  // The row's own Go button does the same.
  vm.run('NS.Panel.Show("quests")');
  const n = vm.num('#STUB.waypoints');
  vm.run('for _, r in ipairs(SpellmindPanel.rows) do if r.mark and r.mark.questID == 297 and r:IsShown() then r.actions[1].scripts.OnClick(r.actions[1]) end end');
  assert.equal(vm.num('#STUB.waypoints'), n + 1);
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

test('resizable: the grip sizes it, the rows and Ask buttons follow, the size is kept for next time', () => {
  const vm = session();
  vm.run('NS.Panel.Show("quests")');
  assert.equal(vm.num('SpellmindPanel.content:GetWidth()'), 560 - 150 - 24);
  vm.run('SpellmindPanel:SetSize(800, 600); SpellmindPanel.grip.scripts.OnMouseUp(SpellmindPanel.grip)');
  assert.equal(vm.num('SpellmindDB.panel.w'), 800);
  assert.equal(vm.num('SpellmindDB.panel.h'), 600);
  assert.equal(vm.num('SpellmindPanel.content:GetWidth()'), 800 - 150 - 24, 'the rows take the new width');
  assert.equal(vm.num('SpellmindPanel.rows[2]:GetWidth()'), 800 - 150 - 24);
  assert.equal(vm.num('SpellmindPanel.asks[1]:GetWidth()'), Math.floor((800 - 150 - 24 - 12) / 2));
});

test('LFG on a dungeon quest: the dungeon and its quests, who\'s asking, in the chat box on the LookingForGroup channel, to send yourself', () => {
  const vm = session();
  vm.run('C_QuestLog.GetQuestTagInfo = function(id) if id == 96393 or id == 297 then return { tagID = 81, tagName = "Dungeon" } end end');
  vm.run('NS.Panel.Show("quests")');
  const row = drawn(vm).find(x => /Old Ironforge Incursion/.test(x.text || ''));
  assert.ok(row);
  vm.run('NS.Panel.LFG(96393)');
  assert.equal(vm.evaluate('STUB.openedChat'), '/4 LFG Ironforge DPS Rogue', 'short: the dungeon, the role, the class');
  vm.run('NS.Panel.LFG(297)');
  assert.equal(vm.evaluate('STUB.openedChat'), '/4 LFG Ironforge DPS Rogue', "any of the dungeon's quests: the same line");
  assert.ok(!vm.chatLines().some(l => /^LFG/.test(l)), 'nothing sent');
  vm.run('STUB.channels = {}; STUB.openedChat = nil; NS.Panel.LFG(96393)');
  assert.match(vm.evaluate('STUB.openedChat'), /^LFG Ironforge/, 'not in the channel: no channel number');
});

test('the LFG button: only on group, elite or dungeon quests that aren\'t done', () => {
  const vm = session();
  vm.run('C_QuestLog.GetQuestTagInfo = function(id) if id == 96393 then return { tagID = 81, tagName = "Dungeon" } end end');
  vm.run('NS.Panel.Show("quests")');
  const labels = vm.json('(function() local out = {} for _, r in ipairs(SpellmindPanel.rows) do if r:IsShown() and r.mark and r.mark.questID then local t = {} for _, a in ipairs(r.actions or {}) do if a:IsShown() then t[#t + 1] = a.text:GetText() end end out[tostring(r.mark.questID)] = table.concat(t, ",") end end return out end)()');
  assert.equal(labels['96393'], 'LFG,Go');
  assert.equal(labels['2038'], 'Go');
});

test('LFG on a group quest that isn\'t a dungeon: its own title; a leading "The" goes', () => {
  const vm = session();
  vm.run('STUB.quests[11].title = "The Mo\'grosh Problem"; C_QuestLog.IsEliteQuest = function(id) return id == 96393 end');
  vm.run('NS.Panel.LFG(96393)');
  assert.equal(vm.evaluate('STUB.openedChat'), "/4 LFG Mo'grosh Problem DPS Rogue");
});
