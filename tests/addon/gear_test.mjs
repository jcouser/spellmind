// Milestone 9 (docs/milestone-9.md): the gear advisor's local side. Weak slots; upgrades within
// reach (wearables in the bags, cached rewards of quests in the log); the Gear tab's Next upgrades;
// the reward pick on a turn-in; the character sheet's dots; the merchant's sell list. The level-15
// Dwarf rogue of the stub: empty head, hands and back; a dagger in the main hand.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
const session = () => newVM().login().advance(3.1);

test('weak slots: empty first, then gear well below the level, then common quality; shirt and tabard don\'t count', () => {
  const vm = session();
  const weak = list(vm, 'NS.Gear.WeakSlots()');
  assert.deepEqual(weak.slice(0, 3).map(w => [w.name, w.why]), [['Head', 'empty'], ['Neck', 'empty'], ['Shoulder', 'empty']]);
  assert.ok(!weak.some(w => w.slot === 4 || w.slot === 19));
  const legs = weak.find(w => w.slot === 7);
  assert.equal(legs.why, 'item level 10, 5 below your level', 'the pants: ilvl 10 at level 15');
});

test('upgrades in the bags: a better sword (usable: Swords skill), a cloak for the empty back; the bow (no Bows) isn\'t one', () => {
  const vm = session();
  vm.run('table.insert(STUB.bags[2].items, { 2140, 1 }); table.insert(STUB.bags[2].items, { 4936, 1 }); table.insert(STUB.bags[2].items, { 2504, 1 })');
  const c = list(vm, 'NS.Gear.Candidates()');
  const sword = c.find(x => x.name === 'Fine Longsword');
  assert.equal(sword.slot, 16);
  assert.equal(sword.from, 'bags');
  assert.match(sword.reason, /\+0\.9 dps/);
  assert.equal(c.find(x => x.name === 'Dirt-stained Cloak').reason, 'fills an empty slot');
  assert.ok(!c.some(x => x.name === 'Worn Shortbow'), 'unusable: not an upgrade');
});

test('quest rewards: read when the quest\'s details are seen, kept, and offered while the quest is in the log', () => {
  const vm = session();
  assert.ok(!list(vm, 'NS.Gear.Candidates()').some(x => x.quest), 'nothing seen yet');
  vm.run('QuestMapFrame_ShowQuestDetails(297)'); // the player looks at Gathering Idols
  const c = list(vm, 'NS.Gear.Candidates()');
  const gloves = c.find(x => x.name === "Ironband's Gloves");
  assert.ok(gloves, JSON.stringify(c));
  assert.equal(gloves.from, 'Gathering Idols');
  assert.equal(gloves.quest, 297);
  assert.equal(gloves.reason, 'fills an empty slot');
  assert.ok(!c.some(x => x.name === 'Trogg Mace'), 'no Maces skill');
  vm.run('for i, q in ipairs(STUB.quests) do if q.questID == 297 then table.remove(STUB.quests, i) break end end');
  assert.ok(!list(vm, 'NS.Gear.Candidates()').some(x => x.quest === 297), 'abandoned or done: gone');
});

test('the Gear tab: Next upgrades first (within reach, with where from and Go for a quest), then the weakest slots', () => {
  const vm = session();
  vm.run('QuestMapFrame_ShowQuestDetails(297); NS.Panel.Show("gear")');
  const d = list(vm, 'SpellmindPanel.drawn');
  assert.equal(d[0].text, 'Upgrades within reach');
  const gloves = d.find(x => /Ironband's Gloves/.test(x.text || ''));
  assert.match(gloves.text, /^Hands · /);
  assert.match(gloves.sub, /Reward of Gathering Idols/);
  assert.equal(gloves.tag, undefined, 'no "upgrade" label under "Upgrades within reach" (the review)');
  assert.ok(d.some(x => x.text === 'Weakest slots'));
  assert.ok(d.some(x => x.text === 'Head' && /empty/.test(x.right)), 'a weak slot with nothing within reach yet');
  assert.ok(!d.some(x => x.text === 'Your gear (worn)'), 'no copy of the character sheet (the review)');
});

test('the reward pick: turning in with a choice, a box says the likely pick (usable, an upgrade) and why; Why? asks the AI', () => {
  const vm = session();
  vm.run('STUB.window = { id = 297, title = "Gathering Idols", choices = { 7002, 7001, 7003 } }; STUB.FireEvent("QUEST_COMPLETE")');
  vm.advance(0.2);
  assert.equal(vm.evaluate('tostring(SpellmindPick.shown)'), 'true');
  assert.equal(vm.evaluate('SpellmindPick.title:GetText()'), "Spellmind picks: Ironband's Gloves");
  assert.equal(vm.evaluate('SpellmindPick.text:GetText()'), 'fills an empty slot');
  vm.run('SpellmindPick.why.scripts.OnClick(SpellmindPick.why)');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Reward pick: Gathering Idols');
  assert.ok(vm.outbox().some(o => o.wire.includes("The rewards to choose from are Trogg Mace, Ironband's Gloves, Idol Cloak")));
  vm.run('STUB.FireEvent("QUEST_FINISHED")');
  assert.equal(vm.evaluate('tostring(SpellmindPick.shown)'), 'false');
});

test('the character sheet: a green dot on a slot with an upgrade waiting, orange for low durability; the slot\'s tooltip says why', () => {
  const vm = session();
  vm.run('table.insert(STUB.bags[2].items, { 4936, 1 })'); // a cloak for the empty back
  vm.run('STUB.equipped[16].dur = { 15, 45 }'); // the dagger at 33%
  vm.run('PaperDollFrame:Hide(); PaperDollFrame:Show(); for _, fn in ipairs(PaperDollFrame.hooks.OnShow or {}) do fn(PaperDollFrame) end');
  const dot = slot => vm.json(`(function() local d = NS.GearUI.dots[${slot}] return { shown = d.shown, color = d.color } end)()`);
  assert.equal(dot(15).shown, true);
  assert.deepEqual(list(vm, `NS.GearUI.dots[15].color`).slice(0, 3), [0.1, 1, 0.1], 'green: upgrade waiting');
  assert.equal(dot(16).shown, true);
  assert.deepEqual(list(vm, `NS.GearUI.dots[16].color`).slice(0, 3), [1, 0.6, 0.15], 'orange: 33% durability');
  assert.equal(dot(5).shown, false, 'the robe: nothing to say');
  // The game's slot function, as the sheet calls it: on enter, then again and again while the mouse
  // stays, each call rebuilding the tooltip. The line must be there after every call (seen in game:
  // it showed for one frame, then the refresh wiped it).
  vm.run('PaperDollItemSlotButton_OnEnter(CharacterBackSlot)');
  assert.ok(list(vm, 'GameTooltip.added').some(l => /upgrade waiting: Dirt-stained Cloak \(in your bags\)/.test(l)));
  vm.run('PaperDollItemSlotButton_OnEnter(CharacterBackSlot); PaperDollItemSlotButton_OnEnter(CharacterBackSlot)');
  const after = list(vm, 'GameTooltip.added');
  assert.equal(after.filter(l => /upgrade waiting/.test(l)).length, 1, 'there after the refresh, once');
  vm.run('PaperDollItemSlotButton_OnEnter(CharacterMainHandSlot)');
  assert.ok(list(vm, 'GameTooltip.added').some(l => /durability 33%: repair soon/.test(l)));
});

test('the merchant: "what to sell" beside its window; the card lists grey junk and bound gear you can\'t use, with values; nothing is sold', () => {
  const vm = session();
  vm.run('table.insert(STUB.bags[3].items, { 2504, 1, true })'); // a bound bow the rogue can't use
  vm.run('STUB.FireEvent("MERCHANT_SHOW")');
  vm.run('NS.GearUI.sell.scripts.OnClick(NS.GearUI.sell)');
  assert.equal(vm.evaluate('SpellmindCard.title:GetText()'), 'Spellmind: what to sell');
  const text = list(vm, 'SpellmindCard.lines').join('\n');
  assert.match(text, /^Safe to sell, worth/);
  assert.match(text, /Rabbit's Foot: 45c \|cff888888\(grey junk\)/);
  assert.match(text, /Worn Shortbow: 7c \|cff888888\(bound, and you can't use it\)/);
  assert.doesNotMatch(text, /Hearthstone|Light Leather/, 'not junk, not gear');
  assert.match(text, /doesn't sell anything/);
  vm.run('STUB.FireEvent("MERCHANT_CLOSED")');
  assert.equal(vm.evaluate('tostring(SpellmindCard.shown)'), 'false');
});

test('every quest in the log is read for rewards a few seconds after login, without opening it (seen in game: the list was empty until then)', () => {
  const vm = newVM().login().advance(7); // past the 6 s first read
  const gloves = list(vm, 'NS.Gear.Candidates()').find(x => x.name === "Ironband's Gloves");
  assert.ok(gloves, 'Gathering Idols read without its details being opened');
  assert.equal(gloves.from, 'Gathering Idols');
  assert.equal(vm.evaluate('tostring(STUB.selectedQuest == 297)'), 'true', 'the selection untouched');
});

test('the Gear tab says so when nothing within reach beats what you wear', () => {
  const vm = session();
  vm.run('STUB.questRewards = {}; NS.Panel.Show("gear")');
  const d = list(vm, 'SpellmindPanel.drawn');
  assert.equal(d[0].text, 'Upgrades within reach');
  assert.match(d[1].text, /Nothing in your bags or your quests' rewards beats what you wear/);
});

test('the slot\'s line also survives a rebuild from the item\'s tooltip data (the other refresh path), and never shows twice', () => {
  const vm = session();
  vm.run('STUB.equipped[16].dur = { 15, 45 }');
  vm.run('PaperDollFrame:Hide(); PaperDollFrame:Show(); for _, fn in ipairs(PaperDollFrame.hooks.OnShow or {}) do fn(PaperDollFrame) end');
  vm.run('PaperDollItemSlotButton_OnEnter(CharacterMainHandSlot)'); // the slot function: our line
  vm.run('STUB.ShowItem(GameTooltip, STUB.equipped[16].link); GameTooltip.owner = CharacterMainHandSlot'); // a rebuild from data (clears)
  vm.run('GameTooltip.added = {}; GameTooltip.owner = CharacterMainHandSlot; for _, c in ipairs(STUB.tipCalls) do c.fn(GameTooltip, { lines = {} }) end');
  assert.equal(list(vm, 'GameTooltip.added').filter(l => /durability 33%/.test(l)).length, 1, 'added by the post-call');
  vm.run('for _, c in ipairs(STUB.tipCalls) do c.fn(GameTooltip, { lines = {} }) end');
  assert.equal(list(vm, 'GameTooltip.added').filter(l => /durability 33%/.test(l)).length, 1, 'not twice');
});

test('hovering a Gear tab row shows that item\'s tooltip: a reward by its link, a worn item by its slot (the player, 2026-11-14)', () => {
  const vm = session();
  vm.run('QuestMapFrame_ShowQuestDetails(297); NS.Panel.Show("gear")');
  const d = list(vm, 'SpellmindPanel.drawn');
  const at = d.findIndex(x => /Ironband's Gloves/.test(x.text || '')) + 1;
  assert.ok(at > 0);
  vm.run(`local r = SpellmindPanel.rows[${at}]; r.scripts.OnEnter(r)`);
  assert.equal(vm.evaluate('tostring(GameTooltip.shown)'), 'true');
  assert.match(vm.evaluate('tostring(GameTooltip.hyperlink)'), /item:/);
  vm.run(`local r = SpellmindPanel.rows[${at}]; r.scripts.OnLeave(r)`);
  assert.equal(vm.evaluate('tostring(GameTooltip.shown)'), 'false');
  // A row with no item (an empty slot) shows nothing.
  const empty = d.findIndex(x => x.text === 'Head' && /empty/.test(x.right || '')) + 1;
  vm.run(`local r = SpellmindPanel.rows[${empty}]; GameTooltip:Hide(); r.scripts.OnEnter(r)`);
  assert.equal(vm.evaluate('tostring(GameTooltip.shown)'), 'false');
});
