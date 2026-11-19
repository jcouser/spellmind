// The route (addon/Spellmind/Route.lua, docs/milestone-23-route.md phase 1): this character's steps
// where it stands, in an order that keeps the rules (pick up, do, turn in; a chain in order) and is
// short; ticked off by the game's state; the tracker window (/sm route).
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM } from '../helpers/addon-vm.mjs';

// A small Loch Modan (area 38, map 1432, 3000 x 2000 yards in the stub). The player stands at (40, 40).
// In the log: Kobold Candles (700, kill Tunnel Rats around (20, 20), back to Mountaineer Kadrell at
// (50, 52)), and Mountaineer's Report (701, complete, to Kadrell too). To pick up: Ironband's
// Excavation (702, from Prospector Ironband at (85, 85), Stonesplinters at (87, 83), back to him);
// Not yet: Ironband Wants Help (703, after 702), Grey Pelts (704, far below the level).
const ZONE = `
  STUB.player.x, STUB.player.y = 0.40, 0.40
  STUB.player.level = 15
  STUB.quests = {
    { title = "Loch Modan", isHeader = true },
    { title = "Kobold Candles", questID = 700, level = 14 },
    { title = "Mountaineer's Report", questID = 701, level = 13, complete = true },
  }
  STUB.objectives = { [700] = { { text = "Tunnel Rat: 0/8", numFulfilled = 0, numRequired = 8 } } }
  STUB.questsOnMap = {}
  local Q, N = STUB.qdb.quests, STUB.qdb.npcs
  Q[700] = { name = "Kobold Candles", zone = 38, level = 14, obj = { { { 800 } }, {}, {} }, ender = 801 }
  Q[701] = { name = "Mountaineer's Report", zone = 38, level = 13, ender = 801 }
  Q[702] = { name = "Ironband's Excavation", zone = 38, level = 15, npc = 802, obj = { { { 803 } }, {}, {} }, ender = 802 }
  Q[703] = { name = "Ironband Wants Help", zone = 38, level = 16, npc = 802, single = { 702 }, ender = 802 }
  Q[704] = { name = "Grey Pelts", zone = 38, level = 6, npc = 802, obj = { { { 803 } }, {}, {} }, ender = 802 }
  N[800] = { name = "Tunnel Rat", zone = 38, spawns = { [38] = { { 20, 20 }, { 21, 21 }, { 19.5, 20.5 }, { 60, 10 } } } }
  N[801] = { name = "Mountaineer Kadrell", zone = 38, spawns = { [38] = { { 50, 52 } } }, friendly = "A" }
  N[802] = { name = "Prospector Ironband", zone = 38, spawns = { [38] = { { 85, 85 } } }, friendly = "A" }
  N[803] = { name = "Stonesplinter Trogg", zone = 38, spawns = { [38] = { { 87, 83 }, { 88, 84 } } } }
  STUB.UseQuestieDB()
  LibQuestieDB.Quest.objectives = function(id) local q = Q[id]; if q then return q.obj or { {}, {}, {} } end end
  LibQuestieDB.Quest.finishedBy = function(id) local q = Q[id]; if q and q.ender then return { { q.ender }, {} } end end
`;
const session = () => newVM({ before: ZONE }).login().advance(9);
const keys = vm => JSON.parse(vm.evaluate(`NS.State.JSON.encode((function()
  local out = {} for i, s in ipairs(NS.Route.Build().stops) do out[i] = s.key end return out end)())`));

test('the route: the log\'s quests and the zone\'s pickup, close goals as one stop, in an order that keeps the rules and is short', () => {
  const vm = session();
  assert.deepEqual(keys(vm), ['do:700', 'turnin:700,turnin:701', 'pickup:702,do:702,turnin:702'],
    'the rats first (the nearest step that can be done), then both turn-ins at Kadrell, then Ironband\'s quest at his camp');
  const later = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Route.Build().stops)'));
  assert.ok(!JSON.stringify(later).includes('"q":703'), 'a quest behind one not done isn\'t a step');
  assert.ok(!JSON.stringify(later).includes('"q":704'), 'a quest far below the level isn\'t a step');
  assert.equal(vm.evaluate('NS.Route.Here().zone'), 'Loch Modan');
});

test('the order: 2-opt keeps a rule even where breaking it would be shorter', () => {
  const vm = session();
  // Two stops on a line: the turn-in nearer than the objective. Shorter would be turn-in first; the rule says no.
  const r = JSON.parse(vm.evaluate(`NS.State.JSON.encode((function()
    local here = { w = 1000, h = 1000 }
    local a = { x = 10, y = 0, goals = { { kind = "turnin", q = 1 } } }
    local b = { x = 50, y = 0, goals = { { kind = "do", q = 1 } } }
    local rules = NS.Route.Rules({ a, b })
    local o = NS.Route.Order({ a, b }, { x = 0, y = 0 }, here, rules)
    return { o[1].goals[1].kind, o[2].goals[1].kind, NS.Route.Keeps(o, rules) }
  end)())`));
  assert.deepEqual(r, ['do', 'turnin', true]);
});

test('steps advance by the game\'s state: objectives full, a turn-in, a pick up; done ones never show', () => {
  const vm = session();
  vm.run('NS.Route.Build()');
  const cur = () => vm.evaluate('(NS.Route.Current() or {}).key or "none"');
  assert.equal(cur(), 'do:700');
  // The eighth rat: the objective is full, the quest complete.
  vm.run('STUB.objectives[700][1].numFulfilled = 8; STUB.quests[2].complete = true; STUB.FireEvent("QUEST_LOG_UPDATE")');
  assert.equal(cur(), 'turnin:700,turnin:701', 'on to the turn-ins, without a rebuild');
  // Both turned in.
  vm.run('table.remove(STUB.quests, 3); table.remove(STUB.quests, 2); STUB.completed[700] = true; STUB.completed[701] = true');
  assert.equal(cur(), 'pickup:702,do:702,turnin:702');
  // Picked up: that goal is done, the stop isn't yet.
  vm.run('table.insert(STUB.quests, { title = "Ironband\'s Excavation", questID = 702, level = 15 })');
  assert.equal(vm.evaluate('tostring(NS.Route.GoalDone({ kind = "pickup", q = 702 }))'), 'true');
  assert.equal(cur(), 'pickup:702,do:702,turnin:702');
  // A rebuild now leaves out what's done.
  assert.deepEqual(keys(vm), ['do:702,turnin:702']);
});

test('Skip moves past a step, Back brings it back; a rebuild keeps the skip', () => {
  const vm = session();
  vm.run('NS.Route.Build(); NS.Route.Skip()');
  assert.equal(vm.evaluate('NS.Route.Current().key'), 'turnin:700,turnin:701');
  vm.run('NS.Route.Build()');
  assert.equal(vm.evaluate('NS.Route.Current().key'), 'turnin:700,turnin:701', 'skipped still');
  vm.run('NS.Route.Back()');
  assert.equal(vm.evaluate('NS.Route.Current().key'), 'do:700');
});

test('/sm route: the tracker with the zone, the step, its goals, Go, Up next; Go sets the game\'s pin', () => {
  const vm = session();
  vm.slash('route');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.shown)'), 'true');
  assert.equal(vm.evaluate('SpellmindRoute.title:GetText()'), 'Route · Loch Modan');
  assert.equal(vm.evaluate('SpellmindRoute.step:GetText()'), 'Step 1 of 3');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /^Kobold Candles: 0\/8 Tunnel Rat$/);
  assert.match(vm.evaluate('SpellmindRoute.next[1]:GetText()'), /^Turn in Kobold Candles to Mountaineer Kadrell .*\(\+1\)/);
  assert.match(vm.evaluate('SpellmindRoute.next[2]:GetText()'), /^Pick up Ironband's Excavation/);
  vm.run('SpellmindRoute.go.scripts.OnClick(SpellmindRoute.go)');
  assert.equal(vm.num('STUB.waypoints[1].uiMapID'), 1432);
  assert.equal(vm.evaluate('string.format("%.2f", STUB.waypoints[1].position.x)'), '0.20', 'the rats\' densest spot, not the stray one');
  vm.slash('route');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.shown)'), 'false', 'and closes it');
});

test('without QuestieDB: the log\'s quests the game places on this map; no pickups; the tracker says what QuestieDB adds', () => {
  const vm = newVM({ before: `
    STUB.player.x, STUB.player.y = 0.40, 0.40
    STUB.quests = { { title = "Kobold Candles", questID = 700, level = 14 } }
    STUB.questsOnMap = { [1432] = { { questID = 700, x = 0.2, y = 0.2 } } }` }).login().advance(9);
  assert.deepEqual(keys(vm), ['do:700']);
  vm.run('STUB.questsOnMap = {}; NS.R.routeStale = true');
  vm.slash('route');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /Nothing left here.*With QuestieDB installed/s);
});

// Look to the Stars (705): bring a Bronze Tube (item 900), which nothing in Loch Modan drops.
const TUBE = `
  table.insert(STUB.quests, { title = "Look to the Stars", questID = 705, level = 15 })
  STUB.objectives[705] = { { text = "Bronze Tube: 0/1", numFulfilled = 0, numRequired = 1 } }
  local Q, N = STUB.qdb.quests, STUB.qdb.npcs
  Q[705] = { name = "Look to the Stars", zone = 38, level = 15, obj = { {}, {}, { { 900 } } }, ender = 801 }
  N[804] = { name = "Tinkerwiz", zone = 1537, spawns = { [1537] = { { 68, 44 } } }, friendly = "A" }
  local items = { [900] = { name = "Bronze Tube", vendors = { 804 } } }
  LibQuestieDB.Item = { name = function(id) return items[id] and items[id].name end, vendors = function(id) return items[id] and items[id].vendors end,
    npcDrops = function() return nil end, objectDrops = function() return nil end }`;

test('an item nothing here drops (the player, 2026-11-19: a Bronze Tube): no turn-in step before it; where it\'s sold, under Elsewhere', () => {
  const vm = session();
  vm.run(TUBE);
  const ks = keys(vm);
  assert.ok(!ks.some(k => /turnin:705/.test(k)), `no turn-in before the tube: ${ks}`);
  assert.equal(vm.evaluate('(function() local z = {} for k in pairs(NS.R.route.elsewhere) do z[#z + 1] = k end table.sort(z) return table.concat(z, ",") end)()'), 'Ironforge');
  assert.equal(vm.evaluate('NS.R.route.elsewhere.Ironforge[1].buy'), 'Bronze Tube');
  assert.equal(vm.evaluate('NS.Route.GoalText(NS.R.route.elsewhere.Ironforge[1])'), 'Look to the Stars: 0/1 Bronze Tube |cff888888(sold by Tinkerwiz)|r');
  vm.slash('route');
  assert.match(vm.evaluate('SpellmindRoute.also:GetText()'), /Elsewhere: Ironforge: 1/);
});

test('an item sold in this zone: a step at the vendor, then the turn-in', () => {
  const vm = session();
  vm.run(TUBE + `
    STUB.qdb.npcs[804].spawns = { [38] = { { 45, 45 } } }`);
  const ks = keys(vm);
  const buy = ks.findIndex(k => /do:705/.test(k)), back = ks.findIndex(k => /turnin:705/.test(k));
  assert.ok(buy >= 0 && back > buy, `buy, then turn in: ${ks}`);
});

test('a route vendor without the item (limited stock, the player 2026-11-19): the step moves off, a line says so, Auction House suggested', () => {
  const vm = session();
  vm.run(TUBE + `
    STUB.qdb.npcs[804].spawns = { [38] = { { 45, 45 } } }`);
  assert.ok(keys(vm).some(k => /do:705/.test(k)));
  // Herble's window, without a Bronze Tube.
  vm.run(`UnitGUID = (function(old) return function(u) if u == "npc" then return "Creature-0-5250-0-38-804-0000ABCD" end return old(u) end end)(UnitGUID)
    GetMerchantNumItems = function() return 2 end
    GetMerchantItemLink = function(i) return "item:" .. ({ 2901, 4399 })[i] end
    STUB.FireEvent("MERCHANT_SHOW")`);
  assert.ok(!JSON.stringify(vm.evaluate('(function() local o = {} for _, s in ipairs(NS.R.route.stops) do o[#o + 1] = s.key end return table.concat(o, " ") end)()')).includes('do:705'), 'off the route');
  assert.ok(vm.savedLines().some(l => /Tinkerwiz has no Bronze Tube right now.*Auction House/.test(l)) || vm.chatLines().some(l => /Tinkerwiz has no Bronze Tube right now/.test(l)));
  assert.match(vm.evaluate('NS.Route.GoalText(NS.R.route.elsewhere[""][1])'), /Tinkerwiz has none right now: try the Auction House or an engineer/);
});
