// Milestone 14 (docs/milestone-14.md): the Professions and Gold tabs say what to do next, not what the
// game already shows. Professions: the next rank (train now, or at what skill and level), recipes worth
// crafting for a skill-up with how many the bags make, and the bags' materials. Gold: income this
// session and today, costs coming up, and what the bags would fetch (vendor, and Auctionator's prices).
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

const list = (vm, expr) => { const v = vm.json(expr); return Array.isArray(v) ? v : Object.values(v || {}); };
const session = () => newVM().login().advance(9);
const drawn = (vm, tab) => { vm.run(`NS.Panel.Show("${tab}")`); return list(vm, 'SpellmindPanel.drawn'); };

// The Leatherworking window: Light Armor Kit orange (4 Light Leather), Handstitched Leather Boots
// yellow (2 Light Leather, 3 Ruined Leather Scraps), a yellow belt needing thread you don't have, a
// grey one left out.
const LW = `C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Leatherworking", skillLevel = 61 } end,
  GetAllRecipeIDs = function() return { 2152, 2149, 3753, 9058 } end,
  GetRecipeInfo = function(id) return ({
    [2152] = { name = "Light Armor Kit", learned = true, relativeDifficulty = 0 },
    [2149] = { name = "Handstitched Leather Boots", learned = true, relativeDifficulty = 1 },
    [3753] = { name = "Handstitched Leather Belt", learned = true, relativeDifficulty = 1 },
    [9058] = { name = "Handstitched Leather Cloak", learned = true, relativeDifficulty = 3 } })[id] end,
  GetRecipeSchematic = function(id) return ({
    [2152] = { reagentSlotSchematics = { { quantityRequired = 4, reagents = { { itemID = 2318 } } } } },
    [2149] = { reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = 2318 } } }, { quantityRequired = 3, reagents = { { itemID = 2934 } } } } },
    [3753] = { reagentSlotSchematics = { { quantityRequired = 6, reagents = { { itemID = 2318 } } }, { quantityRequired = 1, reagents = { { itemID = 2320 } } } } },
    [9058] = { reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = 2318 } } } } } })[id] end,
}; STUB.FireEvent("TRADE_SKILL_SHOW")`;

test('Professions: the next rank, train now when skill and level allow; before its window is read, a crafting one says to open it', () => {
  const vm = session();
  const d = drawn(vm, 'professions');
  const lw = d.find(x => x.text === 'Leatherworking');
  assert.match(lw.sub, /Train Journeyman now/, '61 of 75, level 15: skill 50 and level 10 are met');
  assert.equal(lw.tag, 'train');
  assert.ok(d.some(x => /Open your Leatherworking window once/.test(x.text || '')));
  assert.ok(!d.some(x => /Open your Skinning window/.test(x.text || '')), 'Skinning has no recipes');
  assert.match(vm.evaluate('NS.Professions.NextRank(104, 150).name'), /^Expert$/);
  assert.equal(vm.evaluate('tostring(NS.Professions.NextRank(104, 150).ready)'), 'false', '125 and level 20');
  assert.equal(vm.evaluate('NS.Professions.NextRank(300, 300)'), 'max');
});

test('Professions: skill-ups, orange first, with how many the bags make and what\'s short; the materials and what they make', () => {
  const vm = session();
  vm.run(LW);
  vm.advance(1.5);
  const d = drawn(vm, 'professions');
  const ups = d.filter(x => / {2}.cff888888(orange|yellow)/.test(x.text || ''));
  assert.deepEqual(ups.map(x => x.text.replace(/\|c\w{8}|\|r/g, '').replace(/\s+(orange|yellow)$/, '')),
    ['Light Armor Kit', 'Handstitched Leather Boots', 'Handstitched Leather Belt'], 'the grey cloak left out; one you can make before one you can\'t');
  assert.match(ups[0].right, /make 5/, '20 Light Leather / 4');
  assert.match(ups[1].right, /make 1/, '4 scraps / 3');
  assert.match(ups[2].right, /make 0/);
  assert.match(ups[2].sub, /\|cffff6060item 2320 0\/1\|r/, 'what\'s short in red');
  const mats = d.find(x => /^Light Leather x20$/.test(x.text || ''));
  assert.match(mats.right, /makes 5 Light Armor Kit/);
  assert.match(mats.sub, /also Handstitched Leather Boots/);
});

test('Professions: after skill-ups since the window was read, a line says the colours may have moved', () => {
  const vm = session();
  vm.run(LW);
  vm.advance(1.5);
  vm.run('for _, s in ipairs(STUB.skills) do if s.name == "Leatherworking" then s.rank = 64 end end');
  assert.ok(drawn(vm, 'professions').some(x => /As of skill 61: open the window again/.test(x.text || '')));
});

test('Gold: in and out this session and today, from the game\'s money changes', () => {
  const vm = session();
  vm.run('STUB.player.money = STUB.player.money + 500; STUB.FireEvent("PLAYER_MONEY")');
  vm.run('STUB.player.money = STUB.player.money - 200; STUB.FireEvent("PLAYER_MONEY")');
  const d = drawn(vm, 'gold');
  const ses = d.find(x => x.text === 'This session');
  assert.match(ses.right, /\+.*3s/);
  assert.match(ses.sub, /in .*5s.* · out .*2s/);
  assert.match(d.find(x => x.text === 'Today').right, /\+.*3s/);
});

test('Gold: costs coming up (trainer spells, a rank to train) against your gold; what the bags fetch at a vendor', () => {
  const vm = session();
  vm.run('for _, t in ipairs(STUB.spellbook.tabs) do for i = #t.items, 1, -1 do if t.items[i].itemType == 2 then table.remove(t.items, i) end end end');
  vm.run('STUB.trainer = { { "Sprint", "Rank 1", "available", 600, 10 }, { "Backstab", "Rank 2", "available", 300, 12 } }; STUB.FireEvent("TRAINER_SHOW")');
  vm.advance(0.3);
  const d = drawn(vm, 'gold');
  const spells = d.find(x => x.text === '2 spells at your trainer');
  assert.match(spells.right, /9s/);
  assert.ok(d.some(x => x.text === 'Journeyman Leatherworking' && /train now/.test(x.sub)));
  assert.ok(d.some(x => /Known costs: .*9s.* of your/.test(x.text || '')));
  const vendor = d.find(x => x.text === 'Safe to sell at a vendor');
  assert.match(vendor.right, /45c/);
  assert.match(vendor.sub, /Rabbit's Foot/);
  assert.ok(d.some(x => /With Auctionator, auction house prices/.test(x.text || '')), 'no Auctionator: says what it would add');
});

test('Gold: the auction house worth from Auctionator\'s public API, soulbound and grey left out', () => {
  const vm = session();
  vm.run('Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id) STUB.ahCaller = caller; return ({ [2318] = 200, [2589] = 50, [6948] = 9999, [3300] = 9999 })[id] end } } }');
  const ah = drawn(vm, 'gold').find(x => x.text === 'On the auction house');
  assert.match(ah.right, /47s/, '20 Light Leather at 2s, 14 Linen Cloth at 50c');
  assert.match(ah.sub, /Light Leather x20 .*40s/);
  assert.equal(vm.evaluate('STUB.ahCaller'), 'Spellmind');
});

test('Gold: Auctionator without prices yet says to scan', () => {
  const vm = session();
  vm.run('Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return nil end } } }');
  const ah = drawn(vm, 'gold').find(x => x.text === 'On the auction house');
  assert.match(ah.sub, /Scan at the auction house/);
});

test('the advisor part stays the same as time passes (seen in game: a per-hour rate made it go again and again, and arrive late)', () => {
  const vm = session();
  vm.run('STUB.player.money = STUB.player.money + 500; STUB.FireEvent("PLAYER_MONEY")');
  const a = vm.evaluate('NS.State.JSON.encode(NS.State.Collect.advisor())');
  vm.advance(900); // 15 minutes on
  assert.equal(vm.evaluate('NS.State.JSON.encode(NS.State.Collect.advisor())'), a);
  assert.match(a, /"sessionNet":500/);
});
