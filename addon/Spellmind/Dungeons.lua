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
function DG.FromLog()
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

-- The briefing's question: what to know before going in, for this character.
function DG.Briefing(name)
	local class = ns.Try(UnitClass, "player")
	local role = Role()
	local who = ((role and (role .. " ") or "") .. (type(class) == "string" and class or "")):gsub("^%s+", ""):gsub("%s+$", "")
	local mine
	for _, d in ipairs(DG.FromLog()) do if d.name == name then mine = d end end
	local parts = { "Brief me for " .. name .. (who ~= "" and (" as a level " .. Level() .. " " .. who) or "") .. "." }
	if mine then
		local titles = {}
		for _, q in ipairs(mine.quests) do titles[#titles + 1] = q.title .. (q.complete and " (done)" or "") end
		parts[#parts + 1] = "My quests for it: " .. table.concat(titles, ", ") .. "."
	end
	parts[#parts + 1] = "Tell me: which other quests to pick up before going in (who gives them and where), the level range, the bosses in order with one tip each for my role, loot worth hoping for my class, and what to bring."
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
