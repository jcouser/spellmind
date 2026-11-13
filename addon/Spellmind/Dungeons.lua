-- Dungeons.lua: dungeon prep (docs/features.md §3.7, docs/milestone-13.md). Which dungeons matter to
-- the character now, from the game itself: the instance they're in (GetInstanceInfo), the dungeons
-- their quest log has quests for (the log's own headers), and, where the client lists them, the LFG
-- tool's dungeons with their levels. Forever has dungeons of its own (the Hall of Thanes), so there's
-- no built-in list to go stale. The briefing (bosses, tips for the role, loot, what to bring, quests to
-- pick up first) is the AI's, with web search.
--
-- Read only: nothing is joined, posted or set. LFG puts a line in the chat box for the player to send.

local _, ns = ...
local DG = {}
ns.Dungeons = DG

DG.NEAR_BELOW, DG.NEAR_ABOVE = 3, 4 -- "at your level": a dungeon whose range reaches within these levels

local function Level() return tonumber((ns.Try(UnitLevel, "player"))) or 1 end

-- The instance the character is in: { name, kind ("party", "raid"), diff } or nil outside one.
function DG.Here()
	local inside, kind = ns.Try(IsInInstance)
	if not inside then return nil end
	local name, itype, _, diffName = ns.Try(GetInstanceInfo)
	if type(name) ~= "string" or name == "" then return nil end
	itype = type(itype) == "string" and itype or kind
	if itype ~= "party" and itype ~= "raid" then return nil end
	return { name = ns.State.Text(name), kind = itype, diff = type(diffName) == "string" and diffName ~= "" and diffName or nil }
end

-- The quest log's dungeon quests by dungeon (the log's header for a quest the game tags Dungeon or
-- Raid), in log order: { { name, quests = { { id, title, level, complete } }, low, high, ready } }.
-- Kept for the frame it was read in (the review: one state build read the whole log five or six
-- times, through the Dungeons and Advisor parts).
function DG.FromLog()
	local now = GetTime()
	if DG.logAt == now and DG.log then return DG.log end
	DG.log, DG.logAt = DG.ReadLog(), now
	return DG.log
end

function DG.ReadLog()
	local out, by = {}, {}
	local q = ns.State and ns.State.Collect and ns.State.Collect.quests and select(2, pcall(ns.State.Collect.quests))
	local ids = {}
	for _, kv in ipairs(type(q) == "table" and q._o or {}) do
		if kv[1] == "list" then
			for _, it in ipairs(kv[2] or {}) do
				for _, f in ipairs(it._o or {}) do if f[1] == "id" then ids[#ids + 1] = f[2] end end
			end
		end
	end
	for _, id in ipairs(ids) do
		local info = ns.Quests.Read(id)
		if info and (info.tagName == "Dungeon" or info.tagName == "Raid") and type(info.header) == "string" and info.header ~= "" then
			local d = by[info.header]
			if not d then
				d = { name = info.header, quests = {}, ready = 0, raid = info.tagName == "Raid" }
				by[info.header] = d
				out[#out + 1] = d
			end
			d.quests[#d.quests + 1] = { id = id, title = info.title, level = info.level, complete = info.complete }
			if info.complete then d.ready = d.ready + 1 end
			local lvl = tonumber(info.level)
			if lvl then
				d.low = math.min(d.low or lvl, lvl)
				d.high = math.max(d.high or lvl, lvl)
			end
		end
	end
	return out
end

-- The dungeons the client's LFG tool lists, with their levels, if it has them (probe round 6 checks):
-- { { name, low, high } }. Kept for the session: the list doesn't change.
function DG.Listed()
	if DG.listed then return DG.listed end
	local out = {}
	local LL = rawget(_G, "C_LFGList")
	if type(LL) == "table" and type(LL.GetAvailableActivities) == "function" and type(LL.GetActivityInfoTable) == "function" then
		local ok, acts = pcall(LL.GetAvailableActivities, 2) -- category 2: dungeons
		for _, id in ipairs(ok and type(acts) == "table" and acts or {}) do
			local okInfo, t = pcall(LL.GetActivityInfoTable, id)
			if okInfo and type(t) == "table" and type(t.fullName) == "string" and t.fullName ~= "" then
				local low = tonumber(t.minLevelSuggestion) or tonumber(t.minLevel)
				local high = tonumber(t.maxLevelSuggestion) or tonumber(t.maxLevel)
				if high == 0 then high = nil end
				out[#out + 1] = { name = ns.State.Text(t.fullName), low = low, high = high }
			end
		end
	end
	if #out > 0 then DG.listed = out end
	return out
end

-- The listed dungeons that fit now: the character's level within a few of the range.
function DG.AtLevel()
	local you, out = Level(), {}
	for _, d in ipairs(DG.Listed()) do
		local low, high = d.low or 0, d.high or (d.low and d.low + 8) or 99
		if low <= you + DG.NEAR_ABOVE and high >= you - DG.NEAR_BELOW then out[#out + 1] = d end
	end
	table.sort(out, function(a, b) return (a.low or 0) < (b.low or 0) end)
	return out
end

-- "18–22", "level 20", or nil.
function DG.Range(low, high)
	if low and high and high ~= low then return low .. "–" .. high end
	if low then return "level " .. low end
	return nil
end

local function Role()
	local t = ns.State and ns.State.Collect and ns.State.Collect.talents and select(2, pcall(ns.State.Collect.talents))
	for _, kv in ipairs(type(t) == "table" and t._o or {}) do
		if kv[1] == "role" then return ns.Quests.ROLES[kv[2]] end
	end
end

---------------------------------------------------------------------------
-- A dungeon's quests, from QuestieDB's public API (LibQuestieDB), when that addon is installed.
-- Read at runtime only: Spellmind ships none of its data. One pass over its quests sorts them by
-- zone (a dungeon's quests have the dungeon as their zone), a few hundred a frame, kept for the
-- session; each dungeon's list is then checked against this character: done, in the log, to pick up
-- (with who gives it and where), or locked behind a quest not done yet.
---------------------------------------------------------------------------

DG.SCAN_PER_TICK = 400

local function DB()
	local L = rawget(_G, "LibQuestieDB")
	if type(L) ~= "table" or type(L.Quest) ~= "table" or type(L.Quest.GetAllIds) ~= "function" then return nil end
	if type(L.RequireContract) == "function" and not ns.Try(L.RequireContract, 4) then return nil end
	return L
end
DG.HasDB = function() return DB() ~= nil end

-- "The Hall of Thanes" and "Hall of Thanes" are one dungeon.
function DG.Norm(name)
	return tostring(name or ""):lower():gsub("^the%s+", ""):gsub("[^%w]", "")
end

-- a AND b on whole numbers, without the bit library (Lua 5.1 in game has bit.band; the tests' VM doesn't).
local function Band(a, b)
	a, b = math.floor(tonumber(a) or 0), math.floor(tonumber(b) or 0)
	local r, bitv = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
		a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
	end
	return r
end

-- The pass over every quest: R.dungeonIndex = { [areaID] = { questIDs } } once done. Starts it when
-- not yet started; returns the index or nil while it runs. done: called when it finishes.
function DG.Index(done)
	if DG.index then return DG.index end
	local L = DB()
	if not L then return nil end
	if DG.scanning then return nil end
	local ok, ids = pcall(L.Quest.GetAllIds)
	if not ok or type(ids) ~= "table" then return nil end
	DG.scanning = true
	local index, i = {}, 1
	local function step()
		local stop = math.min(#ids, i + DG.SCAN_PER_TICK - 1)
		for k = i, stop do
			local id = ids[k]
			local okZ, zone = pcall(L.Quest.zoneOrSort, id)
			zone = okZ and tonumber(zone)
			if zone and zone > 0 then
				local list = index[zone]
				if not list then list = {}; index[zone] = list end
				list[#list + 1] = id
			end
		end
		i = stop + 1
		if i > #ids then
			DG.index, DG.scanning = index, nil
			if done then pcall(done) end
		else
			C_Timer.After(0, step)
		end
	end
	step()
	return DG.index
end

-- A dungeon's area ID: from a quest of its in the log, else by name (QuestieDB's named areas, the
-- game's own area names).
function DG.AreaOf(name)
	DG.areas = DG.areas or {}
	local key = DG.Norm(name)
	-- A hit kept for the session; a miss tried again a minute on (the review: a dungeon not found
	-- before its quest was in the log stayed unfound until /reload).
	local hit = DG.areas[key]
	if type(hit) == "number" then return hit end
	if type(hit) == "table" and GetTime() < hit.retry then return nil end
	local found = DG.FindArea(name)
	DG.areas[key] = found or { retry = GetTime() + 60 }
	return found
end

function DG.FindArea(name)
	local L = DB()
	if not L then return nil end
	local want = DG.Norm(name)
	for _, d in ipairs(DG.FromLog()) do
		if DG.Norm(d.name) == want then
			for _, q in ipairs(d.quests) do
				local ok, z = pcall(L.Quest.zoneOrSort, q.id)
				if ok and tonumber(z) and z > 0 then return z end
			end
		end
	end
	local zones = type(L.Enum) == "table" and L.Enum.zoneIDs
	if type(zones) ~= "table" then return nil end
	for key, id in pairs(zones) do
		if DG.Norm(tostring(key):gsub("_", " ")) == want then return id end
	end
	local MAP = rawget(_G, "C_Map")
	if MAP and type(MAP.GetAreaInfo) == "function" then
		for _, id in pairs(zones) do
			local n = ns.Try(MAP.GetAreaInfo, id)
			if type(n) == "string" and DG.Norm(n) == want then return id end
		end
	end
	return nil
end

local function Done(id)
	local QL = C_QuestLog
	if QL and type(QL.IsQuestFlaggedCompleted) == "function" then return ns.Try(QL.IsQuestFlaggedCompleted, id) and true or false end
	if type(rawget(_G, "IsQuestFlaggedCompleted")) == "function" then return ns.Try(IsQuestFlaggedCompleted, id) and true or false end
	return false
end

-- Who gives a quest and where: "Gryan Stoutmantle, Westfall (56, 48)", "an item: Old Map", with the
-- giver's faction ("A", "H", "AH") and spot { zone, x, y } (QuestieDB's coordinates, 0-100, as Questie
-- shows them) for Go.
local function Giver(L, id)
	local ok, by = pcall(L.Quest.startedBy, id)
	if not ok or type(by) ~= "table" then return nil end
	local MAP = rawget(_G, "C_Map")
	local function Place(zone, spawns)
		local zname = zone and MAP and type(MAP.GetAreaInfo) == "function" and ns.Try(MAP.GetAreaInfo, zone) or nil
		local at = type(spawns) == "table" and zone and type(spawns[zone]) == "table" and spawns[zone][1]
		local x, y = type(at) == "table" and tonumber(at[1]), type(at) == "table" and tonumber(at[2])
		local coords = (x and y and x >= 0 and y >= 0) and (" (" .. math.floor(x + 0.5) .. ", " .. math.floor(y + 0.5) .. ")") or ""
		local spot = (x and y and x >= 0 and y >= 0) and { zone = zone, x = x, y = y } or nil
		return type(zname) == "string" and zname ~= "" and (", " .. zname .. coords) or "", spot
	end
	for _, npc in ipairs(type(by[1]) == "table" and by[1] or {}) do
		local n = L.Npc and ns.Try(L.Npc.name, npc)
		if type(n) == "string" and n ~= "" then
			local where, spot = Place(L.Npc and ns.Try(L.Npc.zoneID, npc), L.Npc and ns.Try(L.Npc.spawns, npc))
			if spot then spot.name = n end
			return n .. where, ns.Try(L.Npc.friendlyToFaction, npc), spot
		end
	end
	for _, obj in ipairs(type(by[2]) == "table" and by[2] or {}) do
		local n = L.Object and ns.Try(L.Object.name, obj)
		if type(n) == "string" and n ~= "" then
			local where, spot = Place(L.Object and ns.Try(L.Object.zoneID, obj), L.Object and ns.Try(L.Object.spawns, obj))
			if spot then spot.name = n end
			return n .. where, nil, spot
		end
	end
	for _, item in ipairs(type(by[3]) == "table" and by[3] or {}) do
		local n = L.Item and ns.Try(L.Item.name, item)
		if type(n) == "string" and n ~= "" then return "an item: " .. n end
	end
	return nil
end

-- Go to a quest's giver: the game's map pin on the giver's zone (QuestieDB's zone-to-map table).
-- Returns "pin", or nil when the game can't pin there.
function DG.Go(spot)
	if type(spot) ~= "table" then return nil end
	local map = DG.MapForArea(spot.zone)
	if map and ns.Quests.Pin(map, spot.x, spot.y) then return "pin" end
	return nil
end

-- The game's map for an area (a zone) by its name, from the game's own map list (seen in game:
-- QuestieDB keeps its zone-to-map table as Lua source text, so nothing came of it and every Go failed;
-- the game's list needs no other addon). The player's own map first, then each continent's zones.
-- Kept for the session.
DG.maps = {}
function DG.MapForArea(area)
	if not area then return nil end
	if DG.maps[area] ~= nil then return DG.maps[area] or nil end
	local M = rawget(_G, "C_Map")
	local name = M and type(M.GetAreaInfo) == "function" and ns.Try(M.GetAreaInfo, area)
	local found
	if type(name) == "string" and name ~= "" then found = DG.MapNamed(name) end
	DG.maps[area] = found or false
	return found
end

-- A zone map's id by its name, or nil.
function DG.MapNamed(name)
	local M = rawget(_G, "C_Map")
	if not M then return nil end
	local want = DG.Norm(name)
	local function named(id)
		local info = ns.Try(M.GetMapInfo, id)
		return type(info) == "table" and type(info.name) == "string" and DG.Norm(info.name) == want
	end
	local here = ns.Try(M.GetBestMapForUnit, "player")
	if type(here) == "number" and named(here) then return here end
	if type(M.GetMapChildrenInfo) ~= "function" then return nil end
	local E = type(Enum) == "table" and Enum.UIMapType or {}
	local CONTINENT, ZONE = E.Continent or 2, E.Zone or 3
	for _, c in ipairs(ns.Try(M.GetMapChildrenInfo, 947, CONTINENT, true) or {}) do -- 947: Azeroth
		for _, z in ipairs(ns.Try(M.GetMapChildrenInfo, c.mapID, ZONE, true) or {}) do
			if type(z) == "table" and type(z.name) == "string" and DG.Norm(z.name) == want then return z.mapID end
		end
	end
	return nil
end

-- The quests a quest needs done first that aren't: every one of its group, or one of its singles.
local function Missing(L, id)
	local out = {}
	local group = ns.Try(L.Quest.preQuestGroup, id)
	for _, p in ipairs(type(group) == "table" and group or {}) do
		if not Done(p) then out[#out + 1] = p end
	end
	local single = ns.Try(L.Quest.preQuestSingle, id)
	if type(single) == "table" and #single > 0 then
		local anyDone = false
		for _, p in ipairs(single) do if Done(p) then anyDone = true end end
		if not anyDone then out[#out + 1] = single[1] end
	end
	return out
end

-- Walked back from a quest that's locked: the step to do next, { id, inLog }. A prerequisite in the
-- log is it (do that one); else the earliest one whose own prerequisites are done (take that one).
-- nil when nothing's missing. At most 12 steps back.
local function Chain(L, id, Have, depth)
	depth = depth or 0
	local miss = Missing(L, id)
	if #miss == 0 or depth > 12 then return nil end
	local p = miss[1]
	if Have(p) then return { id = p, inLog = true } end
	return Chain(L, p, Have, depth + 1) or { id = p }
end

-- A quest's place in its chain: 1 for the first, 2 for the one after it… (seen in game: "after The
-- Defias Brotherhood (in your log)" read as the step just finished, when it was the next step, of the
-- same name). The prerequisite walked back regardless of what's done, 12 steps at most.
local function StepOf(L, id, depth)
	depth = depth or 0
	if depth > 12 then return 1 end
	local single = ns.Try(L.Quest.preQuestSingle, id)
	local group = ns.Try(L.Quest.preQuestGroup, id)
	local pre = (type(single) == "table" and single[1]) or (type(group) == "table" and group[1])
	if not pre then return 1 end
	return 1 + StepOf(L, pre, depth + 1)
end

-- Where a quest is handed in: "Wiley the Black, Stormwind City", or nil.
local function Finisher(L, id)
	local ok, by = pcall(L.Quest.finishedBy, id)
	if not ok or type(by) ~= "table" then return nil end
	local MAP = rawget(_G, "C_Map")
	for _, npc in ipairs(type(by[1]) == "table" and by[1] or {}) do
		local n = L.Npc and ns.Try(L.Npc.name, npc)
		if type(n) == "string" and n ~= "" then
			local zone = L.Npc and ns.Try(L.Npc.zoneID, npc)
			local zname = zone and MAP and type(MAP.GetAreaInfo) == "function" and ns.Try(MAP.GetAreaInfo, zone) or nil
			return n .. ((type(zname) == "string" and zname ~= "") and (", " .. zname) or "")
		end
	end
	return nil
end

local function Name(L, id)
	local n = ns.Try(L.Quest.name, id)
	return type(n) == "string" and n ~= "" and n or nil
end

-- A dungeon's quests for this character: { area, done = {names}, log = {names}, pickup = { { id,
-- name, level, from, after, at } }, total }, or nil (no QuestieDB, the pass still running, or no
-- area). Quests for another race, class or faction, a profession, past their max level, or shut out
-- by one already done are left out. after: a quest to do first; at: the level it opens at.
function DG.Quests(name, done)
	local L = DB()
	if not L then return nil end
	local index = DG.Index(done)
	if not index then return nil end
	local area = DG.AreaOf(name)
	if not area then return nil end
	local level = Level()
	local _, classFile = ns.Try(UnitClass, "player")
	local _, _, raceID = ns.Try(UnitRace, "player")
	local faction = ns.Try(UnitFactionGroup, "player")
	local E = type(L.Enum) == "table" and L.Enum or {}
	local myClass = type(E.classKeys) == "table" and classFile and E.classKeys[classFile] or nil
	local myRace = type(E.raceMaskById) == "table" and raceID and E.raceMaskById[raceID] or nil
	local inLog = {}
	for _, d in ipairs(DG.FromLog()) do for _, q in ipairs(d.quests) do inLog[q.id] = true end end
	local QL = C_QuestLog
	local function Have(id) return inLog[id] or (QL and type(QL.IsOnQuest) == "function" and ns.Try(QL.IsOnQuest, id)) and true or false end
	local out = { area = area, done = {}, log = {}, pickup = {}, total = 0 }
	local starts = {} -- the first steps of chains that lead to this dungeon's quests, by id
	for _, id in ipairs(index[area] or {}) do
		local races = tonumber((ns.Try(L.Quest.requiredRaces, id))) or 0
		local classes = tonumber((ns.Try(L.Quest.requiredClasses, id))) or 0
		local maxLevel = tonumber((ns.Try(L.Quest.requiredMaxLevel, id))) or 0
		local skill = ns.Try(L.Quest.requiredSkill, id)
		local fits = (races == 0 or not myRace or Band(races, myRace) > 0)
			and (classes == 0 or not myClass or Band(classes, myClass) > 0)
			and (maxLevel == 0 or maxLevel >= level) and type(skill) ~= "table"
		if fits then
			for _, other in ipairs(ns.Try(L.Quest.exclusiveTo, id) or {}) do
				if Done(other) or Have(other) then fits = false end
			end
		end
		local qname = fits and Name(L, id)
		if qname then
			local from, friendly, spot = Giver(L, id)
			if friendly and faction and not tostring(friendly):find(faction == "Alliance" and "A" or "H", 1, true) then qname = nil end
			if qname then
				out.total = out.total + 1
				if Done(id) then
					out.done[#out.done + 1] = qname
				elseif Have(id) then
					out.log[#out.log + 1] = qname
				else
					-- A quest behind another: the chain walked back to the step that can be taken now (often
					-- outside the dungeon: The Defias Brotherhood starts in Westfall), or the one in the log.
					local after, afterLog, afterStep, afterTo
					local step = Chain(L, id, Have)
					if step then
						after = Name(L, step.id)
						afterLog = step.inLog
						-- Which step of a chain, when there's more than one; and for one in the log, who takes it.
						afterStep = StepOf(L, step.id)
						if afterStep < 2 and Name(L, id) ~= after then afterStep = nil end
						if step.inLog then afterTo = Finisher(L, step.id) end
						if not step.inLog and not starts[step.id] and after then
							local sfrom, _, sspot = Giver(L, step.id)
							local sreq = tonumber((ns.Try(L.Quest.requiredLevel, step.id)))
							starts[step.id] = { id = step.id, name = after, level = tonumber((ns.Try(L.Quest.questLevel, step.id))), from = sfrom,
								at = (sreq and sreq > level) and sreq or nil, opens = {}, first = true, spot = sspot }
						end
						if starts[step.id] then table.insert(starts[step.id].opens, qname) end
					end
					local req = tonumber((ns.Try(L.Quest.requiredLevel, id)))
					out.pickup[#out.pickup + 1] = { id = id, name = qname, level = tonumber((ns.Try(L.Quest.questLevel, id))), from = from,
						after = after, afterLog = afterLog, afterStep = afterStep, afterTo = afterTo, at = (req and req > level) and req or nil, spot = spot }
				end
			end
		end
	end
	-- The first steps of those chains are pickups too, unless one is already on the list.
	local listed = {}
	for _, q in ipairs(out.pickup) do listed[q.id] = q end
	for id, s in pairs(starts) do
		if listed[id] then listed[id].opens = s.opens else out.pickup[#out.pickup + 1] = s end
	end
	table.sort(out.pickup, function(a, b)
		local la, lb = (a.after or a.at) and 1 or 0, (b.after or b.at) and 1 or 0
		if la ~= lb then return la < lb end
		return (a.level or 0) < (b.level or 0)
	end)
	return out
end

-- The one-line summary: "All 4 quests done", "2 to pick up · 1 in your log · 1 done".
function DG.Summary(qs)
	if not qs then return nil end
	if qs.total == 0 then return "No quests for you here" end
	if #qs.done == qs.total then return "|cff19ff19All " .. qs.total .. " quest" .. (qs.total > 1 and "s" or "") .. " done|r" end
	local bits = {}
	local now, later = 0, 0
	for _, q in ipairs(qs.pickup) do if q.after or q.at then later = later + 1 else now = now + 1 end end
	if now > 0 then bits[#bits + 1] = "|cffffd100" .. now .. " to pick up|r" end
	if later > 0 then bits[#bits + 1] = later .. " later" end
	if #qs.log > 0 then bits[#bits + 1] = #qs.log .. " in your log" end
	if #qs.done > 0 then bits[#bits + 1] = #qs.done .. " done" end
	return table.concat(bits, " · ")
end

-- The briefing's question: what to know before going in, for this character.
function DG.Briefing(name)
	local class = ns.Try(UnitClass, "player")
	local role = Role()
	local who = ((role and (role .. " ") or "") .. (type(class) == "string" and class or "")):gsub("^%s+", ""):gsub("%s+$", "")
	local mine
	for _, d in ipairs(DG.FromLog()) do if DG.Norm(d.name) == DG.Norm(name) then mine = d end end
	local parts = { "Brief me for " .. name .. (who ~= "" and (" as a level " .. Level() .. " " .. who) or "") .. "." }
	if mine then
		local titles = {}
		for _, q in ipairs(mine.quests) do titles[#titles + 1] = q.title .. (q.complete and " (done)" or "") end
		parts[#parts + 1] = "My quests for it: " .. table.concat(titles, ", ") .. "."
	end
	-- What QuestieDB says is still to pick up, so the AI doesn't have to guess the list.
	local qs = DG.Quests(name)
	if qs then
		local pick = {}
		for i, q in ipairs(qs.pickup) do
			if i <= 6 then
				pick[#pick + 1] = q.name .. (q.first and " (the first step of a chain" .. ((q.opens and #q.opens > 0) and (" leading to " .. table.concat(q.opens, ", ")) or "") .. ")" or "") .. (q.from and (" (from " .. q.from .. ")") or "") .. (q.after and (" after " .. q.after .. (q.afterStep and (" (step " .. q.afterStep .. ")") or "") .. (q.afterLog and (", which is in my log" .. (q.afterTo and (", handed in to " .. q.afterTo) or "")) or "")) or "") .. (q.at and (" at level " .. q.at) or "")
			end
		end
		if #pick > 0 then parts[#parts + 1] = "Quests for it I haven't picked up: " .. table.concat(pick, "; ") .. "." end
		if #qs.done > 0 then parts[#parts + 1] = "Already done: " .. table.concat(qs.done, ", ") .. "." end
		if qs.total > 0 and #qs.pickup == 0 and #qs.log == 0 then parts[#parts + 1] = "I've done all its quests." end
		parts[#parts + 1] = "Tell me: the level range, the bosses in order with one tip each for my role, loot worth hoping for my class, and what to bring" .. (#pick > 0 and ", and the best order to pick up the missing quests." or ".")
	else
		parts[#parts + 1] = "Tell me: which other quests to pick up before going in (who gives them and where), the level range, the bosses in order with one tip each for my role, loot worth hoping for my class, and what to bring."
	end
	return table.concat(parts, " ")
end

-- The question behind "Which dungeon now?".
function DG.WhichQuestion()
	local names = {}
	for _, d in ipairs(DG.FromLog()) do names[#names + 1] = d.name end
	local q = "Which dungeons fit my level and class right now, and which is best to do next?"
	if #names > 0 then q = q .. " I have quests for " .. table.concat(names, ", ") .. "." end
	return q
end
