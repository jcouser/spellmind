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
RT.STOPS_MAX = 40
RT.PASSES = 8 -- improvement passes over the order
RT.REBUILD_DELAY = 1.5 -- seconds: game events coalesce into one rebuild
RT.NEXT_SHOWN = 3

local function Try(fn, ...) return ns.Try(fn, ...) end
local function DG() return ns.Dungeons end
local function L() return ns.Dungeons and ns.Dungeons.DB and ns.Dungeons.DB() end
local function Level() return tonumber((Try(UnitLevel, "player"))) or 1 end
local function InCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false end

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

-- An item objective nothing here drops (the player, 2026-11-19: a Bronze Tube, bought or crafted):
-- who sells it, { item, name, spot } in this area, else { item, name, zone } or { item } (no vendor known).
function RT.Vendor(Q, id, area)
	local o = Try(Q.Quest.objectives, id)
	local I, N = Q.Item, Q.Npc
	if type(o) ~= "table" or type(o[3]) ~= "table" or not I or not N then return nil end
	local away, empty
	R.routeNoStock = R.routeNoStock or {}
	for _, c in ipairs(o[3]) do
		local itemID = type(c) == "table" and tonumber(c[1]) or nil
		local item = itemID and Try(I.name, itemID) or nil
		for _, npc in ipairs(itemID and type(I.vendors) == "function" and Try(I.vendors, itemID) or {}) do
			local name = Try(N.name, npc)
			-- Seen this session without it (limited stock sells out: the player, 2026-11-19).
			if R.routeNoStock[npc .. ":" .. itemID] then
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
	local function Place(kind, id, title, spot, to, extra)
		raw[#raw + 1] = { x = spot.x, y = spot.y, goals = { Goal(kind, id, title, to, extra) } }
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
		if qlevel > level + RT.ABOVE then
			route.later[#route.later + 1] = title
		else
			local complete = Complete(id)
			local fin = Q and here.area and RT.TurnIn(Q, id, here.area) or nil
			local doHere = false
			if not complete then
				local center = Q and here.area and RT.Center(RT.ObjectiveSpots(Q, id, here.area)) or nil
				center = center or GameSpot(id)
				if center then
					Place("do", id, title, center); doHere = true
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
	if index and index[here.area] then
		local ctx = DG().Context(Q)
		local function Has(id) return log[id] ~= nil end
		for _, id in ipairs(index[here.area]) do
			if not log[id] and not Done(id) and not RT.Hidden(id) and not RT.NotOffered(id) and DG().Fits(Q, id, ctx, Has) and #DG().Missing(id) == 0 and RT.Known(id) then
				local req = tonumber((Try(Q.Quest.requiredLevel, id))) or 1
				local ql = tonumber((Try(Q.Quest.questLevel, id))) or req
				if req <= level and ql >= level - RT.BELOW and ql <= level + RT.ABOVE then
					local _, friendly, spot = DG().Giver(Q, id)
					local mine = not friendly or not ctx.faction or tostring(friendly):find(ctx.faction == "Alliance" and "A" or "H", 1, true)
					if mine and spot and spot.zone == here.area then
						local title = DG().Name(Q, id) or ("quest " .. id)
						local center = RT.Center(RT.ObjectiveSpots(Q, id, here.area))
						local fin = RT.TurnIn(Q, id, here.area)
						-- Its objectives have to be doable here (mobs, objects, a vendor), or it has none.
						local hasObjectives = RT.HasObjectives(Q, id)
						local v = hasObjectives and not center and RT.Vendor(Q, id, here.area) or nil
						local doable = center or (v and v.spot) or nil
						if (hasObjectives and doable) or (not hasObjectives and fin and fin.spot) then
							Place("pickup", id, title, spot, spot.name, { fromID = spot.npc })
							if center then Place("do", id, title, center)
							elseif v and v.spot then Place("do", id, title, v.spot, nil, { buy = v.item, buyID = v.itemID, from = v.name, fromID = v.npc, empty = v.empty }) end
							if fin and fin.spot then Place("turnin", id, title, fin.spot, fin.name) end
							local pre = Try(Q.Quest.preQuestSingle, id)
							if type(pre) == "table" and pre[1] then chains[#chains + 1] = { pre[1], id } end
						end
					end
				end
			end
		end
	end
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
	local function Rank(g, st)
		if g.kind == "turnin" then
			for _, h in ipairs(st.goals) do if h.q == g.q and h.kind ~= "turnin" then return 4 end end
			return 0
		end
		return RANK[g.kind]
	end
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
	return route
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
	if g.kind == "pickup" then return "Pick up " .. ns.Escape(g.title) end
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
	local out, at = {}, {}
	for _, g in ipairs(st.goals) do
		if not RT.GoalDone(g) then
			local key = g.kind .. "|" .. (g.kind == "do" and "" or (g.to or ""))
			local gr = at[key]
			if not gr then gr = { kind = g.kind, to = g.kind ~= "do" and g.to or nil, goals = {} }; at[key] = gr; out[#out + 1] = gr end
			gr.goals[#gr.goals + 1] = g
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

-- Go: the game's pin on the current step.
function RT.Go(s)
	s = s or RT.Current()
	if not s or not R.route or not R.route.map then return nil end
	if ns.Quests.Pin(R.route.map, s.x, s.y) then
		ns.Chat.System("Map pin set: " .. RT.GoalText(s.goals[1]) .. ". Follow the arrow.")
		return "pin"
	end
	ns.Chat.System("The game can't pin that spot on its map.")
	return nil
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
	local dropped = 0
	for _, st in ipairs(route.stops or {}) do
		for _, g in ipairs(st.goals) do
			if g.kind == "pickup" and g.fromID == npc and not RT.GoalDone(g) then
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
	R.routeNoStock = R.routeNoStock or {}
	local gone
	for _, s in ipairs(route.stops or {}) do
		for _, g in ipairs(s.goals) do
			if g.buyID and g.fromID == npc then
				local key = npc .. ":" .. g.buyID
				if have[g.buyID] then R.routeNoStock[key] = nil
				elseif not R.routeNoStock[key] then R.routeNoStock[key] = true; gone = gone or g end
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

for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP" }) do
	ns.On(ev, function() RT.Dirty() end)
end
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "BAG_UPDATE_DELAYED" }) do
	ns.On(ev, function() RT.Refresh() end)
end
ns.On("PLAYER_REGEN_ENABLED", function() if R.routeStale and RT.Shown() then R.routeStale = nil; RT.Dirty() end end)

---------------------------------------------------------------------------
-- The tracker: a small window to leave open while questing (closed by default; /sm route)
---------------------------------------------------------------------------

RT.W, RT.H = 330, 240
RT.UPNEXT_LINES = 3
RT.THEN_LINES = 2

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
	f.step = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.step:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -14)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
	f.close:SetScript("OnClick", function() f:Hide() end)
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
	f.now = Line(f.band, "GameFontHighlight", RT.W - 96)
	f.now:SetPoint("TOPLEFT", f.band, "TOPLEFT", 8, -8)
	f.nowSub = Line(f.band, "GameFontDisableSmall", RT.W - 96)
	f.go = ns.GearUI.Button(f.band, "Go", 48)
	f.go:SetPoint("TOPRIGHT", f.band, "TOPRIGHT", -6, -6)
	f.go:SetScript("OnClick", function() RT.Go() end)
	f.thens = {}
	for i = 1, RT.THEN_LINES do
		local l = Line(f, "GameFontHighlightSmall", RT.W - 40)
		if l.SetWordWrap then l:SetWordWrap(false) end
		f.thens[i] = l
	end
	f.nextLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.nextLabel:SetText("Up next")
	f.next = {}
	for i = 1, RT.UPNEXT_LINES do
		local l = Line(f, "GameFontHighlightSmall", RT.W - 40)
		if l.SetWordWrap then l:SetWordWrap(false) end
		f.next[i] = l
	end
	f.also = Line(f, "GameFontDisableSmall", RT.W - 28)
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
	f:Hide()
	RT.frame = f
	return f
end

-- "Also: Stormwind City: 2 turn-ins · Lakeshire: 1" for what's left elsewhere.
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
	return text
end

function RT.Draw()
	local f = RT.frame
	if not f then return end
	local route = R.route or {}
	f.title:SetText("Route" .. (route.zone and (" · " .. ns.Escape(route.zone)) or ""))
	local cur, i = RT.Current()
	local done, total = RT.Progress()
	f.step:SetText(total > 0 and ("Step " .. math.min(done + 1, total) .. " of " .. total) or "")
	local groups = cur and RT.Groups(cur) or {}
	local sub
	if route.nowhere then
		f.now:SetText("|cff888888No map position here (an instance or a loading screen): the route waits until you're outside.|r")
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
	if cur then f.go:Show() else f.go:Hide() end
	local bandH = 16 + math.max(20, tonumber(f.now:GetStringHeight()) or 20) + (sub and (3 + (tonumber(f.nowSub:GetStringHeight()) or 12)) or 0)
	f.band:SetHeight(bandH)
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
			y = y - 15
		else
			l:SetText("")
			l:Hide()
		end
	end
	y = y - 6
	local upnext = RT.UpNext(RT.UPNEXT_LINES)
	f.nextLabel:ClearAllPoints()
	f.nextLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
	if #upnext > 0 then f.nextLabel:Show() else f.nextLabel:Hide() end
	y = y - 16
	for k, l in ipairs(f.next) do
		local s = upnext[k]
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
		if s then
			l:SetText(RT.StopText(s))
			l:Show()
			y = y - 15
		else
			l:SetText("")
			l:Hide()
		end
	end
	local also = AlsoText(route)
	f.also:ClearAllPoints()
	f.also:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y - 8)
	f.also:SetText(also and ("|cff888888" .. also .. "|r") or "")
	if also then y = y - 8 - (tonumber(f.also:GetStringHeight()) or 12) end
	-- As tall as what it shows, with room for the buttons (the player, 2026-11-19: text ran out of it).
	f:SetHeight(math.max(150, -y + 44))
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
