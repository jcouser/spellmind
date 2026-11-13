-- Advisor.lua: what Spellmind's tabs work out, for the AI too (docs/milestone-18.md). The AI had the
-- raw game data but not the tabs' conclusions (seen in game: the Dungeons tab listed "Testing the
-- Wells" and its giver, while the AI said it couldn't confirm the giver). So the advisor part carries
-- a compact copy:
--   dungeons     the quest log's dungeons and the one you're in: level range, done / in log / to
--                pick up, and the quests to pick up with their givers or what opens them (needs the
--                QuestieDB addon for the list; without it, just the log's)
--   upgrades     the gear upgrades within reach (bags, quest rewards), by slot
--   professions  each one's next rank (train now, or at what skill and level) and its best skill-ups
--   gold         this session's net and rate, and the known costs coming up
-- Everything here is computed from the game in Spellmind; nothing is new data.

local _, ns = ...
local AV = {}
ns.Advisor = AV

AV.DUNGEONS_MAX, AV.PICKUP_MAX, AV.UPGRADES_MAX, AV.SKILLUPS_MAX = 4, 5, 6, 3

local function O(...) return ns.State.JSON.O(...) end

local function Dungeons()
	local DG = ns.Dungeons
	if not DG then return nil end
	local list, seen = {}, {}
	local function Add(name, low, high, inLog)
		local key = DG.Norm(name)
		if seen[key] or #list >= AV.DUNGEONS_MAX then return end
		seen[key] = true
		local qs = DG.Quests(name)
		local pickup
		if qs and #qs.pickup > 0 then
			pickup = {}
			for i, q in ipairs(qs.pickup) do
				if i > AV.PICKUP_MAX then break end
				pickup[#pickup + 1] = O("name", q.name, "from", q.from, "after", q.after, "afterStep", q.afterStep, "afterInLog", q.afterLog and true or nil, "afterTo", q.afterTo,
					"at", q.at, "first", q.first and true or nil)
			end
		end
		-- The range is the dungeon's own (the game's group finder) when it lists it; the log's quest levels are
		-- their own field (seen in game: "18-20", the quests', was taken for the dungeon's 17-26).
		local range
		for _, l in ipairs(DG.Listed()) do if DG.Norm(l.name) == key then range = DG.Range(l.low, l.high) end end
		list[#list + 1] = O("name", name, "range", range, "questLevels", inLog and DG.Range(low, high) or nil, "inLog", inLog,
			"done", qs and #qs.done or nil, "toPickUp", qs and #qs.pickup or nil, "total", qs and qs.total or nil, "pickup", pickup)
	end
	local here = DG.Here()
	local log = DG.FromLog()
	if here then
		local n
		for _, d in ipairs(log) do if DG.Norm(d.name) == DG.Norm(here.name) then n = #d.quests end end
		Add(here.name, nil, nil, n)
	end
	for _, d in ipairs(log) do Add(d.name, d.low, d.high, #d.quests) end
	for _, d in ipairs(DG.AtLevel()) do Add(d.name, d.low, d.high, nil) end
	return #list > 0 and list or nil
end

local function Upgrades()
	local G = ns.Gear
	if not G or type(G.Candidates) ~= "function" then return nil end
	local ok, c = pcall(G.Candidates)
	if not ok or type(c) ~= "table" then return nil end
	local out = {}
	for i, u in ipairs(c) do
		if i > AV.UPGRADES_MAX then break end
		out[#out + 1] = O("slot", G.SLOT_NAMES[u.slot], "name", u.name, "from", u.from)
	end
	return #out > 0 and out or nil
end

local function Professions()
	local PR = ns.Professions
	local s = ns.State.Collect and select(2, pcall(ns.State.Collect.skills))
	local out = {}
	for _, kv in ipairs(type(s) == "table" and s._o or {}) do
		if kv[1] == "prof" then
			for _, p in ipairs(kv[2] or {}) do
				local t = {}
				for _, f in ipairs(p._o or {}) do t[f[1]] = f[2] end
				local nr = PR.NextRank(t.rank, t.max)
				local next
				if nr == "max" then next = "top rank"
				elseif type(nr) == "table" and nr.ready then next = "train " .. nr.name .. " now"
				elseif type(nr) == "table" then next = nr.name .. " at skill " .. nr.skill .. " and level " .. nr.level end
				local ups
				if not PR.GATHERING[t.name] then
					local su = PR.SkillUps(t.name)
					if su.list then
						ups = {}
						for i, r in ipairs(su.list) do
							if i > AV.SKILLUPS_MAX then break end
							ups[#ups + 1] = O("name", r.name, "color", r.diff == "optimal" and "orange" or "yellow", "makes", r.makes)
						end
						if #ups == 0 then ups = nil end
					end
				end
				out[#out + 1] = O("name", t.name, "next", next, "skillUps", ups)
			end
		end
	end
	return #out > 0 and out or nil
end

local function Gold()
	local GL = ns.Gold
	if not GL then return nil end
	local inc = GL.Income()
	local costs, total = GL.Costs()
	local list = {}
	for i, c in ipairs(costs) do if i <= 6 then list[#list + 1] = c.label .. (c.copper and (": " .. c.copper .. "c") or "") end end -- the app takes 6
	-- No per-hour rate: it changes every second, so the part would be built and sent again and again
	-- (seen in game: it came in after the turn had stopped waiting). The Gold tab shows it.
	return O("sessionNet", inc.session.net, "todayNet", inc.today.net,
		"costs", #list > 0 and list or nil, "costsTotal", total > 0 and total or nil)
end

function AV.Part()
	local function Safe(fn) local ok, v = pcall(fn); return ok and v or nil end
	return O("v", 1, "dungeons", Safe(Dungeons), "upgrades", Safe(Upgrades), "professions", Safe(Professions), "gold", Safe(Gold))
end
