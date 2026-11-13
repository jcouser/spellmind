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
  assert.equal(vm.evaluate('SpellmindPanel.title:GetText()'), 'Spellmind');
  assert.equal(vm.evaluate('SpellmindPanel.who:GetText()'), 'Level 15 · Dwarf Rogue');
  vm.slash('panel');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.shown)'), 'false', '/sm panel toggles');
  vm.slash('panel');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.shown)'), 'true');
  assert.equal(vm.num('#SpellmindPanel.tabs'), 10, 'Chat, Quests, Dungeons, five more, Nudges and Settings');
  assert.equal(vm.evaluate('NS.Panel.tab'), 'quests', 'the right-click opens a tab other than Chat');
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
  assert.deepEqual(heads, ['Ready to turn in', 'Do now: Loch Modan', 'Dungeons', 'Later'], 'the zone you\'re in (Loch Modan) first');
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
  const dungeon = section('Dungeons');
  assert.match(dungeon[0].text, /\]\|r Ironforge$/, 'one row for the dungeon, by its header, though no marker is on this map');
  assert.match(dungeon[0].sub, /1 quest: Old Ironforge Incursion/);
  const later = section('Later');
  assert.match(later[0].text, /\[18\]\|r Gathering Idols/);
  assert.equal(later[0].right, 'NE · 560 yd');
  assert.ok(d.filter(x => x.kind === 'item' && x !== dungeon[0]).every(x => typeof x.quest === 'number'), 'every quest row has its mark');
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
test('Gear: only what needs you (the review): gear about to break, bag items with something to say (the bow you cannot use), empty slots', () => {
  const vm = session();
  vm.run('table.insert(STUB.bags[2].items, { 2504, 1 })'); // the bow into a bag
  vm.run('NS.Panel.Show("gear")');
  const d = drawn(vm);
  assert.ok(!d.some(x => x.text === 'Your gear (worn)'), 'no copy of the character sheet');
  const repairAt = d.findIndex(x => x.text === 'Needs repair');
  assert.ok(repairAt >= 0);
  assert.match(d[repairAt + 1].text, /^Chest · .*Simple Robe of the Monkey/);
  assert.match(d[repairAt + 1].right, /72% durability/);
  assert.ok(!d.some(x => /Handstitched Leather Pants/.test(x.text || '')), '85%: fine, not listed');
  const bow = d.find(x => /Worn Shortbow/.test(x.text || ''));
  assert.ok(bow, JSON.stringify(d.map(x => x.text)));
  assert.match(bow.right, /Bows/);
  assert.ok(d.some(x => x.kind === 'head' && /^Worth a look in your bags \(\d+ of \d+ free\)$/.test(x.text)));
  assert.ok(!d.some(x => /Hearthstone/.test(x.text || '')), 'nothing to say: not listed');
  const empty = d[d.findIndex(x => x.text === 'Empty slots') + 1].text;
  assert.match(empty, /^Head, Neck, Shoulder, Waist/);
  assert.doesNotMatch(empty, /Shirt|Tabard/, "cosmetic slots aren't empty");
});

test('the other tabs: talents, the spells coming (train now when due), professions near their cap, gold and bag space', () => {
  const vm = session();
  vm.run('NS.Panel.Show("talents")');
  assert.ok(drawn(vm).some(x => x.text === 'No guide yet'), 'without a guide: how to set one');
  assert.ok(drawn(vm).some(x => /spent/.test(x.text || '')), "and what's spent, not the game's own list");
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
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Find my next upgrades');
  assert.equal(vm.evaluate('tostring(SpellmindCard.anchor.rel == SpellmindPanel)'), 'true');
  assert.ok(vm.savedLines().some(l => /Find my next upgrades/.test(l)), 'the chat keeps the question');
  // The question names the weakest slots, so the AI looks where it counts.
  assert.ok(vm.outbox().some(o => o.wire.includes('Find my next realistic gear upgrades, starting with my weakest slots: Head (empty)')));
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
  assert.equal(vm.num('SpellmindPanel.content:GetWidth()'), 600 - 150 - 24);
  vm.run('SpellmindPanel:SetSize(800, 600); SpellmindPanel.grip.scripts.OnMouseUp(SpellmindPanel.grip)');
  assert.equal(vm.num('SpellmindDB.panel.w'), 800);
  assert.equal(vm.num('SpellmindDB.panel.h'), 600);
  assert.equal(vm.num('SpellmindPanel.content:GetWidth()'), 800 - 150 - 24, 'the rows take the new width');
  assert.equal(vm.num('SpellmindPanel.rows[2]:GetWidth()'), 800 - 150 - 24);
  assert.equal(vm.num('SpellmindPanel.asks[1]:GetWidth()'), Math.floor((800 - 150 - 24 - 12) / 2));
});

test('LFG: every click asks where (the current chat channel, the joined channels, Say, Party, Guild); the pick puts the line in the chat box', () => {
  const vm = session();
  vm.run('C_QuestLog.GetQuestTagInfo = function(id) if id == 96393 or id == 297 then return { tagID = 81, tagName = "Dungeon" } end end');
  vm.run('NS.Panel.Show("quests")');
  vm.run('NS.Panel.LFG(96393, "LeftButton")');
  assert.equal(vm.evaluate('tostring(SpellmindLFGMenu.shown)'), 'true', 'the menu');
  assert.equal(vm.evaluate('tostring(STUB.openedChat)'), 'nil', 'nothing in the chat box yet');
  const labels = list(vm, '(function() local t = {} for _, r in ipairs(SpellmindLFGMenu.rows) do if r:IsShown() then t[#t + 1] = r.text:GetText() end end return t end)()');
  assert.deepEqual(labels, ['Current chat channel', '2. General - Ironforge', '3. Trade - City', 'Say', 'Party', 'Guild']);
  vm.run('SpellmindLFGMenu.rows[3].scripts.OnClick(SpellmindLFGMenu.rows[3])'); // Trade
  assert.equal(vm.evaluate('STUB.openedChat'), '/3 LFG Ironforge DPS Rogue', 'short: the dungeon, the role, the class');
  assert.equal(vm.evaluate('tostring(SpellmindLFGMenu.shown)'), 'false');
  assert.ok(!vm.chatLines().some(l => /^LFG/.test(l)), 'nothing sent');
  vm.run('STUB.openedChat = nil; NS.Panel.LFG(297, "LeftButton")');
  assert.equal(vm.evaluate('tostring(STUB.openedChat)'), 'nil', 'no pick kept: the menu again');
  assert.equal(vm.evaluate('tostring(SpellmindLFGMenu.shown)'), 'true');
  vm.run('SpellmindLFGMenu.rows[1].scripts.OnClick(SpellmindLFGMenu.rows[1])'); // the current chat channel
  assert.equal(vm.evaluate('STUB.openedChat'), 'LFG Ironforge DPS Rogue', "any of the dungeon's quests: the same line; no prefix: the chat box's own channel");
});
test('the LFG button: only on group or elite quests that aren\'t done, and on a dungeon\'s row', () => {
  const vm = session();
  vm.run('C_QuestLog.IsEliteQuest = function(id) return id == 96393 end');
  vm.run('NS.Panel.Show("quests")');
  const labels = vm.json('(function() local out = {} for _, r in ipairs(SpellmindPanel.rows) do if r:IsShown() and r.mark and r.mark.questID then local t = {} for _, a in ipairs(r.actions or {}) do if a:IsShown() then t[#t + 1] = a.text:GetText() end end out[tostring(r.mark.questID)] = table.concat(t, ",") end end return out end)()');
  assert.equal(labels['96393'], 'LFG,Go');
  assert.equal(labels['2038'], 'Go');
  vm.run('C_QuestLog.IsEliteQuest = function() return false end; C_QuestLog.GetQuestTagInfo = function(id) if id == 96393 then return { tagID = 81, tagName = "Dungeon" } end end');
  vm.run('NS.Panel.Show("quests")');
  const row = vm.evaluate('(function() for _, r in ipairs(SpellmindPanel.rows) do if r:IsShown() and tostring(r.left:GetText()):match("%]|r Ironforge$") then local t = {} for _, a in ipairs(r.actions or {}) do if a:IsShown() then t[#t + 1] = a.text:GetText() end end return table.concat(t, ",") end end end)()');
  assert.equal(row, 'LFG,Open', 'the dungeon\'s one row');
});

test('LFG on a group quest that isn\'t a dungeon: its own title; a leading "The" goes', () => {
  const vm = session();
  vm.run('STUB.quests[11].title = "The Mo\'grosh Problem"; C_QuestLog.IsEliteQuest = function(id) return id == 96393 end');
  vm.run('NS.Panel.LFGTo(96393, "/4")');
  assert.equal(vm.evaluate('STUB.openedChat'), "/4 LFG Mo'grosh Problem DPS Rogue");
});

test('a dungeon\'s quests stay together, levels apart (seen in game: one under Do now, two under Later)', () => {
  const vm = session();
  vm.run(`table.insert(STUB.quests, { title = "The Deadmines", isHeader = true })
table.insert(STUB.quests, { title = "Collecting Memories", questID = 168, level = 18 })
table.insert(STUB.quests, { title = "Oh Brother...", questID = 167, level = 20 })
table.insert(STUB.quests, { title = "Underground Assault", questID = 2040, level = 20 })
C_QuestLog.GetQuestTagInfo = function(id) if id == 168 or id == 167 or id == 2040 then return { tagID = 81, tagName = "Dungeon" } end end`);
  vm.run('NS.Panel.Show("quests")');
  const d = drawn(vm);
  // One row for the dungeon (the player's call: the Dungeons tab has the details), its quests named.
  const row = d.find(x => /\]\|r The Deadmines$/.test(x.text || ''));
  assert.ok(row);
  assert.match(row.text, /\[18\]/, 'its lowest quest\'s level');
  assert.match(row.sub, /3 quests: Collecting Memories, Oh Brother\.\.\., Underground Assault/);
  assert.equal(row.right, '|cffff9933+3 levels|r', 'its lowest quest\'s gap (the rogue is 15)');
  assert.ok(!d.some(x => /^\|c\w+\[20\]\|r (Oh Brother|Underground Assault)/.test(x.text || '')), 'its quests aren\'t listed one by one');
  vm.run('SpellmindPanel.rows[' + (d.indexOf(row) + 1) + '].actions[2].scripts.OnClick(SpellmindPanel.rows[' + (d.indexOf(row) + 1) + '].actions[2])');
  assert.equal(vm.evaluate('NS.Panel.tab'), 'dungeons', 'Open: the Dungeons tab');
  const later = d.findIndex(x => x.text === 'Later');
  assert.ok(!d.slice(later + 1).some(x => /Oh Brother|Underground Assault/.test(x.text || '')), 'not under Later');
});

test('a live redraw keeps the scroll (the review: the list jumped to the top a second after every loot)', () => {
  const vm = session();
  vm.run('NS.Panel.Show("quests")');
  vm.run('SpellmindPanel.scroll:SetVerticalScroll(40)');
  vm.run('STUB.FireEvent("QUEST_LOG_UPDATE")');
  vm.advance(1.2);
  assert.equal(vm.num('SpellmindPanel.scroll:GetVerticalScroll()'), 0, 'the stub\'s range is 0: clamped, as a shorter list would be');
  vm.run('SpellmindPanel.scroll.GetVerticalScrollRange = function() return 100 end; SpellmindPanel.scroll:SetVerticalScroll(40)');
  vm.run('STUB.FireEvent("QUEST_LOG_UPDATE")');
  vm.advance(1.2);
  assert.equal(vm.num('SpellmindPanel.scroll:GetVerticalScroll()'), 40, 'kept');
  vm.run('NS.Panel.Show("gear")');
  assert.equal(vm.num('SpellmindPanel.scroll:GetVerticalScroll()'), 0, 'a tab switch starts at the top');
});

test('a scrollbar shows on a list that\'s longer than its view, follows the scroll, and drags (the player, 2026-11-13)', () => {
  const vm = session();
  vm.run('NS.Panel.Show("settings")');
  vm.run('SpellmindPanel.scroll.range = 0; SpellmindPanel.bar.Update()');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.bar:IsShown())'), 'false', 'all in view: no bar');
  vm.run('SpellmindPanel.scroll.range = 600; SpellmindPanel.bar.Update()');
  assert.equal(vm.evaluate('tostring(SpellmindPanel.bar:IsShown())'), 'true');
  const h = vm.num('SpellmindPanel.scroll:GetHeight()');
  assert.ok(h > 0);
  assert.equal(Math.round(vm.num('SpellmindPanel.bar.thumb:GetHeight()')), Math.round(Math.max(20, h * h / (h + 600))), 'its size is the share in view');
  // Dragging the thumb down scrolls down, never past the end.
  vm.run('STUB.cursor = { 100, 500 }; SpellmindPanel.bar.scripts.OnMouseDown(SpellmindPanel.bar)');
  vm.run('STUB.cursor = { 100, 300 }; SpellmindPanel.bar.scripts.OnUpdate(SpellmindPanel.bar, 0.02)');
  assert.ok(vm.num('SpellmindPanel.scroll:GetVerticalScroll()') > 0);
  vm.run('STUB.cursor = { 100, -5000 }; SpellmindPanel.bar.scripts.OnUpdate(SpellmindPanel.bar, 0.02)');
  assert.equal(vm.num('SpellmindPanel.scroll:GetVerticalScroll()'), 600);
  vm.run('SpellmindPanel.bar.scripts.OnMouseUp(SpellmindPanel.bar)');
  // The chat and the answer card have one too.
  vm.run('NS.Panel.Show("chat")');
  assert.equal(vm.evaluate('tostring(NS.Window.Get and NS.Window.Get() and NS.Window.Get().bar ~= nil)'), 'true');
});
