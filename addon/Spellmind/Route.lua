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
RT.NEXT_SHOWN = 6

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
	if type(o) == "table" then
		for _, c in ipairs(type(o[1]) == "table" and o[1] or {}) do if N then AddSpawns(pts, Try(N.spawns, c[1]), area) end end
		for _, c in ipairs(type(o[2]) == "table" and o[2] or {}) do if O then AddSpawns(pts, Try(O.spawns, c[1]), area) end end
		for _, c in ipairs(type(o[3]) == "table" and o[3] or {}) do
			if I then
				for _, npc in ipairs(Try(I.npcDrops, c[1]) or {}) do if N then AddSpawns(pts, Try(N.spawns, npc), area) end end
				for _, obj in ipairs(Try(I.objectDrops, c[1]) or {}) do if O then AddSpawns(pts, Try(O.spawns, obj), area) end end
			end
		end
		for _, c in ipairs(type(o[5]) == "table" and o[5] or {}) do
			for _, npc in ipairs(type(c[1]) == "table" and c[1] or {}) do if N then AddSpawns(pts, Try(N.spawns, npc), area) end end
		end
	end
	local trig = type(Q.Quest.triggerEnd) == "function" and Try(Q.Quest.triggerEnd, id) or nil
	if type(trig) == "table" then AddSpawns(pts, trig[2], area) end
	return pts
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
	local function Place(kind, id, title, spot, to)
		raw[#raw + 1] = { x = spot.x, y = spot.y, goals = { { kind = kind, q = id, title = title, to = to } } }
	end
	local function Elsewhere(zoneName, kind, id, title, to)
		local key = zoneName or "Elsewhere"
		route.elsewhere[key] = route.elsewhere[key] or {}
		table.insert(route.elsewhere[key], { kind = kind, q = id, title = title, to = to })
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
			if not complete then
				local center = Q and here.area and RT.Center(RT.ObjectiveSpots(Q, id, here.area)) or nil
				center = center or GameSpot(id)
				if center then Place("do", id, title, center) else Elsewhere(nil, "do", id, title) end
			end
			if fin and fin.spot then Place("turnin", id, title, fin.spot, fin.name)
			elseif complete then
				local spot = GameSpot(id)
				if spot then Place("turnin", id, title, spot, fin and fin.name)
				else Elsewhere(fin and AreaName(fin.zone), "turnin", id, title, fin and fin.name) end
			elseif fin then Elsewhere(AreaName(fin.zone), "turnin", id, title, fin.name) end
		end
	end
	-- This zone's quests to pick up (QuestieDB): for this character, open now, at its level, given here,
	-- with their objectives here too (or none), so a pick up never sends the player away.
	local index = Q and here.area and DG().Index(function() RT.Dirty() end)
	if index and index[here.area] then
		local ctx = DG().Context(Q)
		local function Has(id) return log[id] ~= nil end
		for _, id in ipairs(index[here.area]) do
			if not log[id] and not Done(id) and DG().Fits(Q, id, ctx, Has) and #DG().Missing(id) == 0 then
				local req = tonumber((Try(Q.Quest.requiredLevel, id))) or 1
				local ql = tonumber((Try(Q.Quest.questLevel, id))) or req
				if req <= level and ql >= level - RT.BELOW and ql <= level + RT.ABOVE then
					local _, friendly, spot = DG().Giver(Q, id)
					local mine = not friendly or not ctx.faction or tostring(friendly):find(ctx.faction == "Alliance" and "A" or "H", 1, true)
					if mine and spot and spot.zone == here.area then
						local title = DG().Name(Q, id) or ("quest " .. id)
						local pts = RT.ObjectiveSpots(Q, id, here.area)
						local center = RT.Center(pts)
						local fin = RT.TurnIn(Q, id, here.area)
						local hasObjectives = #pts > 0
						if (hasObjectives and center) or (not hasObjectives and fin and fin.spot) then
							Place("pickup", id, title, spot)
							if center then Place("do", id, title, center) end
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
	-- Close ones are one stop.
	local stops = {}
	for _, s in ipairs(keep) do
		local joined
		for _, t in ipairs(stops) do
			if RT.Yards(s, t, here) <= RT.GROUP_YARDS then joined = t; break end
		end
		if joined then
			for _, g in ipairs(s.goals) do joined.goals[#joined.goals + 1] = g end
		else
			stops[#stops + 1] = s
		end
	end
	for _, s in ipairs(stops) do
		table.sort(s.goals, function(a, b) return RANK[a.kind] < RANK[b.kind] end)
		-- A stop's key: its goals, so a skip outlives a rebuild that keeps the stop.
		local keys = {}
		for _, g in ipairs(s.goals) do keys[#keys + 1] = g.kind .. ":" .. g.q end
		s.key = table.concat(keys, ",")
	end
	while #stops > RT.STOPS_MAX do table.remove(stops) end
	local rules = RT.Rules(stops, chains)
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
	return ns.Escape(g.title) .. (left and (": " .. left) or "")
end

function RT.StopText(s)
	local first = s.goals[1]
	local more = #s.goals - 1
	return RT.GoalText(first) .. (more > 0 and (" |cff888888(+" .. more .. ")|r") or "")
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

RT.W, RT.H = 330, 370
RT.UPNEXT_LINES = 6

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
	-- The current step: its goals with their progress, and Go.
	f.now = Line(f, "GameFontHighlight", RT.W - 90)
	f.now:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)
	f.go = ns.GearUI.Button(f, "Go", 52)
	f.go:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -40)
	f.go:SetScript("OnClick", function() RT.Go() end)
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
	local bits = {}
	for zone, goals in pairs(route.elsewhere or {}) do bits[#bits + 1] = { zone = zone, n = #goals } end
	table.sort(bits, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.zone < b.zone end)
	local words = {}
	for i, b in ipairs(bits) do
		if i > 3 then break end
		words[#words + 1] = ns.Escape(b.zone) .. ": " .. b.n
	end
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
	local y = -42
	if route.nowhere then
		f.now:SetText("|cff888888No map position here (an instance or a loading screen): the route waits until you're outside.|r")
	elseif not cur then
		f.now:SetText("|cff19ff19Nothing left here that Spellmind knows of.|r" .. (route.db and "" or
			"\n|cff888888With QuestieDB installed, the route also lists quests to pick up here, and where mobs are.|r"))
	else
		local lines = {}
		for _, g in ipairs(cur.goals) do lines[#lines + 1] = (RT.GoalDone(g) and "|cff19ff19" or "") .. RT.GoalText(g) .. (RT.GoalDone(g) and "|r" or "") end
		f.now:SetText(table.concat(lines, "\n"))
	end
	if cur then f.go:Show() else f.go:Hide() end
	y = y - math.max(24, tonumber(f.now:GetStringHeight()) or 24) - 14
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
