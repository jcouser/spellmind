// Milestone 17 (docs/milestone-17.md): the world part. The model named a vendor the player couldn't
// find and a pass that doesn't exist, so the game says where things are: the hearth, the flight paths
// the character knows (noted at flight masters), the NPCs it has used with their titles, spots and a
// vendor's goods (noted as their windows open), and QuestieDB's only when it's installed.
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';
import { validatePart } from '../../core/link/charstate.mjs';

const session = () => newVM().login().advance(3.1);
const part = vm => JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.State.Collect.world())'));

// Talking to an NPC: its GUID (the npc id is the sixth field) and its tooltip's name and title.
const TALK = (id, name, sub) => `UnitGUID = (function(old) return function(u) if u == "npc" then return "Creature-0-5250-0-38-${id}-0000ABCD" end return old(u) end end)(UnitGUID)
C_TooltipInfo.GetUnit = function(u) return { lines = { { leftText = "${name}" }, { leftText = "${sub}" }, { leftText = "Level 30" } } } end`;
const SHOP = `GetMerchantNumItems = function() return 3 end
GetMerchantItemInfo = function(i) return ({ "Refreshing Spring Water", "Heavy Shot", "Light Shot" })[i] end
GetMerchantItemLink = function(i) return "item:" .. ({ 159, 2519, 2516 })[i] end
C_Item.GetItemInfoInstant = function(link) local id = tonumber(link:match("item:(%d+)")); return id, "", "", "", 0, (id == 159) and 0 or 6, 0 end
CanMerchantRepair = function() return false end`;

test('a vendor used: name and title from the game, where, its goods (ammo and food first); in the world part, valid', () => {
  const vm = session();
  vm.run(TALK(1682, 'Yanni Stoutheart', 'General Supplies'));
  vm.run(SHOP);
  vm.run('STUB.FireEvent("MERCHANT_SHOW")');
  const w = part(vm);
  assert.equal(w.hearth, 'Thelsamar');
  assert.equal(w.zone, 'Loch Modan');
  assert.deepEqual(w.npcs[0], { name: 'Yanni Stoutheart', sub: 'General Supplies', does: ['vendor'], x: 35.4, y: 48.2,
    sells: ['Refreshing Spring Water', 'Heavy Shot', 'Light Shot'], seen: true });
  assert.equal(validatePart('world', w).ok, true);
  assert.equal(vm.json('STUB.identityCalls').length ?? Object.keys(vm.json('STUB.identityCalls') || {}).length, 0, 'no UnitName: the name comes from the NPC\'s tooltip');
});

test('the flight master\'s map: the paths this character knows; an innkeeper by its gossip option; another zone\'s NPCs left out', () => {
  const vm = session();
  vm.run(TALK(1572, 'Thorgrum Borrelson', 'Gryphon Master'));
  vm.run(`NumTaxiNodes = function() return 3 end
TaxiNodeName = function(i) return ({ "Thelsamar, Loch Modan", "Ironforge, Dun Morogh", "Menethil Harbor, Wetlands" })[i] end
TaxiNodeGetType = function(i) return ({ "CURRENT", "REACHABLE", "NONE" })[i] end
STUB.FireEvent("TAXIMAP_OPENED")`);
  vm.run(TALK(6734, 'Innkeeper Hearthstove', 'Innkeeper'));
  vm.run('C_GossipInfo = { GetOptions = function() return { { name = "Make this inn your home.", type = "binder" } } end }; STUB.FireEvent("GOSSIP_SHOW")');
  let w = part(vm);
  assert.deepEqual(w.flights, ['Ironforge, Dun Morogh', 'Thelsamar, Loch Modan'], 'not one it doesn\'t know');
  assert.deepEqual(w.npcs.map(n => `${n.name}: ${n.does.join(',')}`).sort(), ['Innkeeper Hearthstove: innkeeper', 'Thorgrum Borrelson: flight']);
  vm.run('STUB.player.zone = "Wetlands"');
  w = part(vm);
  assert.equal(w.npcs, undefined, 'in the Wetlands: Loch Modan\'s NPCs aren\'t nearby');
  assert.deepEqual(w.flights, ['Ironforge, Dun Morogh', 'Thelsamar, Loch Modan'], 'flights go everywhere');
});

test('QuestieDB, only when installed: the zone\'s other service NPCs, friendly ones, nearest first, after its read', () => {
  const vm = newVM();
  vm.run('STUB.UseQuestieDB()');
  vm.run(`LibQuestieDB.Enum.npcFlags = { VENDOR = 128, FLIGHT_MASTER = 8192, TRAINER = 16, INNKEEPER = 65536 }
local Npc = LibQuestieDB.Npc
local extra = {
  [1682] = { name = "Yanni Stoutheart", sub = "General Supplies", flags = 128, zone = 38, spawns = { [38] = { { 35.6, 48.1 } } }, friendly = "A" },
  [1686] = { name = "Irene Sureshot", sub = "Gunsmith", flags = 128, zone = 38, spawns = { [38] = { { 37.0, 47.0 } } }, friendly = "A" },
  [9999] = { name = "Grunt Vendor", sub = "General Goods", flags = 128, zone = 38, spawns = { [38] = { { 35.5, 48.0 } } }, friendly = "H" },
  [7777] = { name = "Just A Dwarf", flags = 0, zone = 38, spawns = {}, friendly = "A" },
}
Npc.GetAllIds = function() return { 1682, 1686, 9999, 7777 } end
Npc.npcFlags = function(id) return extra[id] and extra[id].flags end
Npc.subName = function(id) return extra[id] and extra[id].sub end
local name, zone, spawns, friendly = Npc.name, Npc.zoneID, Npc.spawns, Npc.friendlyToFaction
Npc.name = function(id) return extra[id] and extra[id].name or name(id) end
Npc.zoneID = function(id) return extra[id] and extra[id].zone or zone(id) end
Npc.spawns = function(id) return extra[id] and extra[id].spawns or spawns(id) end
Npc.friendlyToFaction = function(id) return extra[id] and extra[id].friendly or friendly(id) end
local get = LibQuestieDB.Support.Get
`);
  vm.login().advance(3.1);
  part(vm); // starts QuestieDB's read
  vm.advance(1);
  const w = part(vm);
  assert.deepEqual(w.npcs.map(n => `${n.name} <${n.sub}>`), ['Yanni Stoutheart <General Supplies>', 'Irene Sureshot <Gunsmith>'], 'the Horde vendor and the plain dwarf left out; nearest first');
  assert.equal(w.npcs[0].seen, undefined, 'from QuestieDB, not a visit');
});

test('without QuestieDB or any visit: the hearth and where you are, nothing made up', () => {
  const w = part(session());
  assert.deepEqual(w, { v: 1, zone: 'Loch Modan', sub: 'Stoutlager Inn', x: 35.4, y: 48.2, hearth: 'Thelsamar' });
});
