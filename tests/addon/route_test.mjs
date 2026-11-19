// The route (addon/Spellmind/Route.lua, docs/milestone-23-route.md phase 1): this character's steps
// where it stands, in an order that keeps the rules (pick up, do, turn in; a chain in order) and is
// short; ticked off by the game's state; the tracker window (/sm route).
import test from 'node:test';
import assert from 'node:assert/strict';
import { newVM, reloadVM } from '../helpers/addon-vm.mjs';

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
  assert.deepEqual(keys(vm), ['do:700', 'turnin:700,turnin:701', 'pickup:702,do:702,turnin:702,pickup:703,turnin:703'],
    'the rats first (the nearest step that can be done), then both turn-ins at Kadrell, then Ironband\'s quest at his camp, and its follow-up from him after the turn-in');
  const later = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Route.Build().stops)'));
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
  assert.equal(cur(), 'pickup:702,do:702,turnin:702,pickup:703,turnin:703');
  // Picked up: that goal is done, the stop isn't yet.
  vm.run('table.insert(STUB.quests, { title = "Ironband\'s Excavation", questID = 702, level = 15 })');
  assert.equal(vm.evaluate('tostring(NS.Route.GoalDone({ kind = "pickup", q = 702 }))'), 'true');
  assert.equal(cur(), 'pickup:702,do:702,turnin:702,pickup:703,turnin:703');
  // A rebuild now leaves out what's done.
  assert.deepEqual(keys(vm), ['do:702,turnin:702,pickup:703,turnin:703'], 'and the follow-up after it');
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
  assert.equal(vm.evaluate('SpellmindRoute.next[1]:GetText()'), 'Turn in 2 quests to Mountaineer Kadrell', 'two turn-ins to one NPC: one line');
  assert.match(vm.evaluate('SpellmindRoute.next[2]:GetText()'), /^Pick up \|cffffff00\[15\]\|r Ironband's Excavation/, 'its level, in the game\'s colour');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.go)'), 'nil', 'no Go: the arrow and the map show the way');
  assert.equal(vm.evaluate('string.format("%.2f", NS.Route.Current().x / 100)'), '0.20', 'the rats\' densest spot, not the stray one');
  assert.match(vm.evaluate('SpellmindRoute.credit:GetText()'), /Quest data from Questie/, 'the credit, its own line');
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
  // Its own heading, one line per zone saying what's there (the player, 2026-11-19: the crammed line was hard to read).
  assert.equal(vm.evaluate('SpellmindRoute.awayLabel:GetText()'), 'Elsewhere');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.awayLabel.shown)'), 'true');
  assert.match(vm.evaluate('SpellmindRoute.away[1]:GetText()'), /Ironforge:.*Look to the Stars: 0\/1 Bronze Tube/);
  assert.equal(vm.evaluate('tostring(SpellmindRoute.away[2].shown)'), 'false', 'no empty lines');
  // No known spot and above the level: named, not counted.
  const lines = vm.evaluate(`(function() local o = {} for _, l in ipairs(NS.Route.AwayLines({ elsewhere = { [""] = { { title = "Ogre Thievery" } } }, later = { "Gyrodrillmatic Excavationators" } })) do o[#o + 1] = l end return table.concat(o, "\\n") end)()`);
  assert.match(lines, /No known spot:\|r Ogre Thievery/);
  assert.match(lines, /Above your level for now:\|r Gyrodrillmatic Excavationators/);
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
  // Kept through a /reload (the saved data), and tried again after a few hours (limited stock restocks).
  assert.ok(vm.num('SpellmindDB.routeNoStock["804:900"]') > 0, 'in the saved data');
  vm.run('NS.R.route = nil; NS.Route.Build()');
  assert.ok(!vm.evaluate('(function() local o = {} for _, s in ipairs(NS.R.route.stops) do o[#o + 1] = s.key end return table.concat(o, " ") end)()').includes('do:705'), 'still off after a rebuild');
  vm.run('SpellmindDB.routeNoStock["804:900"] = time() - 4 * 3600; NS.Route.Build()');
  assert.ok(vm.evaluate('(function() local o = {} for _, s in ipairs(NS.R.route.stops) do o[#o + 1] = s.key end return table.concat(o, " ") end)()').includes('do:705'), 'back after the hours pass');
});

test('a giver who also takes the quest back, its mobs elsewhere (the player, 2026-11-19: Calor, Worgen in the Woods): two visits, the turn-in after the kills', () => {
  const vm = session();
  vm.run(`
    local Q, N = STUB.qdb.quests, STUB.qdb.npcs
    Q[706] = { name = "Worgen in the Woods", zone = 38, level = 15, npc = 805, obj = { { { 806 } }, {}, {} }, ender = 805 }
    N[805] = { name = "Calor", zone = 38, spawns = { [38] = { { 42, 41 } } }, friendly = "A" }
    N[806] = { name = "Nightbane Shadow Weaver", zone = 38, spawns = { [38] = { { 10, 70 }, { 11, 71 } } } }`);
  const ks = keys(vm);
  const pick = ks.findIndex(k => /pickup:706/.test(k)), kill = ks.findIndex(k => /do:706/.test(k)), back = ks.findIndex(k => /turnin:706/.test(k));
  assert.ok(pick >= 0 && kill > pick && back > kill, `pick up, kill, then turn in: ${ks.join(' | ')}`);
  assert.equal(vm.evaluate('tostring(NS.Route.Keeps(NS.R.route.stops, NS.R.route.rules))'), 'true');
});

test('one NPC\'s many quests (the player, 2026-11-19: Field Captain Palandar\'s thirteen pick ups and three turn-ins): one line each, names under it, two "Then" lines, three Up next, the window fits', () => {
  const vm = session();
  vm.run(`
    local Q, N = STUB.qdb.quests, STUB.qdb.npcs
    N[807] = { name = "Field Captain Palandar", zone = 38, spawns = { [38] = { { 40.5, 40.5 } } }, friendly = "A" }
    N[808] = { name = "Deranged Ogre", zone = 38, spawns = { [38] = { { 70, 20 } } } }
    for i = 1, 6 do Q[710 + i] = { name = "Duskwood Mission " .. i, zone = 38, level = 15, npc = 807, obj = { { { 808 } }, {}, {} }, ender = 807 } end
    for i = 1, 2 do
      table.insert(STUB.quests, { title = "Duskwood Mission Done " .. i, questID = 730 + i, level = 15, complete = true })
      Q[730 + i] = { name = "Duskwood Mission Done " .. i, zone = 38, level = 15, ender = 807 }
    end`);
  vm.slash('route');
  // Wherever the order puts Palandar's stop (the shortest path may pass him on the way): skipped to it.
  for (let i = 0; i < 6 && !/Palandar/.test(vm.evaluate('SpellmindRoute.now:GetText()')); i++) vm.run('NS.Route.Skip()');
  assert.equal(vm.evaluate('SpellmindRoute.now:GetText()'), 'Turn in 2 quests to Field Captain Palandar', 'turn-ins first, as one line');
  assert.match(vm.evaluate('SpellmindRoute.nowSub:GetText()'), /^Duskwood Mission Done [12], Duskwood Mission Done [12]$/);
  assert.equal(vm.evaluate('SpellmindRoute.thens[1]:GetText()'), '|cff888888Then:|r Pick up 6 quests from Field Captain Palandar');
  const shown = [1, 2, 3, 4].map(i => vm.evaluate(`tostring(SpellmindRoute.next[${i}] and SpellmindRoute.next[${i}].shown)`));
  assert.deepEqual(shown, ['true', 'true', 'true', 'false'], 'three Up next lines at most');
  assert.ok(vm.num('SpellmindRoute.height') <= 260, `the window fits its lines: ${vm.num('SpellmindRoute.height')}`);
});

test('a giver who doesn\'t offer a pick up (the player, 2026-11-19: Season of Discovery missions Questie hides): off the route when you talk to him, until the next level', () => {
  const vm = session();
  vm.run(`
    local Q, N = STUB.qdb.quests, STUB.qdb.npcs
    N[807] = { name = "Field Captain Palandar", zone = 38, spawns = { [38] = { { 30, 60 } } }, friendly = "A" }
    N[808] = { name = "Deranged Ogre", zone = 38, spawns = { [38] = { { 31, 62 } } } }
    for i = 1, 3 do Q[740 + i] = { name = "Duskwood Mission " .. i, zone = 38, level = 15, npc = 807, obj = { { { 808 } }, {}, {} }, ender = 807 } end`);
  assert.equal(keys(vm).filter(k => /pickup:74[123]/.test(k)).length, 1, 'all three, at his spot');
  // Talking to him: he offers only Mission 2.
  vm.run(`UnitGUID = (function(old) return function(u) if u == "npc" then return "Creature-0-5250-0-38-807-0000ABCD" end return old(u) end end)(UnitGUID)
    C_GossipInfo = C_GossipInfo or {}
    C_GossipInfo.GetAvailableQuests = function() return { { questID = 742, title = "Duskwood Mission 2" } } end
    STUB.FireEvent("GOSSIP_SHOW")`);
  const after = keys(vm).join(' ');
  assert.ok(after.includes('pickup:742'), after);
  assert.ok(!/pickup:741|pickup:743/.test(after), `the two he didn't offer are off: ${after}`);
  assert.ok(vm.chatLines().some(l => /Field Captain Palandar doesn't offer 2 of the quests/.test(l)) || vm.savedLines().some(l => /doesn't offer 2/.test(l)));
  // The next level: they're tried again.
  vm.run('STUB.player.level = 16');
  assert.ok(/pickup:741/.test(keys(vm).join(' ')), 'back at the next level');
});

test('a quest the game server doesn\'t have (the player, 2026-11-19: Season of Discovery\'s Duskwood Missions; Palandar isn\'t in Forever): never a step; asked once, kept', () => {
  const vm = session();
  vm.run(`
    local Q, N = STUB.qdb.quests, STUB.qdb.npcs
    N[807] = { name = "Field Captain Palandar", zone = 38, spawns = { [38] = { { 30, 60 } } }, friendly = "A" }
    N[808] = { name = "Deranged Ogre", zone = 38, spawns = { [38] = { { 31, 62 } } } }
    Q[7777] = { name = "Duskwood Mission I", zone = 38, level = 15, npc = 807, obj = { { { 808 } }, {}, {} }, ender = 807 }
    STUB.serverUnknown[7777] = true
    NS.db.routeKnown = nil`);
  assert.ok(!keys(vm).join(' ').includes('7777'), 'not while the server is asked');
  vm.advance(1);
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeKnown[7777])'), 'false', 'the server said no: kept');
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeKnown[702])'), 'true', 'a quest it has: kept too');
  assert.ok(!keys(vm).join(' ').includes('7777'));
  assert.ok(keys(vm).join(' ').includes('pickup:702'), 'the zone\'s real quest is still there');
});

test('quests not in this version of the game (the player, 2026-11-19): Questie\'s own hidden list when Questie is loaded; Season of Discovery\'s ids on Forever without it', () => {
  const vm = session();
  vm.run(`
    local Q, N = STUB.qdb.quests, STUB.qdb.npcs
    N[807] = { name = "Field Captain Palandar", zone = 38, spawns = { [38] = { { 30, 60 } } }, friendly = "A" }
    N[808] = { name = "Deranged Ogre", zone = 38, spawns = { [38] = { { 31, 62 } } } }
    Q[81730] = { name = "Duskwood Mission I", zone = 38, level = 15, npc = 807, obj = { { { 808 } }, {}, {} }, ender = 807 }`);
  // The server knows its title (as Forever's does): only the hidden list or the id range can tell.
  assert.ok(!keys(vm).join(' ').includes('81730'), 'without Questie, on Forever: a Season of Discovery id is left out');
  assert.ok(keys(vm).join(' ').includes('pickup:702'));
  // With Questie's list: what it hides is left out, whatever the id; what it doesn't, stays.
  vm.run('QuestieLoader = { _modules = { QuestieCorrections = { hiddenQuests = { [702] = true, [81730] = false } } } }');
  const ks = keys(vm).join(' ');
  assert.ok(!ks.includes('pickup:702'), `Questie hides 702: ${ks}`);
  assert.ok(ks.includes('pickup:81730'), 'and says 81730 is fine: its list wins over the id range');
});

test('the tracker sized by its corner shows more of Up next; the fold shows the current step alone; both kept (the player, 2026-11-19)', () => {
  const vm = session();
  // Eight more quests to pick up, each at its own spot along the zone.
  vm.run(`
    local Q, N = STUB.qdb.quests, STUB.qdb.npcs
    for i = 1, 8 do
      N[820 + i] = { name = "Giver " .. i, zone = 38, spawns = { [38] = { { 5 + i * 9, 95 } } }, friendly = "A" }
      Q[750 + i] = { name = "Errand " .. i, zone = 38, level = 15, npc = 820 + i, ender = 820 + i }
    end`);
  vm.slash('route');
  const shown = () => Array.from({ length: 12 }, (_, i) => vm.evaluate(`tostring(SpellmindRoute.next[${i + 1}].shown)`)).filter(x => x === 'true').length;
  assert.equal(shown(), 3, 'three until it\'s sized');
  // The player drags the corner: the size is kept, and more steps fit.
  vm.run('SpellmindRoute.height = 480; SpellmindRoute.grip.scripts.OnMouseUp(SpellmindRoute.grip)');
  assert.equal(vm.num('SpellmindDB.routeUI.h'), 480);
  assert.ok(shown() > 3, `more of Up next: ${shown()}`);
  assert.equal(vm.num('SpellmindRoute.height'), 480, 'the player\'s height kept');
  // The fold: the current step alone; the choice kept.
  vm.run('SpellmindRoute.fold.scripts.OnClick(SpellmindRoute.fold)');
  assert.equal(shown(), 0);
  assert.equal(vm.evaluate('tostring(SpellmindRoute.skip.shown)'), 'false');
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeUI.compact)'), 'true');
  assert.ok(vm.num('SpellmindRoute.height') < 150, 'short when folded');
  vm.run('SpellmindRoute.fold.scripts.OnClick(SpellmindRoute.fold)');
  assert.ok(shown() > 3, 'unfolded: back to the player\'s size');
});

// Where next (the player, 2026-11-19: a leveling guide sent them to Stormwind while Duskwood still had
// quests for them). Ironforge (3000 yards east of Loch Modan's corner): two quests from Thane Ironbelly.
// Westfall (9000 yards): three from Gryan, and one above the level that doesn't count.
const MORE = `
  local Q, N = STUB.qdb.quests, STUB.qdb.npcs
  Q[710] = { name = "Forge Work", zone = 1537, level = 15, npc = 900 }
  Q[711] = { name = "Anvil Dust", zone = 1537, level = 16, npc = 900 }
  N[810] = { name = "Gryan Stoutmantle", zone = 40, spawns = { [40] = { { 56, 48 } } }, friendly = "A" }
  Q[712] = { name = "Westfall Stew", zone = 40, level = 14, npc = 810 }
  Q[713] = { name = "Harvest Golems", zone = 40, level = 15, npc = 810 }
  Q[714] = { name = "Murloc Fins", zone = 40, level = 16, npc = 810 }
  Q[715] = { name = "The Defias Lair", zone = 40, level = 22, req = 20, npc = 810 }`;

test('Where next: the zones by quests left for this character and the time to get there; the AI has it too', async () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  const zones = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Route.ZonesPart())'));
  assert.deepEqual(zones.map(z => z.zone), ['Loch Modan', 'Ironforge', 'Westfall'], 'here first while it has quests, then the nearer one');
  assert.equal(zones[0].here, true);
  assert.deepEqual([zones[1].toPickUp, zones[1].minutesAway], [2, 10]);
  assert.deepEqual([zones[2].toPickUp, zones[2].levels], [3, '14–16'], 'the one above the level left out');
  // The AI's advisor part carries it, and the app's contract takes it.
  const part = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Advisor.Part())'));
  assert.equal(part.whereNext.length, 3);
  const { validatePart } = await import('../../core/link/charstate.mjs');
  assert.equal(validatePart('advisor', part).ok, true);
  // Three steps left here: the tracker shows Where next, each line a pin at that zone's quest givers.
  vm.slash('route');
  assert.equal(vm.evaluate('SpellmindRoute.whereLabel:GetText()'), 'Where next');
  assert.equal(vm.evaluate('SpellmindRoute.where[1].text:GetText()'), '|cffffd100Ironforge:|r 2 quests to pick up · about 10 min away');
  // A click on a zone: the arrow points the way there (steps still left here), marked; again: back.
  vm.run('SpellmindRoute.where[2].scripts.OnClick(SpellmindRoute.where[2]); NS.Route.ArrowUpdate()');
  assert.equal(vm.evaluate('SpellmindArrow.text:GetText()'), 'Westfall: Gryan Stoutmantle');
  assert.match(vm.evaluate('SpellmindRoute.where[2].text:GetText()'), /^\|cff19ff19»\|r \|cffffd100Westfall/);
  assert.equal(vm.evaluate('tostring(STUB.waypoints[1])'), 'nil', 'no pin');
  vm.run('SpellmindRoute.where[2].scripts.OnClick(SpellmindRoute.where[2]); NS.Route.ArrowUpdate()');
  assert.match(vm.evaluate('SpellmindArrow.text:GetText()'), /Kobold Candles/, 'back to the steps');
  // Chosen, then a new zone reached: the choice is done.
  vm.run('SpellmindRoute.where[2].scripts.OnClick(SpellmindRoute.where[2]); STUB.FireEvent("ZONE_CHANGED_NEW_AREA")');
  assert.equal(vm.evaluate('tostring(NS.R.routeAim)'), 'nil');
});

test('Where next: done here, the band names the next zone and Go pins it', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run('STUB.quests = {}; for id = 700, 704 do STUB.completed[id] = true end');
  vm.slash('route');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /Done here at your level.*Next: .*Ironforge/);
  assert.match(vm.evaluate('SpellmindRoute.nowSub:GetText()'), /2 quests to pick up · about 10 min away/);
  assert.equal(vm.evaluate('SpellmindRoute.whereLabel:GetText()'), 'Or');
  assert.match(vm.evaluate('SpellmindRoute.where[1].text:GetText()'), /Westfall/);
  vm.run('NS.Route.ArrowUpdate()');
  assert.equal(vm.evaluate('SpellmindArrow.text:GetText()'), 'Ironforge: Thane Ironbelly', 'the arrow shows the way');
  assert.equal(vm.evaluate('tostring(STUB.waypoints[1])'), 'nil', 'no pin');
});

test('Where next waits while plenty is left here', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run('NS.Route.WHERE_WHEN = 1');
  vm.slash('route');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.whereLabel.shown)'), 'false');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.where[1].shown)'), 'false');
});

test('a narrow window wraps a long line (the player, 2026-11-19: it cut them off) and moves what\'s under it down', () => {
  const vm = session();
  vm.slash('route');
  const top = i => vm.num(`select(5, SpellmindRoute.next[${i}]:GetPoint())`);
  const gap = top(1) - top(2);
  assert.equal(gap, 15, 'one line each');
  // The first line wraps to two (the game measures 26).
  vm.run('SpellmindRoute.next[1].GetStringHeight = function() return 26 end; NS.Route.Draw()');
  assert.equal(top(1) - top(2), 30, 'the next line under both of its lines');
});

// The flight map in Loch Modan: Thelsamar where the player stands (1200, 800 in the world), Sentinel
// Hill at Gryan's spot in Westfall (10680, 960).
const TAXI = `
  GetTaxiMapID = function() return 1415 end
  NumTaxiNodes = function() return 3 end
  TaxiNodeName = function(i) return ({ "Thelsamar, Loch Modan", "Sentinel Hill, Westfall", "Menethil Harbor, Wetlands" })[i] end
  TaxiNodeGetType = function(i) return ({ "CURRENT", "REACHABLE", "NONE" })[i] end
  TaxiNodePosition = function(i) return ({ { 0.1, 0.1 }, { 0.89, 0.12 }, { 0.3, 0.3 } })[i][1], ({ { 0.1, 0.1 }, { 0.89, 0.12 }, { 0.3, 0.3 } })[i][2] end`;

test('travel by a flight path the character knows (the player, 2026-11-19): Westfall by air is nearer than Ironforge on foot', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED")');
  const spots = vm.json('NS.State.Me().flightSpots');
  assert.deepEqual(Object.keys(spots).sort(), ['Sentinel Hill, Westfall', 'Thelsamar, Loch Modan'], 'the known ones, not the one it doesn\'t know');
  assert.equal(Math.round(-spots['Sentinel Hill, Westfall'].y), 10680, 'west is +y: 10680 yards east is y = -10680');
  const zones = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Route.ZonesPart())'));
  assert.deepEqual(zones.map(z => z.zone), ['Loch Modan', 'Westfall', 'Ironforge']);
  assert.deepEqual([zones[1].minutesAway, zones[1].via], [5, 'fly Thelsamar to Sentinel Hill']);
  assert.equal(zones[2].via, undefined, 'Ironforge on foot');
  vm.slash('route');
  assert.equal(vm.evaluate('SpellmindRoute.where[1].text:GetText()'), '|cffffd100Westfall:|r 3 quests to pick up · about 5 min away by flight');
});

test('the flight map\'s spots are trusted only when the one you stand at comes out where you stand', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(TAXI + '; TaxiNodePosition = function(i) return 0.5, 0.5 end; STUB.FireEvent("TAXIMAP_OPENED")');
  const spots = vm.json('NS.State.Me().flightSpots');
  assert.deepEqual(Object.keys(spots), ['Thelsamar, Loch Modan'], 'just the one under your feet');
  assert.equal(Math.round(-spots['Thelsamar, Loch Modan'].y), 1200);
});

test('the hearthstone: its landing spot noted after it\'s used; used for travel only when it\'s ready', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  // Bound in Westfall; the player hearths there and the spot is noted, then walks back to Loch Modan.
  vm.run(`GetBindLocation = function() return "Sentinel Hill" end
    GetItemCount = function(id) return id == 6948 and 1 or 0 end
    STUB.hearthCD = 0
    GetItemCooldown = function(id) return 0, STUB.hearthCD end
    STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1436, "Westfall", 0.56, 0.48
    STUB.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8690)`); vm.advance(6);
  assert.equal(vm.evaluate('NS.State.Me().hearthSpot.name'), 'Sentinel Hill');
  vm.run('STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1432, "Loch Modan", 0.40, 0.40; NS.R.routeWhere = nil');
  let zones = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Route.ZonesPart())'));
  const west = () => zones.find(z => z.zone === 'Westfall');
  assert.deepEqual([west().minutesAway, west().via], [1, 'hearthstone to Sentinel Hill']);
  // On its cooldown: on foot again.
  vm.run('STUB.hearthCD = 3600; NS.R.routeWhere = nil');
  zones = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Route.ZonesPart())'));
  assert.equal(west().via, undefined);
  assert.equal(west().minutesAway, 30);
});

test('Where next pins a real quest giver, not the empty middle of a spread-out group (the player, 2026-11-19: Wetlands)', () => {
  // Gryan at (50, 40), the Saldeans at (56, 46) and (58, 48): one group, its middle (54.7, 44.7) empty.
  const vm = newVM({ before: ZONE + MORE + `
    local N = STUB.qdb.npcs
    N[810].spawns = { [40] = { { 50, 40 } } }
    N[811] = { name = "Farmer Saldean", zone = 40, spawns = { [40] = { { 56, 46 } } }, friendly = "A" }
    N[812] = { name = "Salma Saldean", zone = 40, spawns = { [40] = { { 58, 48 } } }, friendly = "A" }
    STUB.qdb.quests[713].npc = 811
    STUB.qdb.quests[714].npc = 812` }).login().advance(9);
  const z = vm.json('(function() for _, z in ipairs(NS.Route.Zones(true)) do if z.zone == "Westfall" then return z.spot end end end)()');
  assert.deepEqual([z.x, z.y, z.giver], [56, 46, 'Farmer Saldean'], 'the giver nearest the middle (54.7, 44.7), where nobody stands');
  vm.run('NS.Route.Aim((function() for _, z in ipairs(NS.Route.Zones()) do if z.zone == "Westfall" then return z end end end)())');
  vm.slash('route');
  vm.run('NS.Route.ArrowUpdate()');
  assert.equal(vm.evaluate('SpellmindArrow.text:GetText()'), 'Westfall: Farmer Saldean');
});

// The arrow. Loch Modan's rats (the first step) are around (20.2, 20.5); the player at (40, 40) on a
// 3000 x 2000 yard map: about 595 yards west and 390 north.
test('the arrow: points at the current step from where you face, with the yards; green straight on', () => {
  const vm = session();
  vm.slash('route');
  assert.equal(vm.evaluate('tostring(SpellmindArrow.shown)'), 'true', 'shown with the tracker');
  const c = vm.json('NS.Route.Current()');
  const west = (40 - c.x) * 30, north = (40 - c.y) * 20;
  const angle = Math.atan2(west, north);
  vm.run('NS.Route.ArrowUpdate()');
  assert.equal(vm.num('math.floor(SpellmindArrow.yards + 0.5)'), Math.round(Math.hypot(west, north)));
  assert.ok(Math.abs(vm.num('SpellmindArrow.tex.rotation') - angle) < 1e-6, 'facing north: turned left, toward the north-west');
  assert.match(vm.evaluate('SpellmindArrow.dist:GetText()'), /^\d+ yd$/);
  assert.match(vm.evaluate('SpellmindArrow.text:GetText()'), /Kobold Candles/);
  // Facing it: no turn, green.
  vm.run(`STUB.player.facing = ${angle}; NS.Route.ArrowUpdate()`);
  assert.ok(Math.abs(vm.num('SpellmindArrow.tex.rotation')) < 1e-6);
  // Facing west: it's to the right (clockwise, a negative turn).
  vm.run(`STUB.player.facing = ${Math.PI / 2}; NS.Route.ArrowUpdate()`);
  assert.ok(Math.abs(vm.num('SpellmindArrow.tex.rotation') - (angle - Math.PI / 2)) < 1e-6);
  // Standing on it.
  vm.run(`STUB.player.x, STUB.player.y = ${c.x / 100}, ${c.y / 100}; NS.Route.ArrowUpdate()`);
  assert.match(vm.evaluate('SpellmindArrow.dist:GetText()'), /You're there/);
  assert.equal(vm.evaluate('tostring(SpellmindArrow.tex.shown)'), 'false');
  // In an instance: no position, and it says so.
  vm.run('STUB.player.facing = false; NS.Route.ArrowUpdate()');
  assert.match(vm.evaluate('SpellmindArrow.dist:GetText()'), /No position in here/);
});

test('the arrow, done here: to the next zone\'s giver on foot, or to the flight master to fly from', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run('STUB.quests = {}; for id = 700, 704 do STUB.completed[id] = true end');
  vm.slash('route');
  vm.run('NS.Route.ArrowUpdate()');
  assert.equal(vm.evaluate('SpellmindArrow.text:GetText()'), 'Ironforge: Thane Ironbelly');
  assert.ok(vm.num('SpellmindArrow.yards') > 2000, 'into the next zone');
  // Knowing the flight paths: Westfall by air is best, and the arrow points at the flight master first.
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED"); NS.Route.Build(); NS.Route.Draw(); NS.Route.ArrowUpdate()');
  assert.equal(vm.evaluate('SpellmindArrow.text:GetText()'), 'Flight master at Thelsamar');
  assert.equal(vm.evaluate('SpellmindArrow.sub:GetText()'), 'then fly to Sentinel Hill', 'it lands in Westfall');
  assert.match(vm.evaluate('SpellmindArrow.dist:GetText()'), /You're there/, 'standing at it');
});

test('the arrow: right-click hides it (kept), /sm arrow brings it back; closing the tracker hides it', () => {
  const vm = session();
  vm.slash('route');
  vm.run('SpellmindArrow.scripts.OnClick(SpellmindArrow, "RightButton")');
  assert.equal(vm.evaluate('tostring(SpellmindArrow.shown)'), 'false');
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeUI.arrowOff)'), 'true');
  vm.run('NS.Route.Draw()');
  assert.equal(vm.evaluate('tostring(SpellmindArrow.shown)'), 'false', 'stays hidden');
  vm.slash('arrow');
  assert.equal(vm.evaluate('tostring(SpellmindArrow.shown)'), 'true');
  vm.slash('route');
  assert.equal(vm.evaluate('tostring(SpellmindArrow.shown)'), 'false', 'closed with the tracker');
});

test('a follow-up is planned after the turn-in that opens it (the player, 2026-11-19: Calor\'s next Worgen in the Woods); not one behind a quest done elsewhere', () => {
  const vm = newVM({ before: ZONE + `
    local Q = STUB.qdb.quests
    -- Kobold Candles (700, in the log, turned in to Kadrell here) opens Kobold Wicks (706) from Kadrell, then Kobold Wax (707).
    Q[706] = { name = "Kobold Wicks", zone = 38, level = 15, npc = 801, single = { 700 }, obj = { { { 800 } }, {}, {} }, ender = 801 }
    Q[707] = { name = "Kobold Wax", zone = 38, level = 16, npc = 801, single = { 706 }, ender = 801 }
    -- One behind a quest neither done nor on the route stays out.
    Q[708] = { name = "Far Errand", zone = 38, level = 15, npc = 801, single = { 9999 }, ender = 801 }` }).login().advance(9);
  const ks = keys(vm);
  const at = k => ks.findIndex(x => x.split(',').includes(k));
  assert.ok(at('turnin:700') >= 0 && at('pickup:706') >= 0, `planned: ${ks}`);
  assert.ok(at('turnin:700') <= at('pickup:706'), 'picked up after the turn-in');
  assert.ok(at('do:706') > at('pickup:706') && at('turnin:706') >= at('do:706'));
  assert.ok(at('pickup:707') >= at('turnin:706'), 'two steps down the chain');
  assert.ok(!ks.join(' ').includes(':708'), 'not behind a quest done elsewhere');
  // At Kadrell's stop: the turn-in before the pick up it opens.
  const stop = ks[at('pickup:706')].split(',');
  assert.ok(stop.indexOf('turnin:700') < stop.indexOf('pickup:706'), `in the stop: ${stop}`);
});

test('the follow-up after a turn-in is its own line in the stop, not counted with the pick up before it', () => {
  const vm = session();
  vm.run('NS.Route.Build()');
  const gs = JSON.parse(vm.evaluate(`NS.State.JSON.encode((function()
    for _, s in ipairs(NS.R.route.stops) do if s.key:find("pickup:703") then
      local o = {} for _, g in ipairs(NS.Route.Groups(s)) do o[#o + 1] = g.kind .. ":" .. g.goals[1].q .. "x" .. #g.goals end return o end end end)())`));
  assert.deepEqual(gs, ['pickup:702x1', 'do:702x1', 'turnin:702x1', 'pickup:703x1', 'turnin:703x1'], 'five lines, in order');
});

test('levels: a quest in the log to +3 is done on the route; +4 and up wait for the level; in a group, two more', () => {
  const vm = newVM({ before: ZONE + `
    table.insert(STUB.quests, { title = "Orange Errand", questID = 720, level = 19 })
    table.insert(STUB.quests, { title = "Red Errand", questID = 721, level = 20 })
    STUB.questsOnMap = { [1432] = { { questID = 720, x = 0.3, y = 0.3 }, { questID = 721, x = 0.31, y = 0.31 } } }
    STUB.grouped = false
    IsInGroup = function() return STUB.grouped end` }).login().advance(9);
  let ks = keys(vm).join(' ');
  assert.ok(!ks.includes('do:720') && !ks.includes('do:721'), `solo: +4 and +5 wait: ${ks}`);
  assert.deepEqual(vm.json('NS.R.route.later').sort(), ['Orange Errand', 'Red Errand']);
  vm.run('STUB.grouped = true');
  ks = keys(vm).join(' ');
  assert.ok(ks.includes('do:720') && !ks.includes('do:721'), 'in a group: +4 done, +5 still later');
  // Done in the group, then solo again: the turn-in is still on the route (free XP at any level).
  vm.run('STUB.grouped = false; STUB.quests[#STUB.quests].complete = true; STUB.qdb.quests[721] = { name = "Red Errand", zone = 38, level = 20, ender = 801 }');
  ks = keys(vm).join(' ');
  assert.ok(ks.includes('turnin:721'), `a done one above the level: its turn-in stays: ${ks}`);
  assert.ok(!vm.json('NS.R.route.later').includes('Red Errand'));
});

test('talking to a giver to turn in doesn\'t mark the follow-up he\'ll give after as one he doesn\'t offer (the player, 2026-11-19: Calor); what he shows clears an old mark', () => {
  const vm = newVM({ before: ZONE + `
    STUB.qdb.quests[706] = { name = "Kobold Wicks", zone = 38, level = 15, npc = 801, single = { 700 }, obj = { { { 800 } }, {}, {} }, ender = 801 }` }).login().advance(9);
  assert.ok(keys(vm).join(' ').includes('pickup:706'), 'planned');
  // At Kadrell, to turn in: he offers nothing to pick up yet.
  vm.run(`UnitGUID = (function(old) return function(u) if u == "npc" then return "Creature-0-5250-0-38-801-0000ABCD" end return old(u) end end)(UnitGUID)
    C_GossipInfo = C_GossipInfo or {}
    C_GossipInfo.GetAvailableQuests = function() return {} end
    STUB.FireEvent("GOSSIP_SHOW")`);
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeNotOffered[706])'), 'nil', 'not marked: it waits on Kobold Candles');
  assert.ok(keys(vm).join(' ').includes('pickup:706'), 'still planned');
  // An old mark (from before this fix): cleared when he shows it.
  vm.run('SpellmindDB.routeNotOffered[706] = 15; table.remove(STUB.quests, 2); STUB.completed[700] = true; NS.Route.Build()');
  assert.ok(!keys(vm).join(' ').includes('pickup:706'), 'off while marked');
  vm.run('C_GossipInfo.GetAvailableQuests = function() return { { questID = 706, title = "Kobold Wicks" } } end; STUB.FireEvent("GOSSIP_SHOW")');
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeNotOffered[706])'), 'nil');
  assert.ok(keys(vm).join(' ').includes('pickup:706'), 'back on the route');
});

test('a quest is done on the route to +2 solo (the AI\'s review: leave a +3 one until closer), +4 in a group; orange ones picked up for later', () => {
  const vm = newVM({ before: ZONE + `
    STUB.qdb.quests[729] = { name = "Hard Pick Up", zone = 38, level = 18, npc = 802, ender = 802 }
    STUB.qdb.quests[730] = { name = "Orange Pick Up", zone = 38, level = 19, npc = 802, ender = 802 }
    STUB.qdb.quests[731] = { name = "Red Pick Up", zone = 38, level = 20, npc = 802, ender = 802 }
    STUB.qdb.npcs[809] = { name = "Lonely Hermit", zone = 38, spawns = { [38] = { { 8, 92 } } }, friendly = "A" }
    STUB.qdb.quests[732] = { name = "Hermit's Errand", zone = 38, level = 19, npc = 809, ender = 809 }
    STUB.grouped = false
    IsInGroup = function() return STUB.grouped end` }).login().advance(9);
  let ks = keys(vm).join(' ');
  assert.ok(ks.includes('pickup:729') && !ks.includes('turnin:729'), `solo, +3: picked up for later, not done: ${ks}`);
  assert.ok(ks.includes('pickup:730') && !ks.includes('turnin:730'), `solo, +4: picked up for later, not done: ${ks}`);
  assert.ok(!ks.includes(':731'), `solo, +5: not at all: ${ks}`);
  assert.ok(!ks.includes(':732'), `+4 from a giver the route doesn't pass: no detour: ${ks}`);
  vm.run('STUB.player.x, STUB.player.y = 0.085, 0.915');
  assert.ok(keys(vm).join(' ').includes('pickup:732'), 'standing by that giver: picked up for later');
  vm.run('STUB.player.x, STUB.player.y = 0.40, 0.40');
  assert.equal(vm.evaluate(`(function() for _, s in ipairs(NS.R.route.stops) do for _, g in ipairs(s.goals) do
    if g.q == 730 then return NS.Route.GoalText(g) end end end end)()`), 'Pick up |cffffff00[19]|r Orange Pick Up |cff888888(for later)|r');
  vm.run('STUB.grouped = true');
  ks = keys(vm).join(' ');
  assert.ok(ks.includes('turnin:729') && ks.includes('turnin:730'), `in a group: +3 and +4 done: ${ks}`);
  assert.ok(ks.includes('pickup:731') && !ks.includes('turnin:731'), `in a group: +5 for later: ${ks}`);
});

// The world map: a canvas 1000 x 667 showing Loch Modan.
const MAP = `
  WorldMapFrame.canvas = CreateFrame("Frame", nil, WorldMapFrame)
  WorldMapFrame.canvas:SetSize(1000, 667)
  function WorldMapFrame:GetCanvas() return self.canvas end
  STUB.mapShown = 1432
  function WorldMapFrame:GetMapID() return STUB.mapShown end`;

test('the world map: each step still to do numbered at its spot, its objective\'s area shaded (the player, 2026-11-19)', () => {
  const vm = session();
  vm.run(MAP);
  vm.slash('route');
  const M = 'NS.Route.marks';
  assert.equal(vm.num(`${M}.shown`), 3, 'three steps, three dots');
  assert.equal(vm.evaluate(`${M}.dots[1].num:GetText()`), '1');
  // The rats' area (around 20.2, 20.5): at least 2.5% each way, so 50 x 33 on the canvas.
  const a = vm.json(`(function() local t = ${M}.areas[1]; local _, _, _, x, y = t:GetPoint(); return { x = x, y = y, w = t.width, h = t.height, shown = t.shown } end)()`);
  assert.ok(Math.abs(a.x - 201.7) < 0.5 && Math.abs(a.y + 136.7) < 0.5, JSON.stringify(a));
  assert.ok(Math.abs(a.w - 50) < 0.01 && Math.abs(a.h - 33.35) < 0.01, JSON.stringify(a));
  assert.equal(a.shown, true);
  assert.equal(vm.evaluate(`tostring(${M}.areas[2] and ${M}.areas[2].shown)`), 'true', 'Ironband\'s troggs too');
  assert.equal(vm.evaluate(`tostring(${M}.dots[2].scripts.OnClick)`), 'nil', 'hover only: no pin');
  // The rats done: their dot and area go; the numbers stay the tracker's.
  vm.run('STUB.objectives[700][1].numFulfilled = 8; STUB.quests[2].complete = true; STUB.FireEvent("QUEST_LOG_UPDATE")');
  assert.equal(vm.num(`${M}.shown`), 2);
  assert.equal(vm.evaluate(`${M}.dots[1].num:GetText()`), '2');
  assert.equal(vm.evaluate('SpellmindRoute.step:GetText()'), 'Step 2 of 3');
  // Another map shown: none; the tracker closed: none.
  vm.run('STUB.mapShown = 1436; NS.Route.DrawMap()');
  assert.equal(vm.num(`${M}.shown`), 0);
  vm.run('STUB.mapShown = 1432; NS.Route.DrawMap()');
  assert.equal(vm.num(`${M}.shown`), 2);
  vm.slash('route');
  assert.equal(vm.num(`${M}.shown`), 0, 'closed with the tracker');
  assert.equal(vm.evaluate(`tostring(${M}.dots[1].shown)`), 'false');
});

test('the route on stays on: open again after a /reload and at login; the X turns it off, kept (the player, 2026-11-19)', () => {
  let vm = session();
  vm.slash('route');
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeUI.on)'), 'true');
  vm = reloadVM(vm, { before: ZONE }).login().advance(5);
  assert.equal(vm.evaluate('tostring(SpellmindRoute and SpellmindRoute.shown)'), 'true', 'open again after the /reload');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /Kobold Candles/);
  vm.run('SpellmindRoute.close.scripts.OnClick(SpellmindRoute.close)');
  assert.equal(vm.evaluate('tostring(SpellmindDB.routeUI.on)'), 'nil');
  assert.ok(vm.chatLines().some(l => /The route is off\. \/sm route, or Settings, brings it back\./.test(l)));
  vm = reloadVM(vm, { before: ZONE }).login().advance(5);
  assert.equal(vm.evaluate('tostring(SpellmindRoute and SpellmindRoute.shown or false)'), 'false', 'off stays off');
});

test('the Route tab (the player, 2026-11-19: the route is a core feature, not a switch in Settings): its switches, every step with Skip, where next with Aim', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(MAP);
  vm.run('NS.Panel.Show("route")');
  const drawn = () => { const v = vm.json('SpellmindPanel.drawn'); return Array.isArray(v) ? v : Object.values(v || {}); };
  const rowOf = text => drawn().findIndex(x => x.kind === 'item' && typeof x.text === 'string' && x.text.includes(text)) + 1;
  const click = (row, k = 1) => vm.run(`SpellmindPanel.rows[${row}].actions[${k}].scripts.OnClick(SpellmindPanel.rows[${row}].actions[${k}], "LeftButton")`);
  assert.equal(vm.evaluate('SpellmindPanel.tabs[3].text:GetText()'), 'Route');
  // Off: the switch, the arrow's and the map's dimmed, no steps.
  assert.ok(rowOf('Quest route') > 0);
  assert.equal(drawn().filter(x => x.kind === 'head').map(x => x.text).join(','), 'Quest route');
  click(rowOf('Quest route'));
  assert.equal(vm.evaluate('tostring(SpellmindRoute.shown)'), 'true', 'on: the tracker opens');
  assert.equal(vm.evaluate('tostring(SpellmindArrow.shown)'), 'true');
  // On: the steps, numbered, the current one "now"; where next; the arrow's and map's switches.
  const heads = drawn().filter(x => x.kind === 'head').map(x => x.text);
  assert.deepEqual(heads.slice(0, 3), ['Quest route', 'Steps', 'Where next']);
  const first = drawn()[rowOf('1.|r ') - 1];
  assert.match(first.text, /Kobold Candles/);
  assert.match(first.right, /now/);
  assert.match(drawn()[rowOf('Quest route') - 1].sub, /Step 1 of 3 · Loch Modan/);
  // Skip the first from here: the tracker moves on; Unskip brings it back.
  click(rowOf('1.|r '));
  assert.equal(vm.evaluate('NS.Route.Current().key'), 'turnin:700,turnin:701');
  assert.match(drawn()[rowOf('1.|r ') - 1].right, /skipped/);
  click(rowOf('1.|r '));
  assert.equal(vm.evaluate('NS.Route.Current().key'), 'do:700');
  // Aim at a zone: the arrow's target.
  click(rowOf('Westfall'));
  assert.equal(vm.evaluate('tostring(NS.R.routeAim)'), '40');
  // The arrow and the map's steps off from here.
  click(rowOf('The arrow'));
  assert.equal(vm.evaluate('tostring(SpellmindArrow.shown)'), 'false');
  click(rowOf('Steps on the world map'));
  assert.equal(vm.num('NS.Route.marks.shown'), 0);
  // The quick asks: Review my route and Why this order?, with the route on.
  assert.equal(vm.evaluate('SpellmindPanel.asks[1].text:GetText()'), 'Ask: Review my route');
  assert.equal(vm.evaluate('SpellmindPanel.asks[2].text:GetText()'), 'Ask: Why this order?');
  assert.match(vm.evaluate('NS.Panel.RouteQuestion("ROUTE_REVIEW")'), /Review my quest route/);
  // The tracker's owl opens this tab.
  vm.run('NS.Panel.Show("quests"); SpellmindRoute.owl.scripts.OnClick(SpellmindRoute.owl)');
  assert.equal(vm.evaluate('NS.Panel.tab'), 'route');
  // Off again from here.
  click(rowOf('Quest route'));
  assert.equal(vm.evaluate('tostring(SpellmindRoute.shown)'), 'false');
});

test('the AI gets the route (advisor.route): the steps in words, without live counts; the contract takes it', async () => {
  const vm = session();
  vm.slash('route');
  const part = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Advisor.Part())'));
  assert.equal(part.route.zone, 'Loch Modan');
  assert.deepEqual([part.route.step, part.route.of], [1, 3]);
  assert.deepEqual(part.route.steps, ['1. do Kobold Candles (at 20, 21)', '2. turn in Kobold Candles, Mountaineer\'s Report to Mountaineer Kadrell (at 50, 52)',
    '3. pick up Ironband\'s Excavation (level 15) from Prospector Ironband; do Ironband\'s Excavation; turn in Ironband\'s Excavation to Prospector Ironband; pick up Ironband Wants Help (level 16) from Prospector Ironband; turn in Ironband Wants Help to Prospector Ironband (at 85, 85)'],
    'each with where it is (the AI searched the web for a giver\'s place)');
  const { validatePart } = await import('../../core/link/charstate.mjs');
  assert.equal(validatePart('advisor', part).ok, true);
  vm.slash('route');
  assert.equal(JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Advisor.Part())')).route, undefined, 'the route off: not sent');
});

test('the map\'s layer goes over the map\'s art, under its points of interest (seen in game: it was under the art)', () => {
  const vm = session();
  vm.run(MAP + `
    WorldMapFrame.canvas:SetFrameLevel(5)
    function WorldMapFrame:GetPinFrameLevelsManager()
      return { GetValidFrameLevel = function(self, kind) return kind == "PIN_FRAME_LEVEL_AREA_POI" and 600 or 50 end }
    end`);
  vm.slash('route');
  assert.equal(vm.num('SpellmindRouteMap:GetFrameLevel()'), 599);
  vm.run('WorldMapFrame.GetPinFrameLevelsManager = nil; NS.Route.DrawMap()');
  assert.equal(vm.num('SpellmindRouteMap:GetFrameLevel()'), 105, 'no levels to ask: well over the canvas');
});

test('the tracker\'s place is kept through a /reload (the player, 2026-11-19), and its size', () => {
  let vm = session();
  vm.slash('route');
  // Dragged: the game re-anchors it to the screen's corner.
  vm.run('SpellmindRoute:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80); SpellmindRoute.scripts.OnDragStop(SpellmindRoute)');
  assert.deepEqual(vm.json('SpellmindDB.routeUI.pos'), ['TOPLEFT', 'TOPLEFT', 120, -80]);
  vm.run('SpellmindRoute:SetSize(400, 420); SpellmindRoute.grip.scripts.OnMouseUp(SpellmindRoute.grip)');
  vm = reloadVM(vm, { before: ZONE }).login().advance(5);
  const p = vm.json('(function() local a, _, _, x, y = SpellmindRoute:GetPoint(); return { a, 0, 0, x, y } end)()');
  assert.deepEqual([p[0], p[3], p[4]], ['TOPLEFT', 120, -80], 'where it was left');
  assert.equal(vm.num('SpellmindRoute:GetWidth()'), 400);
  assert.equal(vm.num('SpellmindRoute:GetHeight()'), 420);
});

test('a window shorter than what it shows scrolls (the player, 2026-11-19: the text ran out of it)', () => {
  const vm = session();
  vm.slash('route');
  // The sections are the scroll's content, so the window clips them.
  assert.equal(vm.evaluate('tostring(SpellmindRoute.next[1].parent == SpellmindRoute.content)'), 'true');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.away[1].parent == SpellmindRoute.content)'), 'true');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.where[1].parent == SpellmindRoute.content)'), 'true');
  // Sized short: the content is taller than the room between the band and the credit line.
  vm.run('SpellmindDB.routeUI.h = 160; NS.Route.Draw()');
  assert.equal(vm.num('SpellmindRoute:GetHeight()'), 160);
  const contentH = vm.num('SpellmindRoute.content:GetHeight()');
  const bandH = vm.num('SpellmindRoute.band:GetHeight()');
  const room = 160 - (36 + bandH + 4) - 50;
  assert.ok(contentH > room, `content ${contentH} > room ${room}: it scrolls`);
  // The wheel scrolls it, within its range.
  vm.run('SpellmindRoute.scroll.GetVerticalScrollRange = function() return 40 end; SpellmindRoute.scroll.scripts.OnMouseWheel(SpellmindRoute.scroll, -1)');
  assert.equal(vm.num('SpellmindRoute.scroll.vscroll'), 30);
  vm.run('SpellmindRoute.scroll.GetVerticalScroll = function() return 30 end; SpellmindRoute.scroll.scripts.OnMouseWheel(SpellmindRoute.scroll, -1)');
  assert.equal(vm.num('SpellmindRoute.scroll.vscroll'), 40, 'not past its end');
  // Folded: no scroll.
  vm.run('SpellmindRoute.fold.scripts.OnClick(SpellmindRoute.fold)');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.scroll.shown)'), 'false');
});

test('two steps at one spot (a pick up and its turn-in, the objectives between): their dots side by side, not one on the other', () => {
  const vm = session();
  vm.run(MAP);
  vm.slash('route');
  vm.run(`NS.R.route = { map = 1432, zone = "Loch Modan", stops = {
      { x = 50, y = 50, key = "pickup:901", goals = { { kind = "pickup", q = 901, title = "A" } } },
      { x = 30, y = 30, key = "do:901", goals = { { kind = "do", q = 901, title = "A" } } },
      { x = 50.2, y = 50.1, key = "turnin:901", goals = { { kind = "turnin", q = 901, title = "A" } } } } }
    NS.Route.DrawMap()`);
  const at = k => vm.json(`(function() local _, _, _, x, y = NS.Route.marks.dots[${k}]:GetPoint(); return { x, y } end)()`);
  const [a, c] = [at(1), at(3)];
  assert.equal(vm.evaluate('NS.Route.marks.dots[3].num:GetText()'), '3');
  assert.equal(c[0] - a[0], vm.num('NS.Route.DOT') + 2, 'beside it, to the right');
  assert.ok(Math.abs(c[1] - a[1]) < 1, 'on the same line');
  const b = at(2);
  assert.deepEqual(b, [300, -200.1], 'one on its own spot stays there');
});

test('the way to a chosen zone on the map (the player, 2026-11-19: with the pins gone it showed nothing): a green » on each map that has it', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(MAP);
  vm.slash('route');
  vm.run('NS.Route.Aim((function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z end end end)())');
  const M = 'NS.Route.marks';
  // On Loch Modan's map: the steps; Gryan is off this map, so a mark on its edge toward Westfall.
  vm.run('NS.Route.DrawMap()');
  assert.equal(vm.num(`${M}.shown`), 3);
  assert.equal(vm.num(`${M}.legsShown`), 1);
  assert.equal(vm.evaluate(`${M}.legs[1].tip[1]`), 'Toward Westfall');
  // On Westfall's: Gryan, where the arrow heads; no steps (they're Loch Modan's).
  vm.run('STUB.mapShown = 1436; NS.Route.DrawMap()');
  assert.equal(vm.num(`${M}.shown`), 0);
  assert.equal(vm.num(`${M}.legsShown`), 1);
  const at = vm.json(`(function() local _, _, _, x, y = ${M}.legs[1]:GetPoint(); return { x, y } end)()`);
  assert.ok(Math.abs(at[0] - 560) < 0.5 && Math.abs(at[1] + 320.2) < 0.5, JSON.stringify(at));
  assert.equal(vm.evaluate(`${M}.legs[1].tip[1]`), 'Westfall: Gryan Stoutmantle');
  // By air: the flight master on Loch Modan's map too.
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED"); NS.Route.Build(); STUB.mapShown = 1432; NS.Route.DrawMap()');
  assert.equal(vm.num(`${M}.legsShown`), 2, 'the flight master, then the edge toward where it lands');
  assert.equal(vm.evaluate(`${M}.legs[1].tip[1]`), 'Flight master at Thelsamar');
  assert.equal(vm.evaluate(`${M}.legs[2].tip[1]`), 'Toward Westfall');
  // Back to the steps: none.
  vm.run('NS.R.routeAim = nil; NS.Route.DrawMap()');
  assert.equal(vm.num(`${M}.legsShown`), 0);
});

test('the route\'s line on the map (the player, 2026-11-19, as NeverQuestAlone\'s): you to the current step in gold, live; on through the steps; a switch', () => {
  const vm = session();
  vm.run(MAP);
  vm.slash('route');
  const M = 'NS.Route.marks';
  const line = k => vm.json(`{ from = ${M}.lines[${k}].from, to = ${M}.lines[${k}].to, color = ${M}.lines[${k}].color, shown = ${M}.lines[${k}].shown }`);
  assert.equal(vm.num(`${M}.linesShown`), 3, 'you to step 1, 1 to 2, 2 to 3');
  const first = line(1);
  assert.deepEqual(first.from.map(Math.round), [400, -267], 'from where you stand');
  assert.deepEqual(first.to.map(Math.round), [202, -137], 'to the rats');
  assert.deepEqual(first.color.slice(0, 3), [1, 0.82, 0], 'gold');
  assert.deepEqual(line(2).color.slice(0, 3), [0.62, 0.49, 1], 'then purple');
  // You move: the line follows, the rest stays.
  vm.run('STUB.player.x = 0.5; NS.Route.MapLive()');
  assert.deepEqual(line(1).from.map(Math.round), [500, -267]);
  // The switch (the Route tab's): off, none.
  vm.run('NS.Route.SetLines(false)');
  assert.equal(vm.num(`${M}.linesShown`), 0);
  assert.equal(vm.num(`${M}.shown`), 3, 'the dots stay');
  vm.run('NS.Route.SetLines(true)');
  assert.equal(vm.num(`${M}.linesShown`), 3);
});

test('the line to a chosen zone: green, from you through its legs, on the continent\'s map', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(MAP);
  vm.slash('route');
  vm.run('NS.Route.Aim((function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z end end end)())');
  vm.run('STUB.mapShown = 1415; NS.Route.DrawMap()');
  const M = 'NS.Route.marks';
  assert.equal(vm.num(`${M}.linesShown`), 1, 'you to Gryan');
  const l = vm.json(`{ from = ${M}.lines[1].from, to = ${M}.lines[1].to, color = ${M}.lines[1].color }`);
  assert.deepEqual(l.color.slice(0, 3), [0.3, 0.95, 0.4]);
  // Eastern Kingdoms here is 12000 x 8000 on a 1000 x 667 canvas: you at (1200, 800), Gryan at (10680, 960).
  assert.deepEqual(l.from.map(Math.round), [100, -67]);
  assert.deepEqual(l.to.map(Math.round), [890, -80]);
});

// The minimap: 140 px across, 200 yards to its rim (70 px), so 0.35 px a yard.
test('the minimap (the player, 2026-11-19): the current step, on the rim with an arrow when it\'s farther; the next one in view; a switch', () => {
  const vm = session();
  vm.slash('route');
  const P = 'NS.RoutePins.pins';
  vm.run('NS.RoutePins.Update(true)');
  // The rats: 595 yards west, 390 north: off the minimap, so on its rim toward them, with the arrow.
  assert.equal(vm.evaluate(`tostring(${P}[1].shown)`), 'true');
  assert.equal(vm.evaluate(`tostring(${P}[1].onEdge)`), 'true');
  assert.equal(vm.evaluate(`tostring(${P}[1].arrow.shown)`), 'true');
  assert.equal(vm.evaluate(`${P}[1].num:GetText()`), '1');
  const rim = vm.json(`(function() local _, _, _, x, y = ${P}[1]:GetPoint(); return { x, y } end)()`);
  assert.ok(rim[0] < 0 && rim[1] > 0, 'up and to the left: north-west');
  assert.ok(Math.hypot(rim[0], rim[1]) < 70, 'inside the rim');
  assert.equal(vm.evaluate(`tostring(${P}[2].shown)`), 'false', 'Kadrell, the next, is out of view');
  // Close to the rats: in view, where they are; Kadrell still out.
  vm.run('STUB.player.x, STUB.player.y = 0.22, 0.22; NS.Route.Draw(); NS.RoutePins.Update(true)');
  assert.equal(vm.evaluate(`tostring(${P}[1].onEdge)`), 'nil');
  const at = vm.json(`(function() local _, _, _, x, y = ${P}[1]:GetPoint(); return { x, y } end)()`);
  const c = vm.json('NS.Route.Current()');
  assert.ok(Math.abs(at[0] - (c.x - 22) * 30 * 0.35) < 0.5 && Math.abs(at[1] - (22 - c.y) * 20 * 0.35) < 0.5, JSON.stringify([at, c.x, c.y]));
  // The next in view: a wider minimap.
  vm.run('STUB.minimapRadius = 2000; NS.RoutePins.Update(true)');
  assert.equal(vm.evaluate(`tostring(${P}[2].shown)`), 'true');
  assert.equal(vm.evaluate(`${P}[2].num:GetText()`), '2');
  // A turning minimap, facing west: north (the rats) is now to the right.
  vm.run(`STUB.minimapRadius = 200; STUB.cvars.rotateMinimap = "1"; STUB.player.facing = ${Math.PI / 2}; NS.RoutePins.Update(true)`);
  const turned = vm.json(`(function() local _, _, _, x, y = ${P}[1]:GetPoint(); return { x, y } end)()`);
  assert.ok(Math.abs(turned[0] - at[1]) < 0.5 && Math.abs(turned[1] + at[0]) < 0.5, 'facing west: north to the right, west up: ' + JSON.stringify([at, turned]));
  // The switch: off, none.
  vm.run('STUB.cvars.rotateMinimap = nil; NS.Route.SetMinimap(false)');
  assert.equal(vm.evaluate(`tostring(${P}[1].shown)`), 'false');
  vm.run('NS.Route.SetMinimap(true)');
  assert.equal(vm.evaluate(`tostring(${P}[1].shown)`), 'true');
  // The tracker closed: none.
  vm.slash('route');
  assert.equal(vm.evaluate(`tostring(${P}[1].shown)`), 'false');
});

test('a zone on another continent says how: "by boat" (the player, 2026-11-19: Ashenvale\'s minutes didn\'t say)', () => {
  const vm = session();
  assert.equal(vm.evaluate('NS.Route.WhereText({ quests = 6, inLog = 0, minutes = 12, how = "boat" })'), '6 quests to pick up · about 12 min away by boat');
});

test('done here: no Up next, and no gap where it would be', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run('STUB.quests = {}; for id = 700, 704 do STUB.completed[id] = true end');
  vm.slash('route');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.nextLabel.shown)'), 'false');
  const bandBottom = -(36 + vm.num('SpellmindRoute.band:GetHeight()'));
  const top = 36 + vm.num('SpellmindRoute.band:GetHeight()') + 4; // the scroll's top, under the band
  // The first section under the band (the way there when it shows, else "Or") starts right under it.
  const first = vm.evaluate('tostring(SpellmindRoute.wayLabel.shown)') === 'true' ? 'wayLabel' : 'whereLabel';
  const orY = vm.num(`select(5, SpellmindRoute.${first}:GetPoint())`);
  assert.ok(orY > -24, `${first} right under the band: ${orY} (band ends at ${bandBottom}, scroll at -${top})`);
});

test('Where next is worked out again when the hearthstone comes off its cooldown, and when a flight map notes paths', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(`GetBindLocation = function() return "Sentinel Hill" end
    GetItemCount = function(id) return id == 6948 and 1 or 0 end
    STUB.hearthStart = GetTime()
    GetItemCooldown = function(id) return STUB.hearthStart, 60 end
    STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1436, "Westfall", 0.56, 0.48`);
  vm.run('NS.World.NoteHearth()');
  vm.run('STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1432, "Loch Modan", 0.40, 0.40');
  vm.slash('route');
  const west = () => JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Route.ZonesPart())')).find(z => z.zone === 'Westfall');
  assert.equal(west().via, undefined, 'on its cooldown: on foot');
  // The minute passes: the route is built again, and the hearthstone counts.
  vm.advance(63);
  assert.equal(vm.evaluate('NS.R.route.where and (function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z.via end end end)()'), 'hearthstone to Sentinel Hill');
  // A flight map opened: worked out again too.
  vm.run('NS.R.routeWhere = { at = GetTime(), area = 38, level = 15, list = {} }');
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED")');
  vm.advance(2);
  assert.ok(vm.num('#NS.R.routeWhere.list') > 0, 'the stale (empty) count replaced');
  assert.ok(vm.num('#NS.R.route.where') > 0, 'and the route built again');
});

test('a flight that lands short of the zone says where (the player, 2026-11-19: "fly on to Wetlands" with no path there)', () => {
  const vm = session();
  const z = (land) => `{ zone = "Wetlands", land = ${land} }`;
  assert.equal(vm.evaluate(`NS.Route.LandText(${z('{ name = "Thelsamar, Loch Modan" }')})`), 'then fly to Thelsamar, and on to Wetlands from there');
  assert.equal(vm.evaluate(`NS.Route.LandText(${z('{ name = "Menethil Harbor, Wetlands" }')})`), 'then fly to Menethil Harbor');
  // On the map: the landing spot is its own green mark, the line through it.
  const v2 = newVM({ before: ZONE + MORE }).login().advance(9);
  v2.run(MAP);
  v2.run(TAXI + '; TaxiNodeName = function(i) return ({ "Thelsamar, Loch Modan", "Sentinel Hill, Elwynn", "Menethil Harbor, Wetlands" })[i] end; STUB.FireEvent("TAXIMAP_OPENED")');
  v2.slash('route');
  v2.run('NS.Route.Aim((function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z end end end)()); STUB.mapShown = 1415; NS.Route.DrawMap()');
  assert.equal(v2.num('NS.Route.marks.legsShown'), 2, 'the flight master; where it lands and the quest giver, one stacked mark');
  assert.equal(v2.evaluate('NS.Route.marks.legs[2].tip[1]'), 'Land at Sentinel Hill');
  assert.equal(v2.evaluate('NS.Route.marks.legs[2].tip[2]'), 'Then on to Westfall from there');
  assert.equal(v2.evaluate('NS.Route.marks.legs[2].num:GetText()'), '»2', 'two legs in it');
});

// A detour (the player, 2026-11-19): Thane's Errand (750, done) is handed in to Thane Ironbelly in
// Ironforge, and opens Thane's Second Errand (751, from him), whose rats are here in Loch Modan.
const DETOUR = `
  table.insert(STUB.quests, { title = "Thane's Errand", questID = 750, level = 15, complete = true })
  local Q = STUB.qdb.quests
  Q[750] = { name = "Thane's Errand", zone = 38, level = 15, ender = 900 }
  Q[751] = { name = "Thane's Second Errand", zone = 38, level = 15, npc = 900, single = { 750 }, obj = { { { 800 } }, {}, {} }, ender = 801 }`;

test('routes across zones: a detour to hand in a quest elsewhere when what it opens here pays for the trip', () => {
  const vm = newVM({ before: ZONE + DETOUR }).login().advance(9);
  const ks = keys(vm);
  const at = k => ks.findIndex(x => x.split(',').includes(k));
  assert.ok(at('turnin:750') >= 0, `the turn-in in Ironforge: ${ks}`);
  assert.ok(at('pickup:751') >= 0 && at('do:751') > at('pickup:751') && at('turnin:751') >= at('do:751'), `then the follow-up, back here: ${ks}`);
  assert.ok(at('turnin:750') <= at('pickup:751'));
  // That stop is Ironforge's: its own map, and the tracker says so.
  const stop = vm.json(`(function() for _, s in ipairs(NS.R.route.stops) do if s.key:find("turnin:750") then return { map = s.map, zone = s.zoneName } end end end)()`);
  assert.deepEqual(stop, { map: 1455, zone: 'Ironforge' });
  assert.equal(vm.evaluate('tostring(NS.R.route.elsewhere.Ironforge)'), 'nil', 'not under Elsewhere any more');
  vm.slash('route');
  const lines = [1, 2, 3, 4].map(k => vm.evaluate(`SpellmindRoute.next[${k}]:GetText()`));
  assert.ok(lines.some(l => /^\|cffffd100In Ironforge:\|r Turn in Thane's Errand to Thane Ironbelly/.test(l)), JSON.stringify(lines));
  // The AI's steps name the zone too.
  const part = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Advisor.Part())'));
  assert.ok(part.route.steps.some(s => /In Ironforge: .*turn in Thane's Errand/.test(s)), JSON.stringify(part.route.steps));
});

test('no detour when another zone pays better: the turn-in waits under Elsewhere', () => {
  const vm = newVM({ before: ZONE + MORE + DETOUR }).login().advance(9);
  const ks = keys(vm).join(' ');
  assert.ok(!ks.includes('turnin:750') && !ks.includes(':751'), ks);
  assert.ok(vm.evaluate('NS.R.route.elsewhere.Ironforge[1].q') === '750' || vm.num('NS.R.route.elsewhere.Ironforge[1].q') === 750);
});

test('the map shows a stop on its own map: the Ironforge turn-in on Ironforge\'s, not on Loch Modan\'s', () => {
  const vm = newVM({ before: ZONE + DETOUR }).login().advance(9);
  vm.run(MAP);
  vm.slash('route');
  const shownHere = vm.num('NS.Route.marks.shown');
  vm.run('STUB.mapShown = 1455; NS.Route.DrawMap()');
  assert.equal(vm.num('NS.Route.marks.shown'), 1, 'the one in Ironforge');
  assert.ok(shownHere >= 3, `Loch Modan's: ${shownHere}`);
});

// The Deadmines (area 1581; its way in is in Westfall): Red Silk Bandanas (1001) from Gryan at Sentinel
// Hill, open now; Collecting Memories (1002) opens after The Defias Brotherhood (1003), from Gryan too,
// whose trappers are in Westfall.
const PREP = `
  local Q, N = STUB.qdb.quests, STUB.qdb.npcs
  N[810] = { name = "Gryan Stoutmantle", zone = 40, spawns = { [40] = { { 56, 48 } } }, friendly = "A" }
  N[830] = { name = "Defias Trapper", zone = 40, spawns = { [40] = { { 50, 60 }, { 51, 61 } } } }
  Q[1001].npc, Q[1001].ender = 810, 810
  Q[1003] = { name = "The Defias Brotherhood", zone = 40, level = 14, npc = 810, obj = { { { 830 } }, {}, {} }, ender = 810 }
  Q[1002].npc, Q[1002].ender, Q[1002].single = 810, 810, { 1003 }`;

test('dungeon prep (the player, 2026-11-19): its quests, the questline that opens the locked one, across zones, then the way in', () => {
  const vm = newVM({ before: ZONE + PREP }).login().advance(9);
  vm.run('NS.Route.SetMode("dungeon", "The Deadmines")');
  const ks = keys(vm);
  const at = k => ks.findIndex(x => x.split(',').includes(k));
  for (const k of ['pickup:1001', 'pickup:1003', 'do:1003', 'turnin:1003', 'pickup:1002', 'enter:0']) assert.ok(at(k) >= 0, `${k}: ${ks}`);
  assert.ok(at('pickup:1003') < at('do:1003') && at('do:1003') < at('turnin:1003') && at('turnin:1003') <= at('pickup:1002'), `the questline in order: ${ks}`);
  assert.equal(at('enter:0'), ks.length - 1, 'the way in last');
  assert.ok(!ks.join(' ').includes('turnin:1001'), 'the dungeon\'s own turn-ins wait for the run');
  assert.ok(!ks.join(' ').includes(':700'), 'not this zone\'s quests: it\'s the dungeon\'s plan');
  // Westfall's stops say so; the tracker says what it's for.
  vm.slash('route');
  assert.equal(vm.evaluate('SpellmindRoute.title:GetText()'), 'Route · The Deadmines prep');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /In Westfall:/);
  const door = vm.json(`(function() for _, s in ipairs(NS.R.route.stops) do if s.key == "enter:0" then return { map = s.map, x = s.x, y = s.y, text = NS.Route.StopText(s) } end end end)()`);
  assert.deepEqual([door.map, door.x, door.y], [1436, 42.6, 71.8]);
  assert.match(door.text, /In Westfall:.*Enter The Deadmines/);
});

test('dungeon prep: inside, the way in is done and its spot learned; done quests are turned in after the run; back to questing', () => {
  const vm = newVM({ before: ZONE + PREP + `
    table.insert(STUB.quests, { title = "Red Silk Bandanas", questID = 1001, level = 17 })` }).login().advance(9);
  vm.run('NS.Route.SetMode("dungeon", "The Deadmines")');
  vm.slash('route');
  // Standing at the door in Westfall, then inside.
  vm.run('STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1436, "Westfall", 0.43, 0.72; NS.Route.ArrowUpdate()');
  vm.run('STUB.instance = { name = "The Deadmines", type = "party" }; STUB.FireEvent("PLAYER_ENTERING_WORLD")');
  assert.equal(vm.evaluate('tostring(NS.Route.Entered("The Deadmines"))'), 'true');
  const learned = vm.json('SpellmindDB.routeEntrances.deadmines');
  assert.deepEqual([learned.map, Math.round(learned.x), Math.round(learned.y)], [1436, 43, 72], 'where you went in');
  // The run's done: back outside with the bandanas.
  vm.run('STUB.instance = nil; STUB.quests[#STUB.quests].complete = true; NS.Route.Build()');
  const ks = keys(vm);
  assert.ok(ks.some(k => k.includes('turnin:1001')), `the turn-in after the run: ${ks}`);
  assert.ok(!ks.some(k => k.includes('enter:0')), 'the way in done');
  // Back in Loch Modan, questing again.
  vm.run('STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1432, "Loch Modan", 0.40, 0.40; NS.Route.SetMode("questing")');
  assert.ok(keys(vm).some(k => k.includes('do:700')), 'this zone\'s quests again');
  assert.equal(vm.evaluate('SpellmindRoute.title:GetText()'), 'Route · Loch Modan');
});

test('the Route tab and the Dungeons tab: Prep a dungeon, back to questing', () => {
  const vm = newVM({ before: ZONE + PREP + `
    table.insert(STUB.quests, { title = "Red Silk Bandanas", questID = 1001, level = 17 })` }).login().advance(9);
  // The Deadmines in the log (the game tags its quests Dungeon, under its header).
  vm.run('NS.Dungeons.FromLog = function() return { { name = "The Deadmines", quests = {}, ready = 0, low = 17, high = 17 } } end');
  vm.run('NS.Route.SetOn(true); NS.Panel.Show("route")');
  const drawn = () => { const v = vm.json('SpellmindPanel.drawn'); return Array.isArray(v) ? v : Object.values(v || {}); };
  const rowOf = text => drawn().findIndex(x => x.kind === 'item' && typeof x.text === 'string' && x.text.includes(text)) + 1;
  const click = (row, k = 1) => vm.run(`SpellmindPanel.rows[${row}].actions[${k}].scripts.OnClick(SpellmindPanel.rows[${row}].actions[${k}], "LeftButton")`);
  assert.ok(rowOf('Plan for') > 0);
  const d = rowOf('The Deadmines');
  assert.ok(d > 0, JSON.stringify(drawn().map(x => x.text)));
  click(d);
  assert.equal(vm.evaluate('select(2, NS.Route.Mode())'), 'The Deadmines');
  assert.match(drawn()[rowOf('Plan for') - 1].right, /The Deadmines prep/);
  click(rowOf('Plan for'));
  assert.equal(vm.evaluate('NS.Route.Mode()'), 'questing');
});

test('a flight path sits on its own flight master (the player, 2026-11-19: Ironforge\'s was at the Great Forge)', () => {
  const vm = newVM({ before: ZONE + MORE + `
    LibQuestieDB.Enum.npcFlags = { FLIGHT_MASTER = 8192 }
    local Npc = LibQuestieDB.Npc
    local extra = { [352] = { name = "Thor", flags = 8192, zone = 40, spawns = { [40] = { { 56.6, 52.6 } } }, friendly = "A" } }
    Npc.GetAllIds = function() return { 352 } end
    Npc.npcFlags = function(id) return extra[id] and extra[id].flags end
    local name, zone, spawns, friendly = Npc.name, Npc.zoneID, Npc.spawns, Npc.friendlyToFaction
    Npc.name = function(id) return extra[id] and extra[id].name or name(id) end
    Npc.zoneID = function(id) return extra[id] and extra[id].zone or zone(id) end
    Npc.spawns = function(id) return extra[id] and extra[id].spawns or spawns(id) end
    Npc.friendlyToFaction = function(id) return extra[id] and extra[id].friendly or friendly(id) end` }).login().advance(9);
  vm.run('NS.World.Index()');
  vm.advance(1);
  // The flight map put Sentinel Hill's path at (56, 48) in Westfall; Thor stands at (56.6, 52.6), 92 yards off.
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED")');
  const f = vm.json('(function() for _, f in ipairs(NS.Route.Flights()) do if f.name == "Sentinel Hill, Westfall" then return f end end end)()');
  assert.equal(f.npc, 'Thor');
  assert.equal(Math.round(-f.y), Math.round(9000 + 0.566 * 3000), 'on Thor');
  // The arrow's line names him.
  vm.slash('route');
  vm.run('NS.Route.Aim((function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z end end end)()); NS.Route.ArrowUpdate()');
  assert.match(vm.evaluate('SpellmindArrow.text:GetText()'), /flight master at Thelsamar|Flight master at Thelsamar/);
});

test('a step in another zone: the way there on this map, to its edge, as "done here" draws it (the player, 2026-11-19: prep\'s Duskwood step showed nothing in Redridge)', () => {
  const vm = newVM({ before: ZONE + PREP }).login().advance(9);
  vm.run(MAP);
  vm.run('NS.Route.SetMode("dungeon", "The Deadmines")');
  vm.slash('route');
  // On foot (no flight paths known): the arrow says which way, the map marks its edge toward Westfall.
  vm.run('NS.Route.ArrowUpdate(); NS.Route.DrawMap()');
  assert.match(vm.evaluate('SpellmindArrow.text:GetText()'), /In Westfall:/);
  assert.match(vm.evaluate('SpellmindArrow.sub:GetText()'), /^head (east|north-east|south-east) to Westfall$/);
  const M = 'NS.Route.marks';
  assert.equal(vm.num(`${M}.legsShown`), 1);
  assert.equal(vm.evaluate(`tostring(${M}.legs[1].edge)`), 'true');
  assert.equal(vm.evaluate(`${M}.legs[1].tip[1]`), 'Toward Westfall');
  const at = vm.json(`(function() local _, _, _, x, y = ${M}.legs[1]:GetPoint(); return { x, y } end)()`);
  assert.ok(Math.abs(at[0] - 970) < 1, `on the right edge (3% in): ${at}`);
  assert.ok(vm.num(`${M}.linesShown`) >= 1, 'and the green line to it');
  // By air: the flight master first.
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED"); NS.R.routeWay = nil; NS.Route.ArrowUpdate()');
  assert.match(vm.evaluate('SpellmindArrow.text:GetText()'), /Flight master at Thelsamar/);
  assert.match(vm.evaluate('SpellmindArrow.sub:GetText()'), /^then fly to Sentinel Hill, for: .*In Westfall:/);
});

// The way there across zones: Loch Modan (0, 0), Ironforge (3000, 0) and Westfall (9000, 0) side by side
// in the stub's world; crossings at their shared edges, and a long road from Ironforge to Westfall.
const LINKS = `
  NS.Route.LINKS = {
    { "Loch Modan", 99, 50, "Ironforge", 1, 50, name = "the pass" },
    { "Ironforge", 99, 50, "Westfall", 1, 50, name = "the long road" },
  }
  NS.R.routeLinks = nil`;

test('the way there (the player, 2026-11-19): on foot through the crossings, leg by leg; by air when that\'s faster', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(LINKS);
  const legs = () => vm.json(`NS.Route.PlanLegs((NS.Route.Plan({ map = 1432, x = 40, y = 40 }, { map = 1436, x = 56, y = 48 })), { "Gryan" }, "Westfall")`);
  let l = legs();
  assert.deepEqual(l.map(x => x.tip[0]), ['Cross into Ironforge', 'Cross into Westfall', 'Gryan'], 'through Ironforge on foot');
  assert.equal(l[0].tip[1], 'By the pass (about here)');
  // Knowing the flight paths: fly from Thelsamar to Sentinel Hill instead.
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED")');
  l = legs();
  assert.deepEqual(l.map(x => x.tip[0]), ['Flight master at Thelsamar', 'Fly to Sentinel Hill', 'Gryan']);
  // No crossing joins them, no flight: no plan (the straight way stands).
  vm.run('NS.Route.LINKS = {}; NS.R.routeLinks = nil; SpellmindDB.chars = {}');
  assert.equal(vm.evaluate('tostring(NS.Route.Plan({ map = 1432, x = 40, y = 40 }, { map = 1436, x = 56, y = 48 }))'), 'nil');
});

test('the arrow and the map follow the planned legs; a walked crossing is learned and replaces the written one', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(MAP + LINKS);
  vm.slash('route');
  vm.run('NS.Route.Aim((function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z end end end)()); NS.R.routePlan = nil; NS.Route.ArrowUpdate(); NS.Route.DrawMap()');
  assert.equal(vm.evaluate('SpellmindArrow.text:GetText()'), 'Cross into Ironforge');
  assert.equal(vm.evaluate('SpellmindArrow.sub:GetText()'), 'then cross into Westfall');
  // Loch Modan's map: the crossing (on the map), then the edge toward Ironforge's next leg.
  const M = 'NS.Route.marks';
  assert.equal(vm.evaluate(`${M}.legs[1].tip[1]`), 'Cross into Ironforge');
  // Walking across at (99.5, 52) into Ironforge (0.5, 52), 30 yards: learned, and it replaces "the pass".
  vm.run('STUB.player.x, STUB.player.y = 0.995, 0.52; NS.Route.NoteOutside()');
  vm.run('STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1455, "Ironforge", 0.005, 0.52; NS.Route.NoteOutside()');
  const c = vm.json('SpellmindDB.routeCrossings[1]');
  assert.deepEqual([c.a.map, c.b.map], [1432, 1455]);
  const links = vm.json('(function() local o = {} for _, l in ipairs(NS.Route.Links()) do o[#o + 1] = l.name or "learned" end return o end)()');
  assert.deepEqual(links, ['learned', 'the long road'], 'the walked one in place of the written one');
  // Now in Ironforge, the plan starts here: the next leg first.
  vm.run('NS.R.routePlan = nil; NS.Route.ArrowUpdate()');
  assert.equal(vm.evaluate('SpellmindArrow.text:GetText()'), 'Cross into Westfall');
});

test('the way to a step in another zone: on the step\'s own map, its numbered dot ends the line, no second mark (the player, 2026-11-19)', () => {
  const vm = newVM({ before: ZONE + PREP }).login().advance(9);
  vm.run(MAP + `
    NS.Route.LINKS = { { "Loch Modan", 99, 50, "Westfall", 1, 50, name = "the road" } }
    NS.R.routeLinks = nil`);
  vm.run('NS.Route.SetMode("dungeon", "The Deadmines")');
  vm.slash('route');
  // Westfall's map: the step's dot, the crossing's mark, no » on the step.
  vm.run('STUB.mapShown = 1436; NS.R.routePlan = nil; NS.Route.DrawMap()');
  const M = 'NS.Route.marks';
  const tips = vm.json(`(function() local o = {} for k = 1, ${M}.legsShown do o[k] = ${M}.legs[k].tip[1] end return o end)()`);
  const list = Array.isArray(tips) ? tips : Object.values(tips || {});
  assert.ok(!list.some(x => /Pick up/.test(x)), `no » on the step: ${JSON.stringify(tips)}`);
  assert.ok(vm.num(`${M}.shown`) >= 1, 'its numbered dot');
  // Loch Modan's map: where the way leaves it (the crossing) still marked.
  vm.run('STUB.mapShown = 1432; NS.Route.DrawMap()');
  assert.equal(vm.evaluate(`${M}.legs[1].tip[1]`), 'Cross into Westfall');
});

test('a flight path named by its zone\'s short name still has its map (the player, 2026-11-19: "Lakeshire, Redridge" was left out)', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(TAXI + '; TaxiNodeName = function(i) return ({ "Thelsamar, Loch", "Sentinel Hill, Westfall", "Menethil Harbor, Wetlands" })[i] end; STUB.FireEvent("TAXIMAP_OPENED")');
  const f = vm.json('(function() for _, f in ipairs(NS.Route.Flights()) do if f.name == "Thelsamar, Loch" then return f end end end)()');
  assert.equal(f.map, 1432, '"Loch" is Loch Modan');
  assert.equal(vm.num('NS.Route.ZoneMap("Westfall")'), 1436);
  assert.equal(vm.evaluate('tostring(NS.Route.ZoneMap("Nowhere"))'), 'nil');
});

test('legs too close together for two marks are one, its tooltip naming both (the player, 2026-11-19: Darkshire\'s landing and step on the continent\'s map)', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run(MAP);
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED")');
  vm.slash('route');
  // Westfall chosen: the flight master at Thelsamar, the landing at Sentinel Hill and Gryan there,
  // on the continent's map (12000 x 8000 on 1000 px: Sentinel Hill and Gryan are the same few pixels).
  vm.run('NS.Route.Aim((function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z end end end)()); NS.R.routePlan = nil; STUB.mapShown = 1415; NS.Route.DrawMap()');
  const M = 'NS.Route.marks';
  const tips = vm.json(`(function() local o = {} for k = 1, ${M}.legsShown do o[k] = ${M}.legs[k].tip end return o end)()`);
  const list = Array.isArray(tips) ? tips : Object.values(tips || {});
  assert.equal(list.length, 2, `the flight master, then one mark for the landing and Gryan: ${JSON.stringify(list)}`);
  const last = Array.isArray(list[1]) ? list[1] : Object.values(list[1]);
  assert.match(last.join(' | '), /Fly to Sentinel Hill.*Westfall: Gryan Stoutmantle/);
  assert.equal(vm.evaluate(`${M}.legs[2].num:GetText()`), '»2');
});

test('travel times as measured (AzerothGPS\'s planner): 32 yards a second and 15 s a flight, the hearthstone 25 s; the player\'s own speed; a flight flown keeps its time', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  assert.ok(Math.abs(vm.num('NS.Route.FlightMinutes({ x = 0, y = 0 }, { x = 1920, y = 0 })') - 1.25) < 1e-9, '1920 yards: a minute, and 15 s');
  assert.equal(vm.num('NS.Route.Speed()'), 7, 'no reading: on foot');
  vm.run('GetUnitSpeed = function() return 0, 9.8 end');
  assert.equal(vm.num('NS.Route.Speed()'), 9.8, 'the game\'s (mounted)');
  vm.run('GetUnitSpeed = nil');
  // Flying Thelsamar to Sentinel Hill: 200 s on the clock.
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED")');
  vm.run('STUB.onTaxi = false; UnitOnTaxi = function() return STUB.onTaxi end; NS.Route.NoteFlight()');
  vm.run('STUB.onTaxi = true; NS.Route.NoteFlight()');
  vm.advance(200);
  vm.run('STUB.player.map, STUB.player.zone, STUB.player.x, STUB.player.y = 1436, "Westfall", 0.56, 0.48; STUB.onTaxi = false; NS.Route.NoteFlight()');
  assert.equal(vm.num('SpellmindDB.routeFlightTimes["Thelsamar, Loch Modan>Sentinel Hill, Westfall"]'), 200);
  assert.ok(Math.abs(vm.num(`NS.Route.FlightMinutes({ name = "Thelsamar, Loch Modan", x = 0, y = 0 }, { name = "Sentinel Hill, Westfall", x = 1, y = 0 })`) - (200 / 60 + 0.25)) < 1e-9, 'its own time next');
});

// Trails: a walk recorded, then the way that follows it. Loch Modan is 3000 x 2000 yards in the stub:
// 1% is 30 yards east-west, 20 yards north-south.
const WALK = (vm, pts) => { for (const [x, y] of pts) vm.run(`STUB.player.x, STUB.player.y = ${x}, ${y}; NS.Route.NoteOutside()`); };

test('trails (the player, 2026-11-19): a point every 10 yards as you walk, the same road walked again merged into it; Forget', () => {
  const vm = session();
  vm.slash('route');
  // East along y = 40%, from 40% to 50% (300 yards), a step of 0.5% (15 yards) at a time.
  const east = []; for (let x = 40; x <= 50; x += 0.5) east.push([x / 100, 0.40]);
  WALK(vm, east);
  const n1 = vm.num('NS.Route.TrailCount()');
  assert.ok(n1 >= 19 && n1 <= 22, `a point a step: ${n1}`);
  // Back the same way, 8 yards to the north: the same points.
  WALK(vm, east.slice().reverse().map(([x, y]) => [x, y - 0.004]));
  assert.ok(vm.num('NS.Route.TrailCount()') <= n1 + 2, 'merged, not a second road');
  // A jump (a portal, a loading screen) breaks it: no line across.
  vm.run('NS.Route.ForgetTrails()');
  assert.equal(vm.num('NS.Route.TrailCount()'), 0);
});

test('the way along a trail: around a bend instead of straight over it; the arrow aims ahead along it, the yards along it', () => {
  const vm = session();
  vm.run(MAP);
  vm.slash('route');
  // A trail from where the player stands (40, 40) south to (40, 60), then west to the rats' (20, 60) and north to them (20, 21).
  const pts = [];
  for (let y = 40; y <= 60; y += 0.5) pts.push([0.40, y / 100]);
  for (let x = 40; x >= 20; x -= 0.5) pts.push([x / 100, 0.60]);
  for (let y = 60; y >= 21; y -= 0.5) pts.push([0.20, y / 100]);
  WALK(vm, pts);
  // Back where we started.
  vm.run('STUB.player.x, STUB.player.y = 0.40, 0.40; NS.R.routeTrailWay = nil; NS.R.routeTrailAt = nil');
  const c = vm.json('NS.Route.Current()');
  const path = vm.json(`NS.Route.TrailBetween(NS.Route.PlayerWorld(), NS.Route.World(1432, ${c.x}, ${c.y}))`);
  const list = Array.isArray(path) ? path : Object.values(path || {});
  assert.ok(list.length >= 3 && list.length <= 6, `its bends kept, the rest simplified: ${list.length}`);
  // The arrow aims south, along the trail, not north-west straight at the rats.
  vm.run('STUB.player.facing = 0; NS.Route.ArrowUpdate()');
  const turn = vm.num('SpellmindArrow.tex.rotation');
  assert.ok(Math.abs(Math.abs(turn) - Math.PI) < 0.3, `south: ${turn}`);
  assert.ok(vm.num('SpellmindArrow.yards') > 1000, `the yards along the trail (400 + 600 + 780), not the 710 straight: ${vm.num('SpellmindArrow.yards')}`);
  // The map's gold line follows it: more than one part.
  vm.run('NS.Route.DrawMap()');
  assert.ok(vm.num('NS.Route.marks.linesShown') >= 4, 'the trail\'s bends drawn');
  // No trail near: straight, as before.
  vm.run('NS.Route.ForgetTrails(); NS.R.routeTrailWay = nil; NS.Route.ArrowUpdate()');
  const straight = Math.atan2((40 - c.x) * 30, (40 - c.y) * 20);
  assert.ok(Math.abs(vm.num('SpellmindArrow.tex.rotation') - straight) < 1e-6);
});

test('a trail far from the way is left: the straight way stands', () => {
  const vm = session();
  vm.slash('route');
  // A long loop far east, away from the way to the rats.
  const pts = [];
  for (let x = 40; x <= 90; x += 0.5) pts.push([x / 100, 0.40]);
  WALK(vm, pts);
  vm.run('STUB.player.x, STUB.player.y = 0.40, 0.40');
  const c = vm.json('NS.Route.Current()');
  assert.equal(vm.evaluate(`tostring(NS.Route.TrailBetween(NS.Route.PlayerWorld(), NS.Route.World(1432, ${c.x}, ${c.y})))`), 'nil');
});

test('the way there, listed under "Done here" and on the Route tab (the player, 2026-11-19)', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run('STUB.quests = {}; for id = 700, 704 do STUB.completed[id] = true end');
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED")');
  vm.slash('route');
  vm.run('NS.R.routePlan = nil; NS.Route.Draw()');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /Done here at your level.*Next: .*Westfall/);
  assert.equal(vm.evaluate('SpellmindRoute.wayLabel:GetText()'), 'The way there');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.wayLabel.shown)'), 'true');
  const lines = [1, 2, 3].map(k => vm.evaluate(`SpellmindRoute.way[${k}]:GetText()`));
  assert.match(lines[0], /^\|cffffd1001\.\|r Flight master at Thelsamar/);
  assert.match(lines[1], /2\.\|r Fly to Sentinel Hill/);
  assert.match(lines[2], /3\.\|r Westfall: Gryan Stoutmantle/);
  // The Route tab too.
  vm.run('NS.Panel.Show("route")');
  const v = vm.json('SpellmindPanel.drawn'); const d = Array.isArray(v) ? v : Object.values(v || {});
  assert.ok(d.some(x => x.kind === 'head' && x.text === 'The way there'));
  // Questing here again (steps left): no way there.
  vm.run('NS.Route.Aim(nil); STUB.completed = {}; table.insert(STUB.quests, { title = "Kobold Candles", questID = 700, level = 14 }); NS.Route.Build(); NS.Route.Draw()');
  assert.equal(vm.evaluate('tostring(SpellmindRoute.wayLabel.shown)'), 'false');
});

test('a swim on a trail counts at the swim\'s pace: taken only when it\'s really faster than going round (the player, 2026-11-19)', () => {
  const vm = session();
  vm.slash('route');
  vm.run('STUB.swimming = false; IsSwimming = function() return STUB.swimming end');
  // Two ways from (40, 40) to (40, 60), 400 yards straight south: a swim straight across, and a walk round
  // by (46, 50): 2 x 220 = 440 yards.
  const swim = []; for (let y = 40; y <= 60; y += 0.5) swim.push([0.40, y / 100]);
  vm.run('STUB.swimming = true'); WALK(vm, swim); vm.run('STUB.swimming = false; NS.R.routeTrailAt = nil');
  const round = [];
  for (let k = 0; k <= 20; k++) round.push([(40 + 6 * k / 20) / 100, (40 + 10 * k / 20) / 100]);
  for (let k = 1; k <= 20; k++) round.push([(46 - 6 * k / 20) / 100, (50 + 10 * k / 20) / 100]);
  WALK(vm, round); vm.run('NS.R.routeTrailAt = nil');
  const via = () => {
    const p = vm.json('NS.Route.TrailBetween(NS.Route.World(1432, 40, 40), NS.Route.World(1432, 40, 60))');
    const list = Array.isArray(p) ? p : Object.values(p || {});
    return list.some(q => -q.y > 0.43 * 3000) ? 'round' : 'swim';
  };
  // 400 yards swum at 1.48 a yard (~593) against 440 walked: round.
  assert.equal(via(), 'round');
  // A fast swimmer (the game says 7 and 7): the swim.
  vm.run('GetUnitSpeed = function() return 0, 7, 0, 7 end');
  assert.equal(via(), 'swim');
});

test('a prep route across zones goes by travel time, not the straight line (the player, 2026-11-19: it zig-zagged)', () => {
  // A third Deadmines quest from Thane Ironbelly in Ironforge. From Loch Modan, Ironforge is nearer in a
  // straight line, but Westfall is 5 minutes by air and Ironforge 10 on foot.
  const vm = newVM({ before: ZONE + PREP + `
    STUB.qdb.quests[1004] = { name = "Ironforge's Errand", zone = 1581, level = 17, npc = 900, ender = 900 }` }).login().advance(9);
  vm.run('NS.Route.SetMode("dungeon", "The Deadmines")');
  const firstZone = () => vm.evaluate('(function() local s = NS.R.route.stops[1]; return s.zoneName or "here" end)()');
  assert.equal(firstZone(), 'Ironforge', 'no flight paths: the nearer, Ironforge');
  vm.run(TAXI + '; STUB.FireEvent("TAXIMAP_OPENED"); NS.Route.Build()');
  assert.equal(firstZone(), 'Westfall', 'by air, Westfall first: the quicker');
});

test('yards between two spots on another zone\'s map are that map\'s, not the player\'s zone\'s size', () => {
  const vm = session();
  // Two spots 10% apart east-west on Westfall's map (3000 yards wide in the stub, like Loch Modan's): 300 yards.
  vm.run('STUB.mapSizes[1436] = { 6000, 4000 }');
  assert.equal(Math.round(vm.num('NS.Route.Yards({ map = 1436, x = 10, y = 50 }, { map = 1436, x = 20, y = 50 }, NS.Route.Here())')), 600, 'Westfall\'s 6000 yards, not Loch Modan\'s 3000');
});

test('XP for the walk (the player, 2026-11-19): a far quest with little XP is "worth skipping?" and comes later; the log\'s own XP read', () => {
  const vm = newVM({ before: ZONE + `
    STUB.questRewards = { [700] = { xp = 3000 }, [701] = { xp = 2500 } }
    local Q, N = STUB.qdb.quests, STUB.qdb.npcs
    -- A grey-ish errand (level 10 at 15) from a hermit in the far corner, a long walk for 800 XP.
    N[809] = { name = "Lonely Hermit", zone = 38, spawns = { [38] = { { 98, 2 } } }, friendly = "A" }
    Q[709] = { name = "Hermit's Errand", zone = 38, level = 10, npc = 809, ender = 809 }` }).login().advance(9);
  assert.equal(vm.num('NS.Route.QuestXP(700, 15, 14)'), 3000, 'the quest log\'s reward');
  assert.equal(vm.num('NS.Route.QuestXP(709, 15, 10)'), 800, 'an estimate by its level');
  assert.equal(vm.num('NS.Route.QuestXP(709, 21, 10)'), 80, 'far below: down to a tenth, as the game does');
  const ks = keys(vm);
  assert.equal(vm.evaluate('tostring(NS.R.route.low[709])'), 'true', `worth skipping: ${ks}`);
  assert.equal(vm.evaluate('tostring(NS.R.route.low[700])'), 'nil');
  assert.ok(ks[ks.length - 1].includes(':709'), `its stop last: ${ks}`);
  // Said on the tracker, the Route tab and to the AI.
  vm.slash('route');
  const all = [1, 2, 3, 4].map(k => vm.evaluate(`SpellmindRoute.next[${k}]:GetText()`) || '').join(' | ');
  assert.match(all, /Hermit's Errand.*worth skipping\? little XP for the walk/);
  const part = JSON.parse(vm.evaluate('NS.State.JSON.encode(NS.Advisor.Part())'));
  assert.ok(part.route.steps.some(x => /Hermit's Errand.*worth skipping\?/.test(x)));
  vm.run('NS.Panel.Show("route")');
  const v = vm.json('SpellmindPanel.drawn'); const d = Array.isArray(v) ? v : Object.values(v || {});
  assert.ok(d.some(x => /Kobold Candles|Mountaineer Kadrell/.test(x.text || '') && /XP/.test(x.right || '')), 'a turn-in step\'s XP');
});

test('skip chips (the player, 2026-11-19): the review\'s "Skip: <quest>" lines become buttons that skip that quest\'s steps', () => {
  const vm = session();
  vm.slash('route');
  vm.run('NS.Route.Build()');
  // The lines out of the text; only quests on the route; quotes and colour aside.
  const r = vm.json(`(function() local t, s = NS.Route.SkipLines("Looks good.\\nSkip: \\"Ironband's Excavation\\"\\n- Skip: |cffffd100Nope Quest|r\\nThen Wetlands.") return { t = t, s = s } end)()`);
  assert.equal(r.t, 'Looks good.\nThen Wetlands.');
  const s = Array.isArray(r.s) ? r.s : Object.values(r.s || {});
  assert.deepEqual(s.map(x => x.title), ["Ironband's Excavation"], 'not one off the route');
  // Its steps skipped.
  const n = vm.num(`NS.Route.SkipQuest(${s[0].q})`);
  assert.equal(n, 1, 'its one stop (pick up, do, turn in at Ironband)');
  assert.ok(!vm.evaluate('NS.Route.UpNext(5) and (function() local o = {} for _, x in ipairs(NS.Route.UpNext(5)) do o[#o + 1] = x.key end return table.concat(o, " ") end)()').includes('702'));
  vm.run('NS.Route.Back()');
  assert.ok(vm.evaluate('(function() local o = {} for _, x in ipairs(NS.Route.UpNext(5)) do o[#o + 1] = x.key end return table.concat(o, " ") end)()').includes('702'), 'Back brings it back');
  // The review question asks for the lines.
  assert.match(vm.evaluate('NS.Panel.RouteQuestion("ROUTE_REVIEW")'), /Skip: <the quest's exact name>/);
});

test('done here with a zone chosen: the band names the chosen one, "Or" offers the rest (the player, 2026-11-19)', () => {
  const vm = newVM({ before: ZONE + MORE }).login().advance(9);
  vm.run('STUB.quests = {}; for id = 700, 704 do STUB.completed[id] = true end');
  vm.slash('route');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /Next: .*Ironforge/, 'the best first');
  vm.run('NS.Route.Aim((function() for _, z in ipairs(NS.R.route.where) do if z.zone == "Westfall" then return z end end end)())');
  assert.match(vm.evaluate('SpellmindRoute.now:GetText()'), /Next: \|cffffd100Westfall\|r \|cff888888\(your choice\)/);
  const or = [1, 2, 3].map(k => vm.evaluate(`SpellmindRoute.where[${k}].text:GetText()`) || '');
  assert.ok(or.some(x => /Ironforge/.test(x)), `Ironforge under Or now: ${JSON.stringify(or)}`);
  assert.ok(!or.some(x => /Westfall/.test(x)), 'not Westfall twice');
});
