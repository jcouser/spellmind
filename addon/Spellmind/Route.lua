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
RT.BELOW, RT.ABOVE = 5, 3 -- pickups this far below (grey) or above the character's level are left out
-- A quest is done on the route up to +3 (the player, 2026-11-19: +4 is a lot solo), taken or not; in a
-- group, two levels more. One level past that, a pick up is still a step "for later" when its giver is
-- by another stop (the player: "I should have at least picked up the quest"): taken, it waits in the
-- log until the level (or a group) comes.
RT.LOG_ABOVE, RT.GROUP_ABOVE = 3, 2
RT.STOPS_MAX = 40
RT.CHAIN_PASSES = 3 -- follow-ups planned this many steps down a chain
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

-- Yards between two points on the same map (x, y 0-100).
function RT.Yards(a, b, here)
	local dx, dy = (a.x - b.x) * here.w / 100, (a.y - b.y) * here.h / 100
	return math.sqrt(dx * dx + dy * dy)
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

local RANK = { pickup = 1, ["do"] = 2, turnin = 3 }
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
function RT.Length(order, start, here)
	local total, at = 0, start
	for _, s in ipairs(order) do total = total + RT.Yards(at, s, here); at = s end
	return total
end

-- The stops in an efficient order that keeps the rules: nearest next (of the stops whose earlier
-- goals are done or behind), then 2-opt passes, each kept only when it's shorter and keeps the rules.
function RT.Order(stops, start, here, rules)
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
				local d = RT.Yards(at, s, here)
				if not bestD or d < bestD then best, bestD = i, d end
			end
		end
		if not best then -- nothing ready (a rule the data gets wrong): the nearest, so nothing is lost
			for i, s in ipairs(left) do
				local d = RT.Yards(at, s, here)
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
		local len = RT.Length(order, start, here)
		for i = 1, n - 1 do
			for j = i + 1, n do
				local try = {}
				for k = 1, i - 1 do try[#try + 1] = order[k] end
				for k = j, i, -1 do try[#try + 1] = order[k] end
				for k = j + 1, n do try[#try + 1] = order[k] end
				local l2 = RT.Length(try, start, here)
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
function RT.Build()
	local here = RT.Here()
	local route = { stops = {}, elsewhere = {}, later = {}, built = GetTime() }
	R.route = route
	if not here then route.nowhere = true; return route end
	route.zone, route.map, route.area = here.zone, here.map, here.area
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
		raw[#raw + 1] = { x = spot.x, y = spot.y, goals = { Goal(kind, id, title, to, extra) } }
		if kind == "turnin" then turnsHere[id] = true end
	end
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
					else Elsewhere(fin and AreaName(fin.zone), "turnin", id, title, fin and fin.name) end
				elseif fin then Elsewhere(AreaName(fin.zone), "turnin", id, title, fin.name) end
			end
		end
	end
	-- This zone's quests to pick up (QuestieDB): for this character, open now, at its level, given here,
	-- with their objectives here too (or none), so a pick up never sends the player away.
	local index = Q and here.area and DG().Index(function() RT.Dirty() end)
	R.routeAskedNow = 0
	-- after[id] = { the quests on this route it opens after }: a follow-up, planned.
	local after = {}
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
			if not taken[id] and not log[id] and not Done(id) then open, needs = Opens(id) end
			if open and not RT.Hidden(id) and not RT.NotOffered(id) and DG().Fits(Q, id, ctx, Has) and RT.Known(id) then
				local req = tonumber((Try(Q.Quest.requiredLevel, id))) or 1
				local ql = tonumber((Try(Q.Quest.questLevel, id))) or req
				local later = ql > level + RT.Above()
				if req <= level and ql >= level - RT.BELOW and ql <= level + RT.Above() + 1 then
					local _, friendly, spot = DG().Giver(Q, id)
					local mine = not friendly or not ctx.faction or tostring(friendly):find(ctx.faction == "Alliance" and "A" or "H", 1, true)
					if later and mine and spot and spot.zone == here.area then
						taken[id] = true
						forLater[#forLater + 1] = { id = id, title = DG().Name(Q, id) or ("quest " .. id), spot = spot, needs = needs }
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
							Place("pickup", id, title, spot, spot.name, { fromID = spot.npc })
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
				Place("pickup", p.id, p.title, p.spot, p.spot.name, { fromID = p.spot.npc, later = true })
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
	route.stops = RT.Order(stops, { x = here.x, y = here.y }, here, rules)
	route.rules = rules
	if Q then route.where = RT.Zones(true) end
	return route
end

---------------------------------------------------------------------------
-- Where next
---------------------------------------------------------------------------

-- The player (2026-11-19): a leveling guide sent them to Stormwind for its next stretch while Duskwood
-- still had quests for them, and the AI said stay. So the zones are ranked by what's really left for
-- this character (quests it can pick up there now, at its level, not done, and its log's quests there),
-- against the time it takes to get there and do them. Needs QuestieDB.
RT.WHERE_WHEN = 3 -- steps left here at or below which the tracker shows Where next
RT.WHERE_SHOWN = 3
RT.WHERE_MAX = 5 -- other zones kept (for the tracker and the AI)
RT.WHERE_MIN = 2 -- fewer quests than this isn't somewhere to go next
RT.QUEST_MINUTES = 5 -- a quest's time, on average: to the giver, the objectives, back
RT.RUN_SPEED, RT.MOUNT_LEVEL, RT.MOUNT_SPEED = 7, 40, 11 -- yards a second
RT.PATH_FACTOR = 1.3 -- roads and hills: the way is longer than the straight line
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
RT.FLY_SPEED = 25 -- yards a second, the straight line between the two
RT.FLY_MINUTES = 1 -- the flight master, take off, landing
RT.HEARTH_MINUTES = 0.5 -- the cast and the loading screen
RT.HEARTHSTONE = 6948

local function Dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function Short(name) return (tostring(name):gsub(",.*$", "")) end

-- The flight paths known, with where they are: { { name, c, x, y } }.
function RT.Flights()
	local me = ns.State and ns.State.Me and ns.State.Me()
	local out = {}
	local known = me and type(me.flights) == "table" and me.flights or {}
	for name, w in pairs(me and type(me.flightSpots) == "table" and me.flightSpots or {}) do
		if known[name] and type(w) == "table" and w.c and w.x and w.y then out[#out + 1] = { name = name, c = w.c, x = w.x, y = w.y } end
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
	if not start or (dur and dur > 0 and start + dur - GetTime() > 0) then return nil end
	return h
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
		local m = Walk(a, A) + RT.FLY_MINUTES + Dist(A, B) / RT.FLY_SPEED / 60 + Walk(B, b)
		return m, Short(A.name) .. " to " .. Short(B.name), A
	end
	-- leg: where the way starts (a flight master's spot, or "hearth"); nil on foot.
	local best
	local function Try2(m, how, via, leg) if m and (not best or m < best.minutes) then best = { minutes = m, how = how, via = via, leg = leg } end end
	Try2(Walk(from, to), "walk")
	local fm, fv, fa = Fly(from, to)
	Try2(fm, "fly", fv and ("fly " .. fv), fa)
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
	local speed = level >= RT.MOUNT_LEVEL and RT.MOUNT_SPEED or RT.RUN_SPEED
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
				if way then travel, z.how, z.via, z.leg = way.minutes, way.how, way.via, way.leg
				elseif me and there then travel = RT.SEA_MINUTES
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
	while #others > RT.WHERE_MAX do table.remove(others) end
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
-- until it's clicked again or the player reaches a new zone. R.routeAim = its area ID.
function RT.Aim(z)
	if type(z) ~= "table" then return end
	if R.routeAim == z.area then
		R.routeAim = nil
		ns.Chat.System("The arrow points at the route's steps again.")
	else
		R.routeAim = z.area
		ns.Chat.System("The arrow points the way to " .. z.zone .. ". Click it again to go back to the route's steps.")
	end
	RT.Refresh()
end
ns.On("ZONE_CHANGED_NEW_AREA", function() R.routeAim = nil end)

-- "Westfall: 3 quests to pick up, 1 in your log · about 4 min away"
function RT.WhereText(z)
	local bits = {}
	if z.quests > 0 then bits[#bits + 1] = z.quests .. (z.quests == 1 and " quest" or " quests") .. " to pick up" end
	if z.inLog > 0 then bits[#bits + 1] = z.inLog .. " in your log" end
	local how = z.how == "fly" and " away by flight" or (z.how == "hearth" and " away by hearthstone" or " away")
	return table.concat(bits, ", ") .. (z.minutes and (" · about " .. z.minutes .. " min" .. how) or "")
end

-- The other zones for the tracker: once few steps are left here (or none), the best few.
function RT.WhereLines(route)
	local out = {}
	local done, total = RT.Progress()
	if total - done > RT.WHERE_WHEN then return out end
	for _, z in ipairs(route.where or {}) do
		if not z.here and #out < RT.WHERE_SHOWN then out[#out + 1] = z end
	end
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
function RT.GoalText(g)
	if g.kind == "pickup" then return "Pick up " .. ns.Escape(g.title) .. (g.later and " |cff888888(for later)|r" or "") end
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
function RT.Groups(st)
	local out, last, lastKey = {}, nil, nil
	for _, g in ipairs(st.goals) do
		if not RT.GoalDone(g) then
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
		names[#names + 1] = ns.Escape(g.title)
	end
	local more = #gr.goals - #names
	return table.concat(names, ", ") .. (more > 0 and (", +" .. more .. " more") or "")
end

-- A stop in one short line (Up next): its first group, and how many more groups.
function RT.StopText(st)
	local groups = RT.Groups(st)
	if #groups == 0 then return "" end
	local more = #groups - 1
	return RT.GroupText(groups[1]) .. (more > 0 and (" |cff888888(+" .. more .. ")|r") or "")
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
function RT.Dirty()
	if not RT.Shown() then R.routeStale = true; return end
	if R.routeTimer then return end
	R.routeTimer = true
	C_Timer.After(RT.REBUILD_DELAY, function()
		R.routeTimer = nil
		if InCombat() then R.routeStale = true; return end
		RT.Build()
		RT.Refresh()
	end)
end

-- Progress changed (an objective ticked, an item looted): the tracker drawn again, the order kept.
function RT.Refresh()
	if RT.Shown() and RT.Draw then RT.Draw() end
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

local function Build()
	if RT.frame then return RT.frame end
	local f = CreateFrame("Frame", "SpellmindRoute", UIParent, "BackdropTemplate")
	f:SetSize(RT.W, RT.H)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 40)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
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
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -12)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.close:SetScript("OnClick", function() f:Hide() end)
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
	f.thens = {}
	for i = 1, RT.THEN_LINES do
		local l = Line(f, "GameFontHighlightSmall", RT.W - 40)
		if l.SetMaxLines then l:SetMaxLines(3) end
		f.thens[i] = l
	end
	f.nextLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.nextLabel:SetText("Up next")
	f.next = {}
	for i = 1, RT.NEXT_MAX do
		local l = Line(f, "GameFontHighlightSmall", RT.W - 40)
		if l.SetMaxLines then l:SetMaxLines(3) end
		f.next[i] = l
	end
	-- Where next: the best zones to go on to, each a line to click for a pin at its quest givers.
	f.whereLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.whereLabel:SetText("Where next")
	f.where = {}
	for i = 1, RT.WHERE_SHOWN do
		local b = CreateFrame("Button", nil, f)
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
	f.awayLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.awayLabel:SetText("Elsewhere")
	f.away = {}
	for i = 1, RT.AWAY_LINES do
		local l = Line(f, "GameFontHighlightSmall", RT.W - 40)
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
		RT.Draw()
	end)
	f:SetScript("OnSizeChanged", function() if f.sizing then RT.Draw() end end)
	f:SetScript("OnHide", function() if RT.arrow then RT.arrow:Hide() end pcall(RT.DrawMap) end)
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
		lines[#lines + 1] = "|cffffd100" .. ns.Escape(z.zone) .. ":|r " .. RT.GoalText(z.goals[1]) .. (more > 0 and (" |cff888888(+" .. more .. ")|r") or "")
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
	local W = tonumber(f:GetWidth()) or RT.W
	f.now:SetWidth(W - 32); f.nowSub:SetWidth(W - 32); f.credit:SetWidth(W - 28)
	for _, l in ipairs(f.away) do l:SetWidth(W - 40) end
	for _, b in ipairs(f.where) do b:SetWidth(W - 40); b.text:SetWidth(W - 40) end
	local wl = RT.WhereLines(route)
	for _, l in ipairs(f.thens) do l:SetWidth(W - 40) end
	for _, l in ipairs(f.next) do l:SetWidth(W - 40) end
	f.fold:SetNormalTexture(ui.compact and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
	f.fold.tip = ui.compact and "Show Up next" or "Only the current step"
	f.title:SetText("Route" .. (route.zone and (" · " .. ns.Escape(route.zone)) or ""))
	local cur, i = RT.Current()
	local done, total = RT.Progress()
	f.step:SetText(total > 0 and ("Step " .. (i or math.min(done + 1, total)) .. " of " .. total) or "")
	local groups = cur and RT.Groups(cur) or {}
	local sub
	if route.nowhere then
		f.now:SetText("|cff888888No map position here (an instance or a loading screen): the route waits until you're outside.|r")
	elseif not cur and wl[1] then
		f.now:SetText("|cff19ff19Done here at your level.|r Next: |cffffd100" .. ns.Escape(wl[1].zone) .. "|r")
		sub = RT.WhereText(wl[1])
	elseif not cur then
		f.now:SetText("|cff19ff19Nothing left here that Spellmind knows of.|r" .. (route.db and "" or
			"\n|cff888888With QuestieDB installed, the route also lists quests to pick up here, and where mobs are.|r"))
	else
		f.now:SetText(groups[1] and RT.GroupText(groups[1]) or "")
		sub = groups[1] and RT.GroupNames(groups[1])
	end
	f.nowSub:SetText(sub or "")
	f.nowSub:ClearAllPoints()
	f.nowSub:SetPoint("TOPLEFT", f.now, "BOTTOMLEFT", 0, -3)
	if sub then f.nowSub:Show() else f.nowSub:Hide() end
	local bandH = 16 + math.max(20, tonumber(f.now:GetStringHeight()) or 20) + (sub and (3 + (tonumber(f.nowSub:GetStringHeight()) or 12)) or 0)
	f.band:SetHeight(bandH)
	local rest = { f.nextLabel, f.whereLabel, f.awayLabel, f.credit, f.back, f.skip, f.rebuild, f.grip }
	-- Folded: the current step alone.
	if ui.compact then
		for _, l in ipairs(f.thens) do l:Hide() end
		for _, l in ipairs(f.next) do l:Hide() end
		for _, l in ipairs(f.away) do l:Hide() end
		for _, b in ipairs(f.where) do b:Hide() end
		for _, r in ipairs(rest) do r:Hide() end
		if not f.sizing then f:SetHeight(36 + bandH + 10) end
		return
	end
	for _, r in ipairs({ f.credit, f.back, f.skip, f.rebuild, f.grip }) do r:Show() end
	local y = -36 - bandH - 8
	-- Then: the rest of this stop, two lines at most.
	for k, l in ipairs(f.thens) do
		local gr = groups[k + 1]
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y)
		if gr then
			local last = k == RT.THEN_LINES and #groups > RT.THEN_LINES + 1
			l:SetText("|cff888888Then:|r " .. RT.GroupText(gr) .. (last and (" |cff888888(+" .. (#groups - RT.THEN_LINES - 1) .. ")|r") or ""))
			l:Show()
			y = y - Row(l)
		else
			l:SetText("")
			l:Hide()
		end
	end
	y = y - 6
	-- How many of Up next: three, or as many as the player's size of the window holds.
	local away = RT.AwayLines(route)
	local credit = RT.Credit(route)
	f.credit:SetText(credit and ("|cff777777" .. credit .. "|r") or "")
	-- Where next, when the band isn't already saying it: the zones after the first.
	local shownWhere = {}
	for k, z in ipairs(wl) do if cur or k > 1 then shownWhere[#shownWhere + 1] = z end end
	local whereH, awayH = 0, 0
	for k, b in ipairs(f.where) do
		local z = shownWhere[k]
		b.zone = z
		local aimed = z and R.routeAim == z.area
		b.text:SetText(z and ((aimed and "|cff19ff19\194\187|r " or "") .. "|cffffd100" .. ns.Escape(z.zone) .. ":|r " .. RT.WhereText(z)) or "")
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
	local upnext = RT.UpNext(fixedH and RT.NEXT_MAX or RT.UPNEXT_LINES)
	f.nextLabel:ClearAllPoints()
	f.nextLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
	if #upnext > 0 then f.nextLabel:Show() else f.nextLabel:Hide() end
	y = y - 16
	local used = 0
	for k, l in ipairs(f.next) do
		local s = upnext[k]
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
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
		f.whereLabel:SetText(cur and "Where next" or "Or")
		f.whereLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
		f.whereLabel:Show()
		y = y - 16
	else
		f.whereLabel:Hide()
	end
	for k, b in ipairs(f.where) do
		local z = shownWhere[k]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
		if z then b:Show(); y = y - Row(b.text) else b:Hide() end
	end
	-- Elsewhere: a gap, its heading, its lines.
	f.awayLabel:ClearAllPoints()
	if #away > 0 then
		y = y - 14
		f.awayLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
		f.awayLabel:Show()
		y = y - 16
	else
		f.awayLabel:Hide()
	end
	for k, l in ipairs(f.away) do
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
		if away[k] then l:Show(); y = y - Row(l) else l:Hide() end
	end
	if credit then y = y - 16 end
	-- As tall as what it shows, with room for the buttons (the player, 2026-11-19: text ran out of it),
	-- or the player's own size.
	if not f.sizing then f:SetHeight(ui.h and math.max(RT.MIN_H, math.min(RT.MAX_H, ui.h)) or math.max(RT.MIN_H, -y + 44)) end
	if R.routeSkipped and #R.routeSkipped > 0 then f.back:Enable() else f.back:Disable() end
	if cur then f.skip:Enable() else f.skip:Disable() end
end

-- /sm route: open (built fresh when it's stale) or close.
function RT.Toggle(show)
	local f = Build()
	if show == nil then show = not f:IsShown() end
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
function RT.ArrowTarget()
	local route = R.route
	if not route or route.nowhere then return nil end
	local z
	for _, w in ipairs(route.where or {}) do if R.routeAim and w.area == R.routeAim then z = w end end
	local cur = RT.Current()
	if cur and not z then
		local gr = RT.Groups(cur)[1]
		return { world = World(route.map, cur.x, cur.y), text = gr and RT.GroupText(gr) or RT.GoalText(cur.goals[1]) }
	end
	z = z or RT.WhereLines(route)[1]
	if not z then return nil end
	if z.leg == "hearth" then
		return { hearth = true, text = "Use your hearthstone", sub = (z.via and (z.via:gsub("^hearthstone ", "")) or "") .. ", then on to " .. z.zone }
	end
	if type(z.leg) == "table" then
		return { world = z.leg, text = "Flight master at " .. Short(z.leg.name), sub = "then fly on to " .. z.zone }
	end
	return { world = z.spot and World(z.map, z.spot.x, z.spot.y), text = z.zone .. (z.spot and z.spot.giver and (": " .. z.spot.giver) or "") }
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
	if not t then return Still("", "|cff19ff19Nothing left on the route here.|r") end
	if t.hearth then return Still("", t.text, t.sub) end
	local me = RT.PlayerWorld()
	local facing = Try(rawget(_G, "GetPlayerFacing"))
	if not me or type(facing) ~= "number" then return Still("|cff888888No position in here|r", t.text, t.sub) end
	if not t.world then return Still("", t.text, t.sub) end
	if t.world.c ~= me.c then return Still("|cff888888On another continent|r", t.text, t.sub) end
	local turn, yards = RT.Bearing(me, t.world, facing)
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

local function Layer(canvas)
	if marks.layer then return marks.layer end
	local l = CreateFrame("Frame", "SpellmindRouteMap", canvas)
	l:SetAllPoints(canvas)
	l:SetFrameLevel((tonumber((canvas:GetFrameLevel())) or 1) + 2)
	marks.layer = l
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
local function Dot(layer, k)
	local d = marks.dots[k]
	if d then return d end
	d = CreateFrame("Button", nil, layer)
	d:SetSize(RT.DOT, RT.DOT)
	d.tex = d:CreateTexture(nil, "ARTWORK")
	d.tex:SetAllPoints(d)
	d.tex:SetTexture(DOT_TEX)
	d.num = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.num:SetPoint("CENTER", d, "CENTER", 0, 0)
	d:SetScript("OnEnter", function(self)
		if not GameTooltip or not self.stop then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Step " .. self.index)
		for _, gr in ipairs(RT.Groups(self.stop)) do GameTooltip:AddLine(RT.GroupText(gr), 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	d:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	marks.dots[k] = d
	return d
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
	local layer = Layer(canvas)
	for _, t in pairs(marks.areas) do t:Hide() end
	for _, d in pairs(marks.dots) do d:Hide(); d.stop = nil end
	marks.shown = 0
	local route = R.route
	if not RT.Shown() or not W:IsShown() or not route or not route.map or W:GetMapID() ~= route.map then return end
	local cw, ch = tonumber((canvas:GetWidth())) or 0, tonumber((canvas:GetHeight())) or 0
	if cw <= 0 or ch <= 0 then return end
	local cur = RT.Current()
	local base = tonumber((layer:GetFrameLevel())) or 1
	local na, nd = 0, 0
	for i, s in ipairs(route.stops or {}) do
		if nd >= RT.MAP_STEPS then break end
		if not RT.StopDone(s) and not (R.routeSkip and R.routeSkip[s.key]) then
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
			d:SetPoint("CENTER", layer, "TOPLEFT", s.x / 100 * cw, -s.y / 100 * ch)
			d.tex:SetVertexColor(r, g, b)
			d.num:SetText(tostring(i))
			if now then d.num:SetTextColor(0.1, 0.05, 0) else d.num:SetTextColor(1, 1, 1) end
			d.stop, d.index = s, i
			d:SetFrameLevel(base + (now and 3 or 1))
			d:Show()
		end
	end
	marks.shown = nd
end
