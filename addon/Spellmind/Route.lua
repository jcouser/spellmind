-- Route.lua: the route (docs/milestone-23-route.md, phase 1): this character's next steps where it
-- stands, in an efficient order, ticked off by what happens in the game, in a small tracker window.
--
--   steps     pick up, do (a quest's objectives), turn in; grouped when they're close together
--   order     pick up before doing before turning in, a chain's earlier quest before its next;
--             nearest next from where the player stands, then improved by swaps (2-opt) while the
--             order holds
--   done      by state, never by step number: in the log, objectives full, the game counts the quest
--             completed; a step done out of order is skipped past, and one done already never shows
--   data      the quest log, and the game's quest map markers; with QuestieDB (its public API, at
--             runtime only), where givers, turn-ins, mobs and objects are, and the zone's quests to
--             pick up. Without it, the route has the log's quests the game can place on this map.
--
-- Advice only: Go sets the game's map pin on the player's click; nothing is accepted, turned in or
-- clicked for them. Written for Spellmind; nothing taken from other guide addons.

local _, ns = ...
local RT = {}
ns.Route = RT
local R = ns.R

RT.GROUP_YARDS = 90 -- stops this close are one stop
RT.SPOTS_MAX = 80 -- an objective's spawn points read, at most
RT.CLUSTER = 7 -- map percent: the radius of an objective's densest spot
RT.BELOW, RT.ABOVE = 5, 2 -- quests this far below (grey) or above (past yellow) the character's level aren't done on the route
-- A quest is done on the route up to +2, yellow, taken or not (the player, 2026-11-19: +4 is a lot solo;
-- the AI's review: a +3 quest at the top of the route is better left until closer to its level); in a
-- group, two levels more. Orange ones (+3, +4) are still a pick up "for later" when its giver is by
-- another stop (the player: "I should have at least picked up the quest"): taken, they wait in the log
-- until the level (or a group) comes.
RT.LOG_ABOVE, RT.GROUP_ABOVE = 2, 2
RT.LATER_ABOVE = 2 -- this many levels past the cap (orange), a pick up is still a step "for later"
RT.STOPS_MAX = 40
RT.CHAIN_PASSES = 3 -- follow-ups planned this many steps down a chain
RT.DETOUR_MIN_RATE = 0.05 -- a detour's value a minute, at least, when no other zone is counted

RT.PASSES = 8 -- improvement passes over the order
RT.REBUILD_DELAY = 1.5 -- seconds: game events coalesce into one rebuild
RT.NEXT_SHOWN = 3

local function Try(fn, ...) return ns.Try(fn, ...) end
local function DG() return ns.Dungeons end
local function L() return ns.Dungeons and ns.Dungeons.DB and ns.Dungeons.DB() end
local function Level() return tonumber((Try(UnitLevel, "player"))) or 1 end
local function InCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false end
local function InGroup()
	local f = rawget(_G, "IsInGroup")
	if type(f) == "function" then return Try(f) and true or false end
	return (tonumber((Try(rawget(_G, "GetNumPartyMembers")))) or 0) > 0
end
-- The most levels above the character a quest may be: one in the log (inLog) or one to pick up.
function RT.Above(inLog) return (inLog and RT.LOG_ABOVE or RT.ABOVE) + (InGroup() and RT.GROUP_ABOVE or 0) end

-- The quests each quest opens (its follow-ups): QuestieDB's prerequisites turned around, once a
-- session (one pass over the quests the index has).
function RT.FollowUps(id)
	if not R.routeFollow then
		local Q = L()
		local index = Q and DG().Index()
		if not index then return {} end
		local rev = {}
		local function Add(p, q) if type(p) == "number" then rev[p] = rev[p] or {}; table.insert(rev[p], q) end end
		for _, ids in pairs(index) do
			for _, q in ipairs(ids) do
				local single, group = Try(Q.Quest.preQuestSingle, q), Try(Q.Quest.preQuestGroup, q)
				for _, p in ipairs(type(single) == "table" and single or {}) do Add(p, q) end
				for _, p in ipairs(type(group) == "table" and group or {}) do Add(p, q) end
			end
		end
		R.routeFollow = rev
	end
	return R.routeFollow[id] or {}
end

-- The rate a detour has to reach: the best other zone's (Where next), else RT.DETOUR_MIN_RATE.
function RT.DetourBar()
	local best = RT.DETOUR_MIN_RATE
	for _, z in ipairs(RT.Zones and RT.Zones() or {}) do
		if not z.here and z.rate and z.rate > best then best = z.rate end
	end
	return best
end

---------------------------------------------------------------------------
-- Where the player is
---------------------------------------------------------------------------

-- { map, zone, area, x, y (0-100), w, h (yards) }, or nil (no position: an instance, a loading screen).
function RT.Here()
	local M = rawget(_G, "C_Map")
	if type(M) ~= "table" then return nil end
	local map = Try(M.GetBestMapForUnit, "player")
	if type(map) ~= "number" then return nil end
	-- A town or a building's own map: its zone's, so the route is the zone's.
	local info = Try(M.GetMapInfo, map)
	local depth = 0
	while type(info) == "table" and tonumber(info.mapType) and info.mapType > 3 and info.parentMapID and depth < 4 do
		map, info, depth = info.parentMapID, Try(M.GetMapInfo, info.parentMapID), depth + 1
	end
	local pos = Try(M.GetPlayerMapPosition, map, "player")
	local x, y
	if type(pos) == "table" then
		if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	end
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	local w, h = Try(M.GetMapWorldSize, map)
	local zone = type(info) == "table" and info.name or nil
	return { map = map, zone = zone, area = zone and DG() and DG().AreaOf(zone) or nil, x = x * 100, y = y * 100,
		w = (type(w) == "number" and w > 0) and w or 1000, h = (type(h) == "number" and h > 0) and h or 1000 }
end

-- Yards between two points (x, y 0-100 on their map). On the same map, by the map's size; a point on
-- another map (a route across zones: map = its uiMapID; none is the player's) by the world's yards,
-- and another continent is as good as out of reach.
RT.FAR = 1e6
local function PointWorld(p, map)
	if p.w == nil then p.w = (RT.World and RT.World(map, p.x, p.y)) or false end
	return p.w or nil
end
function RT.Yards(a, b, here)
	local am, bm = a.map or (here and here.map), b.map or (here and here.map)
	if am and bm and (am ~= bm or (here and here.map and am ~= here.map)) then
		local wa, wb = PointWorld(a, am), PointWorld(b, bm)
		if not wa or not wb or wa.c ~= wb.c then return RT.FAR end
		return math.sqrt((wa.x - wb.x) ^ 2 + (wa.y - wb.y) ^ 2)
	end
	local dx, dy = (a.x - b.x) * here.w / 100, (a.y - b.y) * here.h / 100
	return math.sqrt(dx * dx + dy * dy)
end
-- A stop's map: its own, or the route's (the zone the route is built in).
function RT.StopMap(s) return s and (s.map or (R.route and R.route.map)) or nil end
-- "In Ironforge: " for a stop in another zone than the route's.
function RT.StopZone(s)
	if s and s.map and R.route and s.map ~= R.route.map then return "|cffffd100In " .. ns.Escape(s.zoneName or "another zone") .. ":|r " end
	return ""
end

---------------------------------------------------------------------------
-- Where things are (QuestieDB)
---------------------------------------------------------------------------

local function AddSpawns(points, list, area)
	local t = type(list) == "table" and list[area]
	if type(t) ~= "table" then return end
	for _, c in ipairs(t) do
		local x, y = type(c) == "table" and tonumber(c[1]), type(c) == "table" and tonumber(c[2])
		if x and y and x >= 0 and y >= 0 and #points < RT.SPOTS_MAX then points[#points + 1] = { x, y } end
	end
end

-- Every spot a quest's objectives can be done in this area: its mobs, objects, the mobs and objects
-- that drop its items, its kill-credit mobs, its "go there" spot.
function RT.ObjectiveSpots(Q, id, area)
	local pts = {}
	local o = Try(Q.Quest.objectives, id)
	local N, O, I = Q.Npc, Q.Object, Q.Item
	-- An objective is a tuple { id, text, count }; anything else is skipped, never indexed.
	local function Ids(list)
		local out = {}
		for _, c in ipairs(type(list) == "table" and list or {}) do
			if type(c) == "table" and tonumber(c[1]) then out[#out + 1] = c[1] end
		end
		return out
	end
	if type(o) == "table" then
		for _, npc in ipairs(Ids(o[1])) do if N then AddSpawns(pts, Try(N.spawns, npc), area) end end
		for _, obj in ipairs(Ids(o[2])) do if O then AddSpawns(pts, Try(O.spawns, obj), area) end end
		for _, item in ipairs(Ids(o[3])) do
			if I then
				for _, npc in ipairs(type(I.npcDrops) == "function" and Try(I.npcDrops, item) or {}) do if N then AddSpawns(pts, Try(N.spawns, npc), area) end end
				for _, obj in ipairs(type(I.objectDrops) == "function" and Try(I.objectDrops, item) or {}) do if O then AddSpawns(pts, Try(O.spawns, obj), area) end end
			end
		end
		for _, c in ipairs(type(o[5]) == "table" and o[5] or {}) do
			for _, npc in ipairs(type(c) == "table" and type(c[1]) == "table" and c[1] or {}) do if N then AddSpawns(pts, Try(N.spawns, npc), area) end end
		end
	end
	local trig = type(Q.Quest.triggerEnd) == "function" and Try(Q.Quest.triggerEnd, id) or nil
	if type(trig) == "table" then AddSpawns(pts, trig[2], area) end
	return pts
end

-- Whether QuestieDB lists any objective for a quest (mobs, objects, items, kill credit, a spot to reach).
function RT.HasObjectives(Q, id)
	local o = Try(Q.Quest.objectives, id)
	if type(o) == "table" then
		for _, k in ipairs({ 1, 2, 3, 5 }) do if type(o[k]) == "table" and #o[k] > 0 then return true end end
	end
	local trig = type(Q.Quest.triggerEnd) == "function" and Try(Q.Quest.triggerEnd, id) or nil
	return type(trig) == "table"
end

RT.NO_STOCK_HOURS = 3
-- Was this vendor seen without this item lately? SpellmindDB.routeNoStock = { ["npc:item"] = time() }.
function RT.NoStock(npc, item)
	local t = ns.db and ns.db.routeNoStock
	local at = t and t[npc .. ":" .. item]
	if not at then return false end
	if time() - at > RT.NO_STOCK_HOURS * 3600 then t[npc .. ":" .. item] = nil; return false end
	return true
end

-- An item objective nothing here drops (the player, 2026-11-19: a Bronze Tube, bought or crafted):
-- who sells it, { item, name, spot } in this area, else { item, name, zone } or { item } (no vendor known).
function RT.Vendor(Q, id, area)
	local o = Try(Q.Quest.objectives, id)
	local I, N = Q.Item, Q.Npc
	if type(o) ~= "table" or type(o[3]) ~= "table" or not I or not N then return nil end
	local away, empty
	for _, c in ipairs(o[3]) do
		local itemID = type(c) == "table" and tonumber(c[1]) or nil
		local item = itemID and Try(I.name, itemID) or nil
		for _, npc in ipairs(itemID and type(I.vendors) == "function" and Try(I.vendors, itemID) or {}) do
			local name = Try(N.name, npc)
			-- Seen this session without it (limited stock sells out: the player, 2026-11-19).
			if RT.NoStock(npc, itemID) then
				empty = empty or name
			else
				local sp = Try(N.spawns, npc)
				local at = type(sp) == "table" and type(sp[area]) == "table" and sp[area][1]
				if at and tonumber(at[1]) and tonumber(at[2]) then
					return { item = item, itemID = itemID, npc = npc, name = name, spot = { x = at[1], y = at[2] } }
				end
				away = away or { item = item, itemID = itemID, npc = npc, name = name, zone = Try(N.zoneID, npc) }
			end
		end
		if not away and type(item) == "string" then away = { item = item, itemID = itemID, empty = empty } end
	end
	return away
end

-- The middle of the densest group of points (where most of a quest's mobs are), or nil.
function RT.Center(pts, radius)
	radius = radius or RT.CLUSTER
	local r2, best, most = radius * radius, nil, -1
	for _, p in ipairs(pts) do
		local n = 0
		for _, q in ipairs(pts) do if (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 <= r2 then n = n + 1 end end
		if n > most then best, most = p, n end
	end
	if not best then return nil end
	local sx, sy, c = 0, 0, 0
	for _, q in ipairs(pts) do
		if (best[1] - q[1]) ^ 2 + (best[2] - q[2]) ^ 2 <= r2 then sx, sy, c = sx + q[1], sy + q[2], c + 1 end
	end
	return { x = sx / c, y = sy / c }
end

-- An objective's area for the world map: the densest group's middle and its reach each way (map
-- percent), at least RT.AREA_MIN, with RT.AREA_PAD around the outer spawns.
RT.AREA_MIN, RT.AREA_PAD = 2.5, 1.5
function RT.Area(pts, radius)
	local c = RT.Center(pts, radius)
	if not c then return nil end
	radius = radius or RT.CLUSTER
	local r2, rx, ry = radius * radius, 0, 0
	for _, q in ipairs(pts) do
		if (q[1] - c.x) ^ 2 + (q[2] - c.y) ^ 2 <= r2 then
			rx, ry = math.max(rx, math.abs(q[1] - c.x)), math.max(ry, math.abs(q[2] - c.y))
		end
	end
	c.rx, c.ry = math.max(RT.AREA_MIN, rx + RT.AREA_PAD), math.max(RT.AREA_MIN, ry + RT.AREA_PAD)
	return c
end
local function AreaOf(c) return c and c.rx and { ax = c.x, ay = c.y, rx = c.rx, ry = c.ry } or nil end

-- Who takes a quest back: { name, spot = { x, y } in this area } or { name, zone = areaID } elsewhere.
function RT.TurnIn(Q, id, area)
	local by = Try(Q.Quest.finishedBy, id)
	if type(by) ~= "table" then return nil end
	local function From(kind, list)
		local T = Q[kind]
		for _, who in ipairs(type(list) == "table" and list or {}) do
			local name = T and Try(T.name, who)
			if type(name) == "string" and name ~= "" then
				local sp = T and Try(T.spawns, who)
				local here = type(sp) == "table" and type(sp[area]) == "table" and sp[area][1]
				if here and tonumber(here[1]) and tonumber(here[2]) then return { name = name, spot = { x = here[1], y = here[2] } } end
				return { name = name, zone = T and Try(T.zoneID, who) }
			end
		end
	end
	return From("Npc", by[1]) or From("Object", by[2])
end

---------------------------------------------------------------------------
-- The order
---------------------------------------------------------------------------

local RANK = { pickup = 1, ["do"] = 2, turnin = 3, enter = 5 }
RT.RANK = RANK

-- The order rules as pairs { before, after } of goal keys ("pickup:123"): a quest's pick up, do and
-- turn in in that order, and a chain's turn in before the next quest's pick up.
function RT.Rules(stops, chains)
	local have = {}
	for _, s in ipairs(stops) do for _, g in ipairs(s.goals) do have[g.kind .. ":" .. g.q] = true end end
	local rules = {}
	local function Rule(a, b) if have[a] and have[b] then rules[#rules + 1] = { a, b } end end
	for key in pairs(have) do
		local kind, q = key:match("^(%a+):(%d+)$")
		if kind == "pickup" then Rule(key, "do:" .. q); Rule(key, "turnin:" .. q) end
		if kind == "do" then Rule(key, "turnin:" .. q) end
	end
	for _, c in ipairs(chains or {}) do Rule("turnin:" .. c[1], "pickup:" .. c[2]) end
	return rules
end

-- Can these stops be put in an order that keeps the rules? False when a rule's two goals sit in two
-- stops that must each come before the other (the player, 2026-11-19: Calor gives and takes back
-- Worgen in the Woods, so its pick up and turn in were one stop with the kills elsewhere, and the
-- turn-in came first). stopOf: goal key -> stop.
function RT.Orderable(stops, rules, stopOf)
	local edges = {}
	for _, r in ipairs(rules) do
		local a, b = stopOf[r[1]], stopOf[r[2]]
		if a and b and a ~= b then
			edges[a] = edges[a] or {}
			edges[a][b] = true
		end
	end
	local state = {}
	local function Visit(n)
		if state[n] == 1 then return false end -- on the path: a cycle
		if state[n] == 2 then return true end
		state[n] = 1
		for m in pairs(edges[n] or {}) do if not Visit(m) then return false end end
		state[n] = 2
		return true
	end
	for _, st in ipairs(stops) do if not Visit(st) then return false end end
	return true
end

-- Does an order of stops keep every rule? (A goal and the one it must follow may share a stop.)
function RT.Keeps(order, rules)
	local at = {}
	for i, s in ipairs(order) do for _, g in ipairs(s.goals) do at[g.kind .. ":" .. g.q] = i end end
	for _, r in ipairs(rules) do
		local a, b = at[r[1]], at[r[2]]
		if a and b and a > b then return false end
	end
	return true
end

-- The length of a path from start through the stops, in yards.
function RT.Length(order, start, here, cost)
	cost = cost or RT.Yards
	local total, at = 0, start
	for _, s in ipairs(order) do total = total + cost(at, s, here); at = s end
	return total
end

-- The stops in an efficient order that keeps the rules: nearest next (of the stops whose earlier
-- goals are done or behind), then 2-opt passes, each kept only when it's shorter and keeps the rules.
function RT.Order(stops, start, here, rules, cost)
	cost = cost or RT.Yards
	local left, order = {}, {}
	for _, s in ipairs(stops) do left[#left + 1] = s end
	local placed = {}
	local function Ready(s)
		for _, r in ipairs(rules) do
			for _, g in ipairs(s.goals) do
				if r[2] == g.kind .. ":" .. g.q and not placed[r[1]] then
					-- the earlier goal may be in this same stop
					local mine = false
					for _, h in ipairs(s.goals) do if h.kind .. ":" .. h.q == r[1] then mine = true end end
					if not mine then return false end
				end
			end
		end
		return true
	end
	local at = start
	while #left > 0 do
		local best, bestD
		for i, s in ipairs(left) do
			if Ready(s) then
				local d = cost(at, s, here)
				if not bestD or d < bestD then best, bestD = i, d end
			end
		end
		if not best then -- nothing ready (a rule the data gets wrong): the nearest, so nothing is lost
			for i, s in ipairs(left) do
				local d = cost(at, s, here)
				if not bestD or d < bestD then best, bestD = i, d end
			end
		end
		local s = table.remove(left, best)
		order[#order + 1] = s
		for _, g in ipairs(s.goals) do placed[g.kind .. ":" .. g.q] = true end
		at = s
	end
	-- 2-opt: reverse a stretch when that's shorter and still keeps the rules.
	local n = #order
	for _ = 1, RT.PASSES do
		local better = false
		local len = RT.Length(order, start, here, cost)
		for i = 1, n - 1 do
			for j = i + 1, n do
				local try = {}
				for k = 1, i - 1 do try[#try + 1] = order[k] end
				for k = j, i, -1 do try[#try + 1] = order[k] end
				for k = j + 1, n do try[#try + 1] = order[k] end
				local l2 = RT.Length(try, start, here, cost)
				if l2 < len - 0.5 and RT.Keeps(try, rules) then order, len, better = try, l2, true end
			end
		end
		if not better then break end
	end
	return order
end

---------------------------------------------------------------------------
-- The goals, and whether they're done
---------------------------------------------------------------------------

local function Done(id) return DG() and DG().Done(id) or false end
-- In the log now: its log index (the game's, live), else the game's own check.
local function Have(id)
	local QL = C_QuestLog
	if type(QL) ~= "table" then return false end
	if type(QL.GetLogIndexForQuestID) == "function" then
		local i = Try(QL.GetLogIndexForQuestID, id)
		if type(i) == "number" and i > 0 then return true end
	end
	return type(QL.IsOnQuest) == "function" and Try(QL.IsOnQuest, id) and true or false
end
local function Complete(id)
	local QL = C_QuestLog
	local c = QL and Try(QL.IsComplete, id)
	if c == nil and QL then c = Try(QL.ReadyForTurnIn, id) end
	return c and true or false
end

-- A goal is done by the game's state, whatever order things happened in.
function RT.GoalDone(g)
	if g.kind == "enter" then return RT.Entered(g.title) end
	if g.kind == "pickup" then return Have(g.q) or Done(g.q) end
	if g.kind == "do" then return Done(g.q) or (Have(g.q) and Complete(g.q)) end
	return Done(g.q)
end

function RT.StopDone(s)
	for _, g in ipairs(s.goals) do if not RT.GoalDone(g) then return false end end
	return true
end

-- The quest log: { [id] = { id, title, level } }, read as State does (headers, hidden rows and
-- tasks aren't quests).
local function ReadLog()
	local QL = C_QuestLog
	local out = {}
	if type(QL) ~= "table" then return out end
	for i = 1, tonumber((Try(QL.GetNumQuestLogEntries))) or 0 do
		local info = Try(QL.GetInfo, i)
		if type(info) == "table" and not info.isHeader and not info.isHidden and not info.isTask and type(info.questID) == "number" and info.questID > 0 then
			out[info.questID] = { id = info.questID, title = info.title, level = tonumber(info.level) }
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Building the route
---------------------------------------------------------------------------

-- R.route = { zone, map, area, stops = { { x, y, goals = { { kind, q, title, to } } } }, elsewhere =
-- { [zone name] = { goals } }, later = { titles }, db = true when QuestieDB placed things }.
-- What the route plans for (the player, 2026-11-19): the quests where you stand ("questing", the
-- default), or everything to get ready for one dungeon ("dungeon": UI().dungeon, its name).
local function ModeUI()
	ns.db.routeUI = type(ns.db.routeUI) == "table" and ns.db.routeUI or {}
	return ns.db.routeUI
end
-- The zone the player chose (Aim), kept through /reload and logins (the player, 2026-11-19: a /reload
-- forgot Wetlands), per character: SpellmindDB.routeUI.aims[ns.State.Key()] = { area, from }, the key a
-- hash of the character's GUID, never its name.
local function Aims()
	local ui = ModeUI()
	ui.aims = type(ui.aims) == "table" and ui.aims or {}
	return ui.aims
end
local function AimKey() return ns.State and ns.State.Key and ns.State.Key() or nil end
function RT.SetAim(area, from)
	R.routeAim, R.routeAimFrom = area, area and from or nil
	local key = AimKey()
	if key then Aims()[key] = area and { area = area, from = from } or nil end
end
-- Once a session: the saved choice back.
function RT.LoadAim()
	if R.routeAimLoaded then return end
	R.routeAimLoaded = true
	local key = AimKey()
	local a = key and Aims()[key]
	if type(a) == "table" and tonumber(a.area) then R.routeAim, R.routeAimFrom = tonumber(a.area), tonumber(a.from) end
end

function RT.Mode() local ui = ModeUI(); return ui.mode == "dungeon" and ui.dungeon and "dungeon" or "questing", ui.dungeon end
function RT.SetMode(mode, name)
	local ui = ModeUI()
	if mode == "dungeon" and name then ui.mode, ui.dungeon = "dungeon", name else ui.mode, ui.dungeon = nil, nil end
	R.routeSkip, R.routeSkipped = {}, {}
	RT.SetAim(nil)
	RT.Build()
	RT.Refresh()
end

function RT.Build()
	if RT.Mode() == "dungeon" then return RT.BuildPrep(select(2, RT.Mode())) end
	local here = RT.Here()
	local route = { stops = {}, elsewhere = {}, later = {}, built = GetTime() }
	R.route = route
	if not here then route.nowhere = true; return route end
	route.zone, route.map, route.area = here.zone, here.map, here.area
	-- Arrived in the zone the player chose: the choice is done, the route plans its quests.
	RT.LoadAim()
	if R.routeAim and R.routeAim == here.area then RT.SetAim(nil) end
	local Q = L()
	route.db = Q ~= nil
	local level = Level()
	local log = ReadLog()
	R.routeLog = {}
	for id in pairs(log) do R.routeLog[id] = true end
	local raw = {}
	local chains = {}
	-- extra: { buy = item name, from = vendor } for an item to buy.
	local function Goal(kind, id, title, to, extra)
		local g = { kind = kind, q = id, title = title, to = to }
		for k, v in pairs(extra or {}) do g[k] = v end
		return g
	end
	-- The quests turned in on this route (a follow-up of one can be planned: picked up after it).
	local turnsHere = {}
	local function Place(kind, id, title, spot, to, extra)
		raw[#raw + 1] = { x = spot.x, y = spot.y, map = spot.map, zoneName = spot.zoneName, goals = { Goal(kind, id, title, to, extra) } }
		if kind == "turnin" then turnsHere[id] = true end
	end
	-- after[id] = { the quests on this route it opens after }: a follow-up, planned. planned: the
	-- quests a detour already placed.
	local after, planned = {}, {}
	-- What's left in another zone, by its name; "" for what Spellmind can't place at all.
	local function Elsewhere(zoneName, kind, id, title, to, extra)
		local key = zoneName or ""
		route.elsewhere[key] = route.elsewhere[key] or {}
		table.insert(route.elsewhere[key], Goal(kind, id, title, to, extra))
	end
	local function AreaName(area)
		local M = rawget(_G, "C_Map")
		local n = area and M and type(M.GetAreaInfo) == "function" and Try(M.GetAreaInfo, area) or nil
		return type(n) == "string" and n ~= "" and n or nil
	end
	-- The game's own spot for a quest in the log on this map (its map marker), as a fallback.
	local function GameSpot(id)
		for _, q in ipairs(Try(C_QuestLog.GetQuestsOnMap, here.map) or {}) do
			if type(q) == "table" and q.questID == id and type(q.x) == "number" and type(q.y) == "number" then
				return { x = q.x * 100, y = q.y * 100 }
			end
		end
	end
	-- A detour (the player, 2026-11-19): a quest of this zone handed in somewhere else, whose follow-ups
	-- are done here again, goes there and back when the turn-in and what it opens pay for the trip as
	-- well as the best other zone would. Otherwise it waits under Elsewhere.
	local function Detour(id, title, fin)
		if not Q or not here.area or type(fin) ~= "table" or not fin.zone or fin.zone == here.area then return false end
		local follow = RT.FollowUps(id)
		if #follow == 0 then return false end
		local finAt = RT.TurnIn(Q, id, fin.zone)
		local finMap = DG().MapForArea(fin.zone)
		if not finAt or not finAt.spot or not finMap then return false end
		local ctx = DG().Context(Q)
		local function Has(x) return log[x] ~= nil end
		local cands = {}
		for _, f in ipairs(follow) do
			if not log[f] and not Done(f) and not RT.Hidden(f) and not RT.NotOffered(f) and DG().Fits(Q, f, ctx, Has) then
				local req = tonumber((Try(Q.Quest.requiredLevel, f))) or 1
				local ql = tonumber((Try(Q.Quest.questLevel, f))) or req
				if req <= level and ql >= level - RT.BELOW and ql <= level + RT.Above() then
					local center = RT.Area(RT.ObjectiveSpots(Q, f, here.area))
					local _, _, gspot = DG().Giver(Q, f)
					if center and gspot then
						cands[#cands + 1] = { id = f, title = DG().Name(Q, f) or ("quest " .. f), level = ql, center = center, giver = gspot, fin = RT.TurnIn(Q, f, here.area) }
					end
				end
			end
		end
		if #cands == 0 then return false end
		-- Worth the way there and back?
		local me = RT.PlayerWorld()
		local there = RT.World(finMap, finAt.spot.x, finAt.spot.y)
		local way = me and there and RT.Travel(me, there, RT.Speed())
		if not way then return false end
		local value = 1 + #cands
		if value / (2 * way.minutes + value * RT.QUEST_MINUTES) < RT.DetourBar() then return false end
		local zname = AreaName(fin.zone)
		Place("turnin", id, title, { x = finAt.spot.x, y = finAt.spot.y, map = finMap, zoneName = zname }, fin.name)
		for _, c in ipairs(cands) do
			local gMap = c.giver.zone ~= here.area and DG().MapForArea(c.giver.zone) or nil
			if c.giver.zone == here.area or gMap then
				planned[c.id] = true
				Place("pickup", c.id, c.title, { x = c.giver.x, y = c.giver.y, map = gMap, zoneName = gMap and AreaName(c.giver.zone) or nil },
					c.giver.name, { fromID = c.giver.npc, level = c.level })
				Place("do", c.id, c.title, c.center, nil, AreaOf(c.center))
				if c.fin and c.fin.spot then Place("turnin", c.id, c.title, c.fin.spot, c.fin.name) end
				chains[#chains + 1] = { id, c.id }
				after[c.id] = { id }
			end
		end
		route.detours = (route.detours or 0) + 1
		return true
	end

	-- The log's quests: what's left of each, here or elsewhere.
	for id, q in pairs(log) do
		local title = q.title or ("quest " .. id)
		local qlevel = (Q and tonumber((Try(Q.Quest.questLevel, id)))) or q.level or level
		-- Above the level: for later, unless it's done and only the turn-in is left (free XP at any level).
		if qlevel > level + RT.Above(true) and not Complete(id) then
			route.later[#route.later + 1] = title
		else
			local complete = Complete(id)
			local fin = Q and here.area and RT.TurnIn(Q, id, here.area) or nil
			local doHere = false
			if not complete then
				local center = Q and here.area and RT.Area(RT.ObjectiveSpots(Q, id, here.area)) or nil
				center = center or GameSpot(id)
				if center then
					Place("do", id, title, center, nil, AreaOf(center)); doHere = true
				else
					-- An item nothing here drops: bought here, or got elsewhere.
					local v = Q and here.area and RT.Vendor(Q, id, here.area) or nil
					if v and v.spot then
						Place("do", id, title, v.spot, nil, { buy = v.item, buyID = v.itemID, from = v.name, fromID = v.npc, empty = v.empty }); doHere = true
					else
						Elsewhere(v and AreaName(v.zone), "do", id, title, nil, v and { buy = v.item, buyID = v.itemID, from = v.name, fromID = v.npc, empty = v.empty })
					end
				end
			end
			-- Its turn-in: on the route once the quest is complete, or once its objectives are on it too
			-- (the player, 2026-11-19: a turn-in came up as the step before the item it needed).
			if complete or doHere then
				if fin and fin.spot then Place("turnin", id, title, fin.spot, fin.name)
				elseif complete then
					local spot = GameSpot(id)
					if spot then Place("turnin", id, title, spot, fin and fin.name)
					elseif not Detour(id, title, fin) then Elsewhere(fin and AreaName(fin.zone), "turnin", id, title, fin and fin.name) end
				elseif fin and not Detour(id, title, fin) then Elsewhere(AreaName(fin.zone), "turnin", id, title, fin.name) end
			end
		end
	end
	-- This zone's quests to pick up (QuestieDB): for this character, open now, at its level, given here,
	-- with their objectives here too (or none), so a pick up never sends the player away.
	local index = Q and here.area and DG().Index(function() RT.Dirty() end)
	R.routeAskedNow = 0
	if index and index[here.area] then
		local ctx = DG().Context(Q)
		local function Has(id) return log[id] ~= nil end
		local taken, forLater = {}, {}
		-- Open now, or once the quests it needs are turned in on this route.
		local function Opens(id)
			local miss = DG().Missing(id)
			if #miss == 0 then return true end
			for _, p in ipairs(miss) do if not turnsHere[p] then return false end end
			return true, miss
		end
		for pass = 1, RT.CHAIN_PASSES do
		local added = false
		for _, id in ipairs(index[here.area]) do
			local open, needs = false, nil
			if not taken[id] and not planned[id] and not log[id] and not Done(id) then open, needs = Opens(id) end
			if open and not RT.Hidden(id) and not RT.NotOffered(id) and DG().Fits(Q, id, ctx, Has) and RT.Known(id) then
				local req = tonumber((Try(Q.Quest.requiredLevel, id))) or 1
				local ql = tonumber((Try(Q.Quest.questLevel, id))) or req
				local later = ql > level + RT.Above()
				if req <= level and ql >= level - RT.BELOW and ql <= level + RT.Above() + RT.LATER_ABOVE then
					local _, friendly, spot = DG().Giver(Q, id)
					local mine = not friendly or not ctx.faction or tostring(friendly):find(ctx.faction == "Alliance" and "A" or "H", 1, true)
					if later and mine and spot and spot.zone == here.area then
						taken[id] = true
						forLater[#forLater + 1] = { id = id, title = DG().Name(Q, id) or ("quest " .. id), spot = spot, needs = needs, level = ql }
					elseif mine and spot and spot.zone == here.area then
						local title = DG().Name(Q, id) or ("quest " .. id)
						local center = RT.Area(RT.ObjectiveSpots(Q, id, here.area))
						local fin = RT.TurnIn(Q, id, here.area)
						-- Its objectives have to be doable here (mobs, objects, a vendor), or it has none.
						local hasObjectives = RT.HasObjectives(Q, id)
						local v = hasObjectives and not center and RT.Vendor(Q, id, here.area) or nil
						local doable = center or (v and v.spot) or nil
						if (hasObjectives and doable) or (not hasObjectives and fin and fin.spot) then
							taken[id], added = true, true
							Place("pickup", id, title, spot, spot.name, { fromID = spot.npc, level = ql })
							if center then Place("do", id, title, center, nil, AreaOf(center))
							elseif v and v.spot then Place("do", id, title, v.spot, nil, { buy = v.item, buyID = v.itemID, from = v.name, fromID = v.npc, empty = v.empty }) end
							if fin and fin.spot then Place("turnin", id, title, fin.spot, fin.name) end
							local pre = Try(Q.Quest.preQuestSingle, id)
							if type(pre) == "table" and pre[1] then chains[#chains + 1] = { pre[1], id } end
							for _, p in ipairs(needs or {}) do
								chains[#chains + 1] = { p, id }
								after[id] = after[id] or {}
								table.insert(after[id], p)
							end
						end
					end
				end
			end
		end
		if not added then break end
		end
		-- For later: only where the route already goes, or where the player stands (the player, 2026-11-19:
		-- at Calor, the rest of the route at Sven's camp); no detour for a quest not done now.
		for _, p in ipairs(forLater) do
			local near = RT.Yards({ x = here.x, y = here.y }, p.spot, here) <= RT.GROUP_YARDS
			for _, r in ipairs(raw) do
				if RT.Yards(r, p.spot, here) <= RT.GROUP_YARDS then near = true; break end
			end
			if near then
				Place("pickup", p.id, p.title, p.spot, p.spot.name, { fromID = p.spot.npc, later = true, level = p.level })
				for _, q in ipairs(p.needs or {}) do
					chains[#chains + 1] = { q, p.id }
					after[p.id] = after[p.id] or {}
					table.insert(after[p.id], q)
				end
			end
		end
	end
	route.after = after
	-- Goals already done never show (a quest completed since the log was read, a pick up taken).
	local keep = {}
	for _, s in ipairs(raw) do if not RT.StopDone(s) then keep[#keep + 1] = s end end
	-- Close ones are one stop, unless that leaves no order that keeps the rules (a quest's pick up and
	-- turn in at one giver, its objectives elsewhere: two visits, not one).
	local rules = RT.Rules(keep, chains)
	local stops, stopOf = {}, {}
	for _, s in ipairs(keep) do
		local joined
		for _, t in ipairs(stops) do
			if RT.Yards(s, t, here) <= RT.GROUP_YARDS then
				for _, g in ipairs(s.goals) do stopOf[g.kind .. ":" .. g.q] = t end
				if RT.Orderable(stops, rules, stopOf) then joined = t; break end
			end
		end
		if joined then
			for _, g in ipairs(s.goals) do joined.goals[#joined.goals + 1] = g end
		else
			stops[#stops + 1] = s
			for _, g in ipairs(s.goals) do stopOf[g.kind .. ":" .. g.q] = s end
		end
	end
	-- In a stop: turn-ins first (one may open the next quest), then pick ups, then objectives; a quest
	-- picked up and finished in the same stop keeps its own order.
	local function Base(g, st)
		if g.kind == "turnin" then
			for _, h in ipairs(st.goals) do if h.q == g.q and h.kind ~= "turnin" then return 4 end end
			return 0
		end
		return RANK[g.kind]
	end
	-- How far down a chain a quest is in this stop: 0, or 1 + its opener's when that's turned in here.
	local function Depth(q, st, n)
		n = n or 0
		if n > RT.CHAIN_PASSES then return n end
		for _, p in ipairs(after[q] or {}) do
			for _, h in ipairs(st.goals) do
				if h.kind == "turnin" and h.q == p then return 1 + Depth(p, st, n + 1) end
			end
		end
		return 0
	end
	local function Rank(g, st) return Depth(g.q, st) * 10 + Base(g, st) end
	for _, s in ipairs(stops) do
		table.sort(s.goals, function(a, b) return Rank(a, s) < Rank(b, s) end)
		-- A stop's key: its goals, so a skip outlives a rebuild that keeps the stop.
		local keys = {}
		for _, g in ipairs(s.goals) do keys[#keys + 1] = g.kind .. ":" .. g.q end
		s.key = table.concat(keys, ",")
	end
	while #stops > RT.STOPS_MAX do table.remove(stops) end
	rules = RT.Rules(stops, chains)
	local start = { x = here.x, y = here.y }
	route.stops = RT.Order(stops, start, here, rules)
	-- XP for the walk (the player, 2026-11-19): a quest far below the route's XP a minute that costs a
	-- real detour is marked "worth skipping?", and its stops come later (the order again, those stops'
	-- way dearer), so the ones worth more come first. Nothing is dropped: Skip is the player's.
	route.xp, route.low = RT.Worth(route.stops, start, here, level)
	if next(route.low) then
		local function Cost(a, b, h)
			local d = RT.Yards(a, b, h)
			if b.goals and RT.StopLow(b, route.low) then d = d * RT.LOW_LATER end
			return d
		end
		route.stops = RT.Order(stops, start, here, rules, Cost)
	end
	route.rules = rules
	-- What the order was made from, for /sm route why.
	route.start, route.here, route.cost = start, here, route.low and next(route.low) and function(a, b, h)
		local d = RT.Yards(a, b, h)
		if b.goals and RT.StopLow(b, route.low) then d = d * RT.LOW_LATER end
		return d
	end or nil
	if Q then route.where = RT.Zones(true) end
	return route
end

-- A quest's XP: the quest log's reward when it's there, else an estimate by its level, reduced as the
-- game reduces quests far below the character (by 20% a level past five, down to a tenth).
RT.XP_BASE, RT.XP_PER_LEVEL = 100, 70
function RT.QuestXP(id, level, qlevel)
	local xp = tonumber((Try(rawget(_G, "GetQuestLogRewardXP"), id)))
	if xp and xp > 0 then return xp, true end
	local ql = tonumber(qlevel) or level
	local diff = level - ql
	local share = diff <= 5 and 1 or math.max(0.1, 1 - 0.2 * (diff - 5))
	return math.floor((RT.XP_BASE + RT.XP_PER_LEVEL * ql) * share), false
end

RT.LOW_SHARE = 0.35 -- a quest under this share of the route's XP a minute ...
RT.LOW_MINUTES = 2 -- ... and adding at least this many minutes of walking, is worth skipping?
RT.LOW_LATER = 1.5 -- its stops' way this much dearer in the order: later
-- Each quest's XP, and the ones worth skipping: { [q] = xp }, { [q] = true }. Its extra walking: the
-- way through its own stops (those with only its goals) less the way straight past them.
function RT.Worth(stops, start, here, level)
	local Q = L()
	local xp, own, mins = {}, {}, {}
	local speed = RT.Speed()
	for k, st in ipairs(stops) do
		local qs = {}
		for _, g in ipairs(st.goals) do qs[g.q] = true end
		local only
		for q in pairs(qs) do only = (only == nil) and q or false end
		if only then
			local prev, nxt = stops[k - 1] or start, stops[k + 1]
			local extra = RT.Yards(prev, st, here) + (nxt and RT.Yards(st, nxt, here) or 0) - (nxt and RT.Yards(prev, nxt, here) or 0)
			own[only] = (own[only] or 0) + math.max(0, extra)
		end
		for q in pairs(qs) do
			if not xp[q] and q ~= 0 then
				local ql = Q and tonumber((Try(Q.Quest.questLevel, q))) or nil
				xp[q] = RT.QuestXP(q, level, ql)
			end
		end
	end
	local totalXP, totalMin = 0, 0
	for q, x in pairs(xp) do
		mins[q] = (own[q] or 0) * RT.PATH_FACTOR / speed / 60 + RT.QUEST_MINUTES
		totalXP, totalMin = totalXP + x, totalMin + mins[q]
	end
	local avg = totalMin > 0 and totalXP / totalMin or 0
	local low = {}
	for q, x in pairs(xp) do
		local walk = mins[q] - RT.QUEST_MINUTES
		if avg > 0 and x / mins[q] < avg * RT.LOW_SHARE and walk >= RT.LOW_MINUTES then low[q] = true end
	end
	return xp, low
end
-- "1,150 XP": what a stop's turn-ins give (the Route tab).
function RT.StopXP(st)
	local xp = R.route and R.route.xp or {}
	local n = 0
	for _, g in ipairs(st.goals or {}) do if g.kind == "turnin" and xp[g.q] then n = n + xp[g.q] end end
	if n <= 0 then return nil end
	local txt = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return "|cffb48cff" .. txt .. " XP|r"
end
-- A stop whose every quest is worth skipping.
function RT.StopLow(st, low)
	low = low or (R.route and R.route.low) or {}
	local any = false
	for _, g in ipairs(st.goals or {}) do
		if not low[g.q] then return false end
		any = true
	end
	return any
end

---------------------------------------------------------------------------
-- Where next
---------------------------------------------------------------------------

-- The player (2026-11-19): a leveling guide sent them to Stormwind for its next stretch while Duskwood
-- still had quests for them, and the AI said stay. So the zones are ranked by what's really left for
-- this character (quests it can pick up there now, at its level, not done, and its log's quests there),
-- against the time it takes to get there and do them. Needs QuestieDB.
RT.WHERE_SHOWN = 3
RT.WHERE_MAX = 5 -- other zones kept (for the tracker and the AI)
RT.WHERE_MIN = 2 -- fewer quests than this isn't somewhere to go next
RT.QUEST_MINUTES = 5 -- a quest's time, on average: to the giver, the objectives, back
RT.RUN_SPEED, RT.MOUNT_LEVEL, RT.MOUNT_SPEED = 7, 40, 11 -- yards a second
RT.PATH_FACTOR = 1.35 -- roads and hills: the way is longer than the straight line (AzerothGPS's measure)
-- The player's own speed on foot or mounted (the game's: buffs, talents, the mount), else by level.
function RT.Speed()
	local _, run = Try(rawget(_G, "GetUnitSpeed"), "player")
	run = tonumber(run)
	if run and run > 0 then return run end
	return Level() >= RT.MOUNT_LEVEL and RT.MOUNT_SPEED or RT.RUN_SPEED
end
RT.SEA_MINUTES = 12 -- another continent: a boat or a tram, about
RT.WHERE_KEEP = 30 -- seconds a count is kept (quest events clear it sooner)

-- A spot's place in the world: { c = continent, x, y } in yards, or nil. x, y: 0-100 on the map.
function RT.World(map, x, y)
	local M = rawget(_G, "C_Map")
	if not map or type(M) ~= "table" or type(M.GetWorldPosFromMapPos) ~= "function" then return nil end
	local V = rawget(_G, "CreateVector2D")
	local v = type(V) == "function" and V(x / 100, y / 100) or { x = x / 100, y = y / 100 }
	local ok, c, pos = pcall(M.GetWorldPosFromMapPos, map, v)
	if not ok or type(c) ~= "number" or type(pos) ~= "table" then return nil end
	local px, py
	if type(pos.GetXY) == "function" then px, py = pos:GetXY() else px, py = pos.x, pos.y end
	if type(px) ~= "number" or type(py) ~= "number" then return nil end
	return { c = c, x = px, y = py }
end
local World = RT.World

-- The player's own: from where they stand on their zone's map.
function RT.PlayerWorld()
	local here = RT.Here()
	return here and World(here.map, here.x, here.y) or nil
end

-- The continent map the player is on (the flight map's own, when the game doesn't say).
function RT.ContinentMap()
	local M = rawget(_G, "C_Map")
	if type(M) ~= "table" then return nil end
	local map = Try(M.GetBestMapForUnit, "player")
	local info, depth = type(map) == "number" and Try(M.GetMapInfo, map), 0
	while type(info) == "table" and depth < 6 do
		if tonumber(info.mapType) == 2 then return map end
		map = info.parentMapID
		info, depth = map and Try(M.GetMapInfo, map), depth + 1
	end
	return nil
end

-- Getting there (the player, 2026-11-19): on foot (mounted from 40), by a flight path the character
-- knows (World.lua notes where each one is at the flight map), or by its hearthstone when it's ready
-- and where it lands is known; the quickest. Flights fly about this fast, turns and all.
-- (the measures of AzerothGPS's planner, 2026-11-19: a gryphon flies about 32 yards a second, a trip has
-- about 15 seconds of its own, the hearthstone 25 seconds; a flight once flown, its own time)
RT.FLY_SPEED = 32 -- yards a second, the straight line between the two
RT.FLY_MINUTES = 0.25 -- the flight master, take off, landing
RT.HEARTH_MINUTES = 25 / 60 -- the cast and the loading screen

-- A flight's minutes: as flown before (SpellmindDB.routeFlightTimes["A>B"], seconds), else by distance.
function RT.FlightMinutes(a, b)
	local t = ns.db and type(ns.db.routeFlightTimes) == "table" and a.name and b.name and ns.db.routeFlightTimes[a.name .. ">" .. b.name]
	if tonumber(t) then return tonumber(t) / 60 + RT.FLY_MINUTES end
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) / RT.FLY_SPEED / 60 + RT.FLY_MINUTES
end
RT.HEARTHSTONE = 6948

local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function Short(name) return (tostring(name):gsub(",.*$", "")) end

-- The flight paths known, with where they are: { { name, c, x, y } }.
function RT.Flights()
	local me = ns.State and ns.State.Me and ns.State.Me()
	local out = {}
	local known = me and type(me.flights) == "table" and me.flights or {}
	R.routeSnapTried = R.routeSnapTried or {}
	for name, w in pairs(me and type(me.flightSpots) == "table" and me.flightSpots or {}) do
		if known[name] and type(w) == "table" and w.c and w.x and w.y then
			if not w.snapped and not R.routeSnapTried[name] and ns.World and ns.World.SnapFlight then
				local s = ns.World.SnapFlight(w)
				if s then me.flightSpots[name] = s; w = s else R.routeSnapTried[name] = true end
			end
			-- Its zone's map: its flight master's (QuestieDB), else the zone its name says ("Thelsamar, Loch
			-- Modan"; the player, 2026-11-19: "Lakeshire, Redridge" found no map named "Redridge", so the
			-- path left Lakeshire's flight master out).
			local map = w.map or (type(name) == "string" and name:match(",%s*(.+)$") and RT.ZoneMap(name:match(",%s*(.+)$"))) or nil
			out[#out + 1] = { name = name, c = w.c, x = w.x, y = w.y, npc = w.npc, map = map }
		end
	end
	return out
end

-- Where the hearthstone lands, when it's in the bags, off its cooldown and its landing spot is known.
function RT.Hearth()
	local me = ns.State and ns.State.Me and ns.State.Me()
	local h = me and me.hearthSpot
	if type(h) ~= "table" or not h.c then return nil end
	if h.name ~= ns.State.Text(Try(GetBindLocation)) then return nil end -- bound somewhere else since
	if (tonumber((Try(rawget(_G, "GetItemCount"), RT.HEARTHSTONE))) or 0) < 1 then return nil end
	local C = rawget(_G, "C_Container")
	local cd = rawget(_G, "GetItemCooldown") or (type(C) == "table" and C.GetItemCooldown) or nil
	local start, dur = Try(cd, RT.HEARTHSTONE)
	start, dur = tonumber(start), tonumber(dur)
	if not start then return nil end
	local left = (dur and dur > 0) and (start + dur - GetTime()) or 0
	if left > 0 then
		-- Ready again later: Where next is worked out again then (nothing else would say so).
		if not R.routeHearthWake then
			R.routeHearthWake = true
			C_Timer.After(math.min(left + 1, 3600), function()
				R.routeHearthWake = nil
				R.routeWhere = nil
				RT.Dirty()
			end)
		end
		return nil
	end
	return h
end

-- Something that changes the way to other zones (a flight map's paths noted, the hearthstone's landing
-- spot): Where next worked out again.
function RT.TravelChanged()
	R.routeWhere = nil
	RT.Dirty()
end

-- The quickest way from one world spot to another: { minutes, how = "walk" | "fly" | "hearth",
-- via = words for it }, or nil when neither way is known (another continent, no hearth there).
function RT.Travel(from, to, speed)
	if not from or not to then return nil end
	speed = speed or RT.RUN_SPEED
	local function Walk(a, b) return a.c == b.c and Dist(a, b) * RT.PATH_FACTOR / speed / 60 or nil end
	local flights = RT.Flights()
	local function Nearest(p)
		local best, bd
		for _, n in ipairs(flights) do
			if n.c == p.c then local d = Dist(n, p); if not bd or d < bd then best, bd = n, d end end
		end
		return best
	end
	local function Fly(a, b)
		local A, B = Nearest(a), Nearest(b)
		if not A or not B or A == B or A.c ~= B.c then return nil end
		local m = Walk(a, A) + RT.FlightMinutes(A, B) + Walk(B, b)
		return m, Short(A.name) .. " to " .. Short(B.name), A, B
	end
	-- leg: where the way starts (a flight master's spot, or "hearth"); nil on foot.
	local best
	-- land: where a flight comes down (the player, 2026-11-19: "fly on to Wetlands" read as a flight to
	-- Wetlands they don't have; it lands at the known path nearest it, and goes on from there).
	local function Try2(m, how, via, leg, land) if m and (not best or m < best.minutes) then best = { minutes = m, how = how, via = via, leg = leg, land = land } end end
	Try2(Walk(from, to), "walk")
	local fm, fv, fa, fb = Fly(from, to)
	Try2(fm, "fly", fv and ("fly " .. fv), fa, fb)
	local h = RT.Hearth()
	if h then
		Try2(Walk(h, to) and (RT.HEARTH_MINUTES + Walk(h, to)), "hearth", "hearthstone to " .. h.name, "hearth")
		local hm, hv = Fly(h, to)
		Try2(hm and (RT.HEARTH_MINUTES + hm), "hearth", hv and ("hearthstone to " .. h.name .. ", fly " .. hv), "hearth")
	end
	return best
end

local function ZoneName(area)
	local M = rawget(_G, "C_Map")
	local n = area and M and type(M.GetAreaInfo) == "function" and Try(M.GetAreaInfo, area) or nil
	return type(n) == "string" and n ~= "" and n or nil
end

-- A quest's fixed facts, read once a session: its levels and (when asked) its giver.
local facts = {}
local function Facts(Q, id)
	local f = facts[id]
	if not f then
		local req = tonumber((Try(Q.Quest.requiredLevel, id))) or 1
		f = { req = req, ql = tonumber((Try(Q.Quest.questLevel, id))) or req }
		facts[id] = f
	end
	return f
end

-- R.routeWhere.list = { { area, zone, map, here, quests (to pick up), inLog, low, high, minutes (to
-- get there), spot (its quest givers, for Go), rate } }, best first; the player's own zone is in it
-- (here = true) for the AI, so "stay" can be the answer. nil without QuestieDB or a position.
function RT.Zones(fresh)
	local here = RT.Here()
	local Q = L()
	if not here or not Q or not here.area then return nil end
	local level = Level()
	local c = R.routeWhere
	if not fresh and c and c.area == here.area and c.level == level and GetTime() - c.at < RT.WHERE_KEEP then return c.list end
	local index = DG().Index(function() R.routeWhere = nil; RT.Dirty() end)
	if not index then return nil end
	local log = ReadLog()
	local ctx = DG().Context(Q)
	local function Has(id) return log[id] ~= nil end
	local faction = ctx.faction == "Alliance" and "A" or (ctx.faction == "Horde" and "H") or nil
	local known = ns.db.routeKnown or {}
	local zones = {}
	local function Zone(area)
		local z = zones[area]
		if not z then z = { area = area, quests = 0, inLog = 0, value = 0, givers = {} }; zones[area] = z end
		return z
	end
	-- To pick up: the same rules as the route's own pick ups.
	for area, ids in pairs(index) do
		for _, id in ipairs(ids) do
			local f = Facts(Q, id)
			if not log[id] and f.req <= level and f.ql >= level - RT.BELOW and f.ql <= level + RT.Above()
				and not Done(id) and known[id] ~= false and not RT.Hidden(id) and not RT.NotOffered(id)
				and DG().Fits(Q, id, ctx, Has) and #DG().Missing(id) == 0 then
				if f.giver == nil then
					local _, friendly, spot = DG().Giver(Q, id)
					f.giver, f.friendly = spot or false, friendly
				end
				local mine = not f.friendly or not faction or tostring(f.friendly):find(faction, 1, true)
				if f.giver and mine and f.giver.zone == area then
					local z = Zone(area)
					z.quests = z.quests + 1
					-- A quest a few levels below gives less.
					z.value = z.value + (f.ql >= level - 2 and 1 or 0.6)
					z.low, z.high = math.min(z.low or f.ql, f.ql), math.max(z.high or f.ql, f.ql)
					z.givers[#z.givers + 1] = { f.giver.x, f.giver.y, f.giver.name }
				end
			end
		end
	end
	-- In the log: where its objectives are, or where it's handed in once complete.
	for id, q in pairs(log) do
		local ql = tonumber((Try(Q.Quest.questLevel, id))) or q.level or level
		if ql <= level + RT.Above(true) or Complete(id) then
			local area
			if Complete(id) then local fin = RT.TurnIn(Q, id, -1); area = fin and tonumber(fin.zone)
			else area = tonumber((Try(Q.Quest.zoneOrSort, id))) end
			if area and area > 0 then local z = Zone(area); z.inLog = z.inLog + 1; z.value = z.value + 1 end
		end
	end
	-- The time: the quests, and the way there (on foot or mounted; flight paths not yet).
	local me = World(here.map, here.x, here.y)
	local speed = RT.Speed()
	local others, mine = {}, nil
	for area, z in pairs(zones) do
		local isHere = area == here.area
		local map = isHere and here.map or DG().MapForArea(area)
		z.zone = isHere and here.zone or ZoneName(area)
		if map and z.zone and (isHere or z.quests + z.inLog >= RT.WHERE_MIN) then
			z.map, z.here = map, isHere or nil
			-- The pin goes on a real quest giver: the one nearest the middle of the busiest group (the
			-- player, 2026-11-19: Wetlands' givers are spread out, and the middle was empty ground).
			local hub = RT.Center(z.givers, 10)
			local at
			if hub then
				local bd
				for _, g in ipairs(z.givers) do
					local d = (g[1] - hub.x) ^ 2 + (g[2] - hub.y) ^ 2
					if not bd or d < bd then at, bd = g, d end
				end
			end
			z.spot = { zone = area, x = at and at[1] or 50, y = at and at[2] or 50, giver = at and at[3] or nil, givers = at and true or nil }
			local travel = 0
			if not isHere then
				local there = World(map, z.spot.x, z.spot.y)
				local way = RT.Travel(me, there, speed)
				if way then travel, z.how, z.via, z.leg, z.land = way.minutes, way.how, way.via, way.leg, way.land
				elseif me and there then travel, z.how, z.via = RT.SEA_MINUTES, "boat", "a boat or the tram to another continent"
				else travel = nil end
			end
			z.minutes = travel and math.max(isHere and 0 or 1, math.floor(travel + 0.5)) or nil
			z.rate = z.value / ((z.quests + z.inLog) * RT.QUEST_MINUTES + (travel or RT.SEA_MINUTES))
			z.givers = nil
			if isHere then mine = z else others[#others + 1] = z end
		end
	end
	local function Better(a, b) if a.rate ~= b.rate then return a.rate > b.rate end return a.zone < b.zone end
	table.sort(others, Better)
	-- The zone the player chose stays, however it ranks (or it would drop out of the list on the way).
	while #others > RT.WHERE_MAX do
		local k = #others
		if R.routeAim and others[k].area == R.routeAim then k = k - 1 end
		table.remove(others, k)
	end
	if mine then others[#others + 1] = mine; table.sort(others, Better) end
	R.routeWhere = { at = GetTime(), area = here.area, level = level, list = others }
	return others
end

-- For the AI (the advisor part): the same ranking, best first, the player's zone marked.
function RT.ZonesPart()
	local list = RT.Zones()
	if not list or #list == 0 then return nil end
	local O = ns.State.JSON.O
	local out = {}
	for _, z in ipairs(list) do
		out[#out + 1] = O("zone", z.zone, "here", z.here, "toPickUp", z.quests, "inLog", z.inLog,
			"levels", z.low and DG().Range(z.low, z.high) or nil, "minutesAway", (not z.here) and z.minutes or nil,
			"via", (not z.here) and z.via or nil)
	end
	return out
end

-- A zone chosen from Where next: the arrow points the way there instead of at the route's steps,
-- until it's clicked again or the player arrives there (the player, 2026-11-19: flying to Wetlands
-- through Loch Modan, the choice ended at Loch Modan and the route had them questing there).
-- R.routeAim = its area ID (saved: RT.SetAim).
function RT.Aim(z)
	if type(z) ~= "table" then return end
	if R.routeAim == z.area then RT.SetAim(nil) else RT.SetAim(z.area, R.route and R.route.area) end
	RT.Refresh()
end

-- "Westfall: 3 quests to pick up, 1 in your log · about 4 min away"
function RT.WhereText(z)
	local bits = {}
	if z.quests > 0 then bits[#bits + 1] = z.quests .. (z.quests == 1 and " quest" or " quests") .. " to pick up" end
	if z.inLog > 0 then bits[#bits + 1] = z.inLog .. " in your log" end
	-- (the player, 2026-11-19: Ashenvale's "about 12 min away" didn't say it's over the sea)
	local how = z.how == "fly" and " away by flight" or (z.how == "hearth" and " away by hearthstone")
		or (z.how == "boat" and " away by boat") or " away"
	return table.concat(bits, ", ") .. (z.minutes and (" · about " .. z.minutes .. " min" .. how) or "")
end

-- The zone the arrow heads for: the one the player chose (Aim), else nil.
function RT.NextZone(route)
	if not R.routeAim then return nil end
	for _, z in ipairs(route and route.where or {}) do if z.area == R.routeAim then return z end end
	return nil
end

-- On the way to the zone the player chose (in another zone): that zone, else nil. The steps here are
-- set aside meanwhile: the arrow, the band, the map and the minimap show the way there.
function RT.Traveling(route)
	route = route or R.route
	if not R.routeAim or not route or route.nowhere or route.prep or route.area == R.routeAim then return nil end
	return RT.NextZone(route)
end

-- The other zones for the tracker: the best few, always (the player, 2026-11-19: in Loch Modan with
-- steps left, Wetlands couldn't be chosen; it showed only once few were left), the chosen one among them.
function RT.WhereLines(route)
	local out = {}
	local aimed
	for _, z in ipairs(route.where or {}) do
		if not z.here then
			if #out < RT.WHERE_SHOWN then out[#out + 1] = z
			elseif R.routeAim and z.area == R.routeAim then aimed = z end
		end
	end
	if aimed then out[#out] = aimed end
	return out
end

-- The current step: the first stop not done and not skipped, with its number.
function RT.Current()
	local route = R.route
	if not route then return nil end
	R.routeSkip = R.routeSkip or {}
	for i, s in ipairs(route.stops) do
		if not RT.StopDone(s) and not R.routeSkip[s.key] then return s, i end
	end
	return nil
end

-- Steps still to do after the current one, at most n.
function RT.UpNext(n)
	local out, seen = {}, false
	local cur = RT.Current()
	for _, s in ipairs(R.route and R.route.stops or {}) do
		if s == cur then seen = true
		elseif seen and not RT.StopDone(s) and not R.routeSkip[s.key] then
			out[#out + 1] = s
			if #out >= (n or RT.NEXT_SHOWN) then break end
		end
	end
	return out
end

-- How many of the route's stops are done (or skipped).
function RT.Progress()
	local done, total = 0, 0
	for _, s in ipairs(R.route and R.route.stops or {}) do
		total = total + 1
		if RT.StopDone(s) or (R.routeSkip and R.routeSkip[s.key]) then done = done + 1 end
	end
	return done, total
end

-- One line for a goal: "Pick up Collecting Memories", "Do Oh Brother...: 0/1 Foreman Thistlenettle's
-- Explorers' League Badge", "Turn in Wanted: Lieutenant Fangore to Magistrate Solomon".
-- A quest's level in the game's difficulty colour, "[28] " (the player, 2026-11-19: shown by a pick up).
function RT.LevelTag(level)
	level = tonumber(level)
	if not level then return "" end
	local c = Try(rawget(_G, "GetQuestDifficultyColor"), level)
	local function B(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
	local hex = type(c) == "table" and string.format("|cff%02x%02x%02x", B(c.r), B(c.g), B(c.b)) or "|cffffffff"
	return hex .. "[" .. level .. "]|r "
end
function RT.GoalText(g)
	if g.kind == "enter" then return "Enter " .. ns.Escape(g.title) .. (g.to and (" |cff888888(" .. ns.Escape(g.to) .. ")|r") or "") end
	if g.kind == "pickup" then return "Pick up " .. RT.LevelTag(g.level) .. ns.Escape(g.title) .. (g.later and " |cff888888(for later)|r" or "") end
	if g.kind == "turnin" then return "Turn in " .. ns.Escape(g.title) .. (g.to and (" to " .. ns.Escape(g.to)) or "") end
	local left = ns.Quests and ns.Quests.Left and ns.Quests.Left({ obj = ns.State and ns.State.Objectives and ns.State.Objectives(g.q) }) or nil
	if g.buy then
		if g.empty then
			return ns.Escape(g.title) .. ": " .. (left or ("get " .. ns.Escape(g.buy)))
				.. " |cff888888(" .. ns.Escape(g.empty) .. " has none right now: try the Auction House or an engineer)|r"
		end
		return ns.Escape(g.title) .. ": " .. (left or ("get " .. ns.Escape(g.buy)))
			.. (g.from and (" |cff888888(sold by " .. ns.Escape(g.from) .. ")|r") or "")
	end
	return ns.Escape(g.title) .. (left and (": " .. left) or "")
end

-- A stop's goals still to do, grouped: the pick ups from one NPC, the turn-ins to one NPC, the
-- objectives here (the player, 2026-11-19: one captain's thirteen pick ups and three turn-ins were
-- sixteen lines). { { kind, to, goals } }, in the stop's order.
function RT.Groups(st, all)
	local out, last, lastKey = {}, nil, nil
	for _, g in ipairs(st.goals) do
		if all or not RT.GoalDone(g) then
			local key = g.kind .. "|" .. (g.kind == "do" and "" or (g.to or ""))
			if key ~= lastKey then
				last = { kind = g.kind, to = g.kind ~= "do" and g.to or nil, goals = {} }
				out[#out + 1], lastKey = last, key
			end
			last.goals[#last.goals + 1] = g
		end
	end
	return out
end

-- A group's line: the goal's own for one; "Pick up 13 quests from Field Captain Palandar" for many.
function RT.GroupText(gr)
	local n = #gr.goals
	if n == 1 then return RT.GoalText(gr.goals[1]) end
	if gr.kind == "pickup" then return "Pick up " .. n .. " quests" .. (gr.to and (" from " .. ns.Escape(gr.to)) or "") end
	if gr.kind == "turnin" then return "Turn in " .. n .. " quests" .. (gr.to and (" to " .. ns.Escape(gr.to)) or "") end
	return "Objectives of " .. n .. " quests here"
end

-- The names under a many-quest line: the first few, then how many more.
function RT.GroupNames(gr, max)
	max = max or 3
	if #gr.goals < 2 then return nil end
	local names = {}
	for k, g in ipairs(gr.goals) do
		if k > max then break end
		names[#names + 1] = (g.kind == "pickup" and RT.LevelTag(g.level) or "") .. ns.Escape(g.title)
	end
	local more = #gr.goals - #names
	return table.concat(names, ", ") .. (more > 0 and (", +" .. more .. " more") or "")
end

-- What else a stop holds, after the groups a line shows (the player, 2026-11-19: "(+2)" at the end of
-- Up next's rows wasn't descriptive): " (also here: 2 to pick up, 1 to turn in)", or "".
function RT.AlsoText(groups, from)
	local n = { turnin = 0, pickup = 0, ["do"] = 0, enter = 0 }
	for k = from or 2, #groups do
		local gr = groups[k]
		n[gr.kind] = (n[gr.kind] or 0) + #gr.goals
	end
	local bits = {}
	if n.turnin > 0 then bits[#bits + 1] = n.turnin .. " to turn in" end
	if n.pickup > 0 then bits[#bits + 1] = n.pickup .. " to pick up" end
	if n["do"] > 0 then bits[#bits + 1] = n["do"] .. (n["do"] == 1 and " objective" or " objectives") end
	if n.enter > 0 then bits[#bits + 1] = "the way in" end
	if #bits == 0 then return "" end
	return " |cff888888(also here: " .. table.concat(bits, ", ") .. ")|r"
end

-- A stop in one short line (Up next): its first group, and what else is done there.
RT.LOW_TAG = " |cff888888(worth skipping? little XP for the walk)|r"
function RT.StopText(st)
	local groups = RT.Groups(st)
	if #groups == 0 then return "" end
	return RT.StopZone(st) .. RT.GroupText(groups[1]) .. RT.AlsoText(groups, 2) .. (RT.StopLow(st) and RT.LOW_TAG or "")
end

-- Skip the current step (the player's Next); Back brings the last one skipped back.
function RT.Skip()
	local s = RT.Current()
	if not s then return end
	R.routeSkip = R.routeSkip or {}
	R.routeSkip[s.key] = true
	R.routeSkipped = R.routeSkipped or {}
	table.insert(R.routeSkipped, s)
	RT.Refresh()
end
function RT.SetSkip(key, on)
	R.routeSkip = R.routeSkip or {}
	R.routeSkipped = R.routeSkipped or {}
	if on and not R.routeSkip[key] then
		R.routeSkip[key] = true
		for _, s in ipairs(R.route and R.route.stops or {}) do if s.key == key then table.insert(R.routeSkipped, s) end end
	elseif not on and R.routeSkip[key] then
		R.routeSkip[key] = nil
		for k = #R.routeSkipped, 1, -1 do if R.routeSkipped[k].key == key then table.remove(R.routeSkipped, k) end end
	end
	RT.Refresh()
end
function RT.Back()
	local list = R.routeSkipped
	if not list or #list == 0 then return end
	local s = table.remove(list)
	R.routeSkip[s.key] = nil
	RT.Refresh()
end

---------------------------------------------------------------------------
-- Keeping it current
---------------------------------------------------------------------------

-- Something changed what the route should be (the log, the zone, a level): rebuilt a moment later,
-- once however many events came, never in combat (it waits for the fight to end).
-- On a flight path (the player, 2026-11-19: the route kept changing to each zone flown over): the
-- route holds still, and is built again where the player lands.
function RT.OnTaxi() return Try(rawget(_G, "UnitOnTaxi"), "player") and true or false end
function RT.Landed()
	R.routeAfterTaxi = nil
	R.routePlan, R.routeWay, R.routeTrailWay, R.routeWhere = nil, nil, nil, nil
	RT.Dirty()
end
ns.On("PLAYER_CONTROL_GAINED", function() if R.routeAfterTaxi and not RT.OnTaxi() then RT.Landed() end end)

function RT.Dirty()
	if RT.OnTaxi() then R.routeAfterTaxi = true; return end
	if not RT.Shown() then R.routeStale = true; return end
	if R.routeTimer then return end
	R.routeTimer = true
	C_Timer.After(RT.REBUILD_DELAY, function()
		R.routeTimer = nil
		if InCombat() then R.routeStale = true; return end
		-- A rebuild asked for just before takeoff waits for the landing too.
		if RT.OnTaxi() then R.routeAfterTaxi = true; return end
		RT.Build()
		RT.Refresh()
	end)
end

-- Progress changed (an objective ticked, an item looted): the tracker drawn again, the order kept.
function RT.Refresh()
	if RT.Shown() and RT.Draw then RT.Draw() end
	local P = ns.Panel
	if P and P.tab == "route" and P.Soon then P.Soon() end
end

function RT.Shown() return RT.frame and RT.frame:IsShown() and true or false end

-- Quests not in this version of the game (the player, 2026-11-19: Season of Discovery's Duskwood
-- Missions and their Field Captain Palandar are in the quest database, not in Forever; the server even
-- knows their titles, and nothing in the data marks them). Questie keeps a hand-made list of the quests
-- it hides on each version (QuestieCorrections.hiddenQuests): read when Questie is loaded, read only,
-- by the maintainer's choice (2026-11-19) the one exception to "only QuestieDB's and Auctionator's
-- public interfaces"; a list it stops keeping there is simply not read. Without Questie, on WoW
-- Forever: Season of Discovery's quest ids (the 76000s to 91000s), a rough fallback.
RT.SOD_FROM, RT.SOD_TO = 76000, 91999
local function QuestieHidden()
	local loader = rawget(_G, "QuestieLoader")
	local mods = type(loader) == "table" and rawget(loader, "_modules")
	local qc = type(mods) == "table" and rawget(mods, "QuestieCorrections")
	local hidden = type(qc) == "table" and rawget(qc, "hiddenQuests")
	if type(hidden) == "table" and next(hidden) ~= nil then return hidden end
	return nil
end
function RT.IsForever()
	local iface = select(4, Try(GetBuildInfo))
	iface = tonumber(iface)
	return iface ~= nil and iface >= 16000 and iface < 17000
end
function RT.Hidden(id)
	local ok, hidden = pcall(QuestieHidden)
	if ok and hidden then
		local v = hidden[id]
		return v ~= nil and v ~= false
	end
	return RT.IsForever() and id >= RT.SOD_FROM and id <= RT.SOD_TO or false
end

-- Does the game server have this quest at all? (The player, 2026-11-19: the quest database has
-- Season of Discovery's Duskwood Missions and their Field Captain Palandar; Forever has neither,
-- and the route sent the player to an empty spot. The server knows "Wolves at Our Heels" and not
-- "Duskwood Mission I".) The game answers with the quest's title once it has it; a quest it's never
-- heard of stays without one. Asked once per quest and kept (SpellmindDB.routeKnown); a quest not
-- answered yet is left out until it is, so nothing unknown is ever a step.
RT.ASK_PER_BUILD = 40
RT.ASK_WAIT = 5 -- seconds before a quest still without a title counts as unknown (no load event)
function RT.Known(id)
	ns.db.routeKnown = ns.db.routeKnown or {}
	local known = ns.db.routeKnown[id]
	if known ~= nil then return known end
	local QL = C_QuestLog
	local title = QL and type(QL.GetTitleForQuestID) == "function" and Try(QL.GetTitleForQuestID, id) or nil
	if type(title) == "string" and title ~= "" then ns.db.routeKnown[id] = true; return true end
	R.routeAsked = R.routeAsked or {}
	local asked = R.routeAsked[id]
	if asked then
		if GetTime() - asked >= RT.ASK_WAIT and not (QL and type(QL.RequestLoadQuestByID) == "function") then
			ns.db.routeKnown[id] = false
		end
		return false
	end
	R.routeAskedNow = (R.routeAskedNow or 0) + 1
	if R.routeAskedNow > RT.ASK_PER_BUILD then return false end
	R.routeAsked[id] = GetTime()
	if QL and type(QL.RequestLoadQuestByID) == "function" then pcall(QL.RequestLoadQuestByID, id)
	else C_Timer.After(RT.ASK_WAIT + 0.5, function() RT.Dirty() end) end
	return false
end
ns.On("QUEST_DATA_LOAD_RESULT", function(_, id, ok)
	if type(id) ~= "number" or not (R.routeAsked and R.routeAsked[id]) then return end
	ns.db.routeKnown = ns.db.routeKnown or {}
	ns.db.routeKnown[id] = ok and true or false
	R.routeAsked[id] = nil
	if ok then RT.Dirty() end
end)

-- What a quest giver really offers (the player, 2026-11-19: Field Captain Palandar's eighteen
-- Season of Discovery missions are in the quest database, and Questie itself hides them): when the
-- player talks to an NPC the route sends them to for a pick up, a pick up he doesn't offer is left
-- out, and remembered until the character's next level (one may open then).
-- SpellmindDB.routeNotOffered = { [questID] = the level it wasn't offered at }.
function RT.NotOffered(id)
	local t = ns.db and ns.db.routeNotOffered
	local at = t and t[id]
	return at ~= nil and at >= Level()
end

-- The quests the NPC in front of the player offers now: { [questID] = true }, { [title] = true }.
local function Offered(event)
	local ids, titles = {}, {}
	if event == "QUEST_DETAIL" then
		local id = Try(GetQuestID)
		if type(id) == "number" and id > 0 then ids[id] = true end
		local t = Try(GetTitleText)
		if type(t) == "string" then titles[t] = true end
	elseif event == "QUEST_GREETING" then
		for i = 1, tonumber((Try(GetNumAvailableQuests))) or 0 do
			local t = Try(GetAvailableTitle, i)
			if type(t) == "string" then titles[t] = true end
			if type(GetAvailableQuestInfo) == "function" then
				local r = { pcall(GetAvailableQuestInfo, i) }
				if r[1] and type(r[6]) == "number" then ids[r[6]] = true end
			end
		end
	else
		local G = rawget(_G, "C_GossipInfo")
		for _, q in ipairs(G and type(G.GetAvailableQuests) == "function" and Try(G.GetAvailableQuests) or {}) do
			if type(q) == "table" then
				if type(q.questID) == "number" then ids[q.questID] = true end
				if type(q.title) == "string" then titles[q.title] = true end
			end
		end
	end
	return ids, titles
end

function RT.OnGiver(event)
	local route = R.route
	if not route then return end
	-- The NPC by his id, from his GUID (only ns.Redact ever reads a unit's name: the privacy rule).
	local guid = Try(UnitGUID, "npc")
	local npc = type(guid) == "string" and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
	if not npc then return end
	local ids, titles = Offered(event)
	local who
	-- A single-quest window shows one quest, not all he offers: it only confirms, never rules out.
	local single = event == "QUEST_DETAIL"
	ns.db.routeNotOffered = ns.db.routeNotOffered or {}
	-- Whatever he does offer is his, whether the route has it or not (an earlier "doesn't" forgotten).
	local cleared = false
	for id in pairs(ids) do
		if ns.db.routeNotOffered[id] then ns.db.routeNotOffered[id] = nil; cleared = true end
	end
	-- A follow-up the route plans after a turn-in can't be offered yet (the player, 2026-11-19: talking to
	-- Calor to turn in Worgen in the Woods marked its next part as one he doesn't give).
	local function Waits(q)
		for _, p in ipairs((route.after or {})[q] or {}) do if not Done(p) then return true end end
		return false
	end
	local dropped = 0
	for _, st in ipairs(route.stops or {}) do
		for _, g in ipairs(st.goals) do
			if g.kind == "pickup" and g.fromID == npc and not RT.GoalDone(g) and not Waits(g.q) then
				who = who or g.to
				if ids[g.q] or titles[g.title] then
					ns.db.routeNotOffered[g.q] = nil
				elseif not single then
					ns.db.routeNotOffered[g.q] = Level()
					dropped = dropped + 1
				end
			end
		end
	end
	if dropped > 0 then
		ns.Chat.System(ns.Escape(who or "This quest giver") .. " doesn't offer " .. dropped .. " of the quests the route had for him; they're off the route until your next level.")
	end
	if dropped > 0 or cleared then
		if not InCombat() then RT.Build() end
		RT.Refresh()
	end
end
for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do
	ns.On(ev, function() pcall(RT.OnGiver, ev) end)
end

-- A merchant the route sends the player to buy from: when the item isn't in his list (limited stock
-- sells out; the player, 2026-11-19), that step moves off the route for the session, and a line says
-- so; when it is, any earlier "none" is forgotten.
function RT.OnMerchant()
	local route = R.route
	if not route then return end
	local guid = Try(UnitGUID, "npc")
	local npc = type(guid) == "string" and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")) or nil
	if not npc then return end
	local have = {}
	for i = 1, math.min(tonumber((Try(GetMerchantNumItems))) or 0, 200) do
		local link = Try(GetMerchantItemLink, i)
		local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
		if id then have[id] = true end
	end
	ns.db.routeNoStock = ns.db.routeNoStock or {}
	local stock = ns.db.routeNoStock
	local gone
	for _, s in ipairs(route.stops or {}) do
		for _, g in ipairs(s.goals) do
			if g.buyID and g.fromID == npc then
				local key = npc .. ":" .. g.buyID
				if have[g.buyID] then stock[key] = nil
				elseif not RT.NoStock(npc, g.buyID) then stock[key] = time(); gone = gone or g end
			end
		end
	end
	if gone then
		ns.Chat.System(ns.Escape(gone.from or "This vendor") .. " has no " .. ns.Escape(gone.buy) .. " right now (it's limited stock, or not sold here). Try the Auction House or an engineer; the route moves on.")
		if not InCombat() then RT.Build() end
		RT.Refresh()
	end
end
ns.On("MERCHANT_SHOW", function() pcall(RT.OnMerchant) end)

for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE" }) do
	ns.On(ev, function() R.routeWhere = nil; RT.Dirty() end)
end
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "BAG_UPDATE_DELAYED" }) do
	ns.On(ev, function() RT.Refresh() end)
end
ns.On("PLAYER_REGEN_ENABLED", function() if R.routeStale and RT.Shown() then R.routeStale = nil; RT.Dirty() end end)

---------------------------------------------------------------------------
-- The tracker: a small window to leave open while questing (closed by default; /sm route)
---------------------------------------------------------------------------

RT.W, RT.H = 330, 240
RT.UPNEXT_LINES = 3 -- until the player sizes the window; then as many as fit
RT.NEXT_MAX = 12
RT.THEN_LINES = 2
RT.AWAY_LINES = 5
RT.WAY_LINES = 6
RT.MIN_W, RT.MIN_H, RT.MAX_W, RT.MAX_H = 260, 150, 640, 720
-- The window's size and fold, kept: SpellmindDB.routeUI = { w, h, compact }.
local function UI()
	ns.db.routeUI = type(ns.db.routeUI) == "table" and ns.db.routeUI or {}
	return ns.db.routeUI
end

local BACKDROP = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } }

local function Line(parent, font, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH("LEFT")
	fs:SetWidth(width)
	if fs.SetWordWrap then fs:SetWordWrap(true) end
	return fs
end

-- The tracker's place, kept: SpellmindDB.routeUI.pos = { point, relative point, x, y }.
function RT.KeepPlace(f)
	local p, _, rp, x, y = f:GetPoint()
	if not p then return end
	UI().pos = { p, rp or p, math.floor((tonumber(x) or 0) + 0.5), math.floor((tonumber(y) or 0) + 0.5) }
end

local function Build()
	if RT.frame then return RT.frame end
	local f = CreateFrame("Frame", "SpellmindRoute", UIParent, "BackdropTemplate")
	f:SetSize(RT.W, RT.H)
	-- Where the player left it (the player, 2026-11-19: back in the default spot after a /reload).
	local pos = UI().pos
	if type(pos) == "table" and pos[1] then
		f:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 40)
	end
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); RT.KeepPlace(self) end)
	if f.SetBackdrop then
		f:SetBackdrop(BACKDROP)
		f:SetBackdropColor(0.05, 0.04, 0.1, 0.94)
		f:SetBackdropBorderColor(0.62, 0.49, 1, 1)
	end
	if ns.Window and ns.Window.Corners then ns.Window.Corners(f, 18) end
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetSize(22, 22)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -8)
	f.portrait:SetTexture(ns.Marks and ns.Marks.PORTRAIT or "Interface\\AddOns\\Spellmind\\Media\\Portrait")
	-- The owl: the Route tab, with every step, the switches and the questions (the player, 2026-11-19).
	f.owl = CreateFrame("Button", nil, f)
	f.owl:SetAllPoints(f.portrait)
	f.owl:SetScript("OnClick", function() if ns.Panel then ns.Panel.Show("route") end end)
	f.owl:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("The Route tab")
		GameTooltip:AddLine("Every step, where next, the switches, and questions for your AI.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.owl:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -12)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.close:SetScript("OnClick", function()
		RT.Toggle(false)
		ns.Chat.System("The route is off. /sm route, or Settings, brings it back.")
	end)
	-- The fold (the player, 2026-11-19): only the current step, for less on screen while questing.
	f.fold = CreateFrame("Button", nil, f)
	f.fold:SetSize(16, 16)
	f.fold:SetPoint("RIGHT", f.close, "LEFT", 0, 0)
	f.fold:SetScript("OnClick", function() local ui = UI(); ui.compact = not ui.compact or nil; RT.Draw() end)
	f.step = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.step:SetPoint("RIGHT", f.fold, "LEFT", -4, 0)
	-- The current step, on a lighter band: its line (with progress), the names under a many-quest
	-- line, and Go; then up to two more lines of the same stop.
	f.band = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.band:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -36)
	f.band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -36)
	if f.band.SetBackdrop then
		f.band:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f.band:SetBackdropColor(0.16, 0.11, 0.3, 0.9)
		f.band:SetBackdropBorderColor(0.62, 0.49, 1, 0.9)
	end
	f.now = Line(f.band, "GameFontHighlight", RT.W - 32)
	f.now:SetPoint("TOPLEFT", f.band, "TOPLEFT", 8, -8)
	f.nowSub = Line(f.band, "GameFontDisableSmall", RT.W - 32)
	-- Everything under the band scrolls when the window is shorter than it (the player, 2026-11-19:
	-- the text ran out of the window). The bar shows only then.
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(RT.W - 22, 10)
	f.scroll:SetScrollChild(f.content)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = tonumber((self:GetVerticalScrollRange())) or 0
		local y = (tonumber((self:GetVerticalScroll())) or 0) - delta * 30
		self:SetVerticalScroll(math.max(0, math.min(range, y)))
		if f.bar and f.bar.Update then f.bar.Update() end
	end)
	f.bar = ns.Window and ns.Window.ScrollBar and ns.Window.ScrollBar(f.scroll, 4) or nil
	local C = f.content
	f.thens = {}
	for i = 1, RT.THEN_LINES do
		local l = Line(C, "GameFontHighlightSmall", RT.W - 40)
		if l.SetMaxLines then l:SetMaxLines(3) end
		f.thens[i] = l
	end
	-- The way there (the player, 2026-11-19: list the travel steps under "Done here" when the way is to
	-- another zone): its legs in order, the one to do now in gold.
	f.wayLabel = C:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.wayLabel:SetText("The way there")
	f.way = {}
	for i = 1, RT.WAY_LINES do
		local l = Line(C, "GameFontHighlightSmall", RT.W - 40)
		if l.SetMaxLines then l:SetMaxLines(2) end
		f.way[i] = l
	end
	f.nextLabel = C:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.nextLabel:SetText("Up next")
	f.next = {}
	for i = 1, RT.NEXT_MAX do
		local l = Line(C, "GameFontHighlightSmall", RT.W - 40)
		if l.SetMaxLines then l:SetMaxLines(3) end
		f.next[i] = l
	end
	-- Where next: the best zones to go on to, each a line to click for a pin at its quest givers.
	f.whereLabel = C:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.whereLabel:SetText("Where next")
	f.where = {}
	for i = 1, RT.WHERE_SHOWN do
		local b = CreateFrame("Button", nil, C)
		b:SetSize(RT.W - 40, 15)
		b.text = Line(b, "GameFontHighlightSmall", RT.W - 40)
		if b.text.SetMaxLines then b.text:SetMaxLines(3) end
		b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b:SetScript("OnClick", function(self) if self.zone then RT.Aim(self.zone) end end)
		f.where[i] = b
	end
	-- Elsewhere: its own heading and lines (the player, 2026-11-19: one crammed line was hard to read),
	-- and where the route's data comes from, on a line of its own above the buttons.
	f.awayLabel = C:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.awayLabel:SetText("Elsewhere")
	f.away = {}
	for i = 1, RT.AWAY_LINES do
		local l = Line(C, "GameFontHighlightSmall", RT.W - 40)
		if l.SetMaxLines then l:SetMaxLines(3) end
		f.away[i] = l
	end
	f.credit = Line(f, "GameFontDisableSmall", RT.W - 28)
	f.credit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 36)
	-- Back, Skip, Rebuild.
	f.back = ns.GearUI.Button(f, "Back", 60)
	f.back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
	f.back:SetScript("OnClick", function() RT.Back() end)
	f.skip = ns.GearUI.Button(f, "Skip", 60)
	f.skip:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
	f.skip:SetScript("OnClick", function() RT.Skip() end)
	f.rebuild = ns.GearUI.Button(f, "Rebuild", 76)
	f.rebuild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
	f.rebuild:SetScript("OnClick", function() RT.Build(); RT.Draw() end)
	-- Sized by its corner (the player, 2026-11-19): taller shows more of Up next; the size is kept.
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(RT.MIN_W, RT.MIN_H, RT.MAX_W, RT.MAX_H)
	elseif f.SetMinResize then f:SetMinResize(RT.MIN_W, RT.MIN_H); if f.SetMaxResize then f:SetMaxResize(RT.MAX_W, RT.MAX_H) end end
	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(16, 16)
	f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	f.grip:SetScript("OnMouseDown", function() f.sizing = true; f:StartSizing("BOTTOMRIGHT") end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		f.sizing = nil
		local ui = UI()
		ui.w, ui.h = math.floor((tonumber(f:GetWidth()) or RT.W) + 0.5), math.floor((tonumber(f:GetHeight()) or RT.H) + 0.5)
		RT.KeepPlace(f)
		RT.Draw()
	end)
	f:SetScript("OnSizeChanged", function() if f.sizing then RT.Draw() end end)
	f:SetScript("OnHide", function()
		if RT.arrow then RT.arrow:Hide() end
		pcall(RT.DrawMap)
		if ns.RoutePins then pcall(ns.RoutePins.Refresh); pcall(ns.RoutePins.Update, true) end
	end)
	local ui = UI()
	if ui.w then f:SetWidth(math.max(RT.MIN_W, math.min(RT.MAX_W, ui.w))) end
	f:Hide()
	RT.frame = f
	return f
end

-- Elsewhere, in lines a player can read: "Westfall: Turn in Wolves at Our Heels to Gryan Stoutmantle
-- (+1)", "No known spot: Look to the Stars, Ogre Thievery", "Above your level for now: …".
local function Names(goals, max)
	local out, seen = {}, {}
	for _, g in ipairs(goals) do
		if not seen[g.title] and #out < max then seen[g.title] = true; out[#out + 1] = ns.Escape(g.title) end
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	return table.concat(out, ", ") .. (n > #out and (", +" .. (n - #out)) or "")
end
function RT.AwayLines(route)
	local zones, unplaced = {}, {}
	for zone, goals in pairs(route.elsewhere or {}) do
		if zone == "" then unplaced = goals else zones[#zones + 1] = { zone = zone, goals = goals } end
	end
	table.sort(zones, function(a, b) if #a.goals ~= #b.goals then return #a.goals > #b.goals end return a.zone < b.zone end)
	local lines = {}
	for i, z in ipairs(zones) do
		if i > 3 then break end
		local more = #z.goals - 1
		lines[#lines + 1] = "|cffffd100" .. ns.Escape(z.zone) .. ":|r " .. RT.GoalText(z.goals[1]) .. (more > 0 and (" |cff888888(and " .. more .. " more there)|r") or "")
	end
	if #zones > 3 then lines[#lines + 1] = "|cff888888and " .. (#zones - 3) .. " more zones|r" end
	if #unplaced > 0 then lines[#lines + 1] = "|cff888888No known spot:|r " .. Names(unplaced, 2) end
	if #(route.later or {}) > 0 then
		local later = {}
		for _, t in ipairs(route.later) do later[#later + 1] = { title = t } end
		lines[#lines + 1] = "|cff888888Above your level for now:|r " .. Names(later, 2)
	end
	return lines
end
function RT.Credit(route)
	if route.nowhere then return nil end
	return route.db and "Quest data from Questie" or "Questie adds quests to pick up here and exact objective spots"
end

-- (kept for anything that still asks for the old one-paragraph form)
local function AlsoText(route)
	local bits, unplaced = {}, 0
	for zone, goals in pairs(route.elsewhere or {}) do
		if zone == "" then unplaced = #goals else bits[#bits + 1] = { zone = zone, n = #goals } end
	end
	table.sort(bits, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.zone < b.zone end)
	local words = {}
	for i, b in ipairs(bits) do
		if i > 3 then break end
		words[#words + 1] = ns.Escape(b.zone) .. ": " .. b.n
	end
	if unplaced > 0 then words[#words + 1] = unplaced .. " Spellmind can't place" end
	local text = #words > 0 and ("Elsewhere: " .. table.concat(words, " · ")) or nil
	if #(route.later or {}) > 0 then
		text = (text and (text .. "\n") or "") .. #route.later .. " quest" .. (#route.later > 1 and "s" or "") .. " in your log for later (above your level)"
	end
	-- Where the route's knowledge comes from, said plainly (the player, 2026-11-19: Questie is the
	-- popular choice; credit it, and say what it adds when it isn't there).
	if not route.nowhere then
		local source = route.db and "Quest data from Questie"
			or "Questie adds quests to pick up here and exact objective spots"
		text = (text and (text .. "\n") or "") .. source
	end
	return text
end

local function Row(fs)
	local h = tonumber(fs:GetStringHeight()) or 12
	return h > 16 and math.floor(h + 4.5) or 15
end

function RT.Draw()
	local f = RT.frame
	if not f then return end
	local route = R.route or {}
	local ui = UI()
	RT.ArrowSync()
	pcall(RT.DrawMap)
	if ns.RoutePins then pcall(ns.RoutePins.Refresh) end
	local W = tonumber(f:GetWidth()) or RT.W
	f.now:SetWidth(W - 32); f.nowSub:SetWidth(W - 32); f.credit:SetWidth(W - 28)
	for _, l in ipairs(f.away) do l:SetWidth(W - 40) end
	for _, b in ipairs(f.where) do b:SetWidth(W - 40); b.text:SetWidth(W - 40) end
	local wl = RT.WhereLines(route)
	for _, l in ipairs(f.thens) do l:SetWidth(W - 40) end
	for _, l in ipairs(f.next) do l:SetWidth(W - 40) end
	f.fold:SetNormalTexture(ui.compact and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
	f.fold.tip = ui.compact and "Show Up next" or "Only the current step"
	f.title:SetText("Route" .. (route.prep and (" · " .. ns.Escape(route.prep) .. " prep") or (route.zone and (" · " .. ns.Escape(route.zone)) or "")))
	local cur, i = RT.Current()
	local done, total = RT.Progress()
	-- On the way to a chosen zone: the steps here wait. Done in the zone it was chosen in, the band says
	-- so as ever ("Done here ... Next: Westfall (your choice)").
	local going = RT.Traveling(route)
	if going and not cur and route.area == R.routeAimFrom then going = nil end
	if going then cur = nil end
	f.step:SetText(going and "" or total > 0 and ("Step " .. (i or math.min(done + 1, total)) .. " of " .. total) or "")
	local groups = cur and RT.Groups(cur) or {}
	local sub
	if route.nowhere then
		f.now:SetText("|cff888888No map position here (an instance or a loading screen): the route waits until you're outside.|r")
	elseif going then
		f.now:SetText("|cff19ff19On the way to|r |cffffd100" .. ns.Escape(going.zone) .. "|r |cff888888(your choice)|r")
		sub = RT.WhereText(going)
	elseif not cur and wl[1] then
		-- The zone the player chose, else the best (the player, 2026-11-19: Wetlands chosen, the band still
		-- said Stormwind City).
		local nz = RT.NextZone(route) or wl[1]
		f.now:SetText("|cff19ff19Done here at your level.|r Next: |cffffd100" .. ns.Escape(nz.zone) .. "|r" .. (R.routeAim == nz.area and " |cff888888(your choice)|r" or ""))
		sub = RT.WhereText(nz)
	elseif not cur then
		f.now:SetText("|cff19ff19Nothing left here that Spellmind knows of.|r" .. (route.db and "" or
			"\n|cff888888With QuestieDB installed, the route also lists quests to pick up here, and where mobs are.|r"))
	else
		f.now:SetText(groups[1] and (RT.StopZone(cur) .. RT.GroupText(groups[1])) or "")
		sub = groups[1] and RT.GroupNames(groups[1])
	end
	f.nowSub:SetText(sub or "")
	f.nowSub:ClearAllPoints()
	f.nowSub:SetPoint("TOPLEFT", f.now, "BOTTOMLEFT", 0, -3)
	if sub then f.nowSub:Show() else f.nowSub:Hide() end
	local bandH = 16 + math.max(20, tonumber(f.now:GetStringHeight()) or 20) + (sub and (3 + (tonumber(f.nowSub:GetStringHeight()) or 12)) or 0)
	f.band:SetHeight(bandH)
	local rest = { f.nextLabel, f.wayLabel, f.whereLabel, f.awayLabel, f.credit, f.back, f.skip, f.rebuild, f.grip }
	-- Folded: the current step alone.
	if ui.compact then
		for _, l in ipairs(f.thens) do l:Hide() end
		for _, l in ipairs(f.next) do l:Hide() end
		for _, l in ipairs(f.away) do l:Hide() end
		for _, l in ipairs(f.way) do l:Hide() end
		for _, b in ipairs(f.where) do b:Hide() end
		for _, r in ipairs(rest) do r:Hide() end
		f.scroll:Hide()
		if f.bar then f.bar:Hide() end
		if not f.sizing then f:SetHeight(36 + bandH + 10) end
		return
	end
	for _, r in ipairs({ f.credit, f.back, f.skip, f.rebuild, f.grip }) do r:Show() end
	f.scroll:Show()
	local top = -36 - bandH - 4 -- the scroll's top, from the window's
	local y = -36 - bandH - 8
	-- Then: the rest of this stop, two lines at most.
	for k, l in ipairs(f.thens) do
		local gr = groups[k + 1]
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f.content, "TOPLEFT", 16 - 8, y - top)
		if gr then
			local last = k == RT.THEN_LINES and #groups > RT.THEN_LINES + 1
			l:SetText("|cff888888Then:|r " .. RT.GroupText(gr) .. (last and RT.AlsoText(groups, RT.THEN_LINES + 2) or ""))
			l:Show()
			y = y - Row(l)
		else
			l:SetText("")
			l:Hide()
		end
	end
	y = y - 6
	-- The way there: the legs of the arrow's way when it leads to another zone.
	local wt = RT.ArrowTarget()
	local wayLegs = (wt and (wt.away or wt.zone) and wt.legs) or {}
	f.wayLabel:ClearAllPoints()
	if #wayLegs > 0 then
		y = y - 8
		f.wayLabel:SetPoint("TOPLEFT", f.content, "TOPLEFT", 6, y - top)
		f.wayLabel:Show()
		y = y - 16
	else
		f.wayLabel:Hide()
	end
	for k, l in ipairs(f.way) do
		local leg = wayLegs[k]
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f.content, "TOPLEFT", 12, y - top)
		if leg then
			local more = k == RT.WAY_LINES and #wayLegs > RT.WAY_LINES
			l:SetText((k == 1 and "|cffffd100" or "|cffffffff") .. k .. ".|r " .. (leg.tip and leg.tip[1] or "?") .. (more and (" |cff888888(then " .. (#wayLegs - RT.WAY_LINES) .. " more " .. ((#wayLegs - RT.WAY_LINES) == 1 and "leg" or "legs") .. ")|r") or ""))
			l:Show()
			y = y - Row(l)
		else
			l:SetText("")
			l:Hide()
		end
	end
	if #wayLegs > 0 then y = y - 4 end
	-- How many of Up next: three, or as many as the player's size of the window holds.
	local away = RT.AwayLines(route)
	local credit = RT.Credit(route)
	f.credit:SetText(credit and ("|cff777777" .. credit .. "|r") or "")
	-- Where next, when the band isn't already saying it: the zones after the first.
	local shownWhere = {}
	if going then
		-- Quest here instead: ends the choice (Aim on the chosen zone again), the steps here back.
		local left = total - done
		if left > 0 then shownWhere[1] = { instead = true, area = going.area, zone = route.zone, left = left } end
		for _, z in ipairs(route.where or {}) do
			if not z.here and z ~= going and #shownWhere < RT.WHERE_SHOWN then shownWhere[#shownWhere + 1] = z end
		end
	else
		local named = not cur and (RT.NextZone(route) or wl[1]) or nil
		for _, z in ipairs(wl) do if z ~= named then shownWhere[#shownWhere + 1] = z end end
	end
	local whereH, awayH = 0, 0
	for k, b in ipairs(f.where) do
		local z = shownWhere[k]
		b.zone = z
		local aimed = z and R.routeAim == z.area
		if z and z.instead then
			b.text:SetText("|cff19ff19Quest here instead:|r |cffffd100" .. ns.Escape(z.zone or "here") .. "|r, " .. z.left .. (z.left == 1 and " step" or " steps"))
		else
			b.text:SetText(z and ((aimed and "|cff19ff19\194\187|r " or "") .. "|cffffd100" .. ns.Escape(z.zone) .. ":|r " .. RT.WhereText(z)) or "")
		end
		if z then b:SetHeight(Row(b.text)); whereH = whereH + Row(b.text) end
	end
	for k, l in ipairs(f.away) do
		l:SetText(away[k] or "")
		if away[k] then awayH = awayH + Row(l) end
	end
	local alsoH = (#away > 0 and (14 + 16 + awayH) or 0) + (credit and 16 or 0)
		+ (#shownWhere > 0 and (14 + 16 + whereH) or 0)
	local fixedH = f.sizing and (tonumber(f:GetHeight()) or RT.H) or ui.h
	-- Room for Up next: three, or as many as the player's size of the window holds (one at least).
	local room = fixedH and (fixedH + y - 16 - alsoH - 44) or nil
	local upnext = going and {} or RT.UpNext(fixedH and RT.NEXT_MAX or RT.UPNEXT_LINES)
	f.nextLabel:ClearAllPoints()
	f.nextLabel:SetPoint("TOPLEFT", f.content, "TOPLEFT", 14 - 8, y - top)
	-- No Up next: no heading, and no room kept for it (the player's screenshot, 2026-11-19: a gap
	-- under "Done here" before "Or").
	if #upnext > 0 then f.nextLabel:Show(); y = y - 16 else f.nextLabel:Hide(); y = y + 6 end
	local used = 0
	for k, l in ipairs(f.next) do
		local s = upnext[k]
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f.content, "TOPLEFT", 20 - 8, y - top)
		if s then l:SetText(RT.StopText(s)) else l:SetText("") end
		local h = s and Row(l)
		if s and (k == 1 or not room or used + h <= room) then
			l:Show()
			y, used = y - h, used + h
		else
			upnext[k] = nil
			l:Hide()
		end
	end
	-- Where next: a gap, its heading ("Or" when the band names the first), its lines.
	f.whereLabel:ClearAllPoints()
	if #shownWhere > 0 then
		y = y - 14
		f.whereLabel:SetText((cur and "Where next") or (going and "Or") or "Or")
		f.whereLabel:SetPoint("TOPLEFT", f.content, "TOPLEFT", 14 - 8, y - top)
		f.whereLabel:Show()
		y = y - 16
	else
		f.whereLabel:Hide()
	end
	for k, b in ipairs(f.where) do
		local z = shownWhere[k]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f.content, "TOPLEFT", 20 - 8, y - top)
		if z then b:Show(); y = y - Row(b.text) else b:Hide() end
	end
	-- Elsewhere: a gap, its heading, its lines.
	f.awayLabel:ClearAllPoints()
	if #away > 0 then
		y = y - 14
		f.awayLabel:SetPoint("TOPLEFT", f.content, "TOPLEFT", 14 - 8, y - top)
		f.awayLabel:Show()
		y = y - 16
	else
		f.awayLabel:Hide()
	end
	for k, l in ipairs(f.away) do
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f.content, "TOPLEFT", 20 - 8, y - top)
		if away[k] then l:Show(); y = y - Row(l) else l:Hide() end
	end
	-- The content's height (what scrolls), and the scroll between the band and the credit line.
	f.content:SetSize(W - 22, math.max(1, top - y + 4))
	f.scroll:ClearAllPoints()
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, top)
	f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, credit and 50 or 38)
	if credit then y = y - 16 end
	-- As tall as what it shows, with room for the buttons (the player, 2026-11-19: text ran out of it),
	-- or the player's own size.
	if not f.sizing then f:SetHeight(ui.h and math.max(RT.MIN_H, math.min(RT.MAX_H, ui.h)) or math.max(RT.MIN_H, -y + 44)) end
	if f.bar and f.bar.Update then f.bar.Update() end
	if R.routeSkipped and #R.routeSkipped > 0 then f.back:Enable() else f.back:Disable() end
	if cur and not going then f.skip:Enable() else f.skip:Disable() end
end

-- The route on or off, kept (SpellmindDB.routeUI.on): on, the tracker is open through /reload and
-- logins (the player, 2026-11-19: "I have to type /sm route every time").
function RT.On() return UI().on == true end
function RT.SetOn(v) RT.Toggle(v and true or false) end
ns.On("PLAYER_LOGIN", function()
	C_Timer.After(RT.OPEN_DELAY, function() if RT.On() and not RT.Shown() then RT.Toggle(true) end end)
end)
RT.OPEN_DELAY = 3 -- seconds after login: the map and the quest log are ready

-- The arrow and the map's steps, each its own switch (Settings).
function RT.ArrowOn() return not UI().arrowOff end
function RT.SetArrow(v) UI().arrowOff = (not v) or nil; RT.ArrowSync() end
function RT.MapOn() return not UI().mapOff end
function RT.LinesOn() return not UI().linesOff end
-- The lines on the minimap (the player, 2026-11-19), on by default: thin, under the pins.
function RT.MinimapLinesOn() return not UI().miniLinesOff end
function RT.SetMinimapLines(v) UI().miniLinesOff = (not v) or nil; if ns.RoutePins then ns.RoutePins.Refresh(); pcall(ns.RoutePins.Update, true) end end
function RT.MinimapOn() return not UI().minimapOff end
function RT.SetMinimap(v) UI().minimapOff = (not v) or nil; if ns.RoutePins then ns.RoutePins.Refresh(); pcall(ns.RoutePins.Update, true) end end
function RT.SetLines(v) UI().linesOff = (not v) or nil; pcall(RT.DrawMap) end
function RT.SetMap(v) UI().mapOff = (not v) or nil; pcall(RT.DrawMap) end

-- /sm route: open (built fresh when it's stale) or close.
function RT.Toggle(show)
	local f = Build()
	if show == nil then show = not f:IsShown() end
	UI().on = show or nil
	if not show then f:Hide(); return false end
	f:Show()
	if not R.route or R.routeStale then R.routeStale = nil; RT.Build() end
	RT.Draw()
	return true
end

---------------------------------------------------------------------------
-- The arrow (docs/milestone-23-route.md phase 2): on screen, pointing at the current step, with the
-- yards to it
---------------------------------------------------------------------------

-- The player (2026-11-19): navigation to the next objective, and on to the next questing area. It
-- points at the current step; with nothing left here, at the way to the next zone (its first leg: the
-- flight master to fly from, or the zone's quest giver on foot; the hearthstone said in words). From
-- the game's facing and world positions; in an instance there's no position, and it says so. Shown
-- with the tracker; right-click hides it (/sm arrow brings it back), drag moves it (kept).
RT.ARROW_TICK = 0.05 -- seconds between turns
RT.ARRIVE_YARDS = 12
RT.AHEAD = 0.35 -- radians either side of straight on: the arrow goes green

-- What the arrow points at: { world = { c, x, y }, text, sub, hearth }, or nil.
-- The way to somewhere in another zone (the player, 2026-11-19: a prep step in Duskwood showed nothing
-- on Redridge's map, while "done here" drew a clear path): { minutes, how, leg, land } from RT.Travel,
-- kept a few seconds per target so the arrow's ticks don't work it out again each time.
RT.WAY_KEEP = 5
function RT.WayTo(key, target)
	local c = R.routeWay
	if c and c.key == key and (GetTime() - c.at < RT.WAY_KEEP or RT.OnTaxi()) then return c.way end
	local me = RT.PlayerWorld()
	local way = me and target and RT.Travel(me, target, RT.Speed()) or nil
	R.routeWay = { key = key, at = GetTime(), way = way }
	return way
end

-- "south-west": the way from the player to a world spot (x north, y west).
function RT.Heading(to)
	local me = RT.PlayerWorld()
	if not me or not to or me.c ~= to.c then return nil end
	local a = math.atan2 and math.atan2(to.y - me.y, to.x - me.x) or math.atan(to.y - me.y, to.x - me.x)
	local k = math.floor((a / (math.pi / 4)) + 0.5) % 8
	return ({ "north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east" })[k + 1]
end

local function FlightText(leg) return (leg.npc and (leg.npc .. ", the flight master at ") or "Flight master at ") .. Short(leg.name) end

-- The legs to a destination: the flight master and where it lands (when flying is quickest), then the
-- destination itself, each { world, tip, zone }.
local function Legs(way, dest, destTip, destZone)
	local legs = {}
	if way and way.how == "fly" and type(way.leg) == "table" then
		legs[#legs + 1] = { world = way.leg, tip = { FlightText(way.leg), type(way.land) == "table" and ("Fly to " .. Short(way.land.name)) or nil } }
		if type(way.land) == "table" then
			legs[#legs + 1] = { world = way.land, tip = { "Land at " .. Short(way.land.name), "Then on to " .. (destZone or "the next step") .. " from there" }, zone = way.land.name:match(",%s*(.+)$") }
		end
	end
	if dest then legs[#legs + 1] = { world = dest, tip = destTip, zone = destZone, dest = true } end
	return legs
end

function RT.ArrowTarget()
	local route = R.route
	if not route or route.nowhere then return nil end
	local z
	for _, w in ipairs(route.where or {}) do if R.routeAim and w.area == R.routeAim then z = w end end
	local cur = RT.Current()
	if cur and not z then
		local gr = RT.Groups(cur)[1]
		local text = RT.StopZone(cur) .. (gr and RT.GroupText(gr) or RT.GoalText(cur.goals[1]))
		local target = World(RT.StopMap(cur), cur.x, cur.y)
		local here = RT.Here()
		-- In another zone: the quickest way there, leg by leg.
		if target and here and RT.StopMap(cur) ~= here.map then
			local plan = RT.PlanTo(cur.key, { map = RT.StopMap(cur), x = cur.x, y = cur.y }, { text, "Your next step." }, cur.zoneName)
			if plan then local t = RT.PlanTarget(plan); if t then t.step = cur end; return t end
			local way = RT.WayTo(cur.key, target)
			local legs = Legs(way, target, { text, "Your next step." }, cur.zoneName)
			if way and way.how == "hearth" then
				return { hearth = true, text = "Use your hearthstone", sub = (way.via and (way.via:gsub("^hearthstone ", "")) or "") .. ", then on to " .. (cur.zoneName or "the next step"), legs = legs, away = true }
			end
			if way and way.how == "fly" and type(way.leg) == "table" then
				local land = type(way.land) == "table" and Short(way.land.name)
				return { world = way.leg, text = FlightText(way.leg), sub = "then fly to " .. (land or "?") .. ", for: " .. text, legs = legs, away = true }
			end
			local dir = RT.Heading(target)
			return { world = target, text = text, sub = dir and ("head " .. dir .. " to " .. (cur.zoneName or "the next zone")) or nil, legs = legs, away = true }
		end
		return { world = target, text = text, path = RT.TrailTo(cur.key, target), step = cur }
	end
	z = z or RT.WhereLines(route)[1]
	if not z then return nil end
	if z.spot then
		local plan = RT.PlanTo("zone:" .. tostring(z.area), { map = z.map, x = z.spot.x, y = z.spot.y },
			{ z.zone .. (z.spot.giver and (": " .. z.spot.giver) or ""), RT.WhereText(z), "Where the arrow is heading." }, z.zone)
		if plan then local t = RT.PlanTarget(plan); t.zone = z; return t end
	end
	local dest = z.spot and World(z.map, z.spot.x, z.spot.y)
	local legs = Legs({ how = z.how, leg = z.leg, land = z.land }, dest,
		{ z.zone .. (z.spot and z.spot.giver and (": " .. z.spot.giver) or ""), RT.WhereText(z), "Where the arrow is heading." }, z.zone)
	if z.leg == "hearth" then
		return { hearth = true, zone = z, legs = legs, text = "Use your hearthstone", sub = (z.via and (z.via:gsub("^hearthstone ", "")) or "") .. ", then on to " .. z.zone }
	end
	if type(z.leg) == "table" then
		return { world = z.leg, zone = z, legs = legs, text = FlightText(z.leg), sub = RT.LandText(z) }
	end
	return { world = dest, zone = z, legs = legs, text = z.zone .. (z.spot and z.spot.giver and (": " .. z.spot.giver) or "") }
end

-- Where a flight to a zone comes down: in the zone itself (its flight path's name says the zone:
-- "Menethil Harbor, Wetlands"), or at a known path short of it.
function RT.LandsIn(z)
	local name = type(z.land) == "table" and z.land.name
	return type(name) == "string" and DG().Norm(name:match(",%s*(.+)$") or "") == DG().Norm(z.zone) or false
end
function RT.LandText(z)
	if type(z.land) ~= "table" then return "then fly on to " .. z.zone end
	local at = Short(z.land.name)
	if RT.LandsIn(z) then return "then fly to " .. at end
	return "then fly to " .. at .. ", and on to " .. z.zone .. " from there"
end

-- The arrow's turn (radians, counterclockwise from straight up) and the yards from the player to a
-- spot. The game's world positions run x to the north and y to the west; its facing is 0 to the north,
-- counterclockwise.
function RT.Bearing(me, to, facing)
	local north, west = to.x - me.x, to.y - me.y
	local angle = math.atan2 and math.atan2(west, north) or math.atan(west, north)
	return angle - (facing or 0), math.sqrt(north * north + west * west)
end

function RT.BuildArrow()
	if RT.arrow then return RT.arrow end
	local a = CreateFrame("Button", "SpellmindArrow", UIParent)
	a:SetSize(64, 64)
	local spot = UI().arrow
	if type(spot) == "table" and spot[1] then a:SetPoint(spot[1], UIParent, spot[1], tonumber(spot[2]) or 0, tonumber(spot[3]) or 0)
	else a:SetPoint("TOP", UIParent, "TOP", 0, -120) end
	a:SetFrameStrata("MEDIUM")
	a:SetClampedToScreen(true)
	a:EnableMouse(true)
	a:SetMovable(true)
	a:RegisterForDrag("LeftButton")
	a:SetScript("OnDragStart", function(self) self:StartMoving() end)
	a:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint()
		UI().arrow = { p or "CENTER", math.floor((tonumber(x) or 0) + 0.5), math.floor((tonumber(y) or 0) + 0.5) }
	end)
	if a.RegisterForClicks then a:RegisterForClicks("RightButtonUp") end
	a:SetScript("OnClick", function(_, button) if button == "RightButton" then RT.ArrowOff(true) end end)
	a:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Spellmind: the route")
		GameTooltip:AddLine("Points at the current step. Drag to move it; right-click to hide it (/sm arrow shows it again).", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	a:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	-- The game's own arrow art (the minimap's), turned.
	a.tex = a:CreateTexture(nil, "ARTWORK")
	a.tex:SetSize(48, 48)
	a.tex:SetPoint("CENTER", a, "CENTER", 0, 4)
	a.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
	a.dist = a:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	a.dist:SetPoint("TOP", a, "BOTTOM", 0, 4)
	a.text = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	a.text:SetPoint("TOP", a.dist, "BOTTOM", 0, -2)
	a.text:SetWidth(240)
	a.sub = a:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	a.sub:SetPoint("TOP", a.text, "BOTTOM", 0, -2)
	a.sub:SetWidth(240)
	local acc = 0
	a:SetScript("OnUpdate", function(_, dt)
		acc = acc + (tonumber(dt) or 0)
		if acc >= RT.ARROW_TICK then acc = 0; RT.ArrowUpdate() end
	end)
	a:Hide()
	RT.arrow = a
	return a
end

-- Shown while the tracker is, unless the player hid it.
function RT.ArrowSync()
	local show = RT.Shown() and not UI().arrowOff
	if not show then if RT.arrow then RT.arrow:Hide() end return end
	local a = RT.BuildArrow()
	if not a:IsShown() then a:Show() end
	RT.ArrowUpdate()
end

function RT.ArrowOff(off)
	UI().arrowOff = off and true or nil
	RT.ArrowSync()
	if off then ns.Chat.System("The route's arrow is hidden. /sm arrow shows it again.") end
end

-- /sm arrow: the arrow back (and the tracker with it), or hidden.
function RT.ToggleArrow()
	if UI().arrowOff or not RT.Shown() then
		UI().arrowOff = nil
		RT.Toggle(true)
		return true
	end
	RT.ArrowOff(true)
	return false
end

function RT.ArrowUpdate()
	pcall(RT.NoteOutside)
	local a = RT.arrow
	if not a or not a:IsShown() then return end
	local t = RT.ArrowTarget()
	a.turn, a.yards = nil, nil
	local function Still(dist, text, sub)
		a.tex:Hide()
		a.dist:SetText(dist or "")
		a.text:SetText(text or "")
		a.sub:SetText(sub or "")
	end
	if RT.OnTaxi() then return Still("", "|cff9d7dffIn flight|r", "The route picks up where you land.") end
	if not t then return Still("", "|cff19ff19Nothing left on the route here.|r") end
	if t.hearth then return Still("", t.text, t.sub) end
	local me = RT.PlayerWorld()
	local facing = Try(rawget(_G, "GetPlayerFacing"))
	if not me or type(facing) ~= "number" then return Still("|cff888888No position in here|r", t.text, t.sub) end
	if not t.world then return Still("", t.text, t.sub) end
	if t.world.c ~= me.c then return Still("|cff888888On another continent|r", t.text, t.sub) end
	local aim, along = t.world, nil
	if t.path then aim, along = RT.LookAhead(me, t.path, t.world) end
	local turn, yards = RT.Bearing(me, aim, facing)
	yards = along or yards
	if yards <= RT.ARRIVE_YARDS then return Still("|cff19ff19You're there|r", t.text, t.sub) end
	a.tex:Show()
	a.tex:SetRotation(turn)
	local off = math.abs(((turn + math.pi) % (2 * math.pi)) - math.pi)
	if off <= RT.AHEAD then a.tex:SetVertexColor(0.35, 1, 0.35) else a.tex:SetVertexColor(1, 0.82, 0) end
	a.dist:SetText(math.floor(yards + 0.5) .. " yd")
	a.text:SetText(t.text or "")
	a.sub:SetText(t.sub or "")
	a.turn, a.yards = turn, yards
end

---------------------------------------------------------------------------
-- The world map (phase 2): the next steps numbered, their objectives' areas shaded
---------------------------------------------------------------------------

-- The player (2026-11-19): "shaded areas with numbers indicating which step they're for". On the
-- route's own zone map, while the tracker is open: a numbered dot at each step still to do (the
-- tracker's Step numbers; hover for what it is, click for the game's pin), and over each kill or loot
-- objective the area its mobs or objects are in (the current step gold, the rest Spellmind's purple).
-- Drawn on the map's canvas, under the map's own pins (Questie's spawn marks stay on top).
RT.MAP_STEPS = 12
RT.DOT = 18
local AREA_TEX = "Interface\\AddOns\\Spellmind\\Media\\Area"
local DOT_TEX = "Interface\\AddOns\\Spellmind\\Media\\Dot"
local marks = { areas = {}, dots = {}, shown = 0 }
RT.marks = marks

-- Above the map's own art, under its points of interest (Questie's marks among them): the map gives
-- each kind of pin its frame level (seen in game, 2026-11-19: a layer 2 levels over the canvas was
-- under the map's art, and nothing showed).
RT.MAP_POI_LEVEL = "PIN_FRAME_LEVEL_AREA_POI"
local function LayerLevel(W, canvas)
	local m = type(W.GetPinFrameLevelsManager) == "function" and Try(W.GetPinFrameLevelsManager, W) or nil
	local lvl = type(m) == "table" and type(m.GetValidFrameLevel) == "function" and tonumber((Try(m.GetValidFrameLevel, m, RT.MAP_POI_LEVEL))) or nil
	if lvl then return math.max(1, lvl - 1) end
	return (tonumber((canvas:GetFrameLevel())) or 1) + 100
end
local function Layer(W, canvas)
	local l = marks.layer
	if not l then
		l = CreateFrame("Frame", "SpellmindRouteMap", canvas)
		l:SetAllPoints(canvas)
		local wait = 0
		l:SetScript("OnUpdate", function(_, dt)
			wait = wait - (tonumber(dt) or 0)
			if wait > 0 then return end
			wait = RT.LINE_TICK
			pcall(RT.MapLive)
		end)
		marks.layer = l
	end
	l:SetFrameLevel(LayerLevel(W, canvas))
	return l
end
local function AreaTex(layer, k)
	local t = marks.areas[k]
	if not t then
		t = layer:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(AREA_TEX)
		marks.areas[k] = t
	end
	return t
end
local function Dot(layer, k, pool)
	pool = pool or marks.dots
	local d = pool[k]
	if d then return d end
	d = CreateFrame("Button", nil, layer)
	d:SetSize(RT.DOT, RT.DOT)
	d.tex = d:CreateTexture(nil, "ARTWORK")
	d.tex:SetAllPoints(d)
	d.tex:SetTexture(DOT_TEX)
	d.num = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.num:SetPoint("CENTER", d, "CENTER", 0, 0)
	d:SetScript("OnEnter", function(self)
		if GameTooltip and self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tip[1])
			for k = 2, #self.tip do GameTooltip:AddLine(self.tip[k], 1, 1, 1, true) end
			GameTooltip:Show()
			return
		end
		if not GameTooltip or not self.stop then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Step " .. self.index)
		for _, gr in ipairs(RT.Groups(self.stop)) do GameTooltip:AddLine(RT.GroupText(gr), 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	d:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	pool[k] = d
	return d
end

-- A world spot on the map shown (0-100), or nil when it's off that map.
local function OnMap(world, mapID)
	local M = rawget(_G, "C_Map")
	if not world or not mapID or type(M) ~= "table" or type(M.GetMapPosFromWorldPos) ~= "function" then return nil end
	local V = rawget(_G, "CreateVector2D")
	local v = type(V) == "function" and V(world.x, world.y) or { x = world.x, y = world.y }
	local ok, _, pos = pcall(M.GetMapPosFromWorldPos, world.c, v, mapID)
	if not ok or type(pos) ~= "table" then return nil end
	local x, y
	if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x * 100, y * 100
end
-- A world spot on a map's coordinates (0-100), off the map too (for the edge toward it).
local function OnMapRaw(world, mapID)
	local M = rawget(_G, "C_Map")
	if not world or not mapID or type(M) ~= "table" or type(M.GetMapPosFromWorldPos) ~= "function" then return nil end
	local V = rawget(_G, "CreateVector2D")
	local v = type(V) == "function" and V(world.x, world.y) or { x = world.x, y = world.y }
	local ok, _, pos = pcall(M.GetMapPosFromWorldPos, world.c, v, mapID)
	if not ok or type(pos) ~= "table" then return nil end
	local x, y
	if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x * 100, y * 100
end
-- Where the line from (x1, y1), on the map, to (x2, y2), off it, crosses its edge (kept 3% in).
RT.EDGE_IN = 3
local function Clip(x1, y1, x2, y2)
	local lo, hi = RT.EDGE_IN, 100 - RT.EDGE_IN
	local t = 1
	local dx, dy = x2 - x1, y2 - y1
	if dx > 0 and x2 > hi then t = math.min(t, (hi - x1) / dx) elseif dx < 0 and x2 < lo then t = math.min(t, (lo - x1) / dx) end
	if dy > 0 and y2 > hi then t = math.min(t, (hi - y1) / dy) elseif dy < 0 and y2 < lo then t = math.min(t, (lo - y1) / dy) end
	if t <= 0 then return nil end
	return x1 + dx * t, y1 + dy * t
end
marks.legs = {}
marks.legsShown = 0

RT.LINE_TICK = 0.1 -- seconds between moves of the line from the player
marks.lines = {}
marks.linesShown = 0
-- The same width on screen at any zoom (the map's canvas scales its children).
local function Scale()
	local W = rawget(_G, "WorldMapFrame")
	local s = W and type(W.GetCanvasScale) == "function" and tonumber((Try(W.GetCanvasScale, W))) or nil
	return (s and s > 0) and s or 1
end
local function MapLine(layer, x1, y1, x2, y2, r, g, b, a, thick)
	marks.linesShown = marks.linesShown + 1
	local l = marks.lines[marks.linesShown]
	if not l then
		l = layer:CreateLine(nil, "ARTWORK")
		marks.lines[marks.linesShown] = l
	end
	l:SetThickness(thick / Scale())
	l:SetColorTexture(r, g, b, a)
	l:SetStartPoint("TOPLEFT", layer, x1, -y1)
	l:SetEndPoint("TOPLEFT", layer, x2, -y2)
	l:Show()
	return l
end
-- The player on the map shown (canvas units), or nil.
local function PlayerOnMap(mapID, route, cw, ch)
	local here = RT.Here()
	if here and here.map == mapID then return { here.x / 100 * cw, here.y / 100 * ch } end
	local x, y = OnMap(RT.PlayerWorld(), mapID)
	if x then return { x / 100 * cw, y / 100 * ch } end
	return nil
end

-- Drawn again when the map opens, changes map or changes size.
local hooked
local function Hook(W)
	if hooked then return end
	hooked = true
	local function Again() pcall(RT.DrawMap) end
	if type(W.HookScript) == "function" then W:HookScript("OnShow", Again) end
	if type(W.OnMapChanged) == "function" then hooksecurefunc(W, "OnMapChanged", Again) end
	if type(W.OnCanvasSizeChanged) == "function" then hooksecurefunc(W, "OnCanvasSizeChanged", Again) end
end

function RT.DrawMap()
	local W = rawget(_G, "WorldMapFrame")
	if type(W) ~= "table" or type(W.GetCanvas) ~= "function" then return end
	Hook(W)
	local canvas = W:GetCanvas()
	if not canvas then return end
	local layer = Layer(W, canvas)
	for _, t in pairs(marks.areas) do t:Hide() end
	for _, d in pairs(marks.dots) do d:Hide(); d.stop = nil end
	for _, d in pairs(marks.legs) do d:Hide(); d.tip = nil end
	for _, l in pairs(marks.lines) do l:Hide() end
	marks.shown, marks.legsShown, marks.linesShown, marks.live = 0, 0, 0, nil
	local route = R.route
	if not RT.Shown() or not RT.MapOn() or not W:IsShown() or not route or not route.map then return end
	local shownMap = W:GetMapID()
	local onRouteMap = shownMap == route.map
	local cw, ch = tonumber((canvas:GetWidth())) or 0, tonumber((canvas:GetHeight())) or 0
	if cw <= 0 or ch <= 0 then return end
	local cur = RT.Current()
	local base = tonumber((layer:GetFrameLevel())) or 1
	local na, nd = 0, 0
	local path = {} -- the steps' own spots (canvas units), in order, for the lines
	-- Dots already placed (canvas units): one that would cover another sits beside it (the player,
	-- 2026-11-19: a pick up and its turn-in at Sven Yorgen, two steps apart, were one on the other).
	local placed = {}
	local function Free(px, py)
		local moved = true
		while moved do
			moved = false
			for _, q in ipairs(placed) do
				if math.abs(q[1] - px) < RT.DOT and math.abs(q[2] - py) < RT.DOT then px, moved = q[1] + RT.DOT + 2, true; break end
			end
		end
		placed[#placed + 1] = { px, py }
		return px, py
	end
	local going = RT.Traveling(route)
	for i, s in ipairs(going and {} or route.stops or {}) do
		if nd >= RT.MAP_STEPS then break end
		if RT.StopMap(s) == shownMap and not RT.StopDone(s) and not (R.routeSkip and R.routeSkip[s.key]) then
			local now = s == cur
			local r, g, b = now and 1 or 0.62, now and 0.82 or 0.49, now and 0 or 1
			for _, goal in ipairs(s.goals) do
				if goal.kind == "do" and goal.rx and not RT.GoalDone(goal) then
					na = na + 1
					local t = AreaTex(layer, na)
					t:ClearAllPoints()
					t:SetPoint("CENTER", layer, "TOPLEFT", goal.ax / 100 * cw, -goal.ay / 100 * ch)
					t:SetSize(2 * goal.rx / 100 * cw, 2 * goal.ry / 100 * ch)
					t:SetVertexColor(r, g, b, now and 0.55 or 0.35)
					t:Show()
				end
			end
			nd = nd + 1
			local d = Dot(layer, nd)
			d:ClearAllPoints()
			path[#path + 1] = { s.x / 100 * cw, s.y / 100 * ch, now = now }
			local px, py = Free(s.x / 100 * cw, s.y / 100 * ch)
			d:SetPoint("CENTER", layer, "TOPLEFT", px, -py)
			d.tex:SetVertexColor(r, g, b)
			d.num:SetText(tostring(i))
			if now then d.num:SetTextColor(0.1, 0.05, 0) else d.num:SetTextColor(1, 1, 1) end
			d.stop, d.index = s, i
			d:SetFrameLevel(base + (now and 3 or 1))
			d:Show()
		end
	end
	marks.shown = nd
	local lines = RT.LinesOn()
	local me = lines and PlayerOnMap(shownMap, route, cw, ch) or nil
	-- A line from a point to another along a trail's points between them (world spots) when there's one,
	-- else straight; live: its first part is the one that follows the player.
	local function Along(from, to, interior, r, g, b, live)
		local pts = {}
		for _, w in ipairs(interior or {}) do
			local x, y = OnMapRaw(w, shownMap)
			if x then pts[#pts + 1] = { x / 100 * cw, y / 100 * ch } end
		end
		pts[#pts + 1] = to
		local at = from
		for k, c in ipairs(pts) do
			local first = live and k == 1
			local l = MapLine(layer, at[1], at[2], c[1], c[2], r, g, b, first and 0.9 or 0.7, live and 3 or 2)
			if first then marks.live = { line = l, to = c } end
			at = c
		end
	end
	local t = RT.ArrowTarget()
	local away = t and t.zone
	-- The route's line (the player, 2026-11-19, as NeverQuestAlone draws its): from the player to the
	-- current step in gold, kept live as they move, then on through the next steps in purple.
	if lines then
		if me and path[1] and not away then Along(me, path[1], path[1].now and t and t.path or nil, 1, 0.82, 0, true) end
		for k = 1, #path - 1 do MapLine(layer, path[k][1], path[k][2], path[k + 1][1], path[k + 1][2], 0.62, 0.49, 1, 0.7, 2) end
	end
	-- The way somewhere else (the player, 2026-11-19: with the pins gone a chosen zone showed nothing, and
	-- a prep step in another zone left the map empty): the target's legs, each a green » on the maps
	-- that show it, joined by the green line from the player; where the way leaves this map, a » on its
	-- edge toward it.
	local t = RT.ArrowTarget()
	local legs = t and t.legs
	if not legs or #legs == 0 then return end
	local legPts = {}
	local prev = me and { me[1] / cw * 100, me[2] / ch * 100 } or nil
	local stepHere = t.step and RT.StopMap(t.step) == shownMap
	for _, leg in ipairs(legs) do
		local x, y = OnMap(leg.world, shownMap)
		local edge = false
		if x and leg.dest and stepHere then
			-- Its numbered dot is here already: the line ends on it, no second mark.
			legPts[#legPts + 1] = { x / 100 * cw, y / 100 * ch, path = leg.path }
			break
		end
		if not x and prev then
			-- Off this map: where the line to it crosses the edge.
			local rx, ry = OnMapRaw(leg.world, shownMap)
			if rx then x, y = Clip(prev[1], prev[2], rx, ry); edge = x ~= nil end
		end
		-- Too close to the last leg's mark to be its own (the player, 2026-11-19: on the continent's map the
		-- landing at Darkshire and the step there were one on the other, and the step was pushed aside
		-- over Deadwind Pass): it joins that mark, its words added to the tooltip.
		local last = marks.legsShown > 0 and marks.legs[marks.legsShown] or nil
		if x and last and last.at and math.abs(last.at[1] - x / 100 * cw) < RT.DOT and math.abs(last.at[2] - y / 100 * ch) < RT.DOT then
			local tip = { last.tip and last.tip[1] or "" }
			for k = 2, #(last.tip or {}) do tip[#tip + 1] = last.tip[k] end
			for _, line in ipairs(edge and { "Toward " .. (leg.zone or "the next zone") } or leg.tip or {}) do tip[#tip + 1] = line end
			last.tip = tip
			-- How many legs it holds (the player's idea: a number on stacked marks, their tooltips joined).
			last.count = (last.count or 1) + 1
			last.num:SetText("\194\187" .. last.count)
			if edge then break end
		elseif x then
			legPts[#legPts + 1] = { x / 100 * cw, y / 100 * ch, path = leg.path }
			marks.legsShown = marks.legsShown + 1
			local d = Dot(layer, marks.legsShown, marks.legs)
			d.at, d.count = { x / 100 * cw, y / 100 * ch }, 1
			d:ClearAllPoints()
			local px, py = Free(x / 100 * cw, y / 100 * ch)
			d:SetPoint("CENTER", layer, "TOPLEFT", px, -py)
			d.tex:SetVertexColor(0.3, 0.95, 0.4)
			d.num:SetText("\194\187")
			d.num:SetTextColor(0.05, 0.15, 0.05)
			d.tip = edge and { "Toward " .. (leg.zone or "the next zone"), leg.tip and leg.tip[1] or nil } or leg.tip
			d.edge = edge or nil
			d:SetFrameLevel(base + 4)
			d:Show()
			prev = { x, y }
			if edge then break end
		end
	end
	-- Its line, in green: from the player (live) through each leg this map shows.
	if lines and #legPts > 0 then
		if me then Along(me, legPts[1], legPts[1].path, 0.3, 0.95, 0.4, true) end
		for k = 1, #legPts - 1 do Along(legPts[k], legPts[k + 1], legPts[k + 1].path, 0.3, 0.95, 0.4) end
	end
end

-- The line from the player, moved with them a few times a second while the map is open.
function RT.MapLive()
	local live = marks.live
	local W = rawget(_G, "WorldMapFrame")
	if not live or type(W) ~= "table" or not W:IsShown() then return end
	local canvas = W:GetCanvas()
	local cw, ch = tonumber((canvas:GetWidth())) or 0, tonumber((canvas:GetHeight())) or 0
	local me = PlayerOnMap(W:GetMapID(), R.route, cw, ch)
	if not me then live.line:Hide(); return end
	live.line:SetStartPoint("TOPLEFT", marks.layer, me[1], -me[2])
	live.line:Show()
end

---------------------------------------------------------------------------
-- For the AI (the advisor part's route): the plan the player sees, so every answer starts from it
---------------------------------------------------------------------------

-- The player (2026-11-19): with the route in place, "Plan my next hour" became "Review my route". The
-- steps in words without their live counts (the quests part has those; a count in here would send the
-- part again at every kill).
RT.AI_STEPS = 10
local function Plain(s)
	local bits = {}
	for _, gr in ipairs(RT.Groups(s)) do
		local names = {}
		for _, g in ipairs(gr.goals) do names[#names + 1] = g.title .. ((gr.kind == "pickup" and g.level) and (" (level " .. g.level .. ")") or "") end
		local list = table.concat(names, ", ")
		if gr.kind == "pickup" then bits[#bits + 1] = "pick up " .. list .. (gr.to and (" from " .. gr.to) or "")
		elseif gr.kind == "turnin" then bits[#bits + 1] = "turn in " .. list .. (gr.to and (" to " .. gr.to) or "")
		else
			local g = gr.goals[1]
			bits[#bits + 1] = "do " .. list .. (g.buy and (" (buy " .. g.buy .. (g.from and (" from " .. g.from) or "") .. ")") or "")
		end
	end
	local at = (tonumber(s.x) and tonumber(s.y)) and (" (at " .. math.floor(s.x + 0.5) .. ", " .. math.floor(s.y + 0.5) .. ")") or ""
	return table.concat(bits, "; ") .. at
end
function RT.Part()
	if not RT.On() then return nil end
	local route = R.route
	if not route or route.nowhere then return nil end
	local O = ns.State.JSON.O
	local steps, skipped = {}, 0
	local _, i = RT.Current()
	local _, total = RT.Progress()
	for k, s in ipairs(route.stops or {}) do
		local skip = R.routeSkip and R.routeSkip[s.key]
		if skip then skipped = skipped + 1 end
		if #steps < RT.AI_STEPS and not RT.StopDone(s) and not skip then
			steps[#steps + 1] = ns.State.Text(k .. ". " .. RT.StopZone(s) .. Plain(s) .. (RT.StopLow(s) and " (little XP for the walk: worth skipping?)" or ""), 400)
		end
	end
	local later = {}
	for _, t in ipairs(route.later or {}) do if #later < 6 then later[#later + 1] = ns.State.Text(t, 80) end end
	local going = RT.Traveling(route)
	return O("zone", route.zone, "step", i, "of", total, "steps", #steps > 0 and steps or nil,
		"later", #later > 0 and later or nil, "skipped", skipped > 0 and skipped or nil,
		"headingTo", going and going.zone or nil)
end

---------------------------------------------------------------------------
-- Dungeon prep (the player, 2026-11-19): every quest for one dungeon, the questlines that open them,
-- across zones, then the way in; after the run, the turn-ins
---------------------------------------------------------------------------

-- Where each dungeon's way in is (Spellmind's own table, approximate: the game didn't say where its
-- entrance markers come from): { zone, x, y } by the dungeon's name. Replaced by where the player
-- really stood just outside, the first time they go in (SpellmindDB.routeEntrances).
RT.ENTRANCES = {
	["The Deadmines"] = { "Westfall", 42.6, 71.8 },
	["The Stockade"] = { "Stormwind City", 41.0, 57.5 },
	["Gnomeregan"] = { "Dun Morogh", 24.4, 39.8 },
	["Shadowfang Keep"] = { "Silverpine Forest", 44.8, 67.8 },
	["Scarlet Monastery"] = { "Tirisfal Glades", 84.5, 31.0 },
	["Uldaman"] = { "Badlands", 42.4, 13.0 },
	["The Temple of Atal'Hakkar"] = { "Swamp of Sorrows", 69.7, 53.6 },
	["Ragefire Chasm"] = { "Orgrimmar", 52.8, 49.1 },
	["Wailing Caverns"] = { "The Barrens", 46.0, 36.4 },
	["Razorfen Kraul"] = { "The Barrens", 42.3, 89.9 },
	["Razorfen Downs"] = { "The Barrens", 49.0, 93.9 },
	["Blackfathom Deeps"] = { "Ashenvale", 14.1, 13.9 },
	["Zul'Farrak"] = { "Tanaris", 39.2, 21.3 },
	["Maraudon"] = { "Desolace", 29.2, 62.5 },
	["The Hall of Thanes"] = { "Dun Morogh", 47.0, 52.0 },
}

-- The way in: the player's own (learned), else the table's. { map, x, y, zoneName, learned }.
function RT.Entrance(name)
	local key = DG().Norm(name)
	local mine = ns.db and type(ns.db.routeEntrances) == "table" and ns.db.routeEntrances[key]
	if type(mine) == "table" and mine.map then return { map = mine.map, x = mine.x, y = mine.y, zoneName = mine.zone, learned = true } end
	for n, e in pairs(RT.ENTRANCES) do
		if DG().Norm(n) == key then
			local map = DG().MapNamed(e[1])
			if map then return { map = map, x = e[2], y = e[3], zoneName = e[1] } end
		end
	end
	return nil
end

-- Kept a few times a second while the route is on: where the player stands outside, so that going
-- into a dungeon notes its way in.
-- A flight flown while the route is on: its time kept, from the known path nearest where it began to
-- the one nearest where it landed (each within RT.FLIGHT_NEAR yards).
RT.FLIGHT_NEAR = 150
local function NearestFlight(w)
	local best, bd
	for _, f in ipairs(RT.Flights()) do
		if w and f.c == w.c then local d = Dist(f, w); if d <= RT.FLIGHT_NEAR and (not bd or d < bd) then best, bd = f, d end end
	end
	return best
end
function RT.NoteFlight()
	local onTaxi = Try(rawget(_G, "UnitOnTaxi"), "player") and true or false
	local w = RT.PlayerWorld()
	if onTaxi and not R.routeTaxi then
		local from = R.routeGround and NearestFlight(R.routeGround)
		R.routeTaxi = { from = from and from.name, at = GetTime() }
	elseif not onTaxi and R.routeTaxi then
		local to = NearestFlight(w)
		local t = R.routeTaxi
		R.routeTaxi = nil
		if t.from and to and to.name ~= t.from then
			ns.db.routeFlightTimes = type(ns.db.routeFlightTimes) == "table" and ns.db.routeFlightTimes or {}
			ns.db.routeFlightTimes[t.from .. ">" .. to.name] = math.floor(GetTime() - t.at + 0.5)
		end
		if R.routeAfterTaxi then RT.Landed() end
	end
	if not onTaxi then R.routeGround = w end
end

function RT.NoteOutside()
	pcall(RT.NoteFlight)
	local here = RT.Here()
	if not here then return end
	local prev = R.routeOutside
	if prev and prev.map ~= here.map and not Try(rawget(_G, "UnitOnTaxi"), "player") then
		local a, b = World(prev.map, prev.x, prev.y), World(here.map, here.x, here.y)
		if a and b and a.c == b.c and Dist(a, b) <= RT.CROSS_YARDS then RT.LearnCrossing(prev, here) end
	end
	R.routeOutside = { map = here.map, x = here.x, y = here.y, zone = here.zone }
	pcall(RT.NoteTrail, World(here.map, here.x, here.y))
end
local function Inside()
	local inst, kind = Try(rawget(_G, "IsInInstance"))
	if not inst or (kind ~= "party" and kind ~= "raid") then return nil end
	local name = Try(rawget(_G, "GetInstanceInfo"))
	return type(name) == "string" and name or nil
end
function RT.OnEnterWorld()
	local name = Inside()
	if not name then return end
	R.routeEntered = R.routeEntered or {}
	R.routeEntered[DG().Norm(name)] = true
	local out = R.routeOutside
	if out and ns.db then
		ns.db.routeEntrances = type(ns.db.routeEntrances) == "table" and ns.db.routeEntrances or {}
		ns.db.routeEntrances[DG().Norm(name)] = { map = out.map, x = out.x, y = out.y, zone = out.zone }
	end
	RT.Refresh()
end
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do ns.On(ev, function() pcall(RT.OnEnterWorld) end) end
-- Been in this session (or every quest for it done: the run is over).
function RT.Entered(name)
	return (R.routeEntered and R.routeEntered[DG().Norm(name)]) and true or false
end

-- A quest's three places, wherever they are: its giver, its objectives' area, its finisher; each
-- { x, y, map (nil when it's the player's), zoneName } or nil.
local function SpotOn(area, x, y, here)
	if not area or not x or not y then return nil end
	if here and area == here.area then return { x = x, y = y } end
	local map = DG().MapForArea(area)
	if not map then return nil end
	local M = rawget(_G, "C_Map")
	local zname = M and type(M.GetAreaInfo) == "function" and Try(M.GetAreaInfo, area) or nil
	return { x = x, y = y, map = map, zoneName = zname }
end
function RT.QuestPlaces(Q, id, here)
	local out = {}
	local _, _, g = DG().Giver(Q, id)
	if g then out.giver = SpotOn(g.zone, g.x, g.y, here); if out.giver then out.giver.name, out.giver.npc = g.name, g.npc end end
	local area = tonumber((Try(Q.Quest.zoneOrSort, id)))
	if area and area > 0 then
		local c = RT.Area(RT.ObjectiveSpots(Q, id, area))
		if c then out.area = SpotOn(area, c.x, c.y, here); if out.area then out.area.rx, out.area.ry, out.area.cx, out.area.cy = c.rx, c.ry, c.x, c.y end end
	end
	local fin = RT.TurnIn(Q, id, -1)
	if fin and fin.zone then
		local at = RT.TurnIn(Q, id, fin.zone)
		if at and at.spot then out.fin = SpotOn(tonumber(fin.zone), at.spot.x, at.spot.y, here); if out.fin then out.fin.name = at.name end end
	end
	return out
end

-- The questline from a step to a dungeon quest: the quests between them, in order (follow-ups walked
-- forward, at most eight deep), or nil.
local function Path(from, to)
	local seen, queue = { [from] = true }, { { from } }
	while #queue > 0 do
		local p = table.remove(queue, 1)
		local last = p[#p]
		if last == to then return p end
		if #p < 9 then
			for _, f in ipairs(RT.FollowUps(last)) do
				if not seen[f] then seen[f] = true; local q = {}; for k, v in ipairs(p) do q[k] = v end; q[#q + 1] = f; queue[#queue + 1] = q end
			end
		end
	end
	return nil
end

-- The prep route: R.route as RT.Build makes it (stops, rules), with prep = the dungeon's name.
function RT.BuildPrep(name)
	local here = RT.Here()
	local route = { stops = {}, elsewhere = {}, later = {}, built = GetTime(), prep = name }
	R.route = route
	if not here then route.nowhere = true; return route end
	route.zone, route.map, route.area = here.zone, here.map, here.area
	local Q = L()
	route.db = Q ~= nil
	local qs = Q and DG().Quests(name)
	if not qs then route.noData = true; return route end
	local log = ReadLog()
	local raw, chains, extra = {}, {}, {}
	local placed = {}
	local function Place(kind, id, title, spot, to, x)
		if not spot then return false end
		local g = { kind = kind, q = id, title = title, to = to }
		for k, v in pairs(x or {}) do g[k] = v end
		raw[#raw + 1] = { x = spot.x, y = spot.y, map = spot.map, zoneName = spot.zoneName, goals = { g } }
		placed[kind .. ":" .. id] = true
		return true
	end
	-- One quest, as far as it goes: picked up (unless in the log), its objectives (when outside), its
	-- turn-in (unless it's this dungeon's and not done yet: that's after the run).
	local function Quest(id, title, dungeonQuest)
		local p = RT.QuestPlaces(Q, id, here)
		if not log[id] and not Done(id) then
			local lv = tonumber((Try(Q.Quest.questLevel, id)))
			if not Place("pickup", id, title, p.giver, p.giver and p.giver.name, { fromID = p.giver and p.giver.npc, level = lv }) then
				route.elsewhere[""] = route.elsewhere[""] or {}
				table.insert(route.elsewhere[""], { kind = "pickup", q = id, title = title })
				return false
			end
		end
		if p.area and not (log[id] and Complete(id)) then
			Place("do", id, title, p.area, nil, { ax = p.area.cx, ay = p.area.cy, rx = p.area.rx, ry = p.area.ry })
		end
		if not dungeonQuest or (log[id] and Complete(id)) then Place("turnin", id, title, p.fin, p.fin and p.fin.name) end
		return true
	end
	local dungeonIds = {}
	-- This dungeon's quests open now, and the questlines to the locked ones.
	for _, q in ipairs(qs.pickup) do
		if not q.at then
			if q.after or q.first then
				-- The chain's step to do now, then each quest after it up to this one.
				local start = q.first and q.id or nil
				if not start then
					for _, c in ipairs(qs.chains) do for _, o in ipairs(c.opens) do if o.id == q.id then start = c.id end end end
				end
				local path = start and Path(start, q.id) or (q.first and { q.id }) or nil
				for k, step in ipairs(path or {}) do
					if not placed["pickup:" .. step] and not placed["turnin:" .. step] then
						local last = k == #path and not q.first
						Quest(step, DG().Name(Q, step) or ("quest " .. step), last)
						if last then dungeonIds[#dungeonIds + 1] = step end
					end
					if k > 1 then chains[#chains + 1] = { path[k - 1], step } end
				end
			else
				Quest(q.id, q.name, true)
				dungeonIds[#dungeonIds + 1] = q.id
			end
		else
			route.later[#route.later + 1] = q.name
		end
	end
	-- Its quests already in the log: their turn-ins once done (after the run).
	for id, q in pairs(log) do
		if tonumber((Try(Q.Quest.zoneOrSort, id))) == qs.area then
			dungeonIds[#dungeonIds + 1] = id
			Quest(id, q.title or ("quest " .. id), true)
		end
	end
	-- The way in.
	local door = RT.Entrance(name)
	if door then
		local spot = door.map == here.map and { x = door.x, y = door.y } or door
		raw[#raw + 1] = { x = spot.x, y = spot.y, map = spot.map, zoneName = spot.zoneName,
			goals = { { kind = "enter", q = 0, title = name, to = door.learned and nil or ("around " .. math.floor(door.x + 0.5) .. ", " .. math.floor(door.y + 0.5) .. " in " .. (door.zoneName or "?")) } } }
		for _, id in ipairs(dungeonIds) do
			if not log[id] then extra[#extra + 1] = { "pickup:" .. id, "enter:0" } end
			extra[#extra + 1] = { "enter:0", "turnin:" .. id }
		end
	end
	-- As the questing route does: what's done never shows; close ones are one stop when they can be.
	local keep = {}
	for _, s in ipairs(raw) do if not RT.StopDone(s) then keep[#keep + 1] = s end end
	local function Rules(stops)
		local rules = RT.Rules(stops, chains)
		local have = {}
		for _, s in ipairs(stops) do for _, g in ipairs(s.goals) do have[g.kind .. ":" .. g.q] = true end end
		for _, r in ipairs(extra) do if have[r[1]] and have[r[2]] then rules[#rules + 1] = r end end
		return rules
	end
	local rules = Rules(keep)
	local stops, stopOf = {}, {}
	for _, s in ipairs(keep) do
		local joined
		for _, t in ipairs(stops) do
			if RT.Yards(s, t, here) <= RT.GROUP_YARDS then
				for _, g in ipairs(s.goals) do stopOf[g.kind .. ":" .. g.q] = t end
				if RT.Orderable(stops, rules, stopOf) then joined = t; break end
			end
		end
		if joined then
			for _, g in ipairs(s.goals) do joined.goals[#joined.goals + 1] = g end
		else
			stops[#stops + 1] = s
			for _, g in ipairs(s.goals) do stopOf[g.kind .. ":" .. g.q] = s end
		end
	end
	for _, s in ipairs(stops) do
		table.sort(s.goals, function(a, b) return (RANK[a.kind] or 9) < (RANK[b.kind] or 9) end)
		local keys = {}
		for _, g in ipairs(s.goals) do keys[#keys + 1] = g.kind .. ":" .. g.q end
		s.key = table.concat(keys, ",")
	end
	rules = Rules(stops)
	-- Across zones by the time to get there (the player, 2026-11-19: Duskwood, Wetlands, then Stormwind
	-- zig-zagged): the way there's own fastest path (flights, crossings, tram, boats), as yards walked at
	-- the player's speed; within a zone, the yards. Each pair worked out once.
	local speed = RT.Speed()
	local memo = {}
	local function Cost(p, q)
		local pm, qm = p.map or here.map, q.map or here.map
		if pm == qm then return RT.Yards(p, q, here) end
		memo[p] = memo[p] or {}
		local c = memo[p][q]
		if c then return c end
		local _, minutes = RT.Plan({ map = pm, x = p.x, y = p.y }, { map = qm, x = q.x, y = q.y }, speed)
		c = minutes and minutes * 60 * speed or RT.Yards(p, q, here) * RT.PATH_FACTOR
		memo[p][q] = c
		return c
	end
	route.stops = RT.Order(stops, { x = here.x, y = here.y }, here, rules, Cost)
	route.rules = rules
	return route
end

---------------------------------------------------------------------------
-- The way there (the player, 2026-11-19: "fly to Ironforge, walk through Loch Modan and north to
-- Wetlands: the map and the markers should show that"): the fastest path over walking within a zone,
-- crossings between zones, the flight paths the character knows, the tram and the boats, and the
-- hearthstone; shown leg by leg
---------------------------------------------------------------------------

-- Where one zone meets the next (Spellmind's own, approximate: the game has no such data): { zone, x,
-- y, zone, x, y, name, how ("road", "tram", "boat"), minutes (a tram's or a boat's) }. A crossing the
-- player walks is noted exactly (SpellmindDB.routeCrossings) and replaces the one here.
RT.LINKS = {
	{ "Stormwind City", 70.5, 89.5, "Elwynn Forest", 32.0, 50.0, name = "Stormwind's gates" },
	{ "Elwynn Forest", 20.8, 81.0, "Westfall", 61.5, 17.0, name = "the road to Westfall" },
	{ "Elwynn Forest", 31.8, 93.0, "Duskwood", 21.5, 8.5, name = "the bridge to Duskwood" },
	{ "Elwynn Forest", 91.0, 72.5, "Redridge Mountains", 2.7, 75.8, name = "the road to Redridge" },
	{ "Redridge Mountains", 4.0, 92.0, "Duskwood", 92.0, 25.0, name = "Three Corners" },
	{ "Redridge Mountains", 41.8, 6.5, "Burning Steppes", 66.0, 79.0, name = "the road to Burning Steppes" },
	{ "Westfall", 68.5, 71.0, "Duskwood", 8.5, 58.0, name = "the road to Duskwood" },
	{ "Duskwood", 36.0, 95.0, "Stranglethorn Vale", 38.0, 4.0, name = "the road to Stranglethorn" },
	{ "Duskwood", 88.0, 80.0, "Deadwind Pass", 30.0, 30.0, name = "Deadwind Pass" },
	{ "Deadwind Pass", 60.0, 60.0, "Swamp of Sorrows", 5.0, 60.0, name = "the road to the Swamp of Sorrows" },
	{ "Swamp of Sorrows", 32.0, 98.0, "Blasted Lands", 50.0, 2.0, name = "the road to the Blasted Lands" },
	{ "Ironforge", 15.5, 85.5, "Dun Morogh", 53.5, 34.6, name = "the Gates of Ironforge" },
	{ "Dun Morogh", 85.8, 51.0, "Loch Modan", 21.0, 68.0, name = "the North Gate Pass" },
	{ "Loch Modan", 24.5, 1.5, "Wetlands", 57.5, 72.5, name = "Dun Algaz" },
	{ "Loch Modan", 47.0, 96.0, "Badlands", 50.0, 5.0, name = "the road to the Badlands" },
	{ "Wetlands", 53.7, 11.6, "Arathi Highlands", 44.5, 92.0, name = "Thandol Span" },
	{ "Arathi Highlands", 20.0, 30.0, "Hillsbrad Foothills", 86.0, 45.0, name = "the road to Hillsbrad" },
	{ "Hillsbrad Foothills", 13.0, 45.0, "Silverpine Forest", 68.0, 78.0, name = "the road to Silverpine" },
	{ "Silverpine Forest", 45.0, 5.0, "Tirisfal Glades", 55.0, 90.0, name = "the road to Tirisfal" },
	{ "Stormwind City", 64.0, 8.0, "Ironforge", 76.6, 51.0, name = "the Deeprun Tram", how = "tram", minutes = 2 },
	{ "Wetlands", 4.8, 63.0, "Darkshore", 32.5, 44.0, name = "the boat between Menethil Harbor and Auberdine", how = "boat", minutes = 6 },
	{ "Wetlands", 4.8, 57.5, "Dustwallow Marsh", 71.6, 56.3, name = "the boat between Menethil Harbor and Theramore", how = "boat", minutes = 6 },
	{ "Stranglethorn Vale", 25.8, 73.0, "The Barrens", 63.6, 38.6, name = "the boat between Booty Bay and Ratchet", how = "boat", minutes = 6 },
	{ "Darkshore", 33.0, 40.0, "Teldrassil", 55.0, 96.0, name = "the boat between Auberdine and Rut'theran", how = "boat", minutes = 3 },
}
RT.CROSS_YARDS = 60 -- one tick's move across a border, at most (a loading screen or a flight is no crossing)
RT.LEARNED_NEAR = 400 -- a learned crossing replaces a written one this close, for the same two zones

-- A crossing the player walked: kept, replacing one near it for the same two zones.
function RT.LearnCrossing(from, to)
	ns.db.routeCrossings = type(ns.db.routeCrossings) == "table" and ns.db.routeCrossings or {}
	local list = ns.db.routeCrossings
	local a = World(from.map, from.x, from.y)
	for k = #list, 1, -1 do
		local c = list[k]
		local same = (c.a.map == from.map and c.b.map == to.map) or (c.a.map == to.map and c.b.map == from.map)
		local w = same and World(c.a.map, c.a.x, c.a.y)
		if w and a and Dist(w, a) <= RT.LEARNED_NEAR then table.remove(list, k) end
	end
	list[#list + 1] = { a = { map = from.map, x = from.x, y = from.y }, b = { map = to.map, x = to.x, y = to.y } }
	R.routeLinks = nil
end

-- Every crossing, with its two sides' maps and world spots: the learned, then the written ones no
-- learned one replaces. Worked out once a session (and after a crossing is learned).
-- A zone's map by its name, or by the start of it ("Redridge" for Redridge Mountains, "Elwynn" for
-- Elwynn Forest: the flight paths' short names). Kept for the session.
function RT.ZoneMap(name)
	R.routeZoneMaps = R.routeZoneMaps or {}
	local hit = R.routeZoneMaps[name]
	if hit ~= nil then return hit or nil end
	local map = DG().MapNamed(name)
	if not map then
		local want = DG().Norm(name)
		local M = rawget(_G, "C_Map")
		local E = type(Enum) == "table" and Enum.UIMapType or {}
		for _, c in ipairs(M and Try(M.GetMapChildrenInfo, 947, E.Continent or 2, true) or {}) do
			for _, z in ipairs(Try(M.GetMapChildrenInfo, c.mapID, E.Zone or 3, true) or {}) do
				if not map and type(z) == "table" and type(z.name) == "string" and want ~= "" and DG().Norm(z.name):sub(1, #want) == want then map = z.mapID end
			end
		end
	end
	R.routeZoneMaps[name] = map or false
	return map
end

function RT.Links()
	if R.routeLinks then return R.routeLinks end
	local out = {}
	local function Side(map, x, y) local w = map and World(map, x, y); return w and { map = map, x = x, y = y, w = w } or nil end
	for _, c in ipairs(ns.db and type(ns.db.routeCrossings) == "table" and ns.db.routeCrossings or {}) do
		local a, b = Side(c.a.map, c.a.x, c.a.y), Side(c.b.map, c.b.x, c.b.y)
		if a and b then out[#out + 1] = { a = a, b = b, how = "road", learned = true } end
	end
	for _, l in ipairs(RT.LINKS) do
		local a, b = Side(DG().MapNamed(l[1]), l[2], l[3]), Side(DG().MapNamed(l[4]), l[5], l[6])
		if a and b then
			local replaced = false
			for _, m in ipairs(out) do
				if m.learned and ((m.a.map == a.map and m.b.map == b.map) or (m.a.map == b.map and m.b.map == a.map))
					and (Dist(m.a.w, a.w) <= RT.LEARNED_NEAR or Dist(m.a.w, b.w) <= RT.LEARNED_NEAR) then replaced = true end
			end
			if not replaced then out[#out + 1] = { a = a, b = b, name = l.name, how = l.how or "road", minutes = l.minutes, zoneA = l[1], zoneB = l[4] } end
		end
	end
	R.routeLinks = out
	return out
end

local function ZoneOf(map)
	local M = rawget(_G, "C_Map")
	local info = map and M and Try(M.GetMapInfo, map)
	return type(info) == "table" and info.name or nil
end

-- The fastest path from one spot to another ({ map, x, y }), as nodes with the way to each: nil when
-- no path is known (the crossings don't join the two zones).
function RT.Plan(from, to, speed)
	speed = speed or RT.RUN_SPEED
	local fw, tw = from.map and World(from.map, from.x, from.y), to.map and World(to.map, to.x, to.y)
	if not fw or not tw then return nil end
	local nodes = {}
	local function Node(n) nodes[#nodes + 1] = n; n.i = #nodes; return n end
	local s = Node({ kind = "start", map = from.map, w = fw })
	local d = Node({ kind = "dest", map = to.map, w = tw })
	for _, f in ipairs(RT.Flights()) do if f.map then Node({ kind = "fp", map = f.map, w = f, name = f.name, npc = f.npc }) end end
	local h = RT.Hearth()
	local hn = h and h.map and Node({ kind = "hearth", map = h.map, w = h, name = h.name }) or nil
	for _, l in ipairs(RT.Links()) do
		local a = Node({ kind = "link", map = l.a.map, w = l.a.w, link = l })
		local b = Node({ kind = "link", map = l.b.map, w = l.b.w, link = l })
		a.other, b.other = b, a
	end
	local function Walk(u, v) return Dist(u.w, v.w) * RT.PATH_FACTOR / speed / 60 end
	local dist, prev, how, done = {}, {}, {}, {}
	dist[s.i] = 0
	while true do
		local u, best
		for i, n in ipairs(nodes) do if not done[i] and dist[i] and (not best or dist[i] < best) then u, best = n, dist[i] end end
		if not u or u == d then break end
		done[u.i] = true
		local function Relax(v, cost, kind)
			if v ~= u and not done[v.i] and cost and (not dist[v.i] or best + cost < dist[v.i]) then dist[v.i], prev[v.i], how[v.i] = best + cost, u, kind end
		end
		for _, v in ipairs(nodes) do
			if v.map == u.map and v.w.c == u.w.c and v.kind ~= "hearth" then Relax(v, Walk(u, v), "walk") end
			if u.kind == "fp" and v.kind == "fp" and v.w.c == u.w.c then Relax(v, RT.FlightMinutes({ name = u.name, x = u.w.x, y = u.w.y }, { name = v.name, x = v.w.x, y = v.w.y }), "fly") end
		end
		if u.kind == "link" and u.other then Relax(u.other, u.link.minutes or Walk(u, u.other), u.link.how) end
		if u == s and hn then Relax(hn, RT.HEARTH_MINUTES, "hearth") end
	end
	if not dist[d.i] then return nil end
	local path = {}
	local n = d
	while n do table.insert(path, 1, { node = n, how = how[n.i], at = dist[n.i] }); n = prev[n.i] end
	return path, dist[d.i]
end

-- The path as legs to show and follow: { world, map, tip = { title, line }, zone, hearth }.
function RT.PlanLegs(path, destTip, destZone)
	local legs = {}
	for k = 2, #path do
		local p, n = path[k], path[k].node
		local nxt = path[k + 1]
		local walked = p.how == "walk" and path[k - 1].node.w and RT.TrailBetween(path[k - 1].node.w, n.w) or nil
		if n.kind == "dest" then
			legs[#legs + 1] = { path = walked, world = n.w, map = n.map, tip = destTip, zone = destZone, dest = true }
		elseif p.how == "hearth" then
			legs[#legs + 1] = { path = walked, world = n.w, map = n.map, hearth = true, tip = { "Use your hearthstone", "To " .. tostring(n.name) }, zone = ZoneOf(n.map) }
		elseif n.kind == "fp" and p.how == "fly" then
			legs[#legs + 1] = { path = walked, world = n.w, map = n.map, tip = { "Fly to " .. Short(n.name), "Land at the flight master there" }, zone = ZoneOf(n.map) }
		elseif n.kind == "fp" and nxt and nxt.how == "fly" then
			legs[#legs + 1] = { path = walked, world = n.w, map = n.map, tip = { (n.npc and (n.npc .. ", the flight master at ") or "Flight master at ") .. Short(n.name), "Fly to " .. Short(nxt.node.name) }, zone = ZoneOf(n.map) }
		elseif n.kind == "link" and nxt and nxt.node == n.other then
			-- The near side of a crossing (the far side is the same place): cross, or take the tram or boat.
			local l, into = n.link, ZoneOf(n.other.map) or "the next zone"
			local title = (l.how == "tram" or l.how == "boat") and ("Take " .. (l.name or ("the " .. l.how))) or ("Cross into " .. into)
			legs[#legs + 1] = { path = walked, world = n.w, map = n.map, tip = { title, (l.how == "road" and l.name) and ("By " .. l.name .. (l.learned and "" or " (about here)")) or ("To " .. into) }, zone = ZoneOf(n.map), crossing = true }
		end
	end
	return legs
end

-- Planned from where the player stands, kept a few seconds per target (the arrow asks many times a
-- second; as the player goes, the next plan starts where they are, so the legs advance).
function RT.PlanTo(key, to, destTip, destZone)
	local c = R.routePlan
	if c and c.key == key and (GetTime() - c.at < RT.WAY_KEEP or RT.OnTaxi()) then return c.legs end
	local here = RT.Here()
	local legs
	if here and to.map then
		local path = RT.Plan({ map = here.map, x = here.x, y = here.y }, to, RT.Speed())
		if path then legs = RT.PlanLegs(path, destTip, destZone) end
	end
	R.routePlan = { key = key, at = GetTime(), legs = legs }
	return legs
end

-- The arrow's target for planned legs: the first, with the second as "then …".
function RT.PlanTarget(legs)
	local first, second = legs[1], legs[2]
	if not first then return nil end
	local thenLine = second and ("then " .. second.tip[1]:gsub("^%u", string.lower)) or first.tip[2]
	if first.hearth then return { hearth = true, text = first.tip[1], sub = first.tip[2] .. (second and (", " .. thenLine) or ""), legs = legs, away = true } end
	return { world = first.world, text = first.tip[1], sub = thenLine, legs = legs, away = true, path = first.path }
end

---------------------------------------------------------------------------
-- Trails learned from walking (the player, 2026-11-19: "learned trails, offline for now"): the paths the
-- player walks while the route is on, kept as a road network on this PC only, so the arrow and the
-- lines follow them instead of a straight line over a ridge. Ideas from studying AzerothGPS (none of
-- its code or data): a point every 10 yards, a walk near an old one merged into it, the ends joined to
-- the nearest trail, walking off it dearer than along it and a straight line dearest, and the arrow
-- aimed a little way ahead along the way.
---------------------------------------------------------------------------

RT.TRAIL_STEP = 10 -- yards between a trail's points
RT.TRAIL_MERGE = 12 -- a point this near an old one is that one (the same road walked again)
RT.TRAIL_JUMP = 40 -- farther in one tick is a loading screen, a flight or a portal: the trail breaks
RT.TRAIL_CELL = 25 -- the index's cells
RT.TRAIL_JOIN = 150 -- how far to look for a trail from where a way starts or ends
RT.TRAIL_ENDS = 4 -- the trail points tried at each end
RT.TRAIL_MAX = 15000 -- points kept, at most (a saved file holds about 262,000 values in all, AzerothGPS's notes say)
-- yards cost: off a trail, and a straight line with no trail. A straight line costs 3 here, not the 2 AzerothGPS
-- uses: it knows whether the straight line is blocked (its terrain), Spellmind doesn't, and a trail walked is a way
-- that exists.
RT.OFF_TRAIL, RT.STRAIGHT = 1.25, 3
RT.LOOK_NEAR, RT.LOOK_FAR = 36, 84 -- the arrow aims at the trail's points this far ahead, averaged
-- A stretch swum (the player, 2026-11-19: "if I walk across the water because it's faster"): dearer by
-- running speed over swimming speed (the game's two when it says, about 7 against 4.7, so 1.5 a yard).
RT.SWIM_SPEED = 4.72
function RT.SwimCost()
	local _, run, _, swim = Try(rawget(_G, "GetUnitSpeed"), "player")
	run, swim = tonumber(run), tonumber(swim)
	if run and swim and run > 0 and swim > 0 then return math.max(1, run / swim) end
	return RT.RUN_SPEED / RT.SWIM_SPEED
end

-- SpellmindDB.routeTrails[continent] = { x = {}, y = {}, e = { a1, b1, a2, b2, … } } (world yards); the
-- session's adjacency and index built from it on first use.
local trails = {}
local function Trail(c)
	ns.db.routeTrails = type(ns.db.routeTrails) == "table" and ns.db.routeTrails or {}
	local saved = ns.db.routeTrails[c]
	if type(saved) ~= "table" then saved = { x = {}, y = {}, e = {} }; ns.db.routeTrails[c] = saved end
	local T = trails[c]
	if T and T.saved == saved then return T end
	T = { saved = saved, adj = {}, grid = {} }
	trails[c] = T
	local function Cell(x, y) return math.floor(x / RT.TRAIL_CELL) .. ":" .. math.floor(y / RT.TRAIL_CELL) end
	T.Cell = Cell
	for i = 1, #saved.x do
		local k = Cell(saved.x[i], saved.y[i])
		T.grid[k] = T.grid[k] or {}
		table.insert(T.grid[k], i)
		T.adj[i] = {}
	end
	for k = 1, #saved.e, 2 do
		local a, b = saved.e[k], saved.e[k + 1]
		if T.adj[a] and T.adj[b] then table.insert(T.adj[a], b); table.insert(T.adj[b], a) end
	end
	return T
end
RT.Trail = Trail

-- The trail points within r yards of a spot, nearest first: { { i, d } }.
local function Near(T, x, y, r, max)
	local out = {}
	local cx, cy = math.floor(x / RT.TRAIL_CELL), math.floor(y / RT.TRAIL_CELL)
	local reach = math.ceil(r / RT.TRAIL_CELL)
	for i = cx - reach, cx + reach do
		for j = cy - reach, cy + reach do
			for _, n in ipairs(T.grid[i .. ":" .. j] or {}) do
				local d = math.sqrt((T.saved.x[n] - x) ^ 2 + (T.saved.y[n] - y) ^ 2)
				if d <= r then out[#out + 1] = { n, d } end
			end
		end
	end
	table.sort(out, function(a, b) return a[2] < b[2] end)
	while max and #out > max do table.remove(out) end
	return out
end

local function AddPoint(T, x, y, wet)
	local s = T.saved
	if #s.x >= RT.TRAIL_MAX then return nil end
	local i = #s.x + 1
	s.x[i], s.y[i] = math.floor(x * 10 + 0.5) / 10, math.floor(y * 10 + 0.5) / 10
	if wet then s.w = s.w or {}; s.w[i] = true end
	local k = T.Cell(s.x[i], s.y[i])
	T.grid[k] = T.grid[k] or {}
	table.insert(T.grid[k], i)
	T.adj[i] = {}
	return i
end
local function Join(T, a, b)
	if not a or not b or a == b then return end
	for _, n in ipairs(T.adj[a]) do if n == b then return end end
	table.insert(T.adj[a], b)
	table.insert(T.adj[b], a)
	local e = T.saved.e
	e[#e + 1], e[#e + 2] = a, b
end

-- One tick of walking: a point every RT.TRAIL_STEP yards, merged into the trail it's on.
function RT.NoteTrail(w)
	if not w or (ns.db and ns.db.routeTrailsOff) or Try(rawget(_G, "UnitOnTaxi"), "player") then R.routeTrailAt = nil; return end
	local last = R.routeTrailAt
	if not last or last.c ~= w.c then R.routeTrailAt = { c = w.c, x = w.x, y = w.y }; R.routeTrailNode = nil; return end
	local d = Dist(last, w)
	if d > RT.TRAIL_JUMP then R.routeTrailAt = { c = w.c, x = w.x, y = w.y }; R.routeTrailNode = nil; return end
	if d < RT.TRAIL_STEP then return end
	local T = Trail(w.c)
	local wet = Try(rawget(_G, "IsSwimming")) and true or false
	local near = Near(T, w.x, w.y, RT.TRAIL_MERGE, 1)[1]
	local node = near and near[1] or AddPoint(T, w.x, w.y, wet)
	if R.routeTrailNode == nil and last then
		-- The first step: where it began joins too.
		local back = Near(T, last.x, last.y, RT.TRAIL_MERGE, 1)[1]
		R.routeTrailNode = back and back[1] or AddPoint(T, last.x, last.y, wet)
	end
	Join(T, R.routeTrailNode, node)
	R.routeTrailNode = node
	R.routeTrailAt = { c = w.c, x = w.x, y = w.y }
end

-- Noted four times a second while the route is on, the arrow shown or not (crossings, flights, trails).
RT.NOTE_TICK = 0.25
if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(RT.NOTE_TICK, function() if RT.Shown() and ns.db then pcall(RT.NoteOutside) end end)
end

-- How many trail points this PC knows (the Route tab).
function RT.TrailCount()
	local n = 0
	for _, t in pairs(ns.db and type(ns.db.routeTrails) == "table" and ns.db.routeTrails or {}) do
		if type(t) == "table" and type(t.x) == "table" then n = n + #t.x end
	end
	return n
end
function RT.ForgetTrails()
	if ns.db then ns.db.routeTrails = {} end
	trails = {}
	R.routeTrailAt, R.routeTrailNode, R.routeTrailWay = nil, nil, nil
	RT.Refresh()
end

-- A small binary heap for the search.
local function Push(h, v, f) h[#h + 1] = { v, f }; local i = #h; while i > 1 do local p = math.floor(i / 2); if h[p][2] <= h[i][2] then break end; h[p], h[i] = h[i], h[p]; i = p end end
local function Pop(h)
	local top = h[1]
	if not top then return nil end
	h[1] = h[#h]; h[#h] = nil
	local i = 1
	while true do
		local l, r, m = 2 * i, 2 * i + 1, i
		if h[l] and h[l][2] < h[m][2] then m = l end
		if h[r] and h[r][2] < h[m][2] then m = r end
		if m == i then break end
		h[m], h[i] = h[i], h[m]; i = m
	end
	return top[1], top[2]
end

-- The way from one world spot to another over the trails: the points between them (world spots) when
-- the trails make it cheaper than the straight line, else nil.
RT.TRAIL_EXPAND = 20000 -- search steps, at most
function RT.TrailBetween(a, b)
	if not a or not b or a.c ~= b.c then return nil end
	local T = Trail(a.c)
	if #T.saved.x == 0 then return nil end
	local starts = Near(T, a.x, a.y, RT.TRAIL_JOIN, RT.TRAIL_ENDS)
	local ends = Near(T, b.x, b.y, RT.TRAIL_JOIN, RT.TRAIL_ENDS)
	if #starts == 0 or #ends == 0 then return nil end
	local X, Y = T.saved.x, T.saved.y
	local goal = {}
	for _, e in ipairs(ends) do goal[e[1]] = e[2] * RT.OFF_TRAIL end
	local g, prev, done, heap = {}, {}, {}, {}
	local Wet = T.saved.w or {}
	local swim = RT.SwimCost()
	local function H(i) return math.sqrt((X[i] - b.x) ^ 2 + (Y[i] - b.y) ^ 2) end
	for _, s0 in ipairs(starts) do g[s0[1]] = s0[2] * RT.OFF_TRAIL; Push(heap, s0[1], g[s0[1]] + H(s0[1])) end
	local best, bestCost
	local steps = 0
	while true do
		local u = Pop(heap)
		if not u then break end
		if not done[u] then
			done[u] = true
			steps = steps + 1
			if steps > RT.TRAIL_EXPAND then break end
			if goal[u] then
				local total = g[u] + goal[u]
				if not bestCost or total < bestCost then best, bestCost = u, total end
			end
			if bestCost and g[u] + H(u) >= bestCost then break end
			for _, v in ipairs(T.adj[u]) do
				local c = g[u] + math.sqrt((X[u] - X[v]) ^ 2 + (Y[u] - Y[v]) ^ 2) * ((Wet[u] or Wet[v]) and swim or 1)
				if not g[v] or c < g[v] then g[v], prev[v] = c, u; Push(heap, v, c + H(v)) end
			end
		end
	end
	if not best then return nil end
	if bestCost >= Dist(a, b) * RT.STRAIGHT then return nil end
	local pts, n = {}, best
	while n do table.insert(pts, 1, { c = a.c, x = X[n], y = Y[n] }); n = prev[n] end
	-- Fewer points to draw: those that bend the way (within 3 yards of the line otherwise).
	local function Simplify(list, tol)
		if #list < 3 then return list end
		local keep, out = { [1] = true, [#list] = true }, {}
		local function Seg(i, j)
			local ax, ay, bx, by = list[i].x, list[i].y, list[j].x, list[j].y
			local dx, dy = bx - ax, by - ay
			local len = math.sqrt(dx * dx + dy * dy)
			local far, at = 0, nil
			for k = i + 1, j - 1 do
				local d = len > 0 and math.abs((list[k].x - ax) * dy - (list[k].y - ay) * dx) / len or math.sqrt((list[k].x - ax) ^ 2 + (list[k].y - ay) ^ 2)
				if d > far then far, at = d, k end
			end
			if at and far > tol then keep[at] = true; Seg(i, at); Seg(at, j) end
		end
		Seg(1, #list)
		for k, p in ipairs(list) do if keep[k] then out[#out + 1] = p end end
		return out
	end
	return Simplify(pts, 3)
end

-- The trail from where the player stands to a world spot, kept a few seconds per target.
function RT.TrailTo(key, target)
	local c = R.routeTrailWay
	if c and c.key == key and (GetTime() - c.at < RT.WAY_KEEP or RT.OnTaxi()) then return c.path end
	local me = RT.PlayerWorld()
	local path = me and target and RT.TrailBetween(me, target) or nil
	R.routeTrailWay = { key = key, at = GetTime(), path = path }
	return path
end

-- Where the arrow aims on a way along points (world spots) to a target: the average of the points
-- RT.LOOK_NEAR to RT.LOOK_FAR yards ahead of the player along it (so a bend doesn't swing it), and the
-- yards still to go along it.
function RT.LookAhead(me, path, target)
	local pts = {}
	for _, p in ipairs(path) do pts[#pts + 1] = p end
	pts[#pts + 1] = target
	-- From the nearest point of the way, onward.
	local from, fd = 1, nil
	for k, p in ipairs(pts) do local d = Dist(me, p); if not fd or d < fd then from, fd = k, d end end
	local ahead, along, sx, sy, n = 0, fd, 0, 0, 0
	local at = me
	for k = from, #pts do
		local p = pts[k]
		local seg = Dist(at, p)
		ahead = ahead + seg
		if ahead >= RT.LOOK_NEAR and ahead <= RT.LOOK_FAR then sx, sy, n = sx + p.x, sy + p.y, n + 1 end
		at = p
	end
	along = 0
	at = me
	for k = from, #pts do along = along + Dist(at, pts[k]); at = pts[k] end
	if n == 0 then
		-- Nothing in the window: the first point past it, or the target.
		local acc = 0
		at = me
		for k = from, #pts do acc = acc + Dist(at, pts[k]); at = pts[k]; if acc >= RT.LOOK_NEAR then return pts[k], along end end
		return target, along
	end
	return { c = me.c, x = sx / n, y = sy / n }, along
end

---------------------------------------------------------------------------
-- Skip chips (the player, 2026-11-19): the route review asks the AI to end with "Skip: <quest>" lines;
-- each one naming a quest on the route becomes a button that skips its steps
---------------------------------------------------------------------------

RT.SKIPS_MAX = 3
-- The quest on the route with this name (any case, colour codes and quotes aside), or nil.
local function OnRoute(name)
	local want = DG().Norm(name)
	if want == "" then return nil end
	for _, st in ipairs(R.route and R.route.stops or {}) do
		for _, g in ipairs(st.goals) do
			if g.title and DG().Norm(g.title) == want then return g.q, g.title end
		end
	end
	return nil
end
-- A reply's text without its "Skip:" lines, and the quests they name that are on the route: { { q, title } }.
function RT.SkipLines(text)
	local keep, skips, seen = {}, {}, {}
	for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
		local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		local name = plain:match("^[%s%-%*•]*[Ss]kip:%s*(.-)%s*$")
		if name then
			name = name:gsub("^[\"'“‘]+", ""):gsub("[\"'”’%.!]+$", "")
			local q, title = OnRoute(name)
			if q and not seen[q] and #skips < RT.SKIPS_MAX then seen[q] = true; skips[#skips + 1] = { q = q, title = title } end
		else
			keep[#keep + 1] = line
		end
	end
	return table.concat(keep, "\n"):gsub("%s+$", ""), skips
end
-- Every step of a quest skipped (its other quests' goals in a shared stop stay; that stop isn't
-- skipped). Returns how many steps.
function RT.SkipQuest(q)
	-- The quest and the follow-ups planned after it (they can't come without it).
	local set, after = { [q] = true }, R.route and R.route.after or {}
	local grew = true
	while grew do
		grew = false
		for f, pres in pairs(after) do
			if not set[f] then
				for _, p in ipairs(pres) do if set[p] then set[f], grew = true, true end end
			end
		end
	end
	local n = 0
	for _, st in ipairs(R.route and R.route.stops or {}) do
		local only = #st.goals > 0
		for _, g in ipairs(st.goals) do if not set[g.q] then only = false end end
		if only and not (R.routeSkip and R.routeSkip[st.key]) and not RT.StopDone(st) then RT.SetSkip(st.key, true); n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------------
-- /sm route why <step> (the player, 2026-11-19: "so we can ensure we're optimizing our routes"): why a
-- step sits where it is. Its rules (what must come before and after it, and why), its weighting, its
-- spot (for an objective: which of the mobs' groups, and how near the others are), and every earlier
-- place it could go: how much shorter or longer the route would be, and the rule that forbids it.
---------------------------------------------------------------------------

RT.WHY_TRIES = 3 -- the best earlier places shown
local function Bare(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Yd(n) return math.floor(n + 0.5) .. " yd" end
-- The goal for a rule's key on the route ("turnin:702"), its stop's number and its words.
local function GoalAt(route, key)
	for i, st in ipairs(route.stops or {}) do
		for _, g in ipairs(st.goals) do
			if g.kind .. ":" .. g.q == key then return i, Bare(RT.GoalText(g)) end
		end
	end
	return nil, key
end
local function RuleWhy(a, b)
	local ka, qa = a:match("^(%a+):(%d+)$")
	local kb, qb = b:match("^(%a+):(%d+)$")
	if qa == qb and ka == "pickup" then return "it has to be picked up first" end
	if qa == qb and ka == "do" then return "its objectives come before the turn-in" end
	if ka == "turnin" and kb == "pickup" then return "a chain: turning in the one opens the other" end
	return "a rule"
end
-- The first rule an order breaks, or nil.
function RT.Broken(order, rules)
	local at = {}
	for i, st in ipairs(order) do for _, g in ipairs(st.goals) do at[g.kind .. ":" .. g.q] = i end end
	for _, r in ipairs(rules) do
		local a, b = at[r[1]], at[r[2]]
		if a and b and a > b then return r end
	end
	return nil
end

function RT.Why(n)
	local route = R.route
	n = tonumber(n)
	if not route or route.nowhere or not route.stops then return { "No route to explain: open it with /sm route." } end
	local st = n and route.stops[n]
	if not st then return { "There's no step " .. tostring(n) .. ": the route has " .. #route.stops .. " (/sm route why <step>)." } end
	local here, cost = route.here or RT.Here(), route.cost or RT.Yards
	local start = route.start or (here and { x = here.x, y = here.y })
	local out = {}
	local function Add(t) out[#out + 1] = t end
	Add("Step " .. n .. " of " .. #route.stops .. ": " .. Bare(Plain(st)))
	local prev, nxt = route.stops[n - 1] or start, route.stops[n + 1]
	if here and prev then
		Add("  The way: " .. Yd(RT.Yards(prev, st, here)) .. " from " .. (n > 1 and ("step " .. (n - 1)) or "where the route began")
			.. (nxt and (", then " .. Yd(RT.Yards(st, nxt, here)) .. " to step " .. (n + 1)) or ""))
	end
	-- Its rules.
	local mine = {}
	for _, g in ipairs(st.goals) do mine[g.kind .. ":" .. g.q] = true end
	local after, before = {}, {}
	for _, r in ipairs(route.rules or {}) do
		if mine[r[2]] and not mine[r[1]] then
			local k, words = GoalAt(route, r[1])
			after[#after + 1] = "  After step " .. tostring(k or "?") .. " (" .. words .. "): " .. RuleWhy(r[1], r[2]) .. "."
		elseif mine[r[1]] and not mine[r[2]] then
			local k, words = GoalAt(route, r[2])
			before[#before + 1] = "  Before step " .. tostring(k or "?") .. " (" .. words .. "): " .. RuleWhy(r[1], r[2]) .. "."
		end
	end
	if #after == 0 and #before == 0 then Add("  No rule ties it to another step.") end
	for _, t in ipairs(after) do Add(t) end
	for _, t in ipairs(before) do Add(t) end
	-- Its weighting.
	if RT.StopLow(st) then
		Add("  Marked worth skipping? (little XP for the walk): its way counts " .. RT.LOW_LATER .. "x in the order, so it comes later.")
	end
	-- Its spot: for an objective, which group of the mobs, and the nearest one to the steps around it.
	local Q = L()
	for _, g in ipairs(st.goals) do
		if g.kind == "do" and Q and here and here.area and not st.map then
			local pts = RT.ObjectiveSpots(Q, g.q, here.area)
			if #pts > 1 then
				local c = RT.Center(pts)
				local r2, inGroup = RT.CLUSTER * RT.CLUSTER, 0
				for _, p in ipairs(pts) do if c and (p[1] - c.x) ^ 2 + (p[2] - c.y) ^ 2 <= r2 then inGroup = inGroup + 1 end end
				if inGroup < #pts then Add("  " .. Bare(g.title) .. ": the spot is the busiest group, " .. inGroup .. " of " .. #pts .. " spawns here.") end
				local function Nearest(from)
					local best
					for _, p in ipairs(pts) do
						local d = RT.Yards(from, { x = p[1], y = p[2] }, here)
						if not best or d < best then best = d end
					end
					return best
				end
				if prev then
					local near = Nearest(prev)
					local spot = RT.Yards(prev, st, here)
					if near and near + 50 < spot then Add("    The nearest of them to the step before is " .. Yd(near) .. " from it (the spot: " .. Yd(spot) .. ").") end
				end
			end
		end
	end
	-- Every earlier place: the route's length with this step moved there.
	if here and start then
		local base = RT.Length(route.stops, start, here, cost)
		local tries = {}
		for p = 1, n - 1 do
			local try = {}
			for k, s2 in ipairs(route.stops) do if k ~= n then try[#try + 1] = s2 end end
			table.insert(try, p, st)
			tries[#tries + 1] = { p = p, d = RT.Length(try, start, here, cost) - base, broken = RT.Broken(try, route.rules or {}) }
		end
		table.sort(tries, function(a, b) return a.d < b.d end)
		local shown = 0
		for _, t in ipairs(tries) do
			if shown >= RT.WHY_TRIES then break end
			shown = shown + 1
			local what = t.d < -0.5 and (Yd(-t.d) .. " shorter") or (t.d > 0.5 and (Yd(t.d) .. " longer") or "the same")
			local why
			if t.broken then
				local k, words = GoalAt(route, t.broken[1])
				why = "not allowed: step " .. tostring(k or "?") .. " (" .. words .. ") must come first"
			else
				why = t.d < -0.5 and "allowed: |cffff9933the order could be better|r" or "allowed"
			end
			Add("  As step " .. t.p .. ": " .. what .. "; " .. why .. ".")
		end
		if #tries == 0 then Add("  It's the first step.") end
	end
	return out
end
